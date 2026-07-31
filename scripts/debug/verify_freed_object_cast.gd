extends Node

## Reproduces freed-object cast crash paths and verifies guards.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_freed_object_cast.tscn

const REPORT_PATH := "user://freed_object_cast_verify_result.txt"
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const SELECTION_MANAGER_SCRIPT: Script = preload("res://scripts/systems/selection_manager.gd")
const PLAYER_TEAM_ID: int = 0


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	await _verify_selection_selected_building_cleared(failures)
	await _verify_attack_range_with_freed_target(failures)
	await _verify_order_queue_skips_dead_target(failures)
	await _verify_military_clears_attack_target_on_exit(failures)
	await _verify_ai_focus_objective_variant_cast(failures)
	_verify_unit_order_get_alive_target(failures)
	_verify_within_attack_range_freed_variant(failures)

	var report: String
	if failures.is_empty():
		report = "PASS freed_object_cast\n"
	else:
		report = "FAIL freed_object_cast\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_selection_selected_building_cleared(failures: PackedStringArray) -> void:
	var selection: Node = SELECTION_MANAGER_SCRIPT.new()
	add_child(selection)

	var building: Building = FARM_SCENE.instantiate() as Building
	add_child(building)
	building.team_id = PLAYER_TEAM_ID
	building.building_state = Building.STATE_COMPLETED
	await get_tree().process_frame

	selection.call("_set_selected_building", building)
	if selection.get("selected_building") != building:
		failures.append("selected_building was not set")
		building.queue_free()
		selection.queue_free()
		return

	building.destroy_building()
	building.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	if selection.get("selected_building") != null:
		failures.append("selected_building not cleared after destroy")

	var building_ref: Variant = selection.get("selected_building")
	if NodeSafety.is_alive_node(building_ref):
		failures.append("freed selected building still reported alive")

	selection.queue_free()


func _verify_attack_range_with_freed_target(failures: PackedStringArray) -> void:
	var attacker: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(attacker)
	add_child(target)
	attacker.global_position = Vector3.ZERO
	target.global_position = Vector3(2.0, 0.0, 0.0)
	target.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	target.building_state = Building.STATE_COMPLETED
	await get_tree().process_frame

	attacker.call("_begin_attack_on_target", target, -1, true)
	if attacker.get("_attack_target") != target:
		failures.append("failed to lock military attack target before free")

	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var in_range: bool = bool(attacker.call("_is_in_attack_range", attacker.get("_attack_target")))
	if in_range:
		failures.append("attack range should be false after target freed")

	if attacker.get("_attack_target") != null:
		failures.append("military _attack_target still set after target tree_exiting")

	attacker.queue_free()


func _verify_order_queue_skips_dead_target(failures: PackedStringArray) -> void:
	var unit: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(unit)
	add_child(target)
	target.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	target.building_state = Building.STATE_COMPLETED
	await get_tree().process_frame

	unit.issue_order(UnitOrder.move(Vector3(20.0, 0.0, 0.0)), false)
	unit.issue_order(UnitOrder.attack(target), true)

	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	unit.notify_order_completed(UnitOrder.Type.MOVE)
	await get_tree().process_frame

	var active: UnitOrder = unit.get_active_order()
	if active != null and active.type == UnitOrder.Type.ATTACK:
		var alive: Node3D = active.get_alive_target()
		if alive != null:
			failures.append("queued attack order still resolved a freed target")

	unit.queue_free()


func _verify_military_clears_attack_target_on_exit(failures: PackedStringArray) -> void:
	var unit: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(unit)
	add_child(target)
	target.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	target.building_state = Building.STATE_COMPLETED
	await get_tree().process_frame

	unit.call("_begin_attack_on_target", target, -1, true)
	if unit.get("_attack_target") != target:
		failures.append("failed to set military attack target")
		unit.queue_free()
		return

	target.queue_free()
	await get_tree().process_frame

	if unit.get("_attack_target") != null:
		failures.append("military attack target not cleared on tree_exiting")

	unit.queue_free()


func _verify_ai_focus_objective_variant_cast(failures: PackedStringArray) -> void:
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(target)
	await get_tree().process_frame

	var entry: Dictionary = {"focus_objective": target}
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var focus_objective_ref: Variant = entry.get("focus_objective")
	if NodeSafety.is_alive_node(focus_objective_ref) and focus_objective_ref is Node3D:
		failures.append("freed focus_objective should not be alive")


func _verify_unit_order_get_alive_target(failures: PackedStringArray) -> void:
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(target)
	var order: UnitOrder = UnitOrder.attack(target)
	target.free()

	var alive: Node3D = order.get_alive_target()
	if alive != null:
		failures.append("UnitOrder.get_alive_target returned freed node")
	order.clear_invalid_target()
	if order.target != null:
		failures.append("UnitOrder.clear_invalid_target did not null target")


func _verify_within_attack_range_freed_variant(failures: PackedStringArray) -> void:
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(target)
	var attacker: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	add_child(attacker)
	var dangling: Variant = target
	target.free()

	if CombatTargetValidation.is_within_attack_range(attacker, dangling, 50.0):
		failures.append("is_within_attack_range true for freed target")

	attacker.queue_free()
