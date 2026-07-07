class_name TooltipFormatter
extends RefCounted

## Builds multi-line RTS-style tooltip text from existing game data.

const _BUILD_MANAGER := preload("res://scripts/systems/build_manager.gd")

const UNIT_ROLE_DESCRIPTIONS: Dictionary = {
	&"worker": "Gathers resources and constructs buildings.",
	&"spearman": "Basic melee infantry with reach.",
	&"swordsman": "Basic melee infantry.",
	&"archer": "Ranged damage dealer.",
	&"heavy_cavalry": "Armored heavy mounted melee.",
	&"light_cavalry": "Fast light mounted melee.",
	&"cavalry_archer": "Ranged mounted damage dealer.",
	&"hero": "Powerful leader with abilities.",
	&"enemy_dummy": "Training target.",
	&"neutral_creep": "Neutral hostile unit.",
}

const BUILD_PLACEMENT_NAMES: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_FARM: "Farm",
	_BUILD_MANAGER.PLACEMENT_BARRACKS: "Barracks",
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: "Blacksmith",
	_BUILD_MANAGER.PLACEMENT_STABLE: "Stable",
	_BUILD_MANAGER.PLACEMENT_SHOP: "Shop",
	_BUILD_MANAGER.PLACEMENT_TOWER: "Tower",
	_BUILD_MANAGER.PLACEMENT_HERO_ALTAR: "Hero Altar",
	_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER: "Town Center",
}

const BUILD_PLACEMENT_DESCRIPTIONS: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_FARM: "Provides supply.",
	_BUILD_MANAGER.PLACEMENT_BARRACKS: "Trains Spearmen, Swordsmen, and Archers.",
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: "Unlocks upgrades.",
	_BUILD_MANAGER.PLACEMENT_STABLE: "Trains cavalry units.",
	_BUILD_MANAGER.PLACEMENT_SHOP: "Buys hero items.",
	_BUILD_MANAGER.PLACEMENT_TOWER: "Defensive building.",
	_BUILD_MANAGER.PLACEMENT_HERO_ALTAR: "Trains/revives your Hero.",
	_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER: "Expands your base.",
}

const BUILD_PLACEMENT_REQUIREMENTS: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: ["Command Center Tier 2"],
	_BUILD_MANAGER.PLACEMENT_STABLE: ["Command Center Tier 2", "Blacksmith"],
}

