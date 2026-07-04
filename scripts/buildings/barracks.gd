class_name Barracks
extends Building

## Placeholder barracks building used for early 3D scene testing.

signal swordsman_queue_changed(queue_count: int)
signal archer_queue_changed(queue_count: int)
signal training_queue_changed()
signal repeat_state_changed()

const TRAIN_ID_SWORDSMAN: StringName = &"swordsman"
const TRAIN_ID_ARCHER: StringName = &"archer"

const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/archer.tscn")
const TRAIN_GOLD_COST: int = 100
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 4.0
const RALLY_MARKER_Y: float = 0.05
const ENEMY_PRODUCTION_INTERVAL_SECONDS: float = 8.0
const MAX_ENEMY_UNIT_QUEUE: int = 3
const ENEMY_TEAM_ID: int = 1
const ENEMY_GATHER_OFFSET: Vector3 = Vector3(-2.0, -0.5, 3.0)
const RALLY_SLOT_SPACING: float = 2.0

@export var swordsman_spawn_offset: Vector3 = Vector3(0.0, -0.5, -2.5)
@export var archer_spawn_offset: Vector3 = Vector3(1.2, -0.5, -2.5)

@export var enable_enemy_auto_production: bool = false

var _training_queue: Array[StringName] = []
var _is_training: bool = false
var _training_session: int = 0
var _training_started_at: float = 0.0
var _current_training_id: StringName = &""
var _repeat_enabled: bool = false
var _repeat_unit_type: StringName = &""
var _repeat_waiting_for_resources: bool = false
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null
var _rally_next_slot: int = 0
var _enemy_gather_next_slot: int = 0
var _enemy_production_spawn_swordsman_next: bool = true
var _enemy_production_active: bool = false

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)

	if enable_enemy_auto_production:
		_start_enemy_auto_production()


func _exit_tree() -> void:
	_disconnect_player_resource_listener()


func _start_enemy_auto_production() -> void:
	_enemy_production_active = true
	_schedule_enemy_production_tick()


func _schedule_enemy_production_tick() -> void:
	if not _enemy_production_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(
		ENEMY_PRODUCTION_INTERVAL_SECONDS
	)
	wait_timer.timeout.connect(_on_enemy_production_tick, CONNECT_ONE_SHOT)


func _on_enemy_production_tick() -> void:
	if not _enemy_production_active or not is_instance_valid(self):
		return

	if building_state != STATE_COMPLETED:
		_schedule_enemy_production_tick()
		return

	if _enemy_production_spawn_swordsman_next:
		if not try_train_enemy_swordsman():
			try_train_enemy_archer()
	else:
		if not try_train_enemy_archer():
			try_train_enemy_swordsman()

	_enemy_production_spawn_swordsman_next = not _enemy_production_spawn_swordsman_next
	_schedule_enemy_production_tick()


func is_enemy_training_busy() -> bool:
	return _is_training


func get_enemy_pending_unit_count() -> int:
	return _training_queue.size()


func try_train_enemy_swordsman() -> bool:
	return _try_train_enemy_unit(TRAIN_ID_SWORDSMAN)


func try_train_enemy_archer() -> bool:
	return _try_train_enemy_unit(TRAIN_ID_ARCHER)


func _try_train_enemy_unit(train_id: StringName) -> bool:
	if building_state != STATE_COMPLETED:
		return false

	if _training_queue.size() >= MAX_ENEMY_UNIT_QUEUE:
		return false

	if not EnemyResourceManager.try_pay_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		return false

	_enqueue_training(train_id)

	return true


func _spawn_enemy_unit(scene: PackedScene) -> void:
	var unit: Unit = scene.instantiate() as Unit
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or unit == null:
		return

	spawn_parent.add_child(unit)
	unit.global_position = global_position + swordsman_spawn_offset
	_finalize_spawned_unit(unit)
	_finalize_enemy_unit(unit)
	UpgradeManager.apply_enemy_upgrades_to_unit(unit)
	unit.set_movement_target(_claim_enemy_gather_target())


