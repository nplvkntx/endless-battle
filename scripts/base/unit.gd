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
## Temporary combat-type defaults (identity multipliers — no balance change yet).
@export var damage_type: DamageService.DamageType = DamageService.DamageType.PHYSICAL
@export var armor_type: DamageService.ArmorType = DamageService.ArmorType.MEDIUM

const UNSTUCK_STUCK_MOVE_RATIO := 0.2
## Stuck only after no meaningful goal-progress for this long (not frame jitter).
const UNSTUCK_CONFIRM_SECONDS := 1.6
const UNSTUCK_DETOUR_START_DELAY := 0.35
const UNSTUCK_DETOUR_COMMIT_TIME := 0.75
const UNSTUCK_DETOUR_MAX_TIME := 2.0
const UNSTUCK_MAX_SIDE_FLIPS := 1
const UNSTUCK_LATERAL_FORWARD_BLEND := 0.12
const UNSTUCK_PROBE_DISTANCE := 2.5
const UNSTUCK_PATH_CHECK_DISTANCE := 3.0
const UNSTUCK_RECOVERY_COOLDOWN_SECONDS := 1.5
## Must still be meaningfully far from the accepted arrival radius.
const UNSTUCK_MIN_REMAINING_DISTANCE := 2.25
## Distance-to-goal must improve by at least this much to count as progress.
const UNSTUCK_PROGRESS_EPSILON := 0.35
const UNSTUCK_WAYPOINT_OFFSET := 2.25
const UNSTUCK_YIELD_SECONDS := 1.1
const UNSTUCK_CANCEL_AFTER_STAGES := 3
const MOVE_DEST_TOLERANCE := 1.0
const MOVE_DEST_NEAR_SKIP := 0.35
const PLAYER_DEST_NEAR_SKIP := 0.25
const REPATH_COOLDOWN_NORMAL_SECONDS := 0.85
const REPATH_COOLDOWN_FORMATION_SECONDS := 1.15
const REPATH_COOLDOWN_CHASE_SECONDS := 1.0
const REPATH_COOLDOWN_URGENT_SECONDS := 0.4
const REPATH_COOLDOWN_STUCK_SECONDS := 0.9
const REPATH_STAGGER_OFFSET_SECONDS := 0.1
const PATH_VALIDITY_CHECK_INTERVAL := 0.7
const CHASE_TARGET_MOVE_THRESHOLD := 1.75
const CHASE_UPDATE_INTERVAL := 0.35
const CHASE_UPDATE_JITTER := 0.25
const COMBAT_TARGET_SCAN_INTERVAL := 0.45
const COMBAT_TARGET_SCAN_JITTER := 0.30
const COMBAT_TARGET_VALIDATE_INTERVAL := 0.12
const VISUAL_FACING_TURN_SPEED := 8.0
const VISUAL_FACING_VELOCITY_THRESHOLD_SQ := 0.09
const VISUAL_FACING_MIN_TURN_DOT := 0.998 # ~3.6deg — ignore tiny facing corrections
const MOVE_VELOCITY_SMOOTH := 14.0
const MOVE_VELOCITY_DEAD_ZONE_SQ := 0.0225 # ~0.15 m/s — kill micro-corrections
## Facing only from meaningful travel velocity / combat facing — never residual push.
const ROTATION_VELOCITY_MIN_SQ := 0.16 # ~0.4 m/s
const ORDER_DEST_EQUIVALENCE := 0.35
## Settle when blocked by world/buildings near the destination instead of sliding forever.
const BLOCKED_ARRIVAL_DISTANCE := 3.75
const BLOCKED_ARRIVAL_CONFIRM_SECONDS := 0.22
## Non-zero acceptance radius — never require exact destination equality.
const ARRIVAL_ACCEPTANCE_RADIUS := 0.65
## Crawl-arrive: stop when nearly at the destination even if still slowly approaching.
const SOFT_ARRIVAL_DISTANCE := 1.0
const SOFT_ARRIVAL_SPEED_SQ := 2.25 # ~1.5 m/s — covers arrival crawl + residual push
## Mute travel separation inside this band so groups can settle.
const ARRIVAL_SEPARATION_MUTE_DISTANCE := 1.35

