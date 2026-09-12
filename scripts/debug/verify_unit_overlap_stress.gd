extends Node

## Deterministic overlap/clump movement stress harness (Tests Aâ€“E).
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_unit_overlap_stress.tscn
##
## Reports physics/script ms + PerfCounters rates. Rendered FPS is NEEDS MANUAL TEST.

const REPORT_PATH := "user://unit_overlap_stress_result.txt"
const UNIT_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const GOLD_SCENE: PackedScene = preload("res://scenes/resources/gold_mine.tscn")
const WARMUP_MSEC := 800
const SAMPLE_MSEC := 2200
const TAG := "OVERLAP_STRESS"


func _ready() -> void:
	print("%s: start" % TAG)
	PlayerRouteNavigation.clear_all()
	CombatTargetValidation.reset_match_state()
	PerfCounters.reset_all()
	await get_tree().process_frame

	var results: Array[Dictionary] = []
	results.append(await _run_test_a())
	results.append(await _run_test_b())
	results.append(await _run_test_c())
	results.append(await _run_test_d())
	results.append(await _run_test_e())
	results.append(await _run_test_f())
	results.append(await _run_test_g_40_workers())
	results.append(await _run_test_h_60_standing())
	results.append(await _run_test_i_60_moving())
	results.append(await _run_test_j_30v30())
	results.append(await _run_test_k_five_gold())
	results.append(await _run_test_l_overlay_off())
	results.append(await _run_test_m_overlay_on())

	var report := _format_report(results)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	print(report)
	print("PASS unit_overlap_stress")
	await get_tree().process_frame
	get_tree().quit(0)


func _run_test_a() -> Dictionary:
	## 100 units standing separated.
	return await _measure_scenario(
		"A_100_separated_idle",
		100,
		false,
		false,
		Vector3(40.0, 0.0, 0.0),
		2.4
	)


func _run_test_b() -> Dictionary:
	## 100 units moving same direction with spacing (little overlap).
	return await _measure_scenario(
		"B_100_moving_spaced",
		100,
		true,
		false,
		Vector3(48.0, 0.0, 0.0),
		2.2
	)


func _run_test_c() -> Dictionary:
	## 50 units compressed into a small area / crossing.
	return await _measure_scenario(
		"C_50_clumped_crossing",
		50,
		true,
		true,
		Vector3(36.0, 0.0, 0.0),
		0.35
	)


func _run_test_d() -> Dictionary:
	## 100 units compressed/crossing.
	return await _measure_scenario(
		"D_100_clumped_crossing",
		100,
		true,
		true,
		Vector3(40.0, 0.0, 0.0),
		0.28
	)


func _run_test_e() -> Dictionary:
	## Two groups of 50 crossing through one another.
	print("%s: E_2x50_crossing" % TAG)
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	await get_tree().process_frame

	var root := Node3D.new()
	root.name = "OverlapStressE"
	add_child(root)
	PlayerRouteNavigation.ensure_grid_ready()

	var group_a: Array = _spawn_grid(root, 50, Vector3(-18.0, 0.0, -6.0), 0.4, TeamVisuals.PLAYER_TEAM_ID)
	var group_b: Array = _spawn_grid(root, 50, Vector3(18.0, 0.0, 6.0), 0.4, TeamVisuals.PLAYER_TEAM_ID)
	await get_tree().process_frame
	await get_tree().physics_frame

	PlayerRouteNavigation.issue_player_group_command(
		group_a, Vector3(22.0, 0.0, 6.0), &"move", false
	)
	PlayerRouteNavigation.issue_player_group_command(
		group_b, Vector3(-22.0, 0.0, -6.0), &"move", false
	)

	var snapshot: Dictionary = await _sample_metrics(group_a.size() + group_b.size(), true)
	snapshot["name"] = "E_2x50_crossing"
	snapshot["collision_layer"] = PhysicsLayers.UNITS
	snapshot["collision_mask"] = PhysicsLayers.UNIT_COLLISION_MASK

	_free_units(group_a)
	_free_units(group_b)
	root.queue_free()
	await get_tree().process_frame
	return snapshot


