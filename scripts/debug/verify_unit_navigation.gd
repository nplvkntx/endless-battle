extends Node

## Headless verification for combat unit NavigationAgent movement.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_unit_navigation.tscn

const REPORT_PATH := "user://unit_navigation_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const ARRIVE_TIMEOUT_MS := 8000


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	print("verify_unit_navigation: start")
	_verify_agent_present(failures)
	await _verify_move_around_building(failures)
	await _verify_move_around_trees(failures)
	await _verify_chase_moving_target(failures)
	await _verify_change_destination_mid_path(failures)
	await _verify_stop_clears_navigation(failures)
	await _verify_invalid_target_cleanup(failures)

	var report: String
	if failures.is_empty():
		report = "PASS unit_navigation\n"
	else:
		report = "FAIL unit_navigation\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_agent_present(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	_expect(failures, "swordsman has NavigationAgent3D", unit.get_node_or_null("NavigationAgent3D") != null)
	_expect(failures, "unit exposes navigation agent field", unit._navigation_agent != null)
	_expect(failures, "unit has stop_movement API", unit.has_method("stop_movement"))
	_expect(failures, "unit has clear_move_target API", unit.has_method("clear_move_target"))
	unit.free()


func _verify_move_around_building(failures: PackedStringArray) -> void:
	print("verify: move around building")
	var harness: Dictionary = await _spawn_nav_harness(true, false)
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-8.0, 0.0, 0.0)
	await _wait_nav_ready(unit)

	unit.set_movement_target(Vector3(8.0, 0.0, 0.0))
	_expect(failures, "building path: move target accepted", unit.has_move_target)

	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(
		failures,
		"building path: navigation destination applied",
		unit._navigation_agent != null
		and _horizontal_distance(unit._navigation_agent.target_position, Vector3(8.0, 0.0, 0.0)) < 0.25
	)

	var path_bends: bool = await _wait_for_path_bend_or_arrival(unit, Vector3(8.0, 0.0, 0.0), 2.0)
	_expect(failures, "building path: path bends around obstacle or arrives", path_bends)

	await _free_harness(harness)


func _verify_move_around_trees(failures: PackedStringArray) -> void:
	print("verify: move around trees")
	var harness: Dictionary = await _spawn_nav_harness(true, true)
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-7.0, 0.0, -2.0)
	await _wait_nav_ready(unit)

	unit.set_movement_target(Vector3(7.0, 0.0, 2.0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var path_bends: bool = await _wait_for_path_bend_or_arrival(unit, Vector3(7.0, 0.0, 2.0), 2.0)
	_expect(failures, "trees path: path bends around trees or arrives", path_bends)

	await _free_harness(harness)


func _verify_chase_moving_target(failures: PackedStringArray) -> void:
	print("verify: chase moving target")
	var harness: Dictionary = await _spawn_nav_harness(false, false)
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-6.0, 0.0, 4.0)
	await _wait_nav_ready(unit)

	var prey: Archer = ARCHER_SCENE.instantiate() as Archer
	add_child(prey)
	prey.add_to_group(&"enemies")
	prey.team_id = 1
	prey.global_position = Vector3(0.0, 0.0, 4.0)
	await get_tree().process_frame

	unit.command_attack(prey)
	_expect(failures, "chase: attack target assigned", unit._attack_target == prey)
	_expect(failures, "chase: chase movement started", unit.has_move_target or unit._has_chase_target)

	var first_dest: Vector3 = unit.get_movement_destination()
	prey.global_position = Vector3(5.0, 0.0, 4.0)
	await _wait_msec(100)
	unit._update_chase_movement()
	await get_tree().physics_frame

	var approach: Vector3 = unit._compute_attack_approach_position(prey)
	var expected_standoff: float = CombatTargetValidation.get_preferred_attack_standoff(
		unit, prey, unit.attack_range, unit.stopping_distance, 0
	)
	_expect(
		failures,
		"chase: approach standoff stays outside attack target center",
		_horizontal_distance(approach, prey.global_position) >= expected_standoff - 0.05
	)
	_expect(
		failures,
		"chase: approach lands inside effective attack reach after soft arrival",
		expected_standoff + Unit.SOFT_ARRIVAL_DISTANCE
		<= CombatTargetValidation.get_effective_attack_range(unit.attack_range) + 0.05
	)

	# Allow repath cooldown window, then force an urgent update check via threshold.
	await _wait_msec(1200)
	unit._has_chase_target = true
	unit._update_chase_movement(0.0, true)
	var dest_delta: float = _horizontal_distance(unit.get_movement_destination(), first_dest)
	_expect(
		failures,
		"chase: destination updates when target moves far enough (or already chasing new approach)",
		dest_delta >= Unit.CHASE_TARGET_MOVE_THRESHOLD * 0.5
		or _horizontal_distance(unit.get_movement_destination(), approach) < 0.5
		or unit._is_in_attack_range(prey)
	)

	if NodeSafety.is_alive_node(prey):
		prey.free()
	await _free_harness(harness)


func _verify_change_destination_mid_path(failures: PackedStringArray) -> void:
	print("verify: change destination mid-path")
	var harness: Dictionary = await _spawn_nav_harness(false, false)
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-8.0, 0.0, 6.0)
	await _wait_nav_ready(unit)

	unit.set_movement_target(Vector3(8.0, 0.0, 6.0))
	await _wait_msec(200)
	_expect(failures, "mid-path: first destination active", unit.has_move_target)

	var redirected: bool = unit.set_movement_target(Vector3(-8.0, 0.0, 8.0))
	_expect(failures, "mid-path: player redirect applied immediately", redirected)
	_expect(
		failures,
		"mid-path: destination updated",
		_horizontal_distance(unit.get_movement_destination(), Vector3(-8.0, 0.0, 8.0)) < 0.1
	)

	var arrived: bool = await _wait_until_arrived(unit, Vector3(-8.0, 0.0, 8.0), 2.0)
	_expect(failures, "mid-path: arrived at redirected destination", arrived)

	await _free_harness(harness)


