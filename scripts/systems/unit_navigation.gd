class_name UnitNavigation
extends RefCounted

## Shared NavigationAgent3D helpers for combat and general unit movement.
## Workers keep WorkerTaskNavigation for gather/build; non-task moves use Unit.


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

	agent.path_desired_distance = maxf(stopping_distance, 0.15)
	agent.target_desired_distance = maxf(stopping_distance, 0.15)
	agent.avoidance_enabled = false


static func apply_destination(agent: NavigationAgent3D, destination: Vector3) -> void:
	if agent == null or not is_instance_valid(agent):
		return

	# Skip no-op writes — NavigationAgent recalculates on every target_position assignment.
	var previous: Vector3 = agent.target_position
	var delta: Vector3 = destination - previous
	delta.y = 0.0
	if delta.length_squared() < 0.04: # ~0.2m
		return

	agent.target_position = destination
	PerfCounters.record_navigation_path_request()


static func clear(agent: NavigationAgent3D, unit_position: Vector3) -> void:
	if agent == null or not is_instance_valid(agent):
		return

	agent.target_position = unit_position


static func process_movement(
	body: CharacterBody3D,
	agent: NavigationAgent3D,
	destination: Vector3,
	move_speed: float,
	stopping_distance: float,
	apply_separation: bool = true
) -> bool:
	var offset: Vector3 = destination - body.global_position
	offset.y = 0.0
	if offset.length() <= stopping_distance:
		body.velocity = Vector3.ZERO
		return true

	if not can_use(agent):
		return process_direct_movement(
			body, destination, move_speed, stopping_distance, apply_separation
		)

	if agent.is_navigation_finished():
		return process_direct_movement(
			body, destination, move_speed, stopping_distance, apply_separation
		)

	var next_position: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = next_position - body.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return process_direct_movement(
			body, destination, move_speed, stopping_distance, apply_separation
		)

	var desired_velocity: Vector3 = direction.normalized() * move_speed
	if apply_separation:
		desired_velocity = UnitSeparation.blend_desired_velocity(
			body, desired_velocity, move_speed
		)
	body.velocity = desired_velocity
	body.velocity.y = 0.0
	body.move_and_slide()
	return false


static func process_direct_movement(
	body: CharacterBody3D,
	destination: Vector3,
	move_speed: float,
	stopping_distance: float,
	apply_separation: bool = true
) -> bool:
	var offset: Vector3 = destination - body.global_position
	offset.y = 0.0
	if offset.length() <= stopping_distance:
		body.velocity = Vector3.ZERO
		return true

	if offset.length_squared() < 0.0001:
		body.velocity = Vector3.ZERO
		body.move_and_slide()
		return true

	var desired_velocity: Vector3 = offset.normalized() * move_speed
	if apply_separation:
		desired_velocity = UnitSeparation.blend_desired_velocity(
			body, desired_velocity, move_speed
		)
	body.velocity = desired_velocity
	body.velocity.y = 0.0
	body.move_and_slide()
	return false
