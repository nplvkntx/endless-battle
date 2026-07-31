class_name Unit
extends CharacterBody3D

## Base class for all movable units (workers, soldiers, archers, etc.).
## Owns health, movement hooks, selection state, team ownership, and death flow.
## Stat values must come from an external Resource — never hardcoded in this script.

signal health_changed(current: float, maximum: float)
signal selected_changed(is_selected: bool)
signal died(unit: Unit)

@export var unit_data: Resource
@export var move_speed: float = 5.0
@export var stopping_distance: float = 0.25

const UNSTUCK_STUCK_MOVE_RATIO := 0.2
const UNSTUCK_CONFIRM_SECONDS := 1.25
const UNSTUCK_DETOUR_START_DELAY := 1.25
const UNSTUCK_DETOUR_COMMIT_TIME := 0.75
const UNSTUCK_DETOUR_MAX_TIME := 2.0
const UNSTUCK_MAX_SIDE_FLIPS := 1
const UNSTUCK_LATERAL_FORWARD_BLEND := 0.12
const UNSTUCK_PROBE_DISTANCE := 2.5
const UNSTUCK_PATH_CHECK_DISTANCE := 3.0
const UNSTUCK_RECOVERY_COOLDOWN_SECONDS := 1.5
const UNSTUCK_MIN_REMAINING_DISTANCE := 1.5
const MOVE_DEST_TOLERANCE := 1.0
const MOVE_DEST_NEAR_SKIP := 0.35
const REPATH_COOLDOWN_NORMAL_SECONDS := 0.7
const REPATH_COOLDOWN_FORMATION_SECONDS := 1.0
const REPATH_COOLDOWN_URGENT_SECONDS := 0.35
const REPATH_COOLDOWN_STUCK_SECONDS := 0.75
const REPATH_STAGGER_OFFSET_SECONDS := 0.08
const PATH_VALIDITY_CHECK_INTERVAL := 0.55
const CHASE_TARGET_MOVE_THRESHOLD := 1.25
const COMBAT_TARGET_SCAN_INTERVAL := 0.45
const COMBAT_TARGET_SCAN_JITTER := 0.30
const COMBAT_TARGET_VALIDATE_INTERVAL := 0.12
const VISUAL_FACING_TURN_SPEED := 12.0
const VISUAL_FACING_VELOCITY_THRESHOLD_SQ := 0.04

enum RepathUrgency {
	NORMAL,
	FORMATION,
	URGENT,
	STUCK_RECOVERY,
	PLAYER_ORDER,
}

var team_id: int = -1
var is_selected: bool = false
var has_move_target: bool = false

var _current_health: float = 0.0
var _max_health: float = 0.0

var _selection_indicator: Node3D
var _movement_target: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _is_confirmed_stuck: bool = false
var _detour_active: bool = false
var _detour_side: float = 1.0
var _detour_time: float = 0.0
var _detour_flips: int = 0
var _detour_gave_up: bool = false
var _distance_at_detour_start: float = 0.0
var _stuck_recovery_cooldown: float = 0.0
var _stuck_repath_attempted: bool = false
var _combat_target_scan_timer: float = 0.0
var _combat_target_validate_timer: float = 0.0
var _last_issued_move_destination: Vector3 = Vector3.ZERO
var _last_requested_destination: Vector3 = Vector3.ZERO
var _last_path_request_msec: int = 0
var _last_move_order_msec: int = 0
var _previous_position: Vector3 = Vector3.ZERO
var _visual_pivot: Node3D
var _visual_facing_yaw_offset: float = PI
var _visual_facing_initialized: bool = false
var _visual_animator: UnitVisualAnimator
var _population_food_released: bool = false
var _navigation_agent: NavigationAgent3D
var _navigation_active: bool = false
var _path_validity_timer: float = 0.0

## Shared player order queue (WC3-style). Non-shift replaces; Shift appends.
var _order_queue: Array[UnitOrder] = []
var _active_order: UnitOrder = null
var _issuing_order: bool = false


