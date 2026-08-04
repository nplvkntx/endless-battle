class_name EnemyGatherManager
extends Node

## Assigns enemy workers near the enemy Command Center to nearby gather targets.

const ENEMY_WORKER_GROUP := &"enemy_workers"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const REASSIGN_INTERVAL_SECONDS: float = 3.0
const EARLY_GAME_GOLD_RATIO: float = 0.7
const MID_GAME_GOLD_RATIO: float = 0.6
const LATE_GAME_GOLD_RATIO: float = 0.55
const BUILDING_PRESSURE_GOLD_RATIO: float = 0.45
const WORKER_TRAIN_GOLD_COST: int = UnitStats.WORKER_GOLD_COST
const FARM_WOOD_COST: int = BuildingStats.FARM_WOOD_COST
const FOOD_RESERVE: int = 2
const WOOD_STOCK_COMFORT: int = 120
const GOLD_STOCK_COMFORT: int = 150
const RESOURCE_HIGH_THRESHOLD: int = 350
const RESOURCE_CRITICAL_THRESHOLD: int = 100
const TARGET_GOLD_SHIFT_THRESHOLD: int = 2
const MIN_WOOD_WORKERS_WHEN_TREES_EXIST: int = 1
const FALLBACK_IDLE_NEAR_CC_RADIUS: float = 8.0
const STARTING_GOLD_WORKERS: int = 4
const GOLD_MINE_NEAR_CC_DISTANCE: float = 22.0
const MAX_GOLD_MINE_TRANSFERS_PER_REBALANCE: int = 2
const NAV_READY_MAX_FRAMES: int = 60
const DEBUG_AI_WORKER_GATHER: bool = false
const WORKER_REASSIGN_LOG_COOLDOWN_SECONDS: float = 4.0
const WORKER_REASSIGN_SAME_JOB_COOLDOWN_SECONDS: float = 6.0

@export var enemy_command_center_path: NodePath
@export var enemy_gold_mine_path: NodePath

var _reassign_active: bool = true
var _cached_target_gold: int = -1
var _starting_gold_mine: GoldMine = null
var _cached_active_gold_mines: Array[GoldMine] = []
var _cached_active_gold_mines_frame: int = -1
var _director: EnemyStrategicDirector = null
var _last_worker_reassign_log_msec: int = 0
## worker_instance_id -> {resource_id, msec}
var _last_worker_reassign_by_id: Dictionary = {}


func _ready() -> void:
	call_deferred("_initial_assign_and_schedule")


func _initial_assign_and_schedule() -> void:
	_director = get_parent().get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector
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

	var start_usec: int = PerfCounters.begin_section()
	_rebalance_gather_workers()
	_scan_fallback_idle_enemy_workers()
	PerfCounters.end_section("Economy update", start_usec)
	PerfCounters.record_ai_economy_update()
	_schedule_reassign()


func assign_worker_adaptively(worker: Worker) -> void:
	if not _can_reassign_worker(worker):
		return

	request_gather_rebalance()


func assign_gather_job(worker: Worker, prefer_gold: bool = false, force_recovery: bool = false) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false

	if not _can_assign_gather_job(worker, force_recovery):
		_debug_log_assign(worker, "blocked_by_mission", prefer_gold)
		return false

	if _resolve_enemy_command_center() == null:
		return false

	var gold_mine: GoldMine = _resolve_gold_mine_for_worker(worker)
	var trees: Array[WoodTree] = _resolve_safe_trees()
	if gold_mine == null and trees.is_empty():
		_debug_log_assign(worker, "no_resources", prefer_gold)
		return false

	if prefer_gold and _try_assign_gold_gather(worker, gold_mine, force_recovery):
		return true

	if _try_assign_wood_gather(worker, trees, force_recovery):
		return true

	return _try_assign_gold_gather(worker, gold_mine, force_recovery)


