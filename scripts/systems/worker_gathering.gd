class_name WorkerGathering
extends RefCounted

## Shared deposit helpers for worker gathering trips.

const PLAYER_DROPOFF_GROUP := &"player_command_center"
const ENEMY_DROPOFF_GROUP := &"enemy_command_center"

static var _enemy_stockpile_warning_shown: bool = false


static func find_nearest_dropoff(
	from_position: Vector3,
	for_enemy: bool,
	tree: SceneTree
) -> CommandCenter:
	if tree == null:
		return null

	var group_name: StringName = (
		ENEMY_DROPOFF_GROUP if for_enemy else PLAYER_DROPOFF_GROUP
	)
	var closest_dropoff: CommandCenter = null
	var closest_distance_squared: float = INF

	for node: Node in tree.get_nodes_in_group(group_name):
		if not node is CommandCenter:
			continue

		var command_center: CommandCenter = node as CommandCenter
		if not is_valid_dropoff(command_center, for_enemy):
			continue

		var offset: Vector3 = from_position - command_center.global_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_dropoff = command_center

	return closest_dropoff


static func is_valid_dropoff(command_center: CommandCenter, for_enemy: bool) -> bool:
	if command_center == null or not is_instance_valid(command_center):
		return false

	if command_center.is_queued_for_deletion():
		return false

	if (
		command_center.building_state == Building.STATE_UNDER_CONSTRUCTION
		or command_center.building_state == Building.STATE_CONSTRUCTING
	):
		return false

	var health_component: HealthComponent = (
		command_center.get_node_or_null("HealthComponent") as HealthComponent
	)
	if health_component != null and health_component.current_health <= 0:
		return false

	if for_enemy:
		if not command_center.is_in_group(ENEMY_DROPOFF_GROUP):
			return false
		if command_center.is_in_group(PLAYER_DROPOFF_GROUP):
			return false
		if (
			command_center.team_id >= 0
			and command_center.team_id != CommandCenter.ENEMY_TEAM_ID
		):
			return false
	else:
		if not command_center.is_in_group(PLAYER_DROPOFF_GROUP):
			return false
		if command_center.is_in_group(ENEMY_DROPOFF_GROUP):
			return false
		if command_center.team_id == CommandCenter.ENEMY_TEAM_ID:
			return false

	return true


static func find_nearest_gather_source(
	resource_id: StringName,
	from_position: Vector3,
	scene_root: Node,
	for_enemy: bool,
	exclude: GatherableResource = null
) -> GatherableResource:
	if scene_root == null or not is_instance_valid(scene_root):
		return null

	var closest_source: GatherableResource = null
	var closest_distance_squared: float = INF

	for node: Node in scene_root.get_children():
		if not _is_matching_gather_source(node, resource_id, for_enemy):
			continue

		var source := node as GatherableResource
		if source == exclude or not _is_usable_gather_source(source):
			continue

		var distance_squared: float = from_position.distance_squared_to(source.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_source = source

	return closest_source


static func _is_matching_gather_source(
	node: Node, resource_id: StringName, for_enemy: bool
) -> bool:
	if for_enemy:
		if not node.name.begins_with("Enemy"):
			return false
	else:
		if node.name.begins_with("Enemy"):
			return false

	match resource_id:
		&"wood":
			return node is WoodTree
		&"gold":
			return node is GoldMine
		_:
			return false


static func _is_usable_gather_source(source: GatherableResource) -> bool:
	return (
		source != null
		and is_instance_valid(source)
		and not source.is_queued_for_deletion()
		and source.can_gather()
	)


static func deposit(resource_id: StringName, amount: int, for_enemy: bool = false) -> void:
	if amount <= 0:
		return

	if for_enemy:
		_deposit_to_enemy_stockpile(resource_id, amount)
		return

	match resource_id:
		&"gold":
			ResourceManager.add_gold(amount)
		&"wood":
			ResourceManager.add_wood(amount)
		_:
			push_error("Unknown gather resource id: %s" % resource_id)


static func _deposit_to_enemy_stockpile(resource_id: StringName, amount: int) -> void:
	if not _is_enemy_stockpile_available():
		_warn_enemy_stockpile_unavailable(resource_id, amount)
		return

	match resource_id:
		&"gold":
			EnemyResourceManager.add_gold(amount)
		&"wood":
			EnemyResourceManager.add_wood(amount)
		_:
			push_error("Unknown gather resource id: %s" % resource_id)


static func _is_enemy_stockpile_available() -> bool:
	if not is_instance_valid(EnemyResourceManager):
		return false

	if not EnemyResourceManager.has_method("is_stockpile_available"):
		return (
			EnemyResourceManager.has_method("add_gold")
			and EnemyResourceManager.has_method("add_wood")
		)

	return EnemyResourceManager.is_stockpile_available()


static func _warn_enemy_stockpile_unavailable(resource_id: StringName, amount: int) -> void:
	if _enemy_stockpile_warning_shown:
		return

	_enemy_stockpile_warning_shown = true
	push_warning(
		"WorkerGathering: enemy stockpile unavailable; dropped %d %s" % [amount, resource_id]
	)