enum RepathUrgency {
	NORMAL,
	FORMATION,
	CHASE,
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
var _stuck_recovery_stage: int = 0
var _stuck_progress_anchor_distance: float = -1.0
var _crowd_yield_seconds: float = 0.0
var _original_move_destination: Vector3 = Vector3.ZERO
var _combat_target_scan_timer: float = 0.0
var _combat_target_validate_timer: float = 0.0
var _chase_update_timer: float = 0.0
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
var _feedback_tween: Tween
var _smoothed_move_velocity: Vector3 = Vector3.ZERO
var _desired_move_facing: Vector3 = Vector3.ZERO
var _stable_move_facing: Vector3 = Vector3.ZERO
var _blocked_arrival_time: float = 0.0
## Bumped whenever movement starts, changes destination, arrives, or is cancelled.
## Stale NavigationAgent avoidance callbacks must match this generation.
var _movement_generation: int = 0
var _nav_velocity_request_generation: int = -1
var _arrival_completed_generation: int = -1

## Shared player order queue (WC3-style). Non-shift replaces; Shift appends.
var _order_queue: Array[UnitOrder] = []
var _active_order: UnitOrder = null
var _issuing_order: bool = false

## Combat stealth — skipped by auto-targeting; area damage and manual orders still work.
var _combat_hidden: bool = false


func is_combat_hidden() -> bool:
	return _combat_hidden


func set_combat_hidden(hidden: bool) -> void:
	if _combat_hidden == hidden:
		return
	_combat_hidden = hidden
	_apply_stealth_visual(hidden)


func _apply_stealth_visual(hidden: bool) -> void:
	# Friendly always sees the unit; use a soft transparency cue for feedback.
	var pivot: Node3D = _visual_pivot
	if pivot == null:
		pivot = get_node_or_null("MeshInstance3D") as Node3D
	if pivot == null:
		return
	_set_node_albedo_alpha(pivot, 0.45 if hidden else 1.0)


func _set_node_albedo_alpha(node: Node, alpha: float) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface_index: int in mesh_instance.get_surface_override_material_count():
			var mat: Material = mesh_instance.get_surface_override_material(surface_index)
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				std.transparency = (
					BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
				)
				var color: Color = std.albedo_color
				color.a = alpha
				std.albedo_color = color
		if mesh_instance.material_override is StandardMaterial3D:
			var override_mat := mesh_instance.material_override as StandardMaterial3D
			override_mat.transparency = (
				BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
			)
			var override_color: Color = override_mat.albedo_color
			override_color.a = alpha
			override_mat.albedo_color = override_color
	for child: Node in node.get_children():
		_set_node_albedo_alpha(child, alpha)


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
	BuffComponent.ensure_on(self)
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


## Brief pulse used by player attack-command feedback.
func play_target_feedback() -> void:
	var visuals: Node3D = _visual_pivot
	if visuals == null or not is_instance_valid(visuals):
		visuals = get_node_or_null("MeshInstance3D") as Node3D
	if visuals == null:
		return
	_feedback_tween = TargetFeedback.play_on_visuals(self, visuals, _feedback_tween)


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


func command_attack_move(_destination: Vector3, _urgency: RepathUrgency = RepathUrgency.PLAYER_ORDER) -> void:
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
		if _is_duplicate_queued_order(order):
			return true
		if _active_order != null:
			_order_queue.append(order)
			return true
	else:
		if _active_order != null and _active_order.is_equivalent(order, ORDER_DEST_EQUIVALENCE):
			# Equivalent non-shift order: keep current nav/attack/animation state.
			return true
		_order_queue.clear()