func _run_test_f() -> Dictionary:
	## 50 player + 50 enemy overlapping in one fight area.
	print("%s: F_100_combat_clump" % TAG)
	PlayerRouteNavigation.clear_all()
	CombatTargetValidation.reset_match_state()
	PerfCounters.reset_all()
	await get_tree().process_frame

	var root := Node3D.new()
	root.name = "OverlapStressF"
	add_child(root)
	PlayerRouteNavigation.ensure_grid_ready()

	var players: Array = _spawn_grid(
		root, 50, Vector3(-1.5, 0.0, -1.5), 0.35, TeamVisuals.PLAYER_TEAM_ID
	)
	var enemies: Array = _spawn_grid(
		root, 50, Vector3(1.5, 0.0, 1.5), 0.35, TeamVisuals.ENEMY_TEAM_ID
	)
	await get_tree().process_frame
	await get_tree().physics_frame

	PlayerRouteNavigation.issue_player_group_command(
		players, Vector3(2.0, 0.0, 2.0), &"attack_move", false
	)
	PlayerRouteNavigation.issue_player_group_command(
		enemies, Vector3(-2.0, 0.0, -2.0), &"attack_move", false
	)

	var snapshot: Dictionary = await _sample_metrics(players.size() + enemies.size(), true)
	snapshot["name"] = "F_100_combat_clump"
	snapshot["collision_layer"] = PhysicsLayers.UNITS
	snapshot["collision_mask"] = PhysicsLayers.UNIT_COLLISION_MASK

	_free_units(players)
	_free_units(enemies)
	root.queue_free()
	await get_tree().process_frame
	return snapshot


func _run_test_g_40_workers() -> Dictionary:
	return await _measure_worker_grid("G_40_workers_idle", 40, false)


func _run_test_h_60_standing() -> Dictionary:
	return await _measure_scenario(
		"H_60_military_standing",
		60,
		false,
		false,
		Vector3(20.0, 0.0, 0.0),
		2.2
	)


func _run_test_i_60_moving() -> Dictionary:
	return await _measure_scenario(
		"I_60_military_moving",
		60,
		true,
		false,
		Vector3(40.0, 0.0, 0.0),
		2.2
	)


func _run_test_j_30v30() -> Dictionary:
	print("%s: J_30v30_combat" % TAG)
	PlayerRouteNavigation.clear_all()
	CombatTargetValidation.reset_match_state()
	PerfCounters.reset_all()
	await get_tree().process_frame

	var root := Node3D.new()
	root.name = "OverlapStressJ"
	add_child(root)
	PlayerRouteNavigation.ensure_grid_ready()

	var players: Array = _spawn_grid(
		root, 30, Vector3(-8.0, 0.0, -4.0), 1.4, TeamVisuals.PLAYER_TEAM_ID
	)
	var enemies: Array = _spawn_grid(
		root, 30, Vector3(8.0, 0.0, 4.0), 1.4, TeamVisuals.ENEMY_TEAM_ID
	)
	await get_tree().process_frame
	await get_tree().physics_frame

	PlayerRouteNavigation.issue_player_group_command(
		players, Vector3(6.0, 0.0, 2.0), &"attack_move", false
	)
	PlayerRouteNavigation.issue_player_group_command(
		enemies, Vector3(-6.0, 0.0, -2.0), &"attack_move", false
	)

	var snapshot: Dictionary = await _sample_metrics(players.size() + enemies.size(), true)
	snapshot["name"] = "J_30v30_combat"
	_free_units(players)
	_free_units(enemies)
	root.queue_free()
	await get_tree().process_frame
	return snapshot


func _run_test_k_five_gold() -> Dictionary:
	print("%s: K_5_gold_workers" % TAG)
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	await get_tree().process_frame

	var root := Node3D.new()
	root.name = "OverlapStressK"
	add_child(root)
	PlayerRouteNavigation.ensure_grid_ready()

	var mine: GoldMine = GOLD_SCENE.instantiate() as GoldMine
	root.add_child(mine)
	mine.set_owner_faction(GatherableResource.OwnerFaction.ENEMY)
	mine.global_position = Vector3(8.0, 0.0, 0.0)

	var workers: Array = []
	for index: int in 5:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		root.add_child(worker)
		worker.add_to_group(&"units")
		worker.add_to_group(&"enemy_workers")
		worker.add_to_group(&"enemies")
		worker.team_id = TeamVisuals.ENEMY_TEAM_ID
		worker.global_position = Vector3(-2.0 + float(index) * 1.2, 0.0, -6.0)
		workers.append(worker)

	await get_tree().process_frame
	await get_tree().physics_frame
	for worker_ref: Variant in workers:
		(worker_ref as Worker).command_gather_gold_mine(mine, false)

	var snapshot: Dictionary = await _sample_metrics(workers.size(), true)
	snapshot["name"] = "K_5_gold_workers"
	_free_units(workers)
	mine.queue_free()
	root.queue_free()
	await get_tree().process_frame
	return snapshot


