class_name EnemyGatherManager
extends Node

## Assigns enemy workers near the enemy Command Center to nearby gather targets.

const ENEMY_WORKER_GROUP := &"enemy_workers"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const REASSIGN_INTERVAL_SECONDS: float = 3.0
const EARLY_GAME_GOLD_RATIO: float = 0.6
const BUILDING_PRESSURE_GOLD_RATIO: float = 0.45
const WORKER_TRAIN_GOLD_COST: int = 50
const FARM_WOOD_COST: int = 20
const FOOD_RESERVE: int = 2
const WOOD_STOCK_COMFORT: int = 120
const GOLD_STOCK_COMFORT: int = 150
const RESOURCE_HIGH_THRESHOLD: int = 350
const RESOURCE_CRITICAL_THRESHOLD: int = 100
const TARGET_GOLD_SHIFT_THRESHOLD: int = 2
const MIN_WOOD_WORKERS_WHEN_TREES_EXIST: int = 1
const FALLBACK_IDLE_NEAR_CC_RADIUS: float = 8.0
const STARTING_GOLD_WORKERS: int = 4
const NAV_READY_MAX_FRAMES: int = 60
const DEBUG_AI_WORKER_GATHER: bool = false

@export var enemy_command_center_path: NodePath
@export var enemy_gold_mine_path: NodePath

var _reassign_active: bool = true
var _cached_target_gold: int = -1
var _starting_gold_mine: GoldMine = null


func _ready() -> void:
	call_deferred("_initial_assign_and_schedule")


func _initial_assign_and_schedule() -> void:
	# Wait for scene nodes, navigation agents, and the nav mesh bake to settle.
	var frames_waited: int = 0
	while frames_waited < NAV_READY_MAX_FRAMES:
		await get_tree().process_frame
		frames_waited += 1
		if _is_enemy_navigation_ready():
			break

	_starting_gold_mine = _resolve_starting_gold_mine()
	_assign_starting_workers()
	_rebalance_gather_workers()
	call_deferred("_rebalance_gather_workers")
	_schedule_reassign()


func request_gather_rebalance() -> void:
	call_deferred("_rebalance_gather_workers")


func _schedule_reassign() -> void:
	if not _reassign_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(REASSIGN_INTERVAL_SECONDS)
	wait_timer.timeout.connect(_on_reassign_timer, CONNECT_ONE_SHOT)


func _on_reassign_timer() -> void:
	if not _reassign_active or not is_inside_tree():
		return

	_rebalance_gather_workers()
	_scan_fallback_idle_enemy_workers()
	_schedule_reassign()


func assign_worker_adaptively(worker: Worker) -> void:
	if not _can_reassign_worker(worker):
		return

	request_gather_rebalance()


func assign_gather_job(worker: Worker, prefer_gold: bool = false) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	if not _can_assign_gather_job(worker):
		_debug_log_assign(worker, "blocked_by_mission", prefer_gold)
		return false

	if _resolve_enemy_command_center() == null:
		return false

	var gold_mine: GoldMine = _resolve_starting_gold_mine()
	var trees: Array[WoodTree] = _resolve_safe_trees()
	if gold_mine == null and trees.is_empty():
		_debug_log_assign(worker, "no_resources", prefer_gold)
		return false

	if prefer_gold and _try_assign_gold_gather(worker, gold_mine):
		return true

	if _try_assign_wood_gather(worker, trees):
		return true

	return _try_assign_gold_gather(worker, gold_mine)


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
	var target_gold: int = _apply_target_hysteresis(_compute_target_gold_workers(total), total)
	var target_wood: int = total - target_gold

	_reassign_idle_workers(gather_pool, target_gold)

	gold_workers.clear()
	wood_workers.clear()
	unassigned_workers.clear()

	for worker: Worker in gather_pool:
		match worker.get_assigned_gather_resource_id():
			&"gold":
				gold_workers.append(worker)
			&"wood":
				wood_workers.append(worker)
			_:
				unassigned_workers.append(worker)

	for worker: Worker in unassigned_workers:
		if gold_workers.size() < target_gold:
			if assign_gather_job(worker, true):
				_append_worker_to_gather_bucket(worker, gold_workers, wood_workers)
		elif assign_gather_job(worker, false):
			wood_workers.append(worker)

	while gold_workers.size() > target_gold:
		var worker: Worker = _pick_worker_to_reassign(gold_workers)
		if worker == null:
			break

		gold_workers.erase(worker)
		if (
			assign_gather_job(worker, false)
			and worker.get_assigned_gather_resource_id() == &"wood"
		):
			wood_workers.append(worker)

	while gold_workers.size() < target_gold and wood_workers.size() > target_wood:
		var worker: Worker = _pick_worker_to_reassign(wood_workers)
		if worker == null:
			break

		wood_workers.erase(worker)
		if (
			assign_gather_job(worker, true)
			and worker.get_assigned_gather_resource_id() == &"gold"
		):
			gold_workers.append(worker)

	_assign_still_idle_workers(gather_pool, target_gold)
	_ensure_wood_worker_coverage(gather_pool, target_gold)
	_scan_fallback_idle_enemy_workers()


