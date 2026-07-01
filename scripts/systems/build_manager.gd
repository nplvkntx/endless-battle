extends Node

## Handles building placement preview and worker-driven construction.

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_TOWER: StringName = &"tower"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"
const PLACEMENT_COMMAND_CENTER: StringName = &"command_center"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const FARM_GOLD_COST: int = 80
const FARM_WOOD_COST: int = 20
const BARRACKS_GOLD_COST: int = 150
const BARRACKS_WOOD_COST: int = 100
const TOWER_GOLD_COST: int = 120
const TOWER_WOOD_COST: int = 80
const HERO_ALTAR_GOLD_COST: int = 180
const HERO_ALTAR_WOOD_COST: int = 110
const COMMAND_CENTER_GOLD_COST: int = 200
const COMMAND_CENTER_WOOD_COST: int = 400
const FARM_GROUND_Y: float = 0.75
const BARRACKS_GROUND_Y: float = 1.0
const TOWER_GROUND_Y: float = 1.5
const HERO_ALTAR_GROUND_Y: float = 1.25
const COMMAND_CENTER_GROUND_Y: float = 1.25
const GHOST_ALPHA: float = 0.4
const GHOST_COLOR_VALID := Color(0.5, 0.85, 0.5, GHOST_ALPHA)
const GHOST_COLOR_INVALID := Color(0.9, 0.35, 0.35, GHOST_ALPHA)
const CONSTRUCTION_DURATION_ONE_WORKER: float = 4.0
const CONSTRUCTION_DURATION_TWO_WORKERS: float = 2.5
const CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = 2.0

@export var camera_path: NodePath = "../Camera3D"
@export var buildings_parent_path: NodePath = ".."
@export var selection_manager_path: NodePath = "../SelectionManager"

var _active_placement: StringName = &""
var _placement_ghost: Node3D = null
var _ghost_material: StandardMaterial3D = null


func _process(_delta: float) -> void:
	if _active_placement.is_empty() or _placement_ghost == null:
		return

	var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return

	var ground_position: Vector3 = _raycast_ground_plane(
		camera,
		get_viewport().get_mouse_position()
	)
	if not ground_position.is_finite():
		return

	var ground_y: float = _get_ground_y(_active_placement)
	var snapped_position: Vector3 = EnemyBuildPlacement.snap_to_grid(ground_position)
	snapped_position.y = ground_y
	_placement_ghost.global_position = snapped_position
	_update_ghost_validity(snapped_position)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _active_placement.is_empty() and _can_use_worker_build_hotkeys():
			if event.keycode == KEY_B:
				start_farm_placement()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_R:
				start_barracks_placement()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_T:
				start_tower_placement()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_H:
				start_hero_altar_placement()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_C:
				start_command_center_placement()
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_ESCAPE:
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return

	if _active_placement.is_empty():
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_place_building()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_cancel_placement()
				get_viewport().set_input_as_handled()


func start_farm_placement() -> void:
	_start_placement(PLACEMENT_FARM)


func start_barracks_placement() -> void:
	_start_placement(PLACEMENT_BARRACKS)


func start_tower_placement() -> void:
	_start_placement(PLACEMENT_TOWER)


func start_hero_altar_placement() -> void:
	_start_placement(PLACEMENT_HERO_ALTAR)


func start_command_center_placement() -> void:
	_start_placement(PLACEMENT_COMMAND_CENTER)


func _start_placement(placement_type: StringName) -> void:
	if not _active_placement.is_empty():
		return

	if not _has_worker_selected():
		print("Select a Worker first")
		return

	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return

	var scene: PackedScene = _get_building_scene(placement_type)
	if scene == null:
		return

	_active_placement = placement_type
	_placement_ghost = scene.instantiate()
	_disable_ghost_collision(_placement_ghost)
	_disable_ghost_processing(_placement_ghost)
	_apply_ghost_material(_placement_ghost)
	buildings_parent.add_child(_placement_ghost)


func _cancel_placement() -> void:
	_active_placement = &""
	_ghost_material = null
	if _placement_ghost != null:
		_placement_ghost.queue_free()
		_placement_ghost = null


