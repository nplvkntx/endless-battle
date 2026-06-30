extends Node

## Routes right-click gather commands for wood trees without modifying SelectionManager.

@export var selection_manager_path: NodePath = "../SelectionManager"
@export var camera_path: NodePath = "../Camera3D"


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_RIGHT or not mouse_button.pressed:
		return

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
	if selection_manager == null or camera == null:
		return

	if selection_manager.get("selected_building") != null:
		return

	var selected_units: Array = selection_manager.get("selected_units")
	if selected_units.is_empty():
		return

	var tree: WoodTree = _raycast_tree(camera, mouse_button.position)
	if tree == null:
		return

	var dispatched_to_worker := false
	for unit: Node in selected_units:
		if unit is Worker:
			(unit as Worker).command_gather_tree(tree)
			dispatched_to_worker = true

	if dispatched_to_worker and tree != null and is_instance_valid(tree) and tree.has_method("play_target_feedback"):
		tree.play_target_feedback()

	get_viewport().set_input_as_handled()


func _raycast_tree(camera: Camera3D, screen_position: Vector2) -> WoodTree:
	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return null

	return _find_tree_from_collider(result.collider as Node)


func _find_tree_from_collider(node: Node) -> WoodTree:
	var current: Node = node
	while current:
		if current is WoodTree:
			return current as WoodTree
		current = current.get_parent()
	return null