func _ready() -> void:
	_combat_target_scan_timer = randf() * (COMBAT_TARGET_SCAN_INTERVAL + COMBAT_TARGET_SCAN_JITTER)
	_combat_target_validate_timer = randf() * COMBAT_TARGET_VALIDATE_INTERVAL
	_path_validity_timer = randf() * PATH_VALIDITY_CHECK_INTERVAL
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = PhysicsLayers.UNITS
	collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	_selection_indicator = get_node_or_null("SelectionIndicator") as Node3D
	if _selection_indicator:
		_selection_indicator.visible = false
	_visual_pivot = get_node_or_null("MeshInstance3D") as Node3D
	_visual_facing_yaw_offset = _detect_visual_facing_yaw_offset()
	_setup_visual_animator()
	_setup_navigation_agent()
	_apply_unit_data()
	call_deferred("apply_team_visuals")


func _exit_tree() -> void:
	EnemyUnitMission.clear_unit_mission(self)
	if _visual_animator != null:
		_visual_animator.release()
		_visual_animator = null


## Applies a team-colored accent ring and subtle body tint from team_id or faction groups.
func apply_team_visuals() -> void:
	TeamVisuals.apply_to_entity(self, team_id)


## Updates selection state and toggles the optional SelectionIndicator child.
func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return

	is_selected = selected
	SelectionGlow.set_selection_glow_selected(self, selected)


## Shows or hides the selection ring while inspecting enemy/neutral entities.
func set_inspected(inspected: bool) -> void:
	if inspected:
		SelectionGlow.set_selection_glow_selected(self, true)
	elif not is_selected:
		SelectionGlow.set_selection_glow_selected(self, false)


## True for units that accept attack / attack-move / cancel-attack orders.
func supports_combat_orders() -> bool:
	return false


## True for units that accept Hold Position / Patrol.
func supports_hold_position() -> bool:
	return supports_combat_orders()


func supports_patrol() -> bool:
	return supports_combat_orders()


## Combat order stubs — MilitaryUnit / Hero / legacy combat scripts override these.
func command_attack(_target: Node3D, _assigned_slot: int = -1) -> void:
	pass


func command_attack_move(_destination: Vector3) -> void:
	pass


func command_hold_position() -> void:
	pass


func command_patrol(_points: Array[Vector3]) -> void:
	pass


func cancel_attack() -> void:
	pass


func cancel_attack_move() -> void:
	pass


func append_patrol_point(_point: Vector3) -> void:
	pass


## Issue a player order. `queued` true (Shift) appends; false replaces the queue.
func issue_order(order: UnitOrder, queued: bool = false) -> bool:
	if order == null:
		return false
	if not _can_accept_order(order):
		return false

	if order.type == UnitOrder.Type.STOP:
		issue_stop()
		return true

	if queued:
		if _active_order != null:
			_order_queue.append(order)
			return true
	else:
		_order_queue.clear()

	return _start_order(order)


func issue_stop() -> void:
	_order_queue.clear()
	_active_order = null
	_prepare_for_new_player_order()
	stop_movement()


func clear_order_queue() -> void:
	_order_queue.clear()


func get_active_order() -> UnitOrder:
	return _active_order


func get_queued_orders() -> Array[UnitOrder]:
	return _order_queue.duplicate()


func has_queued_orders() -> bool:
	return not _order_queue.is_empty()


func _can_accept_order(order: UnitOrder) -> bool:
	match order.type:
		UnitOrder.Type.ATTACK, UnitOrder.Type.ATTACK_MOVE:
			return supports_combat_orders()
		UnitOrder.Type.HOLD_POSITION:
			return supports_hold_position()
		UnitOrder.Type.PATROL:
			return supports_patrol()
		UnitOrder.Type.BUILD:
			return self is Worker
		UnitOrder.Type.MOVE, UnitOrder.Type.STOP:
			return true
		_:
			return false


func _start_order(order: UnitOrder) -> bool:
	_active_order = order
	_issuing_order = true
	_prepare_for_new_player_order()
	var applied: bool = _apply_order(order)
	_issuing_order = false
	if not applied and order.type != UnitOrder.Type.HOLD_POSITION:
		_active_order = null
		_advance_order_queue()
		return false
	return true


## Override to cancel attack / hold / patrol / gather before a replacement order.
func _prepare_for_new_player_order() -> void:
	pass


func _apply_order(order: UnitOrder) -> bool:
	match order.type:
		UnitOrder.Type.MOVE:
			return set_movement_target(order.destination)
		UnitOrder.Type.ATTACK:
			command_attack(order.target, order.assigned_slot)
			return true
		UnitOrder.Type.ATTACK_MOVE:
			command_attack_move(order.destination)
			return true
		UnitOrder.Type.HOLD_POSITION:
			command_hold_position()
			return true
		UnitOrder.Type.PATROL:
			command_patrol(order.patrol_points)
			return true
		UnitOrder.Type.BUILD:
			if self is Worker and NodeSafety.is_alive_node(order.target) and order.target is Building:
				(self as Worker).start_construction_order(order.target as Building)
				return true
			return false
		_:
			return false


