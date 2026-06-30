class_name NavigationObstacleSetup
extends RefCounted

## Adds a carved NavigationObstacle3D from an existing CollisionShape3D child.


static func apply_from_collision_body(body: CollisionObject3D) -> void:
	if body.get_node_or_null("NavigationObstacle3D") != null:
		return

	var collision_shape: CollisionShape3D = (
		body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	if collision_shape == null or collision_shape.shape == null:
		return

	var obstacle := NavigationObstacle3D.new()
	obstacle.name = "NavigationObstacle3D"
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.position = collision_shape.position

	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		obstacle.radius = maxf(box_shape.size.x, box_shape.size.z) * 0.5
		obstacle.height = box_shape.size.y
	elif collision_shape.shape is CylinderShape3D:
		var cylinder_shape := collision_shape.shape as CylinderShape3D
		obstacle.radius = cylinder_shape.radius
		obstacle.height = cylinder_shape.height
	else:
		obstacle.radius = 0.5
		obstacle.height = 2.0

	body.add_child(obstacle)
