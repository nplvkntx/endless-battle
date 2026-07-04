class_name CreepCampSafety
extends RefCounted

## Detects active creep camps and whether gather resources are guarded.

const CAMP_GUARD_RADIUS: float = 20.0
const CAMP_RESPAWN_BLOCK_RADIUS: float = 20.0
const CREEP_LEASH_DISTANCE: float = 16.0
const CAMP_HOME_TOLERANCE: float = 1.25
const CREEP_MOVE_SPEED: float = 3.5

const _CAMP_BLOCK_UNIT_GROUPS: Array[StringName] = [
	&"units",
	&"heroes",
	&"enemies",
	&"enemy_workers",
	&"enemy_combat_units",
]


static var _cached_active_camps_frame: int = -1
static var _cached_active_camps_tree_id: int = -1
static var _cached_active_camps: Array[Node3D] = []


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
	if tree == null:
		return []

	var frame: int = Engine.get_process_frames()
	var tree_id: int = tree.get_instance_id()
	if (
		frame == _cached_active_camps_frame
		and tree_id == _cached_active_camps_tree_id
	):
		return _cached_active_camps

	var camps: Dictionary = {}

	for node: Node in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if not _is_living_creep(node):
			continue

		var parent: Node = node.get_parent()
		if parent == null or not parent is Node3D:
			continue

		camps[parent.get_instance_id()] = parent as Node3D

	var active_camps: Array[Node3D] = []
	for camp: Node3D in camps.values():
		active_camps.append(camp)

	_cached_active_camps_frame = frame
	_cached_active_camps_tree_id = tree_id
	_cached_active_camps = active_camps
	return active_camps


static func count_cleared_enemy_side_camps(
	tree: SceneTree,
	rally_position: Vector3,
	search_range: float,
	clear_radius: float
) -> int:
	if tree == null or rally_position == Vector3.ZERO:
		return 0

	var cleared: int = 0

	for node: Node in tree.get_nodes_in_group(&"creep_camps"):
		if not node is Node3D:
			continue

		var camp: Node3D = node as Node3D
		if not _is_enemy_side_camp(camp, rally_position, tree):
			continue

		var distance: float = _horizontal_distance(camp.global_position, rally_position)
		if distance > search_range:
			continue

		if _count_living_creeps_near(tree, camp.global_position, clear_radius) == 0:
			cleared += 1

	return cleared


static func _count_living_creeps_near(
	tree: SceneTree,
	position: Vector3,
	radius: float
) -> int:
	var count: int = 0

	for node: Node in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if not _is_living_creep(node):
			continue

		if not node is Node3D:
			continue

		var distance: float = _horizontal_distance(
			position,
			(node as Node3D).global_position
		)
		if distance <= radius:
			count += 1

	return count


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


static func is_camp_area_clear(camp_position: Vector3, tree: SceneTree) -> bool:
	if tree == null or camp_position == Vector3.ZERO:
		return false

	var seen: Dictionary = {}

	for group_name: StringName in _CAMP_BLOCK_UNIT_GROUPS:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not _is_blocking_unit_in_camp(node, camp_position, seen):
				continue

			return false

	return true


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


static func _is_blocking_unit_in_camp(
	node: Node,
	camp_position: Vector3,
	seen: Dictionary
) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not node is Node3D:
		return false

	var instance_id: int = node.get_instance_id()
	if seen.has(instance_id):
		return false

	seen[instance_id] = true

	if CombatTargetValidation.is_neutral_creep(node):
		return false

	if CombatTargetValidation.get_target_current_health(node) <= 0:
		return false

	var unit_position: Vector3 = (node as Node3D).global_position
	return _horizontal_distance(unit_position, camp_position) <= CAMP_RESPAWN_BLOCK_RADIUS


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