func _rebalance_gather_workers() -> void:
	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		push_warning("EnemyGatherManager: enemy Command Center not found")
		return

	var gather_pool: Array[Worker] = _collect_gather_pool(command_center.global_position)
	if gather_pool.is_empty():
		return

	_reserve_opening_farm_builder(gather_pool)
	if gather_pool.is_empty():
		return

	var gold_workers: Array[Worker] = []
	var wood_workers: Array[Worker] = []
	var unassigned_workers: Array[Worker] = []

	for worker_ref: Variant in gather_pool:
		if not NodeSafety.is_alive_node(worker_ref) or not worker_ref is Worker:
			continue
		var worker: Worker = worker_ref as Worker
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

	for worker_ref: Variant in gather_pool:
		if not NodeSafety.is_alive_node(worker_ref) or not worker_ref is Worker:
			continue
		var worker: Worker = worker_ref as Worker
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
	_rebalance_gold_mine_assignments(gather_pool)
	_recover_workers_needing_attention()
	_scan_fallback_idle_enemy_workers()


func _reserve_opening_farm_builder(gather_pool: Array[Worker]) -> void:
	if not _should_reserve_opening_farm_builder():
		return

	if gather_pool.size() <= STARTING_GOLD_WORKERS:
		return

	var reserved: Worker = null
	for worker: Worker in gather_pool:
		if worker.get_assigned_gather_resource_id() == &"gold":
			continue
		reserved = worker
		break

	if reserved == null:
		for worker: Worker in gather_pool:
			if worker.get_assigned_gather_resource_id() != &"gold":
				continue
			if not _can_reassign_worker(worker):
				continue
			reserved = worker
			break

	if reserved == null:
		return

	gather_pool.erase(reserved)


func _should_reserve_opening_farm_builder() -> bool:
	if _director == null:
		return false

	if _director.get_strategic_phase() != EnemyStrategicDirector.StrategicPhase.OPENING:
		return false

	return not _has_enemy_farm_started()


