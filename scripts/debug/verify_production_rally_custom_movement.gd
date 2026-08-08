extends Node

## Production-rally must use the same custom RTS backend as player RMB move.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_production_rally_custom_movement.tscn

const REPORT_PATH := "user://production_rally_custom_movement_verify_result.txt"
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARRIVE_TIMEOUT_SEC := 35.0
const ARRIVE_RADIUS := 1.6


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_production_rally_custom_movement: start")

	_expect(failures, "autoload PlayerRouteNavigation present", PlayerRouteNavigation != null)

	await _test_barracks_rally_around_obstacle(failures)
	await _test_sequential_rally_group(failures)
	await _test_rmb_same_backend(failures)

	var report: String
	if failures.is_empty():
		report = "PASS production_rally_custom_movement\n"
	else:
		report = "FAIL production_rally_custom_movement\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_barracks_rally_around_obstacle(failures: PackedStringArray) -> void:
	print("verify: barracks rally around obstacle")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var barracks: Barracks = BARRACKS_SCENE.instantiate() as Barracks
	add_child(barracks)
	barracks.global_position = Vector3(-16.0, 0.0, 0.0)
	barracks.set_completed()

	var obstacle: Building = CC_SCENE.instantiate() as Building
	add_child(obstacle)
	obstacle.global_position = Vector3(0.0, 0.0, 0.0)
	obstacle.set_completed()

	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(barracks)
	PlayerRouteNavigation.register_static_obstacle(obstacle)

	var rally: Vector3 = Vector3(16.0, 0.0, 0.0)
	barracks.set_rally_point(rally)
	_expect(failures, "obstacle blocks straight line", not PlayerRouteNavigation.is_world_walkable(Vector3(0.0, 0.0, 0.0)))

	var before_children: int = get_child_count()
	barracks._spawn_trained_unit(UNIT_SCENE, barracks.swordsman_spawn_offset)
	await get_tree().process_frame
	await get_tree().physics_frame

	var unit: Unit = _find_newest_player_unit(before_children)
	_expect(failures, "unit spawned from barracks", unit != null)
	if unit == null:
		_free_nodes([barracks, obstacle])
		return

	_expect(failures, "rally order issued (move target or custom)", unit.has_move_target or unit.has_custom_rts_route())
	_expect(failures, "movement backend CUSTOM", unit.get_movement_backend_label() == "CUSTOM")
	_expect(failures, "custom route present", unit.has_custom_rts_route())
	_expect(failures, "custom route has waypoints", unit.get_custom_rts_route_waypoint_count() > 0)
	_expect(
		failures,
		"spawn on walkable custom cell",
		PlayerRouteNavigation.is_world_walkable(unit.global_position)
	)
	_expect(
		failures,
		"old NavigationAgent not authoritative",
		not bool(unit.get("_navigation_active"))
	)

	var prov: Dictionary = unit.get_strategic_order_provenance()
	_expect(failures, "order source RALLY", String(prov.get("source", "")) == "RALLY")
	_expect(failures, "order destination recorded", (prov.get("target", Vector3.ZERO) as Vector3) != Vector3.ZERO)
	_expect(failures, "telemetry source rally", PlayerRouteNavigation.last_command_source == &"rally")

	var path: PackedVector3Array = PlayerRouteNavigation.grid.find_path(
		unit.global_position,
		rally
	)
	_expect(failures, "route exists around obstacle", path.size() > 0)
	_expect(
		failures,
		"route avoids blocked cells",
		PlayerRouteNavigation.grid.path_avoids_blocked(path)
	)
	_expect(failures, "route is not a straight blocked line", path.size() >= 3)

	var arrived: bool = await _wait_until_near(unit, rally, ARRIVE_TIMEOUT_SEC)
	_expect(failures, "unit reaches rally without second command", arrived)
	_expect(
		failures,
		"no permanent corner stall (arrived)",
		arrived and _horizontal_distance(unit.global_position, rally) <= ARRIVE_RADIUS
	)

	unit.queue_free()
	_free_nodes([barracks, obstacle])
	await get_tree().process_frame


