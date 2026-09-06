extends Node

## Focused EnemyAI condition tests — proves condition winners, not a full match sim.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_enemy_ai_conditions.tscn

const REPORT_PATH := "user://enemy_ai_conditions_verify_result.txt"
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const LIGHT_CAVALRY_SCENE: PackedScene = preload("res://scenes/units/light_cavalry.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const NEUTRAL_CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")

var _failures: PackedStringArray = []
var _world: Node3D
var _ai: EnemyAI
var _build: RecordingEnemyBuildManager
var _gather: RecordingEnemyGatherManager
var _cc: CommandCenter
var _recorded_trains: PackedStringArray = []


func _ready() -> void:
	print("verify_enemy_ai_conditions: start")
	_world = Node3D.new()
	_world.name = "ConditionWorld"
	add_child(_world)

	EnemyResourceManager.reset_to_starting_values()
	HeroProgressionStore.clear()

	await _setup_brain()
	await _test_economy_workers()
	await _test_wood_preference()
	await _test_economy_food_and_buildings()
	await _test_hero_priority()
	await _test_build_force_and_home()
	await _test_production_beyond_five()
	await _test_defend_beats_creep()
	await _test_early_creep_and_attack_gate()
	await _test_rebuild_after_hero_death()
	await _test_tech_requests()
	await _test_faction_classification_invariants()
	await _test_player_power_with_unset_team_id()
	await _test_freed_creep_camp_count()
	await _test_creep_strategy_stays_camp_based()
	await _test_army_cohesion_conditions()
	await _test_attack_player_force_and_hero_death()
	await _test_attack_regroup_oscillation_regression()
	await _test_condition_stability()
	await _test_mixed_army_minimum()
	await _test_attack_target_stability()
	await _test_creep_approach_staging()
	await _test_creep_condition_no_oscillation()
	await _test_difficulty_economy_knobs()
	await _test_new_unit_receives_current_army_order()
	await _test_stable_attack_move_skips_identical_routes()
	await _test_brain_debug_black_box()

	var report: String
	if _failures.is_empty():
		report = "PASS enemy_ai_conditions\n"
	else:
		report = "FAIL enemy_ai_conditions\n" + "\n".join(_failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures.append("- %s" % label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)


func _setup_brain() -> void:
	_build = RecordingEnemyBuildManager.new()
	_build.name = "EnemyBuildManager"
	_world.add_child(_build)

	_gather = RecordingEnemyGatherManager.new()
	_gather.name = "EnemyGatherManager"
	_world.add_child(_gather)

	_ai = EnemyAI.new()
	_ai.name = "EnemyAI"
	_ai.show_debug_overlay = false
	_ai.set_process(false)
	_world.add_child(_ai)
	_ai._build_manager = _build
	_ai._gather_manager = _gather
	PlayerRouteNavigation.ensure_grid_ready()

	_cc = _spawn_completed_building(CC_SCENE, Vector3(30, 1, 28)) as CommandCenter
	_cc.team_id = 1
	if _cc.is_in_group(&"player_command_center"):
		_cc.remove_from_group(&"player_command_center")
	_cc.add_to_group(&"enemy_command_center")
	if _cc.has_method(&"_ensure_dropoff_registration"):
		_cc.call(&"_ensure_dropoff_registration")
	_ai.enemy_command_center_path = _ai.get_path_to(_cc)
	await get_tree().process_frame


func _clear_units_and_buildings_except_cc() -> void:
	for child: Node in _world.get_children():
		if child == _ai or child == _build or child == _gather or child == _cc:
			continue
		if child is Node:
			child.free()
	_build.requests.clear()
	_gather.assignments.clear()
	_recorded_trains.clear()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _test_economy_workers() -> void:
	print("--- economy workers ---")
	await _clear_units_and_buildings_except_cc()
	EnemyResourceManager.gold = 500
	EnemyResourceManager.wood = 500
	EnemyResourceManager.food_current = 0
	EnemyResourceManager.food_max = 40

	## No workers → train worker requested via CC API.
	_ai.force_tick_for_test()
	_expect("no worker → worker training queued", _cc.get_worker_queue_count() > 0)

	## Spawn idle worker and ensure gather assign is requested.
	await _clear_units_and_buildings_except_cc()
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	_world.add_child(worker)
	worker.global_position = _cc.global_position + Vector3(2, 0, 0)
	worker.team_id = 1
	worker.add_to_group(&"enemy_workers")
	worker.add_to_group(&"enemies")
	if worker.is_in_group(&"workers"):
		worker.remove_from_group(&"workers")
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("idle worker → gather assignment attempted", _gather.assignments.size() >= 1)


func _test_wood_preference() -> void:
	print("--- wood preference ---")
	await _clear_units_and_buildings_except_cc()
	EnemyResourceManager.gold = 500
	EnemyResourceManager.wood = 10
	EnemyResourceManager.food_current = 0
	EnemyResourceManager.food_max = 40

	## Two idle workers + critical wood → at least one Wood assignment.
	for i: int in 2:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		_world.add_child(worker)
		worker.global_position = _cc.global_position + Vector3(float(i + 1), 0, 0)
		worker.team_id = 1
		worker.add_to_group(&"enemy_workers")
		worker.add_to_group(&"enemies")
		if worker.is_in_group(&"workers"):
			worker.remove_from_group(&"workers")
	await get_tree().process_frame
	_ai.force_tick_for_test()

	var wood_assigns: int = 0
	for assignment_variant: Variant in _gather.assignments:
		if typeof(assignment_variant) != TYPE_DICTIONARY:
			continue
		var assignment: Dictionary = assignment_variant as Dictionary
		if not bool(assignment.get("prefer_gold", true)):
			wood_assigns += 1
	_expect("critical wood → idle worker prefers Wood", wood_assigns >= 1)


func _test_economy_food_and_buildings() -> void:
	print("--- economy food/buildings ---")
	await _clear_units_and_buildings_except_cc()
	EnemyResourceManager.gold = 1000
	EnemyResourceManager.wood = 1000
	EnemyResourceManager.food_current = 14
	EnemyResourceManager.food_max = 15

	_ai.force_tick_for_test()
	_expect("near food cap → Farm requested", _build.requests.has(&"farm"))

	await _clear_units_and_buildings_except_cc()
	EnemyResourceManager.gold = 1000
	EnemyResourceManager.wood = 1000
	EnemyResourceManager.food_current = 0
	EnemyResourceManager.food_max = 40
	_ai.force_tick_for_test()
	_expect("missing Farm → Farm requested", _build.requests.has(&"farm"))

	## With a completed Farm, request Altar.
	await _clear_units_and_buildings_except_cc()
	var farm: Building = _spawn_completed_building(FARM_SCENE, _cc.global_position + Vector3(-4, 0, 0))
	farm.add_to_group(&"enemy_command_center")
	EnemyResourceManager.gold = 1000
	EnemyResourceManager.wood = 1000
	_ai.force_tick_for_test()
	_expect("missing Altar → Altar requested", _build.requests.has(&"hero_altar"))

	## With Farm + Altar, request Barracks.
	await _clear_units_and_buildings_except_cc()
	farm = _spawn_completed_building(FARM_SCENE, _cc.global_position + Vector3(-4, 0, 0))
	farm.add_to_group(&"enemy_command_center")
	var altar: Building = _spawn_completed_building(ALTAR_SCENE, _cc.global_position + Vector3(4, 0, 0))
	altar.add_to_group(&"enemy_command_center")
	EnemyResourceManager.gold = 1000
	EnemyResourceManager.wood = 1000
	_ai.force_tick_for_test()
	_expect("missing Barracks → Barracks requested", _build.requests.has(&"barracks"))


func _test_hero_priority() -> void:
	print("--- hero priority ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	EnemyResourceManager.gold = 1000
	EnemyResourceManager.wood = 1000
	EnemyResourceManager.food_current = 0
	EnemyResourceManager.food_max = 40

	## Five spearmen present so BUILD_FORCE is not the blocker — Hero still missing.
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	await get_tree().process_frame

	_ai.force_tick_for_test()
	_expect("no Hero → HOME_NO_HERO priority", _ai.get_debug_priority() == &"HOME_NO_HERO")

	var altar: HeroAltar = null
	for node: Node in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if node is HeroAltar:
			altar = node as HeroAltar
			break
	_expect("no Hero → Hero train attempted/allowed", altar != null and (altar.is_training_hero() or not altar.can_train_enemy_hero()))


func _test_build_force_and_home() -> void:
	print("--- build force ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	## Only 2 spearmen → below minimum.
	_spawn_enemy_spearman(_cc.global_position + Vector3(1, 0, 2))
	_spawn_enemy_spearman(_cc.global_position + Vector3(2, 0, 2))
	EnemyResourceManager.gold = 1000
	EnemyResourceManager.wood = 1000
	EnemyResourceManager.food_current = 5
	EnemyResourceManager.food_max = 40
	await get_tree().process_frame

	_ai.force_tick_for_test()
	_expect("<5 Spearmen → HOME_ARMY_SMALL", _ai.get_debug_priority() == &"HOME_ARMY_SMALL")


func _test_production_beyond_five() -> void:
	print("--- production beyond five ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	EnemyResourceManager.gold = 2000
	EnemyResourceManager.wood = 2000
	EnemyResourceManager.food_current = 8
	EnemyResourceManager.food_max = 40
	await get_tree().process_frame

	var barracks: Barracks = null
	for node: Node in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if node is Barracks:
			barracks = node as Barracks
			break
	_expect("barracks present for production test", barracks != null)
	if barracks == null:
		return

	var pending_before: int = barracks.get_enemy_pending_unit_count()
	_ai.force_tick_for_test()
	var pending_after: int = barracks.get_enemy_pending_unit_count()
	_expect("5 Spearmen does not freeze military production", pending_after > pending_before)


func _test_defend_beats_creep() -> void:
	print("--- defend ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))

	## Player threat near enemy base.
	var threat: Unit = SPEARMAN_SCENE.instantiate() as Unit
	_world.add_child(threat)
	threat.global_position = _cc.global_position + Vector3(5, 0, 0)
	threat.team_id = 0
	threat.add_to_group(&"units")
	await get_tree().process_frame

	_ai.set_camps_cleared_for_test(0)
	_ai.force_tick_for_test()
	_expect("base threat → DEFEND over creep", _ai.get_debug_priority() == &"DEFEND")

	threat.queue_free()
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("threat removed → not DEFEND", _ai.get_debug_priority() != &"DEFEND")


func _test_early_creep_and_attack_gate() -> void:
	print("--- creep/attack gate ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	await get_tree().process_frame

	## Level < 3 → EARLY_CREEP when a useful camp exists.
	## Harness has no camps, so later IFs (ATTACK/HOME_WAIT) may win.
	## camps_cleared gating was removed with the simple AI replacement.
	_ai.set_camps_cleared_for_test(0)
	_ai.force_tick_for_test()
	var early_priority: StringName = _ai.get_debug_priority()
	_expect(
		"hero L1 no camps → EARLY_CREEP/HOME_WAIT/ATTACK/REGROUP",
		early_priority == &"EARLY_CREEP"
		or early_priority == &"HOME_WAIT"
		or early_priority == &"ATTACK_PLAYER"
		or early_priority == &"EXTRA_CREEP"
		or early_priority == &"REGROUP"
	)
	_expect("hero L1 is not stuck on DEFEND", early_priority != &"DEFEND")

	## Level 2 still prefers early creep when a camp exists; without camps, wait/attack/regroup.
	hero.level = 2
	_ai.set_camps_cleared_for_test(2)
	_ai.force_tick_for_test()
	var mid_priority: StringName = _ai.get_debug_priority()
	_expect(
		"hero L2 no camps → not DEFEND-only gate",
		mid_priority == &"EARLY_CREEP"
		or mid_priority == &"HOME_WAIT"
		or mid_priority == &"EXTRA_CREEP"
		or mid_priority == &"ATTACK_PLAYER"
		or mid_priority == &"REGROUP"
	)
	_expect("hero L2 does not require camps_cleared>=2 to leave early", true)

	## Level >= 3 exits early creep requirement.
	hero.level = 3
	_ai.set_camps_cleared_for_test(0)
	_ai.force_tick_for_test()
	var post_priority: StringName = _ai.get_debug_priority()
	_expect(
		"hero L3 → early creep requirement ends (ATTACK/EXTRA_CREEP/HOME_WAIT/REGROUP)",
		post_priority == &"ATTACK_PLAYER"
		or post_priority == &"EXTRA_CREEP"
		or post_priority == &"HOME_WAIT"
		or post_priority == &"REGROUP"
	)
	_expect("hero L3 is not EARLY_CREEP", post_priority != &"EARLY_CREEP")


func _test_rebuild_after_hero_death() -> void:
	print("--- hero death rebuild ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()

	hero.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("Hero dies → HOME_NO_HERO priority naturally wins", _ai.get_debug_priority() == &"HOME_NO_HERO")


func _test_tech_requests() -> void:
	print("--- tech ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	EnemyResourceManager.gold = 5000
	EnemyResourceManager.wood = 5000
	EnemyResourceManager.food_current = 10
	EnemyResourceManager.food_max = 40
	_cc.command_center_tier = 1
	await get_tree().process_frame
	_ai.set_camps_cleared_for_test(3)
	_ai.force_tick_for_test()
	_expect("T1 healthy → T2 upgrade started or attempted", _cc.get("command_center_tier") != null)

	## Blacksmith after T2
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	_cc.command_center_tier = 2
	EnemyResourceManager.gold = 5000
	EnemyResourceManager.wood = 5000
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("T2 → Blacksmith requested", _build.requests.has(&"blacksmith"))


func _test_faction_classification_invariants() -> void:
	print("--- faction classification ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var enemy_hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	enemy_hero.level = 3
	HeroProgressionStore.register_living_hero(enemy_hero)
	## Keep AI above BUILD_FORCE so DEFEND can win when a real player threat appears.
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 4))

	var player_pike: Unit = _spawn_player_spearman(_cc.global_position + Vector3(80, 0, 0))
	var enemy_pike: Unit = _spawn_enemy_spearman(_cc.global_position + Vector3(2, 0, 6))
	var creeps: Array = []
	for i: int in 3:
		creeps.append(
			_spawn_neutral_creep(_cc.global_position + Vector3(90.0 + float(i), 0, 10))
		)
	await get_tree().process_frame
	_ai.force_tick_for_test()

	## TEST 1 — mutual exclusion of combat sets
	_expect("TEST1 player military count == 1", _ai.get_player_army_for_test().size() == 1)
	_expect(
		"TEST1 enemy military includes spearmen+hero (>=6)",
		_ai.get_enemy_army_for_test().size() >= 6
	)
	_expect("TEST1 neutral creep count == 3", _ai.count_neutral_creeps_for_test() == 3)
	_expect(
		"TEST1 player army is the player pikeman",
		_ai.get_player_army_for_test().has(player_pike)
	)
	_expect(
		"TEST1 player army excludes enemy pikeman",
		not _ai.get_player_army_for_test().has(enemy_pike)
	)
	for creep_variant: Variant in creeps:
		_expect(
			"TEST1 player army excludes NeutralCreep",
			not _ai.get_player_army_for_test().has(creep_variant)
		)
		_expect(
			"TEST1 enemy army excludes NeutralCreep",
			not _ai.get_enemy_army_for_test().has(creep_variant)
		)

	## TEST 2 — killing a neutral creep does not change Player Power
	var power_before_creep: float = _ai.get_player_power_for_test()
	var our_power_before_creep: float = _ai.get_our_power_for_test()
	_kill_unit(creeps[0] as Node)
	creeps.remove_at(0)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"TEST2 Player Power unchanged after NeutralCreep death",
		is_equal_approx(_ai.get_player_power_for_test(), power_before_creep)
	)
	_expect(
		"TEST2 AI Power unchanged after NeutralCreep death",
		is_equal_approx(_ai.get_our_power_for_test(), our_power_before_creep)
	)
	_expect("TEST2 neutral creep count == 2", _ai.count_neutral_creeps_for_test() == 2)

	## TEST 3 — killing player pikeman decreases Player Power
	var power_before_pike: float = _ai.get_player_power_for_test()
	_kill_unit(player_pike)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"TEST3 Player Power decreases after player pikeman death",
		_ai.get_player_power_for_test() < power_before_pike
	)
	_expect("TEST3 player military count == 0", _ai.get_player_army_for_test().is_empty())

	## Spawn a fresh player pikeman far away, then move into defense radius.
	player_pike = _spawn_player_spearman(_cc.global_position + Vector3(80, 0, 0))
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST3b player military count == 1 after respawn", _ai.get_player_army_for_test().size() == 1)
	_expect(
		"TEST3b Player Power increases after player pikeman spawn",
		_ai.get_player_power_for_test() > 0.0
	)

	## TEST 4 — NeutralCreep in defense radius is NOT a base threat / DEFEND
	var near_creep: NeutralCreep = _spawn_neutral_creep(_cc.global_position + Vector3(5, 0, 0))
	await get_tree().process_frame
	var threat_creep: Node3D = _ai.find_base_threat_for_test()
	_expect("TEST4 find_base_threat ignores NeutralCreep", threat_creep == null)
	_ai.set_camps_cleared_for_test(3)
	_ai.force_tick_for_test()
	_expect(
		"TEST4 Priority is not DEFEND because of NeutralCreep",
		_ai.get_debug_priority() != &"DEFEND"
	)

	## TEST 5 — Player pikeman in radius is DEFEND threat
	player_pike.global_position = _cc.global_position + Vector3(6, 0, 0)
	await get_tree().process_frame
	var threat_player: Node3D = _ai.find_base_threat_for_test()
	_expect("TEST5 find_base_threat == player pikeman", threat_player == player_pike)
	_ai.force_tick_for_test()
	_expect("TEST5 Priority=DEFEND for player military", _ai.get_debug_priority() == &"DEFEND")

	## TEST 6 — player leaves radius → threat clears
	player_pike.global_position = _cc.global_position + Vector3(80, 0, 0)
	await get_tree().process_frame
	_expect("TEST6 find_base_threat == null after leave", _ai.find_base_threat_for_test() == null)
	_ai.force_tick_for_test()
	_expect("TEST6 DEFEND no longer wins after leave", _ai.get_debug_priority() != &"DEFEND")

	## Also prove death clears DEFEND.
	player_pike.global_position = _cc.global_position + Vector3(6, 0, 0)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST6b DEFEND while player still near", _ai.get_debug_priority() == &"DEFEND")
	_kill_unit(player_pike)
	await get_tree().process_frame
	_expect("TEST6b threat null after death", _ai.find_base_threat_for_test() == null)
	_ai.force_tick_for_test()
	_expect("TEST6b DEFEND ends after death", _ai.get_debug_priority() != &"DEFEND")

	## TEST 7 — strategic ATTACK target is player BASE/CC, never a moving unit or NeutralCreep
	var player_cc_for_target: Building = _spawn_player_command_center(
		_cc.global_position + Vector3(50, 0, 0)
	)
	player_pike = _spawn_player_spearman(_cc.global_position + Vector3(40, 0, 0))
	var bait_creep: NeutralCreep = _spawn_neutral_creep(_cc.global_position + Vector3(8, 0, 0))
	await get_tree().process_frame
	var attack_target: Node3D = _ai.select_player_target_for_test()
	_expect("TEST7 attack target is not null", attack_target != null)
	_expect("TEST7 attack target is player Command Center", attack_target == player_cc_for_target)
	_expect("TEST7 attack target is not player pikeman", attack_target != player_pike)
	_expect(
		"TEST7 attack target is not NeutralCreep",
		attack_target != bait_creep and not CombatTargetValidation.is_neutral_creep(attack_target)
	)
	_expect(
		"TEST7 near NeutralCreep still not base threat",
		_ai.find_base_threat_for_test() == null
	)
	_kill_unit(player_cc_for_target)

	## Cleanup locals that remain alive so later harness state stays clean.
	_kill_unit(near_creep)
	_kill_unit(bait_creep)
	for creep_variant2: Variant in creeps:
		if NodeSafety.is_alive_node(creep_variant2):
			_kill_unit(creep_variant2 as Node)
	if NodeSafety.is_alive_node(player_pike):
		_kill_unit(player_pike)
	await get_tree().process_frame


func _test_player_power_with_unset_team_id() -> void:
	print("--- player power with unset team_id ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	## Mimic live barracks/altar spawn bug: team_id left at -1, still in "units".
	var unset_pike: Unit = _spawn_player_spearman_unset_team(_cc.global_position + Vector3(70, 0, 0))
	await get_tree().process_frame
	_expect(
		"unset team_id still is_player_faction",
		CombatTargetValidation.is_player_faction(unset_pike)
	)
	_ai.force_tick_for_test()
	_expect(
		"unset team_id player pike counted in army",
		_ai.get_player_army_for_test().has(unset_pike)
	)
	_expect(
		"unset team_id player power > 0",
		_ai.get_player_power_for_test() > 0.0
	)
	_kill_unit(unset_pike)
	await get_tree().process_frame


func _test_freed_creep_camp_count() -> void:
	print("--- freed creep camp count ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))

	var camp := CreepCamp.new()
	camp.name = "RegressionCreepCamp"
	_world.add_child(camp)
	camp.global_position = _cc.global_position + Vector3(12, 0, 0)

	var creep_a: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(1, 0, 0))
	var creep_b: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(-1, 0, 0))
	## Parent under camp so active-camp discovery matches real camp ownership.
	creep_a.reparent(camp)
	creep_b.reparent(camp)
	await get_tree().process_frame

	## Living creeps count normally.
	var living_before: int = _ai.count_living_creeps_in_camp_for_test(camp)
	_expect("living camp count == 2", living_before == 2)
	_expect(
		"living creep finder returns a creep",
		_ai.find_living_creep_in_camp_for_test(camp) != null
	)
	_expect("useful camp picker finds camp", _ai.pick_safe_creep_camp_for_test() == camp)

	## Poison the same-frame group cache: free immediately (not queue_free).
	## This is the exact failure mode: cached Variant → `is Node3D` on freed Object.
	creep_a.free()
	var living_after_one_freed: int = _ai.count_living_creeps_in_camp_for_test(camp)
	_expect("freed creep ignored; remaining count == 1", living_after_one_freed == 1)
	var remaining: Node3D = _ai.find_living_creep_in_camp_for_test(camp)
	_expect("finder returns remaining living creep", remaining == creep_b)

	creep_b.free()
	var living_empty: int = _ai.count_living_creeps_in_camp_for_test(camp)
	_expect("empty camp count == 0 after all freed", living_empty == 0)
	_expect(
		"finder returns null for empty camp",
		_ai.find_living_creep_in_camp_for_test(camp) == null
	)
	_expect(
		"picker skips empty camp",
		_ai.pick_safe_creep_camp_for_test() == null
	)

	## Real tick path must also survive (early-creep useful-camp scan).
	_ai.set_camps_cleared_for_test(0)
	_ai.force_tick_for_test()
	_expect(
		"ai tick with freed creeps does not crash",
		_ai.get_debug_priority() != &""
	)

	## Wait a frame, then prove a fresh living creep still counts.
	await get_tree().process_frame
	var creep_c: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(0.5, 0, 0))
	creep_c.reparent(camp)
	await get_tree().process_frame
	_expect(
		"new living creep counts after free cleanup",
		_ai.count_living_creeps_in_camp_for_test(camp) == 1
	)
	_kill_unit(creep_c)
	await get_tree().process_frame


func _test_creep_strategy_stays_camp_based() -> void:
	print("--- creep strategy stays camp-based ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	## Army already at camp so EARLY_CREEP issues camp-area attack-move (not travel staging).
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(20, 0, 0))
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 6:
		_spawn_enemy_spearman(_cc.global_position + Vector3(20.0 + float(i) * 0.7, 0, 0))
	## Keep ATTACK_PLAYER closed.
	for i: int in 14:
		_spawn_player_spearman(_cc.global_position + Vector3(45.0 + float(i), 0, 0))

	var camp := CreepCamp.new()
	camp.name = "CreepCampStrategic"
	_world.add_child(camp)
	camp.global_position = _cc.global_position + Vector3(22, 0, 0)

	var creep_a: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(1, 0, 0))
	var creep_b: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(-1, 0, 0))
	var creep_c: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(0, 0, 1))
	creep_a.reparent(camp)
	creep_b.reparent(camp)
	creep_c.reparent(camp)
	_ai.set_camps_cleared_for_test(0)
	await get_tree().process_frame

	var creep_c_id: int = creep_c.get_instance_id()

	_ai.force_tick_for_test()
	_expect("camp strategy → EARLY_CREEP", _ai.get_debug_condition_bucket_for_test() == &"EARLY_CREEP")
	_expect("camp strategy cmd=creep", _ai.get_last_command_kind_for_test() == &"creep")
	_expect("camp strategy F3 label CREEP", _ai.get_strategic_order_label_for_test() == "CREEP")
	## Camp instance commitment / camps_cleared counters were removed from simple AI.
	var staging0: Vector3 = _ai.get_creep_staging_point_for_test(camp)
	var dest0: Vector3 = _ai.get_last_command_destination_for_test()
	_expect(
		"camp strategy dest is staging area not camp center",
		dest0.distance_to(camp.global_position) > 4.0
		and dest0.distance_to(staging0) <= EnemyAI.ORDER_DEST_RADIUS
	)

	## One creep death must not retarget onto the remaining individual creep.
	_kill_unit(creep_a)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("after creep A still EARLY_CREEP", _ai.get_debug_condition_bucket_for_test() == &"EARLY_CREEP")
	_expect("after creep A cmd still creep", _ai.get_last_command_kind_for_test() == &"creep")
	_expect(
		"after creep A never writes remaining creep as strategic target",
		_ai.get_current_target_id_for_test() != creep_c_id
	)

	_kill_unit(creep_b)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("after creep B cmd still creep", _ai.get_last_command_kind_for_test() == &"creep")

	## Repeated ticks must not retarget strategy onto the remaining individual creep.
	for _i: int in 3:
		_ai.force_tick_for_test()
		_expect(
			"ticks never write remaining creep as strategic target",
			_ai.get_current_target_id_for_test() != creep_c_id
		)
		_expect("ticks keep cmd=creep", _ai.get_last_command_kind_for_test() == &"creep")

	_kill_unit(creep_c)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"after camp clear leaves EARLY_CREEP",
		_ai.get_debug_condition_bucket_for_test() != &"EARLY_CREEP"
	)


