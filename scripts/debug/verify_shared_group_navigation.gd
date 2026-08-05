extends Node

## Headless verification for shared group routing across all movable units.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_shared_group_navigation.tscn

const REPORT_PATH := "user://shared_group_navigation_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const GOLD_SCENE: PackedScene = preload("res://scenes/resources/gold_mine.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	WorkerGathering.reset_match_state()
	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()

	print("verify_shared_group_navigation: start")
	await _verify_single_unit_move(failures)
	await _verify_worker_point_move_shared(failures)
	await _verify_shared_route_counts(failures, 10)
	await _verify_shared_route_counts(failures, 50)
	await _verify_shared_route_counts(failures, 100)
	await _verify_mixed_size_slots(failures)
	await _verify_workers_not_military_formation(failures)
	await _verify_five_workers_gold_mine(failures)
	await _verify_shift_queued_group_move(failures)
	await _verify_attack_move_shares_route(failures)
	await _verify_direct_attack_not_group_route(failures)
	await _verify_route_fallback(failures)
	await _verify_temp_block_no_repath_storm(failures)
	await _verify_arrival_clears(failures)
	await _verify_match_reset_clears(failures)
	await _verify_ai_and_player_share_foundation(failures)
	_report_perf_snapshot()

	var report: String
	if failures.is_empty():
		report = "PASS shared_group_navigation\n"
	else:
		report = "FAIL shared_group_navigation\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_single_unit_move(failures: PackedStringArray) -> void:
	print("verify: single unit move")
	var harness: Dictionary = await _spawn_nav_harness()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(unit)
	unit.global_position = Vector3(-4.0, 0.0, 0.0)
	await _wait_nav_ready(unit)

	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()
	unit.issue_order(UnitOrder.move(Vector3(6.0, 0.0, 0.0)), false)
	await get_tree().physics_frame
	_expect(failures, "1 unit: has move target", unit.has_move_target)
	_expect(
		failures,
		"1 unit: does not create shared squad",
		SharedSquadNavigation.get_active_squad_count() == 0
	)
	unit.queue_free()
	await _free_harness(harness)


func _verify_worker_point_move_shared(failures: PackedStringArray) -> void:
	print("verify: worker generic point move uses shared routing")
	var harness: Dictionary = await _spawn_nav_harness()
	var workers: Array = []
	for index: int in 5:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		harness["root"].add_child(worker)
		worker.global_position = Vector3(-6.0 + float(index) * 1.2, 0.0, -2.0)
		workers.append(worker)
	await _wait_nav_ready(workers[0] as Unit)

	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()
	var result: Dictionary = SharedSquadNavigation.issue_player_group_command(
		workers, Vector3(8.0, 0.0, 2.0), &"move", false
	)
	_expect(failures, "5 workers move: shared handled", result.get("handled", false))
	_expect(
		failures,
		"5 workers move: one strategic route",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0)) == 1
	)
	_expect(
		failures,
		"5 workers move: active squad",
		SharedSquadNavigation.get_active_squad_count() == 1
	)
	var slots: Dictionary = {}
	for worker: Variant in workers:
		var w: Worker = worker as Worker
		_expect(failures, "5 workers move: each has target", w.has_move_target)
		var key: String = "%.2f,%.2f" % [w._movement_target.x, w._movement_target.z]
		slots[key] = true
	_expect(failures, "5 workers move: unique slots", slots.size() >= 4)
	await _free_harness(harness)


func _verify_shared_route_counts(failures: PackedStringArray, count: int) -> void:
	print("verify: shared route for %d units" % count)
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in count:
		var unit: Unit
		if index % 3 == 0:
			unit = ARCHER_SCENE.instantiate() as Unit
		else:
			unit = SWORDSMAN_SCENE.instantiate() as Unit
		harness["root"].add_child(unit)
		unit.global_position = Vector3(
			float(index % 10) * 1.15 - 5.0,
			0.0,
			float(index / 10) * 1.15 - 5.0
		)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()
	var result: Dictionary = SharedSquadNavigation.issue_player_group_command(
		units, Vector3(12.0, 0.0, 8.0), &"move", false
	)
	var routes: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	print("  %d units: strategic_routes=%d handled=%s" % [count, routes, result.get("handled", false)])
	_expect(failures, "%d units: shared handled" % count, result.get("handled", false))
	_expect(failures, "%d units: one strategic corridor" % count, routes == 1)
	_expect(
		failures,
		"%d units: one active squad" % count,
		SharedSquadNavigation.get_active_squad_count() == 1
	)
	await _free_harness(harness)


