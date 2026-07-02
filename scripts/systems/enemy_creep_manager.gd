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
const CREEP_HERO_POWER: int = 220
const CREEP_MELEE_POWER_PER_HEALTH: float = 1.0
const CREEP_RANGED_POWER_PER_HEALTH: float = 0.85
const CREEP_DAMAGE_POWER_MULTIPLIER: float = 8.0

var _tick_timer: float = 0.0


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < CREEP_TICK_INTERVAL_SECONDS:
		return

	_tick_timer = 0.0
	_update_creeping()


func _update_creeping() -> void:
	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if EnemyArmyCommand.is_enemy_base_threatened(tree):
		_retreat_creep_army(tree, rally_position)
		return

	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(tree)
	if not creep_plan.get("can_launch", false):
		return

	var creep_army: Array = creep_plan.get("units", [])
	if creep_army.is_empty():
		return

	if EnemyArmyCommand.is_enemy_army_under_attack(tree, creep_army, ARMY_UNDER_ATTACK_RANGE):
		_retreat_creep_army(tree, rally_position)
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(creep_army)
	if army_center == Vector3.ZERO:
		return

	if not _army_available_for_creeping(tree, army_center, rally_position):
		return

	var army_power: int = _estimate_army_power(creep_army)
	var camp: Node3D = _find_best_creep_camp(tree, rally_position, army_power)
	if camp == null:
		return

	if _is_camp_cleared(tree, camp):
		return

	if _is_army_engaging_camp(tree, creep_army, camp):
		return

	EnemyArmyCommand.command_attack_move(creep_army, camp.global_position)


func _retreat_creep_army(tree: SceneTree, rally_position: Vector3) -> void:
	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(tree)
	var creep_army: Array = creep_plan.get("units", [])
	if creep_army.is_empty():
		return

	EnemyArmyCommand.command_hold_at_rally(creep_army, rally_position)


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

		if float(camp_power) * CAMP_POWER_MARGIN > float(army_power):
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
	return _count_living_creeps_near(tree, camp.global_position, CAMP_CLEAR_RADIUS) == 0


func _is_army_engaging_camp(tree: SceneTree, army: Array, camp: Node3D) -> bool:
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

	for node: Node in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
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


func _estimate_camp_power(camp: Node3D) -> int:
	var power: int = 0

	for child: Node in camp.get_children():
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


func _is_living_creep(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not CombatTargetValidation.is_neutral_creep(node):
		return false

	return CombatTargetValidation.get_target_current_health(node) > 0
