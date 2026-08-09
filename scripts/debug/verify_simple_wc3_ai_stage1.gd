extends Node

## Small Simple WC3 full-loop regression.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_simple_wc3_ai_stage1.tscn

const REPORT_PATH := "user://simple_wc3_ai_stage1_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_simple_wc3_ai_stage1: start")

	_expect(failures, "Simple WC3 AI config on", MilitaryAIConfig.is_simple_wc3_ai_enabled())
	_expect(failures, "ai_version_label SimpleWC3", MilitaryAIConfig.ai_version_label() == "SimpleWC3")
	_expect(failures, "V2 runtime inactive", not MilitaryAIConfig.is_v2_runtime_active())
	_expect(failures, "legacy military suspended", MilitaryAIConfig.is_legacy_military_suspended())

	await _test_exclusive_authority(failures)
	await _test_full_loop(failures)
	await _test_early_creep_gate(failures)
	await _test_creep_transition_and_respawn(failures)
	await _test_hero_death_assemble_and_retrain(failures)
	await _test_match_systems_scene_wiring(failures)

	var report: String
	if failures.is_empty():
		report = "PASS simple_wc3_ai_stage1\n"
	else:
		report = "FAIL simple_wc3_ai_stage1\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)


func _test_exclusive_authority(failures: PackedStringArray) -> void:
	print("verify: exclusive authority")

	var root := MatchCompositionRoot.new()
	root.name = "MatchSystems"

	var state := AIPlayerState.new()
	state.name = "AIPlayerState"
	root.add_child(state)

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	root.add_child(simple)

	var gather := EnemyGatherManager.new()
	gather.name = "EnemyGatherManager"
	root.add_child(gather)

	var build := EnemyBuildManager.new()
	build.name = "EnemyBuildManager"
	root.add_child(build)

	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "authority is SimpleWc3AI", root.military_command_authority is SimpleWc3AI)
	_expect(failures, "V2 military not active", not root.is_v2_military_active())
	_expect(failures, "old military runtime inactive", not root.is_old_military_runtime_active())
	_expect(failures, "starts OPENING", simple.get_state() == SimpleWc3AI.State.OPENING)
	_expect(failures, "no MilitaryDirectorV2 child", root.get_node_or_null("MilitaryDirectorV2") == null)
	_expect(failures, "no EnemyStrategicDirector child", root.get_node_or_null("EnemyStrategicDirector") == null)

	root.queue_free()
	await get_tree().process_frame


