class_name Worker
extends Unit

## Placeholder worker unit used for early 3D scene testing.

enum GoldMineTripState {
	IDLE,
	TO_GOLD_MINE,
	MINING_WAIT,
	TO_COMMAND_CENTER,
	DONE,
}

enum BuildTripState {
	IDLE,
	TO_FARM,
	CONSTRUCTION_WAIT,
	DONE,
}

const GOLD_MINE_COMMAND_MESSAGE: String = "Worker received gold mine command"
const MINING_WAIT_SECONDS: float = 1.0
const GOLD_DEPOSIT_AMOUNT: int = 5

var _gold_mine_trip_state: GoldMineTripState = GoldMineTripState.IDLE
var _gathering_gold_mine: GoldMine = null
var _build_trip_state: BuildTripState = BuildTripState.IDLE
var _building_target: Building = null


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_gold_mine_trip()
	_update_build_trip()


func command_gather_gold_mine(gold_mine: GoldMine) -> void:
	print(GOLD_MINE_COMMAND_MESSAGE)
	_gathering_gold_mine = gold_mine
	_gold_mine_trip_state = GoldMineTripState.TO_GOLD_MINE
	set_movement_target(_compute_approach_position(gold_mine))


func cancel_gathering() -> void:
	_gold_mine_trip_state = GoldMineTripState.IDLE
	_gathering_gold_mine = null


func command_build_farm(farm: Farm) -> void:
	cancel_gathering()
	_build_trip_state = BuildTripState.TO_FARM
	_building_target = farm
	set_movement_target(_compute_approach_position(farm))


func on_building_construction_finished() -> void:
	if _build_trip_state != BuildTripState.CONSTRUCTION_WAIT:
		return

	_build_trip_state = BuildTripState.IDLE
	_building_target = null


func _update_gold_mine_trip() -> void:
	match _gold_mine_trip_state:
		GoldMineTripState.TO_GOLD_MINE:
			if not has_move_target:
				_begin_mining_wait()
		GoldMineTripState.TO_COMMAND_CENTER:
			if not has_move_target:
				_deposit_gold()
				_continue_gathering_cycle()


func _update_build_trip() -> void:
	match _build_trip_state:
		BuildTripState.TO_FARM:
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

	var offset: Vector3 = global_position - _building_target.global_position
	offset.y = 0.0
	var reach_distance: float = (
		stopping_distance
		+ _get_collision_xz_radius(_building_target)
		+ _get_collision_xz_radius(self)
		+ 0.5
	)
	return offset.length_squared() <= reach_distance * reach_distance


func _begin_mining_wait() -> void:
	_gold_mine_trip_state = GoldMineTripState.MINING_WAIT
	var wait_timer: SceneTreeTimer = get_tree().create_timer(MINING_WAIT_SECONDS)
	wait_timer.timeout.connect(_on_mining_wait_finished, CONNECT_ONE_SHOT)


func _on_mining_wait_finished() -> void:
	if _gold_mine_trip_state != GoldMineTripState.MINING_WAIT:
		return

	var command_center: CommandCenter = _find_command_center()
	if command_center == null:
		_gold_mine_trip_state = GoldMineTripState.DONE
		return

	_gold_mine_trip_state = GoldMineTripState.TO_COMMAND_CENTER
	set_movement_target(_compute_approach_position(command_center))


func _deposit_gold() -> void:
	ResourceManager.add_gold(GOLD_DEPOSIT_AMOUNT)


func _continue_gathering_cycle() -> void:
	if _gathering_gold_mine == null or not is_instance_valid(_gathering_gold_mine):
		_gold_mine_trip_state = GoldMineTripState.DONE
		return

	_gold_mine_trip_state = GoldMineTripState.TO_GOLD_MINE
	set_movement_target(_compute_approach_position(_gathering_gold_mine))


func _find_command_center() -> CommandCenter:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	return scene_root.find_child("CommandCenter", true, false) as CommandCenter


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

	return 0.5
