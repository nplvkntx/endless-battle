extends Node

## Global manager for spawning and pooling projectiles.
## Visual trails/impacts are owned by ImpactEffects / ImpactFxPool.

signal projectile_spawned(projectile_id: StringName)
signal projectile_despawned(projectile_id: StringName)


func _ready() -> void:
	# Projectile node pooling can plug in here later.
	# Impact/trail FX already pool via ImpactEffects.
	pass