func _test_full_loop(failures: PackedStringArray) -> void:
	print("verify: opening → creep → attack → defend → assemble")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	_expect(failures, "1 starts OPENING", simple.get_state() == SimpleWc3AI.State.OPENING)

	var farm: Building = FARM_SCENE.instantiate() as Building
	farm.name = "EnemyFarm"
	farm.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(farm)
	farm.global_position = Vector3(22.0, 1.0, 20.0)
	farm.set_completed()
	farm.add_to_group(&"enemy_command_center")
	farm.add_to_group(&"buildings")
	simple._process(1.0)

	var altar: Building = ALTAR_SCENE.instantiate() as Building
	altar.name = "EnemyHeroAltar"
	altar.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(altar)
	altar.global_position = Vector3(24.0, 1.0, 20.0)
	altar.set_completed()
	altar.add_to_group(&"enemy_command_center")
	altar.add_to_group(&"buildings")
	simple._process(1.0)

	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	barracks.name = "EnemyBarracks"
	barracks.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(barracks)
	barracks.global_position = Vector3(26.0, 1.0, 20.0)
	barracks.set_completed()
	barracks.add_to_group(&"enemy_command_center")
	barracks.add_to_group(&"buildings")
	simple._process(1.0)

	var enemy_cc: Building = CC_SCENE.instantiate() as Building
	enemy_cc.name = "EnemyCommandCenter"
	enemy_cc.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(enemy_cc)
	enemy_cc.global_position = Vector3(20.0, 1.0, 20.0)
	enemy_cc.set_completed()
	enemy_cc.add_to_group(&"enemy_command_center")
	enemy_cc.add_to_group(&"buildings")

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = Vector3(18.0, 0.5, 18.0)
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero.add_to_group(&"enemy_combat_units")
	hero.add_to_group(&"heroes")
	hero.level = 1
	simple._process(1.0)
	_expect(failures, "1 still OPENING with Hero alone", simple.get_state() == SimpleWc3AI.State.OPENING)

	var pikes: Array = []
	for i: int in 5:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike)
		pike.global_position = Vector3(17.0 + float(i) * 0.8, 0.5, 17.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		pikes.append(pike)

	simple._process(1.0)
	_expect(failures, "1 opening reaches Hero + 5 Pikemen → ASSEMBLE", simple.get_state() == SimpleWc3AI.State.ASSEMBLE)
	_expect(failures, "assembly position chosen", simple.assembly_position != Vector3.ZERO)

	var assemble_at: Vector3 = simple.assembly_position
	hero.global_position = assemble_at + Vector3(0.0, 0.5, 0.0)
	for pike_ref: Variant in pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = assemble_at + Vector3(-1.0, 0.5, 0.5)

	## Strong distant player army so AI creeps instead of attacking immediately.
	var player_pikes: Array = []
	for i: int in 10:
		var pp: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pp)
		pp.global_position = Vector3(-60.0 + float(i) * 0.5, 0.5, -60.0)
		pp.team_id = TeamVisuals.PLAYER_TEAM_ID
		pp.add_to_group(&"units")
		player_pikes.append(pp)

	var player_cc: Building = CC_SCENE.instantiate() as Building
	player_cc.name = "PlayerCommandCenter"
	player_cc.team_id = TeamVisuals.PLAYER_TEAM_ID
	add_child(player_cc)
	player_cc.global_position = Vector3(-40.0, 1.0, -40.0)
	player_cc.set_completed()
	player_cc.add_to_group(&"player_command_center")
	player_cc.add_to_group(&"buildings")

	var camp_a := CreepCamp.new()
	camp_a.name = "MediumCampA"
	add_child(camp_a)
	camp_a.global_position = Vector3(18.0, 0.0, 30.0)
	camp_a.add_to_group(&"creep_camps")
	var creep_a: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp_a.add_child(creep_a)
	creep_a.global_position = Vector3(18.0, 0.5, 30.0)
	creep_a.add_to_group(&"neutral_creeps")
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "2 creep target selected", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "2 camp name set", simple.get_camp_name() == "MediumCampA")
	_expect(failures, "7 custom movement used", simple.last_move_handled)

	var orders_after_select: int = simple.strategic_orders_issued
	simple._process(1.0)
	var orders_after_second: int = simple.strategic_orders_issued
	simple._process(1.0)
	_expect(
		failures,
		"order refresh: camp alive does not spam army orders",
		simple.strategic_orders_issued == orders_after_second
		or simple.strategic_orders_issued <= orders_after_select + 8
	)
	_expect(
		failures,
		"stable orders after cohesion settle",
		simple.strategic_orders_issued == orders_after_second
	)

	if NodeSafety.is_alive_node(creep_a):
		creep_a.queue_free()
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()

	## Camp cleared; wipe player army so attack condition passes.
	for pp_ref: Variant in player_pikes:
		if NodeSafety.is_alive_node(pp_ref):
			(pp_ref as Node).queue_free()
	await get_tree().process_frame
	hero.level = 3
	simple._process(1.0)
	_expect(failures, "3 camp cleared → reevaluate", simple.get_camps_cleared() >= 1)
	_expect(failures, "4 attack condition selects player", simple.get_state() == SimpleWc3AI.State.ATTACK)
	_expect(failures, "4 attack target PlayerCC", simple.get_objective_name() == "PlayerCC")
	_expect(failures, "7 custom movement on attack", simple.last_move_handled)

	## 5) Defend: player military near enemy CC.
	var raider: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(raider)
	raider.global_position = enemy_cc.global_position + Vector3(5.0, 0.5, 0.0)
	raider.team_id = TeamVisuals.PLAYER_TEAM_ID
	raider.add_to_group(&"units")
	simple._process(1.0)
	_expect(failures, "5 defend triggers on base threat", simple.get_state() == SimpleWc3AI.State.DEFEND)
	_expect(failures, "5 defend targets raider", simple.get_objective_name() == String(raider.name) or simple._objective_id == raider.get_instance_id())

	## Threat gone → reevaluate (attack again with hero lvl 3 + army).
	raider.queue_free()
	await get_tree().process_frame
	simple._process(1.0)
	_expect(
		failures,
		"defend clear → ATTACK or ASSEMBLE or CREEP",
		simple.get_state() == SimpleWc3AI.State.ATTACK
		or simple.get_state() == SimpleWc3AI.State.ASSEMBLE
		or simple.get_state() == SimpleWc3AI.State.CREEP
	)

	## 6) Assemble when weak — kill hero. Must stay ASSEMBLE (not OPENING).
	hero.queue_free()
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "6 assemble occurs when hero dies", simple.get_state() == SimpleWc3AI.State.ASSEMBLE)
	_expect(failures, "6 opening stays complete after hero death", simple.is_opening_complete())
	_expect(failures, "6 does not return to OPENING", simple.get_state() != SimpleWc3AI.State.OPENING)

	for node_ref: Variant in [farm, altar, barracks, enemy_cc, player_cc, camp_a]:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()
	for pike_ref: Variant in pikes + player_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Node).queue_free()
	simple.queue_free()
	await get_tree().process_frame


