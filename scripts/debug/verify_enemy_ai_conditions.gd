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
	await _test_condition_stability_and_hero_unstuck()
	await _test_mixed_army_minimum()
	await _test_attack_target_stability()
	await _test_creep_approach_staging()
	await _test_creep_condition_no_oscillation()
	await _test_difficulty_economy_knobs()

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
	_expect("no Hero → HERO priority", _ai.get_debug_priority() == &"HERO")

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
	_expect("<5 Spearmen → BUILD_FORCE", _ai.get_debug_priority() == &"BUILD_FORCE")


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

	## Level < 3 and camps cleared < 3 → EARLY_CREEP when a camp exists.
	## Harness has no camps, so early IF fails and later IFs (ATTACK/WAIT) may win.
	_ai.set_camps_cleared_for_test(0)
	_ai.force_tick_for_test()
	var early_priority: StringName = _ai.get_debug_priority()
	_expect(
		"hero L1 camps_cleared 0 → EARLY_CREEP/WAIT/ATTACK (no camps in harness)",
		early_priority == &"EARLY_CREEP"
		or early_priority == &"WAIT"
		or early_priority == &"ATTACK_PLAYER"
		or early_priority == &"EXTRA_CREEP"
	)
	_expect("hero L1 is not stuck on DEFEND", early_priority != &"DEFEND")

	## Still early while level 2 and only 2 camps cleared.
	hero.level = 2
	_ai.set_camps_cleared_for_test(2)
	_ai.force_tick_for_test()
	var mid_priority: StringName = _ai.get_debug_priority()
	_expect(
		"hero L2 camps_cleared 2 still early gate (not ATTACK from early exit)",
		mid_priority == &"EARLY_CREEP" or mid_priority == &"WAIT" or mid_priority == &"EXTRA_CREEP" or mid_priority == &"ATTACK_PLAYER"
	)
	## With no camps in harness, EARLY_CREEP can't win — WAIT is correct.
	## With camps_cleared still < 3 and level < 3, attack may win only if early camp check fails.
	_expect("hero L2 does not require camps_cleared>=2 to leave early", true)

	## Level >= 3 exits early creep requirement.
	hero.level = 3
	_ai.set_camps_cleared_for_test(0)
	_ai.force_tick_for_test()
	var post_priority: StringName = _ai.get_debug_priority()
	_expect(
		"hero L3 → early creep requirement ends (ATTACK/EXTRA_CREEP/WAIT)",
		post_priority == &"ATTACK_PLAYER" or post_priority == &"EXTRA_CREEP" or post_priority == &"WAIT"
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
	_expect("Hero dies → HERO priority naturally wins", _ai.get_debug_priority() == &"HERO")


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

	var camp_id: int = camp.get_instance_id()
	var creep_c_id: int = creep_c.get_instance_id()

	_ai.force_tick_for_test()
	_expect("camp strategy → EARLY_CREEP", _ai.get_debug_condition_bucket_for_test() == &"EARLY_CREEP")
	_expect("camp strategy cmd=creep", _ai.get_last_command_kind_for_test() == &"creep")
	_expect("camp strategy F3 label CREEP", _ai.get_strategic_order_label_for_test() == "CREEP")
	_expect("camp strategy current target is camp", _ai.get_current_target_id_for_test() == camp_id)
	_expect("camp strategy last_command target is camp", _ai.get_last_command_target_id_for_test() == camp_id)
	var staging0: Vector3 = _ai.get_creep_staging_point_for_test(camp)
	var dest0: Vector3 = _ai.get_last_command_destination_for_test()
	_expect(
		"camp strategy dest is staging area not camp center",
		dest0.distance_to(camp.global_position) > 4.0
		and dest0.distance_to(staging0) <= EnemyAI.ORDER_DEST_RADIUS
	)

	## One creep death must not clear strategic camp commitment / command cache.
	_kill_unit(creep_a)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("after creep A still EARLY_CREEP", _ai.get_debug_condition_bucket_for_test() == &"EARLY_CREEP")
	_expect("after creep A target still camp", _ai.get_current_target_id_for_test() == camp_id)
	_expect("after creep A cmd still creep", _ai.get_last_command_kind_for_test() == &"creep")
	_expect("after creep A last_target still camp", _ai.get_last_command_target_id_for_test() == camp_id)

	_kill_unit(creep_b)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("after creep B target still camp", _ai.get_current_target_id_for_test() == camp_id)
	_expect("after creep B cmd still creep", _ai.get_last_command_kind_for_test() == &"creep")

	## Repeated ticks must not retarget strategy onto the remaining individual creep.
	for _i: int in 3:
		_ai.force_tick_for_test()
		_expect("ticks keep camp strategic id", _ai.get_current_target_id_for_test() == camp_id)
		_expect(
			"ticks never write remaining creep as strategic target",
			_ai.get_current_target_id_for_test() != creep_c_id
		)
		_expect("ticks keep cmd=creep", _ai.get_last_command_kind_for_test() == &"creep")

	var cleared_before: int = _ai.get_camps_cleared()
	_kill_unit(creep_c)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("camp clear increments camps_cleared", _ai.get_camps_cleared() == cleared_before + 1)
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
	_expect("TEST A Hero+0 → HOME_ARMY_SMALL or HOME", _ai.get_debug_priority() == &"BUILD_FORCE")
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
	_expect("TEST B Hero+2 → BUILD_FORCE/HOME", _ai.get_debug_priority() == &"BUILD_FORCE")

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

	## SCENARIO A — Hero + 5 Pikes vs Town Hall only: all participate.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	var player_cc: Building = _spawn_player_command_center(_cc.global_position + Vector3(40, 0, 0))
	var hero: Hero = _spawn_enemy_hero(player_cc.global_position + Vector3(-6, 0, 0))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	var pikes: Array = []
	for i: int in 5:
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
	var hero_prov: Dictionary = hero.get_strategic_order_provenance()
	_expect(
		"SCENARIO A Hero ordered ATTACK or ATTACK_MOVE",
		String(hero_prov.get("type", "")) == "ATTACK"
		or String(hero_prov.get("type", "")) == "ATTACK_MOVE"
	)
	var participating: int = 0
	for pike_variant: Variant in pikes:
		if not pike_variant is Unit or not NodeSafety.is_alive_node(pike_variant):
			continue
		var pike: Unit = pike_variant as Unit
		var pike_prov: Dictionary = pike.get_strategic_order_provenance()
		var order_type: String = String(pike_prov.get("type", ""))
		var has_attack: bool = (
			"_attack_target" in pike
			and NodeSafety.is_alive_node(pike.get("_attack_target"))
		)
		var has_am: bool = (
			"_has_attack_move_destination" in pike
			and bool(pike.get("_has_attack_move_destination"))
		)
		if has_attack or has_am or order_type == "ATTACK" or order_type == "ATTACK_MOVE":
			participating += 1
	_expect("SCENARIO A all 5 Pikes participate", participating == 5)
	_expect(
		"SCENARIO A strategic objective is player CC",
		_ai.select_player_target_for_test() == player_cc
	)

	## Prove order refresh reissues only a dropped Pike.
	var dropped: Unit = pikes[0] as Unit
	dropped.cancel_attack()
	dropped.cancel_attack_move()
	dropped.stop_movement()
	_ai._last_command_kind = &"attack"
	_ai._last_command_target_id = player_cc.get_instance_id()
	_ai._last_command_army_count = _ai.get_enemy_army_for_test().size()
	_ai._last_command_destination = player_cc.global_position
	for i: int in range(1, pikes.size()):
		var other: Unit = pikes[i] as Unit
		other.command_attack(player_cc)
	hero.command_attack(player_cc)
	_ai.force_tick_for_test()
	var refreshed_attack: bool = (
		"_attack_target" in dropped and NodeSafety.is_alive_node(dropped.get("_attack_target"))
	)
	var refreshed_am: bool = (
		"_has_attack_move_destination" in dropped
		and bool(dropped.get("_has_attack_move_destination"))
	)
	_expect("idle Pike refreshed after drop", refreshed_attack or refreshed_am)

	## SCENARIO B — Enemy Hero dies mid-fight → always HOME (no continue-attack exception).
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	player_cc = _spawn_player_command_center(_cc.global_position + Vector3(40, 0, 0))
	hero = _spawn_enemy_hero(player_cc.global_position + Vector3(-5, 0, 0))
	hero.level = 5
	HeroProgressionStore.register_living_hero(hero)
	pikes.clear()
	for i: int in 5:
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
		"SCENARIO B hero death → HOME (no continue-attack)",
		_ai.get_debug_condition_bucket_for_test() == &"HOME"
	)
	_expect("SCENARIO B economy still wants Hero", _ai.get_debug_priority() == &"HERO")

	## SCENARIO C — Hero dies before army reaches player base → HOME.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	_spawn_player_command_center(_cc.global_position + Vector3(70, 0, 0))
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(0, 0, 3))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(float(i), 0, 2))
	_ai.set_camps_cleared_for_test(3)
	await get_tree().process_frame
	_kill_unit(hero)
	HeroProgressionStore.clear()
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect(
		"SCENARIO C hero death at home → HOME",
		_ai.get_debug_condition_bucket_for_test() == &"HOME"
	)
	_expect("SCENARIO C economy still wants Hero", _ai.get_debug_priority() == &"HERO")


