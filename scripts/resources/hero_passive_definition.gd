class_name HeroPassiveDefinition
extends Resource

## Data template for a hero innate passive (separate from QWER).
## Runtime behavior lives on a HeroPassive subclass referenced by script_path.

@export var passive_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Key used by HeroPassiveIcons for the UI icon.
@export var icon_id: StringName = &""
## Path to a GDScript that extends HeroPassive.
@export_file("*.gd") var script_path: String = ""

# --- Optional built-in hooks the component can drive ---
@export var grants_stat_bonuses: bool = false
@export var attack_damage_bonus: int = 0
@export var max_health_bonus: int = 0
@export var move_speed_bonus: float = 0.0
@export var armor_bonus: float = 0.0

@export var tracks_out_of_combat: bool = false
## Seconds without dealing/taking damage before out-of-combat hooks fire.
@export var out_of_combat_seconds: float = 0.0
@export var tracks_basic_attacks: bool = false
@export var attacks_per_proc: int = 0

@export var has_ally_aura: bool = false
@export var aura_radius: float = 0.0
@export var aura_tick_interval: float = 0.5


func create_instance() -> HeroPassive:
	if script_path.is_empty():
		return HeroPassive.new()

	var script: Script = load(script_path) as Script
	if script == null:
		push_warning("HeroPassiveDefinition: failed to load script %s" % script_path)
		return HeroPassive.new()

	var instance: Object = script.new()
	if instance is HeroPassive:
		return instance as HeroPassive

	push_warning("HeroPassiveDefinition: script is not a HeroPassive: %s" % script_path)
	if instance is RefCounted:
		pass
	elif instance is Node:
		(instance as Node).queue_free()
	return HeroPassive.new()


static func create(
	passive_id: StringName,
	display_name: String,
	description: String,
	script_path: String,
	icon_id: StringName = &""
) -> HeroPassiveDefinition:
	var definition := HeroPassiveDefinition.new()
	definition.passive_id = passive_id
	definition.display_name = display_name
	definition.description = description
	definition.script_path = script_path
	definition.icon_id = icon_id if icon_id != &"" else passive_id
	return definition
