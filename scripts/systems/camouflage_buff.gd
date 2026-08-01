class_name CamouflageBuff
extends RefCounted

## Status buff mirroring Ranger Camouflage duration for the shared buff UI.
## Stealth itself stays authoritative on Ranger + StealthService — this buff is display/sync only.

const BUFF_ID := &"ranger_camouflage"


static func apply(target: Node, source: Node, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if source != null and not is_instance_valid(source):
		source = null

	var definition := BuffDefinition.create(BUFF_ID, duration)
	definition.display_name = "Camouflage"
	definition.is_debuff = false
	definition.stack_rule = BuffDefinition.StackRule.REPLACE
	definition.max_stacks = 1
	BuffService.apply(target, definition, source, duration)


static func sync_duration(target: Node, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if duration <= 0.0:
		remove(target)
		return

	var component: BuffComponent = BuffService.get_component(target)
	if component == null:
		apply(target, target, duration)
		return

	var instance: BuffInstance = component.find_first(BUFF_ID)
	if instance == null:
		apply(target, target, duration)
		return

	instance.refresh_duration(duration)


static func remove(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	BuffService.remove(target, BUFF_ID)


static func has_buff(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return BuffService.has_buff(target, BUFF_ID)
