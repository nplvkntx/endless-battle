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

	var orders_while_camp: int = simple.strategic_orders_issued
	simple._process(1.0)
	_expect(
		failures,
		"order refresh: camp alive does not recommande army",
		simple.strategic_orders_issued == orders_while_camp
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

	## 6) Assemble when weak — kill hero.
	hero.queue_free()
	await get_tree().process_frame
	simple._process(1.0)
	_expect(failures, "6 assemble occurs when weak", simple.get_state() == SimpleWc3AI.State.ASSEMBLE or simple.get_state() == SimpleWc3AI.State.OPENING)

	for node_ref: Variant in [farm, altar, barracks, enemy_cc, player_cc, camp_a]:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()
	for pike_ref: Variant in pikes + player_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Node).queue_free()
	simple.queue_free()
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
