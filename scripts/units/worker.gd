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

	die()
	print("Worker died")
	queue_free()


func _cancel_build_trip() -> void:
	_build_trip_state = BuildTripState.IDLE
	_building_target = null
	_build_approach_candidate_index = 0
	_task_has_saved_destination = false
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
			_update_task_corner_stuck_detection(delta, position_before)
	elif has_move_target:
		super._physics_process(delta)
	else:
		velocity = Vector3.ZERO

	_update_gather_trip()
	_update_build_trip()


func set_movement_target(target: Vector3) -> void:
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

	if not WorkerTaskNavigation.can_use(_navigation_agent):
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
		var command_center: CommandCenter = _find_command_center()
		if command_center != null and _can_use_command_center_for_deposit(command_center):
			_move_toward_command_center_for_deposit(command_center)
			return

	if _task_has_saved_destination:
		super.set_movement_target(_task_movement_destination)


func command_gather_gold_mine(gold_mine: GoldMine) -> void:
	if not _is_alive():
		return

	print(GOLD_MINE_COMMAND_MESSAGE)
	_start_gathering(gold_mine)


func command_gather_tree(tree: WoodTree) -> void:
	if not _is_alive():
		return

	print(TREE_COMMAND_MESSAGE)
	_start_gathering(tree)


func _start_gathering(source: GatherableResource) -> void:
	cancel_gathering()
	_gather_source = source
	_assigned_resource_id = source.get_resource_id()
	_carried_amount = 0
	_source_approach_candidate_index = 0
	_dropoff_candidate_index = 0
	_gather_state = GatherTripState.TO_SOURCE
	set_movement_target(_compute_resource_approach_position(source))


func cancel_gathering() -> void:
	_gather_state = GatherTripState.IDLE
	_gather_source = null
	_assigned_resource_id = &""
	_carried_amount = 0
	_source_approach_candidate_index = 0
	_dropoff_candidate_index = 0
	_task_has_saved_destination = false
	_disable_task_navigation()
	_reset_task_corner_nudge()


func command_build(building: Building) -> void:
	if not _is_alive():
		return

	cancel_gathering()
	_build_trip_state = BuildTripState.TO_BUILDING
	_building_target = building
	_build_approach_candidate_index = 0
	set_movement_target(_compute_approach_position(building, _build_approach_candidate_index))


func command_build_farm(farm: Farm) -> void:
	command_build(farm)


func on_building_construction_finished() -> void:
	if _build_trip_state != BuildTripState.CONSTRUCTION_WAIT:
		return

	_build_trip_state = BuildTripState.IDLE
	_building_target = null

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
			if _attempt_dropoff_proximity_resolve():
				return
			if not has_move_target:
				if _carried_amount > 0 and not _has_valid_dropoff_target():
					_retry_return_to_command_center()
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
			if _building_target != null and _is_near_building_target():
				has_move_target = false
				_begin_construction_wait()
				return
			if not has_move_target:
				if _is_near_building_target():
					_begin_construction_wait()
				elif _advance_task_approach_candidate():
					_apply_current_task_movement_target()
				else:
					_build_trip_state = BuildTripState.IDLE
					_building_target = null


func _begin_construction_wait() -> void:
	if _building_target == null or not is_instance_valid(_building_target):
		_build_trip_state = BuildTripState.DONE
		_building_target = null
		return

	_build_trip_state = BuildTripState.CONSTRUCTION_WAIT
	_building_target.register_builder(self)


func _is_near_building_target() -> bool:
	if _building_target == null or not is_instance_valid(_building_target):
		return false

	return _is_near_collision_target(
		_building_target, GatheringConfig.RESOURCE_INTERACTION_REACH_BONUS
	)


func _attempt_source_proximity_resolve() -> bool:
	if not _is_valid_gather_source(_gather_source):
		_handle_gather_source_lost()
		return true

	if not _is_near_resource_for_gather(_gather_source):
		return false

	has_move_target = false
	_disable_task_navigation()
	_handle_arrived_at_source()
	return true


func _attempt_dropoff_proximity_resolve() -> bool:
	if _carried_amount <= 0:
		return false

	var command_center: CommandCenter = _find_command_center()
	if command_center == null or not _can_use_command_center_for_deposit(command_center):
		return false

	if not _is_near_command_center_for_deposit(command_center, true):
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
	if _build_trip_state == BuildTripState.TO_BUILDING and _is_near_building_target():
		has_move_target = false
		_disable_task_navigation()
		_begin_construction_wait()
		return true

	return false


