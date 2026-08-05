extends Node

## Headless verification for AI hero mastery.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_hero_mastery.tscn

const _ComboPlanner = preload("res://scripts/systems/ai_hero_combo_planner.gd")
const REPORT_PATH := "user://ai_hero_mastery_verify_result.txt"
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const ENEMY_TEAM_ID: int = 1
const SELECTION_TRIALS: int = 300


func _ready() -> void:
	var failures: PackedStringArray = []
	HeroProgressionStore.clear()
	AIHeroMastery.reset_match_state()
	MatchSession._register_static_match_resets()

	_verify_equal_weight_selection(failures)
	_verify_lock_persists_across_retrain(failures)
	_verify_forced_kits_resolve_on_altar(failures)
	_verify_combo_planner(failures)
	_verify_tactical_state_names(failures)
	_verify_match_reset_clears_mastery(failures)

	var report: String
	if failures.is_empty():
		report = "PASS ai_hero_mastery\n"
	else:
		report = "FAIL ai_hero_mastery\n" + "\n".join(failures) + "\n"

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


func _fund_enemy() -> void:
	EnemyResourceManager.gold = 9999
	EnemyResourceManager.food_current = 0
	EnemyResourceManager.food_max = 99


func _make_enemy_altar(parent: Node, position: Vector3 = Vector3(20, 0, 0)) -> HeroAltar:
	var altar: HeroAltar = HERO_ALTAR_SCENE.instantiate() as HeroAltar
	altar.team_id = ENEMY_TEAM_ID
	altar.add_to_group(&"enemy_command_center")
	parent.add_child(altar)
	altar.global_position = position
	altar.set_completed()
	return altar


func _verify_equal_weight_selection(failures: PackedStringArray) -> void:
	var counts: Dictionary = {
		HeroCatalog.KIT_PALADIN: 0,
		HeroCatalog.KIT_SHADOW_ASSASSIN: 0,
		HeroCatalog.KIT_RANGER: 0,
	}

	AIHeroMastery.set_suppress_selection_log_for_tests(true)
	for _i: int in SELECTION_TRIALS:
		HeroProgressionStore.clear()
		AIHeroMastery.reset_match_state()
		AIHeroMastery.set_suppress_selection_log_for_tests(true)
		var kit: StringName = AIHeroMastery.ensure_enemy_hero_choice()
		counts[kit] = int(counts.get(kit, 0)) + 1
		var again: StringName = AIHeroMastery.ensure_enemy_hero_choice()
		_expect(failures, "selection stable within trial", again == kit)
	AIHeroMastery.set_suppress_selection_log_for_tests(false)

	var expected: float = float(SELECTION_TRIALS) / 3.0
	var min_ok: int = int(expected * 0.55)
	var max_ok: int = int(expected * 1.45)
	for kit_id: StringName in AIHeroMastery.AI_HERO_POOL:
		var count: int = int(counts.get(kit_id, 0))
		_expect(
			failures,
			"equal weight %s got %d (want ~%d)" % [String(kit_id), count, int(expected)],
			count >= min_ok and count <= max_ok
		)

	print(
		"selection counts: paladin=%d assassin=%d ranger=%d"
		% [
			int(counts[HeroCatalog.KIT_PALADIN]),
			int(counts[HeroCatalog.KIT_SHADOW_ASSASSIN]),
			int(counts[HeroCatalog.KIT_RANGER]),
		]
	)