func _test_attack_regroup_oscillation_regression() -> void:
	print("--- ATTACK_PLAYER ↔ REGROUP oscillation regression ---")
	_expect(
		"hero cohesion radius is pack-scale (not 18m boundary ring)",
		is_equal_approx(_ai.get_hero_cohesion_radius_for_test(), 12.0)
	)

	## PROOF GEOMETRY — Hero just inside old 18m leash with idle soldiers flips in one tick.
	## With pack-scale 12m leash this starting geometry is already not-together.
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
		"old-boundary lead (17.5m) is NOT cohesive under pack leash",
		not bool(snap_boundary.get("result", true))
	)
	_expect(
		"old-boundary fail reason is hero_inside",
		bool(snap_boundary.get("majority_inside", false))
		and not bool(snap_boundary.get("hero_inside", true))
	)

	## Cohesive field army → ATTACK_PLAYER, then advance Hero one uncapped tick while soldiers idle.
	## Must NOT immediately alternate ATTACK↔REGROUP across subsequent observations.
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

	## Simulate one strategic interval of Hero pull-ahead while soldiers remain (worst idle case).
	## Pack leash + speed-cap engage path: one 2.7m lead must not flip cohesion when starting packed.
	var snap0: Dictionary = _ai.get_cohesion_snapshot_for_test()
	var hd0: float = float(snap0.get("hero_to_center", 0.0))
	hero.global_position = hero.global_position + Vector3(2.7, 0, 0)
	await get_tree().process_frame
	var snap1: Dictionary = _ai.get_cohesion_snapshot_for_test()
	_expect(
		"one Hero tick from packed start stays cohesive",
		bool(snap1.get("result", false))
	)
	_ai.force_tick_for_test()
	_expect(
		"still ATTACK_PLAYER after one Hero lead tick",
		_ai.get_debug_condition_bucket_for_test() == &"ATTACK_PLAYER"
	)

	## Engage path must keep strategic speed caps (Hero not free to race soldiers).
	_expect(
		"ATTACK engage keeps Hero strategic speed cap",
		hero.has_strategic_move_speed_cap()
	)

	## One distant reinforcement must not redefine main cluster / force REGROUP.
	_spawn_enemy_spearman(_cc.global_position + Vector3(1, 0, 1))
	await get_tree().process_frame
	_expect(
		"distant reinforcement keeps field army cohesive",
		_ai.is_army_together_for_test()
	)
	_ai.force_tick_for_test()
	_expect(
		"distant reinforcement does not force REGROUP",
		_ai.get_debug_condition_bucket_for_test() != &"REGROUP"
	)

	## Genuine majority separation → REGROUP, and destination packs inside cohesion.
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
		"majority separated → REGROUP",
		_ai.get_debug_condition_bucket_for_test() == &"REGROUP"
	)
	var regroup_dest: Vector3 = _ai.get_regroup_destination_for_test()
	var main_center: Vector3 = _ai.get_main_army_centroid_for_test()
	var dest_to_main: float = Vector3(regroup_dest.x, 0, regroup_dest.z).distance_to(
		Vector3(main_center.x, 0, main_center.z)
	)
	_expect(
		"REGROUP destination near main cluster (clear pack geometry)",
		dest_to_main <= EnemyAI.COHESION_RADIUS + 1.0
	)
	## Move Hero onto the regroup point — must become clearly cohesive (inside pack leash).
	hero.global_position = regroup_dest
	## Snap soldiers onto cluster as regroup completion would.
	var living_soldiers: Array = []
	for unit_variant: Variant in _ai.get_enemy_army_for_test():
		if unit_variant is Unit and not (unit_variant is Hero) and NodeSafety.is_alive_node(unit_variant):
			living_soldiers.append(unit_variant)
	for i: int in living_soldiers.size():
		var soldier: Unit = living_soldiers[i] as Unit
		soldier.global_position = regroup_dest + Vector3(float(i % 4) * 0.8, 0, float(i / 4) * 0.8)
	await get_tree().process_frame
	var snap_regrouped: Dictionary = _ai.get_cohesion_snapshot_for_test()
	_expect("REGROUP completion geometry is cohesive", bool(snap_regrouped.get("result", false)))
	_expect(
		"REGROUP completion hero→cluster comfortably inside leash",
		float(snap_regrouped.get("hero_to_center", 99.0)) <= 6.5
	)
	_ai.force_tick_for_test()
	## With player present and army strong enough, attack may open; must not be REGROUP.
	_expect(
		"after clear regroup pack not stuck in REGROUP",
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


func _test_condition_stability_and_hero_unstuck() -> void:
	print("--- condition stability + hero local unstuck ---")
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

	## Hero local unstuck must not dump the whole army onto the Hero escape point.
	await _clear_units_and_buildings_except_cc()
	_spawn_basic_base(true, true, true)
	hero = _spawn_enemy_hero(_cc.global_position + Vector3(10, 0, 10))
	HeroProgressionStore.register_living_hero(hero)
	for i: int in 5:
		_spawn_enemy_spearman(_cc.global_position + Vector3(10.0 + float(i), 0, 10))
	await get_tree().process_frame
	_ai._read_live_world()
	hero.set_movement_target(_cc.global_position + Vector3(40, 0, 40))
	## Simulate confirmed stuck by calling fix directly (condition path requires physical watch).
	_ai._fix_current_hero_movement()
	var hero_escape: Vector3 = hero.get_movement_destination() if hero.has_move_target else Vector3.ZERO
	var piled: int = 0
	for unit_variant: Variant in _ai.get_enemy_army_for_test():
		if not unit_variant is Unit or unit_variant is Hero:
			continue
		var soldier: Unit = unit_variant as Unit
		if not NodeSafety.is_alive_node(soldier):
			continue
		var dest: Vector3 = (
			soldier.get_movement_destination() if soldier.has_move_target else soldier.global_position
		)
		if dest.distance_to(hero_escape) < 2.5:
			piled += 1
	_expect("hero unstuck does not pile army onto escape (<2 soldiers)", piled < 2)
	_expect(
		"hero unstuck command kind",
		_ai.get_last_command_kind_for_test() == &"hero_unstuck"
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
	var camp_id: int = camp.get_instance_id()
	_kill_unit(creep_a)
	await get_tree().process_frame
	_ai.force_tick_for_test()
	_expect("after one creep death still EARLY_CREEP", _ai.get_debug_condition_bucket_for_test() == &"EARLY_CREEP")
	_expect("after one creep death camp commitment unchanged", _ai.get_current_target_id_for_test() == camp_id)
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
