class_name AiTestScenarios
extends CanvasLayer

## Dev-only: deterministic SimpleWc3AI creep-stage jump buttons.
## Clean match reload, then plain setup code. Not a save system.

const HERO_FALLBACK_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")

const CAMP_1 := "MediumCampSouthCenter"
const CAMP_2 := "MediumCampCentralCrossroads"
const CAMP_3 := "MediumCampNorthCenter"

const SCENARIO_AFTER_CAMP_1 := &"after_camp_1"
const SCENARIO_AFTER_CAMP_2 := &"after_camp_2"
const SCENARIO_AFTER_CAMP_3 := &"after_camp_3"

var _status_label: Label = null
var _applying: bool = false


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 90
	_build_buttons()
	var scenario: StringName = MatchSession.take_pending_dev_scenario()
	if scenario != &"":
		_hold_simple_ai(true)
		call_deferred("_apply_pending_scenario", scenario)


func request_after_camp_1() -> void:
	_set_status("LOAD… AFTER CAMP 1")
	MatchSession.request_dev_scenario_reload(SCENARIO_AFTER_CAMP_1)


func request_after_camp_2() -> void:
	_set_status("LOAD… AFTER CAMP 2")
	MatchSession.request_dev_scenario_reload(SCENARIO_AFTER_CAMP_2)


func request_after_camp_3() -> void:
	_set_status("LOAD… AFTER CAMP 3")
	MatchSession.request_dev_scenario_reload(SCENARIO_AFTER_CAMP_3)


func apply_scenario(scenario: StringName) -> bool:
	if scenario == SCENARIO_AFTER_CAMP_1:
		return await _setup_after_camps([CAMP_1], 1)
	if scenario == SCENARIO_AFTER_CAMP_2:
		return await _setup_after_camps([CAMP_1, CAMP_2], 2)
	if scenario == SCENARIO_AFTER_CAMP_3:
		return await _setup_after_camps([CAMP_1, CAMP_2, CAMP_3], 3)
	return false


func _apply_pending_scenario(scenario: StringName) -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		await tree.process_frame
		await tree.process_frame
		await tree.process_frame

	var ok: bool = await apply_scenario(scenario)
	if ok:
		_set_status("OK %s" % String(scenario).to_upper())
		print("AiTestScenarios: applied ", scenario)
	else:
		_set_status("FAIL %s" % String(scenario))
		_hold_simple_ai(false)


func _setup_after_camps(cleared_camps: Array, camps_cleared: int) -> bool:
	var tree: SceneTree = get_tree()
	var main: Node = _main()
	var ai: SimpleWc3AI = _find_simple_ai(tree)
	if tree == null or main == null or ai == null:
		return false
	if _applying:
		return false

	_applying = true
	_hold_simple_ai(true)
	PlayerRouteNavigation.clear_all()
	PlayerRouteNavigation.ensure_grid_ready()

	_ensure_enemy_opening_buildings(main)
	_kill_camps(cleared_camps)
	await tree.process_frame
	await tree.process_frame
	CreepCampSafety.reset_match_state()

	var finished_camp: Node3D = _find_camp(String(cleared_camps[cleared_camps.size() - 1]))
	var gather: Vector3 = _safe_gather_near_camp(finished_camp)
	_spawn_enemy_army(main, gather, camps_cleared)

	EnemyResourceManager.add_gold(EconomyStats.MEDIUM_CAMP_TOTAL_GOLD * camps_cleared)
	var army_food: int = (
		HeroStats.TRAIN_FOOD_COST + UnitStats.SPEARMAN_FOOD_COST * SimpleWc3AI.MIN_PIKEMEN
	)
	EnemyResourceManager.try_pay_training(0, army_food)

	ai.init_test_after_camps(cleared_camps)
	_hold_simple_ai(false)
	_applying = false
	return true


func _ensure_enemy_opening_buildings(main: Node) -> void:
	var base: Vector3 = _enemy_base_position()
	if not _has_completed_enemy_farm():
		_spawn_enemy_building(main, FARM_SCENE, "DevEnemyFarm", base + Vector3(-8.0, 0.0, -4.0))
		EnemyResourceManager.add_food_max(Farm.FOOD_CAP_BONUS)
	if not _has_completed_enemy_altar():
		_spawn_enemy_building(main, ALTAR_SCENE, "DevEnemyAltar", base + Vector3(-6.0, 0.0, -10.0))
	if not _has_completed_enemy_barracks():
		_spawn_enemy_building(main, BARRACKS_SCENE, "DevEnemyBarracks", base + Vector3(-12.0, 0.0, -8.0))


