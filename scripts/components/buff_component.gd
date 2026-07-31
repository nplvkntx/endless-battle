class_name BuffComponent
extends Node

## Per-entity buff/debuff container. Ticks durations, stacks, and periodic effects.
## Aggregators return identity values when no buffs are active (no gameplay change).

signal buff_applied(instance: BuffInstance)
signal buff_removed(instance: BuffInstance)
signal buffs_changed()
signal periodic_tick(instance: BuffInstance)

const COMPONENT_NAME := &"BuffComponent"

var _instances: Array[BuffInstance] = []
## Cached aggregates — rebuilt when the buff list changes.
var _cache_dirty: bool = true
var _move_speed_multiplier: float = 1.0
var _move_speed_bonus: float = 0.0
var _attack_damage_multiplier: float = 1.0
var _attack_damage_bonus: float = 0.0
var _attack_speed_multiplier: float = 1.0
var _armor_bonus: float = 0.0
var _armor_multiplier: float = 1.0
var _damage_dealt_multiplier: float = 1.0
var _damage_taken_multiplier: float = 1.0
var _healing_dealt_multiplier: float = 1.0
var _healing_received_multiplier: float = 1.0
var _cooldown_reduction: float = 0.0
var _silenced: bool = false
var _stunned: bool = false
var _slowed: bool = false
var _rooted: bool = false
var _invulnerable: bool = false


static func find_on(host: Node) -> BuffComponent:
	if host == null or not is_instance_valid(host):
		return null
	return host.get_node_or_null(NodePath(String(COMPONENT_NAME))) as BuffComponent


static func ensure_on(host: Node) -> BuffComponent:
	if host == null or not is_instance_valid(host):
		return null
	var existing: BuffComponent = find_on(host)
	if existing != null:
		return existing
	var component := BuffComponent.new()
	component.name = String(COMPONENT_NAME)
	host.add_child(component)
	return component


func _ready() -> void:
	set_physics_process(not _instances.is_empty())


func _physics_process(delta: float) -> void:
	if _instances.is_empty():
		set_physics_process(false)
		return

	var expired: Array[BuffInstance] = []
	for instance: BuffInstance in _instances:
		_process_periodic(instance, delta)
		if instance.tick(delta):
			expired.append(instance)

	if expired.is_empty():
		return

	for instance: BuffInstance in expired:
		_instances.erase(instance)
		buff_removed.emit(instance)

	_mark_cache_dirty()
	buffs_changed.emit()
	if _instances.is_empty():
		set_physics_process(false)


func apply(
	definition: BuffDefinition,
	source: Node = null,
	duration_override: float = NAN
) -> BuffInstance:
	if definition == null or definition.buff_id == &"":
		return null

	match definition.stack_rule:
		BuffDefinition.StackRule.IGNORE:
			var existing_ignore: BuffInstance = find_first(definition.buff_id)
			if existing_ignore != null:
				return existing_ignore
			return _add_new(definition, source, duration_override)

		BuffDefinition.StackRule.REPLACE:
			remove_by_id(definition.buff_id)
			return _add_new(definition, source, duration_override)

		BuffDefinition.StackRule.REFRESH:
			var existing_refresh: BuffInstance = find_first(definition.buff_id)
			if existing_refresh != null:
				existing_refresh.refresh_duration(duration_override)
				buffs_changed.emit()
				return existing_refresh
			return _add_new(definition, source, duration_override)

		BuffDefinition.StackRule.STACK:
			var existing_stack: BuffInstance = find_first(definition.buff_id)
			if existing_stack != null:
				existing_stack.add_stacks(1)
				if definition.refresh_on_stack:
					existing_stack.refresh_duration(duration_override)
				_mark_cache_dirty()
				buffs_changed.emit()
				return existing_stack
			return _add_new(definition, source, duration_override)

		BuffDefinition.StackRule.STACK_REFRESH:
			var existing_stack_refresh: BuffInstance = find_first(definition.buff_id)
			if existing_stack_refresh != null:
				existing_stack_refresh.add_stacks(1)
				existing_stack_refresh.refresh_duration(duration_override)
				_mark_cache_dirty()
				buffs_changed.emit()
				return existing_stack_refresh
			return _add_new(definition, source, duration_override)

		BuffDefinition.StackRule.INDEPENDENT:
			return _add_new(definition, source, duration_override)

		_:
			return _add_new(definition, source, duration_override)


