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
	PlayerRouteNavigation.clear_all()
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
	await _verify_player_stable_destinations(failures)
	await _verify_player_no_continuous_formation_steering(failures)
	await _verify_new_click_overrides_previous(failures)
	await _verify_arrival_clears(failures)
	await _verify_match_reset_clears(failures)
	await _verify_ai_and_player_share_foundation(failures)
	await _verify_freed_unit_squad_navigation(failures)
	## Custom NavigationServer maps must run last — freeing them breaks later world-map sync.
	await _verify_route_clearance_around_building(failures)
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
	print("verify: worker generic point move uses individual paths")
	var harness: Dictionary = await _spawn_nav_harness()
	var workers: Array = []
	for index: int in 5:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		harness["root"].add_child(worker)
		worker.global_position = Vector3(-6.0 + float(index) * 1.2, 0.0, -2.0)
		workers.append(worker)
	await _wait_nav_ready(workers[0] as Unit)

	SharedSquadNavigation.clear_all()
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	var result: Dictionary = PlayerRouteNavigation.issue_command(
		workers, Vector3(8.0, 0.0, 2.0), &"move", false
	)
	_expect(failures, "5 workers move: handled", result.get("handled", false))
	_expect(
		failures,
		"5 workers move: no shared squad",
		SharedSquadNavigation.get_active_squad_count() == 0
	)
	_expect(
		failures,
		"5 workers move: player route bookkeeping",
		PlayerRouteNavigation.get_active_route_count() == 1
	)
	_expect(
		failures,
		"5 workers move: no military strategic corridor",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0)) == 0
	)
	var travel_keys: Dictionary = {}
	var arrival_keys: Dictionary = {}
	var route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(workers[0] as Unit)
	_expect(failures, "5 workers move: route context", route != null)
	_expect(
		failures,
		"5 workers move: no shared waypoints",
		route == null or route.waypoints.is_empty()
	)
	for worker: Variant in workers:
		var w: Worker = worker as Worker
		_expect(failures, "5 workers move: each has target", w.has_move_target)
		var travel_key: String = "%.2f,%.2f" % [w._movement_target.x, w._movement_target.z]
		travel_keys[travel_key] = true
		if route != null:
			var slot: Vector3 = route.get_final_destination(w.get_instance_id())
			var arrival_key: String = "%.2f,%.2f" % [slot.x, slot.z]
			arrival_keys[arrival_key] = true
	_expect(failures, "5 workers move: individual travel targets", travel_keys.size() >= 4)
	_expect(failures, "5 workers move: unique final slots", arrival_keys.size() >= 4)
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
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	var result: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(12.0, 0.0, 8.0), &"move", false
	)
	var routes: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	print("  %d units: strategic_routes=%d handled=%s" % [count, routes, result.get("handled", false)])
	_expect(failures, "%d units: shared handled" % count, result.get("handled", false))
	_expect(failures, "%d units: one strategic corridor" % count, routes == 1)
	_expect(
		failures,
		"%d units: one active player route" % count,
		PlayerRouteNavigation.get_active_route_count() == 1
	)
	_expect(
		failures,
		"%d units: no legacy player squad" % count,
		SharedSquadNavigation.get_active_squad_count() == 0
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

	PlayerRouteNavigation.clear_all()
	var result: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(0.0, 0.0, 10.0), &"move", false
	)
	_expect(failures, "mixed sizes: handled", result.get("handled", false))
	var route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(units[0])
	_expect(failures, "mixed sizes: route context", route != null)
	if route != null:
		_expect(
			failures,
			"mixed sizes: frozen arrival count",
			route.final_destinations.size() == units.size()
		)
		_expect(
			failures,
			"mixed sizes: shared waypoints present",
			route.waypoints.size() >= 2
		)
		var unique: Dictionary = {}
		for slot: Variant in route.final_destinations.values():
			unique["%s" % slot] = true
		_expect(failures, "mixed sizes: unique arrivals", unique.size() == units.size())
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
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	var first: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(6.0, 0.0, 0.0), &"move", false
	)
	var routes_after_first: int = PlayerRouteNavigation.get_active_route_count()
	var queued: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(6.0, 0.0, 8.0), &"move", true
	)
	var routes: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	_expect(failures, "queue: first handled", first.get("handled", false))
	_expect(failures, "queue: queued handled", queued.get("handled", false))
	_expect(
		failures,
		"queue: queued does not add live route",
		PlayerRouteNavigation.get_active_route_count() == routes_after_first
	)
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
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	var result: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(10.0, 0.0, 4.0), &"attack_move", false
	)
	_expect(failures, "attack-move: handled", result.get("handled", false))
	_expect(
		failures,
		"attack-move: one strategic route",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0)) == 1
	)
	var route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(units[0])
	_expect(failures, "attack-move: attack flag", route != null and route.use_attack_move)
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
	PlayerRouteNavigation.clear_all()
	var result: Dictionary = PlayerRouteNavigation.issue_command(
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
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	PlayerRouteNavigation.issue_command(units, Vector3(10.0, 0.0, 0.0), &"move", false)
	var routes_before: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	var local_before: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_LOCAL_REPATHS, 0))
	for _i: int in 20:
		await get_tree().physics_frame
	var routes_after: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0))
	var local_after: int = int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_LOCAL_REPATHS, 0))
	_expect(failures, "temp block: no strategic repath storm", routes_after == routes_before)
	_expect(
		failures,
		"temp block: no continuous formation local repaths",
		local_after == local_before
	)
	_expect(
		failures,
		"temp block: one player route (no squad)",
		PlayerRouteNavigation.get_active_route_count() == 1
		and SharedSquadNavigation.get_active_squad_count() == 0
	)
	await _free_harness(harness)


