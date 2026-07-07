class_name EnemyCreepManager
extends Node

## Sends the enemy hero and early army to clear nearby neutral creep camps.

const CREEP_TICK_INTERVAL_SECONDS: float = 8.0
const CREEP_SEARCH_RANGE: float = 48.0
const MAX_CREEP_DISTANCE_FROM_RALLY: float = 34.0
const CAMP_ENGAGEMENT_RADIUS: float = 20.0
const CAMP_CLEAR_RADIUS: float = 14.0
const ARMY_UNDER_ATTACK_RANGE: float = 22.0
const CAMP_POWER_MARGIN: float = 1.15
const STRONG_CAMP_POWER_MARGIN: float = 1.35
const STRONG_CAMP_POWER_THRESHOLD: int = 280
const CREEP_REGROUP_MAX_DISTANCE: float = 24.0
const CREEP_HERO_POWER: int = 220
const CREEP_MELEE_POWER_PER_HEALTH: float = 1.0
const CREEP_RANGED_POWER_PER_HEALTH: float = 0.85
const CREEP_DAMAGE_POWER_MULTIPLIER: float = 8.0
const MAX_CREEP_SETBACKS_BEFORE_ATTACK: int = 3

var _tick_timer: float = 0.0
var _consecutive_creep_setbacks: int = 0
var _director: EnemyStrategicDirector = null


func _ready() -> void:
	_director = get_parent().get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < CREEP_TICK_INTERVAL_SECONDS:
		return

	_tick_timer = 0.0
	_update_creeping()


func should_abandon_creep_phase() -> bool:
	return _consecutive_creep_setbacks >= MAX_CREEP_SETBACKS_BEFORE_ATTACK


func has_safe_creep_camp_available() -> bool:
	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(tree)
	if not creep_plan.get("can_launch", false):
		return false

	var army_power: int = _estimate_army_power(creep_plan.get("units", []))
	return _find_best_creep_camp(tree, rally_position, army_power) != null


func _update_creeping() -> void:
	if EnemyArmyCommand.is_finishing_mode_active():
		return

	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	if _director != null and not _director.should_prioritize_creep():
		return

	var creep_plan: Dictionary = _build_regrouped_creep_army(tree, rally_position)
	if not creep_plan.get("can_launch", false):
		var full_plan: Dictionary = EnemyArmyCommand.build_creep_army(tree)
		if (
			full_plan.get("can_launch", false)
			and EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING)
		):
			EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)
		return

	var creep_army: Array = creep_plan.get("units", [])
	creep_army = NodeSafety.clean_node_array(creep_army)
	if creep_army.is_empty():
		return

	if EnemyArmyCommand.is_enemy_army_under_attack(tree, creep_army, ARMY_UNDER_ATTACK_RANGE):
		_record_creep_setback()
		_retreat_creep_army(tree, rally_position)
		return

	if _should_abort_creep_push(tree, creep_army):
		_retreat_creep_army(tree, rally_position)
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(creep_army)
	if army_center == Vector3.ZERO:
		return

	if not _army_available_for_creeping(tree, army_center, rally_position):
		return

	var army_power: int = _estimate_army_power(creep_army)
	var camp: Node3D = _find_best_creep_camp(tree, rally_position, army_power)
	if camp == null or not is_instance_valid(camp):
		if _has_uncleared_enemy_side_camps(tree, rally_position):
			_record_creep_setback()
		if _director != null:
			_director.clear_creep_target()
		return

	if _director != null:
		_director.set_creep_target(camp)

	if _is_camp_cleared(tree, camp):
		_reset_creep_setbacks()
		return

	if _is_army_engaging_camp(tree, creep_army, camp):
		return

	var attack_destination: Vector3 = _resolve_camp_attack_destination(
		tree,
		camp,
		army_center
	)
	if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.CREEPING):
		return

	EnemyArmyCommand.command_attack_move(
		creep_army,
		attack_destination,
		EnemyUnitMission.Mission.CREEP
	)


func _record_creep_setback() -> void:
	_consecutive_creep_setbacks += 1


func _reset_creep_setbacks() -> void:
	_consecutive_creep_setbacks = 0