func _assign_starting_workers() -> void:
	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		return

	var gather_pool: Array[Worker] = _collect_gather_pool(command_center.global_position)
	if gather_pool.is_empty():
		return

	var gold_assigned: int = 0
	for worker: Worker in gather_pool:
		if gold_assigned < STARTING_GOLD_WORKERS:
			if assign_gather_job(worker, true):
				gold_assigned += 1
		else:
			assign_gather_job(worker, false)


func _is_enemy_navigation_ready() -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not _is_valid_worker(node):
			continue

		var agent: NavigationAgent3D = (
			node.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		)
		if agent != null and WorkerTaskNavigation.can_use(agent):
			return true

	return false


func _append_worker_to_gather_bucket(
	worker: Worker, gold_workers: Array[Worker], wood_workers: Array[Worker]
) -> void:
	match worker.get_assigned_gather_resource_id():
		&"gold":
			gold_workers.append(worker)
		&"wood":
			wood_workers.append(worker)


func _compute_target_gold_workers(total_gather_workers: int) -> int:
	if total_gather_workers <= 0:
		return 0

	if total_gather_workers == 1:
		return 1

	var gold_ratio: float = EARLY_GAME_GOLD_RATIO
	if _enemy_needs_wood_for_farms() or _enemy_needs_wood_for_buildings() or _is_wood_heavy_imbalance():
		gold_ratio = BUILDING_PRESSURE_GOLD_RATIO
	elif _enemy_needs_gold_for_worker_training() or _is_gold_heavy_imbalance():
		gold_ratio = 0.72

	var gold_target: int = int(round(float(total_gather_workers) * gold_ratio))
	return clampi(gold_target, 1, total_gather_workers - 1)


func _enemy_needs_gold_for_worker_training() -> bool:
	if EnemyResourceManager.gold >= GOLD_STOCK_COMFORT:
		return false

	return EnemyResourceManager.gold < WORKER_TRAIN_GOLD_COST * 3


func _enemy_needs_wood_for_farms() -> bool:
	if EnemyResourceManager.wood >= WOOD_STOCK_COMFORT:
		return false

	if EnemyResourceManager.food_max - EnemyResourceManager.food_current <= FOOD_RESERVE + 2:
		return true

	return EnemyResourceManager.wood < FARM_WOOD_COST * 3


func _reassign_idle_workers(gather_pool: Array[Worker], target_gold: int) -> void:
	var active_gold: int = 0
	var active_wood: int = 0

	for worker: Worker in gather_pool:
		if _is_idle_gather_worker(worker):
			continue

		match worker.get_assigned_gather_resource_id():
			&"gold":
				active_gold += 1
			&"wood":
				active_wood += 1

	for worker: Worker in gather_pool:
		if not _is_idle_gather_worker(worker):
			continue

		var prefer_gold: bool = active_gold < target_gold
		if assign_gather_job(worker, prefer_gold):
			match worker.get_assigned_gather_resource_id():
				&"gold":
					active_gold += 1
				&"wood":
					active_wood += 1


