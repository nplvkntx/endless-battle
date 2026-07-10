extends Node

## Internal enemy gold/wood/food stockpile from worker gathering. Not shown on player HUD.

signal resources_changed()

var gold: int = MatchConfig.NORMAL_STARTING_GOLD
var wood: int = MatchConfig.NORMAL_STARTING_WOOD
var food_current: int = 0
var food_max: int = MatchConfig.AI_STARTING_FOOD_MAX

var _reserved_gold: int = 0
var _reserved_wood: int = 0


func _ready() -> void:
	reset_to_starting_values()


func reset_to_starting_values() -> void:
	gold = MatchConfig.NORMAL_STARTING_GOLD
	wood = MatchConfig.NORMAL_STARTING_WOOD
	food_current = 0
	food_max = MatchConfig.AI_STARTING_FOOD_MAX
	_reserved_gold = 0
	_reserved_wood = 0
	resources_changed.emit()
	call_deferred("_initialize_population_from_scene")


func add_gold(amount: int) -> void:
	if amount <= 0:
		return

	gold += amount
	resources_changed.emit()
	_log_totals_if_debug()


func add_wood(amount: int) -> void:
	if amount <= 0:
		return

	wood += amount
	resources_changed.emit()
	_log_totals_if_debug()


func add_food_max(amount: int) -> void:
	if amount == 0:
		return

	food_max = maxi(MatchConfig.STARTING_FOOD_MAX, food_max + amount)
	resources_changed.emit()
	_log_totals_if_debug()


func get_spendable_gold() -> int:
	return maxi(0, gold - _reserved_gold)


func get_spendable_wood() -> int:
	return maxi(0, wood - _reserved_wood)


func reserve_resources(gold_amount: int, wood_amount: int) -> void:
	if gold_amount > 0:
		_reserved_gold += gold_amount
	if wood_amount > 0:
		_reserved_wood += wood_amount


func release_reservation(gold_amount: int, wood_amount: int) -> void:
	if gold_amount > 0:
		_reserved_gold = maxi(0, _reserved_gold - gold_amount)
	if wood_amount > 0:
		_reserved_wood = maxi(0, _reserved_wood - wood_amount)


func clear_reservations() -> void:
	_reserved_gold = 0
	_reserved_wood = 0


func can_afford(gold_cost: int, wood_cost: int, respect_reservations: bool = true) -> bool:
	if respect_reservations:
		return get_spendable_gold() >= gold_cost and get_spendable_wood() >= wood_cost
	return gold >= gold_cost and wood >= wood_cost


func has_food_supply(additional: int) -> bool:
	return food_current + additional <= food_max


func can_afford_training(gold_cost: int, food_cost: int) -> bool:
	return get_spendable_gold() >= gold_cost and has_food_supply(food_cost)


func try_spend(gold_cost: int, wood_cost: int, respect_reservations: bool = true) -> bool:
	if not can_afford(gold_cost, wood_cost, respect_reservations):
		return false

	gold -= gold_cost
	wood -= wood_cost
	release_reservation(gold_cost, wood_cost)
	resources_changed.emit()
	_log_totals_if_debug()
	return true


func try_pay_training(gold_cost: int, food_cost: int) -> bool:
	if not can_afford_training(gold_cost, food_cost):
		return false

	gold -= gold_cost
	food_current += food_cost
	resources_changed.emit()
	_log_totals_if_debug()
	return true


func release_food_used(amount: int) -> void:
	if amount <= 0:
		return

	food_current = maxi(0, food_current - amount)
	resources_changed.emit()
	_log_totals_if_debug()


func release_unit_population(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if unit is Worker:
		return

	if not unit.is_in_group(&"enemies"):
		return

	release_food_used(_get_unit_food_supply(unit))


func is_stockpile_available() -> bool:
	return is_inside_tree()


func _initialize_population_from_scene() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var supply_used: int = 0
	for node: Node in tree.get_nodes_in_group(&"enemy_workers"):
		if node is Worker and is_instance_valid(node):
			supply_used += 1

	for node: Node in tree.get_nodes_in_group(&"enemies"):
		if not is_instance_valid(node):
			continue
		if node is Worker:
			continue
		if node is Spearman or node is Swordsman or node is Archer or node is HeavyCavalry or node is LightCavalry or node is CavalryArcher or node is Cannon or node is Hero:
			if node is Hero and not (node as Node).is_in_group(&"enemies"):
				continue
			supply_used += _get_unit_food_supply(node)

	food_current = supply_used
	_log_totals_if_debug()


func _get_unit_food_supply(node: Node) -> int:
	if node is Hero:
		return 2
	return 1


func _log_totals_if_debug() -> void:
	if not OS.is_debug_build():
		return

	print(
		"Enemy stockpile: gold=%d wood=%d food=%d/%d"
		% [gold, wood, food_current, food_max]
	)
