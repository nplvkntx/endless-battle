extends Node

const REPORT_PATH := "user://building_selection_ui_freed_instance_verify_result.txt"
const PLAYER_HUD_SCENE: PackedScene = preload("res://scenes/ui/player_hud.tscn")
const SELECTION_MANAGER_SCRIPT: Script = preload("res://scripts/systems/selection_manager.gd")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const PLAYER_TEAM_ID: int = 0


func _ready() -> void:
	var failures: PackedStringArray = []
	if EntityRegistry != null:
		EntityRegistry.clear()
	HeroProgressionStore.clear()
	MatchSession._register_static_match_resets()

	await _verify_cancelled_selected_building_clears_before_altar_refresh(failures)
	await _verify_command_center_switching_survives_completion(failures)
	await _verify_selection_pulse_survives_freed_cached_mesh(failures)

	var report: String
	if failures.is_empty():
		report = "PASS building_selection_ui_freed_instance\n"
	else:
		report = "FAIL building_selection_ui_freed_instance\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- " + label)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _make_root() -> Dictionary:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	var match_systems := Node.new()
	match_systems.name = "MatchSystems"
	world.add_child(match_systems)

	var selection: Node = SELECTION_MANAGER_SCRIPT.new() as Node
	selection.name = "SelectionManager"
	match_systems.add_child(selection)

	var build_manager: Node = Node.new()
	build_manager.name = "BuildManager"
	match_systems.add_child(build_manager)

	var ui: Node = PLAYER_HUD_SCENE.instantiate()
	ui.name = "GameUI"
	world.add_child(ui)

	await _settle()
	return {
		"world": world,
		"selection": selection,
		"ui": ui,
		"commands": ui.get_node("Hud/CommandBar/MarginContainer/VBoxContainer/SelectionCommandPanel"),
	}


func _make_completed_building(scene: PackedScene, parent: Node3D) -> Building:
	var building: Building = scene.instantiate() as Building
	parent.add_child(building)
	building.team_id = PLAYER_TEAM_ID
	building.set_completed()
	return building


func _verify_cancelled_selected_building_clears_before_altar_refresh(
	failures: PackedStringArray
) -> void:
	var setup: Dictionary = await _make_root()
	var world: Node3D = setup.world as Node3D
	var selection: Node = setup.selection as Node
	var commands: Node = setup.commands as Node

	var cancelled_building: Building = FARM_SCENE.instantiate() as Building
	world.add_child(cancelled_building)
	cancelled_building.team_id = PLAYER_TEAM_ID
	cancelled_building.start_under_construction()
	cancelled_building.setup_construction(10.0)

	var altar: HeroAltar = _make_completed_building(HERO_ALTAR_SCENE, world) as HeroAltar
	await _settle()

	selection.call("_set_selected_building", cancelled_building)
	await _settle()
	_expect(
		failures,
		"raw cancel setup selected building",
		selection.get("selected_building") == cancelled_building
	)

	cancelled_building.refund_and_cancel_construction()
	await get_tree().process_frame
	_expect(
		failures,
		"raw cancel cleared authoritative selection before altar refresh",
		selection.get("selected_building") == null
	)

	selection.call("_set_selected_building", altar)
	await _settle()
	_expect(failures, "altar selection survives prior cancel", selection.get("selected_building") == altar)
	_expect(
		failures,
		"command panel tracks altar after prior cancel",
		commands.get("_selected_hero_altar") == altar
	)

	world.queue_free()
	await _settle()


func _verify_command_center_switching_survives_completion(
	failures: PackedStringArray
) -> void:
	var setup: Dictionary = await _make_root()
	var world: Node3D = setup.world as Node3D
	var selection: Node = setup.selection as Node
	var commands: Node = setup.commands as Node

	var original_cc: CommandCenter = _make_completed_building(COMMAND_CENTER_SCENE, world) as CommandCenter
	original_cc.global_position = Vector3.ZERO
	var second_cc: CommandCenter = COMMAND_CENTER_SCENE.instantiate() as CommandCenter
	world.add_child(second_cc)
	second_cc.team_id = PLAYER_TEAM_ID
	second_cc.global_position = Vector3(6.0, 0.0, 0.0)
	second_cc.start_under_construction()
	second_cc.setup_construction(8.0)
	var altar: HeroAltar = _make_completed_building(HERO_ALTAR_SCENE, world) as HeroAltar
	altar.global_position = Vector3(12.0, 0.0, 0.0)
	await _settle()

	selection.call("_set_selected_building", second_cc)
	await _settle()
	second_cc.complete_construction()
	await _settle()

	selection.call("_set_selected_building", original_cc)
	await _settle()
	selection.call("_set_selected_building", altar)
	await _settle()
	selection.call("_set_selected_building", second_cc)
	await _settle()

	_expect(failures, "second command center remains selected after completion", selection.get("selected_building") == second_cc)
	_expect(
		failures,
		"command panel tracks second command center after switches",
		commands.get("_selected_command_center") == second_cc
	)
	_expect(
		failures,
		"hero altar cache cleared after switching back to command center",
		commands.get("_selected_hero_altar") == null
	)

	world.queue_free()
	await _settle()


