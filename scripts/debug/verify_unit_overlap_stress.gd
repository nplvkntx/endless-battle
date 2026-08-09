extends Node

## Deterministic overlap/clump movement stress harness (Tests A–E).
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_unit_overlap_stress.tscn
##
## Reports physics/script ms + PerfCounters rates. Rendered FPS is NEEDS MANUAL TEST.

const REPORT_PATH := "user://unit_overlap_stress_result.txt"
const UNIT_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
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
	## 50 units standing separated.
	return await _measure_scenario(
		"A_50_separated_idle",
		50,
		false,
		false,
		Vector3(40.0, 0.0, 0.0),
		2.4
	)


func _run_test_b() -> Dictionary:
	## 50 units moving same direction with spacing (little overlap).
	return await _measure_scenario(
		"B_50_moving_spaced",
		50,
		true,
		false,
		Vector3(42.0, 0.0, 0.0),
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
	return snap


func _count_moving_units() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	var moving: int = 0
	for node: Node in tree.get_nodes_in_group(&"units"):
		if node is Unit and (node as Unit).has_move_target:
			moving += 1
	return moving


func _free_units(units: Array) -> void:
	for unit_ref: Variant in units:
		var unit: Node = unit_ref as Node
		if unit != null and is_instance_valid(unit):
			unit.queue_free()


func _wait_msec(duration_msec: int) -> void:
	var deadline: int = Time.get_ticks_msec() + duration_msec
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


func _format_report(results: Array[Dictionary]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("PASS unit_overlap_stress")
	lines.append("visual_fps=NEEDS_MANUAL_TEST (headless)")
	lines.append(
		"collision_before_audit layer=%d mask=%d (UNITS vs WORLD|BUILDINGS; no mobile-mobile hard collide)"
		% [PhysicsLayers.UNITS, PhysicsLayers.UNIT_COLLISION_MASK]
	)
	lines.append("")
	for snap: Dictionary in results:
		lines.append("=== %s ===" % str(snap.get("name", "?")))
		lines.append(
			"units=%d moving_peak=%d phys_ms=%.2f script_ms=%.2f"
			% [
				int(snap.get("units", 0)),
				int(snap.get("moving_peak", 0)),
				float(snap.get("avg_physics_ms", 0.0)),
				float(snap.get("avg_script_ms", 0.0)),
			]
		)
		lines.append(
			"neighQ/s=%.0f neighN/s=%.0f sep/s=%.0f repath/s=%.0f route/s=%.0f tgt/s=%.0f stuckChk/s=%.0f"
			% [
				float(snap.get("neighbor_queries_per_sec", 0.0)),
				float(snap.get("neighbors_processed_per_sec", 0.0)),
				float(snap.get("separation_updates_per_sec", 0.0)),
				float(snap.get("repaths_per_sec", 0.0)),
				float(snap.get("strategic_routes_per_sec", 0.0)),
				float(snap.get("target_searches_per_sec", 0.0)),
				float(snap.get("stuck_checks_per_sec", 0.0)),
			]
		)
		lines.append("")
	return "\n".join(lines)
