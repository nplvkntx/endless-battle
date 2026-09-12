extends Node

## Headless checks for automatic PlayerRouteNavigation army formations.
## Godot --headless --path <project> --scene res://scenes/debug/verify_formations.tscn

const REPORT_PATH := "user://formations_verify_result.txt"
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	PlayerRouteNavigation.clear_all()

	_verify_no_legacy_manager(failures)
	_verify_shape_choice(failures)
	_verify_layout_geometry(failures)
	await _verify_group_slots_and_hero(failures)
	await _verify_assignment_stable(failures)
	await _verify_one_path_calc(failures)
	await _verify_slot_compresses_off_building(failures)
	await _verify_corner_occupancy_inflate(failures)

	var report: String
	if failures.is_empty():
		report = "PASS formations\n"
	else:
		report = "FAIL formations\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)


func _spawn(scene: PackedScene, pos: Vector3) -> Unit:
	var unit: Unit = scene.instantiate() as Unit
	add_child(unit)
	unit.global_position = pos
	unit.team_id = TeamVisuals.PLAYER_TEAM_ID
	return unit


func _verify_no_legacy_manager(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"FormationManager autoload removed",
		not Engine.has_singleton("FormationManager")
	)


func _verify_shape_choice(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"1-5 is line",
		PlayerRouteNavigation.choose_formation_shape(4) == PlayerRouteNavigation.FORMATION_SHAPE_LINE
	)
	_expect(
		failures,
		"6-15 is rectangle",
		PlayerRouteNavigation.choose_formation_shape(8) == PlayerRouteNavigation.FORMATION_SHAPE_RECTANGLE
	)
	_expect(
		failures,
		"16+ is square",
		PlayerRouteNavigation.choose_formation_shape(16) == PlayerRouteNavigation.FORMATION_SHAPE_SQUARE
	)


func _verify_layout_geometry(failures: PackedStringArray) -> void:
	var line: Array[Vector3] = PlayerRouteNavigation.build_formation_locals(4)
	_expect(failures, "line count 4", line.size() == 4)
	var line_depth: float = 0.0
	var line_width: float = 0.0
	for local: Vector3 in line:
		line_depth = maxf(line_depth, absf(local.z))
		line_width = maxf(line_width, absf(local.x))
	_expect(failures, "line is single rank", line_depth < 0.01)
	_expect(failures, "line has lateral spacing", line_width >= PlayerRouteNavigation.SLOT_SPACING * 1.4)

	var rect: Array[Vector3] = PlayerRouteNavigation.build_formation_locals(8)
	_expect(failures, "rectangle count 8", rect.size() == 8)
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for local: Vector3 in rect:
		min_x = minf(min_x, local.x)
		max_x = maxf(max_x, local.x)
		min_z = minf(min_z, local.z)
		max_z = maxf(max_z, local.z)
	_expect(failures, "rectangle wider than deep", (max_x - min_x) + 0.01 >= (max_z - min_z))

	var square: Array[Vector3] = PlayerRouteNavigation.build_formation_locals(16)
	_expect(failures, "square count 16", square.size() == 16)
	min_x = INF
	max_x = -INF
	min_z = INF
	max_z = -INF
	for local: Vector3 in square:
		min_x = minf(min_x, local.x)
		max_x = maxf(max_x, local.x)
		min_z = minf(min_z, local.z)
		max_z = maxf(max_z, local.z)
	var width: float = max_x - min_x
	var depth: float = max_z - min_z
	_expect(failures, "square-ish aspect", absf(width - depth) <= PlayerRouteNavigation.SLOT_SPACING * 1.05)


func _verify_group_slots_and_hero(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var units: Array = []
	var hero: Unit = _spawn(HERO_SCENE, Vector3(-18.0, 0.0, -8.0))
	units.append(hero)
	for i: int in 7:
		units.append(_spawn(SPEARMAN_SCENE, Vector3(-18.0 + float(i) * 1.1, 0.0, -10.0)))
	await get_tree().process_frame

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units,
		Vector3(18.0, 0.0, 10.0),
		&"move",
		false
	)
	_expect(failures, "hero group handled", result.get("handled", false))
	var slots: Array = result.get("slot_targets", []) as Array
	_expect(failures, "hero group slot count", slots.size() == units.size())

	if slots.size() == units.size():
		var dest := Vector3(18.0, 0.0, 10.0)
		var origin := Vector3(-18.0, 0.0, -9.0)
		var forward: Vector3 = dest - origin
		forward.y = 0.0
		forward = forward.normalized()
		var hero_slot: Vector3 = hero.get_player_squad_final_arrival()
		var hero_forward: float = (hero_slot - dest).dot(forward)
		var best_forward: float = -INF
		for slot_v: Variant in slots:
			var slot: Vector3 = slot_v as Vector3
			best_forward = maxf(best_forward, (slot - dest).dot(forward))
		_expect(
			failures,
			"hero near front rank",
			hero_forward >= best_forward - PlayerRouteNavigation.SLOT_SPACING * 0.6
		)
		var unique: Dictionary = {}
		for slot_v: Variant in slots:
			var slot: Vector3 = slot_v as Vector3
			var key: String = "%.2f,%.2f" % [slot.x, slot.z]
			unique[key] = true
		_expect(failures, "slots are unique", unique.size() == slots.size())

	for unit_v: Variant in units:
		(unit_v as Node).queue_free()
	await get_tree().process_frame