func _run_test_l_overlay_off() -> Dictionary:
	PerfDebugOverlay.hide_overlay()
	var snapshot: Dictionary = await _measure_scenario(
		"L_60_moving_F3_off",
		60,
		true,
		false,
		Vector3(36.0, 0.0, 0.0),
		2.2
	)
	return snapshot


func _run_test_m_overlay_on() -> Dictionary:
	PerfDebugOverlay.show_overlay()
	var snapshot: Dictionary = await _measure_scenario(
		"M_60_moving_F3_on",
		60,
		true,
		false,
		Vector3(36.0, 0.0, 0.0),
		2.2
	)
	PerfDebugOverlay.hide_overlay()
	return snapshot


func _measure_worker_grid(name: String, count: int, moving: bool) -> Dictionary:
	print("%s: %s" % [TAG, name])
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	await get_tree().process_frame

	var root := Node3D.new()
	root.name = "OverlapStress_%s" % name
	add_child(root)
	PlayerRouteNavigation.ensure_grid_ready()

	var workers: Array = []
	var cols: int = int(ceil(sqrt(float(count))))
	for index: int in count:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		root.add_child(worker)
		worker.add_to_group(&"units")
		worker.add_to_group(&"workers")
		worker.team_id = TeamVisuals.PLAYER_TEAM_ID
		var col: int = index % cols
		var row: int = int(index / cols)
		worker.global_position = Vector3(-16.0 + float(col) * 1.8, 0.0, float(row) * 1.8)
		workers.append(worker)

	await get_tree().process_frame
	await get_tree().physics_frame
	if moving:
		PlayerRouteNavigation.issue_player_group_command(
			workers, Vector3(24.0, 0.0, 0.0), &"move", false
		)

	var snapshot: Dictionary = await _sample_metrics(count, moving)
	snapshot["name"] = name
	_free_units(workers)
	root.queue_free()
	await get_tree().process_frame
	return snapshot


func _measure_scenario(
	name: String,
	count: int,
	moving: bool,
	clumped: bool,
	destination: Vector3,
	spacing: float
) -> Dictionary:
	print("%s: %s" % [TAG, name])
	PlayerRouteNavigation.clear_all()
	PerfCounters.reset_all()
	await get_tree().process_frame

	var root := Node3D.new()
	root.name = "OverlapStress_%s" % name
	add_child(root)
	PlayerRouteNavigation.ensure_grid_ready()

	var origin := Vector3(-20.0, 0.0, 0.0)
	if clumped:
		origin = Vector3(-4.0, 0.0, 0.0)
	var units: Array = _spawn_grid(
		root, count, origin, spacing, TeamVisuals.PLAYER_TEAM_ID
	)
	await get_tree().process_frame
	await get_tree().physics_frame

	if moving:
		PlayerRouteNavigation.issue_player_group_command(
			units, destination, &"move", false
		)

	var snapshot: Dictionary = await _sample_metrics(count, moving)
	snapshot["name"] = name
	snapshot["collision_layer"] = PhysicsLayers.UNITS
	snapshot["collision_mask"] = PhysicsLayers.UNIT_COLLISION_MASK

	_free_units(units)
	root.queue_free()
	await get_tree().process_frame
	return snapshot


func _spawn_grid(
	parent: Node3D,
	count: int,
	origin: Vector3,
	spacing: float,
	team_id: int
) -> Array:
	var units: Array = []
	var cols: int = int(ceil(sqrt(float(count))))
	for index: int in count:
		var unit: Unit = UNIT_SCENE.instantiate() as Unit
		parent.add_child(unit)
		unit.add_to_group(&"units")
		unit.team_id = team_id
		if team_id == TeamVisuals.ENEMY_TEAM_ID:
			unit.add_to_group(&"enemies")
			unit.add_to_group(&"enemy_combat_units")
		var col: int = index % cols
		var row: int = int(index / cols)
		unit.global_position = origin + Vector3(float(col) * spacing, 0.0, float(row) * spacing)
		units.append(unit)
	return units


