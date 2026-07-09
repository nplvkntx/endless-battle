extends Node

## Player upgrades researched at the Blacksmith and Academy.

signal upgrade_levels_changed()
signal upgrade_applied(upgrade_id: StringName)
signal enemy_upgrade_applied(upgrade_id: StringName)

const MAX_LEVEL: int = 5
const ACADEMY_MAX_LEVEL: int = 1
const LEVEL_COSTS: Array[int] = [100, 150, 225, 325, 450]
const FASTER_GATHERING_SPEED_MULTIPLIER: float = 1.25

const UPGRADE_SWORDSMAN_ATTACK: StringName = &"swordsman_attack"
const UPGRADE_SWORDSMAN_ARMOR: StringName = &"swordsman_armor"
const UPGRADE_ARCHER_ATTACK: StringName = &"archer_attack"
const UPGRADE_ARCHER_ATTACK_SPEED: StringName = &"archer_attack_speed"
const UPGRADE_ARCHER_RANGE: StringName = &"archer_range"
const UPGRADE_FASTER_GATHERING: StringName = &"faster_gathering"

const BLACKSMITH_UPGRADE_ORDER: Array[StringName] = [
	UPGRADE_SWORDSMAN_ATTACK,
	UPGRADE_SWORDSMAN_ARMOR,
	UPGRADE_ARCHER_ATTACK,
	UPGRADE_ARCHER_ATTACK_SPEED,
	UPGRADE_ARCHER_RANGE,
]

const ACADEMY_UPGRADE_ORDER: Array[StringName] = [
	UPGRADE_FASTER_GATHERING,
]

const ACADEMY_UPGRADE_COSTS: Dictionary = {
	UPGRADE_FASTER_GATHERING: {"gold": 1000, "wood": 700},
}

const UPGRADE_DISPLAY_NAMES: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: "Swordsman Attack",
	UPGRADE_SWORDSMAN_ARMOR: "Swordsman Armor",
	UPGRADE_ARCHER_ATTACK: "Archer Attack",
	UPGRADE_ARCHER_ATTACK_SPEED: "Archer Attack Speed",
	UPGRADE_ARCHER_RANGE: "Archer Range",
	UPGRADE_FASTER_GATHERING: "Faster Gathering",
}

const UPGRADE_HOTKEYS: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: "Q",
	UPGRADE_SWORDSMAN_ARMOR: "W",
	UPGRADE_ARCHER_ATTACK: "E",
	UPGRADE_ARCHER_ATTACK_SPEED: "R",
	UPGRADE_ARCHER_RANGE: "T",
	UPGRADE_FASTER_GATHERING: "Q",
}

var _levels: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: 0,
	UPGRADE_SWORDSMAN_ARMOR: 0,
	UPGRADE_ARCHER_ATTACK: 0,
	UPGRADE_ARCHER_ATTACK_SPEED: 0,
	UPGRADE_ARCHER_RANGE: 0,
	UPGRADE_FASTER_GATHERING: 0,
}

var _enemy_levels: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: 0,
	UPGRADE_SWORDSMAN_ARMOR: 0,
	UPGRADE_ARCHER_ATTACK: 0,
	UPGRADE_ARCHER_ATTACK_SPEED: 0,
	UPGRADE_ARCHER_RANGE: 0,
	UPGRADE_FASTER_GATHERING: 0,
}


func is_academy_upgrade(upgrade_id: StringName) -> bool:
	return upgrade_id in ACADEMY_UPGRADE_ORDER


func get_level(upgrade_id: StringName) -> int:
	return int(_levels.get(upgrade_id, 0))


func get_enemy_level(upgrade_id: StringName) -> int:
	return int(_enemy_levels.get(upgrade_id, 0))


func is_max_level(upgrade_id: StringName) -> bool:
	return get_level(upgrade_id) >= MAX_LEVEL


func is_enemy_max_level(upgrade_id: StringName) -> bool:
	return get_enemy_level(upgrade_id) >= MAX_LEVEL


