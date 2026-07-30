extends Node

## Headless smoke test for shared MilitaryUnit / TowerAutoCombat layer.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_combat_command_layer.tscn

const REPORT_PATH := "user://combat_command_layer_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const LIGHT_CAVALRY_SCENE: PackedScene = preload("res://scenes/units/light_cavalry.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	_verify_class_hierarchy(failures)
	_verify_tower_helper(failures)
	await _verify_orders(failures)
	await _verify_invalid_target_cleanup(failures)
	await _verify_tower_scene(failures)

	var report: String
	if failures.is_empty():
		report = "PASS combat_command_layer\n"
	else:
		report = "FAIL combat_command_layer\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_class_hierarchy(failures: PackedStringArray) -> void:
	var swordsman: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var spearman: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	var archer: Archer = ARCHER_SCENE.instantiate() as Archer
	var cavalry: LightCavalry = LIGHT_CAVALRY_SCENE.instantiate() as LightCavalry

	_expect(failures, "swordsman is MilitaryUnit", swordsman is MilitaryUnit)
	_expect(failures, "spearman is MilitaryUnit", spearman is MilitaryUnit)
	_expect(failures, "archer is MilitaryUnit", archer is MilitaryUnit)
	_expect(failures, "light cavalry is MilitaryUnit", cavalry is MilitaryUnit)
	_expect(failures, "swordsman supports combat orders", swordsman.supports_combat_orders())
	_expect(failures, "swordsman default damage", swordsman.attack_damage == 10)
	_expect(failures, "spearman default damage", spearman.attack_damage == 6)
	_expect(failures, "spearman default range", is_equal_approx(spearman.attack_range, 2.4))
	_expect(failures, "archer default range", is_equal_approx(archer.attack_range, 8.0))
	_expect(failures, "archer ignores armor intake", archer._compute_incoming_damage(5.0) == 5)
	_expect(failures, "light cavalry default damage", cavalry.attack_damage == 8)
	_expect(failures, "light cavalry default cooldown", is_equal_approx(cavalry.attack_cooldown, 0.9))

	swordsman.free()
	spearman.free()
	archer.free()
	cavalry.free()


func _verify_tower_helper(failures: PackedStringArray) -> void:
	var combat := TowerAutoCombat.new()
	combat.attack_range = 10.0
	combat.attack_cooldown = 1.5
	combat.randomize_search_timer()
	_expect(failures, "tower combat search timer randomized", combat.target_search_timer >= 0.0)
	combat.mark_fired()
	_expect(failures, "tower combat cooldown set", is_equal_approx(combat.attack_cooldown_timer, 1.5))


func _verify_orders(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO

	unit.command_attack_move(Vector3(10, 0, 0))
	_expect(failures, "attack-move sets destination flag", unit._has_attack_move_destination)
	_expect(failures, "attack-move clears attack target", unit._attack_target == null)

	unit.cancel_attack_move()
	_expect(failures, "cancel attack-move clears flag", not unit._has_attack_move_destination)

	unit.command_attack_move(Vector3(5, 0, 0))
	unit.set_movement_target(Vector3(1, 0, 0))
	_expect(failures, "move cancels attack-move", not unit._has_attack_move_destination)
	_expect(failures, "move cancels attack", unit._attack_target == null)

	unit.queue_free()
	await get_tree().process_frame


func _verify_invalid_target_cleanup(failures: PackedStringArray) -> void:
	var unit: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(unit)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO
	unit.has_move_target = false
	unit.velocity = Vector3.ZERO

	var dummy: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(dummy)
	await get_tree().process_frame
	dummy.global_position = Vector3(1, 0, 0)
	dummy._health_component.current_health = 0

	unit._attack_target = dummy
	unit._has_chase_target = true
	unit._has_attack_move_destination = true
	unit._attack_move_destination = Vector3(8, 0, 0)

	unit._sanitize_attack_target()
	_expect(failures, "invalid target cleared", unit._attack_target == null)
	_expect(failures, "chase cleared after invalid target", not unit._has_chase_target)
	_expect(failures, "attack-move resumed after invalid target", unit.has_move_target)

	dummy.queue_free()
	unit.queue_free()
	await get_tree().process_frame


func _verify_tower_scene(failures: PackedStringArray) -> void:
	var tower: Tower = TOWER_SCENE.instantiate() as Tower
	add_child(tower)
	await get_tree().process_frame
	_expect(failures, "tower has auto combat helper", tower._auto_combat != null)
	_expect(failures, "tower auto combat range wired", is_equal_approx(tower._auto_combat.attack_range, tower.attack_range))
	tower.queue_free()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
