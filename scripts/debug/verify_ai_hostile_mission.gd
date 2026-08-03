extends Node

## Headless verification for authoritative AI mission + hostile-territory idle fix.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_hostile_mission.tscn

const REPORT_PATH := "user://ai_hostile_mission_verify_result.txt"
const REPORT_FALLBACK := "res://ai_hostile_mission_verify_run.txt"


func _ready() -> void:
	var failures: PackedStringArray = []
	EnemyArmyCommand.reset_match_state()
	EnemyAggression.reset_match_state()
	EnemyUnitMission.reset_match_state()

	_verify_false_creeping_display(failures)
	_verify_creeping_validation(failures)
	_verify_hostile_strength_gate(failures)
	_verify_mission_progress_watchdog_constants(failures)
	_verify_report_format(failures)
	_verify_hostile_target_priority_helpers(failures)

	var report: String
	if failures.is_empty():
		report = "PASS ai_hostile_mission\n"
	else:
		report = "FAIL ai_hostile_mission\n" + "\n".join(failures) + "\n"

	_write_report(report)
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- " + label)


func _write_report(report: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	var fallback := FileAccess.open(REPORT_FALLBACK, FileAccess.WRITE)
	if fallback != null:
		fallback.store_string(report)
		fallback.close()


func _verify_false_creeping_display(failures: PackedStringArray) -> void:
	EnemyArmyCommand.reset_match_state()
	## ArmyMode.CREEPING alone must NOT report CREEPING on the authoritative line.
	EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.CREEPING)
	var report: String = EnemyArmyCommand.get_authoritative_mission_report(get_tree())
	_expect(
		failures,
		"mode CREEPING without executable must not claim CREEPING mission",
		not report.begins_with("MISSION: CREEPING")
	)

	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.CREEPING,
		"test camp",
		null,
		Vector3(10, 0, 10),
		"MediumNorth",
		"attack-move",
		[],
		true
	)
	report = EnemyArmyCommand.get_authoritative_mission_report(get_tree())
	_expect(
		failures,
		"executable CREEPING reports CREEPING",
		report.begins_with("MISSION: CREEPING")
	)
	_expect(failures, "report includes camp name", report.contains("MediumNorth"))
	_expect(failures, "report includes reserve", report.contains("Reserve: yes"))


func _verify_creeping_validation(failures: PackedStringArray) -> void:
	EnemyArmyCommand.reset_match_state()
	var invalid: Dictionary = EnemyArmyCommand.validate_creeping_mission(
		get_tree(),
		null,
		0,
		Vector3.ZERO,
		false,
		false
	)
	_expect(failures, "null camp invalid", not invalid.get("valid", true))

	var marker := Node3D.new()
	marker.name = "FakeCamp"
	add_child(marker)
	var no_reserve: Dictionary = EnemyArmyCommand.validate_creeping_mission(
		get_tree(),
		marker,
		0,
		Vector3(1, 0, 1),
		true,
		false
	)
	_expect(failures, "expired reservation invalid", not no_reserve.get("valid", true))

	var ok: Dictionary = EnemyArmyCommand.validate_creeping_mission(
		get_tree(),
		marker,
		marker.get_instance_id(),
		Vector3(1, 0, 1),
		true,
		true
	)
	_expect(failures, "reserved living camp with combat valid", ok.get("valid", false))
	marker.queue_free()


func _verify_hostile_strength_gate(failures: PackedStringArray) -> void:
	EnemyArmyCommand.reset_match_state()
	EnemyAggression.reset_match_state()
	var empty: Dictionary = EnemyArmyCommand.is_army_strong_enough_for_hostile_push(
		get_tree(),
		[],
		Vector3.ZERO
	)
	## Empty army vs no player threat: player_strength 0 => allowed by design.
	_expect(
		failures,
		"empty army at zero with no threat still evaluates",
		empty.has("allowed")
	)

	_expect(
		failures,
		"hostile engage constant configured",
		EnemyArmyCommand.HOSTILE_TERRITORY_ENGAGE_RANGE > 10.0
	)
	_expect(
		failures,
		"hostile base range configured",
		EnemyArmyCommand.HOSTILE_TERRITORY_BASE_RANGE > 20.0
	)


func _verify_mission_progress_watchdog_constants(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"stall window in 5-8s",
		EnemyArmyCommand.MISSION_PROGRESS_STALL_SECONDS >= 5.0
		and EnemyArmyCommand.MISSION_PROGRESS_STALL_SECONDS <= 8.0
	)
	EnemyArmyCommand.reset_match_state()
	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER,
		"test",
		null,
		Vector3(50, 0, 50),
		"MainCC",
		"attack-move"
	)
	EnemyArmyCommand.note_mission_progress(Vector3(40, 0, 40), false, 5)
	var before: float = EnemyArmyCommand.get_seconds_since_mission_progress()
	_expect(failures, "progress timer starts near zero", before < 1.0)

	## Moving closer should count as progress.
	EnemyArmyCommand.note_mission_progress(Vector3(30, 0, 30), false, 5)
	_expect(
		failures,
		"closing distance refreshes progress",
		EnemyArmyCommand.get_seconds_since_mission_progress() < 1.0
	)

	## Combat refreshes progress.
	EnemyArmyCommand.note_mission_progress(Vector3(30, 0, 30), true, 5)
	_expect(
		failures,
		"combat refreshes progress",
		EnemyArmyCommand.get_seconds_since_mission_progress() < 1.0
	)


func _verify_report_format(failures: PackedStringArray) -> void:
	EnemyArmyCommand.reset_match_state()
	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER,
		"army reached hostile base",
		null,
		Vector3(20, 0, 20),
		"MainCC",
		"attack-move"
	)
	var report: String = EnemyArmyCommand.get_authoritative_mission_report(get_tree())
	_expect(failures, "attack report label", report.begins_with("MISSION: ATTACK_PLAYER"))
	_expect(failures, "attack report target", report.contains("MainCC"))
	_expect(failures, "attack report reason", report.contains("army reached hostile base"))

	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.REGROUP,
		"creep objective invalid",
		null,
		Vector3.ZERO,
		"Rally",
		"move"
	)
	report = EnemyArmyCommand.get_authoritative_mission_report(get_tree())
	_expect(failures, "regroup report label", report.begins_with("MISSION: REGROUP"))
	_expect(failures, "regroup report reason", report.contains("creep objective invalid"))


func _verify_hostile_target_priority_helpers(failures: PackedStringArray) -> void:
	EnemyArmyCommand.reset_match_state()
	var empty_target: Dictionary = EnemyArmyCommand.resolve_hostile_territory_target(
		get_tree(),
		Vector3.ZERO
	)
	_expect(failures, "zero origin yields empty target", empty_target.is_empty())

	var label: String = EnemyArmyCommand.executable_mission_to_label(
		EnemyArmyCommand.ExecutableMission.LETHAL_PUSH
	)
	_expect(failures, "lethal push label", label == "LETHAL_PUSH")
	_expect(
		failures,
		"creeping label",
		EnemyArmyCommand.executable_mission_to_label(
			EnemyArmyCommand.ExecutableMission.CREEPING
		) == "CREEPING"
	)
