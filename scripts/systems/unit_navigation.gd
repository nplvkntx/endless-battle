class_name UnitNavigation
extends RefCounted

## Arrival / crawl constants shared by custom RTS locomotion.
## Strategic path following uses PlayerRouteNavigation — not NavigationAgent3D.

const ARRIVAL_SLOWDOWN_DISTANCE := 1.35
const ARRIVAL_MIN_SPEED_RATIO := 0.22
const ARRIVAL_ACCEPTANCE_RADIUS := 0.65


## Direct steered crawl toward a point (AI worker unstuck micro-nudges only).
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
		_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
		return true

	if offset.length_squared() < 0.0001:
		_apply_final_velocity(body, Vector3.ZERO, move_speed, false)
		return true

	var speed: float = _arrival_speed(move_speed, distance, stopping_distance)
	if distance <= maxf(arrive_distance * 1.25, 0.85):
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
