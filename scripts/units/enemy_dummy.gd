class_name EnemyDummy
extends Unit

## Stationary enemy placeholder for future combat features.

@export var attack_damage: int = 8
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.2

const HEALTH_BAR_WIDTH := 1.2
const HEALTH_BAR_HUE_GREEN := 0.333333
const HIT_FLASH_DURATION := 0.12
const ATTACK_LUNGE_DISTANCE := 0.35
const ATTACK_LUNGE_DURATION := 0.12

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill
@onready var _body_mesh: MeshInstance3D = $MeshInstance3D

var _health_bar_fill_material: StandardMaterial3D
var _body_material: StandardMaterial3D
var _body_base_color: Color
var _body_mesh_rest_position: Vector3
var _hit_flash_tween: Tween
var _attack_lunge_tween: Tween
var _attack_target: Unit = null
var _attack_cooldown_timer: float = 0.0


func _ready() -> void:
	super._ready()
	var fill_material := _health_bar_fill.get_surface_override_material(0) as StandardMaterial3D
	_health_bar_fill_material = fill_material.duplicate() as StandardMaterial3D
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	var body_material := _body_mesh.get_surface_override_material(0) as StandardMaterial3D
	_body_material = body_material.duplicate() as StandardMaterial3D
	_body_mesh.set_surface_override_material(0, _body_material)
	_body_base_color = _body_material.albedo_color
	_body_mesh_rest_position = _body_mesh.position
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)


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


func _on_health_depleted() -> void:
	_health_bar.visible = false
	print("EnemyDummy died")
	queue_free()


func take_damage(amount: float, attacker = null) -> void:
	if _health_component.current_health <= 0:
		return

	var damage_amount := int(amount)
	_health_component.take_damage(damage_amount)
	FloatingDamageNumber.spawn(self, damage_amount)
	_play_hit_feedback()

	var valid_attacker: Unit = _resolve_combat_attacker(attacker)
	if valid_attacker != null:
		_set_attack_target(valid_attacker)


func _play_hit_feedback() -> void:
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()

	_body_material.emission_enabled = true
	_body_material.emission = Color(1.0, 0.35, 0.35, 1.0)
	_body_material.albedo_color = Color(1.0, 0.75, 0.75, 1.0)

	_hit_flash_tween = create_tween()
	_hit_flash_tween.set_parallel(true)
	_hit_flash_tween.tween_property(
		_body_material,
		"albedo_color",
		_body_base_color,
		HIT_FLASH_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_flash_tween.tween_property(
		_body_material,
		"emission",
		Color.BLACK,
		HIT_FLASH_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_flash_tween.finished.connect(_on_hit_flash_finished, CONNECT_ONE_SHOT)


func _on_hit_flash_finished() -> void:
	_body_material.emission_enabled = false


func get_current_health() -> int:
	return _health_component.current_health


func set_movement_target(_target: Vector3) -> void:
	pass


func _physics_process(delta: float) -> void:
	velocity = Vector3.ZERO

	if _health_component.current_health <= 0:
		return

	_process_counter_attack(delta)


func _set_attack_target(target: Unit) -> void:
	if not _is_valid_attack_target(target):
		return

	_attack_target = target


func _process_counter_attack(delta: float) -> void:
	_clear_invalid_attack_target()
	if _attack_target == null:
		return

	if not _is_in_attack_range(_attack_target):
		return

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	if not _is_valid_attack_target(_attack_target):
		_clear_invalid_attack_target()
		return

	_attack_target.take_damage(float(attack_damage))
	MeleeHitSound.play_at(self, _attack_target.global_position)
	_play_attack_animation()
	print(
		"EnemyDummy dealt %d damage. Target remaining health: %d"
		% [attack_damage, _attack_target.get_current_health()]
	)
	_attack_cooldown_timer = attack_cooldown
	_clear_invalid_attack_target()


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


func _clear_invalid_attack_target() -> void:
	if _attack_target == null:
		return

	if _is_valid_attack_target(_attack_target):
		return

	_attack_target = null


func _resolve_combat_attacker(attacker) -> Unit:
	if not CombatTargetValidation.is_valid_combat_target(attacker):
		return null

	if not attacker is Unit:
		return null

	var unit: Unit = attacker as Unit
	if unit is EnemyDummy:
		return null

	return unit


func _is_valid_attack_target(target: Unit) -> bool:
	if not CombatTargetValidation.is_valid_combat_target(target):
		return false

	return not target is EnemyDummy


func _is_in_attack_range(target: Unit) -> bool:
	if not CombatTargetValidation.is_valid_combat_target(target):
		return false

	var offset: Vector3 = global_position - target.global_position
	offset.y = 0.0
	return offset.length() <= attack_range
