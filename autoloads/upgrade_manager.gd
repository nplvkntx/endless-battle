extends Node

## Player upgrades researched at the Blacksmith and Academy.

signal upgrade_levels_changed()
signal upgrade_applied(upgrade_id: StringName)
signal enemy_upgrade_applied(upgrade_id: StringName)

const MAX_LEVEL: int = 5
const ACADEMY_MAX_LEVEL: int = 1
const CAVALRY_ATTACK_DAMAGE_PER_LEVEL: int = 3
const CAVALRY_DEFENSE_ARMOR_PER_LEVEL: int = 1
const STABLE_UPGRADE_BASE_GOLD: int = 150
const STABLE_UPGRADE_BASE_WOOD: int = 75
const STABLE_UPGRADE_GOLD_PER_LEVEL: int = 100
const STABLE_UPGRADE_WOOD_PER_LEVEL: int = 50
const LEVEL_COSTS: Array[int] = [100, 150, 225, 325, 450]
const FASTER_GATHERING_SPEED_MULTIPLIER: float = 1.25
const FASTER_UNIT_TRAINING_SPEED_MULTIPLIER: float = 1.2
const IMPROVED_TOOLS_CONSTRUCTION_SPEED_MULTIPLIER: float = 1.2
const ENGINEERING_MAX_HEALTH_MULTIPLIER: float = 1.2
const BALLISTICS_DAMAGE_MULTIPLIER: float = 1.2

const UPGRADE_SWORDSMAN_ATTACK: StringName = &"swordsman_attack"
const UPGRADE_SWORDSMAN_ARMOR: StringName = &"swordsman_armor"
const UPGRADE_ARCHER_ATTACK: StringName = &"archer_attack"
const UPGRADE_ARCHER_ATTACK_SPEED: StringName = &"archer_attack_speed"
const UPGRADE_ARCHER_RANGE: StringName = &"archer_range"
const UPGRADE_FASTER_GATHERING: StringName = &"faster_gathering"
const UPGRADE_FASTER_UNIT_TRAINING: StringName = &"faster_unit_training"
const UPGRADE_IMPROVED_TOOLS: StringName = &"improved_tools"
const UPGRADE_ENGINEERING: StringName = &"engineering"
const UPGRADE_BALLISTICS: StringName = &"ballistics"

const UPGRADE_HEAVY_CAVALRY_ATTACK: StringName = &"heavy_cavalry_attack"
const UPGRADE_HEAVY_CAVALRY_DEFENSE: StringName = &"heavy_cavalry_defense"
const UPGRADE_LIGHT_CAVALRY_ATTACK: StringName = &"light_cavalry_attack"
const UPGRADE_LIGHT_CAVALRY_DEFENSE: StringName = &"light_cavalry_defense"
const UPGRADE_CAVALRY_ARCHER_ATTACK: StringName = &"cavalry_archer_attack"
const UPGRADE_CAVALRY_ARCHER_DEFENSE: StringName = &"cavalry_archer_defense"

const STABLE_CAVALRY_UNIT_IDS: Array[StringName] = [
	&"heavy_cavalry",
	&"light_cavalry",
	&"cavalry_archer",
]

const BLACKSMITH_UPGRADE_ORDER: Array[StringName] = [
	UPGRADE_SWORDSMAN_ATTACK,
	UPGRADE_SWORDSMAN_ARMOR,
	UPGRADE_ARCHER_ATTACK,
	UPGRADE_ARCHER_ATTACK_SPEED,
	UPGRADE_ARCHER_RANGE,
]

const ACADEMY_UPGRADE_ORDER: Array[StringName] = [
	UPGRADE_FASTER_GATHERING,
	UPGRADE_FASTER_UNIT_TRAINING,
	UPGRADE_IMPROVED_TOOLS,
	UPGRADE_ENGINEERING,
	UPGRADE_BALLISTICS,
]

const ACADEMY_UPGRADE_COSTS: Dictionary = {
	UPGRADE_FASTER_GATHERING: {"gold": 1000, "wood": 700},
	UPGRADE_FASTER_UNIT_TRAINING: {"gold": 1200, "wood": 900},
	UPGRADE_IMPROVED_TOOLS: {"gold": 900, "wood": 700},
	UPGRADE_ENGINEERING: {"gold": 1500, "wood": 1200},
	UPGRADE_BALLISTICS: {"gold": 1800, "wood": 1200},
}