func _has_enemy_farm_started() -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Farm:
			continue

		var farm: Farm = node as Farm
		if not is_instance_valid(farm) or farm.is_queued_for_deletion():
			continue

		var state: StringName = farm.building_state
		if (
			state == Building.STATE_COMPLETED
			or state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			return true

	return false


func _assign_starting_workers() -> void:
	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		return

	var gather_pool: Array[Worker] = _collect_gather_pool(command_center.global_position)
	if gather_pool.is_empty():
		return

	var gold_assigned: int = 0
	for worker: Worker in gather_pool:
		if gold_assigned >= STARTING_GOLD_WORKERS:
			# Leave the fifth+ worker free for the opening first Farm builder.
			break

		if assign_gather_job(worker, true):
			gold_assigned += 1

	if gold_assigned > 0:
		EnemyAIDebug.log_opening("%d workers assigned to gold" % gold_assigned)


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

	# Until the opening Farm starts, keep the reserved gather pool on gold.
	if _should_reserve_opening_farm_builder():
		return total_gather_workers

	if total_gather_workers == 1:
		return 1

	var gold_ratio: float = _get_phase_gold_ratio()
	if _enemy_needs_wood_for_farms() or _enemy_needs_wood_for_buildings() or _is_wood_heavy_imbalance():
		gold_ratio = BUILDING_PRESSURE_GOLD_RATIO
	elif _enemy_needs_gold_for_worker_training() or _is_gold_heavy_imbalance():
		gold_ratio = maxf(gold_ratio, 0.72)

	var gold_target: int = int(round(float(total_gather_workers) * gold_ratio))
	return clampi(gold_target, 1, total_gather_workers - 1)


func _get_phase_gold_ratio() -> float:
	if _director == null:
		return EARLY_GAME_GOLD_RATIO

	match _director.get_strategic_phase():
		EnemyStrategicDirector.StrategicPhase.OPENING, \
		EnemyStrategicDirector.StrategicPhase.EARLY_ARMY, \
		EnemyStrategicDirector.StrategicPhase.CREEPING, \
		EnemyStrategicDirector.StrategicPhase.TIER_2:
			return EARLY_GAME_GOLD_RATIO
		EnemyStrategicDirector.StrategicPhase.EXPANSION, \
		EnemyStrategicDirector.StrategicPhase.MID_GAME, \
		EnemyStrategicDirector.StrategicPhase.TIER_3:
			return MID_GAME_GOLD_RATIO
		_:
			return LATE_GAME_GOLD_RATIO


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


func _recover_workers_needing_attention() -> void:
	var command_center: CommandCenter = _resolve_enemy_command_center()
	if command_center == null:
		return

	var trees: Array[WoodTree] = _resolve_safe_trees()
	var has_any_resources: bool = (
		not _collect_active_gold_mines().is_empty()
		or _resolve_starting_gold_mine() != null
		or not trees.is_empty()
	)
	if not has_any_resources:
		return

	var total_gather_workers: int = 0
	var active_gold: int = 0
	var recovery_workers: Array[Worker] = []

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not _is_valid_worker(node):
			continue

		var worker: Worker = node as Worker
		if worker.is_on_construction_trip():
			continue

		total_gather_workers += 1
		if worker.get_assigned_gather_resource_id() == &"gold":
			active_gold += 1

		if not worker.needs_enemy_worker_recovery():
			continue

		if worker.get_enemy_recovery_cooldown() > 0.0:
			continue

		if not worker.can_enemy_economy_force_reassign():
			continue

		recovery_workers.append(worker)

	if recovery_workers.is_empty():
		return

	var target_gold: int = _apply_target_hysteresis(
		_compute_target_gold_workers(maxi(1, total_gather_workers)),
		maxi(1, total_gather_workers)
	)

	for worker: Worker in recovery_workers:
		var prefer_gold: bool = active_gold < target_gold
		if _force_recover_worker(worker, prefer_gold):
			if worker.get_assigned_gather_resource_id() == &"gold":
				active_gold += 1


func _force_recover_worker(worker: Worker, prefer_gold: bool) -> bool:
	if not NodeSafety.is_alive_node(worker):
		return false
	if not worker.needs_enemy_worker_recovery():
		return false
	if worker.get_enemy_recovery_cooldown() > 0.0:
		return false
	if not worker.can_enemy_economy_force_reassign():
		return false

	var desired_resource: StringName = &"gold" if prefer_gold else &"wood"
	var current_resource: StringName = worker.get_assigned_gather_resource_id()
	var worker_id: int = worker.get_instance_id()
	if _last_worker_reassign_by_id.has(worker_id):
		var prev: Dictionary = _last_worker_reassign_by_id[worker_id]
		var age_sec: float = float(Time.get_ticks_msec() - int(prev.get("msec", 0))) / 1000.0
		if (
			age_sec < WORKER_REASSIGN_SAME_JOB_COOLDOWN_SECONDS
			and StringName(prev.get("resource_id", &"")) == desired_resource
			and current_resource == desired_resource
		):
			return false

	## Already gathering the intended resource with a living order — do not reissue.
	if current_resource == desired_resource and not worker.is_enemy_gather_fallback_idle():
		if not worker.needs_gather_target_reassignment():
			return false

	if not worker.prepare_for_enemy_economy_reassign(""):
		return false

	if not assign_gather_job(worker, prefer_gold, true):
		return false

	var assigned: StringName = worker.get_assigned_gather_resource_id()
	_last_worker_reassign_by_id[worker_id] = {
		"resource_id": assigned,
		"msec": Time.get_ticks_msec(),
	}
	_log_worker_reassign(assigned)
	return true


func _log_worker_reassign(assigned: StringName) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if (
		now_msec - _last_worker_reassign_log_msec
		< int(WORKER_REASSIGN_LOG_COOLDOWN_SECONDS * 1000.0)
	):
		return
	_last_worker_reassign_log_msec = now_msec
	match assigned:
		&"gold":
			print("AI WORKER: reassigned idle worker to gold")
		&"wood":
			print("AI WORKER: reassigned idle worker to wood")
		_:
			print("AI WORKER: reassigned idle worker to economy")


func _scan_fallback_idle_enemy_workers() -> void:
	var command_centers: Array[CommandCenter] = _collect_completed_enemy_command_centers()
	if command_centers.is_empty():
		var primary: CommandCenter = _resolve_enemy_command_center()
		if primary == null:
			return
		command_centers.append(primary)

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

		if _is_fallback_idle_enemy_worker(worker, command_centers):
			idle_workers.append(worker)
			continue

		if worker.get_assigned_gather_resource_id() == &"gold":
			active_gold += 1

	if idle_workers.is_empty():
		return

	if _should_reserve_opening_farm_builder() and idle_workers.size() > 0:
		# Keep one idle worker free for the opening first Farm.
		var reserved_index: int = 0
		for index: int in range(idle_workers.size()):
			if idle_workers[index].get_assigned_gather_resource_id() != &"gold":
				reserved_index = index
				break
		idle_workers.remove_at(reserved_index)
		if idle_workers.is_empty():
			return

	var target_gold: int = _apply_target_hysteresis(
		_compute_target_gold_workers(total_gather_workers),
		maxi(1, total_gather_workers)
	)

	for worker: Worker in idle_workers:
		if not _is_fallback_idle_enemy_worker(worker, command_centers):
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
	worker: Worker, command_centers: Array[CommandCenter]
) -> bool:
	if not _is_idle_gather_worker(worker):
		return false

	for command_center: CommandCenter in command_centers:
		if not NodeSafety.is_alive_node(command_center):
			continue
		if _is_near_command_center(worker, command_center, FALLBACK_IDLE_NEAR_CC_RADIUS):
			return true

	return false


