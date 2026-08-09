extends Node

## Headless: post-Camp-1 and post-Camp-2 checkpoint round-trips on the real main match.
## Launcher reparents a driver under SceneTree.root so it survives MatchSession clean reloads.

const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")

const CAMP_1 := "MediumCampSouthCenter"
const CAMP_2 := "MediumCampCentralCrossroads"
const CAMP_3 := "MediumCampNorthCenter"
const DRIVER_NAME := "DevCheckpointRoundtripDriver"

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	## Scene root is freed by change_scene — run from a root-owned driver instead.
	if name != DRIVER_NAME:
		call_deferred("_spawn_rooted_driver")
		return
	await _pipeline()


func _spawn_rooted_driver() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var existing: Node = tree.root.get_node_or_null(DRIVER_NAME)
	if existing != null:
		return
	var driver := Node.new()
	driver.name = DRIVER_NAME
	driver.set_script(get_script())
	tree.root.add_child(driver)


func _pipeline() -> void:
	print("verify_dev_checkpoint_roundtrip: start")
	MatchSession.pending_dev_checkpoint_apply = false
	MatchSession.start_match()
	await _wait_for_match()

	## --- POST CAMP 1 ---
	await _setup_post_camp_state([CAMP_1], CAMP_2, 1)
	var expected_camp1: Dictionary = _capture_expected("post_camp_1")
	var checkpoint: AiTestCheckpoint = _checkpoint()
	if checkpoint == null:
		_failures.append("checkpoint missing before Camp1 save")
		_finish()
		return
	_expect_true("SAVE after Camp 1", checkpoint.save_checkpoint())
	print("verify: saved post-camp-1 checkpoint")
	await _mutate_world()
	_expect_true("LOAD after Camp 1", checkpoint.load_checkpoint())
	await _wait_for_match()
	await _wait_for_checkpoint_apply()
	_assert_restored("Camp1", expected_camp1)
	print("verify: Camp1 round-trip assertions done failures=", _failures.size())

	## --- POST CAMP 2 ---
	await _setup_post_camp_state([CAMP_1, CAMP_2], CAMP_3, 2)
	var expected_camp2: Dictionary = _capture_expected("post_camp_2")
	checkpoint = _checkpoint()
	if checkpoint == null:
		_failures.append("checkpoint missing before Camp2 save")
		_finish()
		return
	_expect_true("SAVE after Camp 2", checkpoint.save_checkpoint())
	print("verify: saved post-camp-2 checkpoint")
	await _mutate_world()
	_expect_true("LOAD after Camp 2", checkpoint.load_checkpoint())
	await _wait_for_match()
	await _wait_for_checkpoint_apply()
	_assert_restored("Camp2", expected_camp2)
	print("verify: Camp2 round-trip assertions done failures=", _failures.size())

	_finish()


func _wait_for_match() -> void:
	var frames: int = 0
	while frames < 240:
		await get_tree().process_frame
		frames += 1
		if _main() != null and _checkpoint() != null and _simple_ai() != null:
			await get_tree().process_frame
			await get_tree().process_frame
			return
	_failures.append("match systems not ready")


func _wait_for_checkpoint_apply() -> void:
	var frames: int = 0
	while frames < 300:
		await get_tree().process_frame
		frames += 1
		var checkpoint: AiTestCheckpoint = _checkpoint()
		if checkpoint == null:
			continue
		if checkpoint._applying:
			continue
		if MatchSession.pending_dev_checkpoint_apply:
			continue
		if checkpoint._status_label != null:
			var status: String = String(checkpoint._status_label.text)
			if status.begins_with("LOAD CHECKPOINT ok"):
				await get_tree().process_frame
				return
			if status.begins_with("LOAD FAIL"):
				_failures.append(status)
				return
		## Fallback: AI no longer at fresh-match BUILD_FARM after apply.
		var ai: SimpleWc3AI = _simple_ai()
		if frames > 45 and ai != null and ai.get_state() == SimpleWc3AI.State.TRAVEL:
			await get_tree().process_frame
			return
	_failures.append("checkpoint apply did not finish")