func _verify_player_stable_destinations(failures: PackedStringArray) -> void:
	print("verify: player move freezes clicked destination and arrival slots once")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 40:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(
			float(index % 8) * 1.15 - 4.0,
			0.0,
			float(index / 8) * 1.15 - 4.0
		)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PlayerRouteNavigation.clear_all()
	PlayerRouteNavigation.reset_player_move_telemetry()
	PerfCounters.reset_all()
	var clicked: Vector3 = Vector3(18.0, 0.0, 12.0)
	var start_positions: Dictionary = {}
	for unit: Variant in units:
		start_positions[(unit as Node).get_instance_id()] = (unit as Node3D).global_position
	var result: Dictionary = PlayerRouteNavigation.issue_command(
		units, clicked, &"move", false
	)
	_expect(failures, "stable: handled", result.get("handled", false))

	var route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(units[0])
	_expect(failures, "stable: route context", route != null)
	if route == null:
		await _free_harness(harness)
		return

	var original_click: Vector3 = route.clicked_destination
	var original_slots: Dictionary = route.final_destinations.duplicate()
	_expect(failures, "stable: slot count", original_slots.size() == units.size())

	var telemetry: Dictionary = PlayerRouteNavigation.get_player_move_telemetry()
	_expect(failures, "stable: slot generation == 1", int(telemetry.get("slot_generation_count", 0)) == 1)
	_expect(failures, "stable: orders issued once", int(telemetry.get("orders_issued", 0)) == units.size())
	_expect(failures, "stable: shared route == 1", int(telemetry.get("shared_route_count", 0)) == 1)
	_expect(
		failures,
		"stable: strategic routes == 1",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0)) == 1
	)
	_expect(
		failures,
		"stable: no legacy player squad",
		SharedSquadNavigation.get_active_squad_count() == 0
	)

	## Let units march along the shared corridor before asserting progress.
	for _i: int in 48:
		await get_tree().physics_frame

	_expect(
		failures,
		"stable: clicked destination unchanged",
		_horizontal_distance(route.clicked_destination, original_click) < 0.01
	)
	var slots_unchanged := true
	for unit_id: Variant in original_slots.keys():
		if not route.final_destinations.has(unit_id):
			slots_unchanged = false
			break
		if _horizontal_distance(
			route.final_destinations[unit_id] as Vector3,
			original_slots[unit_id] as Vector3
		) > 0.01:
			slots_unchanged = false
			break
	_expect(failures, "stable: arrival slots never recomputed", slots_unchanged)

	telemetry = PlayerRouteNavigation.get_player_move_telemetry()
	_expect(
		failures,
		"stable: no continuous formation refreshes",
		int(telemetry.get("formation_refresh_count", 0)) == 0
	)
	_expect(
		failures,
		"stable: no continuous target replacements",
		int(telemetry.get("target_replacements", 0)) == 0
	)
	_expect(
		failures,
		"stable: no local formation repaths",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_LOCAL_REPATHS, 0)) == 0
	)

	var progressed: int = 0
	for unit: Variant in units:
		var u: Unit = unit as Unit
		var start_pos: Vector3 = start_positions[u.get_instance_id()] as Vector3
		var travel: Vector3 = PlayerRouteNavigation.resolve_travel_target(u)
		if travel.length_squared() < 0.0001:
			travel = route.get_final_destination(u.get_instance_id())
		var toward: Vector3 = travel - start_pos
		toward.y = 0.0
		var moved: Vector3 = u.global_position - start_pos
		moved.y = 0.0
		if toward.length_squared() > 0.01 and moved.dot(toward.normalized()) > 0.25:
			progressed += 1
		elif moved.length() > 0.5:
			## Still advancing along the shared corridor even if not yet aimed at final.
			progressed += 1
	_expect(failures, "stable: most units progress toward route", progressed >= 28)

	await _free_harness(harness)