const TRAIN_DESCRIPTIONS: Dictionary = {
	&"worker": "Gathers resources and constructs buildings.",
	&"spearman": "Basic melee infantry with reach.",
	&"swordsman": "Basic melee infantry.",
	&"archer": "Ranged damage dealer.",
	&"heavy_cavalry": "Armored heavy mounted melee.",
	&"light_cavalry": "Fast light mounted melee.",
	&"cavalry_archer": "Ranged mounted damage dealer.",
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
	lines.append(get_placement_display_name(placement_id))

	if costs.gold > 0:
		lines.append("Gold: %d" % costs.gold)
	elif costs.has("gold"):
		lines.append("Gold: 0")

	if costs.wood > 0:
		lines.append("Wood: %d" % costs.wood)
	elif costs.has("wood"):
		lines.append("Wood: 0")

	var build_time: float = get_placement_build_time(placement_id)
	if build_time > 0.0:
		lines.append("Build Time: %s" % _format_seconds(build_time))

	var supply_bonus: int = get_placement_supply_bonus(placement_id)
	if supply_bonus > 0:
		lines.append("Supply: +%d" % supply_bonus)

	var requirements: PackedStringArray = get_placement_requirement_labels(placement_id)
	for requirement: String in requirements:
		lines.append("Requires: %s" % requirement)

	if not blocked_reason.is_empty():
		lines.append(blocked_reason)

	var description: String = String(BUILD_PLACEMENT_DESCRIPTIONS.get(placement_id, ""))
	if not description.is_empty():
		lines.append(description)

	return "\n".join(lines)


static func get_placement_display_name(placement_id: StringName) -> String:
	return String(BUILD_PLACEMENT_NAMES.get(placement_id, placement_id))


static func get_placement_supply_bonus(placement_id: StringName) -> int:
	match placement_id:
		_BUILD_MANAGER.PLACEMENT_FARM:
			return Farm.FOOD_CAP_BONUS
		_:
			return 0


static func get_placement_requirement_labels(placement_id: StringName) -> PackedStringArray:
	var requirements: Variant = BUILD_PLACEMENT_REQUIREMENTS.get(placement_id, [])
	if requirements is PackedStringArray:
		return requirements
	if requirements is Array:
		var labels: PackedStringArray = PackedStringArray()
		for entry: Variant in requirements:
			labels.append(String(entry))
		return labels
	return PackedStringArray()


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


static func format_command_center_tier_upgrade(
	target_tier: int,
	gold_cost: int,
	wood_cost: int,
	upgrade_seconds: float,
	blocked_reason: String = ""
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Upgrade to Tier %d" % target_tier)
	lines.append("Cost:")
	lines.append("%d Gold" % gold_cost)
	lines.append("%d Wood" % wood_cost)
	lines.append("Time:")
	if is_equal_approx(fmod(upgrade_seconds, 1.0), 0.0):
		lines.append("%d seconds" % int(upgrade_seconds))
	else:
		lines.append("%s" % _format_seconds(upgrade_seconds))

	if not blocked_reason.is_empty():
		lines.append(blocked_reason)

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
	_append_ability_stat_lines(lines, ability_id, rank, overrides, hero)

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
	_append_ability_stat_lines(lines, ability_id, next_rank, overrides, hero)

	var mana: int = hero.get_ability_mana_cost_at_rank(ability_id, next_rank)
	lines.append("Mana: %d" % mana)

	var cooldown: float = hero.get_ability_cooldown_at_rank(ability_id, next_rank)
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
		_BUILD_MANAGER.PLACEMENT_STABLE:
			return {
				"gold": _BUILD_MANAGER.STABLE_GOLD_COST,
				"wood": _BUILD_MANAGER.STABLE_WOOD_COST,
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

	if placement_id == _BUILD_MANAGER.PLACEMENT_BLACKSMITH:
		if not TechTree.can_build_blacksmith():
			return TechTree.BLACKSMITH_REQUIRES_TIER_2_MESSAGE

	if placement_id == _BUILD_MANAGER.PLACEMENT_STABLE:
		if not TechTree.can_build_stable():
			return TechTree.STABLE_REQUIRES_TIER_2_AND_BLACKSMITH_MESSAGE

	if ResourceManager.gold < costs.gold and ResourceManager.wood < costs.wood:
		return "Need more gold and wood"
	if ResourceManager.gold < costs.gold:
		return "Need more gold"
	if ResourceManager.wood < costs.wood:
		return "Need more wood"
	return ""


static func get_train_blocked_reason_for_unit(
	train_id: StringName,
	gold_cost: int,
	food_cost: int
) -> String:
	if (
		train_id == Barracks.TRAIN_ID_SWORDSMAN
		or train_id == Barracks.TRAIN_ID_ARCHER
	):
		if not TechTree.can_train_swordsman_or_archer():
			return TechTree.ADVANCED_UNIT_REQUIRES_BLACKSMITH_MESSAGE

	return get_train_blocked_reason(gold_cost, food_cost)


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

	var item: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if item == null:
		return ""

	return HeroItemService.get_purchase_failure_reason(shop, item)


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
	if unit is Spearman:
		return "Spearman"
	if unit is Swordsman:
		return "Swordsman"
	if unit is Archer:
		return "Archer"
	if unit is HeavyCavalry:
		return "Heavy Cavalry"
	if unit is LightCavalry:
		return "Light Cavalry"
	if unit is CavalryArcher:
		return "Cavalry Archer"
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
	if unit is Spearman:
		return String(UNIT_ROLE_DESCRIPTIONS[&"spearman"])
	if unit is Swordsman:
		return String(UNIT_ROLE_DESCRIPTIONS[&"swordsman"])
	if unit is Archer:
		return String(UNIT_ROLE_DESCRIPTIONS[&"archer"])
	if unit is HeavyCavalry:
		return String(UNIT_ROLE_DESCRIPTIONS[&"heavy_cavalry"])
	if unit is LightCavalry:
		return String(UNIT_ROLE_DESCRIPTIONS[&"light_cavalry"])
	if unit is CavalryArcher:
		return String(UNIT_ROLE_DESCRIPTIONS[&"cavalry_archer"])
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
	if unit is Spearman or unit is Swordsman or unit is Archer or unit is LightCavalry or unit is CavalryArcher:
		return Barracks.TRAIN_FOOD_COST
	if unit is HeavyCavalry:
		return Stable.HEAVY_CAVALRY_TRAIN_FOOD_COST
	if unit is Hero:
		return HeroAltar.TRAIN_FOOD_COST
	return 0


static func _append_ability_stat_lines(
	lines: PackedStringArray,
	ability_id: StringName,
	rank: int,
	overrides: Dictionary,
	hero: Hero = null
) -> void:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			var damage: int = (
				hero.get_ability_damage_at_rank(ability_id, rank)
				if hero != null
				else int(HeroAbilityStats.get_stat(ability_id, HeroAbilityStats.STAT_DAMAGE, rank, overrides))
			)
			var radius: float = (
				hero.get_ability_splash_radius_at_rank(ability_id, rank)
				if hero != null
				else float(HeroAbilityStats.get_stat(ability_id, HeroAbilityStats.STAT_SPLASH, rank, overrides))
			)
			lines.append("Damage: %d" % damage)
			lines.append("Splash Radius: %s" % _format_number(radius))
		HeroAbilityProgression.ABILITY_W:
			var duration: float = (
				hero.get_ability_effect_strength_at_rank(ability_id, rank)
				if hero != null
				else float(HeroAbilityStats.get_stat(ability_id, HeroAbilityStats.STAT_EFFECT, rank, overrides))
			)
			lines.append("Duration: %s" % _format_seconds(duration))
		HeroAbilityProgression.ABILITY_E:
			var strike_damage: int = (
				hero.get_ability_damage_at_rank(ability_id, rank)
				if hero != null
				else int(HeroAbilityStats.get_stat(ability_id, HeroAbilityStats.STAT_DAMAGE, rank, overrides))
			)
			lines.append("Damage: %d" % strike_damage)
		HeroAbilityProgression.ABILITY_R:
			var threshold: float = (
				hero.get_ability_effect_strength_at_rank(ability_id, rank)
				if hero != null
				else float(HeroAbilityStats.get_stat(ability_id, HeroAbilityStats.STAT_EFFECT, rank, overrides))
			)
			lines.append("Execute Threshold: %d%% HP" % int(round(threshold * 100.0)))


static func _get_ability_description(ability_id: StringName) -> String:
	return String(ABILITY_DESCRIPTIONS.get(ability_id, ""))


static func _get_shop_item_effect_text(item: HeroItemDefinition) -> String:
	var lines: PackedStringArray = PackedStringArray()

	if item.bonus_attack_damage > 0:
		lines.append("+%d Attack Damage" % item.bonus_attack_damage)
	if item.bonus_max_health > 0:
		lines.append("+%d Max Health" % item.bonus_max_health)
	if item.heal_on_purchase > 0:
		lines.append("+%d Health on Purchase" % item.heal_on_purchase)
	if item.bonus_move_speed > 0.0:
		lines.append("+%d Move Speed" % int(item.bonus_move_speed))
	if item.bonus_max_mana > 0:
		lines.append("+%d Max Mana" % item.bonus_max_mana)
	if item.restore_mana_on_purchase > 0:
		lines.append("+%d Mana on Purchase" % item.restore_mana_on_purchase)
	if item.bonus_ability_power > 0:
		lines.append("+%d Ability Power" % item.bonus_ability_power)
	if item.bonus_cooldown_reduction > 0.0:
		lines.append("+%d%% Cooldown Reduction" % int(round(item.bonus_cooldown_reduction * 100.0)))
	if item.bonus_mana_cost_reduction > 0.0:
		lines.append("+%d%% Mana Cost Reduction" % int(round(item.bonus_mana_cost_reduction * 100.0)))
	if item.bonus_spell_radius > 0.0:
		lines.append("+%s Spell Radius" % _format_number(item.bonus_spell_radius))

	return "\n".join(lines)


static func _format_seconds(value: float) -> String:
	if is_equal_approx(fmod(value, 1.0), 0.0):
		return "%ds" % int(value)
	return "%.1fs" % value


static func _format_number(value: float) -> String:
	if is_equal_approx(fmod(value, 1.0), 0.0):
		return str(int(value))
	return str(value)
