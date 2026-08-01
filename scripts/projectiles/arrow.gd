class_name Arrow
extends Node3D

## Simple straight-line arrow fired by Archers at a fixed aim point.

const SPEED := 20.0
const HIT_DISTANCE := 0.45
const MAX_LIFETIME := 5.0

var _target: Variant = null
var _attacker: Variant = null
var _target_tree_exiting_handler: Callable = Callable()
var _damage: float = 0.0
var _direction: Vector3 = Vector3.ZERO
var _max_travel: float = 0.0
var _traveled: float = 0.0
var _lifetime: float = 0.0
var _trail: GPUParticles3D = null
var _impact_played: bool = false


func launch(target: Node3D, damage: float, spawn_position: Vector3, attacker: Node = null) -> void:
	_clear_target_lifetime_watch()
	_target = NodeSafety.safe_node(target)
	_attacker = NodeSafety.safe_node(attacker)
	_damage = damage
	global_position = spawn_position
	PerfCounters.register_projectile()
	tree_exiting.connect(_on_arrow_tree_exiting, CONNECT_ONE_SHOT)

	if not _is_target_alive():
		queue_free()
		return

	_watch_target_lifetime(_target as Node3D)

	var to_target: Vector3 = (_target as Node3D).global_position - spawn_position
	to_target.y = 0.0

	if to_target.length_squared() < 0.001:
		queue_free()
		return

	_direction = to_target.normalized()
	_max_travel = to_target.length() + HIT_DISTANCE
	look_at(global_position + _direction, Vector3.UP)
	_trail = ImpactEffects.attach_arrow_trail(self)


func _on_arrow_tree_exiting() -> void:
	_clear_target_lifetime_watch()
	_release_trail()
	PerfCounters.unregister_projectile()


func _watch_target_lifetime(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_target_tree_exiting_handler = _on_target_tree_exiting.bind(target.get_instance_id())
	if not target.tree_exiting.is_connected(_target_tree_exiting_handler):
		target.tree_exiting.connect(_target_tree_exiting_handler, CONNECT_ONE_SHOT)


func _clear_target_lifetime_watch() -> void:
	if not _target_tree_exiting_handler.is_valid():
		_target_tree_exiting_handler = Callable()
		return

	var target_ref: Variant = _target
	if (
		NodeSafety.is_alive_node(target_ref)
		and target_ref is Node
		and (target_ref as Node).tree_exiting.is_connected(_target_tree_exiting_handler)
	):
		(target_ref as Node).tree_exiting.disconnect(_target_tree_exiting_handler)

	_target_tree_exiting_handler = Callable()


func _on_target_tree_exiting(expected_instance_id: int) -> void:
	_target_tree_exiting_handler = Callable()
	var target_ref: Variant = _target
	if NodeSafety.is_alive_node(target_ref) and int(target_ref.get_instance_id()) != expected_instance_id:
		return
	_target = null


func _release_trail() -> void:
	if _trail == null:
		return
	ImpactEffects.release_attached(_trail, ImpactFxPool.FxKind.ARROW_TRAIL)
	_trail = null


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		_play_ground_miss()
		queue_free()
		return

	if not _is_target_alive():
		_play_ground_miss()
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
		_play_ground_miss()
		queue_free()


func _is_target_alive() -> bool:
	if not NodeSafety.is_alive_node(_target):
		_clear_target_lifetime_watch()
		_target = null
		return false

	return CombatTargetValidation.is_valid_combat_target(_target)


func _is_close_to_target() -> bool:
	if not _is_target_alive():
		return false

	var offset: Vector3 = global_position - (_target as Node3D).global_position
	offset.y = 0.0
	return offset.length() <= HIT_DISTANCE


func _apply_hit() -> void:
	if not _is_target_alive():
		return

	var hit_target: Node3D = _target as Node3D
	var safe_attacker: Node = CombatTargetValidation.sanitize_damage_attacker(_attacker)
	if not DamageService.apply_damage(hit_target, _damage, safe_attacker):
		return

	MeleeHitSound.play_at(self, hit_target.global_position)
	if not _impact_played:
		_impact_played = true
		ImpactEffects.play_unit_impact(hit_target.global_position)


func _play_ground_miss() -> void:
	if _impact_played:
		return
	_impact_played = true
	ImpactEffects.play_ground_impact(global_position)
