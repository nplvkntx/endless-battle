class_name HealthComponent
extends Node

## Reusable health storage and damage handling for units and buildings.

signal health_changed(current_health: int, max_health: int)
signal health_depleted

@export var max_health: int = 100

var current_health: int = 0


func _ready() -> void:
	current_health = max_health


func take_damage(amount: int) -> void:
	if current_health <= 0:
		return

	current_health = maxi(0, current_health - amount)
	print(
		"Took %d damage. Remaining health: %d / %d"
		% [amount, current_health, max_health]
	)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		health_depleted.emit()
