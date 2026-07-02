class_name Barracks
extends Building

## Placeholder barracks building used for early 3D scene testing.

signal swordsman_queue_changed(queue_count: int)
signal archer_queue_changed(queue_count: int)
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
const ENEMY_TEAM_ID: int = 1
const ENEMY_GATHER_OFFSET: Vector3 = Vector3(-2.0, -0.5, 3.0)

@export var swordsman_spawn_offset: Vector3 = Vector3(0.0, -0.5, -2.5)
@export var archer_spawn_offset: Vector3 = Vector3(1.2, -0.5, -2.5)

@export var enable_enemy_auto_production: bool = false

var _swordsman_queue_count: int = 0
var _archer_queue_count: int = 0
var _is_training: bool = false
var _is_training_archer: bool = false
var _swordsman_training_session: int = 0
var _archer_training_session: int = 0
var _swordsman_training_started_at: float = 0.0
var _archer_training_started_at: float = 0.0
var _repeat_enabled: bool = false
var _repeat_unit_type: StringName = &""
var _last_queued_train_id: StringName = &""
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null
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
	return _is_training or _is_training_archer


func get_enemy_pending_unit_count() -> int:
	return _swordsman_queue_count + _archer_queue_count


func try_train_enemy_swordsman() -> bool:
	if building_state != STATE_COMPLETED or _is_training:
		return false

	if not EnemyResourceManager.try_pay_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		return false

	_swordsman_queue_count += 1
	swordsman_queue_changed.emit(_swordsman_queue_count)

	if not _is_training:
		_start_next_training()

	return true


func try_train_enemy_archer() -> bool:
	if building_state != STATE_COMPLETED or _is_training_archer:
		return false

	if not EnemyResourceManager.try_pay_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		return false

	_archer_queue_count += 1
	archer_queue_changed.emit(_archer_queue_count)

	if not _is_training_archer:
		_start_next_archer_training()

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
	unit.set_movement_target(global_position + ENEMY_GATHER_OFFSET)


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


func take_damage(amount: float, _attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	_stop_enemy_auto_production()
	_repeat_enabled = false
	_swordsman_training_session += 1
	_archer_training_session += 1
	_is_training = false
	_is_training_archer = false

	if _rally_marker != null and is_instance_valid(_rally_marker):
		_rally_marker.queue_free()
		_rally_marker = null

	destroy_building()
	queue_free()


func get_swordsman_queue_count() -> int:
	return _swordsman_queue_count


func get_archer_queue_count() -> int:
	return _archer_queue_count


func get_total_queue_count() -> int:
	return _swordsman_queue_count + _archer_queue_count


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
	repeat_state_changed.emit()


func try_train_swordsman_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_SWORDSMAN):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_SWORDSMAN)

	try_train_swordsman()


func try_train_archer_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_ARCHER):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_ARCHER)

	try_train_archer()


func is_training_swordsman() -> bool:
	return _is_training


func is_training_archer() -> bool:
	return _is_training_archer


func has_active_unit_training() -> bool:
	return _is_training or _is_training_archer


func get_active_unit_training_progress() -> float:
	if _is_training:
		var swordsman_elapsed: float = _get_time_seconds() - _swordsman_training_started_at
		return clampf(swordsman_elapsed / TRAIN_SECONDS, 0.0, 1.0)
	if _is_training_archer:
		var archer_elapsed: float = _get_time_seconds() - _archer_training_started_at
		return clampf(archer_elapsed / TRAIN_SECONDS, 0.0, 1.0)
	return 0.0


func get_active_unit_training_name() -> String:
	if _is_training:
		return "Swordsman"
	if _is_training_archer:
		return "Archer"
	return ""


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func cancel_swordsman_training_at(slot_index: int) -> bool:
	if _swordsman_queue_count <= 0:
		return false

	var cancel_indices: Array[int] = []
	if slot_index >= 0 and slot_index < _swordsman_queue_count:
		cancel_indices.append(slot_index)

	var last_index: int = _swordsman_queue_count - 1
	if not cancel_indices.has(last_index):
		cancel_indices.append(last_index)

	if not cancel_indices.has(0):
		cancel_indices.append(0)

	for cancel_index: int in cancel_indices:
		if _cancel_swordsman_training_at_index(cancel_index):
			return true

	return false


func cancel_archer_training_at(slot_index: int) -> bool:
	if _archer_queue_count <= 0:
		return false

	var cancel_indices: Array[int] = []
	if slot_index >= 0 and slot_index < _archer_queue_count:
		cancel_indices.append(slot_index)

	var last_index: int = _archer_queue_count - 1
	if not cancel_indices.has(last_index):
		cancel_indices.append(last_index)

	if not cancel_indices.has(0):
		cancel_indices.append(0)

	for cancel_index: int in cancel_indices:
		if _cancel_archer_training_at_index(cancel_index):
			return true

	return false