	return _start_order(order)


func _is_duplicate_queued_order(order: UnitOrder) -> bool:
	if _active_order != null and _order_queue.is_empty():
		if _active_order.is_equivalent(order, ORDER_DEST_EQUIVALENCE):
			return true
	if not _order_queue.is_empty():
		var last_queued: UnitOrder = _order_queue[_order_queue.size() - 1]
		if last_queued != null and last_queued.is_equivalent(order, ORDER_DEST_EQUIVALENCE):
			return true
	return false


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
			var attack_target: Node3D = order.get_alive_target()
			if attack_target == null:
				return false
			command_attack(attack_target, order.assigned_slot)
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
			var build_target: Node3D = order.get_alive_target()
			if self is Worker and build_target is Building:
				(self as Worker).start_construction_order(build_target as Building)
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
func set_movement_target(target: Vector3, urgency: RepathUrgency = RepathUrgency.PLAYER_ORDER) -> bool:
	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.move(target)
		_prepare_for_new_player_order()
	return request_movement_target(target, urgency)


## Clears movement and navigation without canceling combat orders.
func clear_move_target() -> void:
	if has_move_target or _nav_velocity_request_generation >= 0:
		_invalidate_movement_generation()
	has_move_target = false
	_clear_residual_movement()
	_navigation_active = false
	_set_navigation_avoidance_enabled(false)
	_clear_navigation_agent()
	_reset_unstuck_state()


## Full stop: clears movement/navigation and the order queue. Combat subclasses also cancel orders.
func stop_movement() -> void:
	if not _issuing_order:
		_order_queue.clear()
		_active_order = null
	clear_move_target()


## True when navigation / steered locomotion may apply non-zero velocity.
## Idle, hold, attack-in-range, gather/deposit wait, and arrival must return false.
func is_movement_active() -> bool:
	if not is_inside_tree():
		return false
	if not NodeSafety.is_alive_node(self):
		return false
	return has_move_target


## Non-zero acceptance radius used by arrival, attack-move settle, and stuck gating.
func get_movement_acceptance_radius() -> float:
	return maxf(stopping_distance, ARRIVAL_ACCEPTANCE_RADIUS)


## Soft settle band — slightly wider than hard acceptance so crawl approaches finish once.
func get_soft_arrival_radius() -> float:
	return maxf(SOFT_ARRIVAL_DISTANCE, get_movement_acceptance_radius() * 1.35)


## Separation blend for the current travel frame. Near destination / yield → muted.
func get_move_separation_blend() -> float:
	if not is_movement_active():
		return 0.0
	if _crowd_yield_seconds > 0.0:
		return UnitSeparation.MOVE_BLEND * 0.25
	var remaining: Vector3 = _movement_target - global_position
	remaining.y = 0.0
	if remaining.length() <= ARRIVAL_SEPARATION_MUTE_DISTANCE:
		return 0.0
	return UnitSeparation.MOVE_BLEND


func get_movement_generation() -> int:
	return _movement_generation


func _invalidate_movement_generation() -> void:
	_movement_generation += 1
	_nav_velocity_request_generation = -1


func _begin_movement_generation() -> void:
	_movement_generation += 1
	_arrival_completed_generation = -1
	_nav_velocity_request_generation = _movement_generation


## Authoritative locomotion step: optional separation, velocity smoothing, then move_and_slide.
## Call once per physics frame. Chase repaths must not reset smoothing (they only change destination).
## separation_blend < 0 uses UnitSeparation.MOVE_BLEND; 0 disables separation.
## update_facing=false for standing unpack so residual push does not spin the unit.
## allow_stationary_correction=true only for hard body-overlap peel while idle/attacking.
func apply_steered_velocity(
	desired_velocity: Vector3,
	delta: float = -1.0,
	separation_blend: float = -1.0,
	update_facing: bool = true,
	allow_stationary_correction: bool = false
) -> void:
	if not is_inside_tree() or not NodeSafety.is_alive_node(self):
		velocity = Vector3.ZERO
		_smoothed_move_velocity = Vector3.ZERO
		return

	if not is_movement_active() and not allow_stationary_correction:
		_smoothed_move_velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		return

	if delta < 0.0:
		delta = get_physics_process_delta_time()

	var blend: float = (
		get_move_separation_blend() if separation_blend < 0.0 else separation_blend
	)

	var desired: Vector3 = desired_velocity
	desired.y = 0.0

	if desired.length_squared() <= MOVE_VELOCITY_DEAD_ZONE_SQ:
		_smoothed_move_velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		return

	# Face only meaningful travel direction — never tiny residual / separation noise.
	if update_facing and desired.length_squared() >= ROTATION_VELOCITY_MIN_SQ:
		_desired_move_facing = desired.normalized()
		_update_stable_move_facing(_desired_move_facing)

	var steered: Vector3 = desired
	if blend > 0.0 and is_movement_active():
		steered = UnitSeparation.blend_desired_velocity(
			self, desired, move_speed, blend
		)
		# Ignore microscopic steering deltas so left/right avoidance cannot buzz.
		var steer_delta: Vector3 = steered - desired
		steer_delta.y = 0.0
		if steer_delta.length_squared() < MOVE_VELOCITY_DEAD_ZONE_SQ:
			steered = desired

	# Light smoothing only for tiny corrections; large steering changes apply immediately
	# so corridor peels and gap traversal stay responsive.
	var delta_vel: Vector3 = steered - _smoothed_move_velocity
	if (
		_smoothed_move_velocity.length_squared() < MOVE_VELOCITY_DEAD_ZONE_SQ
		or delta_vel.length_squared() > 0.36
		or steered.length_squared() < MOVE_VELOCITY_DEAD_ZONE_SQ
	):
		_smoothed_move_velocity = steered
	else:
		var smooth: float = minf(1.0, delta * MOVE_VELOCITY_SMOOTH)
		_smoothed_move_velocity = _smoothed_move_velocity.lerp(steered, maxf(smooth, 0.45))
	if _smoothed_move_velocity.length_squared() < MOVE_VELOCITY_DEAD_ZONE_SQ:
		_smoothed_move_velocity = Vector3.ZERO

