extends Node

## Headless verification for PHASE 2 match composition root / AIPlayerState /
## declared military command authority.
## Godot --headless --path <project> --scene res://scenes/debug/verify_match_composition_root.tscn

const REPORT_PATH := "user://match_composition_root_verify_result.txt"


func _ready() -> void:
	var failures: PackedStringArray = []

	_verify_scene_wiring(failures)
	await _verify_runtime_binding(failures)
	await _verify_authority_declaration(failures)
	await _verify_identity_sync_and_unbind(failures)

	var report: String
	if failures.is_empty():
		report = "PASS match_composition_root\n"
	else:
		report = "FAIL match_composition_root\n" + "\n".join(failures) + "\n"

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


func _make_minimal_composition() -> MatchCompositionRoot:
	## Avoid full match_systems (MatchManager / BuildManager need map CC nodes).
	var root := MatchCompositionRoot.new()
	root.name = "MatchSystems"

	var state := AIPlayerState.new()
	state.name = "AIPlayerState"
	root.add_child(state)

	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	root.add_child(director)

	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	root.add_child(commander)

	var combat := EnemyCombatController.new()
	combat.name = "EnemyCombatController"
	root.add_child(combat)

	var strategic := EnemyStrategicDirector.new()
	strategic.name = "EnemyStrategicDirector"
	strategic.debug_enabled = false
	root.add_child(strategic)

	return root


func _free_composition(root: Node) -> void:
	if root == null:
		return
	root.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_scene_wiring(failures: PackedStringArray) -> void:
	var packed: PackedScene = load("res://scenes/match/match_systems.tscn") as PackedScene
	_expect(failures, "match_systems.tscn loads", packed != null)
	if packed == null:
		return

	var systems: Node = packed.instantiate()
	_expect(failures, "MatchSystems is MatchCompositionRoot", systems is MatchCompositionRoot)
	var root: MatchCompositionRoot = systems as MatchCompositionRoot
	_expect(
		failures,
		"AIPlayerState child present in packed scene",
		root != null and root.get_node_or_null("AIPlayerState") is AIPlayerState
	)
	_expect(
		failures,
		"ArmyCommanderV2 child present",
		root != null and root.get_node_or_null("ArmyCommanderV2") is ArmyCommanderV2
	)
	_expect(
		failures,
		"MilitaryDirectorV2 child present",
		root != null and root.get_node_or_null("MilitaryDirectorV2") is MilitaryDirectorV2
	)
	systems.free()


func _verify_runtime_binding(failures: PackedStringArray) -> void:
	var root: MatchCompositionRoot = _make_minimal_composition()
	add_child(root)
	await get_tree().process_frame

	_expect(failures, "runtime: composition root typed", root != null)
	_expect(failures, "runtime: ai_player_state resolved", root.ai_player_state != null)
	_expect(
		failures,
		"runtime: EnemyArmyCommand bound to AIPlayerState",
		EnemyArmyCommand.get_bound_ai_player_state() == root.ai_player_state
	)
	_expect(
		failures,
		"runtime: find_from_tree finds MatchSystems",
		MatchCompositionRoot.find_from_tree(get_tree()) == root
	)
	_expect(
		failures,
		"runtime: strategic director via composition",
		EnemyArmyCommand.find_strategic_director(get_tree()) == root.enemy_strategic_director
	)

	await _free_composition(root)
	_expect(
		failures,
		"runtime: unbind after free",
		EnemyArmyCommand.get_bound_ai_player_state() == null
	)


func _verify_authority_declaration(failures: PackedStringArray) -> void:
	var root: MatchCompositionRoot = _make_minimal_composition()
	add_child(root)
	await get_tree().process_frame

	_expect(failures, "authority: V2 enabled in production config", MilitaryAIConfig.is_v2_enabled())
	_expect(
		failures,
		"authority: declared ArmyCommanderV2",
		root.military_command_authority is ArmyCommanderV2
	)
	_expect(
		failures,
		"authority: EnemyArmyCommand sees same issuer",
		EnemyArmyCommand.get_declared_command_authority() == root.army_commander_v2
	)
	_expect(
		failures,
		"authority: AIPlayerState records commander name",
		root.ai_player_state != null
		and root.ai_player_state.military_command_authority_name == &"ArmyCommanderV2"
	)
	_expect(failures, "authority: is_v2_military_active", root.is_v2_military_active())

	await _free_composition(root)


