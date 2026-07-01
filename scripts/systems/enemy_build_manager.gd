class_name EnemyBuildManager
extends Node

## Enemy RTS build order: gather economy, place structures, train units, expand base.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const ENEMY_WORKER_GROUP := &"enemy_workers"
const TICK_INTERVAL_SECONDS: float = 4.0
const TARGET_WORKERS_EARLY: int = 8
const TARGET_WORKERS_MID: int = 10
const TARGET_WORKERS_LATE: int = 12
const MIN_WORKERS_BEFORE_MILITARY: int = 8
const WORKER_PHASE_MID_SECONDS: float = 300.0
const WORKER_PHASE_LATE_SECONDS: float = 600.0
const WORKER_TRAIN_GOLD_COST: int = 50
const FOOD_RESERVE: int = 2
const MAX_FARMS: int = 3
const DEFAULT_MAX_BARRACKS: int = 2
const DESIRED_ARMY_EARLY: int = 8
const DESIRED_ARMY_MID: int = 14
const DESIRED_ARMY_LATE: int = 22
const ARMY_SIZE_MID_AFTER_SECONDS: float = 300.0
const ARMY_SIZE_LATE_AFTER_SECONDS: float = 600.0
const MILITARY_TRAIN_FOOD_COST: int = 1
const ENEMY_TEAM_ID: int = 1

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_BLACKSMITH: StringName = &"blacksmith"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"
const PLACEMENT_COMMAND_CENTER: StringName = &"command_center"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const HEALTH_COMPONENT_SCRIPT: Script = preload("res://scripts/components/health_component.gd")

const FARM_GOLD_COST: int = 80
const FARM_WOOD_COST: int = 20
const BARRACKS_GOLD_COST: int = 150
const BARRACKS_WOOD_COST: int = 100
const BLACKSMITH_GOLD_COST: int = 100
const BLACKSMITH_WOOD_COST: int = 150
const HERO_ALTAR_GOLD_COST: int = 180
const HERO_ALTAR_WOOD_COST: int = 110
const COMMAND_CENTER_GOLD_COST: int = 200
const COMMAND_CENTER_WOOD_COST: int = 400

const CONSTRUCTION_DURATION: float = 4.0
const BARRACKS_MAX_HEALTH: int = 300
const HERO_ALTAR_MAX_HEALTH: int = 350
const COMMAND_CENTER_MAX_HEALTH: int = 500

@export var enemy_command_center_path: NodePath
@export var enemy_gather_manager_path: NodePath
@export var buildings_parent_path: NodePath = NodePath("..")
@export var max_barracks: int = DEFAULT_MAX_BARRACKS

var _primary_command_center: CommandCenter = null
var _train_swordsman_next: bool = true
var _tick_active: bool = true


func _ready() -> void:
	call_deferred("_begin_build_order")


func _begin_build_order() -> void:
	_primary_command_center = _resolve_primary_command_center()
	if _primary_command_center == null:
		push_warning("EnemyBuildManager: enemy Command Center not found")
		return

	_schedule_tick()


func _schedule_tick() -> void:
	if not _tick_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(TICK_INTERVAL_SECONDS)
	wait_timer.timeout.connect(_on_build_tick, CONNECT_ONE_SHOT)


func _on_build_tick() -> void:
	if not _tick_active:
		return

	if _resolve_primary_command_center() == null:
		_tick_active = false
		return

	_run_build_order()
	_schedule_tick()


