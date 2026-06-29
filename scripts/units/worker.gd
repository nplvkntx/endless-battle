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

const GOLD_MINE_COMMAND_MESSAGE: String = "Worker received gold mine command"
const MINING_WAIT_SECONDS: float = 1.0
const GOLD_DEPOSIT_AMOUNT: int = 5

var _gold_mine_trip_state: GoldMineTripState = GoldMineTripState.IDLE
var _gathering_gold_mine: GoldMine = null


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_gold_mine_trip()


func command_gather_gold_mine(gold_mine: GoldMine) -> void:
	print(GOLD_MINE_COMMAND_MESSAGE)
	_gathering_gold_mine = gold_mine
	_gold_mine_trip_state = GoldMineTripState.TO_GOLD_MINE
	set_movement_target(_compute_approach_position(gold_mine))


func cancel_gathering() -> void:
	_gold_mine_trip_state = GoldMineTripState.IDLE
	_gathering_gold_mine = null


func _update_gold_mine_trip() -> void:
	match _gold_mine_trip_state:
		GoldMineTripState.TO_GOLD_MINE:
			if not has_move_target:
				_begin_mining_wait()
		GoldMineTripState.TO_COMMAND_CENTER:
			if not has_move_target:
				_deposit_gold()
				_continue_gathering_cycle()


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
