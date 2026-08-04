class_name RangerBasicArrow
extends Node3D

## Straight-line basic-attack arrow for the Ranger. Marks hits as basic attacks
## so Hunter's Precision and other on-hit systems receive the correct notify.

const HIT_DISTANCE := 0.45
const MAX_LIFETIME := 5.0

var _target: Variant = null
var _attacker: Variant = null
var _target_tree_exiting_handler: Callable = Callable()
var _damage: float = 0.0
var _speed: float = RangerStats.BASIC_ARROW_SPEED
var _direction: Vector3 = Vector3.ZERO
var _max_travel: float = 0.0
var _traveled: float = 0.0
var _lifetime: float = 0.0
var _trail: GPUParticles3D = null
var _impact_played: bool = false
var _empowered: bool = false


func launch(
	target: Node3D,
	damage: float,
	spawn_position: Vector3,
	attacker: Node = null,
	empowered: bool = false
) -> void:
	_clear_target_lifetime_watch()
	_target = NodeSafety.safe_node(target)
	_attacker = NodeSafety.safe_node(attacker)
	_damage = damage
	_empowered = empowered
	global_position = spawn_position
	PerfCounters.register_projectile()
	tree_exiting.connect(_on_arrow_tree_exiting, CONNECT_ONE_SHOT)

	if not _is_target_alive():
		queue_free()
		return

	_watch_target_lifetime(_target as Node3D)
	if _empowered:
		_apply_empowered_visual()

	var to_target: Vector3 = (_target as Node3D).global_position - spawn_position
	to_target.y = 0.0
	# Point-blank / overlapping targets are valid — resolve the hit immediately.
	if to_target.length_squared() < 0.001:
		_apply_hit()
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

	var step: float = _speed * delta
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
	var damage_amount: float = _damage
	var options := {DamageService.OPT_IS_BASIC_ATTACK: true}

	if safe_attacker is MeleeHero:
		var hero: MeleeHero = safe_attacker as MeleeHero
		damage_amount = hero.get_basic_attack_damage_amount(hit_target)
		options = hero.build_basic_attack_damage_options(hit_target)

	if not DamageService.apply_damage(
		hit_target,
		damage_amount,
		safe_attacker,
		options
	):
		return

	MeleeHitSound.play_at(self, hit_target.global_position)
	if not _impact_played:
		_impact_played = true
		var impact_scale: float = 1.45 if _empowered else 1.0
		ImpactEffects.play_unit_impact(hit_target.global_position, impact_scale)

	if NodeSafety.is_alive_node(safe_attacker) and safe_attacker is MeleeHero:
		(safe_attacker as MeleeHero).apply_item_cleave_after_hit(hit_target)

	if NodeSafety.is_alive_node(safe_attacker) and safe_attacker.has_method(&"_on_basic_attack_landed"):
		safe_attacker.call(&"_on_basic_attack_landed", hit_target)


func _apply_empowered_visual() -> void:
	scale = Vector3(1.45, 1.45, 1.45)
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var material := mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		material = mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if material == null:
		return
	var empowered_material: StandardMaterial3D = material.duplicate() as StandardMaterial3D
	empowered_material.emission_enabled = true
	empowered_material.emission = Color(1.0, 0.72, 0.2, 1.0)
	empowered_material.emission_energy_multiplier = 2.4
	empowered_material.albedo_color = Color(1.0, 0.85, 0.35, 1.0)
	mesh.set_surface_override_material(0, empowered_material)


func _play_ground_miss() -> void:
	if _impact_played:
		return
	_impact_played = true
	ImpactEffects.play_ground_impact(global_position)