func _run_build_order() -> void:
	_try_assign_idle_builder_to_construction()

	if _try_train_enemy_workers():
		return

	if _should_grow_worker_economy():
		if _needs_farm() and not _should_defer_gold_spending_for_workers():
			if _try_place_building(PLACEMENT_FARM):
				return
		if _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY:
			return

	var defer_military: bool = _update_enemy_hero_restoration()

	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		return

	if _needs_barracks() and _try_place_building(PLACEMENT_BARRACKS):
		return

	if _needs_farm() and not _should_defer_gold_spending_for_workers():
		if _try_place_building(PLACEMENT_FARM):
			return

	if not _has_completed_building(PLACEMENT_BARRACKS) and not _is_building_type_in_progress(
		PLACEMENT_BARRACKS
	):
		if _try_place_building(PLACEMENT_BARRACKS):
			return

	if _should_build_expansion_barracks():
		if _try_place_building(PLACEMENT_BARRACKS):
			return

	if _should_build_blacksmith():
		if _try_place_building(PLACEMENT_BLACKSMITH):
			return

	_try_sustain_blacksmith_research()

	if not defer_military and _can_train_military_units():
		_try_sustain_military_production()

	if _should_build_expansion_command_center():
		_try_place_building(PLACEMENT_COMMAND_CENTER, true)


func _update_enemy_hero_restoration() -> bool:
	if _has_living_enemy_hero():
		return false

	var hero_altar: HeroAltar = _find_enemy_hero_altar()
	if hero_altar != null and hero_altar.is_training_hero():
		return true

	if hero_altar == null and _should_build_hero_altar():
		_try_place_building(PLACEMENT_HERO_ALTAR)

	if hero_altar != null:
		hero_altar.try_train_enemy_hero()

	return true


func _has_living_enemy_hero() -> bool:
	return EnemyArmyCommand.find_living_enemy_hero(get_tree()) != null


func _needs_barracks() -> bool:
	return (
		not _has_completed_building(PLACEMENT_BARRACKS)
		and not _is_building_type_in_progress(PLACEMENT_BARRACKS)
		and _count_living_military_units() > 0
	)


func _should_build_hero_altar() -> bool:
	if _has_completed_building(PLACEMENT_HERO_ALTAR):
		return false

	if _is_building_type_in_progress(PLACEMENT_HERO_ALTAR):
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < _get_target_worker_count():
		return false

	return true


func _should_build_expansion_barracks() -> bool:
	if _count_barracks() >= max_barracks:
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < _get_target_worker_count():
		return false

	return EnemyResourceManager.can_afford(BARRACKS_GOLD_COST, BARRACKS_WOOD_COST)


func _should_build_blacksmith() -> bool:
	if _has_completed_building(PLACEMENT_BLACKSMITH):
		return false

	if _is_building_type_in_progress(PLACEMENT_BLACKSMITH):
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY:
		return false

	return EnemyResourceManager.can_afford(BLACKSMITH_GOLD_COST, BLACKSMITH_WOOD_COST)


func _try_sustain_blacksmith_research() -> void:
	var blacksmith: Blacksmith = _find_completed_enemy_blacksmith()
	if blacksmith == null:
		return

	if blacksmith.is_researching():
		return

	for upgrade_id: StringName in UpgradeManager.BLACKSMITH_UPGRADE_ORDER:
		if UpgradeManager.is_enemy_max_level(upgrade_id):
			continue

		if not UpgradeManager.can_enemy_afford_upgrade(upgrade_id):
			return

		blacksmith.try_research_upgrade(upgrade_id)
		return


func _find_completed_enemy_blacksmith() -> Blacksmith:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Blacksmith or not _is_living_building(node as Building):
			continue

		var blacksmith: Blacksmith = node as Blacksmith
		if blacksmith.building_state == Building.STATE_COMPLETED:
			return blacksmith

	return null


func _needs_farm() -> bool:
	if _count_farms() >= MAX_FARMS:
		return false

	return EnemyResourceManager.food_max - EnemyResourceManager.food_current <= FOOD_RESERVE


func _should_build_expansion_command_center() -> bool:
	if _count_living_command_centers() >= 2:
		return false

	if _is_building_type_in_progress(PLACEMENT_COMMAND_CENTER):
		return false

	if not _has_completed_building(PLACEMENT_HERO_ALTAR) or not _has_living_enemy_hero():
		return false

	return EnemyResourceManager.can_afford(COMMAND_CENTER_GOLD_COST, COMMAND_CENTER_WOOD_COST)


