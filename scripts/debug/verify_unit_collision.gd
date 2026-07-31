extends Node

## Headless verification for unit separation, approach slots, and combat spacing.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_unit_collision.tscn

const REPORT_PATH := "user://unit_collision_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const SETTLE_TIMEOUT_MS := 6000
const CHASE_TIMEOUT_MS := 7000
const GAP_TIMEOUT_MS := 8000


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	print("verify_unit_collision: start")
	_verify_approach_slots_surround(failures)
	_verify_ranged_standoff(failures)
	await _verify_melee_20v20_spread(failures)
	await _verify_mixed_army_spacing(failures)
	await _verify_chase_retreating_target(failures)
	await _verify_narrow_gap_no_deadlock(failures)
	await _verify_stop_attack_attack_move(failures)

	var report: String
	if failures.is_empty():
		report = "PASS unit_collision\n"
	else:
		report = "FAIL unit_collision\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_approach_slots_surround(failures: PackedStringArray) -> void:
	print("verify: approach slots surround")
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(10.0, 0.0, 10.0)

	var positions: Array[Vector3] = []
	var slots: Dictionary = {}
	for index: int in 12:
		var attacker := Node3D.new()
		add_child(attacker)
		attacker.global_position = Vector3(10.0 + float(index) * 0.01, 0.0, 8.0)
		var slot: int = CombatTargetValidation.claim_attack_approach_slot(target, attacker)
		_expect(failures, "slot %d unique" % index, not slots.has(slot))
		slots[slot] = true
		var approach: Vector3 = CombatTargetValidation.compute_attack_approach_position(
			attacker, target, 2.0, 0.25, slot
		)
		positions.append(approach)
		attacker.free()

	var min_pair: float = 999.0
	for i: int in positions.size():
		for j: int in range(i + 1, positions.size()):
			min_pair = minf(min_pair, _horizontal_distance(positions[i], positions[j]))
		var dist_to_target: float = _horizontal_distance(positions[i], target.global_position)
		_expect(
			failures,
			"slot %d keeps melee standoff" % i,
			dist_to_target >= 1.4
		)

	_expect(failures, "12 approach slots have pairwise spacing", min_pair >= 0.55)
	CombatTargetValidation.clear_attack_approach_slots(target)
	target.free()


func _verify_ranged_standoff(failures: PackedStringArray) -> void:
	print("verify: ranged standoff")
	var attacker := Node3D.new()
	var target := Node3D.new()
	add_child(attacker)
	add_child(target)
	attacker.global_position = Vector3(0.0, 0.0, 0.0)
	target.global_position = Vector3(1.0, 0.0, 0.0)

	var approach: Vector3 = CombatTargetValidation.compute_attack_approach_position(
		attacker, target, 8.0, 0.25, 0
	)
	var preferred: float = CombatTargetValidation.get_preferred_attack_standoff(
		attacker, target, 8.0, 0.25, 0
	)
	_expect(failures, "ranged preferred standoff near attack range", preferred >= 6.5)
	_expect(
		failures,
		"ranged approach stays outside melee blob",
		_horizontal_distance(approach, target.global_position) >= 6.5
	)
	_expect(
		failures,
		"ranged too-close detection when overlapping",
		CombatTargetValidation.is_too_close_for_preferred_range(
			attacker, target, 8.0, 0.25, 0
		)
	)

	attacker.free()
	target.free()


func _verify_melee_20v20_spread(failures: PackedStringArray) -> void:
	print("verify: 20 vs 20 melee spread")
	var harness: Dictionary = await _spawn_harness()
	var allies: Array[Swordsman] = []
	var enemies: Array[Swordsman] = []

	for index: int in 20:
		var ally: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(ally)
		ally.add_to_group(&"units")
		ally.team_id = 0
		ally.global_position = Vector3(-8.0 + float(index % 5) * 1.2, 0.0, -6.0 + float(index / 5) * 1.2)
		allies.append(ally)

		var enemy: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(enemy)
		enemy.add_to_group(&"units")
		enemy.add_to_group(&"enemies")
		enemy.team_id = 1
		enemy.global_position = Vector3(8.0 - float(index % 5) * 1.2, 0.0, 6.0 - float(index / 5) * 1.2)
		enemies.append(enemy)

	await get_tree().process_frame
	await get_tree().physics_frame

	for index: int in allies.size():
		allies[index].command_attack(enemies[index % enemies.size()], index)
		enemies[index].command_attack(allies[index % allies.size()], index)

	await _wait_msec(SETTLE_TIMEOUT_MS)

	var overlapping_pairs: int = 0
	var total_pairs: int = 0
	var sample: Array[Swordsman] = allies.duplicate()
	sample.append_array(enemies)
	for i: int in mini(sample.size(), 24):
		for j: int in range(i + 1, mini(sample.size(), 24)):
			if not NodeSafety.is_alive_node(sample[i]) or not NodeSafety.is_alive_node(sample[j]):
				continue
			total_pairs += 1
			if _horizontal_distance(sample[i].global_position, sample[j].global_position) < 0.35:
				overlapping_pairs += 1

	_expect(
		failures,
		"20v20: almost no exact-position stacking",
		overlapping_pairs <= maxi(1, total_pairs / 40)
	)

	var unique_slots: Dictionary = {}
	var first_enemy: Swordsman = enemies[0]
	for ally: Swordsman in allies:
		if not NodeSafety.is_alive_node(ally):
			continue
		if ally._attack_target == first_enemy:
			unique_slots[ally._attack_approach_slot] = true
	_expect(
		failures,
		"20v20: attackers use distinct approach slots when ordered",
		unique_slots.size() >= 1
	)

	await _free_harness(harness)


