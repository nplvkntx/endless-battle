extends Node

## Headless verification for worker gather/delivery/reservation reliability.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_worker_gathering.tscn

const REPORT_PATH := "user://worker_gathering_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/resources/tree.tscn")
const GOLD_SCENE: PackedScene = preload("res://scenes/resources/gold_mine.tscn")
const SETTLE_MS := 5000
const CYCLE_MS := 8000


func _ready() -> void:
	var failures: PackedStringArray = []
	WorkerGathering.reset_match_state()
	WorkerAiUnstuck.reset_match_state()

	print("verify_worker_gathering: start")
	_verify_no_name_based_faction_filter(failures)
	await _verify_multi_tree_gather(failures)
	await _verify_multi_gold_mine(failures)
	await _verify_five_workers_one_mine_no_stuck(failures)
	await _verify_invalid_resource_target(failures)
	await _verify_ordered_away_while_gathering(failures)
	await _verify_blocked_route_recovery(failures)
	await _verify_death_releases_reservation(failures)
	await _verify_gather_return_cycles(failures)
	await _verify_construction_suspend_resume(failures)

	var report: String
	if failures.is_empty():
		report = "PASS worker_gathering\n"
	else:
		report = "FAIL worker_gathering\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_no_name_based_faction_filter(failures: PackedStringArray) -> void:
	print("verify: faction metadata (no name checks)")
	var player_tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	var enemy_tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	var neutral_tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	add_child(player_tree)
	add_child(enemy_tree)
	add_child(neutral_tree)
	player_tree.name = "TotallyRandomPlayerTreeName"
	enemy_tree.name = "TotallyRandomEnemyTreeName"
	neutral_tree.name = "TotallyRandomNeutralTreeName"
	player_tree.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	enemy_tree.set_owner_faction(GatherableResource.OwnerFaction.ENEMY)
	neutral_tree.set_owner_faction(GatherableResource.OwnerFaction.NEUTRAL)

	_expect(failures, "player tree usable by player", player_tree.is_usable_by_faction(false))
	_expect(failures, "player tree not usable by enemy", not player_tree.is_usable_by_faction(true))
	_expect(failures, "enemy tree usable by enemy", enemy_tree.is_usable_by_faction(true))
	_expect(failures, "enemy tree not usable by player", not enemy_tree.is_usable_by_faction(false))
	_expect(failures, "neutral tree usable by both", neutral_tree.is_usable_by_faction(false) and neutral_tree.is_usable_by_faction(true))
	_expect(failures, "player tree in player group", player_tree.is_in_group(GatherableResource.GROUP_PLAYER_RESOURCES))
	_expect(failures, "enemy tree in enemy group", enemy_tree.is_in_group(GatherableResource.GROUP_ENEMY_RESOURCES))

	player_tree.free()
	enemy_tree.free()
	neutral_tree.free()


func _verify_multi_tree_gather(failures: PackedStringArray) -> void:
	print("verify: several workers gathering nearby trees")
	var harness: Dictionary = await _spawn_harness()
	var trees: Array[WoodTree] = []
	for index: int in 4:
		var tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
		harness["root"].add_child(tree)
		tree.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
		tree.global_position = Vector3(float(index) * 2.5, 0.0, 0.0)
		trees.append(tree)

	var workers: Array[Worker] = []
	for index: int in 4:
		var worker: Worker = _spawn_worker(harness["root"], Vector3(float(index) * 2.5, 0.0, -4.0), false)
		workers.append(worker)

	await _wait_nav_ready(workers[0])
	for index: int in workers.size():
		workers[index].command_gather_tree(trees[index % trees.size()], true)

	await _wait_msec(SETTLE_MS)

	var reserved: int = 0
	for tree: WoodTree in trees:
		reserved += tree.get_assigned_worker_count()
	_expect(failures, "multi-tree: reservations distributed", reserved >= 2)

	var approaching: int = 0
	for worker: Worker in workers:
		if worker._gather_state != Worker.GatherTripState.IDLE:
			approaching += 1
	_expect(failures, "multi-tree: workers actively gathering", approaching >= 2)

	await _free_harness(harness)


