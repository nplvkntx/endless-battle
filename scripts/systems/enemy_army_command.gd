class_name EnemyArmyCommand
extends RefCounted

## Shared enemy army command helpers. Registers combat units and issues group orders.

const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMIES_GROUP := &"enemies"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const ENEMY_WORKERS_GROUP := &"enemy_workers"
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const BUILDINGS_GROUP := &"buildings"
const UNITS_GROUP := &"units"
const HEROES_GROUP := &"heroes"

const ARMY_RALLY_OFFSET := Vector3(-2.0, -0.5, 3.0)
const BASE_THREAT_DETECTION_RANGE := 55.0
const APPROACH_DETECTION_RANGE := 68.0
const WORKER_THREAT_RANGE := 30.0
const BUILDING_THREAT_RANGE := 22.0
const FORMATION_SPACING := 2.0
const RANGED_ROW_DEPTH_MULTIPLIER := 1.5
const HERO_ROW_DEPTH_MULTIPLIER := 1.25

const MIN_NON_HERO_FOR_HERO_JOIN := 3
const MIN_ARMY_UNITS_TO_CONTINUE_ATTACK := 3
const HERO_MAX_DISTANCE_FROM_ARMY := 16.0
const HERO_RETREAT_HP_RATIO := 0.30
const HERO_DEFENSE_CRITICAL_RETREAT_HP_RATIO := 0.20
const HERO_WAVE_JOIN_HP_RATIO := 0.60
const HERO_DEFENSIVE_ABILITY_HP_RATIO := 0.40
const DEFENSE_GATHER_MAX_DISTANCE := 42.0
const DEFENSE_HERO_EXTRA_GATHER_DISTANCE := 14.0
const DEFENSE_THREAT_POWER_RANGE := 34.0
const DEFENSE_HOLD_FORWARD_DISTANCE := 10.0
const DEFENSE_POWER_HERO_BASE := 220
const DEFENSE_POWER_MELEE_HEALTH := 1.0
const DEFENSE_POWER_RANGED_HEALTH := 0.85
const DEFENSE_POWER_DAMAGE_MULTIPLIER := 8.0
const HERO_AOE_PLAYER_COUNT := 3
const HERO_AOE_CHECK_RANGE := 10.0
const HERO_POWER_STRIKE_SEARCH_RANGE := 14.0
const HERO_EXECUTE_SEARCH_RANGE := 14.0

const WAVE_1_MIN_NON_HERO_UNITS := 4
const WAVE_2_MIN_NON_HERO_UNITS := 8
const WAVE_3_MIN_NON_HERO_UNITS := 12
const WAVE_4_MIN_NON_HERO_UNITS := 16
const WAVE_REGROUP_MAX_DISTANCE := 22.0
const WAVE_REBUILD_ARMY_RATIO := 0.65

enum ArmyMode {
	IDLE,
	CREEPING,
	ATTACKING,
	REGROUPING,
	DEFENDING,
}

static var _army_mode: ArmyMode = ArmyMode.IDLE


static func get_army_mode() -> ArmyMode:
	return _army_mode


## Returns true when the requested mode owns the army for issuing orders.
## Pass allow_attack_override_creep when a ready wave should take over from creeping.
static func try_claim_army_mode(
	requested_mode: ArmyMode,
	allow_attack_override_creep: bool = false
) -> bool:
	if requested_mode == _army_mode:
		return true

	match _army_mode:
		ArmyMode.IDLE:
			_army_mode = requested_mode
			return true
		ArmyMode.CREEPING:
			if requested_mode == ArmyMode.ATTACKING and allow_attack_override_creep:
				_army_mode = ArmyMode.ATTACKING
				return true
			if requested_mode == ArmyMode.REGROUPING or requested_mode == ArmyMode.DEFENDING:
				_army_mode = requested_mode
				return true
			return false
		ArmyMode.ATTACKING:
			if requested_mode == ArmyMode.REGROUPING or requested_mode == ArmyMode.DEFENDING:
				_army_mode = requested_mode
				return true
			return false
		ArmyMode.REGROUPING:
			if (
				requested_mode == ArmyMode.CREEPING
				or requested_mode == ArmyMode.ATTACKING
				or requested_mode == ArmyMode.IDLE
				or requested_mode == ArmyMode.DEFENDING
			):
				_army_mode = requested_mode
				return true
			return false
		ArmyMode.DEFENDING:
			return requested_mode == ArmyMode.DEFENDING

	return false


