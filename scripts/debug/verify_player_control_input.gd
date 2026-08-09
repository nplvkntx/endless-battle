extends Node

## Space hold-follow + ability-click selection ownership regressions.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_player_control_input.tscn

const REPORT_PATH := "user://player_control_input_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")
const CAMERA_SCRIPT: Script = preload("res://scripts/systems/camera_controller.gd")
const SELECTION_SCRIPT: Script = preload("res://scripts/systems/selection_manager.gd")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_player_control_input: start")
	CombatTargetValidation.reset_match_state()
	HeroAbilityTargetingController.cancel_targeting()
	HeroProgressionStore.clear()

	await _verify_space_press_centers(failures)
	await _verify_space_hold_follows(failures)
	await _verify_space_release_frees_camera(failures)
	await _verify_space_preserves_selection(failures)
	await _verify_ability_valid_click_keeps_selection(failures)
	await _verify_ability_invalid_click_keeps_selection(failures)
	await _verify_ability_click_on_unit_keeps_selection(failures)
	await _verify_ability_drag_blocked(failures)
	await _verify_ability_right_click_cancel(failures)

	Input.action_release(&"focus_hero")
	HeroAbilityTargetingController.cancel_targeting()
	HeroProgressionStore.clear()

	var report: String
	if failures.is_empty():
		report = "PASS player_control_input\n"
	else:
		report = "FAIL player_control_input\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)


func _make_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.set_script(CAMERA_SCRIPT)
	camera.current = true
	camera.edge_margin_pixels = 0.0
	add_child(camera)
	return camera


func _set_selection_units(selection: Node, units: Array[Unit]) -> void:
	selection._set_selected_units(units)


func _make_selection() -> Node:
	var selection := Node.new()
	selection.name = "SelectionManager"
	selection.set_script(SELECTION_SCRIPT)
	add_child(selection)
	return selection


func _spawn_player_hero(position: Vector3) -> Hero:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = position
	hero.team_id = 0
	if not hero.is_in_group(&"heroes"):
		hero.add_to_group(&"heroes")
	HeroProgressionStore.register_living_hero(hero)
	return hero


func _selection_ids(selection: Node) -> Array:
	var ids: Array = []
	if selection == null or not ("selected_units" in selection):
		return ids
	for unit_ref: Variant in selection.selected_units:
		if unit_ref != null and is_instance_valid(unit_ref):
			ids.append((unit_ref as Object).get_instance_id())
	ids.sort()
	return ids