	velocity = _smoothed_move_velocity
	velocity.y = 0.0
	if velocity.length_squared() < MOVE_VELOCITY_DEAD_ZONE_SQ:
		velocity = Vector3.ZERO
		return

	move_and_slide()


## Stationary halt, plus a tiny peel only when collision bodies truly intersect.
## Soft proximity packing is travel-only (blend_desired_velocity while movement-active).
func apply_standing_separation(combat_mode: bool = false) -> void:
	if is_movement_active():
		return

	var desired: Vector3 = UnitSeparation.compute_standing_desired_velocity(
		self, move_speed, combat_mode
	)
	if desired.length_squared() < MOVE_VELOCITY_DEAD_ZONE_SQ:
		_smoothed_move_velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		return

	apply_steered_velocity(desired, -1.0, 0.0, false, true)


func _clear_residual_movement() -> void:
	velocity = Vector3.ZERO
	_smoothed_move_velocity = Vector3.ZERO
	_desired_move_facing = Vector3.ZERO
	_blocked_arrival_time = 0.0
	UnitSeparation.clear_state(self)
	if has_meta(&"_nav_last_path_point"):
		remove_meta(&"_nav_last_path_point")


func _update_stable_move_facing(desired_dir: Vector3) -> void:
	if desired_dir.length_squared() < 0.0001:
		return
	if _stable_move_facing.length_squared() < 0.0001:
		_stable_move_facing = desired_dir
		return
	# Ignore negligible direction changes to prevent facing oscillation.
	if _stable_move_facing.dot(desired_dir) >= VISUAL_FACING_MIN_TURN_DOT:
		return
	_stable_move_facing = desired_dir


func _complete_movement_arrival() -> void:
	if not has_move_target:
		return

	# Recovery waypoint reached — resume the original order destination instead of stopping.
	if (
		_stuck_recovery_stage >= 2
		and _original_move_destination.length_squared() > 0.0001
	):
		var to_original: Vector3 = _original_move_destination - global_position
		to_original.y = 0.0
		if to_original.length() > get_soft_arrival_radius():
			var resume: Vector3 = _original_move_destination
			_stuck_recovery_stage = 3
			_stuck_progress_anchor_distance = -1.0
			_stuck_recovery_cooldown = 0.0
			_crowd_yield_seconds = maxf(_crowd_yield_seconds, UNSTUCK_YIELD_SECONDS * 0.5)
			if not request_movement_target(resume, RepathUrgency.STUCK_RECOVERY):
				_begin_movement_generation()
				_movement_target = resume
				_original_move_destination = resume
				has_move_target = true
				_apply_navigation_destination(resume)
			return

	# Complete once per movement generation — never re-fire every settle frame.
	if _arrival_completed_generation == _movement_generation:
		clear_move_target()
		return
	_arrival_completed_generation = _movement_generation
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
	var near_skip: float = (
		PLAYER_DEST_NEAR_SKIP
		if urgency == RepathUrgency.PLAYER_ORDER
		else MOVE_DEST_NEAR_SKIP
	)
	if distance_to_new <= stopping_distance + near_skip:
		if has_move_target:
			var current_delta: float = Vector3(
				_movement_target.x - next_target.x,
				0.0,
				_movement_target.z - next_target.z
			).length()
			if current_delta <= _destination_change_threshold(urgency):
				return false
		else:
			return false

	if has_move_target:
		var destination_delta: float = Vector3(
			_movement_target.x - next_target.x,
			0.0,
			_movement_target.z - next_target.z
		).length()
		# Always skip effectively-equal destinations (including player/AI re-clicks).
		if destination_delta < near_skip and urgency != RepathUrgency.STUCK_RECOVERY:
			return false

		if urgency != RepathUrgency.STUCK_RECOVERY and urgency != RepathUrgency.PLAYER_ORDER:
			if destination_delta < _destination_change_threshold(urgency):
				return false

		if not _can_request_repath(destination_delta, urgency, now_msec):
			return false

	# Enemy AI soft-avoids visible hostile bear traps when possible.
	if CombatTargetValidation.is_enemy_faction(self):
		next_target = BearTrap.adjust_destination_away_from_traps(self, next_target)

