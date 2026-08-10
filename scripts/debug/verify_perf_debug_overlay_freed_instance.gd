extends Node

## Same-frame cached-group death must not crash F3 perf overlay stats.
## Godot_v4.7-stable_win64.exe --headless --path <project> \
##   res://scenes/debug/verify_perf_debug_overlay_freed_instance.tscn

const REPORT_PATH := "user://perf_debug_overlay_freed_instance_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")
const NEUTRAL_CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	await _settle()
	_verify_cached_group_death(failures, &"units", SWORDSMAN_SCENE, "player unit")
	_verify_cached_group_death(failures, &"enemies", ENEMY_DUMMY_SCENE, "enemy unit")
	_verify_cached_group_death(failures, &"neutral_creeps", NEUTRAL_CREEP_SCENE, "creep")
	_verify_overlay_refresh_survives_freed_cache(failures)

	var report: String
	if failures.is_empty():
		report = "PASS perf_debug_overlay_freed_instance\n"
	else:
		report = "FAIL perf_debug_overlay_freed_instance\n" + "\n".join(failures) + "\n"

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


## Reproduce: cache valid Nodes → free one in the same process frame → collect stats.
## Uses free() (not queue_free+await) so deletion happens before the frame ends and
## before get_cached_group_nodes would rebuild on a new process frame.
func _verify_cached_group_death(
	failures: PackedStringArray,
	group_name: StringName,
	scene: PackedScene,
	label: String
) -> void:
	CombatTargetValidation.reset_match_state()

	var survivor: Unit = scene.instantiate() as Unit
	var doomed: Unit = scene.instantiate() as Unit
	add_child(survivor)
	add_child(doomed)
	_ensure_exclusive_group(survivor, group_name)
	_ensure_exclusive_group(doomed, group_name)
	survivor.has_move_target = true
	doomed.has_move_target = true

	var cached: Array = CombatTargetValidation.get_cached_group_nodes(get_tree(), group_name)
	_expect(
		failures,
		"%s: cache holds survivor+doomed before free" % label,
		cached.has(survivor) and cached.has(doomed)
	)

	doomed.free()

	_expect(
		failures,
		"%s: doomed invalid after free while cache still current frame" % label,
		not is_instance_valid(doomed)
	)
	_expect(
		failures,
		"%s: same-frame cache still contains freed entry" % label,
		cached.has(doomed)
	)

	var stats: Dictionary = PerfDebugOverlay._collect_unit_stats(get_tree())
	_expect(failures, "%s: collect stats returned Dictionary" % label, stats is Dictionary)

	match group_name:
		&"units":
			_expect(
				failures,
				"%s: freed unit not counted in total_units" % label,
				int(stats.get("total_units", -1)) == 1
			)
			_expect(
				failures,
				"%s: player_military counts only survivor" % label,
				int(stats.get("player_military", -1)) == 1
			)
		&"enemies":
			_expect(
				failures,
				"%s: freed enemy not counted in total_units" % label,
				int(stats.get("total_units", -1)) == 1
			)
			_expect(
				failures,
				"%s: enemy_military counts only survivor" % label,
				int(stats.get("enemy_military", -1)) == 1
			)
		&"neutral_creeps":
			_expect(
				failures,
				"%s: freed creep not counted" % label,
				int(stats.get("creeps", -1)) == 1
			)
			_expect(
				failures,
				"%s: freed creep not in total_units" % label,
				int(stats.get("total_units", -1)) == 1
			)

	_expect(
		failures,
		"%s: moving_units counts only living mover" % label,
		int(stats.get("moving_units", -1)) == 1
	)

	survivor.free()
	CombatTargetValidation.reset_match_state()


func _verify_overlay_refresh_survives_freed_cache(failures: PackedStringArray) -> void:
	CombatTargetValidation.reset_match_state()
	var unit: Unit = SWORDSMAN_SCENE.instantiate() as Unit
	add_child(unit)
	_ensure_exclusive_group(unit, &"units")
	unit.has_move_target = true

	CombatTargetValidation.get_cached_group_nodes(get_tree(), &"units")
	unit.free()

	PerfDebugOverlay.show_overlay()
	PerfDebugOverlay._update_label()
	_expect(
		failures,
		"F3 overlay refresh survives same-frame freed cached unit",
		PerfDebugOverlay._label != null and not String(PerfDebugOverlay._label.text).is_empty()
	)
	PerfDebugOverlay.hide_overlay()
	CombatTargetValidation.reset_match_state()


func _ensure_exclusive_group(node: Node, group_name: StringName) -> void:
	for other_group: StringName in [
		&"units",
		&"enemies",
		&"neutral_creeps",
		&"workers",
		&"enemy_workers",
	]:
		if other_group != group_name and node.is_in_group(other_group):
			node.remove_from_group(other_group)
	if not node.is_in_group(group_name):
		node.add_to_group(group_name)
