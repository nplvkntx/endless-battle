extends Node

## Focused regression: after Barracks completes with the builder on a standee,
## the worker must sit on a walkable custom-grid cell and accept a normal
## PlayerRouteNavigation move — no generic stuck recovery.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_post_construction_worker_exit.tscn

const REPORT_PATH := "user://post_construction_worker_exit_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const MOVE_TIMEOUT_SEC := 12.0
const MOVE_ARRIVE_RADIUS := 1.75


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_post_construction_worker_exit: start")
	ConstructionReservations.reset_match_state()
	WorkerGathering.reset_match_state()
	WorkerAiUnstuck.reset_match_state()

	await _test_standee_sides_exit_and_move(failures)

	var report: String
	if failures.is_empty():
		report = "PASS post_construction_worker_exit\n"
	else:
		report = "FAIL post_construction_worker_exit\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_standee_sides_exit_and_move(failures: PackedStringArray) -> void:
	## Corners 0/2/4/6 and mid-edges 1/3/5/7.
	var sample_indices: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	for sample_index: int in sample_indices:
		PlayerRouteNavigation.clear_all()
		var root := Node3D.new()
		add_child(root)

		var barracks: Building = BARRACKS_SCENE.instantiate() as Building
		root.add_child(barracks)
		barracks.global_position = Vector3(0.0, 0.0, 0.0)
		barracks.start_under_construction()
		barracks.setup_construction(0.3)
		await get_tree().process_frame
		await get_tree().process_frame
		PlayerRouteNavigation.ensure_grid_ready()
		barracks._register_rts_occupancy()

		var points: Array[Vector3] = barracks.get_construction_points()
		if sample_index >= points.size():
			_expect(failures, "sample[%d]: standee exists" % sample_index, false)
			_free_nodes([root])
			continue

		var standee: Vector3 = points[sample_index]
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		root.add_child(worker)
		worker.global_position = Vector3(standee.x, 0.5, standee.z)
		worker.start_construction_order(barracks)
		worker.global_position = Vector3(standee.x, 0.5, standee.z)
		worker._construction_target_point = standee
		worker._construction_target_point_valid = true
		if worker._build_trip_state == Worker.BuildTripState.TO_BUILDING:
			worker._try_commit_construction_if_in_range()
		await get_tree().physics_frame

		_expect(
			failures,
			"sample[%d]: constructing" % sample_index,
			worker.is_constructing()
		)

		barracks.force_construction_progress_for_verify(1.0)
		await get_tree().process_frame

		_expect(
			failures,
			"sample[%d]: barracks completed" % sample_index,
			barracks.building_state == Building.STATE_COMPLETED
		)
		_expect(
			failures,
			"sample[%d]: standee itself blocked after complete" % sample_index,
			not PlayerRouteNavigation.is_world_walkable(standee)
		)
		_expect(
			failures,
			"sample[%d]: worker walkable after exit" % sample_index,
			PlayerRouteNavigation.is_world_walkable(worker.global_position)
		)
		_expect(
			failures,
			"sample[%d]: worker outside footprint" % sample_index,
			not barracks.is_position_inside_footprint(worker.global_position)
		)

		## Move away via normal custom RTS command (no unstuck system).
		var destination := Vector3(12.0, 0.0, 12.0)
		destination = PlayerRouteNavigation.nearest_walkable_world(destination)
		var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			[worker],
			destination,
			&"move",
			false,
			&"verify_post_build_exit"
		)
		_expect(
			failures,
			"sample[%d]: custom move handled" % sample_index,
			bool(result.get("handled", false))
		)

		var arrived: bool = await _wait_arrive(worker, destination, MOVE_TIMEOUT_SEC)
		_expect(
			failures,
			"sample[%d]: worker arrives after custom move" % sample_index,
			arrived
		)
		_expect(
			failures,
			"sample[%d]: still walkable at destination" % sample_index,
			PlayerRouteNavigation.is_world_walkable(worker.global_position)
		)

		_free_nodes([root])
		await get_tree().process_frame


func _wait_arrive(unit: Unit, destination: Vector3, timeout_sec: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not NodeSafety.is_alive_node(unit):
			return false
		var delta: Vector3 = unit.global_position - destination
		delta.y = 0.0
		if delta.length() <= MOVE_ARRIVE_RADIUS:
			return true
		await get_tree().physics_frame
	return false


func _free_nodes(nodes: Array) -> void:
	for node_ref: Variant in nodes:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).free()


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
