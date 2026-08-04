extends Node

## Headless AI difficulty system checks. Run with:
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_difficulty.tscn

const REPORT_PATH := "user://ai_difficulty_verify_result.txt"


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()

	_check_config_limits(failures)
	_check_match_session_defaults(failures)
	_check_difficulty_switching(failures)
	_check_clamp(failures)
	_check_display_names(failures)
	_check_build_manager_caps(failures)

	var exit_code: int = 0
	var msg: String = ""
	if failures.is_empty():
		msg = "AI_DIFFICULTY_OK"
	else:
		exit_code = 1
		msg = "AI_DIFFICULTY_FAIL\n - " + "\n - ".join(failures)

	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report:
		report.store_string(msg)
		report.close()

	print(msg)
	if exit_code != 0:
		push_error(msg)

	get_tree().quit(exit_code)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)


func _check_config_limits(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"easy barracks max 1",
		AIDifficultyConfig.max_barracks(AIDifficultyConfig.Difficulty.EASY) == 1
	)
	_expect(
		failures,
		"easy stables max 1",
		AIDifficultyConfig.max_stables(AIDifficultyConfig.Difficulty.EASY) == 1
	)
	_expect(
		failures,
		"easy artillery max 1",
		AIDifficultyConfig.max_artillery_depots(AIDifficultyConfig.Difficulty.EASY) == 1
	)

	_expect(
		failures,
		"normal barracks max 2",
		AIDifficultyConfig.max_barracks(AIDifficultyConfig.Difficulty.NORMAL) == 2
	)
	_expect(
		failures,
		"normal stables max 2",
		AIDifficultyConfig.max_stables(AIDifficultyConfig.Difficulty.NORMAL) == 2
	)
	_expect(
		failures,
		"normal artillery max 2",
		AIDifficultyConfig.max_artillery_depots(AIDifficultyConfig.Difficulty.NORMAL) == 2
	)

	_expect(
		failures,
		"hard barracks max 4",
		AIDifficultyConfig.max_barracks(AIDifficultyConfig.Difficulty.HARD) == 4
	)
	_expect(
		failures,
		"hard stables max 4",
		AIDifficultyConfig.max_stables(AIDifficultyConfig.Difficulty.HARD) == 4
	)
	_expect(
		failures,
		"hard artillery max 4",
		AIDifficultyConfig.max_artillery_depots(AIDifficultyConfig.Difficulty.HARD) == 4
	)


func _check_match_session_defaults(failures: PackedStringArray) -> void:
	## Restore known default before asserting menu default behavior.
	MatchSession.set_ai_difficulty(AIDifficultyConfig.DEFAULT_DIFFICULTY)
	_expect(
		failures,
		"default difficulty is Normal",
		MatchSession.get_ai_difficulty() == AIDifficultyConfig.Difficulty.NORMAL
	)
	_expect(
		failures,
		"default difficulty name Normal",
		MatchSession.get_ai_difficulty_name() == "Normal"
	)


func _check_difficulty_switching(failures: PackedStringArray) -> void:
	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.EASY)
	_expect(failures, "set Easy", MatchSession.get_ai_difficulty_name() == "Easy")
	_expect(
		failures,
		"Easy caps via session",
		AIDifficultyConfig.max_barracks() == 1
		and AIDifficultyConfig.max_stables() == 1
		and AIDifficultyConfig.max_artillery_depots() == 1
	)

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.HARD)
	_expect(failures, "set Hard", MatchSession.get_ai_difficulty_name() == "Hard")
	_expect(
		failures,
		"Hard caps via session",
		AIDifficultyConfig.max_barracks() == 4
		and AIDifficultyConfig.max_stables() == 4
		and AIDifficultyConfig.max_artillery_depots() == 4
	)

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.NORMAL)
	_expect(failures, "set Normal", MatchSession.get_ai_difficulty_name() == "Normal")
	_expect(
		failures,
		"Normal caps via session",
		AIDifficultyConfig.max_barracks() == 2
		and AIDifficultyConfig.max_stables() == 2
		and AIDifficultyConfig.max_artillery_depots() == 2
	)


func _check_clamp(failures: PackedStringArray) -> void:
	MatchSession.set_ai_difficulty(99)
	_expect(
		failures,
		"invalid difficulty clamps to Normal",
		MatchSession.get_ai_difficulty() == AIDifficultyConfig.Difficulty.NORMAL
	)
	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.NORMAL)


func _check_display_names(failures: PackedStringArray) -> void:
	_expect(failures, "Easy name", AIDifficultyConfig.display_name(0) == "Easy")
	_expect(failures, "Normal name", AIDifficultyConfig.display_name(1) == "Normal")
	_expect(failures, "Hard name", AIDifficultyConfig.display_name(2) == "Hard")
	_expect(
		failures,
		"from display Easy",
		AIDifficultyConfig.difficulty_from_display_name("Easy")
		== AIDifficultyConfig.Difficulty.EASY
	)
	_expect(
		failures,
		"from display Hard",
		AIDifficultyConfig.difficulty_from_display_name("Hard")
		== AIDifficultyConfig.Difficulty.HARD
	)


func _check_build_manager_caps(failures: PackedStringArray) -> void:
	## Caps are owned by AIDifficultyConfig; EnemyBuildManager reads them for debug/UI.
	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.EASY)
	_expect(
		failures,
		"session Easy feeds config",
		AIDifficultyConfig.max_barracks() == 1
		and AIDifficultyConfig.max_stables() == 1
		and AIDifficultyConfig.max_artillery_depots() == 1
	)

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.NORMAL)
	_expect(
		failures,
		"session Normal feeds config",
		AIDifficultyConfig.max_barracks() == 2
		and AIDifficultyConfig.max_stables() == 2
		and AIDifficultyConfig.max_artillery_depots() == 2
	)

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.HARD)
	_expect(
		failures,
		"session Hard feeds config",
		AIDifficultyConfig.max_barracks() == 4
		and AIDifficultyConfig.max_stables() == 4
		and AIDifficultyConfig.max_artillery_depots() == 4
	)

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.NORMAL)