func _advance_order_queue() -> void:
	_active_order = null
	while not _order_queue.is_empty():
		var next_order: UnitOrder = _order_queue.pop_front()
		if next_order == null:
			continue
		if next_order.is_target_order() and not NodeSafety.is_alive_node(next_order.target):
			continue
		if not _can_accept_order(next_order):
			continue
		_start_order(next_order)
		return


## Called when a discrete order finishes (move arrived, attack target gone, etc.).
func notify_order_completed(order_type: UnitOrder.Type) -> void:
	if _active_order == null:
		return
	if _active_order.type != order_type:
		return
	_advance_order_queue()


## Sets a single move target. Player/rally orders apply immediately and replace the queue
## unless issued through the order system (`_issuing_order`).
## Returns true when a real destination update was applied.
func set_movement_target(target: Vector3) -> bool:
	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.move(target)
		_prepare_for_new_player_order()
	return request_movement_target(target, RepathUrgency.PLAYER_ORDER)


## Clears movement and navigation without canceling combat orders.
func clear_move_target() -> void:
	has_move_target = false
	velocity = Vector3.ZERO
	_navigation_active = false
	_clear_navigation_agent()
	_reset_unstuck_state()


## Full stop: clears movement/navigation and the order queue. Combat subclasses also cancel orders.
func stop_movement() -> void:
	if not _issuing_order:
		_order_queue.clear()
		_active_order = null
	clear_move_target()


func _complete_movement_arrival() -> void:
	clear_move_target()
	_on_movement_arrived()


## Override for patrol waypoint cycling / attack-move completion hooks.
func _on_movement_arrived() -> void:
	if _active_order != null and _active_order.type == UnitOrder.Type.MOVE:
		notify_order_completed(UnitOrder.Type.MOVE)


## Request a movement destination with urgency-aware repath cooldowns.
## Returns true only when a real path/destination update was applied.
func request_movement_target(
	target: Vector3,
	urgency: RepathUrgency = RepathUrgency.NORMAL
) -> bool:
	var next_target: Vector3 = Vector3(target.x, global_position.y, target.z)
	_last_requested_destination = next_target
	var now_msec: int = Time.get_ticks_msec()

	var distance_to_new: float = Vector3(
		global_position.x - next_target.x,
		0.0,
		global_position.z - next_target.z
	).length()
	if distance_to_new <= stopping_distance + MOVE_DEST_NEAR_SKIP:
		if has_move_target:
			var current_delta: float = Vector3(
				_movement_target.x - next_target.x,
				0.0,
				_movement_target.z - next_target.z
			).length()
			if current_delta <= MOVE_DEST_TOLERANCE:
				return false
		else:
			return false

	if has_move_target:
		var destination_delta: float = Vector3(
			_movement_target.x - next_target.x,
			0.0,
			_movement_target.z - next_target.z
		).length()
		if urgency != RepathUrgency.STUCK_RECOVERY and urgency != RepathUrgency.PLAYER_ORDER:
			if destination_delta < MOVE_DEST_NEAR_SKIP:
				return false

			if (
				urgency != RepathUrgency.URGENT
				and destination_delta < MOVE_DEST_TOLERANCE
			):
				return false

		if not _can_request_repath(destination_delta, urgency, now_msec):
			return false

	_movement_target = next_target
	has_move_target = true
	_last_issued_move_destination = next_target
	_last_path_request_msec = now_msec
	_last_move_order_msec = now_msec
	_apply_navigation_destination(next_target)
	if urgency == RepathUrgency.STUCK_RECOVERY:
		_stuck_repath_attempted = true
		_stuck_recovery_cooldown = UNSTUCK_RECOVERY_COOLDOWN_SECONDS
		_stuck_time = 0.0
	else:
		_reset_unstuck_state()
	PerfCounters.record_repath_request()
	return true


func get_movement_destination() -> Vector3:
	return _movement_target


func is_confirmed_stuck() -> bool:
	return _is_confirmed_stuck


func uses_navigation_agent() -> bool:
	return _navigation_agent != null and UnitNavigation.can_use(_navigation_agent)


func get_repath_stagger_offset_seconds() -> float:
	return float(abs(get_instance_id()) % 7) * REPATH_STAGGER_OFFSET_SECONDS


func _can_request_repath(
	destination_delta: float,
	urgency: RepathUrgency,
	now_msec: int
) -> bool:
	if urgency == RepathUrgency.PLAYER_ORDER:
		return true

	var cooldown: float = REPATH_COOLDOWN_NORMAL_SECONDS
	match urgency:
		RepathUrgency.FORMATION:
			cooldown = REPATH_COOLDOWN_FORMATION_SECONDS
		RepathUrgency.URGENT:
			cooldown = REPATH_COOLDOWN_URGENT_SECONDS
		RepathUrgency.STUCK_RECOVERY:
			cooldown = REPATH_COOLDOWN_STUCK_SECONDS
		_:
			cooldown = REPATH_COOLDOWN_NORMAL_SECONDS

	# Meaningful destination changes stay responsive even under normal urgency.
	if destination_delta >= MOVE_DEST_TOLERANCE * 4.0 and urgency != RepathUrgency.STUCK_RECOVERY:
		cooldown = minf(cooldown, REPATH_COOLDOWN_URGENT_SECONDS)

	cooldown += get_repath_stagger_offset_seconds()
	var elapsed_sec: float = float(now_msec - _last_path_request_msec) / 1000.0
	if urgency == RepathUrgency.STUCK_RECOVERY:
		return elapsed_sec >= cooldown and _stuck_recovery_cooldown <= 0.0

	return elapsed_sec >= cooldown


## Returns true when a throttled combat target scan is due (auto-attack, engage, retarget).
func tick_combat_target_scan_timer(
	delta: float, interval: float = COMBAT_TARGET_SCAN_INTERVAL
) -> bool:
	_combat_target_scan_timer -= delta
	if _combat_target_scan_timer > 0.0:
		return false

	_combat_target_scan_timer = interval + randf() * COMBAT_TARGET_SCAN_JITTER
	return true


## Lightweight cadence for validating an existing attack target (not full acquisition).
func tick_combat_target_validate_timer(
	delta: float, interval: float = COMBAT_TARGET_VALIDATE_INTERVAL
) -> bool:
	_combat_target_validate_timer -= delta
	if _combat_target_validate_timer > 0.0:
		return false

	_combat_target_validate_timer = interval + randf() * 0.04
	return true


## Bucket index for staggered expensive unit maintenance (0..bucket_count-1).
func get_update_bucket(bucket_count: int = 4) -> int:
	return abs(get_instance_id()) % maxi(1, bucket_count)


## True when this unit should run expensive maintenance on the current process frame.
func should_run_staggered_update(bucket_count: int = 4) -> bool:
	return (Engine.get_process_frames() % maxi(1, bucket_count)) == get_update_bucket(bucket_count)


func _physics_process(delta: float) -> void:
	if _stuck_recovery_cooldown > 0.0:
		_stuck_recovery_cooldown = maxf(0.0, _stuck_recovery_cooldown - delta)

	if not has_move_target:
		_reset_unstuck_state()
		# Soft unpack when idle so armies do not remain permanently stacked.
		if should_run_staggered_update(2):
			UnitSeparation.apply_standing_push(self, move_speed, false)
		else:
			velocity = Vector3.ZERO
		return

	var offset: Vector3 = _movement_target - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= stopping_distance:
		_complete_movement_arrival()
		return

	_update_navigation_path_validity(delta)

	var position_before: Vector3 = global_position
	_previous_position = position_before
	var direction: Vector3 = offset.normalized() if distance > 0.0001 else Vector3.ZERO

	if _detour_active and not _detour_gave_up:
		direction = _get_detour_direction(direction)
		var detour_velocity: Vector3 = direction * move_speed
		# Keep separation gentle during unstuck so narrow corridors do not deadlock.
		velocity = UnitSeparation.blend_desired_velocity(
			self, detour_velocity, move_speed, 0.25
		)
		velocity.y = 0.0
		move_and_slide()
	elif _navigation_active and UnitNavigation.can_use(_navigation_agent):
		var arrived: bool = UnitNavigation.process_movement(
			self,
			_navigation_agent,
			_movement_target,
			move_speed,
			stopping_distance,
			true
		)
		if arrived:
			_complete_movement_arrival()
			return
		var moved: Vector3 = global_position - position_before
		moved.y = 0.0
		if moved.length_squared() > 0.0001:
			direction = moved.normalized()
	else:
		if direction.length_squared() < 0.0001:
			_complete_movement_arrival()
			return
		var direct_velocity: Vector3 = direction * move_speed
		velocity = UnitSeparation.blend_desired_velocity(self, direct_velocity, move_speed)
		velocity.y = 0.0
		move_and_slide()

	_update_unstuck(delta, position_before, direction, distance)


func _process(delta: float) -> void:
	_update_visual_facing(delta)
	_update_visual_animation()


## Override to map gameplay state to idle/move/work loop clips.
func get_visual_loop_state() -> UnitVisualAnimator.LoopState:
	if has_move_target:
		return UnitVisualAnimator.LoopState.MOVE

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() > VISUAL_FACING_VELOCITY_THRESHOLD_SQ:
		return UnitVisualAnimator.LoopState.MOVE

	return UnitVisualAnimator.LoopState.IDLE


## Override to customize imported clip name preferences per unit type.
func _configure_visual_animator(_animator: UnitVisualAnimator) -> void:
	pass


## Override to trigger a one-shot attack clip at the exact gameplay attack moment.
func play_visual_attack_animation() -> bool:
	if _visual_animator == null:
		return false

	return _visual_animator.play_one_shot(UnitVisualAnimator.STATE_ATTACK)


func get_visual_animator() -> UnitVisualAnimator:
	return _visual_animator


## Override in combat units to face an attack target while idle or chasing.
func get_attack_facing_direction() -> Vector3:
	return Vector3.ZERO


func get_facing_direction() -> Vector3:
	var attack_direction: Vector3 = get_attack_facing_direction()
	if attack_direction.length_squared() > 0.001:
		return attack_direction

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() > VISUAL_FACING_VELOCITY_THRESHOLD_SQ:
		return horizontal_velocity.normalized()

	return Vector3.ZERO


func _update_visual_facing(delta: float) -> void:
	if _visual_pivot == null or not is_instance_valid(_visual_pivot):
		_visual_pivot = null
		return

	var direction: Vector3 = get_facing_direction()
	if direction.length_squared() <= 0.001:
		return

	var target_yaw: float = atan2(direction.x, direction.z) + _visual_facing_yaw_offset
	if not _visual_facing_initialized:
		_visual_pivot.rotation.y = target_yaw
		_visual_facing_initialized = true
		return

	var blend: float = minf(1.0, delta * VISUAL_FACING_TURN_SPEED)
	_visual_pivot.rotation.y = lerp_angle(_visual_pivot.rotation.y, target_yaw, blend)


func _setup_visual_animator() -> void:
	if _visual_pivot == null or not is_instance_valid(_visual_pivot):
		_visual_pivot = null
		return

	if _visual_pivot.get_child_count() == 0:
		return

	var model_root_variant: Variant = _visual_pivot.get_child(0)
	if model_root_variant == null or not is_instance_valid(model_root_variant):
		return
	if not model_root_variant is Node:
		return

	_visual_animator = UnitVisualAnimator.create_from_model_root(model_root_variant as Node)
	if _visual_animator == null:
		return

	_configure_visual_animator(_visual_animator)
	_visual_animator.play_initial_idle()


func _update_visual_animation() -> void:
	if _visual_animator == null:
		return

	_visual_animator.set_loop_state(get_visual_loop_state())
	if _visual_animator != null and not _visual_animator.has_animation_player():
		_visual_animator = null


func _detect_visual_facing_yaw_offset() -> float:
	if _visual_pivot == null or not is_instance_valid(_visual_pivot):
		_visual_pivot = null
		return PI

	if _visual_pivot.get_child_count() == 0:
		return PI

	var model_variant: Variant = _visual_pivot.get_child(0)
	if model_variant == null or not is_instance_valid(model_variant):
		return PI
	if not model_variant is Node3D:
		return PI

	var model: Node3D = model_variant as Node3D

	var basis: Basis = model.transform.basis
	if basis.x.x < 0.0 and basis.z.z < 0.0:
		return 0.0

	return PI


func _get_detour_direction(forward: Vector3) -> Vector3:
	var lateral: Vector3 = Vector3(-forward.z, 0.0, forward.x).normalized() * _detour_side
	var blended: Vector3 = lateral + forward * UNSTUCK_LATERAL_FORWARD_BLEND
	if blended.length_squared() < 0.001:
		return lateral

	return blended.normalized()


