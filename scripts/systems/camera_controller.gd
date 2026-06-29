extends Camera3D

## RTS camera pan and zoom for the main test scene.
## Supports edge scrolling, arrow keys, and mouse wheel zoom only.

@export var edge_margin_pixels: float = 15.0
@export var move_speed: float = 20.0
@export var zoom_speed: float = 3.0
@export var min_height: float = 8.0
@export var max_height: float = 45.0
@export var min_x: float = -50.0
@export var max_x: float = 50.0
@export var min_z: float = -50.0
@export var max_z: float = 50.0


func _process(delta: float) -> void:
	var direction := _get_movement_direction()
	if direction == Vector3.ZERO:
		return

	direction = direction.normalized()
	var movement := direction * move_speed * delta
	movement.y = 0.0
	global_position = _clamp_position(global_position + movement)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(-1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(1.0)


func _get_movement_direction() -> Vector3:
	var direction := Vector3.ZERO
	var forward := _get_flat_forward()
	var right := _get_flat_right()

	if Input.is_action_pressed("ui_up"):
		direction += forward
	if Input.is_action_pressed("ui_down"):
		direction -= forward
	if Input.is_action_pressed("ui_left"):
		direction -= right
	if Input.is_action_pressed("ui_right"):
		direction += right

	var mouse_position := get_viewport().get_mouse_position()
	var viewport_size := get_viewport().get_visible_rect().size

	if mouse_position.x <= edge_margin_pixels:
		direction -= right
	if mouse_position.x >= viewport_size.x - edge_margin_pixels:
		direction += right
	if mouse_position.y <= edge_margin_pixels:
		direction += forward
	if mouse_position.y >= viewport_size.y - edge_margin_pixels:
		direction -= forward

	return direction


func _get_flat_forward() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() == 0.0:
		return Vector3.FORWARD
	return forward.normalized()


func _get_flat_right() -> Vector3:
	var right := global_transform.basis.x
	right.y = 0.0
	if right.length_squared() == 0.0:
		return Vector3.RIGHT
	return right.normalized()


func _apply_zoom(direction: float) -> void:
	var new_position := global_position + (-global_transform.basis.z * direction * zoom_speed)
	if new_position.y < min_height or new_position.y > max_height:
		return
	global_position = _clamp_position(new_position)


func _clamp_position(position: Vector3) -> Vector3:
	position.x = clampf(position.x, min_x, max_x)
	position.z = clampf(position.z, min_z, max_z)
	return position