func _try_train_enemy_workers() -> bool:
	var target_workers: int = _get_target_worker_count()
	if _get_effective_worker_count() >= target_workers:
		return false

	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		return false

	var trained_any: bool = false
	while _get_effective_worker_count() < target_workers:
		if not command_center.try_train_enemy_worker():
			break
		trained_any = true

	return trained_any


func _get_target_worker_count() -> int:
	var elapsed_seconds: float = Time.get_ticks_msec() / 1000.0
	if elapsed_seconds < WORKER_PHASE_MID_SECONDS:
		return TARGET_WORKERS_EARLY
	if elapsed_seconds < WORKER_PHASE_LATE_SECONDS:
		return TARGET_WORKERS_MID

	return TARGET_WORKERS_LATE


func _should_grow_worker_economy() -> bool:
	return _get_effective_worker_count() < _get_target_worker_count()


func _should_defer_gold_spending_for_workers() -> bool:
	if not _should_grow_worker_economy():
		return false

	if not EnemyResourceManager.has_food_supply(1):
		return false

	return EnemyResourceManager.gold < WORKER_TRAIN_GOLD_COST * 2


func _can_train_military_units() -> bool:
	if _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY:
		return false

	return not _should_grow_worker_economy()


func _get_effective_worker_count() -> int:
	return _count_enemy_workers() + _get_pending_worker_count()


func _get_pending_worker_count() -> int:
	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		return 0

	return command_center.get_worker_queue_count()


func _try_sustain_military_production() -> void:
	if not _can_train_military_units():
		return

	if not _needs_more_military_units():
		return

	if not EnemyResourceManager.has_food_supply(MILITARY_TRAIN_FOOD_COST):
		if _count_farms() < MAX_FARMS:
			_try_place_building(PLACEMENT_FARM)
		return

	for barracks: Barracks in _find_all_completed_enemy_barracks():
		if not _needs_more_military_units():
			break

		_try_train_military(barracks)


func _get_desired_army_size() -> int:
	var elapsed_seconds: float = Time.get_ticks_msec() / 1000.0
	if elapsed_seconds < ARMY_SIZE_MID_AFTER_SECONDS:
		return DESIRED_ARMY_EARLY
	if elapsed_seconds < ARMY_SIZE_LATE_AFTER_SECONDS:
		return DESIRED_ARMY_MID

	return DESIRED_ARMY_LATE


func _count_living_military_units() -> int:
	return EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree()).size()


func _count_pending_military_units() -> int:
	var pending: int = 0
	for barracks: Barracks in _find_all_completed_enemy_barracks():
		pending += barracks.get_enemy_pending_unit_count()

	return pending


func _needs_more_military_units() -> bool:
	return (
		_count_living_military_units() + _count_pending_military_units()
		< _get_desired_army_size()
	)


func _try_train_military(barracks: Barracks) -> void:
	if _train_swordsman_next:
		if barracks.try_train_enemy_swordsman():
			_train_swordsman_next = false
			return
		if barracks.try_train_enemy_archer():
			_train_swordsman_next = true
			return
	else:
		if barracks.try_train_enemy_archer():
			_train_swordsman_next = true
			return
		if barracks.try_train_enemy_swordsman():
			_train_swordsman_next = false