func _finalize_enemy_unit(unit: Unit) -> void:
	unit.team_id = ENEMY_TEAM_ID

	if not unit.is_in_group(&"enemies"):
		unit.add_to_group(&"enemies")

	EnemyArmyCommand.register_combat_unit(unit)

	if unit.is_in_group(&"units"):
		unit.remove_from_group(&"units")

	unit.apply_team_visuals()


func _stop_enemy_auto_production() -> void:
	_enemy_production_active = false


func take_damage(amount: float, attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(self, attacker)
	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	_stop_enemy_auto_production()
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


func get_swordsman_queue_count() -> int:
	return _count_queued_units(TRAIN_ID_SWORDSMAN)


func get_archer_queue_count() -> int:
	return _count_queued_units(TRAIN_ID_ARCHER)


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

	match _repeat_unit_type:
		TRAIN_ID_SWORDSMAN:
			return "Swordsman"
		TRAIN_ID_ARCHER:
			return "Archer"
		_:
			return ""


func set_repeat_training(enabled: bool, train_id: StringName = &"") -> void:
	_repeat_enabled = enabled
	_repeat_unit_type = train_id if enabled else &""
	if not enabled:
		_repeat_waiting_for_resources = false
		_disconnect_player_resource_listener()
	repeat_state_changed.emit()


func try_train_swordsman_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_SWORDSMAN):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_SWORDSMAN)
		_try_repeat_training()
		return

	try_train_swordsman()


func try_train_archer_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_ARCHER):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_ARCHER)
		_try_repeat_training()
		return

	try_train_archer()


func is_training_swordsman() -> bool:
	return _is_training and _current_training_id == TRAIN_ID_SWORDSMAN


func is_training_archer() -> bool:
	return _is_training and _current_training_id == TRAIN_ID_ARCHER


func has_active_unit_training() -> bool:
	return _is_training


func get_active_unit_training_progress() -> float:
	if not _is_training:
		return 0.0

	var elapsed: float = _get_time_seconds() - _training_started_at
	return clampf(elapsed / TRAIN_SECONDS, 0.0, 1.0)


func get_active_unit_training_name() -> String:
	match _current_training_id:
		TRAIN_ID_SWORDSMAN:
			return "Swordsman"
		TRAIN_ID_ARCHER:
			return "Archer"
		_:
			return ""


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func cancel_swordsman_training_at(slot_index: int) -> bool:
	return cancel_training_at(_map_type_slot_to_queue_index(TRAIN_ID_SWORDSMAN, slot_index))


func cancel_archer_training_at(slot_index: int) -> bool:
	return cancel_training_at(_map_type_slot_to_queue_index(TRAIN_ID_ARCHER, slot_index))


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
		_refund_training_cost()

		if not _training_queue.is_empty():
			_start_next_training()
		else:
			_try_repeat_training()

		return true

	if slot_index == _training_queue.size() - 1 and _training_queue.size() > 1:
		_training_queue.remove_at(slot_index)
		_emit_queue_changed()
		_refund_training_cost()
		return true

	return false


func set_rally_point(ground_position: Vector3) -> void:
	_has_rally_point = true
	_rally_point = Vector3(
		ground_position.x,
		global_position.y + swordsman_spawn_offset.y,
		ground_position.z
	)
	_rally_next_slot = 0
	_update_rally_marker(Vector3(ground_position.x, RALLY_MARKER_Y, ground_position.z))


func _claim_rally_move_target() -> Vector3:
	var slot_index: int = _rally_next_slot
	_rally_next_slot += 1
	return GroupMoveSpacing.compute_slot_target(_rally_point, slot_index, RALLY_SLOT_SPACING)


