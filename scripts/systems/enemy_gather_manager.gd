class_name EnemyGatherManager
extends Node

## Assigns enemy workers near the enemy Command Center to nearby gather targets.

const ENEMY_WORKER_GROUP := &"enemy_workers"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const REASSIGN_INTERVAL_SECONDS: float = 7.0
const MIN_GOLD_WORKERS: int = 1
const MIN_WOOD_WORKERS: int = 2
const FOOD_RESERVE: int = 2
const WOOD_STOCK_COMFORT: int = 120
const GOLD_STOCK_COMFORT: int = 150

@export var enemy_command_center_path: NodePath
@export var enemy_gold_mine_path: NodePath

var _reassign_active: bool = true


func _ready() -> void:
	call_deferred("_initial_assign_and_schedule")


func _initial_assign_and_schedule() -> void:
	_rebalance_gather_workers()
	_schedule_reassign()


func _schedule_reassign() -> void:
	if not _reassign_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(REASSIGN_INTERVAL_SECONDS)
	wait_timer.timeout.connect(_on_reassign_timer, CONNECT_ONE_SHOT)


func _on_reassign_timer() -> void:
	if not _reassign_active:
		return

	_rebalance_gather_workers()
	_schedule_reassign()


func assign_worker_adaptively(worker: Worker) -> void:
	if not _can_reassign_worker(worker):
		return

	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		return

	var gather_pool: Array[Worker] = _collect_gather_pool(command_center.global_position)
	if gather_pool.is_empty():
		return

	var gold_count: int = 0
	for pool_worker: Worker in gather_pool:
		if pool_worker == worker:
			continue
		if pool_worker.get_assigned_gather_resource_id() == &"gold":
			gold_count += 1

	var target_gold: int = _compute_target_gold_workers(gather_pool.size())
	assign_gather_job(worker, gold_count < target_gold)


func assign_gather_job(worker: Worker, prefer_gold: bool = false) -> void:
	if worker == null or not is_instance_valid(worker):
		return

	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		return

	var gold_mine: GoldMine = _resolve_gold_mine()
	var trees: Array[WoodTree] = _resolve_trees()
	if gold_mine == null and trees.is_empty():
		return

	if prefer_gold and _is_valid_gold_mine(gold_mine):
		worker.command_gather_gold_mine(gold_mine)
		return

	if trees.is_empty():
		if _is_valid_gold_mine(gold_mine):
			worker.command_gather_gold_mine(gold_mine)
		return

	var tree: WoodTree = _pick_tree_for_worker(worker, trees)
	if tree != null and tree.can_gather():
		worker.command_gather_tree(tree)
	elif _is_valid_gold_mine(gold_mine):
		worker.command_gather_gold_mine(gold_mine)


func _rebalance_gather_workers() -> void:
	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		push_warning("EnemyGatherManager: enemy Command Center not found")
		return

	var gather_pool: Array[Worker] = _collect_gather_pool(command_center.global_position)
	if gather_pool.is_empty():
		return

	var gold_workers: Array[Worker] = []
	var wood_workers: Array[Worker] = []
	var unassigned_workers: Array[Worker] = []

	for worker: Worker in gather_pool:
		match worker.get_assigned_gather_resource_id():
			&"gold":
				gold_workers.append(worker)
			&"wood":
				wood_workers.append(worker)
			_:
				unassigned_workers.append(worker)

	var total: int = gather_pool.size()
	var target_gold: int = _compute_target_gold_workers(total)
	var target_wood: int = total - target_gold

	for worker: Worker in unassigned_workers:
		if gold_workers.size() < target_gold:
			assign_gather_job(worker, true)
			gold_workers.append(worker)
		else:
			assign_gather_job(worker, false)
			wood_workers.append(worker)

	while gold_workers.size() > target_gold:
		var worker: Worker = _pick_worker_to_reassign(gold_workers)
		if worker == null:
			break

		gold_workers.erase(worker)
		assign_gather_job(worker, false)
		wood_workers.append(worker)

	while gold_workers.size() < target_gold and wood_workers.size() > target_wood:
		var worker: Worker = _pick_worker_to_reassign(wood_workers)
		if worker == null:
			break

		wood_workers.erase(worker)
		assign_gather_job(worker, true)
		gold_workers.append(worker)


