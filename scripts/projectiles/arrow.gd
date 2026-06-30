class_name Arrow
extends Node3D

## Simple straight-line arrow fired by Archers at a fixed aim point.

const SPEED := 20.0
const HIT_DISTANCE := 0.45
const MAX_LIFETIME := 5.0

var _target: EnemyDummy = null
var _attacker: Unit = null
var _damage: float = 0.0
var _direction: Vector3 = Vector3.ZERO
var _max_travel: float = 0.0
var _traveled: float = 0.0
var _lifetime: float = 0.0


func launch(attacker: Unit, target: EnemyDummy, damage: float, spawn_position: Vector3) -> void:
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
	return is_instance_valid(_target) and _target.get_current_health() > 0


func _is_close_to_target() -> bool:
	var offset: Vector3 = global_position - _target.global_position
	offset.y = 0.0
	return offset.length() <= HIT_DISTANCE


func _apply_hit() -> void:
	if not _is_target_alive():
		return

	_target.take_damage(_damage, _attacker)
	MeleeHitSound.play_at(self, _target.global_position)
	print(
		"Archer arrow dealt %d damage. Target remaining health: %d"
		% [int(_damage), _target.get_current_health()]
	)
