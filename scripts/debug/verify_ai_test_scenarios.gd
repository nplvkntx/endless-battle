extends Node

## Headless: AFTER CAMP 1 / AFTER CAMP 2 deterministic AI test scenarios on the real main match.

const CAMP_1 := "MediumCampSouthCenter"
const CAMP_2 := "MediumCampCentralCrossroads"
const CAMP_3 := "MediumCampNorthCenter"
const DRIVER_NAME := "AiTestScenariosDriver"

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if name != DRIVER_NAME:
		call_deferred("_spawn_rooted_driver")
		return
	await _pipeline()


func _spawn_rooted_driver() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if tree.root.get_node_or_null(DRIVER_NAME) != null:
		return
	var driver := Node.new()
	driver.name = DRIVER_NAME
	driver.set_script(get_script())
	tree.root.add_child(driver)


func _pipeline() -> void:
	print("verify_ai_test_scenarios: start")
	MatchSession.pending_dev_scenario = &""
	MatchSession.start_match()
	await _wait_for_match()

	var scenarios: AiTestScenarios = _scenarios()
	if scenarios == null:
		_failures.append("AiTestScenarios missing")
		_finish()
		return

	scenarios.request_after_camp_1()
	await _wait_for_match()
	await _wait_for_scenario_ok("after_camp_1")
	_assert_after_camp_1()
	print("verify: AFTER CAMP 1 assertions done failures=", _failures.size())

	scenarios = _scenarios()
	if scenarios == null:
		_failures.append("AiTestScenarios missing before Camp2")
		_finish()
		return
	scenarios.request_after_camp_2()
	await _wait_for_match()
	await _wait_for_scenario_ok("after_camp_2")
	_assert_after_camp_2()
	print("verify: AFTER CAMP 2 assertions done failures=", _failures.size())

	_finish()


func _wait_for_match() -> void:
	var frames: int = 0
	while frames < 240:
		await get_tree().process_frame
		frames += 1
		if _main() != null and _scenarios() != null and _simple_ai() != null:
			await get_tree().process_frame
			await get_tree().process_frame
			return
	_failures.append("match systems not ready")


func _wait_for_scenario_ok(scenario: String) -> void:
	var frames: int = 0
	while frames < 300:
		await get_tree().process_frame
		frames += 1
		var scenarios: AiTestScenarios = _scenarios()
		if scenarios == null:
			continue
		if scenarios._applying:
			continue
		if MatchSession.pending_dev_scenario != &"":
			continue
		if scenarios._status_label != null:
			var status: String = String(scenarios._status_label.text)
			if status.begins_with("OK"):
				await get_tree().process_frame
				return
			if status.begins_with("FAIL"):
				_failures.append(status)
				return
		var ai: SimpleWc3AI = _simple_ai()
		if frames > 45 and ai != null and ai.get_state() == SimpleWc3AI.State.TRAVEL:
			await get_tree().process_frame
			return
	_failures.append("scenario apply did not finish: %s" % scenario)


func _assert_after_camp_1() -> void:
	_assert_army(5, 2)
	_expect_eq("camp1 living", _count_living_creeps(CAMP_1), 0)
	_expect_true("camp2 alive", _count_living_creeps(CAMP_2) > 0)
	var ai: SimpleWc3AI = _simple_ai()
	_expect_true("AI present", ai != null)
	if ai == null:
		return
	_expect_eq("AI state TRAVEL", int(ai.get_state()), int(SimpleWc3AI.State.TRAVEL))
	_expect_eq("AI next camp", ai.get_camp_name(), CAMP_2)
	_expect_true("AI marked camp1 cleared", ai._cleared_camp_names.has(CAMP_1))
	_expect_true("AI sees hero", ai.last_hero_alive)
	_expect_eq("AI pikemen", ai.last_pikeman_count, 5)
	_expect_true("player workers present", _count_group(&"workers") > 0)
	_expect_true("enemy workers present", _count_group(&"enemy_workers") > 0)
	_expect_true("enemy farm", _has_completed_enemy_farm())
	_expect_true("enemy altar", _has_completed_enemy_altar())
	_expect_true("enemy barracks", _has_completed_enemy_barracks())


func _assert_after_camp_2() -> void:
	_assert_army(5, 3)
	_expect_eq("camp1 living", _count_living_creeps(CAMP_1), 0)
	_expect_eq("camp2 living", _count_living_creeps(CAMP_2), 0)
	_expect_true("camp3 alive", _count_living_creeps(CAMP_3) > 0)
	var ai: SimpleWc3AI = _simple_ai()
	_expect_true("AI present", ai != null)
	if ai == null:
		return
	_expect_eq("AI state TRAVEL", int(ai.get_state()), int(SimpleWc3AI.State.TRAVEL))
	_expect_eq("AI next camp", ai.get_camp_name(), CAMP_3)
	_expect_true("AI marked camp1 cleared", ai._cleared_camp_names.has(CAMP_1))
	_expect_true("AI marked camp2 cleared", ai._cleared_camp_names.has(CAMP_2))
	_expect_true("AI sees hero", ai.last_hero_alive)


func _assert_army(expected_pikes: int, expected_min_level: int) -> void:
	var heroes: int = 0
	var pikes: int = 0
	var hero_level: int = 0
	for node_variant: Variant in get_tree().get_nodes_in_group(&"enemy_combat_units"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if node_variant is Hero:
			heroes += 1
			hero_level = (node_variant as Hero).level
		elif node_variant is Spearman:
			pikes += 1
	_expect_eq("single enemy hero", heroes, 1)
	_expect_eq("pikemen", pikes, expected_pikes)
	_expect_true("hero level >= %d" % expected_min_level, hero_level >= expected_min_level)


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


func _count_group(group_name: StringName) -> int:
	var count: int = 0
	for node_variant: Variant in get_tree().get_nodes_in_group(group_name):
		if NodeSafety.is_alive_node(node_variant):
			count += 1
	return count


func _has_completed_enemy_farm() -> bool:
	for node_variant: Variant in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Farm:
			if (node_variant as Farm).building_state == Building.STATE_COMPLETED:
				return true
	return false


func _has_completed_enemy_altar() -> bool:
	for node_variant: Variant in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is HeroAltar:
			if (node_variant as HeroAltar).building_state == Building.STATE_COMPLETED:
				return true
	return false


func _has_completed_enemy_barracks() -> bool:
	for node_variant: Variant in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Barracks:
			if (node_variant as Barracks).building_state == Building.STATE_COMPLETED:
				return true
	return false


func _scenarios() -> AiTestScenarios:
	return get_tree().root.find_child("AiTestScenarios", true, false) as AiTestScenarios


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
		print("PASS ai_test_scenarios")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("FAIL: %s" % failure)
			print("FAIL: ", failure)
		print("FAIL ai_test_scenarios count=", _failures.size())
		get_tree().quit(1)
