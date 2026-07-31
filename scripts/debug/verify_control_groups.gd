extends Node

## Headless verification for control groups, advanced selection helpers, idle workers, hero select.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_control_groups.tscn

const REPORT_PATH := "user://control_groups_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	ControlGroupManager.clear_all_groups()

	await _verify_assign_recall_and_shift_add(failures)
	await _verify_mixed_group_with_building(failures)
	await _verify_dead_unit_cleanup(failures)
	await _verify_destroyed_building_cleanup(failures)
	_verify_idle_worker_detection(failures)
	await _verify_hero_select_api(failures)
	_verify_match_reset_clears_groups(failures)
	_verify_selection_toggle_helpers(failures)

	var report: String
	if failures.is_empty():
		report = "PASS control_groups\n"
	else:
		report = "FAIL control_groups\n" + "\n".join(failures) + "\n"

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


func _make_selection_manager() -> Node:
	var selection_script: Script = load("res://scripts/systems/selection_manager.gd")
	var selection: Node = Node.new()
	selection.set_script(selection_script)
	selection.name = "SelectionManager"
	add_child(selection)
	return selection


func _verify_assign_recall_and_shift_add(failures: PackedStringArray) -> void:
	var selection := _make_selection_manager()
	var worker_a: Worker = WORKER_SCENE.instantiate() as Worker
	var worker_b: Worker = WORKER_SCENE.instantiate() as Worker
	var swordsman: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(worker_a)
	add_child(worker_b)
	add_child(swordsman)
	worker_a.global_position = Vector3(1, 0, 0)
	worker_b.global_position = Vector3(2, 0, 0)
	swordsman.global_position = Vector3(3, 0, 0)

	selection.apply_control_group_selection([worker_a, swordsman])
	_expect(failures, "assign prep: 2 selected", selection.selected_units.size() == 2)

	ControlGroupManager.assign_group(0, selection.get_control_group_members())
	_expect(failures, "assign group 1 size", ControlGroupManager.get_group_size(0) == 2)
	_expect(failures, "active group after assign", ControlGroupManager.get_active_group_index() == 0)

	selection.apply_control_group_selection([worker_b])
	ControlGroupManager.append_members(0, selection.get_control_group_members())
	_expect(failures, "shift-add group size", ControlGroupManager.get_group_size(0) == 3)

	selection._clear_selection()
	selection._clear_building_selection()
	var recalled: Array = ControlGroupManager.get_group_members(0)
	selection.apply_control_group_selection(recalled)
	_expect(failures, "recall selects 3", selection.selected_units.size() == 3)

	ControlGroupManager.clear_all_groups()
	worker_a.queue_free()
	worker_b.queue_free()
	swordsman.queue_free()
	selection.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_mixed_group_with_building(failures: PackedStringArray) -> void:
	var selection := _make_selection_manager()
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	add_child(worker)
	add_child(barracks)
	if barracks.is_in_group(&"enemy_buildings"):
		barracks.remove_from_group(&"enemy_buildings")

	ControlGroupManager.assign_group(2, [worker, barracks])
	_expect(failures, "mixed group size", ControlGroupManager.get_group_size(2) == 2)

	var members: Array = ControlGroupManager.get_group_members(2)
	selection.apply_control_group_selection(members)
	_expect(failures, "mixed recall prefers units", selection.selected_units.size() == 1)
	_expect(failures, "mixed recall unit is worker", selection.selected_units[0] == worker)

	worker.queue_free()
	# After worker removed from group via death/free, building-only recall should select building.
	await get_tree().process_frame
	await get_tree().process_frame
	var size_after_free: int = ControlGroupManager.get_group_size(2)
	_expect(
		failures,
		"building remains after unit free",
		size_after_free == 1
	)
	selection.apply_control_group_selection(ControlGroupManager.get_group_members(2))
	_expect(
		failures,
		"building-only recall",
		selection.selected_building == barracks
	)

	barracks.queue_free()
	selection.queue_free()
	ControlGroupManager.clear_all_groups()


