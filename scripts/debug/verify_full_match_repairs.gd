extends Node

## Difficulty + hero AI ability + selection/targeting + Space focus regressions.
## Godot_v4.7-stable_win64_console.exe --headless --path <project> --scene res://scenes/debug/verify_full_match_repairs.tscn

const REPORT_PATH := "user://full_match_repairs_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const ASSASSIN_SCENE: PackedScene = preload("res://scenes/units/shadow_assassin.tscn")
const RANGER_SCENE: PackedScene = preload("res://scenes/units/ranger.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_full_match_repairs: start")

	_verify_difficulty_helpers(failures)
	_verify_hero_ai_abilities(failures)
	_verify_hero_skill_learning(failures)
	await _verify_ability_targeting_keeps_selection(failures)
	await _verify_space_focus_camera(failures)
	_verify_creep_staging_helper(failures)

	var report: String
	if failures.is_empty():
		report = "PASS full_match_repairs\n"
	else:
		report = "FAIL full_match_repairs\n" + "\n".join(failures) + "\n"

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


func _verify_difficulty_helpers(failures: PackedStringArray) -> void:
	var previous: int = MatchSession.get_ai_difficulty()

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.EASY)
	_expect(failures, "easy max barracks 1", AIDifficultyConfig.get_max_military_buildings(&"barracks") == 1)
	_expect(failures, "easy max stable 1", AIDifficultyConfig.get_max_military_buildings(&"stable") == 1)
	_expect(failures, "easy max artillery 1", AIDifficultyConfig.get_max_military_buildings(&"artillery_depot") == 1)
	_expect(failures, "easy resource 1.0", is_equal_approx(AIDifficultyConfig.get_enemy_resource_multiplier(), 1.0))
	_expect(failures, "easy train 1.0", is_equal_approx(AIDifficultyConfig.get_enemy_train_speed_multiplier(), 1.0))
	_expect(failures, "easy workers T1 13", AIDifficultyConfig.get_desired_worker_count(1, false) == 13)

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.NORMAL)
	_expect(failures, "normal max 3", AIDifficultyConfig.get_max_military_buildings() == 3)
	_expect(failures, "normal resource 1.0", is_equal_approx(AIDifficultyConfig.get_enemy_resource_multiplier(), 1.0))
	_expect(failures, "normal train 1.0", is_equal_approx(AIDifficultyConfig.get_enemy_train_speed_multiplier(), 1.0))
	_expect(failures, "normal workers T2 20", AIDifficultyConfig.get_desired_worker_count(2, false) == 20)
	_expect(failures, "normal workers expansion 33", AIDifficultyConfig.get_desired_worker_count(2, true) == 33)

	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.HARD)
	_expect(failures, "hard max 3", AIDifficultyConfig.get_max_military_buildings() == 3)
	_expect(failures, "hard resource 1.5", is_equal_approx(AIDifficultyConfig.get_enemy_resource_multiplier(), 1.5))
	_expect(failures, "hard train 1.5", is_equal_approx(AIDifficultyConfig.get_enemy_train_speed_multiplier(), 1.5))
	_expect(failures, "hard deposit 10→15", AIDifficultyConfig.scale_enemy_resource_amount(10) == 15)
	_expect(
		failures,
		"hard train seconds /1.5",
		is_equal_approx(TrainingConfig.get_enemy_military_train_seconds(15.0), 10.0)
	)

	MatchSession.set_ai_difficulty(previous)


func _verify_hero_ai_abilities(failures: PackedStringArray) -> void:
	var paladin: Hero = HERO_SCENE.instantiate() as Hero
	var assassin: Hero = ASSASSIN_SCENE.instantiate() as Hero
	var ranger: Hero = RANGER_SCENE.instantiate() as Hero
	add_child(paladin)
	add_child(assassin)
	add_child(ranger)

	for hero: Hero in [paladin, assassin, ranger]:
		hero.level = 16
		hero.ability_points = 20
		for ability_id: StringName in [
			HeroAbilityProgression.ABILITY_Q,
			HeroAbilityProgression.ABILITY_W,
			HeroAbilityProgression.ABILITY_E,
			HeroAbilityProgression.ABILITY_R,
		]:
			while hero.can_learn_ability(ability_id):
				hero.try_learn_ability(ability_id, false)
		var hc: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
		if hc != null:
			hc.current_health = maxi(1, int(float(hc.max_health) * 0.2))

	## Low HP context should drive at least one defensive/offensive cast attempt without error.
	var context := {
		"health_ratio": 0.2,
		"nearby_enemy_count": 4,
		"aoe_needed": 3,
		"defensive_hp_ratio": 0.4,
		"retreating": false,
	}
	paladin.try_ai_cast_abilities(context)
	assassin.try_ai_cast_abilities(context)
	ranger.try_ai_cast_abilities(context)
	_expect(failures, "paladin try_ai_cast_abilities callable", paladin.has_method(&"try_ai_cast_abilities"))
	_expect(failures, "assassin try_ai_cast_abilities callable", assassin.has_method(&"try_ai_cast_abilities"))
	_expect(failures, "ranger try_ai_cast_abilities callable", ranger.has_method(&"try_ai_cast_abilities"))
	## Paladin W is instant self — low HP should activate divine protection when learned.
	_expect(
		failures,
		"paladin defensive cast path",
		paladin.has_method(&"is_divine_protection_active")
		and (
			VariantUtils.to_bool(paladin.call(&"is_divine_protection_active"))
			or VariantUtils.to_bool(paladin.call(&"can_use_divine_protection")) == false
		)
	)

	paladin.queue_free()
	assassin.queue_free()
	ranger.queue_free()


