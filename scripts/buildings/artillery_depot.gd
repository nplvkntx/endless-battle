class_name ArtilleryDepot
extends Building

## Tier 3 military workshop that trains horse-drawn cannons.

signal cannon_queue_changed(queue_count: int)
signal training_queue_changed()
signal repeat_state_changed()

const TRAIN_ID_CANNON: StringName = &"cannon"

const CANNON_SCENE: PackedScene = preload("res://scenes/units/cannon.tscn")
const CANNON_TRAIN_GOLD_COST: int = 275
const CANNON_TRAIN_FOOD_COST: int = 2
const CANNON_TRAIN_SECONDS: float = 14.0
const RALLY_MARKER_Y: float = 0.05
const RALLY_SLOT_SPACING: float = 2.0

@export var cannon_spawn_offset: Vector3 = Vector3(0.0, -0.5, -2.8)

var _training_queue: Array[StringName] = []
var _is_training: bool = false
var _training_session: int = 0
var _training_started_at: float = 0.0
var _current_training_id: StringName = &""
var _current_training_seconds: float = 0.0
var _repeat_enabled: bool = false
var _repeat_unit_type: StringName = &""
var _repeat_waiting_for_resources: bool = false
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null
var _rally_next_slot: int = 0

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	_disconnect_player_resource_listener()


func can_show_commands() -> bool:
	if building_state != STATE_COMPLETED:
		return false

	return TeamVisuals.resolve_team(self, team_id) == TeamVisuals.PLAYER_TEAM_ID


func take_damage(amount: float, attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(self, attacker)
	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	_repeat_enabled = false
	_repeat_waiting_for_resources = false
	_disconnect_player_resource_listener()
	_training_session += 1
	_is_training = false
	_current_training_id = &""
	_training_queue.clear()

	if _rally_marker != null and is_instance_valid(_rally_marker):
		_rally_marker.queue_free()
		_rally_marker = null

	destroy_building()
	queue_free()


func get_training_queue() -> Array[StringName]:
	return _training_queue.duplicate()


func get_cannon_queue_count() -> int:
	return _count_queued_units(TRAIN_ID_CANNON)


func get_total_queue_count() -> int:
	return _training_queue.size()


func _count_queued_units(train_id: StringName) -> int:
	var count: int = 0
	for queued_id: StringName in _training_queue:
		if queued_id == train_id:
			count += 1
	return count


func is_repeat_training_enabled(train_id: StringName) -> bool:
	return _repeat_enabled and _repeat_unit_type == train_id


func get_repeat_unit_display_name() -> String:
	if not _repeat_enabled:
		return ""

	if _repeat_unit_type == TRAIN_ID_CANNON:
		return "Cannon"

	return ""


func set_repeat_training(enabled: bool, train_id: StringName = &"") -> void:
	_repeat_enabled = enabled
	_repeat_unit_type = train_id if enabled else &""
	if not enabled:
		_repeat_waiting_for_resources = false
		_disconnect_player_resource_listener()
	repeat_state_changed.emit()


func try_train_cannon_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_CANNON):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_CANNON)
		_try_repeat_training()
		return

	try_train_cannon()


func is_training_cannon() -> bool:
	return _is_training and _current_training_id == TRAIN_ID_CANNON


func has_active_unit_training() -> bool:
	return _is_training


func get_active_unit_training_progress() -> float:
	if not _is_training:
		return 0.0

	var elapsed: float = _get_time_seconds() - _training_started_at
	return clampf(elapsed / _current_training_seconds, 0.0, 1.0)


func get_active_unit_training_name() -> String:
	if _current_training_id == TRAIN_ID_CANNON:
		return "Cannon"

	return ""


static func get_unit_train_gold_cost(train_id: StringName) -> int:
	if train_id == TRAIN_ID_CANNON:
		return CANNON_TRAIN_GOLD_COST
	return CANNON_TRAIN_GOLD_COST


static func get_unit_train_food_cost(train_id: StringName) -> int:
	if train_id == TRAIN_ID_CANNON:
		return CANNON_TRAIN_FOOD_COST
	return CANNON_TRAIN_FOOD_COST


