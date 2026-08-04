extends Node

## Headless verification for Military AI V2 foundation.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_military_ai_v2.tscn

const REPORT_PATH := "user://military_ai_v2_verify_result.txt"
const REPORT_FALLBACK := "res://military_ai_v2_verify_run.txt"


func _ready() -> void:
	var failures: PackedStringArray = []

	_verify_toggle_default(failures)
	_verify_mission_payload(failures)
	_verify_director_states(failures)
	_verify_commander_does_not_choose_strategy(failures)
	_verify_legacy_gate_helpers(failures)

	var report: String
	if failures.is_empty():
		report = "PASS military_ai_v2_foundation\n"
	else:
		report = "FAIL military_ai_v2_foundation\n" + "\n".join(failures) + "\n"

	_write_report(report)
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)


func _write_report(report: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	var fallback := FileAccess.open(REPORT_FALLBACK, FileAccess.WRITE)
	if fallback != null:
		fallback.store_string(report)
		fallback.close()


func _verify_toggle_default(failures: PackedStringArray) -> void:
	_expect(failures, "USE_MILITARY_AI_V2 defaults false", MilitaryAIConfig.USE_MILITARY_AI_V2 == false)
	_expect(failures, "is_v2_enabled mirrors const", MilitaryAIConfig.is_v2_enabled() == false)
	_expect(failures, "ai_version_label Legacy when disabled", MilitaryAIConfig.ai_version_label() == "Legacy")


func _verify_mission_payload(failures: PackedStringArray) -> void:
	var mission := ArmyMissionV2.new(
		ArmyMissionV2.MissionType.ATTACK,
		Vector3(10, 0, 20),
		null,
		5,
		"test attack"
	)
	_expect(failures, "mission type ATTACK", mission.mission_type == ArmyMissionV2.MissionType.ATTACK)
	_expect(failures, "mission target position", mission.target_position == Vector3(10, 0, 20))
	_expect(failures, "mission priority", mission.priority == 5)
	_expect(failures, "mission transition reason", mission.transition_reason == "test attack")
	_expect(failures, "mission creation time set", mission.creation_time_msec > 0)
	_expect(failures, "mission last progress set", mission.last_progress_time_msec > 0)
	_expect(failures, "mission type label", mission.get_mission_type_name() == "ATTACK")
	_expect(failures, "mission objective label uses position", mission.get_objective_label().contains("10"))

	mission.mark_cancelled("test cancel")
	_expect(failures, "cancellation reason stored", mission.cancellation_reason == "test cancel")
	_expect(
		failures,
		"completion cancelled",
		mission.completion_condition == ArmyMissionV2.CompletionCondition.CANCELLED
	)


func _verify_director_states(failures: PackedStringArray) -> void:
	var director := MilitaryDirectorV2.new()
	add_child(director)
	director.reset_match_state()

	_expect(failures, "director starts IDLE", director.get_state() == MilitaryDirectorV2.State.IDLE)
	_expect(failures, "director state name IDLE", director.get_state_name() == "IDLE")
	_expect(failures, "director has mission", director.get_mission() != null)
	_expect(
		failures,
		"director mission IDLE",
		director.get_mission().mission_type == ArmyMissionV2.MissionType.IDLE
	)
	_expect(
		failures,
		"request_state rejected while V2 disabled",
		director.request_state(MilitaryDirectorV2.State.ATTACK, "should fail") == false
	)

	## Exercise state enum coverage without enabling the feature toggle.
	for state: MilitaryDirectorV2.State in [
		MilitaryDirectorV2.State.IDLE,
		MilitaryDirectorV2.State.ASSEMBLE,
		MilitaryDirectorV2.State.CREEP,
		MilitaryDirectorV2.State.ATTACK,
		MilitaryDirectorV2.State.DEFEND,
		MilitaryDirectorV2.State.RETREAT,
		MilitaryDirectorV2.State.RECOVER,
	]:
		var label: String = MilitaryDirectorV2.state_to_string(state)
		_expect(failures, "state label non-empty for %s" % label, not label.is_empty())
		_expect(failures, "state label not UNKNOWN for %s" % int(state), label != "UNKNOWN")

	director.queue_free()


func _verify_commander_does_not_choose_strategy(failures: PackedStringArray) -> void:
	var source := FileAccess.open("res://scripts/systems/army_commander_v2.gd", FileAccess.READ)
	_expect(failures, "commander script readable", source != null)
	if source == null:
		return

	var text: String = source.get_as_text()
	source.close()
	_expect(
		failures,
		"commander documents no strategic decisions",
		text.contains("Does not choose creep / attack / defend / retreat itself")
	)
	_expect(
		failures,
		"commander does not call request_state",
		not text.contains("request_state(")
	)


func _verify_legacy_gate_helpers(failures: PackedStringArray) -> void:
	var gated_scripts: PackedStringArray = PackedStringArray([
		"res://scripts/systems/enemy_combat_controller.gd",
		"res://scripts/systems/enemy_creep_manager.gd",
		"res://scripts/systems/enemy_defense_manager.gd",
		"res://scripts/systems/enemy_wave_manager.gd",
		"res://scripts/systems/enemy_strategic_director.gd",
	])
	for path: String in gated_scripts:
		var source := FileAccess.open(path, FileAccess.READ)
		_expect(failures, "%s readable" % path.get_file(), source != null)
		if source == null:
			continue
		var text: String = source.get_as_text()
		source.close()
		_expect(
			failures,
			"%s gates on MilitaryAIConfig" % path.get_file(),
			text.contains("MilitaryAIConfig.is_v2_enabled()")
		)
