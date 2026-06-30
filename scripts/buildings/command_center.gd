class_name CommandCenter
extends Building

## Placeholder command center used for early 3D scene testing.

signal worker_queue_changed(queue_count: int)

const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const TRAIN_GOLD_COST: int = 50
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 3.0
const RALLY_MARKER_Y: float = 0.05

@export var worker_spawn_offset: Vector3 = Vector3(3.5, -0.75, 0.0)

enum RallyTargetType {
	NONE,
	GROUND,
	RESOURCE,
}

var _worker_queue_count: int = 0
var _is_training: bool = false
var _rally_target_type: RallyTargetType = RallyTargetType.NONE
var _rally_point: Vector3 = Vector3.ZERO
var _rally_resource: GatherableResource = null
var _rally_marker: MeshInstance3D = null

@onready var _health_component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent


func _ready() -> void:
	super._ready()
	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


func take_damage(amount: float, _attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	if _rally_marker != null and is_instance_valid(_rally_marker):
		_rally_marker.queue_free()
		_rally_marker = null

	destroy_building()
	queue_free()


func get_worker_queue_count() -> int:
	return _worker_queue_count


func set_rally_point(ground_position: Vector3) -> void:
	_rally_target_type = RallyTargetType.GROUND
	_rally_resource = null
	_rally_point = Vector3(ground_position.x, global_position.y + worker_spawn_offset.y, ground_position.z)
	_update_rally_marker(Vector3(ground_position.x, RALLY_MARKER_Y, ground_position.z))


func set_rally_resource(resource: GatherableResource) -> void:
	if resource == null or not is_instance_valid(resource):
		return

	_rally_target_type = RallyTargetType.RESOURCE
	_rally_resource = resource
	_rally_point = Vector3.ZERO

	var marker_position: Vector3 = resource.global_position
	marker_position.y = RALLY_MARKER_Y
	_update_rally_marker(marker_position)
	resource.play_target_feedback()


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
	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		ResourceManager.show_feedback(
			ResourceManager.get_training_failure_message(TRAIN_GOLD_COST, TRAIN_FOOD_COST)
		)
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
	worker.global_position = global_position + worker_spawn_offset

	_apply_worker_rally(worker)


func _apply_worker_rally(worker: Worker) -> void:
	if worker == null:
		return

	match _rally_target_type:
		RallyTargetType.GROUND:
			worker.set_movement_target(_rally_point)
		RallyTargetType.RESOURCE:
			_assign_worker_to_rally_resource(worker)


func _assign_worker_to_rally_resource(worker: Worker) -> void:
	if not _is_valid_rally_resource(_rally_resource):
		return

	if _rally_resource is GoldMine:
		worker.command_gather_gold_mine(_rally_resource as GoldMine)
	elif _rally_resource is WoodTree:
		worker.command_gather_tree(_rally_resource as WoodTree)


func _is_valid_rally_resource(resource: GatherableResource) -> bool:
	return (
		resource != null
		and is_instance_valid(resource)
		and not resource.is_queued_for_deletion()
		and resource.can_gather()
	)
