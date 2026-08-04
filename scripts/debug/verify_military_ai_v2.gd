extends Node

## Headless verification for Military AI V2 foundation + army roster.
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
	await _verify_army_roster_and_squad(failures)
	_verify_assemble_config_and_source(failures)
	await _verify_assemble_slot_stability(failures)
	_verify_defend_config_and_source(failures)
	_verify_defend_priority_order(failures)
	_verify_defend_leash_helper(failures)
	_verify_attack_config_and_source(failures)
	_verify_attack_priority_order(failures)
	_verify_attack_chase_leash_helper(failures)
	_verify_retreat_recover_config_and_source(failures)
	_verify_retreat_role_split_helper(failures)
	_verify_retreat_recover_hysteresis_helpers(failures)

	var report: String
	if failures.is_empty():
		report = "PASS military_ai_v2_roster\n"
	else:
		report = "FAIL military_ai_v2_roster\n" + "\n".join(failures) + "\n"

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
	_expect(failures, "director owns empty main squad", director.get_main_squad() != null)
	_expect(failures, "main squad starts empty", director.get_main_squad().get_size() == 0)

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
	_expect(
		failures,
		"commander receives squad from director",
		text.contains("Receives the main squad from the director")
	)
	_expect(
		failures,
		"commander cannot recruit independently",
		text.contains("cannot recruit units independently")
	)
	_expect(
		failures,
		"commander does not call try_add_member",
		not text.contains("try_add_member(")
	)
	_expect(
		failures,
		"commander does not call debug_enqueue_pending",
		not text.contains("debug_enqueue_pending")
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


func _verify_army_roster_and_squad(failures: PackedStringArray) -> void:
	_verify_role_labels(failures)
	await _verify_squad_membership_lifecycle(failures)
	await _verify_director_pending_admission(failures)
	_verify_exclusion_helpers(failures)
	_verify_perf_squad_api(failures)


func _verify_assemble_config_and_source(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"creep-ready threshold configurable",
		MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS == 5
	)
	_expect(
		failures,
		"attack-ready threshold configurable",
		MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS == 10
	)

	var director_source := FileAccess.open("res://scripts/systems/military_director_v2.gd", FileAccess.READ)
	_expect(failures, "director source readable", director_source != null)
	if director_source != null:
		var text: String = director_source.get_as_text()
		director_source.close()
		_expect(failures, "director has assemble rally helper", text.contains("get_assemble_rally_point"))
		_expect(failures, "director exposes assemble forward hint", text.contains("get_assemble_forward_hint"))
		_expect(
			failures,
			"director evaluates creep strategy",
			text.contains("_evaluate_creep_strategy")
		)
		_expect(
			failures,
			"director evaluates attack strategy",
			text.contains("_evaluate_attack_strategy")
		)
		_expect(
			failures,
			"director selects strategic attack target",
			text.contains("_select_attack_strategic_target")
		)
		_expect(
			failures,
			"director detects lethal attack window",
			text.contains("_detect_lethal_attack_window")
		)
		_expect(
			failures,
			"director owns creep reservation",
			text.contains("get_reserved_creep_camp_id")
		)
		_expect(failures, "director transitions to DEFEND", text.contains("State.DEFEND,"))
		_expect(failures, "director evaluates defend strategy", text.contains("_evaluate_defend_strategy"))
		_expect(failures, "director exits defend after clear", text.contains("_exit_defend_after_clear"))
		_expect(failures, "director does not resume stale camp", text.contains("defense cleared, reassess"))
		_expect(failures, "director checks construction reservations", text.contains("ConstructionReservations.overlaps_reserved_footprint"))
		_expect(failures, "director checks construction points", text.contains("get_construction_points"))
		_expect(failures, "director checks enemy workers", text.contains("_collect_enemy_workers"))
		_expect(failures, "director checks enemy resources", text.contains("GROUP_ENEMY_RESOURCES"))
		_expect(failures, "director checks production exits", text.contains("_get_building_exit_points"))

	var commander_source := FileAccess.open("res://scripts/systems/army_commander_v2.gd", FileAccess.READ)
	_expect(failures, "commander source readable", commander_source != null)
	if commander_source != null:
		var commander_text: String = commander_source.get_as_text()
		commander_source.close()
		_expect(failures, "commander has assemble executor", commander_text.contains("_execute_assemble_mission"))
		_expect(failures, "commander has creep executor", commander_text.contains("_execute_creep_mission"))
		_expect(failures, "commander has defend executor", commander_text.contains("_execute_defend_mission"))
		_expect(failures, "commander has attack executor", commander_text.contains("_execute_attack_mission"))
		_expect(failures, "commander has retreat executor", commander_text.contains("_execute_retreat_mission"))
		_expect(failures, "commander has recover executor", commander_text.contains("_execute_recover_mission"))
		_expect(failures, "commander stages pending reinforcements", commander_text.contains("_stage_pending_reinforcements"))
		_expect(failures, "commander uses attack-move for regroup", commander_text.contains("command_attack_move"))
		_expect(failures, "commander clamps defend leash", commander_text.contains("_clamp_defend_destination"))
		_expect(failures, "commander clamps attack chase", commander_text.contains("_clamp_attack_chase_destination"))
		_expect(failures, "commander splits defend roles", commander_text.contains("_split_defend_roles"))
		_expect(failures, "commander splits retreat roles", commander_text.contains("_split_retreat_roles"))
		_expect(failures, "commander settles assembled units", commander_text.contains("_settle_unit"))
		_expect(failures, "commander keeps stable slots", commander_text.contains("_assemble_role_slots"))
		_expect(failures, "commander uses forward hint", commander_text.contains("get_assemble_forward_hint"))


func _verify_defend_config_and_source(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"defend leash configurable",
		MilitaryAIConfig.V2_DEFEND_LEASH_RADIUS == 42.0
	)
	_expect(
		failures,
		"defend clear seconds configurable",
		MilitaryAIConfig.V2_DEFEND_THREAT_CLEAR_SECONDS == 5.0
	)
	_expect(
		failures,
		"defend ranged standoff configurable",
		MilitaryAIConfig.V2_DEFEND_RANGED_STANDOFF == 7.0
	)

	var director_source := FileAccess.open("res://scripts/systems/military_director_v2.gd", FileAccess.READ)
	_expect(failures, "defend director source readable", director_source != null)
	if director_source != null:
		var text: String = director_source.get_as_text()
		director_source.close()
		_expect(failures, "defend overrides other states", text.contains("DEFEND always wins"))
		_expect(failures, "defend triggers on emergency threat", text.contains("evaluate_emergency_defense_threat"))
		_expect(failures, "defend triggers on worker threat", text.contains("evaluate_defense_threat"))
		_expect(failures, "defend activates emergency recall", text.contains("activate_emergency_defense"))
		_expect(failures, "defend exits to recover when damaged", text.contains("State.RECOVER"))
		_expect(failures, "defend picks focus target", text.contains("_pick_defend_focus_target"))
		_expect(failures, "defend formats F3 reason", text.contains("_format_defend_reason"))

	var combat_source := FileAccess.open("res://scripts/systems/combat_target_validation.gd", FileAccess.READ)
	_expect(failures, "combat priority source readable", combat_source != null)
	if combat_source != null:
		var combat_text: String = combat_source.get_as_text()
		combat_source.close()
		_expect(
			failures,
			"defense priority town hall attacker",
			combat_text.contains("ENEMY_DEFENSE_PRIORITY_TOWN_HALL_ATTACKER")
		)
		_expect(
			failures,
			"defense priority siege",
			combat_text.contains("ENEMY_DEFENSE_PRIORITY_SIEGE")
		)
		_expect(
			failures,
			"defense priority ranged",
			combat_text.contains("ENEMY_DEFENSE_PRIORITY_RANGED")
		)
		_expect(
			failures,
			"defense ignores buildings while military threatens",
			combat_text.contains("Never prioritize buildings")
		)


func _verify_defend_priority_order(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"town hall attackers outrank heroes",
		CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_TOWN_HALL_ATTACKER
		< CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_HERO
	)
	_expect(
		failures,
		"heroes outrank siege",
		CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_HERO
		< CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_SIEGE
	)
	_expect(
		failures,
		"siege outranks ranged",
		CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_SIEGE
		< CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_RANGED
	)
	_expect(
		failures,
		"ranged outranks other military",
		CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_RANGED
		< CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_MILITARY
	)


func _verify_defend_leash_helper(failures: PackedStringArray) -> void:
	var commander := ArmyCommanderV2.new()
	add_child(commander)
	commander.reset_match_state()

	var base := Vector3(5.0, 0.0, 5.0)
	var inside := Vector3(15.0, 0.0, 5.0)
	var far := Vector3(125.0, 0.0, 5.0)
	var clamped: Vector3 = commander._clamp_defend_destination(base, far)
	_expect(
		failures,
		"leash leaves near threats unchanged",
		commander._clamp_defend_destination(base, inside) == inside
	)
	_expect(
		failures,
		"leash clamps far chase",
		is_equal_approx(
			EnemyArmyCommand.horizontal_distance(base, clamped),
			MilitaryAIConfig.V2_DEFEND_LEASH_RADIUS
		)
	)
	_expect(
		failures,
		"leash points toward original chase",
		clamped.x > base.x
	)
	commander.queue_free()


func _verify_attack_config_and_source(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"attack-ready threshold configurable",
		MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS == 10
	)
	_expect(
		failures,
		"attack preferred band configurable",
		MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS_PREFERRED == 12
	)
	_expect(
		failures,
		"attack lethal min configurable",
		MilitaryAIConfig.V2_ATTACK_LETHAL_MIN_MILITARY_UNITS == 6
	)
	_expect(
		failures,
		"attack chase leash configurable",
		MilitaryAIConfig.V2_ATTACK_CHASE_LEASH == 22.0
	)
	_expect(
		failures,
		"attack lethal score threshold configurable",
		MilitaryAIConfig.V2_ATTACK_LETHAL_SCORE_THRESHOLD == 70.0
	)

	var director := MilitaryDirectorV2.new()
	add_child(director)
	director.reset_match_state()
	_expect(failures, "attack ready false on empty squad", director.is_attack_ready() == false)
	_expect(
		failures,
		"attack ready alias matches",
		director.is_attack_ready() == director.is_attack_ready_placeholder()
	)
	director.queue_free()

	var director_source := FileAccess.open("res://scripts/systems/military_director_v2.gd", FileAccess.READ)
	_expect(failures, "attack director source readable", director_source != null)
	if director_source != null:
		var text: String = director_source.get_as_text()
		director_source.close()
		_expect(failures, "attack preempts creep", text.contains("preempts CREEP"))
		_expect(failures, "attack exits to retreat when losing", text.contains("army clearly losing"))
		_expect(failures, "attack exits when hero endangered", text.contains("hero in serious danger"))
		_expect(failures, "attack exits when scattered", text.contains("attack army too scattered"))
		_expect(failures, "attack admits no mid-fight reinforcements", text.contains("_can_admit_reinforcements"))
		_expect(failures, "attack commits to town hall", text.contains("_should_commit_to_town_hall"))

	var commander_source := FileAccess.open("res://scripts/systems/army_commander_v2.gd", FileAccess.READ)
	_expect(failures, "attack commander source readable", commander_source != null)
	if commander_source != null:
		var commander_text: String = commander_source.get_as_text()
		commander_source.close()
		_expect(failures, "attack uses Attack-Move", commander_text.contains("Mission.ATTACK"))
		_expect(failures, "attack resumes strategic route", commander_text.contains("strategic_destination"))
		_expect(failures, "attack stops endless chase", commander_text.contains("V2_ATTACK_CHASE_DURATION_SECONDS"))


func _verify_attack_priority_order(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"route-blocking army outranks town hall",
		CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_ROUTE_BLOCKING_ARMY
		< CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_TOWN_HALL
	)
	_expect(
		failures,
		"town hall outranks dangerous towers",
		CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_TOWN_HALL
		< CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_DANGEROUS_TOWER
	)
	_expect(
		failures,
		"towers outrank production",
		CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_DANGEROUS_TOWER
		< CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_PRODUCTION
	)
	_expect(
		failures,
		"production outranks workers",
		CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_PRODUCTION
		< CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_WORKER
	)
	_expect(
		failures,
		"workers outrank other structures",
		CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_WORKER
		< CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_OTHER_STRUCTURE
	)


func _verify_attack_chase_leash_helper(failures: PackedStringArray) -> void:
	var commander := ArmyCommanderV2.new()
	add_child(commander)
	commander.reset_match_state()

	var strategic := Vector3(5.0, 0.0, 5.0)
	var near := Vector3(15.0, 0.0, 5.0)
	var far := Vector3(125.0, 0.0, 5.0)
	var clamped: Vector3 = commander._clamp_attack_chase_destination(strategic, far)
	_expect(
		failures,
		"attack chase leaves near targets unchanged",
		commander._clamp_attack_chase_destination(strategic, near) == near
	)
	_expect(
		failures,
		"attack chase clamps far pursuit",
		is_equal_approx(
			EnemyArmyCommand.horizontal_distance(strategic, clamped),
			MilitaryAIConfig.V2_ATTACK_CHASE_LEASH
		)
	)
	_expect(
		failures,
		"attack chase points toward pursuit",
		clamped.x > strategic.x
	)
	commander.queue_free()


func _verify_retreat_recover_config_and_source(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"retreat strength ratio configurable",
		MilitaryAIConfig.V2_RETREAT_STRENGTH_RATIO == 0.55
	)
	_expect(
		failures,
		"attack reentry hysteresis configurable",
		MilitaryAIConfig.V2_ATTACK_REENTRY_STRENGTH_RATIO == 1.15
	)
	_expect(
		failures,
		"state commit seconds configurable",
		MilitaryAIConfig.V2_STATE_COMMIT_SECONDS == 3.0
	)
	_expect(
		failures,
		"post-retreat attack cooldown configurable",
		MilitaryAIConfig.V2_POST_RETREAT_ATTACK_COOLDOWN_SECONDS == 6.0
	)
	_expect(
		failures,
		"recover min seconds configurable",
		MilitaryAIConfig.V2_RECOVER_MIN_SECONDS == 4.0
	)
	_expect(
		failures,
		"recover max seconds configurable",
		MilitaryAIConfig.V2_RECOVER_MAX_SECONDS == 18.0
	)
	_expect(
		failures,
		"recover hero hp not full",
		MilitaryAIConfig.V2_RECOVER_HERO_HP_RATIO < 1.0
		and MilitaryAIConfig.V2_RECOVER_HERO_HP_RATIO > MilitaryAIConfig.V2_RETREAT_HERO_HP_RATIO
	)
	_expect(
		failures,
		"recover min military configurable",
		MilitaryAIConfig.V2_RECOVER_MIN_MILITARY_UNITS == 5
	)

	var director_source := FileAccess.open("res://scripts/systems/military_director_v2.gd", FileAccess.READ)
	_expect(failures, "retreat director source readable", director_source != null)
	if director_source != null:
		var text: String = director_source.get_as_text()
		director_source.close()
		_expect(failures, "director evaluates retreat triggers", text.contains("_evaluate_retreat_triggers"))
		_expect(failures, "director begins retreat from losing fights", text.contains("_maybe_begin_retreat"))
		_expect(failures, "director evaluates recover strategy", text.contains("_evaluate_recover_strategy"))
		_expect(failures, "director resolves retreat destination", text.contains("_resolve_retreat_destination"))
		_expect(failures, "director prefers tower coverage", text.contains("_find_tower_cover_point"))
		_expect(failures, "director reports frontline losses", text.contains("frontline losses critical"))
		_expect(failures, "director reports enemy reinforcements", text.contains("enemy reinforcements unfavorable"))
		_expect(failures, "director reports unwinnable fights", text.contains("fight unwinnable"))
		_expect(failures, "director formats recover hold reason", text.contains("_format_recover_hold_reason"))
		_expect(failures, "director has recover timeout", text.contains("recover timeout, reassembling"))
		_expect(failures, "director blocks attack reentry hysteresis", text.contains("_can_reenter_attack"))
		_expect(failures, "director preserves recovery point", text.contains("get_designated_recovery_point"))
		_expect(failures, "director commits state minimum", text.contains("_has_met_state_commitment"))

	var commander_source := FileAccess.open("res://scripts/systems/army_commander_v2.gd", FileAccess.READ)
	_expect(failures, "retreat commander source readable", commander_source != null)
	if commander_source != null:
		var commander_text: String = commander_source.get_as_text()
		commander_source.close()
		_expect(failures, "retreat preserves hero with withdraw group", commander_text.contains("Preserve the hero"))
		_expect(failures, "retreat ranged and siege withdraw first", commander_text.contains("Ranged/siege leave first"))
		_expect(failures, "retreat frontline covers briefly", commander_text.contains("Frontline may briefly cover"))
		_expect(failures, "retreat pulls stragglers", commander_text.contains("_pull_retreat_stragglers"))
		_expect(failures, "retreat uses order reissue timer", commander_text.contains("V2_RETREAT_ORDER_REISSUE_SECONDS"))
		_expect(failures, "recover holds near base", commander_text.contains("_execute_recover_mission"))


func _verify_retreat_role_split_helper(failures: PackedStringArray) -> void:
	var commander := ArmyCommanderV2.new()
	add_child(commander)
	commander.reset_match_state()

	var squad := ArmySquadV2.new()
	var frontline := Node3D.new()
	frontline.name = "RetreatFrontline"
	var ranged := Node3D.new()
	ranged.name = "RetreatRanged"
	var siege := Node3D.new()
	siege.name = "RetreatSiege"
	var hero_stub := Node3D.new()
	hero_stub.name = "RetreatHero"
	add_child(frontline)
	add_child(ranged)
	add_child(siege)
	add_child(hero_stub)

	_expect(failures, "retreat frontline joins", squad.try_add_member(frontline, ArmySquadV2.UnitRole.FRONTLINE))
	_expect(failures, "retreat ranged joins", squad.try_add_member(ranged, ArmySquadV2.UnitRole.RANGED))
	_expect(failures, "retreat siege joins", squad.try_add_member(siege, ArmySquadV2.UnitRole.SIEGE))
	_expect(failures, "retreat hero joins", squad.try_add_member(hero_stub, ArmySquadV2.UnitRole.HERO))

	var army: Array = [frontline, ranged, siege, hero_stub]
	var withdraw: Array = []
	var cover: Array = []
	commander._split_retreat_roles(squad, army, withdraw, cover)

	_expect(failures, "hero withdraws with safe group", withdraw.has(hero_stub))
	_expect(failures, "ranged withdraws safely", withdraw.has(ranged))
	_expect(failures, "siege withdraws safely", withdraw.has(siege))
	_expect(failures, "frontline covers withdrawal", cover.has(frontline))
	_expect(failures, "hero is not left covering alone", not cover.has(hero_stub))

	var army_center := Vector3(5.0, 0.0, 5.0)
	var rally := Vector3(25.0, 0.0, 5.0)
	var threat := Vector3(-10.0, 0.0, 5.0)
	var cover_point: Vector3 = commander._resolve_retreat_cover_point(army_center, rally, threat)
	_expect(
		failures,
		"cover point leans toward recovery",
		cover_point.x > army_center.x
	)
	_expect(
		failures,
		"cover offset is brief not suicidal",
		EnemyArmyCommand.horizontal_distance(army_center, cover_point)
		<= MilitaryAIConfig.V2_RETREAT_COVER_OFFSET + 0.1
	)

	frontline.queue_free()
	ranged.queue_free()
	siege.queue_free()
	hero_stub.queue_free()
	commander.queue_free()


func _verify_retreat_recover_hysteresis_helpers(failures: PackedStringArray) -> void:
	var director := MilitaryDirectorV2.new()
	add_child(director)
	director.reset_match_state()

	## Empty army never falsely forces retreat.
	var no_fight: Dictionary = director._evaluate_retreat_triggers(get_tree(), [])
	_expect(failures, "empty army does not retreat", not bool(no_fight.get("should_retreat", true)))

	## Recover readiness requires hero + minimum squad — never perfection alone.
	_expect(failures, "recover not ready without army", not director._is_recover_ready(get_tree()))
	var hold_reason: String = director._format_recover_hold_reason(get_tree())
	_expect(failures, "recover hold reason reports awaiting hero", hold_reason.contains("awaiting hero"))

	## Post-retreat attack cooldown blocks immediate re-entry (no ATTACK↔RETREAT loop).
	director._post_retreat_attack_cooldown = MilitaryAIConfig.V2_POST_RETREAT_ATTACK_COOLDOWN_SECONDS
	director._state_entered_msec = Time.get_ticks_msec()
	_expect(
		failures,
		"state commitment blocks soft exits",
		not director._has_met_state_commitment()
	)
	## With no nearby enemies, reentry is allowed even during cooldown (rebuild-and-push).
	_expect(
		failures,
		"reentry allowed when no nearby enemies",
		director._can_reenter_attack(get_tree(), Vector3(1, 0, 1))
	)

	## Recover hard ceiling prevents endless RECOVER.
	_expect(
		failures,
		"recover max exceeds min hold",
		MilitaryAIConfig.V2_RECOVER_MAX_SECONDS > MilitaryAIConfig.V2_RECOVER_MIN_SECONDS
	)
	_expect(
		failures,
		"attack reentry stronger than retreat trigger",
		MilitaryAIConfig.V2_ATTACK_REENTRY_STRENGTH_RATIO
		> MilitaryAIConfig.V2_RETREAT_STRENGTH_RATIO
	)

	director.queue_free()


func _verify_assemble_slot_stability(failures: PackedStringArray) -> void:
	var root := Node.new()
	root.name = "AssembleHarness"
	add_child(root)

	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	root.add_child(director)
	director.reset_match_state()

	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	root.add_child(commander)
	commander.reset_match_state()

	var frontline := Node3D.new()
	frontline.name = "Frontline"
	var ranged := Node3D.new()
	ranged.name = "Ranged"
	var siege := Node3D.new()
	siege.name = "Siege"
	var hero_stub := Node3D.new()
	hero_stub.name = "HeroStub"
	root.add_child(frontline)
	root.add_child(ranged)
	root.add_child(siege)
	root.add_child(hero_stub)

	var squad: ArmySquadV2 = director.get_main_squad()
	_expect(failures, "frontline joins assemble test squad", squad.try_add_member(frontline, ArmySquadV2.UnitRole.FRONTLINE))
	_expect(failures, "ranged joins assemble test squad", squad.try_add_member(ranged, ArmySquadV2.UnitRole.RANGED))
	_expect(failures, "siege joins assemble test squad", squad.try_add_member(siege, ArmySquadV2.UnitRole.SIEGE))
	_expect(failures, "hero joins assemble test squad", squad.try_add_member(hero_stub, ArmySquadV2.UnitRole.HERO))

	var rally := Vector3(10.0, 0.0, 10.0)
	var first_slots: Dictionary = commander.debug_get_assemble_slot_positions(rally)
	_expect(failures, "assemble slots created", first_slots.size() == 4)
	_expect(
		failures,
		"frontline ahead of ranged",
		(first_slots[frontline.get_instance_id()] as Vector3).z > (first_slots[ranged.get_instance_id()] as Vector3).z
	)
	_expect(
		failures,
		"siege behind ranged",
		(first_slots[siege.get_instance_id()] as Vector3).z < (first_slots[ranged.get_instance_id()] as Vector3).z
	)

	var reinforcement := Node3D.new()
	reinforcement.name = "Reinforcement"
	root.add_child(reinforcement)
	_expect(
		failures,
		"reinforcement joins assemble test squad",
		squad.try_add_member(reinforcement, ArmySquadV2.UnitRole.RANGED)
	)

	var second_slots: Dictionary = commander.debug_get_assemble_slot_positions(rally)
	_expect(failures, "reinforcement gets a slot", second_slots.has(reinforcement.get_instance_id()))
	_expect(
		failures,
		"existing frontline slot stable after reinforcement",
		first_slots[frontline.get_instance_id()] == second_slots[frontline.get_instance_id()]
	)
	_expect(
		failures,
		"existing ranged slot stable after reinforcement",
		first_slots[ranged.get_instance_id()] == second_slots[ranged.get_instance_id()]
	)
	_expect(
		failures,
		"reinforcement does not stack on existing ranged slot",
		second_slots[reinforcement.get_instance_id()] != second_slots[ranged.get_instance_id()]
	)

	root.queue_free()
	await get_tree().process_frame


func _verify_role_labels(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"role frontline label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.FRONTLINE) == "frontline"
	)
	_expect(
		failures,
		"role melee_guard label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.MELEE_GUARD) == "melee_guard"
	)
	_expect(
		failures,
		"role ranged label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.RANGED) == "ranged"
	)
	_expect(
		failures,
		"role cavalry label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.CAVALRY) == "cavalry"
	)
	_expect(
		failures,
		"role siege label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.SIEGE) == "siege"
	)
	_expect(
		failures,
		"role hero label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.HERO) == "hero"
	)


func _verify_squad_membership_lifecycle(failures: PackedStringArray) -> void:
	var squad := ArmySquadV2.new()
	var unit_a := Node3D.new()
	var unit_b := Node3D.new()
	unit_a.name = "StubA"
	unit_b.name = "StubB"
	add_child(unit_a)
	add_child(unit_b)

	_expect(
		failures,
		"units join squad",
		squad.try_add_member(unit_a, ArmySquadV2.UnitRole.FRONTLINE)
	)
	_expect(
		failures,
		"second unit joins squad",
		squad.try_add_member(unit_b, ArmySquadV2.UnitRole.RANGED)
	)
	_expect(failures, "squad size 2 after joins", squad.get_size() == 2)
	_expect(
		failures,
		"no duplicated squad members",
		squad.try_add_member(unit_a, ArmySquadV2.UnitRole.FRONTLINE) == false
	)
	_expect(failures, "squad size still 2 after dup", squad.get_size() == 2)

	squad.recompute_metrics()
	_expect(failures, "role count frontline", squad.get_role_count(ArmySquadV2.UnitRole.FRONTLINE) == 1)
	_expect(failures, "role count ranged", squad.get_role_count(ArmySquadV2.UnitRole.RANGED) == 1)
	_expect(failures, "hero absent without hero", squad.hero_present == false)
	_expect(failures, "squad has leader/anchor", squad.leader != null)

	var dead_id: int = unit_a.get_instance_id()
	unit_a.queue_free()
	await get_tree().process_frame
	var removed: int = squad.sanitize()
	_expect(failures, "dead units leave safely", removed >= 1)
	_expect(failures, "squad size 1 after death", squad.get_size() == 1)
	_expect(failures, "no stale freed member id", squad.remove_by_instance_id(dead_id) == false)
	_expect(failures, "living member remains", squad.has_member(unit_b))

	unit_b.queue_free()
	await get_tree().process_frame
	squad.sanitize()
	_expect(failures, "squad empty after all freed", squad.get_size() == 0)


func _verify_director_pending_admission(failures: PackedStringArray) -> void:
	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	add_child(director)
	director.reset_match_state()

	var pending_unit := Node3D.new()
	pending_unit.name = "PendingStub"
	add_child(pending_unit)

	_expect(
		failures,
		"director enqueues pending reinforcement",
		director.debug_enqueue_pending_for_tests(pending_unit)
	)
	_expect(
		failures,
		"pending not in squad yet",
		director.get_main_squad().has_member(pending_unit) == false
	)
	_expect(
		failures,
		"pending list contains unit",
		director.get_pending_reinforcements_copy().size() == 1
	)

	director.debug_admit_pending_for_tests()
	_expect(
		failures,
		"units join when admitted (trained join path)",
		director.get_main_squad().has_member(pending_unit)
	)
	_expect(
		failures,
		"pending cleared after admit",
		director.get_pending_reinforcements_copy().is_empty()
	)
	_expect(failures, "no duplicate after re-enqueue", director.debug_enqueue_pending_for_tests(pending_unit) == false)

	## Immediate removal on tree exit.
	var pending_id: int = pending_unit.get_instance_id()
	pending_unit.queue_free()
	await get_tree().process_frame
	director.get_main_squad().sanitize()
	_expect(
		failures,
		"freed unit removed from squad",
		director.get_main_squad().get_size() == 0
	)
	_expect(
		failures,
		"no stale id membership",
		director.get_main_squad().remove_by_instance_id(pending_id) == false
	)

	## Commander receives squad but does not own membership mutation APIs in script.
	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	add_child(commander)
	var received: ArmySquadV2 = commander.get_active_squad()
	_expect(failures, "commander receives director squad", received == director.get_main_squad())

	commander.queue_free()
	director.queue_free()


func _verify_exclusion_helpers(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"null never roster eligible",
		ArmySquadV2.is_roster_eligible(null) == false
	)

	var orphan := Node3D.new()
	_expect(
		failures,
		"out-of-tree unit not eligible",
		ArmySquadV2.is_roster_eligible(orphan) == false
	)
	orphan.free()

	## Worker / building / creep exclusion gates live in ArmySquadV2.
	var source := FileAccess.open("res://scripts/systems/army_squad_v2.gd", FileAccess.READ)
	_expect(failures, "squad script readable", source != null)
	if source != null:
		var text: String = source.get_as_text()
		source.close()
		_expect(failures, "workers never join (eligible gate)", text.contains("unit is Worker"))
		_expect(failures, "buildings excluded", text.contains("unit is Building"))
		_expect(failures, "creeps excluded", text.contains("unit is NeutralCreep"))
		_expect(failures, "combat unit required", text.contains("is_combat_unit"))
		_expect(failures, "hero joins via Hero role", text.contains("unit is Hero"))
		_expect(failures, "hero role enum present", text.contains("UnitRole.HERO"))

	var director_source := FileAccess.open("res://scripts/systems/military_director_v2.gd", FileAccess.READ)
	_expect(failures, "director script readable", director_source != null)
	if director_source != null:
		var director_text: String = director_source.get_as_text()
		director_source.close()
		_expect(
			failures,
			"director owns squad membership",
			director_text.contains("Owns the authoritative army roster")
		)
		_expect(
			failures,
			"reinforcements wait for safe states",
			director_text.contains("_can_admit_reinforcements")
		)
		_expect(
			failures,
			"never solo-push pending units",
			director_text.contains("Never send them alone across the map")
		)


func _verify_perf_squad_api(failures: PackedStringArray) -> void:
	PerfCounters.set_military_ai_v2_squad_status(7, true, "F2 G1 R2 C1 S1 H1", 420.0)
	_expect(failures, "F3 squad size", PerfCounters.get_military_ai_v2_squad_size() == 7)
	_expect(failures, "F3 hero present", PerfCounters.get_military_ai_v2_hero_present() == true)
	_expect(
		failures,
		"F3 role counts",
		PerfCounters.get_military_ai_v2_role_counts() == "F2 G1 R2 C1 S1 H1"
	)
	_expect(
		failures,
		"F3 estimated army strength",
		is_equal_approx(PerfCounters.get_military_ai_v2_army_strength(), 420.0)
	)

	var overlay_source := FileAccess.open("res://scripts/debug/perf_debug_overlay.gd", FileAccess.READ)
	_expect(failures, "overlay script readable", overlay_source != null)
	if overlay_source != null:
		var text: String = overlay_source.get_as_text()
		overlay_source.close()
		_expect(failures, "overlay shows V2 Squad Size", text.contains("V2 Squad Size"))
		_expect(failures, "overlay shows V2 Hero Present", text.contains("V2 Hero Present"))
		_expect(failures, "overlay shows V2 Role Counts", text.contains("V2 Role Counts"))
		_expect(failures, "overlay shows V2 Army Strength", text.contains("V2 Army Strength"))
