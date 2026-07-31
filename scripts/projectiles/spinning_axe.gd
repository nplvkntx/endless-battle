class_name SpinningAxe
extends Node3D

## Homing-ish thrown axe fired by Shadow Assassin's Axe Mark (Q).
## On hit applies damage and invokes an optional callback (used to apply the Marked buff).

const HIT_DISTANCE := 0.5
const MAX_LIFETIME := 4.0
const SPIN_SPEED := 18.0
const HOMING_TURN_RATE := 6.0
const OVERSHOOT_TRAVEL_MULT := 1.5

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _target: Node3D = null
var _attacker: Node = null
var _damage: float = 0.0
var _speed: float = ShadowAssassinStats.AXE_MARK_PROJECTILE_SPEED
var _direction: Vector3 = Vector3.ZERO
var _max_travel: float = 0.0
var _traveled: float = 0.0
var _lifetime: float = 0.0
var _impact_played: bool = false
var _on_hit_callback: Callable = Callable()


func launch(
	target: Node3D,
	damage: float,
	spawn_position: Vector3,
	attacker: Node = null,
	on_hit_callback: Callable = Callable()
) -> void:
	_target = NodeSafety.safe_node(target) as Node3D
	_attacker = NodeSafety.safe_node(attacker) as Node
	_damage = damage
	_on_hit_callback = on_hit_callback
	global_position = spawn_position
	PerfCounters.register_projectile()
	tree_exiting.connect(_on_axe_tree_exiting, CONNECT_ONE_SHOT)

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


func _on_axe_tree_exiting() -> void:
	PerfCounters.unregister_projectile()


func _physics_process(delta: float) -> void:
	_lifetime += delta
	_spin_visual(delta)

	if _lifetime >= MAX_LIFETIME:
		_play_ground_miss()
		queue_free()
		return

	if not _is_target_alive():
		_play_ground_miss()
		queue_free()
		return

	_update_homing_direction(delta)

	var step: float = _speed * delta
	global_position += _direction * step
	_traveled += step

	if _is_close_to_target():
		_apply_hit()
		queue_free()
		return

	if _traveled >= _max_travel * OVERSHOOT_TRAVEL_MULT:
		_play_ground_miss()
		queue_free()


func _spin_visual(delta: float) -> void:
	if _mesh == null:
		return
	_mesh.rotate_x(SPIN_SPEED * delta)


func _update_homing_direction(delta: float) -> void:
	if not _is_target_alive():
		return

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return

	var desired: Vector3 = to_target.normalized()
	_direction = _direction.lerp(desired, clampf(delta * HOMING_TURN_RATE, 0.0, 1.0))
	if _direction.length_squared() > 0.0001:
		_direction = _direction.normalized()
		look_at(global_position + _direction, Vector3.UP)


func _is_target_alive() -> bool:
	if not NodeSafety.is_alive_node(_target):
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
	if not DamageService.apply_damage(_target, _damage, safe_attacker):
		return

	MeleeHitSound.play_at(self, _target.global_position)
	if not _impact_played:
		_impact_played = true
		ImpactEffects.play_unit_impact(_target.global_position)

	if _on_hit_callback.is_valid():
		_on_hit_callback.call(_target)


func _play_ground_miss() -> void:
	if _impact_played:
		return
	_impact_played = true
	ImpactEffects.play_ground_impact(global_position)
