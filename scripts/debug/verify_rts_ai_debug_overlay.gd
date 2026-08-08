extends Node

## Headless smoke for READ-ONLY RTS AI diagnostics (O overlay).
## Godot --headless --path <project> --scene res://scenes/debug/verify_rts_ai_debug_overlay.tscn


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var root := Node.new()
	root.name = "DiagRoot"
	add_child(root)

	var composition := MatchCompositionRoot.new()
	composition.name = "MatchCompositionRoot"
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

	var overlay = get_node_or_null("/root/RtsAiDebugOverlay")
	if overlay == null:
		failures.append("RtsAiDebugOverlay autoload missing")
	else:
		overlay.show_overlay()
		await get_tree().process_frame
		if not overlay.is_overlay_visible():
			failures.append("overlay failed to show")
		overlay.hide_overlay()
		await get_tree().process_frame
		if overlay.is_overlay_visible():
			failures.append("overlay failed to hide")

	if failures.is_empty():
		print("PASS rts_ai_debug_overlay")
		get_tree().quit(0)
	else:
		print("FAIL rts_ai_debug_overlay")
		for f: String in failures:
			print(" - %s" % f)
		get_tree().quit(1)