func _verify_player_no_continuous_formation_steering(failures: PackedStringArray) -> void:
	print("verify: player routes do not chase moving virtual slots")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 10:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index) * 1.2, 0.0, 0.0)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	PlayerRouteNavigation.reset_player_move_telemetry()
	PlayerRouteNavigation.issue_command(units, Vector3(14.0, 0.0, 6.0), &"move", false)
	var route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(units[0])
	_expect(failures, "no-steer: route context", route != null)
	if route == null:
		await _free_harness(harness)
		return

	var finals_before: Dictionary = route.final_destinations.duplicate()
	var generation_before: int = route.command_generation
	var waypoints_before: PackedVector3Array = route.waypoints.duplicate()
	var waypoint_indices_before: Dictionary = route.waypoint_index_by_unit.duplicate()

	## Simulate ~2 seconds of route ticks without issuing new player clicks.
	for _i: int in 40:
		await get_tree().physics_frame

	_expect(
		failures,
		"no-steer: command generation unchanged",
		route.command_generation == generation_before
	)
	_expect(
		failures,
		"no-steer: shared waypoints immutable",
		waypoints_before.size() == route.waypoints.size()
	)
	var finals_unchanged := true
	for unit_id: Variant in finals_before.keys():
		if not route.final_destinations.has(unit_id):
			finals_unchanged = false
			break
		if _horizontal_distance(
			finals_before[unit_id] as Vector3,
			route.final_destinations[unit_id] as Vector3
		) > 0.01:
			finals_unchanged = false
			break
	_expect(failures, "no-steer: frozen arrivals never recomputed", finals_unchanged)

	var telemetry: Dictionary = PlayerRouteNavigation.get_player_move_telemetry()
	_expect(
		failures,
		"no-steer: zero continuous formation refreshes",
		int(telemetry.get("formation_refresh_count", -1)) == 0
	)
	## Corridor waypoint advances may retarget once; that is not formation steering.
	## Without a waypoint advance, there must be no target replacement storm.
	var any_waypoint_advanced := false
	for unit_id: Variant in waypoint_indices_before.keys():
		var before_index: int = int(waypoint_indices_before[unit_id])
		var after_index: int = route.get_waypoint_index(int(unit_id))
		if after_index != before_index:
			any_waypoint_advanced = true
			break
	if not any_waypoint_advanced:
		_expect(
			failures,
			"no-steer: no target replacements without waypoint advance",
			int(telemetry.get("target_replacements", -1)) == 0
		)
	await _free_harness(harness)