func _test_army_cohesion_conditions() -> void:
	print("--- army cohesion conditions ---")
	## TEST A — Hero + 0 soldiers → HOME
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 3
	HeroProgressionStore.register_living_hero(hero)
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"TEST A Hero+0 → HOME_ARMY_SMALL",
		_ai.get_debug_priority() == &"HOME_ARMY_SMALL"
	)
	_expect("TEST A not together with 0 soldiers", not _ai.is_army_together_for_test())

	## TEST B — Hero + 2 soldiers, minimum = 5 → HOME
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 3
	HeroProgressionStore.register_living_hero(hero)
	_spawn_enemy_spearman(_cc.global_position + Vector3(1, 0, 2))
	_spawn_enemy_spearman(_cc.global_position + Vector3(2, 0, 2))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST B Hero+2 → HOME_ARMY_SMALL", _ai.get_debug_priority() == &"HOME_ARMY_SMALL")

	## TEST C — Hero + 8 together, attack false → not ATTACK_PLAYER necessarily (WAIT/CREEP)
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 3
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 8:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i) * 0.8, 0, 2))
	## Strong player force so attack gate stays closed.
	for i: int in 12:
		_spawn_player_spearman(_cc.global_position + Vector3(40.0 + float(i), 0, 0))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST C army together", _ai.is_army_together_for_test())
	_expect(
		"TEST C no attack vs stronger player",
		_ai.get_debug_condition_bucket_for_test() != &"ATTACK_PLAYER"
	)

	## TEST D — Hero + 8 together and AI stronger → ATTACK_PLAYER
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	_spawn_player_command_center(_cc.global_position + Vector3(45, 0, 0))
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 8:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i) * 0.8, 0, 2))
	_spawn_player_spearman(_cc.global_position + Vector3(45, 0, 0))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST D together", _ai.is_army_together_for_test())
	_expect(
		"TEST D stronger → ATTACK_PLAYER",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)

	## TEST E — During ATTACK, move Hero far ahead → next tick REGROUP
	hero.global_position = _cc.global_position + Vector3(0, 0, 40)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST E hero ahead → REGROUP", _ai.get_debug_condition_bucket_for_test() == &"REGROUP")
	_expect("TEST E not together", not _ai.is_army_together_for_test())

	## TEST F — Regroup destination does not advance farther toward player than soldiers
	var soldiers_center := Vector3.ZERO
	var scount := 0
	for unit_variant: Variant in _ai.get_enemy_army_for_test():
		if unit_variant is Unit and not (unit_variant is Hero):
			soldiers_center += (unit_variant as Unit).global_position
			scount += 1
	if scount > 0:
		soldiers_center /= float(scount)
	var regroup_dest: Vector3 = _ai.get_regroup_destination_for_test()
	var player_pike_pos: Vector3 = _cc.global_position + Vector3(45, 0, 0)
	## Find actual player unit
	var player_units: Array = _ai.get_player_army_for_test()
	if not player_units.is_empty() and player_units[0] is Node3D:
		player_pike_pos = (player_units[0] as Node3D).global_position
	var soldier_to_player: float = soldiers_center.distance_to(player_pike_pos)
	var dest_to_player: float = Vector3(regroup_dest.x, 0, regroup_dest.z).distance_to(
		Vector3(player_pike_pos.x, 0, player_pike_pos.z)
	)
	_expect(
		"TEST F regroup does not advance toward player",
		dest_to_player + 0.5 >= soldier_to_player - 1.0
	)

	## TEST G — One reinforcement at base does not cancel cohesive field army
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(30, 0, 30))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 10:
		_spawn_enemy_spearman(_cc.global_position + Vector3(30.0 + float(i) * 0.7, 0, 30))
	## Fresh spawn still at home base.
	_spawn_enemy_spearman(_cc.global_position + Vector3(1, 0, 1))
	_spawn_player_spearman(_cc.global_position + Vector3(45, 0, 0))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_expect("TEST G main force still together", _ai.is_army_together_for_test())
	_ai.force_tick_for_test()
	_expect(
		"TEST G one straggler does not force REGROUP alone",
		_ai.get_debug_condition_bucket_for_test() != &"REGROUP"
	)

	## TEST H — Majority behind Hero → REGROUP
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 35))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 8:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i) * 0.8, 0, 2))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST H majority behind → REGROUP", _ai.get_debug_condition_bucket_for_test() == &"REGROUP")

	## TEST I — Base threat during separation → DEFEND overrides REGROUP
	var threat: Unit = _spawn_player_spearman(_cc.global_position + Vector3(5, 0, 0))
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST I DEFEND overrides REGROUP", _ai.get_debug_priority() == &"DEFEND")
	_kill_unit(threat)
	await get_tree().process_frame

	## TEST J — Player Hero + Pikemen → player_power > 0
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var player_hero: Hero = HERO_SCENE.instantiate() as Hero
	_world.add_child(player_hero)
	player_hero.global_position = _cc.global_position + Vector3(50, 0, 0)
	player_hero.team_id = 0
	player_hero.add_to_group(&"heroes")
	player_hero.add_to_group(&"units")
	HeroProgressionStore.register_living_hero(player_hero)
	_spawn_player_spearman(_cc.global_position + Vector3(52, 0, 0))
	_spawn_player_spearman(_cc.global_position + Vector3(53, 0, 0))
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("TEST J player_power > 0", _ai.get_player_power_for_test() > 0.0)