func _claim_enemy_gather_target() -> Vector3:
	var gather_center: Vector3 = global_position + ENEMY_GATHER_OFFSET
	var slot_index: int = _enemy_gather_next_slot
	_enemy_gather_next_slot += 1
	return GroupMoveSpacing.compute_slot_target(gather_center, slot_index, RALLY_SLOT_SPACING)


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
	_try_train_player_unit(TRAIN_ID_SWORDSMAN)


func try_train_archer() -> void:
	_try_train_player_unit(TRAIN_ID_ARCHER)


func _try_train_player_unit(train_id: StringName) -> void:
	if building_state != STATE_COMPLETED:
		return

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		ResourceManager.show_feedback(
			ResourceManager.get_training_failure_message(TRAIN_GOLD_COST, TRAIN_FOOD_COST)
		)
		return

	_enqueue_training(train_id)


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
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
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

	match _training_queue[0]:
		TRAIN_ID_SWORDSMAN:
			_spawn_swordsman()
		TRAIN_ID_ARCHER:
			_spawn_archer()

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
	if _uses_player_resources():
		return ResourceManager.can_afford_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST)

	return EnemyResourceManager.can_afford_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST)


func _pay_training_costs() -> bool:
	if _uses_player_resources():
		return ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST)

	return EnemyResourceManager.try_pay_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST)


func _uses_player_resources() -> bool:
	return not enable_enemy_auto_production and team_id != ENEMY_TEAM_ID


func _ensure_player_resource_listener() -> void:
	if not _uses_player_resources():
		return

	if not ResourceManager.resources_changed.is_connected(_on_player_resources_changed):
		ResourceManager.resources_changed.connect(_on_player_resources_changed)


func _disconnect_player_resource_listener() -> void:
	if ResourceManager.resources_changed.is_connected(_on_player_resources_changed):
		ResourceManager.resources_changed.disconnect(_on_player_resources_changed)


func _on_player_resources_changed() -> void:
	if not _repeat_waiting_for_resources or not _repeat_enabled:
		return

	_try_repeat_training()


func _spawn_swordsman() -> void:
	_spawn_trained_unit(SWORDSMAN_SCENE, swordsman_spawn_offset)


func _spawn_archer() -> void:
	_spawn_trained_unit(ARCHER_SCENE, archer_spawn_offset)


func _refund_training_cost() -> void:
	if _uses_player_resources():
		ResourceManager.add_gold(TRAIN_GOLD_COST)
		ResourceManager.release_food_used(TRAIN_FOOD_COST)
	else:
		EnemyResourceManager.add_gold(TRAIN_GOLD_COST)
		EnemyResourceManager.release_food_used(TRAIN_FOOD_COST)


func _emit_queue_changed() -> void:
	swordsman_queue_changed.emit(get_swordsman_queue_count())
	archer_queue_changed.emit(get_archer_queue_count())
	training_queue_changed.emit()


func _spawn_trained_unit(scene: PackedScene, spawn_offset: Vector3) -> void:
	var unit: Unit = scene.instantiate() as Unit
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or unit == null:
		return

	spawn_parent.add_child(unit)
	unit.global_position = global_position + spawn_offset

	if is_in_group(&"enemy_command_center"):
		_finalize_enemy_unit(unit)
		UpgradeManager.apply_enemy_upgrades_to_unit(unit)
		unit.set_movement_target(_claim_enemy_gather_target())
	elif _has_rally_point:
		_finalize_spawned_unit(unit)
		unit.set_movement_target(_claim_rally_move_target())
	else:
		_finalize_spawned_unit(unit)


func _finalize_spawned_unit(unit: Unit) -> void:
	unit.collision_layer = PhysicsLayers.UNITS
	unit.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK

	if not unit.is_in_group(&"units"):
		unit.add_to_group(&"units")

	UpgradeManager.apply_player_upgrades_to_unit(unit)

	var collision_shape: CollisionShape3D = unit.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		collision_shape.disabled = false