func _verify_lock_persists_across_retrain(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	AIHeroMastery.reset_match_state()
	AIHeroMastery.set_forced_kit_for_tests(HeroCatalog.KIT_RANGER)
	var kit: StringName = AIHeroMastery.ensure_enemy_hero_choice()
	_expect(failures, "forced ranger lock", kit == HeroCatalog.KIT_RANGER)

	HeroProgressionStore.lock_kit(true, HeroCatalog.KIT_RANGER)
	AIHeroMastery.set_forced_kit_for_tests(HeroCatalog.KIT_PALADIN)
	var still: StringName = AIHeroMastery.ensure_enemy_hero_choice()
	_expect(failures, "no reroll after forced override once locked", still == HeroCatalog.KIT_RANGER)
	_expect(
		failures,
		"faction lock still ranger",
		HeroProgressionStore.get_locked_kit_id(true) == HeroCatalog.KIT_RANGER
	)


func _verify_forced_kits_resolve_on_altar(failures: PackedStringArray) -> void:
	for kit_id: StringName in AIHeroMastery.AI_HERO_POOL:
		HeroProgressionStore.clear()
		AIHeroMastery.reset_match_state()
		AIHeroMastery.set_forced_kit_for_tests(kit_id)
		AIHeroMastery.ensure_enemy_hero_choice()
		_fund_enemy()

		var root := Node3D.new()
		add_child(root)
		var altar: HeroAltar = _make_enemy_altar(root)
		_expect(
			failures,
			"altar pending %s" % String(kit_id),
			altar.get_pending_training_kit_id(true) == kit_id
		)
		_expect(
			failures,
			"cannot offer other kit when locked %s" % String(kit_id),
			not altar.can_offer_kit(
				HeroCatalog.KIT_PALADIN if kit_id != HeroCatalog.KIT_PALADIN else HeroCatalog.KIT_RANGER,
				true
			)
		)
		root.queue_free()


func _verify_combo_planner(failures: PackedStringArray) -> void:
	var planner = _ComboPlanner.new()
	var steps: Array[Dictionary] = [
		_ComboPlanner.make_step(_ComboPlanner.ACTION_Q, true, 8.0, 2.0, true),
		_ComboPlanner.make_step(_ComboPlanner.ACTION_ATTACK, true, 2.0, 2.0, false),
		_ComboPlanner.make_step(_ComboPlanner.ACTION_E, false, -1.0, 1.5, true),
	]

	var dummy := Node3D.new()
	add_child(dummy)
	planner.start(steps, dummy, 0.0)
	_expect(failures, "combo active after start", planner.is_active())

	var waiting: Dictionary = planner.tick(0.1, true, false)
	_expect(failures, "combo waits for range", VariantUtils.to_bool(waiting.get("waiting_for_range", false)))

	var ready: Dictionary = planner.tick(0.2, true, true)
	_expect(
		failures,
		"combo action q",
		StringName(str(ready.get("action", ""))) == _ComboPlanner.ACTION_Q
	)
	planner.mark_step_succeeded(0.2)
	_expect(failures, "combo still active mid sequence", planner.is_active())

	planner.abort("test abort")
	_expect(failures, "combo aborted", not planner.is_active())
	_expect(failures, "combo abort reason", planner.get_abort_reason() == "test abort")

	dummy.queue_free()


func _verify_tactical_state_names(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"FOLLOW_ARMY name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.FOLLOW_ARMY) == "FOLLOW_ARMY"
	)
	_expect(
		failures,
		"POKE name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.POKE) == "POKE"
	)
	_expect(
		failures,
		"ENGAGE name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.ENGAGE) == "ENGAGE"
	)
	_expect(
		failures,
		"COMBO name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.COMBO) == "COMBO"
	)
	_expect(
		failures,
		"KITE name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.KITE) == "KITE"
	)
	_expect(
		failures,
		"PROTECT_BACKLINE name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.PROTECT_BACKLINE)
		== "PROTECT_BACKLINE"
	)
	_expect(
		failures,
		"ESCAPE name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.ESCAPE) == "ESCAPE"
	)
	_expect(
		failures,
		"REPOSITION name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.REPOSITION) == "REPOSITION"
	)
	_expect(
		failures,
		"DEFEND_BASE name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.DEFEND_BASE) == "DEFEND_BASE"
	)
	_expect(
		failures,
		"RETURN_TO_ARMY name",
		AIHeroMastery.get_tactical_state_name(AIHeroMastery.TacticalState.RETURN_TO_ARMY)
		== "RETURN_TO_ARMY"
	)


func _verify_match_reset_clears_mastery(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	AIHeroMastery.reset_match_state()
	AIHeroMastery.set_forced_kit_for_tests(HeroCatalog.KIT_PALADIN)
	AIHeroMastery.ensure_enemy_hero_choice()
	_expect(failures, "pre-reset locked", HeroProgressionStore.has_locked_kit(true))

	MatchSession.prepare_new_match()
	_expect(failures, "reset clears enemy lock", not HeroProgressionStore.has_locked_kit(true))
	_expect(
		failures,
		"reset clears tactical to FOLLOW_ARMY",
		AIHeroMastery.get_tactical_state() == AIHeroMastery.TacticalState.FOLLOW_ARMY
	)
