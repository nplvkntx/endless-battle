class_name EnemyDummy
extends Unit

## Stationary enemy placeholder for future combat features.

const HEALTH_BAR_WIDTH := 1.2

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill


func _ready() -> void:
	super._ready()
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)


func _on_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(current_health, max_health)


func _update_health_bar(current_health: int, max_health: int) -> void:
	if max_health <= 0:
		return

	var ratio: float = float(current_health) / float(max_health)
	_health_bar_fill.scale.x = ratio
	_health_bar_fill.position.x = HEALTH_BAR_WIDTH * (ratio - 1.0) * 0.5


func _on_health_depleted() -> void:
	_health_bar.visible = false
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
