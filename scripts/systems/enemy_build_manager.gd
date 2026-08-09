class_name EnemyBuildManager
extends Node

## Enemy building placement / construction mechanics only.
## Does not decide what to build — callers must request placement.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const ENEMY_WORKER_GROUP := &"enemy_workers"
const ENEMY_TEAM_ID: int = 1

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"
const PLACEMENT_BLACKSMITH: StringName = &"blacksmith"
const PLACEMENT_STABLE: StringName = &"stable"
const PLACEMENT_ARTILLERY_DEPOT: StringName = &"artillery_depot"
const PLACEMENT_COMMAND_CENTER: StringName = &"command_center"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const HEALTH_COMPONENT_SCRIPT: Script = preload("res://scripts/components/health_component.gd")

const FARM_GOLD_COST: int = BuildingStats.FARM_GOLD_COST
const FARM_WOOD_COST: int = BuildingStats.FARM_WOOD_COST
const BARRACKS_GOLD_COST: int = BuildingStats.BARRACKS_GOLD_COST
const BARRACKS_WOOD_COST: int = BuildingStats.BARRACKS_WOOD_COST
const HERO_ALTAR_GOLD_COST: int = BuildingStats.HERO_ALTAR_GOLD_COST
const HERO_ALTAR_WOOD_COST: int = BuildingStats.HERO_ALTAR_WOOD_COST
const BLACKSMITH_GOLD_COST: int = BuildingStats.BLACKSMITH_GOLD_COST
const BLACKSMITH_WOOD_COST: int = BuildingStats.BLACKSMITH_WOOD_COST
const STABLE_GOLD_COST: int = BuildingStats.STABLE_GOLD_COST
const STABLE_WOOD_COST: int = BuildingStats.STABLE_WOOD_COST
const ARTILLERY_DEPOT_GOLD_COST: int = BuildingStats.ARTILLERY_DEPOT_GOLD_COST
const ARTILLERY_DEPOT_WOOD_COST: int = BuildingStats.ARTILLERY_DEPOT_WOOD_COST
const COMMAND_CENTER_GOLD_COST: int = BuildingStats.COMMAND_CENTER_GOLD_COST
const COMMAND_CENTER_WOOD_COST: int = BuildingStats.COMMAND_CENTER_WOOD_COST
const FARM_MAX_HEALTH: int = BuildingStats.FARM_MAX_HEALTH
const HERO_ALTAR_MAX_HEALTH: int = BuildingStats.HERO_ALTAR_MAX_HEALTH
## Farms may duplicate. Barracks may exist up to this count. Other types are unique.
const MAX_BARRACKS: int = 2

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
	if not _is_supported_building_type(building_type):
		return false
	if building_type == PLACEMENT_COMMAND_CENTER:
		return false
	if building_type == PLACEMENT_FARM:
		pass
	elif building_type == PLACEMENT_BARRACKS:
		if _count_buildings_of_type(PLACEMENT_BARRACKS) >= MAX_BARRACKS:
			return false
	elif _has_completed_or_in_progress(building_type):
		return false
	return _try_place_building(building_type, Vector3.ZERO, false)


func try_place_farm() -> bool:
	return try_place_building(PLACEMENT_FARM)


func try_place_hero_altar() -> bool:
	return try_place_building(PLACEMENT_HERO_ALTAR)


func try_place_barracks() -> bool:
	return try_place_building(PLACEMENT_BARRACKS)


func try_place_blacksmith() -> bool:
	return try_place_building(PLACEMENT_BLACKSMITH)


func try_place_stable() -> bool:
	return try_place_building(PLACEMENT_STABLE)


func try_place_artillery_depot() -> bool:
	return try_place_building(PLACEMENT_ARTILLERY_DEPOT)


## Place an expansion Command Center near a gold mine. No AI policy.
func try_place_expansion_at_mine(gold_mine: GoldMine) -> bool:
	if not NodeSafety.is_alive_node(gold_mine):
		return false
	if _has_expansion_command_center_or_constructing():
		return false
	return _try_place_building(PLACEMENT_COMMAND_CENTER, gold_mine.global_position, true)


## Worker finished spawn / finished construction — leave idle for EnemyAI ratio assign.
## Previously forced prefer_gold=true here, which starved Wood allocation.
func notify_enemy_worker_spawned(worker: Worker) -> void:
	if not NodeSafety.is_alive_node(worker):
		return
	## No forced Gold job. EnemyAI assigns idle workers by live Gold/Wood ratio.


## Legacy hook from Command Center; no automatic production policy.
func request_worker_production_check() -> void:
	pass


