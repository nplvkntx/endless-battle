class_name BuffService
extends RefCounted

## Static API for applying and querying buffs/debuffs on units and buildings.
## Existing abilities do not need to use this yet — infrastructure only.


static func ensure_component(host: Node) -> BuffComponent:
	return BuffComponent.ensure_on(host)


static func get_component(host: Node) -> BuffComponent:
	return BuffComponent.find_on(host)


static func apply(
	target: Node,
	definition: BuffDefinition,
	source: Node = null,
	duration_override: float = NAN
) -> BuffInstance:
	if target == null or not is_instance_valid(target) or definition == null:
		return null
	var component: BuffComponent = ensure_component(target)
	if component == null:
		return null
	return component.apply(definition, source, duration_override)


static func remove(target: Node, buff_id: StringName) -> int:
	var component: BuffComponent = get_component(target)
	if component == null:
		return 0
	return component.remove_by_id(buff_id)


static func remove_all(target: Node) -> void:
	var component: BuffComponent = get_component(target)
	if component != null:
		component.remove_all()


static func has_buff(target: Node, buff_id: StringName) -> bool:
	var component: BuffComponent = get_component(target)
	return component != null and component.has_buff(buff_id)


static func get_stacks(target: Node, buff_id: StringName) -> int:
	var component: BuffComponent = get_component(target)
	if component == null:
		return 0
	return component.get_stacks(buff_id)


static func is_silenced(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	return component != null and component.is_silenced()


static func is_stunned(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	return component != null and component.is_stunned()


static func is_slowed(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	return component != null and component.is_slowed()


static func is_rooted(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	return component != null and component.is_rooted()


static func is_invulnerable(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	return component != null and component.is_invulnerable()


static func can_move(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	if component == null:
		return true
	return component.can_move()


static func can_cast(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	if component == null:
		return true
	return component.can_cast()


static func can_attack(target: Node) -> bool:
	var component: BuffComponent = get_component(target)
	if component == null:
		return true
	return component.can_attack()
