class_name AxeMarkBuff
extends RefCounted

## Shared helper for the Shadow Assassin Axe Mark (Q) debuff.
## A single mark can exist on a target at a time (REPLACE stack rule).

const BUFF_ID := &"axe_marked"


static func apply(target: Node, source: Node, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var definition := BuffDefinition.create(BUFF_ID, duration)
	definition.display_name = "Marked"
	definition.is_debuff = true
	definition.stack_rule = BuffDefinition.StackRule.REPLACE
	definition.max_stacks = 1
	BuffService.apply(target, definition, source, duration)


static func has_mark(target: Node) -> bool:
	return BuffService.has_buff(target, BUFF_ID)


## Removes the mark if present. Returns true when a mark was actually removed.
static func consume(target: Node) -> bool:
	if not has_mark(target):
		return false
	return BuffService.remove(target, BUFF_ID) > 0