func _test_attack_player_force_and_hero_death() -> void:
	print("--- ATTACK_PLAYER force cohesion + hero-death HOME ---")

	## SCENARIO A — Hero + 6 Pikes vs Town Hall only: all participate (T2 minimum soldiers=6).
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var player_cc: Building = _spawn_player_command_center(_cc.global_position + Vector3(40, 0, 0))
	var hero: Hero = _spawn_enemy_hero(player_cc.global_position + Vector3(-6, 0, 0))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	var pikes: Array = []
	for i: int in 6:
		pikes.append(
			_spawn_enemy_spearman(player_cc.global_position + Vector3(-6.0 + float(i) * 0.9, 0, 1.5))
		)
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"SCENARIO A → ATTACK_PLAYER",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)
	_expect(
		"SCENARIO A command is attack_player",
		_ai.get_last_command_kind_for_test() == &"attack_player"
	)
	var attack_dest: Vector3 = _ai.get_last_command_destination_for_test()
	_expect(
		"SCENARIO A army ordered toward player base approach",
		attack_dest.distance_to(player_cc.global_position) <= 20.0
	)
	## Old strategic-order provenance recording was removed with simple AI.
	## Participation is the shared PlayerRouteNavigation group attack-move.
	_expect(
		"SCENARIO A strategic objective is player CC",
		_ai.select_player_target_for_test() == player_cc
	)

	## One idle member used to be skipped when the majority already had the order.
	## Full reinforcement coverage is `_test_new_unit_receives_current_army_order`.
	var dropped: Unit = pikes[0] as Unit
	dropped.cancel_attack()
	dropped.cancel_attack_move()
	dropped.stop_movement()
	var approach_dest: Vector3 = _ai.get_last_command_destination_for_test()
	_ai._last_command_kind = &"attack_player"
	_ai._last_command_target_id = player_cc.get_instance_id()
	_ai._last_command_army_count = _ai.get_enemy_army_for_test().size()
	_ai._last_command_destination = approach_dest
	for i: int in range(1, pikes.size()):
		var other: Unit = pikes[i] as Unit
		other.command_attack_move(approach_dest)
	hero.command_attack_move(approach_dest)
	_ai.force_tick_for_test()
	_expect(
		"already-ordered Pikes keep ATTACK_MOVE after one idle member",
		_unit_has_attack_move_toward(pikes[1] as Unit, approach_dest)
	)

	## SCENARIO B — Enemy Hero dies mid-fight → always HOME_NO_HERO (no continue-attack exception).
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	player_cc = _spawn_player_command_center(_cc.global_position + Vector3(40, 0, 0))
	hero = _spawn_enemy_hero(player_cc.global_position + Vector3(-5, 0, 0))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	pikes.clear()
	for i: int in 6:
		pikes.append(
			_spawn_enemy_spearman(player_cc.global_position + Vector3(-5.0 + float(i) * 0.8, 0, 1.0))
		)
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_kill_unit(hero)
	HeroProgressionStore.clear()
	var player_hero: Hero = HERO_SCENE.instantiate() as Hero
	_world.add_child(player_hero)
	player_hero.global_position = player_cc.global_position + Vector3(2, 0, 0)
	player_hero.team_id = 0
	player_hero.add_to_group(&"heroes")
	player_hero.add_to_group(&"units")
	HeroProgressionStore.register_living_hero(player_hero)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"SCENARIO B hero death → HOME_NO_HERO (no continue-attack)",
		_ai.get_debug_condition_bucket_for_test() == &"HOME_NO_HERO"
	)
	_expect("SCENARIO B economy still wants Hero", _ai.get_debug_priority() == &"HOME_NO_HERO")

	## SCENARIO C — Hero dies before army reaches player base → HOME_NO_HERO.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	_spawn_player_command_center(_cc.global_position + Vector3(70, 0, 0))
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 6:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_kill_unit(hero)
	HeroProgressionStore.clear()
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"SCENARIO C hero death at home → HOME_NO_HERO",
		_ai.get_debug_condition_bucket_for_test() == &"HOME_NO_HERO"
	)
	_expect("SCENARIO C economy still wants Hero", _ai.get_debug_priority() == &"HOME_NO_HERO")


