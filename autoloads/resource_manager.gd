extends Node

## Global economy manager for player resources (food, wood, gold, etc.).
## UI and other systems listen to signals; they never mutate resources directly.

signal resources_changed()
signal food_changed(current: int, maximum: int)
signal resource_spent_failed(resource_id: StringName, amount: float)

const STARTING_GOLD: int = 500
const STARTING_WOOD: int = 300
const STARTING_FOOD: int = 5
const STARTING_FOOD_MAX: int = 15

var gold: int = STARTING_GOLD
var wood: int = STARTING_WOOD
var food_current: int = STARTING_FOOD
var food_max: int = STARTING_FOOD_MAX


func _ready() -> void:
	_emit_resource_state()


func _emit_resource_state() -> void:
	resources_changed.emit()
	food_changed.emit(food_current, food_max)