	var began_moving: bool = not has_move_target
	_begin_movement_generation()
	_movement_target = next_target
	_original_move_destination = next_target
	has_move_target = true
	_last_issued_move_destination = next_target
	_last_path_request_msec = now_msec
	_last_move_order_msec = now_msec
	_apply_navigation_destination(next_target)
	if urgency == RepathUrgency.STUCK_RECOVERY:
		_stuck_repath_attempted = true
		_stuck_recovery_cooldown = UNSTUCK_RECOVERY_COOLDOWN_SECONDS
		_stuck_time = 0.0
		_stuck_progress_anchor_distance = -1.0
	else:
		_reset_unstuck_state()
	if began_moving:
		CommandFeedback.notify_movement_started(self)
	return true


func _destination_change_threshold(urgency: RepathUrgency) -> float:
	match urgency:
		RepathUrgency.PLAYER_ORDER:
			return PLAYER_DEST_NEAR_SKIP
		RepathUrgency.CHASE:
			return CHASE_TARGET_MOVE_THRESHOLD
		RepathUrgency.FORMATION:
			return MOVE_DEST_TOLERANCE * 1.5
		RepathUrgency.URGENT:
			return MOVE_DEST_NEAR_SKIP
		_:
			return MOVE_DEST_TOLERANCE


func get_movement_destination() -> Vector3:
	return _movement_target


func is_confirmed_stuck() -> bool:
	return _is_confirmed_stuck


func uses_navigation_agent() -> bool:
	return _navigation_agent != null and UnitNavigation.can_use(_navigation_agent)


func get_repath_stagger_offset_seconds() -> float:
	return float(abs(get_instance_id()) % 11) * REPATH_STAGGER_OFFSET_SECONDS


func get_chase_update_bucket_offset() -> float:
	return float(abs(get_instance_id()) % 13) * (CHASE_UPDATE_JITTER / 4.0)


## Stagger moving-target chase updates across units so armies do not repath together.
func tick_chase_update_timer(delta: float, force: bool = false) -> bool:
	if force:
		_chase_update_timer = 0.0
		return true

	_chase_update_timer -= delta
	if _chase_update_timer > 0.0:
		return false

	_chase_update_timer = (
		CHASE_UPDATE_INTERVAL
		+ get_chase_update_bucket_offset()
		+ randf() * CHASE_UPDATE_JITTER
	)
	return true


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
		RepathUrgency.CHASE:
			cooldown = REPATH_COOLDOWN_CHASE_SECONDS
		RepathUrgency.URGENT:
			cooldown = REPATH_COOLDOWN_URGENT_SECONDS
		RepathUrgency.STUCK_RECOVERY:
			cooldown = REPATH_COOLDOWN_STUCK_SECONDS
		_:
			cooldown = REPATH_COOLDOWN_NORMAL_SECONDS

	# Meaningful destination changes stay responsive even under normal urgency.
	if (
		destination_delta >= MOVE_DEST_TOLERANCE * 4.0
		and urgency != RepathUrgency.STUCK_RECOVERY
		and urgency != RepathUrgency.CHASE
	):
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
	if _crowd_yield_seconds > 0.0:
		_crowd_yield_seconds = maxf(0.0, _crowd_yield_seconds - delta)

	# Root / stun from the Buff system freezes locomotion without clearing orders.
	if not BuffService.can_move(self):
		_clear_residual_movement()
		return

	if not has_move_target:
		_reset_unstuck_state()
		_blocked_arrival_time = 0.0
		# Hard body-intersection peel only — nearby idle units must not soft-slide.
		apply_standing_separation(false)
		return

	var offset: Vector3 = _movement_target - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var arrive_distance: float = get_movement_acceptance_radius()
	if distance <= arrive_distance:
		_complete_movement_arrival()
		return

	_update_navigation_path_validity(delta)

	var position_before: Vector3 = global_position
	_previous_position = position_before
	var direction: Vector3 = offset.normalized() if distance > 0.0001 else Vector3.ZERO
	var separation_blend: float = get_move_separation_blend()

	if _detour_active and not _detour_gave_up:
		direction = _get_detour_direction(direction)
		var detour_velocity: Vector3 = direction * move_speed
		# Keep separation gentle during unstuck so narrow corridors do not deadlock.
		apply_steered_velocity(detour_velocity, delta, minf(separation_blend, 0.12))
	elif _navigation_active and UnitNavigation.can_use(_navigation_agent):
		var arrived: bool = UnitNavigation.process_movement(
			self,
			_navigation_agent,
			_movement_target,
			move_speed,
			stopping_distance,
			separation_blend > 0.0
		)
		if arrived:
			_complete_movement_arrival()
			return
		if _desired_move_facing.length_squared() > 0.0001:
			direction = _desired_move_facing
	else:
		if direction.length_squared() < 0.0001:
			_complete_movement_arrival()
			return
		var arrival_speed: float = move_speed
		var slow_start: float = maxf(stopping_distance * 2.0, UnitNavigation.ARRIVAL_SLOWDOWN_DISTANCE)
		if distance < slow_start:
			var t: float = clampf(
				(distance - stopping_distance) / maxf(0.001, slow_start - stopping_distance),
				0.0,
				1.0
			)
			arrival_speed = move_speed * lerpf(UnitNavigation.ARRIVAL_MIN_SPEED_RATIO, 1.0, t)
		apply_steered_velocity(direction * arrival_speed, delta, separation_blend)