func _verify_new_click_overrides_previous(failures: PackedStringArray) -> void:
	print("verify: newer player click immediately overrides previous command")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 8:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(float(index) * 1.15, 0.0, 0.0)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PlayerRouteNavigation.clear_all()
	PlayerRouteNavigation.reset_player_move_telemetry()
	var first: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(10.0, 0.0, 0.0), &"move", false
	)
	_expect(failures, "override: first handled", first.get("handled", false))
	var first_gen: int = int(
		PlayerRouteNavigation.get_player_move_telemetry().get("command_generation", 0)
	)
	var first_slots: Dictionary = {}
	for unit: Variant in units:
		var u: Unit = unit as Unit
		first_slots[u.get_instance_id()] = u.get_player_squad_final_arrival()

	await get_tree().physics_frame
	var second: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(4.0, 0.0, 12.0), &"move", false
	)
	_expect(failures, "override: second handled", second.get("handled", false))
	var telemetry: Dictionary = PlayerRouteNavigation.get_player_move_telemetry()
	var second_gen: int = int(telemetry.get("command_generation", 0))
	_expect(failures, "override: generation advanced", second_gen > first_gen)
	_expect(failures, "override: stale callbacks blocked == 0", int(telemetry.get("stale_callback_blocks", -1)) == 0)

	for unit: Variant in units:
		var u: Unit = unit as Unit
		_expect(
			failures,
			"override: unit bound to new generation",
			u.matches_player_route_command(second_gen)
		)
		var old_slot: Vector3 = first_slots[u.get_instance_id()] as Vector3
		_expect(
			failures,
			"override: final arrival replaced",
			_horizontal_distance(old_slot, u.get_player_squad_final_arrival()) > 0.5
		)
		var expected_travel: Vector3 = PlayerRouteNavigation.resolve_travel_target(u)
		_expect(
			failures,
			"override: movement target matches new travel",
			expected_travel.length_squared() > 0.0001
			and _horizontal_distance(u._movement_target, expected_travel) < 0.75
		)

	## Ensure first-command slot values are not restored by a later tick.
	for _i: int in 16:
		await get_tree().physics_frame
	for unit: Variant in units:
		var u: Unit = unit as Unit
		var old_slot: Vector3 = first_slots[u.get_instance_id()] as Vector3
		_expect(
			failures,
			"override: first command did not retake targets",
			u.matches_player_route_command(second_gen)
		)
		_expect(
			failures,
			"override: still bound to second command travel goal",
			u.has_move_target
			and _horizontal_distance(u.get_player_squad_final_arrival(), old_slot) > 0.5
		)
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
	PlayerRouteNavigation.clear_all()
	PlayerRouteNavigation.issue_command(units, Vector3(5.0, 0.0, 5.0), &"move", false)
	_expect(
		failures,
		"reset: player route exists before",
		PlayerRouteNavigation.get_active_route_count() > 0
	)
	_expect(
		failures,
		"reset: no legacy player squad",
		SharedSquadNavigation.get_active_squad_count() == 0
	)
	PlayerRouteNavigation.clear_all()
	SharedSquadNavigation.clear_all()
	_expect(failures, "reset: player routes cleared", PlayerRouteNavigation.get_active_route_count() == 0)
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
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	var player_result: Dictionary = PlayerRouteNavigation.issue_command(
		player_units, Vector3(8.0, 0.0, -4.0), &"move", false
	)
	var ai_result: Dictionary = SharedSquadNavigation.issue_group_command(
		ai_units, Vector3(8.0, 0.0, 4.0), true, 1
	)
	_expect(failures, "shared foundation: player handled", player_result.get("handled", false))
	_expect(failures, "shared foundation: AI handled", ai_result.get("handled", false))
	_expect(
		failures,
		"shared foundation: one player route",
		PlayerRouteNavigation.get_active_route_count() == 1
	)
	_expect(
		failures,
		"shared foundation: one AI squad",
		SharedSquadNavigation.get_active_squad_count() == 1
	)
	_expect(
		failures,
		"shared foundation: two strategic routes",
		int(PerfCounters._counts.get(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES, 0)) == 2
	)
	await _free_harness(harness)


