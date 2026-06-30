class_name Swordsman
extends Unit

## Placeholder swordsman unit used for early 3D scene testing.

@export var attack_damage: int = 10
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.0

var _attack_target: EnemyDummy = null
var _attack_cooldown_timer: float = 0.0


func command_attack(target: EnemyDummy) -> void:
	_attack_target = target
	_attack_cooldown_timer = 0.0


func cancel_attack() -> void:
	_attack_target = null


func _physics_process(delta: float) -> void:
	if _attack_target != null:
		if not is_instance_valid(_attack_target):
			_attack_target = null
		else:
			_process_attack(delta)
			return

	super._physics_process(delta)


func _process_attack(delta: float) -> void:
	var distance: float = _horizontal_distance_to(_attack_target)

	if distance > attack_range:
		set_movement_target(_compute_attack_approach_position(_attack_target))
		super._physics_process(delta)
		return

	has_move_target = false
	velocity = Vector3.ZERO

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	_attack_target.take_damage(float(attack_damage))
	print(
		"Swordsman dealt %d damage. Target remaining health: %d"
		% [attack_damage, _attack_target.get_current_health()]
	)
	_attack_cooldown_timer = attack_cooldown


func _horizontal_distance_to(target: Unit) -> float:
	var offset: Vector3 = global_position - target.global_position
	offset.y = 0.0
	return offset.length()


func _compute_attack_approach_position(target: Unit) -> Vector3:
	var to_attacker: Vector3 = global_position - target.global_position
	to_attacker.y = 0.0

	if to_attacker.length_squared() < 0.001:
		to_attacker = Vector3.FORWARD

	var approach_position: Vector3 = (
		target.global_position + to_attacker.normalized() * attack_range
	)
	approach_position.y = global_position.y
	return approach_position
