extends Node

## Headless verification for Ranger Camouflage + Combat Roll synergy.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ranger_camouflage.tscn

const REPORT_PATH := "user://ranger_camouflage_verify_result.txt"
const RANGER_SCENE: PackedScene = preload("res://scenes/units/ranger.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	_verify_balance_constants(failures)
	_verify_camouflage_activation(failures)
	_verify_hunting_speed(failures)
	_verify_combat_roll_preserves_and_extends(failures)
	_verify_offensive_breaks(failures)
	_verify_move_stop_hold_preserve(failures)
	_verify_stealth_auto_target(failures)
	_verify_death_clears_state(failures)

	var report: String
	if failures.is_empty():
		report = "PASS ranger_camouflage\n"
	else:
		report = "FAIL ranger_camouflage\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- " + label)


func _unlock_ranger_abilities(ranger: Node, ultimate_rank: int = 2) -> void:
	ranger.level = 16
	ranger.ability_points = 20
	ranger.current_mana = ranger.max_mana
	for _i in range(5):
		ranger.try_learn_ability(HeroAbilityProgression.ABILITY_Q, false)
		ranger.try_learn_ability(HeroAbilityProgression.ABILITY_W, false)
		ranger.try_learn_ability(HeroAbilityProgression.ABILITY_E, false)
	for _i in range(clampi(ultimate_rank, 1, 3)):
		ranger.try_learn_ability(HeroAbilityProgression.ABILITY_R, false)
	ranger.current_mana = ranger.max_mana


func _make_ranger(ultimate_rank: int = 2) -> Node:
	var ranger: Node = RANGER_SCENE.instantiate()
	add_child(ranger)
	ranger.global_position = Vector3(0.0, 0.0, 0.0)
	_unlock_ranger_abilities(ranger, ultimate_rank)
	return ranger


func _verify_balance_constants(failures: PackedStringArray) -> void:
	_expect(failures, "duration rank1=10", is_equal_approx(RangerStats.get_camouflage_duration(1), 10.0))
	_expect(failures, "duration rank2=14", is_equal_approx(RangerStats.get_camouflage_duration(2), 14.0))
	_expect(failures, "duration rank3=18", is_equal_approx(RangerStats.get_camouflage_duration(3), 18.0))
	_expect(failures, "hunt speed rank1=10%", is_equal_approx(RangerStats.get_camouflage_hunt_speed_bonus(1), 0.10))
	_expect(failures, "hunt speed rank2=15%", is_equal_approx(RangerStats.get_camouflage_hunt_speed_bonus(2), 0.15))
	_expect(failures, "hunt speed rank3=20%", is_equal_approx(RangerStats.get_camouflage_hunt_speed_bonus(3), 0.20))
	_expect(
		failures,
		"max extended rank2=17",
		is_equal_approx(RangerStats.get_camouflage_max_extended_duration(2), 17.0)
	)
	_expect(
		failures,
		"roll extend=3",
		is_equal_approx(RangerStats.CAMOUFLAGE_ROLL_EXTEND_SECONDS, 3.0)
	)


func _verify_camouflage_activation(failures: PackedStringArray) -> void:
	var ranger: Node = _make_ranger(2)
	var ok: bool = ranger.try_camouflage()
	_expect(failures, "activate camouflage", ok)
	_expect(failures, "camouflage active", bool(ranger.get("_camouflage_active")))
	_expect(failures, "combat hidden", ranger.is_combat_hidden())
	_expect(
		failures,
		"duration starts at rank max",
		is_equal_approx(float(ranger.get("_camouflage_remaining")), 14.0)
	)
	_expect(failures, "camouflage buff applied", CamouflageBuff.has_buff(ranger))
	# No hunting bonus without prey / movement.
	_expect(
		failures,
		"no hunt bonus without prey",
		is_equal_approx(float(ranger.get("_hunting_speed_bonus_applied")), 0.0)
	)
	ranger.queue_free()


