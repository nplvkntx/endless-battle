extends Node

## Headless integration: AI military strategic travel uses custom RTS movement.
## Godot --headless --path <project> --scene res://scenes/debug/verify_ai_custom_rts_movement.tscn

const REPORT_PATH := "user://ai_custom_rts_movement_verify_result.txt"
const UNIT_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_ai_custom_rts_movement: start")

	MilitaryAIConfig.clear_custom_rts_movement_override()
	_expect(failures, "CUSTOM_RTS_MOVEMENT default on", MilitaryAIConfig.CUSTOM_RTS_MOVEMENT)

	await _test_ai_group_uses_custom_shared_route(failures)
	await _test_obstacle_progress_and_arrival(failures)
	await _test_reinforcement_joins_custom_mission(failures)
	await _test_mission_preserved(failures)
	await _test_flag_off_restores_old_path(failures)

	MilitaryAIConfig.clear_custom_rts_movement_override()
	PlayerRouteNavigation.clear_all()

	var report: String
	if failures.is_empty():
		report = "PASS ai_custom_rts_movement\n"
	else:
		report = "FAIL ai_custom_rts_movement\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _spawn_ai_unit(pos: Vector3) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	add_child(unit)
	unit.global_position = pos
	unit.team_id = 1
	unit.add_to_group(EnemyArmyForceMath.ENEMY_COMBAT_GROUP)
	unit.add_to_group(&"enemies")
	unit.add_to_group(&"units")
	return unit


func _issue_ai_attack_move(units: Array, destination: Vector3, mission: EnemyUnitMission.Mission) -> bool:
	var issued: Array = [false]
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		issued[0] = EnemyArmyCommand.command_attack_move(units, destination, mission)
	)
	return VariantUtils.to_bool(issued[0])