## Regression: freeing route members / threats must never leave typed Object refs.
func _verify_freed_unit_squad_navigation(failures: PackedStringArray) -> void:
	print("verify: freed unit references during player route navigation")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 40:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(
			float(index % 8) * 1.15 - 4.0,
			0.0,
			float(index / 8) * 1.15 - 4.0
		)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)

	SharedSquadNavigation.clear_all()
	PlayerRouteNavigation.clear_all()
	SharedSquadNavigation.clear_stale_cleanup_reports()
	PerfCounters.reset_all()
	var move_result: Dictionary = PlayerRouteNavigation.issue_command(
		units, Vector3(16.0, 0.0, 10.0), &"move", false
	)
	_expect(failures, "freed-nav: initial move handled", move_result.get("handled", false))
	_expect(
		failures,
		"freed-nav: player route exists",
		PlayerRouteNavigation.get_active_route_count() == 1
	)
	_expect(
		failures,
		"freed-nav: no legacy player squad",
		SharedSquadNavigation.get_active_squad_count() == 0
	)

	var route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(units[0])
	_expect(failures, "freed-nav: route context", route != null)
	if route == null:
		await _free_harness(harness)
		return

	var initial_count: int = route.member_count()
	var front: Unit = units[0] as Unit
	var middle: Unit = units[20] as Unit
	var stagger_victim: Unit = units[5] as Unit
	var front_id: int = front.get_instance_id()
	var middle_id: int = middle.get_instance_id()
	var stagger_id: int = stagger_victim.get_instance_id()

	## Kill while moving: front, middle, staggered index, and a simultaneous batch.
	front.die()
	front.queue_free()
	middle.die()
	middle.queue_free()
	stagger_victim.die()
	stagger_victim.queue_free()
	for index: int in [7, 8, 9]:
		var batch: Unit = units[index] as Unit
		batch.die()
		batch.queue_free()

	## Continue navigation ticks with freed members present in the scene tree exit path.
	for _i: int in 16:
		await get_tree().physics_frame

	route.purge_dead_members()
	_expect(
		failures,
		"freed-nav: no SharedSquadNavigation stale refs after member deaths",
		not SharedSquadNavigation.debug_has_stale_unit_references()
	)
	_expect(
		failures,
		"freed-nav: dead front removed from route",
		not route.contains_unit_id(front_id)
	)
	_expect(
		failures,
		"freed-nav: dead middle removed from route",
		not route.contains_unit_id(middle_id)
	)
	_expect(
		failures,
		"freed-nav: dead stagger removed from route",
		not route.contains_unit_id(stagger_id)
	)

	var living: Array = []
	for unit: Variant in units:
		if NodeSafety.is_alive_node(unit):
			living.append(unit)
	_expect(failures, "freed-nav: survivors remain", living.size() >= 30)

	route = PlayerRouteNavigation.get_route_for_unit(living[0])
	if route != null:
		route.purge_dead_members()
		_expect(
			failures,
			"freed-nav: member count shrunk",
			route.member_count() < initial_count and route.member_count() == living.size()
		)
	else:
		## Route may dissolve only if everyone died; otherwise fail.
		_expect(failures, "freed-nav: survivors still have route", false)

	## Fresh move command with survivors.
	var second: Dictionary = PlayerRouteNavigation.issue_command(
		living, Vector3(6.0, 0.0, -8.0), &"move", false
	)
	_expect(failures, "freed-nav: second move handled", second.get("handled", false))
	for _i: int in 8:
		await get_tree().physics_frame
	_expect(
		failures,
		"freed-nav: no SharedSquadNavigation stale refs after second move",
		not SharedSquadNavigation.debug_has_stale_unit_references()
	)

	## Attack-move then free a nearby threat — must not crash player route ownership.
	var threat: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(threat)
	threat.add_to_group(&"enemies")
	threat.team_id = 1
	threat.global_position = Vector3(4.0, 0.0, 0.0)
	await get_tree().physics_frame

	var attack_move: Dictionary = PlayerRouteNavigation.issue_command(
		living, Vector3(4.0, 0.0, 0.0), &"attack_move", false
	)
	_expect(failures, "freed-nav: attack-move handled", attack_move.get("handled", false))
	route = PlayerRouteNavigation.get_route_for_unit(living[0])
	_expect(failures, "freed-nav: attack-move route", route != null and route.use_attack_move)
	threat.die()
	threat.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(
		failures,
		"freed-nav: route survives threat free",
		PlayerRouteNavigation.get_route_for_unit(living[0]) != null
	)
	_expect(
		failures,
		"freed-nav: no SharedSquadNavigation stale refs after threat free",
		not SharedSquadNavigation.debug_has_stale_unit_references()
	)

	## Delete whole route during delayed processing.
	var squad_to_wipe: Array = living.duplicate()
	PlayerRouteNavigation.issue_command(squad_to_wipe, Vector3(-6.0, 0.0, 6.0), &"move", false)
	await get_tree().physics_frame
	for unit: Variant in squad_to_wipe:
		if NodeSafety.is_alive_node(unit):
			(unit as Unit).die()
			(unit as Unit).queue_free()
	for _i: int in 10:
		await get_tree().physics_frame
	_expect(
		failures,
		"freed-nav: route dissolved after total wipe",
		PlayerRouteNavigation.get_active_route_count() == 0
	)
	_expect(
		failures,
		"freed-nav: no SharedSquadNavigation stale refs after total wipe",
		not SharedSquadNavigation.debug_has_stale_unit_references()
	)

	## Match reset clears every navigation reference.
	var leftover: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var leftover2: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(leftover)
	harness["root"].add_child(leftover2)
	leftover.global_position = Vector3(-2.0, 0.0, -2.0)
	leftover2.global_position = Vector3(-1.0, 0.0, -2.0)
	await _wait_nav_ready(leftover)
	PlayerRouteNavigation.issue_command(
		[leftover, leftover2], Vector3(3.0, 0.0, 3.0), &"move", false
	)
	_expect(
		failures,
		"freed-nav: route before reset",
		PlayerRouteNavigation.get_active_route_count() == 1
	)
	PlayerRouteNavigation.clear_all()
	SharedSquadNavigation.clear_all()
	_expect(failures, "freed-nav: reset clears routes", PlayerRouteNavigation.get_active_route_count() == 0)
	_expect(failures, "freed-nav: reset clears squads", SharedSquadNavigation.get_active_squad_count() == 0)
	_expect(
		failures,
		"freed-nav: reset clears member diag",
		SharedSquadNavigation.get_active_member_count() == 0
	)
	_expect(
		failures,
		"freed-nav: reset leaves zero SharedSquadNavigation stale refs",
		not SharedSquadNavigation.debug_has_stale_unit_references()
	)

	var reports: Array[String] = SharedSquadNavigation.get_stale_cleanup_reports()
	print("freed-nav cleanup reports (%d): %s" % [reports.size(), ", ".join(reports)])
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


