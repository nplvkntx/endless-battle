class_name NavigationObstacleSetup
extends RefCounted

## Canonical static-obstacle footprint for buildings / resources.
## Navigation exclusion = physical collision footprint + ground-agent clearance + margin.
##
## carve_navigation_mesh ignores NavigationMesh.agent_radius (Godot stencil carve),
## so clearance MUST be baked into vertices/radius explicitly.

## Must stay aligned with NavigationRegion bake agent_radius.
const GROUND_AGENT_CLEARANCE := 0.55
## Covers rotating box unit circumscribed radius (~0.707) beyond bake agent radius.
const NAV_CLEARANCE_SAFETY_MARGIN := 0.15


static func total_ground_clearance() -> float:
	return GROUND_AGENT_CLEARANCE + NAV_CLEARANCE_SAFETY_MARGIN


static func apply_from_collision_body(body: CollisionObject3D) -> void:
	if body == null:
		return
	var collision_shape: CollisionShape3D = (
		body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	if collision_shape == null:
		return
	apply_to_collision_shape(body, collision_shape, &"NavigationObstacle3D")


static func apply_to_collision_shape(
	body: CollisionObject3D,
	collision_shape: CollisionShape3D,
	obstacle_name: StringName = &"NavigationObstacle3D"
) -> NavigationObstacle3D:
	if body == null or collision_shape == null or collision_shape.shape == null:
		return null

	var existing: NavigationObstacle3D = (
		body.get_node_or_null(NodePath(str(obstacle_name))) as NavigationObstacle3D
	)
	var obstacle: NavigationObstacle3D = existing
	if obstacle == null:
		obstacle = NavigationObstacle3D.new()
		obstacle.name = String(obstacle_name)
		if body.is_inside_tree():
			body.add_child(obstacle)
		else:
			body.call_deferred("add_child", obstacle)
	_configure_obstacle_from_shape(obstacle, collision_shape)
	return obstacle


static func _configure_obstacle_from_shape(
	obstacle: NavigationObstacle3D,
	collision_shape: CollisionShape3D
) -> void:
	obstacle.affect_navigation_mesh = true
	## Exact stencil — agent_radius is NOT applied by Godot when carve is on.
	obstacle.carve_navigation_mesh = true
	obstacle.avoidance_enabled = false
	obstacle.position = collision_shape.position
	obstacle.radius = 0.0

	var clearance: float = total_ground_clearance()
	var basis_scale: Vector3 = collision_shape.scale.abs()
	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		var half_x: float = box_shape.size.x * 0.5 * maxf(basis_scale.x, 0.001)
		var half_z: float = box_shape.size.z * 0.5 * maxf(basis_scale.z, 0.001)
		var hx: float = half_x + clearance
		var hz: float = half_z + clearance
		## Counter-clockwise outline (push agents outward for avoidance if enabled later).
		obstacle.vertices = PackedVector3Array([
			Vector3(-hx, 0.0, -hz),
			Vector3(hx, 0.0, -hz),
			Vector3(hx, 0.0, hz),
			Vector3(-hx, 0.0, hz),
		])
		obstacle.height = box_shape.size.y * maxf(basis_scale.y, 0.001)
	elif collision_shape.shape is CylinderShape3D:
		var cylinder_shape := collision_shape.shape as CylinderShape3D
		var scaled_radius: float = (
			cylinder_shape.radius * maxf(basis_scale.x, basis_scale.z)
		)
		obstacle.vertices = PackedVector3Array()
		obstacle.radius = scaled_radius + clearance
		obstacle.height = cylinder_shape.height * maxf(basis_scale.y, 0.001)
	else:
		obstacle.vertices = PackedVector3Array()
		obstacle.radius = 0.5 + clearance
		obstacle.height = 2.0


## Debug / inspection: physical XZ half-extents of a body's primary CollisionShape3D.
static func physical_half_extents(body: CollisionObject3D) -> Vector2:
	if body == null:
		return Vector2.ZERO
	var collision_shape: CollisionShape3D = (
		body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	if collision_shape == null or collision_shape.shape == null:
		return Vector2.ZERO
	var basis_scale: Vector3 = collision_shape.scale.abs()
	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		return Vector2(
			box_shape.size.x * 0.5 * maxf(basis_scale.x, 0.001),
			box_shape.size.z * 0.5 * maxf(basis_scale.z, 0.001)
		)
	if collision_shape.shape is CylinderShape3D:
		var radius: float = (
			(collision_shape.shape as CylinderShape3D).radius
			* maxf(basis_scale.x, basis_scale.z)
		)
		return Vector2(radius, radius)
	return Vector2.ZERO


## Debug / inspection: navigation exclusion half-extents (physical + clearance).
static func navigation_half_extents(body: CollisionObject3D) -> Vector2:
	var physical: Vector2 = physical_half_extents(body)
	if physical == Vector2.ZERO:
		return Vector2.ZERO
	var clearance: float = total_ground_clearance()
	return physical + Vector2(clearance, clearance)