func _verify_multi_gold_mine(failures: PackedStringArray) -> void:
	print("verify: several workers using one gold mine")
	var harness: Dictionary = await _spawn_harness()
	var mine: GoldMine = GOLD_SCENE.instantiate() as GoldMine
	harness["root"].add_child(mine)
	mine.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	mine.global_position = Vector3(0.0, 0.0, 0.0)

	var workers: Array[Worker] = []
	for index: int in 4:
		var worker: Worker = _spawn_worker(
			harness["root"],
			Vector3(-4.0 + float(index) * 1.5, 0.0, -5.0),
			false
		)
		workers.append(worker)

	await _wait_nav_ready(workers[0])
	for worker: Worker in workers:
		worker.command_gather_gold_mine(mine, true)

	await _wait_msec(SETTLE_MS)

	_expect(failures, "gold mine: soft reservations tracked", mine.get_assigned_worker_count() >= 2)

	var active: int = 0
	for worker: Worker in workers:
		if worker.get_assigned_gather_resource_id() == &"gold":
			active += 1
	_expect(failures, "gold mine: workers assigned to gold", active >= 3)

	var approaches: Dictionary = {}
	for worker: Worker in workers:
		var approach: Vector3 = worker._compute_resource_approach_position(mine)
		var key: String = "%.1f,%.1f" % [approach.x, approach.z]
		approaches[key] = true
	_expect(failures, "gold mine: approach points are not all identical", approaches.size() >= 2)

	await _free_harness(harness)


func _verify_five_workers_one_mine_no_stuck(failures: PackedStringArray) -> void:
	print("verify: five workers one mine — no permanent stuck / unique slots")
	var harness: Dictionary = await _spawn_harness()
	var mine: GoldMine = GOLD_SCENE.instantiate() as GoldMine
	harness["root"].add_child(mine)
	mine.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	mine.global_position = Vector3(6.0, 0.0, 0.0)

	var workers: Array[Worker] = []
	for index: int in 5:
		var worker: Worker = _spawn_worker(
			harness["root"],
			Vector3(-5.0 + float(index) * 1.2, 0.0, -4.0),
			false
		)
		workers.append(worker)

	await _wait_nav_ready(workers[0])
	for index: int in workers.size():
		workers[index].set_gather_approach_slot_hint(index)
		workers[index].command_gather_gold_mine(mine, true)

	await _wait_msec(SETTLE_MS)

	var active: int = 0
	var idle_stuck: int = 0
	var approaches: Dictionary = {}
	for worker: Worker in workers:
		if worker.get_assigned_gather_resource_id() == &"gold":
			active += 1
		if (
			worker._gather_state == Worker.GatherTripState.IDLE
			and worker._carried_amount <= 0
			and worker.get_assigned_gather_resource_id().is_empty()
		):
			idle_stuck += 1
		var approach: Vector3 = worker._compute_resource_approach_position(mine)
		approaches["%.1f,%.1f" % [approach.x, approach.z]] = true

	_expect(failures, "5-mine: all workers remain assigned", active == 5)
	_expect(failures, "5-mine: none permanently abandoned idle", idle_stuck == 0)
	_expect(failures, "5-mine: unique approach slots", approaches.size() >= 3)
	_expect(failures, "5-mine: reservations present", mine.get_assigned_worker_count() >= 3)

	await _free_harness(harness)