func _verify_stop_clears_navigation(failures: PackedStringArray) -> void:
	print("verify: stop clears navigation")
	var harness: Dictionary = await _spawn_nav_harness(false, false)
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-6.0, 0.0, -6.0)
	await _wait_nav_ready(unit)

	unit.command_attack_move(Vector3(6.0, 0.0, -6.0))
	await _wait_msec(100)
	_expect(failures, "stop: moving before stop", unit.has_move_target)

	unit.stop_movement()
	_expect(failures, "stop: clears move target", not unit.has_move_target)
	_expect(failures, "stop: clears attack-move", not unit._has_attack_move_destination)
	_expect(failures, "stop: clears attack target", unit._attack_target == null)
	_expect(failures, "stop: zeroes velocity", unit.velocity.length_squared() < 0.0001)
	_expect(failures, "stop: navigation inactive", not unit._navigation_active)

	await _free_harness(harness)


func _verify_invalid_target_cleanup(failures: PackedStringArray) -> void:
	print("verify: invalid target cleanup")
	var harness: Dictionary = await _spawn_nav_harness(false, false)
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(0.0, 0.0, -8.0)
	await _wait_nav_ready(unit)

	var prey: Archer = ARCHER_SCENE.instantiate() as Archer
	add_child(prey)
	prey.add_to_group(&"enemies")
	prey.team_id = 1
	prey.global_position = Vector3(3.0, 0.0, -8.0)
	await get_tree().process_frame

	unit.command_attack(prey)
	unit._has_attack_move_destination = true
	unit._attack_move_destination = Vector3(-4.0, 0.0, -8.0)
	await _wait_msec(50)

	prey.free()
	await get_tree().process_frame
	unit._sanitize_attack_target()

	_expect(failures, "invalid target: attack cleared", unit._attack_target == null)
	_expect(failures, "invalid target: chase cleared", not unit._has_chase_target)
	_expect(
		failures,
		"invalid target: resumes attack-move or is idle (not stuck forever chasing)",
		unit.has_move_target or not unit._has_chase_target
	)

	unit.stop_movement()
	_expect(failures, "invalid target: stop leaves unit idle", not unit.has_move_target)

	await _free_harness(harness)


func _spawn_nav_harness(with_building: bool, with_trees: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "NavHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)

	if with_building:
		_add_box_obstacle(root, Vector3.ZERO, Vector3(3.0, 2.0, 3.0), 1.6)

	if with_trees:
		for offset: Vector3 in [
			Vector3(-1.5, 0.0, -1.5),
			Vector3(1.5, 0.0, -1.5),
			Vector3(0.0, 0.0, 1.8),
		]:
			_add_cylinder_obstacle(root, offset, 0.45, 0.55)

	await get_tree().process_frame
	await _bake_nav_mesh(region, root)

	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	root.add_child(unit)
	await get_tree().process_frame
	await get_tree().physics_frame

	return {
		"root": root,
		"region": region,
		"unit": unit,
	}


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


func _add_cylinder_obstacle(parent: Node3D, position: Vector3, cyl_radius: float, nav_radius: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.position = position
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = cyl_radius
	cylinder.height = 2.0
	shape.shape = cylinder
	body.add_child(shape)
	var obstacle := NavigationObstacle3D.new()
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.radius = nav_radius
	obstacle.height = 2.0
	body.add_child(obstacle)
	parent.add_child(body)


func _bake_nav_mesh(region: NavigationRegion3D, parent: Node) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25

	var source_data := NavigationMeshSourceGeometryData3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(40.0, 40.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
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


func _wait_for_path_bend_or_arrival(unit: Unit, destination: Vector3, tolerance: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + ARRIVE_TIMEOUT_MS
	var max_lateral: float = 0.0
	var start_z: float = unit.global_position.z
	while Time.get_ticks_msec() < deadline_msec:
		if not NodeSafety.is_alive_node(unit):
			return false
		if _horizontal_distance(unit.global_position, destination) <= tolerance:
			return true
		max_lateral = maxf(max_lateral, absf(unit.global_position.z - start_z))
		if unit._navigation_agent != null and UnitNavigation.can_use(unit._navigation_agent):
			var path: PackedVector3Array = unit._navigation_agent.get_current_navigation_path()
			if path.size() >= 3:
				for point: Vector3 in path:
					if absf(point.z - start_z) > 0.75:
						return true
		if max_lateral > 0.75:
			return true
		await get_tree().physics_frame
	return _horizontal_distance(unit.global_position, destination) <= tolerance + 1.0 or max_lateral > 0.5


func _wait_until_arrived(unit: Unit, destination: Vector3, tolerance: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + ARRIVE_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline_msec:
		if not NodeSafety.is_alive_node(unit):
			return false
		if _horizontal_distance(unit.global_position, destination) <= tolerance:
			return true
		if (
			not unit.has_move_target
			and _horizontal_distance(unit.global_position, destination) <= tolerance + 0.75
		):
			return true
		await get_tree().physics_frame
	return _horizontal_distance(unit.global_position, destination) <= tolerance + 1.0


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
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
