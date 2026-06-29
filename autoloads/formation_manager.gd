extends Node

## Global manager for unit group formations and layout presets.
## Formation shapes and spacing come from external Resource data.

signal formation_applied(formation_id: StringName, unit_count: int)
signal formation_cleared()


func _ready() -> void:
	# TODO: Load formation presets from Resource files.
	pass
