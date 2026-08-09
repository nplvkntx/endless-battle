extends Node

## Focused Simple WC3 opening regression.
## Proves: Farm→Altar→Barracks complete gate, Hero+5 before creep,
## shared custom-RTS travel, real creep damage, next camp while Hero <3,
## DONE at Hero >=3, old military remains off.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_simple_wc3_ai_stage1.tscn

const REPORT_PATH := "user://simple_wc3_ai_stage1_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_simple_wc3_ai_stage1: start")

	_expect(failures, "Simple WC3 AI config on", MilitaryAIConfig.is_simple_wc3_ai_enabled())
	_expect(failures, "ai_version_label SimpleWC3", MilitaryAIConfig.ai_version_label() == "SimpleWC3")
	_expect(failures, "V2 runtime inactive under Simple", not MilitaryAIConfig.is_v2_runtime_active())
	_expect(
		failures,
		"legacy military suspended",
		MilitaryAIConfig.is_legacy_military_suspended()
	)

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
	print("verify: exclusive authority + old military off")
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

	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	root.add_child(director)

	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	root.add_child(commander)

	var combat := EnemyCombatController.new()
	combat.name = "EnemyCombatController"
	root.add_child(combat)

	var creep_mgr := EnemyCreepManager.new()
	creep_mgr.name = "EnemyCreepManager"
	root.add_child(creep_mgr)

	var wave_mgr := EnemyWaveManager.new()
	wave_mgr.name = "EnemyWaveManager"
	root.add_child(wave_mgr)

	var defense_mgr := EnemyDefenseManager.new()
	defense_mgr.name = "EnemyDefenseManager"
	root.add_child(defense_mgr)

	var strategic := EnemyStrategicDirector.new()
	strategic.name = "EnemyStrategicDirector"
	strategic.debug_enabled = false
	root.add_child(strategic)

	var gather := EnemyGatherManager.new()
	gather.name = "EnemyGatherManager"
	root.add_child(gather)

	var build := EnemyBuildManager.new()
	build.name = "EnemyBuildManager"
	root.add_child(build)

	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "composition uses simple AI", root._uses_simple_wc3_ai())
	_expect(failures, "authority is SimpleWc3AI", root.military_command_authority is SimpleWc3AI)
	_expect(failures, "V2 military not active", not root.is_v2_military_active())
	_expect(failures, "old military runtime inactive", not root.is_old_military_runtime_active())
	_expect(failures, "MilitaryDirectorV2 process off", not director.is_processing())
	_expect(failures, "ArmyCommanderV2 process off", not commander.is_processing())
	_expect(failures, "EnemyCombatController process off", not combat.is_processing())
	_expect(failures, "EnemyCreepManager process off", not creep_mgr.is_processing())
	_expect(failures, "EnemyWaveManager process off", not wave_mgr.is_processing())
	_expect(failures, "EnemyDefenseManager process off", not defense_mgr.is_processing())
	_expect(failures, "EnemyStrategicDirector still processes (economy)", strategic.is_processing())
	_expect(failures, "starts BUILD_FARM", simple.get_state() == SimpleWc3AI.State.BUILD_FARM)

	var attempted: bool = false
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		attempted = true
	)
	_expect(failures, "legacy authorize callback refused", not attempted)
	EnemyArmyCommand.reset_legacy_military_strategic_order_counter()

	root.queue_free()
	await get_tree().process_frame


