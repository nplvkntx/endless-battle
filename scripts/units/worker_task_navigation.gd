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
	PerfCounters.record_navigation_path_request()
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
	if _has_reached_task_destination(offset, stopping_distance):
		return true

	if agent.is_navigation_finished():
		process_direct_movement(worker, destination, move_speed, stopping_distance)
		return _has_reached_task_destination(
			destination - worker.global_position, stopping_distance
		)

	var next_position: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = next_position - worker.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		process_direct_movement(worker, destination, move_speed, stopping_distance)
	else:
		worker.velocity = direction.normalized() * move_speed
		worker.velocity.y = 0.0
		worker.move_and_slide()

	return false


static func process_direct_movement(
	worker: CharacterBody3D,
	destination: Vector3,
	move_speed: float,
	stopping_distance: float
) -> bool:
	var offset: Vector3 = destination - worker.global_position
	offset.y = 0.0
	if _has_reached_task_destination(offset, stopping_distance):
		worker.velocity = Vector3.ZERO
		return true

	_move_direct(worker, offset, move_speed)
	return false


static func _has_reached_task_destination(offset: Vector3, stopping_distance: float) -> bool:
	var flat_offset: Vector3 = offset
	flat_offset.y = 0.0
	var finish_tolerance: float = stopping_distance + GatheringConfig.TASK_NAV_FINISH_TOLERANCE
	return flat_offset.length() <= finish_tolerance


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
