class_name EnemyBuildManager
extends Node

## Enemy building placement / construction mechanics only.
## Does not decide what to build — SimpleWc3AI (or tests) must request placement.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const ENEMY_WORKER_GROUP := &"enemy_workers"
const ENEMY_TEAM_ID: int = 1

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const HEALTH_COMPONENT_SCRIPT: Script = preload("res://scripts/components/health_component.gd")

const FARM_GOLD_COST: int = BuildingStats.FARM_GOLD_COST
const FARM_WOOD_COST: int = BuildingStats.FARM_WOOD_COST
const BARRACKS_GOLD_COST: int = BuildingStats.BARRACKS_GOLD_COST
const BARRACKS_WOOD_COST: int = BuildingStats.BARRACKS_WOOD_COST
const HERO_ALTAR_GOLD_COST: int = BuildingStats.HERO_ALTAR_GOLD_COST
const HERO_ALTAR_WOOD_COST: int = BuildingStats.HERO_ALTAR_WOOD_COST
const FARM_MAX_HEALTH: int = BuildingStats.FARM_MAX_HEALTH
const HERO_ALTAR_MAX_HEALTH: int = BuildingStats.HERO_ALTAR_MAX_HEALTH

@export var enemy_command_center_path: NodePath
@export var enemy_gather_manager_path: NodePath
@export var buildings_parent_path: NodePath = NodePath("..")

var _primary_command_center: CommandCenter = null


func _ready() -> void:
	_primary_command_center = _resolve_primary_command_center()
	if _primary_command_center == null:
		push_warning("EnemyBuildManager: enemy Command Center not found")


## Public mechanic API — place one building if affordable and site is valid.
func try_place_building(building_type: StringName) -> bool:
	if building_type != PLACEMENT_FARM and building_type != PLACEMENT_BARRACKS and building_type != PLACEMENT_HERO_ALTAR:
		return false
	if _has_completed_or_in_progress(building_type):
		return false
	return _try_place_building(building_type)


func try_place_farm() -> bool:
	return try_place_building(PLACEMENT_FARM)


func try_place_hero_altar() -> bool:
	return try_place_building(PLACEMENT_HERO_ALTAR)


func try_place_barracks() -> bool:
	return try_place_building(PLACEMENT_BARRACKS)


## Worker finished spawn / finished construction — hand to gather mechanics.
func notify_enemy_worker_spawned(worker: Worker) -> void:
	if not NodeSafety.is_alive_node(worker):
		return
	var gather: EnemyGatherManager = _resolve_gather_manager()
	if gather != null:
		gather.assign_gather_job(worker, true)


## Legacy hook from Command Center; production decisions are owned by SimpleWc3AI.
func request_worker_production_check() -> void:
	pass


func _try_place_building(building_type: StringName) -> bool:
	if not is_inside_tree():
		return false

	var anchor: CommandCenter = _resolve_primary_command_center()
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
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
		PLACEMENT_HERO_ALTAR:
			gold_cost = HERO_ALTAR_GOLD_COST
			wood_cost = HERO_ALTAR_WOOD_COST
		_:
			return false

	if not EnemyResourceManager.can_afford(gold_cost, wood_cost, true):
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
		false,
		parent,
		_get_navigation_map()
	)
	if not position.is_finite():
		return false

	var footprint: Vector2 = EnemyBuildPlacement.get_footprint(building_type)
	var footprint_reservation_id: int = ConstructionReservations.reserve_footprint(
		position,
		footprint,
		self,
		ConstructionReservations.FOOTPRINT_RESERVATION_TTL_MSEC
	)

	if not EnemyResourceManager.try_spend(gold_cost, wood_cost, true):
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	var building: Building = _instantiate_building(building_type)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(gold_cost)
		EnemyResourceManager.add_wood(wood_cost)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	_tag_enemy_building(building)
	_add_health_component_if_needed(building, building_type)
	parent.add_child(building)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(gold_cost)
		EnemyResourceManager.add_wood(wood_cost)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	building.global_position = position
	building.set_construction_cost(gold_cost, wood_cost, true)
	building.start_under_construction()
	building.setup_construction(
		BuildingStats.get_construction_seconds(building_type, 1)
		/ UpgradeManager.get_construction_speed_multiplier(true)
	)
	ConstructionReservations.release_footprint(footprint_reservation_id)
	_assign_nearest_builder(building)
	return true


