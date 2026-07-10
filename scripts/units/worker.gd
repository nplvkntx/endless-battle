class_name Worker
extends Unit

## Placeholder worker unit used for early 3D scene testing.

enum GatherTripState {
	IDLE,
	TO_SOURCE,
	GATHER_WAIT,
	TO_COMMAND_CENTER,
	DONE,
}

enum BuildTripState {
	IDLE,
	TO_BUILDING,
	CONSTRUCTION_WAIT,
	DONE,
}

const HEALTH_BAR_WIDTH := 1.0
const HEALTH_BAR_HUE_GREEN := 0.333333
const FOOD_SUPPLY_USED: int = 1
const CONSTRUCTION_STUCK_RECOVERY_DELAY: float = 2.0
const CONSTRUCTION_STUCK_RECOVERY_COOLDOWN: float = 0.75
const CONSTRUCTION_REPATH_COOLDOWN: float = 1.25
const BUILD_START_RANGE: float = 0.5
## Imported GLTF root (CharacterArmature): parent of skeleton bones + skinned mesh.
const WORKER_ARMATURE_PATH: NodePath = ^"MeshInstance3D/WorkerModel"
const DEBUG_AI_WORKER_GATHER: bool = false

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill
@onready var _navigation_agent: NavigationAgent3D = (
	get_node_or_null("NavigationAgent3D") as NavigationAgent3D
)

var _health_bar_fill_material: StandardMaterial3D
var _gather_state: GatherTripState = GatherTripState.IDLE
var _gather_source: GatherableResource = null
var _assigned_resource_id: StringName = &""
var _carried_amount: int = 0
var _source_approach_candidate_index: int = 0
var _dropoff_candidate_index: int = 0
var _assigned_dropoff: CommandCenter = null
var _return_dropoff: CommandCenter = null
var _build_approach_candidate_index: int = 0
var _build_trip_state: BuildTripState = BuildTripState.IDLE
var _building_target: Building = null
var _wall_build_job: WallBuildJob = null
var _task_movement_destination: Vector3 = Vector3.ZERO
var _task_has_saved_destination: bool = false
var _task_stuck_time: float = 0.0
var _task_repath_stuck_time: float = 0.0
var _task_nudge_active: bool = false
var _task_nudge_time: float = 0.0
var _task_nudge_direction: Vector3 = Vector3.ZERO
var _task_nudge_start_position: Vector3 = Vector3.ZERO
var _task_nudge_side_sign: float = 1.0
var _task_nudge_side_attempts: int = 0
var _task_navigation_active: bool = false
var _gather_stuck_watch_position: Vector3 = Vector3.ZERO
var _gather_stuck_watch_time: float = 0.0
var _gather_stuck_recovery_cooldown: float = 0.0
var _construction_stuck_watch_position: Vector3 = Vector3.ZERO
var _construction_stuck_watch_time: float = 0.0
var _construction_stuck_recovery_cooldown: float = 0.0
var _construction_target_point: Vector3 = Vector3.ZERO
var _construction_target_point_valid: bool = false
var _construction_repath_cooldown: float = 0.0
var _wood_chop_spot: Vector3 = Vector3.ZERO
var _wood_chop_spot_valid: bool = false
var _locked_wood_tree: WoodTree = null
var _pinned_starting_gold_mine: GoldMine = null
var _work_armature_flip_active: bool = false
var _last_gather_command_source: StringName = &""
var _ai_unstuck_active: bool = false
var _ai_unstuck_target: Vector3 = Vector3.ZERO
var _ai_unstuck_time: float = 0.0
var _ai_unstuck_watch_position: Vector3 = Vector3.ZERO
var _ai_unstuck_watch_time: float = 0.0
var _ai_unstuck_cooldown: float = 0.0
var _ai_unstuck_direction_offset: int = 0
var _ai_unstuck_attempt_number: int = 0
var _ai_unstuck_pending_stagger: float = 0.0
var _ai_unstuck_stuck_location: Vector3 = Vector3.ZERO
var _ai_unstuck_last_stuck_location: Vector3 = Vector3.ZERO
var _ai_unstuck_last_finish_time: float = -INF
var _ai_unstuck_internal_move: bool = false
var _ai_unstuck_saved_gather_state: GatherTripState = GatherTripState.IDLE
var _ai_unstuck_saved_build_state: BuildTripState = BuildTripState.IDLE
var _ai_unstuck_saved_source_index: int = 0
var _ai_unstuck_saved_dropoff_index: int = 0
var _ai_unstuck_saved_build_index: int = 0


func _ready() -> void:
	super._ready()
	_hide_worker_weapon_visual()
	_health_bar_fill_material = HealthBarDisplay.duplicate_mesh_material(_health_bar_fill)
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)
	_configure_faction_groups()
	_configure_task_navigation_agent()
	if _is_enemy_worker():
		call_deferred("_notify_enemy_worker_needs_gather_job")
	call_deferred("_hide_worker_team_accent_marker")


func apply_team_visuals() -> void:
	super.apply_team_visuals()
	_hide_worker_team_accent_marker()


func _hide_worker_team_accent_marker() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	var accent_marker := get_node_or_null("TeamAccentMarker") as MeshInstance3D
	if accent_marker != null:
		accent_marker.visible = false


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


func _get_health_bar_color(ratio: float) -> Color:
	return Color.from_hsv(ratio * HEALTH_BAR_HUE_GREEN, 0.85, 0.9)


func get_visual_loop_state() -> UnitVisualAnimator.LoopState:
	if _build_trip_state == BuildTripState.CONSTRUCTION_WAIT:
		if _visual_animator != null and _visual_animator.has_clip_for_state(UnitVisualAnimator.STATE_WORK):
			return UnitVisualAnimator.LoopState.WORK
		return UnitVisualAnimator.LoopState.IDLE

	if _gather_state == GatherTripState.GATHER_WAIT:
		if _visual_animator != null and _visual_animator.has_clip_for_state(UnitVisualAnimator.STATE_WORK):
			return UnitVisualAnimator.LoopState.WORK
		return UnitVisualAnimator.LoopState.IDLE

	if _task_nudge_active or (
		_is_enemy_worker() and WorkerAiUnstuck.blocks_external_commands(self)
	):
		return UnitVisualAnimator.LoopState.MOVE

	if _is_on_task_movement() and has_move_target:
		return UnitVisualAnimator.LoopState.MOVE

	if has_move_target:
		return UnitVisualAnimator.LoopState.MOVE

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() > VISUAL_FACING_VELOCITY_THRESHOLD_SQ:
		return UnitVisualAnimator.LoopState.MOVE

	return UnitVisualAnimator.LoopState.IDLE


func _configure_visual_animator(animator: UnitVisualAnimator) -> void:
	animator.set_clip_preferences({
		UnitVisualAnimator.STATE_IDLE: [&"Idle"],
		UnitVisualAnimator.STATE_MOVE: [&"Walk", &"Run"],
		UnitVisualAnimator.STATE_WORK: [&"PickUp"],
	})


func _is_playing_work_animation() -> bool:
	return get_visual_loop_state() == UnitVisualAnimator.LoopState.WORK


func _get_work_facing_target() -> Node3D:
	if _build_trip_state == BuildTripState.CONSTRUCTION_WAIT:
		return _building_target
	if _gather_state == GatherTripState.GATHER_WAIT:
		return _get_valid_gather_source() as Node3D
	return null


