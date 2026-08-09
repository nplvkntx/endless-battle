extends Node

## Hero Altar spawn must land on a walkable custom-grid cell outside the altar
## footprint/clearance, then accept normal custom RTS movement.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_hero_altar_spawn.tscn

const REPORT_PATH := "user://hero_altar_spawn_verify_result.txt"
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const SPAWN_LOOPS := 6
const MOVE_TIMEOUT_SEC := 12.0
const MOVE_ARRIVE_RADIUS := 1.6
const DEST_OFFSET := Vector3(0.0, 0.0, -10.0)


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_hero_altar_spawn: start")

	_expect(failures, "autoload PlayerRouteNavigation present", PlayerRouteNavigation != null)

	await _test_raw_offset_blocked_near_neighbor(failures)
	await _test_repeated_enemy_hero_spawn_walkable_and_movable(failures)
	await _test_player_hero_spawn_walkable_and_movable(failures)
	await _test_barracks_pikeman_still_spawns(failures)

	var report: String
	if failures.is_empty():
		report = "PASS hero_altar_spawn\n"
	else:
		report = "FAIL hero_altar_spawn\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_raw_offset_blocked_near_neighbor(failures: PackedStringArray) -> void:
	print("verify: raw HERO_SPAWN_OFFSET blocked beside neighbor")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var altar: HeroAltar = ALTAR_SCENE.instantiate() as HeroAltar
	add_child(altar)
	altar.global_position = Vector3(0.0, 1.0, 0.0)
	altar.set_completed()

	var neighbor: Building = BARRACKS_SCENE.instantiate() as Building
	add_child(neighbor)
	neighbor.global_position = Vector3(6.0, 0.0, 0.0)
	neighbor.set_completed()
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(altar)
	PlayerRouteNavigation.register_static_obstacle(neighbor)

	var preferred: Vector3 = altar.global_position + Vector3(3.0, -0.5, 0.0)
	_expect(
		failures,
		"preferred altar spawn offset is blocked by clearance/neighbors",
		not PlayerRouteNavigation.is_world_walkable(preferred)
	)
	_expect(
		failures,
		"preferred altar spawn offset is outside raw altar footprint",
		not altar.is_position_inside_footprint(preferred)
	)

	altar.queue_free()
	neighbor.queue_free()
	await get_tree().process_frame


func _test_repeated_enemy_hero_spawn_walkable_and_movable(failures: PackedStringArray) -> void:
	print("verify: repeated enemy Hero Altar spawns are walkable and movable")
	for loop_index: int in SPAWN_LOOPS:
		PlayerRouteNavigation.clear_all()
		_clear_hero_store()
		await get_tree().process_frame

		var altar: HeroAltar = ALTAR_SCENE.instantiate() as HeroAltar
		add_child(altar)
		altar.global_position = Vector3(float(loop_index) * 0.1, 1.0, float(loop_index) * 0.05)
		altar.set_completed()

		var neighbor: Building = BARRACKS_SCENE.instantiate() as Building
		add_child(neighbor)
		neighbor.global_position = altar.global_position + Vector3(6.0, -1.0, 0.0)
		neighbor.set_completed()
		await get_tree().process_frame
		await get_tree().process_frame
		PlayerRouteNavigation.ensure_grid_ready()
		PlayerRouteNavigation.register_static_obstacle(altar)
		PlayerRouteNavigation.register_static_obstacle(neighbor)

		var before: int = get_child_count()
		altar._training_kit_id = HeroCatalog.KIT_PALADIN
		altar._spawn_enemy_hero()
		await get_tree().process_frame

		var hero: Hero = _find_newest_hero(before)
		_expect(failures, "enemy hero loop %d spawned" % loop_index, hero != null)
		if hero == null:
			altar.queue_free()
			neighbor.queue_free()
			await get_tree().process_frame
			continue

		_expect(
			failures,
			"enemy hero loop %d spawn walkable" % loop_index,
			PlayerRouteNavigation.is_world_walkable(hero.global_position)
		)
		_expect(
			failures,
			"enemy hero loop %d outside altar footprint" % loop_index,
			not altar.is_position_inside_footprint(hero.global_position)
		)
		_expect(
			failures,
			"enemy hero loop %d not on raw blocked offset" % loop_index,
			_horizontal_distance(
				hero.global_position,
				altar.global_position + Vector3(3.0, -0.5, 0.0)
			) > 0.05
			or PlayerRouteNavigation.is_world_walkable(
				altar.global_position + Vector3(3.0, -0.5, 0.0)
			)
		)

		var destination: Vector3 = PlayerRouteNavigation.nearest_walkable_world(
			altar.global_position + DEST_OFFSET
		)
		var start: Vector3 = hero.global_position
		var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			[hero],
			destination,
			&"move",
			false,
			&"player"
		)
		_expect(failures, "enemy hero loop %d move handled" % loop_index, result.get("handled", false))
		_expect(
			failures,
			"enemy hero loop %d CUSTOM backend" % loop_index,
			hero.get_movement_backend_label() == "CUSTOM"
		)

		var moved := false
		var elapsed := 0.0
		while elapsed < MOVE_TIMEOUT_SEC:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			if not NodeSafety.is_alive_node(hero):
				break
			if (
				_horizontal_distance(hero.global_position, start) >= 2.0
				or _horizontal_distance(hero.global_position, destination) <= MOVE_ARRIVE_RADIUS + 2.0
			):
				moved = true
				break
		_expect(failures, "enemy hero loop %d left spawn" % loop_index, moved)

		if NodeSafety.is_alive_node(hero):
			hero.queue_free()
		altar.queue_free()
		neighbor.queue_free()
		await get_tree().process_frame