func _verify_dead_unit_cleanup(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	ControlGroupManager.assign_group(4, [unit])
	_expect(failures, "pre-death group size", ControlGroupManager.get_group_size(4) == 1)
	unit.die()
	await get_tree().process_frame
	_expect(failures, "dead unit removed from group", ControlGroupManager.get_group_size(4) == 0)
	ControlGroupManager.clear_all_groups()


func _verify_destroyed_building_cleanup(failures: PackedStringArray) -> void:
	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	add_child(barracks)
	ControlGroupManager.assign_group(5, [barracks])
	_expect(failures, "pre-destroy group size", ControlGroupManager.get_group_size(5) == 1)
	barracks.destroyed.emit(barracks)
	barracks.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		failures,
		"destroyed building removed from group",
		ControlGroupManager.get_group_size(5) == 0
	)
	ControlGroupManager.clear_all_groups()


func _verify_idle_worker_detection(failures: PackedStringArray) -> void:
	var selection := _make_selection_manager()
	var idle_worker: Worker = WORKER_SCENE.instantiate() as Worker
	var busy_worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(idle_worker)
	add_child(busy_worker)
	busy_worker.issue_order(UnitOrder.move(Vector3(20, 0, 0)), false)

	_expect(failures, "idle worker flagged", idle_worker.is_player_idle())
	_expect(failures, "busy worker not idle", not busy_worker.is_player_idle())
	_expect(failures, "idle count is 1", selection.count_idle_player_workers() == 1)
	_expect(failures, "select idle succeeds", selection.select_next_idle_worker_and_focus())
	_expect(failures, "selected idle worker", selection.selected_units.has(idle_worker))

	idle_worker.queue_free()
	busy_worker.queue_free()
	selection.queue_free()


func _verify_hero_select_api(failures: PackedStringArray) -> void:
	var selection := _make_selection_manager()
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	await get_tree().process_frame
	_expect(failures, "hero select succeeds", selection.select_player_hero_and_focus())
	_expect(failures, "hero selected", selection.selected_units.size() == 1)
	_expect(failures, "selected is hero", selection.selected_units[0] is Hero)

	hero.die()
	hero.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(failures, "hero select fails after death", not selection.select_player_hero_and_focus())

	var respawned: Hero = HERO_SCENE.instantiate() as Hero
	add_child(respawned)
	await get_tree().process_frame
	_expect(failures, "hero select after respawn", selection.select_player_hero_and_focus())
	_expect(failures, "respawned hero selected", selection.selected_units.has(respawned))

	respawned.queue_free()
	selection.queue_free()
	await get_tree().process_frame


func _verify_match_reset_clears_groups(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	ControlGroupManager.assign_group(8, [worker])
	_expect(failures, "pre-reset has group", ControlGroupManager.get_group_size(8) == 1)
	ControlGroupManager.clear_all_groups()
	_expect(failures, "reset clears groups", ControlGroupManager.get_group_size(8) == 0)
	_expect(failures, "reset clears active", ControlGroupManager.get_active_group_index() == -1)
	worker.queue_free()


func _verify_selection_toggle_helpers(failures: PackedStringArray) -> void:
	var selection := _make_selection_manager()
	var a: Worker = WORKER_SCENE.instantiate() as Worker
	var b: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(a)
	add_child(b)
	selection.apply_control_group_selection([a])
	selection._toggle_unit_in_selection(b)
	_expect(failures, "shift-add via toggle", selection.selected_units.size() == 2)
	selection._toggle_unit_in_selection(a)
	_expect(failures, "shift-remove via toggle", selection.selected_units.size() == 1)
	_expect(failures, "remaining is b", selection.selected_units[0] == b)
	a.queue_free()
	b.queue_free()
	selection.queue_free()