func _try_repath_task_movement() -> void:
	if not _is_on_task_movement() or _task_nudge_active:
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
		var command_center: CommandCenter = _find_command_center()
		if command_center != null and _can_use_command_center_for_deposit(command_center):
			_move_toward_command_center_for_deposit(command_center)
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
		_build_approach_candidate_index += 1
		return (
			_build_approach_candidate_index
			< GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES
		)

	return false


func _apply_current_task_movement_target() -> void:
	match _gather_state:
		GatherTripState.TO_SOURCE:
			if not _is_valid_gather_source(_gather_source):
				_handle_gather_source_lost()
				return
			set_movement_target(_compute_resource_approach_position(_gather_source))
		GatherTripState.TO_COMMAND_CENTER:
			var command_center: CommandCenter = _find_command_center()
			if command_center == null or not _can_use_command_center_for_deposit(command_center):
				return
			set_movement_target(_compute_command_center_dropoff_position(command_center))
		_:
			pass

	if _build_trip_state == BuildTripState.TO_BUILDING:
		if _building_target == null or not is_instance_valid(_building_target):
			_build_trip_state = BuildTripState.IDLE
			_building_target = null
			return

		set_movement_target(
			_compute_approach_position(_building_target, _build_approach_candidate_index)
		)


func _is_valid_gather_source(source: GatherableResource) -> bool:
	return (
		source != null
		and is_instance_valid(source)
		and not source.is_queued_for_deletion()
	)


func _is_near_resource_for_gather(source: CollisionObject3D) -> bool:
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
	if not _is_valid_gather_source(_gather_source):
		_handle_gather_source_lost()
		return

	if not _is_near_resource_for_gather(_gather_source):
		if _advance_task_approach_candidate():
			_apply_current_task_movement_target()
			return

		if not _is_near_collision_target(
			_gather_source, GatheringConfig.GATHER_LAST_RESORT_REACH_BONUS
		):
			_handle_gather_source_lost()
			return

	_source_approach_candidate_index = 0

	if not _gather_source.can_gather():
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
	var command_center: CommandCenter = _find_command_center()
	if command_center == null or not _can_use_command_center_for_deposit(command_center):
		if _carried_amount > 0:
			return
		_finish_gathering_idle()
		return

	if _carried_amount > 0:
		if _try_deposit_at_command_center(command_center):
			_dropoff_candidate_index = 0
			_continue_gather_cycle()
			return

		if _advance_task_approach_candidate():
			_apply_current_task_movement_target()
			return

		_move_toward_command_center_for_deposit(command_center)
		return

	_dropoff_candidate_index = 0
	_continue_gather_cycle()



func _should_return_to_command_center_from_source() -> bool:
	if _carried_amount <= 0:
		return false

	if not _gather_source.gathers_until_carry_full():
		return true

	return (
		_carried_amount >= GatheringConfig.WORKER_CARRY_CAPACITY
		or not _gather_source.can_gather()
	)


func _begin_gather_wait() -> void:
	_gather_state = GatherTripState.GATHER_WAIT
	var wait_timer: SceneTreeTimer = get_tree().create_timer(GatheringConfig.GATHER_WAIT_SECONDS)
	wait_timer.timeout.connect(_on_gather_wait_finished, CONNECT_ONE_SHOT)


func _on_gather_wait_finished() -> void:
	if not _is_alive() or _gather_state != GatherTripState.GATHER_WAIT:
		return

	if not _is_valid_gather_source(_gather_source):
		if _carried_amount > 0:
			_begin_return_to_command_center()
		elif not _try_reassign_gather_source():
			_finish_gathering_idle()
		return

	var gathered: int = _gather_source.gather(_gather_source.get_gather_chunk_size())
	_carried_amount += gathered

	if _carried_amount <= 0 and not _gather_source.can_gather():
		if not _try_reassign_gather_source():
			_finish_gathering_idle()
		return

	if _should_return_to_command_center_from_source():
		_begin_return_to_command_center()
	elif _gather_source.can_gather():
		_begin_gather_wait()
	elif _carried_amount > 0:
		_begin_return_to_command_center()
	else:
		if not _try_reassign_gather_source():
			_finish_gathering_idle()


func _begin_return_to_command_center() -> void:
	_dropoff_candidate_index = 0
	_gather_state = GatherTripState.TO_COMMAND_CENTER
	_retry_return_to_command_center()


func _retry_return_to_command_center() -> void:
	var command_center: CommandCenter = _find_command_center()
	if command_center == null or not _can_use_command_center_for_deposit(command_center):
		return

	set_movement_target(_compute_command_center_dropoff_position(command_center))


