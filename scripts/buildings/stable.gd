class_name Stable
extends Building

## Stable building that trains cavalry units.

signal heavy_cavalry_queue_changed(queue_count: int)
signal light_cavalry_queue_changed(queue_count: int)
signal cavalry_archer_queue_changed(queue_count: int)
signal training_queue_changed()
signal repeat_state_changed()
signal research_state_changed()

const RESEARCH_SECONDS: float = 5.0

const TRAIN_ID_HEAVY_CAVALRY: StringName = &"heavy_cavalry"
const TRAIN_ID_LIGHT_CAVALRY: StringName = &"light_cavalry"
const TRAIN_ID_CAVALRY_ARCHER: StringName = &"cavalry_archer"

const CAVALRY_UNIT_IDS: Array[StringName] = [
	TRAIN_ID_HEAVY_CAVALRY,
	TRAIN_ID_LIGHT_CAVALRY,
	TRAIN_ID_CAVALRY_ARCHER,
]

const HEAVY_CAVALRY_SCENE: PackedScene = preload("res://scenes/units/heavy_cavalry.tscn")
const LIGHT_CAVALRY_SCENE: PackedScene = preload("res://scenes/units/light_cavalry.tscn")
const CAVALRY_ARCHER_SCENE: PackedScene = preload("res://scenes/units/cavalry_archer.tscn")
const LIGHT_CAVALRY_TRAIN_GOLD_COST: int = 85
const HEAVY_CAVALRY_TRAIN_GOLD_COST: int = 150
const TRAIN_FOOD_COST: int = 1
const HEAVY_CAVALRY_TRAIN_FOOD_COST: int = 2
const CAVALRY_ARCHER_TRAIN_GOLD_COST: int = 130
const LIGHT_CAVALRY_TRAIN_SECONDS: float = 3.5
const HEAVY_CAVALRY_TRAIN_SECONDS: float = 7.0
const CAVALRY_ARCHER_TRAIN_SECONDS: float = 5.5
const RALLY_MARKER_Y: float = 0.05
const ENEMY_PRODUCTION_INTERVAL_SECONDS: float = 8.0
const MAX_ENEMY_UNIT_QUEUE: int = 3
const ENEMY_TEAM_ID: int = 1
const ENEMY_GATHER_OFFSET: Vector3 = Vector3(-2.0, -0.5, 3.0)
const RALLY_SLOT_SPACING: float = 2.0

@export var heavy_cavalry_spawn_offset: Vector3 = Vector3(-1.2, -0.5, -2.5)
@export var light_cavalry_spawn_offset: Vector3 = Vector3(0.0, -0.5, -2.5)
@export var cavalry_archer_spawn_offset: Vector3 = Vector3(1.2, -0.5, -2.5)

@export var enable_enemy_auto_production: bool = false

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
var _enemy_gather_next_slot: int = 0
var _enemy_production_spawn_light_cavalry_next: bool = true
var _enemy_production_active: bool = false
var _is_researching: bool = false
var _research_upgrade_id: StringName = &""
var _research_started_at: float = 0.0
var _research_session: int = 0

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


## Keep Quaternius Stable materials untouched; team identity comes from the selection ring.
func apply_team_visuals() -> void:
	_restore_stable_visual_materials()


func _restore_stable_visual_materials() -> void:
	var visuals: Node3D = get_node_or_null("Visuals") as Node3D
	if visuals == null:
		return

	_clear_imported_mesh_overrides(visuals)


func _clear_imported_mesh_overrides(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = null
		if mesh_instance.mesh != null:
			for surface_index: int in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, null)

	for child: Node in node.get_children():
		_clear_imported_mesh_overrides(child)


func can_show_commands() -> bool:
	if building_state != STATE_COMPLETED:
		return false

	return TeamVisuals.resolve_team(self, team_id) == TeamVisuals.PLAYER_TEAM_ID


static func get_cavalry_unit_ids() -> Array[StringName]:
	return CAVALRY_UNIT_IDS.duplicate()


func can_research() -> bool:
	return can_show_commands()


func can_enemy_research() -> bool:
	if building_state != STATE_COMPLETED:
		return false

	return TeamVisuals.resolve_team(self, team_id) != TeamVisuals.PLAYER_TEAM_ID


func is_researching() -> bool:
	return _is_researching


func get_research_upgrade_id() -> StringName:
	return _research_upgrade_id


func get_research_progress() -> float:
	if not _is_researching:
		return 0.0

	var elapsed: float = _get_time_seconds() - _research_started_at
	return clampf(elapsed / RESEARCH_SECONDS, 0.0, 1.0)


