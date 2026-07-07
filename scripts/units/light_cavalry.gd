class_name LightCavalry
extends Unit

## Fast light mounted melee cavalry placeholder.

@export var attack_damage: int = 8
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 0.9
@export var armor: int = 0

const HEALTH_BAR_WIDTH := 1.2
const HEALTH_BAR_HUE_GREEN := 0.333333
const ATTACK_MOVE_ENGAGEMENT_RANGE := 14.0

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill

var _health_bar_fill_material: StandardMaterial3D
var _attack_target: Node3D = null
var _attack_approach_slot: int = -1
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false
var _attack_move_destination: Vector3 = Vector3.ZERO
var _has_attack_move_destination: bool = false


func _ready() -> void:
	super._ready()
	_health_bar_fill_material = HealthBarDisplay.duplicate_mesh_material(_health_bar_fill)
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)


func _exit_tree() -> void:
	cancel_attack_move()
	cancel_attack()
	EnemyUnitMission.clear_unit_mission(self)


func _on_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(current_health, max_health)


func _update_health_bar(current_health: int, max_health: int) -> void:
	HealthBarDisplay.update_world_bar(
		_health_bar,
		_health_bar_fill,
		_health_bar_fill_material,
		current_health,
		max_health,
		HEALTH_BAR_WIDTH,
		HEALTH_BAR_HUE_GREEN
	)


func get_visual_loop_state() -> UnitVisualAnimator.LoopState:
	if has_move_target or _has_chase_target:
		return UnitVisualAnimator.LoopState.MOVE

	return UnitVisualAnimator.LoopState.IDLE


func _process(delta: float) -> void:
	_sanitize_attack_target()
	super._process(delta)


func _sanitize_attack_target() -> void:
	if _attack_target == null:
		return

	if not NodeSafety.is_alive_node(_attack_target):
		cancel_attack()
		_resume_attack_move()
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		_resume_attack_move()


func _is_attack_target_valid_for_facing() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		_attack_target = null
		return false

	return CombatTargetValidation.is_valid_combat_target(_attack_target)


func get_attack_facing_direction() -> Vector3:
	if not _is_attack_target_valid_for_facing():
		return Vector3.ZERO

	var direction: Vector3 = _attack_target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return Vector3.ZERO

	return direction.normalized()


func command_attack(target: Node3D, assigned_slot: int = -1) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if not CombatTargetValidation.is_attack_target_for_attacker(self, target):
		return

	_assign_attack_approach_slot(target, assigned_slot)
	_attack_target = NodeSafety.safe_node(target) as Node3D
	if _attack_target == null:
		return
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
	if NodeSafety.is_alive_node(_attack_target):
		CombatTargetValidation.clear_attack_approach_slots(_attack_target)
	_attack_target = null
	_attack_approach_slot = -1
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

	var can_scan_targets: bool = tick_combat_target_scan_timer(delta)

	if _attack_target == null and not has_move_target:
		if can_scan_targets:
			_try_auto_attack()

	if _has_attack_move_destination and _attack_target == null:
		if can_scan_targets:
			_try_attack_move_engagement()

	if _attack_target != null:
		if not CombatTargetValidation.is_valid_combat_target(_attack_target):
			cancel_attack()
			_resume_attack_move()
		else:
			if CombatTargetValidation.is_enemy_faction(self) and can_scan_targets:
				_try_retarget_higher_priority_during_attack()
			_process_attack(delta)
			return

	super._physics_process(delta)

	if _has_attack_move_destination and _attack_target == null and not has_move_target:
		if _is_at_attack_move_destination():
			cancel_attack_move()


func _try_auto_attack() -> void:
	if CombatTargetValidation.is_enemy_faction(self) and not EnemyUnitMission.allows_combat_micro(self):
		return

	var closest_target: Node3D = _find_closest_attack_target_in_range()
	if closest_target != null:
		command_attack(closest_target)


func _find_closest_attack_target_in_range() -> Node3D:
	if CombatTargetValidation.is_enemy_faction(self):
		return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, attack_range
		)

	return CombatTargetValidation.find_closest_player_unit_attack_target_in_range(
		self, attack_range
	)


func _find_engagement_target_in_range() -> Node3D:
	var search_range: float = maxf(attack_range, ATTACK_MOVE_ENGAGEMENT_RANGE)
	return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
		self, search_range
	)


func _try_retarget_higher_priority_during_attack() -> void:
	if _attack_target == null:
		return

	var search_range: float = maxf(attack_range, ATTACK_MOVE_ENGAGEMENT_RANGE)
	var candidate: Node3D = CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
		self, search_range
	)
	if candidate == null or candidate == _attack_target:
		return

	var current_distance: float = CombatTargetValidation.get_horizontal_attack_distance(
		self, _attack_target
	)
	var candidate_distance: float = CombatTargetValidation.get_horizontal_attack_distance(
		self, candidate
	)
	var current_priority: int = CombatTargetValidation.get_enemy_attack_target_priority(
		self, _attack_target, current_distance
	)
	var candidate_priority: int = CombatTargetValidation.get_enemy_attack_target_priority(
		self, candidate, candidate_distance
	)
	if candidate_priority < current_priority:
		command_attack(candidate)


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

	if not CombatTargetValidation.apply_damage_to_target(_attack_target, float(attack_damage), self):
		cancel_attack()
		_resume_attack_move()
		return

	MeleeHitSound.play_at(self, _attack_target.global_position)
	_attack_cooldown_timer = attack_cooldown


func take_damage(amount: float, attacker = null) -> void:
	if _health_component.current_health <= 0:
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(self, attacker)

	var damage_amount := maxi(1, int(amount) - armor)
	_health_component.take_damage(damage_amount)
	FloatingDamageNumber.spawn(self, damage_amount)

	if (
		CombatTargetValidation.is_enemy_faction(self)
		and attacker is Node3D
		and CombatTargetValidation.is_attack_target_for_attacker(self, attacker)
		and EnemyUnitMission.allows_combat_micro(self)
	):
		command_attack(attacker as Node3D)


func get_current_health() -> int:
	return _health_component.current_health


func _on_health_depleted() -> void:
	HeroXpRewards.notify_unit_killed(self)
	_health_bar.visible = false
	cancel_attack_move()
	cancel_attack()
	EnemyUnitMission.clear_unit_mission(self)
	has_move_target = false
	velocity = Vector3.ZERO
	die()
	queue_free()


func _begin_chase() -> void:
	if not NodeSafety.is_alive_node(_attack_target):
		cancel_attack()
		return

	if _has_chase_target:
		return

	_set_move_destination(_compute_attack_approach_position(_attack_target))
	_has_chase_target = true


func _try_attack_move_engagement() -> void:
	if CombatTargetValidation.is_enemy_faction(self) and not EnemyUnitMission.allows_combat_micro(self):
		return

	var closest_target: Node3D = null
	if CombatTargetValidation.is_enemy_faction(self):
		closest_target = _find_engagement_target_in_range()
	else:
		closest_target = _find_closest_attack_target_in_range()

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
	var slot_index: int = maxi(_attack_approach_slot, 0)
	return CombatTargetValidation.compute_attack_approach_position(
		self, target, attack_range, stopping_distance, slot_index
	)


func _assign_attack_approach_slot(target: Node3D, assigned_slot: int) -> void:
	if assigned_slot >= 0:
		_attack_approach_slot = assigned_slot
	elif _attack_target != target:
		_attack_approach_slot = CombatTargetValidation.claim_attack_approach_slot(target)