func remove_by_id(buff_id: StringName) -> int:
	if buff_id == &"":
		return 0
	var removed_count: int = 0
	var kept: Array[BuffInstance] = []
	for instance: BuffInstance in _instances:
		if instance.get_buff_id() == buff_id:
			removed_count += 1
			buff_removed.emit(instance)
		else:
			kept.append(instance)
	if removed_count == 0:
		return 0
	_instances = kept
	_mark_cache_dirty()
	buffs_changed.emit()
	if _instances.is_empty():
		set_physics_process(false)
	return removed_count


func remove_instance(instance: BuffInstance) -> bool:
	if instance == null or not _instances.has(instance):
		return false
	_instances.erase(instance)
	buff_removed.emit(instance)
	_mark_cache_dirty()
	buffs_changed.emit()
	if _instances.is_empty():
		set_physics_process(false)
	return true


func remove_all() -> void:
	if _instances.is_empty():
		return
	var snapshot: Array[BuffInstance] = _instances.duplicate()
	_instances.clear()
	for instance: BuffInstance in snapshot:
		buff_removed.emit(instance)
	_mark_cache_dirty()
	buffs_changed.emit()
	set_physics_process(false)


func has_buff(buff_id: StringName) -> bool:
	return find_first(buff_id) != null


func find_first(buff_id: StringName) -> BuffInstance:
	for instance: BuffInstance in _instances:
		if instance.get_buff_id() == buff_id:
			return instance
	return null


func get_stacks(buff_id: StringName) -> int:
	var total: int = 0
	for instance: BuffInstance in _instances:
		if instance.get_buff_id() == buff_id:
			total += instance.stacks
	return total


func get_instances() -> Array[BuffInstance]:
	return _instances.duplicate()


func get_instance_count() -> int:
	return _instances.size()


# --- Aggregated modifiers (identity when empty) ---

func get_move_speed_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _move_speed_multiplier


func get_move_speed_bonus() -> float:
	_rebuild_cache_if_needed()
	return _move_speed_bonus


func get_attack_damage_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _attack_damage_multiplier


func get_attack_damage_bonus() -> float:
	_rebuild_cache_if_needed()
	return _attack_damage_bonus


func get_attack_speed_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _attack_speed_multiplier


func get_armor_bonus() -> float:
	_rebuild_cache_if_needed()
	return _armor_bonus


func get_armor_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _armor_multiplier


func get_damage_dealt_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _damage_dealt_multiplier


func get_damage_taken_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _damage_taken_multiplier


func get_healing_dealt_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _healing_dealt_multiplier


func get_healing_received_multiplier() -> float:
	_rebuild_cache_if_needed()
	return _healing_received_multiplier


func get_cooldown_reduction() -> float:
	_rebuild_cache_if_needed()
	return _cooldown_reduction


func is_silenced() -> bool:
	_rebuild_cache_if_needed()
	return _silenced


func is_stunned() -> bool:
	_rebuild_cache_if_needed()
	return _stunned


func is_slowed() -> bool:
	_rebuild_cache_if_needed()
	return _slowed


func is_rooted() -> bool:
	_rebuild_cache_if_needed()
	return _rooted


func is_invulnerable() -> bool:
	_rebuild_cache_if_needed()
	return _invulnerable


func can_move() -> bool:
	_rebuild_cache_if_needed()
	return not _stunned and not _rooted


func can_cast() -> bool:
	_rebuild_cache_if_needed()
	return not _stunned and not _silenced


func can_attack() -> bool:
	_rebuild_cache_if_needed()
	return not _stunned


func modify_outgoing_damage(amount: float) -> float:
	return amount * get_damage_dealt_multiplier()


