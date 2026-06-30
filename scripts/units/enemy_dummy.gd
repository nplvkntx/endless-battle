class_name EnemyDummy
extends Unit

## Stationary enemy placeholder for future combat features.

@onready var _health_component: HealthComponent = $HealthComponent


func _ready() -> void:
	super._ready()
	_health_component.health_depleted.connect(_on_health_depleted)


func _on_health_depleted() -> void:
	print("EnemyDummy died")
	queue_free()


func take_damage(amount: float) -> void:
	_health_component.take_damage(int(amount))


func get_current_health() -> int:
	return _health_component.current_health


func set_movement_target(_target: Vector3) -> void:
	pass


func _physics_process(_delta: float) -> void:
	velocity = Vector3.ZERO