	if _try_complete_blocked_arrival(delta, position_before, direction, distance):
		return

	# Crawl settle: units that slow-walk forever at ~0.3–0.6m must stop cleanly.
	if _try_complete_soft_arrival():
		return

	_update_unstuck(delta, position_before, direction, distance)
	CommandFeedback.notify_unit_moving(self)


func _process(delta: float) -> void:
	_update_visual_facing(delta)
	_update_visual_animation()


## Override to map gameplay state to idle/move/work loop clips.
func get_visual_loop_state() -> UnitVisualAnimator.LoopState:
	# Standing separation must not flip walk/idle every frame.
	if has_move_target:
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

	# Prefer stable path facing over post-separation velocity to avoid wobble.
	if has_move_target and _stable_move_facing.length_squared() > 0.001:
		return _stable_move_facing

	# Stationary / unpacking units keep their last visual yaw — do not rotate from push velocity.
	return Vector3.ZERO


func _update_visual_facing(delta: float) -> void:
	if _visual_pivot == null or not is_instance_valid(_visual_pivot):
		_visual_pivot = null
		return

	var direction: Vector3 = get_facing_direction()
	if direction.length_squared() <= 0.001:
		# Do not rotate stationary units continuously from residual steering.
		return

	var target_yaw: float = atan2(direction.x, direction.z) + _visual_facing_yaw_offset
	if not _visual_facing_initialized:
		_visual_pivot.rotation.y = target_yaw
		_visual_facing_initialized = true
		return

	var current_yaw: float = _visual_pivot.rotation.y
	var yaw_delta: float = absf(angle_difference(current_yaw, target_yaw))
	if yaw_delta < 0.04:
		return

	var blend: float = minf(1.0, delta * VISUAL_FACING_TURN_SPEED)
	_visual_pivot.rotation.y = lerp_angle(current_yaw, target_yaw, blend)


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


## When pressed against a building/world collider near the destination, settle instead of
## oscillating between path desire and collision slide (classic Town Hall jitter).
func _try_complete_blocked_arrival(
	delta: float, position_before: Vector3, forward: Vector3, distance: float
) -> bool:
	if distance > maxf(BLOCKED_ARRIVAL_DISTANCE, stopping_distance * 4.0):
		_blocked_arrival_time = 0.0
		return false

	var moved: Vector3 = global_position - position_before
	moved.y = 0.0
	var expected_move: float = move_speed * delta * UNSTUCK_STUCK_MOVE_RATIO
	var hit_obstacle: bool = get_slide_collision_count() > 0
	if not hit_obstacle or moved.length() >= expected_move:
		_blocked_arrival_time = 0.0
		return false

	var blocked_toward_goal: bool = false
	if forward.length_squared() > 0.0001:
		var goal_dir: Vector3 = forward.normalized()
		for index: int in get_slide_collision_count():
			var collision: KinematicCollision3D = get_slide_collision(index)
			var normal: Vector3 = collision.get_normal()
			normal.y = 0.0
			if normal.length_squared() < 0.0001:
				continue
			if normal.normalized().dot(goal_dir) < -0.15:
				blocked_toward_goal = true
				break
	else:
		blocked_toward_goal = true

	if not blocked_toward_goal:
		_blocked_arrival_time = 0.0
		return false

	_blocked_arrival_time += delta
	if _blocked_arrival_time < BLOCKED_ARRIVAL_CONFIRM_SECONDS:
		return false

	_blocked_arrival_time = 0.0
	_complete_movement_arrival()
	return true


func _try_complete_soft_arrival() -> bool:
	if not has_move_target:
		return false

	var remaining: Vector3 = _movement_target - global_position
	remaining.y = 0.0
	if remaining.length() > get_soft_arrival_radius():
		return false

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() > SOFT_ARRIVAL_SPEED_SQ:
		return false

	_complete_movement_arrival()
	return true


## Override to suppress stuck recovery while attacking / gathering / holding / waiting.
func _should_skip_stuck_recovery() -> bool:
	return false


func _update_unstuck(
	delta: float, _position_before: Vector3, forward: Vector3, distance: float
) -> void:
	if _should_skip_stuck_recovery():
		_stuck_time = 0.0
		_is_confirmed_stuck = false
		return

