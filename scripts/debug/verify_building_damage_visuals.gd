extends Node

## Headless verification for building damage smoke/fire visuals.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_building_damage_visuals.tscn

const REPORT_PATH := "user://building_damage_visuals_verify_result.txt"
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/buildings/shop.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const ACADEMY_SCENE: PackedScene = preload("res://scenes/buildings/academy.tscn")
const ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const WALL_SEGMENT_SCENE: PackedScene = preload("res://scenes/buildings/wall_segment.tscn")

const ALL_BUILDING_SCENES: Array[PackedScene] = [
	FARM_SCENE,
	BARRACKS_SCENE,
	BLACKSMITH_SCENE,
	STABLE_SCENE,
	SHOP_SCENE,
	TOWER_SCENE,
	HERO_ALTAR_SCENE,
	COMMAND_CENTER_SCENE,
	ACADEMY_SCENE,
	ARTILLERY_DEPOT_SCENE,
	WALL_SEGMENT_SCENE,
]


func _ready() -> void:
	var failures: PackedStringArray = []
	BuildingDamageFxPool.reset_match_state()

	print("verify_building_damage_visuals: start")
	_verify_threshold_mapping(failures)
	await _verify_all_buildings_damage_states(failures)
	await _verify_repair_clears_effects(failures)
	await _verify_no_duplicate_emitters(failures)
	await _verify_destruction_releases_fx(failures)
	await _verify_enemy_building_effects(failures)
	await _verify_pool_reuse(failures)

	var report: String
	if failures.is_empty():
		report = "PASS building_damage_visuals\n"
	else:
		report = "FAIL building_damage_visuals\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_threshold_mapping(failures: PackedStringArray) -> void:
	print("verify: threshold mapping")
	var profile := BuildingDamageVisualProfile.default_profile()
	_expect(
		failures,
		"ratio 1.0 => NONE",
		BuildingDamageVisuals.level_for_ratio(1.0, profile) == BuildingDamageVisuals.DamageLevel.NONE
	)
	_expect(
		failures,
		"ratio 0.76 => NONE",
		BuildingDamageVisuals.level_for_ratio(0.76, profile) == BuildingDamageVisuals.DamageLevel.NONE
	)
	_expect(
		failures,
		"ratio 0.75 => MINOR_SMOKE",
		(
			BuildingDamageVisuals.level_for_ratio(0.75, profile)
			== BuildingDamageVisuals.DamageLevel.MINOR_SMOKE
		)
	)
	_expect(
		failures,
		"ratio 0.50 => NOTICEABLE_SMOKE",
		(
			BuildingDamageVisuals.level_for_ratio(0.5, profile)
			== BuildingDamageVisuals.DamageLevel.NOTICEABLE_SMOKE
		)
	)
	_expect(
		failures,
		"ratio 0.25 => SMOKE_AND_FIRE",
		(
			BuildingDamageVisuals.level_for_ratio(0.25, profile)
			== BuildingDamageVisuals.DamageLevel.SMOKE_AND_FIRE
		)
	)
	_expect(
		failures,
		"ratio 0.10 => HEAVY_FIRE",
		(
			BuildingDamageVisuals.level_for_ratio(0.1, profile)
			== BuildingDamageVisuals.DamageLevel.HEAVY_FIRE
		)
	)
	_expect(
		failures,
		"ratio 0.0 => HEAVY_FIRE",
		BuildingDamageVisuals.level_for_ratio(0.0, profile) == BuildingDamageVisuals.DamageLevel.HEAVY_FIRE
	)