func _begin_detour(forward: Vector3, distance: float) -> void:
	_detour_active = true
	_detour_side = _choose_detour_side(forward)
	_detour_time = 0.0
	_detour_flips = 0
	_distance_at_detour_start = distance
	_stuck_time = 0.0


func _choose_detour_side(forward: Vector3) -> float:
	var lateral_right: Vector3 = Vector3(-forward.z, 0.0, forward.x).normalized()
	var lateral_left: Vector3 = -lateral_right

	var right_clearance: float = _probe_clearance(lateral_right)
	var left_clearance: float = _probe_clearance(lateral_left)
	if absf(right_clearance - left_clearance) > 0.15:
		if right_clearance >= left_clearance:
			return 1.0
		return -1.0

	if get_slide_collision_count() > 0:
		var collision_normal: Vector3 = get_slide_collision(0).get_normal()
		collision_normal.y = 0.0
		if collision_normal.length_squared() > 0.001:
			collision_normal = collision_normal.normalized()
			if lateral_right.dot(collision_normal) >= lateral_left.dot(collision_normal):
				return -1.0
			return 1.0

	return 1.0


func _probe_clearance(direction: Vector3) -> float:
	var world: World3D = get_world_3d()
	if world == null:
		return 0.0

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var ray_origin: Vector3 = global_position
	var ray_end: Vector3 = ray_origin + direction * UNSTUCK_PROBE_DISTANCE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end
	)
	query.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	query.exclude = [get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return UNSTUCK_PROBE_DISTANCE

	return ray_origin.distance_to(result.position)


func _is_direct_path_clear(forward: Vector3, distance: float) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return false

	var check_distance: float = minf(distance, UNSTUCK_PATH_CHECK_DISTANCE)
	if check_distance <= stopping_distance:
		return true

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var ray_origin: Vector3 = global_position
	var ray_end: Vector3 = ray_origin + forward * check_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end
	)
	query.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	query.exclude = [get_rid()]

	return space_state.intersect_ray(query).is_empty()


func _update_unstuck(
	delta: float, position_before: Vector3, forward: Vector3, distance: float
) -> void:
	var moved: Vector3 = global_position - position_before
	moved.y = 0.0
	var moved_distance: float = moved.length()
	var expected_move: float = move_speed * delta * UNSTUCK_STUCK_MOVE_RATIO
	var hit_obstacle: bool = get_slide_collision_count() > 0
	var making_progress: bool = moved_distance >= expected_move
	var moving_toward_target: bool = making_progress and moved.dot(forward) > 0.0

	if _detour_active:
		_detour_time += delta

		if _is_direct_path_clear(forward, distance) and _detour_time >= UNSTUCK_DETOUR_COMMIT_TIME * 0.5:
			_reset_unstuck_state()
			return

		if moving_toward_target and distance < _distance_at_detour_start - stopping_distance:
			_reset_unstuck_state()
			return

		if _detour_time < UNSTUCK_DETOUR_COMMIT_TIME:
			return

		if _detour_time >= UNSTUCK_DETOUR_MAX_TIME:
			if _detour_flips < UNSTUCK_MAX_SIDE_FLIPS:
				_detour_side *= -1.0
				_detour_flips += 1
				_detour_time = 0.0
				_distance_at_detour_start = distance
			else:
				_detour_gave_up = true
				_detour_active = false
				_stuck_recovery_cooldown = UNSTUCK_RECOVERY_COOLDOWN_SECONDS

		return

	if _detour_gave_up:
		if making_progress:
			_reset_unstuck_state()
		return

	if moving_toward_target or distance <= UNSTUCK_MIN_REMAINING_DISTANCE:
		_stuck_time = 0.0
		_is_confirmed_stuck = false
		return

	if not hit_obstacle and making_progress:
		_stuck_time = 0.0
		_is_confirmed_stuck = false
		return

	if not hit_obstacle and _stuck_time <= 0.0 and making_progress:
		return

	_stuck_time += delta
	if _stuck_time < UNSTUCK_CONFIRM_SECONDS:
		return

	_is_confirmed_stuck = true
	if _stuck_recovery_cooldown > 0.0:
		return

	# First recovery: one controlled repath to the same destination.
	if not _stuck_repath_attempted:
		_stuck_repath_attempted = true
		request_movement_target(_movement_target, RepathUrgency.STUCK_RECOVERY)
		_stuck_recovery_cooldown = UNSTUCK_RECOVERY_COOLDOWN_SECONDS
		_stuck_time = 0.0
		return

	# Second recovery: lateral unstuck nudge, then cooldown.
	if _stuck_time >= UNSTUCK_DETOUR_START_DELAY:
		_begin_detour(forward, distance)


