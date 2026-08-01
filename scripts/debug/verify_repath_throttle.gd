extends Node

## Headless stress check for navigation repath throttling.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_repath_throttle.tscn

const REPORT_PATH := "user://repath_throttle_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const SAMPLE_SECONDS := 3.0
const CHASE_UNIT_COUNT := 24
const AI_WAVE_COUNT := 40


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	PerfCounters.reset_all()

	print("verify_repath_throttle: start")
	await _verify_duplicate_player_order_skips_repath(failures)
	await _verify_chase_army_repath_rate(failures)
	await _verify_ai_group_order_dedup(failures)

	var report: String
	if failures.is_empty():
		report = "PASS repath_throttle\n"
	else:
		report = "FAIL repath_throttle\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_duplicate_player_order_skips_repath(failures: PackedStringArray) -> void:
	print("verify: duplicate player order")
	var harness: Dictionary = await _spawn_nav_harness()
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-6.0, 0.0, 0.0)
	await _wait_nav_ready(unit)

	PerfCounters.set_process(false)
	PerfCounters.reset_all()
	unit.issue_order(UnitOrder.move(Vector3(6.0, 0.0, 0.0)), false)
	await get_tree().physics_frame
	var first_count: int = int(PerfCounters._counts.get(PerfCounters.KEY_REPATH_REQUESTS, 0))

	unit.issue_order(UnitOrder.move(Vector3(6.05, 0.0, 0.0)), false)
	unit.issue_order(UnitOrder.move(Vector3(6.0, 0.0, 0.0)), true)
	await get_tree().physics_frame
	var second_count: int = int(PerfCounters._counts.get(PerfCounters.KEY_REPATH_REQUESTS, 0))
	PerfCounters.set_process(true)

	_expect(failures, "duplicate order: first move repaths once", first_count == 1)
	_expect(
		failures,
		"duplicate order: equivalent reissue does not repath",
		second_count == first_count
	)
	_expect(failures, "duplicate order: queue not flooded", unit.get_queued_orders().is_empty())

	await _free_harness(harness)


func _verify_chase_army_repath_rate(failures: PackedStringArray) -> void:
	print("verify: chase army repath rate")
	var root := Node3D.new()
	add_child(root)
	var region := NavigationRegion3D.new()
	root.add_child(region)
	await get_tree().process_frame
	await _bake_nav_mesh(region, root)

	var prey: Archer = ARCHER_SCENE.instantiate() as Archer
	root.add_child(prey)
	prey.add_to_group(&"enemies")
	prey.team_id = 1
	prey.global_position = Vector3(8.0, 0.0, 0.0)

	var chasers: Array[Swordsman] = []
	for index: int in CHASE_UNIT_COUNT:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		root.add_child(unit)
		unit.add_to_group(&"units")
		unit.team_id = 0
		unit.global_position = Vector3(-8.0 + float(index % 6) * 0.8, 0.0, float(index / 6) * 0.9)
		chasers.append(unit)

	await get_tree().physics_frame
	await get_tree().physics_frame
	for unit: Swordsman in chasers:
		await _wait_nav_ready(unit)
		unit.command_attack(prey)

	PerfCounters.set_process(false)
	PerfCounters.reset_all()
	var elapsed: float = 0.0
	while elapsed < SAMPLE_SECONDS:
		prey.global_position.x += 1.6 * get_physics_process_delta_time()
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame

	var total: int = int(PerfCounters._counts.get(PerfCounters.KEY_REPATH_REQUESTS, 0))
	var rate: float = float(total) / SAMPLE_SECONDS
	PerfCounters.set_process(true)
	print("chase army repaths: total=%d rate=%.1f/sec over %.1fs" % [total, rate, SAMPLE_SECONDS])
	_expect(
		failures,
		"chase army: sustained repaths stay under 50/sec",
		rate < 50.0
	)

	root.free()
	await get_tree().process_frame


func _verify_ai_group_order_dedup(failures: PackedStringArray) -> void:
	print("verify: AI group order dedup")
	var root := Node3D.new()
	add_child(root)
	var region := NavigationRegion3D.new()
	root.add_child(region)
	await get_tree().process_frame
	await _bake_nav_mesh(region, root)

	EnemyArmyCommand.reset_match_state()
	EnemyUnitMission.reset_match_state()

	var units: Array = []
	for index: int in AI_WAVE_COUNT:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		root.add_child(unit)
		unit.add_to_group(&"enemies")
		unit.team_id = 1
		unit.global_position = Vector3(float(index % 8) * 1.1, 0.0, float(index / 8) * 1.1)
		units.append(unit)

	await get_tree().physics_frame
	for unit: Variant in units:
		EnemyArmyCommand.register_combat_unit(unit)
		await _wait_nav_ready(unit as Unit)

	PerfCounters.set_process(false)
	PerfCounters.reset_all()
	var destination := Vector3(20.0, 0.0, 4.0)
	EnemyUnitMission.claim_units_for_mission(units, EnemyUnitMission.Mission.DEFEND)
	# Bypass strategic attack gates; exercise spaced group-order path directly.
	EnemyArmyCommand._issue_spaced_group_orders(
		units, destination, true, EnemyUnitMission.Mission.DEFEND
	)
	for _i: int in 30:
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().physics_frame

	var after_first: int = int(PerfCounters._counts.get(PerfCounters.KEY_REPATH_REQUESTS, 0))

	for _i: int in 12:
		EnemyArmyCommand._issue_spaced_group_orders(
			units, destination, true, EnemyUnitMission.Mission.DEFEND
		)
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().physics_frame

	var after_spam: int = int(PerfCounters._counts.get(PerfCounters.KEY_REPATH_REQUESTS, 0))
	PerfCounters.set_process(true)
	print("AI group repaths: first=%d after_spam=%d" % [after_first, after_spam])
	_expect(failures, "AI group: initial orders issue some repaths", after_first > 0)
	_expect(
		failures,
		"AI group: duplicate destinations do not keep repathing",
		after_spam <= after_first + 4
	)

	root.free()
	await get_tree().process_frame


func _spawn_nav_harness() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var region := NavigationRegion3D.new()
	root.add_child(region)
	await get_tree().process_frame
	await _bake_nav_mesh(region, root)
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	root.add_child(unit)
	await get_tree().process_frame
	return {"root": root, "unit": unit}


func _bake_nav_mesh(region: NavigationRegion3D, parent: Node) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	var source_data := NavigationMeshSourceGeometryData3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(60.0, 60.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, parent)
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


func _free_harness(harness: Dictionary) -> void:
	var root: Node = harness.get("root") as Node
	if root != null and is_instance_valid(root):
		root.free()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
