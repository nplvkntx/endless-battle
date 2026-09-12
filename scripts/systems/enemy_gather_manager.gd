class_name EnemyGatherManager
extends Node

## Enemy worker gather execution only.
## Assigns a worker to mine/chop when told. No strategic rebalance or ratios.
## Does not auto-assign workers — callers must request jobs.

const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const GOLD_MINE_NEAR_CC_DISTANCE: float = 22.0

@export var enemy_command_center_path: NodePath
@export var enemy_gold_mine_path: NodePath

var _starting_gold_mine: GoldMine = null


## Legacy name kept for spawn/construction finish hooks. Not a strategic rebalance.
func request_gather_rebalance() -> void:
	pass


func assign_worker_adaptively(worker: Worker) -> void:
	assign_gather_job(worker, true)


func assign_gather_job(worker: Worker, prefer_gold: bool = false, _force_recovery: bool = false) -> bool:
	if not NodeSafety.is_alive_node(worker):
		return false
	if worker.is_on_construction_trip():
		return false
	if WorkerAiUnstuck.blocks_external_commands(worker):
		return false
	if _resolve_enemy_command_center() == null:
		return false

	var gold_mine: GoldMine = _resolve_gold_mine(worker.global_position)
	var trees: Array[WoodTree] = _resolve_safe_trees()
	if gold_mine == null and trees.is_empty():
		return false

	if prefer_gold and _try_assign_gold_gather(worker, gold_mine):
		return true
	if _try_assign_wood_gather(worker, trees):
		return true
	return _try_assign_gold_gather(worker, gold_mine)


func _try_assign_gold_gather(worker: Worker, gold_mine: GoldMine) -> bool:
	if gold_mine == null or not _is_valid_gold_mine(gold_mine):
		return false
	if worker.is_enemy_gather_target_blacklisted(gold_mine):
		return false
	worker.pin_starting_gold_mine(gold_mine)
	worker.command_gather_gold_mine(gold_mine, false)
	if worker.get_assigned_gather_resource_id() == &"gold" and not worker.needs_gather_target_reassignment():
		return true
	return false


func _try_assign_wood_gather(worker: Worker, trees: Array[WoodTree]) -> bool:
	var tree_target: WoodTree = null
	for tree: WoodTree in trees:
		if NodeSafety.is_alive_node(tree) and tree.can_gather():
			if worker.is_enemy_gather_target_blacklisted(tree):
				continue
			tree_target = tree
			break
	if tree_target == null:
		return false
	worker.command_gather_tree(tree_target, false)
	if worker.get_assigned_gather_resource_id() == &"wood" and not worker.needs_gather_target_reassignment():
		return true
	return false


func _resolve_enemy_command_center() -> CommandCenter:
	if enemy_command_center_path != NodePath(""):
		var via_path: CommandCenter = get_node_or_null(enemy_command_center_path) as CommandCenter
		if via_path != null and NodeSafety.is_alive_node(via_path):
			return via_path
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter and NodeSafety.is_alive_node(node):
			return node as CommandCenter
	return null


func _resolve_gold_mine(worker_position: Vector3 = Vector3.INF) -> GoldMine:
	if enemy_gold_mine_path != NodePath(""):
		var via_path: GoldMine = get_node_or_null(enemy_gold_mine_path) as GoldMine
		if via_path != null and _is_valid_gold_mine(via_path):
			_starting_gold_mine = via_path
	var cc: CommandCenter = _resolve_enemy_command_center()
	if cc == null:
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var best: GoldMine = null
	var best_score: float = INF
	var origin: Vector3 = cc.global_position if worker_position == Vector3.INF else worker_position
	for node: Node in WorkerGathering.get_gatherable_resources(tree, tree.current_scene):
		if not node is GoldMine:
			continue
		var mine: GoldMine = node as GoldMine
		if not _is_valid_gold_mine(mine):
			continue
		if not mine.is_usable_by_faction(true) or not WorkerGathering.is_safe_gather_source(mine, tree):
			continue
		var dropoff: CommandCenter = WorkerGathering.find_nearest_dropoff(mine.global_position, true, tree)
		if dropoff == null or _horizontal_distance(dropoff.global_position, mine.global_position) > GOLD_MINE_NEAR_CC_DISTANCE:
			continue
		var score: float = _horizontal_distance(origin, mine.global_position) + float(mine.get_assigned_worker_count()) * 6.0
		if score < best_score:
			best_score = score
			best = mine
	if best != null:
		_starting_gold_mine = best
	return best


func _resolve_safe_trees() -> Array[WoodTree]:
	var result: Array[WoodTree] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return result
	var cc: CommandCenter = _resolve_enemy_command_center()
	var origin: Vector3 = cc.global_position if cc != null else Vector3.ZERO
	for node: Node in WorkerGathering.get_gatherable_resources(tree, tree.current_scene):
		if not node is WoodTree:
			continue
		var wood_tree: WoodTree = node as WoodTree
		if not NodeSafety.is_alive_node(wood_tree) or not wood_tree.can_gather():
			continue
		if not wood_tree.is_usable_by_faction(true):
			continue
		if not WorkerGathering.is_safe_gather_source(wood_tree, tree):
			continue
		if cc != null:
			var dist: float = _horizontal_distance(origin, wood_tree.global_position)
			if dist > 80.0:
				continue
		result.append(wood_tree)
	result.sort_custom(func(a: WoodTree, b: WoodTree) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	return result


func _is_valid_gold_mine(mine: GoldMine) -> bool:
	return NodeSafety.is_alive_node(mine) and mine.can_gather()


func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var dx: float = from_position.x - to_position.x
	var dz: float = from_position.z - to_position.z
	return sqrt(dx * dx + dz * dz)
