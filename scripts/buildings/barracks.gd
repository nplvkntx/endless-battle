class_name Barracks
extends Building

## Placeholder barracks building used for early 3D scene testing.

signal swordsman_queue_changed(queue_count: int)

const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const TRAIN_GOLD_COST: int = 100
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 4.0
const SWORDSMAN_SPAWN_OFFSET: Vector3 = Vector3(3.0, -0.5, 0.0)
const RALLY_MARKER_Y: float = 0.05

var _swordsman_queue_count: int = 0
var _is_training: bool = false
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null


func get_swordsman_queue_count() -> int:
	return _swordsman_queue_count


func set_rally_point(ground_position: Vector3) -> void:
	_has_rally_point = true
	_rally_point = Vector3(
		ground_position.x,
		global_position.y + SWORDSMAN_SPAWN_OFFSET.y,
		ground_position.z
	)
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

	if _has_rally_point:
		swordsman.set_movement_target(_rally_point)
