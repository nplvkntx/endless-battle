class_name Arrow
extends Node3D

## Simple straight-line arrow fired by Archers at a fixed aim point.

const SPEED := 20.0
const HIT_DISTANCE := 0.45
const MAX_LIFETIME := 5.0

var _target: Node3D = null
var _attacker: Node = null
var _damage: float = 0.0
var _direction: Vector3 = Vector3.ZERO
var _max_travel: float = 0.0
var _traveled: float = 0.0
var _lifetime: float = 0.0


func launch(target: Node3D, damage: float, spawn_position: Vector3, attacker: Node = null) -> void:
	_attacker = attacker
	_target = target
	_damage = damage
	global_position = spawn_position

	if not _is_target_alive():
		queue_free()
		return

	var to_target: Vector3 = _target.global_position - spawn_position
	to_target.y = 0.0

	if to_target.length_squared() < 0.001:
		queue_free()
		return

	_direction = to_target.normalized()
	_max_travel = to_target.length() + HIT_DISTANCE
	look_at(global_position + _direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		queue_free()
		return

	if not _is_target_alive():
		queue_free()
		return

	var step: float = SPEED * delta
	global_position += _direction * step
	_traveled += step

	if _is_close_to_target():
		_apply_hit()
		queue_free()
		return

	if _traveled >= _max_travel:
		queue_free()


func _is_target_alive() -> bool:
	if _target == null or not is_instance_valid(_target):
		_target = null
		return false

	return CombatTargetValidation.is_valid_combat_target(_target)


func _is_close_to_target() -> bool:
	if not _is_target_alive():
		return false

	var offset: Vector3 = global_position - _target.global_position
	offset.y = 0.0
	return offset.length() <= HIT_DISTANCE


func _apply_hit() -> void:
	if not _is_target_alive():
		return

	var safe_attacker: Node = CombatTargetValidation.sanitize_damage_attacker(_attacker)
	if not CombatTargetValidation.apply_damage_to_target(_target, _damage, safe_attacker):
		return

	MeleeHitSound.play_at(self, _target.global_position)
