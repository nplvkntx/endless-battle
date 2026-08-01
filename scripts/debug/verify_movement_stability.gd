extends Node

## Headless verification for movement wobble / steering oscillation fixes.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_movement_stability.tscn

const REPORT_PATH := "user://movement_stability_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	print("verify_movement_stability: start")
	await _verify_open_terrain_smooth(failures)
	await _verify_group_move_no_oscillation(failures)
	await _verify_stop_clears_velocity(failures)
	await _verify_attack_range_stable(failures)
	await _verify_chase_preserves_smoothing(failures)
	_verify_separation_forward_preserve(failures)

	var report: String
	if failures.is_empty():
		report = "PASS movement_stability\n"
	else:
		report = "FAIL movement_stability\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_open_terrain_smooth(failures: PackedStringArray) -> void:
	print("verify: open terrain smooth move")
	var harness: Dictionary = await _spawn_nav_harness()
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-10.0, 0.0, 0.0)
	await _wait_nav_ready(unit)

	unit.set_movement_target(Vector3(10.0, 0.0, 0.0))
	var stats: Dictionary = await _sample_heading_stats(unit, 2.5)
	_expect(failures, "solo move: unit kept moving", float(stats["samples"]) > 30.0)
	_expect(
		failures,
		"solo move: low heading oscillation",
		float(stats["sign_flips"]) <= 4.0
	)
	_expect(
		failures,
		"solo move: low facing yaw jitter",
		float(stats["yaw_reversals"]) <= 6.0
	)

	await _free_harness(harness)


func _verify_group_move_no_oscillation(failures: PackedStringArray) -> void:
	print("verify: 20 infantry group move")
	var harness: Dictionary = await _spawn_nav_harness()
	var units: Array[Swordsman] = []
	for index: int in 20:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		harness["root"].add_child(unit)
		unit.add_to_group(&"units")
		unit.team_id = 0
		unit.global_position = Vector3(
			-8.0 + float(index % 5) * 1.3,
			0.0,
			-4.0 + float(index / 5) * 1.3
		)
		units.append(unit)

	await get_tree().physics_frame
	await get_tree().physics_frame
	for unit: Swordsman in units:
		unit.set_movement_target(Vector3(8.0, 0.0, unit.global_position.z))

	var total_flips: float = 0.0
	var tracked: int = 0
	for unit: Swordsman in units:
		var stats: Dictionary = await _sample_heading_stats(unit, 1.8)
		total_flips += float(stats["sign_flips"])
		tracked += 1
		if tracked >= 5:
			break

	_expect(
		failures,
		"group move: average heading flips low",
		(total_flips / float(maxi(tracked, 1))) <= 8.0
	)

	for unit: Swordsman in units:
		unit.queue_free()
	await _free_harness(harness)


