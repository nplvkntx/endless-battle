class_name CommandCenter
extends Building

## Placeholder command center used for early 3D scene testing.

signal worker_queue_changed(queue_count: int)

const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const TRAIN_GOLD_COST: int = 50
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 3.0
const WORKER_SPAWN_OFFSET: Vector3 = Vector3(3.5, -0.75, 0.0)
const RALLY_MARKER_Y: float = 0.05

var _worker_queue_count: int = 0
var _is_training: bool = false
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null


func get_worker_queue_count() -> int:
	return _worker_queue_count


func set_rally_point(ground_position: Vector3) -> void:
	_has_rally_point = true
	_rally_point = Vector3(ground_position.x, global_position.y + WORKER_SPAWN_OFFSET.y, ground_position.z)
	_update_rally_marker(Vector3(ground_position.x, RALLY_MARKER_Y, ground_position.z))


func _update_rally_marker(marker_position: Vector3) -> void:
	if _rally_marker == null:
		_rally_marker = MeshInstance3D.new()
		var marker_mesh := CylinderMesh.new()
		marker_mesh.top_radius = 0.45
		marker_mesh.bottom_radius = 0.45
		marker_mesh.height = 0.08
		_rally_marker.mesh = marker_mesh

		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = Color(0.2, 0.85, 0.35, 0.9)
		marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_rally_marker.material_override = marker_material

		var marker_parent: Node = get_parent()
		if marker_parent == null:
			return

		marker_parent.add_child(_rally_marker)

	_rally_marker.global_position = marker_position


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

	if _has_rally_point:
		worker.set_movement_target(_rally_point)