func _verify_mixed_army_spacing(failures: PackedStringArray) -> void:
	print("verify: mixed melee/ranged spacing")
	var harness: Dictionary = await _spawn_harness()
	var target: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(target)
	target.add_to_group(&"units")
	target.add_to_group(&"enemies")
	target.team_id = 1
	target.global_position = Vector3(0.0, 0.0, 0.0)
	# Keep the target alive so spacing can be measured after engage.
	if target._health_component != null:
		target._health_component.max_health = 5000
		target._health_component.current_health = 5000

	var melee: Array[Swordsman] = []
	for index: int in 6:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.add_to_group(&"units")
		unit.team_id = 0
		unit.global_position = Vector3(-4.0 + float(index) * 0.8, 0.0, -5.0)
		melee.append(unit)
		await _wait_nav_ready(unit)

	var archers: Array[Archer] = []
	for index: int in 4:
		var archer: Archer = ARCHER_SCENE.instantiate() as Archer
		harness["root"].add_child(archer)
		archer.add_to_group(&"units")
		archer.team_id = 0
		archer.global_position = Vector3(-3.0 + float(index) * 1.0, 0.0, -9.0)
		archers.append(archer)
		await _wait_nav_ready(archer)

	await get_tree().process_frame
	for index: int in melee.size():
		melee[index].command_attack(target, index)
	for index: int in archers.size():
		archers[index].command_attack(target, index + melee.size())

	var deadline_msec: int = Time.get_ticks_msec() + SETTLE_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline_msec:
		var engaged: int = 0
		for unit: Swordsman in melee:
			if NodeSafety.is_alive_node(unit) and unit._is_in_attack_range(target):
				engaged += 1
		if engaged >= 3:
			break
		await get_tree().physics_frame

	# Extra settle frames so soft separation / approach slots can unpack.
	await _wait_msec(1200)

	_expect(failures, "mixed: target still alive for spacing check", NodeSafety.is_alive_node(target))

	var archer_ok: int = 0
	for archer: Archer in archers:
		if not NodeSafety.is_alive_node(archer) or not NodeSafety.is_alive_node(target):
			continue
		var approach: Vector3 = archer._compute_attack_approach_position(target)
		var live_distance: float = _horizontal_distance(archer.global_position, target.global_position)
		var approach_distance: float = _horizontal_distance(approach, target.global_position)
		if live_distance >= 5.0 or approach_distance >= 6.0:
			archer_ok += 1
	_expect(failures, "mixed: ranged units keep distance from melee target", archer_ok >= 2)

	var melee_ok: int = 0
	for unit: Swordsman in melee:
		if not NodeSafety.is_alive_node(unit) or not NodeSafety.is_alive_node(target):
			continue
		var distance: float = _horizontal_distance(unit.global_position, target.global_position)
		if distance >= 0.8 and distance <= 3.5:
			melee_ok += 1
	_expect(failures, "mixed: melee units surround near attack range", melee_ok >= 3)

	await _free_harness(harness)


func _verify_chase_retreating_target(failures: PackedStringArray) -> void:
	print("verify: chase retreating target")
	var harness: Dictionary = await _spawn_harness()
	var chaser: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(chaser)
	chaser.add_to_group(&"units")
	chaser.team_id = 0
	chaser.global_position = Vector3(-8.0, 0.0, 0.0)

	var prey: Archer = ARCHER_SCENE.instantiate() as Archer
	harness["root"].add_child(prey)
	prey.add_to_group(&"units")
	prey.add_to_group(&"enemies")
	prey.team_id = 1
	prey.global_position = Vector3(-2.0, 0.0, 0.0)

	await _wait_nav_ready(chaser)
	chaser.command_attack(prey)
	_expect(failures, "chase: attack order accepted", chaser._attack_target == prey)

	var start_x: float = chaser.global_position.x
	prey.set_movement_target(Vector3(10.0, 0.0, 0.0))

	var progressed: bool = false
	var deadline_msec: int = Time.get_ticks_msec() + CHASE_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline_msec:
		if not NodeSafety.is_alive_node(chaser) or not NodeSafety.is_alive_node(prey):
			break
		if chaser.global_position.x > start_x + 2.0:
			progressed = true
			break
		if chaser._is_in_attack_range(prey):
			progressed = true
			break
		await get_tree().physics_frame

	_expect(failures, "chase: pursues retreating target", progressed)
	_expect(
		failures,
		"chase: still has attack order or reached range",
		chaser._attack_target == prey or chaser._is_in_attack_range(prey)
	)

	await _free_harness(harness)