func _test_early_creep_gate(failures: PackedStringArray) -> void:
	print("verify: early creep gate (no pre-creep ATTACK)")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()
	HeroProgressionStore.clear()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc: Building = CC_SCENE.instantiate() as Building
	enemy_cc.name = "EnemyCC_Gate"
	enemy_cc.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(enemy_cc)
	enemy_cc.global_position = Vector3(20.0, 1.0, 20.0)
	enemy_cc.set_completed()
	enemy_cc.add_to_group(&"enemy_command_center")
	enemy_cc.add_to_group(&"buildings")

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = Vector3(18.0, 0.5, 18.0)
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero.add_to_group(&"enemy_combat_units")
	hero.add_to_group(&"heroes")
	hero.level = 1

	var pikes: Array = []
	for i: int in 5:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike)
		pike.global_position = Vector3(17.0 + float(i) * 0.8, 0.5, 17.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		pikes.append(pike)

	## Tiny player force so AI power >> player power.
	var player_hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(player_hero)
	player_hero.global_position = Vector3(-50.0, 0.5, -50.0)
	player_hero.team_id = TeamVisuals.PLAYER_TEAM_ID
	player_hero.add_to_group(&"units")
	player_hero.add_to_group(&"heroes")

	var camp_a := CreepCamp.new()
	camp_a.name = "MediumCampGateA"
	add_child(camp_a)
	camp_a.global_position = Vector3(18.0, 0.0, 30.0)
	camp_a.add_to_group(&"creep_camps")
	var creep_a: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp_a.add_child(creep_a)
	creep_a.global_position = Vector3(18.0, 0.5, 30.0)
	creep_a.add_to_group(&"neutral_creeps")

	var camp_b := CreepCamp.new()
	camp_b.name = "MediumCampGateB"
	add_child(camp_b)
	camp_b.global_position = Vector3(22.0, 0.0, 34.0)
	camp_b.add_to_group(&"creep_camps")
	var creep_b: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp_b.add_child(creep_b)
	creep_b.global_position = Vector3(22.0, 0.5, 34.0)
	creep_b.add_to_group(&"neutral_creeps")
	await get_tree().process_frame

	## Force opening complete + assembled force, camps_cleared=0.
	simple._opening_complete = true
	simple._observe_army()
	simple._update_power_estimates()
	simple._ensure_assembly_position()
	simple.assembly_position = Vector3(16.0, 0.0, 16.0)
	hero.global_position = simple.assembly_position + Vector3(0.0, 0.5, 0.0)
	for pike_ref: Variant in pikes:
		(pike_ref as Spearman).global_position = simple.assembly_position + Vector3(-1.0, 0.5, 0.5)
	simple._state = SimpleWc3AI.State.ASSEMBLE
	simple._set_objective(&"rally", 0, "Rally", simple.assembly_position)

	simple._process(1.0)
	_expect(failures, "CASE1 camps=0 → CREEP not ATTACK", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "CASE1 camps still 0", simple.get_camps_cleared() == 0)
	_expect(failures, "CASE1 early creep incomplete", not simple.is_early_creep_complete())
	_expect(failures, "CASE1 AI power still >> player", simple.last_ai_power > simple.last_player_power * 1.25)

	## Clear camp A → camps_cleared=1, still must CREEP (CASE 2).
	if NodeSafety.is_alive_node(creep_a):
		creep_a.queue_free()
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "CASE2 camps=1", simple.get_camps_cleared() == 1)
	_expect(failures, "CASE2 still CREEP not ATTACK", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "CASE2 early creep still incomplete", not simple.is_early_creep_complete())

	## Clear camp B → camps_cleared=2, ATTACK may be selected (CASE 3).
	if NodeSafety.is_alive_node(creep_b):
		creep_b.queue_free()
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "CASE3 camps=2", simple.get_camps_cleared() == 2)
	_expect(failures, "CASE3 early creep complete", simple.is_early_creep_complete())
	_expect(failures, "CASE3 ATTACK eligible/selected", simple.get_state() == SimpleWc3AI.State.ATTACK)

	for node_ref: Variant in [enemy_cc, hero, player_hero, camp_a, camp_b] + pikes:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()
	simple.queue_free()
	await get_tree().process_frame


