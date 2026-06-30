class_name Archer
extends Unit

## Ranged archer unit that stops at attack range and applies damage directly.

@export var attack_damage: int = 7
@export var attack_range: float = 8.0
@export var attack_cooldown: float = 1.2

const HEALTH_BAR_WIDTH := 1.2
const HEALTH_BAR_HUE_GREEN := 0.333333

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill

var _health_bar_fill_material: StandardMaterial3D
var _attack_target: EnemyDummy = null
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false


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


func set_movement_target(target: Vector3) -> void:
	cancel_attack()
	super.set_movement_target(target)


func _physics_process(delta: float) -> void:
	if _health_component.current_health <= 0:
		return

	if _attack_target == null and not has_move_target:
		_try_auto_attack()

	if _attack_target != null:
		if not is_instance_valid(_attack_target):
			cancel_attack()
		else:
			_process_attack(delta)
			return

	super._physics_process(delta)


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
		if not is_instance_valid(enemy):
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

	if not is_instance_valid(_attack_target):
		cancel_attack()
		return

	_attack_target.take_damage(float(attack_damage), self)
	MeleeHitSound.play_at(self, _attack_target.global_position)
	print(
		"Archer dealt %d damage. Target remaining health: %d"
		% [attack_damage, _attack_target.get_current_health()]
	)
	_attack_cooldown_timer = attack_cooldown


func take_damage(amount: float) -> void:
	if _health_component.current_health <= 0:
		return

	_health_component.take_damage(int(amount))


func get_current_health() -> int:
	return _health_component.current_health


func _on_health_depleted() -> void:
	_health_bar.visible = false
	cancel_attack()
	has_move_target = false
	velocity = Vector3.ZERO
	die()
	print("Archer died")
	queue_free()


func _begin_chase() -> void:
	if _attack_target == null or _has_chase_target:
		return

	super.set_movement_target(_compute_attack_approach_position(_attack_target))
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
