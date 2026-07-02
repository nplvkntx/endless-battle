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

const GOLD_MINE_COMMAND_MESSAGE: String = "Worker received gold mine command"
const TREE_COMMAND_MESSAGE: String = "Worker received tree command"
const HEALTH_BAR_WIDTH := 1.0
const HEALTH_BAR_HUE_GREEN := 0.333333
const FOOD_SUPPLY_USED: int = 1
const CONSTRUCTION_STUCK_RECOVERY_DELAY: float = 2.0
const CONSTRUCTION_STUCK_RECOVERY_COOLDOWN: float = 0.75
const CONSTRUCTION_REPATH_COOLDOWN: float = 1.25
const BUILD_START_RANGE: float = 0.5

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


func _ready() -> void:
	super._ready()
	var fill_material := _health_bar_fill.get_surface_override_material(0) as StandardMaterial3D
	_health_bar_fill_material = fill_material.duplicate() as StandardMaterial3D
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)
	_configure_faction_groups()
	_configure_task_navigation_agent()


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
	has_move_target = false
	velocity = Vector3.ZERO
	_health_bar.visible = false

	if _is_enemy_worker():
		EnemyResourceManager.release_food_used(FOOD_SUPPLY_USED)
	else:
		ResourceManager.release_food_used(FOOD_SUPPLY_USED)

	HeroXpRewards.notify_unit_killed(self)
	die()
	print("Worker died")
	queue_free()


func _cancel_build_trip() -> void:
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


func _configure_faction_groups() -> void:
	if not is_in_group(&"enemy_workers"):
		return

	if is_in_group(&"workers"):
		remove_from_group(&"workers")

	if is_in_group(&"units"):
		remove_from_group(&"units")

	if not is_in_group(&"enemies"):
		add_to_group(&"enemies")


func _physics_process(delta: float) -> void:
	if not _is_alive():
		return

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

	if _task_nudge_active:
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
			else:
				_update_task_corner_stuck_detection(delta, position_before)
	elif has_move_target:
		super._physics_process(delta)
	else:
		velocity = Vector3.ZERO

	_update_gather_stuck_recovery(delta)
	_update_construction_stuck_recovery(delta)
	_update_gather_trip()
	_update_build_trip()


func set_movement_target(target: Vector3) -> void:
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


func _reset_gather_stuck_watch() -> void:
	_gather_stuck_watch_position = global_position
	_gather_stuck_watch_time = 0.0


func _configure_task_navigation_agent() -> void:
	if _navigation_agent == null:
		return

	WorkerTaskNavigation.configure_agent(_navigation_agent, stopping_distance)
	call_deferred("_sync_navigation_agent_position")


func _sync_navigation_agent_position() -> void:
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
		var dropoff: CommandCenter = _resolve_dropoff_target()
		if dropoff != null:
			_move_toward_command_center_for_deposit(dropoff)
			return

	if _task_has_saved_destination:
		super.set_movement_target(_task_movement_destination)


func command_gather_gold_mine(gold_mine: GoldMine, player_ordered: bool = true) -> void:
	if not _is_alive():
		return

	print(GOLD_MINE_COMMAND_MESSAGE)
	_start_gathering(gold_mine, player_ordered)


func command_gather_tree(tree: WoodTree, player_ordered: bool = true) -> void:
	if not _is_alive():
		return

	print(TREE_COMMAND_MESSAGE)
	_start_gathering(tree, player_ordered)


func _start_gathering(source: GatherableResource, player_ordered: bool = true) -> void:
	_cancel_build_trip()
	cancel_gathering()
	if source == null or not is_instance_valid(source):
		return

	if (
		not player_ordered
		and CreepCampSafety.is_resource_guarded_by_active_camp(source, get_tree())
	):
		return

	if source is WoodTree:
		var wood_tree: WoodTree = _select_wood_tree(source as WoodTree, player_ordered)
		if wood_tree == null or not is_instance_valid(wood_tree) or not wood_tree.can_gather():
			return
		source = wood_tree
		_lock_to_wood_tree(wood_tree)

	_gather_source = source
	_assigned_resource_id = source.get_resource_id()
	_carried_amount = 0
	_source_approach_candidate_index = 0
	_dropoff_candidate_index = 0
	_return_dropoff = null
	_assigned_dropoff = WorkerGathering.find_nearest_dropoff(
		source.global_position,
		_is_enemy_worker(),
		get_tree()
	)
	_gather_stuck_recovery_cooldown = 0.0
	_reset_gather_stuck_watch()
	_clear_wood_chop_spot()
	_gather_state = GatherTripState.TO_SOURCE
	_set_movement_to_gather_source(source)


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


func start_construction_order(building: Building) -> void:
	if not _is_alive():
		return
	if building == null or not is_instance_valid(building):
		return

	_cancel_build_trip()
	cancel_gathering()
	_build_trip_state = BuildTripState.TO_BUILDING
	_building_target = building
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

	_build_trip_state = BuildTripState.IDLE
	_building_target = null
	_construction_target_point_valid = false

	if _is_enemy_worker():
		_notify_enemy_worker_needs_gather_job()