func _verify_identity_sync_and_unbind(failures: PackedStringArray) -> void:
	var root: MatchCompositionRoot = _make_minimal_composition()
	add_child(root)
	await get_tree().process_frame

	if root.ai_player_state == null:
		_expect(failures, "identity: root + state", false)
		await _free_composition(root)
		return

	var state: AIPlayerState = root.ai_player_state
	_expect(failures, "identity: starts IDLE/ECONOMY", state.army_mode == 0 and state.strategic_state == 0)

	EnemyArmyCommand.force_set_strategic_state_for_v2(
		EnemyArmyCommand.StrategicState.ATTACKING,
		"composition verify"
	)
	_expect(
		failures,
		"identity: strategic sync to AIPlayerState",
		state.strategic_state == int(EnemyArmyCommand.StrategicState.ATTACKING)
	)

	var claimed: bool = EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.ATTACKING, true)
	_expect(failures, "identity: claim ATTACKING", claimed)
	_expect(
		failures,
		"identity: army mode sync to AIPlayerState",
		state.army_mode == int(EnemyArmyCommand.ArmyMode.ATTACKING)
	)

	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER,
		"composition verify exec",
		null,
		Vector3(12.0, 0.0, 8.0),
		"VerifyCC",
		"attack-move"
	)
	_expect(
		failures,
		"exec: mission sync to AIPlayerState",
		state.exec_mission == int(EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER)
	)
	_expect(
		failures,
		"exec: objective position sync",
		state.exec_objective_position.is_equal_approx(Vector3(12.0, 0.0, 8.0))
	)
	_expect(
		failures,
		"exec: order label sync",
		state.exec_order_label == "attack-move"
	)

	EnemyArmyCommand.set_rebuilding_army(true)
	_expect(failures, "combat: rebuilding SoT", state.is_rebuilding_army)
	EnemyArmyCommand.begin_fight_tracking([], Vector3(3.0, 0.0, 1.0))
	_expect(
		failures,
		"combat: fight anchor SoT",
		state.fight_anchor_position.is_equal_approx(Vector3(3.0, 0.0, 1.0))
	)

	## Wave / formation / finishing SoT (no duplicate authority).
	state.attack_wave_state = int(EnemyArmyCommand.AttackWaveState.ADVANCING)
	state.attack_wave_staging_point = Vector3(9.0, 0.0, 4.0)
	state.finishing_mode_active = true
	state.formation_cache_center = Vector3(2.0, 0.0, 2.0)
	state.formation_cache_army_mode = int(EnemyArmyCommand.ArmyMode.ATTACKING)
	_expect(
		failures,
		"wave: SoT readable via EnemyArmyCommand accessors",
		EnemyArmyCommand.get_attack_wave_state() == EnemyArmyCommand.AttackWaveState.ADVANCING
	)
	_expect(failures, "finishing: SoT active", EnemyArmyCommand.is_finishing_mode_active())
	_expect(
		failures,
		"formation: SoT center shared",
		state.formation_cache_center.is_equal_approx(Vector3(2.0, 0.0, 2.0))
	)

	await _verify_intent_bus(failures, state)
	await _verify_authority_and_providers(failures, root, state)
	_verify_runtime_ephemeral_ownership(failures, state)
	_verify_final_static_state_ownership(failures, state)

	## Dirty high-risk bags + frame caches before prepare_new_match.
	state.pending_group_orders = [{
		"verify": true,
		"target": Vector3(5.0, 0.0, 5.0),
		"use_attack_move": true,
	}]
	state.issuing_group_order_batch = true
	state.reinforcement_pool[4242] = {
		"rally": Vector3(1.0, 0.0, 1.0),
		"registered_msec": 1,
	}
	state.defense_threat_cache = {"verify_threat": 9.0}
	state.defense_threat_cache_msec = Time.get_ticks_msec()
	state.emergency_threat_cache = {"verify_emergency": 8.0}
	state.emergency_threat_cache_msec = Time.get_ticks_msec()
	state.exec_watchdog_timer = 99.0
	state.exec_watchdog_refreshed = true
	state.exec_last_progress_msec = Time.get_ticks_msec() - 120000
	state.exec_squad_ids = [1, 2, 3]
	EnemyArmyCommand.seed_frame_local_caches_for_verify()
	EnemyArmyCommand.seed_leftover_runtime_state_for_verify()
	EnemyArmyCommandTelemetry.seed_for_verify()
	_expect(
		failures,
		"ephemeral: pending orders seeded before reset",
		EnemyArmyCommand.get_pending_group_order_count() == 1
	)
	_expect(
		failures,
		"ephemeral: frame caches seeded before reset",
		int(EnemyArmyCommand.get_frame_local_cache_snapshot_for_verify()["main_army_cache_size"]) > 0
	)
	_expect(
		failures,
		"leftover: creep contest + objective timers seeded before reset",
		EnemyArmyCommand.get_creep_contest_cooldown_count_for_verify() == 1
		and state.objective_reissue_timer > 0.0
		and state.objective_eval_timer > 0.0
	)

	MatchSession.prepare_new_match()
	_expect(
		failures,
		"identity: prepare_new_match clears AIPlayerState mode",
		state.army_mode == 0 and state.strategic_state == 0
	)
	_expect(
		failures,
		"exec: prepare_new_match clears exec mission",
		state.exec_mission == 0 and state.exec_order_label.is_empty()
	)
	_expect(
		failures,
		"combat: prepare_new_match clears rebuilding/fight",
		not state.is_rebuilding_army and state.fight_start_msec == 0
	)
	_expect(
		failures,
		"wave: prepare_new_match clears attack wave",
		state.attack_wave_state == 0
		and state.attack_wave_staging_point == Vector3.ZERO
	)
	_expect(
		failures,
		"formation: prepare_new_match clears formation cache",
		state.formation_cache_army_mode == -1
		and state.formation_cache_center == Vector3.ZERO
	)
	_expect(
		failures,
		"finishing: prepare_new_match clears finishing mode",
		not state.finishing_mode_active
	)
	_expect(
		failures,
		"intent: prepare_new_match clears bus + accepted",
		state.pending_intent_count() == 0 and not state.has_live_accepted_intent()
	)
	_expect(
		failures,
		"queue: pending group orders cannot survive reset",
		state.pending_group_orders.is_empty()
		and EnemyArmyCommand.get_pending_group_order_count() == 0
		and not state.issuing_group_order_batch
	)
	_expect(
		failures,
		"reinforcement: pool cleared; sole owner is AIPlayerState",
		state.reinforcement_pool.is_empty()
		and EnemyArmyCommand.get_reinforcement_pool_count() == 0
	)
	_expect(
		failures,
		"threat: TTL caches cleared on reset (not authoritative)",
		state.defense_threat_cache.is_empty()
		and state.emergency_threat_cache.is_empty()
		and state.defense_threat_cache_msec == 0
		and state.emergency_threat_cache_msec == 0
	)
	_expect(
		failures,
		"watchdog: scratch cannot survive reset",
		state.exec_watchdog_timer == 0.0
		and not state.exec_watchdog_refreshed
		and state.exec_last_progress_msec == 0
		and state.exec_squad_ids.is_empty()
		and state.exec_objective_node == null
	)
	_expect(
		failures,
		"creep contest: cooldowns cannot survive reset",
		state.creep_contest_cooldowns.is_empty()
		and EnemyArmyCommand.get_creep_contest_cooldown_count_for_verify() == 0
	)
	_expect(
		failures,
		"objective timers: cannot survive reset",
		state.objective_reissue_timer == 0.0
		and state.objective_stuck_timer == 0.0
		and state.objective_last_building_health == -1
		and state.objective_eval_timer == 0.0
		and state.objective_stuck_check_timer == 0.0
	)
	var frame_after: Dictionary = EnemyArmyCommand.get_frame_local_cache_snapshot_for_verify()
	_expect(
		failures,
		"frame: caches empty or reconstructed after reset",
		int(frame_after["combat_units_cache_frame"]) == -1
		and int(frame_after["offensive_wave_cache_frame"]) == -1
		and int(frame_after["main_army_cache_size"]) == 0
		and int(frame_after["offensive_wave_cache_size"]) == 0
		and int(frame_after["last_combat_eval_msec"]) == 0
	)
	var telemetry_after: Dictionary = EnemyArmyCommandTelemetry.snapshot_for_verify()
	_expect(
		failures,
		"telemetry: cleared on reset (non-authoritative)",
		float(telemetry_after["perf_diag_timer"]) == 0.0
		and int(telemetry_after["orders_issued_since_diag"]) == 0
		and float(telemetry_after["perf_overlay_status_timer"]) == 0.0
		and int(telemetry_after["last_issued_order_msec"]) == 0
		and str(telemetry_after["last_issued_order_label"]).is_empty()
		and EnemyArmyCommandTelemetry.get_last_issued_order_label() == "-"
		and EnemyArmyCommandTelemetry.get_seconds_since_last_order() == INF
	)
	_expect(
		failures,
		"identity: still bound after prepare",
		EnemyArmyCommand.get_bound_ai_player_state() == state
	)
	_expect(
		failures,
		"identity: authority name preserved across reset",
		state.military_command_authority_name == &"ArmyCommanderV2"
	)

	await _free_composition(root)
	_expect(
		failures,
		"identity: unbound after composition free",
		EnemyArmyCommand.get_bound_ai_player_state() == null
		and EnemyArmyCommand.get_declared_command_authority() == null
	)


