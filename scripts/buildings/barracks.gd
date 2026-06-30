class_name Barracks
extends Building

## Placeholder barracks building used for early 3D scene testing.

signal swordsman_queue_changed(queue_count: int)
signal archer_queue_changed(queue_count: int)

const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const TRAIN_GOLD_COST: int = 100
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 4.0
const SWORDSMAN_SPAWN_OFFSET: Vector3 = Vector3(3.0, -0.5, 0.0)
const ARCHER_SPAWN_OFFSET: Vector3 = Vector3(3.0, -0.5, 2.0)
const RALLY_MARKER_Y: float = 0.05

var _swordsman_queue_count: int = 0
var _archer_queue_count: int = 0
var _is_training: bool = false
var _is_training_archer: bool = false
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null


func get_swordsman_queue_count() -> int:
	return _swordsman_queue_count


func get_archer_queue_count() -> int:
	return _archer_queue_count


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
	_spawn_trained_unit(SWORDSMAN_SCENE, SWORDSMAN_SPAWN_OFFSET)


func try_train_archer() -> void:
	if building_state != STATE_COMPLETED:
		return

	if not ResourceManager.can_afford_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		print("Not enough resources")
		return

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		print("Not enough resources")
		return

	_archer_queue_count += 1
	archer_queue_changed.emit(_archer_queue_count)

	if not _is_training_archer:
		_start_next_archer_training()


func _start_next_archer_training() -> void:
	if _archer_queue_count <= 0:
		return

	_is_training_archer = true
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(_on_archer_training_finished, CONNECT_ONE_SHOT)


func _on_archer_training_finished() -> void:
	_is_training_archer = false
	if _archer_queue_count <= 0:
		return

	_spawn_archer()
	_archer_queue_count -= 1
	archer_queue_changed.emit(_archer_queue_count)

	if _archer_queue_count > 0:
		_start_next_archer_training()


func _spawn_archer() -> void:
	_spawn_trained_unit(ARCHER_SCENE, ARCHER_SPAWN_OFFSET)


func _spawn_trained_unit(scene: PackedScene, spawn_offset: Vector3) -> void:
	var unit: Unit = scene.instantiate() as Unit
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or unit == null:
		return

	spawn_parent.add_child(unit)
	unit.global_position = global_position + spawn_offset
	_finalize_spawned_unit(unit)

	if _has_rally_point:
		unit.set_movement_target(_rally_point)


func _finalize_spawned_unit(unit: Unit) -> void:
	unit.collision_layer = PhysicsLayers.UNITS
	unit.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK

	if not unit.is_in_group(&"units"):
		unit.add_to_group(&"units")

	var collision_shape: CollisionShape3D = unit.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		collision_shape.disabled = false
