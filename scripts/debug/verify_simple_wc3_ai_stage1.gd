extends Node

## Priority-rule Simple WC3 AI regression (no state machine).
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
	await _test1_hero_missing(failures)
	await _test2_build_force(failures)
	await _test3_defend(failures)
	await _test4_early_creep(failures)
	await _test5_next_camp_after_clear(failures)
	await _test6_and_7_hero_death_and_return(failures)
	await _test8_attack_player(failures)
	await _test9_new_pikeman_joins(failures)
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
	_expect(failures, "no get_state (state machine gone)", not simple.has_method("get_state"))
	_expect(failures, "no MilitaryDirectorV2 child", root.get_node_or_null("MilitaryDirectorV2") == null)
	_expect(failures, "no EnemyStrategicDirector child", root.get_node_or_null("EnemyStrategicDirector") == null)

	root.queue_free()
	await get_tree().process_frame


func _spawn_enemy_cc(parent: Node, pos: Vector3, name_str: String) -> Building:
	var enemy_cc: Building = CC_SCENE.instantiate() as Building
	enemy_cc.name = name_str
	enemy_cc.team_id = TeamVisuals.ENEMY_TEAM_ID
	parent.add_child(enemy_cc)
	enemy_cc.global_position = pos
	enemy_cc.set_completed()
	enemy_cc.add_to_group(&"enemy_command_center")
	enemy_cc.add_to_group(&"buildings")
	return enemy_cc


func _spawn_enemy_hero(parent: Node, pos: Vector3) -> Hero:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	parent.add_child(hero)
	hero.global_position = pos
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero.add_to_group(&"enemy_combat_units")
	hero.add_to_group(&"heroes")
	hero.level = 1
	return hero


func _spawn_enemy_pikes(parent: Node, origin: Vector3, count: int) -> Array:
	var pikes: Array = []
	for i: int in count:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		parent.add_child(pike)
		pike.global_position = origin + Vector3(float(i) * 0.8, 0.0, 0.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		pikes.append(pike)
	return pikes


func _spawn_camp(parent: Node, camp_name: String, pos: Vector3) -> Dictionary:
	var camp := CreepCamp.new()
	camp.name = camp_name
	parent.add_child(camp)
	camp.global_position = pos
	camp.add_to_group(&"creep_camps")
	var creep: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp.add_child(creep)
	creep.global_position = pos + Vector3(0.0, 0.5, 0.0)
	creep.add_to_group(&"neutral_creeps")
	return {"camp": camp, "creep": creep}


func _cleanup(nodes: Array) -> void:
	for node_ref: Variant in nodes:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()


## TEST 1 — Hero missing → train Hero, army home, HERO priority.
func _test1_hero_missing(failures: PackedStringArray) -> void:
	print("verify: TEST1 hero missing")
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

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T1")
	var altar: Building = ALTAR_SCENE.instantiate() as Building
	altar.name = "EnemyAltar_T1"
	altar.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(altar)
	altar.global_position = Vector3(24.0, 1.0, 20.0)
	altar.set_completed()
	altar.add_to_group(&"enemy_command_center")
	altar.add_to_group(&"buildings")

	var pikes := _spawn_enemy_pikes(self, Vector3(30.0, 0.5, 30.0), 3)
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T1 priority HERO", simple.get_priority() == SimpleWc3AI.PRIORITY_HERO)
	_expect(failures, "T1 hero training requested", simple.last_hero_queued or (altar as HeroAltar).is_training_hero())
	_expect(failures, "T1 army home move", simple.last_move_handled)
	_expect(failures, "T1 assembly chosen", simple.assembly_position != Vector3.ZERO)

	_cleanup([simple, enemy_cc, altar] + pikes)
	await get_tree().process_frame


## TEST 2 — Hero alive, 3 Pikemen → train more, army home, BUILD_FORCE.
func _test2_build_force(failures: PackedStringArray) -> void:
	print("verify: TEST2 build force")
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

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T2")
	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	barracks.name = "EnemyBarracks_T2"
	barracks.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(barracks)
	barracks.global_position = Vector3(26.0, 1.0, 20.0)
	barracks.set_completed()
	barracks.add_to_group(&"enemy_command_center")
	barracks.add_to_group(&"buildings")

	var hero := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	var pikes := _spawn_enemy_pikes(self, Vector3(17.0, 0.5, 17.0), 3)
	await get_tree().process_frame

	var spear_before: int = (barracks as Barracks).get_spearman_queue_count()
	simple._process(1.0)
	_expect(failures, "T2 priority BUILD_FORCE", simple.get_priority() == SimpleWc3AI.PRIORITY_BUILD_FORCE)
	_expect(failures, "T2 pikemen training", (barracks as Barracks).get_spearman_queue_count() > spear_before)
	_expect(failures, "T2 army home move", simple.last_move_handled)

	_cleanup([simple, enemy_cc, barracks, hero] + pikes)
	await get_tree().process_frame


## TEST 3 — Hero + 5 Pikemen + base threat → DEFEND whole army.
func _test3_defend(failures: PackedStringArray) -> void:
	print("verify: TEST3 defend")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T3")
	var hero := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	var pikes := _spawn_enemy_pikes(self, Vector3(17.0, 0.5, 17.0), 5)

	var raider: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(raider)
	raider.global_position = enemy_cc.global_position + Vector3(5.0, 0.5, 0.0)
	raider.team_id = TeamVisuals.PLAYER_TEAM_ID
	raider.add_to_group(&"units")
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T3 priority DEFEND", simple.get_priority() == SimpleWc3AI.PRIORITY_DEFEND)
	_expect(failures, "T3 targets raider", simple.current_target == raider)
	_expect(failures, "T3 whole army ordered", simple.last_move_squad_size >= 6 and simple.last_move_handled)

	_cleanup([simple, enemy_cc, hero, raider] + pikes)
	await get_tree().process_frame


## TEST 4 — Hero + 5 Pikemen, no threat, camps=0 → EARLY_CREEP.
func _test4_early_creep(failures: PackedStringArray) -> void:
	print("verify: TEST4 early creep")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T4")
	var hero := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	var pikes := _spawn_enemy_pikes(self, Vector3(17.0, 0.5, 17.0), 5)

	## Strong distant player so attack threshold alone would not skip early creep.
	var player_pikes: Array = []
	for i: int in 12:
		var pp: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pp)
		pp.global_position = Vector3(-60.0 + float(i) * 0.5, 0.5, -60.0)
		pp.team_id = TeamVisuals.PLAYER_TEAM_ID
		pp.add_to_group(&"units")
		player_pikes.append(pp)

	var camp_data := _spawn_camp(self, "MediumCampA", Vector3(18.0, 0.0, 30.0))
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T4 priority EARLY_CREEP", simple.get_priority() == SimpleWc3AI.PRIORITY_EARLY_CREEP)
	_expect(failures, "T4 camp selected", simple.get_camp_name() == "MediumCampA")
	_expect(failures, "T4 whole army ordered", simple.last_move_squad_size >= 6 and simple.last_move_handled)
	_expect(failures, "T4 camps still 0", simple.get_camps_cleared() == 0)

	_cleanup([simple, enemy_cc, hero, camp_data["camp"]] + pikes + player_pikes)
	await get_tree().process_frame


