class_name Barracks
extends Building

## Placeholder barracks building used for early 3D scene testing.

signal swordsman_queue_changed(queue_count: int)

const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const TRAIN_GOLD_COST: int = 100
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 4.0
const SWORDSMAN_SPAWN_OFFSET: Vector3 = Vector3(3.0, -0.5, 0.0)

var _swordsman_queue_count: int = 0
var _is_training: bool = false


func get_swordsman_queue_count() -> int:
	return _swordsman_queue_count


func try_train_swordsman() -> void:
	if building_state != STATE_COMPLETED:
		return

	if not ResourceManager.can_afford_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		print("Not enough resources")
		return

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		print("Not enough resources")
		return

	_swordsman_queue_count += 1
	swordsman_queue_changed.emit(_swordsman_queue_count)

	if not _is_training:
		_start_next_training()


func _start_next_training() -> void:
	if _swordsman_queue_count <= 0:
		return

	_is_training = true
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(_on_swordsman_training_finished, CONNECT_ONE_SHOT)


func _on_swordsman_training_finished() -> void:
	_is_training = false
	if _swordsman_queue_count <= 0:
		return

	_spawn_swordsman()
	_swordsman_queue_count -= 1
	swordsman_queue_changed.emit(_swordsman_queue_count)

	if _swordsman_queue_count > 0:
		_start_next_training()


func _spawn_swordsman() -> void:
	var swordsman: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		return

	spawn_parent.add_child(swordsman)
	swordsman.global_position = global_position + SWORDSMAN_SPAWN_OFFSET
