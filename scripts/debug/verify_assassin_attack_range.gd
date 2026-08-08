extends Node

## Headless verification: Shadow Assassin direct attack range + chase completion.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_assassin_attack_range.tscn

const REPORT_PATH := "user://assassin_attack_range_verify_result.txt"
const ASSASSIN_SCENE: PackedScene = preload("res://scenes/units/shadow_assassin.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const NEUTRAL_CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const CHASE_TIMEOUT_MS := 9000
const ATTACK_TIMEOUT_MS := 6000


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	print("verify_assassin_attack_range: start")
	_verify_effective_range_and_standoff(failures)
	await _verify_stationary_enemy_chase(failures)
	await _verify_moving_enemy_chase(failures)
	await _verify_enemy_hero_and_creep(failures)
	await _verify_building_edge_attack(failures)
	await _verify_move_cancels_chase(failures)
	await _verify_target_death_cleanup(failures)
	await _verify_no_idle_auto_acquire(failures)
	_verify_qr_targeting_intact(failures)

	var report: String
	if failures.is_empty():
		report = "PASS assassin_attack_range\n"
	else:
		report = "FAIL assassin_attack_range\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_effective_range_and_standoff(failures: PackedStringArray) -> void:
	print("verify: effective range + standoff formula")
	var assassin: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	var dummy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	add_child(assassin)
	add_child(dummy)
	assassin.global_position = Vector3.ZERO
	dummy.global_position = Vector3(8.0, 0.0, 0.0)

	var attack_range: float = assassin.attack_range
	var effective: float = CombatTargetValidation.get_effective_attack_range(attack_range)
	_expect(failures, "assassin configured attack range is 2.0", is_equal_approx(attack_range, 2.0))
	_expect(
		failures,
		"effective melee range = attack_range + tolerance",
		is_equal_approx(effective, attack_range + CombatTargetValidation.MELEE_ATTACK_RANGE_TOLERANCE)
	)

	var standoff: float = CombatTargetValidation.get_preferred_attack_standoff(
		assassin, dummy, attack_range, assassin.stopping_distance, 0
	)
	_expect(
		failures,
		"melee standoff + soft arrival stays inside effective range",
		standoff + Unit.SOFT_ARRIVAL_DISTANCE <= effective + 0.05
	)
	_expect(
		failures,
		"close-in destination survives soft arrival inside effective range",
		(effective - CombatTargetValidation.MELEE_CLOSE_IN_ARRIVAL_MARGIN)
		+ Unit.SOFT_ARRIVAL_DISTANCE
		<= effective + 0.05
	)
	_expect(failures, "melee standoff does not require overlap", standoff >= 1.0)

	# Just outside raw range but inside effective tolerance must still count as in-range.
	assassin.global_position = Vector3(effective - 0.05, 0.0, 0.0)
	dummy.global_position = Vector3.ZERO
	_expect(
		failures,
		"tolerance allows strike slightly past raw attack_range",
		CombatTargetValidation.is_within_attack_range(assassin, dummy, attack_range)
	)

	assassin.global_position = Vector3(effective + 0.2, 0.0, 0.0)
	_expect(
		failures,
		"beyond effective range is out of range",
		not CombatTargetValidation.is_within_attack_range(assassin, dummy, attack_range)
	)

	assassin.queue_free()
	dummy.queue_free()


func _verify_stationary_enemy_chase(failures: PackedStringArray) -> void:
	print("verify: stationary enemy from far away")
	var harness: Dictionary = await _spawn_harness()
	var assassin: MeleeHero = harness["assassin"]
	var dummy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	harness["root"].add_child(dummy)
	dummy.add_to_group(&"enemies")
	dummy.team_id = 1
	assassin.global_position = Vector3(-8.0, 0.0, 0.0)
	dummy.global_position = Vector3(4.0, 0.0, 0.0)
	await _wait_nav_ready(assassin)

	assassin.command_attack(dummy)
	_expect(failures, "stationary: attack target stored", assassin.get_attack_target() == dummy)
	_expect(
		failures,
		"stationary: chase started while out of range",
		assassin.has_move_target or assassin._has_chase_target
	)

	var reached: bool = await _wait_until_in_attack_range(assassin, dummy, CHASE_TIMEOUT_MS)
	_expect(failures, "stationary: reaches effective attack range", reached)

	if reached:
		var struck: bool = await _wait_until_attack_started(assassin, ATTACK_TIMEOUT_MS)
		_expect(failures, "stationary: begins basic attacks", struck)
		_expect(
			failures,
			"stationary: remains committed to direct attack",
			assassin._has_active_attack_order and assassin._committed_attack_order
		)

	await _free_harness(harness)


func _verify_moving_enemy_chase(failures: PackedStringArray) -> void:
	print("verify: moving enemy chase")
	var harness: Dictionary = await _spawn_harness()
	var assassin: MeleeHero = harness["assassin"]
	var dummy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	harness["root"].add_child(dummy)
	dummy.add_to_group(&"enemies")
	dummy.team_id = 1
	assassin.global_position = Vector3(-7.0, 0.0, 2.0)
	dummy.global_position = Vector3(0.0, 0.0, 2.0)
	await _wait_nav_ready(assassin)

	assassin.command_attack(dummy)
	await _wait_msec(200)
	dummy.global_position = Vector3(6.0, 0.0, 2.0)
	assassin._update_chase_movement(0.0, true)

	var reached: bool = await _wait_until_in_attack_range(assassin, dummy, CHASE_TIMEOUT_MS)
	_expect(failures, "moving: reaches relocated target", reached)

	await _free_harness(harness)


func _verify_enemy_hero_and_creep(failures: PackedStringArray) -> void:
	print("verify: enemy hero + creep")
	var harness: Dictionary = await _spawn_harness()
	var assassin: MeleeHero = harness["assassin"]
	await _wait_nav_ready(assassin)

	var enemy_hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	harness["root"].add_child(enemy_hero)
	enemy_hero.add_to_group(&"enemies")
	enemy_hero.team_id = 1
	assassin.global_position = Vector3(-6.0, 0.0, -4.0)
	enemy_hero.global_position = Vector3(2.0, 0.0, -4.0)
	await get_tree().process_frame

	assassin.command_attack(enemy_hero)
	var hero_reached: bool = await _wait_until_in_attack_range(assassin, enemy_hero, CHASE_TIMEOUT_MS)
	_expect(failures, "enemy hero: reaches attack range", hero_reached)
	assassin.cancel_attack()
	assassin.clear_move_target()
	if NodeSafety.is_alive_node(enemy_hero):
		enemy_hero.queue_free()

	var creep: Node3D = NEUTRAL_CREEP_SCENE.instantiate() as Node3D
	harness["root"].add_child(creep)
	creep.add_to_group(&"neutral_creeps")
	assassin.global_position = Vector3(-6.0, 0.0, 4.0)
	creep.global_position = Vector3(2.0, 0.0, 4.0)
	await get_tree().process_frame

	assassin.command_attack(creep)
	_expect(failures, "creep: accepts attack order", assassin.get_attack_target() == creep)
	var creep_reached: bool = await _wait_until_in_attack_range(assassin, creep, CHASE_TIMEOUT_MS)
	_expect(failures, "creep: reaches attack range", creep_reached)

	await _free_harness(harness)


func _verify_building_edge_attack(failures: PackedStringArray) -> void:
	print("verify: building edge attack")
	var harness: Dictionary = await _spawn_harness()
	var assassin: MeleeHero = harness["assassin"]
	var town_hall: CommandCenter = COMMAND_CENTER_SCENE.instantiate() as CommandCenter
	harness["root"].add_child(town_hall)
	town_hall.add_to_group(&"enemy_command_center")
	town_hall.add_to_group(&"buildings")
	town_hall.team_id = 1
	town_hall.global_position = Vector3(5.0, 0.0, 0.0)
	assassin.global_position = Vector3(-8.0, 0.0, 0.0)
	await get_tree().process_frame
	await _wait_nav_ready(assassin)

	var approach: Vector3 = CombatTargetValidation.compute_attack_approach_position(
		assassin, town_hall, assassin.attack_range, assassin.stopping_distance, 0
	)
	var center_dist: float = _horizontal_distance(approach, town_hall.global_position)
	_expect(failures, "building: approach is outside center", center_dist >= 1.0)
	var building_radius: float = _estimate_building_radius(town_hall)
	var effective: float = CombatTargetValidation.get_effective_attack_range(assassin.attack_range)
	_expect(
		failures,
		"building: approach + soft arrival within effective surface range",
		center_dist - building_radius + Unit.SOFT_ARRIVAL_DISTANCE <= effective + 0.15
	)

	assassin.command_attack(town_hall)
	_expect(failures, "building: attack target stored", assassin.get_attack_target() == town_hall)

	var reached: bool = await _wait_until_in_attack_range(assassin, town_hall, CHASE_TIMEOUT_MS)
	_expect(failures, "building: reaches visible edge attack range", reached)
	if reached:
		var surface: float = CombatTargetValidation.get_horizontal_attack_distance_to_surface(
			assassin, town_hall
		)
		_expect(
			failures,
			"building: not forced to stand far past edge",
			surface <= effective + 0.05
		)

	await _free_harness(harness)


func _verify_move_cancels_chase(failures: PackedStringArray) -> void:
	print("verify: move cancels direct attack")
	var harness: Dictionary = await _spawn_harness()
	var assassin: MeleeHero = harness["assassin"]
	var dummy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	harness["root"].add_child(dummy)
	dummy.add_to_group(&"enemies")
	dummy.team_id = 1
	assassin.global_position = Vector3(-6.0, 0.0, -6.0)
	dummy.global_position = Vector3(4.0, 0.0, -6.0)
	await _wait_nav_ready(assassin)

	assassin.command_attack(dummy)
	await _wait_msec(150)
	_expect(failures, "cancel: chasing before move", assassin.get_attack_target() == dummy)

	assassin.set_movement_target(Vector3(-6.0, 0.0, -2.0))
	_expect(failures, "cancel: move clears attack target", assassin.get_attack_target() == null)
	_expect(failures, "cancel: move clears active attack order", not assassin._has_active_attack_order)
	_expect(failures, "cancel: move clears chase flag", not assassin._has_chase_target)

	await _free_harness(harness)


func _verify_target_death_cleanup(failures: PackedStringArray) -> void:
	print("verify: target death cleanup")
	var harness: Dictionary = await _spawn_harness()
	var assassin: MeleeHero = harness["assassin"]
	var dummy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	harness["root"].add_child(dummy)
	dummy.add_to_group(&"enemies")
	dummy.team_id = 1
	assassin.global_position = Vector3(0.0, 0.0, 6.0)
	dummy.global_position = Vector3(1.5, 0.0, 6.0)
	await get_tree().process_frame

	assassin.command_attack(dummy)
	await _wait_msec(50)
	dummy.queue_free()
	await get_tree().process_frame
	assassin._sanitize_attack_target()

	_expect(failures, "death: attack target cleared", assassin.get_attack_target() == null)
	_expect(failures, "death: chase cleared", not assassin._has_chase_target)
	_expect(failures, "death: no active attack order", not assassin._has_active_attack_order)

	await _free_harness(harness)


func _verify_no_idle_auto_acquire(failures: PackedStringArray) -> void:
	print("verify: no idle auto-acquire")
	var assassin: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	var dummy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	add_child(assassin)
	add_child(dummy)
	assassin.global_position = Vector3.ZERO
	dummy.global_position = Vector3(1.2, 0.0, 0.0)
	await get_tree().process_frame

	for _i in range(12):
		await get_tree().physics_frame

	_expect(failures, "idle: no auto attack target", assassin.get_attack_target() == null)
	_expect(failures, "idle: player controlled", assassin.is_player_controlled_hero())

	assassin.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _verify_qr_targeting_intact(failures: PackedStringArray) -> void:
	print("verify: Q/R targeting definitions intact")
	var assassin: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	add_child(assassin)
	assassin.level = 16
	assassin.ability_points = 20
	for ability_id: StringName in [
		HeroAbilityProgression.ABILITY_Q,
		HeroAbilityProgression.ABILITY_W,
		HeroAbilityProgression.ABILITY_E,
		HeroAbilityProgression.ABILITY_R,
	]:
		while assassin.can_learn_ability(ability_id):
			assassin.try_learn_ability(ability_id, false)

	var q_def: HeroAbilityDefinition = assassin.get_ability_definition(HeroAbilityProgression.ABILITY_Q)
	var r_def: HeroAbilityDefinition = assassin.get_ability_definition(HeroAbilityProgression.ABILITY_R)
	_expect(
		failures,
		"Q still target-enemy",
		q_def != null and q_def.targeting_type == HeroAbilityDefinition.TargetingType.TARGET_ENEMY
	)
	_expect(
		failures,
		"R still dash-target",
		r_def != null and r_def.targeting_type == HeroAbilityDefinition.TargetingType.DASH_TARGET
	)
	assassin.queue_free()


func _spawn_harness() -> Dictionary:
	var root := Node3D.new()
	root.name = "AssassinAttackHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)

	await get_tree().process_frame
	await _bake_nav_mesh(region, root)

	var assassin: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	root.add_child(assassin)
	assassin.team_id = 0
	await get_tree().process_frame
	await get_tree().physics_frame

	return {"root": root, "region": region, "assassin": assassin}


func _bake_nav_mesh(region: NavigationRegion3D, parent: Node) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25

	var source_data := NavigationMeshSourceGeometryData3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(48.0, 48.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, parent)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	region.navigation_mesh = nav_mesh
	await get_tree().process_frame
	await get_tree().physics_frame


func _wait_nav_ready(unit: Unit) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline_msec:
		if false:
			return
		await get_tree().physics_frame


func _wait_until_in_attack_range(attacker: MeleeHero, target: Node3D, timeout_ms: int) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline_msec:
		if not NodeSafety.is_alive_node(attacker) or not NodeSafety.is_alive_node(target):
			return false
		if attacker._is_in_attack_range(target):
			return true
		# Keep chase alive if soft-arrival cleared the move target early.
		if attacker._has_active_attack_order and not attacker.has_move_target:
			attacker._update_chase_movement(0.0, true)
		await get_tree().physics_frame
	return false


func _wait_until_attack_started(attacker: MeleeHero, timeout_ms: int) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline_msec:
		if not NodeSafety.is_alive_node(attacker):
			return false
		if attacker._attack_windup_active or attacker._attack_cooldown_timer > 0.0:
			return true
		await get_tree().physics_frame
	return false


func _wait_msec(duration_ms: int) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + duration_ms
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().physics_frame


func _free_harness(harness: Dictionary) -> void:
	var root: Node = harness.get("root")
	if root != null and is_instance_valid(root):
		root.queue_free()
	await get_tree().process_frame
	CombatTargetValidation.reset_match_state()


func _estimate_building_radius(building: CollisionObject3D) -> float:
	var shape_node: CollisionShape3D = building.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return 0.5
	if shape_node.shape is BoxShape3D:
		var box := shape_node.shape as BoxShape3D
		return maxf(box.size.x, box.size.z) * 0.5
	if shape_node.shape is CylinderShape3D:
		return (shape_node.shape as CylinderShape3D).radius
	return 0.5


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset: Vector3 = a - b
	offset.y = 0.0
	return offset.length()


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if condition:
		return
	failures.append(label)
	print("FAIL: ", label)
