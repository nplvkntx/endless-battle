extends Node

## Tracks enemy gold and wood from gathering. No UI yet.

signal resources_changed()

var gold: int = 0
var wood: int = 0


func add_gold(amount: int) -> void:
	if amount <= 0:
		return

	gold += amount
	resources_changed.emit()


func add_wood(amount: int) -> void:
	if amount <= 0:
		return

	wood += amount
	resources_changed.emit()
