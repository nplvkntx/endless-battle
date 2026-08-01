extends Node

## Headless verification: selected building command UI refreshes on construction completion.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_construction_ui_refresh.tscn

const REPORT_PATH := "user://construction_ui_refresh_verify_result.txt"
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")

const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const ACADEMY_SCENE: PackedScene = preload("res://scenes/buildings/academy.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/buildings/shop.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_construction_ui_refresh: start")

	_verify_construction_completed_signal_once(failures)
	await _verify_command_bar_refresh_for_types(failures)
	await _verify_selection_change_before_completion(failures)
	await _verify_destroy_selected_unfinished(failures)

	var report: String
	if failures.is_empty():
		report = "PASS construction_ui_refresh\n"
	else:
		report = "FAIL construction_ui_refresh\n" + "\n".join(failures) + "\n"

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
		push_error("FAIL: " + label)


func _make_selection_manager() -> Node:
	var selection_script: Script = load("res://scripts/systems/selection_manager.gd")
	var selection: Node = Node.new()
	selection.set_script(selection_script)
	selection.name = "SelectionManager"
	add_child(selection)
	return selection


func _make_command_ui(selection: Node) -> Dictionary:
	var hud: Node = HUD_SCENE.instantiate()
	var command_bar: PanelContainer = hud.get_node("CommandBar") as PanelContainer
	hud.remove_child(command_bar)
	hud.free()

	command_bar.selection_manager_path = NodePath("../SelectionManager")
	var panel: Control = command_bar.get_node(
		"MarginContainer/VBoxContainer/SelectionCommandPanel"
	) as Control
	panel.set("selection_manager_path", NodePath("../../../../SelectionManager"))
	panel.set("build_manager_path", NodePath("../../../../BuildManager"))

	add_child(command_bar)
	return {
		"bar": command_bar,
		"panel": panel,
		"center_panel": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/CenterPanel"
		),
		"barracks_row": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/RightPanel/BarracksTrainingRow"
		),
		"hero_altar_panel": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/CenterPanel/HeroAltarPanel"
		),
		"blacksmith_panel": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel"
		),
		"stable_panel": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/RightPanel/StablePanel"
		),
		"artillery_panel": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/RightPanel/ArtilleryDepotPanel"
		),
		"academy_panel": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/RightPanel/AcademyPanel"
		),
		"shop_panel": panel.get_node_or_null(
			"MarginContainer/HBoxContainer/RightPanel/ShopPanel"
		),
	}


func _await_ui_settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _make_under_construction(scene: PackedScene) -> Building:
	var building: Building = scene.instantiate() as Building
	add_child(building)
	building.team_id = TeamVisuals.PLAYER_TEAM_ID
	building.start_under_construction()
	return building


func _verify_construction_completed_signal_once(failures: PackedStringArray) -> void:
	print("verify: construction_completed emits once")
	var building: Building = BARRACKS_SCENE.instantiate() as Building
	add_child(building)
	building.start_under_construction()

	var emit_count: Array[int] = [0]
	building.construction_completed.connect(func() -> void: emit_count[0] += 1)

	building.complete_construction()
	building.complete_construction()
	building.set_completed()

	_expect(failures, "construction_completed emits exactly once", emit_count[0] == 1)
	_expect(failures, "building is completed", building.building_state == Building.STATE_COMPLETED)

	building.queue_free()