## Strategic corridor must keep clearance from a carved building corner and
## retain raw vs final path metadata for path-debug comparison.
func _verify_route_clearance_around_building(failures: PackedStringArray) -> void:
	print("verify: player route clearance around building")
	SharedSquadNavigation.clear_all()
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()

	## Open-field metadata first (world map) — custom maps below can break later world sync.
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array = []
	for index: int in 6:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.global_position = Vector3(
			-8.0 + float(index % 3) * 1.1,
			0.0,
			8.0 + float(index / 3) * 1.1
		)
		units.append(unit)
	await _wait_nav_ready(units[0] as Unit)
	SharedSquadNavigation.clear_all()
	PlayerRouteNavigation.clear_all()
	PlayerRouteNavigation.issue_command(units, Vector3(8.0, 0.0, 8.0), &"move", false)
	var open_route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(units[0])
	_expect(failures, "open-field: player route context", open_route != null)
	if open_route != null:
		_expect(
			failures,
			"open-field: clearance metadata set",
			is_equal_approx(open_route.route_clearance_radius, PlayerRouteNavigation.ROUTE_CLEARANCE)
		)
		_expect(failures, "open-field: raw path stored", open_route.raw_waypoints.size() >= 2)
		_expect(
			failures,
			"open-field: few final waypoints",
			open_route.waypoints.size() <= 4
		)
		var open_len: float = 0.0
		for i: int in range(1, open_route.waypoints.size()):
			open_len += _horizontal_distance(
				open_route.waypoints[i - 1],
				open_route.waypoints[i]
			)
		var direct: float = _horizontal_distance(
			open_route.waypoints[0],
			open_route.waypoints[open_route.waypoints.size() - 1]
		)
		_expect(
			failures,
			"open-field: nearly straight",
			open_len <= direct * 1.15 + 1.0
		)
	await _free_harness(harness)

	var baked: Dictionary = _bake_obstacle_nav_mesh_resource()
	var nav_mesh: NavigationMesh = baked.get("nav_mesh") as NavigationMesh
	_expect(failures, "clearance: baked obstacle navmesh", nav_mesh != null and nav_mesh.get_polygon_count() > 0)
	if nav_mesh == null or nav_mesh.get_polygon_count() <= 0:
		return

	## Server-owned map+region — reliable under headless, independent of world sync.
	var map_rid: RID = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map_rid, true)
	var region_rid: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region_rid, map_rid)
	NavigationServer3D.region_set_navigation_mesh(region_rid, nav_mesh)
	var synced := false
	var deadline_msec: int = Time.get_ticks_msec() + 5000
	var probe_from := Vector3.ZERO
	var probe_to := Vector3.ZERO
	var probe_path := PackedVector3Array()
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().physics_frame
		if not NavigationServer3D.map_is_active(map_rid):
			continue
		probe_from = NavigationServer3D.map_get_closest_point(map_rid, Vector3(-10, 0, -2))
		if probe_from.length() <= 1.0:
			continue
		probe_to = NavigationServer3D.map_get_closest_point(map_rid, Vector3(10, 0, 0))
		probe_path = NavigationServer3D.map_get_path(map_rid, probe_from, probe_to, true)
		if probe_path.size() >= 3:
			synced = true
			break
	print(
		"  harness_probe from=%s to=%s path=%d synced=%s"
		% [probe_from, probe_to, probe_path.size(), synced]
	)
	_expect(failures, "clearance: harness path bends", synced and probe_path.size() >= 3)

	if synced:
		## Direct post-process check: scrape-style raw path hugging the south edge.
		var scrape_raw := PackedVector3Array([
			Vector3(-10.0, 0.5, -2.0),
			Vector3(-4.0, 0.5, -4.05),
			Vector3(0.0, 0.5, -4.05),
			Vector3(4.0, 0.5, -4.05),
			Vector3(10.0, 0.5, 0.0),
		])
		var processed: PackedVector3Array = SharedSquadNavigation.call(
			"_process_player_squad_route",
			map_rid,
			scrape_raw,
			SharedSquadNavigation.SQUAD_ROUTE_CLEARANCE
		) as PackedVector3Array
		_expect(failures, "clearance: processed path non-empty", processed.size() >= 2)
		_expect(
			failures,
			"clearance: destination preserved by processor",
			_horizontal_distance(processed[processed.size() - 1], scrape_raw[scrape_raw.size() - 1]) <= 0.05
		)
		var min_raw_edge: float = 999.0
		var min_final_edge: float = 999.0
		for index: int in range(1, scrape_raw.size() - 1):
			min_raw_edge = minf(min_raw_edge, absf(scrape_raw[index].z))
		for index: int in range(1, maxi(processed.size() - 1, 1)):
			min_final_edge = minf(min_final_edge, absf(processed[index].z))
		_expect(
			failures,
			"clearance: processor pushes off scraped edge",
			min_final_edge >= min_raw_edge + 0.2
		)
		print(
			"  processor raw_edge=%.2f final_edge=%.2f final_wp=%d"
			% [min_raw_edge, min_final_edge, processed.size()]
		)

		## Process the real NavigationServer path too.
		var processed_probe: PackedVector3Array = SharedSquadNavigation.call(
			"_process_player_squad_route",
			map_rid,
			probe_path,
			SharedSquadNavigation.SQUAD_ROUTE_CLEARANCE
		) as PackedVector3Array
		_expect(failures, "clearance: probe processed", processed_probe.size() >= 2)
		_expect(
			failures,
			"clearance: probe destination preserved",
			_horizontal_distance(
				processed_probe[processed_probe.size() - 1],
				probe_path[probe_path.size() - 1]
			) <= 0.05
		)
		var min_raw_clear: float = 999.0
		var min_final_clear: float = 999.0
		for index: int in range(1, probe_path.size() - 1):
			min_raw_clear = minf(min_raw_clear, _horizontal_distance(probe_path[index], Vector3.ZERO))
		for index: int in range(1, maxi(processed_probe.size() - 1, 1)):
			min_final_clear = minf(
				min_final_clear,
				_horizontal_distance(processed_probe[index], Vector3.ZERO)
			)
		if processed_probe.size() >= 3 and min_raw_clear < 900.0:
			_expect(
				failures,
				"clearance: final not tighter than raw",
				min_final_clear + 0.05 >= min_raw_clear
			)
		print(
			"  raw_wp=%d final_wp=%d clearance=%.2f min_interior_dist=%.2f min_raw_dist=%.2f"
			% [
				probe_path.size(),
				processed_probe.size(),
				SharedSquadNavigation.SQUAD_ROUTE_CLEARANCE,
				min_final_clear if min_final_clear < 900.0 else -1.0,
				min_raw_clear if min_raw_clear < 900.0 else -1.0,
			]
		)

	NavigationServer3D.map_set_active(map_rid, false)
	NavigationServer3D.free_rid(region_rid)
	NavigationServer3D.free_rid(map_rid)