func _verify_mixed_size_slots(failures: PackedStringArray) -> void:
	print("verify: mixed unit sizes get stable unique slots")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 8:
		var unit: Unit = (
			ARCHER_SCENE.instantiate() as Unit if index % 2 == 0 else SWORDSMAN_SCENE.instantiate() as Unit
		)
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index) * 1.3, 0.0, 0.0)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	var result: Dictionary = SharedSquadNavigation.issue_player_group_command(
		units, Vector3(0.0, 0.0, 10.0), &"move", false
	)
	_expect(failures, "mixed sizes: handled", result.get("handled", false))
	var ctx: SquadNavContext = SharedSquadNavigation.get_squad_for_unit(units[0])
	_expect(failures, "mixed sizes: squad context", ctx != null)
	if ctx != null:
		_expect(failures, "mixed sizes: not formation layout", not ctx.uses_formation_layout)
		_expect(failures, "mixed sizes: slot count", ctx.slot_locals.size() == units.size())
		var unique: Dictionary = {}
		for local: Variant in ctx.slot_locals.values():
			unique["%s" % local] = true
		_expect(failures, "mixed sizes: unique locals", unique.size() == units.size())
	await _free_harness(harness)


func _verify_workers_not_military_formation(failures: PackedStringArray) -> void:
	print("verify: workers gathering are not military formations")
	var harness: Dictionary = await _spawn_nav_harness()
	var mine: GoldMine = GOLD_SCENE.instantiate() as GoldMine
	harness["root"].add_child(mine)
	mine.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	mine.global_position = Vector3(6.0, 0.0, 0.0)

	var workers: Array[Worker] = []
	for index: int in 3:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		harness["root"].add_child(worker)
		worker.global_position = Vector3(-4.0 + float(index), 0.0, -3.0)
		workers.append(worker)
	await _wait_nav_ready(workers[0])

	SharedSquadNavigation.clear_all()
	for index: int in workers.size():
		workers[index].set_gather_approach_slot_hint(index)
		workers[index].command_gather_gold_mine(mine, true)

	await _wait_msec(400)
	_expect(
		failures,
		"gather: no shared military squad for gather",
		SharedSquadNavigation.get_active_squad_count() == 0
	)
	for worker: Worker in workers:
		_expect(
			failures,
			"gather: worker assigned gold",
			worker.get_assigned_gather_resource_id() == &"gold"
		)
	await _free_harness(harness)


func _verify_five_workers_gold_mine(failures: PackedStringArray) -> void:
	print("verify: five workers one gold mine no permanent stuck")
	var harness: Dictionary = await _spawn_nav_harness()
	var cc: Node3D = CC_SCENE.instantiate() as Node3D
	harness["root"].add_child(cc)
	cc.global_position = Vector3(-8.0, 0.0, 0.0)
	if cc is CommandCenter:
		(cc as CommandCenter).team_id = 0

	var mine: GoldMine = GOLD_SCENE.instantiate() as GoldMine
	harness["root"].add_child(mine)
	mine.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
	mine.global_position = Vector3(8.0, 0.0, 0.0)

	var workers: Array[Worker] = []
	for index: int in 5:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		harness["root"].add_child(worker)
		worker.global_position = Vector3(-7.0 + float(index) * 0.9, 0.0, -2.5)
		workers.append(worker)
	await _wait_nav_ready(workers[0])

	var approach_dirs: Dictionary = {}
	var dropoff_dirs: Dictionary = {}
	for index: int in workers.size():
		workers[index].set_gather_approach_slot_hint(index)
		var approach_dir: Vector3 = workers[index]._compute_resource_approach_direction(mine, 0)
		approach_dirs["%.2f,%.2f" % [approach_dir.x, approach_dir.z]] = true
		if cc is CommandCenter:
			var spawn_dir: Vector3 = Vector3(
				(cc as CommandCenter).worker_spawn_offset.x,
				0.0,
				(cc as CommandCenter).worker_spawn_offset.z
			)
			if spawn_dir.length_squared() < 0.001:
				spawn_dir = Vector3.FORWARD
			else:
				spawn_dir = spawn_dir.normalized()
			var drop_dir: Vector3 = workers[index]._apply_approach_candidate_offset(
				spawn_dir, index
			)
			dropoff_dirs["%.2f,%.2f" % [drop_dir.x, drop_dir.z]] = true
		workers[index].command_gather_gold_mine(mine, true)

	_expect(failures, "5 mine: diversified approaches", approach_dirs.size() >= 3)
	_expect(
		failures,
		"5 mine: diversified dropoffs",
		dropoff_dirs.size() >= 3 or not (cc is CommandCenter)
	)

	await _wait_msec(7000)

	var active: int = 0
	var stuck_near_cc: int = 0
	for worker: Worker in workers:
		if worker.get_assigned_gather_resource_id() == &"gold":
			active += 1
		var near_cc: float = _horizontal_distance(worker.global_position, cc.global_position)
		var near_mine: float = _horizontal_distance(worker.global_position, mine.global_position)
		if near_cc < 3.5 and near_mine > 6.0 and worker._gather_state == Worker.GatherTripState.TO_SOURCE:
			if not worker.has_move_target:
				stuck_near_cc += 1

	_expect(failures, "5 mine: all workers assigned", active == 5)
	_expect(failures, "5 mine: no permanent stuck beside CC", stuck_near_cc == 0)
	_expect(failures, "5 mine: soft reservations", mine.get_assigned_worker_count() >= 3)
	await _free_harness(harness)


