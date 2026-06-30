class_name CombatTargetValidation
extends RefCounted

## Shared checks for whether a node can be safely targeted or damaged in combat.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"


static func is_valid_combat_target(target: Variant) -> bool:
	if target == null:
		return false
	if not is_instance_valid(target):
		return false

	var node: Node = target as Node
	if node != null and node.is_queued_for_deletion():
		return false

	if not _can_receive_damage(target):
		return false

	return _is_alive(target)


static func is_attackable_enemy_building(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if not target is Building:
		return false

	if target is GatherableResource:
		return false

	var building_node: Node = target as Node
	return building_node.is_in_group(ENEMY_BUILDING_GROUP)


static func is_player_unit_attack_target(target: Variant) -> bool:
	if not is_valid_combat_target(target):
		return false

	if target is EnemyDummy:
		return true

	return is_attackable_enemy_building(target)


static func get_target_current_health(target: Variant) -> int:
	var health_component: HealthComponent = _get_health_component(target)
	if health_component != null:
		return health_component.current_health

	if target is Object and (target as Object).has_method("get_current_health"):
		return (target as Object).call("get_current_health")

	return 0


static func apply_damage_to_target(target: Variant, amount: float, attacker = null) -> bool:
	if not is_valid_combat_target(target):
		return false

	if not target is Object or not (target as Object).has_method("take_damage"):
		return false

	(target as Object).call("take_damage", amount, attacker)
	return true


static func is_within_attack_range(
	attacker: Node3D, target: Node3D, attack_range: float
) -> bool:
	if attacker == null or target == null:
		return false

	if is_attackable_enemy_building(target):
		return (
			get_horizontal_attack_distance_to_surface(attacker, target) <= attack_range
		)

	return get_horizontal_center_distance(attacker, target) <= attack_range


static func get_horizontal_attack_distance_to_surface(from: Node3D, target: Node3D) -> float:
	var center_distance: float = get_horizontal_center_distance(from, target)
	if target is CollisionObject3D:
		return maxf(
			0.0,
			center_distance - _get_collision_xz_radius(target as CollisionObject3D)
		)

	return center_distance


static func get_horizontal_center_distance(from: Node3D, to: Node3D) -> float:
	var offset: Vector3 = from.global_position - to.global_position
	offset.y = 0.0
	return offset.length()


static func get_horizontal_attack_distance(attacker: Node3D, target: Node3D) -> float:
	if attacker == null or target == null:
		return INF

	if is_attackable_enemy_building(target):
		return get_horizontal_attack_distance_to_surface(attacker, target)

	return get_horizontal_center_distance(attacker, target)


static func find_closest_player_unit_attack_target_in_range(
	attacker: Node3D, attack_range: float
) -> Node3D:
	if attacker == null or attack_range <= 0.0:
		return null

	var closest_target: Node3D = null
	var closest_distance: float = INF
	var groups_to_search: Array[StringName] = [&"enemies", ENEMY_BUILDING_GROUP]

	for group_name: StringName in groups_to_search:
		for node: Node in attacker.get_tree().get_nodes_in_group(group_name):
			if not node is Node3D:
				continue
			if not is_player_unit_attack_target(node):
				continue

			var target: Node3D = node as Node3D
			var distance: float = get_horizontal_attack_distance(attacker, target)
			if distance > attack_range:
				continue

			if distance < closest_distance:
				closest_distance = distance
				closest_target = target

	return closest_target


static func compute_attack_approach_position(
	attacker: Node3D,
	target: Node3D,
	attack_range: float,
	stopping_distance: float
) -> Vector3:
	var target_center: Vector3 = target.global_position
	var to_attacker: Vector3 = attacker.global_position - target_center
	to_attacker.y = 0.0

	if to_attacker.length_squared() < 0.001:
		to_attacker = Vector3.FORWARD

	var standoff_distance: float
	if is_attackable_enemy_building(target) and target is CollisionObject3D:
		standoff_distance = (
			_get_collision_xz_radius(target as CollisionObject3D)
			+ _get_collision_xz_radius(attacker as CollisionObject3D)
			+ stopping_distance
		)
	else:
		standoff_distance = maxf(attack_range - stopping_distance, stopping_distance)

	var approach_position: Vector3 = (
		target_center + to_attacker.normalized() * standoff_distance
	)
	approach_position.y = attacker.global_position.y
	return approach_position


static func _get_collision_xz_radius(body: CollisionObject3D) -> float:
	if body == null:
		return 0.5

	var collision_shape: CollisionShape3D = body.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 0.5

	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		return maxf(box_shape.size.x, box_shape.size.z) * 0.5

	if collision_shape.shape is CylinderShape3D:
		var cylinder_shape := collision_shape.shape as CylinderShape3D
		return cylinder_shape.radius

	if collision_shape.shape is SphereShape3D:
		var sphere_shape := collision_shape.shape as SphereShape3D
		return sphere_shape.radius

	return 0.5


static func _can_receive_damage(target: Variant) -> bool:
	if target is Node and (target as Node).get_node_or_null("HealthComponent") != null:
		return true

	return target is Object and (target as Object).has_method("take_damage")


static func _is_alive(target: Variant) -> bool:
	var health_component: HealthComponent = _get_health_component(target)
	if health_component != null:
		return health_component.current_health > 0

	if target is Object and (target as Object).has_method("get_current_health"):
		return (target as Object).call("get_current_health") > 0

	return true


static func _get_health_component(target: Variant) -> HealthComponent:
	if target is Node:
		return (target as Node).get_node_or_null("HealthComponent") as HealthComponent
	return null
