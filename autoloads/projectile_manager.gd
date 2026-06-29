extends Node

## Global manager for spawning and pooling projectiles.
## Projectile stats and lifetimes come from external Resource data.

signal projectile_spawned(projectile_id: StringName)
signal projectile_despawned(projectile_id: StringName)


func _ready() -> void:
	# TODO: Set up object pools using projectile Resource definitions.
	pass