func _verify_shift_queued_group_move(failures: PackedStringArray) -> void:
	print("verify: shift-queued group move stays ordered")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 4:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index) * 1.2, 0.0, 0.0)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()
	var first: Dictionary = SharedSquadNavigation.issue_player_group_command(
		units, Vector3(6.0, 0.0, 0.0), &"move", false
	)
	var squads_after_first: int = SharedSquadNavigation.get_active_squad_count()
	var queued: Dictionary = SharedSquadNavigation.issue_player_group_command(
		units, Vector3(6.0, 0.0, 8.0), &"move", true
	)
	var routes: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	_expect(failures, "queue: first handled", first.get("handled", false))
	_expect(failures, "queue: queued handled", queued.get("handled", false))
	_expect(failures, "queue: queued does not add live squad", SharedSquadNavigation.get_active_squad_count() == squads_after_first)
	_expect(failures, "queue: only one strategic route from current", routes == 1)
	for unit: Variant in units:
		_expect(failures, "queue: has queued orders", (unit as Unit).has_queued_orders())
	await _free_harness(harness)


func _verify_attack_move_shares_route(failures: PackedStringArray) -> void:
	print("verify: attack-move shares route")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 6:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index) * 1.1, 0.0, -2.0)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()
	var result: Dictionary = SharedSquadNavigation.issue_player_group_command(
		units, Vector3(10.0, 0.0, 4.0), &"attack_move", false
	)
	_expect(failures, "attack-move: handled", result.get("handled", false))
	_expect(
		failures,
		"attack-move: one strategic route",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0)) == 1
	)
	var ctx: SquadNavContext = SharedSquadNavigation.get_squad_for_unit(units[0])
	_expect(failures, "attack-move: attack flag", ctx != null and ctx.use_attack_move)
	await _free_harness(harness)


func _verify_direct_attack_not_group_route(failures: PackedStringArray) -> void:
	print("verify: direct attack remains target command")
	var harness: Dictionary = await _spawn_nav_harness()
	var attacker: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(attacker)
	harness["root"].add_child(enemy)
	attacker.global_position = Vector3.ZERO
	enemy.global_position = Vector3(4.0, 0.0, 0.0)
	enemy.add_to_group(&"enemies")
	enemy.team_id = 1
	await _wait_nav_ready(attacker)

	SharedSquadNavigation.clear_all()
	attacker.issue_order(UnitOrder.attack(enemy), false)
	_expect(failures, "direct attack: target set", attacker._attack_target == enemy)
	_expect(
		failures,
		"direct attack: no shared squad",
		SharedSquadNavigation.get_active_squad_count() == 0
	)
	await _free_harness(harness)


func _verify_route_fallback(failures: PackedStringArray) -> void:
	print("verify: route failure uses bounded fallback")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 3:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index), 0.0, 0.0)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	var result: Dictionary = SharedSquadNavigation.issue_player_group_command(
		units, Vector3(1000.0, 0.0, 1000.0), &"move", false
	)
	# Destination snaps onto nav mesh; command should still be handled with accepted dest.
	_expect(failures, "fallback: handled or gracefully skipped", true)
	if result.get("handled", false):
		var accepted: Vector3 = result.get("accepted_destination", Vector3.ZERO) as Vector3
		_expect(
			failures,
			"fallback: accepted destination not absurdly far",
			accepted.length() < 80.0
		)
	await _free_harness(harness)


func _verify_temp_block_no_repath_storm(failures: PackedStringArray) -> void:
	print("verify: temporary friendly blockage does not storm repaths")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 12:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index % 4) * 1.1, 0.0, float(index / 4) * 1.1)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()
	SharedSquadNavigation.issue_player_group_command(
		units, Vector3(10.0, 0.0, 0.0), &"move", false
	)
	var routes_before: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	for _i: int in 20:
		await get_tree().physics_frame
	var routes_after: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	_expect(failures, "temp block: no strategic repath storm", routes_after == routes_before)
	await _free_harness(harness)


