extends Node

## Headless verification for Cossacks-style military formations.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_formations.tscn

const REPORT_PATH := "user://formations_verify_result.txt"
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const LIGHT_CAVALRY_SCENE: PackedScene = preload("res://scenes/units/light_cavalry.tscn")
const CANNON_SCENE: PackedScene = preload("res://scenes/units/cannon.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	FormationManager.clear_all()

	_verify_role_metadata(failures)
	_verify_layout_presets(failures)
	_verify_icons(failures)
	await _verify_square_5(failures)
	await _verify_line_15(failures)
	await _verify_arrow_30(failures)
	await _verify_hollow_50(failures)
	await _verify_heroes_excluded(failures)
	await _verify_split_and_dissolve(failures)
	await _verify_role_ordering(failures)
	await _verify_ai_size_choice(failures)
	await _verify_movement_slots_stable(failures)
	_verify_match_reset(failures)

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
	return unit


func _verify_role_metadata(failures: PackedStringArray) -> void:
	var spear: Unit = SPEARMAN_SCENE.instantiate() as Unit
	var sword: Unit = SWORDSMAN_SCENE.instantiate() as Unit
	var archer: Unit = ARCHER_SCENE.instantiate() as Unit
	var cav: Unit = LIGHT_CAVALRY_SCENE.instantiate() as Unit
	var cannon: Unit = CANNON_SCENE.instantiate() as Unit
	var hero: Unit = HERO_SCENE.instantiate() as Unit
	var worker: Unit = WORKER_SCENE.instantiate() as Unit

	_expect(failures, "spearman role pike", UnitFormationRole.get_role(spear) == UnitFormationRole.Role.PIKE)
	_expect(failures, "swordsman role swords", UnitFormationRole.get_role(sword) == UnitFormationRole.Role.SWORDS)
	_expect(failures, "archer role archer", UnitFormationRole.get_role(archer) == UnitFormationRole.Role.ARCHER)
	_expect(failures, "cavalry role light", UnitFormationRole.get_role(cav) == UnitFormationRole.Role.LIGHT_CAVALRY)
	_expect(failures, "cannon role siege", UnitFormationRole.get_role(cannon) == UnitFormationRole.Role.SIEGE)
	_expect(failures, "hero eligible false", not UnitFormationRole.is_formation_eligible(hero))
	_expect(failures, "worker eligible false", not UnitFormationRole.is_formation_eligible(worker))
	_expect(failures, "spearman eligible", UnitFormationRole.is_formation_eligible(spear))
	_expect(failures, "cannon eligible", UnitFormationRole.is_formation_eligible(cannon))

	spear.free()
	sword.free()
	archer.free()
	cav.free()
	cannon.free()
	hero.free()
	worker.free()


func _verify_layout_presets(failures: PackedStringArray) -> void:
	for size_preset: int in FormationLayout.SIZE_PRESETS:
		for shape: int in range(4):
			var slots: Array[Dictionary] = FormationLayout.get_or_build_slots(
				shape as FormationLayout.Shape,
				size_preset
			)
			_expect(
				failures,
				"layout slots shape=%d size=%d" % [shape, size_preset],
				slots.size() == size_preset
			)
	var cached: Array[Dictionary] = FormationLayout.get_or_build_slots(
		FormationLayout.Shape.SQUARE,
		15
	)
	_expect(failures, "layout cache reuse", cached.size() == 15)


func _verify_icons(failures: PackedStringArray) -> void:
	for shape: int in range(4):
		var tex: Texture2D = FormationIcons.get_shape_icon(shape as FormationLayout.Shape)
		_expect(failures, "shape icon %d" % shape, tex != null)
	for size_preset: int in FormationLayout.SIZE_PRESETS:
		_expect(failures, "size icon %d" % size_preset, FormationIcons.get_size_icon(size_preset) != null)
	_expect(failures, "dissolve icon", FormationIcons.get_dissolve_icon() != null)


func _verify_square_5(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.SQUARE)
	FormationManager.set_player_size(5)
	var units: Array = []
	for i: int in range(5):
		units.append(_spawn(SPEARMAN_SCENE, Vector3(float(i), 0, 0)))
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.form_selected_units(units)
	_expect(failures, "square5 one formation", ids.size() == 1)
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	_expect(failures, "square5 members", group != null and group.member_count() == 5)
	_expect(failures, "square5 shape", group != null and group.shape == FormationLayout.Shape.SQUARE)
	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_line_15(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.LINE)
	FormationManager.set_player_size(15)
	var units: Array = []
	for i: int in range(15):
		var scene: PackedScene = ARCHER_SCENE if i % 3 == 0 else SWORDSMAN_SCENE
		units.append(_spawn(scene, Vector3(float(i % 5), 0, float(i / 5))))
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.form_selected_units(units)
	_expect(failures, "line15 one formation", ids.size() == 1)
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	_expect(failures, "line15 members", group != null and group.member_count() == 15)
	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_arrow_30(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.ARROW)
	FormationManager.set_player_size(30)
	var units: Array = []
	for i: int in range(30):
		units.append(_spawn(SWORDSMAN_SCENE, Vector3(float(i % 6) * 1.2, 0, float(i / 6) * 1.2)))
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.form_selected_units(units)
	_expect(failures, "arrow30 one formation", ids.size() == 1)
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	_expect(failures, "arrow30 members", group != null and group.member_count() == 30)
	var slots: Array[Vector3] = group.get_all_world_slots()
	_expect(failures, "arrow30 slot count", slots.size() == 30)
	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_hollow_50(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.HOLLOW_SQUARE)
	FormationManager.set_player_size(50)
	var units: Array = []
	for i: int in range(50):
		units.append(_spawn(SPEARMAN_SCENE, Vector3(float(i % 10) * 1.1, 0, float(i / 10) * 1.1)))
	await get_tree().process_frame
	var start_usec: int = Time.get_ticks_usec()
	var ids: Array[int] = FormationManager.form_selected_units(units)
	var elapsed_usec: int = Time.get_ticks_usec() - start_usec
	_expect(failures, "hollow50 one formation", ids.size() == 1)
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	_expect(failures, "hollow50 members", group != null and group.member_count() == 50)
	_expect(failures, "hollow50 form perf <250ms", elapsed_usec < 250000)
	var slots: Array[Vector3] = group.get_all_world_slots()
	var near_center: int = 0
	for slot: Vector3 in slots:
		var dx: float = slot.x - group.anchor.x
		var dz: float = slot.z - group.anchor.z
		if dx * dx + dz * dz < 1.0:
			near_center += 1
	_expect(failures, "hollow50 center mostly clear", near_center <= 4)
	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_heroes_excluded(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.SQUARE)
	FormationManager.set_player_size(15)
	var units: Array = []
	for i: int in range(8):
		units.append(_spawn(SWORDSMAN_SCENE, Vector3(float(i), 0, 0)))
	var hero: Unit = _spawn(HERO_SCENE, Vector3(10, 0, 0))
	units.append(hero)
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.form_selected_units(units)
	_expect(failures, "hero mix creates formation", ids.size() == 1)
	_expect(failures, "hero not in formation", not FormationManager.is_unit_in_formation(hero))
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	_expect(failures, "hero mix membership 8", group != null and group.member_count() == 8)
	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_split_and_dissolve(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.SQUARE)
	FormationManager.set_player_size(15)
	var units: Array = []
	for i: int in range(34):
		units.append(_spawn(SWORDSMAN_SCENE, Vector3(float(i % 8), 0, float(i / 8))))
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.form_selected_units(units)
	_expect(failures, "34/15 splits into 3", ids.size() == 3)
	var counts: Array[int] = []
	for fid: int in ids:
		counts.append(FormationManager.get_formation(fid).member_count())
	counts.sort()
	_expect(
		failures,
		"split sizes 4,15,15",
		counts.size() == 3 and counts[0] == 4 and counts[1] == 15 and counts[2] == 15
	)

	FormationManager.dissolve_selected_formations(units)
	var still_formed: int = 0
	for unit: Variant in units:
		if FormationManager.is_unit_in_formation(unit as Node):
			still_formed += 1
	_expect(failures, "dissolve clears membership", still_formed == 0)

	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_role_ordering(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.LINE)
	FormationManager.set_player_size(15)
	var units: Array = []
	units.append(_spawn(CANNON_SCENE, Vector3(0, 0, 0)))
	units.append(_spawn(ARCHER_SCENE, Vector3(1, 0, 0)))
	units.append(_spawn(ARCHER_SCENE, Vector3(2, 0, 0)))
	units.append(_spawn(SPEARMAN_SCENE, Vector3(3, 0, 0)))
	units.append(_spawn(SPEARMAN_SCENE, Vector3(4, 0, 0)))
	units.append(_spawn(SWORDSMAN_SCENE, Vector3(5, 0, 0)))
	units.append(_spawn(LIGHT_CAVALRY_SCENE, Vector3(6, 0, 0)))
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.form_selected_units(units)
	_expect(failures, "role order formation created", ids.size() == 1)
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	group.anchor = Vector3(20, 0, 20)
	group.forward = Vector3(0, 0, 1)
	group.needs_reassign = true
	group.ensure_slots_assigned()

	var spear_z: float = -999.0
	var archer_z: float = 999.0
	var cannon_z: float = 999.0
	for unit: Variant in group.get_alive_members():
		var slot: Vector3 = group.get_world_slot_for_unit(unit as Node)
		var role: UnitFormationRole.Role = UnitFormationRole.get_role(unit as Node)
		if role == UnitFormationRole.Role.PIKE:
			spear_z = maxf(spear_z, slot.z)
		elif role == UnitFormationRole.Role.ARCHER:
			archer_z = minf(archer_z, slot.z)
		elif role == UnitFormationRole.Role.SIEGE:
			cannon_z = minf(cannon_z, slot.z)

	_expect(failures, "pikemen ahead of archers", spear_z > archer_z)
	_expect(failures, "cannons behind/at rear", cannon_z <= archer_z + 0.01 or cannon_z < spear_z)

	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_ai_size_choice(failures: PackedStringArray) -> void:
	_expect(failures, "ai size tiny->5", FormationLayout.choose_ai_size(4) == 5)
	_expect(failures, "ai size mid->15", FormationLayout.choose_ai_size(12) == 15)
	_expect(failures, "ai size large->30", FormationLayout.choose_ai_size(28) == 30)
	_expect(failures, "ai size army->50", FormationLayout.choose_ai_size(45) == 50)
	_expect(
		failures,
		"ai attack uses arrow",
		FormationLayout.choose_ai_shape(&"ATTACKING", false, false) == FormationLayout.Shape.ARROW
	)
	_expect(
		failures,
		"ai defend uses line",
		FormationLayout.choose_ai_shape(&"DEFENDING", false, true) == FormationLayout.Shape.LINE
	)
	_expect(
		failures,
		"ai defend siege hollow",
		FormationLayout.choose_ai_shape(&"DEFENDING", true, true) == FormationLayout.Shape.HOLLOW_SQUARE
	)

	FormationManager.clear_all()
	var units: Array = []
	for i: int in range(12):
		units.append(_spawn(SWORDSMAN_SCENE, Vector3(float(i), 0, 0)))
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.ai_ensure_formations(units, &"ATTACKING", false)
	_expect(failures, "ai ensure creates", not ids.is_empty())
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	_expect(failures, "ai attack shape arrow", group != null and group.shape == FormationLayout.Shape.ARROW)
	_expect(failures, "ai size 15 for 12", group != null and group.size_preset == 15)

	var ids2: Array[int] = FormationManager.ai_ensure_formations(units, &"ATTACKING", false)
	_expect(failures, "ai no duplicate reissue", ids2 == ids)

	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_movement_slots_stable(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	FormationManager.set_player_shape(FormationLayout.Shape.SQUARE)
	FormationManager.set_player_size(15)
	var units: Array = []
	for i: int in range(10):
		units.append(_spawn(SWORDSMAN_SCENE, Vector3(float(i), 0, 0)))
	await get_tree().process_frame
	var ids: Array[int] = FormationManager.form_selected_units(units)
	var group: FormationGroup = FormationManager.get_formation(ids[0])
	var version_before: int = group.layout_version
	var slot_a: Vector3 = group.get_world_slot_for_unit(units[0] as Node)
	group.ensure_slots_assigned()
	var slot_b: Vector3 = group.get_world_slot_for_unit(units[0] as Node)
	_expect(failures, "slots stable without reassign", slot_a.is_equal_approx(slot_b))
	_expect(failures, "layout version stable", group.layout_version == version_before)

	FormationManager.issue_formation_ground_order(units, Vector3(30, 0, 30), &"move", false)
	_expect(failures, "move updates anchor", group.anchor.distance_to(Vector3(30, 0, 30)) < 0.1)

	for unit: Variant in units:
		(unit as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_match_reset(failures: PackedStringArray) -> void:
	FormationManager.clear_all()
	_expect(
		failures,
		"reset clears formations",
		int(FormationManager.get_selection_formation_summary([]).get("formation_count", -1)) == 0
	)
