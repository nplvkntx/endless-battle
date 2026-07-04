class_name HealthComponent
extends Node

## Reusable health storage and damage handling for units and buildings.

signal health_changed(current_health: int, max_health: int)
signal health_depleted

const HERO_PASSIVE_REGEN_PER_SECOND := 0.5
const ARMY_PASSIVE_REGEN_PER_SECOND := 0.25

@export var max_health: int = 100
## Set to -1 to auto-detect from the owning unit type. Zero disables passive regen.
@export var passive_regen_per_second: float = -1.0

var current_health: int = 0

var _passive_regen_accumulator: float = 0.0


func _ready() -> void:
	current_health = max_health
	_configure_passive_regen()
	set_physics_process(passive_regen_per_second > 0.0)


func _physics_process(delta: float) -> void:
	_tick_passive_regen(delta)


func take_damage(amount: int) -> void:
	if current_health <= 0:
		return

	current_health = maxi(0, current_health - amount)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		health_depleted.emit()


func heal(amount: int) -> void:
	if amount <= 0 or current_health <= 0:
		return

	var new_health: int = mini(max_health, current_health + amount)
	if new_health == current_health:
		return

	current_health = new_health
	health_changed.emit(current_health, max_health)


func _configure_passive_regen() -> void:
	if passive_regen_per_second >= 0.0:
		return

	var owner: Node = get_parent()
	if not _should_passive_regen(owner):
		passive_regen_per_second = 0.0
		return

	if owner is Hero:
		passive_regen_per_second = HERO_PASSIVE_REGEN_PER_SECOND
	else:
		passive_regen_per_second = ARMY_PASSIVE_REGEN_PER_SECOND


func _should_passive_regen(owner: Node) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false

	if not owner is Unit:
		return false

	if CombatTargetValidation.is_neutral_creep(owner):
		return false

	return true


func _tick_passive_regen(delta: float) -> void:
	if current_health <= 0:
		_passive_regen_accumulator = 0.0
		return

	if current_health >= max_health:
		_passive_regen_accumulator = 0.0
		return

	if passive_regen_per_second <= 0.0:
		return

	_passive_regen_accumulator += passive_regen_per_second * delta
	if _passive_regen_accumulator < 1.0:
		return

	var heal_amount: int = int(_passive_regen_accumulator)
	_passive_regen_accumulator -= float(heal_amount)
	heal(heal_amount)
