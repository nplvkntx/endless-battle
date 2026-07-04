extends Node

## Global economy manager for player resources (food, wood, gold, etc.).
## UI and other systems listen to signals; they never mutate resources directly.

signal resources_changed()
signal food_changed(current: int, maximum: int)
signal resource_spent_failed(resource_id: StringName, amount: float)
signal feedback_message(message: String)

const STARTING_GOLD: int = 500
const STARTING_WOOD: int = 300
const STARTING_FOOD: int = 5
const STARTING_FOOD_MAX: int = 15

var gold: int = STARTING_GOLD
var wood: int = STARTING_WOOD
var food_current: int = STARTING_FOOD
var food_max: int = STARTING_FOOD_MAX


func _ready() -> void:
	reset_to_starting_values()


func reset_to_starting_values() -> void:
	gold = STARTING_GOLD
	wood = STARTING_WOOD
	food_current = STARTING_FOOD
	food_max = STARTING_FOOD_MAX
	_emit_resource_state()


func _emit_resource_state() -> void:
	resources_changed.emit()
	food_changed.emit(food_current, food_max)


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


func add_food_max(amount: int) -> void:
	if amount <= 0:
		return

	food_max += amount
	food_changed.emit(food_current, food_max)


func can_afford(gold_cost: int, wood_cost: int) -> bool:
	return gold >= gold_cost and wood >= wood_cost


func has_food_supply(additional: int) -> bool:
	return food_current + additional <= food_max


func get_training_failure_message(gold_cost: int, food_cost: int) -> String:
	if not has_food_supply(food_cost):
		return "Population cap reached"
	if gold < gold_cost:
		return "Not enough gold"
	return ""


func show_feedback(message: String) -> void:
	if message.is_empty():
		return
	feedback_message.emit(message)


func can_afford_worker_training(gold_cost: int, food_cost: int) -> bool:
	return gold >= gold_cost and has_food_supply(food_cost)


func try_spend_gold(amount: int) -> bool:
	if amount > gold:
		return false

	gold -= amount
	resources_changed.emit()
	return true


func try_pay_worker_training(gold_cost: int, food_cost: int) -> bool:
	if not can_afford_worker_training(gold_cost, food_cost):
		return false

	gold -= gold_cost
	food_current += food_cost
	resources_changed.emit()
	food_changed.emit(food_current, food_max)
	return true


func add_food_used(amount: int) -> void:
	if amount <= 0:
		return

	food_current += amount
	food_changed.emit(food_current, food_max)


func release_food_used(amount: int) -> void:
	if amount <= 0:
		return

	food_current = maxi(0, food_current - amount)
	food_changed.emit(food_current, food_max)


func try_spend(gold_cost: int, wood_cost: int) -> bool:
	if not can_afford(gold_cost, wood_cost):
		return false

	gold -= gold_cost
	wood -= wood_cost
	resources_changed.emit()
	return true