func _compute_target_gold_workers(total_gather_workers: int) -> int:
	if total_gather_workers <= 0:
		return 0

	if total_gather_workers == 1:
		return 1

	var gold_target: int = mini(MIN_GOLD_WORKERS, total_gather_workers)
	var wood_target: int = mini(MIN_WOOD_WORKERS, total_gather_workers - gold_target)
	var remaining: int = total_gather_workers - gold_target - wood_target

	if remaining > 0:
		var bias: float = _compute_gather_bias()
		var gold_share: float = clampf(0.4 + bias * 0.35, 0.25, 0.75)
		var extra_gold: int = int(round(float(remaining) * gold_share))
		gold_target += extra_gold
		wood_target += remaining - extra_gold

	if total_gather_workers >= 2:
		gold_target = clampi(gold_target, 1, total_gather_workers - 1)

	return gold_target


func _compute_gather_bias() -> float:
	var bias: float = 0.0

	var wood_surplus: float = (
		float(EnemyResourceManager.wood - WOOD_STOCK_COMFORT) / float(WOOD_STOCK_COMFORT)
	)
	var gold_surplus: float = (
		float(EnemyResourceManager.gold - GOLD_STOCK_COMFORT) / float(GOLD_STOCK_COMFORT)
	)
	bias += clampf(gold_surplus - wood_surplus, -0.5, 0.5) * 0.6

	if _enemy_needs_wood_for_buildings():
		bias -= 0.35

	if _enemy_needs_gold_for_training():
		bias += 0.35

	return clampf(bias, -1.0, 1.0)


func _enemy_needs_wood_for_buildings() -> bool:
	if EnemyResourceManager.food_max - EnemyResourceManager.food_current <= FOOD_RESERVE:
		return true

	if _has_unfinished_enemy_construction():
		return true

	return EnemyResourceManager.wood < WOOD_STOCK_COMFORT


func _enemy_needs_gold_for_training() -> bool:
	if EnemyResourceManager.gold < GOLD_STOCK_COMFORT:
		return true

	return _is_enemy_training_military_or_hero()


func _has_unfinished_enemy_construction() -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building:
			continue

		var building: Building = node as Building
		if not is_instance_valid(building) or building.is_queued_for_deletion():
			continue

		var state: StringName = building.building_state
		if (
			state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			return true

	return false


func _is_enemy_training_military_or_hero() -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is Barracks:
			var barracks: Barracks = node as Barracks
			if barracks.building_state != Building.STATE_COMPLETED:
				continue
			if barracks.is_training_swordsman() or barracks.is_training_archer():
				return true

		if node is HeroAltar:
			var hero_altar: HeroAltar = node as HeroAltar
			if hero_altar.building_state != Building.STATE_COMPLETED:
				continue
			if hero_altar.is_training_hero():
				return true

	return false


func _collect_gather_pool(command_center_position: Vector3) -> Array[Worker]:
	var gather_pool: Array[Worker] = []

	for worker: Worker in _find_enemy_workers(command_center_position):
		if worker.is_on_construction_trip():
			continue
		gather_pool.append(worker)

	return gather_pool


func _pick_worker_to_reassign(workers: Array[Worker]) -> Worker:
	for worker: Worker in workers:
		if _can_reassign_worker(worker):
			return worker

	return null


func _can_reassign_worker(worker: Worker) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	if worker.is_on_construction_trip():
		return false

	return not worker.is_carrying_gathered_resources()


func _pick_tree_for_worker(worker: Worker, trees: Array[WoodTree]) -> WoodTree:
	if trees.is_empty():
		return null

	var closest_tree: WoodTree = null
	var closest_distance_squared: float = INF
	for tree: WoodTree in trees:
		if tree == null or not tree.can_gather():
			continue

		var distance_squared: float = worker.global_position.distance_squared_to(tree.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_tree = tree

	return closest_tree if closest_tree != null else trees[0]


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
