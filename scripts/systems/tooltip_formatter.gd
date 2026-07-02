class_name TooltipFormatter
extends RefCounted

## Builds multi-line RTS-style tooltip text from existing game data.

const _BUILD_MANAGER := preload("res://scripts/systems/build_manager.gd")

const UNIT_ROLE_DESCRIPTIONS: Dictionary = {
	&"worker": "Gathers resources and constructs buildings.",
	&"swordsman": "Basic melee infantry.",
	&"archer": "Ranged damage dealer.",
	&"hero": "Powerful leader with abilities.",
	&"enemy_dummy": "Training target.",
	&"neutral_creep": "Neutral hostile unit.",
}

const BUILD_PLACEMENT_NAMES: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_FARM: "Build Farm",
	_BUILD_MANAGER.PLACEMENT_BARRACKS: "Build Barracks",
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: "Build Blacksmith",
	_BUILD_MANAGER.PLACEMENT_SHOP: "Build Shop",
	_BUILD_MANAGER.PLACEMENT_TOWER: "Build Tower",
	_BUILD_MANAGER.PLACEMENT_HERO_ALTAR: "Build Hero Altar",
	_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER: "Build Town Center",
}

const BUILD_PLACEMENT_DESCRIPTIONS: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_FARM: "Increases food supply.",
	_BUILD_MANAGER.PLACEMENT_BARRACKS: "Trains infantry units.",
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: "Researches military upgrades.",
	_BUILD_MANAGER.PLACEMENT_SHOP: "Sells items to nearby heroes.",
	_BUILD_MANAGER.PLACEMENT_TOWER: "Defensive structure.",
	_BUILD_MANAGER.PLACEMENT_HERO_ALTAR: "Trains a hero unit.",
	_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER: "Expands your base.",
}

const TRAIN_DESCRIPTIONS: Dictionary = {
	&"worker": "Gathers resources and constructs buildings.",
	&"swordsman": "Basic melee infantry.",
	&"archer": "Ranged damage dealer.",
	&"hero": "Powerful leader with abilities.",
}

const ABILITY_DESCRIPTIONS: Dictionary = {
	HeroAbilityProgression.ABILITY_Q: "Slams the ground, damaging nearby enemies.",
	HeroAbilityProgression.ABILITY_W: "Grants temporary invulnerability.",
	HeroAbilityProgression.ABILITY_E: "A powerful melee strike.",
	HeroAbilityProgression.ABILITY_R: "Executes enemies below a health threshold.",
}

const UPGRADE_DESCRIPTIONS: Dictionary = {
	UpgradeManager.UPGRADE_SWORDSMAN_ATTACK: "Increases swordsman attack damage.",
	UpgradeManager.UPGRADE_SWORDSMAN_ARMOR: "Increases swordsman armor.",
	UpgradeManager.UPGRADE_ARCHER_ATTACK: "Increases archer attack damage.",
	UpgradeManager.UPGRADE_ARCHER_ATTACK_SPEED: "Increases archer attack speed.",
	UpgradeManager.UPGRADE_ARCHER_RANGE: "Increases archer attack range.",
}


