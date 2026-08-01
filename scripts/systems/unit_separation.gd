class_name UnitSeparation
extends RefCounted

## Soft unit-to-unit avoidance (WC3-style). Units do not hard-collide with each other;
## nearby units apply a short-range push so armies unpack instead of stacking.
## Push is cached and lightly hysteretic; forward motion is preserved against full reverses.

const DEFAULT_RADIUS := 0.55
const QUERY_RADIUS := 1.35
const MIN_SEPARATION := 1.05
const MOVE_BLEND := 0.48
const IDLE_PUSH_SPEED_RATIO := 0.35
const COMBAT_PUSH_SPEED_RATIO := 0.22
const MAX_NEIGHBORS := 10
const OVERLAP_EPSILON := 0.04
const MIN_FORWARD_RATIO := 0.25
const PUSH_CACHE_SECONDS := 0.05
const SIDE_HYSTERESIS_SECONDS := 0.18
const PUSH_DEAD_ZONE_SQ := 0.0025
const STANDING_SMOOTH := 10.0

const META_PUSH_CACHE := &"_sep_push_cache"
const META_PUSH_CACHE_TIME := &"_sep_push_cache_time"
const META_SIDE := &"_sep_side"
const META_SIDE_TIMER := &"_sep_side_timer"
const META_STANDING_VEL := &"_sep_standing_vel"

static var _probe_shape: SphereShape3D = null


static func get_unit_radius(body: CollisionObject3D) -> float:
	if body == null:
		return DEFAULT_RADIUS

	var collision_shape: CollisionShape3D = body.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return DEFAULT_RADIUS

	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		return maxf(box_shape.size.x, box_shape.size.z) * 0.5

	if collision_shape.shape is CylinderShape3D:
		return (collision_shape.shape as CylinderShape3D).radius

	if collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius

	return DEFAULT_RADIUS


static func clear_state(body: Object) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_meta(META_PUSH_CACHE):
		body.remove_meta(META_PUSH_CACHE)
	if body.has_meta(META_PUSH_CACHE_TIME):
		body.remove_meta(META_PUSH_CACHE_TIME)
	if body.has_meta(META_SIDE):
		body.remove_meta(META_SIDE)
	if body.has_meta(META_SIDE_TIMER):
		body.remove_meta(META_SIDE_TIMER)
	if body.has_meta(META_STANDING_VEL):
		body.remove_meta(META_STANDING_VEL)


static func compute_push(body: CharacterBody3D, use_cache: bool = true) -> Vector3:
	if body == null or not is_instance_valid(body):
		return Vector3.ZERO

	var now_sec: float = float(Time.get_ticks_msec()) * 0.001
	if use_cache and body.has_meta(META_PUSH_CACHE) and body.has_meta(META_PUSH_CACHE_TIME):
		var cache_time: float = float(body.get_meta(META_PUSH_CACHE_TIME))
		if now_sec - cache_time < PUSH_CACHE_SECONDS:
			return body.get_meta(META_PUSH_CACHE) as Vector3

	var push: Vector3 = _query_push(body)
	body.set_meta(META_PUSH_CACHE, push)
	body.set_meta(META_PUSH_CACHE_TIME, now_sec)
	return push


static func blend_desired_velocity(
	body: CharacterBody3D,
	desired_velocity: Vector3,
	max_speed: float,
	blend: float = MOVE_BLEND
) -> Vector3:
	var push: Vector3 = compute_push(body)
	if push.length_squared() < PUSH_DEAD_ZONE_SQ:
		return desired_velocity

	var desired: Vector3 = desired_velocity
	desired.y = 0.0
	var push_velocity: Vector3 = push * max_speed
	var blended: Vector3
	if desired.length_squared() < 0.0001:
		blended = push_velocity * IDLE_PUSH_SPEED_RATIO
	else:
		var desired_dir: Vector3 = desired.normalized()
		var desired_speed: float = minf(desired.length(), max_speed)
		var effective_blend: float = clampf(blend, 0.0, 1.0)
		# Neighbor ahead → rearward push. Soften so corridors remain passable.
		var forward_push: float = push.dot(desired_dir)
		if forward_push < -0.25:
			effective_blend *= 0.4
		else:
			# Path-relative side hysteresis (left/right of travel), not world axes.
			push = _apply_path_side_hysteresis(body, push, desired_dir)
			push_velocity = push * max_speed

		# Original-style blend, then clamp so separation cannot fully reverse travel.
		blended = desired.lerp(desired + push_velocity, effective_blend)
		var forward_speed: float = blended.dot(desired_dir)
		var min_forward: float = desired_speed * MIN_FORWARD_RATIO
		if forward_push < -0.25:
			min_forward = desired_speed * 0.12
		if forward_speed < min_forward:
			blended += desired_dir * (min_forward - forward_speed)

		if blended.length() > max_speed:
			blended = blended.normalized() * max_speed

	blended.y = 0.0
	return blended