func _verify_hunting_speed(failures: PackedStringArray) -> void:
	var ranger: Node = _make_ranger(2)
	var enemy: Node = ENEMY_DUMMY_SCENE.instantiate()
	add_child(enemy)
	enemy.global_position = Vector3(6.0, 0.0, 0.0)
	CombatTargetValidation.reset_match_state()

	ranger.try_camouflage()
	ranger.call("_refresh_hunted_target", true)
	_expect(failures, "hunted target selected", ranger.get("_hunted_target") == enemy)

	# Simulate moving toward prey.
	ranger.velocity = Vector3(2.0, 0.0, 0.0)
	ranger.set("_hunted_target", enemy)
	ranger.call("_set_hunting_speed_bonus", ranger.call("_should_grant_hunting_speed"))
	var expected_bonus: float = RangerStats.MOVE_SPEED * 0.15
	_expect(
		failures,
		"hunt speed toward enemy",
		is_equal_approx(float(ranger.get("_hunting_speed_bonus_applied")), expected_bonus)
	)

	# Moving away removes bonus.
	ranger.velocity = Vector3(-2.0, 0.0, 0.0)
	ranger.call("_set_hunting_speed_bonus", ranger.call("_should_grant_hunting_speed"))
	_expect(
		failures,
		"no hunt speed when moving away",
		is_equal_approx(float(ranger.get("_hunting_speed_bonus_applied")), 0.0)
	)

	# Standing still — no bonus.
	ranger.velocity = Vector3.ZERO
	ranger.clear_move_target()
	ranger.call("_set_hunting_speed_bonus", ranger.call("_should_grant_hunting_speed"))
	_expect(
		failures,
		"no hunt speed when still",
		is_equal_approx(float(ranger.get("_hunting_speed_bonus_applied")), 0.0)
	)

	enemy.queue_free()
	ranger.queue_free()

	# No nearby enemies — no hunt target.
	var lone: Node = _make_ranger(1)
	CombatTargetValidation.reset_match_state()
	lone.try_camouflage()
	lone.call("_refresh_hunted_target", true)
	_expect(failures, "no hunt target without enemies", lone.get("_hunted_target") == null)
	lone.queue_free()

	# Heroes preferred over military when both in range.
	var ranger_pref: Node = _make_ranger(1)
	var military: Node = SWORDSMAN_SCENE.instantiate()
	var hero_enemy: Node = HERO_SCENE.instantiate()
	add_child(military)
	add_child(hero_enemy)
	military.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	hero_enemy.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	if not military.is_in_group(&"enemies"):
		military.add_to_group(&"enemies")
	if not hero_enemy.is_in_group(&"enemies"):
		hero_enemy.add_to_group(&"enemies")
	military.global_position = Vector3(4.0, 0.0, 0.0)
	hero_enemy.global_position = Vector3(8.0, 0.0, 0.0)
	CombatTargetValidation.reset_match_state()
	ranger_pref.try_camouflage()
	ranger_pref.call("_refresh_hunted_target", true)
	_expect(failures, "prefer hero over military", ranger_pref.get("_hunted_target") == hero_enemy)
	military.queue_free()
	hero_enemy.queue_free()
	ranger_pref.queue_free()


func _verify_combat_roll_preserves_and_extends(failures: PackedStringArray) -> void:
	var ranger: Node = _make_ranger(2)
	ranger.try_camouflage()
	ranger.set("_camouflage_remaining", 10.0)
	CamouflageBuff.sync_duration(ranger, 10.0)

	var rolled: bool = ranger.try_combat_roll(Vector3(5.0, 0.0, 0.0))
	_expect(failures, "combat roll during camo", rolled)
	_expect(failures, "still camouflaged after Q", bool(ranger.get("_camouflage_active")))
	_expect(failures, "still combat hidden after Q", ranger.is_combat_hidden())
	_expect(
		failures,
		"Q extends by 3s",
		is_equal_approx(float(ranger.get("_camouflage_remaining")), 13.0)
	)

	# Clamp: remaining cannot exceed rank max + 3.
	ranger.set("_camouflage_remaining", 16.0)
	ranger.call("_extend_camouflage_from_combat_roll")
	_expect(
		failures,
		"Q clamp at max+3",
		is_equal_approx(float(ranger.get("_camouflage_remaining")), 17.0)
	)
	ranger.call("_extend_camouflage_from_combat_roll")
	_expect(
		failures,
		"repeated Q cannot exceed clamp",
		is_equal_approx(float(ranger.get("_camouflage_remaining")), 17.0)
	)

	ranger.queue_free()


