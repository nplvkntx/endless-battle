class_name HeavyCavalry
extends Unit

## Armored heavy mounted melee cavalry placeholder.

const UNIT_ID: StringName = &"heavy_cavalry"

@export var attack_damage: int = UnitStats.HEAVY_CAVALRY_ATTACK_DAMAGE
@export var attack_range: float = UnitStats.HEAVY_CAVALRY_ATTACK_RANGE
@export var attack_cooldown: float = UnitStats.HEAVY_CAVALRY_ATTACK_COOLDOWN
@export var armor: int = UnitStats.HEAVY_CAVALRY_ARMOR

var _base_attack_damage: int = -1
var _base_armor: int = -1

const HEALTH_BAR_WIDTH := 1.2
const HEALTH_BAR_HUE_GREEN := 0.333333
const ATTACK_MOVE_ENGAGEMENT_RANGE := 14.0

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill

var _health_bar_fill_material: StandardMaterial3D
var _attack_target: Node3D = null
var _attack_target_tree_exiting_handler: Callable = Callable()
var _attack_approach_slot: int = -1
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false
var _has_active_attack_order: bool = false
var _is_backing_off_for_range: bool = false
var _attack_move_destination: Vector3 = Vector3.ZERO
var _has_attack_move_destination: bool = false


func _ready() -> void:
	damage_type = DamageService.DamageType.PHYSICAL
	armor_type = DamageService.ArmorType.HEAVY
	super._ready()
	_cache_base_stats()
	_health_bar_fill_material = HealthBarDisplay.duplicate_mesh_material(_health_bar_fill)
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)
	if CombatTargetValidation.is_enemy_faction(self):
		if not UpgradeManager.enemy_upgrade_applied.is_connected(_on_stable_upgrade_applied):
			UpgradeManager.enemy_upgrade_applied.connect(_on_stable_upgrade_applied)
	else:
		if not UpgradeManager.upgrade_applied.is_connected(_on_stable_upgrade_applied):
			UpgradeManager.upgrade_applied.connect(_on_stable_upgrade_applied)
	call_deferred("_try_apply_stable_upgrades")


func _exit_tree() -> void:
	cancel_attack_move()
	cancel_attack()
	EnemyUnitMission.clear_unit_mission(self)
	if UpgradeManager.upgrade_applied.is_connected(_on_stable_upgrade_applied):
		UpgradeManager.upgrade_applied.disconnect(_on_stable_upgrade_applied)
	if UpgradeManager.enemy_upgrade_applied.is_connected(_on_stable_upgrade_applied):
		UpgradeManager.enemy_upgrade_applied.disconnect(_on_stable_upgrade_applied)


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
	if _has_active_attack_order and not NodeSafety.is_alive_node(_attack_target):
		cancel_attack()
		_resume_attack_move()
		return

	if _attack_target == null:
		if _has_chase_target:
			_has_chase_target = false
			clear_move_target()
			_resume_attack_move()
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		_resume_attack_move()


func _is_attack_target_valid_for_facing() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		_clear_attack_target_lifetime_watch()
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


func supports_combat_orders() -> bool:
	return true


func command_attack(target: Node3D, assigned_slot: int = -1) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if not CombatTargetValidation.is_attack_target_for_attacker(self, target):
		return

	if (
		_attack_target == target
		and _has_active_attack_order
		and (assigned_slot < 0 or assigned_slot == _attack_approach_slot)
	):
		return

	_assign_attack_approach_slot(target, assigned_slot)
	_set_attack_target(target)
	if _attack_target == null:
		return
	_has_active_attack_order = true
	_has_chase_target = false

	if not _is_in_attack_range(_attack_target):
		_begin_chase()


func _set_attack_target(target: Node3D) -> void:
	_clear_attack_target_lifetime_watch()
	_attack_target = NodeSafety.safe_node(target) as Node3D
	if _attack_target == null:
		return
	_watch_attack_target_lifetime(_attack_target)