func _cancel_swordsman_training_at_index(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _swordsman_queue_count:
		return false

	if slot_index == 0 and _is_training:
		if is_repeat_training_enabled(TRAIN_ID_SWORDSMAN):
			set_repeat_training(false)

		_swordsman_training_session += 1
		_is_training = false
		_swordsman_queue_count -= 1
		swordsman_queue_changed.emit(_swordsman_queue_count)
		_refund_training_cost()

		if _swordsman_queue_count > 0:
			_start_next_training()

		return true

	if slot_index == _swordsman_queue_count - 1 and _swordsman_queue_count > 1:
		_swordsman_queue_count -= 1
		swordsman_queue_changed.emit(_swordsman_queue_count)
		_refund_training_cost()
		return true

	return false


func _cancel_archer_training_at_index(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _archer_queue_count:
		return false

	if slot_index == 0 and _is_training_archer:
		if is_repeat_training_enabled(TRAIN_ID_ARCHER):
			set_repeat_training(false)

		_archer_training_session += 1
		_is_training_archer = false
		_archer_queue_count -= 1
		archer_queue_changed.emit(_archer_queue_count)
		_refund_training_cost()

		if _archer_queue_count > 0:
			_start_next_archer_training()

		return true

	if slot_index == _archer_queue_count - 1 and _archer_queue_count > 1:
		_archer_queue_count -= 1
		archer_queue_changed.emit(_archer_queue_count)
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

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		ResourceManager.show_feedback(
			ResourceManager.get_training_failure_message(TRAIN_GOLD_COST, TRAIN_FOOD_COST)
		)
		return

	_swordsman_queue_count += 1
	_last_queued_train_id = TRAIN_ID_SWORDSMAN
	swordsman_queue_changed.emit(_swordsman_queue_count)

	if not _is_training:
		_start_next_training()


func _start_next_training() -> void:
	if _swordsman_queue_count <= 0:
		return

	_swordsman_training_session += 1
	var session: int = _swordsman_training_session
	_is_training = true
	_swordsman_training_started_at = _get_time_seconds()
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(func() -> void:
		_on_swordsman_training_finished(session)
	, CONNECT_ONE_SHOT)


func _on_swordsman_training_finished(session: int) -> void:
	if session != _swordsman_training_session:
		return

	_is_training = false
	if _swordsman_queue_count <= 0:
		return

	_spawn_swordsman()
	_swordsman_queue_count -= 1
	swordsman_queue_changed.emit(_swordsman_queue_count)

	if _swordsman_queue_count > 0:
		_start_next_training()
	else:
		_try_repeat_training(TRAIN_ID_SWORDSMAN)


func _spawn_swordsman() -> void:
	_spawn_trained_unit(SWORDSMAN_SCENE, swordsman_spawn_offset)


func try_train_archer() -> void:
	if building_state != STATE_COMPLETED:
		return

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		ResourceManager.show_feedback(
			ResourceManager.get_training_failure_message(TRAIN_GOLD_COST, TRAIN_FOOD_COST)
		)
		return

	_archer_queue_count += 1
	_last_queued_train_id = TRAIN_ID_ARCHER
	archer_queue_changed.emit(_archer_queue_count)

	if not _is_training_archer:
		_start_next_archer_training()


func _start_next_archer_training() -> void:
	if _archer_queue_count <= 0:
		return

	_archer_training_session += 1
	var session: int = _archer_training_session
	_is_training_archer = true
	_archer_training_started_at = _get_time_seconds()
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(func() -> void:
		_on_archer_training_finished(session)
	, CONNECT_ONE_SHOT)


func _on_archer_training_finished(session: int) -> void:
	if session != _archer_training_session:
		return

	_is_training_archer = false
	if _archer_queue_count <= 0:
		return

	_spawn_archer()
	_archer_queue_count -= 1
	archer_queue_changed.emit(_archer_queue_count)

	if _archer_queue_count > 0:
		_start_next_archer_training()
	else:
		_try_repeat_training(TRAIN_ID_ARCHER)


func _try_repeat_training(train_id: StringName) -> void:
	if not is_repeat_training_enabled(train_id):
		return

	if not is_instance_valid(self) or is_queued_for_deletion() or building_state != STATE_COMPLETED:
		set_repeat_training(false)
		return

	if not ResourceManager.can_afford_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		set_repeat_training(false)
		return

	match train_id:
		TRAIN_ID_SWORDSMAN:
			if _swordsman_queue_count > 0:
				return
			try_train_swordsman()
		TRAIN_ID_ARCHER:
			if _archer_queue_count > 0:
				return
			try_train_archer()


func _refund_training_cost() -> void:
	ResourceManager.add_gold(TRAIN_GOLD_COST)
	ResourceManager.release_food_used(TRAIN_FOOD_COST)


func _spawn_archer() -> void:
	_spawn_trained_unit(ARCHER_SCENE, archer_spawn_offset)


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
		unit.set_movement_target(global_position + ENEMY_GATHER_OFFSET)
	elif _has_rally_point:
		_finalize_spawned_unit(unit)
		unit.set_movement_target(_rally_point)
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