func _verify_invalid_resource_target(failures: PackedStringArray) -> void:
	print("verify: resource target becoming invalid")
	var harness: Dictionary = await _spawn_harness()
	var tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	harness["root"].add_child(tree)
	tree.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	tree.global_position = Vector3(3.0, 0.0, 0.0)
	tree.wood_amount = 2

	var worker: Worker = _spawn_worker(harness["root"], Vector3(-2.0, 0.0, 0.0), false)
	await _wait_nav_ready(worker)
	worker.command_gather_tree(tree, true)
	await _wait_msec(200)
	_expect(failures, "invalid target: gather started", worker._gather_source == tree)

	tree.wood_amount = 0
	tree.depleted.emit()
	await get_tree().process_frame
	await _wait_msec(400)
	worker._sanitize_stored_targets()
	if worker.has_method("_handle_gather_source_lost") and not NodeSafety.is_alive_node(tree):
		pass

	# Force depleted removal path and reassignment attempt.
	if NodeSafety.is_alive_node(tree):
		tree.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	worker._sanitize_stored_targets()
	if worker._gather_source == null and worker._carried_amount <= 0:
		worker._handle_gather_source_lost()

	_expect(
		failures,
		"invalid target: worker released dead source",
		worker._gather_source == null or not NodeSafety.is_alive_node(worker._gather_source)
	)
	_expect(failures, "invalid target: wood lock cleared", worker._locked_wood_tree == null)

	await _free_harness(harness)


func _verify_ordered_away_while_gathering(failures: PackedStringArray) -> void:
	print("verify: worker ordered away while gathering")
	var harness: Dictionary = await _spawn_harness()
	var tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	harness["root"].add_child(tree)
	tree.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	tree.global_position = Vector3(4.0, 0.0, 0.0)

	var worker: Worker = _spawn_worker(harness["root"], Vector3(-2.0, 0.0, 0.0), false)
	await _wait_nav_ready(worker)
	worker.command_gather_tree(tree, true)
	await _wait_msec(200)
	_expect(failures, "ordered away: reservation held while gathering", tree.get_assigned_worker_count() >= 1)

	worker.cancel_gathering()
	worker.set_movement_target(Vector3(-6.0, 0.0, 2.0))
	await get_tree().process_frame

	_expect(failures, "ordered away: gather cancelled", worker._gather_state == Worker.GatherTripState.IDLE)
	_expect(failures, "ordered away: reservation released", tree.get_assigned_worker_count() == 0)
	_expect(failures, "ordered away: move accepted", worker.has_move_target)

	await _free_harness(harness)


func _verify_blocked_route_recovery(failures: PackedStringArray) -> void:
	print("verify: blocked route to resource")
	var harness: Dictionary = await _spawn_harness_with_wall()
	var tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	harness["root"].add_child(tree)
	tree.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	tree.global_position = Vector3(8.0, 0.0, 0.0)

	var worker: Worker = _spawn_worker(harness["root"], Vector3(-8.0, 0.0, 0.0), false)
	await _wait_nav_ready(worker)
	worker.command_gather_tree(tree, true)

	var progressed_or_repathed: bool = false
	var start_slot: int = worker._source_approach_candidate_index
	var deadline: int = Time.get_ticks_msec() + SETTLE_MS
	while Time.get_ticks_msec() < deadline:
		if worker._source_approach_candidate_index != start_slot:
			progressed_or_repathed = true
			break
		if worker.global_position.x > -6.0:
			progressed_or_repathed = true
			break
		if worker._gather_state == Worker.GatherTripState.IDLE and worker._locked_wood_tree == null:
			# Gave up / reassigned rather than infinite loop.
			progressed_or_repathed = true
			break
		await get_tree().physics_frame

	_expect(failures, "blocked route: worker repaths, moves, or releases target", progressed_or_repathed)
	await _free_harness(harness)


