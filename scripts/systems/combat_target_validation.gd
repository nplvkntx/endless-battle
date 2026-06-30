class_name CombatTargetValidation
extends RefCounted

## Shared checks for whether a node can be safely targeted or damaged in combat.


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
