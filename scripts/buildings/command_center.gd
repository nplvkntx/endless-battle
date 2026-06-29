class_name CommandCenter
extends Building

## Placeholder command center used for early 3D scene testing.

const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const TRAIN_GOLD_COST: int = 50
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 3.0
const WORKER_SPAWN_OFFSET: Vector3 = Vector3(3.5, -0.75, 0.0)

var _is_training: bool = false


func try_train_worker() -> void:
	if _is_training:
		return

	if not ResourceManager.can_afford_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		print("Not enough resources")
		return

	if not ResourceManager.try_spend_gold(TRAIN_GOLD_COST):
		print("Not enough resources")
		return

	_is_training = true
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(_on_training_finished, CONNECT_ONE_SHOT)


func _on_training_finished() -> void:
	_is_training = false
	_spawn_worker()


func _spawn_worker() -> void:
	ResourceManager.add_food_used(TRAIN_FOOD_COST)

	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		return

	spawn_parent.add_child(worker)
	worker.global_position = global_position + WORKER_SPAWN_OFFSET
