class_name EnemyArmyForceMath
extends RefCounted

## Pure squad strength / military-power scoring extracted from EnemyArmyCommand.
## One responsibility: order-agnostic force math for a given unit list or unit type.
## Deterministic for the same unit property inputs. Never issues orders, never owns
## AIPlayerState / missions / queues, never reads scene trees or EAC static state.
## Not an autoload — call static methods; EAC keeps thin facade wrappers.

const ENEMY_COMBAT_GROUP := &"enemy_combat_units"

const STRENGTH_SPEARMAN := 1.0
const STRENGTH_SWORDSMAN := 1.2
const STRENGTH_ARCHER := 1.2
const STRENGTH_LIGHT_CAVALRY := 1.6
const STRENGTH_HEAVY_CAVALRY := 2.2
const STRENGTH_CAVALRY_ARCHER := 1.8
const STRENGTH_CANNON := 2.0
const STRENGTH_HERO_BASE := 3.0
const STRENGTH_HERO_PER_LEVEL := 0.5

const DEFENSE_POWER_HERO_BASE := 220
const DEFENSE_POWER_MELEE_HEALTH := 1.0
const DEFENSE_POWER_RANGED_HEALTH := 0.85
const DEFENSE_POWER_DAMAGE_MULTIPLIER := 8.0


static func is_combat_unit(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	return (
		node is Spearman
		or node is Swordsman
		or node is Archer
		or node is HeavyCavalry
		or node is LightCavalry
		or node is CavalryArcher
		or node is Cannon
		or node is Hero
	)


static func has_positive_health(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if not node is Node:
		return false

	var health_component: HealthComponent = (node as Node).get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


## Same living-enemy-combat filter historically used by strength/power sums.
static func is_living_combat_unit(node) -> bool:
	if not NodeSafety.is_alive_node(node):
		return false

	if not is_combat_unit(node):
		return false

	if not node.is_in_group(ENEMY_COMBAT_GROUP):
		return false

	return has_positive_health(node)


static func get_health_ratio(node) -> float:
	if not NodeSafety.is_alive_node(node):
		return 0.0

	if not node is Node:
		return 0.0

	var health_component: HealthComponent = (node as Node).get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component == null or health_component.max_health <= 0:
		return 1.0

	return float(health_component.current_health) / float(health_component.max_health)


static func get_unit_type_strength_weight(unit) -> float:
	if unit == null or not is_instance_valid(unit):
		return 0.0

	if unit is Hero:
		var level: int = int(unit.get("level")) if "level" in unit else 1
		return STRENGTH_HERO_BASE + float(level) * STRENGTH_HERO_PER_LEVEL

	if unit is Spearman:
		return STRENGTH_SPEARMAN
	if unit is Swordsman:
		return STRENGTH_SWORDSMAN
	if unit is Archer:
		return STRENGTH_ARCHER
	if unit is LightCavalry:
		return STRENGTH_LIGHT_CAVALRY
	if unit is HeavyCavalry:
		return STRENGTH_HEAVY_CAVALRY
	if unit is CavalryArcher:
		return STRENGTH_CAVALRY_ARCHER
	if unit is Cannon:
		return STRENGTH_CANNON

	return 1.0


## True for any living combatant that can contribute fighting power.
## Unlike `is_living_combat_unit`, this does NOT require the enemy roster group —
## player armies passed into strength comparisons must score correctly.
static func is_strength_eligible_unit(unit) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	if unit is Worker or unit is Building or unit is NeutralCreep:
		return false
	if not is_combat_unit(unit as Node):
		return false
	return has_positive_health(unit as Node)


static func estimate_combat_strength(units: Array) -> float:
	var strength: float = 0.0

	for unit: Variant in NodeSafety.clean_node_array(units):
		if not is_strength_eligible_unit(unit):
			continue

		var base_weight: float = get_unit_type_strength_weight(unit as Node)
		var health_ratio: float = get_health_ratio(unit as Node)
		strength += base_weight * health_ratio * 100.0

	return strength


static func estimate_military_power(units: Array) -> int:
	var power: int = 0

	for unit: Variant in units:
		if not is_strength_eligible_unit(unit):
			continue

		var health_component: HealthComponent = (unit as Node).get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		var current_health: int = (
			health_component.current_health
			if health_component != null
			else 0
		)

		if unit is Hero:
			power += DEFENSE_POWER_HERO_BASE + current_health
			continue

		var damage: int = (
			int((unit as Object).get("attack_damage"))
			if "attack_damage" in unit
			else 0
		)
		if unit is Archer or unit is CavalryArcher or unit is Cannon:
			power += int(float(current_health) * DEFENSE_POWER_RANGED_HEALTH)
		else:
			power += int(float(current_health) * DEFENSE_POWER_MELEE_HEALTH)
		power += damage * int(DEFENSE_POWER_DAMAGE_MULTIPLIER)

	return power
