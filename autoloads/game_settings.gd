extends Node

## Global access point for game-wide configuration loaded from Resource data.
## Reads settings from external .tres files — does not store hardcoded gameplay values.

signal settings_loaded()
signal settings_changed()

@export var settings_data: Resource


func _ready() -> void:
	# TODO: Load game_settings.tres and expose typed accessors.
	pass