func _setup_post_camp_state(cleared_camps: Array, next_camp: String, hero_level: int) -> void:
	var tree: SceneTree = get_tree()
	var main: Node = _main()
	var ai: SimpleWc3AI = _simple_ai()
	if main == null or ai == null:
		_failures.append("setup missing main/ai")
		return

	ai.set_process(false)

	_free_group_nodes([&"units", &"enemies", &"enemy_combat_units", &"workers", &"enemy_workers", &"heroes"])
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Building:
			continue
		var building: Building = node_variant as Building
		var parent: Node = building.get_parent()
		if (
			building is CommandCenter
			and parent != null
			and String(parent.name).contains("StartingBase")
		):
			continue
		building.queue_free()
	for node_variant: Variant in tree.get_nodes_in_group(&"neutral_creeps"):
		if NodeSafety.is_alive_node(node_variant):
			(node_variant as Node).queue_free()
	await tree.process_frame
	await tree.process_frame

	var enemy_cc: CommandCenter = _find_enemy_cc()
	var base_pos: Vector3 = enemy_cc.global_position if enemy_cc != null else Vector3(31.0, 0.0, 28.0)

	_spawn_enemy_building(FARM_SCENE, "EnemyFarm", base_pos + Vector3(-8.0, 0.0, -4.0))
	_spawn_enemy_building(ALTAR_SCENE, "EnemyAltar", base_pos + Vector3(-6.0, 0.0, -10.0))
	_spawn_enemy_building(BARRACKS_SCENE, "EnemyBarracks", base_pos + Vector3(-12.0, 0.0, -8.0))

	for i: int in 5:
		_spawn_worker(false, Vector3(-29.0 - float(i), 0.5, -23.0))
		_spawn_worker(true, base_pos + Vector3(-2.0 + float(i) * 0.5, 0.5, -4.0))

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	main.add_child(hero)
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero.global_position = base_pos + Vector3(-10.0, 0.5, -12.0)
	hero.add_to_group(&"enemies")
	EnemyArmyCommand.register_combat_unit(hero)
	hero.level = maxi(1, hero_level)
	hero._current_xp = 40.0 * float(hero_level)
	hero._reapply_all_level_stat_scaling()
	HeroProgressionStore.register_living_hero(hero)
	var hero_hp: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
	if hero_hp != null:
		hero_hp.current_health = maxi(1, int(float(hero_hp.max_health) * 0.7))
		hero_hp.health_changed.emit(hero_hp.current_health, hero_hp.max_health)

	for i: int in 5:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		main.add_child(pike)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.global_position = hero.global_position + Vector3(float(i) * 0.8, 0.0, 0.6)
		pike.add_to_group(&"enemies")
		EnemyArmyCommand.register_combat_unit(pike)
		var pike_hp: HealthComponent = pike.get_node_or_null("HealthComponent") as HealthComponent
		if pike_hp != null and i == 0:
			pike_hp.current_health = maxi(1, int(float(pike_hp.max_health) * 0.5))
			pike_hp.health_changed.emit(pike_hp.current_health, pike_hp.max_health)

	_restore_all_default_creeps_except(cleared_camps)
	await tree.process_frame
	CreepCampSafety.reset_match_state()

	ResourceManager.gold = 350 + hero_level
	ResourceManager.wood = 220
	EnemyResourceManager.gold = 480 + hero_level
	EnemyResourceManager.wood = 260
	EnemyResourceManager.food_current = 11
	EnemyResourceManager.food_max = 15
	ResourceManager.food_current = 5
	ResourceManager.food_max = 10

	var next: Node3D = _find_camp(next_camp)
	ai.assembly_position = base_pos + Vector3(-12.0, 0.0, -12.0)
	ai._state = SimpleWc3AI.State.TRAVEL
	ai._camp_name = next_camp
	ai._camp_destination = (
		Vector3(next.global_position.x, 0.0, next.global_position.z)
		if next != null
		else Vector3.ZERO
	)
	ai._travel_issued = true
	ai._cleared_camp_names.clear()
	for cleared_ref: Variant in cleared_camps:
		ai._cleared_camp_names[String(cleared_ref)] = true
	ai.strategic_orders_issued = 20 + hero_level
	ai._resolve_camp_id_from_name()
	ai._observe_army()
	ai.set_process(false)


