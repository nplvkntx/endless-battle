class_name HeroPassive
extends RefCounted

## Base class for hero innate passives. Subclass for unique behavior.
## Passives are never manually cast — the host HeroPassiveComponent drives hooks.

signal state_changed()

var definition: HeroPassiveDefinition
var host: Hero
var _is_enabled: bool = false


func setup(passive_host: Hero, passive_definition: HeroPassiveDefinition) -> void:
	host = passive_host
	definition = passive_definition
	_is_enabled = true
	_on_enabled()


func teardown() -> void:
	if not _is_enabled:
		return
	_on_disabled()
	_is_enabled = false
	host = null


func is_enabled() -> bool:
	return _is_enabled and host != null and is_instance_valid(host)


func get_passive_id() -> StringName:
	if definition == null:
		return &""
	return definition.passive_id


func get_display_name() -> String:
	if definition == null:
		return "Passive"
	return definition.display_name


func get_description() -> String:
	if definition == null:
		return ""
	return definition.description


func get_icon_id() -> StringName:
	if definition == null:
		return &""
	if definition.icon_id != &"":
		return definition.icon_id
	return definition.passive_id


## Status line for the ability bar (e.g. "Active", "Ready").
func get_status_text() -> String:
	return "Passive"


## True while a temporary passive effect is visibly active (regen, stacks, etc.).
func is_effect_active() -> bool:
	return false


func format_tooltip() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s (Passive)" % get_display_name())
	lines.append("Cannot be activated.")
	var description: String = get_description()
	if not description.is_empty():
		lines.append(description)
	var extra: String = _format_tooltip_extra()
	if not extra.is_empty():
		lines.append(extra)
	return "\n".join(lines)


## Flat bonuses applied while the passive is equipped. Override or use definition fields.
func get_stat_bonuses() -> Dictionary:
	var bonuses := {
		&"attack_damage": 0,
		&"max_health": 0,
		&"move_speed": 0.0,
		&"armor": 0.0,
	}
	if definition == null or not definition.grants_stat_bonuses:
		return bonuses

	bonuses[&"attack_damage"] = definition.attack_damage_bonus
	bonuses[&"max_health"] = definition.max_health_bonus
	bonuses[&"move_speed"] = definition.move_speed_bonus
	bonuses[&"armor"] = definition.armor_bonus
	return bonuses


func tick(_delta: float) -> void:
	pass


func on_damage_dealt(_target: Object, _result: Dictionary) -> void:
	pass


func on_damage_taken(_result: Dictionary) -> void:
	pass


func on_basic_attack_hit(_target: Object, _result: Dictionary, _attack_index: int) -> void:
	pass


## Fired when attack_index reaches a multiple of definition.attacks_per_proc.
func on_every_x_attacks(_target: Object, _result: Dictionary, _attack_count: int) -> void:
	pass


func on_kill(_victim: Node) -> void:
	pass


func on_assist(_victim: Node) -> void:
	pass


func on_level_up(_new_level: int) -> void:
	pass


func on_out_of_combat_started() -> void:
	pass


func on_out_of_combat_ended() -> void:
	pass


func on_aura_tick(_allies: Array[Node], _delta: float) -> void:
	pass


func _on_enabled() -> void:
	pass


func _on_disabled() -> void:
	pass


func _format_tooltip_extra() -> String:
	return ""


func _notify_state_changed() -> void:
	state_changed.emit()