func _test_sequential_rally_group(failures: PackedStringArray) -> void:
	print("verify: sequential barracks rally group")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var barracks: Barracks = BARRACKS_SCENE.instantiate() as Barracks
	add_child(barracks)
	barracks.global_position = Vector3(-14.0, 0.0, -8.0)
	barracks.set_completed()

	var obstacle: Building = CC_SCENE.instantiate() as Building
	add_child(obstacle)
	obstacle.global_position = Vector3(0.0, 0.0, -8.0)
	obstacle.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(barracks)
	PlayerRouteNavigation.register_static_obstacle(obstacle)

	var rally: Vector3 = Vector3(14.0, 0.0, -8.0)
	barracks.set_rally_point(rally)

	var units: Array[Unit] = []
	for _i: int in 3:
		var before: int = get_child_count()
		barracks._spawn_trained_unit(UNIT_SCENE, barracks.swordsman_spawn_offset)
		await get_tree().process_frame
		var unit: Unit = _find_newest_player_unit(before)
		if unit != null:
			units.append(unit)
			_expect(
				failures,
				"sequential unit CUSTOM backend",
				unit.get_movement_backend_label() == "CUSTOM"
			)

	_expect(failures, "spawned three rally units", units.size() == 3)

	var elapsed := 0.0
	var all_arrived := false
	while elapsed < ARRIVE_TIMEOUT_SEC:
		var near_count: int = 0
		for unit: Unit in units:
			if NodeSafety.is_alive_node(unit) and _horizontal_distance(unit.global_position, rally) <= ARRIVE_RADIUS + 1.0:
				near_count += 1
		if near_count == units.size():
			all_arrived = true
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_expect(failures, "all sequential rally units arrive", all_arrived)
	if not all_arrived:
		for i: int in units.size():
			var unit: Unit = units[i]
			if not NodeSafety.is_alive_node(unit):
				print("  unit[%d] freed" % i)
				continue
			print(
				"  unit[%d] pos=(%.1f,%.1f) dist=%.2f backend=%s move=%s"
				% [
					i,
					unit.global_position.x,
					unit.global_position.z,
					_horizontal_distance(unit.global_position, rally),
					unit.get_movement_backend_label(),
					unit.has_move_target,
				]
			)

	for unit: Unit in units:
		unit.queue_free()
	_free_nodes([barracks, obstacle])
	await get_tree().process_frame


func _test_rmb_same_backend(failures: PackedStringArray) -> void:
	print("verify: RMB and rally share custom backend")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var obstacle: Building = CC_SCENE.instantiate() as Building
	add_child(obstacle)
	obstacle.global_position = Vector3(0.0, 0.0, 8.0)
	obstacle.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(obstacle)

	var destination := Vector3(12.0, 0.0, 8.0)
	var rally_unit: Unit = UNIT_SCENE.instantiate() as Unit
	add_child(rally_unit)
	rally_unit.global_position = Vector3(-12.0, 0.0, 8.0)
	rally_unit.team_id = TeamVisuals.PLAYER_TEAM_ID
	await get_tree().process_frame

	var barracks: Barracks = BARRACKS_SCENE.instantiate() as Barracks
	add_child(barracks)
	barracks.global_position = Vector3(-12.0, 0.0, 10.0)
	barracks.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(barracks)

	_expect(
		failures,
		"rally API handled",
		barracks.issue_production_rally_move(rally_unit, destination)
	)
	_expect(failures, "rally backend CUSTOM", rally_unit.get_movement_backend_label() == "CUSTOM")

	var rmb_unit: Unit = UNIT_SCENE.instantiate() as Unit
	add_child(rmb_unit)
	rmb_unit.global_position = Vector3(-12.0, 0.0, 6.0)
	rmb_unit.team_id = TeamVisuals.PLAYER_TEAM_ID
	await get_tree().process_frame

	var rmb_result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		[rmb_unit],
		destination,
		&"move",
		false
	)
	_expect(failures, "RMB API handled", rmb_result.get("handled", false))
	_expect(failures, "RMB backend CUSTOM", rmb_unit.get_movement_backend_label() == "CUSTOM")
	_expect(
		failures,
		"both paths use CUSTOM backend",
		rally_unit.get_movement_backend_label() == "CUSTOM"
		and rmb_unit.get_movement_backend_label() == "CUSTOM"
	)

	rally_unit.queue_free()
	rmb_unit.queue_free()
	_free_nodes([barracks, obstacle])
	await get_tree().process_frame


func _find_newest_player_unit(before_child_count: int) -> Unit:
	for i: int in range(before_child_count, get_child_count()):
		var child: Node = get_child(i)
		if child is Unit:
			return child as Unit
	# Spawn parent is barracks parent (this node) — also scan group.
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and (node as Unit).is_inside_tree():
			return node as Unit
	return null


func _wait_until_near(unit: Unit, destination: Vector3, timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if not NodeSafety.is_alive_node(unit):
			return false
		if _horizontal_distance(unit.global_position, destination) <= ARRIVE_RADIUS:
			return true
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return false


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()


func _free_nodes(nodes: Array) -> void:
	for node_ref: Variant in nodes:
		if node_ref is Node and is_instance_valid(node_ref):
			(node_ref as Node).queue_free()


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
