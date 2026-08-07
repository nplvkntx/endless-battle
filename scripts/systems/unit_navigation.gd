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


static func apply_destination(agent: NavigationAgent3D, destination: Vector3) -> void:
	if agent == null or not is_instance_valid(agent):
		return

	# Skip no-op writes — NavigationAgent recalculates on every target_position assignment.
	# Exception: refresh when finished so teleports / re-orders to the same point still repath
	# (including Vector3.ZERO, the agent default).
	var previous: Vector3 = agent.target_position
	var delta: Vector3 = destination - previous
	delta.y = 0.0
	var same_target: bool = delta.length_squared() < 0.04 # ~0.2m
	if same_target and not agent.is_navigation_finished():
		return

	if same_target:
		# Identical assignment may be ignored by NavigationServer — nudge then set.
		agent.target_position = destination + Vector3(0.05, 0.0, 0.0)
	agent.target_position = destination
	PerfCounters.record_navigation_path_request()


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
		# Caller owns a NavigationAgent — never collision-blind steer as a fallback.
		_hold_body(body)
		return false

	if agent.is_navigation_finished():
		# Path not ready or finished early — wait for repath; do not cut through obstacles.
		_hold_body(body)
		return false

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
		_hold_body(body)
		return false

	var speed: float = move_speed
	var slow_start: float = maxf(stopping_distance * 2.0, ARRIVAL_SLOWDOWN_DISTANCE)
	if distance < slow_start:
		speed = _arrival_speed(move_speed, distance, stopping_distance)
		# Below crawl threshold, prefer stop over endless micro-approach.
		if distance <= maxf(arrive_distance * 1.25, 0.85):
			_clear_path_point_cache(body)
			_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
			return true
	# Mute separation near arrival so soft settle can complete.
	var use_separation: bool = apply_separation and distance > arrive_distance * 2.0
	var desired_velocity: Vector3 = direction.normalized() * speed
	_apply_final_velocity(body, desired_velocity, move_speed, use_separation)
	return false


static func _hold_body(body: CharacterBody3D) -> void:
	_apply_final_velocity(body, Vector3.ZERO, 0.0, false)


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

	var speed: float = _arrival_speed(move_speed, distance, stopping_distance)
	if distance <= maxf(arrive_distance * 1.25, 0.85):
		_clear_path_point_cache(body)
		_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
		return true
	var use_separation: bool = apply_separation and distance > arrive_distance * 2.0
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
