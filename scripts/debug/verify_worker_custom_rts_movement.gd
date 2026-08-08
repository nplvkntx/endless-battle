extends Node

## Worker task travel must use the same custom RTS backend as player RMB.
## Godot --headless --path <project> --scene res://scenes/debug/verify_worker_custom_rts_movement.tscn

const REPORT_PATH := "user://worker_custom_rts_movement_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const MINE_SCENE: PackedScene = preload("res://scenes/resources/gold_mine.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/resources/tree.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_worker_custom_rts_movement: start")
	_expect(failures, "autoload PlayerRouteNavigation present", PlayerRouteNavigation != null)
	_expect(
		failures,
		"worker scene has no NavigationAgent3D",
		_worker_scene_has_no_nav_agent()
	)

	await _test_worker_mine_travel(failures)
	await _test_worker_tree_travel(failures)
	await _test_worker_return_travel(failures)
	await _test_worker_build_travel(failures)

	var report: String
	if failures.is_empty():
		report = "PASS worker_custom_rts_movement\n"
	else:
		report = "FAIL worker_custom_rts_movement\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _worker_scene_has_no_nav_agent() -> bool:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	var has_agent: bool = worker.get_node_or_null("NavigationAgent3D") != null
	worker.free()
	return not has_agent


func _test_worker_mine_travel(failures: PackedStringArray) -> void:
	print("verify: worker → mine uses CUSTOM")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: Building = CC_SCENE.instantiate() as Building
	add_child(cc)
	cc.global_position = Vector3(-12.0, 0.0, 0.0)
	cc.set_completed()

	var obstacle: Building = CC_SCENE.instantiate() as Building
	add_child(obstacle)
	obstacle.global_position = Vector3(0.0, 0.0, 0.0)
	obstacle.set_completed()

	var mine: GoldMine = MINE_SCENE.instantiate() as GoldMine
	add_child(mine)
	mine.global_position = Vector3(14.0, 0.0, 0.0)

	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3(-16.0, 0.0, 0.0)
	worker.team_id = 0

	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(cc)
	PlayerRouteNavigation.register_static_obstacle(obstacle)

	worker.issue_order(UnitOrder.gather(mine), false)
	await get_tree().process_frame
	await get_tree().physics_frame

	_expect(failures, "mine: has move or custom route", worker.has_move_target or worker.has_custom_rts_route())
	_expect(failures, "mine: backend CUSTOM", worker.get_movement_backend_label() == "CUSTOM")
	_expect(failures, "mine: custom route present", worker.has_custom_rts_route())
	_expect(failures, "mine: uses_navigation_agent false", not worker.uses_navigation_agent())
	_expect(
		failures,
		"mine: telemetry worker_task",
		PlayerRouteNavigation.last_command_source == &"worker_task"
		or PlayerRouteNavigation.last_command_source == &"strategic"
		or PlayerRouteNavigation.last_command_source == &"player"
	)
	var dest: Vector3 = worker.get_movement_destination()
	_expect(
		failures,
		"mine: destination walkable",
		PlayerRouteNavigation.is_world_walkable(dest)
	)

	_free_nodes([worker, mine, obstacle, cc])


func _test_worker_tree_travel(failures: PackedStringArray) -> void:
	print("verify: worker → tree uses CUSTOM")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	add_child(tree)
	tree.global_position = Vector3(10.0, 0.0, 4.0)

	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3(-8.0, 0.0, 4.0)
	worker.team_id = 0

	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()

	worker.issue_order(UnitOrder.gather(tree), false)
	await get_tree().process_frame
	await get_tree().physics_frame

	_expect(failures, "tree: backend CUSTOM", worker.get_movement_backend_label() == "CUSTOM")
	_expect(failures, "tree: custom route present", worker.has_custom_rts_route())
	_expect(failures, "tree: no nav agent", not worker.uses_navigation_agent())

	_free_nodes([worker, tree])


func _test_worker_return_travel(failures: PackedStringArray) -> void:
	print("verify: worker return → drop-off uses CUSTOM")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: CommandCenter = CC_SCENE.instantiate() as CommandCenter
	add_child(cc)
	cc.global_position = Vector3(12.0, 0.0, -6.0)
	cc.set_completed()
	cc.team_id = 0

	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3(-10.0, 0.0, -6.0)
	worker.team_id = 0
	worker._carried_amount = 10
	worker._assigned_resource_id = &"gold"
	worker._gather_state = Worker.GatherTripState.TO_COMMAND_CENTER
	worker._return_dropoff = cc
	worker._assigned_dropoff = cc

	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(cc)

	worker.set_movement_target(worker._compute_command_center_dropoff_position(cc))
	await get_tree().process_frame
	await get_tree().physics_frame

	_expect(failures, "return: backend CUSTOM", worker.get_movement_backend_label() == "CUSTOM")
	_expect(failures, "return: custom route present", worker.has_custom_rts_route())
	_expect(failures, "return: no nav agent", not worker.uses_navigation_agent())

	_free_nodes([worker, cc])


func _test_worker_build_travel(failures: PackedStringArray) -> void:
	print("verify: worker → build site uses CUSTOM")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var farm: Building = FARM_SCENE.instantiate() as Building
	add_child(farm)
	farm.global_position = Vector3(10.0, 0.0, 10.0)
	farm.team_id = 0
	# Leave under construction so worker can travel to build.
	if farm.has_method("begin_construction"):
		farm.begin_construction()
	elif "building_state" in farm:
		farm.building_state = Building.STATE_UNDER_CONSTRUCTION

	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3(-8.0, 0.0, 10.0)
	worker.team_id = 0

	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(farm)

	worker.issue_order(UnitOrder.build(farm), false)
	await get_tree().process_frame
	await get_tree().physics_frame

	_expect(failures, "build: backend CUSTOM", worker.get_movement_backend_label() == "CUSTOM")
	_expect(
		failures,
		"build: custom route or move target",
		worker.has_custom_rts_route() or worker.has_move_target
	)
	_expect(failures, "build: no nav agent", not worker.uses_navigation_agent())

	_free_nodes([worker, farm])


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if ok:
		print("  OK  ", label)
	else:
		failures.append(label)
		print("  FAIL ", label)


func _free_nodes(nodes: Array) -> void:
	for node: Variant in nodes:
		if NodeSafety.is_alive_node(node):
			(node as Node).queue_free()
	await get_tree().process_frame
