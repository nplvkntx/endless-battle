class_name EnemyEarlyStrategy
extends RefCounted

## Early-game creep-vs-attack decision using the same unit awareness the AI already has.
## Units count as "visible" when within scout range of the enemy rally (no fog cheat).

const SCOUT_RANGE := 55.0
const ATTACK_PATH_DEFENSE_RANGE := 60.0
const LOW_VISIBLE_ARMY_POWER := 140
const ARMY_ADVANTAGE_RATIO := 1.35
const ATTACK_VISIBLE_MIN_RATIO := 1.2
const GREEDY_BUILD_DISTANCE := 26.0
const GREEDY_LOCAL_DEFENSE_RADIUS := 18.0
const GREEDY_MAX_LOCAL_DEFENSE := 1
const HERO_AWAY_FROM_BASE_DISTANCE := 32.0
const UNKNOWN_ARMY_FALLBACK_SECONDS := 420.0

const CREEP_HERO_POWER := 220
const CREEP_MELEE_POWER_PER_HEALTH := 1.0
const CREEP_RANGED_POWER_PER_HEALTH := 0.85
const CREEP_DAMAGE_POWER_MULTIPLIER := 8.0


static func should_attack_early(tree: SceneTree, rally_position: Vector3) -> bool:
	if tree == null or rally_position == Vector3.ZERO:
		return false

	return not _assess_vulnerability(tree, rally_position).get("reasons", []).is_empty()


## Returns whether a planned wave should commit to attack based on army size and visible player power.
static func evaluate_wave_attack_commitment(
	tree: SceneTree,
	rally_position: Vector3,
	wave_units: Array,
	min_non_hero_units: int,
	match_elapsed_seconds: float
) -> Dictionary:
	if tree == null or rally_position == Vector3.ZERO:
		return _build_attack_decision(false, &"invalid_state")

	var non_hero_units: Array = []
	var hero_in_wave: Hero = null
	for unit: Variant in wave_units:
		if unit == null or not is_instance_valid(unit):
			continue

		if unit is Hero:
			hero_in_wave = unit as Hero
		elif _is_enemy_non_hero_combat_unit(unit as Node):
			non_hero_units.append(unit)

	var non_hero_count: int = non_hero_units.size()
	if non_hero_count <= 0:
		return _build_attack_decision(false, &"hero_only")

	if non_hero_count < min_non_hero_units:
		return _build_attack_decision(false, &"army_too_small")

	if hero_in_wave != null and non_hero_count < EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN:
		return _build_attack_decision(false, &"hero_isolated")

	var attack_destination: Vector3 = EnemyArmyCommand.resolve_wave_attack_destination(
		tree,
		rally_position
	)
	var wave_power: int = _estimate_player_or_enemy_power(wave_units)
	var visible_power: int = _estimate_visible_player_defense_power(
		tree,
		rally_position,
		attack_destination
	)

	if visible_power > 0:
		var required_power: int = int(float(visible_power) * ATTACK_VISIBLE_MIN_RATIO)
		if wave_power < required_power:
			return _build_attack_decision(
				false,
				&"outpowered",
				{
					"wave_power": wave_power,
					"visible_power": visible_power,
					"required_power": required_power,
				}
			)

		return _build_attack_decision(
			true,
			&"visible_advantage",
			{
				"wave_power": wave_power,
				"visible_power": visible_power,
				"required_power": required_power,
			}
		)

	if match_elapsed_seconds >= UNKNOWN_ARMY_FALLBACK_SECONDS:
		return _build_attack_decision(
			true,
			&"unknown_army_timeout",
			{"wave_power": wave_power, "non_hero_count": non_hero_count}
		)

	if non_hero_count >= min_non_hero_units:
		return _build_attack_decision(
			true,
			&"unknown_army_ready",
			{"wave_power": wave_power, "non_hero_count": non_hero_count}
		)

	return _build_attack_decision(false, &"unknown_army_not_ready")


static func _build_attack_decision(
	can_attack: bool,
	reason: StringName,
	details: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"can_attack": can_attack,
		"reason": reason,
	}
	result.merge(details, true)
	return result


static func _estimate_visible_player_defense_power(
	tree: SceneTree,
	rally_position: Vector3,
	attack_destination: Vector3
) -> int:
	var rally_visible: Array = _collect_visible_player_military(tree, rally_position)
	var path_visible: Array = _collect_player_military_near(
		tree,
		attack_destination,
		ATTACK_PATH_DEFENSE_RANGE
	)
	var combined: Array = rally_visible.duplicate()
	for unit: Variant in path_visible:
		if unit == null or not is_instance_valid(unit):
			continue

		if combined.has(unit):
			continue

		combined.append(unit)

	return _estimate_player_or_enemy_power(combined)


static func _collect_player_military_near(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> Array:
	var units: Array = []

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
			if distance > search_range:
				continue

			units.append(node)

	return units


static func _is_enemy_non_hero_combat_unit(node: Node) -> bool:
	if not EnemyArmyCommand.is_living_combat_unit(node):
		return false

	return not EnemyArmyCommand.is_hero_unit(node)


static func _estimate_player_or_enemy_power(units: Array) -> int:
	var power: int = 0

	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			continue

		if not unit is Node:
			continue

		if unit is Hero or unit is Swordsman or unit is Archer:
			if CombatTargetValidation.is_enemy_faction(unit as Node):
				if not EnemyArmyCommand.is_living_combat_unit(unit as Node):
					continue
			elif not _is_player_military_unit(unit as Node):
				continue
		else:
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
