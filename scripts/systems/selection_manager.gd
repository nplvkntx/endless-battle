extends Node

## Handles unit selection through left-click and drag-box selection.

signal selection_changed(units: Array[Unit])
signal building_selection_changed(building: Building)

const DRAG_THRESHOLD_PIXELS: float = 4.0
const DOUBLE_CLICK_TIME_SECONDS: float = 0.3
const UNIT_GROUP: StringName = &"units"
const WORKER_GROUP: StringName = &"workers"

@export var camera_path: NodePath = "../Camera3D"
@export var selection_box_path: NodePath = "../SelectionUI/SelectionBox"

var selected_units: Array[Unit] = []
var selected_building: Building = null

var _left_button_down: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _last_clicked_unit: Unit = null
var _last_click_time_msec: int = -1


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
	_reset_click_tracking()


func _handle_left_click(screen_position: Vector2) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	var unit: Unit = _raycast_unit(camera, screen_position)
	var building: Building = _raycast_building(camera, screen_position)

	if unit != null and building != null:
		var unit_distance: float = _raycast_hit_distance(
			camera, screen_position, PhysicsLayers.UNITS
		)
		var building_distance: float = _raycast_hit_distance(
			camera, screen_position, PhysicsLayers.BUILDINGS
		)
		if building_distance < unit_distance:
			_set_selected_building(building)
			_reset_click_tracking()
			return

	if unit:
		if _is_double_click(unit):
			_select_all_visible_same_type(unit, camera)
		else:
			_set_selected_units([unit])
		_record_click(unit)
		return

	if building != null:
		_set_selected_building(building)
		_reset_click_tracking()
		return

	_clear_selection()
	_clear_building_selection()
	_reset_click_tracking()


func _handle_right_click(screen_position: Vector2) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	if selected_building is CommandCenter:
		var rally_ground_position: Vector3 = _raycast_ground_plane(camera, screen_position)
		if rally_ground_position.is_finite():
			(selected_building as CommandCenter).set_rally_point(rally_ground_position)
		return

	if selected_units.is_empty():
		return

	var gold_mine: GoldMine = _raycast_gold_mine(camera, screen_position)
	if gold_mine != null:
		_dispatch_gold_mine_gather_command(gold_mine)
		return

	var ground_position: Vector3 = _raycast_ground_plane(camera, screen_position)
	if not ground_position.is_finite():
		return

	var move_targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
		ground_position,
		selected_units.size()
	)
	for index: int in selected_units.size():
		var unit: Unit = selected_units[index]
		if unit is Worker:
			(unit as Worker).cancel_gathering()
		unit.set_movement_target(move_targets[index])


func _dispatch_gold_mine_gather_command(gold_mine: GoldMine) -> void:
	for unit: Unit in selected_units:
		if unit is Worker:
			(unit as Worker).command_gather_gold_mine(gold_mine)


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

	_clear_building_selection_without_signal()
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


func _set_selected_building(building: Building) -> void:
	if selected_building == building:
		return

	_clear_selection_without_signal()
	_clear_building_selection_without_signal()
	selected_building = building
	if selected_building != null:
		selected_building.set_selected(true)
	building_selection_changed.emit(selected_building)
	selection_changed.emit(selected_units)


func _clear_building_selection() -> void:
	if selected_building == null:
		return

	_clear_building_selection_without_signal()
	building_selection_changed.emit(null)


func _clear_building_selection_without_signal() -> void:
	if selected_building == null:
		return

	selected_building.set_selected(false)
	selected_building = null


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
	var result: Dictionary = _raycast_with_mask(camera, screen_position, PhysicsLayers.UNITS)
	if result.is_empty():
		return null

	return _find_unit_from_collider(result.collider as Node)


func _raycast_gold_mine(camera: Camera3D, screen_position: Vector2) -> GoldMine:
	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return null

	return _find_gold_mine_from_collider(result.collider as Node)


func _find_gold_mine_from_collider(node: Node) -> GoldMine:
	var current: Node = node
	while current:
		if current is GoldMine:
			return current as GoldMine
		current = current.get_parent()
	return null


func _is_double_click(unit: Unit) -> bool:
	if _last_clicked_unit == null or _last_click_time_msec < 0:
		return false

	if not _is_same_unit_type(_last_clicked_unit, unit):
		return false

	var elapsed_seconds: float = float(Time.get_ticks_msec() - _last_click_time_msec) / 1000.0
	return elapsed_seconds <= DOUBLE_CLICK_TIME_SECONDS


func _record_click(unit: Unit) -> void:
	_last_clicked_unit = unit
	_last_click_time_msec = Time.get_ticks_msec()


func _reset_click_tracking() -> void:
	_last_clicked_unit = null
	_last_click_time_msec = -1


func _is_same_unit_type(first_unit: Unit, second_unit: Unit) -> bool:
	var first_type: StringName = _get_unit_selection_group(first_unit)
	var second_type: StringName = _get_unit_selection_group(second_unit)
	if first_type.is_empty() or second_type.is_empty():
		return false
	return first_type == second_type


func _get_unit_selection_group(unit: Unit) -> StringName:
	if unit.is_in_group(WORKER_GROUP):
		return WORKER_GROUP

	# TODO: Return soldier/archer groups when those unit types exist.
	return &""


func _select_all_visible_same_type(clicked_unit: Unit, camera: Camera3D) -> void:
	var type_group: StringName = _get_unit_selection_group(clicked_unit)
	if type_group.is_empty():
		_set_selected_units([clicked_unit])
		return

	var units: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group(type_group):
		var unit := node as Unit
		if unit == null:
			continue
		if not camera.is_position_in_frustum(unit.global_position):
			continue
		units.append(unit)

	_set_selected_units(units)


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


func _raycast_building(camera: Camera3D, screen_position: Vector2) -> Building:
	var result: Dictionary = _raycast_with_mask(
		camera, screen_position, PhysicsLayers.BUILDINGS
	)
	if result.is_empty():
		return null

	return _find_building_from_collider(result.collider as Node)


func _raycast_hit_distance(
	camera: Camera3D, screen_position: Vector2, collision_mask: int
) -> float:
	var result: Dictionary = _raycast_with_mask(camera, screen_position, collision_mask)
	if result.is_empty():
		return INF

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	return ray_origin.distance_to(result.position)


func _raycast_with_mask(
	camera: Camera3D, screen_position: Vector2, collision_mask: int
) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = collision_mask

	return space_state.intersect_ray(query)


func _find_building_from_collider(node: Node) -> Building:
	var current: Node = node
	while current:
		if current is Building:
			return current as Building
		current = current.get_parent()
	return null