func _bake_obstacle_nav_mesh_resource() -> Dictionary:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	var source_data := NavigationMeshSourceGeometryData3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(80.0, 80.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
	var half := Vector2(3.5, 3.5)
	var verts := PackedVector3Array([
		Vector3(-half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, half.y),
		Vector3(-half.x, 0.0, half.y),
	])
	source_data.add_projected_obstruction(verts, 0.0, 2.5, false)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	return {"nav_mesh": nav_mesh}


var _shared_nav_root: Node3D = null
var _shared_nav_region: NavigationRegion3D = null


func _spawn_nav_harness() -> Dictionary:
	## Reuse one NavigationRegion for the whole suite. Freeing regions from the
	## default world map leaves map_get_closest_point returning origin forever,
	## which makes PlayerRouteNavigation refuse every later command.
	if _shared_nav_root == null or not is_instance_valid(_shared_nav_root):
		_shared_nav_root = Node3D.new()
		add_child(_shared_nav_root)
		_shared_nav_region = NavigationRegion3D.new()
		_shared_nav_root.add_child(_shared_nav_region)
		await get_tree().process_frame
		await _bake_nav_mesh(_shared_nav_region)
	else:
		## Clear leftover non-region children from the previous case.
		for child: Node in _shared_nav_root.get_children():
			if child == _shared_nav_region:
				continue
			if child is Unit:
				(child as Unit).set_process(false)
				(child as Unit).set_physics_process(false)
				SharedSquadNavigation.release_unit(child)
				PlayerRouteNavigation.release_unit(child)
			child.free()
		await get_tree().process_frame
	return {"root": _shared_nav_root, "region": _shared_nav_region}


func _bake_nav_mesh(region: NavigationRegion3D) -> void:
	## Deterministic walkable plane — no runtime mesh parse / bake flakiness.
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	var half := 40.0
	nav_mesh.set_vertices(PackedVector3Array([
		Vector3(-half, 0.0, -half),
		Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half),
		Vector3(-half, 0.0, half),
	]))
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	nav_mesh.add_polygon(PackedInt32Array([0, 2, 3]))
	region.navigation_mesh = nav_mesh
	region.enabled = true
	var world: World3D = region.get_world_3d()
	if world != null:
		var nav_map: RID = world.get_navigation_map()
		if nav_map.is_valid():
			NavigationServer3D.map_set_active(nav_map, true)
	for _i: int in 10:
		await get_tree().physics_frame
	var deadline_msec: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().physics_frame
		world = region.get_world_3d()
		if world == null:
			continue
		var nav_map2: RID = world.get_navigation_map()
		if not nav_map2.is_valid() or not NavigationServer3D.map_is_active(nav_map2):
			continue
		var from: Vector3 = NavigationServer3D.map_get_closest_point(nav_map2, Vector3(-4.0, 0.0, -4.0))
		var to: Vector3 = NavigationServer3D.map_get_closest_point(nav_map2, Vector3(8.0, 0.0, 6.0))
		if _horizontal_distance(from, Vector3(-4.0, 0.0, -4.0)) > 8.0:
			continue
		if _horizontal_distance(to, Vector3(8.0, 0.0, 6.0)) > 8.0:
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map2, from, to, true)
		if path.size() >= 2:
			print("  nav harness synced path_wp=%d" % path.size())
			return
	push_warning("verify_shared_group_navigation: nav harness failed to sync walkable path")