func _instantiate_building(building_type: StringName) -> Building:
	match building_type:
		PLACEMENT_FARM:
			return FARM_SCENE.instantiate() as Building
		PLACEMENT_BARRACKS:
			return BARRACKS_SCENE.instantiate() as Building
		PLACEMENT_HERO_ALTAR:
			return HERO_ALTAR_SCENE.instantiate() as Building
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
		PLACEMENT_FARM:
			max_health = FARM_MAX_HEALTH
		PLACEMENT_HERO_ALTAR:
			max_health = HERO_ALTAR_MAX_HEALTH
		_:
			return
	var health_component: Node = HEALTH_COMPONENT_SCRIPT.new()
	health_component.name = "HealthComponent"
	health_component.set("max_health", max_health)
	building.add_child(health_component)


func _assign_nearest_builder(building: Building) -> void:
	if not NodeSafety.is_alive_node(building):
		return
	var worker: Worker = _find_nearest_available_enemy_worker(building.global_position)
	if not NodeSafety.is_alive_node(worker):
		return
	worker.command_build(building)


func _find_nearest_available_enemy_worker(near_position: Vector3) -> Worker:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var best: Worker = null
	var best_dist: float = INF
	for node: Node in tree.get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue
		var worker: Worker = node as Worker
		if not NodeSafety.is_alive_node(worker):
			continue
		if worker.is_on_construction_trip():
			continue
		var dist: float = _horizontal_distance(worker.global_position, near_position)
		if dist < best_dist:
			best_dist = dist
			best = worker
	return best


func _has_completed_or_in_progress(building_type: StringName) -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for node: Node in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node) or not node is Building:
			continue
		var building: Building = node as Building
		var matches := false
		match building_type:
			PLACEMENT_FARM:
				matches = building is Farm
			PLACEMENT_BARRACKS:
				matches = building is Barracks
			PLACEMENT_HERO_ALTAR:
				matches = building is HeroAltar
			_:
				matches = false
		if not matches:
			continue
		var state: StringName = building.building_state
		if (
			state == Building.STATE_COMPLETED
			or state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			return true
	return false


func _resolve_primary_command_center() -> CommandCenter:
	if (
		_primary_command_center != null
		and is_instance_valid(_primary_command_center)
		and _primary_command_center.is_inside_tree()
	):
		return _primary_command_center
	if enemy_command_center_path != NodePath(""):
		_primary_command_center = get_node_or_null(enemy_command_center_path) as CommandCenter
		if _primary_command_center != null:
			return _primary_command_center
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is CommandCenter and NodeSafety.is_alive_node(node):
			_primary_command_center = node as CommandCenter
			return _primary_command_center
	return null


func _resolve_gather_manager() -> EnemyGatherManager:
	if enemy_gather_manager_path != NodePath(""):
		var via_path: EnemyGatherManager = get_node_or_null(enemy_gather_manager_path) as EnemyGatherManager
		if via_path != null:
			return via_path
	var parent: Node = get_parent()
	if parent != null:
		return parent.get_node_or_null("EnemyGatherManager") as EnemyGatherManager
	return null


func _get_navigation_map() -> RID:
	var world: World3D = get_viewport().find_world_3d() if get_viewport() != null else null
	if world == null:
		return RID()
	return world.get_navigation_map()


func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var dx: float = from_position.x - to_position.x
	var dz: float = from_position.z - to_position.z
	return sqrt(dx * dx + dz * dz)
