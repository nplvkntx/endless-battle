class_name ArtilleryShell
extends Node3D

## Slow visible artillery projectile that splashes on impact.

const SPEED := 14.0
const HIT_DISTANCE := 0.6
const MAX_LIFETIME := 8.0

var _aim_position: Vector3 = Vector3.ZERO
var _attacker: Node = null
var _damage: float = 0.0
var _splash_radius: float = 0.0
var _splash_min_damage_ratio: float = 0.5
var _direction: Vector3 = Vector3.ZERO
var _max_travel: float = 0.0
var _traveled: float = 0.0
var _lifetime: float = 0.0


func launch(
	target: Node3D,
	damage: float,
	splash_radius: float,
	spawn_position: Vector3,
	attacker: Node = null,
	splash_min_damage_ratio: float = 0.5
) -> void:
	_attacker = NodeSafety.safe_node(attacker) as Node
	_damage = damage
	_splash_radius = splash_radius
	_splash_min_damage_ratio = splash_min_damage_ratio
	global_position = spawn_position

	var safe_target: Node3D = NodeSafety.safe_node(target) as Node3D
	if safe_target == null:
		queue_free()
		return

	_aim_position = safe_target.global_position

	var to_target: Vector3 = _aim_position - spawn_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		_apply_impact()
		queue_free()
		return

	_direction = to_target.normalized()
	_max_travel = to_target.length() + HIT_DISTANCE
	look_at(global_position + _direction, Vector3.UP)


func _enter_tree() -> void:
	PerfCounters.register_projectile()


func _exit_tree() -> void:
	PerfCounters.unregister_projectile()


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		_apply_impact()
		queue_free()
		return

	var step: float = SPEED * delta
	global_position += _direction * step
	_traveled += step

	if _is_close_to_impact():
		_apply_impact()
		queue_free()
		return

	if _traveled >= _max_travel:
		_apply_impact()
		queue_free()


func _is_close_to_impact() -> bool:
	var offset: Vector3 = global_position - _aim_position
	offset.y = 0.0
	return offset.length() <= HIT_DISTANCE


func _apply_impact() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var safe_attacker: Node = CombatTargetValidation.sanitize_damage_attacker(_attacker)
	SplashDamage.apply_radial_damage(
		tree,
		global_position,
		safe_attacker,
		_damage,
		_splash_radius,
		_splash_min_damage_ratio
	)
	MeleeHitSound.play_at(self, global_position)
