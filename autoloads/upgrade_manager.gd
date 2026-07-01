extends Node

## Player military upgrades researched at the Blacksmith.

signal upgrade_levels_changed()
signal upgrade_applied(upgrade_id: StringName)
signal enemy_upgrade_applied(upgrade_id: StringName)

const MAX_LEVEL: int = 5
const LEVEL_COSTS: Array[int] = [100, 150, 225, 325, 450]

const UPGRADE_SWORDSMAN_ATTACK: StringName = &"swordsman_attack"
const UPGRADE_SWORDSMAN_ARMOR: StringName = &"swordsman_armor"
const UPGRADE_ARCHER_ATTACK: StringName = &"archer_attack"
const UPGRADE_ARCHER_ATTACK_SPEED: StringName = &"archer_attack_speed"
const UPGRADE_ARCHER_RANGE: StringName = &"archer_range"

const BLACKSMITH_UPGRADE_ORDER: Array[StringName] = [
	UPGRADE_SWORDSMAN_ATTACK,
	UPGRADE_SWORDSMAN_ARMOR,
	UPGRADE_ARCHER_ATTACK,
	UPGRADE_ARCHER_ATTACK_SPEED,
	UPGRADE_ARCHER_RANGE,
]

const UPGRADE_DISPLAY_NAMES: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: "Swordsman Attack",
	UPGRADE_SWORDSMAN_ARMOR: "Swordsman Armor",
	UPGRADE_ARCHER_ATTACK: "Archer Attack",
	UPGRADE_ARCHER_ATTACK_SPEED: "Archer Attack Speed",
	UPGRADE_ARCHER_RANGE: "Archer Range",
}

const UPGRADE_HOTKEYS: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: "Q",
	UPGRADE_SWORDSMAN_ARMOR: "W",
	UPGRADE_ARCHER_ATTACK: "E",
	UPGRADE_ARCHER_ATTACK_SPEED: "R",
	UPGRADE_ARCHER_RANGE: "T",
}

var _levels: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: 0,
	UPGRADE_SWORDSMAN_ARMOR: 0,
	UPGRADE_ARCHER_ATTACK: 0,
	UPGRADE_ARCHER_ATTACK_SPEED: 0,
	UPGRADE_ARCHER_RANGE: 0,
}

var _enemy_levels: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: 0,
	UPGRADE_SWORDSMAN_ARMOR: 0,
	UPGRADE_ARCHER_ATTACK: 0,
	UPGRADE_ARCHER_ATTACK_SPEED: 0,
	UPGRADE_ARCHER_RANGE: 0,
}


func get_level(upgrade_id: StringName) -> int:
	return int(_levels.get(upgrade_id, 0))


func get_enemy_level(upgrade_id: StringName) -> int:
	return int(_enemy_levels.get(upgrade_id, 0))


func is_max_level(upgrade_id: StringName) -> bool:
	return get_level(upgrade_id) >= MAX_LEVEL


func is_enemy_max_level(upgrade_id: StringName) -> bool:
	return get_enemy_level(upgrade_id) >= MAX_LEVEL


func get_display_name(upgrade_id: StringName) -> String:
	return String(UPGRADE_DISPLAY_NAMES.get(upgrade_id, upgrade_id))


func get_hotkey_label(upgrade_id: StringName) -> String:
	return String(UPGRADE_HOTKEYS.get(upgrade_id, ""))


func get_next_level_cost(upgrade_id: StringName) -> Dictionary:
	return _get_level_cost(get_level(upgrade_id))


func get_enemy_next_level_cost(upgrade_id: StringName) -> Dictionary:
	return _get_level_cost(get_enemy_level(upgrade_id))


func _get_level_cost(level: int) -> Dictionary:
	if level >= MAX_LEVEL:
		return {"wood": 0, "gold": 0}

	var cost: int = LEVEL_COSTS[level]
	return {"wood": cost, "gold": cost}


func can_afford_upgrade(upgrade_id: StringName) -> bool:
	if is_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_next_level_cost(upgrade_id)
	return ResourceManager.can_afford(cost.gold, cost.wood)


func can_enemy_afford_upgrade(upgrade_id: StringName) -> bool:
	if is_enemy_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_enemy_next_level_cost(upgrade_id)
	return EnemyResourceManager.can_afford(cost.gold, cost.wood)


func try_pay_for_research(upgrade_id: StringName) -> bool:
	if is_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_next_level_cost(upgrade_id)
	if not ResourceManager.try_spend(cost.gold, cost.wood):
		if ResourceManager.gold < cost.gold and ResourceManager.wood < cost.wood:
			ResourceManager.show_feedback("Not enough gold and wood")
		elif ResourceManager.gold < cost.gold:
			ResourceManager.show_feedback("Not enough gold")
		else:
			ResourceManager.show_feedback("Not enough wood")
		return false

	return true


func try_pay_for_enemy_research(upgrade_id: StringName) -> bool:
	if is_enemy_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_enemy_next_level_cost(upgrade_id)
	return EnemyResourceManager.try_spend(cost.gold, cost.wood)


func finish_research(upgrade_id: StringName) -> void:
	if is_max_level(upgrade_id):
		return

	_levels[upgrade_id] = get_level(upgrade_id) + 1
	upgrade_levels_changed.emit()
	upgrade_applied.emit(upgrade_id)
	call_deferred("_refresh_all_player_military_units")


func finish_enemy_research(upgrade_id: StringName) -> void:
	if is_enemy_max_level(upgrade_id):
		return

	_enemy_levels[upgrade_id] = get_enemy_level(upgrade_id) + 1
	enemy_upgrade_applied.emit(upgrade_id)
	call_deferred("_refresh_all_enemy_military_units")


func try_research(upgrade_id: StringName) -> bool:
	if not try_pay_for_research(upgrade_id):
		return false

	finish_research(upgrade_id)
	return true


func apply_player_upgrades_to_unit(unit: Unit) -> void:
	if not _is_player_military_unit(unit):
		return

	if unit is Swordsman:
		(unit as Swordsman).apply_blacksmith_upgrades()
	elif unit is Archer:
		(unit as Archer).apply_blacksmith_upgrades()


func apply_enemy_upgrades_to_unit(unit: Unit) -> void:
	if not _is_enemy_military_unit(unit):
		return

	if unit is Swordsman:
		(unit as Swordsman).apply_blacksmith_upgrades()
	elif unit is Archer:
		(unit as Archer).apply_blacksmith_upgrades()


func _refresh_all_player_military_units() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	for node: Node in tree.get_nodes_in_group(&"units"):
		if node is Unit:
			apply_player_upgrades_to_unit(node as Unit)


func _refresh_all_enemy_military_units() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	for node: Node in tree.get_nodes_in_group(&"enemies"):
		if node is Unit:
			apply_enemy_upgrades_to_unit(node as Unit)


func _is_player_military_unit(unit: Unit) -> bool:
	if not (unit is Swordsman or unit is Archer):
		return false
	if TeamVisuals.resolve_team(unit, unit.team_id) != TeamVisuals.PLAYER_TEAM_ID:
		return false
	return true


func _is_enemy_military_unit(unit: Unit) -> bool:
	if not (unit is Swordsman or unit is Archer):
		return false
	if TeamVisuals.resolve_team(unit, unit.team_id) == TeamVisuals.PLAYER_TEAM_ID:
		return false
	return true