func _place_building() -> void:
	if _placement_ghost == null or _active_placement.is_empty():
		return

	if not _is_current_placement_valid():
		print("Invalid placement")
		return

	var gold_cost: int = 0
	var wood_cost: int = 0
	match _active_placement:
		PLACEMENT_FARM:
			gold_cost = FARM_GOLD_COST
			wood_cost = FARM_WOOD_COST
		PLACEMENT_BARRACKS:
			gold_cost = BARRACKS_GOLD_COST
			wood_cost = BARRACKS_WOOD_COST
		PLACEMENT_TOWER:
			gold_cost = TOWER_GOLD_COST
			wood_cost = TOWER_WOOD_COST
		PLACEMENT_HERO_ALTAR:
			gold_cost = HERO_ALTAR_GOLD_COST
			wood_cost = HERO_ALTAR_WOOD_COST
		PLACEMENT_COMMAND_CENTER:
			gold_cost = COMMAND_CENTER_GOLD_COST
			wood_cost = COMMAND_CENTER_WOOD_COST
		_:
			return

	if not ResourceManager.try_spend(gold_cost, wood_cost):
		print("Not enough resources")
		return

	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return

	var scene: PackedScene = _get_building_scene(_active_placement)
	if scene == null:
		return

	var building: Building = scene.instantiate() as Building
	building.global_position = _placement_ghost.global_position
	buildings_parent.add_child(building)
	building.start_under_construction()

	var workers: Array[Worker] = _get_selected_workers()
	building.setup_construction(_get_construction_duration(workers.size()))
	for worker: Worker in workers:
		worker.start_construction_order(building)

	_cancel_placement()


func _get_building_scene(placement_type: StringName) -> PackedScene:
	match placement_type:
		PLACEMENT_FARM:
			return FARM_SCENE
		PLACEMENT_BARRACKS:
			return BARRACKS_SCENE
		PLACEMENT_TOWER:
			return TOWER_SCENE
		PLACEMENT_HERO_ALTAR:
			return HERO_ALTAR_SCENE
		PLACEMENT_COMMAND_CENTER:
			return COMMAND_CENTER_SCENE
		_:
			return null


func _get_ground_y(placement_type: StringName) -> float:
	match placement_type:
		PLACEMENT_FARM:
			return FARM_GROUND_Y
		PLACEMENT_BARRACKS:
			return BARRACKS_GROUND_Y
		PLACEMENT_TOWER:
			return TOWER_GROUND_Y
		PLACEMENT_HERO_ALTAR:
			return HERO_ALTAR_GROUND_Y
		PLACEMENT_COMMAND_CENTER:
			return COMMAND_CENTER_GROUND_Y
		_:
			return 0.0


func _get_selected_workers() -> Array[Worker]:
	var workers: Array[Worker] = []
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return workers

	for unit: Unit in selection_manager.selected_units:
		if unit is Worker:
			workers.append(unit as Worker)

	return workers


func _get_construction_duration(worker_count: int) -> float:
	if worker_count >= 3:
		return CONSTRUCTION_DURATION_THREE_PLUS_WORKERS
	if worker_count == 2:
		return CONSTRUCTION_DURATION_TWO_WORKERS
	return CONSTRUCTION_DURATION_ONE_WORKER


func _has_worker_selected() -> bool:
	return not _get_selected_workers().is_empty()


func _can_use_worker_build_hotkeys() -> bool:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return false

	if selection_manager.selected_building != null:
		return false

	var selected_units: Array[Unit] = selection_manager.selected_units
	if selected_units.is_empty():
		return false

	for unit: Unit in selected_units:
		if not unit is Worker:
			return false

	return true


func _disable_ghost_collision(ghost: Node3D) -> void:
	if ghost is CollisionObject3D:
		(ghost as CollisionObject3D).collision_layer = 0
		(ghost as CollisionObject3D).collision_mask = 0

	var collision_shape: CollisionShape3D = ghost.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		collision_shape.disabled = true


func _disable_ghost_processing(ghost: Node3D) -> void:
	ghost.set_process(false)
	ghost.set_physics_process(false)


func _apply_ghost_material(ghost: Node3D) -> void:
	var mesh_instance: MeshInstance3D = ghost.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		return

	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = GHOST_COLOR_VALID
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = _ghost_material


func _update_ghost_validity(position: Vector3) -> void:
	if _ghost_material == null:
		return

	var is_valid: bool = _is_placement_valid_at(position)
	_ghost_material.albedo_color = GHOST_COLOR_VALID if is_valid else GHOST_COLOR_INVALID


func _is_current_placement_valid() -> bool:
	if _placement_ghost == null or _active_placement.is_empty():
		return false

	return _is_placement_valid_at(_placement_ghost.global_position)


func _is_placement_valid_at(position: Vector3) -> bool:
	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return false

	var exclude_nodes: Array[Node] = []
	if _placement_ghost != null:
		exclude_nodes.append(_placement_ghost)

	return EnemyBuildPlacement.is_position_valid(
		position,
		_active_placement,
		_collect_placement_obstacles(buildings_parent),
		buildings_parent,
		exclude_nodes
	)


func _collect_placement_obstacles(buildings_parent: Node) -> Array[Node3D]:
	var buildings: Array[Node3D] = EnemyBuildPlacement.collect_all_buildings(buildings_parent)
	if _placement_ghost != null:
		buildings.erase(_placement_ghost)

	return buildings


func _raycast_ground_plane(camera: Camera3D, screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return Vector3(INF, INF, INF)

	var intersection_distance: float = -ray_origin.y / ray_direction.y
	if intersection_distance < 0.0:
		return Vector3(INF, INF, INF)

	return ray_origin + ray_direction * intersection_distance
