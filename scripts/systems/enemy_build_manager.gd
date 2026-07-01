class_name EnemyBuildManager
extends Node

## Enemy RTS build order: gather economy, place structures, train units, expand base.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const ENEMY_WORKER_GROUP := &"enemy_workers"
const TICK_INTERVAL_SECONDS: float = 4.0
const TARGET_WORKERS: int = 8
const FOOD_RESERVE: int = 2
const MAX_FARMS: int = 3
const ENEMY_TEAM_ID: int = 1

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"
const PLACEMENT_COMMAND_CENTER: StringName = &"command_center"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const HEALTH_COMPONENT_SCRIPT: Script = preload("res://scripts/components/health_component.gd")

const FARM_GOLD_COST: int = 80
const FARM_WOOD_COST: int = 20
const BARRACKS_GOLD_COST: int = 150
const BARRACKS_WOOD_COST: int = 100
const HERO_ALTAR_GOLD_COST: int = 180
const HERO_ALTAR_WOOD_COST: int = 110
const COMMAND_CENTER_GOLD_COST: int = 200
const COMMAND_CENTER_WOOD_COST: int = 400

const CONSTRUCTION_DURATION: float = 3.0
const BARRACKS_MAX_HEALTH: int = 300
const HERO_ALTAR_MAX_HEALTH: int = 350
const COMMAND_CENTER_MAX_HEALTH: int = 500

@export var enemy_command_center_path: NodePath
@export var enemy_gather_manager_path: NodePath
@export var buildings_parent_path: NodePath = NodePath("..")

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

	var defer_military: bool = _update_enemy_hero_restoration()

	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		return

	if _needs_barracks() and _try_place_building(PLACEMENT_BARRACKS):
		return

	if _needs_farm() and _try_place_building(PLACEMENT_FARM):
		return

	if not _has_completed_building(PLACEMENT_BARRACKS) and not _is_building_type_in_progress(
		PLACEMENT_BARRACKS
	):
		if _try_place_building(PLACEMENT_BARRACKS):
			return

	var barracks: Barracks = _find_enemy_barracks()
	if barracks != null and not defer_military:
		_try_train_military(barracks)

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
		and _count_enemy_military_units() > 0
	)


func _should_build_hero_altar() -> bool:
	if _has_completed_building(PLACEMENT_HERO_ALTAR):
		return false

	if _is_building_type_in_progress(PLACEMENT_HERO_ALTAR):
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < TARGET_WORKERS:
		return false

	return true


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
	if _count_enemy_workers() >= TARGET_WORKERS:
		return false

	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		return false

	return command_center.try_train_enemy_worker()


func _try_train_military(barracks: Barracks) -> void:
	if barracks.is_enemy_training_busy():
		return

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
	var gold_cost: int = 0
	var wood_cost: int = 0
	match building_type:
		PLACEMENT_FARM:
			gold_cost = FARM_GOLD_COST
			wood_cost = FARM_WOOD_COST
		PLACEMENT_BARRACKS:
			gold_cost = BARRACKS_GOLD_COST
			wood_cost = BARRACKS_WOOD_COST
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
	if anchor == null:
		return false

	var parent: Node = get_node_or_null(buildings_parent_path)
	if parent == null:
		return false

	var existing_buildings: Array[Node3D] = EnemyBuildPlacement.collect_nearby_buildings(
		anchor.global_position,
		parent
	)
	var position: Vector3 = EnemyBuildPlacement.find_position(
		anchor.global_position,
		building_type,
		existing_buildings,
		prefer_expansion
	)
	if not position.is_finite():
		return false

	if not EnemyResourceManager.try_spend(gold_cost, wood_cost):
		return false

	var building: Building = _instantiate_building(building_type)
	if building == null:
		return false

	building.global_position = position
	_tag_enemy_building(building)
	_add_health_component_if_needed(building, building_type)
	parent.add_child(building)
	building.start_under_construction()
	building.setup_construction(CONSTRUCTION_DURATION)
	_assign_idle_builder(building)
	return true


func _instantiate_building(building_type: StringName) -> Building:
	match building_type:
		PLACEMENT_FARM:
			return FARM_SCENE.instantiate() as Building
		PLACEMENT_BARRACKS:
			return BARRACKS_SCENE.instantiate() as Building
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
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Building:
			continue

		var building: Building = node as Building
		if building.building_state != Building.STATE_UNDER_CONSTRUCTION:
			continue

		_assign_idle_builder(building)


func _assign_idle_builder(building: Building) -> void:
	var worker: Worker = _find_idle_enemy_worker()
	if worker == null:
		return

	worker.command_build(building)


func _find_idle_enemy_worker() -> Worker:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not is_instance_valid(worker) or worker.is_queued_for_deletion():
			continue

		if worker.is_busy_with_task():
			continue

		return worker

	return null


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


func _find_enemy_barracks() -> Barracks:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is Barracks and _is_living_building(node as Building):
			if (node as Barracks).building_state == Building.STATE_COMPLETED:
				return node as Barracks

	return null


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


func _count_enemy_military_units() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Swordsman or node is Archer:
			if is_instance_valid(node) and not node.is_queued_for_deletion():
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

	var prefer_gold: bool = (_count_enemy_workers() % 2) == 1
	gather_manager.assign_gather_job(worker, prefer_gold)