func face_work_target(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return

	var target_position: Vector3 = target.global_position
	target_position.y = global_position.y
	look_at(target_position, Vector3.UP)

	if _visual_pivot != null and is_instance_valid(_visual_pivot):
		_visual_pivot.rotation_degrees.y = 0.0


func set_work_armature_flip(enabled: bool) -> void:
	var armature: Node3D = get_node_or_null(WORKER_ARMATURE_PATH) as Node3D
	if armature == null:
		return

	armature.rotation_degrees.y = 180.0 if enabled else 0.0
	_work_armature_flip_active = enabled


func _clear_work_facing() -> void:
	rotation.y = 0.0
	set_work_armature_flip(false)
	_visual_facing_initialized = false


func _update_work_facing() -> void:
	if not _is_playing_work_animation():
		if _work_armature_flip_active or absf(rotation.y) > 0.001:
			_clear_work_facing()
		return

	face_work_target(_get_work_facing_target())
	set_work_armature_flip(true)


func _process(delta: float) -> void:
	_update_work_facing()
	super._process(delta)


func _update_visual_facing(delta: float) -> void:
	if _is_playing_work_animation():
		return

	super._update_visual_facing(delta)


func _hide_worker_weapon_visual() -> void:
	if _visual_pivot == null or not is_instance_valid(_visual_pivot):
		_visual_pivot = null
		return

	for weapon_name: StringName in [&"Warrior_Sword", &"Weapon.R"]:
		var weapon_variant: Variant = _visual_pivot.find_child(weapon_name, true, false)
		if weapon_variant == null or not is_instance_valid(weapon_variant):
			continue
		if weapon_variant is Node3D:
			(weapon_variant as Node3D).visible = false


func _is_alive() -> bool:
	return (
		_health_component != null
		and is_instance_valid(_health_component)
		and _health_component.current_health > 0
	)


func take_damage(amount: float, attacker = null) -> void:
	if not _is_alive():
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(self, attacker)

	var damage_amount := int(amount)
	_health_component.take_damage(damage_amount)
	FloatingDamageNumber.spawn(self, damage_amount)


func get_current_health() -> int:
	if _health_component == null:
		return 0

	return _health_component.current_health


func _on_health_depleted() -> void:
	_cancel_build_trip()
	cancel_gathering()
	EnemyUnitMission.clear_unit_mission(self)
	has_move_target = false
	velocity = Vector3.ZERO
	_health_bar.visible = false

	if _is_enemy_worker():
		EnemyResourceManager.release_food_used(FOOD_SUPPLY_USED)
	else:
		ResourceManager.release_food_used(FOOD_SUPPLY_USED)

	HeroXpRewards.notify_unit_killed(self)
	die()
	queue_free()


func _exit_tree() -> void:
	_cancel_build_trip()
	cancel_gathering()
	EnemyUnitMission.clear_unit_mission(self)


func _sanitize_stored_targets() -> void:
	if not NodeSafety.is_alive_node(_gather_source):
		_gather_source = null

	if not NodeSafety.is_alive_node(_building_target):
		if _wall_build_job != null:
			var job: WallBuildJob = _wall_build_job
			var lost_segment: Building = _building_target
			_cancel_build_trip(false)
			job.on_worker_segment_lost(self, lost_segment)
		else:
			_cancel_build_trip()

	if not NodeSafety.is_alive_node(_locked_wood_tree):
		_locked_wood_tree = null

	if not NodeSafety.is_alive_node(_pinned_starting_gold_mine):
		_pinned_starting_gold_mine = null

	if not NodeSafety.is_alive_node(_assigned_dropoff):
		_assigned_dropoff = null

	if not NodeSafety.is_alive_node(_return_dropoff):
		_return_dropoff = null


func _cancel_build_trip(clear_wall_job: bool = true) -> void:
	if clear_wall_job and _wall_build_job != null:
		var job: WallBuildJob = _wall_build_job
		_wall_build_job = null
		job.on_worker_left(self)

	if _building_target != null and is_instance_valid(_building_target):
		_building_target.unregister_builder(self)

	_build_trip_state = BuildTripState.IDLE
	_building_target = null
	_build_approach_candidate_index = 0
	_task_has_saved_destination = false
	_construction_target_point_valid = false
	_construction_stuck_recovery_cooldown = 0.0
	_construction_repath_cooldown = 0.0
	_reset_construction_stuck_watch()
	_disable_task_navigation()
	_reset_task_corner_nudge()
	_reset_ai_unstuck_state()


func _configure_faction_groups() -> void:
	if not is_in_group(&"enemy_workers"):
		return

	if team_id < 0:
		team_id = CommandCenter.ENEMY_TEAM_ID

	if is_in_group(&"workers"):
		remove_from_group(&"workers")

	if is_in_group(&"units"):
		remove_from_group(&"units")

	if not is_in_group(&"enemies"):
		add_to_group(&"enemies")


func _physics_process(delta: float) -> void:
	if not _is_alive():
		return

	_sanitize_stored_targets()

	if _build_trip_state == BuildTripState.CONSTRUCTION_WAIT:
		velocity = Vector3.ZERO
		has_move_target = false
		_disable_task_navigation()
		if not _validate_construction_session():
			return
		return

	if _gather_state == GatherTripState.GATHER_WAIT and _is_gathering_wood():
		velocity = Vector3.ZERO
		has_move_target = false
		_disable_task_navigation()
		_update_gather_trip()
		_update_build_trip()
		return

	if _construction_repath_cooldown > 0.0:
		_construction_repath_cooldown = maxf(0.0, _construction_repath_cooldown - delta)

	if _try_commit_construction_if_in_range():
		velocity = Vector3.ZERO
		_update_gather_trip()
		_update_build_trip()
		return

	var position_before: Vector3 = global_position

	if _is_enemy_worker() and WorkerAiUnstuck.is_active(self):
		WorkerAiUnstuck.process_movement(self, delta)
	elif _task_nudge_active:
		_process_task_corner_nudge(delta)
	elif _is_on_task_movement() and has_move_target:
		var arrived: bool = false
		if _task_navigation_active:
			arrived = _process_task_navigation_movement()
		else:
			arrived = WorkerTaskNavigation.process_direct_movement(
				self,
				_task_movement_destination,
				move_speed,
				stopping_distance
			)

		if arrived:
			if not _attempt_task_proximity_resolve():
				has_move_target = false
			velocity = Vector3.ZERO
		else:
			if _build_trip_state == BuildTripState.TO_BUILDING:
				_try_commit_construction_if_in_range()
			elif not _is_enemy_worker():
				_update_task_corner_stuck_detection(delta, position_before)
	elif has_move_target:
		super._physics_process(delta)
	else:
		velocity = Vector3.ZERO

	if _is_enemy_worker():
		WorkerAiUnstuck.update_detection(self, delta)
	else:
		_update_gather_stuck_recovery(delta)
		_update_construction_stuck_recovery(delta)
	_update_gather_trip()
	_update_build_trip()


func set_movement_target(target: Vector3) -> void:
	if (
		_is_enemy_worker()
		and WorkerAiUnstuck.blocks_external_commands(self)
		and not _ai_unstuck_internal_move
	):
		return

	if _build_trip_state == BuildTripState.CONSTRUCTION_WAIT:
		_cancel_build_trip()
	elif _build_trip_state == BuildTripState.TO_BUILDING:
		if _try_commit_construction_if_in_range():
			return
		if not _is_construction_approach_move_target(target):
			_cancel_build_trip()

	super.set_movement_target(target)
	if _is_on_task_movement():
		_task_movement_destination = Vector3(target.x, global_position.y, target.z)
		_task_has_saved_destination = true
		_refresh_task_navigation()
	_reset_task_corner_nudge()


func _is_on_task_movement() -> bool:
	return (
		_gather_state == GatherTripState.TO_SOURCE
		or _gather_state == GatherTripState.TO_COMMAND_CENTER
		or _build_trip_state == BuildTripState.TO_BUILDING
	)


func _reset_task_corner_nudge() -> void:
	_task_nudge_active = false
	_task_nudge_time = 0.0
	_task_stuck_time = 0.0
	_task_repath_stuck_time = 0.0
	_task_nudge_side_attempts = 0
	_task_nudge_side_sign = 1.0
	_reset_gather_stuck_watch()


func _reset_ai_unstuck_state() -> void:
	WorkerAiUnstuck.clear_unstuck_state(self)


func _reset_gather_stuck_watch() -> void:
	_gather_stuck_watch_position = global_position
	_gather_stuck_watch_time = 0.0


func _configure_task_navigation_agent() -> void:
	if _navigation_agent == null:
		return

	WorkerTaskNavigation.configure_agent(_navigation_agent, stopping_distance)
	call_deferred("_sync_navigation_agent_position")


func _sync_navigation_agent_position() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if _navigation_agent == null:
		return

	_navigation_agent.target_position = global_position


func _refresh_task_navigation() -> void:
	_task_navigation_active = false
	if not _is_on_task_movement() or not _task_has_saved_destination:
		return

	if _build_trip_state == BuildTripState.TO_BUILDING:
		if _try_commit_construction_if_in_range():
			return

	if not WorkerTaskNavigation.can_use(_navigation_agent):
		if _build_trip_state == BuildTripState.TO_BUILDING:
			if _try_commit_construction_if_in_range():
				return
			call_deferred("_try_repath_construction_movement")
		else:
			call_deferred("_try_repath_task_movement")
		return

	_navigation_agent.target_position = _task_movement_destination
	_check_task_navigation_reachable.call_deferred()


func _check_task_navigation_reachable() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if not _is_on_task_movement() or not has_move_target:
		_task_navigation_active = false
		return

	if not WorkerTaskNavigation.can_use(_navigation_agent):
		_task_navigation_active = false
		return

	_task_navigation_active = _navigation_agent.is_target_reachable()
	if not _task_navigation_active:
		if _build_trip_state == BuildTripState.TO_BUILDING:
			if _try_commit_construction_if_in_range():
				return
			call_deferred("_try_repath_construction_movement")
		else:
			call_deferred("_try_repath_task_movement")


func _process_task_navigation_movement() -> bool:
	return WorkerTaskNavigation.process_movement(
		self,
		_navigation_agent,
		_task_movement_destination,
		move_speed,
		stopping_distance
	)


func _disable_task_navigation() -> void:
	_task_navigation_active = false


func _update_task_corner_stuck_detection(delta: float, position_before: Vector3) -> void:
	if _build_trip_state == BuildTripState.TO_BUILDING:
		if _try_commit_construction_if_in_range():
			return
		return

	if _is_gathering_wood() and _gather_state == GatherTripState.TO_SOURCE:
		return

	var moved: Vector3 = global_position - position_before
	moved.y = 0.0
	var expected_move: float = (
		move_speed * delta * GatheringConfig.TASK_CORNER_NUDGE_STUCK_MOVE_RATIO
	)
	var hit_obstacle: bool = get_slide_collision_count() > 0
	var barely_moved: bool = moved.length() < expected_move

	var to_destination: Vector3 = _task_movement_destination - global_position
	to_destination.y = 0.0
	var progress_toward: float = 0.0
	if to_destination.length_squared() > 0.001 and moved.length_squared() > 0.0001:
		progress_toward = moved.normalized().dot(to_destination.normalized()) * moved.length()

	var not_progressing: bool = progress_toward < expected_move * GatheringConfig.TASK_STUCK_PROGRESS_RATIO
	var is_stuck: bool = barely_moved and (hit_obstacle or not_progressing)

	if not is_stuck:
		_task_stuck_time = 0.0
		_task_repath_stuck_time = 0.0
		return

	_task_stuck_time += delta
	_task_repath_stuck_time += delta

	if _task_stuck_time >= GatheringConfig.TASK_CORNER_NUDGE_STUCK_DELAY:
		_begin_task_corner_nudge()

	if _task_repath_stuck_time >= GatheringConfig.TASK_REPATH_STUCK_DELAY:
		_task_repath_stuck_time = 0.0
		_try_repath_task_movement()


func _begin_task_corner_nudge() -> void:
	if _task_nudge_active or not _task_has_saved_destination:
		return

	if _build_trip_state == BuildTripState.TO_BUILDING:
		return

	if _is_gathering_wood():
		return

	_disable_task_navigation()
	has_move_target = false
	_task_repath_stuck_time = 0.0
	_task_nudge_side_sign = _choose_task_nudge_side()
	_task_nudge_direction = _get_task_nudge_direction()
	_task_nudge_active = true
	_task_nudge_time = 0.0
	_task_nudge_start_position = global_position
	_task_stuck_time = 0.0
	velocity = Vector3.ZERO


func _restart_task_corner_nudge_on_opposite_side() -> void:
	_task_nudge_side_sign *= -1.0
	_task_nudge_direction = _get_task_nudge_direction()
	_task_nudge_time = 0.0
	_task_nudge_start_position = global_position
	_task_stuck_time = 0.0


func _get_task_nudge_direction() -> Vector3:
	var to_target: Vector3 = _task_movement_destination - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		to_target = Vector3.FORWARD

	var forward: Vector3 = to_target.normalized()
	return Vector3(-forward.z, 0.0, forward.x).normalized() * _task_nudge_side_sign


func _choose_task_nudge_side() -> float:
	var to_target: Vector3 = _task_movement_destination - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		return 1.0

	var forward: Vector3 = to_target.normalized()
	var lateral_right: Vector3 = Vector3(-forward.z, 0.0, forward.x).normalized()
	var lateral_left: Vector3 = -lateral_right

	if get_slide_collision_count() > 0:
		var collision_normal: Vector3 = get_slide_collision(0).get_normal()
		collision_normal.y = 0.0
		if collision_normal.length_squared() > 0.001:
			collision_normal = collision_normal.normalized()
			if lateral_right.dot(collision_normal) >= lateral_left.dot(collision_normal):
				return -1.0
			return 1.0

	return 1.0


func _process_task_corner_nudge(delta: float) -> void:
	_task_nudge_time += delta
	velocity = _task_nudge_direction * move_speed
	velocity.y = 0.0
	move_and_slide()

	var nudged_offset: Vector3 = global_position - _task_nudge_start_position
	nudged_offset.y = 0.0
	var duration_complete: bool = (
		_task_nudge_time >= GatheringConfig.TASK_CORNER_NUDGE_DURATION
	)
	var distance_complete: bool = (
		nudged_offset.length() >= GatheringConfig.TASK_CORNER_NUDGE_DISTANCE
	)
	if not duration_complete and not distance_complete:
		return

	if (
		get_slide_collision_count() > 0
		and _task_nudge_side_attempts < GatheringConfig.TASK_CORNER_NUDGE_MAX_SIDE_ATTEMPTS - 1
	):
		_task_nudge_side_attempts += 1
		_restart_task_corner_nudge_on_opposite_side()
		return

	_finish_task_corner_nudge()


func _finish_task_corner_nudge() -> void:
	_task_nudge_active = false
	_task_nudge_time = 0.0
	_task_stuck_time = 0.0
	velocity = Vector3.ZERO

	if not _is_on_task_movement():
		return

	if _attempt_task_proximity_resolve():
		return

	if _advance_task_approach_candidate():
		_apply_current_task_movement_target()
		return

	if (
		_gather_state == GatherTripState.TO_COMMAND_CENTER
		and _carried_amount > 0
	):
		var dropoff: CommandCenter = _get_valid_cached_return_dropoff()
		if dropoff == null:
			dropoff = _resolve_dropoff_target()
		if dropoff != null:
			_move_toward_command_center_for_deposit(dropoff)
			return

	if _task_has_saved_destination:
		super.set_movement_target(_task_movement_destination)


func command_gather_gold_mine(gold_mine: GoldMine, player_ordered: bool = true) -> void:
	if not _is_alive():
		return

	if not player_ordered and _is_enemy_worker() and WorkerAiUnstuck.blocks_external_commands(self):
		return

	_last_gather_command_source = &"command_gather_gold_mine"
	_start_gathering(gold_mine, player_ordered)
	_debug_log_ai_gather_state("command_gather_gold_mine")


func command_gather_tree(tree: WoodTree, player_ordered: bool = true) -> void:
	if not _is_alive():
		return

	if not player_ordered and _is_enemy_worker() and WorkerAiUnstuck.blocks_external_commands(self):
		return

	_last_gather_command_source = &"command_gather_tree"
	_start_gathering(tree, player_ordered)
	_debug_log_ai_gather_state("command_gather_tree")


func pin_starting_gold_mine(gold_mine: GoldMine) -> void:
	if gold_mine == null or not is_instance_valid(gold_mine):
		return

	_pinned_starting_gold_mine = gold_mine


func get_pinned_starting_gold_mine() -> GoldMine:
	if not NodeSafety.is_alive_node(_pinned_starting_gold_mine):
		_pinned_starting_gold_mine = null
		return null

	return _pinned_starting_gold_mine


func _start_gathering(source: GatherableResource, player_ordered: bool = true) -> void:
	_cancel_build_trip()
	cancel_gathering()
	if source == null or not is_instance_valid(source):
		_debug_log_ai_gather_state("start_gathering_invalid_source")
		return

	if (
		not player_ordered
		and CreepCampSafety.is_resource_guarded_by_active_camp(source, get_tree())
	):
		_debug_log_ai_gather_state("start_gathering_creep_guarded")
		return

	if source is GoldMine and _is_enemy_worker():
		var pinned_mine: GoldMine = get_pinned_starting_gold_mine()
		if pinned_mine != null:
			source = pinned_mine
		else:
			pin_starting_gold_mine(source as GoldMine)

	if source is WoodTree:
		var wood_tree: WoodTree = _select_wood_tree(source as WoodTree, player_ordered)
		if wood_tree == null or not is_instance_valid(wood_tree) or not wood_tree.can_gather():
			return
		source = wood_tree
		_lock_to_wood_tree(wood_tree)

	if not _is_valid_gather_source(source):
		return

	_gather_source = NodeSafety.safe_node(source) as GatherableResource
	if _gather_source == null:
		return
	_assigned_resource_id = source.get_resource_id()
	_carried_amount = 0
	_source_approach_candidate_index = 0
	_dropoff_candidate_index = 0
	_return_dropoff = null
	var dropoff: CommandCenter = WorkerGathering.find_nearest_dropoff(
		source.global_position,
		_is_enemy_worker(),
		get_tree()
	)
	if dropoff != null and is_instance_valid(dropoff):
		_assigned_dropoff = dropoff
	else:
		_assigned_dropoff = null
	_gather_stuck_recovery_cooldown = 0.0
	_reset_gather_stuck_watch()
	_clear_wood_chop_spot()
	_gather_state = GatherTripState.TO_SOURCE
	_set_movement_to_gather_source(source)
	_debug_log_ai_gather_state("start_gathering_committed")


func cancel_gathering() -> void:
	_unlock_wood_tree()
	_gather_state = GatherTripState.IDLE
	_gather_source = null
	_assigned_resource_id = &""
	_carried_amount = 0
	_source_approach_candidate_index = 0
	_dropoff_candidate_index = 0
	_assigned_dropoff = null
	_return_dropoff = null
	_gather_stuck_recovery_cooldown = 0.0
	_task_has_saved_destination = false
	_clear_wood_chop_spot()
	_disable_task_navigation()
	_reset_task_corner_nudge()
	_reset_ai_unstuck_state()


func start_construction_order(building: Building) -> void:
	if not _is_alive():
		return
	if building == null or not is_instance_valid(building):
		return

	if _is_enemy_worker() and WorkerAiUnstuck.blocks_external_commands(self):
		return

	_begin_construction_trip(building, true)


func assign_wall_build_job(job: WallBuildJob) -> void:
	if _wall_build_job != null and _wall_build_job != job:
		var previous_job: WallBuildJob = _wall_build_job
		_wall_build_job = null
		previous_job.on_worker_left(self)

	_wall_build_job = job


func clear_wall_build_job_assignment() -> void:
	_wall_build_job = null


func get_wall_build_job() -> WallBuildJob:
	return _wall_build_job


func continue_wall_build_order(building: Building) -> void:
	if not _is_alive():
		return
	if building == null or not is_instance_valid(building):
		return

	_begin_construction_trip(building, false)


func _begin_construction_trip(building: Building, clear_wall_job: bool) -> void:
	_cancel_build_trip(clear_wall_job)
	cancel_gathering()
	_build_trip_state = BuildTripState.TO_BUILDING
	_building_target = NodeSafety.safe_node(building) as Building
	if _building_target == null:
		return
	_build_approach_candidate_index = 0
	_construction_target_point_valid = false
	_construction_stuck_recovery_cooldown = 0.0
	_construction_repath_cooldown = 0.0
	_reset_construction_stuck_watch()
	_assign_construction_target_point(false)
	set_movement_target(_construction_target_point)


func command_build(building: Building) -> void:
	start_construction_order(building)


func command_build_farm(farm: Farm) -> void:
	start_construction_order(farm)


func on_building_construction_finished() -> void:
	if _build_trip_state != BuildTripState.CONSTRUCTION_WAIT:
		return

	var finished_building: Building = _building_target
	_build_trip_state = BuildTripState.IDLE
	_building_target = null
	_construction_target_point_valid = false

	if _wall_build_job != null:
		_wall_build_job.on_worker_segment_finished(self, finished_building)
		return

	if _is_enemy_worker():
		_notify_enemy_worker_needs_gather_job()


func notify_building_destroyed(building: Building) -> void:
	if _building_target != building:
		return

	if _wall_build_job != null:
		var job: WallBuildJob = _wall_build_job
		_cancel_build_trip(false)
		job.on_worker_segment_lost(self, building)
		return

	_cancel_build_trip()


func _notify_enemy_worker_needs_gather_job() -> void:
	if not NodeSafety.is_alive_node(self) or not is_inside_tree():
		return

	for node: Node in get_tree().get_nodes_in_group(&"enemy_build_manager"):
		if node is EnemyBuildManager:
			(node as EnemyBuildManager).notify_enemy_worker_spawned(self)
			return


func _update_gather_trip() -> void:
	if not _is_alive():
		return

	if (
		_gather_state == GatherTripState.TO_SOURCE
		or _gather_state == GatherTripState.GATHER_WAIT
	):
		if not _has_valid_gather_source():
			_handle_gather_source_lost()
			return

	match _gather_state:
		GatherTripState.TO_SOURCE:
			if _task_nudge_active or (
				_is_enemy_worker() and WorkerAiUnstuck.blocks_external_commands(self)
			):
				return
			if _attempt_source_proximity_resolve():
				return
			if not has_move_target:
				_handle_arrived_at_source()
		GatherTripState.TO_COMMAND_CENTER:
			if _task_nudge_active or (
				_is_enemy_worker() and WorkerAiUnstuck.blocks_external_commands(self)
			):
				return
			if _carried_amount > 0:
				_ensure_returning_to_current_dropoff()
			if _attempt_dropoff_proximity_resolve():
				return
			if not has_move_target:
				if _carried_amount > 0 and not _has_valid_dropoff_target():
					has_move_target = false
					return
				_handle_command_center_arrival()
		GatherTripState.DONE:
			_recover_done_gather_state()


func _update_build_trip() -> void:
	if not _is_alive():
		return

	match _build_trip_state:
		BuildTripState.TO_BUILDING:
			if _task_nudge_active or (
				_is_enemy_worker() and WorkerAiUnstuck.blocks_external_commands(self)
			):
				return
			if _try_commit_construction_if_in_range():
				return
			if not has_move_target:
				if _is_in_build_start_range():
					_commit_to_construction()
				else:
					_try_repath_construction_movement()
		BuildTripState.DONE:
			_build_trip_state = BuildTripState.IDLE
			_building_target = null
			if _is_enemy_worker():
				_notify_enemy_worker_needs_gather_job()


func _try_commit_construction_if_in_range() -> bool:
	if _build_trip_state != BuildTripState.TO_BUILDING:
		return false

	if not _is_in_build_start_range():
		return false

	_commit_to_construction()
	return true


func _commit_to_construction() -> void:
	has_move_target = false
	_task_has_saved_destination = false
	_construction_target_point_valid = false
	_disable_task_navigation()
	_reset_task_corner_nudge()
	_reset_ai_unstuck_state()
	_reset_construction_stuck_watch()
	velocity = Vector3.ZERO
	_begin_construction_wait()


func _assign_construction_target_point(advance_to_next: bool = false) -> void:
	if _building_target == null or not is_instance_valid(_building_target):
		_construction_target_point_valid = false
		return

	if advance_to_next:
		_build_approach_candidate_index += 1

	var raw_point: Vector3 = _building_target.get_construction_point_by_rank(
		global_position,
		_build_approach_candidate_index
	)
	raw_point.y = global_position.y
	_construction_target_point = _snap_construction_target_to_navigation(raw_point)
	_construction_target_point_valid = true


func _try_repath_construction_movement() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if _build_trip_state != BuildTripState.TO_BUILDING:
		return

	if _construction_repath_cooldown > 0.0:
		return

	if _try_commit_construction_if_in_range():
		return

	if _is_in_build_start_range():
		_commit_to_construction()
		return

	_assign_construction_target_point(true)
	set_movement_target(_construction_target_point)
	_construction_repath_cooldown = CONSTRUCTION_REPATH_COOLDOWN


func _begin_construction_wait() -> void:
	if _building_target == null or not is_instance_valid(_building_target):
		_build_trip_state = BuildTripState.IDLE
		_building_target = null
		if _is_enemy_worker():
			_notify_enemy_worker_needs_gather_job()
		return

	_build_trip_state = BuildTripState.CONSTRUCTION_WAIT
	_building_target.register_builder(self)


func is_in_build_start_range() -> bool:
	return _is_in_build_start_range()


func _is_in_build_start_range() -> bool:
	if _building_target == null or not is_instance_valid(_building_target):
		return false

	var worker_radius: float = _get_collision_xz_radius(self)
	var effective_range: float = BUILD_START_RANGE + worker_radius
	var effective_range_sq: float = effective_range * effective_range

	if _construction_target_point_valid:
		var to_spot: Vector3 = global_position - _construction_target_point
		to_spot.y = 0.0
		if to_spot.length_squared() <= effective_range_sq:
			return true

	var nearest_point: Vector3 = _building_target.get_nearest_construction_point(
		global_position
	)
	var to_point: Vector3 = global_position - nearest_point
	to_point.y = 0.0
	return to_point.length_squared() <= effective_range_sq


func is_actively_constructing_building(building: Building) -> bool:
	return (
		_build_trip_state == BuildTripState.CONSTRUCTION_WAIT
		and building != null
		and is_instance_valid(_building_target)
		and _building_target == building
		and _is_in_build_start_range()
	)


func _is_construction_approach_move_target(target: Vector3) -> bool:
	if not _construction_target_point_valid:
		return false

	var offset: Vector3 = target - _construction_target_point
	offset.y = 0.0
	return offset.length_squared() <= 0.25


func _validate_construction_session() -> bool:
	if _building_target == null or not is_instance_valid(_building_target):
		if _wall_build_job != null:
			var job: WallBuildJob = _wall_build_job
			var lost_segment: Building = _building_target
			_cancel_build_trip(false)
			job.on_worker_segment_lost(self, lost_segment)
		else:
			_cancel_build_trip()
		return false

	if _building_target.building_state == Building.STATE_COMPLETED:
		on_building_construction_finished()
		return false

	if not is_in_build_start_range():
		if _wall_build_job != null and NodeSafety.is_alive_node(_building_target):
			if _build_trip_state == BuildTripState.CONSTRUCTION_WAIT:
				_building_target.unregister_builder(self)
			_build_trip_state = BuildTripState.TO_BUILDING
			_try_repath_construction_movement()
			return false

		_cancel_build_trip()
		return false

	return true


func _is_touching_building_target() -> bool:
	if _building_target == null or not is_instance_valid(_building_target):
		return false

	for collision_index: int in get_slide_collision_count():
		var collider: Object = get_slide_collision(collision_index).get_collider()
		if collider == _building_target:
			return true
		if collider is Node and _building_target.is_ancestor_of(collider as Node):
			return true

	return false


func _compute_building_approach_position(candidate_index: int) -> Vector3:
	if _building_target == null or not is_instance_valid(_building_target):
		return global_position

	var target_center: Vector3 = _building_target.global_position
	var direction: Vector3 = global_position - target_center
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	direction = _apply_approach_candidate_offset(direction, candidate_index)

	var ring: int = candidate_index / GatheringConfig.APPROACH_CANDIDATES_PER_RING
	var stand_off_distance: float = (
		_get_collision_xz_radius(_building_target)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
		+ Building.CONSTRUCTION_EDGE_STANDOFF
		+ float(ring) * GatheringConfig.APPROACH_RING_STANDOFF_STEP
	)
	var approach_position: Vector3 = (
		target_center + direction.normalized() * stand_off_distance
	)
	approach_position.y = global_position.y
	return approach_position


func _snap_construction_target_to_navigation(target: Vector3) -> Vector3:
	if _building_target == null or not is_instance_valid(_building_target):
		return _snap_task_target_to_navigation(target)

	var snapped: Vector3 = _snap_task_target_to_navigation(target)
	if _building_target.is_position_inside_footprint(
		snapped, _get_collision_xz_radius(self)
	):
		return target

	return snapped


func _get_construction_movement_target() -> Vector3:
	if not _construction_target_point_valid:
		_assign_construction_target_point(false)

	return _construction_target_point


func _reset_construction_stuck_watch() -> void:
	_construction_stuck_watch_position = global_position
	_construction_stuck_watch_time = 0.0


func _update_construction_stuck_recovery(delta: float) -> void:
	if _construction_stuck_recovery_cooldown > 0.0:
		_construction_stuck_recovery_cooldown = maxf(
			0.0, _construction_stuck_recovery_cooldown - delta
		)

	if _build_trip_state != BuildTripState.TO_BUILDING:
		_reset_construction_stuck_watch()
		return

	if _task_nudge_active or not has_move_target:
		_reset_construction_stuck_watch()
		return

	if _is_in_build_start_range():
		_reset_construction_stuck_watch()
		return

	var moved: Vector3 = global_position - _construction_stuck_watch_position
	moved.y = 0.0
	if moved.length() >= GatheringConfig.GATHER_STUCK_MIN_MOVE_DISTANCE:
		_reset_construction_stuck_watch()
		return

	_construction_stuck_watch_time += delta
	if _construction_stuck_watch_time < CONSTRUCTION_STUCK_RECOVERY_DELAY:
		return

	if _construction_stuck_recovery_cooldown > 0.0:
		return

	_attempt_construction_stuck_recovery()
	_construction_stuck_recovery_cooldown = CONSTRUCTION_STUCK_RECOVERY_COOLDOWN
	_reset_construction_stuck_watch()


func _attempt_construction_stuck_recovery() -> void:
	if _building_target == null or not is_instance_valid(_building_target):
		_build_trip_state = BuildTripState.IDLE
		_building_target = null
		_construction_target_point_valid = false
		return

	if _is_in_build_start_range():
		_commit_to_construction()
		return

	_try_repath_construction_movement()


func _attempt_source_proximity_resolve() -> bool:
	if not _has_valid_gather_source():
		_handle_gather_source_lost()
		return true

	var source: GatherableResource = _get_valid_gather_source()
	if not _is_near_resource_for_gather(source):
		return false

	has_move_target = false
	_disable_task_navigation()
	_handle_arrived_at_source()
	return true


func _attempt_dropoff_proximity_resolve() -> bool:
	if _carried_amount <= 0:
		return false

	var dropoff: CommandCenter = _get_valid_cached_return_dropoff()
	if dropoff == null:
		dropoff = _resolve_dropoff_target()
	if dropoff == null:
		return false

	if not _is_near_command_center_for_deposit(dropoff, true):
		return false

	has_move_target = false
	_disable_task_navigation()
	_handle_command_center_arrival()
	return true


func _attempt_task_proximity_resolve() -> bool:
	if _gather_state == GatherTripState.TO_SOURCE:
		return _attempt_source_proximity_resolve()
	if _gather_state == GatherTripState.TO_COMMAND_CENTER:
		return _attempt_dropoff_proximity_resolve()
	if _build_trip_state == BuildTripState.TO_BUILDING:
		return _try_commit_construction_if_in_range()

	return false


func _update_gather_stuck_recovery(delta: float) -> void:
	if _gather_stuck_recovery_cooldown > 0.0:
		_gather_stuck_recovery_cooldown = maxf(0.0, _gather_stuck_recovery_cooldown - delta)

	if (
		_gather_state != GatherTripState.TO_SOURCE
		and _gather_state != GatherTripState.TO_COMMAND_CENTER
	):
		_reset_gather_stuck_watch()
		return

	if _task_nudge_active:
		_reset_gather_stuck_watch()
		return

	if not has_move_target:
		var waiting_to_start_gather: bool = (
			_gather_state == GatherTripState.TO_SOURCE and _has_valid_gather_source()
		)
		if not waiting_to_start_gather:
			_reset_gather_stuck_watch()
			return

	if _gather_state == GatherTripState.TO_SOURCE and _is_gathering_wood():
		if _wood_chop_spot_valid and _is_near_wood_chop_spot():
			_attempt_source_proximity_resolve()
		_reset_gather_stuck_watch()
		return

	var moved: Vector3 = global_position - _gather_stuck_watch_position
	moved.y = 0.0
	if moved.length() >= GatheringConfig.GATHER_STUCK_MIN_MOVE_DISTANCE:
		_reset_gather_stuck_watch()
		return

	_gather_stuck_watch_time += delta
	if _gather_stuck_watch_time < GatheringConfig.GATHER_STUCK_RECOVERY_DELAY:
		return

	if _gather_stuck_recovery_cooldown > 0.0:
		return

	_attempt_gather_stuck_recovery()
	_gather_stuck_recovery_cooldown = GatheringConfig.GATHER_STUCK_RECOVERY_COOLDOWN
	_reset_gather_stuck_watch()


func _attempt_gather_stuck_recovery() -> void:
	if _gather_state == GatherTripState.TO_SOURCE:
		if _is_gathering_wood():
			return

		if not _has_valid_gather_source():
			_handle_gather_source_lost()
			return

		if not has_move_target and not _task_has_saved_destination:
			_set_movement_to_gather_source(_get_valid_gather_source())
			return

		if _advance_task_approach_candidate():
			_apply_current_task_movement_target()
			return

		_source_approach_candidate_index = 0
		_apply_current_task_movement_target()
		return

	if _gather_state == GatherTripState.TO_COMMAND_CENTER:
		if not _has_valid_dropoff_target():
			if _carried_amount <= 0:
				_finish_gathering_idle()
			return

		if _advance_task_approach_candidate():
			_apply_current_task_movement_target()
			return

		_retry_return_to_command_center()


func _try_repath_task_movement() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if not _is_on_task_movement() or _task_nudge_active:
		return

	if _is_gathering_wood() and _gather_state == GatherTripState.TO_SOURCE:
		if (
			_wood_chop_spot_valid
			and _is_near_wood_chop_spot()
		):
			_attempt_source_proximity_resolve()
		return

	if _build_trip_state == BuildTripState.TO_BUILDING:
		_try_repath_construction_movement()
		return

	if _attempt_task_proximity_resolve():
		return

	if _advance_task_approach_candidate():
		_apply_current_task_movement_target()
		return

	if (
		_gather_state == GatherTripState.TO_COMMAND_CENTER
		and _carried_amount > 0
	):
		var dropoff: CommandCenter = _get_valid_cached_return_dropoff()
		if dropoff == null:
			dropoff = _resolve_dropoff_target()
		if dropoff != null:
			_move_toward_command_center_for_deposit(dropoff)
			return

	_attempt_task_proximity_resolve()


func _advance_task_approach_candidate() -> bool:
	match _gather_state:
		GatherTripState.TO_SOURCE:
			_source_approach_candidate_index += 1
			return (
				_source_approach_candidate_index
				< GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES
			)
		GatherTripState.TO_COMMAND_CENTER:
			_dropoff_candidate_index += 1
			return (
				_dropoff_candidate_index < GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES
			)

	if _build_trip_state == BuildTripState.TO_BUILDING:
		return false

	return false


func _apply_current_task_movement_target() -> void:
	match _gather_state:
		GatherTripState.TO_SOURCE:
			if not _has_valid_gather_source():
				_handle_gather_source_lost()
				return
			_set_movement_to_gather_source(_get_valid_gather_source())
		GatherTripState.TO_COMMAND_CENTER:
			var dropoff: CommandCenter = _resolve_dropoff_target()
			if dropoff == null:
				return
			set_movement_target(_compute_command_center_dropoff_position(dropoff))
		_:
			pass

	if _build_trip_state == BuildTripState.TO_BUILDING:
		if _building_target == null or not is_instance_valid(_building_target):
			_build_trip_state = BuildTripState.IDLE
			_building_target = null
			return

		if not _construction_target_point_valid:
			_assign_construction_target_point(false)

		set_movement_target(_construction_target_point)


func _has_valid_gather_source() -> bool:
	if _gather_source == null:
		return false
	if not is_instance_valid(_gather_source):
		_gather_source = null
		return false
	return not _gather_source.is_queued_for_deletion()


func _get_valid_gather_source() -> GatherableResource:
	if not _has_valid_gather_source():
		return null
	return _gather_source


func _is_valid_gather_source(source: Variant) -> bool:
	if source == null or not source is GatherableResource:
		return false
	if not is_instance_valid(source):
		return false
	return not source.is_queued_for_deletion()


func _is_near_resource_for_gather(source: CollisionObject3D) -> bool:
	if source is WoodTree and _wood_chop_spot_valid:
		return _is_near_wood_chop_spot()

	return _is_near_collision_target(source, GatheringConfig.RESOURCE_INTERACTION_REACH_BONUS)


func _is_near_collision_target(
	target: CollisionObject3D, reach_bonus: float = 0.5
) -> bool:
	if target == null:
		return false

	var offset: Vector3 = global_position - target.global_position
	offset.y = 0.0
	var reach_distance: float = (
		stopping_distance
		+ _get_collision_xz_radius(target)
		+ _get_collision_xz_radius(self)
		+ reach_bonus
	)
	return offset.length_squared() <= reach_distance * reach_distance


func _handle_arrived_at_source() -> void:
	if not _has_valid_gather_source():
		_handle_gather_source_lost()
		return

	var source: GatherableResource = _get_valid_gather_source()
	if not _is_near_resource_for_gather(source):
		if _is_gathering_wood():
			if not _is_near_wood_chop_spot(GatheringConfig.GATHER_LAST_RESORT_REACH_BONUS):
				_set_movement_to_gather_source(source)
				return
		elif _advance_task_approach_candidate():
			_apply_current_task_movement_target()
			return
		elif not _is_near_collision_target(
			source, GatheringConfig.GATHER_LAST_RESORT_REACH_BONUS
		):
			_handle_gather_source_lost()
			return

	_source_approach_candidate_index = 0

	if not source.can_gather():
		if _carried_amount > 0:
			_begin_return_to_command_center()
		elif not _try_reassign_gather_source():
			_finish_gathering_idle()
		return

	if _should_return_to_command_center_from_source():
		_begin_return_to_command_center()
	else:
		_begin_gather_wait()


func _handle_command_center_arrival() -> void:
	var dropoff: CommandCenter = _resolve_dropoff_target()
	if dropoff == null or not WorkerGathering.is_valid_dropoff(dropoff, _is_enemy_worker()):
		if _carried_amount > 0:
			_return_dropoff = null
			has_move_target = false
			return
		_finish_gathering_idle()
		return

	if _carried_amount > 0:
		if _try_deposit_at_command_center(dropoff):
			_dropoff_candidate_index = 0
			_return_dropoff = null
			_continue_gather_cycle()
			return

		if _advance_task_approach_candidate():
			_apply_current_task_movement_target()
			return

		_move_toward_command_center_for_deposit(dropoff)
		return

	_dropoff_candidate_index = 0
	_return_dropoff = null
	_continue_gather_cycle()



func _should_return_to_command_center_from_source() -> bool:
	if _carried_amount <= 0:
		return false

	if not _has_valid_gather_source():
		return true

	var source: GatherableResource = _get_valid_gather_source()
	if not source.can_gather():
		return true

	if not source.gathers_until_carry_full():
		return true

	return _carried_amount >= GatheringConfig.WORKER_CARRY_CAPACITY


func _begin_gather_wait() -> void:
	if _is_gathering_wood():
		_lock_wood_gathering_position()

	_gather_state = GatherTripState.GATHER_WAIT
	var wait_timer: SceneTreeTimer = get_tree().create_timer(_get_gather_wait_seconds())
	wait_timer.timeout.connect(_on_gather_wait_finished, CONNECT_ONE_SHOT)


func _get_gather_wait_seconds() -> float:
	return GatheringConfig.get_gather_wait_seconds(_get_gather_speed_multiplier())


func _get_gather_speed_multiplier() -> float:
	if UpgradeManager.has_faster_gathering(_is_enemy_worker()):
		return UpgradeManager.FASTER_GATHERING_SPEED_MULTIPLIER

	return 1.0


func _on_gather_wait_finished() -> void:
	if not _is_alive() or _gather_state != GatherTripState.GATHER_WAIT:
		return

	if not _has_valid_gather_source():
		if _carried_amount > 0:
			_begin_return_to_command_center()
		elif not _try_reassign_gather_source():
			_finish_gathering_idle()
		return

	var source: GatherableResource = _get_valid_gather_source()
	var gathered: int = source.gather(source.get_gather_chunk_size())
	_carried_amount += gathered

	if _carried_amount <= 0 and not source.can_gather():
		if not _try_reassign_gather_source():
			_finish_gathering_idle()
		return

	if _should_return_to_command_center_from_source():
		_begin_return_to_command_center()
	elif source.can_gather():
		_begin_gather_wait()
	elif _carried_amount > 0:
		_begin_return_to_command_center()
	else:
		if not _try_reassign_gather_source():
			_finish_gathering_idle()


func _begin_return_to_command_center() -> void:
	_dropoff_candidate_index = 0
	var search_position: Vector3 = (
		global_position if _is_gathering_wood() else _get_dropoff_search_position()
	)
	var dropoff: CommandCenter = WorkerGathering.find_nearest_dropoff(
		search_position,
		_is_enemy_worker(),
		get_tree()
	)
	if dropoff != null and is_instance_valid(dropoff):
		_return_dropoff = dropoff
		_assigned_dropoff = dropoff
	else:
		_return_dropoff = null
		_assigned_dropoff = null
	_gather_state = GatherTripState.TO_COMMAND_CENTER
	_ensure_returning_to_current_dropoff()


func _retry_return_to_command_center() -> void:
	if not _ensure_returning_to_current_dropoff():
		has_move_target = false


func _has_valid_dropoff_target() -> bool:
	if _get_valid_cached_return_dropoff() != null:
		return true
	return _resolve_dropoff_target() != null


func _deposit_carried() -> void:
	if _carried_amount <= 0:
		return

	var resource_id: StringName = _get_carried_resource_id()
	if resource_id.is_empty():
		return

	WorkerGathering.deposit(resource_id, _carried_amount, _is_enemy_worker())
	_carried_amount = 0


func _get_carried_resource_id() -> StringName:
	if not _assigned_resource_id.is_empty():
		return _assigned_resource_id

	var source: GatherableResource = _get_valid_gather_source()
	if source != null:
		return source.get_resource_id()

	return &""


func _try_deposit_at_command_center(command_center: CommandCenter) -> bool:
	if _carried_amount <= 0:
		return true

	if not _is_near_command_center_for_deposit(command_center, true):
		return false

	_deposit_carried()
	return _carried_amount <= 0


func _move_toward_command_center_for_deposit(command_center: CommandCenter) -> void:
	if command_center == null or not is_instance_valid(command_center):
		return

	if not WorkerGathering.is_valid_dropoff(command_center, _is_enemy_worker()):
		return

	_return_dropoff = command_center
	_dropoff_candidate_index = 0
	set_movement_target(_compute_command_center_dropoff_position(command_center))


func _continue_gather_cycle() -> void:
	if _is_gathering_wood():
		if (
			_locked_wood_tree != null
			and is_instance_valid(_locked_wood_tree)
			and _locked_wood_tree.can_gather()
		):
			_gather_source = _locked_wood_tree
			_gather_state = GatherTripState.TO_SOURCE
			_source_approach_candidate_index = 0
			_set_movement_to_gather_source(_locked_wood_tree)
			return
		if _try_reassign_gather_source():
			return
		_finish_gathering_idle()
		return

	var source: GatherableResource = _get_valid_gather_source()
	if source == null or not source.can_gather():
		if _try_reassign_gather_source():
			return
		_finish_gathering_idle()
		return

	_gather_state = GatherTripState.TO_SOURCE
	_source_approach_candidate_index = 0
	_set_movement_to_gather_source(source)


func _handle_gather_source_lost() -> void:
	_gather_source = null
	if _is_gathering_wood():
		_unlock_wood_tree()
	_clear_wood_chop_spot()

	if _carried_amount > 0:
		_begin_return_to_command_center()
		return

	if not _try_reassign_gather_source():
		_finish_gathering_idle()


func _try_reassign_gather_source() -> bool:
	var resource_id: StringName = _get_assigned_resource_id()
	if resource_id.is_empty():
		return false

	if resource_id == &"gold":
		var gold_mine: GoldMine = null
		if _is_enemy_worker():
			gold_mine = get_pinned_starting_gold_mine()
		if gold_mine == null:
			var scene_root: Node = get_tree().current_scene
			if scene_root == null:
				return false

			var replacement: GatherableResource = WorkerGathering.find_nearest_gather_source(
				&"gold",
				global_position,
				scene_root,
				_is_enemy_worker(),
				null,
				false
			)
			if replacement == null or not is_instance_valid(replacement) or not replacement is GoldMine:
				return false

			gold_mine = replacement as GoldMine
		if not gold_mine.can_gather():
			return false

		if _is_enemy_worker() and not WorkerGathering.is_safe_gather_source(gold_mine, get_tree()):
			return false

		_gather_source = gold_mine
		_assigned_resource_id = gold_mine.get_resource_id()
		_source_approach_candidate_index = 0
		_gather_state = GatherTripState.TO_SOURCE
		_set_movement_to_gather_source(gold_mine)
		return true

	if resource_id == &"wood":
		_unlock_wood_tree()
		var scene_root: Node = get_tree().current_scene
		if scene_root == null or not is_instance_valid(scene_root):
			return false

		var replacement: WoodTree = WorkerGathering.find_best_wood_tree(
			global_position,
			scene_root,
			_is_enemy_worker(),
			null,
			_get_valid_gather_source(),
			false
		)
		if replacement == null or not is_instance_valid(replacement):
			return false

		_lock_to_wood_tree(replacement)
		_gather_source = replacement
		_assigned_resource_id = replacement.get_resource_id()
		_source_approach_candidate_index = 0
		_gather_state = GatherTripState.TO_SOURCE
		_set_movement_to_gather_source(replacement)
		return true

	return false


func _get_assigned_resource_id() -> StringName:
	if not _assigned_resource_id.is_empty():
		return _assigned_resource_id

	var source: GatherableResource = _get_valid_gather_source()
	if source != null:
		return source.get_resource_id()

	return &""


func _recover_done_gather_state() -> void:
	if _carried_amount > 0:
		_begin_return_to_command_center()
		return

	if _try_reassign_gather_source():
		return

	_finish_gathering_idle()


func _finish_gathering_idle() -> void:
	if _carried_amount > 0:
		var dropoff: CommandCenter = _resolve_dropoff_target()
		if dropoff != null and _try_deposit_at_command_center(dropoff):
			pass
		if _carried_amount > 0:
			return

	_unlock_wood_tree()
	_gather_state = GatherTripState.IDLE
	_gather_source = null
	_assigned_resource_id = &""
	_assigned_dropoff = null
	_return_dropoff = null
	_carried_amount = 0
	_clear_wood_chop_spot()

	if _is_enemy_worker():
		_debug_log_ai_gather_state("finish_gathering_idle")
		_notify_enemy_worker_needs_gather_job()


func needs_gather_target_reassignment() -> bool:
	if _build_trip_state != BuildTripState.IDLE:
		return false

	if _carried_amount > 0:
		return false

	if _gather_state == GatherTripState.GATHER_WAIT:
		return false

	if _gather_state == GatherTripState.TO_COMMAND_CENTER:
		return false

	if _gather_state == GatherTripState.IDLE or _gather_state == GatherTripState.DONE:
		return true

	if not _has_valid_gather_source():
		return true

	var source: GatherableResource = _get_valid_gather_source()
	if not source.can_gather():
		return true

	if _is_enemy_worker() and not WorkerGathering.is_safe_gather_source(source, get_tree()):
		return true

	return false


func is_enemy_gather_fallback_idle() -> bool:
	if not _is_enemy_worker() or not _is_alive():
		return false

	if is_on_construction_trip() or is_constructing():
		return false

	if is_carrying_gathered_resources():
		return false

	match _gather_state:
		GatherTripState.GATHER_WAIT:
			return false
		GatherTripState.TO_COMMAND_CENTER:
			return false
		GatherTripState.TO_SOURCE:
			if _has_valid_gather_source():
				if has_move_target or _task_has_saved_destination:
					return false
				# Assigned to gather but movement never started (nav not ready).
				return true

	if needs_gather_target_reassignment():
		return true

	return not is_busy_with_task() and not has_move_target


func is_on_active_gather_trip() -> bool:
	if _build_trip_state != BuildTripState.IDLE:
		return false

	match _gather_state:
		GatherTripState.GATHER_WAIT, GatherTripState.TO_COMMAND_CENTER:
			return true
		GatherTripState.TO_SOURCE:
			return _has_valid_gather_source()
		_:
			return false


func _debug_log_ai_gather_state(trigger: String) -> void:
	if not DEBUG_AI_WORKER_GATHER or not _is_enemy_worker():
		return

	var source_name: String = "none"
	var source: GatherableResource = _get_valid_gather_source()
	if source != null and is_instance_valid(source):
		source_name = source.name

	var dropoff_name: String = "none"
	var dropoff: CommandCenter = _assigned_dropoff
	if dropoff == null:
		dropoff = _return_dropoff
	if dropoff != null and is_instance_valid(dropoff):
		dropoff_name = dropoff.name

	var nav_destination: Vector3 = (
		_task_movement_destination if _task_has_saved_destination else Vector3.ZERO
	)
	var idle_reason: String = "active"
	if is_enemy_gather_fallback_idle():
		if needs_gather_target_reassignment():
			idle_reason = "needs_reassignment"
		elif not is_busy_with_task() and not has_move_target:
			idle_reason = "no_task_no_move"
		elif (
			_gather_state == GatherTripState.TO_SOURCE
			and _has_valid_gather_source()
			and not has_move_target
			and not _task_has_saved_destination
		):
			idle_reason = "to_source_no_move"
		else:
			idle_reason = "fallback_idle"

	print(
		(
			"[AI Worker %s] %s | gather=%s build=%s carry=%d/%s "
			+ "source=%s dropoff=%s nav=%s move=%s cmd=%s idle=%s"
		)
		% [
			name,
			trigger,
			GatherTripState.keys()[_gather_state],
			BuildTripState.keys()[_build_trip_state],
			_carried_amount,
			_assigned_resource_id,
			source_name,
			dropoff_name,
			nav_destination,
			has_move_target,
			_last_gather_command_source,
			idle_reason,
		]
	)


func _get_dropoff_search_position() -> Vector3:
	var source: GatherableResource = _get_valid_gather_source()
	if source != null:
		return source.global_position

	return global_position


func _get_valid_cached_return_dropoff() -> CommandCenter:
	if _return_dropoff == null or not is_instance_valid(_return_dropoff):
		return null

	if not WorkerGathering.is_valid_dropoff(_return_dropoff, _is_enemy_worker()):
		return null

	return _return_dropoff


func _resolve_dropoff_target() -> CommandCenter:
	var cached_return: CommandCenter = _get_valid_cached_return_dropoff()
	if cached_return != null and _gather_state == GatherTripState.TO_COMMAND_CENTER:
		_assigned_dropoff = cached_return
		return cached_return

	if (
		_assigned_dropoff != null
		and is_instance_valid(_assigned_dropoff)
		and WorkerGathering.is_valid_dropoff(_assigned_dropoff, _is_enemy_worker())
	):
		return _assigned_dropoff

	var dropoff: CommandCenter = WorkerGathering.find_nearest_dropoff(
		_get_dropoff_search_position(),
		_is_enemy_worker(),
		get_tree()
	)
	if dropoff != null and is_instance_valid(dropoff):
		_assigned_dropoff = dropoff
	else:
		_assigned_dropoff = null
	if _gather_state == GatherTripState.TO_COMMAND_CENTER and _assigned_dropoff != null:
		_return_dropoff = _assigned_dropoff
	return _assigned_dropoff


func _ensure_returning_to_current_dropoff() -> bool:
	var dropoff: CommandCenter = _get_valid_cached_return_dropoff()
	if dropoff == null:
		dropoff = _resolve_dropoff_target()
		if dropoff == null:
			_return_dropoff = null
			return false
		_return_dropoff = dropoff

	if has_move_target:
		return true

	_dropoff_candidate_index = 0
	set_movement_target(_compute_command_center_dropoff_position(dropoff))
	return true


func _is_enemy_worker() -> bool:
	return is_in_group(&"enemy_workers")


func is_busy_with_task() -> bool:
	if _build_trip_state != BuildTripState.IDLE:
		return true

	return _gather_state != GatherTripState.IDLE


func is_assigned_to_build(building: Building) -> bool:
	if _build_trip_state == BuildTripState.IDLE or building == null:
		return false

	return is_instance_valid(_building_target) and _building_target == building


func is_available_for_construction_assignment(allow_gather_interrupt: bool = false) -> bool:
	if _build_trip_state != BuildTripState.IDLE:
		return false

	if _gather_state == GatherTripState.IDLE:
		return true

	return allow_gather_interrupt


func is_on_construction_trip() -> bool:
	return _build_trip_state != BuildTripState.IDLE


func is_constructing() -> bool:
	return _build_trip_state == BuildTripState.CONSTRUCTION_WAIT


func get_build_target() -> Building:
	return _building_target


func is_carrying_gathered_resources() -> bool:
	return _carried_amount > 0


func get_assigned_gather_resource_id() -> StringName:
	return _get_assigned_resource_id()


func _is_near_command_center_for_deposit(
	command_center: CommandCenter, use_extended_reach: bool = false
) -> bool:
	if command_center == null or not is_instance_valid(command_center):
		return false

	var reach_bonus: float = GatheringConfig.COMMAND_CENTER_DEPOSIT_REACH_BONUS
	if use_extended_reach:
		reach_bonus += GatheringConfig.COMMAND_CENTER_DEPOSIT_EXTENDED_REACH

	var reach_distance: float = (
		stopping_distance
		+ _get_collision_xz_radius(command_center)
		+ _get_collision_xz_radius(self)
		+ reach_bonus
	)
	var offset: Vector3 = global_position - command_center.global_position
	offset.y = 0.0
	return offset.length_squared() <= reach_distance * reach_distance


func _is_gathering_wood() -> bool:
	return _get_assigned_resource_id() == &"wood"


func _clear_wood_chop_spot() -> void:
	_wood_chop_spot_valid = false


func _lock_to_wood_tree(tree: WoodTree) -> void:
	if tree == null or not is_instance_valid(tree):
		_unlock_wood_tree()
		return

	if _locked_wood_tree == tree:
		return

	_unlock_wood_tree()
	_clear_wood_chop_spot()
	_locked_wood_tree = tree
	tree.register_assigned_worker()


func _unlock_wood_tree() -> void:
	if _locked_wood_tree != null and is_instance_valid(_locked_wood_tree):
		_locked_wood_tree.unregister_assigned_worker()
	_locked_wood_tree = null


func _select_wood_tree(preferred: WoodTree, player_ordered: bool = true) -> WoodTree:
	if (
		player_ordered
		and preferred != null
		and is_instance_valid(preferred)
		and preferred.can_gather()
	):
		return preferred

	var scene_root: Node = get_tree().current_scene
	return WorkerGathering.find_best_wood_tree(
		global_position,
		scene_root,
		_is_enemy_worker(),
		preferred,
		null,
		false
	)


func _lock_wood_gathering_position() -> void:
	has_move_target = false
	_task_has_saved_destination = false
	_disable_task_navigation()
	_reset_task_corner_nudge()
	_reset_ai_unstuck_state()
	velocity = Vector3.ZERO


func _is_near_wood_chop_spot(
	reach_bonus: float = GatheringConfig.WOOD_CHOP_REACH_BONUS
) -> bool:
	if not _wood_chop_spot_valid:
		return false

	var offset: Vector3 = global_position - _wood_chop_spot
	offset.y = 0.0
	var reach_distance: float = stopping_distance + _get_collision_xz_radius(self) + reach_bonus
	return offset.length_squared() <= reach_distance * reach_distance


func _set_movement_to_gather_source(source: Variant) -> void:
	if not _is_valid_gather_source(source):
		return

	var gather_source := source as GatherableResource
	if gather_source is WoodTree:
		var tree := gather_source as WoodTree
		if not (_wood_chop_spot_valid and _locked_wood_tree == tree):
			_wood_chop_spot = _compute_wood_chop_spot(tree)
			_wood_chop_spot_valid = true
		set_movement_target(_wood_chop_spot)
		return

	_clear_wood_chop_spot()
	set_movement_target(_compute_resource_approach_position(gather_source))


func _compute_wood_chop_spot(tree: WoodTree) -> Vector3:
	var base_slot: int = _get_gather_approach_base_slot()
	var fallback_position: Vector3 = global_position
	var nearby_workers: Array[Worker] = _collect_workers_for_approach_check(tree)
	var attempt_limit: int = mini(
		GatheringConfig.APPROACH_OCCUPIED_MAX_ATTEMPTS,
		GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES
	)
	for attempt_offset: int in attempt_limit:
		var candidate_index: int = base_slot + attempt_offset
		fallback_position = _compute_resource_approach_position_for_candidate(
			tree, candidate_index
		)
		if _is_approach_position_occupied(fallback_position, tree, nearby_workers):
			continue
		return fallback_position

	return fallback_position


func _is_wood_chop_spot_reachable(chop_spot: Vector3) -> bool:
	if not WorkerTaskNavigation.can_use(_navigation_agent):
		return true

	return WorkerTaskNavigation.is_target_reachable(_navigation_agent, chop_spot)


func _get_gather_approach_base_slot() -> int:
	return absi(get_instance_id()) % GatheringConfig.GATHER_APPROACH_BASE_SLOT_COUNT


func _compute_resource_approach_direction(source: CollisionObject3D, candidate_index: int) -> Vector3:
	var target_center: Vector3 = source.global_position
	var direction: Vector3 = global_position - target_center
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()

	var slot_in_ring: int = (
		_get_gather_approach_base_slot() + candidate_index
	) % GatheringConfig.APPROACH_CANDIDATES_PER_RING
	var angle: float = deg_to_rad(
		float(slot_in_ring) * GatheringConfig.GATHER_APPROACH_BASE_ANGLE_STEP
	)
	return direction.rotated(Vector3.UP, angle)


func _compute_resource_approach_position_for_candidate(
	source: CollisionObject3D, candidate_index: int
) -> Vector3:
	var target_center: Vector3 = source.global_position
	var direction: Vector3 = _compute_resource_approach_direction(source, candidate_index)
	var ring: int = candidate_index / GatheringConfig.APPROACH_CANDIDATES_PER_RING
	var stand_off_distance: float = (
		_get_collision_xz_radius(source)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
		+ (GatheringConfig.WOOD_CHOP_STANDOFF_EXTRA if source is WoodTree else 0.0)
		+ float(ring) * GatheringConfig.APPROACH_RING_STANDOFF_STEP
	)
	var approach_position: Vector3 = target_center + direction.normalized() * stand_off_distance
	approach_position.y = global_position.y
	return _snap_task_target_to_navigation(approach_position)


func _collect_workers_for_approach_check(_source: CollisionObject3D) -> Array[Worker]:
	var workers: Array[Worker] = []
	var tree: SceneTree = get_tree()
	for group_name: StringName in [&"workers", &"enemy_workers"]:
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if node_variant == self:
				continue
			if node_variant == null or not is_instance_valid(node_variant):
				continue
			if not node_variant is Worker:
				continue

			var other_worker: Worker = node_variant as Worker
			workers.append(other_worker)
	return workers


func _is_approach_position_occupied(
	approach_position: Vector3,
	source: CollisionObject3D = null,
	nearby_workers: Array[Worker] = []
) -> bool:
	var occupied_radius_sq: float = (
		GatheringConfig.APPROACH_OCCUPIED_RADIUS * GatheringConfig.APPROACH_OCCUPIED_RADIUS
	)
	var destination_radius_sq: float = (
		GatheringConfig.APPROACH_OCCUPIED_DESTINATION_RADIUS
		* GatheringConfig.APPROACH_OCCUPIED_DESTINATION_RADIUS
	)

	for other_worker_variant: Variant in nearby_workers:
		if other_worker_variant == null or not is_instance_valid(other_worker_variant):
			continue
		if not other_worker_variant is Worker:
			continue

		var other_worker: Worker = other_worker_variant as Worker

		var to_other: Vector3 = other_worker.global_position - approach_position
		to_other.y = 0.0
		if to_other.length_squared() <= occupied_radius_sq:
			return true

		if other_worker._is_on_task_movement() and other_worker._task_has_saved_destination:
			var to_destination: Vector3 = (
				other_worker._task_movement_destination - approach_position
			)
			to_destination.y = 0.0
			if to_destination.length_squared() <= destination_radius_sq:
				return true

		if source != null and other_worker._gather_source == source:
			if other_worker._wood_chop_spot_valid:
				var to_chop_spot: Vector3 = other_worker._wood_chop_spot - approach_position
				to_chop_spot.y = 0.0
				if to_chop_spot.length_squared() <= destination_radius_sq:
					return true

			if other_worker._gather_state == GatherTripState.GATHER_WAIT:
				var to_gathering_worker: Vector3 = (
					other_worker.global_position - approach_position
				)
				to_gathering_worker.y = 0.0
				if to_gathering_worker.length_squared() <= occupied_radius_sq:
					return true

	return false


func _compute_resource_approach_position(source: CollisionObject3D) -> Vector3:
	if source == null or not is_instance_valid(source):
		return global_position

	var fallback_position: Vector3 = global_position
	var nearby_workers: Array[Worker] = _collect_workers_for_approach_check(source)
	var attempt_limit: int = mini(
		GatheringConfig.APPROACH_OCCUPIED_MAX_ATTEMPTS,
		GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES - _source_approach_candidate_index
	)
	for attempt_offset: int in attempt_limit:
		var candidate_index: int = _source_approach_candidate_index + attempt_offset
		fallback_position = _compute_resource_approach_position_for_candidate(
			source, candidate_index
		)
		if _is_approach_position_occupied(fallback_position, source, nearby_workers):
			continue
		if source is WoodTree and not _is_wood_chop_spot_reachable(fallback_position):
			continue
		return fallback_position

	return fallback_position


func _compute_command_center_dropoff_position(command_center: CommandCenter) -> Vector3:
	if command_center == null:
		return global_position

	var target_center: Vector3 = command_center.global_position
	var direction: Vector3 = Vector3(
		command_center.worker_spawn_offset.x,
		0.0,
		command_center.worker_spawn_offset.z
	)
	if direction.length_squared() < 0.001:
		direction = global_position - target_center
		direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	if _dropoff_candidate_index > 0:
		direction = _apply_approach_candidate_offset(direction, _dropoff_candidate_index)
	else:
		direction = direction.normalized()

	var ring: int = _dropoff_candidate_index / GatheringConfig.APPROACH_CANDIDATES_PER_RING
	var stand_off_distance: float = (
		_get_collision_xz_radius(command_center)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
		+ 0.25
		+ float(ring) * GatheringConfig.APPROACH_RING_STANDOFF_STEP
	)
	var dropoff_position: Vector3 = target_center + direction * stand_off_distance
	dropoff_position.y = global_position.y
	return _snap_task_target_to_navigation(dropoff_position)


func _compute_approach_position(
	target: CollisionObject3D, candidate_index: int = 0
) -> Vector3:
	var target_center: Vector3 = target.global_position
	var direction: Vector3 = global_position - target_center
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	direction = _apply_approach_candidate_offset(direction, candidate_index)

	var ring: int = candidate_index / GatheringConfig.APPROACH_CANDIDATES_PER_RING
	var stand_off_distance: float = (
		_get_collision_xz_radius(target)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
		+ float(ring) * GatheringConfig.APPROACH_RING_STANDOFF_STEP
	)
	var approach_position: Vector3 = target_center + direction.normalized() * stand_off_distance
	approach_position.y = global_position.y
	return _snap_task_target_to_navigation(approach_position)


func _apply_approach_candidate_offset(direction: Vector3, candidate_index: int) -> Vector3:
	if candidate_index <= 0:
		return direction

	var ring_index: int = candidate_index / GatheringConfig.APPROACH_CANDIDATES_PER_RING
	var slot_index: int = candidate_index % GatheringConfig.APPROACH_CANDIDATES_PER_RING
	var base_direction: Vector3 = direction
	if base_direction.length_squared() < 0.001:
		base_direction = Vector3.FORWARD
	else:
		base_direction = base_direction.normalized()

	if slot_index == 0 and ring_index > 0:
		return base_direction

	var angle: float = deg_to_rad(float(slot_index * 45))
	return base_direction.rotated(Vector3.UP, angle)


func _snap_task_target_to_navigation(target: Vector3) -> Vector3:
	if not WorkerTaskNavigation.can_use(_navigation_agent):
		return target

	var nav_map: RID = _navigation_agent.get_navigation_map()
	if nav_map == RID():
		return target

	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, target)
	snapped.y = target.y
	return snapped


func _get_collision_xz_radius(body: CollisionObject3D) -> float:
	var collision_shape: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 0.5

	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		return maxf(box_shape.size.x, box_shape.size.z) * 0.5

	if collision_shape.shape is CylinderShape3D:
		var cylinder_shape := collision_shape.shape as CylinderShape3D
		return cylinder_shape.radius

	return 0.5