func _sample_metrics(expected_units: int, expect_moving: bool) -> Dictionary:
	await _wait_msec(WARMUP_MSEC)
	PerfCounters.reset_all()

	var physics_sum: float = 0.0
	var script_sum: float = 0.0
	var samples: int = 0
	var moving_peak: int = 0
	## Wait for at least one full PerfCounters rate window (~1s), then sample a bit more.
	var deadline: int = Time.get_ticks_msec() + SAMPLE_MSEC
	var last_good_snap: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		physics_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		script_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		samples += 1
		var moving_now: int = _count_moving_units()
		moving_peak = maxi(moving_peak, moving_now)
		var candidate: Dictionary = PerfCounters.collect_rate_snapshot()
		if float(candidate.get("neighbor_queries_per_sec", 0.0)) > 0.0 or samples > 30:
			last_good_snap = candidate
		await get_tree().physics_frame

	var snap: Dictionary = last_good_snap if not last_good_snap.is_empty() else PerfCounters.collect_rate_snapshot()
	snap["units"] = expected_units
	snap["moving_peak"] = moving_peak
	snap["expect_moving"] = expect_moving
	snap["avg_physics_ms"] = physics_sum / float(maxi(samples, 1))
	snap["avg_script_ms"] = script_sum / float(maxi(samples, 1))
	snap["sample_frames"] = samples
	snap["visual_fps"] = "NEEDS_MANUAL_TEST"
	snap["collision_pairs"] = Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
	return snap


func _count_moving_units() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	var moving: int = 0
	for node_variant: Variant in tree.get_nodes_in_group(&"units"):
		if not NodeSafety.is_alive_node(node_variant) or not node_variant is Unit:
			continue
		if (node_variant as Unit).has_move_target:
			moving += 1
	return moving


func _free_units(units: Array) -> void:
	for unit_ref: Variant in units:
		var node: Variant = NodeSafety.safe_node(unit_ref)
		if node == null:
			continue
		(node as Node).queue_free()


func _wait_msec(duration_msec: int) -> void:
	var deadline: int = Time.get_ticks_msec() + duration_msec
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


func _format_report(results: Array[Dictionary]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("PASS unit_overlap_stress")
	lines.append("visual_fps=NEEDS_MANUAL_TEST (headless)")
	lines.append(
		"collision_after_audit layer=%d mask=%d (UNITS vs WORLD|BUILDINGS; no mobile-mobile hard collide)"
		% [PhysicsLayers.UNITS, PhysicsLayers.UNIT_COLLISION_MASK]
	)
	lines.append("")
	for snap: Dictionary in results:
		lines.append("=== %s ===" % str(snap.get("name", "?")))
		lines.append(
			"units=%d moving_peak=%d phys_ms=%.2f script_ms=%.2f fps=%.0f"
			% [
				int(snap.get("units", 0)),
				int(snap.get("moving_peak", 0)),
				float(snap.get("avg_physics_ms", 0.0)),
				float(snap.get("avg_script_ms", 0.0)),
				float(snap.get("fps", 0.0)),
			]
		)
		lines.append(
			"neighQ/s=%.0f neighN/s=%.0f sep/s=%.0f repath/s=%.0f route/s=%.0f tgt/s=%.0f stuckChk/s=%.0f stuckRec/s=%.0f"
			% [
				float(snap.get("neighbor_queries_per_sec", 0.0)),
				float(snap.get("neighbors_processed_per_sec", 0.0)),
				float(snap.get("separation_updates_per_sec", 0.0)),
				float(snap.get("repaths_per_sec", 0.0)),
				float(snap.get("strategic_routes_per_sec", 0.0)),
				float(snap.get("target_searches_per_sec", 0.0)),
				float(snap.get("stuck_checks_per_sec", 0.0)),
				float(snap.get("stuck_recoveries_per_sec", 0.0)),
			]
		)
		lines.append(
			"orders/s=%.0f query_ms/f=%.2f slide_ms/f=%.2f tgt_ms/f=%.2f pairs=%.0f"
			% [
				float(snap.get("orders_per_sec", 0.0)),
				float(snap.get("query_nearby_ms", 0.0)),
				float(snap.get("move_and_slide_ms", 0.0)),
				float(snap.get("target_search_ms", 0.0)),
				float(snap.get("collision_pairs", 0.0)),
			]
		)
		lines.append(
			"unit_ms/f=%.2f mil_ms/f=%.2f rts_ms/f=%.2f stuck_ms/f=%.2f steer_ms/f=%.2f"
			% [
				float(snap.get("unit_phys_ms", 0.0)),
				float(snap.get("mil_phys_ms", 0.0)),
				float(snap.get("rts_move_ms", 0.0)),
				float(snap.get("stuck_watch_ms", 0.0)),
				float(snap.get("steer_ms", 0.0)),
			]
		)
		lines.append("")
	return "\n".join(lines)
