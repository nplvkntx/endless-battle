class_name Hero
extends Unit

## Base class for hero units. Extends Unit with XP, leveling, abilities, inventory, and respawn.
## Hero-specific values must come from an external Resource — never hardcoded in this script.

signal xp_changed(current_xp: float, xp_to_next_level: float)
signal level_changed(new_level: int)
signal ability_points_changed(new_amount: int)
signal ability_ready(ability_id: StringName)
signal inventory_changed()
signal respawn_requested(hero: Hero)

const MAX_LEVEL: int = 10
const XP_PER_LEVEL_MULTIPLIER: int = 100

@export var hero_data: Resource

var level: int = 1
var ability_points: int = 0
var _current_xp: float = 0.0


func _ready() -> void:
	super._ready()
	if level < 1:
		level = 1
	_apply_hero_data()
	_emit_xp_state()


func get_current_xp() -> float:
	return _current_xp


func get_xp_required_for_next_level() -> float:
	if level >= MAX_LEVEL:
		return 0.0

	return float(XP_PER_LEVEL_MULTIPLIER * level)


func add_xp(amount: float) -> void:
	if amount <= 0.0 or level >= MAX_LEVEL:
		return

	_current_xp += amount
	while level < MAX_LEVEL and _current_xp >= get_xp_required_for_next_level():
		_current_xp -= get_xp_required_for_next_level()
		level += 1
		_on_level_up()

	_emit_xp_state()


func _on_level_up() -> void:
	ability_points += 1
	ability_points_changed.emit(ability_points)
	level_changed.emit(level)
	_restore_health_on_level_up()
	_restore_mana_on_level_up()
	_show_level_up_feedback()
	print("Level Up! Hero reached level %d" % level)
	print("Ability points: %d" % ability_points)


func _restore_health_on_level_up() -> void:
	var health_component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		return

	health_component.current_health = health_component.max_health
	health_component.health_changed.emit(health_component.current_health, health_component.max_health)


func _restore_mana_on_level_up() -> void:
	pass


func _show_level_up_feedback() -> void:
	FloatingDamageNumber.spawn_message(
		self, "Level Up!", Color(0.45, 0.85, 1.0, 1.0), true
	)


func _emit_xp_state() -> void:
	xp_changed.emit(_current_xp, get_xp_required_for_next_level())


## Loads hero-specific runtime state from hero_data when the data pipeline is available.
func _apply_hero_data() -> void:
	# TODO: Read hero stats and ability slots from hero_data Resource.
	pass
