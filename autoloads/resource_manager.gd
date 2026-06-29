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


func add_gold(amount: int) -> void:
	if amount <= 0:
		return

	gold += amount
	resources_changed.emit()


func add_food_max(amount: int) -> void:
	if amount <= 0:
		return

	food_max += amount
	food_changed.emit(food_current, food_max)


func can_afford(gold_cost: int, wood_cost: int) -> bool:
	return gold >= gold_cost and wood >= wood_cost


func try_spend(gold_cost: int, wood_cost: int) -> bool:
	if not can_afford(gold_cost, wood_cost):
		return false

	gold -= gold_cost
	wood -= wood_cost
	resources_changed.emit()
	return true
