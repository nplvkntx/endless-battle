class_name UnitSeparation
extends RefCounted

## Soft unit-to-unit avoidance (WC3-style). Units do not hard-collide with each other;
## nearby units apply a short-range push so armies unpack instead of stacking.

const DEFAULT_RADIUS := 0.55
const QUERY_RADIUS := 1.35
const MIN_SEPARATION := 1.05
const MOVE_BLEND := 0.55
const IDLE_PUSH_SPEED_RATIO := 0.42
const COMBAT_PUSH_SPEED_RATIO := 0.55
const MAX_NEIGHBORS := 10
const OVERLAP_EPSILON := 0.04

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


static func compute_push(body: CharacterBody3D) -> Vector3:
	if body == null or not is_instance_valid(body):
		return Vector3.ZERO

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

	if contributors <= 0 or push.length_squared() < 0.0001:
		return Vector3.ZERO

	return push.normalized()


static func blend_desired_velocity(
	body: CharacterBody3D,
	desired_velocity: Vector3,
	max_speed: float,
	blend: float = MOVE_BLEND
) -> Vector3:
	var push: Vector3 = compute_push(body)
	if push.length_squared() < 0.0001:
		return desired_velocity

	var desired: Vector3 = desired_velocity
	desired.y = 0.0
	var push_velocity: Vector3 = push * max_speed
	var blended: Vector3
	if desired.length_squared() < 0.0001:
		blended = push_velocity * IDLE_PUSH_SPEED_RATIO
	else:
		blended = desired.lerp(desired + push_velocity, clampf(blend, 0.0, 1.0))
		if blended.length() > max_speed:
			blended = blended.normalized() * max_speed

	blended.y = 0.0
	return blended


static func apply_standing_push(
	body: CharacterBody3D,
	move_speed: float,
	combat_mode: bool = false
) -> bool:
	var push: Vector3 = compute_push(body)
	if push.length_squared() < 0.0001:
		body.velocity = Vector3.ZERO
		return false

	var ratio: float = COMBAT_PUSH_SPEED_RATIO if combat_mode else IDLE_PUSH_SPEED_RATIO
	body.velocity = push * move_speed * ratio
	body.velocity.y = 0.0
	body.move_and_slide()
	return true


static func _get_probe_shape() -> SphereShape3D:
	if _probe_shape == null:
		_probe_shape = SphereShape3D.new()
		_probe_shape.radius = QUERY_RADIUS
	return _probe_shape