func _test_opening_sequence(failures: PackedStringArray) -> void:
	print("verify: opening build → army → creep fight → next camp → DONE")
	EnemyArmyCommand.reset_match_state()
	EnemyArmyCommand.reset_legacy_military_strategic_order_counter()
	CreepCampSafety.reset_match_state()
	PlayerRouteNavigation.clear_all()

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	add_child(simple)
	await get_tree().process_frame

	## --- Build completion gates ---
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

	## Hero alone must NOT start creeping.
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
	_expect(
		failures,
		"Hero+3 still TRAIN_PIKEMEN (no early creep)",
		simple.get_state() == SimpleWc3AI.State.TRAIN_PIKEMEN
	)

	## Camp A ready before army completes — must still wait for 5 pikemen.
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

	simple._process(0.5)
	_expect(
		failures,
		"still TRAIN_PIKEMEN with camp available but <5 pikes",
		simple.get_state() == SimpleWc3AI.State.TRAIN_PIKEMEN
	)

	## Reach 5 living pikemen → creep starts.
	var more_pikes: Array = []
	for i: int in 2:
		var pike2: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike2)
		pike2.global_position = Vector3(16.0 + float(i) * 0.8, 0.5, 16.5)
		pike2.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike2.add_to_group(&"enemy_combat_units")
		more_pikes.append(pike2)

	simple._process(0.5)
	_expect(failures, "Hero+5 → TRAVEL", simple.get_state() == SimpleWc3AI.State.TRAVEL)
	_expect(failures, "observed pikemen >= 5", simple.last_pikeman_count >= 5)
	_expect(failures, "custom move issued", simple.last_move_handled)
	_expect(failures, "move squad is army size", simple.last_move_squad_size >= 6)
	_expect(failures, "hero has custom RTS route", hero.has_custom_rts_route())
	_expect(
		failures,
		"old military strategic orders still 0",
		EnemyArmyCommand.get_legacy_military_strategic_orders_issued() == 0
	)

	## Place army at camp → FIGHT with real attack orders + HP drop.
	hero.global_position = Vector3(18.0, 0.5, 29.0)
	for pike_ref: Variant in few_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = Vector3(17.5, 0.5, 29.2)
	for pike_ref: Variant in more_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Spearman).global_position = Vector3(18.5, 0.5, 29.2)

	var health_a: HealthComponent = creep_a.get_node_or_null("HealthComponent") as HealthComponent
	_expect(failures, "camp A creep has health", health_a != null)
	var hp_before: float = health_a.current_health if health_a != null else 0.0

	simple._process(0.5)
	_expect(failures, "engage → FIGHT", simple.get_state() == SimpleWc3AI.State.FIGHT)

	## Drive combat a few frames so damage lands.
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
	_expect(failures, "still FIGHT while camp alive", simple.get_state() == SimpleWc3AI.State.FIGHT)

	## Clear camp A → next camp while Hero < 3.
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
	_expect(failures, "next camp selected", simple.get_camp_name() == "MediumCampB")

	## Hero reaches level 3 after clear → DONE.
	if NodeSafety.is_alive_node(creep_b):
		creep_b.queue_free()
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()
	hero.level = 3
	## Reseed a camp so DONE is from level stop, not empty map.
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

	## Simulate clear of current camp at level 3.
	simple._camp_id = camp_b.get_instance_id()
	simple._state = SimpleWc3AI.State.FIGHT
	simple._process(0.5)
	_expect(failures, "Hero level >=3 → DONE", simple.get_state() == SimpleWc3AI.State.DONE)
	_expect(
		failures,
		"old military orders still 0 after opening",
		EnemyArmyCommand.get_legacy_military_strategic_orders_issued() == 0
	)

	## Cleanup
	for node_ref: Variant in [
		farm, altar, barracks, enemy_cc, hero, camp_a, camp_b, camp_c
	]:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node).queue_free()
	for pike_ref: Variant in few_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Node).queue_free()
	for pike_ref: Variant in more_pikes:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Node).queue_free()
	if NodeSafety.is_alive_node(creep_c):
		creep_c.queue_free()
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
	_expect(failures, "scene uses simple AI", root._uses_simple_wc3_ai())
	_expect(failures, "scene authority SimpleWc3AI", root.military_command_authority is SimpleWc3AI)
	_expect(failures, "scene V2 military inactive", not root.is_v2_military_active())
	_expect(failures, "scene old military inactive", not root.is_old_military_runtime_active())
	_expect(failures, "EnemyBuildManager still present", root.enemy_build_manager != null)
	_expect(failures, "EnemyGatherManager still present", root.enemy_gather_manager != null)
	_expect(failures, "EnemyStrategicDirector still present", root.enemy_strategic_director != null)

	systems.queue_free()
	await get_tree().process_frame
