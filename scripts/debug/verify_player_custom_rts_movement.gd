extends Node

## Headless checks for player-only custom RTS movement integration.
## Godot --headless --path <project> --scene res://scenes/debug/verify_player_custom_rts_movement.tscn

const REPORT_PATH := "user://player_custom_rts_movement_verify_result.txt"
const UNIT_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_player_custom_rts_movement: start")

	_expect(failures, "CUSTOM_RTS_MOVEMENT default on", MilitaryAIConfig.CUSTOM_RTS_MOVEMENT)
	_expect(
		failures,
		"PlayerRouteNavigation.enabled mirrors config",
		PlayerRouteNavigation.is_custom_rts_movement_enabled()
	)
	_expect(
		failures,
		"autoload PlayerRouteNavigation present",
		PlayerRouteNavigation != null
	)

	await _test_grid_building_footprint(failures)
	await _test_group_one_path_calc(failures)
	await _test_single_unit_route(failures)
	await _test_building_unregister(failures)

	var report: String
	if failures.is_empty():
		report = "PASS player_custom_rts_movement\n"
	else:
		report = "FAIL player_custom_rts_movement\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_grid_building_footprint(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: Building = CC_SCENE.instantiate() as Building
	add_child(cc)
	cc.global_position = Vector3(0.0, 0.0, 0.0)
	cc.set_completed()
	await get_tree().process_frame
	await get_tree().process_frame

	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(cc)

	_expect(
		failures,
		"building marks occupancy",
		PlayerRouteNavigation.grid.has_obstacle(cc.get_instance_id())
	)
	_expect(
		failures,
		"building center blocked",
		not PlayerRouteNavigation.is_world_walkable(Vector3(0.0, 0.0, 0.0))
	)
	_expect(
		failures,
		"far cell walkable",
		PlayerRouteNavigation.is_world_walkable(Vector3(20.0, 0.0, 20.0))
	)

	cc.queue_free()
	await get_tree().process_frame


func _test_group_one_path_calc(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: Building = CC_SCENE.instantiate() as Building
	add_child(cc)
	cc.global_position = Vector3(0.0, 0.0, 0.0)
	cc.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(cc)

	var units: Array = []
	for i: int in 5:
		var unit: Unit = UNIT_SCENE.instantiate() as Unit
		add_child(unit)
		unit.global_position = Vector3(-18.0 + float(i) * 1.2, 0.0, -10.0)
		unit.team_id = TeamVisuals.PLAYER_TEAM_ID
		units.append(unit)

	await get_tree().process_frame

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units,
		Vector3(18.0, 0.0, 10.0),
		&"move",
		false
	)
	_expect(failures, "group command handled", result.get("handled", false))
	_expect(failures, "group route valid", result.get("route_valid", false))
	_expect(
		failures,
		"exactly one path calc",
		int(result.get("path_calculations", -1)) == 1
	)
	_expect(
		failures,
		"telemetry path calc == 1",
		PlayerRouteNavigation.get_path_calculations_this_command() == 1
	)

	var custom_active_count: int = 0
	for unit_ref: Variant in units:
		var unit: Unit = unit_ref as Unit
		if unit.is_custom_rts_movement_active():
			custom_active_count += 1
		_expect(failures, "unit has move target", unit.has_move_target)
	_expect(failures, "all units on custom RTS", custom_active_count == units.size())

	for unit_ref: Variant in units:
		(unit_ref as Node).queue_free()
	cc.queue_free()
	await get_tree().process_frame


func _test_single_unit_route(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	add_child(unit)
	unit.global_position = Vector3(-12.0, 0.0, 0.0)
	unit.team_id = TeamVisuals.PLAYER_TEAM_ID
	await get_tree().process_frame

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		[unit],
		Vector3(12.0, 0.0, 0.0),
		&"move",
		false
	)
	_expect(failures, "single unit handled", result.get("handled", false))
	_expect(failures, "single unit path calc 1", int(result.get("path_calculations", -1)) == 1)
	_expect(failures, "single unit custom active", unit.is_custom_rts_movement_active())

	unit.queue_free()
	await get_tree().process_frame


func _test_building_unregister(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: Building = CC_SCENE.instantiate() as Building
	add_child(cc)
	cc.global_position = Vector3(5.0, 0.0, 5.0)
	cc.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(cc)
	_expect(
		failures,
		"registered before destroy",
		not PlayerRouteNavigation.is_world_walkable(Vector3(5.0, 0.0, 5.0))
	)

	var obstacle_id: int = cc.get_instance_id()
	cc.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(
		failures,
		"obstacle cleared after destroy",
		not PlayerRouteNavigation.grid.has_obstacle(obstacle_id)
	)
	_expect(
		failures,
		"cell walkable after destroy",
		PlayerRouteNavigation.is_world_walkable(Vector3(5.0, 0.0, 5.0))
	)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