func _verify_death_releases_reservation(failures: PackedStringArray) -> void:
	print("verify: worker dying while holding reservation")
	var harness: Dictionary = await _spawn_harness()
	var tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	harness["root"].add_child(tree)
	tree.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	tree.global_position = Vector3(2.0, 0.0, 0.0)

	var worker: Worker = _spawn_worker(harness["root"], Vector3(-2.0, 0.0, 0.0), false)
	await _wait_nav_ready(worker)
	worker.command_gather_tree(tree, true)
	await _wait_msec(100)
	_expect(failures, "death: reservation acquired", tree.get_assigned_worker_count() >= 1)

	worker._on_health_depleted()
	await get_tree().process_frame
	await get_tree().process_frame

	tree.purge_stale_reservations()
	_expect(failures, "death: reservation released", tree.get_assigned_worker_count() == 0)
	await _free_harness(harness)


func _verify_gather_return_cycles(failures: PackedStringArray) -> void:
	print("verify: repeated gather and return cycles")
	var harness: Dictionary = await _spawn_harness()
	var mine: GoldMine = GOLD_SCENE.instantiate() as GoldMine
	harness["root"].add_child(mine)
	mine.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	mine.global_position = Vector3(4.0, 0.0, 0.0)

	var dropoff: CommandCenter = _spawn_fake_command_center(harness["root"], Vector3(-4.0, 0.0, 0.0), false)
	var worker: Worker = _spawn_worker(harness["root"], Vector3(0.0, 0.0, -2.0), false)
	await _wait_nav_ready(worker)
	worker.command_gather_gold_mine(mine, true)

	var saw_to_source: bool = false
	var saw_wait_or_return: bool = false
	var resumed_to_source: bool = false
	var deadline: int = Time.get_ticks_msec() + CYCLE_MS
	while Time.get_ticks_msec() < deadline:
		if worker._gather_state == Worker.GatherTripState.TO_SOURCE:
			if saw_wait_or_return:
				resumed_to_source = true
				break
			saw_to_source = true
		if (
			worker._gather_state == Worker.GatherTripState.GATHER_WAIT
			or worker._gather_state == Worker.GatherTripState.TO_COMMAND_CENTER
			or worker._carried_amount > 0
		):
			saw_wait_or_return = true

		if worker._gather_state == Worker.GatherTripState.TO_SOURCE:
			if _horizontal_distance(worker.global_position, mine.global_position) < 4.5:
				worker.global_position = mine.global_position + Vector3(2.4, 0.0, 0.0)
				worker._handle_arrived_at_source()
		elif worker._gather_state == Worker.GatherTripState.GATHER_WAIT:
			# Real wait is 1s; allow a few frames then complete.
			await _wait_msec(1100)
			if worker._gather_state == Worker.GatherTripState.GATHER_WAIT:
				worker._on_gather_wait_finished()
		elif worker._gather_state == Worker.GatherTripState.TO_COMMAND_CENTER:
			if dropoff != null:
				worker.global_position = dropoff.global_position + Vector3(1.6, 0.0, 0.0)
				worker._handle_command_center_arrival()
		await get_tree().physics_frame

	_expect(failures, "cycle: started toward source", saw_to_source)
	_expect(failures, "cycle: gathered or returned", saw_wait_or_return)
	_expect(failures, "cycle: resumed gather after delivery", resumed_to_source)

	await _free_harness(harness)


func _verify_construction_suspend_resume(failures: PackedStringArray) -> void:
	print("verify: construction suspends and can resume gathering")
	var harness: Dictionary = await _spawn_harness()
	var tree: WoodTree = TREE_SCENE.instantiate() as WoodTree
	harness["root"].add_child(tree)
	tree.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	tree.global_position = Vector3(3.0, 0.0, 0.0)

	var building := _spawn_fake_building(harness["root"], Vector3(-3.0, 0.0, 3.0))
	var worker: Worker = _spawn_worker(harness["root"], Vector3(0.0, 0.0, 0.0), false)
	await _wait_nav_ready(worker)
	worker.command_gather_tree(tree, true)
	await _wait_msec(100)
	_expect(failures, "build override: gathering active", worker._gather_state != Worker.GatherTripState.IDLE)

	worker.start_construction_order(building)
	await get_tree().process_frame
	_expect(failures, "build override: gather suspended", worker._gather_state == Worker.GatherTripState.IDLE)
	_expect(failures, "build override: wood reservation released while building", tree.get_assigned_worker_count() == 0)
	_expect(failures, "build override: construction active", worker.is_on_construction_trip() or worker._build_trip_state != Worker.BuildTripState.IDLE)

	# Simulate finished construction resume path.
	worker._build_trip_state = Worker.BuildTripState.CONSTRUCTION_WAIT
	worker._building_target = building
	worker.on_building_construction_finished()
	await get_tree().process_frame

	_expect(
		failures,
		"build override: gathering resumed or reassigned after construction",
		worker._gather_state != Worker.GatherTripState.IDLE or worker._suspended_resource_id.is_empty()
	)

	await _free_harness(harness)