func _verify_runtime_ephemeral_ownership(
	failures: PackedStringArray,
	state: AIPlayerState
) -> void:
	## Reinforcement: one owner — EAC accessors share the AIPlayerState dictionary.
	state.reinforcement_pool.clear()
	state.reinforcement_pool[9001] = {
		"rally": Vector3(2.0, 0.0, 2.0),
		"registered_msec": Time.get_ticks_msec(),
	}
	_expect(
		failures,
		"reinforcement: AIPlayerState owns pool entries",
		state.reinforcement_pool.size() == 1
	)
	state.reinforcement_pool[9002] = {
		"rally": Vector3(3.0, 0.0, 3.0),
		"registered_msec": Time.get_ticks_msec(),
	}
	_expect(
		failures,
		"reinforcement: EAC accessor sees same owner bag",
		EnemyArmyCommand.get_reinforcement_pool_raw_count_for_verify() == 2
		and state.reinforcement_pool.size() == 2
	)

	## Watchdog must not reactivate an expired / cleared mission.
	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER,
		"watchdog verify seed",
		null,
		Vector3(20.0, 0.0, 10.0),
		"WatchdogCC",
		"attack-move"
	)
	state.exec_watchdog_refreshed = false
	state.exec_watchdog_timer = 99.0
	state.exec_last_progress_msec = Time.get_ticks_msec() - 120000
	EnemyArmyCommand.clear_executable_mission("watchdog verify expire")
	_expect(
		failures,
		"watchdog: mission cleared to IDLE before tick",
		state.exec_mission == int(EnemyArmyCommand.ExecutableMission.IDLE)
	)
	state.exec_watchdog_refreshed = false
	state.exec_watchdog_timer = 99.0
	state.exec_last_progress_msec = Time.get_ticks_msec() - 120000
	state.pending_group_orders.clear()
	EnemyArmyCommand.tick_mission_watchdog(get_tree(), 10.0)
	_expect(
		failures,
		"watchdog: expired mission stays IDLE (no reactivation)",
		state.exec_mission == int(EnemyArmyCommand.ExecutableMission.IDLE)
		or state.exec_mission == int(EnemyArmyCommand.ExecutableMission.NONE)
	)
	_expect(
		failures,
		"watchdog: no attack orders after expired mission tick",
		state.pending_group_orders.is_empty()
	)
	## Leave reinforcement clean for subsequent seed-before-reset assertions.
	state.reinforcement_pool.clear()
	EnemyArmyCommand.clear_executable_mission("watchdog verify cleanup")