func _spawn_enemy_army(main: Node, gather: Vector3, camps_cleared: int) -> void:
	## Fresh match has no enemy combat army yet — spawn the real opening force once.
	AIHeroMastery.ensure_enemy_hero_choice()
	var kit_id: StringName = HeroProgressionStore.get_locked_kit_id(true)
	var hero_scene: PackedScene = HeroCatalog.load_scene(kit_id)
	if hero_scene == null:
		hero_scene = HERO_FALLBACK_SCENE

	var hero: Hero = hero_scene.instantiate() as Hero
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	if hero.is_in_group(&"units"):
		hero.remove_from_group(&"units")
	if hero.is_in_group(&"heroes"):
		hero.remove_from_group(&"heroes")
	if not hero.is_in_group(&"enemies"):
		hero.add_to_group(&"enemies")
	main.add_child(hero)
	hero.global_position = gather
	hero.apply_team_visuals()
	EnemyArmyCommand.register_combat_unit(hero)
	HeroProgressionStore.register_living_hero(hero)
	hero.add_xp(float(EconomyStats.MEDIUM_CAMP_TOTAL_XP * camps_cleared))

	for i: int in SimpleWc3AI.MIN_PIKEMEN:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		if pike.is_in_group(&"units"):
			pike.remove_from_group(&"units")
		if not pike.is_in_group(&"enemies"):
			pike.add_to_group(&"enemies")
		main.add_child(pike)
		pike.global_position = gather + Vector3(float(i) * 0.9 - 1.8, 0.0, 1.2)
		pike.apply_team_visuals()
		EnemyArmyCommand.register_combat_unit(pike)


func _kill_camps(camp_names: Array) -> void:
	for name_ref: Variant in camp_names:
		var camp: Node3D = _find_camp(String(name_ref))
		if camp == null:
			continue
		for child: Node in camp.get_children():
			if child is NeutralCreep:
				child.queue_free()


func _safe_gather_near_camp(camp: Node3D) -> Vector3:
	var base: Vector3 = _enemy_base_position()
	var origin: Vector3 = camp.global_position if camp != null else base
	## Offset toward the enemy base so the army sits past the cleared camp, not inside it.
	var toward_base: Vector3 = (base - origin)
	toward_base.y = 0.0
	if toward_base.length_squared() < 0.01:
		toward_base = Vector3(8.0, 0.0, 8.0)
	else:
		toward_base = toward_base.normalized() * 10.0
	var candidate: Vector3 = origin + toward_base
	candidate.y = 0.0
	var walkable: Vector3 = PlayerRouteNavigation.nearest_walkable_world(candidate)
	walkable.y = 0.0
	return walkable


func _spawn_enemy_building(main: Node, scene: PackedScene, node_name: String, pos: Vector3) -> Building:
	var building: Building = scene.instantiate() as Building
	building.name = node_name
	building.team_id = TeamVisuals.ENEMY_TEAM_ID
	main.add_child(building)
	building.global_position = pos
	if not building.is_in_group(&"enemy_command_center"):
		building.add_to_group(&"enemy_command_center")
	building.set_completed()
	building.apply_team_visuals()
	PlayerRouteNavigation.register_static_obstacle(building)
	return building


func _has_completed_enemy_farm() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Farm:
			var farm: Farm = node_variant as Farm
			if farm.building_state == Building.STATE_COMPLETED:
				return true
	return false


func _has_completed_enemy_altar() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is HeroAltar:
			var altar: HeroAltar = node_variant as HeroAltar
			if altar.building_state == Building.STATE_COMPLETED:
				return true
	return false


func _has_completed_enemy_barracks() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Barracks:
			var barracks: Barracks = node_variant as Barracks
			if barracks.building_state == Building.STATE_COMPLETED:
				return true
	return false


func _build_buttons() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.offset_left = -200.0
	root.offset_top = 12.0
	root.offset_right = -12.0
	root.offset_bottom = 140.0
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)

	var camp1_btn := Button.new()
	camp1_btn.text = "AFTER CAMP 1"
	camp1_btn.pressed.connect(request_after_camp_1)
	vbox.add_child(camp1_btn)

	var camp2_btn := Button.new()
	camp2_btn.text = "AFTER CAMP 2"
	camp2_btn.pressed.connect(request_after_camp_2)
	vbox.add_child(camp2_btn)

	var camp3_btn := Button.new()
	camp3_btn.text = "AFTER CAMP 3"
	camp3_btn.pressed.connect(request_after_camp_3)
	vbox.add_child(camp3_btn)

	_status_label = Label.new()
	_status_label.text = "AI test: -"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7, 1.0))
	vbox.add_child(_status_label)


func _set_status(text: String) -> void:
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = text


func _hold_simple_ai(hold: bool) -> void:
	var ai: SimpleWc3AI = _find_simple_ai(get_tree())
	if ai == null:
		return
	if hold:
		ai.set_process(false)
	elif MilitaryAIConfig.is_simple_wc3_ai_enabled():
		ai.set_process(true)


func _find_camp(camp_name: String) -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(&"creep_camps"):
		if NodeSafety.is_alive_node(node_variant) and String((node_variant as Node).name) == camp_name:
			return node_variant as Node3D
	return null


func _enemy_base_position() -> Vector3:
	var tree: SceneTree = get_tree()
	if tree == null:
		return Vector3(31.0, 0.0, 28.0)
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_command_center"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is CommandCenter:
			return (node_variant as CommandCenter).global_position
	return Vector3(31.0, 0.0, 28.0)


func _find_simple_ai(tree: SceneTree) -> SimpleWc3AI:
	if tree == null:
		return null
	var root: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	if root != null and root.simple_wc3_ai != null:
		return root.simple_wc3_ai
	return tree.root.find_child("SimpleWc3AI", true, false) as SimpleWc3AI


func _main() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("Main")