const ACADEMY_UPGRADE_RESEARCH_SECONDS: Dictionary = {
	UPGRADE_FASTER_GATHERING: 60.0,
	UPGRADE_FASTER_UNIT_TRAINING: 75.0,
	UPGRADE_IMPROVED_TOOLS: 60.0,
	UPGRADE_ENGINEERING: 90.0,
	UPGRADE_BALLISTICS: 90.0,
}

const UPGRADE_DISPLAY_NAMES: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: "Swordsman Attack",
	UPGRADE_SWORDSMAN_ARMOR: "Swordsman Armor",
	UPGRADE_ARCHER_ATTACK: "Archer Attack",
	UPGRADE_ARCHER_ATTACK_SPEED: "Archer Attack Speed",
	UPGRADE_ARCHER_RANGE: "Archer Range",
	UPGRADE_FASTER_GATHERING: "Faster Gathering",
	UPGRADE_FASTER_UNIT_TRAINING: "Faster Unit Training",
	UPGRADE_IMPROVED_TOOLS: "Improved Tools",
	UPGRADE_ENGINEERING: "Engineering",
	UPGRADE_BALLISTICS: "Ballistics",
}

const UPGRADE_HOTKEYS: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: "Q",
	UPGRADE_SWORDSMAN_ARMOR: "W",
	UPGRADE_ARCHER_ATTACK: "E",
	UPGRADE_ARCHER_ATTACK_SPEED: "R",
	UPGRADE_ARCHER_RANGE: "T",
	UPGRADE_FASTER_GATHERING: "Q",
	UPGRADE_FASTER_UNIT_TRAINING: "W",
	UPGRADE_IMPROVED_TOOLS: "E",
	UPGRADE_ENGINEERING: "R",
	UPGRADE_BALLISTICS: "T",
}

var _levels: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: 0,
	UPGRADE_SWORDSMAN_ARMOR: 0,
	UPGRADE_ARCHER_ATTACK: 0,
	UPGRADE_ARCHER_ATTACK_SPEED: 0,
	UPGRADE_ARCHER_RANGE: 0,
	UPGRADE_FASTER_GATHERING: 0,
	UPGRADE_FASTER_UNIT_TRAINING: 0,
	UPGRADE_IMPROVED_TOOLS: 0,
	UPGRADE_ENGINEERING: 0,
	UPGRADE_BALLISTICS: 0,
	UPGRADE_HEAVY_CAVALRY_ATTACK: 0,
	UPGRADE_HEAVY_CAVALRY_DEFENSE: 0,
	UPGRADE_LIGHT_CAVALRY_ATTACK: 0,
	UPGRADE_LIGHT_CAVALRY_DEFENSE: 0,
	UPGRADE_CAVALRY_ARCHER_ATTACK: 0,
	UPGRADE_CAVALRY_ARCHER_DEFENSE: 0,
}

var _enemy_levels: Dictionary = {
	UPGRADE_SWORDSMAN_ATTACK: 0,
	UPGRADE_SWORDSMAN_ARMOR: 0,
	UPGRADE_ARCHER_ATTACK: 0,
	UPGRADE_ARCHER_ATTACK_SPEED: 0,
	UPGRADE_ARCHER_RANGE: 0,
	UPGRADE_FASTER_GATHERING: 0,
	UPGRADE_FASTER_UNIT_TRAINING: 0,
	UPGRADE_IMPROVED_TOOLS: 0,
	UPGRADE_ENGINEERING: 0,
	UPGRADE_BALLISTICS: 0,
	UPGRADE_HEAVY_CAVALRY_ATTACK: 0,
	UPGRADE_HEAVY_CAVALRY_DEFENSE: 0,
	UPGRADE_LIGHT_CAVALRY_ATTACK: 0,
	UPGRADE_LIGHT_CAVALRY_DEFENSE: 0,
	UPGRADE_CAVALRY_ARCHER_ATTACK: 0,
	UPGRADE_CAVALRY_ARCHER_DEFENSE: 0,
}

