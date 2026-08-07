class_name UnitNavigation
extends RefCounted

## Shared NavigationAgent3D helpers for combat and general unit movement.
## Workers keep WorkerTaskNavigation for gather/build; non-task moves use Unit.

const ARRIVAL_SLOWDOWN_DISTANCE := 1.35
const ARRIVAL_MIN_SPEED_RATIO := 0.22
const ARRIVAL_ACCEPTANCE_RADIUS := 0.65
const PATH_POINT_HYSTERESIS_SQ := 0.04 # ~0.2m — ignore small next-point jitter
const PATH_POINT_NEAR_DEST_HYSTERESIS_SQ := 0.25 # ~0.5m — damp corridor flips near arrival
const META_LAST_PATH_POINT := &"_nav_last_path_point"
## Matches NavigationRegion bake + NavigationObstacleSetup.GROUND_AGENT_CLEARANCE.
const GROUND_AGENT_RADIUS := 0.55


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

	var accept: float = _acceptance_radius(stopping_distance)
	agent.path_desired_distance = accept
	agent.target_desired_distance = accept
	# RVO avoidance stays off: idle units must never receive safe-velocity drift.
	# Moving units use UnitSeparation; stationary units do not get soft push.
	agent.avoidance_enabled = false


## Match NavigationAgent radius to the unit's horizontal collision footprint.
## Box units use the circumscribed circle so corners are not tighter than physics.
## Never smaller than the bake ground-agent radius.
static func sync_agent_radius_to_collision(agent: NavigationAgent3D, body: CollisionObject3D) -> void:
	if agent == null or body == null:
		return
	agent.radius = maxf(GROUND_AGENT_RADIUS, effective_collision_radius(body))


static func effective_collision_radius(body: CollisionObject3D) -> float:
	if body == null:
		return GROUND_AGENT_RADIUS
	var collision_shape: CollisionShape3D = body.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return GROUND_AGENT_RADIUS
	if collision_shape.shape is CapsuleShape3D:
		return (collision_shape.shape as CapsuleShape3D).radius
	if collision_shape.shape is CylinderShape3D:
		return (collision_shape.shape as CylinderShape3D).radius
	if collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	if collision_shape.shape is BoxShape3D:
		var box := collision_shape.shape as BoxShape3D
		## Circumscribed XZ radius — matches corner contact distance of the box.
		return 0.5 * sqrt(box.size.x * box.size.x + box.size.z * box.size.z)
	return GROUND_AGENT_RADIUS


static func apply_destination(
	agent: NavigationAgent3D,
	destination: Vector3,
	force_repath: bool = false
) -> void:
	if agent == null or not is_instance_valid(agent):
		return

	# Skip no-op writes — NavigationAgent recalculates on every target_position assignment.
	# Exception: refresh when finished so teleports / re-orders to the same point still repath
	# (including Vector3.ZERO, the agent default).
	var previous: Vector3 = agent.target_position
	var delta: Vector3 = destination - previous
	delta.y = 0.0
	var same_target: bool = delta.length_squared() < 0.04 # ~0.2m
	if same_target and not force_repath and not agent.is_navigation_finished():
		return

	if same_target or force_repath:
		# Identical assignment may be ignored by NavigationServer — nudge then set.
		agent.target_position = destination + Vector3(0.05, 0.0, 0.0)
	agent.target_position = destination
	PerfCounters.record_navigation_path_request()


## Re-request the same destination so NavigationAgent rebuilds from the current pose.
## Does not teleport, change command generation, or alter the destination.
static func force_same_destination_repath(
	agent: NavigationAgent3D,
	_body: CharacterBody3D,
	destination: Vector3
) -> bool:
	if agent == null or not is_instance_valid(agent):
		return false
	if not can_use(agent):
		return false
	apply_destination(agent, destination, true)
	return true