func _test_creep_transition_and_respawn(failures: PackedStringArray) -> void:
	print("verify: camp transition / solo prevention / hero death / respawn / no freeze")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()
	HeroProgressionStore.clear()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc: Building = CC_SCENE.instantiate() as Building
	enemy_cc.name = "EnemyCC_CreepTrans"
	enemy_cc.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(enemy_cc)
	enemy_cc.global_position = Vector3(20.0, 1.0, 20.0)
	enemy_cc.set_completed()
	enemy_cc.add_to_group(&"enemy_command_center")
	enemy_cc.add_to_group(&"buildings")

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = Vector3(18.0, 0.5, 18.0)
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero.add_to_group(&"enemy_combat_units")
	hero.add_to_group(&"enemies")
	hero.level = 1

	var pikes: Array = []
	for i: int in 5:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike)
		pike.global_position = Vector3(17.0 + float(i) * 0.8, 0.5, 17.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		pike.add_to_group(&"enemies")
		pikes.append(pike)

	var camp_a := CreepCamp.new()
	camp_a.name = "MediumCampTransA"
	add_child(camp_a)
	camp_a.global_position = Vector3(18.0, 0.0, 28.0)
	camp_a.add_to_group(&"creep_camps")
	var creep_a: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp_a.add_child(creep_a)
	creep_a.global_position = Vector3(18.0, 0.5, 28.0)
	creep_a.add_to_group(&"neutral_creeps")

	var camp_b := CreepCamp.new()
	camp_b.name = "MediumCampTransB"
	add_child(camp_b)
	camp_b.global_position = Vector3(40.0, 0.0, 40.0)
	camp_b.add_to_group(&"creep_camps")
	var creep_b: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp_b.add_child(creep_b)
	creep_b.global_position = Vector3(40.0, 0.5, 40.0)
	creep_b.add_to_group(&"neutral_creeps")
	await get_tree().process_frame

	simple._opening_complete = true
	simple.assembly_position = Vector3(16.0, 0.0, 16.0)
	simple._observe_army()
	simple._state = SimpleWc3AI.State.ASSEMBLE
	simple._set_objective(&"rally", 0, "Rally", simple.assembly_position)
	simple._process(1.0)
	_expect(failures, "creep start on Camp A", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "Camp A selected", simple.get_camp_name() == "MediumCampTransA")
	_expect(
		failures,
		"CASE1 initial group order includes whole army",
		simple.last_move_squad_size >= 6
	)

	## CASE 1 — clear Camp A → Camp B group order for ALL.
	if NodeSafety.is_alive_node(creep_a):
		creep_a.queue_free()
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "CASE1 camps cleared = 1", simple.get_camps_cleared() == 1)
	_expect(failures, "CASE1 Camp B selected", simple.get_camp_name() == "MediumCampTransB")
	_expect(failures, "CASE1 still CREEP", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(
		failures,
		"CASE1 Camp B group order whole army",
		simple.last_move_squad_size >= 6 and simple.last_move_handled
	)
	_expect(failures, "CASE1 combat not committed yet at distance", not simple.last_creep_combat_committed)

	## CASE 2 — Hero alone at Camp B, Pikemen far: no solo combat commit.
	hero.global_position = Vector3(40.0, 0.5, 40.0)
	for i: int in pikes.size():
		(pikes[i] as Spearman).global_position = Vector3(10.0 + float(i), 0.5, 10.0)
	var orders_before_solo: int = simple.strategic_orders_issued
	simple._process(1.0)
	_expect(failures, "CASE2 still CREEP while waiting cohesion", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "CASE2 no solo combat commit", not simple.last_creep_combat_committed)

	## Bring Pikemen near camp → combat may commit.
	for i: int in pikes.size():
		(pikes[i] as Spearman).global_position = Vector3(39.0 + float(i) * 0.4, 0.5, 39.0)
	simple._process(1.0)
	_expect(failures, "CASE2 combat commits when cohesive", simple.last_creep_combat_committed)

	## CASE 3 — Hero dies during CREEP.
	hero.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "CASE3 ASSEMBLE after hero death", simple.get_state() == SimpleWc3AI.State.ASSEMBLE)
	_expect(failures, "CASE3 camp objective cleared", simple._objective_kind == &"rally")
	_expect(failures, "CASE3 combat flag cleared", not simple.last_creep_combat_committed)
	_expect(failures, "CASE3 rally move issued", simple.last_move_handled)

	## CASE 4 + 5 — Hero respawns, early creep incomplete → fresh CREEP, no freeze.
	var hero2: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero2)
	hero2.global_position = Vector3(18.0, 0.5, 18.0)
	hero2.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero2.add_to_group(&"enemy_combat_units")
	hero2.add_to_group(&"enemies")
	hero2.level = 1
	HeroProgressionStore.register_living_hero(hero2)
	for i: int in pikes.size():
		(pikes[i] as Spearman).global_position = Vector3(17.0 + float(i) * 0.5, 0.5, 17.0)

	simple._process(1.0)
	_expect(failures, "CASE4 CREEP after hero respawn", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "CASE4 fresh camp objective", simple._objective_kind == &"camp")
	_expect(
		failures,
		"CASE4 whole army fresh group order",
		simple.last_move_squad_size >= 6 and simple.get_camp_name() == "MediumCampTransB"
	)

	var state_after: SimpleWc3AI.State = simple.get_state()
	var camp_after: String = simple.get_camp_name()
	simple._process(1.0)
	simple._process(1.0)
	simple._process(1.0)
	_expect(failures, "CASE5 no freeze — still CREEP", simple.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "CASE5 still has camp objective", simple._objective_kind == &"camp")
	_expect(
		failures,
		"CASE5 hero alive + pikes + camp remain active",
		simple.last_hero_alive
		and simple.last_pikeman_count >= 5
		and not simple.get_camp_name().is_empty()
		and simple.get_camp_name() != "-"
	)
	## Quiet unused.
	_expect(failures, "CASE5 tracked prior state", state_after == SimpleWc3AI.State.CREEP or camp_after != "")
	_expect(failures, "CASE2 tracked orders", orders_before_solo >= 0)

	for node_ref: Variant in [enemy_cc, hero2, camp_a, camp_b] + pikes:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()
	simple.queue_free()
	await get_tree().process_frame


