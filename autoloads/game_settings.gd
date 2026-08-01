extends Node

## Global access point for game-wide configuration loaded from Resource data.
## Reads settings from external .tres files — does not store hardcoded gameplay values.

@warning_ignore("unused_signal")
signal settings_loaded()
@warning_ignore("unused_signal")
signal settings_changed()

@export var settings_data: Resource

## Mirrors HeroAbilityDefinition.CastMode — kept numeric to avoid autoload load-order issues.
const CAST_MODE_NORMAL := 0
const CAST_MODE_QUICK := 1
const CAST_MODE_QUICK_WITH_INDICATOR := 2

## Hero ability cast mode. Default is normal (key → preview → click).
## QUICK and QUICK_WITH_INDICATOR are prepared for a future settings menu.
var hero_ability_cast_mode: int = CAST_MODE_NORMAL


func _ready() -> void:
	# TODO: Load game_settings.tres and expose typed accessors.
	pass


func get_hero_ability_cast_mode() -> int:
	return hero_ability_cast_mode


func set_hero_ability_cast_mode(mode: int) -> void:
	hero_ability_cast_mode = mode
	settings_changed.emit()