func _nav_agent_strategically_active(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit.is_custom_rts_movement_active():
		# Dual authority: NavAgent must not also be steering strategic travel.
		return bool(unit.get("_navigation_active"))
	return false


func _test_ai_group_uses_custom_shared_route(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var units: Array = []
	for i: int in 4:
		units.append(_spawn_ai_unit(Vector3(-16.0 + float(i) * 1.2, 0.0, -8.0)))
	await get_tree().process_frame

	var ok: bool = _issue_ai_attack_move(
		units,
		Vector3(16.0, 0.0, 8.0),
		EnemyUnitMission.Mission.ATTACK
	)
	_expect(failures, "AI group order issued", ok)
	_expect(
		failures,
		"custom backend selected",
		PlayerRouteNavigation.was_last_ai_custom_move()
	)
	_expect(
		failures,
		"one shared path calc",
		PlayerRouteNavigation.get_path_calculations_this_command() == 1
	)
	_expect(
		failures,
		"route has waypoints",
		PlayerRouteNavigation.get_last_route_waypoints() > 0
	)
	_expect(failures, "squad size recorded", PlayerRouteNavigation.get_last_squad_size() == 4)

	var custom_count: int = 0
	var dual_authority: bool = false
	for entry: Variant in units:
		var unit: Unit = entry as Unit
		if unit.is_custom_rts_movement_active():
			custom_count += 1
		if _nav_agent_strategically_active(unit):
			dual_authority = true
		_expect(
			failures,
			"unit mission ATTACK",
			EnemyUnitMission.get_unit_mission(unit) == EnemyUnitMission.Mission.ATTACK
		)
		_expect(failures, "unit has custom route", unit.has_custom_rts_route())
		_expect(
			failures,
			"movement backend CUSTOM",
			unit.get_movement_backend_label() == "CUSTOM"
		)
		_expect(
			failures,
			"not in SharedSquadNavigation",
			SharedSquadNavigation.get_squad_for_unit(unit) == null
		)
	_expect(failures, "all units on custom RTS", custom_count == units.size())
	_expect(failures, "no NavAgent dual authority", not dual_authority)

	for entry: Variant in units:
		(entry as Node).queue_free()
	await get_tree().process_frame


func _test_obstacle_progress_and_arrival(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: Building = CC_SCENE.instantiate() as Building
	add_child(cc)
	cc.global_position = Vector3(0.0, 0.0, 0.0)
	cc.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(cc)

	var unit: Unit = _spawn_ai_unit(Vector3(-14.0, 0.0, 0.0))
	await get_tree().process_frame

	var objective := Vector3(14.0, 0.0, 0.0)
	var ok: bool = _issue_ai_attack_move([unit], objective, EnemyUnitMission.Mission.CREEP)
	_expect(failures, "obstacle route issued", ok)
	_expect(failures, "obstacle route valid custom", unit.is_custom_rts_movement_active())
	_expect(
		failures,
		"shared route bends around building",
		PlayerRouteNavigation.get_last_route_waypoints() >= 2
	)

	var start: Vector3 = unit.global_position
	var max_x: float = start.x
	for _i: int in 180:
		unit._physics_process(1.0 / 30.0)
		max_x = maxf(max_x, unit.global_position.x)
		# Must not tunnel through building center occupancy.
		var at_center: bool = (
			absf(unit.global_position.x) < 1.2 and absf(unit.global_position.z) < 1.2
		)
		if at_center and not PlayerRouteNavigation.is_world_walkable(unit.global_position):
			failures.append("unit entered blocked building cell")
			print("FAIL: unit entered blocked building cell")
			break
		if not unit.has_move_target:
			break
		await get_tree().process_frame

	_expect(failures, "unit progressed toward objective", max_x > start.x + 2.0)
	var dist_to_obj: float = EnemyArmyCommand.horizontal_distance(
		unit.global_position,
		objective
	)
	_expect(
		failures,
		"objective reached or near",
		dist_to_obj <= 3.5 or not unit.has_move_target
	)
	_expect(
		failures,
		"creep mission preserved after travel",
		EnemyUnitMission.get_unit_mission(unit) == EnemyUnitMission.Mission.CREEP
	)

	unit.queue_free()
	cc.queue_free()
	await get_tree().process_frame


func _test_reinforcement_joins_custom_mission(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var main: Array = []
	for i: int in 3:
		main.append(_spawn_ai_unit(Vector3(-12.0 + float(i) * 1.1, 0.0, -6.0)))
	await get_tree().process_frame

	var objective := Vector3(12.0, 0.0, 6.0)
	_expect(
		failures,
		"main squad custom order",
		_issue_ai_attack_move(main, objective, EnemyUnitMission.Mission.ATTACK)
	)

	var reinforcement: Unit = _spawn_ai_unit(Vector3(-14.0, 0.0, -8.0))
	await get_tree().process_frame
	var joined: Array = main.duplicate()
	joined.append(reinforcement)
	_expect(
		failures,
		"reinforcement join order",
		_issue_ai_attack_move(joined, objective, EnemyUnitMission.Mission.ATTACK)
	)
	_expect(failures, "reinforcement custom active", reinforcement.is_custom_rts_movement_active())
	_expect(failures, "reinforcement has shared route", reinforcement.has_custom_rts_route())
	_expect(
		failures,
		"reinforcement not on SharedSquadNav",
		SharedSquadNavigation.get_squad_for_unit(reinforcement) == null
	)
	_expect(
		failures,
		"reinforcement mission ATTACK",
		EnemyUnitMission.get_unit_mission(reinforcement) == EnemyUnitMission.Mission.ATTACK
	)

	for entry: Variant in joined:
		(entry as Node).queue_free()
	await get_tree().process_frame


func _test_mission_preserved(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame
	var unit: Unit = _spawn_ai_unit(Vector3(-8.0, 0.0, 0.0))
	await get_tree().process_frame
	_issue_ai_attack_move([unit], Vector3(8.0, 0.0, 0.0), EnemyUnitMission.Mission.DEFEND)
	_expect(
		failures,
		"defend mission preserved",
		EnemyUnitMission.get_unit_mission(unit) == EnemyUnitMission.Mission.DEFEND
	)
	_expect(failures, "defend uses custom", unit.is_custom_rts_movement_active())
	unit.queue_free()
	await get_tree().process_frame


func _test_flag_off_restores_old_path(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	MilitaryAIConfig.set_custom_rts_movement_override(false)
	_expect(
		failures,
		"override disables custom",
		not MilitaryAIConfig.is_custom_rts_movement_enabled()
	)

	var units: Array = []
	for i: int in 3:
		units.append(_spawn_ai_unit(Vector3(-10.0 + float(i) * 1.2, 0.0, 4.0)))
	await get_tree().process_frame

	var direct: Dictionary = PlayerRouteNavigation.request_group_move(
		units,
		Vector3(10.0, 0.0, 4.0),
		&"attack_move",
		false,
		&"ai"
	)
	_expect(failures, "flag off request_group_move not handled", not direct.get("handled", true))
	_expect(failures, "flag off request_group_move not valid", not direct.get("route_valid", true))

	# Legacy SharedSquadNavigation / formation may still fail without a navmesh in this
	# headless harness. The contract under test: custom backend must stay off.
	_issue_ai_attack_move(units, Vector3(10.0, 0.0, 4.0), EnemyUnitMission.Mission.ATTACK)
	_expect(
		failures,
		"flag off does not mark AI custom",
		not PlayerRouteNavigation.was_last_ai_custom_move()
	)

	var any_custom: bool = false
	for entry: Variant in units:
		var unit: Unit = entry as Unit
		if unit.is_custom_rts_movement_active() or unit.has_custom_rts_route():
			any_custom = true
	_expect(failures, "flag off units not on custom RTS", not any_custom)

	# Prove old SharedSquadNavigation API remains callable for A/B when custom is off.
	var legacy: Dictionary = SharedSquadNavigation.issue_group_command(
		units,
		Vector3(10.0, 0.0, 4.0),
		true,
		int(EnemyUnitMission.Mission.ATTACK),
		1
	)
	_expect(
		failures,
		"legacy SharedSquadNavigation still available",
		MilitaryAIConfig.is_shared_squad_nav_enabled()
		and (legacy.has("handled") or legacy.has("route_valid"))
	)

	for entry: Variant in units:
		(entry as Node).queue_free()
	MilitaryAIConfig.clear_custom_rts_movement_override()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