func _verify_selection_pulse_survives_freed_cached_mesh(failures: PackedStringArray) -> void:
	## Reproduces TargetFeedback meta cache retaining a freed MeshInstance3D after
	## construction/visual mesh replacement, then selecting again through the real pulse path.
	var altar: HeroAltar = HERO_ALTAR_SCENE.instantiate() as HeroAltar
	add_child(altar)
	altar.team_id = PLAYER_TEAM_ID
	altar.set_completed()
	await _settle()

	altar.set_selected(true)
	await _settle()
	_expect(
		failures,
		"selection pulse populated material cache",
		altar.has_meta(&"target_feedback_visual_materials")
	)

	var cached_before: Array = altar.get_meta(&"target_feedback_visual_materials") as Array
	_expect(failures, "material cache has entries before free", not cached_before.is_empty())
	if cached_before.is_empty():
		altar.queue_free()
		await _settle()
		return

	var first_entry: Dictionary = cached_before[0]
	var raw_mesh: Variant = first_entry.get("mesh")
	_expect(failures, "cached mesh present before free", raw_mesh != null and is_instance_valid(raw_mesh))
	if raw_mesh == null or not is_instance_valid(raw_mesh) or not raw_mesh is MeshInstance3D:
		altar.queue_free()
		await _settle()
		return

	## Leave the stale Dictionary entry in host meta; do not clear the cache here.
	(raw_mesh as MeshInstance3D).free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(failures, "cached mesh is invalid after free", not is_instance_valid(raw_mesh))
	_expect(
		failures,
		"stale material cache still retained before second pulse",
		altar.has_meta(&"target_feedback_visual_materials")
	)

	## Mirror normal visual replacement: a living mesh remains under Visuals for rebuild.
	var visuals_root: Node3D = altar.get_node_or_null("Visuals") as Node3D
	_expect(failures, "hero altar has Visuals root", visuals_root != null)
	if visuals_root != null:
		var replacement := MeshInstance3D.new()
		replacement.name = "ReplacementPulseMesh"
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 1.0, 1.0)
		replacement.mesh = box
		var replacement_material := StandardMaterial3D.new()
		replacement_material.albedo_color = Color(0.52, 0.32, 0.72, 1.0)
		replacement.material_override = replacement_material
		visuals_root.add_child(replacement)

	## Real public re-select path: deselect then select again (selection pulse).
	altar.set_selected(false)
	altar.set_selected(true)
	await _settle()

	_expect(failures, "altar still selected after freed-mesh pulse", altar.is_selected)
	_expect(
		failures,
		"material cache rebuilt after stale discard",
		altar.has_meta(&"target_feedback_visual_materials")
	)

	var cached_after: Array = altar.get_meta(&"target_feedback_visual_materials") as Array
	var stale_retained := false
	for entry_variant: Variant in cached_after:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var entry_mesh: Variant = entry.get("mesh")
		if entry_mesh != null and is_same(entry_mesh, raw_mesh):
			stale_retained = true
			break
		if entry_mesh != null and not is_instance_valid(entry_mesh):
			stale_retained = true
			break
	_expect(failures, "rebuilt cache has no freed mesh refs", not stale_retained)
	_expect(failures, "rebuilt cache is usable", not cached_after.is_empty())

	## Second pulse with rebuilt cache must also succeed.
	altar.play_selection_pulse()
	await _settle()
	_expect(failures, "repeat selection pulse after rebuild", altar.is_selected)

	altar.queue_free()
	await _settle()