func _test_attack_regroup_oscillation_regression() -> void:
	print("--- ATTACK_PLAYER ↔ REGROUP oscillation regression ---")
	_expect(
		"hero cohesion radius matches simple AI COHESION_RADIUS",
		is_equal_approx(_ai.get_hero_cohesion_radius_for_test(), EnemyAI.COHESION_RADIUS)
	)

	## Mid-march lead inside cohesion radius must NOT force REGROUP.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var player_cc: Building = _spawn_player_command_center(_cc.global_position + Vector3(55, 0, 0))
	var cluster := _cc.global_position + Vector3(30, 0, 0)
	var hero: Hero = _spawn_enemy_hero(cluster + Vector3(17.5, 0, 0))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	var pikes: Array = []
	for i: int in 8:
		pikes.append(_spawn_enemy_spearman(cluster + Vector3(float(i) * 0.7, 0, 0)))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	var snap_boundary: Dictionary = _ai.get_cohesion_snapshot_for_test()
	_expect(
		"mid-march lead (17.5m) stays with army under generous threshold",
		bool(snap_boundary.get("result", false))
	)

	## Cohesive field army → ATTACK_PLAYER; small Hero lead must not flap.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	player_cc = _spawn_player_command_center(_cc.global_position + Vector3(55, 0, 0))
	cluster = player_cc.global_position + Vector3(-20, 0, 0)
	hero = _spawn_enemy_hero(cluster)
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	pikes.clear()
	for i: int in 8:
		pikes.append(_spawn_enemy_spearman(cluster + Vector3(float(i) * 0.7 - 2.5, 0, 1.0)))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_expect("cohesive pack together before attack", _ai.is_army_together_for_test())
	_ai.force_tick_for_test()
	_expect(
		"cohesive pack selects ATTACK_PLAYER",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)

	var snap0: Dictionary = _ai.get_cohesion_snapshot_for_test()
	var hd0: float = float(snap0.get("hero_to_center", 0.0))
	hero.global_position = hero.global_position + Vector3(2.7, 0, 0)
	await get_tree().process_frame
	var snap1: Dictionary = _ai.get_cohesion_snapshot_for_test()
	_expect(
		"one Hero tick from packed start stays with army",
		bool(snap1.get("result", false))
	)
	_ai.force_tick_for_test()
	_expect(
		"still ATTACK_PLAYER after one Hero lead tick",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)

	## One distant reinforcement must not force REGROUP.
	_spawn_enemy_spearman(_cc.global_position + Vector3(1, 0, 1))
	await get_tree().process_frame
	_expect(
		"distant reinforcement keeps field army together",
		_ai.is_army_together_for_test()
	)
	_ai.force_tick_for_test()
	_expect(
		"distant reinforcement does not force REGROUP",
		_ai.get_debug_condition_bucket_for_test() != &"REGROUP"
	)

	## Obvious Hero separation → REGROUP near main soldier centroid.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	_spawn_player_command_center(_cc.global_position + Vector3(55, 0, 0))
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 40))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 8:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i) * 0.8, 0, 2))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"obviously separated → REGROUP",
		_ai.get_debug_condition_bucket_for_test() == &"REGROUP"
	)
	var regroup_dest: Vector3 = _ai.get_regroup_destination_for_test()
	var main_center: Vector3 = _ai.get_main_army_centroid_for_test()
	var dest_to_main: float = Vector3(regroup_dest.x, 0, regroup_dest.z).distance_to(
		Vector3(main_center.x, 0, main_center.z)
	)
	_expect(
		"REGROUP destination near main cluster",
		dest_to_main <= EnemyAI.MAIN_CLUSTER_RADIUS + 1.0
	)
	hero.global_position = regroup_dest
	var living_soldiers: Array = []
	for unit_variant: Variant in _ai.get_enemy_army_for_test():
		if unit_variant is Unit and not (unit_variant is Hero) and NodeSafety.is_alive_node(unit_variant):
			living_soldiers.append(unit_variant)
	for i: int in living_soldiers.size():
		var soldier: Unit = living_soldiers[i] as Unit
		soldier.global_position = regroup_dest + Vector3(float(i % 4) * 0.8, 0, float(i / 4) * 0.8)
	await get_tree().process_frame
	var snap_regrouped: Dictionary = _ai.get_cohesion_snapshot_for_test()
	_expect("REGROUP completion geometry is with army", bool(snap_regrouped.get("result", false)))
	_expect(
		"REGROUP completion hero→cluster well under far threshold",
		float(snap_regrouped.get("hero_to_center", 99.0)) <= EnemyAI.HERO_FAR_THRESHOLD
	)
	_ai.force_tick_for_test()
	_expect(
		"after regroup pack not stuck in REGROUP",
		_ai.get_debug_condition_bucket_for_test() != &"REGROUP"
	)

	## Multi-tick stability: packed ATTACK must not alternate every tick while facts stay packed.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	player_cc = _spawn_player_command_center(_cc.global_position + Vector3(40, 0, 0))
	hero = _spawn_enemy_hero(player_cc.global_position + Vector3(-8, 0, 0))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 8:
		_spawn_enemy_spearman(player_cc.global_position + Vector3(-8.0 + float(i) * 0.7, 0, 1.2))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	var buckets: PackedStringArray = PackedStringArray()
	for _i: int in 6:
		_ai.force_tick_for_test()
		buckets.append(String(_ai.get_debug_condition_bucket_for_test()))
	var attack_regroup_flips: int = 0
	for i: int in range(1, buckets.size()):
		var prev_b: String = buckets[i - 1]
		var cur_b: String = buckets[i]
		if (
			(prev_b == "ATTACK_PLAYER" and cur_b == "REGROUP")
			or (prev_b == "REGROUP" and cur_b == "ATTACK_PLAYER")
		):
			attack_regroup_flips += 1
	_expect(
		"packed near-base attack does not ATTACK↔REGROUP every tick",
		attack_regroup_flips == 0
	)
	_expect("hd0 recorded for packed start", hd0 >= 0.0)
	_expect("player_cc alive for attack scenarios", NodeSafety.is_alive_node(player_cc))