func _verify_final_static_state_ownership(
	failures: PackedStringArray,
	state: AIPlayerState
) -> void:
	## Creep contest: match-owned on AIPlayerState; EAC accessors share the same bag.
	state.creep_contest_cooldowns.clear()
	state.creep_contest_cooldowns[5555] = Time.get_ticks_msec() + 30000
	_expect(
		failures,
		"creep contest: AIPlayerState owns cooldown map",
		state.creep_contest_cooldowns.size() == 1
		and EnemyArmyCommand.get_creep_contest_cooldown_count_for_verify() == 1
	)
	EnemyArmyCommand.seed_leftover_runtime_state_for_verify()
	_expect(
		failures,
		"creep contest: EAC accessor writes same SoT bag",
		state.creep_contest_cooldowns.has(7777)
		and state.objective_reissue_timer == 11.0
		and state.objective_stuck_timer == 22.0
		and state.objective_last_building_health == 55
		and is_equal_approx(state.objective_eval_timer, 3.5)
		and is_equal_approx(state.objective_stuck_check_timer, 1.25)
	)

	## Objective timers must die with wave/objective cancel — cannot reactivate later work.
	EnemyArmyCommand.clear_offensive_wave_tracking()
	var after_cancel: Dictionary = EnemyArmyCommand.get_leftover_runtime_snapshot_for_verify()
	_expect(
		failures,
		"objective timers: cleared on wave/objective cancel",
		float(after_cancel["objective_reissue_timer"]) == 0.0
		and float(after_cancel["objective_stuck_timer"]) == 0.0
		and int(after_cancel["objective_last_building_health"]) == -1
		and float(after_cancel["objective_eval_timer"]) == 0.0
		and float(after_cancel["objective_stuck_check_timer"]) == 0.0
		and state.objective_reissue_timer == 0.0
		and state.objective_eval_timer == 0.0
	)

	## Telemetry lives on EnemyArmyCommandTelemetry — must not alter mission/orders.
	state.army_mode = 0
	state.strategic_state = 0
	state.exec_mission = int(EnemyArmyCommand.ExecutableMission.NONE)
	state.exec_order_label = ""
	state.pending_group_orders.clear()
	state.creep_contest_cooldowns.clear()
	var mode_before: int = state.army_mode
	var mission_before: int = state.exec_mission
	var contest_before: int = state.creep_contest_cooldowns.size()
	EnemyArmyCommandTelemetry.seed_for_verify()
	var telemetry: Dictionary = EnemyArmyCommandTelemetry.snapshot_for_verify()
	_expect(
		failures,
		"telemetry: seed succeeds without becoming SoT",
		bool(telemetry["debug_enabled_override"])
		and str(telemetry["last_issued_order_label"]) == "verify-telemetry-order"
		and int(telemetry["orders_issued_since_diag"]) == 42
		and is_equal_approx(float(telemetry["perf_diag_timer"]), 9.0)
		and is_equal_approx(float(telemetry["perf_overlay_status_timer"]), 0.2)
		and EnemyArmyCommandTelemetry.get_last_issued_order_label() == "verify-telemetry-order"
		and EnemyArmyCommandTelemetry.get_last_issued_order_destination() == Vector3(99.0, 0.0, 99.0)
	)
	_expect(
		failures,
		"telemetry: cannot alter mission selection or army mode",
		state.army_mode == mode_before
		and state.exec_mission == mission_before
		and state.exec_order_label.is_empty()
	)
	_expect(
		failures,
		"telemetry: cannot enqueue orders or invent contest cooldowns",
		state.pending_group_orders.is_empty()
		and state.creep_contest_cooldowns.size() == contest_before
		and EnemyArmyCommand.get_pending_group_order_count() == 0
	)
	## note_issued_order / record_order_issued are bookkeeping only.
	var orders_before_note: int = state.pending_group_orders.size()
	EnemyArmyCommandTelemetry.note_issued_order("verify-note", Vector3(1.0, 0.0, 2.0))
	EnemyArmyCommandTelemetry.record_order_issued()
	_expect(
		failures,
		"telemetry: note/record do not issue orders or change missions",
		state.pending_group_orders.size() == orders_before_note
		and state.exec_mission == mission_before
		and EnemyArmyCommandTelemetry.get_last_issued_order_label() == "verify-note"
		and int(EnemyArmyCommandTelemetry.snapshot_for_verify()["orders_issued_since_diag"]) == 43
	)
	## Extracted helper must not be an autoload / global singleton node.
	_expect(
		failures,
		"telemetry: not registered as project autoload",
		not ProjectSettings.has_setting("autoload/EnemyArmyCommandTelemetry")
		and Engine.get_main_loop().root.get_node_or_null("/root/EnemyArmyCommandTelemetry") == null
	)

	## No remaining static authoritative military bags outside AIPlayerState.
	## Remaining EAC statics are frame-local caches or composition binding only.
	_expect(
		failures,
		"authority: creep contest + objective timers live on AIPlayerState",
		typeof(state.creep_contest_cooldowns) == TYPE_DICTIONARY
		and typeof(state.objective_reissue_timer) == TYPE_FLOAT
		and typeof(state.objective_eval_timer) == TYPE_FLOAT
		and typeof(state.objective_stuck_timer) == TYPE_FLOAT
		and typeof(state.objective_stuck_check_timer) == TYPE_FLOAT
		and typeof(state.objective_last_building_health) == TYPE_INT
	)
	## Cleanup leftover seeds for later dirty-before-reset path.
	state.creep_contest_cooldowns.clear()
	EnemyArmyCommand.clear_offensive_wave_tracking()
	EnemyArmyCommand.clear_executable_mission("final ownership cleanup")
	EnemyArmyCommandTelemetry.reset_match_state()
	EnemyArmyCommandTelemetry.set_debug_override(false)