static func _apply_path_side_hysteresis(
	body: CharacterBody3D,
	push: Vector3,
	desired_dir: Vector3
) -> Vector3:
	var right: Vector3 = desired_dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		return push
	right = right.normalized()

	var lateral: float = push.dot(right)
	if absf(lateral) < 0.08:
		return push

	var now_sec: float = float(Time.get_ticks_msec()) * 0.001
	var side: float = 0.0
	var side_timer: float = -999.0
	if body.has_meta(META_SIDE):
		side = float(body.get_meta(META_SIDE))
	if body.has_meta(META_SIDE_TIMER):
		side_timer = float(body.get_meta(META_SIDE_TIMER))

	var lateral_sign: float = signf(lateral)
	if side == 0.0:
		side = lateral_sign
		side_timer = now_sec
	elif now_sec - side_timer < SIDE_HYSTERESIS_SECONDS and lateral_sign != side:
		# Keep previous pass side briefly instead of flipping every frame.
		var forward_part: Vector3 = desired_dir * push.dot(desired_dir)
		push = (forward_part + right * side * absf(lateral)).normalized()
	else:
		side = lateral_sign
		side_timer = now_sec

	body.set_meta(META_SIDE, side)
	body.set_meta(META_SIDE_TIMER, side_timer)
	return push


static func apply_standing_push(
	body: CharacterBody3D,
	move_speed: float,
	combat_mode: bool = false
) -> bool:
	var push: Vector3 = compute_push(body)
	var ratio: float = COMBAT_PUSH_SPEED_RATIO if combat_mode else IDLE_PUSH_SPEED_RATIO
	var target_velocity: Vector3 = Vector3.ZERO
	if push.length_squared() >= PUSH_DEAD_ZONE_SQ:
		# Combat: only unpack hard overlaps so in-range units do not shuffle.
		if combat_mode and push.length_squared() < 0.09:
			target_velocity = Vector3.ZERO
		else:
			target_velocity = push * move_speed * ratio

	var previous: Vector3 = Vector3.ZERO
	if body.has_meta(META_STANDING_VEL):
		previous = body.get_meta(META_STANDING_VEL) as Vector3

	var delta: float = 0.016667
	if body.is_inside_tree():
		delta = body.get_physics_process_delta_time()
	var smooth: float = minf(1.0, delta * STANDING_SMOOTH)
	var smoothed: Vector3 = previous.lerp(target_velocity, smooth)
	if smoothed.length_squared() < PUSH_DEAD_ZONE_SQ:
		smoothed = Vector3.ZERO

	body.set_meta(META_STANDING_VEL, smoothed)
	body.velocity = smoothed
	body.velocity.y = 0.0
	if smoothed.length_squared() < PUSH_DEAD_ZONE_SQ:
		return false

	body.move_and_slide()
	return true


static func _query_push(body: CharacterBody3D) -> Vector3:
	var world: World3D = body.get_world_3d()
	if world == null:
		return Vector3.ZERO

	var self_radius: float = get_unit_radius(body)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _get_probe_shape()
	query.transform = Transform3D(Basis.IDENTITY, body.global_position)
	query.collision_mask = PhysicsLayers.UNITS
	query.exclude = [body.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(
		query, MAX_NEIGHBORS
	)
	if hits.is_empty():
		return Vector3.ZERO

	var push: Vector3 = Vector3.ZERO
	var contributors: int = 0
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider")
		if collider == null or not collider is CharacterBody3D:
			continue
		if not (collider as Node).is_in_group(&"units"):
			continue

		var other: CharacterBody3D = collider as CharacterBody3D
		var offset: Vector3 = body.global_position - other.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		var desired: float = maxf(
			MIN_SEPARATION,
			self_radius + get_unit_radius(other) + OVERLAP_EPSILON
		)
		if distance >= desired:
			continue

		var direction: Vector3
		if distance < 0.001:
			# Deterministic tie-break so overlapping units still peel apart.
			var hash_bits: int = abs(body.get_instance_id() - other.get_instance_id())
			var angle: float = float(hash_bits % 628) * 0.01
			direction = Vector3(cos(angle), 0.0, sin(angle))
		else:
			direction = offset / distance

		var weight: float = (desired - distance) / desired
		push += direction * weight
		contributors += 1

	if contributors <= 0 or push.length_squared() < PUSH_DEAD_ZONE_SQ:
		return Vector3.ZERO

	return push.normalized()


static func _get_probe_shape() -> SphereShape3D:
	if _probe_shape == null:
		_probe_shape = SphereShape3D.new()
		_probe_shape.radius = QUERY_RADIUS
	return _probe_shape
