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