static func get_unit_train_seconds(train_id: StringName) -> float:
	if train_id == TRAIN_ID_CANNON:
		return CANNON_TRAIN_SECONDS
	return CANNON_TRAIN_SECONDS


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func cancel_cannon_training_at(slot_index: int) -> bool:
	return cancel_training_at(_map_type_slot_to_queue_index(TRAIN_ID_CANNON, slot_index))


func cancel_training_at(slot_index: int) -> bool:
	if _training_queue.is_empty():
		return false

	var cancel_indices: Array[int] = []
	if slot_index >= 0 and slot_index < _training_queue.size():
		cancel_indices.append(slot_index)

	var last_index: int = _training_queue.size() - 1
	if not cancel_indices.has(last_index):
		cancel_indices.append(last_index)

	if not cancel_indices.has(0):
		cancel_indices.append(0)

	for cancel_index: int in cancel_indices:
		if _cancel_training_at_index(cancel_index):
			return true

	return false


func _map_type_slot_to_queue_index(train_id: StringName, type_slot_index: int) -> int:
	var seen: int = 0
	for queue_index: int in _training_queue.size():
		if _training_queue[queue_index] == train_id:
			if seen == type_slot_index:
				return queue_index
			seen += 1
	return -1


func _cancel_training_at_index(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _training_queue.size():
		return false

	if slot_index == 0 and _is_training:
		var cancelled_id: StringName = _training_queue[0]
		if is_repeat_training_enabled(cancelled_id):
			set_repeat_training(false)

		_training_session += 1
		_is_training = false
		_current_training_id = &""
		_training_queue.remove_at(0)
		_emit_queue_changed()
		_refund_training_cost(cancelled_id)

		if not _training_queue.is_empty():
			_start_next_training()
		else:
			_try_repeat_training()

		return true

	if slot_index == _training_queue.size() - 1 and _training_queue.size() > 1:
		var cancelled_id: StringName = _training_queue[slot_index]
		_training_queue.remove_at(slot_index)
		_emit_queue_changed()
		_refund_training_cost(cancelled_id)
		return true

	return false


func set_rally_point(ground_position: Vector3) -> void:
	_has_rally_point = true
	_rally_point = Vector3(
		ground_position.x,
		global_position.y + cannon_spawn_offset.y,
		ground_position.z
	)
	_rally_next_slot = 0
	_update_rally_marker(Vector3(ground_position.x, RALLY_MARKER_Y, ground_position.z))


func _claim_rally_move_target() -> Vector3:
	var slot_index: int = _rally_next_slot
	_rally_next_slot += 1
	return GroupMoveSpacing.compute_slot_target(_rally_point, slot_index, RALLY_SLOT_SPACING)


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


func try_train_cannon() -> void:
	_try_train_player_unit(TRAIN_ID_CANNON)


func _try_train_player_unit(train_id: StringName) -> void:
	if building_state != STATE_COMPLETED:
		return

	var gold_cost: int = get_unit_train_gold_cost(train_id)
	var food_cost: int = get_unit_train_food_cost(train_id)
	if not ResourceManager.try_pay_worker_training(gold_cost, food_cost):
		ResourceManager.show_feedback(
			ResourceManager.get_training_failure_message(gold_cost, food_cost)
		)
		return

	_enqueue_training(train_id)


func _is_enemy_owned() -> bool:
	return TeamVisuals.resolve_team(self, team_id) != TeamVisuals.PLAYER_TEAM_ID


func _get_unit_training_speed_multiplier() -> float:
	if UpgradeManager.has_faster_unit_training(_is_enemy_owned()):
		return UpgradeManager.FASTER_UNIT_TRAINING_SPEED_MULTIPLIER
	return 1.0


func _get_effective_train_seconds(train_id: StringName) -> float:
	return TrainingConfig.get_train_seconds(
		get_unit_train_seconds(train_id),
		_get_unit_training_speed_multiplier()
	)


func _enqueue_training(train_id: StringName) -> void:
	_training_queue.append(train_id)
	_emit_queue_changed()

	if not _is_training:
		_start_next_training()


func _start_next_training() -> void:
	if _training_queue.is_empty():
		_try_repeat_training()
		return

	_training_session += 1
	var session: int = _training_session
	_current_training_id = _training_queue[0]
	_is_training = true
	_training_started_at = _get_time_seconds()
	_current_training_seconds = _get_effective_train_seconds(_current_training_id)
	var wait_timer: SceneTreeTimer = get_tree().create_timer(
		_current_training_seconds
	)
	wait_timer.timeout.connect(func() -> void:
		_on_training_finished(session)
	, CONNECT_ONE_SHOT)


func _on_training_finished(session: int) -> void:
	if session != _training_session:
		return

	_is_training = false
	if _training_queue.is_empty():
		_current_training_id = &""
		_try_repeat_training()
		return

	if _training_queue[0] == TRAIN_ID_CANNON:
		_spawn_cannon()

	_training_queue.remove_at(0)
	_emit_queue_changed()

	if not _training_queue.is_empty():
		_start_next_training()
	else:
		_current_training_id = &""
		_try_repeat_training()


func _try_repeat_training() -> void:
	if not _repeat_enabled:
		return

	if not is_instance_valid(self) or is_queued_for_deletion() or building_state != STATE_COMPLETED:
		set_repeat_training(false)
		return

	if _is_training or not _training_queue.is_empty():
		return

	if not _can_pay_training_costs():
		_repeat_waiting_for_resources = true
		_ensure_player_resource_listener()
		return

	_repeat_waiting_for_resources = false
	_disconnect_player_resource_listener()

	if not _pay_training_costs():
		_repeat_waiting_for_resources = true
		_ensure_player_resource_listener()
		return

	_enqueue_training(_repeat_unit_type)


func _can_pay_training_costs() -> bool:
	return ResourceManager.can_afford_worker_training(
		get_unit_train_gold_cost(_repeat_unit_type),
		get_unit_train_food_cost(_repeat_unit_type)
	)


func _pay_training_costs() -> bool:
	return ResourceManager.try_pay_worker_training(
		get_unit_train_gold_cost(_repeat_unit_type),
		get_unit_train_food_cost(_repeat_unit_type)
	)


func _ensure_player_resource_listener() -> void:
	if not ResourceManager.resources_changed.is_connected(_on_player_resources_changed):
		ResourceManager.resources_changed.connect(_on_player_resources_changed)


func _disconnect_player_resource_listener() -> void:
	if ResourceManager.resources_changed.is_connected(_on_player_resources_changed):
		ResourceManager.resources_changed.disconnect(_on_player_resources_changed)


func _on_player_resources_changed() -> void:
	if not _repeat_waiting_for_resources or not _repeat_enabled:
		return

	_try_repeat_training()


func _spawn_cannon() -> void:
	_spawn_trained_unit(CANNON_SCENE, cannon_spawn_offset)


func _spawn_trained_unit(scene: PackedScene, spawn_offset: Vector3) -> void:
	var unit: Unit = scene.instantiate() as Unit
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or unit == null:
		return

	spawn_parent.add_child(unit)
	unit.global_position = global_position + spawn_offset

	if _has_rally_point:
		_finalize_spawned_unit(unit)
		unit.set_movement_target(_claim_rally_move_target())
	else:
		_finalize_spawned_unit(unit)


func _finalize_spawned_unit(unit: Unit) -> void:
	unit.collision_layer = PhysicsLayers.UNITS
	unit.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK

	if not unit.is_in_group(&"units"):
		unit.add_to_group(&"units")

	var collision_shape: CollisionShape3D = unit.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		collision_shape.disabled = false


func _refund_training_cost(train_id: StringName) -> void:
	ResourceManager.add_gold(get_unit_train_gold_cost(train_id))
	ResourceManager.release_food_used(get_unit_train_food_cost(train_id))


func _emit_queue_changed() -> void:
	cannon_queue_changed.emit(get_cannon_queue_count())
	training_queue_changed.emit()