func _is_near_command_center(
	worker: Worker, command_center: CommandCenter, radius: float
) -> bool:
	var offset: Vector3 = worker.global_position - command_center.global_position
	offset.y = 0.0
	return offset.length_squared() <= radius * radius


func _try_assign_gold_gather(
	worker: Worker,
	gold_mine: GoldMine,
	force_recovery: bool = false,
	allow_active_transfer: bool = false
) -> bool:
	if gold_mine == null or worker.is_enemy_gather_target_blacklisted(gold_mine):
		return false

	if not _is_valid_gold_mine(gold_mine):
		return false

	if _is_worker_already_gathering_from_mine(worker, gold_mine):
		EnemyUnitMission.try_set_mission(worker, EnemyUnitMission.Mission.ECONOMY)
		return true

	if not _can_assign_gather_job(worker, force_recovery, allow_active_transfer):
		return false

	worker.pin_starting_gold_mine(gold_mine)
	worker.command_gather_gold_mine(gold_mine, false)
	if not worker.needs_gather_target_reassignment():
		EnemyUnitMission.try_set_mission(worker, EnemyUnitMission.Mission.ECONOMY)
		_debug_log_assign(worker, "assigned_gold", true)
	return not worker.needs_gather_target_reassignment()


func _try_assign_wood_gather(worker: Worker, trees: Array[WoodTree], force_recovery: bool = false) -> bool:
	var tree: WoodTree = _pick_tree_for_worker(worker, trees)
	if tree == null or not tree.can_gather():
		return false

	if not _can_assign_gather_job(worker, force_recovery):
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

	if _has_missing_tier_1_setup_buildings():
		return true

	return EnemyResourceManager.wood < WOOD_STOCK_COMFORT


func _has_missing_tier_1_setup_buildings() -> bool:
	if _director == null:
		return false

	if _director.get_strategic_phase() != EnemyStrategicDirector.StrategicPhase.TIER_2:
		return false

	for building_type: StringName in TechTree.get_core_setup_buildings_for_command_center_tier(1):
		if not _enemy_has_building_type_completed_or_building(building_type):
			return true
	return false


