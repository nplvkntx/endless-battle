class_name HeroItemRuntime
extends Node

## Per-hero runtime for item actives: cooldowns and charges.
## Existing items have no actives — this stays idle until data enables them.

signal slot_state_changed(slot_index: int)

const COMPONENT_NAME := &"HeroItemRuntime"

## slot_index -> { "cooldown": float, "charges": int, "item_id": StringName }
var _slot_state: Dictionary = {}


static func find_on(host: Node) -> HeroItemRuntime:
	if host == null or not is_instance_valid(host):
		return null
	return host.get_node_or_null(NodePath(String(COMPONENT_NAME))) as HeroItemRuntime


static func ensure_on(host: Node) -> HeroItemRuntime:
	if host == null or not is_instance_valid(host):
		return null
	var existing: HeroItemRuntime = find_on(host)
	if existing != null:
		return existing
	var runtime := HeroItemRuntime.new()
	runtime.name = String(COMPONENT_NAME)
	host.add_child(runtime)
	return runtime


func _ready() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _slot_state.is_empty():
		set_physics_process(false)
		return

	var any_cooling: bool = false
	for slot_index: Variant in _slot_state.keys():
		var state: Dictionary = _slot_state[slot_index]
		var cooldown: float = float(state.get("cooldown", 0.0))
		if cooldown <= 0.0:
			continue
		cooldown = maxf(0.0, cooldown - delta)
		state["cooldown"] = cooldown
		_slot_state[slot_index] = state
		any_cooling = any_cooling or cooldown > 0.0
		slot_state_changed.emit(int(slot_index))

	if not any_cooling:
		set_physics_process(false)


func clear_all() -> void:
	_slot_state.clear()
	set_physics_process(false)


func sync_slot(slot_index: int, item: HeroItemDefinition) -> void:
	if item == null or not item.has_active():
		_slot_state.erase(slot_index)
		slot_state_changed.emit(slot_index)
		_refresh_process()
		return

	var previous: Dictionary = _slot_state.get(slot_index, {})
	var same_item: bool = StringName(previous.get("item_id", &"")) == item.item_id
	var state := {
		"item_id": item.item_id,
		"cooldown": float(previous.get("cooldown", 0.0)) if same_item else 0.0,
		"charges": int(previous.get("charges", item.get_starting_charges())) if same_item else item.get_starting_charges(),
	}
	_slot_state[slot_index] = state
	slot_state_changed.emit(slot_index)
	_refresh_process()


func clear_slot(slot_index: int) -> void:
	if _slot_state.erase(slot_index):
		slot_state_changed.emit(slot_index)
	_refresh_process()


func get_cooldown_remaining(slot_index: int) -> float:
	var state: Variant = _slot_state.get(slot_index, null)
	if state == null:
		return 0.0
	return float((state as Dictionary).get("cooldown", 0.0))


func get_charges(slot_index: int) -> int:
	var state: Variant = _slot_state.get(slot_index, null)
	if state == null:
		return 0
	return int((state as Dictionary).get("charges", 0))


func is_ready(slot_index: int, item: HeroItemDefinition) -> bool:
	if item == null or not item.has_active():
		return false
	if get_cooldown_remaining(slot_index) > 0.0:
		return false
	if item.uses_charges() and get_charges(slot_index) <= 0:
		return false
	return true


## Starts cooldown / spends a charge. Does not invoke gameplay effects.
func begin_activation(slot_index: int, item: HeroItemDefinition) -> bool:
	if not is_ready(slot_index, item):
		return false

	var state: Dictionary = _slot_state.get(slot_index, {
		"item_id": item.item_id,
		"cooldown": 0.0,
		"charges": item.get_starting_charges(),
	})

	if item.uses_charges():
		state["charges"] = maxi(0, int(state.get("charges", 0)) - 1)

	var cooldown: float = item.get_active_cooldown()
	if cooldown > 0.0:
		state["cooldown"] = cooldown
		set_physics_process(true)

	state["item_id"] = item.item_id
	_slot_state[slot_index] = state
	slot_state_changed.emit(slot_index)
	return true


func sync_from_hero(hero: Hero) -> void:
	if hero == null:
		clear_all()
		return

	var seen: Dictionary = {}
	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition:
			sync_slot(slot_index, item as HeroItemDefinition)
			seen[slot_index] = true
		else:
			clear_slot(slot_index)

	for slot_index: Variant in _slot_state.keys():
		if not seen.has(slot_index):
			_slot_state.erase(slot_index)


func _refresh_process() -> void:
	for slot_index: Variant in _slot_state.keys():
		if float((_slot_state[slot_index] as Dictionary).get("cooldown", 0.0)) > 0.0:
			set_physics_process(true)
			return
	set_physics_process(false)
