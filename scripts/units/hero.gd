class_name Hero
extends Unit

## Player hero unit — melee combat, stronger than a Swordsman.

@export var attack_damage: int = 18
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 0.85

const HEALTH_BAR_WIDTH := 1.4
const HEALTH_BAR_HUE_GREEN := 0.333333
const ATTACK_LUNGE_DISTANCE := 0.4
const ATTACK_LUNGE_DURATION := 0.12
const GROUND_SLAM_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/ground_slam_effect.tscn")
const GROUND_SLAM_COOLDOWN := 9.0
const GROUND_SLAM_RADIUS := 3.5
const GROUND_SLAM_DAMAGE := 35
const GROUND_SLAM_BODY_PULSE_DURATION := 0.18

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill
@onready var _body_mesh: MeshInstance3D = $MeshInstance3D

var _health_bar_fill_material: StandardMaterial3D
var _body_mesh_rest_position: Vector3
var _attack_lunge_tween: Tween
var _attack_target: EnemyDummy = null
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false
var _attack_move_destination: Vector3 = Vector3.ZERO
var _has_attack_move_destination: bool = false
var _ground_slam_cooldown_timer: float = 0.0
var _ground_slam_pulse_tween: Tween


func _ready() -> void:
	super._ready()
	var fill_material := _health_bar_fill.get_surface_override_material(0) as StandardMaterial3D
	_health_bar_fill_material = fill_material.duplicate() as StandardMaterial3D
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)
	_body_mesh_rest_position = _body_mesh.position
	died.connect(_notify_hero_altars_of_death)


func _notify_hero_altars_of_death(_unit: Unit) -> void:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is HeroAltar:
			(node as HeroAltar).hero_altar_state_changed.emit()


func _on_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(current_health, max_health)


func _update_health_bar(current_health: int, max_health: int) -> void:
	if max_health <= 0:
		return

	var ratio: float = float(current_health) / float(max_health)
	_health_bar_fill.scale.x = ratio
	_health_bar_fill.position.x = HEALTH_BAR_WIDTH * (ratio - 1.0) * 0.5
	_health_bar_fill_material.albedo_color = _get_health_bar_color(ratio)


func _get_health_bar_color(ratio: float) -> Color:
	return Color.from_hsv(ratio * HEALTH_BAR_HUE_GREEN, 0.85, 0.9)


func command_attack(target: EnemyDummy) -> void:
	_attack_target = target
	_has_chase_target = false

	if not _is_in_attack_range(_attack_target):
		_begin_chase()


func command_attack_move(destination: Vector3) -> void:
	_attack_move_destination = destination
	_has_attack_move_destination = true
	cancel_attack()
	_set_move_destination(destination)


func cancel_attack_move() -> void:
	_has_attack_move_destination = false


func cancel_attack() -> void:
	_attack_target = null
	_has_chase_target = false


func set_movement_target(target: Vector3) -> void:
	cancel_attack_move()
	cancel_attack()
	_set_move_destination(target)


func _set_move_destination(target: Vector3) -> void:
	super.set_movement_target(target)


func get_ground_slam_cooldown_remaining() -> float:
	return maxf(_ground_slam_cooldown_timer, 0.0)


func can_use_ground_slam() -> bool:
	return _health_component.current_health > 0 and _ground_slam_cooldown_timer <= 0.0


func try_ground_slam() -> bool:
	if not can_use_ground_slam():
		if _ground_slam_cooldown_timer > 0.0:
			ResourceManager.show_feedback(
				"Ground Slam on cooldown (%.0fs)" % ceilf(_ground_slam_cooldown_timer)
			)
		return false

	_execute_ground_slam()
	return true


func _execute_ground_slam() -> void:
	_ground_slam_cooldown_timer = GROUND_SLAM_COOLDOWN
	_damage_enemies_in_ground_slam_radius()
	_spawn_ground_slam_effect()
	_play_ground_slam_pulse()
	MeleeHitSound.play_at(self, global_position)


func _damage_enemies_in_ground_slam_radius() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyDummy:
			continue

		var enemy: EnemyDummy = node as EnemyDummy
		if not CombatTargetValidation.is_valid_combat_target(enemy):
			continue

		if _horizontal_distance_to(enemy) > GROUND_SLAM_RADIUS:
			continue

		enemy.take_damage(float(GROUND_SLAM_DAMAGE), self)


func _spawn_ground_slam_effect() -> void:
	var effect: GroundSlamEffect = GROUND_SLAM_EFFECT_SCENE.instantiate() as GroundSlamEffect
	if effect == null:
		return

	effect.radius = GROUND_SLAM_RADIUS

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		effect.queue_free()
		return

	spawn_parent.add_child(effect)
	effect.global_position = Vector3(global_position.x, 0.03, global_position.z)