func _make_mouse(button: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	event.global_position = position
	return event


func _verify_space_press_centers(failures: PackedStringArray) -> void:
	print("test: space press centers")
	var camera: Camera3D = _make_camera()
	camera.global_position = Vector3(40, 18, 40)
	var hero: Hero = _spawn_player_hero(Vector3(5, 0, -4))
	await get_tree().process_frame

	Input.action_press(&"focus_hero")
	camera._process(0.016)
	_expect(
		failures,
		"space press centers X",
		is_equal_approx(camera.global_position.x, hero.global_position.x)
	)
	_expect(
		failures,
		"space press centers Z",
		is_equal_approx(camera.global_position.z, hero.global_position.z)
	)
	_expect(failures, "space press preserves camera Y", is_equal_approx(camera.global_position.y, 18.0))

	Input.action_release(&"focus_hero")
	hero.queue_free()
	camera.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_space_hold_follows(failures: PackedStringArray) -> void:
	print("test: space hold follows A->B->C")
	var camera: Camera3D = _make_camera()
	camera.global_position = Vector3(20, 16, 20)
	var hero: Hero = _spawn_player_hero(Vector3(1, 0, 1))
	await get_tree().process_frame

	Input.action_press(&"focus_hero")
	var path: Array[Vector3] = [
		Vector3(1, 0, 1),
		Vector3(8, 0, -3),
		Vector3(-6, 0, 9),
	]
	for point: Vector3 in path:
		hero.global_position = point
		camera._process(0.016)
		_expect(
			failures,
			"space hold follows (%.0f,%.0f)" % [point.x, point.z],
			is_equal_approx(camera.global_position.x, point.x)
			and is_equal_approx(camera.global_position.z, point.z)
		)

	Input.action_release(&"focus_hero")
	hero.queue_free()
	camera.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_space_release_frees_camera(failures: PackedStringArray) -> void:
	print("test: space release frees camera")
	var camera: Camera3D = _make_camera()
	camera.global_position = Vector3(0, 15, 0)
	var hero: Hero = _spawn_player_hero(Vector3(4, 0, 4))
	await get_tree().process_frame

	Input.action_press(&"focus_hero")
	camera._process(0.016)
	_expect(
		failures,
		"space hold centers before release",
		is_equal_approx(camera.global_position.x, hero.global_position.x)
		and is_equal_approx(camera.global_position.z, hero.global_position.z)
	)
	Input.action_release(&"focus_hero")

	hero.global_position = Vector3(12, 0, -8)
	camera._process(0.016)
	_expect(
		failures,
		"space release stops follow",
		not (
			is_equal_approx(camera.global_position.x, hero.global_position.x)
			and is_equal_approx(camera.global_position.z, hero.global_position.z)
		)
	)

	## Manual pan still works after release (simulate WASD via direct move helper path).
	camera.focus_on_world_position(Vector3(2, 0, 2))
	_expect(
		failures,
		"space release allows manual recenter",
		is_equal_approx(camera.global_position.x, 2.0)
		and is_equal_approx(camera.global_position.z, 2.0)
	)

	hero.queue_free()
	camera.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_space_preserves_selection(failures: PackedStringArray) -> void:
	print("test: space preserves multi-selection")
	var selection: Node = _make_selection()
	var camera: Camera3D = _make_camera()
	camera.global_position = Vector3(10, 14, 10)
	var hero: Hero = _spawn_player_hero(Vector3.ZERO)
	var units: Array[Unit] = []
	for i in range(5):
		var soldier: Unit = SPEARMAN_SCENE.instantiate() as Unit
		add_child(soldier)
		soldier.global_position = Vector3(float(i) + 1.0, 0, 0)
		soldier.team_id = 0
		units.append(soldier)
	await get_tree().process_frame

	var selected: Array[Unit] = [hero]
	selected.append_array(units)
	_set_selection_units(selection, selected)
	var before: Array = _selection_ids(selection)

	Input.action_press(&"focus_hero")
	camera._process(0.016)
	hero.global_position = Vector3(3, 0, -2)
	camera._process(0.016)
	Input.action_release(&"focus_hero")
	camera._process(0.016)

	_expect(failures, "space hold keeps selection size", selection.selected_units.size() == 6)
	_expect(failures, "space hold keeps selection identity", _selection_ids(selection) == before)

	for unit in units:
		unit.queue_free()
	hero.queue_free()
	camera.queue_free()
	selection.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _unlock_ability(hero: MeleeHero, ability_id: StringName) -> void:
	hero.level = 16
	hero.ability_points = 20
	while hero.can_learn_ability(ability_id):
		hero.try_learn_ability(ability_id, false)


func _verify_ability_valid_click_keeps_selection(failures: PackedStringArray) -> void:
	print("test: valid ability click keeps selection")
	var selection: Node = _make_selection()
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var soldier_a: Unit = SPEARMAN_SCENE.instantiate() as Unit
	var soldier_b: Unit = SPEARMAN_SCENE.instantiate() as Unit
	var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(hero)
	add_child(soldier_a)
	add_child(soldier_b)
	add_child(enemy)
	await get_tree().process_frame
	hero.global_position = Vector3.ZERO
	soldier_a.global_position = Vector3(1, 0, 0)
	soldier_b.global_position = Vector3(2, 0, 0)
	enemy.global_position = Vector3(3, 0, 0)
	hero.team_id = 0
	HeroProgressionStore.register_living_hero(hero)
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_E)

	var selected: Array[Unit] = [hero, soldier_a, soldier_b]
	_set_selection_units(selection, selected)
	var before: Array = _selection_ids(selection)
	HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_E)
	_expect(failures, "valid path: targeting armed", HeroAbilityTargetingController.is_targeting())

	## Press while targeting arms the latch, then simulate successful cast clearing targeting
	## before release (the exact leak that previously reselected on mouse-up).
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, true, Vector2(100, 100)))
	_expect(failures, "valid path: latch owned after press", selection._ability_owns_left_mouse)
	HeroAbilityTargetingController.cancel_targeting()
	_expect(failures, "valid path: targeting cleared like successful cast", not HeroAbilityTargetingController.is_targeting())
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, false, Vector2(100, 100)))

	_expect(failures, "valid path: selection size unchanged", selection.selected_units.size() == 3)
	_expect(failures, "valid path: selection identity unchanged", _selection_ids(selection) == before)
	_expect(failures, "valid path: latch cleared after release", not selection._ability_owns_left_mouse)

	HeroAbilityTargetingController.cancel_targeting()
	enemy.queue_free()
	soldier_b.queue_free()
	soldier_a.queue_free()
	hero.queue_free()
	selection.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_ability_invalid_click_keeps_selection(failures: PackedStringArray) -> void:
	print("test: invalid ability click keeps selection + targeting")
	var selection: Node = _make_selection()
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var soldiers: Array[Unit] = []
	for i in range(5):
		var soldier: Unit = SPEARMAN_SCENE.instantiate() as Unit
		add_child(soldier)
		soldier.global_position = Vector3(float(i) + 1.0, 0, 0)
		soldier.team_id = 0
		soldiers.append(soldier)
	add_child(hero)
	await get_tree().process_frame
	hero.global_position = Vector3.ZERO
	hero.team_id = 0
	HeroProgressionStore.register_living_hero(hero)
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_E)

	var selected: Array[Unit] = [hero]
	selected.append_array(soldiers)
	_set_selection_units(selection, selected)
	var before: Array = _selection_ids(selection)

	HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_E)
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, true, Vector2(12, 12)))
	_expect(failures, "invalid path: targeting stays armed", HeroAbilityTargetingController.is_targeting())
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, false, Vector2(12, 12)))

	_expect(failures, "invalid path: selection size unchanged", selection.selected_units.size() == 6)
	_expect(failures, "invalid path: selection identity unchanged", _selection_ids(selection) == before)

	HeroAbilityTargetingController.cancel_targeting()
	for soldier in soldiers:
		soldier.queue_free()
	hero.queue_free()
	selection.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_ability_click_on_unit_keeps_selection(failures: PackedStringArray) -> void:
	print("test: click another unit while targeting does not reselect")
	var selection: Node = _make_selection()
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var army: Unit = SPEARMAN_SCENE.instantiate() as Unit
	var other: Unit = SPEARMAN_SCENE.instantiate() as Unit
	add_child(hero)
	add_child(army)
	add_child(other)
	await get_tree().process_frame
	hero.global_position = Vector3.ZERO
	army.global_position = Vector3(1, 0, 0)
	other.global_position = Vector3(4, 0, 0)
	hero.team_id = 0
	army.team_id = 0
	other.team_id = 0
	HeroProgressionStore.register_living_hero(hero)
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_Q)

	var selected: Array[Unit] = [hero, army]
	_set_selection_units(selection, selected)
	var before: Array = _selection_ids(selection)
	HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_Q)

	## Ground/self ability click path — SelectionManager must consume regardless of hit.
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, true, Vector2(200, 200)))
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, false, Vector2(200, 200)))

	_expect(failures, "unit click path: selection unchanged", _selection_ids(selection) == before)

	HeroAbilityTargetingController.cancel_targeting()
	other.queue_free()
	army.queue_free()
	hero.queue_free()
	selection.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_ability_drag_blocked(failures: PackedStringArray) -> void:
	print("test: drag while targeting does not start selection box")
	var selection: Node = _make_selection()
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var army: Unit = SPEARMAN_SCENE.instantiate() as Unit
	add_child(hero)
	add_child(army)
	await get_tree().process_frame
	hero.team_id = 0
	army.team_id = 0
	HeroProgressionStore.register_living_hero(hero)
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_E)
	var selected: Array[Unit] = [hero, army]
	_set_selection_units(selection, selected)
	var before: Array = _selection_ids(selection)

	HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_E)
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, true, Vector2(10, 10)))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(80, 80)
	motion.global_position = Vector2(80, 80)
	selection._unhandled_input(motion)
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_LEFT, false, Vector2(80, 80)))

	_expect(failures, "drag path: not dragging", not selection._is_dragging)
	_expect(failures, "drag path: left not held", not selection._left_button_down)
	_expect(failures, "drag path: selection unchanged", _selection_ids(selection) == before)

	HeroAbilityTargetingController.cancel_targeting()
	army.queue_free()
	hero.queue_free()
	selection.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_ability_right_click_cancel(failures: PackedStringArray) -> void:
	print("test: right click cancels targeting and keeps selection")
	var selection: Node = _make_selection()
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var army: Unit = SPEARMAN_SCENE.instantiate() as Unit
	add_child(hero)
	add_child(army)
	await get_tree().process_frame
	hero.team_id = 0
	army.team_id = 0
	HeroProgressionStore.register_living_hero(hero)
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_E)
	var selected: Array[Unit] = [hero, army]
	_set_selection_units(selection, selected)
	var before: Array = _selection_ids(selection)

	HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_E)
	_expect(failures, "right cancel: targeting armed", HeroAbilityTargetingController.is_targeting())
	selection._unhandled_input(_make_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(50, 50)))
	_expect(failures, "right cancel: targeting cleared", not HeroAbilityTargetingController.is_targeting())
	_expect(failures, "right cancel: selection unchanged", _selection_ids(selection) == before)

	army.queue_free()
	hero.queue_free()
	selection.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame
