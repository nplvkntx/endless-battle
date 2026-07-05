class_name NeutralCreep
extends EnemyDummy

## Neutral camp unit. Retaliates when attacked, chases within leash, then returns home.

var _camp_anchor: Vector3 = Vector3.ZERO
var _spawn_position: Vector3 = Vector3.ZERO
var _returning_home: bool = false


func _ready() -> void:
	if is_in_group(&"enemies"):
		remove_from_group(&"enemies")
	if not is_in_group(&"neutral_creeps"):
		add_to_group(&"neutral_creeps")
	team_id = -1
	move_speed = CreepCampSafety.CREEP_MOVE_SPEED
	super._ready()
	_spawn_position = global_position
	_camp_anchor = CreepCampSafety.get_camp_anchor_for_creep(self)


func take_damage(amount: float, attacker = null) -> void:
	super.take_damage(amount, attacker)

	var valid_attacker: Unit = _resolve_combat_attacker(
		CombatTargetValidation.sanitize_damage_attacker(attacker)
	)
	if valid_attacker == null:
		return

	var parent: Node = get_parent()
	if parent is CreepCamp:
		(parent as CreepCamp).alert_camp_to_attacker(valid_attacker, self)


func alert_to_attacker(attacker: Unit) -> void:
	if not NodeSafety.is_alive_node(attacker):
		return

	if _health_component.current_health <= 0:
		return

	_set_attack_target(attacker)
	_returning_home = false


func _physics_process(delta: float) -> void:
	if _health_component.current_health <= 0:
		return

	_clear_invalid_attack_target()
	_process_camp_defense(delta)


func _process_camp_defense(delta: float) -> void:
	if not NodeSafety.is_alive_node(_attack_target):
		_attack_target = null
		_returning_home = true

	if _attack_target != null and _is_target_beyond_leash(_attack_target):
		_attack_target = null
		_returning_home = true

	if (
		_attack_target != null
		and _horizontal_distance(global_position, _camp_anchor)
		> CreepCampSafety.CREEP_LEASH_DISTANCE
	):
		_attack_target = null
		_returning_home = true

	if _returning_home:
		if _move_toward_position(_spawn_position, delta, CreepCampSafety.CAMP_HOME_TOLERANCE):
			_returning_home = false
			_attack_target = null
		return

	if _attack_target != null:
		if _is_in_attack_range(_attack_target):
			velocity = Vector3.ZERO
			move_and_slide()
			_process_counter_attack(delta)
			return

		_move_toward_target(_attack_target, delta)
		return

	velocity = Vector3.ZERO
	move_and_slide()


func _is_target_beyond_leash(target: Unit) -> bool:
	if not CombatTargetValidation.is_valid_combat_target(target):
		return true

	var target_position: Vector3 = target.global_position
	return (
		_horizontal_distance(target_position, _camp_anchor)
		> CreepCampSafety.CREEP_LEASH_DISTANCE
	)


func _move_toward_target(target: Unit, delta: float) -> void:
	if not CombatTargetValidation.is_valid_combat_target(target):
		return

	_move_toward_position(target.global_position, delta)


func _move_toward_position(
	target_position: Vector3,
	delta: float,
	arrival_tolerance: float = -1.0
) -> bool:
	var offset: Vector3 = target_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var tolerance: float = (
		arrival_tolerance if arrival_tolerance >= 0.0 else stopping_distance
	)

	if distance <= tolerance:
		velocity = Vector3.ZERO
		move_and_slide()
		return true

	var direction: Vector3 = offset / distance
	velocity = direction * move_speed
	velocity.y = 0.0
	move_and_slide()
	return false


func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length()


func _on_health_depleted() -> void:
	_attack_target = null
	HeroXpRewards.notify_unit_killed(self)
	_notify_camp_parent()
	_health_bar.visible = false
	die()
	queue_free()


func _notify_camp_parent() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent) or parent.is_queued_for_deletion():
		return

	if not parent.has_method(&"notify_creep_died"):
		return

	parent.call(&"notify_creep_died", self)