func _try_place_building(building_type: StringName, prefer_expansion: bool = false) -> bool:
	if _has_unfinished_construction():
		return false

	var gold_cost: int = 0
	var wood_cost: int = 0
	match building_type:
		PLACEMENT_FARM:
			gold_cost = FARM_GOLD_COST
			wood_cost = FARM_WOOD_COST
		PLACEMENT_BARRACKS:
			gold_cost = BARRACKS_GOLD_COST
			wood_cost = BARRACKS_WOOD_COST
		PLACEMENT_BLACKSMITH:
			gold_cost = BLACKSMITH_GOLD_COST
			wood_cost = BLACKSMITH_WOOD_COST
		PLACEMENT_HERO_ALTAR:
			gold_cost = HERO_ALTAR_GOLD_COST
			wood_cost = HERO_ALTAR_WOOD_COST
		PLACEMENT_COMMAND_CENTER:
			gold_cost = COMMAND_CENTER_GOLD_COST
			wood_cost = COMMAND_CENTER_WOOD_COST
		_:
			return false

	if not EnemyResourceManager.can_afford(gold_cost, wood_cost):
		return false

	var anchor: CommandCenter = _resolve_primary_command_center()
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return false

	var parent: Node = get_node_or_null(buildings_parent_path)
	if parent == null or not parent.is_inside_tree():
		return false

	var existing_buildings: Array[Node3D] = EnemyBuildPlacement.collect_nearby_buildings(
		anchor.global_position,
		parent
	)
	var position: Vector3 = EnemyBuildPlacement.find_position(
		anchor.global_position,
		building_type,
		existing_buildings,
		prefer_expansion,
		parent,
		_get_navigation_map()
	)
	if not position.is_finite():
		return false

	if not EnemyResourceManager.try_spend(gold_cost, wood_cost):
		return false

	var building: Building = _instantiate_building(building_type)
	if building == null:
		return false

	_tag_enemy_building(building)
	_add_health_component_if_needed(building, building_type)
	parent.add_child(building)
	building.global_position = position
	building.start_under_construction()
	building.setup_construction(CONSTRUCTION_DURATION)
	_assign_nearest_builder(building)
	return true


func _instantiate_building(building_type: StringName) -> Building:
	match building_type:
		PLACEMENT_FARM:
			return FARM_SCENE.instantiate() as Building
		PLACEMENT_BARRACKS:
			return BARRACKS_SCENE.instantiate() as Building
		PLACEMENT_BLACKSMITH:
			return BLACKSMITH_SCENE.instantiate() as Building
		PLACEMENT_HERO_ALTAR:
			return HERO_ALTAR_SCENE.instantiate() as Building
		PLACEMENT_COMMAND_CENTER:
			return COMMAND_CENTER_SCENE.instantiate() as Building
		_:
			return null


func _tag_enemy_building(building: Building) -> void:
	building.team_id = ENEMY_TEAM_ID

	if building.is_in_group(&"player_command_center"):
		building.remove_from_group(&"player_command_center")

	if not building.is_in_group(ENEMY_BUILDING_GROUP):
		building.add_to_group(ENEMY_BUILDING_GROUP)

	building.apply_team_visuals()


func _add_health_component_if_needed(building: Building, building_type: StringName) -> void:
	if building.get_node_or_null("HealthComponent") != null:
		return

	var max_health: int = 0
	match building_type:
		PLACEMENT_BARRACKS:
			max_health = BARRACKS_MAX_HEALTH
		PLACEMENT_HERO_ALTAR:
			max_health = HERO_ALTAR_MAX_HEALTH
		PLACEMENT_COMMAND_CENTER:
			max_health = COMMAND_CENTER_MAX_HEALTH
		_:
			return

	var health_component: Node = HEALTH_COMPONENT_SCRIPT.new()
	health_component.name = "HealthComponent"
	health_component.set("max_health", max_health)
	building.add_child(health_component)


func _try_assign_idle_builder_to_construction() -> void:
	for building: Building in _collect_unfinished_buildings():
		if not is_instance_valid(building) or not _is_living_building(building):
			continue

		if _building_has_active_builder(building):
			continue

		_assign_nearest_builder(building)