func _has_uncleared_enemy_side_camps(tree: SceneTree, rally_position: Vector3) -> bool:
	return CreepCampSafety.has_uncleared_nearby_camps(
		tree,
		rally_position,
		CREEP_SEARCH_RANGE
	)


func _retreat_creep_army(tree: SceneTree, rally_position: Vector3) -> void:
	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(tree)
	var creep_army: Array = creep_plan.get("units", [])
	creep_army = NodeSafety.clean_node_array(creep_army)
	if creep_army.is_empty():
		var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
		if hero != null and NodeSafety.is_alive_node(hero):
			EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	EnemyArmyCommand.cancel_offensive_orders(tree)
	EnemyArmyCommand.command_hold_at_rally(creep_army, rally_position)


func _should_abort_creep_push(tree: SceneTree, creep_army: Array) -> bool:
	var non_hero_count: int = 0
	for unit: Variant in NodeSafety.clean_node_array(creep_army):
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Hero:
			continue
		if EnemyArmyCommand.is_living_combat_unit(unit as Node):
			non_hero_count += 1

	return non_hero_count < EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN


func _build_regrouped_creep_army(tree: SceneTree, rally_position: Vector3) -> Dictionary:
	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(tree)
	if not creep_plan.get("can_launch", false):
		return creep_plan

	var regrouped_units: Array = EnemyArmyCommand.filter_units_near_rally(
		creep_plan.get("units", []),
		rally_position,
		CREEP_REGROUP_MAX_DISTANCE
	)
	var non_hero_count: int = 0
	for unit: Variant in NodeSafety.clean_node_array(regrouped_units):
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Hero:
			continue
		non_hero_count += 1

	var can_launch: bool = non_hero_count >= EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN
	return {
		"units": regrouped_units if can_launch else [],
		"can_launch": can_launch,
	}


func _army_available_for_creeping(
	tree: SceneTree,
	army_center: Vector3,
	rally_position: Vector3
) -> bool:
	var distance_to_rally: float = EnemyArmyCommand.horizontal_distance(
		army_center,
		rally_position
	)
	if distance_to_rally <= MAX_CREEP_DISTANCE_FROM_RALLY:
		return true

	if _count_living_creeps_near(tree, army_center, CAMP_ENGAGEMENT_RADIUS) > 0:
		return true

	return not _is_army_on_offensive_push(tree, army_center, rally_position)


func _is_army_on_offensive_push(
	tree: SceneTree,
	army_center: Vector3,
	rally_position: Vector3
) -> bool:
	var player_command_center: CommandCenter = (
		EnemyArmyCommand.find_living_player_command_center(tree)
	)
	if player_command_center == null:
		return false

	var distance_to_player: float = EnemyArmyCommand.horizontal_distance(
		army_center,
		player_command_center.global_position
	)
	var distance_to_rally: float = EnemyArmyCommand.horizontal_distance(
		army_center,
		rally_position
	)
	return distance_to_player + 12.0 < distance_to_rally


func _find_best_creep_camp(
	tree: SceneTree,
	rally_position: Vector3,
	army_power: int
) -> Node3D:
	var best_camp: Node3D = null
	var best_power: int = -1
	var best_distance: float = INF

	for camp: Node3D in _collect_creep_camps(tree):
		if camp == null or not is_instance_valid(camp):
			continue

		if not _is_enemy_side_camp(camp, rally_position, tree):
			continue

		if _is_camp_cleared(tree, camp):
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			camp.global_position,
			rally_position
		)
		if distance > CREEP_SEARCH_RANGE:
			continue

		var camp_power: int = _estimate_camp_power(camp)
		if camp_power <= 0:
			continue

		var power_margin: float = (
			STRONG_CAMP_POWER_MARGIN
			if camp_power >= STRONG_CAMP_POWER_THRESHOLD
			else CAMP_POWER_MARGIN
		)
		if float(camp_power) * power_margin > float(army_power):
			continue

		if (
			best_camp == null
			or camp_power < best_power
			or (camp_power == best_power and distance < best_distance)
		):
			best_camp = camp
			best_power = camp_power
			best_distance = distance

	return best_camp