func _verify_assignment_stable(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var units: Array = []
	for i: int in 6:
		units.append(_spawn(SPEARMAN_SCENE, Vector3(-12.0 + float(i) * 1.2, 0.0, -6.0)))
	await get_tree().process_frame

	var first: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units, Vector3(14.0, 0.0, 8.0), &"move", false
	)
	var first_slots: Array = first.get("slot_targets", []) as Array
	var second: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units, Vector3(14.0, 0.0, 8.0), &"move", false
	)
	var second_slots: Array = second.get("slot_targets", []) as Array
	_expect(failures, "stable slot count", first_slots.size() == second_slots.size())
	if first_slots.size() == second_slots.size():
		var same := true
		for i: int in first_slots.size():
			var a: Vector3 = first_slots[i] as Vector3
			var b: Vector3 = second_slots[i] as Vector3
			if Vector2(a.x - b.x, a.z - b.z).length() > 0.05:
				same = false
				break
		_expect(failures, "same command regenerates same slots", same)

	for unit_v: Variant in units:
		(unit_v as Node).queue_free()
	await get_tree().process_frame


func _verify_one_path_calc(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var units: Array = []
	for i: int in 9:
		units.append(_spawn(SPEARMAN_SCENE, Vector3(-16.0 + float(i) * 1.1, 0.0, -12.0)))
	await get_tree().process_frame

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units, Vector3(16.0, 0.0, 12.0), &"attack_move", false
	)
	_expect(failures, "attack-move handled", result.get("handled", false))
	_expect(failures, "one shared path", int(result.get("path_calculations", -1)) == 1)

	for unit_v: Variant in units:
		(unit_v as Node).queue_free()
	await get_tree().process_frame


func _verify_slot_compresses_off_building(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: Building = CC_SCENE.instantiate() as Building
	add_child(cc)
	cc.global_position = Vector3(12.0, 0.0, 0.0)
	cc.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(cc)

	var units: Array = []
	for i: int in 8:
		units.append(_spawn(SPEARMAN_SCENE, Vector3(-16.0 + float(i) * 1.1, 0.0, 0.0)))
	await get_tree().process_frame

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units, cc.global_position, &"move", false
	)
	_expect(failures, "compress command handled", result.get("handled", false))
	var slots: Array = result.get("slot_targets", []) as Array
	for slot_v: Variant in slots:
		var slot: Vector3 = slot_v as Vector3
		_expect(
			failures,
			"slot walkable after compress",
			PlayerRouteNavigation.is_world_walkable(slot)
		)

	for unit_v: Variant in units:
		(unit_v as Node).queue_free()
	cc.queue_free()
	await get_tree().process_frame


func _verify_corner_occupancy_inflate(failures: PackedStringArray) -> void:
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var cc: Building = CC_SCENE.instantiate() as Building
	add_child(cc)
	cc.global_position = Vector3(0.0, 0.0, 0.0)
	cc.set_completed()
	await get_tree().process_frame
	PlayerRouteNavigation.register_static_obstacle(cc)

	var half: Vector3 = cc.get_rts_occupancy_half_extents()
	var inside: Vector3 = Vector3(half.x * 0.4, 0.0, half.z * 0.4)
	_expect(
		failures,
		"building interior blocked",
		not PlayerRouteNavigation.is_world_walkable(inside)
	)
	var around: PackedVector3Array = PlayerRouteNavigation.find_path(
		Vector3(-12.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 12.0)
	)
	_expect(failures, "path exists around building", around.size() >= 2)
	var clipped := false
	for point: Vector3 in around:
		if cc.is_position_inside_footprint(point, 0.05):
			clipped = true
			break
	_expect(failures, "route does not clip building interior", not clipped)

	cc.queue_free()
	await get_tree().process_frame
