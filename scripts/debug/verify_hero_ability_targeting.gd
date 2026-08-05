extends Node

## Headless verification for LoL-style hero targeting + player hero manual kiting.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_hero_ability_targeting.tscn

const REPORT_PATH := "user://hero_ability_targeting_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const ASSASSIN_SCENE: PackedScene = preload("res://scenes/units/shadow_assassin.tscn")
const RANGER_SCENE: PackedScene = preload("res://scenes/units/ranger.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	_verify_definitions(failures)
	_verify_targeting_controller_api(failures)
	await _verify_player_hero_idle_auto_attack(failures)
	await _verify_military_keeps_auto_attack(failures)
	await _verify_attack_windup_and_move_cancel(failures)
	await _verify_invalid_cast_spends_nothing(failures)
	_verify_cast_mode_default(failures)

	var report: String
	if failures.is_empty():
		report = "PASS hero_ability_targeting\n"
	else:
		report = "FAIL hero_ability_targeting\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_definitions(failures: PackedStringArray) -> void:
	var paladin: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var assassin: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	var ranger: MeleeHero = RANGER_SCENE.instantiate() as MeleeHero
	add_child(paladin)
	add_child(assassin)
	add_child(ranger)

	for hero: MeleeHero in [paladin, assassin, ranger]:
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

	var p_q: HeroAbilityDefinition = paladin.get_ability_definition(HeroAbilityProgression.ABILITY_Q)
	var p_w: HeroAbilityDefinition = paladin.get_ability_definition(HeroAbilityProgression.ABILITY_W)
	var p_e: HeroAbilityDefinition = paladin.get_ability_definition(HeroAbilityProgression.ABILITY_E)
	var p_r: HeroAbilityDefinition = paladin.get_ability_definition(HeroAbilityProgression.ABILITY_R)
	_expect(failures, "paladin Q circular self", p_q != null and p_q.targeting_type == HeroAbilityDefinition.TargetingType.CIRCULAR_SELF)
	_expect(failures, "paladin W instant self", p_w != null and p_w.is_instant_cast())
	_expect(failures, "paladin E target enemy", p_e != null and p_e.targeting_type == HeroAbilityDefinition.TargetingType.TARGET_ENEMY)
	_expect(failures, "paladin R target enemy", p_r != null and p_r.targeting_type == HeroAbilityDefinition.TargetingType.TARGET_ENEMY)
	_expect(failures, "paladin Q radius matches slam", p_q != null and is_equal_approx(p_q.effect_radius, float(paladin.call(&"get_ground_slam_radius"))))

	var a_q: HeroAbilityDefinition = assassin.get_ability_definition(HeroAbilityProgression.ABILITY_Q)
	var a_w: HeroAbilityDefinition = assassin.get_ability_definition(HeroAbilityProgression.ABILITY_W)
	var a_e: HeroAbilityDefinition = assassin.get_ability_definition(HeroAbilityProgression.ABILITY_E)
	var a_r: HeroAbilityDefinition = assassin.get_ability_definition(HeroAbilityProgression.ABILITY_R)
	_expect(failures, "assassin Q target enemy", a_q != null and a_q.targeting_type == HeroAbilityDefinition.TargetingType.TARGET_ENEMY)
	_expect(failures, "assassin W circular area", a_w != null and a_w.targeting_type == HeroAbilityDefinition.TargetingType.CIRCULAR_AREA)
	_expect(failures, "assassin E circular self", a_e != null and a_e.targeting_type == HeroAbilityDefinition.TargetingType.CIRCULAR_SELF)
	_expect(failures, "assassin R dash target", a_r != null and a_r.targeting_type == HeroAbilityDefinition.TargetingType.DASH_TARGET)
	_expect(failures, "assassin Q range matches", a_q != null and is_equal_approx(a_q.cast_range, assassin.get_ability_range(HeroAbilityProgression.ABILITY_Q)))
	_expect(failures, "assassin W cast range", a_w != null and is_equal_approx(a_w.cast_range, ShadowAssassinStats.SMOKE_CAST_RANGE))

	var r_q: HeroAbilityDefinition = ranger.get_ability_definition(HeroAbilityProgression.ABILITY_Q)
	var r_w: HeroAbilityDefinition = ranger.get_ability_definition(HeroAbilityProgression.ABILITY_W)
	var r_e: HeroAbilityDefinition = ranger.get_ability_definition(HeroAbilityProgression.ABILITY_E)
	var r_r: HeroAbilityDefinition = ranger.get_ability_definition(HeroAbilityProgression.ABILITY_R)
	_expect(failures, "ranger Q dash direction", r_q != null and r_q.targeting_type == HeroAbilityDefinition.TargetingType.DASH_DIRECTION)
	_expect(failures, "ranger W circular area", r_w != null and r_w.targeting_type == HeroAbilityDefinition.TargetingType.CIRCULAR_AREA)
	_expect(failures, "ranger E directional line", r_e != null and r_e.targeting_type == HeroAbilityDefinition.TargetingType.DIRECTIONAL_LINE)
	_expect(failures, "ranger R instant self", r_r != null and r_r.is_instant_cast())
	_expect(failures, "ranger E range matches bolt", r_e != null and is_equal_approx(r_e.cast_range, RangerStats.CROSSBOW_BOLT_RANGE))
	_expect(failures, "ranger E width matches hit radius", r_e != null and is_equal_approx(r_e.line_width, RangerStats.CROSSBOW_BOLT_HIT_RADIUS * 2.0))
	_expect(failures, "ranger Q dash distance", r_q != null and is_equal_approx(r_q.max_travel_distance, RangerStats.COMBAT_ROLL_DISTANCE))

	paladin.queue_free()
	assassin.queue_free()
	ranger.queue_free()


func _verify_targeting_controller_api(failures: PackedStringArray) -> void:
	_expect(failures, "targeting controller autoload present", HeroAbilityTargetingController != null)
	_expect(failures, "targeting starts inactive", not HeroAbilityTargetingController.is_targeting())
	HeroAbilityTargetingController.cancel_targeting()
	_expect(failures, "cancel while inactive safe", not HeroAbilityTargetingController.is_targeting())


func _verify_player_hero_idle_auto_attack(failures: PackedStringArray) -> void:
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(hero)
	add_child(enemy)
	await get_tree().process_frame
	hero.global_position = Vector3.ZERO
	enemy.global_position = Vector3(1.5, 0, 0)
	CombatTargetValidation.reset_match_state()

	for _i in range(30):
		await get_tree().physics_frame
		if hero.get_attack_target() == enemy:
			break

	_expect(failures, "player hero idle auto-acquires nearby enemy", hero.get_attack_target() == enemy)
	_expect(failures, "player hero is player controlled", hero.is_player_controlled_hero())

	hero.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _verify_military_keeps_auto_attack(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	add_child(unit)
	add_child(enemy)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO
	enemy.global_position = Vector3(1.5, 0, 0)
	CombatTargetValidation.reset_match_state()
	await get_tree().physics_frame

	_expect(failures, "dummy is enemy faction", CombatTargetValidation.is_enemy_faction(enemy))
	_expect(failures, "swordsman hostile to dummy", CombatTargetValidation.are_hostile(unit, enemy))
	var found: Node3D = CombatTargetValidation.find_closest_player_unit_attack_target_in_range(
		unit, unit.attack_range
	)
	_expect(failures, "military target search finds dummy", found == enemy)

	unit._try_auto_attack()
	_expect(failures, "military unit still auto-acquires", unit._attack_target == enemy)
	_expect(failures, "military unit supports combat orders", unit.supports_combat_orders())

	unit.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _verify_attack_windup_and_move_cancel(failures: PackedStringArray) -> void:
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(hero)
	add_child(enemy)
	await get_tree().process_frame
	hero.global_position = Vector3.ZERO
	enemy.global_position = Vector3(1.2, 0, 0)

	hero.command_attack(enemy)
	_expect(failures, "direct attack sets target", hero.get_attack_target() == enemy)

	for _i in range(5):
		await get_tree().physics_frame

	var mana_before: int = hero.current_mana
	hero.set_movement_target(Vector3(8, 0, 0))
	_expect(failures, "move cancels attack order", hero.get_attack_target() == null)
	_expect(failures, "move does not spend mana", hero.current_mana == mana_before)
	_expect(failures, "windup cleared after move", not hero._attack_windup_active)

	hero.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _verify_invalid_cast_spends_nothing(failures: PackedStringArray) -> void:
	var assassin: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	add_child(assassin)
	await get_tree().process_frame
	assassin.level = 6
	assassin.ability_points = 4
	assassin.try_learn_ability(HeroAbilityProgression.ABILITY_Q, false)
	assassin.current_mana = assassin.max_mana

	var mana_before: int = assassin.current_mana
	var cd_before: float = assassin.get_ability_cooldown_remaining(HeroAbilityProgression.ABILITY_Q)
	var cast_ok: bool = VariantUtils.to_bool(assassin.call(&"try_axe_mark"))
	_expect(failures, "axe mark without target fails", not cast_ok)
	_expect(failures, "failed axe mark spends no mana", assassin.current_mana == mana_before)
	_expect(
		failures,
		"failed axe mark starts no cooldown",
		is_equal_approx(
			assassin.get_ability_cooldown_remaining(HeroAbilityProgression.ABILITY_Q),
			cd_before
		)
	)

	assassin.queue_free()
	await get_tree().process_frame


func _verify_cast_mode_default(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"default cast mode is normal",
		GameSettings.get_hero_ability_cast_mode() == GameSettings.CAST_MODE_NORMAL
	)


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if condition:
		return
	failures.append("FAIL: " + label)
