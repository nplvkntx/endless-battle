extends Node

## Global input routing for selection, commands, and camera controls.
## Translates raw input into game commands via signals — no direct unit control here.

signal selection_requested(screen_position: Vector2)
signal move_command_requested(world_position: Vector3)
signal build_command_requested(building_id: StringName)


func _ready() -> void:
	# TODO: Bind input actions and forward them as signals.
	pass
