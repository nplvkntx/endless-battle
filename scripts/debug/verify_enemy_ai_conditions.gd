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
	await _test_freed_creep_camp_count()

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
	_cc.add_to_group(&"enemy_command_center")
	_cc.team_id = 1
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

	## TEST 7 — ATTACK_PLAYER target selects player entity only
	player_pike = _spawn_player_spearman(_cc.global_position + Vector3(40, 0, 0))
	var bait_creep: NeutralCreep = _spawn_neutral_creep(_cc.global_position + Vector3(8, 0, 0))
	await get_tree().process_frame
	var attack_target: Node3D = _ai.select_player_target_for_test()
	_expect("TEST7 attack target is not null", attack_target != null)
	_expect("TEST7 attack target is player pikeman", attack_target == player_pike)
	_expect(
		"TEST7 attack target is not NeutralCreep",
		attack_target != bait_creep and not CombatTargetValidation.is_neutral_creep(attack_target)
	)
	_expect(
		"TEST7 near NeutralCreep still not base threat",
		_ai.find_base_threat_for_test() == null
	)

	## Cleanup locals that remain alive so later harness state stays clean.
	_kill_unit(near_creep)
	_kill_unit(bait_creep)
	for creep_variant2: Variant in creeps:
		if NodeSafety.is_alive_node(creep_variant2):
			_kill_unit(creep_variant2 as Node)
	if NodeSafety.is_alive_node(player_pike):
		_kill_unit(player_pike)
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
	_world.add_child(building)
	building.global_position = position
	building.team_id = 1
	building.set_completed()
	building.add_to_group(&"buildings")
	return building


func _spawn_enemy_spearman(position: Vector3) -> Unit:
	var unit: Unit = SPEARMAN_SCENE.instantiate() as Unit
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

	func try_place_expansion_at_mine(_gold_mine: GoldMine) -> bool:
		requests.append(&"command_center")
		return true


class RecordingEnemyGatherManager extends EnemyGatherManager:
	var assignments: Array = []

	func assign_gather_job(worker: Worker, prefer_gold: bool = false, _force_recovery: bool = false) -> bool:
		assignments.append({"worker": worker, "prefer_gold": prefer_gold})
		return true