func _try_place_building(
	building_type: StringName,
	override_anchor: Vector3,
	prefer_expansion: bool
) -> bool:
	if not is_inside_tree():
		return false

	var costs: Vector2i = _get_building_costs(building_type)
	if costs.x < 0:
		return false

	if not EnemyResourceManager.can_afford(costs.x, costs.y, true):
		return false

	var parent: Node = get_node_or_null(buildings_parent_path)
	if parent == null or not parent.is_inside_tree():
		return false

	var anchor: Vector3 = override_anchor
	if not prefer_expansion:
		var cc: CommandCenter = _resolve_primary_command_center()
		if cc == null or not is_instance_valid(cc) or not cc.is_inside_tree():
			return false
		anchor = cc.global_position
	elif not anchor.is_finite():
		return false

	var existing_buildings: Array[Node3D] = EnemyBuildPlacement.collect_nearby_buildings(
		anchor,
		parent
	)
	var position: Vector3 = EnemyBuildPlacement.find_position(
		anchor,
		building_type,
		existing_buildings,
		prefer_expansion,
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

	if not EnemyResourceManager.try_spend(costs.x, costs.y, true):
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	var building: Building = _instantiate_building(building_type)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(costs.x)
		EnemyResourceManager.add_wood(costs.y)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	_tag_enemy_building(building)
	_add_health_component_if_needed(building, building_type)
	parent.add_child(building)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(costs.x)
		EnemyResourceManager.add_wood(costs.y)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	building.global_position = position
	building.set_construction_cost(costs.x, costs.y, true)
	building.start_under_construction()
	building.setup_construction(
		BuildingStats.get_construction_seconds(building_type, 1)
		/ UpgradeManager.get_construction_speed_multiplier(true)
	)
	ConstructionReservations.release_footprint(footprint_reservation_id)
	_assign_nearest_builder(building)
	return true


func _get_building_costs(building_type: StringName) -> Vector2i:
	match building_type:
		PLACEMENT_FARM:
			return Vector2i(FARM_GOLD_COST, FARM_WOOD_COST)
		PLACEMENT_BARRACKS:
			return Vector2i(BARRACKS_GOLD_COST, BARRACKS_WOOD_COST)
		PLACEMENT_HERO_ALTAR:
			return Vector2i(HERO_ALTAR_GOLD_COST, HERO_ALTAR_WOOD_COST)
		PLACEMENT_BLACKSMITH:
			return Vector2i(BLACKSMITH_GOLD_COST, BLACKSMITH_WOOD_COST)
		PLACEMENT_STABLE:
			return Vector2i(STABLE_GOLD_COST, STABLE_WOOD_COST)
		PLACEMENT_ARTILLERY_DEPOT:
			return Vector2i(ARTILLERY_DEPOT_GOLD_COST, ARTILLERY_DEPOT_WOOD_COST)
		PLACEMENT_COMMAND_CENTER:
			return Vector2i(COMMAND_CENTER_GOLD_COST, COMMAND_CENTER_WOOD_COST)
		_:
			return Vector2i(-1, -1)


func _is_supported_building_type(building_type: StringName) -> bool:
	return (
		building_type == PLACEMENT_FARM
		or building_type == PLACEMENT_BARRACKS
		or building_type == PLACEMENT_HERO_ALTAR
		or building_type == PLACEMENT_BLACKSMITH
		or building_type == PLACEMENT_STABLE
		or building_type == PLACEMENT_ARTILLERY_DEPOT
		or building_type == PLACEMENT_COMMAND_CENTER
	)


func _instantiate_building(building_type: StringName) -> Building:
	match building_type:
		PLACEMENT_FARM:
			return FARM_SCENE.instantiate() as Building
		PLACEMENT_BARRACKS:
			return BARRACKS_SCENE.instantiate() as Building
		PLACEMENT_HERO_ALTAR:
			return HERO_ALTAR_SCENE.instantiate() as Building
		PLACEMENT_BLACKSMITH:
			return BLACKSMITH_SCENE.instantiate() as Building
		PLACEMENT_STABLE:
			return STABLE_SCENE.instantiate() as Building
		PLACEMENT_ARTILLERY_DEPOT:
			return ARTILLERY_DEPOT_SCENE.instantiate() as Building
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


## Public: staff an unfinished enemy foundation (AI condition tick / recovery).
func assign_builder_to(building: Building) -> bool:
	if not NodeSafety.is_alive_node(building):
		return false
	if not building.is_being_constructed():
		return false
	var worker: Worker = _find_nearest_available_enemy_worker(building.global_position)
	if not NodeSafety.is_alive_node(worker):
		return false
	worker.command_build(building)
	return true


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
	return _count_buildings_of_type(building_type) > 0


func _count_buildings_of_type(building_type: StringName) -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node) or not node is Building:
			continue
		var building: Building = node as Building
		if not _building_matches_type(building, building_type):
			continue
		var state: StringName = building.building_state
		if (
			state == Building.STATE_COMPLETED
			or state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			count += 1
	return count


func _has_expansion_command_center_or_constructing() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	var primary: CommandCenter = _resolve_primary_command_center()
	var primary_id: int = primary.get_instance_id() if primary != null else 0
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node) or not node is CommandCenter:
			continue
		var cc: CommandCenter = node as CommandCenter
		var state: StringName = cc.building_state
		if (
			state != Building.STATE_COMPLETED
			and state != Building.STATE_UNDER_CONSTRUCTION
			and state != Building.STATE_CONSTRUCTING
		):
			continue
		if primary_id != 0 and cc.get_instance_id() == primary_id:
			continue
		count += 1
	return count > 0


func _building_matches_type(building: Building, building_type: StringName) -> bool:
	match building_type:
		PLACEMENT_FARM:
			return building is Farm
		PLACEMENT_BARRACKS:
			return building is Barracks
		PLACEMENT_HERO_ALTAR:
			return building is HeroAltar
		PLACEMENT_BLACKSMITH:
			return building is Blacksmith
		PLACEMENT_STABLE:
			return building is Stable
		PLACEMENT_ARTILLERY_DEPOT:
			return building is ArtilleryDepot
		PLACEMENT_COMMAND_CENTER:
			return building is CommandCenter
		_:
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
