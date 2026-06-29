extends Node

## Global manager for technology research and unlock state.
## Research costs and prerequisites come from external Resource data.

signal tech_unlocked(tech_id: StringName)
signal research_started(tech_id: StringName)
signal research_completed(tech_id: StringName)
signal research_failed(tech_id: StringName, reason: StringName)


func _ready() -> void:
	# TODO: Load tech definitions from Resource files.
	pass
