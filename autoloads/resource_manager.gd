extends Node

## Global economy manager for player resources (food, wood, gold, etc.).
## UI and other systems listen to signals; they never mutate resources directly.

signal resources_changed()
signal food_changed(current: float, maximum: float)
signal resource_spent_failed(resource_id: StringName, amount: float)


func _ready() -> void:
	# TODO: Initialize economy state from Resource data.
	pass