static func release_army_mode(mode: ArmyMode) -> bool:
	if _army_mode != mode:
		return false

	_army_mode = ArmyMode.IDLE
	return true


static func is_combat_unit(node: Node) -> bool:
	return node is Swordsman or node is Archer or node is Hero


static func is_hero_unit(node: Node) -> bool:
	return node is Hero


static func is_non_hero_combat_unit(node: Node) -> bool:
	return is_combat_unit(node) and not is_hero_unit(node)


static func is_living_combat_unit(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not is_combat_unit(node):
		return false

	if not node.is_in_group(ENEMY_COMBAT_GROUP):
		return false

	return _has_positive_health(node)


static func register_combat_unit(unit: Unit) -> void:
	if unit == null or not is_combat_unit(unit):
		return

	if not unit.is_in_group(ENEMIES_GROUP):
		unit.add_to_group(ENEMIES_GROUP)

	if not unit.is_in_group(ENEMY_COMBAT_GROUP):
		unit.add_to_group(ENEMY_COMBAT_GROUP)


static func collect_living_combat_units(tree: SceneTree) -> Array:
	var units: Array = []

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node):
			units.append(node)

	return units


static func collect_living_non_hero_combat_units(tree: SceneTree) -> Array:
	var units: Array = []

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node) and is_non_hero_combat_unit(node):
			units.append(node)

	return units


static func find_living_enemy_hero(tree: SceneTree) -> Hero:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node) and is_hero_unit(node):
			return node as Hero

	return null


static func get_min_non_hero_units_for_wave(wave_number: int) -> int:
	if wave_number <= 1:
		return WAVE_1_MIN_NON_HERO_UNITS
	if wave_number == 2:
		return WAVE_2_MIN_NON_HERO_UNITS
	if wave_number == 3:
		return WAVE_3_MIN_NON_HERO_UNITS

	return WAVE_4_MIN_NON_HERO_UNITS