func _verify_all_buildings_damage_states(failures: PackedStringArray) -> void:
	print("verify: all buildings damage states")
	var root := Node3D.new()
	add_child(root)

	for scene: PackedScene in ALL_BUILDING_SCENES:
		var building: Building = scene.instantiate() as Building
		_expect(failures, "%s instantiates" % scene.resource_path, building != null)
		if building == null:
			continue

		root.add_child(building)
		building.global_position = Vector3(float(root.get_child_count()) * 4.0, 0.0, 0.0)
		if building.has_method(&"set_completed"):
			building.set_completed()
		await _wait_frames(2)

		var visuals: BuildingDamageVisuals = _get_damage_visuals(building)
		_expect(
			failures,
			"%s has damage visuals" % building.name,
			visuals != null
		)
		if visuals == null:
			building.queue_free()
			continue

		var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
		_expect(failures, "%s has HealthComponent" % building.name, health != null)
		if health == null:
			building.queue_free()
			continue

		_expect(
			failures,
			"%s starts at NONE" % building.name,
			visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.NONE
		)

		_set_health_ratio(health, 0.75)
		await _wait_frames(1)
		_expect(
			failures,
			"%s @75%% minor smoke" % building.name,
			visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.MINOR_SMOKE
		)
		_expect(failures, "%s @75%% has smoke" % building.name, visuals.has_smoke_emitter())
		_expect(failures, "%s @75%% no fire" % building.name, not visuals.has_fire_emitter())

		_set_health_ratio(health, 0.5)
		await _wait_frames(1)
		_expect(
			failures,
			"%s @50%% noticeable smoke" % building.name,
			visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.NOTICEABLE_SMOKE
		)
		_expect(failures, "%s @50%% has smoke" % building.name, visuals.has_smoke_emitter())
		_expect(failures, "%s @50%% no fire" % building.name, not visuals.has_fire_emitter())

		_set_health_ratio(health, 0.25)
		await _wait_frames(1)
		_expect(
			failures,
			"%s @25%% smoke+fire" % building.name,
			visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.SMOKE_AND_FIRE
		)
		_expect(failures, "%s @25%% has smoke" % building.name, visuals.has_smoke_emitter())
		_expect(failures, "%s @25%% has fire" % building.name, visuals.has_fire_emitter())

		_set_health_ratio(health, 0.1)
		await _wait_frames(1)
		_expect(
			failures,
			"%s @10%% heavy fire" % building.name,
			visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.HEAVY_FIRE
		)
		_expect(failures, "%s @10%% has smoke" % building.name, visuals.has_smoke_emitter())
		_expect(failures, "%s @10%% has fire" % building.name, visuals.has_fire_emitter())

		var host: Node = building.get_node_or_null(NodePath(String(BuildingDamageVisuals.HOST_NAME)))
		_expect(failures, "%s FX host is child of building" % building.name, host != null)
		if host is Node3D:
			_expect(
				failures,
				"%s FX host parent is building" % building.name,
				host.get_parent() == building
			)

		building.queue_free()
		await _wait_frames(1)

	root.queue_free()
	await _wait_frames(1)


func _verify_repair_clears_effects(failures: PackedStringArray) -> void:
	print("verify: repair clears effects")
	var root := Node3D.new()
	add_child(root)

	var building: Building = FARM_SCENE.instantiate() as Building
	root.add_child(building)
	building.set_completed()
	await _wait_frames(2)

	var visuals: BuildingDamageVisuals = _get_damage_visuals(building)
	var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
	_expect(failures, "repair: visuals ready", visuals != null and health != null)
	if visuals == null or health == null:
		root.queue_free()
		return

	_set_health_ratio(health, 0.1)
	await _wait_frames(1)
	_expect(failures, "repair: damaged to heavy fire", visuals.has_fire_emitter())

	# Gradual repair upward through states.
	_set_health_ratio(health, 0.25)
	await _wait_frames(1)
	_expect(
		failures,
		"repair: 25% still smoke+fire",
		visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.SMOKE_AND_FIRE
	)

	_set_health_ratio(health, 0.5)
	await _wait_frames(1)
	_expect(
		failures,
		"repair: 50% smoke only",
		visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.NOTICEABLE_SMOKE
	)

	health.heal(health.max_health)
	# Allow fade tweens to release emitters.
	await get_tree().create_timer(0.85).timeout
	await _wait_frames(2)
	_expect(
		failures,
		"repair: full heal => NONE",
		visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.NONE
	)
	_expect(failures, "repair: smoke gone", not visuals.has_smoke_emitter())
	_expect(failures, "repair: fire gone", not visuals.has_fire_emitter())

	root.queue_free()
	await _wait_frames(1)


func _verify_no_duplicate_emitters(failures: PackedStringArray) -> void:
	print("verify: no duplicate emitters")
	var root := Node3D.new()
	add_child(root)

	var building: Building = BARRACKS_SCENE.instantiate() as Building
	root.add_child(building)
	building.set_completed()
	await _wait_frames(2)

	var visuals: BuildingDamageVisuals = _get_damage_visuals(building)
	var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
	if visuals == null or health == null:
		failures.append("duplicate: missing visuals/health")
		root.queue_free()
		return

	_set_health_ratio(health, 0.1)
	visuals.force_refresh()
	visuals.force_refresh()
	await _wait_frames(1)

	var host: Node = building.get_node_or_null(NodePath(String(BuildingDamageVisuals.HOST_NAME)))
	_expect(failures, "duplicate: host exists", host != null)
	if host != null:
		var smoke_count := 0
		var fire_count := 0
		for child: Node in host.get_children():
			if child.name == &"PooledSmoke":
				smoke_count += 1
			elif child.name == &"PooledFire":
				fire_count += 1
		_expect(failures, "duplicate: single smoke", smoke_count == 1)
		_expect(failures, "duplicate: single fire", fire_count == 1)

	root.queue_free()
	await _wait_frames(1)


