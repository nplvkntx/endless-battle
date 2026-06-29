extends Node

## Handles single-unit selection through left-click raycasts.

signal selection_changed(unit: Unit)

@export var camera_path: NodePath = "../Camera3D"

var selected_unit: Unit = null


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		MOUSE_BUTTON_RIGHT:
			_handle_right_click(event.position)


func _handle_left_click(screen_position: Vector2) -> void:
	var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return

	var unit: Unit = _raycast_unit(camera, screen_position)
	if unit:
		_select_unit(unit)
	else:
		_deselect()


func _handle_right_click(screen_position: Vector2) -> void:
	if selected_unit == null:
		return

	var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return

	var ground_position: Vector3 = _raycast_ground_plane(camera, screen_position)
	if not ground_position.is_finite():
		return

	selected_unit.move_to(ground_position)


func _raycast_unit(camera: Camera3D, screen_position: Vector2) -> Unit:
	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return null

	return _find_unit_from_collider(result.collider as Node)


func _raycast_ground_plane(camera: Camera3D, screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return Vector3(INF, INF, INF)

	var intersection_distance: float = -ray_origin.y / ray_direction.y
	if intersection_distance < 0.0:
		return Vector3(INF, INF, INF)

	return ray_origin + ray_direction * intersection_distance


func _find_unit_from_collider(node: Node) -> Unit:
	var current: Node = node
	while current:
		if current is Unit:
			return current
		current = current.get_parent()
	return null


func _select_unit(unit: Unit) -> void:
	if selected_unit == unit:
		return

	_deselect()
	selected_unit = unit
	selected_unit.set_selected(true)
	selection_changed.emit(selected_unit)


func _deselect() -> void:
	if selected_unit == null:
		return

	selected_unit.set_selected(false)
	selected_unit = null
	selection_changed.emit(null)
