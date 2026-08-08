extends Node

## Newly trained workers must spawn on a walkable custom-grid cell outside the
## Command Center inflated footprint, then accept normal custom movement.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_worker_spawn_command_center.tscn

const REPORT_PATH := "user://worker_spawn_command_center_verify_result.txt"
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const SPAWN_COUNT := 16
const MOVE_TIMEOUT_SEC := 20.0
const MOVE_ARRIVE_RADIUS := 1.6
const DEST_OFFSET := Vector3(0.0, 0.0, -10.0)


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_worker_spawn_command_center: start")

	_expect(failures, "autoload PlayerRouteNavigation present", PlayerRouteNavigation != null)

	await _test_raw_spawn_offset_is_blocked(failures)
	await _test_sequential_spawns_walkable_and_movable(failures)
	await _test_ground_rally_uses_custom(failures)

	var report: String
	if failures.is_empty():
		report = "PASS worker_spawn_command_center\n"
	else:
		report = "FAIL worker_spawn_command_center\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_raw_spawn_offset_is_blocked(failures: PackedStringArray) -> void:
	print("verify: preferred worker_spawn_offset is inside CC clearance")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: CommandCenter = CC_SCENE.instantiate() as CommandCenter
	add_child(cc)
	cc.global_position = Vector3(0.0, 0.0, 0.0)
	cc.set_completed()
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(cc)

	var preferred: Vector3 = cc.global_position + cc.worker_spawn_offset
	_expect(
		failures,
		"preferred spawn offset is blocked by inflated CC footprint",
		not PlayerRouteNavigation.is_world_walkable(preferred)
	)

	cc.queue_free()
	await get_tree().process_frame


func _test_sequential_spawns_walkable_and_movable(failures: PackedStringArray) -> void:
	print("verify: sequential CC worker spawns are walkable and movable")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: CommandCenter = CC_SCENE.instantiate() as CommandCenter
	add_child(cc)
	cc.global_position = Vector3(4.0, 0.0, 4.0)
	cc.set_completed()
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(cc)

	var workers: Array[Worker] = []
	for i: int in SPAWN_COUNT:
		var before: int = get_child_count()
		cc._spawn_worker()
		await get_tree().process_frame
		var worker: Worker = _find_newest_worker(before)
		_expect(failures, "worker %d spawned" % i, worker != null)
		if worker == null:
			continue
		workers.append(worker)

		_expect(
			failures,
			"worker %d spawn walkable" % i,
			PlayerRouteNavigation.is_world_walkable(worker.global_position)
		)
		_expect(
			failures,
			"worker %d not inside preferred blocked offset" % i,
			_horizontal_distance(
				worker.global_position,
				cc.global_position + cc.worker_spawn_offset
			) > 0.05
			or PlayerRouteNavigation.is_world_walkable(cc.global_position + cc.worker_spawn_offset)
		)
		_expect(
			failures,
			"worker %d no NavigationAgent authority" % i,
			not worker.uses_navigation_agent()
		)

	_expect(failures, "spawned all workers", workers.size() == SPAWN_COUNT)

	# Move each worker a short distance with the normal custom backend.
	var destination: Vector3 = cc.global_position + DEST_OFFSET
	destination = PlayerRouteNavigation.nearest_walkable_world(destination)
	for i: int in workers.size():
		var worker: Worker = workers[i]
		if not NodeSafety.is_alive_node(worker):
			_expect(failures, "worker %d alive for move" % i, false)
			continue
		var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			[worker],
			destination,
			&"move",
			false,
			&"player"
		)
		_expect(failures, "worker %d custom move handled" % i, result.get("handled", false))
		_expect(
			failures,
			"worker %d CUSTOM backend" % i,
			worker.get_movement_backend_label() == "CUSTOM"
		)

	var elapsed := 0.0
	var all_left_spawn := false
	while elapsed < MOVE_TIMEOUT_SEC:
		var moved_count: int = 0
		for worker: Worker in workers:
			if not NodeSafety.is_alive_node(worker):
				continue
			# Left the CC edge and progressed toward destination.
			if (
				_horizontal_distance(worker.global_position, cc.global_position) >= 4.0
				or _horizontal_distance(worker.global_position, destination) <= MOVE_ARRIVE_RADIUS + 2.0
			):
				moved_count += 1
		if moved_count == workers.size():
			all_left_spawn = true
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

	_expect(failures, "all workers leave CC spawn via custom movement", all_left_spawn)
	if not all_left_spawn:
		for i: int in workers.size():
			var worker: Worker = workers[i]
			if not NodeSafety.is_alive_node(worker):
				print("  worker[%d] freed" % i)
				continue
			print(
				"  worker[%d] pos=(%.2f,%.2f) dist_cc=%.2f dist_dest=%.2f backend=%s walkable=%s"
				% [
					i,
					worker.global_position.x,
					worker.global_position.z,
					_horizontal_distance(worker.global_position, cc.global_position),
					_horizontal_distance(worker.global_position, destination),
					worker.get_movement_backend_label(),
					str(PlayerRouteNavigation.is_world_walkable(worker.global_position)),
				]
			)

	for worker: Worker in workers:
		if NodeSafety.is_alive_node(worker):
			worker.queue_free()
	cc.queue_free()
	await get_tree().process_frame


func _test_ground_rally_uses_custom(failures: PackedStringArray) -> void:
	print("verify: CC ground rally uses custom movement")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: CommandCenter = CC_SCENE.instantiate() as CommandCenter
	add_child(cc)
	cc.global_position = Vector3(-8.0, 0.0, 0.0)
	cc.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(cc)

	var rally: Vector3 = Vector3(8.0, 0.0, 0.0)
	cc.set_rally_point(rally)

	var before: int = get_child_count()
	cc._spawn_worker()
	await get_tree().process_frame
	await get_tree().physics_frame

	var worker: Worker = _find_newest_worker(before)
	_expect(failures, "rally worker spawned", worker != null)
	if worker == null:
		cc.queue_free()
		return

	_expect(
		failures,
		"rally spawn walkable",
		PlayerRouteNavigation.is_world_walkable(worker.global_position)
	)
	_expect(failures, "rally CUSTOM backend", worker.get_movement_backend_label() == "CUSTOM")
	_expect(failures, "rally custom route present", worker.has_custom_rts_route())
	_expect(failures, "rally no NavigationAgent", not worker.uses_navigation_agent())

	var arrived: bool = await _wait_until_near(worker, rally, MOVE_TIMEOUT_SEC)
	_expect(failures, "rally worker reaches rally point", arrived)

	worker.queue_free()
	cc.queue_free()
	await get_tree().process_frame


func _find_newest_worker(before_child_count: int) -> Worker:
	for i: int in range(before_child_count, get_child_count()):
		var child: Node = get_child(i)
		if child is Worker:
			return child as Worker
	for node: Node in get_tree().get_nodes_in_group("workers"):
		if node is Worker and (node as Worker).is_inside_tree():
			return node as Worker
	return null


func _wait_until_near(unit: Unit, destination: Vector3, timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if not NodeSafety.is_alive_node(unit):
			return false
		if _horizontal_distance(unit.global_position, destination) <= MOVE_ARRIVE_RADIUS:
			return true
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return false


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