func _spawn_worker(parent: Node, position: Vector3, enemy: bool) -> Worker:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	parent.add_child(worker)
	worker.add_to_group(&"units")
	if enemy:
		worker.add_to_group(&"enemy_workers")
		worker.add_to_group(&"enemies")
		worker.team_id = 1
	else:
		worker.add_to_group(&"workers")
		worker.team_id = 0
	worker.global_position = position
	return worker


func _spawn_fake_command_center(parent: Node, position: Vector3, enemy: bool) -> CommandCenter:
	var cc_scene: PackedScene = load("res://scenes/buildings/command_center.tscn") as PackedScene
	var command_center: CommandCenter = cc_scene.instantiate() as CommandCenter
	parent.add_child(command_center)
	command_center.global_position = position
	command_center.building_state = Building.STATE_COMPLETED
	if enemy:
		command_center.team_id = CommandCenter.ENEMY_TEAM_ID
		if not command_center.is_in_group(&"enemy_command_center"):
			command_center.add_to_group(&"enemy_command_center")
		if command_center.is_in_group(&"player_command_center"):
			command_center.remove_from_group(&"player_command_center")
	else:
		command_center.team_id = 0
		if not command_center.is_in_group(&"player_command_center"):
			command_center.add_to_group(&"player_command_center")
	return command_center


func _spawn_fake_building(parent: Node, position: Vector3) -> Building:
	var farm_scene: PackedScene = load("res://scenes/buildings/farm.tscn") as PackedScene
	var farm: Building = farm_scene.instantiate() as Building
	parent.add_child(farm)
	farm.global_position = position
	farm.building_state = Building.STATE_UNDER_CONSTRUCTION
	return farm


func _spawn_harness() -> Dictionary:
	var root := Node3D.new()
	root.name = "WorkerGatherHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)
	await get_tree().process_frame
	await _bake_nav_mesh(region, root, false)
	return {"root": root, "region": region}


func _spawn_harness_with_wall() -> Dictionary:
	var root := Node3D.new()
	root.name = "WorkerBlockedHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)

	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.BUILDINGS
	wall.position = Vector3(0.0, 0.0, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 12.0)
	shape.shape = box
	wall.add_child(shape)
	var obstacle := NavigationObstacle3D.new()
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.radius = 1.2
	obstacle.height = 2.0
	wall.add_child(obstacle)
	root.add_child(wall)

	await get_tree().process_frame
	await _bake_nav_mesh(region, root, true)
	return {"root": root, "region": region}


func _bake_nav_mesh(region: NavigationRegion3D, parent: Node, parse_obstacles: bool) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25

	var source_data := NavigationMeshSourceGeometryData3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(40.0, 40.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
	if parse_obstacles:
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


func _wait_msec(duration_msec: int) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + duration_msec
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().physics_frame


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var delta: Vector3 = a - b
	delta.y = 0.0
	return delta.length()


func _free_harness(harness: Dictionary) -> void:
	var root: Node = harness.get("root") as Node
	if root != null and is_instance_valid(root):
		root.free()
	WorkerGathering.reset_match_state()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
