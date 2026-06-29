extends Unit

## Placeholder worker unit used for early 3D scene testing.

const GOLD_MINE_COMMAND_MESSAGE: String = "Worker received gold mine command"


func _input(event: InputEvent) -> void:
	if not is_selected:
		return
	if not _is_right_mouse_press(event):
		return

	var mouse_button := event as InputEventMouseButton
	var gold_mine: GoldMine = _raycast_gold_mine(mouse_button.position)
	if gold_mine == null:
		return

	print(GOLD_MINE_COMMAND_MESSAGE)
	get_viewport().set_input_as_handled()


func _is_right_mouse_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		return mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_RIGHT
	return false


func _raycast_gold_mine(screen_position: Vector2) -> GoldMine:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null

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