static func filter_units_near_rally(
	units: Array,
	rally_position: Vector3,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> Array:
	var nearby_units: Array = []

	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			continue

		if not unit is Node3D:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		if horizontal_distance((unit as Node3D).global_position, rally_position) <= max_distance:
			nearby_units.append(unit)

	return nearby_units


static func is_army_regrouped_at_rally(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero_units: int,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> bool:
	if rally_position == Vector3.ZERO:
		return false

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	return (
		filter_units_near_rally(non_hero_units, rally_position, max_distance).size()
		>= min_non_hero_units
	)


static func command_regroup_at_rally(tree: SceneTree, rally_position: Vector3) -> void:
	if rally_position == Vector3.ZERO:
		return

	var units: Array = collect_living_combat_units(tree)
	command_hold_at_rally(units, rally_position)


static func build_regrouped_attack_wave_units(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero_units: int
) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var regrouped_non_hero: Array = filter_units_near_rally(
		non_hero_units,
		rally_position
	)
	var can_launch: bool = regrouped_non_hero.size() >= min_non_hero_units
	var wave_units: Array = regrouped_non_hero.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		if (
			hero != null
			and regrouped_non_hero.size() >= MIN_NON_HERO_FOR_HERO_JOIN
			and is_hero_healthy_enough_for_wave(hero)
			and horizontal_distance(hero.global_position, rally_position)
			<= WAVE_REGROUP_MAX_DISTANCE + 6.0
		):
			wave_units.append(hero)

	return {
		"units": wave_units,
		"can_launch": can_launch,
		"non_hero_count": regrouped_non_hero.size(),
		"total_non_hero_count": non_hero_units.size(),
	}


static func should_rebuild_army_after_wave(
	current_non_hero_count: int,
	last_wave_non_hero_count: int
) -> bool:
	if last_wave_non_hero_count <= 0:
		return false

	return (
		current_non_hero_count
		< int(float(last_wave_non_hero_count) * WAVE_REBUILD_ARMY_RATIO)
	)


static func build_attack_wave_units(tree: SceneTree, min_non_hero_units: int) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var can_launch: bool = non_hero_units.size() >= min_non_hero_units
	var wave_units: Array = non_hero_units.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		if (
			hero != null
			and non_hero_units.size() >= MIN_NON_HERO_FOR_HERO_JOIN
			and is_hero_healthy_enough_for_wave(hero)
		):
			wave_units.append(hero)

	return {
		"units": wave_units,
		"can_launch": can_launch,
		"non_hero_count": non_hero_units.size(),
	}


static func build_creep_army(tree: SceneTree) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var can_launch: bool = non_hero_units.size() >= MIN_NON_HERO_FOR_HERO_JOIN
	var creep_units: Array = non_hero_units.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		if hero != null and is_living_combat_unit(hero):
			creep_units.append(hero)

	return {
		"units": creep_units,
		"can_launch": can_launch,
		"non_hero_count": non_hero_units.size(),
	}


static func is_enemy_base_threatened(tree: SceneTree) -> bool:
	return evaluate_defense_threat(tree).get("threatened", false)


static func evaluate_defense_threat(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return {"threatened": false}

	var worker_threat: Vector3 = _find_player_military_near_enemy_workers(
		tree,
		WORKER_THREAT_RANGE
	)
	if worker_threat != Vector3.ZERO:
		return {
			"threatened": true,
			"intercept_position": worker_threat,
			"reason": &"workers",
		}

	var building_threat: Vector3 = _find_player_military_near_enemy_buildings(
		tree,
		BUILDING_THREAT_RANGE
	)
	if building_threat != Vector3.ZERO:
		return {
			"threatened": true,
			"intercept_position": building_threat,
			"reason": &"buildings",
		}

	var base_threat: Node3D = _find_player_military_near_position(
		tree,
		rally_position,
		BASE_THREAT_DETECTION_RANGE
	)
	if base_threat != null:
		return {
			"threatened": true,
			"intercept_position": base_threat.global_position,
			"reason": &"base",
		}

	var approach_threat: Node3D = _find_player_military_near_position(
		tree,
		rally_position,
		APPROACH_DETECTION_RANGE
	)
	if approach_threat != null:
		return {
			"threatened": true,
			"intercept_position": approach_threat.global_position,
			"reason": &"approach",
		}

	return {"threatened": false}


static func build_defense_army(
	tree: SceneTree,
	threat_anchor: Vector3 = Vector3.ZERO
) -> Array:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return []

	var anchor_position: Vector3 = rally_position
	if threat_anchor != Vector3.ZERO:
		anchor_position = threat_anchor

	var gathered_units: Array = []
	var seen_units: Dictionary = {}

	for unit: Variant in collect_living_combat_units(tree):
		if unit == null or not is_instance_valid(unit):
			continue

		if not unit is Node3D:
			continue

		var unit_position: Vector3 = (unit as Node3D).global_position
		var near_rally: bool = (
			horizontal_distance(unit_position, rally_position) <= DEFENSE_GATHER_MAX_DISTANCE
		)
		var near_threat: bool = (
			horizontal_distance(unit_position, anchor_position) <= DEFENSE_GATHER_MAX_DISTANCE
		)
		if not near_rally and not near_threat:
			continue

		gathered_units.append(unit)
		seen_units[unit] = true

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and not seen_units.has(hero):
		var hero_distance: float = horizontal_distance(hero.global_position, rally_position)
		if hero_distance <= DEFENSE_GATHER_MAX_DISTANCE + DEFENSE_HERO_EXTRA_GATHER_DISTANCE:
			gathered_units.append(hero)

	return gathered_units


static func evaluate_defense_commitment(
	tree: SceneTree,
	defense_army: Array,
	threat_position: Vector3
) -> Dictionary:
	var defender_power: int = estimate_military_power(defense_army)
	var threat_power: int = estimate_player_threat_power_near(
		tree,
		threat_position,
		DEFENSE_THREAT_POWER_RANGE
	)

	return {
		"defender_power": defender_power,
		"threat_power": threat_power,
		"can_commit": defender_power >= threat_power,
	}


static func estimate_military_power(units: Array) -> int:
	var power: int = 0

	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			continue

		if not is_living_combat_unit(unit as Node):
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
		if unit is Archer:
			power += int(float(current_health) * DEFENSE_POWER_RANGED_HEALTH)
		else:
			power += int(float(current_health) * DEFENSE_POWER_MELEE_HEALTH)
		power += damage * int(DEFENSE_POWER_DAMAGE_MULTIPLIER)

	return power


static func estimate_player_threat_power_near(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> int:
	return estimate_military_power(
		collect_player_military_near(tree, position, search_range)
	)


static func collect_player_military_near(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> Array:
	var targets: Array = []

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not _is_player_military_unit(node):
				continue

			var target: Node3D = node as Node3D
			if horizontal_distance(position, target.global_position) > search_range:
				continue

			targets.append(node)

	return targets


static func resolve_defense_hold_position(
	rally_position: Vector3,
	threat_position: Vector3
) -> Vector3:
	if rally_position == Vector3.ZERO:
		return threat_position

	if threat_position == Vector3.ZERO:
		return rally_position

	var offset: Vector3 = threat_position - rally_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		return rally_position

	var forward: Vector3 = offset.normalized()
	var hold_distance: float = minf(
		DEFENSE_HOLD_FORWARD_DISTANCE,
		offset.length() * 0.35
	)
	return rally_position + forward * hold_distance


static func is_enemy_army_under_attack(
	tree: SceneTree,
	army_units: Array,
	search_range: float
) -> bool:
	var army_center: Vector3 = compute_army_center(army_units)
	if army_center == Vector3.ZERO:
		return false

	return (
		_find_player_military_near_position(tree, army_center, search_range) != null
	)


static func find_living_player_command_center(tree: SceneTree) -> CommandCenter:
	return _resolve_living_player_command_center(tree)


static func horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	return _horizontal_distance(from_position, to_position)


static func resolve_enemy_rally_position(tree: SceneTree) -> Vector3:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_building(node as Building):
			return (node as Node3D).global_position + ARMY_RALLY_OFFSET

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if node is Node3D:
			return (node as Node3D).global_position

	return Vector3.ZERO


static func has_player_attack_targets(tree: SceneTree, enemy_base_position: Vector3) -> bool:
	if _find_player_military_near_position(tree, enemy_base_position, BASE_THREAT_DETECTION_RANGE) != null:
		return true

	if _resolve_living_player_command_center(tree) != null:
		return true

	if _find_nearest_living_player_building(tree, enemy_base_position) != null:
		return true

	if _find_nearest_living_player_unit(tree, enemy_base_position) != null:
		return true

	return false


static func resolve_wave_attack_destination(tree: SceneTree, enemy_base_position: Vector3) -> Vector3:
	var nearby_military: Node3D = _find_player_military_near_position(
		tree,
		enemy_base_position,
		BASE_THREAT_DETECTION_RANGE
	)
	if nearby_military != null:
		return nearby_military.global_position

	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return command_center.global_position

	var nearest_building: Node3D = _find_nearest_living_player_building(
		tree,
		enemy_base_position
	)
	if nearest_building != null:
		return nearest_building.global_position

	var nearest_unit: Node3D = _find_nearest_living_player_unit(tree, enemy_base_position)
	if nearest_unit != null:
		return nearest_unit.global_position

	return enemy_base_position


static func is_hero_healthy_enough_for_wave(hero: Hero) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false

	return get_health_ratio(hero) >= HERO_WAVE_JOIN_HP_RATIO


static func get_health_ratio(node: Node) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0

	var health_component: HealthComponent = node.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component == null or health_component.max_health <= 0:
		return 1.0

	return float(health_component.current_health) / float(health_component.max_health)


static func command_retreat_hero(hero: Hero, rally_position: Vector3) -> void:
	if hero == null or not is_instance_valid(hero):
		return

	if not is_living_combat_unit(hero):
		return

	_issue_hold_at_rally(hero, rally_position)


static func command_attack_move(units: Array, destination: Vector3) -> void:
	_issue_spaced_group_orders(units, destination, true)


static func command_defend_position(units: Array, position: Vector3) -> void:
	command_attack_move(units, position)


static func command_retreat_to(units: Array, position: Vector3) -> void:
	_issue_spaced_group_orders(units, position, false)


static func command_hold_at_rally(units: Array, rally_position: Vector3) -> void:
	_issue_spaced_group_orders(units, rally_position, false)


static func _issue_attack_move(unit: Variant, destination: Vector3) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if not (unit as Object).has_method("command_attack_move"):
		return

	(unit as Object).call("command_attack_move", destination)


static func _issue_spaced_group_orders(units: Array, center: Vector3, use_attack_move: bool) -> void:
	var ordered_units: Array = _order_units_for_formation(units)
	if ordered_units.is_empty():
		return

	var move_targets: Array[Vector3] = (
		_compute_attack_formation_targets(ordered_units, center, FORMATION_SPACING)
		if use_attack_move
		else GroupMoveSpacing.compute_targets(
			center,
			ordered_units.size(),
			FORMATION_SPACING
		)
	)
	for index: int in ordered_units.size():
		var unit: Variant = ordered_units[index]
		if unit == null or not is_instance_valid(unit):
			continue

		var target: Vector3 = move_targets[index]
		if use_attack_move:
			_issue_attack_move(unit, target)
		else:
			_issue_hold_at_rally(unit, target)


static func _order_units_for_formation(units: Array) -> Array:
	var melee_units: Array = []
	var ranged_units: Array = []
	var hero_units: Array = []

	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			continue

		if unit is Worker:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		if is_hero_unit(unit as Node):
			hero_units.append(unit)
		elif unit is Archer:
			ranged_units.append(unit)
		else:
			melee_units.append(unit)

	var ordered_units: Array = []
	ordered_units.append_array(melee_units)
	ordered_units.append_array(ranged_units)
	ordered_units.append_array(hero_units)
	return ordered_units


static func _compute_attack_formation_targets(
	units: Array,
	destination: Vector3,
	spacing: float
) -> Array[Vector3]:
	if units.is_empty():
		return []

	var army_center: Vector3 = compute_army_center(units)
	var forward: Vector3 = destination - army_center
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0.0, 0.0, 1.0)
	else:
		forward = forward.normalized()

	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var melee_count: int = 0
	var ranged_count: int = 0
	var hero_count: int = 0
	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			continue

		if is_hero_unit(unit as Node):
			hero_count += 1
		elif unit is Archer:
			ranged_count += 1
		else:
			melee_count += 1

	var melee_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		destination,
		right,
		melee_count,
		spacing
	)
	var ranged_row_center: Vector3 = (
		destination - forward * spacing * RANGED_ROW_DEPTH_MULTIPLIER
	)
	var ranged_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		ranged_row_center,
		right,
		ranged_count,
		spacing
	)
	var hero_row_center: Vector3 = destination - forward * spacing * HERO_ROW_DEPTH_MULTIPLIER
	var hero_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		hero_row_center,
		right,
		hero_count,
		spacing
	)

	var targets: Array[Vector3] = []
	var melee_index: int = 0
	var ranged_index: int = 0
	var hero_index: int = 0

	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			targets.append(destination)
			continue

		var candidate: Vector3 = destination
		if is_hero_unit(unit as Node):
			candidate = hero_targets[hero_index]
			hero_index += 1
		elif unit is Archer:
			candidate = ranged_targets[ranged_index]
			ranged_index += 1
		else:
			candidate = melee_targets[melee_index]
			melee_index += 1

		targets.append(
			GroupMoveSpacing.resolve_nearby_walkable_position(
				candidate,
				unit as Node3D,
				destination,
				spacing
			)
		)

	return targets


static func compute_army_center(units: Array) -> Vector3:
	if units.is_empty():
		return Vector3.ZERO

	var position_sum: Vector3 = Vector3.ZERO
	var count: int = 0

	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit):
			continue

		if not unit is Node3D:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		position_sum += (unit as Node3D).global_position
		count += 1

	if count == 0:
		return Vector3.ZERO

	return position_sum / float(count)