func _enemy_has_building_type_completed_or_building(building_type: StringName) -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building:
			continue
		var building: Building = node as Building
		if not is_instance_valid(building) or building.is_queued_for_deletion():
			continue
		if not _node_matches_core_building_type(building, building_type):
			continue
		var state: StringName = building.building_state
		if (
			state == Building.STATE_COMPLETED
			or state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			return true
	return false


func _node_matches_core_building_type(node: Building, building_type: StringName) -> bool:
	match building_type:
		&"farm":
			return node is Farm
		&"barracks":
			return node is Barracks
		&"hero_altar":
			return node is HeroAltar
		&"shop":
			return node is Shop
		&"blacksmith":
			return node is Blacksmith
		_:
			return false


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

	for worker_ref: Variant in NodeSafety.clean_node_array(_find_enemy_workers(command_center_position)):
		if not NodeSafety.is_alive_node(worker_ref) or not worker_ref is Worker:
			continue
		var worker: Worker = worker_ref as Worker
		if worker.is_on_construction_trip():
			continue
		gather_pool.append(worker)

	return gather_pool


func _pick_worker_to_reassign(workers: Array[Worker]) -> Worker:
	for worker_ref: Variant in workers:
		if not NodeSafety.is_alive_node(worker_ref) or not worker_ref is Worker:
			continue
		var worker: Worker = worker_ref as Worker
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
		if (
			not worker.is_enemy_gather_fallback_idle()
			and not worker.needs_gather_target_reassignment()
		):
			return false

	if EnemyUnitMission.get_unit_mission(worker) == EnemyUnitMission.Mission.BUILD:
		return false

	return not worker.is_carrying_gathered_resources()


func _can_assign_gather_job(
	worker: Worker,
	force_recovery: bool = false,
	allow_active_transfer: bool = false
) -> bool:
	if not NodeSafety.is_alive_node(worker) or not worker is Worker:
		return false

	if WorkerAiUnstuck.blocks_external_commands(worker):
		if not force_recovery or not worker.can_enemy_economy_force_reassign():
			return false

	if worker.is_on_construction_trip():
		return false

	if worker.is_carrying_gathered_resources():
		return false

	if force_recovery:
		if not worker.needs_enemy_worker_recovery():
			return false
		if not worker.can_enemy_economy_force_reassign():
			return false
	elif allow_active_transfer:
		if not worker.can_enemy_economy_force_reassign():
			return false
	elif worker.has_method(&"is_enemy_gather_fallback_idle"):
		if (
			not worker.is_enemy_gather_fallback_idle()
			and not worker.needs_gather_target_reassignment()
		):
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
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	var exclude: GatherableResource = null
	for tree: WoodTree in trees:
		if tree == null or not is_instance_valid(tree) or not tree.can_gather():
			continue
		if worker.is_enemy_gather_target_blacklisted(tree):
			exclude = tree
			break

	var best_tree: WoodTree = WorkerGathering.find_best_wood_tree(
		worker.global_position,
		scene_root,
		true,
		null,
		exclude,
		false
	)
	if best_tree != null and not worker.is_enemy_gather_target_blacklisted(best_tree):
		return best_tree

	for tree: WoodTree in trees:
		if tree == null or not is_instance_valid(tree) or not tree.can_gather():
			continue
		if worker.is_enemy_gather_target_blacklisted(tree):
			continue
		return tree

	return null


func _resolve_gold_mine_for_worker(worker: Worker) -> GoldMine:
	if not NodeSafety.is_alive_node(worker):
		return null

	var active_mines: Array[GoldMine] = _collect_active_gold_mines()
	if active_mines.is_empty():
		var starting_mine: GoldMine = _resolve_starting_gold_mine()
		if (
			_is_valid_gold_mine(starting_mine)
			and not worker.is_enemy_gather_target_blacklisted(starting_mine)
		):
			return starting_mine
		return null

	var current_mine: GoldMine = _get_worker_assigned_gold_mine(worker)
	if (
		_is_valid_gold_mine(current_mine)
		and active_mines.has(current_mine)
		and not worker.is_enemy_gather_target_blacklisted(current_mine)
		and not worker.needs_gather_target_reassignment()
	):
		return current_mine

	return _pick_understaffed_gold_mine(
		worker,
		active_mines,
		_count_workers_per_active_mine(active_mines)
	)


func _count_workers_per_active_mine(active_mines: Array[GoldMine]) -> Dictionary:
	var assigned_counts: Dictionary = {}
	for mine: GoldMine in active_mines:
		assigned_counts[mine.get_instance_id()] = 0

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not _is_valid_worker(node):
			continue

		var worker: Worker = node as Worker
		if worker.get_assigned_gather_resource_id() != &"gold":
			continue

		var mine: GoldMine = _get_worker_assigned_gold_mine(worker)
		if mine == null or not assigned_counts.has(mine.get_instance_id()):
			continue

		assigned_counts[mine.get_instance_id()] = int(assigned_counts[mine.get_instance_id()]) + 1

	return assigned_counts


func _rebalance_gold_mine_assignments(gather_pool: Array[Worker]) -> void:
	var active_mines: Array[GoldMine] = _collect_active_gold_mines()
	if active_mines.is_empty():
		return

	var gold_workers: Array[Worker] = []
	for worker: Worker in gather_pool:
		if not NodeSafety.is_alive_node(worker):
			continue
		if worker.get_assigned_gather_resource_id() != &"gold":
			continue
		gold_workers.append(worker)

	if gold_workers.is_empty():
		return

	var assigned_counts: Dictionary = {}
	for mine: GoldMine in active_mines:
		assigned_counts[mine.get_instance_id()] = 0

	var invalid_workers: Array[Worker] = []
	for worker: Worker in gold_workers:
		var mine: GoldMine = _get_worker_assigned_gold_mine(worker)
		if (
			_is_valid_gold_mine(mine)
			and assigned_counts.has(mine.get_instance_id())
			and not worker.is_enemy_gather_target_blacklisted(mine)
			and not worker.needs_gather_target_reassignment()
		):
			assigned_counts[mine.get_instance_id()] = (
				int(assigned_counts[mine.get_instance_id()]) + 1
			)
		else:
			invalid_workers.append(worker)

	var transfers_remaining: int = MAX_GOLD_MINE_TRANSFERS_PER_REBALANCE

	# Always repair invalid / depleted / blocked mine assignments first.
	for worker: Worker in invalid_workers:
		if transfers_remaining <= 0:
			break
		var target_mine: GoldMine = _pick_understaffed_gold_mine(
			worker,
			active_mines,
			assigned_counts
		)
		if target_mine == null:
			continue
		if _try_assign_gold_gather(worker, target_mine, false, true):
			_increment_mine_count(assigned_counts, target_mine)
			transfers_remaining -= 1

	if transfers_remaining <= 0 or active_mines.size() <= 1:
		return

	var target_counts: Dictionary = _compute_gold_mine_target_counts(
		gold_workers.size(),
		active_mines
	)

	while transfers_remaining > 0:
		var overstaffed: GoldMine = _find_most_overstaffed_mine(
			active_mines,
			assigned_counts,
			target_counts
		)
		var understaffed: GoldMine = _find_most_understaffed_mine(
			active_mines,
			assigned_counts,
			target_counts
		)
		if overstaffed == null or understaffed == null or overstaffed == understaffed:
			break

		var transfer_worker: Worker = _pick_gold_worker_from_mine(
			gold_workers,
			overstaffed,
			true
		)
		if transfer_worker == null:
			transfer_worker = _pick_gold_worker_from_mine(gold_workers, overstaffed, false)
		if transfer_worker == null:
			break

		if not _try_assign_gold_gather(transfer_worker, understaffed, false, true):
			break

		_decrement_mine_count(assigned_counts, overstaffed)
		_increment_mine_count(assigned_counts, understaffed)
		transfers_remaining -= 1


func _compute_gold_mine_target_counts(
	gold_worker_count: int,
	active_mines: Array[GoldMine]
) -> Dictionary:
	var targets: Dictionary = {}
	var mine_count: int = active_mines.size()
	if mine_count <= 0 or gold_worker_count <= 0:
		for mine: GoldMine in active_mines:
			targets[mine.get_instance_id()] = 0
		return targets

	var base_share: int = gold_worker_count / mine_count
	var remainder: int = gold_worker_count % mine_count

	# Prefer keeping leftover workers on the starting mine when present.
	var starting_mine: GoldMine = _resolve_starting_gold_mine()
	var ordered_mines: Array[GoldMine] = active_mines.duplicate()
	if _is_valid_gold_mine(starting_mine) and ordered_mines.has(starting_mine):
		ordered_mines.erase(starting_mine)
		ordered_mines.push_front(starting_mine)

	for index: int in range(ordered_mines.size()):
		var share: int = base_share
		if index < remainder:
			share += 1
		targets[ordered_mines[index].get_instance_id()] = share

	return targets


func _pick_understaffed_gold_mine(
	worker: Worker,
	active_mines: Array[GoldMine],
	assigned_counts: Dictionary
) -> GoldMine:
	var best_mine: GoldMine = null
	var best_count: int = 999999
	var best_distance_sq: float = INF

	for mine: GoldMine in active_mines:
		if not _is_valid_gold_mine(mine):
			continue
		if worker.is_enemy_gather_target_blacklisted(mine):
			continue

		var count: int = int(assigned_counts.get(mine.get_instance_id(), 0))
		var distance_sq: float = worker.global_position.distance_squared_to(mine.global_position)
		if count < best_count or (count == best_count and distance_sq < best_distance_sq):
			best_count = count
			best_distance_sq = distance_sq
			best_mine = mine

	return best_mine


func _find_most_overstaffed_mine(
	active_mines: Array[GoldMine],
	assigned_counts: Dictionary,
	target_counts: Dictionary
) -> GoldMine:
	var best_mine: GoldMine = null
	var best_excess: int = 0

	for mine: GoldMine in active_mines:
		var assigned: int = int(assigned_counts.get(mine.get_instance_id(), 0))
		var target: int = int(target_counts.get(mine.get_instance_id(), 0))
		var excess: int = assigned - target
		if excess > best_excess:
			best_excess = excess
			best_mine = mine

	return best_mine


func _find_most_understaffed_mine(
	active_mines: Array[GoldMine],
	assigned_counts: Dictionary,
	target_counts: Dictionary
) -> GoldMine:
	var best_mine: GoldMine = null
	var best_deficit: int = 0

	for mine: GoldMine in active_mines:
		var assigned: int = int(assigned_counts.get(mine.get_instance_id(), 0))
		var target: int = int(target_counts.get(mine.get_instance_id(), 0))
		var deficit: int = target - assigned
		if deficit > best_deficit:
			best_deficit = deficit
			best_mine = mine

	return best_mine


func _pick_gold_worker_from_mine(
	gold_workers: Array[Worker],
	mine: GoldMine,
	prefer_idle: bool
) -> Worker:
	for worker: Worker in gold_workers:
		if not NodeSafety.is_alive_node(worker):
			continue
		if _get_worker_assigned_gold_mine(worker) != mine:
			continue
		if worker.is_carrying_gathered_resources() or worker.is_on_construction_trip():
			continue

		match EnemyUnitMission.get_unit_mission(worker):
			EnemyUnitMission.Mission.BUILD:
				continue
			EnemyUnitMission.Mission.ATTACK, EnemyUnitMission.Mission.DEFEND:
				continue
			EnemyUnitMission.Mission.CREEP, EnemyUnitMission.Mission.RETREAT:
				continue
			_:
				pass

		if prefer_idle and not _is_idle_gather_worker(worker):
			continue
		if not prefer_idle and _is_idle_gather_worker(worker):
			continue
		if not worker.can_enemy_economy_force_reassign():
			continue
		return worker

	return null


func _increment_mine_count(assigned_counts: Dictionary, mine: GoldMine) -> void:
	if mine == null:
		return
	var mine_id: int = mine.get_instance_id()
	assigned_counts[mine_id] = int(assigned_counts.get(mine_id, 0)) + 1


func _decrement_mine_count(assigned_counts: Dictionary, mine: GoldMine) -> void:
	if mine == null:
		return
	var mine_id: int = mine.get_instance_id()
	assigned_counts[mine_id] = maxi(0, int(assigned_counts.get(mine_id, 0)) - 1)


func _get_worker_assigned_gold_mine(worker: Worker) -> GoldMine:
	if not NodeSafety.is_alive_node(worker):
		return null

	var pinned_mine: GoldMine = worker.get_pinned_starting_gold_mine()
	if NodeSafety.is_alive_node(pinned_mine) and pinned_mine is GoldMine:
		return pinned_mine as GoldMine

	return null


func _is_worker_already_gathering_from_mine(worker: Worker, gold_mine: GoldMine) -> bool:
	if not NodeSafety.is_alive_node(worker) or not _is_valid_gold_mine(gold_mine):
		return false

	if worker.get_assigned_gather_resource_id() != &"gold":
		return false

	if worker.needs_gather_target_reassignment():
		return false

	var pinned_mine: GoldMine = worker.get_pinned_starting_gold_mine()
	return pinned_mine == gold_mine


func _collect_active_gold_mines() -> Array[GoldMine]:
	var frame: int = Engine.get_process_frames()
	if frame == _cached_active_gold_mines_frame:
		return _cached_active_gold_mines

	_cached_active_gold_mines_frame = frame
	_cached_active_gold_mines.clear()

	var command_centers: Array[CommandCenter] = _collect_completed_enemy_command_centers()
	if command_centers.is_empty():
		return _cached_active_gold_mines

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return _cached_active_gold_mines

	var seen_ids: Dictionary = {}
	for command_center: CommandCenter in command_centers:
		var mine: GoldMine = _find_gold_mine_near_command_center(command_center, scene_root)
		if not _is_valid_gold_mine(mine):
			continue
		if _is_mine_occupied_by_player(mine):
			continue

		var mine_id: int = mine.get_instance_id()
		if seen_ids.has(mine_id):
			continue

		seen_ids[mine_id] = true
		_cached_active_gold_mines.append(mine)

	return _cached_active_gold_mines


func _collect_completed_enemy_command_centers() -> Array[CommandCenter]:
	var centers: Array[CommandCenter] = []

	if not enemy_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(enemy_command_center_path)
		if _is_completed_enemy_command_center(path_node):
			centers.append(path_node as CommandCenter)

	for node: Node in get_tree().get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not _is_completed_enemy_command_center(node):
			continue
		if centers.has(node):
			continue
		centers.append(node as CommandCenter)

	return centers


func _is_completed_enemy_command_center(node: Variant) -> bool:
	if not NodeSafety.is_alive_node(node) or not node is CommandCenter:
		return false

	var command_center: CommandCenter = node as CommandCenter
	if command_center.building_state != Building.STATE_COMPLETED:
		return false

	var health_component: HealthComponent = (
		command_center.get_node_or_null("HealthComponent") as HealthComponent
	)
	if health_component != null and health_component.current_health <= 0:
		return false

	return true


func _find_gold_mine_near_command_center(
	command_center: CommandCenter,
	scene_root: Node
) -> GoldMine:
	if not NodeSafety.is_alive_node(command_center) or scene_root == null:
		return null

	var best_mine: GoldMine = null
	var best_distance: float = INF
	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if not NodeSafety.is_alive_node(child) or not child is GoldMine:
			continue

		var mine: GoldMine = child as GoldMine
		if not mine.can_gather():
			continue
		if not mine.is_usable_by_faction(true):
			continue
		if not WorkerGathering.is_safe_gather_source(mine, get_tree()):
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			mine.global_position,
			command_center.global_position
		)
		if distance > GOLD_MINE_NEAR_CC_DISTANCE:
			continue

		if distance < best_distance:
			best_distance = distance
			best_mine = mine

	return best_mine