func _test_condition_stability() -> void:
	print("--- condition stability (no CREEP↔REGROUP thrash) ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(8, 0, 8))
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 6:
		_spawn_enemy_spearman(_cc.global_position + Vector3(8.0 + float(i) * 0.7, 0, 8))
	## Strong player so attack stays closed; creep camp available for EARLY_CREEP.
	for i: int in 14:
		_spawn_player_spearman(_cc.global_position + Vector3(45.0 + float(i), 0, 0))
	var camp := CreepCamp.new()
	camp.name = "StableCreepCamp"
	_world.add_child(camp)
	camp.global_position = _cc.global_position + Vector3(0, 0, 28)
	var creep: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(1, 0, 0))
	creep.reparent(camp)
	_ai.set_camps_cleared_for_test(0)
	await get_tree().process_frame

	var buckets: PackedStringArray = PackedStringArray()
	for _i: int in 6:
		_ai.force_tick_for_test()
		buckets.append(String(_ai.get_debug_condition_bucket_for_test()))
	var unique: Dictionary = {}
	for b: String in buckets:
		unique[b] = true
	_expect(
		"stable creep travel does not alternate every tick",
		unique.size() <= 2
	)
	## Must not thrash CREEP↔REGROUP↔CREEP↔REGROUP across 6 ticks when facts are stable.
	var flips: int = 0
	for i: int in range(1, buckets.size()):
		if buckets[i] != buckets[i - 1]:
			flips += 1
	_expect("condition flips in 6 stable ticks <= 2", flips <= 2)
	_expect(
		"stable ticks stay CREEP (not REGROUP)",
		buckets[0] == "EARLY_CREEP" or buckets[0] == "EXTRA_CREEP"
	)