func _verify_offensive_breaks(failures: PackedStringArray) -> void:
	# Basic attack
	var ranger_aa: Node = _make_ranger(1)
	ranger_aa.try_camouflage()
	ranger_aa.call("_break_camouflage_from_action")
	_expect(failures, "AA ends camo active", not bool(ranger_aa.get("_camouflage_active")))
	_expect(failures, "AA clears remaining", is_equal_approx(float(ranger_aa.get("_camouflage_remaining")), 0.0))
	_expect(failures, "AA removes buff", not CamouflageBuff.has_buff(ranger_aa))
	_expect(failures, "AA clears hidden", not ranger_aa.is_combat_hidden())
	ranger_aa.queue_free()

	# W
	var ranger_w: Node = _make_ranger(1)
	ranger_w.try_camouflage()
	ranger_w.current_mana = ranger_w.max_mana
	ranger_w.try_bear_trap(Vector3(1.0, 0.0, 0.0))
	_expect(failures, "W ends camouflage", not bool(ranger_w.get("_camouflage_active")))
	_expect(failures, "W clears remaining", is_equal_approx(float(ranger_w.get("_camouflage_remaining")), 0.0))
	ranger_w.queue_free()

	# E
	var ranger_e: Node = _make_ranger(1)
	ranger_e.try_camouflage()
	ranger_e.current_mana = ranger_e.max_mana
	ranger_e.try_crossbow_bolt(Vector3(1.0, 0.0, 0.0))
	_expect(failures, "E ends camouflage", not bool(ranger_e.get("_camouflage_active")))
	_expect(failures, "E clears remaining", is_equal_approx(float(ranger_e.get("_camouflage_remaining")), 0.0))
	ranger_e.queue_free()


func _verify_move_stop_hold_preserve(failures: PackedStringArray) -> void:
	var ranger: Node = _make_ranger(1)
	ranger.try_camouflage()
	ranger.set_movement_target(Vector3(4.0, 0.0, 0.0))
	_expect(failures, "move keeps camo", bool(ranger.get("_camouflage_active")))
	ranger.clear_move_target()
	_expect(failures, "stop keeps camo", bool(ranger.get("_camouflage_active")))
	if ranger.has_method(&"command_hold_position"):
		ranger.command_hold_position()
	_expect(failures, "hold keeps camo", bool(ranger.get("_camouflage_active")))
	_expect(failures, "hold clears hunt bonus while still", is_equal_approx(float(ranger.get("_hunting_speed_bonus_applied")), 0.0))
	ranger.queue_free()


func _verify_stealth_auto_target(failures: PackedStringArray) -> void:
	var ranger: Node = _make_ranger(1)
	var attacker: Node = SWORDSMAN_SCENE.instantiate()
	add_child(attacker)
	attacker.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	if not attacker.is_in_group(&"enemies"):
		attacker.add_to_group(&"enemies")
	ranger.try_camouflage()
	_expect(
		failures,
		"enemies cannot auto-target camouflaged ranger",
		not StealthService.can_auto_target(attacker, ranger)
	)
	attacker.queue_free()
	ranger.queue_free()


func _verify_death_clears_state(failures: PackedStringArray) -> void:
	var ranger: Node = _make_ranger(1)
	ranger.try_camouflage()
	ranger.call("_clear_camouflage_state")
	_expect(failures, "death clear active", not bool(ranger.get("_camouflage_active")))
	_expect(failures, "death clear remaining", is_equal_approx(float(ranger.get("_camouflage_remaining")), 0.0))
	_expect(failures, "death clear hunt bonus", is_equal_approx(float(ranger.get("_hunting_speed_bonus_applied")), 0.0))
	_expect(failures, "death clear buff", not CamouflageBuff.has_buff(ranger))
	_expect(failures, "death clear hidden", not ranger.is_combat_hidden())
	ranger.queue_free()
