extends Unit

## Placeholder worker unit used for early 3D scene testing.

const GOLD_MINE_COMMAND_MESSAGE: String = "Worker received gold mine command"


func _input(event: InputEvent) -> void:
	if not _is_only_selected_worker():
		return
	if not _is_right_mouse_press(event):
		return

	var mouse_button := event as InputEventMouseButton
	var gold_mine: GoldMine = _raycast_gold_mine(mouse_button.position)
	if gold_mine == null:
		return

	print(GOLD_MINE_COMMAND_MESSAGE)
	set_movement_target(_compute_gold_mine_approach_position(gold_mine))
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


func _is_only_selected_worker() -> bool:
	if not is_selected:
		return false

	var selected_worker_count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"workers"):
		var unit := node as Unit
		if unit == null or not unit.is_selected:
			continue
		selected_worker_count += 1
		if selected_worker_count > 1:
			return false

	return selected_worker_count == 1


func _compute_gold_mine_approach_position(gold_mine: GoldMine) -> Vector3:
	var mine_center: Vector3 = gold_mine.global_position
	var direction: Vector3 = global_position - mine_center
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	var stand_off_distance: float = (
		_get_collision_xz_radius(gold_mine)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
	)
	var approach_position: Vector3 = mine_center + direction.normalized() * stand_off_distance
	approach_position.y = global_position.y
	return approach_position


func _get_collision_xz_radius(body: CollisionObject3D) -> float:
	var collision_shape: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 0.5

	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		return maxf(box_shape.size.x, box_shape.size.z) * 0.5

	return 0.5