func get_research_activity_label() -> String:
	if not _is_researching:
		return ""

	var next_level: int = _get_upgrade_level(_research_upgrade_id) + 1
	var upgrade_kind: String = "Attack" if UpgradeManager.is_cavalry_attack_upgrade(_research_upgrade_id) else "Defense"
	return "%s Upgrade %d/%d" % [upgrade_kind, next_level, UpgradeManager.MAX_LEVEL]


func try_research_upgrade(upgrade_id: StringName) -> bool:
	if _is_researching:
		return false

	if not UpgradeManager.is_stable_cavalry_upgrade(upgrade_id):
		return false

	if _is_enemy_owned():
		if not can_enemy_research():
			return false
		if not UpgradeManager.try_pay_for_enemy_research(upgrade_id):
			return false
	else:
		if not can_research():
			return false
		if not UpgradeManager.try_pay_for_research(upgrade_id):
			return false

	_begin_research(upgrade_id)
	return true


func _begin_research(upgrade_id: StringName) -> void:
	_research_session += 1
	var session: int = _research_session
	_is_researching = true
	_research_upgrade_id = upgrade_id
	_research_started_at = _get_time_seconds()
	research_state_changed.emit()

	var wait_timer: SceneTreeTimer = get_tree().create_timer(RESEARCH_SECONDS)
	wait_timer.timeout.connect(func() -> void:
		_on_research_finished(session)
	, CONNECT_ONE_SHOT)


func _on_research_finished(session: int) -> void:
	if session != _research_session:
		return

	var completed_upgrade_id: StringName = _research_upgrade_id
	_is_researching = false
	_research_upgrade_id = &""
	if _is_enemy_owned():
		UpgradeManager.finish_enemy_research(completed_upgrade_id)
	else:
		UpgradeManager.finish_research(completed_upgrade_id)
	research_state_changed.emit()


func _invalidate_research() -> void:
	_research_session += 1
	_is_researching = false
	_research_upgrade_id = &""
	research_state_changed.emit()


func _get_upgrade_level(upgrade_id: StringName) -> int:
	if _is_enemy_owned():
		return UpgradeManager.get_enemy_level(upgrade_id)

	return UpgradeManager.get_level(upgrade_id)


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

	if _enemy_production_spawn_light_cavalry_next:
		if not try_train_enemy_light_cavalry():
			if not try_train_enemy_cavalry_archer():
				try_train_enemy_heavy_cavalry()
	else:
		if not try_train_enemy_cavalry_archer():
			if not try_train_enemy_light_cavalry():
				try_train_enemy_heavy_cavalry()

	_enemy_production_spawn_light_cavalry_next = not _enemy_production_spawn_light_cavalry_next
	_schedule_enemy_production_tick()


func is_enemy_training_busy() -> bool:
	return _is_training


func get_enemy_pending_unit_count() -> int:
	return _training_queue.size()


func try_train_enemy_heavy_cavalry() -> bool:
	return _try_train_enemy_unit(TRAIN_ID_HEAVY_CAVALRY)


func try_train_enemy_light_cavalry() -> bool:
	return _try_train_enemy_unit(TRAIN_ID_LIGHT_CAVALRY)


func try_train_enemy_cavalry_archer() -> bool:
	return _try_train_enemy_unit(TRAIN_ID_CAVALRY_ARCHER)


func _try_train_enemy_unit(train_id: StringName) -> bool:
	if building_state != STATE_COMPLETED:
		return false

	if not _is_unit_unlocked_for_team(train_id):
		return false

	if _training_queue.size() >= MAX_ENEMY_UNIT_QUEUE:
		return false

	var gold_cost: int = get_unit_train_gold_cost(train_id)
	var food_cost: int = get_unit_train_food_cost(train_id)
	if not EnemyResourceManager.try_pay_training(gold_cost, food_cost):
		return false

	_enqueue_training(train_id)

	return true


func _spawn_enemy_unit(scene: PackedScene) -> void:
	var unit: Unit = scene.instantiate() as Unit
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or unit == null:
		return

	spawn_parent.add_child(unit)
	unit.global_position = global_position + light_cavalry_spawn_offset
	_finalize_spawned_unit(unit)
	_finalize_enemy_unit(unit)
	UpgradeManager.apply_enemy_upgrades_to_unit(unit)
	EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), unit)


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
	_invalidate_research()
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


func get_light_cavalry_queue_count() -> int:
	return _count_queued_units(TRAIN_ID_LIGHT_CAVALRY)