func _verify_intent_bus(failures: PackedStringArray, state: AIPlayerState) -> void:
	state.clear_intents()
	state.clear_accepted_intent()
	_expect(failures, "intent: starts empty", state.pending_intent_count() == 0)

	var defend := MilitaryIntent.make_defend({
		"threatened": true,
		"reason": &"verify_base",
		"intercept_position": Vector3(1.0, 0.0, 2.0),
		"emergency": true,
	})
	_expect(
		failures,
		"intent: defend nominates ArmyCommanderV2 owner",
		defend.mission_owner == MilitaryIntent.MISSION_OWNER_COMMANDER
	)
	state.publish_intent(defend)
	state.publish_intent(
		MilitaryIntent.make_creep(&"verify_camp", 40.0, null, &"creep")
	)
	state.publish_intent(
		MilitaryIntent.make_attack(&"verify_push", 75.0, &"wave")
	)
	_expect(failures, "intent: three kinds pending", state.pending_intent_count() == 3)
	_expect(
		failures,
		"intent: has DEFEND",
		state.has_intent_kind(MilitaryIntent.Kind.DEFEND)
	)

	## Same kind+source replaces rather than stacking.
	state.publish_intent(
		MilitaryIntent.make_attack(&"verify_push_stronger", 90.0, &"wave")
	)
	_expect(failures, "intent: attack replaced not stacked", state.pending_intent_count() == 3)
	var best_attack: MilitaryIntent = state.peek_best_intent(MilitaryIntent.Kind.ATTACK)
	_expect(
		failures,
		"intent: peek keeps higher attack score",
		best_attack != null and best_attack.score >= 90.0
	)

	## Cancelled intents cannot republish / reactivate.
	var cancelled := MilitaryIntent.make_attack(&"cancelled", 99.0, &"wave")
	cancelled.cancel()
	state.publish_intent(cancelled)
	_expect(
		failures,
		"intent: cancelled publish ignored",
		state.pending_intent_count() == 3
	)

	## Expired intents are purged and cannot survive consume.
	var expired := MilitaryIntent.make_creep(&"expired", 10.0, null, &"creep_expired")
	expired.expires_msec = Time.get_ticks_msec() - 10
	state.publish_intent(expired)
	_expect(
		failures,
		"intent: expired publish ignored",
		not state.has_intent_kind(MilitaryIntent.Kind.CREEP)
		or state.peek_best_intent(MilitaryIntent.Kind.CREEP).source != &"creep_expired"
	)

	var snapshot: Array = state.consume_intents()
	_expect(failures, "intent: consume drains bus", state.pending_intent_count() == 0)
	_expect(failures, "intent: consume returns three actionable", snapshot.size() == 3)
	for entry: Variant in snapshot:
		_expect(
			failures,
			"intent: consumed entries actionable",
			entry is MilitaryIntent and (entry as MilitaryIntent).is_actionable()
		)

	## Director arbitration helpers see drained snapshot shape + accept ownership.
	var director: MilitaryDirectorV2 = MilitaryDirectorV2.new()
	director.name = "IntentProbeDirector"
	add_child(director)
	await get_tree().process_frame
	director._intent_snapshot = snapshot
	var found_defend: MilitaryIntent = director._find_intent(MilitaryIntent.Kind.DEFEND)
	_expect(
		failures,
		"intent: director finds DEFEND payload",
		found_defend != null
		and found_defend.payload.get("reason", &"") == &"verify_base"
	)
	director._accept_intent_for_mission(found_defend)
	_expect(failures, "intent: accepted ownership live", state.has_live_accepted_intent())
	_expect(
		failures,
		"intent: accepted owner is commander",
		state.accepted_intent_mission_owner == MilitaryIntent.MISSION_OWNER_COMMANDER
	)
	## Force expiry of accepted ownership.
	state.accepted_intent_expires_msec = Time.get_ticks_msec() - 1
	_expect(
		failures,
		"intent: expired accepted cannot reactivate",
		not state.has_live_accepted_intent()
	)
	director.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_authority_and_providers(
	failures: PackedStringArray,
	root: MatchCompositionRoot,
	state: AIPlayerState
) -> void:
	_expect(failures, "authority: V2 enabled", MilitaryAIConfig.is_v2_enabled())
	_expect(
		failures,
		"authority: declared ArmyCommanderV2",
		root.military_command_authority is ArmyCommanderV2
		and EnemyArmyCommand.get_declared_command_authority() == root.army_commander_v2
	)
	_expect(
		failures,
		"authority: AIPlayerState records commander",
		state.military_command_authority_name == &"ArmyCommanderV2"
	)
	_expect(
		failures,
		"authority: is_v2_military_active",
		root.is_v2_military_active()
	)
	## Under V2, only the declared commander is the executable military authority.
	_expect(
		failures,
		"authority: sole executable owner name",
		String(state.military_command_authority_name) == root.army_commander_v2.name
	)
	## Providers publish intents only — they must not enqueue unit orders.
	state.pending_group_orders.clear()
	state.publish_intent(
		MilitaryIntent.make_defend({
			"threatened": true,
			"reason": &"provider_no_orders",
			"intercept_position": Vector3.ZERO,
			"emergency": false,
		})
	)
	state.publish_intent(MilitaryIntent.make_attack(&"provider_no_orders", 50.0, &"wave"))
	state.publish_intent(MilitaryIntent.make_creep(&"provider_no_orders", 40.0, null, &"creep"))
	_expect(
		failures,
		"authority: providers publish intents without issuing orders",
		state.pending_intent_count() >= 1
		and state.pending_group_orders.is_empty()
		and EnemyArmyCommand.get_pending_group_order_count() == 0
	)
	state.clear_intents()
	state.clear_accepted_intent()
	state.pending_group_orders.clear()