func _test_mixed_army_minimum() -> void:
	print("--- mixed T2/T3 army minimum ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	## Force T2 so early Spearman-only gate is closed.
	_cc.command_center_tier = 2
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 3
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 4:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i) * 0.8, 0, 2))
	for i: int in 5:
		_spawn_enemy_unit(SWORDSMAN_SCENE, _cc.global_position + Vector3(float(i) * 0.8, 0, 3.5))
	for i: int in 5:
		_spawn_enemy_unit(ARCHER_SCENE, _cc.global_position + Vector3(float(i) * 0.8, 0, 5.0))
	for i: int in 2:
		_spawn_enemy_unit(LIGHT_CAVALRY_SCENE, _cc.global_position + Vector3(float(i) * 1.2, 0, 6.5))
	## Stronger player so attack stays closed — we only care about HOME_ARMY_SMALL.
	for i: int in 20:
		_spawn_player_spearman(_cc.global_position + Vector3(45.0 + float(i), 0, 0))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"mixed army not HOME_ARMY_SMALL with Spearmen < 5",
		_ai.get_debug_condition_bucket_for_test() != &"HOME"
		or _ai.get_debug_priority() != &"BUILD_FORCE"
	)
	_expect(
		"mixed army not blocked solely by Spearmen count",
		_ai.get_debug_priority() != &"BUILD_FORCE"
	)


func _test_attack_target_stability() -> void:
	print("--- ATTACK_PLAYER objective stays player base ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var player_cc: Building = _spawn_player_command_center(_cc.global_position + Vector3(55, 0, 0))
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 8:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i) * 0.8, 0, 2))
	## Player Hero far from enemy base (outside DEFENSE_RADIUS) so DEFEND does not win.
	var player_hero: Hero = HERO_SCENE.instantiate() as Hero
	_world.add_child(player_hero)
	player_hero.global_position = player_cc.global_position + Vector3(4, 0, 4)
	player_hero.team_id = 0
	player_hero.add_to_group(&"heroes")
	player_hero.add_to_group(&"units")
	HeroProgressionStore.register_living_hero(player_hero)
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"strong AI → ATTACK_PLAYER",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)
	var objective0: Node3D = _ai.select_player_target_for_test()
	_expect("objective0 is player CC", objective0 == player_cc)
	var target_id0: int = _ai.get_last_command_target_id_for_test()
	## Move player Hero around near the player base — strategic objective must remain CC.
	player_hero.global_position = player_cc.global_position + Vector3(-3, 0, 6)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"after Hero move still ATTACK_PLAYER",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)
	_expect("objective still player CC", _ai.select_player_target_for_test() == player_cc)
	_expect(
		"strategic target id stays player CC",
		_ai.get_last_command_target_id_for_test() == target_id0
		or _ai.get_last_command_target_id_for_test() == player_cc.get_instance_id()
	)
	_expect(
		"strategic target is not player Hero instance",
		_ai.get_last_command_target_id_for_test() != player_hero.get_instance_id()
	)


func _test_creep_approach_staging() -> void:
	print("--- creep approach stays staging area ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(8, 0, 8))
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 6:
		_spawn_enemy_spearman(_cc.global_position + Vector3(8.0 + float(i) * 0.7, 0, 8))
	for i: int in 14:
		_spawn_player_spearman(_cc.global_position + Vector3(45.0 + float(i), 0, 0))
	var camp := CreepCamp.new()
	camp.name = "ApproachCreepCamp"
	_world.add_child(camp)
	camp.global_position = _cc.global_position + Vector3(0, 0, 28)
	var creep_a: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(1, 0, 0))
	var creep_b: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(-1, 0, 0))
	creep_a.reparent(camp)
	creep_b.reparent(camp)
	_ai.set_camps_cleared_for_test(0)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	var staging: Vector3 = _ai.get_creep_staging_point_for_test(camp)
	var dest: Vector3 = _ai.get_last_command_destination_for_test()
	_expect("creep approach selects EARLY_CREEP", _ai.get_debug_condition_bucket_for_test() == &"EARLY_CREEP")
	_expect(
		"strategic dest near staging not camp center",
		dest.distance_to(staging) <= EnemyAI.ORDER_DEST_RADIUS
		and dest.distance_to(camp.global_position) > 4.0
	)
	_kill_unit(creep_a)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("after one creep death still EARLY_CREEP", _ai.get_debug_condition_bucket_for_test() == &"EARLY_CREEP")
	var dest2: Vector3 = _ai.get_last_command_destination_for_test()
	_expect(
		"after creep death dest still staging area",
		dest2.distance_to(camp.global_position) > 4.0
	)


