class_name MilitaryUnit
extends Unit

## Shared combat + order layer for military units (move / attack / attack-move / hold / patrol).
## Subclasses configure stats and override attack delivery (melee, projectile, etc.).

@export var attack_damage: int = 10
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0
@export var armor: int = 0

const HEALTH_BAR_WIDTH := 1.2
const HEALTH_BAR_HUE_GREEN := 0.333333
const ATTACK_MOVE_ENGAGEMENT_RANGE := 14.0
const HOLD_RETURN_DISTANCE := 1.25
const OPPORTUNISTIC_CHASE_LEASH := 18.0
## Idle alert radius beyond attack range.
const ACQUISITION_RANGE_BONUS := 3.5
## Max chase distance from the position where idle auto-acquire began.
const AUTO_ACQUIRE_CHASE_LEASH := 8.0

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
## True while backing off to preferred ranged standoff (hysteresis vs too-close).
var _is_backing_off_for_range: bool = false
## True for explicit Attack orders; false for attack-move / patrol opportunistic fights.
var _committed_attack_order: bool = false
var _attack_move_destination: Vector3 = Vector3.ZERO
var _has_attack_move_destination: bool = false
var _is_holding_position: bool = false
var _hold_anchor: Vector3 = Vector3.ZERO
var _is_patrolling: bool = false
var _patrol_points: Array[Vector3] = []
var _patrol_index: int = 0
var _auto_acquire_origin: Vector3 = Vector3.ZERO
var _has_auto_acquire_origin: bool = false
var _is_returning_from_leash: bool = false
var _leash_return_destination: Vector3 = Vector3.ZERO


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
	super._exit_tree()


func supports_combat_orders() -> bool:
	return true


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
		_finish_attack_target_lost()
		return

	if _attack_target == null:
		if _has_chase_target:
			_has_chase_target = false
			clear_move_target()
			_resume_attack_move_or_patrol()
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		_finish_attack_target_lost()


func _finish_attack_target_lost() -> void:
	var was_committed: bool = _committed_attack_order
	cancel_attack()
	if _resume_attack_move_or_patrol():
		return
	if was_committed:
		notify_order_completed(UnitOrder.Type.ATTACK)


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


func _prepare_for_new_player_order() -> void:
	_clear_hold_position_state()
	_clear_patrol_state()
	_clear_auto_acquire_leash()
	cancel_attack_move()
	cancel_attack()
	super._prepare_for_new_player_order()


func command_attack(target: Node3D, assigned_slot: int = -1) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if not CombatTargetValidation.is_attack_target_for_attacker(self, target):
		return

	# Same attack target already active — do not reset nav/attack/animation.
	if (
		_attack_target == target
		and _has_active_attack_order
		and (assigned_slot < 0 or assigned_slot == _attack_approach_slot)
	):
		return

	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.attack(target, assigned_slot)
		_clear_hold_position_state()
		_clear_patrol_state()
		cancel_attack_move()

	_begin_attack_on_target(target, assigned_slot, true)


func _begin_attack_on_target(target: Node3D, assigned_slot: int, committed: bool) -> void:
	# Avoid duplicate attack orders against an already-active identical target.
	if (
		_attack_target == target
		and _has_active_attack_order
		and _committed_attack_order == committed
		and (assigned_slot < 0 or assigned_slot == _attack_approach_slot)
	):
		return

	_assign_attack_approach_slot(target, assigned_slot)
	_set_attack_target(target)
	if _attack_target == null:
		return
	_has_active_attack_order = true
	_committed_attack_order = committed
	_has_chase_target = false
	_is_returning_from_leash = false

	if committed or _has_attack_move_destination or _is_patrolling:
		_has_auto_acquire_origin = false
	elif not _has_auto_acquire_origin:
		_auto_acquire_origin = global_position
		_has_auto_acquire_origin = true

	if _is_holding_position:
		# Hold Position: strike only when already in range; never chase away.
		if not _is_in_attack_range(_attack_target):
			cancel_attack()
		return

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
	_finish_attack_target_lost()


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
			# Equivalent attack-move: keep chase/move state; only ensure destination bookkeeping.
			if not _issuing_order and urgency == RepathUrgency.PLAYER_ORDER:
				_active_order = UnitOrder.attack_move(destination)
			if has_move_target or _attack_target != null:
				return
			# Idle at same attack-move point with no move — nothing to repath.
			if _is_at_attack_move_destination():
				return

	if not _issuing_order and urgency == RepathUrgency.PLAYER_ORDER:
		_order_queue.clear()
		_active_order = UnitOrder.attack_move(destination)
		_clear_hold_position_state()
		_clear_patrol_state()
	elif not _issuing_order and urgency != RepathUrgency.PLAYER_ORDER:
		# AI formation orders must not wipe the player-style order queue bookkeeping the same way,
		# but they still need a clean attack-move destination.
		_clear_hold_position_state()
		_clear_patrol_state()

	_attack_move_destination = flat_destination
	_has_attack_move_destination = true
	cancel_attack()
	_set_move_destination(flat_destination, urgency)


func command_hold_position() -> void:
	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.hold_position()
		_clear_patrol_state()
		cancel_attack_move()
		cancel_attack()

	_is_holding_position = true
	_hold_anchor = global_position
	clear_move_target()


func command_patrol(points: Array[Vector3]) -> void:
	var resolved_points: Array[Vector3] = _normalize_patrol_points(points)
	if resolved_points.size() < 2:
		return

	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.patrol(resolved_points)
		_clear_hold_position_state()

	_patrol_points = resolved_points
	_patrol_index = 0
	_is_patrolling = true
	cancel_attack()
	_start_patrol_leg()


func append_patrol_point(point: Vector3) -> void:
	if not _is_patrolling:
		command_patrol([global_position, point] as Array[Vector3])
		return

	var next_point := Vector3(point.x, global_position.y, point.z)
	_patrol_points.append(next_point)
	if _active_order != null and _active_order.type == UnitOrder.Type.PATROL:
		_active_order.patrol_points = _patrol_points.duplicate()


func _normalize_patrol_points(points: Array[Vector3]) -> Array[Vector3]:
	var resolved: Array[Vector3] = []
	for point: Vector3 in points:
		resolved.append(Vector3(point.x, global_position.y, point.z))
	if resolved.is_empty():
		return resolved
	if resolved.size() == 1:
		resolved.insert(0, global_position)
	return resolved


func _start_patrol_leg() -> void:
	if _patrol_points.is_empty():
		_clear_patrol_state()
		return

	_patrol_index = posmod(_patrol_index, _patrol_points.size())
	var destination: Vector3 = _patrol_points[_patrol_index]
	_attack_move_destination = destination
	_has_attack_move_destination = true
	_set_move_destination(destination, RepathUrgency.PLAYER_ORDER)


func _advance_patrol_waypoint() -> void:
	if not _is_patrolling or _patrol_points.is_empty():
		return
	_patrol_index = (_patrol_index + 1) % _patrol_points.size()
	_start_patrol_leg()


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
	_committed_attack_order = false


func _clear_auto_acquire_leash() -> void:
	_has_auto_acquire_origin = false
	_is_returning_from_leash = false


func _clear_hold_position_state() -> void:
	_is_holding_position = false


func _clear_patrol_state() -> void:
	_is_patrolling = false
	_patrol_points.clear()
	_patrol_index = 0


func set_movement_target(
	target: Vector3,
	urgency: RepathUrgency = RepathUrgency.PLAYER_ORDER
) -> bool:
	if not _issuing_order and urgency == RepathUrgency.PLAYER_ORDER:
		_order_queue.clear()
		_active_order = UnitOrder.move(target)
		_prepare_for_new_player_order()
	elif not _issuing_order:
		# AI / formation moves: cancel combat overlays without treating as player replace.
		_clear_auto_acquire_leash()
		cancel_attack_move()
		cancel_attack()
	else:
		_clear_auto_acquire_leash()
		cancel_attack_move()
		cancel_attack()
	return _set_move_destination(target, urgency)


func stop_movement() -> void:
	_clear_hold_position_state()
	_clear_patrol_state()
	cancel_attack_move()
	cancel_attack()
	super.stop_movement()


func _on_movement_arrived() -> void:
	if _is_patrolling and _has_attack_move_destination:
		_advance_patrol_waypoint()
		return

	if _has_attack_move_destination and _is_at_attack_move_destination():
		cancel_attack_move()
		notify_order_completed(UnitOrder.Type.ATTACK_MOVE)
		return

	super._on_movement_arrived()


func _set_move_destination(
	target: Vector3,
	urgency: RepathUrgency = RepathUrgency.NORMAL
) -> bool:
	return request_movement_target(target, urgency)


func _physics_process(delta: float) -> void:
	if _health_component.current_health <= 0:
		return

	var can_scan_targets: bool = tick_combat_target_scan_timer(delta)

	if _is_holding_position:
		_update_hold_position(can_scan_targets, delta)
		return

	if _is_returning_from_leash:
		_update_leash_return(delta)
		return

	if _attack_target == null and not has_move_target:
		if can_scan_targets:
			_try_auto_attack()

	if _has_attack_move_destination and _attack_target == null:
		if can_scan_targets:
			_try_attack_move_engagement()

	if _has_active_attack_order:
		if not NodeSafety.is_alive_node(_attack_target):
			_finish_attack_target_lost()
		elif not CombatTargetValidation.is_valid_combat_target(_attack_target):
			_finish_attack_target_lost()
		elif not _committed_attack_order and _should_break_opportunistic_chase():
			_break_opportunistic_or_auto_chase()
		else:
			if can_scan_targets:
				_try_retarget_higher_priority_during_attack()
			_process_attack(delta)
			return

	super._physics_process(delta)

	if _has_attack_move_destination and _attack_target == null and not has_move_target:
		if _is_patrolling:
			_advance_patrol_waypoint()
		elif _is_at_attack_move_destination():
			cancel_attack_move()
			notify_order_completed(UnitOrder.Type.ATTACK_MOVE)


func _update_hold_position(can_scan_targets: bool, delta: float) -> void:
	# Drift correction: return toward anchor if pushed away.
	var offset: Vector3 = global_position - _hold_anchor
	offset.y = 0.0
	if offset.length() > HOLD_RETURN_DISTANCE and _attack_target == null:
		_set_move_destination(_hold_anchor, RepathUrgency.NORMAL)
		super._physics_process(delta)
		return

	if _attack_target == null:
		clear_move_target()
		if can_scan_targets:
			var nearby: Node3D = _find_closest_attack_target_in_range()
			if nearby != null:
				_begin_attack_on_target(nearby, -1, false)
		apply_standing_separation(true)
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		apply_standing_separation(true)
		return

	if _is_in_attack_range(_attack_target):
		_stop_and_attack(delta)
	else:
		# Target left acquisition — drop it and stay put.
		cancel_attack()
		apply_standing_separation(true)


func _try_auto_attack() -> void:
	if CombatTargetValidation.is_enemy_faction(self) and not EnemyUnitMission.allows_combat_micro(self):
		return

	var closest_target: Node3D = _find_auto_acquire_target()
	if closest_target != null:
		_begin_attack_on_target(closest_target, -1, false)


func get_acquisition_range() -> float:
	return attack_range + ACQUISITION_RANGE_BONUS


func _find_auto_acquire_target() -> Node3D:
	var search_range: float = get_acquisition_range()
	if SharedSquadNavigation.is_shared_navigation_enabled():
		var squad_target: Node3D = SharedSquadNavigation.try_get_assigned_target(self)
		if squad_target != null:
			return squad_target
	if CombatTargetValidation.is_enemy_faction(self):
		return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, search_range
		)
	return CombatTargetValidation.find_best_auto_acquire_target_in_range(self, search_range)


func _find_closest_attack_target_in_range() -> Node3D:
	## Hold Position uses strict attack range (no chase).
	if CombatTargetValidation.is_enemy_faction(self):
		return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, attack_range
		)

	return CombatTargetValidation.find_closest_player_unit_attack_target_in_range(
		self, attack_range
	)


func _find_engagement_target_in_range() -> Node3D:
	var search_range: float = maxf(attack_range, ATTACK_MOVE_ENGAGEMENT_RANGE)
	if SharedSquadNavigation.is_shared_navigation_enabled():
		var squad_target: Node3D = SharedSquadNavigation.try_get_assigned_target(self)
		if squad_target != null:
			return squad_target
	if CombatTargetValidation.is_enemy_faction(self):
		return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, search_range
		)
	return CombatTargetValidation.find_best_auto_acquire_target_in_range(self, search_range)


func _try_retarget_higher_priority_during_attack() -> void:
	if _attack_target == null:
		return
	if _committed_attack_order:
		return
	## AI keeps a valid in-range target unless a significantly better threat appears.
	if (
		CombatTargetValidation.is_enemy_faction(self)
		and _is_in_attack_range(_attack_target)
		and CombatTargetValidation.is_valid_combat_target(_attack_target)
	):
		## Only re-evaluate on a slower cadence than acquire scans.
		if not should_run_staggered_update(5):
			return

	var search_range: float = get_acquisition_range()
	if _has_attack_move_destination:
		search_range = maxf(attack_range, ATTACK_MOVE_ENGAGEMENT_RANGE)

	var candidate: Node3D = null
	if CombatTargetValidation.is_enemy_faction(self):
		candidate = CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, search_range
		)
	else:
		candidate = CombatTargetValidation.find_best_auto_acquire_target_in_range(
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
	var current_priority: int
	var candidate_priority: int
	if CombatTargetValidation.is_enemy_faction(self):
		current_priority = CombatTargetValidation.get_enemy_attack_target_priority(
			self, _attack_target, current_distance
		)
		candidate_priority = CombatTargetValidation.get_enemy_attack_target_priority(
			self, candidate, candidate_distance
		)
		## Require a clear priority upgrade before abandoning a valid AI target.
		if candidate_priority >= current_priority:
			return
	else:
		current_priority = CombatTargetValidation.get_auto_acquire_target_priority(
			self, _attack_target, current_distance
		)
		candidate_priority = CombatTargetValidation.get_auto_acquire_target_priority(
			self, candidate, candidate_distance
		)
	if candidate_priority < current_priority:
		_begin_attack_on_target(candidate, -1, _committed_attack_order)


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
		_finish_attack_target_lost()
		return

	if not _deliver_attack():
		_finish_attack_target_lost()
		return

	_attack_cooldown_timer = UnitStats.get_final_attack_cooldown(
		attack_cooldown,
		_get_ally_aura_attack_speed_bonus()
	)


func _should_reposition_for_preferred_range() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		_is_backing_off_for_range = false
		return false
	if _is_holding_position:
		_is_backing_off_for_range = false
		return false

	# Hysteresis: once backing off, keep moving until preferred hold range is reached.
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


## Override for unit-specific strike delivery. Return false if the strike failed.
func _deliver_attack() -> bool:
	if not DamageService.apply_damage(_attack_target, float(attack_damage), self):
		return false

	MeleeHitSound.play_at(self, _attack_target.global_position)
	return true


## Override when incoming damage ignores armor (e.g. archer).
func _compute_incoming_damage(amount: float) -> int:
	var total_armor: float = float(armor) + _get_ally_aura_armor_bonus()
	return DamageService.compute_armored_damage(amount, int(round(total_armor)))


func _get_ally_aura_armor_bonus() -> float:
	return float(HeroItemService.get_nearby_ally_aura_bonuses(self).get("armor", 0.0))


func _get_ally_aura_attack_speed_bonus() -> float:
	return float(HeroItemService.get_nearby_ally_aura_bonuses(self).get("attack_speed", 0.0))


func take_damage(amount: float, attacker = null) -> void:
	DamageService.apply(
		self,
		amount,
		attacker,
		{DamageService.OPT_IGNORE_HOSTILITY: true}
	)


func _on_combat_damage_received(result: Dictionary) -> void:
	var resolved_attacker = result.get(DamageService.RESULT_ATTACKER)
	if not UnitCombatDamage.should_enemy_retaliate(self, resolved_attacker):
		return

	if _is_holding_position:
		if CombatTargetValidation.is_within_attack_range(
			self, resolved_attacker as Node3D, attack_range
		):
			_begin_attack_on_target(resolved_attacker as Node3D, -1, false)
	else:
		command_attack(resolved_attacker as Node3D)


func get_current_health() -> int:
	return _health_component.current_health


func _on_health_depleted() -> void:
	HeroXpRewards.notify_unit_killed(self)
	_health_bar.visible = false
	_clear_order_queue_internal()
	_active_order = null
	_clear_hold_position_state()
	_clear_patrol_state()
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
	if _is_holding_position:
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
		# Near-skip / cooldown rejected but we still need a chase flag when already close.
		_has_chase_target = true


func _try_attack_move_engagement() -> void:
	if CombatTargetValidation.is_enemy_faction(self) and not EnemyUnitMission.allows_combat_micro(self):
		return

	var closest_target: Node3D = _find_engagement_target_in_range()
	if closest_target != null:
		_begin_attack_on_target(closest_target, -1, false)


func _should_break_opportunistic_chase() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		return true

	# Idle auto-acquire leash from the acquisition origin.
	if _has_auto_acquire_origin and not _has_attack_move_destination and not _is_patrolling:
		var from_origin: Vector3 = global_position - _auto_acquire_origin
		from_origin.y = 0.0
		if from_origin.length() > AUTO_ACQUIRE_CHASE_LEASH:
			return true
		var target_from_origin: Vector3 = _attack_target.global_position - _auto_acquire_origin
		target_from_origin.y = 0.0
		if target_from_origin.length() > AUTO_ACQUIRE_CHASE_LEASH:
			return true
		return false

	var distance: float = CombatTargetValidation.get_horizontal_attack_distance(self, _attack_target)
	if distance > OPPORTUNISTIC_CHASE_LEASH:
		return true

	# Prefer staying near the attack-move / patrol destination rather than chasing forever.
	if _has_attack_move_destination:
		var target_from_dest: Vector3 = _attack_target.global_position - _attack_move_destination
		target_from_dest.y = 0.0
		if target_from_dest.length() > OPPORTUNISTIC_CHASE_LEASH:
			return true

	return false


func _break_opportunistic_or_auto_chase() -> void:
	var should_return_home: bool = (
		_has_auto_acquire_origin
		and not _has_attack_move_destination
		and not _is_patrolling
	)
	var return_pos: Vector3 = _auto_acquire_origin
	cancel_attack()
	if _resume_attack_move_or_patrol():
		_clear_auto_acquire_leash()
		return
	if should_return_home:
		_begin_leash_return(return_pos)
	else:
		_clear_auto_acquire_leash()


func _begin_leash_return(destination: Vector3) -> void:
	_is_returning_from_leash = true
	_leash_return_destination = Vector3(destination.x, global_position.y, destination.z)
	_has_auto_acquire_origin = false
	_set_move_destination(_leash_return_destination, RepathUrgency.NORMAL)


func _update_leash_return(delta: float) -> void:
	var offset: Vector3 = global_position - _leash_return_destination
	offset.y = 0.0
	if offset.length() <= get_movement_acceptance_radius() or not has_move_target:
		_is_returning_from_leash = false
		clear_move_target()
		# Remain alert immediately after returning.
		_try_auto_attack()
		return
	super._physics_process(delta)


func _resume_attack_move() -> bool:
	return _resume_attack_move_or_patrol()


func _resume_attack_move_or_patrol() -> bool:
	if _is_patrolling:
		_start_patrol_leg()
		return true

	if not _has_attack_move_destination:
		return false

	if _is_at_attack_move_destination():
		cancel_attack_move()
		notify_order_completed(UnitOrder.Type.ATTACK_MOVE)
		return false

	_has_chase_target = false
	var resume_dest: Vector3 = _attack_move_destination
	## Player shared-route: resume the active route guide, not a stale mid-fight point.
	if _player_squad_command_generation >= 0:
		var travel: Vector3 = PlayerRouteNavigation.resolve_travel_target(self)
		if travel.length_squared() > 0.0001:
			resume_dest = travel
			if _player_squad_final_arrival.length_squared() > 0.0001:
				_attack_move_destination = Vector3(
					_player_squad_final_arrival.x,
					global_position.y,
					_player_squad_final_arrival.z
				)
	if (
		_player_squad_command_generation >= 0
		and _player_squad_final_arrival.length_squared() > 0.0001
	):
		request_route_travel_target(
			resume_dest,
			_player_squad_final_arrival,
			RepathUrgency.NORMAL
		)
	else:
		_set_move_destination(resume_dest, RepathUrgency.NORMAL)
	return true


func _is_at_attack_move_destination() -> bool:
	var offset: Vector3 = global_position - _attack_move_destination
	offset.y = 0.0
	return offset.length() <= get_movement_acceptance_radius()


func _should_skip_stuck_recovery() -> bool:
	# Attacking / holding / waiting in range are not movement deadlocks.
	if _is_holding_position:
		return true
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
