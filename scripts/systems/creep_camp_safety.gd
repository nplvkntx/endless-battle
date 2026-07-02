class_name CreepCampSafety
extends RefCounted

## Detects active creep camps and whether gather resources are guarded.

const CAMP_GUARD_RADIUS: float = 20.0
const CREEP_LEASH_DISTANCE: float = 16.0
const CAMP_HOME_TOLERANCE: float = 1.25
const CREEP_MOVE_SPEED: float = 3.5


static func is_resource_guarded_by_active_camp(
	resource: Node3D,
	tree: SceneTree
) -> bool:
	if resource == null or not is_instance_valid(resource) or tree == null:
		return false

	var resource_position: Vector3 = resource.global_position
	for camp: Node3D in collect_active_camps(tree):
		if _horizontal_distance(resource_position, camp.global_position) <= CAMP_GUARD_RADIUS:
			return true

	return false


static func collect_active_camps(tree: SceneTree) -> Array[Node3D]:
	var camps: Dictionary = {}

	for node: Node in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if not _is_living_creep(node):
			continue

		var parent: Node = node.get_parent()
		if parent == null or not parent is Node3D:
			continue

		camps[parent.get_instance_id()] = parent as Node3D

	return camps.values()


static func has_uncleared_nearby_camps(
	tree: SceneTree,
	rally_position: Vector3,
	search_range: float
) -> bool:
	if tree == null or rally_position == Vector3.ZERO:
		return false

	for camp: Node3D in collect_active_camps(tree):
		if not _is_enemy_side_camp(camp, rally_position, tree):
			continue

		var distance: float = _horizontal_distance(camp.global_position, rally_position)
		if distance <= search_range:
			return true

	return false


static func get_camp_anchor_for_creep(creep: Node3D) -> Vector3:
	if creep == null or not is_instance_valid(creep):
		return Vector3.ZERO

	var parent: Node = creep.get_parent()
	if parent is Node3D:
		return (parent as Node3D).global_position

	return creep.global_position


static func _is_enemy_side_camp(
	camp: Node3D,
	enemy_rally: Vector3,
	tree: SceneTree
) -> bool:
	var player_command_center: CommandCenter = (
		EnemyArmyCommand.find_living_player_command_center(tree)
	)
	if player_command_center == null:
		return true

	var camp_position: Vector3 = camp.global_position
	var distance_to_enemy: float = _horizontal_distance(camp_position, enemy_rally)
	var distance_to_player: float = _horizontal_distance(
		camp_position,
		player_command_center.global_position
	)
	return distance_to_enemy <= distance_to_player


static func _is_living_creep(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not CombatTargetValidation.is_neutral_creep(node):
		return false

	return CombatTargetValidation.get_target_current_health(node) > 0


static func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length()