const _STABLE_CAVALRY_UPGRADE_IDS: Array[StringName] = [
	UPGRADE_HEAVY_CAVALRY_ATTACK,
	UPGRADE_HEAVY_CAVALRY_DEFENSE,
	UPGRADE_LIGHT_CAVALRY_ATTACK,
	UPGRADE_LIGHT_CAVALRY_DEFENSE,
	UPGRADE_CAVALRY_ARCHER_ATTACK,
	UPGRADE_CAVALRY_ARCHER_DEFENSE,
]


static func get_cavalry_attack_upgrade_id(cavalry_unit_id: StringName) -> StringName:
	return StringName("%s_attack" % cavalry_unit_id)


static func get_cavalry_defense_upgrade_id(cavalry_unit_id: StringName) -> StringName:
	return StringName("%s_defense" % cavalry_unit_id)


static func is_stable_cavalry_upgrade(upgrade_id: StringName) -> bool:
	return upgrade_id in _STABLE_CAVALRY_UPGRADE_IDS


static func is_cavalry_attack_upgrade(upgrade_id: StringName) -> bool:
	return String(upgrade_id).ends_with("_attack") and is_stable_cavalry_upgrade(upgrade_id)


static func is_cavalry_defense_upgrade(upgrade_id: StringName) -> bool:
	return String(upgrade_id).ends_with("_defense") and is_stable_cavalry_upgrade(upgrade_id)


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


func has_faster_unit_training(for_enemy: bool = false) -> bool:
	if for_enemy:
		return get_enemy_level(UPGRADE_FASTER_UNIT_TRAINING) >= ACADEMY_MAX_LEVEL

	return get_level(UPGRADE_FASTER_UNIT_TRAINING) >= ACADEMY_MAX_LEVEL


func has_improved_tools(for_enemy: bool = false) -> bool:
	if for_enemy:
		return get_enemy_level(UPGRADE_IMPROVED_TOOLS) >= ACADEMY_MAX_LEVEL

	return get_level(UPGRADE_IMPROVED_TOOLS) >= ACADEMY_MAX_LEVEL


func has_engineering(for_enemy: bool = false) -> bool:
	if for_enemy:
		return get_enemy_level(UPGRADE_ENGINEERING) >= ACADEMY_MAX_LEVEL

	return get_level(UPGRADE_ENGINEERING) >= ACADEMY_MAX_LEVEL


func has_ballistics(for_enemy: bool = false) -> bool:
	if for_enemy:
		return get_enemy_level(UPGRADE_BALLISTICS) >= ACADEMY_MAX_LEVEL

	return get_level(UPGRADE_BALLISTICS) >= ACADEMY_MAX_LEVEL


func get_construction_speed_multiplier(for_enemy: bool = false) -> float:
	if has_improved_tools(for_enemy):
		return IMPROVED_TOOLS_CONSTRUCTION_SPEED_MULTIPLIER

	return 1.0


func get_ballistics_damage_multiplier(for_enemy: bool = false) -> float:
	if has_ballistics(for_enemy):
		return BALLISTICS_DAMAGE_MULTIPLIER

	return 1.0


func get_academy_upgrade_research_seconds(upgrade_id: StringName) -> float:
	return float(ACADEMY_UPGRADE_RESEARCH_SECONDS.get(upgrade_id, 60.0))


func get_display_name(upgrade_id: StringName) -> String:
	return String(UPGRADE_DISPLAY_NAMES.get(upgrade_id, upgrade_id))


func get_hotkey_label(upgrade_id: StringName) -> String:
	return String(UPGRADE_HOTKEYS.get(upgrade_id, ""))


func get_next_level_cost(upgrade_id: StringName) -> Dictionary:
	if is_stable_cavalry_upgrade(upgrade_id):
		return _get_stable_level_cost(get_level(upgrade_id))
	return _get_level_cost(get_level(upgrade_id))


func get_enemy_next_level_cost(upgrade_id: StringName) -> Dictionary:
	if is_stable_cavalry_upgrade(upgrade_id):
		return _get_stable_level_cost(get_enemy_level(upgrade_id))
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