func _has_valid_dropoff_target() -> bool:
	var command_center: CommandCenter = _find_command_center()
	return command_center != null and _can_use_command_center_for_deposit(command_center)


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

	if _is_valid_gather_source(_gather_source):
		return _gather_source.get_resource_id()

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

	var target: Vector3 = command_center.global_position
	target.y = global_position.y
	_dropoff_candidate_index = 0
	set_movement_target(_snap_task_target_to_navigation(target))


func _continue_gather_cycle() -> void:
	if not _is_valid_gather_source(_gather_source) or not _gather_source.can_gather():
		if _try_reassign_gather_source():
			return
		_finish_gathering_idle()
		return

	_gather_state = GatherTripState.TO_SOURCE
	_source_approach_candidate_index = 0
	set_movement_target(_compute_resource_approach_position(_gather_source))


func _handle_gather_source_lost() -> void:
	if _carried_amount > 0:
		_begin_return_to_command_center()
		return

	if not _try_reassign_gather_source():
		_finish_gathering_idle()


func _try_reassign_gather_source() -> bool:
	var resource_id: StringName = _get_assigned_resource_id()
	if resource_id.is_empty():
		return false

	var scene_root: Node = get_tree().current_scene
	var replacement: GatherableResource = WorkerGathering.find_nearest_gather_source(
		resource_id,
		global_position,
		scene_root,
		_is_enemy_worker(),
		_gather_source if _is_valid_gather_source(_gather_source) else null
	)
	if replacement == null:
		return false

	_gather_source = replacement
	_assigned_resource_id = replacement.get_resource_id()
	_source_approach_candidate_index = 0
	_gather_state = GatherTripState.TO_SOURCE
	set_movement_target(_compute_resource_approach_position(replacement))
	return true


func _get_assigned_resource_id() -> StringName:
	if not _assigned_resource_id.is_empty():
		return _assigned_resource_id

	if _is_valid_gather_source(_gather_source):
		return _gather_source.get_resource_id()

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
		var command_center: CommandCenter = _find_command_center()
		if command_center != null and _try_deposit_at_command_center(command_center):
			pass
		if _carried_amount > 0:
			return

	_gather_state = GatherTripState.IDLE
	_gather_source = null
	_assigned_resource_id = &""
	_carried_amount = 0


func _find_command_center() -> CommandCenter:
	if _is_enemy_worker():
		return _find_enemy_command_center()

	return _find_player_command_center()


func _is_enemy_worker() -> bool:
	return is_in_group(&"enemy_workers")


func _find_player_command_center() -> CommandCenter:
	var closest_command_center: CommandCenter = null
	var closest_distance_squared: float = INF

	for node: Node in get_tree().get_nodes_in_group(&"player_command_center"):
		if not node is CommandCenter:
			continue

		var command_center: CommandCenter = node as CommandCenter
		if not _can_use_command_center_for_deposit(command_center):
			continue

		var offset: Vector3 = global_position - command_center.global_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_command_center = command_center

	return closest_command_center


func _can_use_command_center_for_deposit(command_center: CommandCenter) -> bool:
	if command_center == null or not is_instance_valid(command_center):
		return false

	if command_center.is_queued_for_deletion():
		return false

	if (
		command_center.building_state == Building.STATE_UNDER_CONSTRUCTION
		or command_center.building_state == Building.STATE_CONSTRUCTING
	):
		return false

	var health_component: HealthComponent = (
		command_center.get_node_or_null("HealthComponent") as HealthComponent
	)
	if health_component != null and health_component.current_health <= 0:
		return false

	return true


func _find_enemy_command_center() -> CommandCenter:
	var closest_command_center: CommandCenter = null
	var closest_distance_squared: float = INF

	for node: Node in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if not node is CommandCenter:
			continue

		var command_center: CommandCenter = node as CommandCenter
		if not _can_use_command_center_for_deposit(command_center):
			continue

		var offset: Vector3 = global_position - command_center.global_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_command_center = command_center

	return closest_command_center


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


func _compute_resource_approach_position(source: CollisionObject3D) -> Vector3:
	if source == null:
		return global_position

	var target_center: Vector3 = source.global_position
	var direction: Vector3 = global_position - target_center
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	direction = _apply_approach_candidate_offset(direction, _source_approach_candidate_index)

	var ring: int = (
		_source_approach_candidate_index / GatheringConfig.APPROACH_CANDIDATES_PER_RING
	)
	var stand_off_distance: float = (
		_get_collision_xz_radius(source)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
		+ float(ring) * GatheringConfig.APPROACH_RING_STANDOFF_STEP
	)
	var approach_position: Vector3 = target_center + direction.normalized() * stand_off_distance
	approach_position.y = global_position.y
	return _snap_task_target_to_navigation(approach_position)


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