## TEST 5 — Camp #1 dies → next tick selects another living camp for whole army.
func _test5_next_camp_after_clear(failures: PackedStringArray) -> void:
	print("verify: TEST5 next camp after clear")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T5")
	var hero := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	var pikes := _spawn_enemy_pikes(self, Vector3(17.0, 0.5, 17.0), 5)

	var camp_a := _spawn_camp(self, "MediumCampTransA", Vector3(18.0, 0.0, 28.0))
	var camp_b := _spawn_camp(self, "MediumCampTransB", Vector3(40.0, 0.0, 40.0))
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T5 start Camp A", simple.get_camp_name() == "MediumCampTransA")
	_expect(failures, "T5 priority EARLY_CREEP", simple.get_priority() == SimpleWc3AI.PRIORITY_EARLY_CREEP)

	if NodeSafety.is_alive_node(camp_a["creep"]):
		(camp_a["creep"] as Node).queue_free()
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "T5 camps cleared = 1", simple.get_camps_cleared() == 1)
	_expect(failures, "T5 Camp B selected", simple.get_camp_name() == "MediumCampTransB")
	_expect(failures, "T5 still EARLY_CREEP", simple.get_priority() == SimpleWc3AI.PRIORITY_EARLY_CREEP)
	_expect(failures, "T5 whole army on Camp B", simple.last_move_squad_size >= 6 and simple.last_move_handled)

	_cleanup([simple, enemy_cc, hero, camp_a["camp"], camp_b["camp"]] + pikes)
	await get_tree().process_frame