func get_cavalry_archer_queue_count() -> int:
	return _count_queued_units(TRAIN_ID_CAVALRY_ARCHER)


func get_heavy_cavalry_queue_count() -> int:
	return _count_queued_units(TRAIN_ID_HEAVY_CAVALRY)


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
		TRAIN_ID_HEAVY_CAVALRY:
			return "Heavy Cavalry"
		TRAIN_ID_LIGHT_CAVALRY:
			return "Light Cavalry"
		TRAIN_ID_CAVALRY_ARCHER:
			return "Cavalry Archer"
		_:
			return ""


func set_repeat_training(enabled: bool, train_id: StringName = &"") -> void:
	_repeat_enabled = enabled
	_repeat_unit_type = train_id if enabled else &""
	if not enabled:
		_repeat_waiting_for_resources = false
		_disconnect_player_resource_listener()
	repeat_state_changed.emit()


func try_train_heavy_cavalry_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_HEAVY_CAVALRY):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_HEAVY_CAVALRY)
		_try_repeat_training()
		return

	try_train_heavy_cavalry()


func try_train_light_cavalry_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_LIGHT_CAVALRY):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_LIGHT_CAVALRY)
		_try_repeat_training()
		return

	try_train_light_cavalry()


func try_train_cavalry_archer_with_repeat(ctrl_held: bool) -> void:
	if ctrl_held:
		if is_repeat_training_enabled(TRAIN_ID_CAVALRY_ARCHER):
			set_repeat_training(false)
			return

		set_repeat_training(true, TRAIN_ID_CAVALRY_ARCHER)
		_try_repeat_training()
		return

	try_train_cavalry_archer()


func is_training_heavy_cavalry() -> bool:
	return _is_training and _current_training_id == TRAIN_ID_HEAVY_CAVALRY


func is_training_light_cavalry() -> bool:
	return _is_training and _current_training_id == TRAIN_ID_LIGHT_CAVALRY


func is_training_cavalry_archer() -> bool:
	return _is_training and _current_training_id == TRAIN_ID_CAVALRY_ARCHER


func has_active_unit_training() -> bool:
	return _is_training


func get_active_unit_training_progress() -> float:
	if not _is_training:
		return 0.0

	var elapsed: float = _get_time_seconds() - _training_started_at
	var train_seconds: float = _current_training_seconds
	return clampf(elapsed / train_seconds, 0.0, 1.0)


func get_active_unit_training_name() -> String:
	match _current_training_id:
		TRAIN_ID_HEAVY_CAVALRY:
			return "Heavy Cavalry"
		TRAIN_ID_LIGHT_CAVALRY:
			return "Light Cavalry"
		TRAIN_ID_CAVALRY_ARCHER:
			return "Cavalry Archer"
		_:
			return ""


static func get_unit_train_gold_cost(train_id: StringName) -> int:
	match train_id:
		TRAIN_ID_HEAVY_CAVALRY:
			return HEAVY_CAVALRY_TRAIN_GOLD_COST
		TRAIN_ID_LIGHT_CAVALRY:
			return LIGHT_CAVALRY_TRAIN_GOLD_COST
		TRAIN_ID_CAVALRY_ARCHER:
			return CAVALRY_ARCHER_TRAIN_GOLD_COST
		_:
			return LIGHT_CAVALRY_TRAIN_GOLD_COST


static func get_unit_train_food_cost(train_id: StringName) -> int:
	match train_id:
		TRAIN_ID_HEAVY_CAVALRY:
			return HEAVY_CAVALRY_TRAIN_FOOD_COST
		_:
			return TRAIN_FOOD_COST


static func get_unit_train_seconds(train_id: StringName) -> float:
	match train_id:
		TRAIN_ID_HEAVY_CAVALRY:
			return HEAVY_CAVALRY_TRAIN_SECONDS
		TRAIN_ID_LIGHT_CAVALRY:
			return LIGHT_CAVALRY_TRAIN_SECONDS
		TRAIN_ID_CAVALRY_ARCHER:
			return CAVALRY_ARCHER_TRAIN_SECONDS
		_:
			return LIGHT_CAVALRY_TRAIN_SECONDS


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func cancel_heavy_cavalry_training_at(slot_index: int) -> bool:
	return cancel_training_at(_map_type_slot_to_queue_index(TRAIN_ID_HEAVY_CAVALRY, slot_index))


func cancel_light_cavalry_training_at(slot_index: int) -> bool:
	return cancel_training_at(_map_type_slot_to_queue_index(TRAIN_ID_LIGHT_CAVALRY, slot_index))