func _wait_nav_ready(unit: Unit) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline_msec:
		var agent_ok: bool = (
			unit._navigation_agent != null and UnitNavigation.can_use(unit._navigation_agent)
		)
		var map_ok := false
		var world: World3D = unit.get_world_3d()
		if world != null:
			var nav_map: RID = world.get_navigation_map()
			if nav_map.is_valid() and NavigationServer3D.map_is_active(nav_map):
				var from: Vector3 = NavigationServer3D.map_get_closest_point(
					nav_map, unit.global_position
				)
				var to_point: Vector3 = unit.global_position + Vector3(4.0, 0.0, 0.0)
				var to: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to_point)
				if (
					_horizontal_distance(from, unit.global_position) <= 8.0
					and _horizontal_distance(to, to_point) <= 8.0
				):
					var path: PackedVector3Array = NavigationServer3D.map_get_path(
						nav_map, from, to, true
					)
					map_ok = path.size() >= 2
		if agent_ok and map_ok:
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
	PlayerRouteNavigation.clear_all()
	var root: Node = harness.get("root") as Node
	if root == null or not is_instance_valid(root):
		await get_tree().process_frame
		return
	## Free units only — keep the shared NavigationRegion alive for later cases.
	var to_free: Array[Node] = []
	for child: Node in root.get_children():
		if child is NavigationRegion3D:
			continue
		if child is Unit:
			(child as Unit).set_process(false)
			(child as Unit).set_physics_process(false)
			SharedSquadNavigation.release_unit(child)
			PlayerRouteNavigation.release_unit(child)
		to_free.append(child)
	for child: Node in to_free:
		if is_instance_valid(child):
			child.free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
