extends Node

## Handles building placement preview and worker-driven construction.

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_BLACKSMITH: StringName = &"blacksmith"
const PLACEMENT_STABLE: StringName = &"stable"
const PLACEMENT_ARTILLERY_DEPOT: StringName = &"artillery_depot"
const PLACEMENT_ACADEMY: StringName = &"academy"
const PLACEMENT_SHOP: StringName = &"shop"
const PLACEMENT_TOWER: StringName = &"tower"
const PLACEMENT_WALL_SEGMENT: StringName = &"wall_segment"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"
const PLACEMENT_COMMAND_CENTER: StringName = &"command_center"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const ACADEMY_SCENE: PackedScene = preload("res://scenes/buildings/academy.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/buildings/shop.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")
const WALL_SEGMENT_SCENE: PackedScene = preload("res://scenes/buildings/wall_segment.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const FARM_GOLD_COST: int = 80
const FARM_WOOD_COST: int = 20
const BARRACKS_GOLD_COST: int = 150
const BARRACKS_WOOD_COST: int = 100
const BLACKSMITH_GOLD_COST: int = 100
const BLACKSMITH_WOOD_COST: int = 150
const STABLE_GOLD_COST: int = 175
const STABLE_WOOD_COST: int = 125
const ARTILLERY_DEPOT_GOLD_COST: int = 225
const ARTILLERY_DEPOT_WOOD_COST: int = 175
const ACADEMY_GOLD_COST: int = 200
const ACADEMY_WOOD_COST: int = 150
const SHOP_GOLD_COST: int = 80
const SHOP_WOOD_COST: int = 120
const TOWER_GOLD_COST: int = 120
const TOWER_WOOD_COST: int = 80
const WALL_SEGMENT_GOLD_COST: int = 0
const WALL_SEGMENT_WOOD_COST: int = 40
const HERO_ALTAR_GOLD_COST: int = 180
const HERO_ALTAR_WOOD_COST: int = 110
const COMMAND_CENTER_GOLD_COST: int = 200
const COMMAND_CENTER_WOOD_COST: int = 400
const FARM_GROUND_Y: float = 0.75
const BARRACKS_GROUND_Y: float = 1.0
const BLACKSMITH_GROUND_Y: float = 1.0
const STABLE_GROUND_Y: float = 1.0
const ARTILLERY_DEPOT_GROUND_Y: float = 1.0
const ACADEMY_GROUND_Y: float = 1.0
const SHOP_GROUND_Y: float = 1.0
const TOWER_GROUND_Y: float = 1.5
const WALL_SEGMENT_GROUND_Y: float = 0.75
const HERO_ALTAR_GROUND_Y: float = 1.25
const COMMAND_CENTER_GROUND_Y: float = 1.25
const GHOST_ALPHA: float = 0.4
const GHOST_COLOR_VALID := Color(0.5, 0.85, 0.5, GHOST_ALPHA)
const GHOST_COLOR_INVALID := Color(0.9, 0.35, 0.35, GHOST_ALPHA)
const CONSTRUCTION_DURATION_ONE_WORKER: float = 4.0
const CONSTRUCTION_DURATION_TWO_WORKERS: float = 2.5
const CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = 2.0
const SHOP_CONSTRUCTION_DURATION_ONE_WORKER: float = 3.5
const SHOP_CONSTRUCTION_DURATION_TWO_WORKERS: float = 2.2
const SHOP_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = 1.8
const WALL_SEGMENT_CONSTRUCTION_DURATION_ONE_WORKER: float = 8.0
const WALL_SEGMENT_CONSTRUCTION_DURATION_TWO_WORKERS: float = 5.0
const WALL_SEGMENT_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = 4.0
const WALL_DRAG_MAX_SEGMENTS: int = 30

@export var camera_path: NodePath = "../Camera3D"
@export var buildings_parent_path: NodePath = ".."
@export var selection_manager_path: NodePath = "../SelectionManager"

var _active_placement: StringName = &""
var _placement_ghost: Node3D = null
var _ghost_material: StandardMaterial3D = null
var _wall_drag_has_start: bool = false
var _wall_drag_start: Vector3 = Vector3.ZERO
var _wall_drag_ghosts: Array[Node3D] = []
var _wall_drag_ghost_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if not is_inside_tree():
		return

	if _active_placement.is_empty():
		return

	if _active_placement == PLACEMENT_WALL_SEGMENT:
		_process_wall_drag_preview()
		return

	if _placement_ghost == null:
		return

	if not is_instance_valid(_placement_ghost) or not _placement_ghost.is_inside_tree():
		_cancel_placement()
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
			if event.keycode == KEY_W:
				start_wall_segment_placement()
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

	if _active_placement == PLACEMENT_WALL_SEGMENT:
		if event is InputEventMouseButton and event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					if not _wall_drag_has_start:
						_set_wall_drag_start()
					else:
						_place_wall_line()
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_RIGHT:
					_cancel_placement()
					get_viewport().set_input_as_handled()
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


func start_blacksmith_placement() -> void:
	if not TechTree.can_build_blacksmith():
		ResourceManager.show_feedback(TechTree.BLACKSMITH_REQUIRES_TIER_2_MESSAGE)
		return

	_start_placement(PLACEMENT_BLACKSMITH)


func start_stable_placement() -> void:
	if not TechTree.can_build_stable():
		ResourceManager.show_feedback(TechTree.STABLE_REQUIRES_TIER_2_AND_BLACKSMITH_MESSAGE)
		return

	_start_placement(PLACEMENT_STABLE)


func start_artillery_depot_placement() -> void:
	if not TechTree.can_build_artillery_depot():
		ResourceManager.show_feedback(TechTree.ARTILLERY_DEPOT_REQUIRES_TIER_3_AND_BLACKSMITH_MESSAGE)
		return

	_start_placement(PLACEMENT_ARTILLERY_DEPOT)


func start_academy_placement() -> void:
	if not TechTree.can_build_academy():
		ResourceManager.show_feedback(TechTree.ACADEMY_REQUIRES_TIER_3_AND_BLACKSMITH_MESSAGE)
		return

	_start_placement(PLACEMENT_ACADEMY)


func start_shop_placement() -> void:
	_start_placement(PLACEMENT_SHOP)


func start_tower_placement() -> void:
	_start_placement(PLACEMENT_TOWER)


func start_wall_segment_placement() -> void:
	_start_wall_drag_placement()


func start_hero_altar_placement() -> void:
	_start_placement(PLACEMENT_HERO_ALTAR)


func start_command_center_placement() -> void:
	_start_placement(PLACEMENT_COMMAND_CENTER)


func _start_placement(placement_type: StringName) -> void:
	if not is_inside_tree():
		return

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
	_ghost_material = _apply_ghost_material(_placement_ghost)
	buildings_parent.add_child(_placement_ghost)
	set_process(true)


func _cancel_placement() -> void:
	_active_placement = &""
	_ghost_material = null
	_wall_drag_has_start = false
	_wall_drag_start = Vector3.ZERO
	set_process(false)
	_clear_wall_drag_ghosts()
	if _placement_ghost != null:
		_placement_ghost.queue_free()
		_placement_ghost = null


func _place_building() -> void:
	if not is_inside_tree():
		return

	if _placement_ghost == null or _active_placement.is_empty():
		return

	if not is_instance_valid(_placement_ghost) or not _placement_ghost.is_inside_tree():
		return

	if not _is_current_placement_valid():
		print("Invalid placement")
		return

	if _active_placement == PLACEMENT_BLACKSMITH and not TechTree.can_build_blacksmith():
		ResourceManager.show_feedback(TechTree.BLACKSMITH_REQUIRES_TIER_2_MESSAGE)
		return

	if _active_placement == PLACEMENT_STABLE and not TechTree.can_build_stable():
		ResourceManager.show_feedback(TechTree.STABLE_REQUIRES_TIER_2_AND_BLACKSMITH_MESSAGE)
		return

	if _active_placement == PLACEMENT_ARTILLERY_DEPOT and not TechTree.can_build_artillery_depot():
		ResourceManager.show_feedback(TechTree.ARTILLERY_DEPOT_REQUIRES_TIER_3_AND_BLACKSMITH_MESSAGE)
		return

	if _active_placement == PLACEMENT_ACADEMY and not TechTree.can_build_academy():
		ResourceManager.show_feedback(TechTree.ACADEMY_REQUIRES_TIER_3_AND_BLACKSMITH_MESSAGE)
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
		PLACEMENT_BLACKSMITH:
			gold_cost = BLACKSMITH_GOLD_COST
			wood_cost = BLACKSMITH_WOOD_COST
		PLACEMENT_STABLE:
			gold_cost = STABLE_GOLD_COST
			wood_cost = STABLE_WOOD_COST
		PLACEMENT_ARTILLERY_DEPOT:
			gold_cost = ARTILLERY_DEPOT_GOLD_COST
			wood_cost = ARTILLERY_DEPOT_WOOD_COST
		PLACEMENT_ACADEMY:
			gold_cost = ACADEMY_GOLD_COST
			wood_cost = ACADEMY_WOOD_COST
		PLACEMENT_SHOP:
			gold_cost = SHOP_GOLD_COST
			wood_cost = SHOP_WOOD_COST
		PLACEMENT_TOWER:
			gold_cost = TOWER_GOLD_COST
			wood_cost = TOWER_WOOD_COST
		PLACEMENT_WALL_SEGMENT:
			gold_cost = WALL_SEGMENT_GOLD_COST
			wood_cost = WALL_SEGMENT_WOOD_COST
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
	if buildings_parent == null or not buildings_parent.is_inside_tree():
		return

	var scene: PackedScene = _get_building_scene(_active_placement)
	if scene == null:
		return

	var placement_position: Vector3 = _placement_ghost.global_position
	if not placement_position.is_finite():
		return

	var building: Building = scene.instantiate() as Building
	buildings_parent.add_child(building)
	building.global_position = placement_position
	building.start_under_construction()

	var workers: Array[Worker] = _get_selected_workers()
	building.setup_construction(_get_construction_duration(workers.size(), _active_placement))
	for worker: Worker in workers:
		worker.start_construction_order(building)

	_cancel_placement()


func _get_building_scene(placement_type: StringName) -> PackedScene:
	match placement_type:
		PLACEMENT_FARM:
			return FARM_SCENE
		PLACEMENT_BARRACKS:
			return BARRACKS_SCENE
		PLACEMENT_BLACKSMITH:
			return BLACKSMITH_SCENE
		PLACEMENT_STABLE:
			return STABLE_SCENE
		PLACEMENT_ARTILLERY_DEPOT:
			return ARTILLERY_DEPOT_SCENE
		PLACEMENT_ACADEMY:
			return ACADEMY_SCENE
		PLACEMENT_SHOP:
			return SHOP_SCENE
		PLACEMENT_TOWER:
			return TOWER_SCENE
		PLACEMENT_WALL_SEGMENT:
			return WALL_SEGMENT_SCENE
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
		PLACEMENT_BLACKSMITH:
			return BLACKSMITH_GROUND_Y
		PLACEMENT_STABLE:
			return STABLE_GROUND_Y
		PLACEMENT_ARTILLERY_DEPOT:
			return ARTILLERY_DEPOT_GROUND_Y
		PLACEMENT_ACADEMY:
			return ACADEMY_GROUND_Y
		PLACEMENT_SHOP:
			return SHOP_GROUND_Y
		PLACEMENT_TOWER:
			return TOWER_GROUND_Y
		PLACEMENT_WALL_SEGMENT:
			return WALL_SEGMENT_GROUND_Y
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
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue
		if unit is Worker:
			workers.append(unit as Worker)

	return workers


func _get_construction_duration(worker_count: int, placement_type: StringName = &"") -> float:
	if placement_type == PLACEMENT_SHOP:
		if worker_count >= 3:
			return SHOP_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS
		if worker_count == 2:
			return SHOP_CONSTRUCTION_DURATION_TWO_WORKERS
		return SHOP_CONSTRUCTION_DURATION_ONE_WORKER

	if placement_type == PLACEMENT_WALL_SEGMENT:
		if worker_count >= 3:
			return WALL_SEGMENT_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS
		if worker_count == 2:
			return WALL_SEGMENT_CONSTRUCTION_DURATION_TWO_WORKERS
		return WALL_SEGMENT_CONSTRUCTION_DURATION_ONE_WORKER

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
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue
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


func _apply_ghost_material(ghost: Node3D) -> StandardMaterial3D:
	var mesh_instance: MeshInstance3D = ghost.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var wall_placeholder: MeshInstance3D = (
		ghost.get_node_or_null("Visuals/WallPlaceholder") as MeshInstance3D
	)
	var target_mesh: MeshInstance3D = wall_placeholder if wall_placeholder != null else mesh_instance
	var ghost_material := StandardMaterial3D.new()
	ghost_material.albedo_color = GHOST_COLOR_VALID
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if target_mesh != null:
		target_mesh.material_override = ghost_material

	return ghost_material


func _update_ghost_validity(position: Vector3) -> void:
	if _ghost_material == null:
		return

	var is_valid: bool = _is_placement_valid_at(position)
	_ghost_material.albedo_color = GHOST_COLOR_VALID if is_valid else GHOST_COLOR_INVALID


func _is_current_placement_valid() -> bool:
	if (
		_placement_ghost == null
		or not is_instance_valid(_placement_ghost)
		or _active_placement.is_empty()
	):
		return false

	return _is_placement_valid_at(_placement_ghost.global_position)


func _is_placement_valid_at(position: Vector3) -> bool:
	if _active_placement == PLACEMENT_BLACKSMITH and not TechTree.can_build_blacksmith():
		return false

	if _active_placement == PLACEMENT_STABLE and not TechTree.can_build_stable():
		return false

	if _active_placement == PLACEMENT_ARTILLERY_DEPOT and not TechTree.can_build_artillery_depot():
		return false

	if _active_placement == PLACEMENT_ACADEMY and not TechTree.can_build_academy():
		return false

	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return false

	var exclude_nodes: Array[Node] = []
	if _placement_ghost != null and is_instance_valid(_placement_ghost):
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


func _start_wall_drag_placement() -> void:
	if not is_inside_tree():
		return

	if not _active_placement.is_empty():
		return

	if not _has_worker_selected():
		print("Select a Worker first")
		return

	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return

	_active_placement = PLACEMENT_WALL_SEGMENT
	_wall_drag_has_start = false
	_wall_drag_start = Vector3.ZERO
	_placement_ghost = _create_wall_ghost()
	buildings_parent.add_child(_placement_ghost)
	set_process(true)


func _process_wall_drag_preview() -> void:
	var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return

	var ground_position: Vector3 = _raycast_ground_plane(
		camera,
		get_viewport().get_mouse_position()
	)
	if not ground_position.is_finite():
		return

	var snapped_position: Vector3 = EnemyBuildPlacement.snap_to_grid(ground_position)
	snapped_position.y = WALL_SEGMENT_GROUND_Y

	if not _wall_drag_has_start:
		if _placement_ghost == null or not is_instance_valid(_placement_ghost):
			_cancel_placement()
			return

		_placement_ghost.visible = true
		_placement_ghost.global_position = snapped_position
		_update_wall_cursor_ghost_validity(snapped_position)
		return

	if _placement_ghost != null and is_instance_valid(_placement_ghost):
		_placement_ghost.visible = false

	var line_positions: Array[Vector3] = EnemyBuildPlacement.get_wall_segment_line_positions(
		_wall_drag_start,
		snapped_position,
		WALL_SEGMENT_GROUND_Y,
		WALL_DRAG_MAX_SEGMENTS
	)
	_sync_wall_drag_ghosts(line_positions)
	_update_wall_drag_ghosts_validity(line_positions)


func _set_wall_drag_start() -> void:
	if _placement_ghost == null or not is_instance_valid(_placement_ghost):
		return

	_wall_drag_start = _placement_ghost.global_position
	_wall_drag_has_start = true


func _place_wall_line() -> void:
	if not is_inside_tree() or not _wall_drag_has_start:
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

	var snapped_end: Vector3 = EnemyBuildPlacement.snap_to_grid(ground_position)
	snapped_end.y = WALL_SEGMENT_GROUND_Y

	var line_positions: Array[Vector3] = EnemyBuildPlacement.get_wall_segment_line_positions(
		_wall_drag_start,
		snapped_end,
		WALL_SEGMENT_GROUND_Y,
		WALL_DRAG_MAX_SEGMENTS
	)
	if line_positions.is_empty():
		return

	var invalid_count: int = 0
	for position: Vector3 in line_positions:
		if not _is_wall_line_position_valid(position, line_positions):
			invalid_count += 1

	if invalid_count > 0:
		ResourceManager.show_feedback(
			"Cannot place wall: %d invalid segment(s) in line" % invalid_count
		)
		return

	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null or not buildings_parent.is_inside_tree():
		return

	var wood_cost: int = line_positions.size() * WALL_SEGMENT_WOOD_COST
	if not ResourceManager.try_spend(WALL_SEGMENT_GOLD_COST, wood_cost):
		ResourceManager.show_feedback("Not enough wood")
		return

	var workers: Array[Worker] = _get_selected_workers()
	var construction_duration: float = _get_construction_duration(
		workers.size(),
		PLACEMENT_WALL_SEGMENT
	)
	var placed_buildings: Array[Building] = []

	for position: Vector3 in line_positions:
		var building: Building = WALL_SEGMENT_SCENE.instantiate() as Building
		buildings_parent.add_child(building)
		building.global_position = position
		building.start_under_construction()
		building.setup_construction(construction_duration)
		placed_buildings.append(building)

	for worker_index: int in range(workers.size()):
		var building_index: int = worker_index % placed_buildings.size()
		workers[worker_index].start_construction_order(placed_buildings[building_index])

	_cancel_placement()


func _create_wall_ghost() -> Node3D:
	var ghost: Node3D = WALL_SEGMENT_SCENE.instantiate()
	_disable_ghost_collision(ghost)
	_disable_ghost_processing(ghost)
	_ghost_material = _apply_ghost_material(ghost)
	return ghost


func _sync_wall_drag_ghosts(line_positions: Array[Vector3]) -> void:
	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return

	while _wall_drag_ghosts.size() > line_positions.size():
		var ghost: Node3D = _wall_drag_ghosts.pop_back()
		_wall_drag_ghost_materials.pop_back()
		if is_instance_valid(ghost):
			ghost.queue_free()

	while _wall_drag_ghosts.size() < line_positions.size():
		var ghost: Node3D = WALL_SEGMENT_SCENE.instantiate()
		_disable_ghost_collision(ghost)
		_disable_ghost_processing(ghost)
		var ghost_material: StandardMaterial3D = _apply_ghost_material(ghost)
		buildings_parent.add_child(ghost)
		_wall_drag_ghosts.append(ghost)
		_wall_drag_ghost_materials.append(ghost_material)

	for index: int in range(line_positions.size()):
		_wall_drag_ghosts[index].global_position = line_positions[index]


func _clear_wall_drag_ghosts() -> void:
	for ghost: Node3D in _wall_drag_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()

	_wall_drag_ghosts.clear()
	_wall_drag_ghost_materials.clear()


func _update_wall_cursor_ghost_validity(position: Vector3) -> void:
	if _ghost_material == null:
		return

	var line_positions: Array[Vector3] = [position]
	var is_valid: bool = (
		_is_wall_line_position_valid(position, line_positions)
		and ResourceManager.can_afford(WALL_SEGMENT_GOLD_COST, WALL_SEGMENT_WOOD_COST)
	)
	_ghost_material.albedo_color = GHOST_COLOR_VALID if is_valid else GHOST_COLOR_INVALID


func _update_wall_drag_ghosts_validity(line_positions: Array[Vector3]) -> void:
	var can_afford_line: bool = ResourceManager.can_afford(
		WALL_SEGMENT_GOLD_COST,
		line_positions.size() * WALL_SEGMENT_WOOD_COST
	)

	for index: int in range(line_positions.size()):
		if index >= _wall_drag_ghost_materials.size():
			continue

		var ghost_material: StandardMaterial3D = _wall_drag_ghost_materials[index]
		if ghost_material == null:
			continue

		var position_valid: bool = _is_wall_line_position_valid(
			line_positions[index],
			line_positions
		)
		var is_valid: bool = position_valid and can_afford_line
		ghost_material.albedo_color = GHOST_COLOR_VALID if is_valid else GHOST_COLOR_INVALID


func _is_wall_line_position_valid(position: Vector3, line_positions: Array[Vector3]) -> bool:
	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return false

	var exclude_nodes: Array[Node] = _get_wall_drag_exclude_nodes()
	var obstacles: Array[Node3D] = EnemyBuildPlacement.collect_all_buildings(buildings_parent)
	for exclude_node: Node in exclude_nodes:
		if exclude_node is Node3D:
			obstacles.erase(exclude_node as Node3D)

	return EnemyBuildPlacement.is_wall_segment_line_position_valid(
		position,
		line_positions,
		obstacles,
		buildings_parent,
		exclude_nodes
	)


func _get_wall_drag_exclude_nodes() -> Array[Node]:
	var exclude_nodes: Array[Node] = []
	if _placement_ghost != null and is_instance_valid(_placement_ghost):
		exclude_nodes.append(_placement_ghost)

	for ghost: Node3D in _wall_drag_ghosts:
		if is_instance_valid(ghost):
			exclude_nodes.append(ghost)

	return exclude_nodes
