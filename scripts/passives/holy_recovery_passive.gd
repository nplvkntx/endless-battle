class_name HolyRecoveryPassive
extends HeroPassive

## Out-of-combat HP regeneration for the Human Paladin.

const EFFECT_SCENE: PackedScene = preload("res://scenes/effects/holy_recovery_effect.tscn")

var _is_regenerating: bool = false
var _regen_accumulator: float = 0.0
var _effect: Node3D = null


func get_status_text() -> String:
	if _is_regenerating:
		return "Active"
	return "Passive"


func is_effect_active() -> bool:
	return _is_regenerating


func tick(delta: float) -> void:
	if not is_enabled():
		return

	if not _is_regenerating:
		_regen_accumulator = 0.0
		return

	var health: HealthComponent = _get_health()
	if health == null or health.current_health <= 0:
		_stop_regeneration()
		return

	if health.current_health >= health.max_health:
		_regen_accumulator = 0.0
		return

	var regen_per_second: float = (
		float(health.max_health) * HeroPassiveStats.HOLY_RECOVERY_REGEN_PERCENT_PER_SECOND
	)
	_regen_accumulator += regen_per_second * delta
	if _regen_accumulator < 1.0:
		return

	var heal_amount: int = int(_regen_accumulator)
	_regen_accumulator -= float(heal_amount)
	health.heal(heal_amount)


func on_out_of_combat_started() -> void:
	_start_regeneration()


func on_out_of_combat_ended() -> void:
	_stop_regeneration()


func _on_disabled() -> void:
	_stop_regeneration()


func _format_tooltip_extra() -> String:
	return "Out of combat: %.0fs\nRegen: %.1f%% max HP / sec" % [
		HeroPassiveStats.HOLY_RECOVERY_OUT_OF_COMBAT_SECONDS,
		HeroPassiveStats.HOLY_RECOVERY_REGEN_PERCENT_PER_SECOND * 100.0,
	]


func _start_regeneration() -> void:
	if _is_regenerating:
		return

	_is_regenerating = true
	_regen_accumulator = 0.0
	_spawn_effect()
	_notify_state_changed()


func _stop_regeneration() -> void:
	if not _is_regenerating and _effect == null:
		_regen_accumulator = 0.0
		return

	_is_regenerating = false
	_regen_accumulator = 0.0
	_clear_effect()
	_notify_state_changed()


func _spawn_effect() -> void:
	_clear_effect()
	if host == null or not is_instance_valid(host):
		return

	_effect = EFFECT_SCENE.instantiate() as Node3D
	if _effect == null:
		return

	host.add_child(_effect)
	_effect.position = Vector3(0.0, 0.05, 0.0)


func _clear_effect() -> void:
	if _effect != null and is_instance_valid(_effect):
		_effect.queue_free()
	_effect = null


func _get_health() -> HealthComponent:
	if host == null or not is_instance_valid(host):
		return null
	return host.get_node_or_null("HealthComponent") as HealthComponent
