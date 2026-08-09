extends Camera3D

## RTS camera pan and zoom for the main test scene.
## Supports edge scrolling, arrow keys, mouse wheel zoom, and hold-Space hero follow.

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
	## LoL-style hold-Space: living PLAYER hero projects to viewport center while held.
	## Must run before normal pan so edge/WASD cannot overwrite the same frame.
	if Input.is_action_pressed(&"focus_hero"):
		var hero: Hero = _get_living_player_hero()
		if hero != null:
			center_world_position_on_screen(hero.global_position)
			return

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
			_apply_zoom(1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(-1.0)


func _get_living_player_hero() -> Hero:
	return HeroProgressionStore.get_living_hero(false)


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

	if mouse_position.x <= edge_margin_pixels and edge_margin_pixels > 0.0:
		direction -= right
	if mouse_position.x >= viewport_size.x - edge_margin_pixels and edge_margin_pixels > 0.0:
		direction += right
	if mouse_position.y <= edge_margin_pixels and edge_margin_pixels > 0.0:
		direction += forward
	if mouse_position.y >= viewport_size.y - edge_margin_pixels and edge_margin_pixels > 0.0:
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


## Centers a world point on the viewport by translating camera X/Z only.
## Preserves Y, rotation, and FOV. Correct for pitched RTS cameras.
func center_world_position_on_screen(world_position: Vector3) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var center: Vector2 = viewport.get_visible_rect().size * 0.5
	var ray_origin: Vector3 = project_ray_origin(center)
	var ray_dir: Vector3 = project_ray_normal(center)
	if absf(ray_dir.y) < 0.0001:
		## Degenerate (looking horizontal) — fall back to X/Z match.
		focus_on_world_position(world_position)
		return
	var t: float = (world_position.y - ray_origin.y) / ray_dir.y
	var ground_hit: Vector3 = ray_origin + ray_dir * t
	var delta := Vector3(
		world_position.x - ground_hit.x,
		0.0,
		world_position.z - ground_hit.z
	)
	global_position = _clamp_position(global_position + delta)


## Legacy/minimap helper: put camera X/Z over a world point (does NOT screen-center
## under pitch). Prefer center_world_position_on_screen for Space follow.
func focus_on_world_position(world_position: Vector3) -> void:
	var new_position := global_position
	new_position.x = world_position.x
	new_position.z = world_position.z
	global_position = _clamp_position(new_position)


## Screen-space error of a world point vs viewport center (pixels).
func screen_center_error(world_position: Vector3) -> float:
	var viewport := get_viewport()
	if viewport == null:
		return INF
	var center: Vector2 = viewport.get_visible_rect().size * 0.5
	return unproject_position(world_position).distance_to(center)