func _reset_unstuck_state() -> void:
	_stuck_time = 0.0
	_is_confirmed_stuck = false
	_detour_active = false
	_detour_side = 1.0
	_detour_time = 0.0
	_detour_flips = 0
	_detour_gave_up = false
	_distance_at_detour_start = 0.0
	_stuck_repath_attempted = false


func _setup_navigation_agent() -> void:
	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_active = false
		return

	UnitNavigation.configure_agent(_navigation_agent, stopping_distance)
	call_deferred("_sync_navigation_agent_position")


func _sync_navigation_agent_position() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if _navigation_agent == null:
		return

	UnitNavigation.clear(_navigation_agent, global_position)


func _apply_navigation_destination(destination: Vector3) -> void:
	if _navigation_agent == null:
		_navigation_active = false
		return

	UnitNavigation.configure_agent(_navigation_agent, stopping_distance)
	if not UnitNavigation.can_use(_navigation_agent):
		_navigation_active = false
		UnitNavigation.apply_destination(_navigation_agent, destination)
		call_deferred("_refresh_navigation_active_state")
		return

	UnitNavigation.apply_destination(_navigation_agent, destination)
	_navigation_active = true
	_path_validity_timer = PATH_VALIDITY_CHECK_INTERVAL
	call_deferred("_refresh_navigation_active_state")


func _refresh_navigation_active_state() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if not has_move_target or _navigation_agent == null:
		_navigation_active = false
		return

	if not UnitNavigation.can_use(_navigation_agent):
		_navigation_active = false
		return

	_navigation_active = _navigation_agent.is_target_reachable()


func _clear_navigation_agent() -> void:
	if _navigation_agent == null:
		return

	UnitNavigation.clear(_navigation_agent, global_position)


func _update_navigation_path_validity(delta: float) -> void:
	if not has_move_target or _navigation_agent == null:
		return

	_path_validity_timer -= delta
	if _path_validity_timer > 0.0:
		return

	_path_validity_timer = PATH_VALIDITY_CHECK_INTERVAL + get_repath_stagger_offset_seconds()
	if not UnitNavigation.can_use(_navigation_agent):
		_navigation_active = false
		return

	if not _navigation_agent.is_target_reachable():
		_navigation_active = false
		return

	_navigation_active = true
	# Force a repath when the agent finished early but destination is still distant.
	var remaining: Vector3 = _movement_target - global_position
	remaining.y = 0.0
	if (
		_navigation_agent.is_navigation_finished()
		and remaining.length() > stopping_distance + MOVE_DEST_TOLERANCE
		and _stuck_recovery_cooldown <= 0.0
	):
		request_movement_target(_movement_target, RepathUrgency.STUCK_RECOVERY)


## Loads runtime state from unit_data when the data pipeline is available.
func _apply_unit_data() -> void:
	# TODO: Read stats from unit_data Resource.
	pass


## Applies damage using values derived from unit_data.
func take_damage(_amount: float, _attacker = null) -> void:
	# TODO: Implement damage handling.
	pass


## Population food reserved by this unit when trained. Neutral/test units return 0.
func get_food_supply_cost() -> int:
	return UnitFoodSupply.get_cost(self)


## Handles unit death and notifies listeners through signals.
func die() -> void:
	_release_reserved_food()
	EnemyArmyCommand.release_reinforcement_from_pool(self)
	NodeSafety.prepare_node_for_death(self)
	died.emit(self)


## Releases reserved population food once. Workers use their own death path instead.
func _release_reserved_food() -> void:
	if _population_food_released:
		return

	# Worker releases food in Worker._on_health_depleted before calling die().
	if self is Worker:
		return

	var food_cost: int = get_food_supply_cost()
	if food_cost <= 0:
		return

	_population_food_released = true
	if CombatTargetValidation.is_enemy_faction(self):
		EnemyResourceManager.release_food_used(food_cost)
	else:
		ResourceManager.release_food_used(food_cost)