func _verify_hero_skill_learning(failures: PackedStringArray) -> void:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.level = 6
	hero.ability_points = 3
	var spent: int = 0
	while hero.try_ai_spend_ability_point():
		spent += 1
	_expect(failures, "hero AI spent ability points", spent >= 1)
	_expect(failures, "hero AI drained or blocked remaining AP", hero.ability_points < 3)
	hero.queue_free()


func _verify_ability_targeting_keeps_selection(failures: PackedStringArray) -> void:
	var root := Node3D.new()
	add_child(root)
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	var soldier_a: Unit = SPEARMAN_SCENE.instantiate() as Unit
	var soldier_b: Unit = SPEARMAN_SCENE.instantiate() as Unit
	var dummy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	root.add_child(hero)
	root.add_child(soldier_a)
	root.add_child(soldier_b)
	root.add_child(dummy)
	await get_tree().process_frame
	hero.global_position = Vector3.ZERO
	soldier_a.global_position = Vector3(1, 0, 0)
	soldier_b.global_position = Vector3(2, 0, 0)
	dummy.global_position = Vector3(40, 0, 0)

	hero.level = 16
	hero.ability_points = 20
	while hero.can_learn_ability(HeroAbilityProgression.ABILITY_E):
		hero.try_learn_ability(HeroAbilityProgression.ABILITY_E, false)

	var selection: Node = get_tree().root.find_child("SelectionManager", true, false)
	if selection == null:
		## Headless verify scene may not include match SelectionManager — drive controller only.
		HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_E)
		_expect(failures, "targeting armed without selection manager", HeroAbilityTargetingController.is_targeting())
		var kept_armed: bool = not HeroAbilityTargetingController.try_handle_left_click(Vector2(8, 8))
		_expect(failures, "invalid click keeps targeting armed", HeroAbilityTargetingController.is_targeting() and kept_armed)
		HeroAbilityTargetingController.cancel_targeting()
		root.queue_free()
		await get_tree().process_frame
		return

	if selection.has_method(&"_set_selected_units"):
		var selected: Array[Unit] = [hero, soldier_a, soldier_b]
		selection._set_selected_units(selected)
	var before_count: int = 0
	if "selected_units" in selection:
		before_count = (selection.selected_units as Array).size()

	HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_E)
	_expect(failures, "targeting armed", HeroAbilityTargetingController.is_targeting())
	## Drive SelectionManager press+release so release cannot leak into selection.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(12, 12)
	selection._unhandled_input(press)
	_expect(failures, "invalid click keeps targeting", HeroAbilityTargetingController.is_targeting())
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(12, 12)
	selection._unhandled_input(release)
	if before_count > 0 and "selected_units" in selection:
		_expect(
			failures,
			"invalid click keeps selection size",
			(selection.selected_units as Array).size() == before_count
		)
	HeroAbilityTargetingController.cancel_targeting()
	root.queue_free()
	await get_tree().process_frame


func _verify_space_focus_camera(failures: PackedStringArray) -> void:
	Input.action_release(&"focus_hero")
	var camera := Camera3D.new()
	camera.set_script(load("res://scripts/systems/camera_controller.gd"))
	camera.edge_margin_pixels = 0.0
	## Pitched camera matching main.tscn — assert SCREEN center, not X/Z equality.
	camera.transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-55.0), 0.0, 0.0)),
		Vector3(50, 22, 50)
	)
	add_child(camera)
	await get_tree().process_frame

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	await get_tree().process_frame
	hero.global_position = Vector3(3, 0, -7)
	hero.team_id = 0
	if not hero.is_in_group(&"heroes"):
		hero.add_to_group(&"heroes")
	HeroProgressionStore.register_living_hero(hero)

	Input.action_press(&"focus_hero")
	camera._process(0.016)
	_expect(
		failures,
		"space hold screen-centers hero",
		camera.screen_center_error(hero.global_position) <= 3.0
	)
	hero.global_position = Vector3(-4, 0, 11)
	camera._process(0.016)
	_expect(
		failures,
		"space hold follows moved hero on screen",
		camera.screen_center_error(hero.global_position) <= 3.0
	)
	Input.action_release(&"focus_hero")
	_expect(failures, "space action released", not Input.is_action_pressed(&"focus_hero"))
	camera.edge_margin_pixels = 0.0
	hero.global_position = Vector3(9, 0, -2)
	camera._process(0.016)
	_expect(
		failures,
		"space release does not keep hero screen-centered",
		camera.screen_center_error(hero.global_position) > 8.0
	)

	hero.queue_free()
	camera.queue_free()
	HeroProgressionStore.clear()
	await get_tree().process_frame


func _verify_creep_staging_helper(failures: PackedStringArray) -> void:
	var ai := EnemyAI.new()
	ai.show_debug_overlay = false
	ai.set_process(false)
	add_child(ai)
	ai._w = {"home": Vector3(30, 0, 30)}
	var camp := Node3D.new()
	add_child(camp)
	camp.global_position = Vector3(0, 0, 0)
	PlayerRouteNavigation.ensure_grid_ready()
	var staging: Vector3 = ai._compute_creep_staging_point(camp)
	_expect(failures, "creep staging finite", staging.is_finite())
	_expect(
		failures,
		"creep staging not raw camp center",
		Vector2(staging.x - camp.global_position.x, staging.z - camp.global_position.z).length() > 2.0
	)
	_expect(
		failures,
		"creep staging nearer home than camp",
		Vector2(staging.x - 30.0, staging.z - 30.0).length()
		<= Vector2(camp.global_position.x - 30.0, camp.global_position.z - 30.0).length() + 0.1
	)
	camp.queue_free()
	ai.queue_free()