func _verify_stop_clears_velocity(failures: PackedStringArray) -> void:
	print("verify: stop clears residual velocity")
	var harness: Dictionary = await _spawn_nav_harness()
	var unit: Swordsman = harness["unit"]
	unit.global_position = Vector3(-6.0, 0.0, 2.0)
	await _wait_nav_ready(unit)
	unit.set_movement_target(Vector3(8.0, 0.0, 2.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	unit.stop_movement()
	await get_tree().physics_frame
	_expect(failures, "stop: has_move_target cleared", not unit.has_move_target)
	_expect(
		failures,
		"stop: residual velocity cleared",
		Vector3(unit.velocity.x, 0.0, unit.velocity.z).length() < 0.05
	)
	_expect(
		failures,
		"stop: smoothed velocity cleared",
		unit._smoothed_move_velocity.length() < 0.05
	)
	await _free_harness(harness)


func _verify_attack_range_stable(failures: PackedStringArray) -> void:
	print("verify: attack range standing stability")
	var harness: Dictionary = await _spawn_nav_harness()
	var attacker: Swordsman = harness["unit"]
	var target: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(target)
	target.add_to_group(&"units")
	target.team_id = 1
	attacker.global_position = Vector3(0.0, 0.0, 0.0)
	target.global_position = Vector3(1.6, 0.0, 0.0)
	await get_tree().physics_frame
	attacker.command_attack(target)

	var start_msec: int = Time.get_ticks_msec()
	var max_drift: float = 0.0
	var origin: Vector3 = attacker.global_position
	while Time.get_ticks_msec() - start_msec < 2000:
		await get_tree().physics_frame
		var drift: Vector3 = attacker.global_position - origin
		drift.y = 0.0
		max_drift = maxf(max_drift, drift.length())

	_expect(failures, "attack range: low standing drift", max_drift <= 1.25)
	target.queue_free()
	await _free_harness(harness)


func _verify_chase_preserves_smoothing(failures: PackedStringArray) -> void:
	print("verify: chase does not reset smoothing every tick")
	var harness: Dictionary = await _spawn_nav_harness()
	var hunter: Swordsman = harness["unit"]
	var prey: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	harness["root"].add_child(prey)
	prey.add_to_group(&"units")
	prey.team_id = 1
	hunter.global_position = Vector3(-10.0, 0.0, 0.0)
	prey.global_position = Vector3(8.0, 0.0, 0.0)
	await _wait_nav_ready(hunter)
	hunter.command_attack(prey)

	var hard_resets: int = 0
	var previous: Vector3 = hunter._smoothed_move_velocity
	var start_msec: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_msec < 1800:
		# Keep prey ahead so hunter remains in chase (not arrival/stop).
		prey.global_position.x = hunter.global_position.x + 6.0
		await get_tree().physics_frame
		if not hunter.has_move_target:
			continue
		var current: Vector3 = hunter._smoothed_move_velocity
		if previous.length_squared() > 1.0 and current.length_squared() < 0.0001:
			hard_resets += 1
		previous = current

	_expect(failures, "chase: smoothing not hard-reset every frame", hard_resets <= 2)
	prey.queue_free()
	await _free_harness(harness)


func _verify_separation_forward_preserve(failures: PackedStringArray) -> void:
	print("verify: separation preserves forward motion")
	var body := CharacterBody3D.new()
	add_child(body)
	body.global_position = Vector3.ZERO
	body.set_meta(&"_sep_push_cache", Vector3(-1.0, 0.0, 0.0))
	body.set_meta(&"_sep_push_cache_time", float(Time.get_ticks_msec()) * 0.001)
	var desired := Vector3(0.0, 0.0, 5.0)
	var blended: Vector3 = UnitSeparation.blend_desired_velocity(body, desired, 5.0, 0.55)
	_expect(failures, "forward preserve: still moves forward", blended.z > 2.5)
	_expect(failures, "forward preserve: not reversed", blended.z > 0.0)
	body.free()


func _sample_heading_stats(unit: Unit, seconds: float) -> Dictionary:
	var samples: int = 0
	var sign_flips: int = 0
	var yaw_reversals: int = 0
	var previous_lateral_sign: float = 0.0
	var previous_yaw_delta: float = 0.0
	var previous_yaw: float = NAN
	var start_msec: int = Time.get_ticks_msec()
	var duration_ms: int = int(seconds * 1000.0)

	while Time.get_ticks_msec() - start_msec < duration_ms:
		await get_tree().physics_frame
		if not is_instance_valid(unit):
			break
		var vel: Vector3 = Vector3(unit.velocity.x, 0.0, unit.velocity.z)
		if vel.length_squared() < 0.01:
			continue
		samples += 1
		var lateral_sign: float = signf(vel.x)
		if previous_lateral_sign != 0.0 and lateral_sign != 0.0 and lateral_sign != previous_lateral_sign:
			sign_flips += 1
		previous_lateral_sign = lateral_sign

		var facing: Vector3 = unit.get_facing_direction()
		if facing.length_squared() > 0.001:
			var yaw: float = atan2(facing.x, facing.z)
			if not is_nan(previous_yaw):
				var yaw_delta: float = angle_difference(previous_yaw, yaw)
				if previous_yaw_delta != 0.0 and signf(yaw_delta) != 0.0:
					if signf(yaw_delta) != signf(previous_yaw_delta) and absf(yaw_delta) > 0.02:
						yaw_reversals += 1
				previous_yaw_delta = yaw_delta
			previous_yaw = yaw

	return {
		"samples": samples,
		"sign_flips": sign_flips,
		"yaw_reversals": yaw_reversals,
	}


func _spawn_nav_harness() -> Dictionary:
	var root := Node3D.new()
	root.name = "NavHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)

	await get_tree().process_frame
	await _bake_nav_mesh(region, root)

	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	root.add_child(unit)
	unit.add_to_group(&"units")
	unit.team_id = 0
	await get_tree().process_frame
	await get_tree().physics_frame

	return {
		"root": root,
		"region": region,
		"unit": unit,
	}


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
		if unit._navigation_agent != null and UnitNavigation.can_use(unit._navigation_agent):
			return
		await get_tree().physics_frame


func _free_harness(harness: Dictionary) -> void:
	var root: Node = harness.get("root")
	if root != null and is_instance_valid(root):
		root.queue_free()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if ok:
		print("  PASS ", label)
	else:
		print("  FAIL ", label)
		failures.append(label)