	var accept: float = get_movement_acceptance_radius()
	# Already arrived / settling — never stuck.
	if distance <= maxf(UNSTUCK_MIN_REMAINING_DISTANCE, accept * 2.5):
		_stuck_time = 0.0
		_is_confirmed_stuck = false
		return

	if _detour_active:
		_detour_time += delta

		if _is_direct_path_clear(forward, distance) and _detour_time >= UNSTUCK_DETOUR_COMMIT_TIME * 0.5:
			_reset_unstuck_state()
			return

		if distance < _distance_at_detour_start - UNSTUCK_PROGRESS_EPSILON:
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
				_advance_stuck_recovery(distance)

		return

	if _detour_gave_up:
		# After detour, fall through to staged recovery rather than looping forever.
		if _stuck_progress_anchor_distance < 0.0:
			_stuck_progress_anchor_distance = distance
		if distance <= _stuck_progress_anchor_distance - UNSTUCK_PROGRESS_EPSILON:
			_reset_unstuck_state()
			return

	# Meaningful progress = closing on the destination, not raw frame displacement.
	if _stuck_progress_anchor_distance < 0.0:
		_stuck_progress_anchor_distance = distance

	if distance <= _stuck_progress_anchor_distance - UNSTUCK_PROGRESS_EPSILON:
		_stuck_progress_anchor_distance = distance
		_stuck_time = 0.0
		_is_confirmed_stuck = false
		return

	_stuck_time += delta
	if _stuck_time < UNSTUCK_CONFIRM_SECONDS:
		return

	_is_confirmed_stuck = true
	if _stuck_recovery_cooldown > 0.0:
		return

	_advance_stuck_recovery(distance)


## Staged recovery: repath → nearby waypoint → yield crowd → resume → cancel last.
func _advance_stuck_recovery(distance: float) -> void:
	_stuck_recovery_cooldown = UNSTUCK_RECOVERY_COOLDOWN_SECONDS
	_stuck_time = 0.0
	_stuck_progress_anchor_distance = distance

	match _stuck_recovery_stage:
		0:
			# Stage 1: refresh path once to the original destination.
			_stuck_recovery_stage = 1
			_stuck_repath_attempted = true
			var resume_target: Vector3 = (
				_original_move_destination
				if _original_move_destination.length_squared() > 0.0001
				else _movement_target
			)
			request_movement_target(resume_target, RepathUrgency.STUCK_RECOVERY)
		1:
			# Stage 2: nearby reachable waypoint, then continue to original goal.
			_stuck_recovery_stage = 2
			var waypoint: Vector3 = _compute_stuck_recovery_waypoint(distance)
			request_movement_target(waypoint, RepathUrgency.STUCK_RECOVERY)
		2:
			# Stage 3: temporarily yield / reduce crowd pressure, keep destination.
			_stuck_recovery_stage = 3
			_crowd_yield_seconds = UNSTUCK_YIELD_SECONDS
			var detour_forward: Vector3 = _movement_target - global_position
			detour_forward.y = 0.0
			if detour_forward.length_squared() > 0.0001:
				_begin_detour(detour_forward.normalized(), distance)
		_:
			# Stage 4+: cancel only as final fallback — never teleport.
			_stuck_recovery_stage = 0
			_original_move_destination = Vector3.ZERO
			if _arrival_completed_generation == _movement_generation:
				clear_move_target()
			else:
				_arrival_completed_generation = _movement_generation
				clear_move_target()
				_on_movement_arrived()


func _compute_stuck_recovery_waypoint(distance: float) -> Vector3:
	var goal: Vector3 = (
		_original_move_destination
		if _original_move_destination.length_squared() > 0.0001
		else _movement_target
	)
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.0001:
		return goal

	var forward: Vector3 = to_goal.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var side: float = _detour_side if _detour_side != 0.0 else 1.0
	var offset_distance: float = minf(UNSTUCK_WAYPOINT_OFFSET, maxf(distance * 0.35, 1.25))
	var min_clearance: float = offset_distance * 0.8

	var candidate: Vector3 = (
		global_position + forward * (offset_distance * 0.55) + right * (side * offset_distance)
	)
	candidate.y = global_position.y
	var probe_dir: Vector3 = candidate - global_position
	probe_dir.y = 0.0
	if probe_dir.length_squared() > 0.0001 and _probe_clearance(probe_dir.normalized()) >= min_clearance:
		return candidate

	candidate = (
		global_position + forward * (offset_distance * 0.55) - right * (side * offset_distance)
	)
	candidate.y = global_position.y
	probe_dir = candidate - global_position
	probe_dir.y = 0.0
	if probe_dir.length_squared() > 0.0001 and _probe_clearance(probe_dir.normalized()) >= min_clearance:
		return candidate