## TEST 6+7 — Hero dies during creep → HERO/home; Hero returns → resumes naturally.
func _test6_and_7_hero_death_and_return(failures: PackedStringArray) -> void:
	print("verify: TEST6/7 hero death and return")
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

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T67")
	var altar: Building = ALTAR_SCENE.instantiate() as Building
	altar.name = "EnemyAltar_T67"
	altar.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(altar)
	altar.global_position = Vector3(24.0, 1.0, 20.0)
	altar.set_completed()
	altar.add_to_group(&"enemy_command_center")
	altar.add_to_group(&"buildings")

	var hero := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	HeroProgressionStore.register_living_hero(hero)
	var pikes := _spawn_enemy_pikes(self, Vector3(17.0, 0.5, 17.0), 5)
	var camp_data := _spawn_camp(self, "MediumCampDeath", Vector3(18.0, 0.0, 28.0))
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T6 start EARLY_CREEP", simple.get_priority() == SimpleWc3AI.PRIORITY_EARLY_CREEP)

	hero.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "T6 priority HERO after death", simple.get_priority() == SimpleWc3AI.PRIORITY_HERO)
	_expect(failures, "T6 survivors home", simple.last_move_handled)
	_expect(failures, "T6 hero training requested", simple.last_hero_queued or (altar as HeroAltar).is_training_hero())

	var hero2 := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	HeroProgressionStore.register_living_hero(hero2)
	for i: int in pikes.size():
		(pikes[i] as Spearman).global_position = Vector3(17.0 + float(i) * 0.5, 0.5, 17.0)
	await get_tree().process_frame
	simple._process(1.0)
	_expect(
		failures,
		"T7 resumes EARLY_CREEP or BUILD_FORCE (no respawn transition)",
		simple.get_priority() == SimpleWc3AI.PRIORITY_EARLY_CREEP
		or simple.get_priority() == SimpleWc3AI.PRIORITY_BUILD_FORCE
	)
	_expect(failures, "T7 hero alive again", simple.last_hero_alive)

	_cleanup([simple, enemy_cc, altar, hero2, camp_data["camp"]] + pikes)
	await get_tree().process_frame


## TEST 8 — camps >= 2 and power advantage → ATTACK_PLAYER.
func _test8_attack_player(failures: PackedStringArray) -> void:
	print("verify: TEST8 attack player")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T8")
	var hero := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	hero.level = 3
	var pikes := _spawn_enemy_pikes(self, Vector3(17.0, 0.5, 17.0), 5)

	var player_cc: Building = CC_SCENE.instantiate() as Building
	player_cc.name = "PlayerCommandCenter"
	player_cc.team_id = TeamVisuals.PLAYER_TEAM_ID
	add_child(player_cc)
	player_cc.global_position = Vector3(-40.0, 1.0, -40.0)
	player_cc.set_completed()
	player_cc.add_to_group(&"player_command_center")
	player_cc.add_to_group(&"buildings")

	## Mark early creep complete with no remaining camps so EXTRA_CREEP cannot steal.
	simple._camps_cleared = 2
	simple._cleared_camp_names["seed"] = true
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T8 early creep complete", simple.is_early_creep_complete())
	_expect(failures, "T8 power advantage", simple.last_ai_power > simple.last_player_power * 1.25)
	_expect(failures, "T8 priority ATTACK_PLAYER", simple.get_priority() == SimpleWc3AI.PRIORITY_ATTACK_PLAYER)
	_expect(failures, "T8 targets PlayerCC", simple.get_objective_name() == "PlayerCC")
	_expect(failures, "T8 whole army ordered", simple.last_move_squad_size >= 6 and simple.last_move_handled)

	_cleanup([simple, enemy_cc, hero, player_cc] + pikes)
	await get_tree().process_frame


## TEST 9 — new Pikeman during creep receives current group objective next tick.
func _test9_new_pikeman_joins(failures: PackedStringArray) -> void:
	print("verify: TEST9 new pikeman joins live army")
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	var enemy_cc := _spawn_enemy_cc(self, Vector3(20.0, 1.0, 20.0), "EnemyCC_T9")
	var hero := _spawn_enemy_hero(self, Vector3(18.0, 0.5, 18.0))
	var pikes := _spawn_enemy_pikes(self, Vector3(17.0, 0.5, 17.0), 5)
	var camp_data := _spawn_camp(self, "MediumCampJoin", Vector3(18.0, 0.0, 30.0))
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T9 start EARLY_CREEP", simple.get_priority() == SimpleWc3AI.PRIORITY_EARLY_CREEP)
	var squad_before: int = simple.last_move_squad_size

	var new_pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(new_pike)
	new_pike.global_position = Vector3(16.0, 0.5, 16.0)
	new_pike.team_id = TeamVisuals.ENEMY_TEAM_ID
	new_pike.add_to_group(&"enemy_combat_units")
	await get_tree().process_frame

	simple._process(1.0)
	_expect(failures, "T9 still EARLY_CREEP", simple.get_priority() == SimpleWc3AI.PRIORITY_EARLY_CREEP)
	_expect(failures, "T9 army count includes new pike", simple.last_army_count >= squad_before + 1)
	_expect(failures, "T9 group order includes new pike", simple.last_move_squad_size >= squad_before + 1)
	_expect(failures, "T9 same camp objective", simple.get_camp_name() == "MediumCampJoin")

	_cleanup([simple, enemy_cc, hero, new_pike, camp_data["camp"]] + pikes)
	await get_tree().process_frame


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
