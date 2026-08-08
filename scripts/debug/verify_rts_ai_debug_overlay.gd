extends Node

## Headless smoke for READ-ONLY RTS AI diagnostics (O overlay).
## Godot --headless --path <project> --scene res://scenes/debug/verify_rts_ai_debug_overlay.tscn


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var root := Node.new()
	root.name = "DiagRoot"
	add_child(root)

	var composition := MatchCompositionRoot.new()
	composition.name = "MatchSystems"
	root.add_child(composition)

	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	composition.add_child(director)
	composition.military_director_v2 = director

	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	composition.add_child(commander)
	composition.army_commander_v2 = commander

	await get_tree().process_frame
	await get_tree().process_frame

	if not director.has_method("get_rts_diagnostic_snapshot"):
		failures.append("missing get_rts_diagnostic_snapshot")
	else:
		var snap: Dictionary = director.get_rts_diagnostic_snapshot()
		if snap.is_empty():
			failures.append("empty diagnostic snapshot")
		for key: String in [
			"state",
			"mission",
			"mission_generation",
			"decision_lines",
			"director_power",
			"commander_power",
			"power_mismatch",
			"hero_with_main",
			"idle_military",
		]:
			if not snap.has(key):
				failures.append("snapshot missing %s" % key)

		## Snapshot must not mutate mission / state.
		var state_before: String = director.get_state_name()
		var snap2: Dictionary = director.get_rts_diagnostic_snapshot()
		if director.get_state_name() != state_before:
			failures.append("snapshot mutated director state")
		if String(snap2.get("state", "")) != state_before:
			failures.append("snapshot state mismatch")

	## Overlay must expose ORDER AUTHORITY provenance fields (source-level).
	var overlay_src := FileAccess.open(
		"res://scripts/debug/rts_ai_debug_overlay.gd",
		FileAccess.READ
	)
	if overlay_src == null:
		failures.append("overlay source unreadable")
	else:
		var overlay_text: String = overlay_src.get_as_text()
		overlay_src.close()
		if not overlay_text.contains("ORDER AUTHORITY"):
			failures.append("overlay missing ORDER AUTHORITY")
		if not overlay_text.contains("get_strategic_order_provenance"):
			failures.append("overlay missing provenance reader")
		if not overlay_text.contains("CONFLICT:"):
			failures.append("overlay missing CONFLICT")

	var overlay = get_node_or_null("/root/RtsAiDebugOverlay")
	if overlay == null:
		failures.append("RtsAiDebugOverlay autoload missing")
	else:
		for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1106, 512)]:
			if overlay.has_method("set_layout_size_override_for_tests"):
				overlay.call("set_layout_size_override_for_tests", Vector2(size))
			overlay.show_overlay()
			await get_tree().process_frame
			if not overlay.is_overlay_visible():
				failures.append("overlay failed to show @ %dx%d" % [size.x, size.y])
			else:
				_check_overlay_layout(overlay, size, failures)
			overlay.hide_overlay()
			await get_tree().process_frame
			if overlay.is_overlay_visible():
				failures.append("overlay failed to hide @ %dx%d" % [size.x, size.y])
			var world := get_tree().root.find_child("RtsAiDebugWorld", true, false)
			if world != null and is_instance_valid(world):
				failures.append("stale world debug after hide @ %dx%d" % [size.x, size.y])
		if overlay.has_method("set_layout_size_override_for_tests"):
			overlay.call("set_layout_size_override_for_tests", Vector2.ZERO)

	if failures.is_empty():
		print("PASS rts_ai_debug_overlay")
		get_tree().quit(0)
	else:
		print("FAIL rts_ai_debug_overlay")
		for f: String in failures:
			print(" - %s" % f)
		get_tree().quit(1)


func _check_overlay_layout(overlay: Node, size: Vector2i, failures: PackedStringArray) -> void:
	var panel: PanelContainer = overlay.get("_panel") as PanelContainer
	var label: RichTextLabel = overlay.get("_label") as RichTextLabel
	if panel == null or label == null:
		failures.append("overlay panel/label missing @ %dx%d" % [size.x, size.y])
		return
	var panel_w: float = absf(panel.offset_right - panel.offset_left)
	var panel_h: float = absf(panel.offset_bottom - panel.offset_top)
	var width_frac: float = panel_w / float(size.x)
	var height_frac: float = panel_h / float(size.y)
	if width_frac > 0.34:
		failures.append(
			"panel too wide %.0f%% @ %dx%d" % [width_frac * 100.0, size.x, size.y]
		)
	if height_frac > 0.52:
		failures.append(
			"panel too tall %.0f%% @ %dx%d" % [height_frac * 100.0, size.x, size.y]
		)
	## Prefer BBCode source; parsed text can lag one frame in headless.
	var text: String = String(label.text)
	for needle: String in ["AI BRAIN", "Mission:", "Decision:", "Why:"]:
		if text.find(needle) < 0:
			failures.append("missing '%s' @ %dx%d" % [needle, size.x, size.y])
	if text.find("Dir power:") < 0 and text.find("Dir:") < 0:
		failures.append("missing director power line @ %dx%d" % [size.x, size.y])
	if text.find("Cmd power:") < 0 and text.find("Cmd:") < 0 and text.find("Commander:") < 0:
		failures.append("missing commander power/state @ %dx%d" % [size.x, size.y])
	var primary_font: int = int(overlay.get("_primary_font"))
	if size.y <= 520 and primary_font < 14:
		failures.append("primary font too small (%d) @ %dx%d" % [primary_font, size.x, size.y])
	print(
		"layout ok @ %dx%d w=%.0f%% h=%.0f%% font=%d" % [
			size.x,
			size.y,
			width_frac * 100.0,
			height_frac * 100.0,
			primary_font,
		]
	)