func _is_mine_occupied_by_player(mine: GoldMine) -> bool:
	if not NodeSafety.is_alive_node(mine):
		return true

	for node: Node in get_tree().get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if not NodeSafety.is_alive_node(node) or not node is CommandCenter:
			continue

		var command_center: CommandCenter = node as CommandCenter
		if command_center.building_state != Building.STATE_COMPLETED:
			continue

		var health_component: HealthComponent = (
			command_center.get_node_or_null("HealthComponent") as HealthComponent
		)
		if health_component != null and health_component.current_health <= 0:
			continue

		if (
			EnemyArmyCommand.horizontal_distance(
				mine.global_position,
				command_center.global_position
			)
			<= GOLD_MINE_NEAR_CC_DISTANCE
		):
			return true

	return false


func _resolve_enemy_command_center() -> CommandCenter:
	var centers: Array[CommandCenter] = _collect_completed_enemy_command_centers()
	if not centers.is_empty():
		return centers[0]

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
	var active_mines: Array[GoldMine] = _collect_active_gold_mines()
	var best_mine: GoldMine = null
	var best_distance_sq: float = INF
	for mine: GoldMine in active_mines:
		if not _is_valid_gold_mine(mine):
			continue
		var distance_sq: float = near_position.distance_squared_to(mine.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_mine = mine

	if best_mine != null:
		return best_mine

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
	var active_mines: Array[GoldMine] = _collect_active_gold_mines()
	for mine: GoldMine in active_mines:
		if _is_valid_gold_mine(mine):
			return mine

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

	var from_position: Vector3 = Vector3(38.0, 0.0, 38.0)
	var centers: Array[CommandCenter] = _collect_completed_enemy_command_centers()
	if not centers.is_empty():
		from_position = centers[0].global_position

	return WorkerGathering.find_best_gold_mine(
		from_position,
		scene_root,
		true,
		null,
		null,
		false
	)


func _resolve_trees() -> Array[WoodTree]:
	var trees: Array[WoodTree] = []
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return trees

	for node: Node in WorkerGathering.get_gatherable_resources(get_tree(), scene_root):
		if not node is WoodTree:
			continue
		var wood_tree := node as WoodTree
		if not wood_tree.is_usable_by_faction(true):
			continue
		if not wood_tree.can_gather():
			continue
		trees.append(wood_tree)

	trees.sort_custom(
		func(first: WoodTree, second: WoodTree) -> bool:
			return first.get_instance_id() < second.get_instance_id()
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
		NodeSafety.is_alive_node(gold_mine)
		and gold_mine is GoldMine
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
