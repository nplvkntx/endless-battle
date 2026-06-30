class_name Swordsman
extends Unit

## Placeholder swordsman unit used for early 3D scene testing.

@export var attack_damage: int = 10
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0

var _attack_target: EnemyDummy = null
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false


func command_attack(target: EnemyDummy) -> void:
	_attack_target = target
	_attack_cooldown_timer = 0.0
	_has_chase_target = false

	if _is_in_attack_range(_attack_target):
		_stop_and_attack(0.0)
		return

	_begin_chase()


func cancel_attack() -> void:
	_attack_target = null
	_has_chase_target = false


func _physics_process(delta: float) -> void:
	if _attack_target != null:
		if not is_instance_valid(_attack_target):
			cancel_attack()
		else:
			_process_attack(delta)
			return

	super._physics_process(delta)


func _process_attack(delta: float) -> void:
	if _is_in_attack_range(_attack_target):
		_stop_and_attack(delta)
		return

	if not has_move_target:
		_has_chase_target = false
		_begin_chase()

	super._physics_process(delta)

	if _attack_target != null and _is_in_attack_range(_attack_target):
		_stop_and_attack(delta)


func _stop_and_attack(delta: float) -> void:
	has_move_target = false
	_has_chase_target = false
	velocity = Vector3.ZERO

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	if not is_instance_valid(_attack_target):
		cancel_attack()
		return

	_attack_target.take_damage(float(attack_damage))
	print(
		"Swordsman dealt %d damage. Target remaining health: %d"
		% [attack_damage, _attack_target.get_current_health()]
	)
	_attack_cooldown_timer = attack_cooldown


func _begin_chase() -> void:
	if _attack_target == null or _has_chase_target:
		return

	set_movement_target(_compute_attack_approach_position(_attack_target))
	_has_chase_target = true


func _is_in_attack_range(target: Unit) -> bool:
	return _horizontal_distance_to(target) <= attack_range


func _horizontal_distance_to(target: Unit) -> float:
	var offset: Vector3 = global_position - target.global_position
	offset.y = 0.0
	return offset.length()


func _compute_attack_approach_position(target: Unit) -> Vector3:
	var to_attacker: Vector3 = global_position - target.global_position
	to_attacker.y = 0.0

	if to_attacker.length_squared() < 0.001:
		to_attacker = Vector3.FORWARD

	var standoff_distance: float = maxf(attack_range - stopping_distance, stopping_distance)
	var approach_position: Vector3 = (
		target.global_position + to_attacker.normalized() * standoff_distance
	)
	approach_position.y = global_position.y
	return approach_position