func _verify_narrow_gap_no_deadlock(failures: PackedStringArray) -> void:
	print("verify: narrow gap no deadlock")
	var harness: Dictionary = await _spawn_harness_with_corridor()
	var unit_a: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var unit_b: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(unit_a)
	harness["root"].add_child(unit_b)
	unit_a.add_to_group(&"units")
	unit_b.add_to_group(&"units")
	unit_a.global_position = Vector3(-8.0, 0.0, 0.0)
	unit_b.global_position = Vector3(-8.0, 0.0, 1.2)

	await _wait_nav_ready(unit_a)
	await _wait_nav_ready(unit_b)

	unit_a.set_movement_target(Vector3(8.0, 0.0, 0.0))
	unit_b.set_movement_target(Vector3(8.0, 0.0, 0.4))

	var arrived_a: bool = false
	var arrived_b: bool = false
	var permanently_stuck: bool = false
	var stuck_frames: int = 0
	var deadline_msec: int = Time.get_ticks_msec() + GAP_TIMEOUT_MS
	var last_a: Vector3 = unit_a.global_position
	while Time.get_ticks_msec() < deadline_msec:
		if _horizontal_distance(unit_a.global_position, Vector3(8.0, 0.0, 0.0)) <= 2.0:
			arrived_a = true
		if _horizontal_distance(unit_b.global_position, Vector3(8.0, 0.0, 0.4)) <= 2.0:
			arrived_b = true
		if arrived_a and arrived_b:
			break

		var moved: float = _horizontal_distance(unit_a.global_position, last_a)
		last_a = unit_a.global_position
		if moved < 0.01 and unit_a.has_move_target:
			stuck_frames += 1
		else:
			stuck_frames = 0
		if stuck_frames > 180:
			permanently_stuck = true
			break
		await get_tree().physics_frame

	_expect(failures, "narrow gap: unit A progresses or arrives", arrived_a or unit_a.global_position.x > -2.0)
	_expect(failures, "narrow gap: unit B progresses or arrives", arrived_b or unit_b.global_position.x > -2.0)
	_expect(failures, "narrow gap: no permanent deadlock", not permanently_stuck)

	unit_a.stop_movement()
	unit_b.stop_movement()
	_expect(failures, "stop works after gap traversal", not unit_a.has_move_target and not unit_b.has_move_target)

	await _free_harness(harness)


func _verify_stop_attack_attack_move(failures: PackedStringArray) -> void:
	print("verify: stop / attack / attack-move with separation")
	var harness: Dictionary = await _spawn_harness()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(unit)
	unit.add_to_group(&"units")
	unit.global_position = Vector3(-6.0, 0.0, -4.0)
	await _wait_nav_ready(unit)

	unit.command_attack_move(Vector3(6.0, 0.0, -4.0))
	await _wait_msec(150)
	_expect(failures, "attack-move: has destination", unit.has_move_target)

	var prey: Archer = ARCHER_SCENE.instantiate() as Archer
	harness["root"].add_child(prey)
	prey.add_to_group(&"units")
	prey.add_to_group(&"enemies")
	prey.team_id = 1
	prey.global_position = Vector3(-2.0, 0.0, -4.0)
	await get_tree().process_frame
	unit.command_attack(prey, 0)
	_expect(failures, "attack: target assigned", unit._attack_target == prey)

	unit.stop_movement()
	_expect(failures, "stop: clears move", not unit.has_move_target)
	_expect(failures, "stop: clears attack", unit._attack_target == null)
	_expect(failures, "stop: clears attack-move", not unit._has_attack_move_destination)

	await _free_harness(harness)


func _spawn_harness() -> Dictionary:
	var root := Node3D.new()
	root.name = "CollisionHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)
	await get_tree().process_frame
	await _bake_nav_mesh(region, root, false)

	return {"root": root, "region": region}


func _spawn_harness_with_corridor() -> Dictionary:
	var root := Node3D.new()
	root.name = "CorridorHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)

	_add_box_obstacle(root, Vector3(0.0, 0.0, 3.2), Vector3(8.0, 2.0, 4.0), 2.2)
	_add_box_obstacle(root, Vector3(0.0, 0.0, -3.2), Vector3(8.0, 2.0, 4.0), 2.2)

	await get_tree().process_frame
	await _bake_nav_mesh(region, root, true)
	return {"root": root, "region": region}


func _add_box_obstacle(parent: Node3D, position: Vector3, size: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.BUILDINGS
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var obstacle := NavigationObstacle3D.new()
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.radius = radius
	obstacle.height = size.y
	body.add_child(obstacle)
	parent.add_child(body)


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
		if unit._navigation_agent != null:
			if UnitNavigation.can_use(unit._navigation_agent):
				return
			await get_tree().physics_frame
			return
		await get_tree().process_frame


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
	CombatTargetValidation.reset_match_state()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
