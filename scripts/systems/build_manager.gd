extends Node

## Handles building placement preview and instant placement.

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const FARM_GOLD_COST: int = 80
const FARM_WOOD_COST: int = 20
const FARM_GROUND_Y: float = 0.75
const GHOST_ALPHA: float = 0.4

@export var camera_path: NodePath = "../Camera3D"
@export var buildings_parent_path: NodePath = ".."

var _is_placing_farm: bool = false
var _farm_ghost: Node3D = null


func _process(_delta: float) -> void:
	if not _is_placing_farm or _farm_ghost == null:
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

	_farm_ghost.global_position = Vector3(ground_position.x, FARM_GROUND_Y, ground_position.z)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B and not _is_placing_farm:
			_start_farm_placement()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and _is_placing_farm:
			_cancel_farm_placement()
			get_viewport().set_input_as_handled()
			return

	if not _is_placing_farm:
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_place_farm()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_cancel_farm_placement()
				get_viewport().set_input_as_handled()


func _start_farm_placement() -> void:
	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return

	_is_placing_farm = true
	_farm_ghost = FARM_SCENE.instantiate()
	_disable_ghost_collision(_farm_ghost)
	_apply_ghost_material(_farm_ghost)
	buildings_parent.add_child(_farm_ghost)


func _cancel_farm_placement() -> void:
	_is_placing_farm = false
	if _farm_ghost != null:
		_farm_ghost.queue_free()
		_farm_ghost = null


func _place_farm() -> void:
	if _farm_ghost == null:
		return

	if not ResourceManager.try_spend(FARM_GOLD_COST, FARM_WOOD_COST):
		print("Not enough resources")
		return

	var buildings_parent: Node = get_node_or_null(buildings_parent_path)
	if buildings_parent == null:
		return

	var farm: Node3D = FARM_SCENE.instantiate()
	farm.global_position = _farm_ghost.global_position
	buildings_parent.add_child(farm)


func _disable_ghost_collision(ghost: Node3D) -> void:
	if ghost is CollisionObject3D:
		(ghost as CollisionObject3D).collision_layer = 0
		(ghost as CollisionObject3D).collision_mask = 0

	var collision_shape: CollisionShape3D = ghost.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		collision_shape.disabled = true


func _apply_ghost_material(ghost: Node3D) -> void:
	var mesh_instance: MeshInstance3D = ghost.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		return

	var ghost_material := StandardMaterial3D.new()
	ghost_material.albedo_color = Color(0.6, 0.6, 0.6, GHOST_ALPHA)
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = ghost_material


func _raycast_ground_plane(camera: Camera3D, screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return Vector3(INF, INF, INF)

	var intersection_distance: float = -ray_origin.y / ray_direction.y
	if intersection_distance < 0.0:
		return Vector3(INF, INF, INF)

	return ray_origin + ray_direction * intersection_distance
