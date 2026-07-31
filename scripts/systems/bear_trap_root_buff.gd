class_name BearTrapRootBuff
extends RefCounted

## Root debuff applied when a Bear Trap triggers. Uses the shared Buff system.

const BUFF_ID := &"bear_trap_root"


static func apply(target: Node, source: Node, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if source != null and not is_instance_valid(source):
		source = null

	var definition := BuffDefinition.create(BUFF_ID, duration)
	definition.display_name = "Bear Trap"
	definition.is_debuff = true
	definition.stack_rule = BuffDefinition.StackRule.REPLACE
	definition.max_stacks = 1
	definition.grants_root = true
	definition.move_speed_multiplier = 0.0
	BuffService.apply(target, definition, source, duration)


static func has_root(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return BuffService.has_buff(target, BUFF_ID)