func modify_incoming_damage(amount: float) -> float:
	return amount * get_damage_taken_multiplier()


func modify_outgoing_healing(amount: float) -> float:
	return amount * get_healing_dealt_multiplier()


func modify_incoming_healing(amount: float) -> float:
	return amount * get_healing_received_multiplier()


func _add_new(
	definition: BuffDefinition,
	source: Node,
	duration_override: float
) -> BuffInstance:
	var instance := BuffInstance.new()
	instance.setup(definition, source, duration_override)
	_instances.append(instance)
	_mark_cache_dirty()
	set_physics_process(true)
	buff_applied.emit(instance)
	buffs_changed.emit()
	return instance


func _process_periodic(instance: BuffInstance, delta: float) -> void:
	var ticks: int = instance.consume_period_ticks(delta)
	if ticks <= 0:
		return

	var host: Node = get_parent()
	var def: BuffDefinition = instance.definition
	for _i in ticks:
		periodic_tick.emit(instance)
		if def.periodic_damage > 0.0 and host != null:
			var options := {}
			if def.periodic_damage_is_true:
				options[DamageService.OPT_DAMAGE_TYPE] = DamageService.DamageType.TRUE
			DamageService.apply(
				host,
				def.periodic_damage * float(instance.stacks),
				instance.get_source(),
				options
			)
		if def.periodic_heal > 0.0 and host != null:
			var health: HealthComponent = DamageService.resolve_health_component(host)
			if health != null:
				var heal_amount: int = int(
					round(def.periodic_heal * float(instance.stacks) * get_healing_received_multiplier())
				)
				if heal_amount > 0:
					health.heal(heal_amount)


func _mark_cache_dirty() -> void:
	_cache_dirty = true


func _rebuild_cache_if_needed() -> void:
	if not _cache_dirty:
		return
	_cache_dirty = false

	_move_speed_multiplier = 1.0
	_move_speed_bonus = 0.0
	_attack_damage_multiplier = 1.0
	_attack_damage_bonus = 0.0
	_attack_speed_multiplier = 1.0
	_armor_bonus = 0.0
	_armor_multiplier = 1.0
	_damage_dealt_multiplier = 1.0
	_damage_taken_multiplier = 1.0
	_healing_dealt_multiplier = 1.0
	_healing_received_multiplier = 1.0
	_cooldown_reduction = 0.0
	_silenced = false
	_stunned = false
	_slowed = false
	_rooted = false
	_invulnerable = false

	for instance: BuffInstance in _instances:
		var def: BuffDefinition = instance.definition
		if def == null:
			continue
		var stacks: float = float(maxi(1, instance.stacks))

		_move_speed_multiplier *= pow(def.move_speed_multiplier, stacks)
		_move_speed_bonus += def.move_speed_bonus * stacks
		_attack_damage_multiplier *= pow(def.attack_damage_multiplier, stacks)
		_attack_damage_bonus += def.attack_damage_bonus * stacks
		_attack_speed_multiplier *= pow(def.attack_speed_multiplier, stacks)
		_armor_bonus += def.armor_bonus * stacks
		_armor_multiplier *= pow(def.armor_multiplier, stacks)
		_damage_dealt_multiplier *= pow(def.damage_dealt_multiplier, stacks)
		_damage_taken_multiplier *= pow(def.damage_taken_multiplier, stacks)
		_healing_dealt_multiplier *= pow(def.healing_dealt_multiplier, stacks)
		_healing_received_multiplier *= pow(def.healing_received_multiplier, stacks)
		_cooldown_reduction += def.cooldown_reduction * stacks

		if def.grants_silence:
			_silenced = true
		if def.grants_stun:
			_stunned = true
		if def.grants_slow or def.move_speed_multiplier < 1.0:
			_slowed = true
		if def.grants_root:
			_rooted = true
		if def.grants_invulnerability:
			_invulnerable = true

	_cooldown_reduction = clampf(_cooldown_reduction, 0.0, 0.95)
