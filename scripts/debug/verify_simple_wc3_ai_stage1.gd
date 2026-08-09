extends Node

## Focused Simple WC3 opening regression after total AI purge.
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
	await _test_opening_sequence(failures)
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
	EnemyArmyCommand.reset_match_state()
	EnemyArmyCommand.reset_legacy_military_strategic_order_counter()

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
	_expect(failures, "starts BUILD_FARM", simple.get_state() == SimpleWc3AI.State.BUILD_FARM)
	_expect(failures, "no MilitaryDirectorV2 child", root.get_node_or_null("MilitaryDirectorV2") == null)
	_expect(failures, "no EnemyStrategicDirector child", root.get_node_or_null("EnemyStrategicDirector") == null)

	var attempted: bool = false
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		attempted = true
	)
	_expect(failures, "legacy authorize callback refused", not attempted)

	root.queue_free()
	await get_tree().process_frame


func _test_opening_sequence(failures: PackedStringArray) -> void:
	print("verify: opening build → army → creep fight → DONE")
	EnemyArmyCommand.reset_match_state()
	EnemyArmyCommand.reset_legacy_military_strategic_order_counter()
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	_expect(failures, "gate starts BUILD_FARM", simple.get_state() == SimpleWc3AI.State.BUILD_FARM)

	var farm: Building = FARM_SCENE.instantiate() as Building
	farm.name = "EnemyFarm"
	farm.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(farm)
	farm.global_position = Vector3(22.0, 1.0, 20.0)
	farm.set_completed()
	farm.add_to_group(&"enemy_command_center")
	farm.add_to_group(&"buildings")
	simple._process(0.5)
	_expect(failures, "Farm complete → BUILD_ALTAR", simple.get_state() == SimpleWc3AI.State.BUILD_ALTAR)

	var altar: Building = ALTAR_SCENE.instantiate() as Building
	altar.name = "EnemyHeroAltar"
	altar.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(altar)
	altar.global_position = Vector3(24.0, 1.0, 20.0)
	altar.set_completed()
	altar.add_to_group(&"enemy_command_center")
	altar.add_to_group(&"buildings")
	simple._process(0.5)
	_expect(failures, "Altar complete → BUILD_BARRACKS", simple.get_state() == SimpleWc3AI.State.BUILD_BARRACKS)

	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	barracks.name = "EnemyBarracks"
	barracks.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(barracks)
	barracks.global_position = Vector3(26.0, 1.0, 20.0)
	barracks.set_completed()
	barracks.add_to_group(&"enemy_command_center")
	barracks.add_to_group(&"buildings")
	simple._process(0.5)
	_expect(failures, "Barracks complete → TRAIN_HERO", simple.get_state() == SimpleWc3AI.State.TRAIN_HERO)

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
	simple._process(0.5)
	_expect(failures, "Hero alone → TRAIN_PIKEMEN", simple.get_state() == SimpleWc3AI.State.TRAIN_PIKEMEN)

	var few_pikes: Array = []
	for i: int in 3:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike)
		pike.global_position = Vector3(17.0 + float(i) * 0.8, 0.5, 17.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		few_pikes.append(pike)
	simple._process(0.5)
	_expect(failures, "Hero+3 still TRAIN_PIKEMEN", simple.get_state() == SimpleWc3AI.State.TRAIN_PIKEMEN)

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

	var more_pikes: Array = []
	for i: int in 2:
		var pike2: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike2)
		pike2.global_position = Vector3(16.0 + float(i) * 0.8, 0.5, 16.5)
		pike2.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike2.add_to_group(&"enemy_combat_units")
		more_pikes.append(pike2)

	simple._process(0.5)
	_expect(failures, "Hero+5 → ASSEMBLE (wait)", simple.get_state() == SimpleWc3AI.State.ASSEMBLE)
	_expect(failures, "assembly position chosen", simple.assembly_position != Vector3.ZERO)
	_expect(
		failures,
		"old military strategic orders still 0",
		EnemyArmyCommand.get_legacy_military_strategic_orders_issued() == 0
	)

	## Gather at assembly before creeping — do not leave AFK at Barracks.
	var assemble_at: Vector3 = simple.assembly_position
	hero.global_position = assemble_at + Vector3(0.0, 0.5, 0.0)
	for pike_ref: Variant in few_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = assemble_at + Vector3(-1.0, 0.5, 0.5)
	for pike_ref: Variant in more_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = assemble_at + Vector3(1.0, 0.5, 0.5)

	simple._process(0.5)
	_expect(failures, "assembled → TRAVEL", simple.get_state() == SimpleWc3AI.State.TRAVEL)
	_expect(failures, "custom move issued", simple.last_move_handled)

	hero.global_position = Vector3(18.0, 0.5, 29.0)
	for pike_ref: Variant in few_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = Vector3(17.5, 0.5, 29.2)
	for pike_ref: Variant in more_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = Vector3(18.5, 0.5, 29.2)

	var health_a: HealthComponent = creep_a.get_node_or_null("HealthComponent") as HealthComponent
	var hp_before: float = health_a.current_health if health_a != null else 0.0
	simple._process(0.5)
	_expect(failures, "engage → FIGHT", simple.get_state() == SimpleWc3AI.State.FIGHT)

	for _i: int in 40:
		await get_tree().physics_frame
		simple._process(0.5)
		if health_a != null and health_a.current_health < hp_before:
			break

	_expect(
		failures,
		"real creep HP decreased",
		health_a != null and health_a.current_health < hp_before
	)

	if NodeSafety.is_alive_node(creep_a):
		creep_a.queue_free()
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()

	var camp_b := CreepCamp.new()
	camp_b.name = "MediumCampB"
	add_child(camp_b)
	camp_b.global_position = Vector3(40.0, 0.0, 40.0)
	camp_b.add_to_group(&"creep_camps")
	var creep_b: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp_b.add_child(creep_b)
	creep_b.global_position = Vector3(40.0, 0.5, 40.0)
	creep_b.add_to_group(&"neutral_creeps")
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()

	hero.level = 2
	simple._process(0.5)
	_expect(failures, "camp cleared Hero<3 → TRAVEL next", simple.get_state() == SimpleWc3AI.State.TRAVEL)
	_expect(failures, "next camp is Camp B", simple.get_camp_name() == "MediumCampB")

	## Arrive at Camp 2 — same combat-start path as Camp 1.
	hero.global_position = Vector3(40.0, 0.5, 39.0)
	for pike_ref: Variant in few_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = Vector3(39.5, 0.5, 39.2)
	for pike_ref: Variant in more_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = Vector3(40.5, 0.5, 39.2)

	var health_b: HealthComponent = creep_b.get_node_or_null("HealthComponent") as HealthComponent
	var hp_b_before: float = health_b.current_health if health_b != null else 0.0
	simple._process(0.5)
	_expect(failures, "Camp 2 engage → FIGHT", simple.get_state() == SimpleWc3AI.State.FIGHT)

	for _i: int in 40:
		await get_tree().physics_frame
		simple._process(0.5)
		if health_b != null and health_b.current_health < hp_b_before:
			break

	_expect(
		failures,
		"Camp 2 creep HP decreased",
		health_b != null and health_b.current_health < hp_b_before
	)

	## Camp 2 clear while Hero < 3 → whole army to Camp 3.
	if NodeSafety.is_alive_node(creep_b):
		creep_b.queue_free()
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()
	hero.level = 2

	var camp_c := CreepCamp.new()
	camp_c.name = "MediumCampC"
	add_child(camp_c)
	camp_c.global_position = Vector3(50.0, 0.0, 50.0)
	camp_c.add_to_group(&"creep_camps")
	var creep_c: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp_c.add_child(creep_c)
	creep_c.global_position = Vector3(50.0, 0.5, 50.0)
	creep_c.add_to_group(&"neutral_creeps")
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()

	simple._process(0.5)
	_expect(failures, "camp 2 cleared Hero<3 → TRAVEL Camp 3", simple.get_state() == SimpleWc3AI.State.TRAVEL)
	_expect(failures, "next camp is Camp C", simple.get_camp_name() == "MediumCampC")
	_expect(failures, "Camp 3 move squad includes whole army", simple.last_move_squad_size >= 6)

	## Continuous Pikeman production while creeping when Barracks is free.
	## Fight-loop ticks may already have filled the Barracks queue (max 3).
	var barracks_node: Barracks = barracks as Barracks
	var queued_or_training: bool = (
		barracks_node.get_total_queue_count() > 0 or barracks_node.is_enemy_training_busy()
	)
	if not queued_or_training:
		EnemyResourceManager.reset_to_starting_values()
		EnemyResourceManager.add_gold(400)
		EnemyResourceManager.add_food_max(40)
		var pending_before: int = barracks_node.get_total_queue_count()
		simple._process(0.5)
		queued_or_training = barracks_node.get_total_queue_count() > pending_before
	_expect(failures, "Barracks keeps training Pikemen while creeping", queued_or_training)

	## New Pikeman while creeping → one-shot toward current camp objective.
	var late_pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(late_pike)
	late_pike.global_position = Vector3(26.0, 0.5, 20.0)
	late_pike.team_id = TeamVisuals.ENEMY_TEAM_ID
	late_pike.add_to_group(&"enemy_combat_units")
	var late_id: int = late_pike.get_instance_id()
	simple._process(0.5)
	_expect(failures, "new Pikeman ordered toward current camp", simple._ordered_unit_ids.has(late_id))
	_expect(failures, "new Pikeman move handled", simple.last_move_handled)

	## Arrive at Camp 3 — Pikemen-first combat handoff.
	hero.global_position = Vector3(50.0, 0.5, 49.0)
	for pike_ref: Variant in few_pikes + more_pikes + [late_pike]:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = Vector3(49.5, 0.5, 49.2)

	var health_c: HealthComponent = creep_c.get_node_or_null("HealthComponent") as HealthComponent
	var hp_c_before: float = health_c.current_health if health_c != null else 0.0
	simple._process(0.5)
	_expect(failures, "Camp 3 engage → FIGHT", simple.get_state() == SimpleWc3AI.State.FIGHT)

	for _i: int in 40:
		await get_tree().physics_frame
		simple._process(0.5)
		if health_c != null and health_c.current_health < hp_c_before:
			break

	_expect(
		failures,
		"Camp 3 creep HP decreased",
		health_c != null and health_c.current_health < hp_c_before
	)

	if NodeSafety.is_alive_node(creep_c):
		creep_c.queue_free()
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()
	hero.level = 3

	simple._camp_id = camp_c.get_instance_id()
	simple._state = SimpleWc3AI.State.FIGHT
	simple._process(0.5)
	_expect(failures, "Hero level >=3 → DONE", simple.get_state() == SimpleWc3AI.State.DONE)

	for node_ref: Variant in [farm, altar, barracks, enemy_cc, hero, camp_a, camp_b, camp_c, late_pike]:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()
	for pike_ref: Variant in few_pikes + more_pikes:
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