func cancel_cavalry_archer_training_at(slot_index: int) -> bool:
	return cancel_training_at(_map_type_slot_to_queue_index(TRAIN_ID_CAVALRY_ARCHER, slot_index))


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
		global_position.y + light_cavalry_spawn_offset.y,
		ground_position.z
	)
	_rally_next_slot = 0
	_update_rally_marker(Vector3(ground_position.x, RALLY_MARKER_Y, ground_position.z))


func _claim_rally_move_target() -> Vector3:
	var slot_index: int = _rally_next_slot
	_rally_next_slot += 1
	return GroupMoveSpacing.compute_slot_target(_rally_point, slot_index, RALLY_SLOT_SPACING)


func _claim_enemy_gather_target() -> Vector3:
	return _claim_enemy_rally_target()


func _claim_enemy_rally_target() -> Vector3:
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	if rally_position == Vector3.ZERO:
		var gather_center: Vector3 = global_position + ENEMY_GATHER_OFFSET
		var slot_index: int = _enemy_gather_next_slot
		_enemy_gather_next_slot += 1
		return GroupMoveSpacing.compute_slot_target(gather_center, slot_index, RALLY_SLOT_SPACING)

	var slot_index: int = _enemy_gather_next_slot
	_enemy_gather_next_slot += 1
	return GroupMoveSpacing.compute_slot_target(rally_position, slot_index, RALLY_SLOT_SPACING)


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


func try_train_heavy_cavalry() -> void:
	_try_train_player_unit(TRAIN_ID_HEAVY_CAVALRY)


func try_train_light_cavalry() -> void:
	_try_train_player_unit(TRAIN_ID_LIGHT_CAVALRY)


func try_train_cavalry_archer() -> void:
	_try_train_player_unit(TRAIN_ID_CAVALRY_ARCHER)


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


func _is_unit_unlocked_for_team(_train_id: StringName) -> bool:
	return true


func _get_owner_team_id() -> int:
	return TeamVisuals.resolve_team(self, team_id)


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

	match _training_queue[0]:
		TRAIN_ID_HEAVY_CAVALRY:
			_spawn_heavy_cavalry()
		TRAIN_ID_LIGHT_CAVALRY:
			_spawn_light_cavalry()
		TRAIN_ID_CAVALRY_ARCHER:
			_spawn_cavalry_archer()

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

	if not _is_unit_unlocked_for_team(_repeat_unit_type):
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
	var gold_cost: int = get_unit_train_gold_cost(_repeat_unit_type)
	var food_cost: int = get_unit_train_food_cost(_repeat_unit_type)
	if _uses_player_resources():
		return ResourceManager.can_afford_worker_training(gold_cost, food_cost)

	return EnemyResourceManager.can_afford_training(gold_cost, food_cost)


func _pay_training_costs() -> bool:
	var gold_cost: int = get_unit_train_gold_cost(_repeat_unit_type)
	var food_cost: int = get_unit_train_food_cost(_repeat_unit_type)
	if _uses_player_resources():
		return ResourceManager.try_pay_worker_training(gold_cost, food_cost)

	return EnemyResourceManager.try_pay_training(gold_cost, food_cost)


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


func _spawn_heavy_cavalry() -> void:
	_spawn_trained_unit(HEAVY_CAVALRY_SCENE, heavy_cavalry_spawn_offset)


func _spawn_light_cavalry() -> void:
	_spawn_trained_unit(LIGHT_CAVALRY_SCENE, light_cavalry_spawn_offset)


func _spawn_cavalry_archer() -> void:
	_spawn_trained_unit(CAVALRY_ARCHER_SCENE, cavalry_archer_spawn_offset)


func _refund_training_cost(train_id: StringName) -> void:
	var gold_cost: int = get_unit_train_gold_cost(train_id)
	var food_cost: int = get_unit_train_food_cost(train_id)
	if _uses_player_resources():
		ResourceManager.add_gold(gold_cost)
		ResourceManager.release_food_used(food_cost)
	else:
		EnemyResourceManager.add_gold(gold_cost)
		EnemyResourceManager.release_food_used(food_cost)


func _emit_queue_changed() -> void:
	heavy_cavalry_queue_changed.emit(get_heavy_cavalry_queue_count())
	light_cavalry_queue_changed.emit(get_light_cavalry_queue_count())
	cavalry_archer_queue_changed.emit(get_cavalry_archer_queue_count())
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
		EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), unit)
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
