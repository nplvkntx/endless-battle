extends Node

## Internal enemy gold/wood stockpile from worker gathering. Not shown on player HUD.

signal resources_changed()

var gold: int = 0
var wood: int = 0


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


func is_stockpile_available() -> bool:
	return is_inside_tree()


func _log_totals_if_debug() -> void:
	if not OS.is_debug_build():
		return

	print("Enemy stockpile: gold=%d wood=%d" % [gold, wood])
