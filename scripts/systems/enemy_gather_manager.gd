class_name EnemyGatherManager
extends Node

## Assigns enemy workers near the enemy Command Center to nearby gather targets.

const ENEMY_WORKER_GROUP := &"enemy_workers"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"

@export var enemy_command_center_path: NodePath
@export var enemy_gold_mine_path: NodePath


func _ready() -> void:
	call_deferred("_assign_gather_jobs")


func _assign_gather_jobs() -> void:
	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		push_warning("EnemyGatherManager: enemy Command Center not found")
		return

	var gold_mine: GoldMine = _resolve_gold_mine()
	var trees: Array[WoodTree] = _resolve_trees()
	if gold_mine == null and trees.is_empty():
		push_warning("EnemyGatherManager: no enemy gather targets found")
		return

	var workers: Array[Worker] = _find_enemy_workers(command_center.global_position)
	if workers.is_empty():
		push_warning("EnemyGatherManager: no enemy workers found near Command Center")
		return

	var tree_index: int = 0
	for worker_index: int in workers.size():
		var worker: Worker = workers[worker_index]
		if worker == null or not is_instance_valid(worker):
			continue

		if worker_index == 0 and _is_valid_gold_mine(gold_mine):
			worker.command_gather_gold_mine(gold_mine)
			continue

		if trees.is_empty():
			if _is_valid_gold_mine(gold_mine):
				worker.command_gather_gold_mine(gold_mine)
			continue

		var tree: WoodTree = trees[tree_index % trees.size()]
		tree_index += 1
		if tree.can_gather():
			worker.command_gather_tree(tree)
		elif _is_valid_gold_mine(gold_mine):
			worker.command_gather_gold_mine(gold_mine)


func _resolve_enemy_command_center() -> CommandCenter:
	if not enemy_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(enemy_command_center_path)
		if path_node is CommandCenter:
			return path_node as CommandCenter

	for node: Node in get_tree().get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter:
			return node as CommandCenter

	return null


func _resolve_gold_mine() -> GoldMine:
	if not enemy_gold_mine_path.is_empty():
		var path_node: Node = get_node_or_null(enemy_gold_mine_path)
		if path_node is GoldMine:
			return path_node as GoldMine

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	var named_mine: Node = scene_root.get_node_or_null("EnemyGoldMine")
	if named_mine is GoldMine:
		return named_mine as GoldMine

	return null


func _resolve_trees() -> Array[WoodTree]:
	var trees: Array[WoodTree] = []
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return trees

	for child: Node in scene_root.get_children():
		if not child is WoodTree:
			continue
		if not child.name.begins_with("EnemyTree"):
			continue
		trees.append(child as WoodTree)

	trees.sort_custom(
		func(first: WoodTree, second: WoodTree) -> bool:
			return first.name < second.name
	)
	return trees


func _find_enemy_workers(command_center_position: Vector3) -> Array[Worker]:
	var workers: Array[Worker] = []

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not _is_valid_worker(node):
			continue
		workers.append(node as Worker)

	workers.sort_custom(
		func(first: Worker, second: Worker) -> bool:
			var first_distance: float = first.global_position.distance_squared_to(
				command_center_position
			)
			var second_distance: float = second.global_position.distance_squared_to(
				command_center_position
			)
			return first_distance < second_distance
	)
	return workers


func _is_valid_worker(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	return node is Worker


func _is_valid_gold_mine(gold_mine: GoldMine) -> bool:
	return (
		gold_mine != null
		and is_instance_valid(gold_mine)
		and not gold_mine.is_queued_for_deletion()
		and gold_mine.can_gather()
	)