func _notify_enemy_worker_needs_gather_job() -> void:
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
			if _task_nudge_active:
				return
			if _attempt_source_proximity_resolve():
				return
			if not has_move_target:
				_handle_arrived_at_source()
		GatherTripState.TO_COMMAND_CENTER:
			if _task_nudge_active:
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
			if _task_nudge_active:
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
		_cancel_build_trip()
		return false

	if _building_target.building_state == Building.STATE_COMPLETED:
		on_building_construction_finished()
		return false

	if not is_in_build_start_range():
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

	var dropoff: CommandCenter = _resolve_dropoff_target()
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

	if _task_nudge_active or not has_move_target:
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
		var dropoff: CommandCenter = _resolve_dropoff_target()
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
	var wait_timer: SceneTreeTimer = get_tree().create_timer(GatheringConfig.GATHER_WAIT_SECONDS)
	wait_timer.timeout.connect(_on_gather_wait_finished, CONNECT_ONE_SHOT)


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
	if _is_gathering_wood():
		var dropoff: CommandCenter = WorkerGathering.find_nearest_dropoff(
			global_position,
			_is_enemy_worker(),
			get_tree()
		)
		_return_dropoff = dropoff
		_assigned_dropoff = dropoff
	else:
		_return_dropoff = null
	_gather_state = GatherTripState.TO_COMMAND_CENTER
	_ensure_returning_to_current_dropoff()


func _retry_return_to_command_center() -> void:
	if not _ensure_returning_to_current_dropoff():
		has_move_target = false


func _has_valid_dropoff_target() -> bool:
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
		return false

	if resource_id == &"wood":
		_unlock_wood_tree()
		var scene_root: Node = get_tree().current_scene
		var replacement: WoodTree = WorkerGathering.find_best_wood_tree(
			global_position,
			scene_root,
			_is_enemy_worker(),
			null,
			_get_valid_gather_source(),
			false
		)
		if replacement == null:
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


func _get_dropoff_search_position() -> Vector3:
	var source: GatherableResource = _get_valid_gather_source()
	if source != null:
		return source.global_position

	return global_position


func _resolve_dropoff_target() -> CommandCenter:
	if (
		_is_gathering_wood()
		and _gather_state == GatherTripState.TO_COMMAND_CENTER
		and _return_dropoff != null
		and is_instance_valid(_return_dropoff)
		and WorkerGathering.is_valid_dropoff(_return_dropoff, _is_enemy_worker())
	):
		_assigned_dropoff = _return_dropoff
		return _return_dropoff

	_assigned_dropoff = WorkerGathering.find_nearest_dropoff(
		_get_dropoff_search_position(),
		_is_enemy_worker(),
		get_tree()
	)
	return _assigned_dropoff


func _ensure_returning_to_current_dropoff() -> bool:
	var dropoff: CommandCenter = null
	if (
		_is_gathering_wood()
		and _return_dropoff != null
		and is_instance_valid(_return_dropoff)
		and WorkerGathering.is_valid_dropoff(_return_dropoff, _is_enemy_worker())
	):
		dropoff = _return_dropoff
		_assigned_dropoff = dropoff
	else:
		dropoff = _resolve_dropoff_target()
		if dropoff == null:
			_return_dropoff = null
			return false
		_return_dropoff = dropoff

	if dropoff == _return_dropoff and has_move_target:
		return true

	_return_dropoff = dropoff
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
	if _locked_wood_tree == tree:
		return

	_unlock_wood_tree()
	_clear_wood_chop_spot()
	_locked_wood_tree = tree
	if tree != null and is_instance_valid(tree):
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
	var attempt_limit: int = mini(
		GatheringConfig.APPROACH_OCCUPIED_MAX_ATTEMPTS,
		GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES
	)
	for attempt_offset: int in attempt_limit:
		var candidate_index: int = base_slot + attempt_offset
		fallback_position = _compute_resource_approach_position_for_candidate(
			tree, candidate_index
		)
		if _is_approach_position_occupied(fallback_position, tree):
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


func _is_approach_position_occupied(
	approach_position: Vector3, source: CollisionObject3D = null
) -> bool:
	var occupied_radius_sq: float = (
		GatheringConfig.APPROACH_OCCUPIED_RADIUS * GatheringConfig.APPROACH_OCCUPIED_RADIUS
	)
	var destination_radius_sq: float = (
		GatheringConfig.APPROACH_OCCUPIED_DESTINATION_RADIUS
		* GatheringConfig.APPROACH_OCCUPIED_DESTINATION_RADIUS
	)

	for group_name: StringName in [&"workers", &"enemy_workers"]:
		for node: Node in get_tree().get_nodes_in_group(group_name):
			if node == self or not node is Worker:
				continue

			var other_worker: Worker = node as Worker
			if not is_instance_valid(other_worker):
				continue

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
	var attempt_limit: int = mini(
		GatheringConfig.APPROACH_OCCUPIED_MAX_ATTEMPTS,
		GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES - _source_approach_candidate_index
	)
	for attempt_offset: int in attempt_limit:
		var candidate_index: int = _source_approach_candidate_index + attempt_offset
		fallback_position = _compute_resource_approach_position_for_candidate(
			source, candidate_index
		)
		if _is_approach_position_occupied(fallback_position, source):
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