func _test_player_hero_spawn_walkable_and_movable(failures: PackedStringArray) -> void:
	print("verify: player Hero Altar spawn is walkable and movable")
	PlayerRouteNavigation.clear_all()
	_clear_hero_store()
	await get_tree().process_frame

	var altar: HeroAltar = ALTAR_SCENE.instantiate() as HeroAltar
	add_child(altar)
	altar.global_position = Vector3(2.0, 1.0, 2.0)
	altar.set_completed()

	var neighbor: Building = BARRACKS_SCENE.instantiate() as Building
	add_child(neighbor)
	neighbor.global_position = altar.global_position + Vector3(6.0, -1.0, 0.0)
	neighbor.set_completed()
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(altar)
	PlayerRouteNavigation.register_static_obstacle(neighbor)

	var before: int = get_child_count()
	altar._training_kit_id = HeroCatalog.KIT_PALADIN
	altar._spawn_hero()
	await get_tree().process_frame

	var hero: Hero = _find_newest_hero(before)
	_expect(failures, "player hero spawned", hero != null)
	if hero != null:
		_expect(
			failures,
			"player hero spawn walkable",
			PlayerRouteNavigation.is_world_walkable(hero.global_position)
		)
		_expect(
			failures,
			"player hero outside altar footprint",
			not altar.is_position_inside_footprint(hero.global_position)
		)
		var destination: Vector3 = PlayerRouteNavigation.nearest_walkable_world(
			altar.global_position + DEST_OFFSET
		)
		var start: Vector3 = hero.global_position
		var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			[hero],
			destination,
			&"move",
			false,
			&"player"
		)
		_expect(failures, "player hero move handled", result.get("handled", false))
		_expect(
			failures,
			"player hero CUSTOM backend",
			hero.get_movement_backend_label() == "CUSTOM"
		)
		var moved := false
		var elapsed := 0.0
		while elapsed < MOVE_TIMEOUT_SEC:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			if not NodeSafety.is_alive_node(hero):
				break
			if _horizontal_distance(hero.global_position, start) >= 2.0:
				moved = true
				break
		_expect(failures, "player hero left spawn", moved)
		if NodeSafety.is_alive_node(hero):
			hero.queue_free()

	altar.queue_free()
	neighbor.queue_free()
	await get_tree().process_frame


func _test_barracks_pikeman_still_spawns(failures: PackedStringArray) -> void:
	print("verify: Barracks pikeman spawn path still works")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var barracks: Barracks = BARRACKS_SCENE.instantiate() as Barracks
	add_child(barracks)
	barracks.global_position = Vector3(-12.0, 0.0, 0.0)
	barracks.set_completed()
	barracks.set_rally_point(barracks.global_position + Vector3(0.0, 0.0, -8.0))
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(barracks)

	var before: int = get_child_count()
	barracks._spawn_trained_unit(SPEARMAN_SCENE, barracks.spearman_spawn_offset)
	await get_tree().process_frame
	var unit: Unit = _find_newest_non_hero_unit(before)
	_expect(failures, "pikeman spawned", unit != null)
	if unit != null:
		_expect(
			failures,
			"pikeman spawn/rally walkable",
			PlayerRouteNavigation.is_world_walkable(unit.global_position)
		)
		_expect(
			failures,
			"pikeman CUSTOM or moving after rally",
			unit.get_movement_backend_label() == "CUSTOM" or unit.has_custom_rts_route()
		)
		unit.queue_free()

	barracks.queue_free()
	await get_tree().process_frame


func _clear_hero_store() -> void:
	var living_player: Hero = HeroProgressionStore.get_living_hero(false)
	if living_player != null:
		living_player.queue_free()
	var living_enemy: Hero = HeroProgressionStore.get_living_hero(true)
	if living_enemy != null:
		living_enemy.queue_free()
	HeroProgressionStore.clear()


func _find_newest_hero(before_count: int) -> Hero:
	for index: int in range(get_child_count() - 1, before_count - 1, -1):
		var node: Node = get_child(index)
		if node is Hero:
			return node as Hero
	return null


func _find_newest_non_hero_unit(before_count: int) -> Unit:
	for index: int in range(get_child_count() - 1, before_count - 1, -1):
		var node: Node = get_child(index)
		if node is Unit and not (node is Hero):
			return node as Unit
	return null


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if condition:
		return
	failures.append(label)
	print("FAIL: ", label)
