extends Node

## Global manager for unit and building upgrades.
## Upgrade effects and costs are defined in external Resource data.

signal upgrade_applied(upgrade_id: StringName, target_id: StringName)
signal upgrade_failed(upgrade_id: StringName, reason: StringName)


func _ready() -> void:
	# TODO: Load upgrade definitions from Resource files.
	pass
