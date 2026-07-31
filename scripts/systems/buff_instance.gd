class_name BuffInstance
extends RefCounted

## Runtime buff/debuff applied to a BuffComponent host.

var definition: BuffDefinition
var source: WeakRef
var stacks: int = 1
## Remaining seconds. Negative means infinite.
var remaining_duration: float = 0.0
var period_accumulator: float = 0.0


func setup(
	def: BuffDefinition,
	source_node: Node = null,
	duration_override: float = NAN
) -> void:
	definition = def
	source = weakref(source_node) if source_node != null else null
	stacks = 1
	period_accumulator = 0.0
	if not is_nan(duration_override):
		remaining_duration = duration_override
	elif def != null:
		remaining_duration = def.duration
	else:
		remaining_duration = 0.0


func get_buff_id() -> StringName:
	if definition == null:
		return &""
	return definition.buff_id


func get_source() -> Node:
	if source == null:
		return null
	var node: Object = source.get_ref()
	if node is Node and is_instance_valid(node):
		return node as Node
	return null


func is_infinite() -> bool:
	return remaining_duration < 0.0


func is_expired() -> bool:
	if is_infinite():
		return false
	return remaining_duration <= 0.0


func refresh_duration(duration_seconds: float = NAN) -> void:
	if definition == null:
		return
	if not is_nan(duration_seconds):
		remaining_duration = duration_seconds
	else:
		remaining_duration = definition.duration


func add_stacks(amount: int = 1) -> void:
	if definition == null:
		stacks = maxi(1, stacks + amount)
		return
	stacks = clampi(stacks + amount, 1, maxi(1, definition.max_stacks))


## Advances timers. Returns true when this instance should be removed.
func tick(delta: float) -> bool:
	if definition == null:
		return true
	if not is_infinite():
		remaining_duration -= delta
		if remaining_duration <= 0.0:
			remaining_duration = 0.0
			return true
	return false


func should_tick_period() -> bool:
	return definition != null and definition.period > 0.0


## Accumulates period time. Returns how many period ticks fired this frame.
func consume_period_ticks(delta: float) -> int:
	if not should_tick_period():
		return 0
	period_accumulator += delta
	var ticks: int = 0
	while period_accumulator >= definition.period:
		period_accumulator -= definition.period
		ticks += 1
	return ticks