func _get_stable_level_cost(level: int) -> Dictionary:
	if level >= MAX_LEVEL:
		return {"wood": 0, "gold": 0}

	return {
		"gold": STABLE_UPGRADE_BASE_GOLD + level * STABLE_UPGRADE_GOLD_PER_LEVEL,
		"wood": STABLE_UPGRADE_BASE_WOOD + level * STABLE_UPGRADE_WOOD_PER_LEVEL,
	}


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
	if upgrade_id == UPGRADE_ENGINEERING:
		call_deferred("_refresh_team_building_engineering", false)
	elif upgrade_id == UPGRADE_IMPROVED_TOOLS:
		call_deferred("_refresh_team_construction_speed", false)


func finish_enemy_academy_research(upgrade_id: StringName) -> void:
	if not is_academy_upgrade(upgrade_id) or is_enemy_academy_max_level(upgrade_id):
		return

	_enemy_levels[upgrade_id] = ACADEMY_MAX_LEVEL
	enemy_upgrade_applied.emit(upgrade_id)
	if upgrade_id == UPGRADE_ENGINEERING:
		call_deferred("_refresh_team_building_engineering", true)
	elif upgrade_id == UPGRADE_IMPROVED_TOOLS:
		call_deferred("_refresh_team_construction_speed", true)


func try_research(upgrade_id: StringName) -> bool:
	if not try_pay_for_research(upgrade_id):
		return false

	finish_research(upgrade_id)
	return true


func apply_player_upgrades_to_unit(unit: Unit) -> void:
	if unit is Swordsman and _is_player_military_unit(unit):
		(unit as Swordsman).apply_blacksmith_upgrades()
	elif unit is Archer and _is_player_military_unit(unit):
		(unit as Archer).apply_blacksmith_upgrades()
	elif _is_player_cavalry_unit(unit):
		_apply_stable_upgrades_to_cavalry(unit)


func apply_enemy_upgrades_to_unit(unit: Unit) -> void:
	if unit is Swordsman and _is_enemy_military_unit(unit):
		(unit as Swordsman).apply_blacksmith_upgrades()
	elif unit is Archer and _is_enemy_military_unit(unit):
		(unit as Archer).apply_blacksmith_upgrades()
	elif _is_enemy_cavalry_unit(unit):
		_apply_stable_upgrades_to_cavalry(unit)


func _apply_stable_upgrades_to_cavalry(unit: Unit) -> void:
	if unit is HeavyCavalry:
		(unit as HeavyCavalry).apply_stable_upgrades()
	elif unit is LightCavalry:
		(unit as LightCavalry).apply_stable_upgrades()
	elif unit is CavalryArcher:
		(unit as CavalryArcher).apply_stable_upgrades()


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


func _is_player_cavalry_unit(unit: Unit) -> bool:
	if not (unit is HeavyCavalry or unit is LightCavalry or unit is CavalryArcher):
		return false
	if TeamVisuals.resolve_team(unit, unit.team_id) != TeamVisuals.PLAYER_TEAM_ID:
		return false
	return true


func _is_enemy_cavalry_unit(unit: Unit) -> bool:
	if not (unit is HeavyCavalry or unit is LightCavalry or unit is CavalryArcher):
		return false
	if TeamVisuals.resolve_team(unit, unit.team_id) == TeamVisuals.PLAYER_TEAM_ID:
		return false
	return true


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


func _refresh_team_building_engineering(for_enemy: bool) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	for node: Node in tree.get_nodes_in_group(&"buildings"):
		if not node is Building:
			continue

		var building: Building = node as Building
		if building.building_state != Building.STATE_COMPLETED:
			continue

		var is_enemy_building: bool = (
			TeamVisuals.resolve_team(building, building.team_id) != TeamVisuals.PLAYER_TEAM_ID
		)
		if is_enemy_building != for_enemy:
			continue

		building.apply_engineering_bonus()


func _refresh_team_construction_speed(for_enemy: bool) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var speed_multiplier: float = get_construction_speed_multiplier(for_enemy)
	if speed_multiplier <= 1.0:
		return

	for node: Node in tree.get_nodes_in_group(&"buildings"):
		if not node is Building:
			continue

		var building: Building = node as Building
		var is_enemy_building: bool = (
			TeamVisuals.resolve_team(building, building.team_id) != TeamVisuals.PLAYER_TEAM_ID
		)
		if is_enemy_building != for_enemy:
			continue

		building.apply_construction_speed_bonus(speed_multiplier)