func _watch_attack_target_lifetime(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_attack_target_tree_exiting_handler = _on_attack_target_tree_exiting.bind(target.get_instance_id())
	if not target.tree_exiting.is_connected(_attack_target_tree_exiting_handler):
		target.tree_exiting.connect(_attack_target_tree_exiting_handler, CONNECT_ONE_SHOT)


func _clear_attack_target_lifetime_watch() -> void:
	if not _attack_target_tree_exiting_handler.is_valid():
		_attack_target_tree_exiting_handler = Callable()
		return

	var target_ref: Variant = _attack_target
	if (
		target_ref != null
		and is_instance_valid(target_ref)
		and target_ref is Node
		and (target_ref as Node).tree_exiting.is_connected(_attack_target_tree_exiting_handler)
	):
		(target_ref as Node).tree_exiting.disconnect(_attack_target_tree_exiting_handler)

	_attack_target_tree_exiting_handler = Callable()


func _on_attack_target_tree_exiting(expected_instance_id: int) -> void:
	_attack_target_tree_exiting_handler = Callable()
	var target_ref: Variant = _attack_target
	if target_ref != null and is_instance_valid(target_ref):
		if int(target_ref.get_instance_id()) != expected_instance_id:
			return
	cancel_attack()
	_resume_attack_move()


func command_attack_move(
	destination: Vector3,
	urgency: RepathUrgency = RepathUrgency.PLAYER_ORDER
) -> void:
	var flat_destination: Vector3 = Vector3(destination.x, global_position.y, destination.z)
	if _has_attack_move_destination:
		var existing_delta: Vector3 = flat_destination - _attack_move_destination
		existing_delta.y = 0.0
		var skip_threshold: float = (
			PLAYER_DEST_NEAR_SKIP
			if urgency == RepathUrgency.PLAYER_ORDER
			else MOVE_DEST_TOLERANCE
		)
		if existing_delta.length() <= skip_threshold:
			if has_move_target or _attack_target != null:
				return
			if _is_at_attack_move_destination():
				return

	_attack_move_destination = flat_destination
	_has_attack_move_destination = true
	cancel_attack()
	_set_move_destination(flat_destination, urgency)


func cancel_attack_move() -> void:
	_has_attack_move_destination = false


func cancel_attack() -> void:
	if NodeSafety.is_alive_node(_attack_target):
		CombatTargetValidation.release_attack_approach_slot(_attack_target, self)
	_clear_attack_target_lifetime_watch()
	_attack_target = null
	_attack_approach_slot = -1
	_has_chase_target = false
	_is_backing_off_for_range = false
	_has_active_attack_order = false


func set_movement_target(
	target: Vector3,
	urgency: RepathUrgency = RepathUrgency.PLAYER_ORDER
) -> bool:
	cancel_attack_move()
	cancel_attack()
	return _set_move_destination(target, urgency)


func stop_movement() -> void:
	cancel_attack_move()
	cancel_attack()
	super.stop_movement()


func _set_move_destination(
	target: Vector3,
	urgency: RepathUrgency = RepathUrgency.NORMAL
) -> bool:
	return request_movement_target(target, urgency)


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

	if _has_active_attack_order:
		if not NodeSafety.is_alive_node(_attack_target):
			cancel_attack()
			_resume_attack_move()
		elif not CombatTargetValidation.is_valid_combat_target(_attack_target):
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
		if _should_reposition_for_preferred_range():
			_update_chase_movement(delta)
			super._physics_process(delta)
			if _attack_target != null and _is_in_attack_range(_attack_target):
				if not _should_reposition_for_preferred_range():
					_is_backing_off_for_range = false
					_stop_and_attack(delta)
			return

		_is_backing_off_for_range = false
		_stop_and_attack(delta)
		return

	_update_chase_movement(delta)
	super._physics_process(delta)

	if _attack_target != null and _is_in_attack_range(_attack_target):
		if not _should_reposition_for_preferred_range():
			_is_backing_off_for_range = false
			_stop_and_attack(delta)


func _stop_and_attack(delta: float) -> void:
	clear_move_target()
	_has_chase_target = false
	_is_backing_off_for_range = false
	apply_standing_separation(true)

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		_resume_attack_move()
		return

	if not DamageService.apply_damage(_attack_target, float(attack_damage), self):
		cancel_attack()
		_resume_attack_move()
		return

	MeleeHitSound.play_at(self, _attack_target.global_position)
	_attack_cooldown_timer = UnitStats.get_final_attack_cooldown(
		attack_cooldown,
		float(HeroItemService.get_nearby_ally_aura_bonuses(self).get("attack_speed", 0.0))
	)


func _should_reposition_for_preferred_range() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		_is_backing_off_for_range = false
		return false

	if _is_backing_off_for_range:
		if CombatTargetValidation.is_at_preferred_hold_range(
			self,
			_attack_target,
			attack_range,
			stopping_distance,
			maxi(_attack_approach_slot, 0)
		):
			_is_backing_off_for_range = false
			return false
		return true

	if CombatTargetValidation.is_too_close_for_preferred_range(
		self,
		_attack_target,
		attack_range,
		stopping_distance,
		maxi(_attack_approach_slot, 0)
	):
		_is_backing_off_for_range = true
		return true

	return false


func apply_stable_upgrades() -> void:
	_cache_base_stats()
	var attack_level: int = _get_stable_upgrade_level(
		UpgradeManager.get_cavalry_attack_upgrade_id(UNIT_ID)
	)
	var defense_level: int = _get_stable_upgrade_level(
		UpgradeManager.get_cavalry_defense_upgrade_id(UNIT_ID)
	)
	attack_damage = _base_attack_damage + attack_level * UpgradeStats.CAVALRY_ATTACK_DAMAGE_PER_LEVEL
	armor = _base_armor + defense_level * UpgradeStats.CAVALRY_DEFENSE_ARMOR_PER_LEVEL


func _get_stable_upgrade_level(upgrade_id: StringName) -> int:
	if CombatTargetValidation.is_enemy_faction(self):
		return UpgradeManager.get_enemy_level(upgrade_id)

	return UpgradeManager.get_level(upgrade_id)


func _cache_base_stats() -> void:
	if _base_attack_damage < 0:
		_base_attack_damage = attack_damage
	if _base_armor < 0:
		_base_armor = armor


func _try_apply_stable_upgrades() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if CombatTargetValidation.is_enemy_faction(self):
		UpgradeManager.apply_enemy_upgrades_to_unit(self)
	else:
		UpgradeManager.apply_player_upgrades_to_unit(self)


func _on_stable_upgrade_applied(upgrade_id: StringName) -> void:
	if upgrade_id != UpgradeManager.get_cavalry_attack_upgrade_id(UNIT_ID):
		if upgrade_id != UpgradeManager.get_cavalry_defense_upgrade_id(UNIT_ID):
			return

	_try_apply_stable_upgrades()


func _compute_incoming_damage(amount: float) -> int:
	var total_armor: float = float(armor) + float(
		HeroItemService.get_nearby_ally_aura_bonuses(self).get("armor", 0.0)
	)
	return DamageService.compute_armored_damage(amount, int(round(total_armor)))


func take_damage(amount: float, attacker = null) -> void:
	DamageService.apply(
		self,
		amount,
		attacker,
		{DamageService.OPT_IGNORE_HOSTILITY: true}
	)


func _on_combat_damage_received(result: Dictionary) -> void:
	var attacker = result.get(DamageService.RESULT_ATTACKER)
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
	clear_move_target()
	die()
	queue_free()


func _begin_chase() -> void:
	_update_chase_movement(0.0, true)


func _update_chase_movement(delta: float = 0.0, force: bool = false) -> void:
	if not NodeSafety.is_alive_node(_attack_target):
		cancel_attack()
		return

	if not force and not tick_chase_update_timer(delta, false):
		return

	var approach_position: Vector3 = _compute_attack_approach_position(_attack_target)
	if _has_chase_target and has_move_target:
		var destination_delta: Vector3 = approach_position - _movement_target
		destination_delta.y = 0.0
		if destination_delta.length() < CHASE_TARGET_MOVE_THRESHOLD:
			return

	if _set_move_destination(approach_position, RepathUrgency.CHASE):
		_has_chase_target = true
	elif not has_move_target:
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
	_set_move_destination(_attack_move_destination, RepathUrgency.NORMAL)


func _is_at_attack_move_destination() -> bool:
	var offset: Vector3 = global_position - _attack_move_destination
	offset.y = 0.0
	return offset.length() <= get_movement_acceptance_radius()


func _should_skip_stuck_recovery() -> bool:
	if _attack_target != null and _is_in_attack_range(_attack_target):
		if not _should_reposition_for_preferred_range():
			return true
	return false


func _is_in_attack_range(target: Variant) -> bool:
	return CombatTargetValidation.is_within_attack_range(self, target, attack_range)


func _compute_attack_approach_position(target: Node3D) -> Vector3:
	var slot_index: int = maxi(_attack_approach_slot, 0)
	return CombatTargetValidation.compute_attack_approach_position(
		self, target, attack_range, stopping_distance, slot_index
	)


func _assign_attack_approach_slot(target: Node3D, assigned_slot: int) -> void:
	if assigned_slot >= 0:
		_attack_approach_slot = CombatTargetValidation.reserve_attack_approach_slot(
			target, self, assigned_slot
		)
	elif _attack_target != target:
		_attack_approach_slot = CombatTargetValidation.claim_attack_approach_slot(target, self)