static func _issue_hold_at_rally(unit: Variant, rally_position: Vector3) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if (unit as Object).has_method("set_movement_target"):
		(unit as Object).call("set_movement_target", rally_position)
		return

	_issue_attack_move(unit, rally_position)


static func _find_player_military_near_enemy_workers(
	tree: SceneTree,
	search_range: float
) -> Vector3:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_threat: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_WORKERS_GROUP):
		if not node is Worker or not _has_positive_health(node):
			continue

		if not node is Node3D:
			continue

		var worker_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			worker_position,
			search_range
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_threat = threat

	if closest_threat != null:
		return closest_threat.global_position

	return Vector3.ZERO


static func _find_player_military_near_enemy_buildings(
	tree: SceneTree,
	search_range: float
) -> Vector3:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_threat: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			search_range
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_threat = threat

	if closest_threat != null:
		return closest_threat.global_position

	return Vector3.ZERO


static func _find_player_military_near_position(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> Node3D:
	var closest_target: Node3D = null
	var closest_distance: float = INF

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not _is_player_military_unit(node):
				continue

			var target: Node3D = node as Node3D
			var distance: float = _horizontal_distance(position, target.global_position)
			if distance > search_range:
				continue

			if distance < closest_distance:
				closest_distance = distance
				closest_target = target

	return closest_target


static func _is_player_military_unit(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if CombatTargetValidation.is_enemy_faction(node):
		return false

	if not (node is Swordsman or node is Archer or node is Hero):
		return false

	return _has_positive_health(node)


static func _resolve_living_player_command_center(tree: SceneTree) -> CommandCenter:
	for node: Node in tree.get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_building(node as Building):
			return node as CommandCenter

	return null


static func _find_nearest_living_player_building(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_building: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		var building: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, building.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_building = building

	return closest_building


static func _find_nearest_living_player_unit(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_unit: Node3D = null
	var closest_distance: float = INF

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not node is Node3D:
				continue

			if CombatTargetValidation.is_enemy_faction(node):
				continue

			if not CombatTargetValidation.is_valid_combat_target(node):
				continue

			if node is Worker:
				continue

			var target: Node3D = node as Node3D
			var distance: float = _horizontal_distance(from_position, target.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_unit = target

	return closest_unit


static func _is_living_building(building: Building) -> bool:
	if building == null or not is_instance_valid(building):
		return false

	if building.is_queued_for_deletion():
		return false

	return _has_positive_health(building)


static func _has_positive_health(node: Node) -> bool:
	var health_component: HealthComponent = node.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


static func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length()