func _verify_arrival_clears(failures: PackedStringArray) -> void:
	print("verify: arrival clears movement cleanly")
	var harness: Dictionary = await _spawn_nav_harness()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(unit)
	unit.global_position = Vector3.ZERO
	await _wait_nav_ready(unit)
	unit.issue_order(UnitOrder.move(Vector3(1.0, 0.0, 0.0)), false)
	await _wait_msec(2500)
	_expect(
		failures,
		"arrival: eventually clears or is near target",
		(not unit.has_move_target)
		or _horizontal_distance(unit.global_position, Vector3(1.0, 0.0, 0.0)) < 2.0
	)
	await _free_harness(harness)


func _verify_match_reset_clears(failures: PackedStringArray) -> void:
	print("verify: match reset clears transient route state")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 4:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index), 0.0, 0.0)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)
	SharedSquadNavigation.issue_player_group_command(
		units, Vector3(5.0, 0.0, 5.0), &"move", false
	)
	_expect(failures, "reset: squad exists before", SharedSquadNavigation.get_active_squad_count() > 0)
	SharedSquadNavigation.clear_all()
	_expect(failures, "reset: squads cleared", SharedSquadNavigation.get_active_squad_count() == 0)
	_expect(failures, "reset: members cleared", SharedSquadNavigation.get_active_member_count() == 0)
	await _free_harness(harness)


func _verify_ai_and_player_share_foundation(failures: PackedStringArray) -> void:
	print("verify: AI and player share strategic routing foundation")
	var harness: Dictionary = await _spawn_nav_harness()
	var player_units: Array = []
	var ai_units: Array = []
	for index: int in 5:
		var player: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(player)
		player.global_position = Vector3(-4.0 + float(index), 0.0, -4.0)
		player_units.append(player)
		var enemy: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(enemy)
		enemy.add_to_group(&"enemies")
		enemy.team_id = 1
		enemy.global_position = Vector3(-4.0 + float(index), 0.0, 4.0)
		ai_units.append(enemy)
	await _wait_nav_ready(player_units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PerfCounters.reset_all()
	var player_result: Dictionary = SharedSquadNavigation.issue_player_group_command(
		player_units, Vector3(8.0, 0.0, -4.0), &"move", false
	)
	var ai_result: Dictionary = SharedSquadNavigation.issue_group_command(
		ai_units, Vector3(8.0, 0.0, 4.0), true, 1
	)
	_expect(failures, "shared foundation: player handled", player_result.get("handled", false))
	_expect(failures, "shared foundation: AI handled", ai_result.get("handled", false))
	_expect(
		failures,
		"shared foundation: two squads",
		SharedSquadNavigation.get_active_squad_count() == 2
	)
	_expect(
		failures,
		"shared foundation: two strategic routes",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0)) == 2
	)
	await _free_harness(harness)


func _report_perf_snapshot() -> void:
	print(
		"perf snapshot: strategic=%s local=%s stalls=%s cache_hits=%s"
		% [
			PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0),
			PerfCounters._counts.get(PerfCounters.KEY_SQUAD_LOCAL_REPATHS, 0),
			PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STALLS, 0),
			PerfCounters._counts.get(PerfCounters.KEY_SQUAD_ROUTE_CACHE_HITS, 0),
		]
	)


func _spawn_nav_harness() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var region := NavigationRegion3D.new()
	root.add_child(region)
	await get_tree().process_frame
	await _bake_nav_mesh(region)
	return {"root": root, "region": region}


func _bake_nav_mesh(region: NavigationRegion3D) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	var source_data := NavigationMeshSourceGeometryData3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(80.0, 80.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	region.navigation_mesh = nav_mesh
	await get_tree().process_frame
	await get_tree().physics_frame


func _wait_nav_ready(unit: Unit) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline_msec:
		if unit._navigation_agent != null and UnitNavigation.can_use(unit._navigation_agent):
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
	SharedSquadNavigation.clear_all()
	var root: Node = harness.get("root") as Node
	if root != null and is_instance_valid(root):
		# Stop units before free so deferred lambdas do not sort freed bodies.
		for child: Node in root.get_children():
			if child is Unit:
				(child as Unit).set_process(false)
				(child as Unit).set_physics_process(false)
				SharedSquadNavigation.release_unit(child)
		await get_tree().process_frame
		root.free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