	# Fall back: short step toward the goal.
	return global_position + forward * offset_distance * 0.75


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
	_stuck_recovery_stage = 0
	_stuck_progress_anchor_distance = -1.0
	_blocked_arrival_time = 0.0
	# Keep _crowd_yield_seconds ticking — do not clear mid-yield.


func _setup_navigation_agent() -> void:
	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_active = false
		return

	UnitNavigation.configure_agent(_navigation_agent, stopping_distance)
	_set_navigation_avoidance_enabled(false)
	if not _navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		_navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)
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
	# Keep RVO off — manual UnitSeparation handles moving units only.
	_set_navigation_avoidance_enabled(false)
	if not UnitNavigation.can_use(_navigation_agent):
		_navigation_active = false
		UnitNavigation.apply_destination(_navigation_agent, destination)
		call_deferred("_refresh_navigation_active_state")
		return

	UnitNavigation.apply_destination(_navigation_agent, destination)
	_navigation_active = true
	_path_validity_timer = PATH_VALIDITY_CHECK_INTERVAL
	_nav_velocity_request_generation = _movement_generation
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

	_set_navigation_avoidance_enabled(false)
	UnitNavigation.clear(_navigation_agent, global_position)


func _set_navigation_avoidance_enabled(enabled: bool) -> void:
	if _navigation_agent == null or not is_instance_valid(_navigation_agent):
		return
	_navigation_agent.avoidance_enabled = enabled
	if not enabled and _navigation_agent.has_method("set_velocity_forced"):
		_navigation_agent.set_velocity_forced(Vector3.ZERO)


## Guard for delayed NavigationAgent avoidance callbacks.
## Even with avoidance disabled, a stale safe-velocity must never restart idle motion.
func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	if not is_movement_active():
		_reject_navigation_velocity()
		return
	if _nav_velocity_request_generation != _movement_generation:
		_reject_navigation_velocity()
		return
	if _navigation_agent == null or not is_instance_valid(_navigation_agent):
		_reject_navigation_velocity()
		return
	if _navigation_agent.is_navigation_finished():
		_reject_navigation_velocity()
		return

	var remaining: Vector3 = _movement_target - global_position
	remaining.y = 0.0
	var arrive_distance: float = maxf(stopping_distance, 0.5)
	if remaining.length() <= arrive_distance:
		_reject_navigation_velocity()
		return

	var horizontal: Vector3 = Vector3(safe_velocity.x, 0.0, safe_velocity.z)
	if horizontal.length_squared() < ROTATION_VELOCITY_MIN_SQ:
		_reject_navigation_velocity()
		return

	# Avoidance is intentionally disabled project-wide; if re-enabled later, still
	# route through the authoritative steered path with generation checks above.
	apply_steered_velocity(horizontal, -1.0, 0.0, true)


func _reject_navigation_velocity() -> void:
	_smoothed_move_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		if _navigation_agent.has_method("set_velocity_forced"):
			_navigation_agent.set_velocity_forced(Vector3.ZERO)


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


## Applies damage through the shared combat pipeline.
func take_damage(amount: float, attacker = null) -> void:
	DamageService.apply(
		self,
		amount,
		attacker,
		{DamageService.OPT_IGNORE_HOSTILITY: true}
	)


## Buff-framework hook for DamageService. Identity when no damage-dealt buffs.
func modify_outgoing_damage(amount: float, _target: Object, _damage_type: int) -> float:
	var buffs: BuffComponent = BuffComponent.find_on(self)
	if buffs == null:
		return amount
	return buffs.modify_outgoing_damage(amount)


## Buff-framework hook for DamageService. Identity when no damage-taken buffs.
func modify_incoming_damage(amount: float, _attacker: Object, _damage_type: int) -> float:
	var buffs: BuffComponent = BuffComponent.find_on(self)
	if buffs == null:
		return amount
	return buffs.modify_incoming_damage(amount)


## Buff-framework invulnerability. Divine Protection still uses its own check first.
func is_damage_immune() -> bool:
	var buffs: BuffComponent = BuffComponent.find_on(self)
	return buffs != null and buffs.is_invulnerable()


## Population food reserved by this unit when trained. Neutral/test units return 0.
func get_food_supply_cost() -> int:
	return UnitFoodSupply.get_cost(self)


## Handles unit death and notifies listeners through signals.
func die() -> void:
	BuffService.remove_all(self)
	_release_reserved_food()
	EnemyArmyCommand.release_reinforcement_from_pool(self)
	DeathEffects.play_unit_death(self)
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
