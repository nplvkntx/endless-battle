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

var _target: Variant = null
var _attacker: Variant = null
var _target_tree_exiting_handler: Callable = Callable()
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
	_clear_target_lifetime_watch()
	_target = NodeSafety.safe_node(target)
	_attacker = NodeSafety.safe_node(attacker)
	_damage = damage
	_on_hit_callback = on_hit_callback
	global_position = spawn_position
	PerfCounters.register_projectile()
	tree_exiting.connect(_on_axe_tree_exiting, CONNECT_ONE_SHOT)

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


func _on_axe_tree_exiting() -> void:
	_clear_target_lifetime_watch()
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

	var to_target: Vector3 = (_target as Node3D).global_position - global_position
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

	# queue_free keeps the instance valid until end of frame; truly freed refs must stop here.
	if hit_target == null or not is_instance_valid(hit_target):
		_target = null
		return

	MeleeHitSound.play_at(self, hit_target.global_position)
	if not _impact_played:
		_impact_played = true
		ImpactEffects.play_unit_impact(hit_target.global_position)

	if _on_hit_callback.is_valid() and is_instance_valid(hit_target):
		_on_hit_callback.call(hit_target)

	if not NodeSafety.is_alive_node(hit_target):
		_target = null


func _play_ground_miss() -> void:
	if _impact_played:
		return
	_impact_played = true
	ImpactEffects.play_ground_impact(global_position)
