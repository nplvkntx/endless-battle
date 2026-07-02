class_name CommandCenter
extends Building

## Placeholder command center used for early 3D scene testing.

signal worker_queue_changed(queue_count: int)
signal repeat_state_changed()

const TRAIN_ID_WORKER: StringName = &"worker"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const TRAIN_GOLD_COST: int = 50
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 3.0
const MAX_ENEMY_WORKER_QUEUE: int = 3
const RALLY_MARKER_Y: float = 0.05
const ENEMY_TEAM_ID: int = 1

@export var worker_spawn_offset: Vector3 = Vector3(0.0, -0.75, -2.8)

enum RallyTargetType {
	NONE,
	GROUND,
	RESOURCE,
}

var _worker_queue_count: int = 0
var _is_training: bool = false
var _training_session: int = 0
var _training_started_at: float = 0.0
var _repeat_enabled: bool = false
var _repeat_unit_type: StringName = &""
var _rally_target_type: RallyTargetType = RallyTargetType.NONE
var _rally_point: Vector3 = Vector3.ZERO
var _rally_resource: GatherableResource = null
var _rally_marker: MeshInstance3D = null

@onready var _health_component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent


func _ready() -> void:
	super._ready()
	if building_state == STATE_COMPLETED:
		_ensure_dropoff_registration()
	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


func complete_construction() -> void:
	super.complete_construction()
	_ensure_dropoff_registration()


func _ensure_dropoff_registration() -> void:
	if is_in_group(&"enemy_command_center") or team_id == ENEMY_TEAM_ID:
		if is_in_group(&"player_command_center"):
			remove_from_group(&"player_command_center")
		if not is_in_group(&"enemy_command_center"):
			add_to_group(&"enemy_command_center")
		return

	if not is_in_group(&"player_command_center"):
		add_to_group(&"player_command_center")
	if is_in_group(&"enemy_command_center"):
		remove_from_group(&"enemy_command_center")


func take_damage(amount: float, _attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	_repeat_enabled = false
	_invalidate_training_session()
	_is_training = false

	if _rally_marker != null and is_instance_valid(_rally_marker):
		_rally_marker.queue_free()
		_rally_marker = null

	destroy_building()
	queue_free()


func get_worker_queue_count() -> int:
	return _worker_queue_count


func is_repeat_training_enabled(train_id: StringName = TRAIN_ID_WORKER) -> bool:
	return _repeat_enabled and _repeat_unit_type == train_id


func get_repeat_unit_display_name() -> String:
	if not _repeat_enabled:
		return ""

	match _repeat_unit_type:
		TRAIN_ID_WORKER:
			return "Worker"
		_:
			return ""


func set_repeat_training(enabled: bool, train_id: StringName = TRAIN_ID_WORKER) -> void:
	_repeat_enabled = enabled
	_repeat_unit_type = train_id if enabled else &""
	repeat_state_changed.emit()


func try_train_worker_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_WORKER):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_WORKER)

	try_train_worker()


func is_training_worker() -> bool:
	return _is_training


func has_active_unit_training() -> bool:
	return _is_training


func get_active_unit_training_progress() -> float:
	if not _is_training:
		return 0.0

	var elapsed: float = _get_time_seconds() - _training_started_at
	return clampf(elapsed / TRAIN_SECONDS, 0.0, 1.0)


func get_active_unit_training_name() -> String:
	return "Worker"


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func cancel_worker_training_at(slot_index: int) -> bool:
	if _worker_queue_count <= 0:
		return false

	var cancel_indices: Array[int] = []
	if slot_index >= 0 and slot_index < _worker_queue_count:
		cancel_indices.append(slot_index)

	var last_index: int = _worker_queue_count - 1
	if not cancel_indices.has(last_index):
		cancel_indices.append(last_index)

	if not cancel_indices.has(0):
		cancel_indices.append(0)

	for cancel_index: int in cancel_indices:
		if _cancel_worker_training_at_index(cancel_index):
			return true

	return false


