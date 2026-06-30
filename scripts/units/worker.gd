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

var _gather_state: GatherTripState = GatherTripState.IDLE
var _gather_source: GatherableResource = null
var _carried_amount: int = 0
var _build_trip_state: BuildTripState = BuildTripState.IDLE
var _building_target: Building = null


func _ready() -> void:
	super._ready()
	_configure_faction_groups()


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
	super._physics_process(delta)
	_update_gather_trip()
	_update_build_trip()


func command_gather_gold_mine(gold_mine: GoldMine) -> void:
	print(GOLD_MINE_COMMAND_MESSAGE)
	_start_gathering(gold_mine)


func command_gather_tree(tree: WoodTree) -> void:
	print(TREE_COMMAND_MESSAGE)
	_start_gathering(tree)


func _start_gathering(source: GatherableResource) -> void:
	cancel_gathering()
	_gather_source = source
	_carried_amount = 0
	_gather_state = GatherTripState.TO_SOURCE
	set_movement_target(_compute_approach_position(source))


func cancel_gathering() -> void:
	_gather_state = GatherTripState.IDLE
	_gather_source = null
	_carried_amount = 0


func command_build(building: Building) -> void:
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
	match _gather_state:
		GatherTripState.TO_SOURCE:
			if not has_move_target:
				_handle_arrived_at_source()
		GatherTripState.TO_COMMAND_CENTER:
			_handle_command_center_arrival()


func _update_build_trip() -> void:
	match _build_trip_state:
		BuildTripState.TO_BUILDING:
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
		set_movement_target(_compute_approach_position(_gather_source))
		return

	if not _gather_source.can_gather():
		_finish_gathering_idle()
		return

	if _should_return_to_command_center_from_source():
		_begin_return_to_command_center()
	else:
		_begin_gather_wait()


func _handle_command_center_arrival() -> void:
	if not _has_reached_command_center():
		return

	if _carried_amount > 0:
		_deposit_carried()

	if _carried_amount > 0:
		return

	_continue_gather_cycle()


func _has_reached_command_center() -> bool:
	if not has_move_target:
		return true

	var command_center: CommandCenter = _find_command_center()
	return _is_near_collision_target(command_center)


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
	if _gather_state != GatherTripState.GATHER_WAIT:
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
	if command_center == null:
		_gather_state = GatherTripState.DONE
		return

	_gather_state = GatherTripState.TO_COMMAND_CENTER
	set_movement_target(_compute_approach_position(command_center))


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
	set_movement_target(_compute_approach_position(_gather_source))


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