func _restore_all_default_creeps_except(dead_camps: Array) -> void:
	var tree: SceneTree = get_tree()
	for node_variant: Variant in tree.get_nodes_in_group(&"creep_camps"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		var camp: Node3D = node_variant as Node3D
		var camp_name: String = String(camp.name)
		if dead_camps.has(camp_name):
			continue
		var has_living: bool = false
		for child: Node in camp.get_children():
			if child is NeutralCreep:
				has_living = true
				break
		if has_living:
			continue
		var count: int = 6 if camp_name.begins_with("Medium") else 5
		for i: int in count:
			var creep: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
			camp.add_child(creep)
			creep.global_position = camp.global_position + Vector3(
				float(i % 3) - 1.0,
				0.5,
				float(int(i / 3)) - 1.0
			)
			if not creep.is_in_group(&"neutral_creeps"):
				creep.add_to_group(&"neutral_creeps")


func _mutate_world() -> void:
	var tree: SceneTree = get_tree()
	var ai: SimpleWc3AI = _simple_ai()
	if ai != null:
		ai._state = SimpleWc3AI.State.DONE
		ai._camp_name = "MUTATED"
		ai._cleared_camp_names.clear()
	ResourceManager.gold = 1
	EnemyResourceManager.gold = 1
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_combat_units"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Spearman:
			(node_variant as Node).queue_free()
			break
	var camp: Node3D = _find_camp(CAMP_2)
	if camp != null:
		for child: Node in camp.get_children():
			if child is NeutralCreep:
				child.queue_free()
	await tree.process_frame
	await tree.process_frame


func _capture_expected(label: String) -> Dictionary:
	var tree: SceneTree = get_tree()
	var ai: SimpleWc3AI = _simple_ai()
	var hero: Hero = null
	var pike_count: int = 0
	var worker_enemy: int = 0
	var worker_player: int = 0
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_combat_units"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if node_variant is Hero:
			hero = node_variant as Hero
		elif node_variant is Spearman:
			pike_count += 1
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_workers"):
		if NodeSafety.is_alive_node(node_variant):
			worker_enemy += 1
	for node_variant: Variant in tree.get_nodes_in_group(&"workers"):
		if NodeSafety.is_alive_node(node_variant):
			worker_player += 1

	var buildings: int = 0
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Building:
			buildings += 1

	var hero_hp: int = -1
	if hero != null:
		var health: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			hero_hp = health.current_health

	return {
		"label": label,
		"hero_level": hero.level if hero != null else -1,
		"hero_hp": hero_hp,
		"pike_count": pike_count,
		"worker_enemy": worker_enemy,
		"worker_player": worker_player,
		"buildings": buildings,
		"player_gold": ResourceManager.gold,
		"enemy_gold": EnemyResourceManager.gold,
		"camp1_alive": _count_living_creeps(CAMP_1),
		"camp2_alive": _count_living_creeps(CAMP_2),
		"ai_state": int(ai.get_state()) if ai != null else -1,
		"ai_camp": ai.get_camp_name() if ai != null else "",
	}


func _assert_restored(tag: String, expected: Dictionary) -> void:
	var got: Dictionary = _capture_expected(tag)
	_expect_eq("%s hero level" % tag, got["hero_level"], expected["hero_level"])
	_expect_eq("%s hero hp" % tag, got["hero_hp"], expected["hero_hp"])
	_expect_eq("%s pikemen" % tag, got["pike_count"], expected["pike_count"])
	_expect_eq("%s enemy workers" % tag, got["worker_enemy"], expected["worker_enemy"])
	_expect_eq("%s player workers" % tag, got["worker_player"], expected["worker_player"])
	_expect_eq("%s buildings" % tag, got["buildings"], expected["buildings"])
	_expect_eq("%s player gold" % tag, got["player_gold"], expected["player_gold"])
	_expect_eq("%s enemy gold" % tag, got["enemy_gold"], expected["enemy_gold"])
	_expect_eq("%s camp1 living creeps" % tag, got["camp1_alive"], expected["camp1_alive"])
	_expect_eq("%s camp2 living creeps" % tag, got["camp2_alive"], expected["camp2_alive"])
	_expect_eq("%s AI state" % tag, got["ai_state"], expected["ai_state"])
	_expect_eq("%s AI camp" % tag, got["ai_camp"], expected["ai_camp"])

	var heroes: int = 0
	for node_variant: Variant in get_tree().get_nodes_in_group(&"enemy_combat_units"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Hero:
			heroes += 1
	_expect_eq("%s single enemy hero" % tag, heroes, 1)

	var ai: SimpleWc3AI = _simple_ai()
	if ai != null:
		ai._observe_army()
		_expect_true("%s AI sees hero" % tag, ai.last_hero_alive)
		_expect_eq("%s AI pikemen observe" % tag, ai.last_pikeman_count, int(expected["pike_count"]))
		_expect_true("%s AI travel_issued cleared" % tag, ai._travel_issued == false)


func _spawn_enemy_building(scene: PackedScene, node_name: String, pos: Vector3) -> Building:
	var main: Node = _main()
	var building: Building = scene.instantiate() as Building
	building.name = node_name
	building.team_id = TeamVisuals.ENEMY_TEAM_ID
	main.add_child(building)
	building.global_position = pos
	building.add_to_group(&"enemy_command_center")
	building.set_completed()
	building.apply_team_visuals()
	PlayerRouteNavigation.register_static_obstacle(building)
	return building


func _spawn_worker(enemy: bool, pos: Vector3) -> Worker:
	var main: Node = _main()
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	main.add_child(worker)
	worker.global_position = pos
	if enemy:
		worker.team_id = TeamVisuals.ENEMY_TEAM_ID
		if worker.is_in_group(&"units"):
			worker.remove_from_group(&"units")
		if worker.is_in_group(&"workers"):
			worker.remove_from_group(&"workers")
		worker.add_to_group(&"enemies")
		worker.add_to_group(&"enemy_workers")
	else:
		if not worker.is_in_group(&"units"):
			worker.add_to_group(&"units")
		if not worker.is_in_group(&"workers"):
			worker.add_to_group(&"workers")
	worker.apply_team_visuals()
	return worker


func _free_group_nodes(groups: Array) -> void:
	var seen: Dictionary = {}
	var to_free: Array[Node] = []
	for group_name: Variant in groups:
		for node_variant: Variant in get_tree().get_nodes_in_group(group_name as StringName):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			var node: Node = node_variant as Node
			var id: int = node.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			to_free.append(node)
	for node: Node in to_free:
		node.queue_free()


func _count_living_creeps(camp_name: String) -> int:
	var camp: Node3D = _find_camp(camp_name)
	if camp == null:
		return -1
	var count: int = 0
	for child: Node in camp.get_children():
		if not (child is NeutralCreep):
			continue
		var health: HealthComponent = child.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_health > 0:
			count += 1
	return count


func _find_camp(camp_name: String) -> Node3D:
	for node_variant: Variant in get_tree().get_nodes_in_group(&"creep_camps"):
		if NodeSafety.is_alive_node(node_variant) and String((node_variant as Node).name) == camp_name:
			return node_variant as Node3D
	return null


func _find_enemy_cc() -> CommandCenter:
	for node_variant: Variant in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is CommandCenter:
			return node_variant as CommandCenter
	return null


func _checkpoint() -> AiTestCheckpoint:
	return get_tree().root.find_child("AiTestCheckpoint", true, false) as AiTestCheckpoint


func _simple_ai() -> SimpleWc3AI:
	var root: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(get_tree())
	if root != null and root.simple_wc3_ai != null:
		return root.simple_wc3_ai
	return get_tree().root.find_child("SimpleWc3AI", true, false) as SimpleWc3AI


func _main() -> Node:
	return get_tree().root.get_node_or_null("Main")


func _expect_true(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _expect_eq(label: String, got: Variant, expected: Variant) -> void:
	if got != expected:
		_failures.append("%s: got %s expected %s" % [label, str(got), str(expected)])


func _finish() -> void:
	if _failures.is_empty():
		print("PASS dev_checkpoint_roundtrip")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("FAIL: %s" % failure)
			print("FAIL: ", failure)
		print("FAIL dev_checkpoint_roundtrip count=", _failures.size())
		get_tree().quit(1)
