extends Node

## Headless verification for AI aggression / lethal / greed punish.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_aggression.tscn

const REPORT_PATH := "user://ai_aggression_verify_result.txt"
const REPORT_FALLBACK := "res://ai_aggression_verify_run.txt"


func _ready() -> void:
	var failures: PackedStringArray = []
	EnemyAggression.reset_match_state()
	EnemyArmyCommand.reset_match_state()

	_verify_confidence_thresholds(failures)
	_verify_lethal_and_greed_empty_tree(failures)
	_verify_aggression_hysteresis(failures)
	_verify_retreat_logic(failures)
	_verify_objective_priority(failures)
	_verify_commit_ratios(failures)
	_verify_creep_suspend_and_wave_bypass(failures)
	_verify_counter_pressure_flags(failures)
	_verify_early_strategy_wrapper(failures)
	_verify_personality_hooks_exist(failures)

	var report: String
	if failures.is_empty():
		report = "PASS ai_aggression\n"
	else:
		report = "FAIL ai_aggression\n" + "\n".join(failures) + "\n"

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


func _verify_confidence_thresholds(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()

	EnemyAggression.force_scores_for_tests(10.0, 0.0)
	_expect(
		failures,
		"low opportunity => VERY_LOW/LOW",
		EnemyAggression.get_confidence() <= EnemyAggression.Confidence.LOW
	)

	EnemyAggression.force_scores_for_tests(40.0, 40.0)
	_expect(
		failures,
		"medium opportunity => MEDIUM+",
		EnemyAggression.get_confidence() >= EnemyAggression.Confidence.MEDIUM
	)

	EnemyAggression.force_scores_for_tests(70.0, 60.0)
	_expect(
		failures,
		"high opportunity => HIGH+",
		EnemyAggression.get_confidence() >= EnemyAggression.Confidence.HIGH
	)

	EnemyAggression.force_scores_for_tests(90.0, 80.0)
	_expect(
		failures,
		"very high opportunity => VERY_HIGH",
		EnemyAggression.get_confidence() == EnemyAggression.Confidence.VERY_HIGH
	)

	_expect(
		failures,
		"confidence_name very_high",
		EnemyAggression.confidence_name(EnemyAggression.Confidence.VERY_HIGH) == "very_high"
	)


func _verify_lethal_and_greed_empty_tree(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()
	var tree: SceneTree = get_tree()

	var lethal: Dictionary = EnemyAggression.compute_lethal_score(tree)
	_expect(failures, "lethal score dictionary has score", lethal.has("score"))
	_expect(
		failures,
		"lethal score in range",
		float(lethal.get("score", -1.0)) >= 0.0 and float(lethal.get("score", 101.0)) <= 100.0
	)

	var greed: Dictionary = EnemyAggression.compute_greed_score(tree)
	_expect(failures, "greed score dictionary has score", greed.has("score"))
	_expect(failures, "greed has reasons array", greed.get("reasons", null) is Array)
	_expect(failures, "greed has counter_pressure flag", greed.has("counter_pressure"))

	## Formula contract: opportunity = lethal*0.62 + greed*0.48
	EnemyAggression.force_scores_for_tests(50.0, 50.0)
	var expected: float = 50.0 * 0.62 + 50.0 * 0.48
	_expect(
		failures,
		"opportunity formula lethal*0.62 + greed*0.48",
		is_equal_approx(EnemyAggression.get_opportunity_score(), expected)
	)


func _verify_aggression_hysteresis(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()
	_expect(failures, "starts inactive", not EnemyAggression.is_aggression_mode_active())

	EnemyAggression.force_scores_for_tests(80.0, 70.0)
	EnemyAggression.force_aggression_for_tests(true, "unit_test")
	_expect(failures, "force enter aggression", EnemyAggression.is_aggression_mode_active())
	_expect(failures, "suspend creeping when high aggression", EnemyAggression.should_suspend_creeping())
	_expect(failures, "prefer town hall focus", EnemyAggression.should_prefer_town_hall_focus())
	_expect(failures, "bypass wave delay", EnemyAggression.should_bypass_wave_delay())
	_expect(
		failures,
		"aggressive strength gate",
		EnemyAggression.should_use_aggressive_strength_gate()
	)

	EnemyAggression.force_aggression_for_tests(false, "unit_test_exit")
	_expect(failures, "force exit aggression", not EnemyAggression.is_aggression_mode_active())

	## notify_attack_failed should exit and arm retreat cooldown
	EnemyAggression.force_aggression_for_tests(true, "pre_fail")
	EnemyAggression.notify_attack_failed()
	_expect(failures, "failed attack exits aggression", not EnemyAggression.is_aggression_mode_active())
	_expect(failures, "failed attack sets retreat cooldown", EnemyAggression.is_on_retreat_cooldown())


func _verify_retreat_logic(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()
	EnemyAggression.force_aggression_for_tests(true, "retreat_test")
	EnemyAggression.force_scores_for_tests(10.0, 10.0)

	var retreat: Dictionary = EnemyAggression.should_retreat_aggression(get_tree())
	## Empty army should retreat.
	_expect(failures, "retreat when army too small", VariantUtils.to_bool(retreat.get("should_retreat", false)))


func _verify_objective_priority(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()
	var objective: Dictionary = EnemyAggression.resolve_aggression_attack_objective(
		get_tree(),
		Vector3(10, 0, 10)
	)
	_expect(failures, "aggression objective returns dictionary", objective.has("position"))
	_expect(
		failures,
		"fallback position used when no targets",
		objective.get("position", Vector3.ZERO) == Vector3(10, 0, 10)
		or objective.get("position", Vector3.ZERO) == Vector3.ZERO
	)


func _verify_commit_ratios(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()
	_expect(
		failures,
		"default commit ratio mid",
		EnemyAggression.get_commit_army_ratio() >= 0.5
	)

	EnemyAggression.force_scores_for_tests(90.0, 80.0)
	EnemyAggression.force_aggression_for_tests(true, "commit")
	_expect(
		failures,
		"very high commit nearly full army",
		EnemyAggression.get_commit_army_ratio() >= 0.9
	)

	var defense_budget: int = EnemyAggression.get_home_defense_budget(20)
	_expect(failures, "home defense budget leaves some units", defense_budget >= 2)
	_expect(failures, "home defense budget not whole army", defense_budget < 20)


func _verify_creep_suspend_and_wave_bypass(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()
	_expect(failures, "no creep suspend by default", not EnemyAggression.should_suspend_creeping())
	_expect(failures, "no wave bypass by default", not EnemyAggression.should_bypass_wave_delay())

	EnemyAggression.force_scores_for_tests(80.0, 50.0)
	EnemyAggression.force_aggression_for_tests(true, "creep")
	_expect(failures, "aggression suspends creeping", EnemyAggression.should_suspend_creeping())
	_expect(failures, "aggression bypasses wave delay", EnemyAggression.should_bypass_wave_delay())


func _verify_counter_pressure_flags(failures: PackedStringArray) -> void:
	EnemyAggression.reset_match_state()
	EnemyAggression.force_aggression_for_tests(true, "cp")
	EnemyAggression.force_counter_pressure_for_tests(true)
	_expect(failures, "counter pressure active", EnemyAggression.is_counter_pressure_active())
	_expect(
		failures,
		"counter pressure leaves minimal defense",
		EnemyAggression.should_leave_minimal_home_defense()
	)


func _verify_early_strategy_wrapper(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"is_player_expanding_greedily callable",
		EnemyEarlyStrategy.is_player_expanding_greedily(get_tree()) == false
		or EnemyEarlyStrategy.is_player_expanding_greedily(get_tree()) == true
	)


func _verify_personality_hooks_exist(failures: PackedStringArray) -> void:
	## Ensure mastery script still parses and aggression mode APIs are reachable.
	_expect(failures, "AIHeroMastery autoload present", AIHeroMastery != null)
	_expect(
		failures,
		"ArmyCommand aggression mirror",
		EnemyArmyCommand.is_aggression_mode_active() == EnemyAggression.is_aggression_mode_active()
	)

	## Threshold contracts documented for the feature report.
	_expect(
		failures,
		"enter high threshold 55",
		is_equal_approx(EnemyAggression.ENTER_HIGH_THRESHOLD, 55.0)
	)
	_expect(
		failures,
		"stay medium threshold 32",
		is_equal_approx(EnemyAggression.STAY_MEDIUM_THRESHOLD, 32.0)
	)
	_expect(
		failures,
		"finishing lethal threshold 72",
		is_equal_approx(EnemyAggression.FINISHING_LETHAL_THRESHOLD, 72.0)
	)
	_expect(
		failures,
		"retreat lethal threshold 22",
		is_equal_approx(EnemyAggression.RETREAT_LETHAL_THRESHOLD, 22.0)
	)