func _collect_unfinished_buildings() -> Array[Building]:
	var buildings: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Building:
			continue

		var building: Building = node as Building
		if not _is_living_building(building):
			continue

		var state: StringName = building.building_state
		if (
			state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			buildings.append(building)

	return buildings


func _has_unfinished_construction() -> bool:
	return not _collect_unfinished_buildings().is_empty()


func _building_has_active_builder(building: Building) -> bool:
	if building == null or not is_instance_valid(building):
		return false

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not is_instance_valid(worker) or worker.is_queued_for_deletion():
			continue

		if worker.is_assigned_to_build(building):
			return true

	return false


func _assign_nearest_builder(building: Building) -> void:
	var worker: Worker = _find_nearest_available_enemy_worker(building.global_position, false)
	if (
		worker == null
		and building.building_state == Building.STATE_UNDER_CONSTRUCTION
	):
		worker = _find_nearest_available_enemy_worker(building.global_position, true)
	if worker == null:
		return

	worker.command_build(building)


func _find_nearest_available_enemy_worker(
	near_position: Vector3, allow_gather_interrupt: bool = false
) -> Worker:
	var closest_worker: Worker = null
	var closest_distance_squared: float = INF

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not is_instance_valid(worker) or worker.is_queued_for_deletion():
			continue

		if not worker.is_available_for_construction_assignment(allow_gather_interrupt):
			continue

		var offset: Vector3 = worker.global_position - near_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_worker = worker

	return closest_worker


func _get_navigation_map() -> RID:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var agent: NavigationAgent3D = (
			node.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		)
		if agent != null and WorkerTaskNavigation.can_use(agent):
			return agent.get_navigation_map()

	return RID()


func _resolve_primary_command_center() -> CommandCenter:
	if _primary_command_center != null and _is_living_building(_primary_command_center):
		return _primary_command_center

	if not enemy_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(enemy_command_center_path)
		if path_node is CommandCenter and _is_living_building(path_node as CommandCenter):
			_primary_command_center = path_node as CommandCenter
			return _primary_command_center

	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			_primary_command_center = node as CommandCenter
			return _primary_command_center

	return null


func _get_training_command_center() -> CommandCenter:
	var primary: CommandCenter = _resolve_primary_command_center()
	if primary != null:
		return primary

	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			return node as CommandCenter

	return null


func _find_all_completed_enemy_barracks() -> Array[Barracks]:
	var barracks_list: Array[Barracks] = []
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Barracks or not _is_living_building(node as Building):
			continue

		var barracks: Barracks = node as Barracks
		if barracks.building_state == Building.STATE_COMPLETED:
			barracks_list.append(barracks)

	return barracks_list


func _count_barracks() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is Barracks and _is_living_building(node as Building):
			count += 1

	return count


func _find_enemy_hero_altar() -> HeroAltar:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is HeroAltar and _is_living_building(node as Building):
			if (node as HeroAltar).building_state == Building.STATE_COMPLETED:
				return node as HeroAltar

	return null


func _node_matches_building_type(node: Node, building_type: StringName) -> bool:
	match building_type:
		PLACEMENT_FARM:
			return node is Farm
		PLACEMENT_BARRACKS:
			return node is Barracks
		PLACEMENT_BLACKSMITH:
			return node is Blacksmith
		PLACEMENT_HERO_ALTAR:
			return node is HeroAltar
		PLACEMENT_COMMAND_CENTER:
			return node is CommandCenter
		_:
			return false


func _has_completed_building(building_type: StringName) -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not _node_matches_building_type(node, building_type):
			continue
		if not _is_living_building(node as Building):
			continue
		if (node as Building).building_state == Building.STATE_COMPLETED:
			return true

	return false


func _is_building_type_in_progress(building_type: StringName) -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not _node_matches_building_type(node, building_type):
			continue
		if not _is_living_building(node as Building):
			continue

		var state: StringName = (node as Building).building_state
		if (
			state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			return true

	return false


func _count_enemy_workers() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if node is Worker and is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1

	return count


func _count_farms() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is Farm and _is_living_building(node as Building):
			count += 1

	return count


func _count_living_command_centers() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			count += 1

	return count


func _is_living_building(building: Building) -> bool:
	if building == null or not is_instance_valid(building):
		return false

	if building.is_queued_for_deletion():
		return false

	var health_component: HealthComponent = building.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


func _get_enemy_gather_manager() -> EnemyGatherManager:
	if not enemy_gather_manager_path.is_empty():
		var manager: Node = get_node_or_null(enemy_gather_manager_path)
		if manager is EnemyGatherManager:
			return manager as EnemyGatherManager

	return null


func notify_enemy_worker_spawned(worker: Worker) -> void:
	var gather_manager: EnemyGatherManager = _get_enemy_gather_manager()
	if gather_manager == null:
		return

	gather_manager.assign_worker_adaptively(worker)
