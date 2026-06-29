extends Node

## Global manager for fog-of-war visibility and explored territory.
## Visibility rules and update rates come from external Resource data.

signal visibility_updated()
signal territory_explored(team_id: int, world_position: Vector3)


func _ready() -> void:
	# TODO: Initialize fog grid or shader state from Resource data.
	pass
