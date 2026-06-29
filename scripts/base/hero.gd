class_name Hero
extends Unit

## Base class for hero units. Extends Unit with XP, leveling, abilities, inventory, and respawn.
## Hero-specific values must come from an external Resource — never hardcoded in this script.

signal xp_changed(current_xp: float, xp_to_next_level: float)
signal level_changed(new_level: int)
signal ability_ready(ability_id: StringName)
signal inventory_changed()
signal respawn_requested(hero: Hero)

@export var hero_data: Resource

var level: int = 0
var _current_xp: float = 0.0


func _ready() -> void:
	super._ready()
	_apply_hero_data()


## Loads hero-specific runtime state from hero_data when the data pipeline is available.
func _apply_hero_data() -> void:
	# TODO: Read hero stats and ability slots from hero_data Resource.
	pass
