extends Node

## Exclusive military-authority regression for Simple WC3 AI (WAIT-only bootstrap).
## Proves: Simple controller exists + owns authority; old military process is off;
## old strategic order count stays 0; no military orders issued yet; economy peers remain.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_simple_wc3_ai_stage1.tscn

const REPORT_PATH := "user://simple_wc3_ai_stage1_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")


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

	await _test_exclusive_authority_wait_only(failures)
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


func _test_exclusive_authority_wait_only(failures: PackedStringArray) -> void:
	print("verify: exclusive authority WAIT-only + economy peers alive")
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
	_expect(failures, "EnemyGatherManager present", gather != null and gather.is_inside_tree())
	_expect(failures, "EnemyBuildManager present", build != null and build.is_inside_tree())

	## Spawn hero + pikemen — Simple must observe but stay WAIT / issue 0 orders.
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

	var pikemen: Array = []
	for i: int in 5:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike)
		pike.global_position = Vector3(17.0 + float(i) * 0.8, 0.5, 17.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		pikemen.append(pike)

	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3(19.0, 0.5, 19.0)
	worker.team_id = TeamVisuals.ENEMY_TEAM_ID
	worker.add_to_group(&"enemy_workers")

	await get_tree().process_frame
	for _i: int in 6:
		simple._process(0.5)
		await get_tree().process_frame

	_expect(failures, "Simple stays WAIT", simple.get_state() == SimpleWc3AI.State.WAIT)
	_expect(failures, "Simple state label WAIT", simple.get_state_label() == "WAIT")
	_expect(failures, "observed hero alive", simple.last_hero_alive)
	_expect(failures, "observed pikemen >= 5", simple.last_pikeman_count >= 5)
	_expect(failures, "Simple strategic orders still 0", simple.strategic_orders_issued == 0)
	_expect(
		failures,
		"old military strategic orders issued == 0",
		EnemyArmyCommand.get_legacy_military_strategic_orders_issued() == 0
	)
	_expect(failures, "hero has no custom RTS route yet", not hero.has_custom_rts_route())

	## Attempted legacy authorize must be refused + counted while Simple owns authority.
	var attempted: bool = false
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		attempted = true
	)
	_expect(failures, "legacy authorize callback refused", not attempted)
	_expect(
		failures,
		"refused authorize increments old-order counter",
		EnemyArmyCommand.get_legacy_military_strategic_orders_issued() == 1
	)
	EnemyArmyCommand.reset_legacy_military_strategic_order_counter()

	hero.queue_free()
	for pike_ref: Variant in pikemen:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Node).queue_free()
	if NodeSafety.is_alive_node(worker):
		worker.queue_free()
	if NodeSafety.is_alive_node(enemy_cc):
		enemy_cc.queue_free()
	root.queue_free()
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
	_expect(
		failures,
		"EnemyBuildManager still present",
		root.enemy_build_manager != null
	)
	_expect(
		failures,
		"EnemyGatherManager still present",
		root.enemy_gather_manager != null
	)
	_expect(
		failures,
		"EnemyStrategicDirector still present",
		root.enemy_strategic_director != null
	)

	systems.queue_free()
	await get_tree().process_frame
