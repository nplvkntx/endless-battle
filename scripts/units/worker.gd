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

var _health_bar_fill_material: StandardMaterial3D
var _gather_state: GatherTripState = GatherTripState.IDLE
var _gather_source: GatherableResource = null
var _carried_amount: int = 0
var _source_approach_candidate_index: int = 0
var _dropoff_candidate_index: int = 0
var _build_trip_state: BuildTripState = BuildTripState.IDLE
var _building_target: Building = null
var _task_movement_destination: Vector3 = Vector3.ZERO
var _task_has_saved_destination: bool = false
var _task_stuck_time: float = 0.0
var _task_nudge_active: bool = false
var _task_nudge_time: float = 0.0
var _task_nudge_direction: Vector3 = Vector3.ZERO
var _task_nudge_start_position: Vector3 = Vector3.ZERO
var _task_nudge_side_sign: float = 1.0
var _task_nudge_side_attempts: int = 0


func _ready() -> void:
	super._ready()
	var fill_material := _health_bar_fill.get_surface_override_material(0) as StandardMaterial3D
	_health_bar_fill_material = fill_material.duplicate() as StandardMaterial3D
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_update_health_bar(_health_component.current_health, _health_component.max_health)
	_configure_faction_groups()


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


func take_damage(amount: float, attacker: Node = null) -> void:
	if not _is_alive():
		return

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

	if not _is_enemy_worker():
		ResourceManager.release_food_used(FOOD_SUPPLY_USED)

	die()
	print("Worker died")
	queue_free()


func _cancel_build_trip() -> void:
	_build_trip_state = BuildTripState.IDLE
	_building_target = null
	_task_has_saved_destination = false
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
	else:
		super._physics_process(delta)
		if _is_on_task_movement() and has_move_target:
			_update_task_corner_stuck_detection(delta, position_before)

	_update_gather_trip()
	_update_build_trip()


func set_movement_target(target: Vector3) -> void:
	super.set_movement_target(target)
	if _is_on_task_movement():
		_task_movement_destination = Vector3(target.x, global_position.y, target.z)
		_task_has_saved_destination = true
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
	_task_nudge_side_attempts = 0
	_task_nudge_side_sign = 1.0


func _update_task_corner_stuck_detection(delta: float, position_before: Vector3) -> void:
	var moved: Vector3 = global_position - position_before
	moved.y = 0.0
	var expected_move: float = (
		move_speed * delta * GatheringConfig.TASK_CORNER_NUDGE_STUCK_MOVE_RATIO
	)
	var hit_obstacle: bool = get_slide_collision_count() > 0
	var is_stuck: bool = hit_obstacle and moved.length() < expected_move

	if not is_stuck:
		_task_stuck_time = 0.0
		return

	_task_stuck_time += delta
	if _task_stuck_time >= GatheringConfig.TASK_CORNER_NUDGE_STUCK_DELAY:
		_begin_task_corner_nudge()


func _begin_task_corner_nudge() -> void:
	if not _task_has_saved_destination:
		return

	has_move_target = false
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

	if _task_has_saved_destination and _is_on_task_movement():
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
	_carried_amount = 0
	_source_approach_candidate_index = 0
	_dropoff_candidate_index = 0
	_gather_state = GatherTripState.TO_SOURCE
	set_movement_target(_compute_resource_approach_position(source))


func cancel_gathering() -> void:
	_gather_state = GatherTripState.IDLE
	_gather_source = null
	_carried_amount = 0
	_source_approach_candidate_index = 0
	_dropoff_candidate_index = 0
	_task_has_saved_destination = false
	_reset_task_corner_nudge()


func command_build(building: Building) -> void:
	if not _is_alive():
		return

	cancel_gathering()
	_build_trip_state = BuildTripState.TO_BUILDING
	_building_target = building
	set_movement_target(_compute_approach_position(building))


func command_build_farm(farm: Farm) -> void:
	command_build(farm)


func on_building_construction_finished() -> void:
	if _build_trip_state != BuildTripState.CONSTRUCTION_WAIT:
		return

	_build_trip_state = BuildTripState.IDLE
	_building_target = null


func _update_gather_trip() -> void:
	if not _is_alive():
		return

	match _gather_state:
		GatherTripState.TO_SOURCE:
			if _task_nudge_active:
				return
			if not has_move_target:
				_handle_arrived_at_source()
		GatherTripState.TO_COMMAND_CENTER:
			if _task_nudge_active:
				return
			_handle_command_center_arrival()


func _update_build_trip() -> void:
	if not _is_alive():
		return

	match _build_trip_state:
		BuildTripState.TO_BUILDING:
			if _task_nudge_active:
				return
			if not has_move_target:
				if _is_near_building_target():
					_begin_construction_wait()
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
	if _building_target == null:
		return false

	return _is_near_collision_target(_building_target)


func _is_near_collision_target(target: CollisionObject3D) -> bool:
	if target == null:
		return false

	var offset: Vector3 = global_position - target.global_position
	offset.y = 0.0
	var reach_distance: float = (
		stopping_distance
		+ _get_collision_xz_radius(target)
		+ _get_collision_xz_radius(self)
		+ 0.5
	)
	return offset.length_squared() <= reach_distance * reach_distance


