class_name Archer
extends Unit

## Ranged archer unit that stops at attack range and fires arrow projectiles.

@export var attack_damage: int = 7
@export var attack_range: float = 8.0
@export var attack_cooldown: float = 1.2

const HEALTH_BAR_WIDTH := 1.2
const HEALTH_BAR_HUE_GREEN := 0.333333
const ARROW_SCENE: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
const ARROW_SPAWN_HEIGHT := 0.5

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill

var _health_bar_fill_material: StandardMaterial3D
var _attack_target: Node3D = null
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false
var _attack_move_destination: Vector3 = Vector3.ZERO
var _has_attack_move_destination: bool = false


func _ready() -> void:
	super._ready()
	var fill_material := _health_bar_fill.get_surface_override_material(0) as StandardMaterial3D
	_health_bar_fill_material = fill_material.duplicate() as StandardMaterial3D
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
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


func command_attack(target: Node3D) -> void:
	if not CombatTargetValidation.is_attack_target_for_attacker(self, target):
		return

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


func _physics_process(delta: float) -> void:
	if _health_component.current_health <= 0:
		return

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
	var closest_target: Node3D = _find_closest_attack_target_in_range()
	if closest_target != null:
		command_attack(closest_target)


func _find_closest_attack_target_in_range() -> Node3D:
	return CombatTargetValidation.find_closest_player_unit_attack_target_in_range(
		self, attack_range
	)


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
		_resume_attack_move()
		return

	_fire_arrow()
	_attack_cooldown_timer = attack_cooldown


func _fire_arrow() -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	get_tree().current_scene.add_child(arrow)
	var spawn_position: Vector3 = global_position + Vector3(0.0, ARROW_SPAWN_HEIGHT, 0.0)
	arrow.launch(_attack_target, float(attack_damage), spawn_position, self)


func take_damage(amount: float, attacker: Node = null) -> void:
	if _health_component.current_health <= 0:
		return

	CombatKillTracker.record_attacker(self, attacker)

	var damage_amount := int(amount)
	_health_component.take_damage(damage_amount)
	FloatingDamageNumber.spawn(self, damage_amount)


func get_current_health() -> int:
	return _health_component.current_health


func _on_health_depleted() -> void:
	HeroXpRewards.notify_unit_killed(self)
	_health_bar.visible = false
	cancel_attack_move()
	cancel_attack()
	has_move_target = false
	velocity = Vector3.ZERO
	die()
	print("Archer died")
	queue_free()


func _begin_chase() -> void:
	if _attack_target == null or _has_chase_target:
		return

	_set_move_destination(_compute_attack_approach_position(_attack_target))
	_has_chase_target = true


func _try_attack_move_engagement() -> void:
	var closest_target: Node3D = _find_closest_attack_target_in_range()
	if closest_target != null:
		command_attack(closest_target)


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


func _is_in_attack_range(target: Node3D) -> bool:
	return CombatTargetValidation.is_within_attack_range(self, target, attack_range)


func _compute_attack_approach_position(target: Node3D) -> Vector3:
	return CombatTargetValidation.compute_attack_approach_position(
		self, target, attack_range, stopping_distance
	)