func _verify_destruction_releases_fx(failures: PackedStringArray) -> void:
	print("verify: destruction releases fx")
	var root := Node3D.new()
	add_child(root)

	var building: Building = TOWER_SCENE.instantiate() as Building
	root.add_child(building)
	building.set_completed()
	await _wait_frames(2)

	var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
	_expect(failures, "destroy: health present", health != null)
	if health == null:
		root.queue_free()
		return

	_set_health_ratio(health, 0.1)
	await _wait_frames(1)

	var host_before: Node = building.get_node_or_null(NodePath(String(BuildingDamageVisuals.HOST_NAME)))
	_expect(failures, "destroy: host before death", host_before != null)

	# Lethal damage path.
	health.take_damage(health.max_health)
	await _wait_frames(3)

	_expect(failures, "destroy: building freed", not is_instance_valid(building))
	root.queue_free()
	await _wait_frames(1)


func _verify_enemy_building_effects(failures: PackedStringArray) -> void:
	print("verify: enemy building effects")
	var root := Node3D.new()
	add_child(root)

	var building: Building = FARM_SCENE.instantiate() as Building
	root.add_child(building)
	building.team_id = 1
	building.add_to_group(&"enemy_command_center")
	building.set_completed()
	building.apply_team_visuals()
	await _wait_frames(2)

	var visuals: BuildingDamageVisuals = _get_damage_visuals(building)
	var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
	_expect(failures, "enemy: visuals ready", visuals != null and health != null)
	if visuals == null or health == null:
		root.queue_free()
		return

	_set_health_ratio(health, 0.2)
	await _wait_frames(1)
	_expect(
		failures,
		"enemy: smoke+fire at 20%",
		visuals.get_current_level() == BuildingDamageVisuals.DamageLevel.SMOKE_AND_FIRE
	)
	_expect(failures, "enemy: has smoke", visuals.has_smoke_emitter())
	_expect(failures, "enemy: has fire", visuals.has_fire_emitter())

	root.queue_free()
	await _wait_frames(1)


func _verify_pool_reuse(failures: PackedStringArray) -> void:
	print("verify: pool reuse")
	BuildingDamageFxPool.reset_match_state()
	var root := Node3D.new()
	add_child(root)

	var first: Building = FARM_SCENE.instantiate() as Building
	root.add_child(first)
	first.set_completed()
	await _wait_frames(2)

	var health_a: HealthComponent = first.get_node_or_null("HealthComponent") as HealthComponent
	var visuals_a: BuildingDamageVisuals = _get_damage_visuals(first)
	_set_health_ratio(health_a, 0.1)
	await _wait_frames(1)
	_expect(failures, "pool: first has emitters", visuals_a.has_smoke_emitter() and visuals_a.has_fire_emitter())

	# Full heal releases emitters back to pool.
	health_a.heal(health_a.max_health)
	await get_tree().create_timer(0.85).timeout
	await _wait_frames(2)
	_expect(failures, "pool: first cleared", not visuals_a.has_smoke_emitter())

	var second: Building = SHOP_SCENE.instantiate() as Building
	root.add_child(second)
	second.set_completed()
	await _wait_frames(2)
	var health_b: HealthComponent = second.get_node_or_null("HealthComponent") as HealthComponent
	var visuals_b: BuildingDamageVisuals = _get_damage_visuals(second)
	_set_health_ratio(health_b, 0.1)
	await _wait_frames(1)
	_expect(failures, "pool: second acquired emitters", visuals_b.has_smoke_emitter())
	_expect(failures, "pool: second has fire", visuals_b.has_fire_emitter())

	root.queue_free()
	BuildingDamageFxPool.reset_match_state()
	await _wait_frames(1)


func _get_damage_visuals(building: Building) -> BuildingDamageVisuals:
	if building == null:
		return null
	return building.get_node_or_null(
		NodePath(String(BuildingDamageVisuals.COMPONENT_NAME))
	) as BuildingDamageVisuals


func _set_health_ratio(health: HealthComponent, ratio: float) -> void:
	# Floor so ratio checks stay at-or-below the requested threshold (no round-up past it).
	var target: int = clampi(
		int(floor(float(health.max_health) * ratio + 0.000001)),
		0,
		health.max_health
	)
	if ratio > 0.0:
		target = maxi(target, 1)
	if target == health.current_health:
		health.health_changed.emit(health.current_health, health.max_health)
		return
	if target > health.current_health:
		health.heal(target - health.current_health)
	else:
		health.take_damage(health.current_health - target)


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