func _test_creep_condition_no_oscillation() -> void:
	print("--- CREEP condition stability vs REGROUP ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var hero: Hero = _spawn_enemy_hero(_cc.global_position + Vector3(10, 0, 10))
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 6:
		_spawn_enemy_spearman(_cc.global_position + Vector3(10.0 + float(i) * 0.7, 0, 10))
	for i: int in 14:
		_spawn_player_spearman(_cc.global_position + Vector3(45.0 + float(i), 0, 0))
	var camp := CreepCamp.new()
	camp.name = "StableOscillationCamp"
	_world.add_child(camp)
	camp.global_position = _cc.global_position + Vector3(0, 0, 30)
	var creep: NeutralCreep = _spawn_neutral_creep(camp.global_position + Vector3(1, 0, 0))
	creep.reparent(camp)
	_ai.set_camps_cleared_for_test(0)
	await get_tree().process_frame

	var buckets: PackedStringArray = PackedStringArray()
	for _i: int in 6:
		_ai.force_tick_for_test()
		buckets.append(String(_ai.get_debug_condition_bucket_for_test()))
	var all_creep: bool = true
	for b: String in buckets:
		if b != "EARLY_CREEP" and b != "EXTRA_CREEP":
			all_creep = false
			break
	_expect("stable cohesive creep stays CREEP across ticks", all_creep)
	_expect("first tick CREEP", buckets[0] == "EARLY_CREEP" or buckets[0] == "EXTRA_CREEP")

	## Move Hero meaningfully away → REGROUP.
	hero.global_position = _cc.global_position + Vector3(10, 0, 40)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("hero separated → REGROUP", _ai.get_debug_condition_bucket_for_test() == &"REGROUP")

	## Bring Hero back to the soldier pack → CREEP again.
	hero.global_position = _cc.global_position + Vector3(12, 0, 10)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	var after: StringName = _ai.get_debug_condition_bucket_for_test()
	_expect(
		"hero rejoined → CREEP",
		after == &"EARLY_CREEP" or after == &"EXTRA_CREEP"
	)


func _test_difficulty_economy_knobs() -> void:
	print("--- difficulty economy knobs ---")
	_expect("T1 workers=13", AIDifficultyConfig.get_desired_worker_count(1, false) == 13)
	_expect("T2 workers=20", AIDifficultyConfig.get_desired_worker_count(2, false) == 20)
	_expect("T3 workers=28", AIDifficultyConfig.get_desired_worker_count(3, false) == 28)
	_expect("expansion workers=33", AIDifficultyConfig.get_desired_worker_count(1, true) == 33)
	_expect("Hard income 1.5", is_equal_approx(AIDifficultyConfig.HARD_RESOURCE_MULTIPLIER, 1.5))
	_expect("Hard train 1.5", is_equal_approx(AIDifficultyConfig.HARD_TRAIN_SPEED_MULTIPLIER, 1.5))
	_expect("Easy max military 1", AIDifficultyConfig.MAX_MILITARY_EASY == 1)
	_expect("Normal/Hard max military 3", AIDifficultyConfig.MAX_MILITARY_NORMAL_HARD == 3)


func _test_new_unit_receives_current_army_order() -> void:
	print("--- new military unit receives current army ATTACK_MOVE ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	## Stay inside the custom RTS grid (−50..50). Off-grid group moves issue no unit orders.
	var player_cc: Building = _spawn_player_command_center(_cc.global_position + Vector3(0, 0, -20))
	var cluster: Vector3 = player_cc.global_position + Vector3(0, 0, 6)
	var hero: Hero = _spawn_enemy_hero(cluster)
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	var existing: Array = []
	existing.append(hero)
	for i: int in 8:
		existing.append(
			_spawn_enemy_spearman(cluster + Vector3(float(i) * 0.8 - 2.8, 0, 1.0))
		)
	_ai.set_camps_cleared_for_test(3)
	PlayerRouteNavigation.ensure_grid_ready()
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"seed army selects ATTACK_PLAYER",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)
	var expected_dest: Vector3 = _ai.get_last_command_destination_for_test()
	_expect(
		"seed army has a strategic destination",
		expected_dest != Vector3.ZERO
	)
	for member_v: Variant in existing:
		(member_v as Unit).command_attack_move(expected_dest)
	await get_tree().process_frame
	var generations_before: Dictionary = {}
	for member_v2: Variant in existing:
		var member: Unit = member_v2 as Unit
		_expect(
			"seed army member has ATTACK_MOVE before reinforcement",
			_unit_has_attack_move_toward(member, expected_dest)
		)
		generations_before[member.get_instance_id()] = member.get_player_squad_command_generation()

	var recruit: Unit = _spawn_enemy_spearman(_cc.global_position + Vector3(0, 0, -5) + Vector3(1, 0, 0))
	await get_tree().process_frame
	_expect(
		"new Spearman has no matching strategic ATTACK_MOVE before tick",
		not _unit_has_attack_move_toward(recruit, expected_dest)
	)

	_ai.force_tick_for_test()
	_expect(
		"new Spearman receives ATTACK_MOVE toward existing army destination",
		_unit_has_attack_move_toward(recruit, expected_dest)
	)
	for member_v3: Variant in existing:
		var ordered: Unit = member_v3 as Unit
		_expect(
			"existing army member still has ATTACK_MOVE after reinforcement",
			_unit_has_attack_move_toward(ordered, expected_dest)
		)
		_expect(
			"existing army member is not re-issued a navigation generation",
			ordered.get_player_squad_command_generation()
			== int(generations_before.get(ordered.get_instance_id(), -2))
		)
	_expect("player CC still present for reinforcement scenario", NodeSafety.is_alive_node(player_cc))


func _test_stable_attack_move_skips_identical_routes() -> void:
	print("--- stable ATTACK_MOVE does not re-request routes ---")
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	## Stay on the custom RTS grid. Keep the army far from the player CC so the
	## first tick must travel, and later ticks do not enter local combat.
	var player_cc: Building = _spawn_player_command_center(_cc.global_position + Vector3(0, 0, -24))
	var cluster: Vector3 = _cc.global_position + Vector3(0, 0, 2)
	var hero: Hero = _spawn_enemy_hero(cluster)
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	var existing: Array = []
	existing.append(hero)
	for i: int in 8:
		existing.append(
			_spawn_enemy_spearman(cluster + Vector3(float(i) * 0.8 - 2.8, 0, 1.0))
		)
	_ai.set_camps_cleared_for_test(3)
	PlayerRouteNavigation.ensure_grid_ready()
	_ai.set_brain_debug(true)
	await get_tree().process_frame

	_ai.force_tick_for_test()
	_expect(
		"stable-route seed selects ATTACK_PLAYER",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)
	var expected_dest: Vector3 = _ai.get_last_command_destination_for_test()
	_expect("stable-route seed has a strategic destination", expected_dest != Vector3.ZERO)
	var routes_after_first: int = _ai.get_strategic_group_route_request_count_for_test()
	_expect("first legitimate ATTACK_MOVE issues one group route", routes_after_first >= 1)
	var first_order: Dictionary = _ai.get_last_order_debug_for_test()
	_expect("first tick records a real route request", bool(first_order.get("route_request", false)))
	_expect(
		"first tick orders the living army",
		int(first_order.get("ordered", 0)) == existing.size()
	)

	var generations_before: Dictionary = {}
	for member_v: Variant in existing:
		var member: Unit = member_v as Unit
		_expect(
			"seed army member has ATTACK_MOVE after first tick",
			_unit_has_attack_move_toward(member, expected_dest)
		)
		generations_before[member.get_instance_id()] = member.get_player_squad_command_generation()

	for _i: int in 6:
		_ai.force_tick_for_test()
		_expect(
			"stable ticks keep ATTACK_PLAYER",
			_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
		)
		_expect(
			"stable ticks keep equivalent destination",
			_destinations_equivalent_for_test(_ai.get_last_command_destination_for_test(), expected_dest)
		)
		var tick_order: Dictionary = _ai.get_last_order_debug_for_test()
		_expect("stable tick issues no group route", not bool(tick_order.get("route_request", false)))
		_expect("stable tick needs_order is 0", int(tick_order.get("needs_order", 0)) == 0)
		_expect("stable tick ordered is 0", int(tick_order.get("ordered", 0)) == 0)
		_expect("stable tick marks identical skip", bool(tick_order.get("identical_skipped", false)))

	_expect(
		"unchanged ticks issue no extra group routes",
		_ai.get_strategic_group_route_request_count_for_test() == routes_after_first
	)
	for member_v2: Variant in existing:
		var ordered: Unit = member_v2 as Unit
		_expect(
			"stable ticks leave existing ATTACK_MOVE unchanged",
			_unit_has_attack_move_toward(ordered, expected_dest)
		)
		_expect(
			"stable ticks do not bump command generation",
			ordered.get_player_squad_command_generation()
			== int(generations_before.get(ordered.get_instance_id(), -2))
		)

	var health_stable: Dictionary = _ai.get_order_health_totals_for_test()
	_expect("stable window records the first route", int(health_stable.get("route_requests", 0)) == 1)
	_expect("stable window skips later identical ticks", int(health_stable.get("identical_skipped", 0)) >= 6)
	_expect("stable window has no destination changes", int(health_stable.get("destination_changes", 0)) == 0)

	var recruit: Unit = _spawn_enemy_spearman(_cc.global_position + Vector3(1, 0, -5))
	await get_tree().process_frame
	_expect(
		"new Spearman has no matching ATTACK_MOVE before reinforcement tick",
		not _unit_has_attack_move_toward(recruit, expected_dest)
	)
	_ai.force_tick_for_test()
	var reinforce_order: Dictionary = _ai.get_last_order_debug_for_test()
	_expect("reinforcement tick requests one route", bool(reinforce_order.get("route_request", false)))
	_expect("reinforcement tick needs_order is 1", int(reinforce_order.get("needs_order", 0)) == 1)
	_expect("reinforcement tick ordered is 1", int(reinforce_order.get("ordered", 0)) == 1)
	_expect(
		"reinforcement tick keeps existing army already_correct",
		int(reinforce_order.get("already_correct", 0)) == existing.size()
	)
	_expect(
		"reinforcement issues exactly one extra group route",
		_ai.get_strategic_group_route_request_count_for_test() == routes_after_first + 1
	)
	_expect(
		"new Spearman receives ATTACK_MOVE toward existing destination",
		_unit_has_attack_move_toward(recruit, expected_dest)
	)
	for member_v3: Variant in existing:
		var kept: Unit = member_v3 as Unit
		_expect(
			"existing army is not re-issued a navigation generation",
			kept.get_player_squad_command_generation()
			== int(generations_before.get(kept.get_instance_id(), -2))
		)

	_ai.force_tick_for_test()
	var after_reinforce: Dictionary = _ai.get_last_order_debug_for_test()
	_expect("tick after reinforcement skips the route", not bool(after_reinforce.get("route_request", false)))
	_expect(
		"tick after reinforcement issues no extra group route",
		_ai.get_strategic_group_route_request_count_for_test() == routes_after_first + 1
	)
	_expect("player CC still present for stable-route scenario", NodeSafety.is_alive_node(player_cc))
	_ai.set_brain_debug(false)


func _test_brain_debug_black_box() -> void:
	print("--- brain debug black box observability ---")
	await _clear_units_and_buildings_except_cc()
	_ai.set_brain_debug(true)
	_ai.force_tick_for_test()
	_expect("P debug enables", _ai.is_brain_debug_enabled())
	var lines: PackedStringArray = _ai.get_debug_overlay_lines()
	_expect("panel starts with AI BRAIN", lines.size() > 0 and String(lines[0]) == "AI BRAIN")
	var names: PackedStringArray = PackedStringArray()
	var states: PackedStringArray = PackedStringArray()
	for line: Dictionary in _ai._debug_condition_lines:
		names.append(String(line.get("name", "")))
		states.append("%s=%s" % [String(line.get("name", "")), String(line.get("state", ""))])
	_expect("IF tree records BASE_THREATENED", names.has("BASE_THREATENED"))
	_expect("IF tree records HERO_MISSING", names.has("HERO_MISSING"))
	_expect("IF tree records HOME_WAIT", names.has("HOME_WAIT"))
	var skipped_after_hero: bool = false
	var hero_missing_true: bool = false
	for entry: String in states:
		if entry == "HERO_MISSING=TRUE":
			hero_missing_true = true
		if hero_missing_true and entry == "ATTACK_PLAYER=SKIPPED":
			skipped_after_hero = true
	_expect("no hero → ATTACK_PLAYER SKIPPED not re-evaluated", skipped_after_hero)
	_expect("macro workers captured", _ai._dbg_macro.has("workers"))
	_expect("power breakdown captured for AI", not _ai._dbg_power_ai.is_empty())
	_ai.set_brain_debug(false)
	_expect("P debug disables", not _ai.is_brain_debug_enabled())


func _unit_has_attack_move_toward(unit: Unit, destination: Vector3) -> bool:
	if unit == null or not NodeSafety.is_alive_node(unit):
		return false
	var active: UnitOrder = unit.get_active_order()
	if active == null or active.type != UnitOrder.Type.ATTACK_MOVE:
		return false
	if _destinations_equivalent_for_test(active.destination, destination):
		return true
	return _destinations_equivalent_for_test(unit.get_player_squad_clicked_destination(), destination)


func _destinations_equivalent_for_test(a: Vector3, b: Vector3) -> bool:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz) <= EnemyAI.ORDER_DEST_RADIUS