func _cancel_worker_training_at_index(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _worker_queue_count:
		return false

	if slot_index == 0 and _is_training:
		if is_repeat_training_enabled(TRAIN_ID_WORKER):
			set_repeat_training(false)

		_invalidate_training_session()
		_is_training = false
		_worker_queue_count -= 1
		worker_queue_changed.emit(_worker_queue_count)
		_refund_worker_training_cost()

		if _worker_queue_count > 0:
			_start_next_training()

		return true

	if slot_index == _worker_queue_count - 1 and _worker_queue_count > 1:
		_worker_queue_count -= 1
		worker_queue_changed.emit(_worker_queue_count)
		_refund_worker_training_cost()
		return true

	return false


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


func can_train_enemy_worker() -> bool:
	if not is_in_group(&"enemy_command_center"):
		return false

	if not _is_enemy_worker_training_allowed():
		return false

	if _worker_queue_count >= MAX_ENEMY_WORKER_QUEUE:
		return false

	return EnemyResourceManager.can_afford_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST)


func try_train_enemy_worker() -> bool:
	if not can_train_enemy_worker():
		return false

	if not EnemyResourceManager.try_pay_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		return false

	_worker_queue_count += 1
	worker_queue_changed.emit(_worker_queue_count)

	if not _is_training:
		_start_next_training()

	return true


func _is_enemy_worker_training_allowed() -> bool:
	if (
		building_state == STATE_UNDER_CONSTRUCTION
		or building_state == STATE_CONSTRUCTING
	):
		return false

	if _health_component != null and _health_component.current_health <= 0:
		return false

	return true


func _start_next_training() -> void:
	if _worker_queue_count <= 0:
		return

	_training_session += 1
	var session: int = _training_session
	_is_training = true
	_training_started_at = _get_time_seconds()
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(func() -> void:
		_on_training_finished(session)
	, CONNECT_ONE_SHOT)


func _on_training_finished(session: int) -> void:
	if session != _training_session:
		return

	_is_training = false
	if _worker_queue_count <= 0:
		return

	_spawn_worker()
	_worker_queue_count -= 1
	worker_queue_changed.emit(_worker_queue_count)

	if _worker_queue_count > 0:
		_start_next_training()
	else:
		_try_repeat_worker_training()


func _try_repeat_worker_training() -> void:
	if not is_repeat_training_enabled(TRAIN_ID_WORKER):
		return

	if not is_instance_valid(self) or is_queued_for_deletion():
		set_repeat_training(false)
		return

	if not ResourceManager.can_afford_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		set_repeat_training(false)
		return

	try_train_worker()


func _invalidate_training_session() -> void:
	_training_session += 1


func _refund_worker_training_cost() -> void:
	ResourceManager.add_gold(TRAIN_GOLD_COST)
	ResourceManager.release_food_used(TRAIN_FOOD_COST)


func _spawn_worker() -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		return

	spawn_parent.add_child(worker)
	worker.global_position = global_position + worker_spawn_offset

	if is_in_group(&"enemy_command_center"):
		_finalize_enemy_worker(worker)
	else:
		_apply_worker_rally(worker)


func _finalize_enemy_worker(worker: Worker) -> void:
	if worker == null:
		return

	worker.team_id = ENEMY_TEAM_ID

	if not worker.is_in_group(&"enemy_workers"):
		worker.add_to_group(&"enemy_workers")

	if worker.is_in_group(&"workers"):
		worker.remove_from_group(&"workers")

	if worker.is_in_group(&"units"):
		worker.remove_from_group(&"units")

	if not worker.is_in_group(&"enemies"):
		worker.add_to_group(&"enemies")

	worker.apply_team_visuals()
	_notify_enemy_worker_spawned(worker)


func _notify_enemy_worker_spawned(worker: Worker) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"enemy_build_manager"):
		if node is EnemyBuildManager:
			(node as EnemyBuildManager).notify_enemy_worker_spawned(worker)
			return


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