func _is_idle_gather_worker(worker: Worker) -> bool:
	if not _is_valid_worker(worker):
		return false

	if worker.has_method(&"is_enemy_gather_fallback_idle"):
		return worker.is_enemy_gather_fallback_idle()

	if worker.is_on_construction_trip():
		return false

	if worker.is_carrying_gathered_resources():
		return false

	if worker.needs_gather_target_reassignment():
		return true

	return false


func _assign_still_idle_workers(gather_pool: Array[Worker], target_gold: int) -> void:
	var active_gold: int = 0
	for worker: Worker in gather_pool:
		if (
			worker.get_assigned_gather_resource_id() == &"gold"
			and not _is_idle_gather_worker(worker)
		):
			active_gold += 1

	for worker: Worker in gather_pool:
		if not _is_idle_gather_worker(worker):
			continue

		var prefer_gold: bool = active_gold < target_gold
		if assign_gather_job(worker, prefer_gold):
			if worker.get_assigned_gather_resource_id() == &"gold":
				active_gold += 1


func _ensure_wood_worker_coverage(gather_pool: Array[Worker], target_gold: int) -> void:
	var trees: Array[WoodTree] = _resolve_safe_trees()
	if trees.is_empty() or gather_pool.size() <= 1:
		return

	var min_wood_workers: int = mini(
		MIN_WOOD_WORKERS_WHEN_TREES_EXIST,
		gather_pool.size() - target_gold
	)
	if min_wood_workers <= 0:
		return

	var active_wood: int = 0
	var reassign_candidates: Array[Worker] = []

	for worker: Worker in gather_pool:
		if _is_idle_gather_worker(worker):
			reassign_candidates.append(worker)
			continue

		if worker.get_assigned_gather_resource_id() == &"wood":
			active_wood += 1

	while active_wood < min_wood_workers and not reassign_candidates.is_empty():
		var worker: Worker = reassign_candidates.pop_front()
		if assign_gather_job(worker, false):
			if worker.get_assigned_gather_resource_id() == &"wood":
				active_wood += 1


func _scan_fallback_idle_enemy_workers() -> void:
	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		return

	var trees: Array[WoodTree] = _resolve_safe_trees()
	var gold_mine: GoldMine = _resolve_safe_gold_mine()
	if gold_mine == null and trees.is_empty():
		return

	var idle_workers: Array[Worker] = []
	var total_gather_workers: int = 0
	var active_gold: int = 0

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not _is_valid_worker(node):
			continue

		var worker: Worker = node as Worker
		if worker.is_on_construction_trip():
			continue

		total_gather_workers += 1

		if _is_fallback_idle_enemy_worker(worker, command_center):
			idle_workers.append(worker)
			continue

		if worker.get_assigned_gather_resource_id() == &"gold":
			active_gold += 1

	if idle_workers.is_empty():
		return

	var target_gold: int = _apply_target_hysteresis(
		_compute_target_gold_workers(total_gather_workers),
		maxi(1, total_gather_workers)
	)

	for worker: Worker in idle_workers:
		if not _is_fallback_idle_enemy_worker(worker, command_center):
			continue

		var assigned_id: StringName = worker.get_assigned_gather_resource_id()
		var prefer_gold: bool
		if assigned_id == &"gold":
			prefer_gold = true
		elif assigned_id == &"wood":
			prefer_gold = false
		else:
			prefer_gold = active_gold < target_gold

		if assign_gather_job(worker, prefer_gold):
			if worker.get_assigned_gather_resource_id() == &"gold":
				active_gold += 1


func _is_fallback_idle_enemy_worker(
	worker: Worker, command_center: CommandCenter
) -> bool:
	if not _is_idle_gather_worker(worker):
		return false

	return _is_near_command_center(worker, command_center, FALLBACK_IDLE_NEAR_CC_RADIUS)


func _is_near_command_center(
	worker: Worker, command_center: CommandCenter, radius: float
) -> bool:
	var offset: Vector3 = worker.global_position - command_center.global_position
	offset.y = 0.0
	return offset.length_squared() <= radius * radius


