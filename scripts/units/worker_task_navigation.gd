class_name WorkerTaskNavigation
extends RefCounted

## NavigationAgent helpers for worker gather/build task movement.
## Reuses UnitNavigation for agent validity / configuration.
## Velocity is applied through Unit.apply_steered_velocity when available.


static func can_use(agent: NavigationAgent3D) -> bool:
	return UnitNavigation.can_use(agent)


static func configure_agent(agent: NavigationAgent3D, stopping_distance: float) -> void:
	UnitNavigation.configure_agent(agent, stopping_distance)


static func is_target_reachable(agent: NavigationAgent3D, target: Vector3) -> bool:
	if not can_use(agent):
		return false

	# Probe without permanently replacing an in-flight destination (avoids repath spam).
	var previous_target: Vector3 = agent.target_position
	agent.target_position = target
	var reachable: bool = agent.is_target_reachable()
	agent.target_position = previous_target
	return reachable


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
		_apply_velocity(worker, Vector3.ZERO, move_speed)
		return true

	if not can_use(agent):
		return process_direct_movement(worker, destination, move_speed, stopping_distance)

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
		# Keep gather packing tight: no combat-style separation blend on task paths.
		_apply_velocity(worker, direction.normalized() * move_speed, move_speed)

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
		_apply_velocity(worker, Vector3.ZERO, move_speed)
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
		_apply_velocity(worker, Vector3.ZERO, move_speed)
		return

	_apply_velocity(worker, offset.normalized() * move_speed, move_speed)


static func _apply_velocity(
	worker: CharacterBody3D, desired_velocity: Vector3, _max_speed: float
) -> void:
	# Authoritative Unit path — no second independent velocity writer.
	if worker is Unit and (worker as Unit).has_method("apply_steered_velocity"):
		# Light UnitSeparation on task paths prevents TH/mine packing freezes.
		# Keep blend low so gather packing stays tighter than combat movement.
		const TASK_SEPARATION_BLEND := 0.35
		var unit := worker as Unit
		if unit.has_move_target:
			unit.apply_steered_velocity(desired_velocity, -1.0, TASK_SEPARATION_BLEND, true, false)
		else:
			# Gather/build often moves without a Unit move-target flag.
			unit.apply_steered_velocity(desired_velocity, -1.0, TASK_SEPARATION_BLEND, true, true)
		return

	worker.velocity = desired_velocity
	worker.velocity.y = 0.0
	worker.move_and_slide()