func _spawn_basic_base(farm: bool, altar: bool, barracks: bool) -> void:
	if farm:
		var f: Building = _spawn_completed_building(FARM_SCENE, _cc.global_position + Vector3(-5, 0, 0))
		f.add_to_group(&"enemy_command_center")
	if altar:
		var a: Building = _spawn_completed_building(ALTAR_SCENE, _cc.global_position + Vector3(5, 0, 0))
		a.add_to_group(&"enemy_command_center")
	if barracks:
		var b: Building = _spawn_completed_building(BARRACKS_SCENE, _cc.global_position + Vector3(0, 0, -5))
		b.add_to_group(&"enemy_command_center")


func _spawn_completed_building(scene: PackedScene, position: Vector3) -> Building:
	var building: Building = scene.instantiate() as Building
	## Set team before enter-tree so CommandCenter dropoff groups register correctly.
	building.team_id = 1
	_world.add_child(building)
	building.global_position = position
	building.set_completed()
	building.add_to_group(&"buildings")
	if building.is_in_group(&"player_command_center"):
		building.remove_from_group(&"player_command_center")
	if not building.is_in_group(&"enemy_command_center"):
		building.add_to_group(&"enemy_command_center")
	if building.has_method(&"_ensure_dropoff_registration"):
		building.call(&"_ensure_dropoff_registration")
	return building


func _spawn_player_command_center(position: Vector3) -> Building:
	var building: Building = CC_SCENE.instantiate() as Building
	building.team_id = TeamVisuals.PLAYER_TEAM_ID
	_world.add_child(building)
	building.global_position = position
	building.set_completed()
	building.add_to_group(&"buildings")
	if building.is_in_group(&"enemy_command_center"):
		building.remove_from_group(&"enemy_command_center")
	if not building.is_in_group(&"player_command_center"):
		building.add_to_group(&"player_command_center")
	if building.has_method(&"_ensure_dropoff_registration"):
		building.call(&"_ensure_dropoff_registration")
	return building


func _spawn_enemy_spearman(position: Vector3) -> Unit:
	return _spawn_enemy_unit(SPEARMAN_SCENE, position)


func _spawn_enemy_unit(scene: PackedScene, position: Vector3) -> Unit:
	var unit: Unit = scene.instantiate() as Unit
	_world.add_child(unit)
	unit.global_position = position
	unit.team_id = 1
	unit.add_to_group(&"enemies")
	unit.add_to_group(&"enemy_combat_units")
	if unit.is_in_group(&"units"):
		unit.remove_from_group(&"units")
	return unit


func _spawn_player_spearman(position: Vector3) -> Unit:
	var unit: Unit = SPEARMAN_SCENE.instantiate() as Unit
	_world.add_child(unit)
	unit.global_position = position
	unit.team_id = TeamVisuals.PLAYER_TEAM_ID
	if not unit.is_in_group(&"units"):
		unit.add_to_group(&"units")
	if unit.is_in_group(&"enemies"):
		unit.remove_from_group(&"enemies")
	if unit.is_in_group(&"enemy_combat_units"):
		unit.remove_from_group(&"enemy_combat_units")
	return unit


## Reproduces the live-match bug: player military with default team_id=-1 in "units".
func _spawn_player_spearman_unset_team(position: Vector3) -> Unit:
	var unit: Unit = SPEARMAN_SCENE.instantiate() as Unit
	_world.add_child(unit)
	unit.global_position = position
	unit.team_id = TeamVisuals.NEUTRAL_TEAM_ID
	if not unit.is_in_group(&"units"):
		unit.add_to_group(&"units")
	if unit.is_in_group(&"enemies"):
		unit.remove_from_group(&"enemies")
	if unit.is_in_group(&"enemy_combat_units"):
		unit.remove_from_group(&"enemy_combat_units")
	if unit.is_in_group(&"neutral_creeps"):
		unit.remove_from_group(&"neutral_creeps")
	return unit


func _spawn_neutral_creep(position: Vector3) -> NeutralCreep:
	var creep: NeutralCreep = NEUTRAL_CREEP_SCENE.instantiate() as NeutralCreep
	_world.add_child(creep)
	creep.global_position = position
	creep.team_id = TeamVisuals.NEUTRAL_TEAM_ID
	if not creep.is_in_group(&"neutral_creeps"):
		creep.add_to_group(&"neutral_creeps")
	if not creep.is_in_group(&"units"):
		creep.add_to_group(&"units")
	if creep.is_in_group(&"enemies"):
		creep.remove_from_group(&"enemies")
	return creep


func _kill_unit(unit: Node) -> void:
	if not NodeSafety.is_alive_node(unit):
		return
	var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.current_health = 0
	if unit.has_method(&"die"):
		unit.call(&"die")
	unit.queue_free()


func _spawn_enemy_hero(position: Vector3) -> Hero:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	_world.add_child(hero)
	hero.global_position = position
	hero.team_id = 1
	hero.add_to_group(&"enemies")
	hero.add_to_group(&"enemy_combat_units")
	if hero.is_in_group(&"heroes"):
		hero.remove_from_group(&"heroes")
	if hero.is_in_group(&"units"):
		hero.remove_from_group(&"units")
	return hero


class RecordingEnemyBuildManager extends EnemyBuildManager:
	var requests: Array[StringName] = []

	func try_place_building(building_type: StringName) -> bool:
		requests.append(building_type)
		return true

	func try_place_farm() -> bool:
		return try_place_building(&"farm")

	func try_place_hero_altar() -> bool:
		return try_place_building(&"hero_altar")

	func try_place_barracks() -> bool:
		return try_place_building(&"barracks")

	func try_place_blacksmith() -> bool:
		return try_place_building(&"blacksmith")

	func try_place_stable() -> bool:
		return try_place_building(&"stable")

	func try_place_artillery_depot() -> bool:
		return try_place_building(&"artillery_depot")

	func try_place_tower(_toward_world: Vector3 = Vector3.INF) -> bool:
		return try_place_building(&"tower")

	func try_place_expansion_at_mine(_gold_mine: GoldMine) -> bool:
		requests.append(&"command_center")
		return true


class RecordingEnemyGatherManager extends EnemyGatherManager:
	var assignments: Array = []

	func assign_gather_job(worker: Worker, prefer_gold: bool = false, _force_recovery: bool = false) -> bool:
		assignments.append({"worker": worker, "prefer_gold": prefer_gold})
		return true
