class_name WorkerTaskNavigation
extends RefCounted

## NavigationAgent helpers for worker gather/build task movement.


static func can_use(agent: NavigationAgent3D) -> bool:
	if agent == null or not is_instance_valid(agent):
		return false

	var nav_map: RID = agent.get_navigation_map()
	if nav_map == RID():
		return false

	return NavigationServer3D.map_is_active(nav_map)


static func configure_agent(agent: NavigationAgent3D, stopping_distance: float) -> void:
	if agent == null:
		return

	agent.path_desired_distance = stopping_distance
	agent.target_desired_distance = stopping_distance
	agent.avoidance_enabled = false


static func is_target_reachable(agent: NavigationAgent3D, target: Vector3) -> bool:
	if not can_use(agent):
		return false

	agent.target_position = target
	return agent.is_target_reachable()


static func process_movement(
	worker: CharacterBody3D,
	agent: NavigationAgent3D,
	destination: Vector3,
	move_speed: float,
	stopping_distance: float
) -> bool:
	var offset: Vector3 = destination - worker.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var finish_tolerance: float = stopping_distance + GatheringConfig.TASK_NAV_FINISH_TOLERANCE
	if distance <= finish_tolerance:
		return true

	if agent.is_navigation_finished():
		if distance <= finish_tolerance + 0.5:
			return true

		_move_direct(worker, offset, move_speed)
		return false

	var next_position: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = next_position - worker.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		_move_direct(worker, offset, move_speed)
	else:
		worker.velocity = direction.normalized() * move_speed

	worker.velocity.y = 0.0
	worker.move_and_slide()
	return false


static func _move_direct(
	worker: CharacterBody3D, offset: Vector3, move_speed: float
) -> void:
	if offset.length_squared() < 0.0001:
		worker.velocity = Vector3.ZERO
		worker.move_and_slide()
		return

	worker.velocity = offset.normalized() * move_speed
	worker.velocity.y = 0.0
	worker.move_and_slide()
