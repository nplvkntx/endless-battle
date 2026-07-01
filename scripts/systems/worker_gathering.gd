class_name WorkerGathering
extends RefCounted

## Shared deposit helpers for worker gathering trips.

static var _enemy_stockpile_warning_shown: bool = false


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