func is_academy_max_level(upgrade_id: StringName) -> bool:
	return get_level(upgrade_id) >= ACADEMY_MAX_LEVEL


func is_enemy_academy_max_level(upgrade_id: StringName) -> bool:
	return get_enemy_level(upgrade_id) >= ACADEMY_MAX_LEVEL


func has_faster_gathering(for_enemy: bool = false) -> bool:
	if for_enemy:
		return get_enemy_level(UPGRADE_FASTER_GATHERING) >= ACADEMY_MAX_LEVEL

	return get_level(UPGRADE_FASTER_GATHERING) >= ACADEMY_MAX_LEVEL


func get_display_name(upgrade_id: StringName) -> String:
	return String(UPGRADE_DISPLAY_NAMES.get(upgrade_id, upgrade_id))


func get_hotkey_label(upgrade_id: StringName) -> String:
	return String(UPGRADE_HOTKEYS.get(upgrade_id, ""))


func get_next_level_cost(upgrade_id: StringName) -> Dictionary:
	return _get_level_cost(get_level(upgrade_id))


func get_enemy_next_level_cost(upgrade_id: StringName) -> Dictionary:
	return _get_level_cost(get_enemy_level(upgrade_id))


func get_academy_upgrade_cost(upgrade_id: StringName) -> Dictionary:
	if is_academy_max_level(upgrade_id):
		return {"wood": 0, "gold": 0}

	return ACADEMY_UPGRADE_COSTS.get(upgrade_id, {"wood": 0, "gold": 0}).duplicate()


func get_enemy_academy_upgrade_cost(upgrade_id: StringName) -> Dictionary:
	if is_enemy_academy_max_level(upgrade_id):
		return {"wood": 0, "gold": 0}

	return ACADEMY_UPGRADE_COSTS.get(upgrade_id, {"wood": 0, "gold": 0}).duplicate()


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


func can_afford_academy_upgrade(upgrade_id: StringName) -> bool:
	if is_academy_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_academy_upgrade_cost(upgrade_id)
	return ResourceManager.can_afford(cost.gold, cost.wood)


func can_enemy_afford_academy_upgrade(upgrade_id: StringName) -> bool:
	if is_enemy_academy_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_enemy_academy_upgrade_cost(upgrade_id)
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


func try_pay_for_academy_research(upgrade_id: StringName) -> bool:
	if not is_academy_upgrade(upgrade_id) or is_academy_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_academy_upgrade_cost(upgrade_id)
	if not ResourceManager.try_spend(cost.gold, cost.wood):
		if ResourceManager.gold < cost.gold and ResourceManager.wood < cost.wood:
			ResourceManager.show_feedback("Not enough gold and wood")
		elif ResourceManager.gold < cost.gold:
			ResourceManager.show_feedback("Not enough gold")
		else:
			ResourceManager.show_feedback("Not enough wood")
		return false

	return true


func try_pay_for_enemy_academy_research(upgrade_id: StringName) -> bool:
	if not is_academy_upgrade(upgrade_id) or is_enemy_academy_max_level(upgrade_id):
		return false

	var cost: Dictionary = get_enemy_academy_upgrade_cost(upgrade_id)
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


func finish_academy_research(upgrade_id: StringName) -> void:
	if not is_academy_upgrade(upgrade_id) or is_academy_max_level(upgrade_id):
		return

	_levels[upgrade_id] = ACADEMY_MAX_LEVEL
	upgrade_levels_changed.emit()
	upgrade_applied.emit(upgrade_id)


func finish_enemy_academy_research(upgrade_id: StringName) -> void:
	if not is_academy_upgrade(upgrade_id) or is_enemy_academy_max_level(upgrade_id):
		return

	_enemy_levels[upgrade_id] = ACADEMY_MAX_LEVEL
	enemy_upgrade_applied.emit(upgrade_id)


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