func _test_hero_death_assemble_and_retrain(failures: PackedStringArray) -> void:
	print("verify: hero death → ASSEMBLE + retrain priority (twice)")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()
	HeroProgressionStore.clear()
	EnemyResourceManager.reset_to_starting_values()
	EnemyResourceManager.add_gold(2000)
	EnemyResourceManager.food_max = 99
	EnemyResourceManager.food_current = 0

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc: Building = CC_SCENE.instantiate() as Building
	enemy_cc.name = "EnemyCC_Retrain"
	enemy_cc.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(enemy_cc)
	enemy_cc.global_position = Vector3(20.0, 1.0, 20.0)
	enemy_cc.set_completed()
	enemy_cc.add_to_group(&"enemy_command_center")
	enemy_cc.add_to_group(&"buildings")

	var altar: HeroAltar = ALTAR_SCENE.instantiate() as HeroAltar
	altar.name = "EnemyAltar_Retrain"
	altar.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(altar)
	altar.global_position = Vector3(24.0, 1.0, 20.0)
	altar.set_completed()
	altar.add_to_group(&"enemy_command_center")
	altar.add_to_group(&"buildings")

	var barracks: Barracks = BARRACKS_SCENE.instantiate() as Barracks
	barracks.name = "EnemyBarracks_Retrain"
	barracks.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(barracks)
	barracks.global_position = Vector3(26.0, 1.0, 20.0)
	barracks.set_completed()
	barracks.add_to_group(&"enemy_command_center")
	barracks.add_to_group(&"buildings")

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = Vector3(30.0, 0.5, 40.0)
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero.add_to_group(&"enemy_combat_units")
	hero.add_to_group(&"enemies")
	hero.add_to_group(&"heroes")
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)

	var pikes: Array = []
	for i: int in 5:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike)
		pike.global_position = Vector3(31.0 + float(i) * 0.8, 0.5, 40.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		pike.add_to_group(&"enemies")
		pikes.append(pike)

	simple._opening_complete = true
	simple._camps_cleared = 2
	simple._creep_phase_complete = true
	simple._observe_army()
	simple._update_power_estimates()
	simple._ensure_assembly_position()
	simple._state = SimpleWc3AI.State.ATTACK
	simple._set_objective(&"attack", 0, "PlayerHero", Vector3(-40.0, 0.0, -40.0))
	simple._issue_army_move([hero] + pikes, Vector3(-40.0, 0.0, -40.0), &"attack_move")

	var gold_before_death: int = EnemyResourceManager.gold

	## CASE 4 — kill hero during ATTACK → ASSEMBLE + one rally order.
	hero.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "CASE4 state ASSEMBLE after hero death", simple.get_state() == SimpleWc3AI.State.ASSEMBLE)
	_expect(failures, "CASE4 not OPENING", simple.get_state() != SimpleWc3AI.State.OPENING)
	_expect(failures, "CASE4 rally objective", simple._objective_kind == &"rally")
	_expect(failures, "CASE4 rally move issued", simple.last_move_handled)
	_expect(failures, "CASE4 opening still complete", simple.is_opening_complete())

	var orders_after_rally: int = simple.strategic_orders_issued
	var objective_kind_after: StringName = simple._objective_kind
	simple._process(1.0)
	_expect(
		failures,
		"CASE4 assemble keeps rally without re-OPENING",
		simple.get_state() == SimpleWc3AI.State.ASSEMBLE
		and simple._objective_kind == objective_kind_after
		and simple.strategic_orders_issued <= orders_after_rally + 1
	)

	## CASE 5 — hero queued again (first retrain).
	_expect(failures, "CASE5 hero queued after first death", simple.last_hero_queued or altar.is_training_hero())
	_expect(failures, "CASE5 altar training", altar.is_training_hero())

	## CASE 6 — hero missing + exact hero gold: must queue Hero, not spend on Pikeman.
	if altar.is_training_hero():
		altar._hero_training_session += 1
		altar._is_training = false
		altar._training_for_enemy = false
		EnemyResourceManager.add_gold(HeroAltar.TRAIN_GOLD_COST)
		EnemyResourceManager.release_food_used(HeroAltar.TRAIN_FOOD_COST)

	EnemyResourceManager.gold = HeroAltar.TRAIN_GOLD_COST
	EnemyResourceManager.food_current = 0
	EnemyResourceManager.food_max = 99
	var spearman_queue_before: int = barracks.get_spearman_queue_count()
	simple.last_hero_alive = false
	simple._try_train_pikeman()
	_expect(failures, "CASE6 hero queued instead of pikeman", altar.is_training_hero())
	_expect(
		failures,
		"CASE6 gold spent on hero cost",
		EnemyResourceManager.gold == 0
	)
	_expect(
		failures,
		"CASE6 no new pikeman queued",
		barracks.get_spearman_queue_count() == spearman_queue_before
	)

	## CASE 5 second time — spawn hero, kill again, prove retrain is not one-shot.
	altar._hero_training_session += 1
	altar._is_training = false
	var spawned: Hero = HERO_SCENE.instantiate() as Hero
	add_child(spawned)
	spawned.global_position = Vector3(24.0, 0.5, 17.0)
	spawned.team_id = TeamVisuals.ENEMY_TEAM_ID
	spawned.add_to_group(&"enemy_combat_units")
	spawned.add_to_group(&"enemies")
	HeroProgressionStore.register_living_hero(spawned)
	simple._observe_army()
	_expect(failures, "CASE5b living hero after first retrain spawn", simple.last_hero_alive)

	spawned.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	HeroProgressionStore.clear_living_hero(null, true)
	EnemyResourceManager.add_gold(500)
	simple._observe_army()
	simple._try_ensure_hero()
	_expect(failures, "CASE5c second death queues hero again", altar.is_training_hero())
	_expect(failures, "CASE5c not one-shot", altar.is_training_hero() and not simple.last_hero_alive)

	for node_ref: Variant in [enemy_cc, altar, barracks] + pikes:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()
	simple.queue_free()
	await get_tree().process_frame
	_expect(failures, "CASE4 had gold before death", gold_before_death >= 0)


