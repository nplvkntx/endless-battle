class_name CommandCenter
extends Building

## Placeholder command center used for early 3D scene testing.

signal worker_queue_changed(queue_count: int)

const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const TRAIN_GOLD_COST: int = 50
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 3.0
const WORKER_SPAWN_OFFSET: Vector3 = Vector3(3.5, -0.75, 0.0)

var _worker_queue_count: int = 0
var _is_training: bool = false


func get_worker_queue_count() -> int:
	return _worker_queue_count


func try_train_worker() -> void:
	if not ResourceManager.can_afford_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		print("Not enough resources")
		return

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		print("Not enough resources")
		return

	_worker_queue_count += 1
	worker_queue_changed.emit(_worker_queue_count)

	if not _is_training:
		_start_next_training()


func _start_next_training() -> void:
	if _worker_queue_count <= 0:
		return

	_is_training = true
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(_on_training_finished, CONNECT_ONE_SHOT)


func _on_training_finished() -> void:
	_is_training = false
	if _worker_queue_count <= 0:
		return

	_spawn_worker()
	_worker_queue_count -= 1
	worker_queue_changed.emit(_worker_queue_count)

	if _worker_queue_count > 0:
		_start_next_training()


func _spawn_worker() -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		return

	spawn_parent.add_child(worker)
	worker.global_position = global_position + WORKER_SPAWN_OFFSET