func _collect_creep_camps(tree: SceneTree) -> Array[Node3D]:
	return CreepCampSafety.collect_active_camps(tree)


func _is_enemy_side_camp(camp: Node3D, enemy_rally: Vector3, tree: SceneTree) -> bool:
	var player_command_center: CommandCenter = (
		EnemyArmyCommand.find_living_player_command_center(tree)
	)
	if player_command_center == null:
		return true

	var camp_position: Vector3 = camp.global_position
	var distance_to_enemy: float = EnemyArmyCommand.horizontal_distance(
		camp_position,
		enemy_rally
	)
	var distance_to_player: float = EnemyArmyCommand.horizontal_distance(
		camp_position,
		player_command_center.global_position
	)
	return distance_to_enemy <= distance_to_player


func _is_camp_cleared(tree: SceneTree, camp: Node3D) -> bool:
	if camp == null or not is_instance_valid(camp):
		return true

	return _count_living_creeps_near(tree, camp.global_position, CAMP_CLEAR_RADIUS) == 0


func _resolve_camp_attack_destination(
	tree: SceneTree,
	camp: Node3D,
	from_position: Vector3
) -> Vector3:
	if camp == null or not is_instance_valid(camp):
		return from_position

	var nearest_creep: Node3D = _find_nearest_living_creep_at_camp(tree, camp, from_position)
	if nearest_creep != null:
		return nearest_creep.global_position

	return camp.global_position


func _find_nearest_living_creep_at_camp(
	tree: SceneTree,
	camp: Node3D,
	from_position: Vector3
) -> Node3D:
	var nearest_creep: Node3D = null
	var nearest_distance: float = INF

	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue

		if not _is_living_creep(child_variant):
			continue

		if not child_variant is Node3D:
			continue

		var child: Node3D = child_variant as Node3D
		var distance: float = EnemyArmyCommand.horizontal_distance(
			from_position,
			child.global_position
		)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_creep = child as Node3D

	return nearest_creep


func _is_army_engaging_camp(tree: SceneTree, army: Array, camp: Node3D) -> bool:
	if camp == null or not is_instance_valid(camp):
		return false

	if _count_living_creeps_near(tree, camp.global_position, CAMP_ENGAGEMENT_RADIUS) == 0:
		return false

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(army)
	if army_center == Vector3.ZERO:
		return false

	return (
		EnemyArmyCommand.horizontal_distance(army_center, camp.global_position)
		<= CAMP_ENGAGEMENT_RADIUS + 6.0
	)


func _count_living_creeps_near(tree: SceneTree, position: Vector3, radius: float) -> int:
	var count: int = 0

	for node_variant: Variant in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if node_variant == null or not is_instance_valid(node_variant) or not node_variant is Node:
			continue

		var node: Node = node_variant as Node
		if not _is_living_creep(node):
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


func _estimate_army_power(units: Array) -> int:
	var power: int = 0

	for unit: Variant in NodeSafety.clean_node_array(units):
		if not NodeSafety.is_alive_node(unit):
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
		if unit is Archer or unit is CavalryArcher:
			power += int(float(current_health) * CREEP_RANGED_POWER_PER_HEALTH)
		else:
			power += int(float(current_health) * CREEP_MELEE_POWER_PER_HEALTH)
		power += damage * int(CREEP_DAMAGE_POWER_MULTIPLIER)

	return power


func _estimate_camp_power(camp: Node3D) -> int:
	var power: int = 0

	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue

		var child: Node = child_variant as Node
		if not _is_living_creep(child):
			continue

		var health_component: HealthComponent = child.get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		if health_component == null:
			continue

		var damage: int = 8
		if "attack_damage" in child:
			damage = int(child.get("attack_damage"))

		power += health_component.max_health + damage * int(CREEP_DAMAGE_POWER_MULTIPLIER)

	return power


func _is_living_creep(node: Variant) -> bool:
	if not NodeSafety.is_alive_node(node):
		return false

	if not node is Node:
		return false

	if not CombatTargetValidation.is_neutral_creep(node):
		return false

	return CombatTargetValidation.get_target_current_health(node) > 0