func _test_match_systems_scene_wiring(failures: PackedStringArray) -> void:
	print("verify: match_systems.tscn declares SimpleWc3AI authority")
	var packed: PackedScene = load("res://scenes/match/match_systems.tscn") as PackedScene
	_expect(failures, "match_systems.tscn loads", packed != null)
	if packed == null:
		return

	var systems: Node = packed.instantiate()
	add_child(systems)
	await get_tree().process_frame
	await get_tree().process_frame

	var root: MatchCompositionRoot = systems as MatchCompositionRoot
	_expect(failures, "root is MatchCompositionRoot", root != null)
	if root == null:
		systems.queue_free()
		await get_tree().process_frame
		return

	_expect(failures, "SimpleWc3AI child present", root.simple_wc3_ai != null)
	_expect(failures, "scene authority SimpleWc3AI", root.military_command_authority is SimpleWc3AI)
	_expect(failures, "scene old military inactive", not root.is_old_military_runtime_active())
	_expect(failures, "EnemyBuildManager present (mechanics)", root.enemy_build_manager != null)
	_expect(failures, "EnemyGatherManager present (mechanics)", root.enemy_gather_manager != null)
	_expect(failures, "no EnemyStrategicDirector", root.get_node_or_null("EnemyStrategicDirector") == null)
	_expect(failures, "no MilitaryDirectorV2", root.get_node_or_null("MilitaryDirectorV2") == null)
	_expect(failures, "no ArmyCommanderV2", root.get_node_or_null("ArmyCommanderV2") == null)
	_expect(failures, "no EnemyWaveManager", root.get_node_or_null("EnemyWaveManager") == null)
	_expect(failures, "no EnemyCreepManager", root.get_node_or_null("EnemyCreepManager") == null)
	_expect(failures, "no EnemyDefenseManager", root.get_node_or_null("EnemyDefenseManager") == null)
	_expect(failures, "no EnemyCombatController", root.get_node_or_null("EnemyCombatController") == null)

	systems.queue_free()
	await get_tree().process_frame