func _handle_arrived_at_source() -> void:
	if _gather_source == null or not is_instance_valid(_gather_source):
		_gather_state = GatherTripState.DONE
		return

	if not _is_near_collision_target(_gather_source):
		_source_approach_candidate_index += 1
		if _source_approach_candidate_index >= GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES:
			_finish_gathering_idle()
			return

		set_movement_target(_compute_resource_approach_position(_gather_source))
		return

	_source_approach_candidate_index = 0

	if not _gather_source.can_gather():
		_finish_gathering_idle()
		return

	if _should_return_to_command_center_from_source():
		_begin_return_to_command_center()
	else:
		_begin_gather_wait()


func _handle_command_center_arrival() -> void:
	var command_center: CommandCenter = _find_command_center()
	if command_center == null or not _can_use_command_center_for_deposit(command_center):
		_finish_gathering_idle()
		return

	if _is_near_command_center_for_deposit(command_center):
		if _carried_amount > 0:
			_deposit_carried()

		if _carried_amount > 0:
			return

		_dropoff_candidate_index = 0
		_continue_gather_cycle()
		return

	if not has_move_target:
		_dropoff_candidate_index += 1
		if _dropoff_candidate_index >= GatheringConfig.MAX_GATHER_APPROACH_CANDIDATES:
			if _carried_amount > 0 and _is_near_command_center_for_deposit(
				command_center, true
			):
				_deposit_carried()
				if _carried_amount <= 0:
					_dropoff_candidate_index = 0
					_continue_gather_cycle()
				return

			_finish_gathering_idle()
			return

		set_movement_target(_compute_command_center_dropoff_position(command_center))



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

	if _gather_source == null or not is_instance_valid(_gather_source):
		_gather_state = GatherTripState.DONE
		return

	var gathered: int = _gather_source.gather(_gather_source.get_gather_chunk_size())
	_carried_amount += gathered

	if _carried_amount <= 0 and not _gather_source.can_gather():
		_finish_gathering_idle()
		return

	if _should_return_to_command_center_from_source():
		_begin_return_to_command_center()
	elif _gather_source.can_gather():
		_begin_gather_wait()
	elif _carried_amount > 0:
		_begin_return_to_command_center()
	else:
		_finish_gathering_idle()


func _begin_return_to_command_center() -> void:
	var command_center: CommandCenter = _find_command_center()
	if command_center == null or not _can_use_command_center_for_deposit(command_center):
		_gather_state = GatherTripState.DONE
		return

	_dropoff_candidate_index = 0
	_gather_state = GatherTripState.TO_COMMAND_CENTER
	set_movement_target(_compute_command_center_dropoff_position(command_center))


func _deposit_carried() -> void:
	if _gather_source == null:
		return

	WorkerGathering.deposit(
		_gather_source.get_resource_id(),
		_carried_amount,
		_is_enemy_worker()
	)
	_carried_amount = 0


func _continue_gather_cycle() -> void:
	if _gather_source == null or not is_instance_valid(_gather_source):
		_finish_gathering_idle()
		return

	if not _gather_source.can_gather():
		_finish_gathering_idle()
		return

	_gather_state = GatherTripState.TO_SOURCE
	_source_approach_candidate_index = 0
	set_movement_target(_compute_resource_approach_position(_gather_source))


func _finish_gathering_idle() -> void:
	_gather_state = GatherTripState.IDLE
	_gather_source = null
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
	for node: Node in get_tree().get_nodes_in_group(&"enemy_command_center"):
		if node is CommandCenter:
			return node as CommandCenter

	return null


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

	if _source_approach_candidate_index > 0:
		var angle: float = deg_to_rad(float(_source_approach_candidate_index * 45))
		direction = direction.normalized().rotated(Vector3.UP, angle)

	var stand_off_distance: float = (
		_get_collision_xz_radius(source)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
	)
	var approach_position: Vector3 = target_center + direction.normalized() * stand_off_distance
	approach_position.y = global_position.y
	return approach_position


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
		var angle: float = deg_to_rad(float(_dropoff_candidate_index * 45))
		direction = direction.normalized().rotated(Vector3.UP, angle)
	else:
		direction = direction.normalized()

	var stand_off_distance: float = (
		_get_collision_xz_radius(command_center)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
		+ 0.25
	)
	var dropoff_position: Vector3 = target_center + direction * stand_off_distance
	dropoff_position.y = global_position.y
	return dropoff_position


func _compute_approach_position(target: CollisionObject3D) -> Vector3:
	var target_center: Vector3 = target.global_position
	var direction: Vector3 = global_position - target_center
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	var stand_off_distance: float = (
		_get_collision_xz_radius(target)
		+ _get_collision_xz_radius(self)
		+ stopping_distance
	)
	var approach_position: Vector3 = target_center + direction.normalized() * stand_off_distance
	approach_position.y = global_position.y
	return approach_position


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
