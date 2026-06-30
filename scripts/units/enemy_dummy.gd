class_name EnemyDummy
extends Unit

## Stationary enemy placeholder for future combat features.


func set_movement_target(_target: Vector3) -> void:
	pass


func _physics_process(_delta: float) -> void:
	velocity = Vector3.ZERO