static func format_unit(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""

	if node is Unit:
		return _format_unit_stats(node as Unit)

	if node is Building:
		return _format_building_stats(node as Building)

	return ""


static func format_build_placement(placement_id: StringName, blocked_reason: String = "") -> String:
	var costs: Dictionary = get_placement_costs(placement_id)
	if costs.is_empty():
		return ""

	var lines: PackedStringArray = PackedStringArray()
	lines.append(String(BUILD_PLACEMENT_NAMES.get(placement_id, placement_id)))

	if costs.gold > 0:
		lines.append("Gold: %d" % costs.gold)
	if costs.wood > 0:
		lines.append("Wood: %d" % costs.wood)

	var build_time: float = get_placement_build_time(placement_id)
	if build_time > 0.0:
		lines.append("Time: %s" % _format_seconds(build_time))

	if not blocked_reason.is_empty():
		lines.append(blocked_reason)

	var description: String = String(BUILD_PLACEMENT_DESCRIPTIONS.get(placement_id, ""))
	if not description.is_empty():
		lines.append(description)

	return "\n".join(lines)


static func format_train_command(
	unit_name: String,
	gold_cost: int,
	wood_cost: int,
	food_cost: int,
	train_seconds: float,
	train_id: StringName,
	blocked_reason: String = ""
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Train %s" % unit_name)

	if gold_cost > 0:
		lines.append("Gold: %d" % gold_cost)
	if wood_cost > 0:
		lines.append("Wood: %d" % wood_cost)
	if food_cost > 0:
		lines.append("Food: %d" % food_cost)

	if train_seconds > 0.0:
		lines.append("Time: %s" % _format_seconds(train_seconds))

	if not blocked_reason.is_empty():
		lines.append(blocked_reason)

	var description: String = String(TRAIN_DESCRIPTIONS.get(train_id, ""))
	if not description.is_empty():
		lines.append(description)

	return "\n".join(lines)


static func format_upgrade_research(
	upgrade_id: StringName,
	blocked_reason: String = "",
	is_researching: bool = false
) -> String:
	var display_name: String = UpgradeManager.get_display_name(upgrade_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Research %s" % display_name)

	var level: int = UpgradeManager.get_level(upgrade_id)
	if UpgradeManager.is_max_level(upgrade_id):
		lines.append("Max rank reached")
	else:
		var cost: Dictionary = UpgradeManager.get_next_level_cost(upgrade_id)
		if cost.gold > 0:
			lines.append("Gold: %d" % cost.gold)
		if cost.wood > 0:
			lines.append("Wood: %d" % cost.wood)
		lines.append("Time: %s" % _format_seconds(Blacksmith.RESEARCH_SECONDS))
		lines.append("Rank: %d/%d" % [level, UpgradeManager.MAX_LEVEL])

	if is_researching:
		lines.append("Research in progress")
	elif not blocked_reason.is_empty():
		lines.append(blocked_reason)

	var description: String = String(UPGRADE_DESCRIPTIONS.get(upgrade_id, ""))
	if not description.is_empty():
		lines.append(description)

	return "\n".join(lines)


static func format_inventory_item(item: HeroItemDefinition) -> String:
	if item == null:
		return "Empty inventory slot"

	var lines: PackedStringArray = PackedStringArray()
	lines.append(item.display_name)

	var effect: String = _get_shop_item_effect_text(item)
	if not effect.is_empty():
		lines.append(effect)

	lines.append("Right-click to sell")
	return "\n".join(lines)


static func format_shop_item(item_id: StringName, blocked_reason: String = "") -> String:
	var item: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if item == null:
		return ""

	var lines: PackedStringArray = PackedStringArray()
	lines.append(item.display_name)
	lines.append("Gold: %d" % item.gold_cost)

	var effect: String = _get_shop_item_effect_text(item)
	if not effect.is_empty():
		lines.append(effect)

	if not blocked_reason.is_empty():
		lines.append(blocked_reason)

	return "\n".join(lines)


static func format_ability_cast(hero: Hero, ability_id: StringName, slot_label: String) -> String:
	var display_name: String = HeroAbilityStats.get_display_name(ability_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s (%s)" % [display_name, slot_label])

	if hero == null or not is_instance_valid(hero):
		lines.append(_get_ability_description(ability_id))
		return "\n".join(lines)

	var rank: int = hero.get_ability_rank(ability_id)
	var max_rank: int = hero.get_ability_max_rank(ability_id)
	lines.append("Rank: %d/%d" % [rank, max_rank])

	if rank <= 0:
		if hero.ability_progression != null:
			var learn_reason: String = hero.ability_progression.get_learn_blocked_reason(
				hero.level, hero.ability_points, ability_id
			)
			if not learn_reason.is_empty():
				lines.append(learn_reason)
		lines.append(_get_ability_description(ability_id))
		return "\n".join(lines)

	var overrides: Dictionary = hero.get_ability_base_overrides(ability_id)
	_append_ability_stat_lines(lines, ability_id, rank, overrides)

	var mana: int = hero.get_ability_mana_cost(ability_id)
	lines.append("Mana: %d" % mana)

	var cooldown: float = hero.get_ability_cooldown(ability_id)
	lines.append("Cooldown: %s" % _format_seconds(cooldown))

	var cast_reason: String = get_ability_cast_blocked_reason(hero, ability_id)
	if not cast_reason.is_empty():
		lines.append(cast_reason)

	lines.append(_get_ability_description(ability_id))
	return "\n".join(lines)


static func format_ability_upgrade(hero: Hero, ability_id: StringName, slot_label: String) -> String:
	var display_name: String = HeroAbilityStats.get_display_name(ability_id)
	if hero == null or not is_instance_valid(hero):
		return "Upgrade %s (%s)" % [display_name, slot_label]

	var current_rank: int = hero.get_ability_rank(ability_id)
	var max_rank: int = hero.get_ability_max_rank(ability_id)
	if current_rank >= max_rank:
		return "%s (%s)\nAbility max rank reached" % [display_name, slot_label]

	var next_rank: int = maxi(current_rank, 0) + 1
	var overrides: Dictionary = hero.get_ability_base_overrides(ability_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Upgrade %s (%s)" % [display_name, slot_label])
	lines.append("Next rank: %d/%d" % [next_rank, max_rank])
	_append_ability_stat_lines(lines, ability_id, next_rank, overrides)

	var mana: int = int(
		HeroAbilityStats.get_stat(ability_id, HeroAbilityStats.STAT_MANA, next_rank, overrides)
	)
	lines.append("Mana: %d" % mana)

	var cooldown: float = float(
		HeroAbilityStats.get_stat(ability_id, HeroAbilityStats.STAT_COOLDOWN, next_rank, overrides)
	)
	lines.append("Cooldown: %s" % _format_seconds(cooldown))

	if not hero.can_learn_ability(ability_id) and hero.ability_progression != null:
		lines.append(
			hero.ability_progression.get_learn_blocked_reason(
				hero.level, hero.ability_points, ability_id
			)
		)

	lines.append(_get_ability_description(ability_id))
	return "\n".join(lines)


static func get_placement_costs(placement_id: StringName) -> Dictionary:
	match placement_id:
		_BUILD_MANAGER.PLACEMENT_FARM:
			return {
				"gold": _BUILD_MANAGER.FARM_GOLD_COST,
				"wood": _BUILD_MANAGER.FARM_WOOD_COST,
			}
		_BUILD_MANAGER.PLACEMENT_BARRACKS:
			return {
				"gold": _BUILD_MANAGER.BARRACKS_GOLD_COST,
				"wood": _BUILD_MANAGER.BARRACKS_WOOD_COST,
			}
		_BUILD_MANAGER.PLACEMENT_BLACKSMITH:
			return {
				"gold": _BUILD_MANAGER.BLACKSMITH_GOLD_COST,
				"wood": _BUILD_MANAGER.BLACKSMITH_WOOD_COST,
			}
		_BUILD_MANAGER.PLACEMENT_SHOP:
			return {
				"gold": _BUILD_MANAGER.SHOP_GOLD_COST,
				"wood": _BUILD_MANAGER.SHOP_WOOD_COST,
			}
		_BUILD_MANAGER.PLACEMENT_TOWER:
			return {
				"gold": _BUILD_MANAGER.TOWER_GOLD_COST,
				"wood": _BUILD_MANAGER.TOWER_WOOD_COST,
			}
		_BUILD_MANAGER.PLACEMENT_HERO_ALTAR:
			return {
				"gold": _BUILD_MANAGER.HERO_ALTAR_GOLD_COST,
				"wood": _BUILD_MANAGER.HERO_ALTAR_WOOD_COST,
			}
		_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER:
			return {
				"gold": _BUILD_MANAGER.COMMAND_CENTER_GOLD_COST,
				"wood": _BUILD_MANAGER.COMMAND_CENTER_WOOD_COST,
			}
		_:
			return {}


static func get_placement_build_time(placement_id: StringName, worker_count: int = 1) -> float:
	if placement_id == _BUILD_MANAGER.PLACEMENT_SHOP:
		if worker_count >= 3:
			return _BUILD_MANAGER.SHOP_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS
		if worker_count == 2:
			return _BUILD_MANAGER.SHOP_CONSTRUCTION_DURATION_TWO_WORKERS
		return _BUILD_MANAGER.SHOP_CONSTRUCTION_DURATION_ONE_WORKER

	if worker_count >= 3:
		return _BUILD_MANAGER.CONSTRUCTION_DURATION_THREE_PLUS_WORKERS
	if worker_count == 2:
		return _BUILD_MANAGER.CONSTRUCTION_DURATION_TWO_WORKERS
	return _BUILD_MANAGER.CONSTRUCTION_DURATION_ONE_WORKER


static func get_build_blocked_reason(placement_id: StringName) -> String:
	var costs: Dictionary = get_placement_costs(placement_id)
	if costs.is_empty():
		return ""

	if ResourceManager.gold < costs.gold and ResourceManager.wood < costs.wood:
		return "Need more gold and wood"
	if ResourceManager.gold < costs.gold:
		return "Need more gold"
	if ResourceManager.wood < costs.wood:
		return "Need more wood"
	return ""


static func get_train_blocked_reason(gold_cost: int, food_cost: int) -> String:
	if not ResourceManager.can_afford_worker_training(gold_cost, food_cost):
		return ResourceManager.get_training_failure_message(gold_cost, food_cost)
	return ""


static func get_upgrade_blocked_reason(upgrade_id: StringName, is_researching: bool) -> String:
	if is_researching:
		return "Research in progress"
	if UpgradeManager.is_max_level(upgrade_id):
		return "Max rank reached"

	var cost: Dictionary = UpgradeManager.get_next_level_cost(upgrade_id)
	if ResourceManager.gold < cost.gold and ResourceManager.wood < cost.wood:
		return "Need more gold and wood"
	if ResourceManager.gold < cost.gold:
		return "Need more gold"
	if ResourceManager.wood < cost.wood:
		return "Need more wood"
	return ""


static func get_shop_item_blocked_reason(shop: Shop, item_id: StringName) -> String:
	if shop == null or not is_instance_valid(shop):
		return ""

	if shop.get_nearby_shop_hero() == null:
		return "Move hero near shop"

	var item: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if item == null:
		return ""

	if ResourceManager.gold < item.gold_cost:
		return "Need more gold"
	return ""


static func get_hero_train_blocked_reason(hero_altar: HeroAltar) -> String:
	if hero_altar == null or not is_instance_valid(hero_altar):
		return ""

	if hero_altar.building_state != Building.STATE_COMPLETED:
		return "Building under construction"

	if hero_altar.is_training_hero():
		return "Already training hero"

	if hero_altar.has_living_owner_hero(false):
		return "Hero already exists"

	return get_train_blocked_reason(HeroAltar.TRAIN_GOLD_COST, HeroAltar.TRAIN_FOOD_COST)


static func get_ability_cast_blocked_reason(hero: Hero, ability_id: StringName) -> String:
	if hero == null or not is_instance_valid(hero):
		return ""

	if not hero.is_ability_unlocked(ability_id):
		return "Ability not learned"

	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			if hero.get_ground_slam_cooldown_remaining() > 0.0:
				return "On cooldown"
			if hero.current_mana < hero.get_ground_slam_mana_cost():
				return "Not enough mana"
		HeroAbilityProgression.ABILITY_W:
			if hero.get_divine_protection_cooldown_remaining() > 0.0:
				return "On cooldown"
			if hero.is_divine_protection_active():
				return "Already active"
			if hero.current_mana < hero.get_divine_protection_mana_cost():
				return "Not enough mana"
		HeroAbilityProgression.ABILITY_E:
			if hero.get_power_strike_cooldown_remaining() > 0.0:
				return "On cooldown"
			if hero.current_mana < hero.get_power_strike_mana_cost():
				return "Not enough mana"
		HeroAbilityProgression.ABILITY_R:
			if hero.get_execute_cooldown_remaining() > 0.0:
				return "On cooldown"
			if hero.current_mana < hero.get_execute_mana_cost():
				return "Not enough mana"

	return ""


static func _format_unit_stats(unit: Unit) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_get_unit_display_name(unit))

	var health_component: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	if health_component != null:
		lines.append(
			"HP: %d / %d" % [health_component.current_health, health_component.max_health]
		)

	if "attack_damage" in unit:
		lines.append("Damage: %s" % str(unit.get("attack_damage")))

	if "armor" in unit:
		var armor_value: int = int(unit.get("armor"))
		if armor_value > 0:
			lines.append("Armor: %d" % armor_value)

	if "attack_range" in unit:
		var attack_range: float = float(unit.get("attack_range"))
		if attack_range > 2.5:
			lines.append("Range: %s" % _format_number(attack_range))

	if "attack_cooldown" in unit:
		var attack_cooldown: float = float(unit.get("attack_cooldown"))
		if attack_cooldown > 0.0:
			lines.append("Attack Speed: %s" % _format_seconds(attack_cooldown))

	if unit.move_speed > 0.0:
		lines.append("Move Speed: %s" % _format_number(snapped(unit.move_speed, 0.1)))

	var food_cost: int = _get_unit_food_cost(unit)
	if food_cost > 0:
		lines.append("Food: %d" % food_cost)

	var role: String = _get_unit_role_description(unit)
	if not role.is_empty():
		lines.append("Role: %s" % role)

	return "\n".join(lines)


static func _format_building_stats(building: Building) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_get_building_display_name(building))

	var health_component: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
	if health_component != null:
		lines.append(
			"HP: %d / %d" % [health_component.current_health, health_component.max_health]
		)

	if building.is_being_constructed():
		lines.append("Status: Under construction")

	return "\n".join(lines)


static func _get_unit_display_name(unit: Unit) -> String:
	if unit is Worker:
		return "Worker"
	if unit is Swordsman:
		return "Swordsman"
	if unit is Archer:
		return "Archer"
	if unit is Hero:
		return "Hero"
	if unit is NeutralCreep:
		return "Neutral Creep"
	if unit is EnemyDummy:
		return "Enemy Dummy"
	return unit.name


static func _get_building_display_name(building: Building) -> String:
	if building is CommandCenter:
		return "Town Center"
	if building is Barracks:
		return "Barracks"
	if building is Blacksmith:
		return "Blacksmith"
	if building is Shop:
		return "Shop"
	if building is HeroAltar:
		return "Hero Altar"
	if building is Farm:
		return "Farm"
	if building is Tower:
		return "Tower"
	return building.name


static func _get_unit_role_description(unit: Unit) -> String:
	if unit is Worker:
		return String(UNIT_ROLE_DESCRIPTIONS[&"worker"])
	if unit is Swordsman:
		return String(UNIT_ROLE_DESCRIPTIONS[&"swordsman"])
	if unit is Archer:
		return String(UNIT_ROLE_DESCRIPTIONS[&"archer"])
	if unit is Hero:
		return String(UNIT_ROLE_DESCRIPTIONS[&"hero"])
	if unit is NeutralCreep:
		return String(UNIT_ROLE_DESCRIPTIONS[&"neutral_creep"])
	if unit is EnemyDummy:
		return String(UNIT_ROLE_DESCRIPTIONS[&"enemy_dummy"])
	return ""


static func _get_unit_food_cost(unit: Unit) -> int:
	if unit is Worker:
		return CommandCenter.TRAIN_FOOD_COST
	if unit is Swordsman or unit is Archer:
		return Barracks.TRAIN_FOOD_COST
	if unit is Hero:
		return HeroAltar.TRAIN_FOOD_COST
	return 0


static func _append_ability_stat_lines(
	lines: PackedStringArray,
	ability_id: StringName,
	rank: int,
	overrides: Dictionary
) -> void:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			lines.append(
				"Damage: %d" % int(
					HeroAbilityStats.get_stat(
						ability_id, HeroAbilityStats.STAT_DAMAGE, rank, overrides
					)
				)
			)
			lines.append(
				"Splash Radius: %s" % _format_number(
					float(
						HeroAbilityStats.get_stat(
							ability_id, HeroAbilityStats.STAT_SPLASH, rank, overrides
						)
					)
				)
			)
		HeroAbilityProgression.ABILITY_W:
			lines.append(
				"Duration: %s" % _format_seconds(
					float(
						HeroAbilityStats.get_stat(
							ability_id, HeroAbilityStats.STAT_EFFECT, rank, overrides
						)
					)
				)
			)
		HeroAbilityProgression.ABILITY_E:
			lines.append(
				"Damage: %d" % int(
					HeroAbilityStats.get_stat(
						ability_id, HeroAbilityStats.STAT_DAMAGE, rank, overrides
					)
				)
			)
		HeroAbilityProgression.ABILITY_R:
			var threshold: float = float(
				HeroAbilityStats.get_stat(
					ability_id, HeroAbilityStats.STAT_EFFECT, rank, overrides
				)
			)
			lines.append("Execute Threshold: %d%% HP" % int(round(threshold * 100.0)))


static func _get_ability_description(ability_id: StringName) -> String:
	return String(ABILITY_DESCRIPTIONS.get(ability_id, ""))


static func _get_shop_item_effect_text(item: HeroItemDefinition) -> String:
	if item.bonus_attack_damage > 0:
		return "+%d Attack Damage" % item.bonus_attack_damage
	if item.bonus_max_health > 0:
		return "+%d Max Health" % item.bonus_max_health
	if item.bonus_move_speed > 0.0:
		return "+%d Move Speed" % int(item.bonus_move_speed)
	if item.bonus_max_mana > 0:
		return "+%d Max Mana" % item.bonus_max_mana
	return ""


static func _format_seconds(value: float) -> String:
	if is_equal_approx(fmod(value, 1.0), 0.0):
		return "%ds" % int(value)
	return "%.1fs" % value


static func _format_number(value: float) -> String:
	if is_equal_approx(fmod(value, 1.0), 0.0):
		return str(int(value))
	return str(value)