func _try_assign_gold_gather(worker: Worker, gold_mine: GoldMine) -> bool:
	if not _is_valid_gold_mine(gold_mine):
		return false

	if not _can_assign_gather_job(worker):
		return false

	worker.pin_starting_gold_mine(gold_mine)
	worker.command_gather_gold_mine(gold_mine, false)
	if not worker.needs_gather_target_reassignment():
		EnemyUnitMission.try_set_mission(worker, EnemyUnitMission.Mission.ECONOMY)
		_debug_log_assign(worker, "assigned_gold", true)
	return not worker.needs_gather_target_reassignment()


func _try_assign_wood_gather(worker: Worker, trees: Array[WoodTree]) -> bool:
	var tree: WoodTree = _pick_tree_for_worker(worker, trees)
	if tree == null or not tree.can_gather():
		return false

	if not _can_assign_gather_job(worker):
		return false

	worker.command_gather_tree(tree, false)
	if not worker.needs_gather_target_reassignment():
		EnemyUnitMission.try_set_mission(worker, EnemyUnitMission.Mission.ECONOMY)
		_debug_log_assign(worker, "assigned_wood", false)
	return not worker.needs_gather_target_reassignment()


func _apply_target_hysteresis(computed_target: int, total_gather_workers: int) -> int:
	if _cached_target_gold < 0:
		_cached_target_gold = computed_target
		return computed_target

	if _is_resource_critically_imbalanced():
		_cached_target_gold = computed_target
		return computed_target

	if abs(computed_target - _cached_target_gold) >= TARGET_GOLD_SHIFT_THRESHOLD:
		_cached_target_gold = computed_target
		return computed_target

	return clampi(_cached_target_gold, 1, maxi(1, total_gather_workers - 1))


func _is_wood_heavy_imbalance() -> bool:
	return (
		EnemyResourceManager.wood >= RESOURCE_HIGH_THRESHOLD
		and EnemyResourceManager.gold <= RESOURCE_CRITICAL_THRESHOLD
	)


func _is_gold_heavy_imbalance() -> bool:
	return (
		EnemyResourceManager.gold >= RESOURCE_HIGH_THRESHOLD
		and EnemyResourceManager.wood <= RESOURCE_CRITICAL_THRESHOLD
	)


func _is_resource_critically_imbalanced() -> bool:
	return _is_wood_heavy_imbalance() or _is_gold_heavy_imbalance()


func _enemy_needs_wood_for_buildings() -> bool:
	if EnemyResourceManager.wood >= WOOD_STOCK_COMFORT * 2:
		return false

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

	for worker: Worker in NodeSafety.clean_node_array(_find_enemy_workers(command_center_position)):
		if not NodeSafety.is_alive_node(worker):
			continue
		if worker.is_on_construction_trip():
			continue
		gather_pool.append(worker)

	return gather_pool


func _pick_worker_to_reassign(workers: Array[Worker]) -> Worker:
	for worker: Worker in workers:
		if not _is_idle_gather_worker(worker):
			continue
		if _can_reassign_worker(worker):
			return worker

	return null


func _can_reassign_worker(worker: Worker) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	if WorkerAiUnstuck.blocks_external_commands(worker):
		return false

	if worker.is_on_construction_trip():
		return false

	if worker.has_method(&"is_enemy_gather_fallback_idle"):
		if not worker.is_enemy_gather_fallback_idle():
			return false

	if EnemyUnitMission.get_unit_mission(worker) == EnemyUnitMission.Mission.BUILD:
		return false

	return not worker.is_carrying_gathered_resources()


func _can_assign_gather_job(worker: Worker) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	if WorkerAiUnstuck.blocks_external_commands(worker):
		return false

	if worker.is_on_construction_trip():
		return false

	if worker.is_carrying_gathered_resources():
		return false

	if worker.has_method(&"is_enemy_gather_fallback_idle"):
		if not worker.is_enemy_gather_fallback_idle():
			return false

	match EnemyUnitMission.get_unit_mission(worker):
		EnemyUnitMission.Mission.BUILD:
			return false
		EnemyUnitMission.Mission.ATTACK, EnemyUnitMission.Mission.DEFEND:
			return false
		EnemyUnitMission.Mission.CREEP, EnemyUnitMission.Mission.RETREAT:
			return false
		_:
			return true