func _verify_command_bar_refresh_for_types(failures: PackedStringArray) -> void:
	print("verify: command bar refresh per building type")
	var selection: Node = _make_selection_manager()
	var ui: Dictionary = _make_command_ui(selection)
	var bar: PanelContainer = ui.bar
	var panel: Control = ui.panel

	var cases: Array[Dictionary] = [
		{
			"name": "Barracks",
			"scene": BARRACKS_SCENE,
			"visible_node": ui.barracks_row,
		},
		{
			"name": "TownHall",
			"scene": COMMAND_CENTER_SCENE,
			"visible_node": ui.center_panel,
		},
		{
			"name": "HeroAltar",
			"scene": HERO_ALTAR_SCENE,
			"visible_node": ui.hero_altar_panel,
		},
		{
			"name": "Blacksmith",
			"scene": BLACKSMITH_SCENE,
			"visible_node": ui.blacksmith_panel,
		},
		{
			"name": "Stable",
			"scene": STABLE_SCENE,
			"visible_node": ui.stable_panel,
		},
		{
			"name": "ArtilleryDepot",
			"scene": ARTILLERY_DEPOT_SCENE,
			"visible_node": ui.artillery_panel,
		},
		{
			"name": "Academy",
			"scene": ACADEMY_SCENE,
			"visible_node": ui.academy_panel,
		},
		{
			"name": "Shop",
			"scene": SHOP_SCENE,
			"visible_node": ui.shop_panel,
		},
	]

	for case_data: Dictionary in cases:
		var label: String = String(case_data.name)
		var building: Building = _make_under_construction(case_data.scene as PackedScene)
		selection._set_selected_building(building)
		await _await_ui_settle()

		_expect(
			failures,
			"%s: frame hidden while constructing" % label,
			not bar.visible
		)
		_expect(
			failures,
			"%s: panel hidden while constructing" % label,
			not panel.visible
		)

		var completed_emitted: Array[bool] = [false]
		building.construction_completed.connect(func() -> void: completed_emitted[0] = true)
		building.complete_construction()
		await _await_ui_settle()

		_expect(failures, "%s: construction_completed fired" % label, completed_emitted[0])
		_expect(
			failures,
			"%s: still selected after completion" % label,
			selection.selected_building == building
		)
		_expect(failures, "%s: frame visible after completion" % label, bar.visible)
		_expect(failures, "%s: panel visible after completion" % label, panel.visible)

		var command_node: Control = case_data.visible_node as Control
		if command_node != null:
			_expect(
				failures,
				"%s: command UI visible after completion" % label,
				command_node.visible
			)

		selection._clear_building_selection()
		building.queue_free()
		await _await_ui_settle()

	bar.queue_free()
	selection.queue_free()
	await _await_ui_settle()


func _verify_selection_change_before_completion(failures: PackedStringArray) -> void:
	print("verify: selection change before completion")
	var selection: Node = _make_selection_manager()
	var ui: Dictionary = _make_command_ui(selection)
	var bar: PanelContainer = ui.bar

	var unfinished: Building = _make_under_construction(BARRACKS_SCENE)
	var other: Building = _make_under_construction(BLACKSMITH_SCENE)
	other.complete_construction()

	selection._set_selected_building(unfinished)
	await _await_ui_settle()
	_expect(failures, "switch-prep: unfinished selected hides bar", not bar.visible)

	selection._set_selected_building(other)
	await _await_ui_settle()
	_expect(failures, "switch: completed blacksmith shows bar", bar.visible)

	unfinished.complete_construction()
	await _await_ui_settle()
	_expect(
		failures,
		"switch: still showing completed blacksmith after other finishes",
		selection.selected_building == other and bar.visible
	)
	_expect(
		failures,
		"switch: did not steal selection to finished barracks",
		selection.selected_building != unfinished
	)

	unfinished.queue_free()
	other.queue_free()
	bar.queue_free()
	selection.queue_free()
	await _await_ui_settle()


func _verify_destroy_selected_unfinished(failures: PackedStringArray) -> void:
	print("verify: destroy selected unfinished building")
	var selection: Node = _make_selection_manager()
	var ui: Dictionary = _make_command_ui(selection)
	var bar: PanelContainer = ui.bar
	var panel: Control = ui.panel

	var unfinished: Building = _make_under_construction(BARRACKS_SCENE)
	selection._set_selected_building(unfinished)
	await _await_ui_settle()
	_expect(failures, "destroy-prep: bar hidden", not bar.visible)

	unfinished.destroy_building()
	unfinished.queue_free()
	await _await_ui_settle()

	if selection.has_method("purge_invalid_selection"):
		selection.purge_invalid_selection()
	await _await_ui_settle()

	_expect(
		failures,
		"destroy: selection cleared",
		selection.selected_building == null
	)
	_expect(failures, "destroy: bar stays hidden", not bar.visible)
	_expect(failures, "destroy: panel stays hidden", not panel.visible)

	bar.queue_free()
	selection.queue_free()
	await _await_ui_settle()
