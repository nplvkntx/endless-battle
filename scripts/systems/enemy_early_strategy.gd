class_name EnemyEarlyStrategy
extends RefCounted

## Early-game creep-vs-attack decision using the same unit awareness the AI already has.
## Units count as "visible" when within scout range of the enemy rally (no fog cheat).

const SCOUT_RANGE := 55.0
const LOW_VISIBLE_ARMY_POWER := 140
const ARMY_ADVANTAGE_RATIO := 1.35
const GREEDY_BUILD_DISTANCE := 26.0
const GREEDY_LOCAL_DEFENSE_RADIUS := 18.0
const GREEDY_MAX_LOCAL_DEFENSE := 1
const HERO_AWAY_FROM_BASE_DISTANCE := 32.0

const CREEP_HERO_POWER := 220
const CREEP_MELEE_POWER_PER_HEALTH := 1.0
const CREEP_RANGED_POWER_PER_HEALTH := 0.85
const CREEP_DAMAGE_POWER_MULTIPLIER := 8.0


static func should_attack_early(tree: SceneTree, rally_position: Vector3) -> bool:
	if tree == null or rally_position == Vector3.ZERO:
		return false

	return not _assess_vulnerability(tree, rally_position).get("reasons", []).is_empty()


static func _assess_vulnerability(tree: SceneTree, rally_position: Vector3) -> Dictionary:
	var reasons: Array[StringName] = []
	var visible_units: Array = _collect_visible_player_military(tree, rally_position)
	var visible_power: int = _estimate_army_power(visible_units)
	var enemy_power: int = _estimate_army_power(
		EnemyArmyCommand.collect_living_combat_units(tree)
	)

	if visible_power > 0 and visible_power <= LOW_VISIBLE_ARMY_POWER:
		reasons.append(&"low_visible_army")

	if (
		visible_power > 0
		and float(enemy_power) >= float(visible_power) * ARMY_ADVANTAGE_RATIO
	):
		reasons.append(&"army_advantage")

	if _is_player_expanding_greedily(tree):
		reasons.append(&"greedy_expansion")

	if _is_detectable_player_hero_away_from_base(tree, rally_position):
		reasons.append(&"hero_away")

	return {
		"vulnerable": not reasons.is_empty(),
		"reasons": reasons,
		"visible_power": visible_power,
		"enemy_power": enemy_power,
	}


static func _collect_visible_player_military(tree: SceneTree, rally_position: Vector3) -> Array:
	var units: Array = []

	for group_name: StringName in [EnemyArmyCommand.UNITS_GROUP, EnemyArmyCommand.HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not _is_player_military_unit(node):
				continue

			if not node is Node3D:
				continue

			var distance: float = EnemyArmyCommand.horizontal_distance(
				rally_position,
				(node as Node3D).global_position
			)
			if distance > SCOUT_RANGE:
				continue

			units.append(node)

	return units


static func _is_player_military_unit(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if CombatTargetValidation.is_enemy_faction(node):
		return false

	if not (node is Swordsman or node is Archer or node is Hero):
		return false

	if node is Worker:
		return false

	return CombatTargetValidation.get_target_current_health(node) > 0


static func _estimate_army_power(units: Array) -> int:
	var power: int = 0

	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			continue

		if not EnemyArmyCommand.is_living_combat_unit(unit as Node):
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
			power += CREEP_HERO_POWER + current_health
			continue

		var damage: int = int((unit as Object).get("attack_damage")) if "attack_damage" in unit else 0
		if unit is Archer:
			power += int(float(current_health) * CREEP_RANGED_POWER_PER_HEALTH)
		else:
			power += int(float(current_health) * CREEP_MELEE_POWER_PER_HEALTH)
		power += damage * int(CREEP_DAMAGE_POWER_MULTIPLIER)

	return power


static func _is_player_expanding_greedily(tree: SceneTree) -> bool:
	var command_center: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	if command_center == null:
		return false

	var command_center_position: Vector3 = command_center.global_position

	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.BUILDINGS_GROUP):
		if not node is Building:
			continue

		if node is CommandCenter:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		var building: Node3D = node as Node3D
		var distance_from_base: float = EnemyArmyCommand.horizontal_distance(
			building.global_position,
			command_center_position
		)
		if distance_from_base < GREEDY_BUILD_DISTANCE:
			continue

		if (
			_count_player_military_near(
				tree,
				building.global_position,
				GREEDY_LOCAL_DEFENSE_RADIUS
			) <= GREEDY_MAX_LOCAL_DEFENSE
		):
			return true

	return false


static func _is_detectable_player_hero_away_from_base(
	tree: SceneTree,
	rally_position: Vector3
) -> bool:
	var command_center: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	if command_center == null:
		return false

	var player_hero: Hero = _find_living_player_hero(tree)
	if player_hero == null:
		return false

	if (
		EnemyArmyCommand.horizontal_distance(
			rally_position,
			player_hero.global_position
		) > SCOUT_RANGE
	):
		return false

	return (
		EnemyArmyCommand.horizontal_distance(
			player_hero.global_position,
			command_center.global_position
		) >= HERO_AWAY_FROM_BASE_DISTANCE
	)


static func _find_living_player_hero(tree: SceneTree) -> Hero:
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.HEROES_GROUP):
		if not node is Hero:
			continue

		if CombatTargetValidation.is_enemy_faction(node):
			continue

		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue

		return node as Hero

	return null


static func _count_player_military_near(
	tree: SceneTree,
	position: Vector3,
	radius: float
) -> int:
	var count: int = 0

	for group_name: StringName in [EnemyArmyCommand.UNITS_GROUP, EnemyArmyCommand.HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not _is_player_military_unit(node):
				continue

			if not node is Node3D:
				continue

			var distance: float = EnemyArmyCommand.horizontal_distance(
				position,
				(node as Node3D).global_position
			)
			if distance <= radius:
				count += 1

	return count


static func _is_living_building(building: Building) -> bool:
	if building == null or not is_instance_valid(building):
		return false

	if building.is_queued_for_deletion():
		return false

	var health_component: HealthComponent = building.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true