func _play_ground_slam_pulse() -> void:
	if _ground_slam_pulse_tween != null and _ground_slam_pulse_tween.is_valid():
		_ground_slam_pulse_tween.kill()

	_body_mesh.scale = Vector3.ONE
	_ground_slam_pulse_tween = create_tween()
	_ground_slam_pulse_tween.tween_property(
		_body_mesh,
		"scale",
		Vector3(1.25, 0.75, 1.25),
		GROUND_SLAM_BODY_PULSE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ground_slam_pulse_tween.tween_property(
		_body_mesh,
		"scale",
		Vector3.ONE,
		GROUND_SLAM_BODY_PULSE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _tick_ground_slam_cooldown(delta: float) -> void:
	if _ground_slam_cooldown_timer <= 0.0:
		return

	_ground_slam_cooldown_timer = maxf(_ground_slam_cooldown_timer - delta, 0.0)


func _physics_process(delta: float) -> void:
	if _health_component.current_health <= 0:
		return

	_tick_ground_slam_cooldown(delta)

	if _attack_target == null and not has_move_target:
		_try_auto_attack()

	if _has_attack_move_destination and _attack_target == null:
		_try_attack_move_engagement()

	if _attack_target != null:
		if not CombatTargetValidation.is_valid_combat_target(_attack_target):
			cancel_attack()
			_resume_attack_move()
		else:
			_process_attack(delta)
			return

	super._physics_process(delta)

	if _has_attack_move_destination and _attack_target == null and not has_move_target:
		if _is_at_attack_move_destination():
			cancel_attack_move()


func _try_auto_attack() -> void:
	var closest_enemy: EnemyDummy = _find_closest_enemy_in_range()
	if closest_enemy != null:
		command_attack(closest_enemy)


func _find_closest_enemy_in_range() -> EnemyDummy:
	var closest_enemy: EnemyDummy = null
	var closest_distance: float = INF

	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyDummy:
			continue

		var enemy: EnemyDummy = node as EnemyDummy
		if not CombatTargetValidation.is_valid_combat_target(enemy):
			continue

		var distance: float = _horizontal_distance_to(enemy)
		if distance > attack_range:
			continue

		if distance < closest_distance:
			closest_distance = distance
			closest_enemy = enemy

	return closest_enemy


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

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		return

	_attack_target.take_damage(float(attack_damage), self)
	MeleeHitSound.play_at(self, _attack_target.global_position)
	_play_attack_animation()
	print(
		"Hero dealt %d damage. Target remaining health: %d"
		% [attack_damage, _attack_target.get_current_health()]
	)
	_attack_cooldown_timer = attack_cooldown


func _play_attack_animation() -> void:
	if _attack_lunge_tween != null and _attack_lunge_tween.is_valid():
		_attack_lunge_tween.kill()

	var lunge_offset := Vector3.ZERO
	if CombatTargetValidation.is_valid_combat_target(_attack_target):
		var direction := _attack_target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			lunge_offset = global_transform.basis.inverse() * (direction.normalized() * ATTACK_LUNGE_DISTANCE)

	_body_mesh.position = _body_mesh_rest_position
	_attack_lunge_tween = create_tween()
	_attack_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position + lunge_offset,
		ATTACK_LUNGE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position,
		ATTACK_LUNGE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func take_damage(amount: float) -> void:
	if _health_component.current_health <= 0:
		return

	var damage_amount := int(amount)
	_health_component.take_damage(damage_amount)
	FloatingDamageNumber.spawn(self, damage_amount)


func get_current_health() -> int:
	return _health_component.current_health


func _on_health_depleted() -> void:
	_health_bar.visible = false
	cancel_attack_move()
	cancel_attack()
	has_move_target = false
	velocity = Vector3.ZERO
	die()
	print("Hero died")
	queue_free()


func _begin_chase() -> void:
	if _attack_target == null or _has_chase_target:
		return

	_set_move_destination(_compute_attack_approach_position(_attack_target))
	_has_chase_target = true


func _try_attack_move_engagement() -> void:
	var closest_enemy: EnemyDummy = _find_closest_enemy_in_range()
	if closest_enemy != null:
		command_attack(closest_enemy)


func _resume_attack_move() -> void:
	if not _has_attack_move_destination:
		return

	if _is_at_attack_move_destination():
		cancel_attack_move()
		return

	_has_chase_target = false
	_set_move_destination(_attack_move_destination)


func _is_at_attack_move_destination() -> bool:
	var offset: Vector3 = global_position - _attack_move_destination
	offset.y = 0.0
	return offset.length() <= stopping_distance


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
