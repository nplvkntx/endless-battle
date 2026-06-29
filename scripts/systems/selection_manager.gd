extends Node

## Handles unit selection through left-click and drag-box selection.

signal selection_changed(units: Array[Unit])

const DRAG_THRESHOLD_PIXELS: float = 4.0
const UNIT_GROUP: StringName = &"units"

@export var camera_path: NodePath = "../Camera3D"
@export var selection_box_path: NodePath = "../SelectionUI/SelectionBox"

var selected_units: Array[Unit] = []

var _left_button_down: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		match mouse_button.button_index:
			MOUSE_BUTTON_LEFT:
				if mouse_button.pressed:
					_on_left_press(mouse_button.position)
				else:
					_on_left_release(mouse_button.position)
			MOUSE_BUTTON_RIGHT:
				if mouse_button.pressed:
					_handle_right_click(mouse_button.position)
	elif event is InputEventMouseMotion and _left_button_down:
		_on_mouse_motion((event as InputEventMouseMotion).position)


func _on_left_press(screen_position: Vector2) -> void:
	_left_button_down = true
	_drag_start = screen_position
	_is_dragging = false


func _on_mouse_motion(screen_position: Vector2) -> void:
	var selection_box := _get_selection_box()
	if selection_box == null:
		return

	if _is_dragging:
		selection_box.update_drag(screen_position)
		return

	if _drag_start.distance_to(screen_position) < DRAG_THRESHOLD_PIXELS:
		return

	_is_dragging = true
	selection_box.begin_drag(_drag_start)
	selection_box.update_drag(screen_position)


func _on_left_release(screen_position: Vector2) -> void:
	_left_button_down = false

	if _is_dragging:
		var selection_box := _get_selection_box()
		if selection_box:
			selection_box.end_drag()
		_is_dragging = false
		_finish_drag_selection(screen_position)
		return

	_handle_left_click(screen_position)


func _finish_drag_selection(screen_position: Vector2) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	var selection_rect := _make_screen_rect(_drag_start, screen_position)
	var units := _get_units_in_rect(camera, selection_rect)
	_set_selected_units(units)


func _handle_left_click(screen_position: Vector2) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	var unit: Unit = _raycast_unit(camera, screen_position)
	if unit:
		_set_selected_units([unit])
	else:
		_clear_selection()


func _handle_right_click(screen_position: Vector2) -> void:
	if selected_units.is_empty():
		return

	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	var ground_position: Vector3 = _raycast_ground_plane(camera, screen_position)
	if not ground_position.is_finite():
		return

	for unit: Unit in selected_units:
		unit.set_movement_target(ground_position)


func _get_units_in_rect(camera: Camera3D, rect: Rect2) -> Array[Unit]:
	var units: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group(UNIT_GROUP):
		var unit := node as Unit
		if unit == null:
			continue
		if not _is_unit_in_selection_rect(unit, camera, rect):
			continue
		units.append(unit)
	return units


func _is_unit_in_selection_rect(unit: Unit, camera: Camera3D, rect: Rect2) -> bool:
	if not camera.is_position_in_frustum(unit.global_position):
		return false

	var screen_position: Vector2 = camera.unproject_position(unit.global_position)
	return rect.has_point(screen_position)


func _make_screen_rect(start: Vector2, end: Vector2) -> Rect2:
	return Rect2(
		Vector2(minf(start.x, end.x), minf(start.y, end.y)),
		Vector2(absf(start.x - end.x), absf(start.y - end.y))
	)


func _set_selected_units(units: Array[Unit]) -> void:
	if _arrays_match(selected_units, units):
		return

	_clear_selection_without_signal()
	selected_units = units.duplicate()
	for unit: Unit in selected_units:
		unit.set_selected(true)
	selection_changed.emit(selected_units)


func _clear_selection() -> void:
	if selected_units.is_empty():
		return

	_clear_selection_without_signal()
	selection_changed.emit(selected_units)


func _clear_selection_without_signal() -> void:
	for unit: Unit in selected_units:
		unit.set_selected(false)
	selected_units.clear()


func _arrays_match(current: Array[Unit], next: Array[Unit]) -> bool:
	if current.size() != next.size():
		return false

	for index: int in current.size():
		if current[index] != next[index]:
			return false
	return true


func _get_camera() -> Camera3D:
	return get_node_or_null(camera_path) as Camera3D


func _get_selection_box() -> SelectionBox:
	return get_node_or_null(selection_box_path) as SelectionBox


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
			return current as Unit
		current = current.get_parent()
	return null