static func clear(agent: NavigationAgent3D, unit_position: Vector3) -> void:
	if agent == null or not is_instance_valid(agent):
		return

	agent.avoidance_enabled = false
	agent.target_position = unit_position
	if agent.has_method("set_velocity_forced"):
		agent.set_velocity_forced(Vector3.ZERO)


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
	var distance: float = offset.length()
	var arrive_distance: float = _acceptance_radius_for_body(body, stopping_distance)
	if distance <= arrive_distance:
		_clear_path_point_cache(body)
		_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
		return true

	if not can_use(agent):
		## Corridor guides must not fall through to raw direct steering through buildings.
		if body is Unit and (body as Unit).is_player_corridor_travel_active():
			_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
			return false
		return process_direct_movement(
			body, destination, move_speed, stopping_distance, apply_separation
		)

	if agent.is_navigation_finished():
		## Intermediate corridor waypoint path ended: look ahead instead of ramming the point.
		if body is Unit and (body as Unit).is_player_corridor_travel_active():
			_clear_path_point_cache(body)
			_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
			return true
		return process_direct_movement(
			body, destination, move_speed, stopping_distance, apply_separation
		)

	var next_position: Vector3 = agent.get_next_path_position()
	next_position.y = body.global_position.y
	# Only ignore small next-point jitter; larger swaps must apply for corridors.
	# Near the destination, use a wider hysteresis so building-adjacent path samples do not flip.
	var hysteresis_sq: float = PATH_POINT_HYSTERESIS_SQ
	if distance <= ARRIVAL_SLOWDOWN_DISTANCE * 1.5:
		hysteresis_sq = PATH_POINT_NEAR_DEST_HYSTERESIS_SQ
	if body.has_meta(META_LAST_PATH_POINT):
		var previous: Vector3 = body.get_meta(META_LAST_PATH_POINT) as Vector3
		var delta: Vector3 = next_position - previous
		delta.y = 0.0
		if delta.length_squared() < hysteresis_sq:
			next_position = previous
		else:
			body.set_meta(META_LAST_PATH_POINT, next_position)
	else:
		body.set_meta(META_LAST_PATH_POINT, next_position)

	var direction: Vector3 = next_position - body.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		if body is Unit and (body as Unit).is_player_corridor_travel_active():
			_clear_path_point_cache(body)
			_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
			return true
		return process_direct_movement(
			body, destination, move_speed, stopping_distance, apply_separation
		)

	var speed: float = move_speed
	var slow_start: float = maxf(stopping_distance * 2.0, ARRIVAL_SLOWDOWN_DISTANCE)
	var corridor_travel: bool = (
		body is Unit and (body as Unit).is_player_corridor_travel_active()
	)
	if distance < slow_start and not corridor_travel:
		speed = _arrival_speed(move_speed, distance, stopping_distance)
		# Below crawl threshold, prefer stop over endless micro-approach.
		if distance <= maxf(arrive_distance * 1.25, 0.85):
			_clear_path_point_cache(body)
			_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
			return true
	# Mute separation near arrival so soft settle can complete.
	var use_separation: bool = apply_separation and distance > arrive_distance * 2.0
	if corridor_travel:
		use_separation = apply_separation
	var desired_velocity: Vector3 = direction.normalized() * speed
	_apply_final_velocity(body, desired_velocity, move_speed, use_separation)
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
	var distance: float = offset.length()
	var arrive_distance: float = _acceptance_radius_for_body(body, stopping_distance)
	if distance <= arrive_distance:
		_clear_path_point_cache(body)
		_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
		return true

	if offset.length_squared() < 0.0001:
		_clear_path_point_cache(body)
		_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
		return true

	var corridor_travel: bool = (
		body is Unit and (body as Unit).is_player_corridor_travel_active()
	)
	var speed: float = move_speed
	if not corridor_travel:
		speed = _arrival_speed(move_speed, distance, stopping_distance)
		if distance <= maxf(arrive_distance * 1.25, 0.85):
			_clear_path_point_cache(body)
			_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
			return true
	var use_separation: bool = apply_separation and distance > arrive_distance * 2.0
	if corridor_travel:
		use_separation = apply_separation
	var desired_velocity: Vector3 = offset.normalized() * speed
	_apply_final_velocity(body, desired_velocity, move_speed, use_separation)
	return false


static func _apply_final_velocity(
	body: CharacterBody3D,
	desired_velocity: Vector3,
	max_speed: float,
	apply_separation: bool
) -> void:
	# Prefer Unit's authoritative smoothing path when available.
	# Pass -1 so Unit.get_move_separation_blend() owns the blend amount.
	if body is Unit and (body as Unit).has_method("apply_steered_velocity"):
		(body as Unit).apply_steered_velocity(
			desired_velocity,
			-1.0,
			-1.0 if apply_separation else 0.0
		)
		return

	var final_velocity: Vector3 = desired_velocity
	if apply_separation:
		final_velocity = UnitSeparation.blend_desired_velocity(
			body, desired_velocity, max_speed
		)
	body.velocity = final_velocity
	body.velocity.y = 0.0
	body.move_and_slide()


static func _arrival_speed(move_speed: float, distance: float, stopping_distance: float) -> float:
	var slow_start: float = maxf(stopping_distance * 2.0, ARRIVAL_SLOWDOWN_DISTANCE)
	if distance >= slow_start:
		return move_speed

	var t: float = clampf(
		(distance - stopping_distance) / maxf(0.001, slow_start - stopping_distance),
		0.0,
		1.0
	)
	return move_speed * lerpf(ARRIVAL_MIN_SPEED_RATIO, 1.0, t)


static func _acceptance_radius(stopping_distance: float) -> float:
	return maxf(stopping_distance, ARRIVAL_ACCEPTANCE_RADIUS)


static func _acceptance_radius_for_body(body: CharacterBody3D, stopping_distance: float) -> float:
	if body is Unit and (body as Unit).has_method("get_movement_acceptance_radius"):
		return (body as Unit).get_movement_acceptance_radius()
	return _acceptance_radius(stopping_distance)


static func _clear_path_point_cache(body: CharacterBody3D) -> void:
	if body != null and body.has_meta(META_LAST_PATH_POINT):
		body.remove_meta(META_LAST_PATH_POINT)