func _pick_tree_for_worker(worker: Worker, trees: Array[WoodTree]) -> WoodTree:
	if trees.is_empty():
		return null

	var closest_tree: WoodTree = null
	var closest_distance_squared: float = INF
	for tree: WoodTree in trees:
		if tree == null or not is_instance_valid(tree) or not tree.can_gather():
			continue

		var distance_squared: float = worker.global_position.distance_squared_to(tree.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_tree = tree

	return closest_tree


func _resolve_enemy_command_center() -> CommandCenter:
	if not enemy_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(enemy_command_center_path)
		if path_node is CommandCenter:
			return path_node as CommandCenter

	for node: Node in get_tree().get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter:
			return node as CommandCenter

	return null


func _resolve_starting_gold_mine() -> GoldMine:
	if _is_valid_gold_mine(_starting_gold_mine):
		return _starting_gold_mine

	var configured_mine: GoldMine = _resolve_gold_mine()
	if _is_valid_gold_mine(configured_mine):
		_starting_gold_mine = configured_mine
		return configured_mine

	_starting_gold_mine = null
	return null


func _resolve_best_safe_gold_mine(near_position: Vector3) -> GoldMine:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	var source: GatherableResource = WorkerGathering.find_nearest_gather_source(
		&"gold",
		near_position,
		scene_root,
		true,
		null,
		false
	)
	if source is GoldMine:
		return source as GoldMine

	return null


func _resolve_safe_gold_mine() -> GoldMine:
	return _resolve_starting_gold_mine()


func _resolve_safe_trees() -> Array[WoodTree]:
	var trees: Array[WoodTree] = []
	for tree: WoodTree in _resolve_trees():
		if WorkerGathering.is_safe_gather_source(tree, get_tree()):
			trees.append(tree)
	return trees


func _resolve_gold_mine() -> GoldMine:
	if not enemy_gold_mine_path.is_empty():
		var path_node: Node = get_node_or_null(enemy_gold_mine_path)
		if path_node is GoldMine:
			return path_node as GoldMine

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	var named_mine: Node = scene_root.get_node_or_null("MapResources/EnemyGoldMine")
	if named_mine == null:
		named_mine = scene_root.get_node_or_null("EnemyGoldMine")
	if named_mine is GoldMine:
		return named_mine as GoldMine

	return null


func _resolve_trees() -> Array[WoodTree]:
	var trees: Array[WoodTree] = []
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return trees

	var map_resources: Node = scene_root.get_node_or_null("MapResources")
	var search_root: Node = map_resources if map_resources != null else scene_root

	for child: Node in search_root.get_children():
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


func _is_valid_worker(node) -> bool:
	if not NodeSafety.is_alive_node(node):
		return false

	if not node is Worker:
		return false

	var worker: Worker = node as Worker
	return worker.get_current_health() > 0


func _is_valid_gold_mine(gold_mine: GoldMine) -> bool:
	return (
		gold_mine != null
		and is_instance_valid(gold_mine)
		and not gold_mine.is_queued_for_deletion()
		and gold_mine.can_gather()
		and WorkerGathering.is_safe_gather_source(gold_mine, get_tree())
	)


func _debug_log_assign(worker: Worker, reason: String, prefer_gold: bool) -> void:
	if not DEBUG_AI_WORKER_GATHER or worker == null:
		return

	print(
		"[EnemyGatherManager] %s worker=%s prefer_gold=%s assigned=%s idle=%s"
		% [
			reason,
			worker.name,
			prefer_gold,
			worker.get_assigned_gather_resource_id(),
			worker.is_enemy_gather_fallback_idle()
			if worker.has_method(&"is_enemy_gather_fallback_idle")
			else false,
		]
	)
