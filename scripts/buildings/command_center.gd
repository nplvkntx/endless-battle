class_name CommandCenter
extends Building

## Placeholder command center used for early 3D scene testing.

signal worker_queue_changed(queue_count: int)
signal repeat_state_changed()
signal tier_state_changed()

const TRAIN_ID_WORKER: StringName = &"worker"
const UPGRADE_ID_TIER: StringName = &"cc_tier_upgrade"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const TRAIN_GOLD_COST: int = 50
const TRAIN_FOOD_COST: int = 1
const TRAIN_SECONDS: float = 3.0
const MAX_ENEMY_WORKER_QUEUE: int = 2
const RALLY_MARKER_Y: float = 0.05
const RALLY_SLOT_SPACING: float = 2.0
const ENEMY_TEAM_ID: int = 1

const MIN_TIER: int = 1
const MAX_TIER: int = 3
const TIER_2_GOLD_COST: int = 800
const TIER_2_WOOD_COST: int = 500
const TIER_2_UPGRADE_SECONDS: float = 60.0
const TIER_3_GOLD_COST: int = 2000
const TIER_3_WOOD_COST: int = 1200
const TIER_3_UPGRADE_SECONDS: float = 120.0

const TIER_VISUALS_NODE_NAME := &"TierVisuals"
const TIER2_MARKER_NAME := &"Tier2Marker"
const TIER3_MARKER_NAME := &"Tier3Marker"
const TIER_MARKER_RADIUS := 0.12
const TIER2_MARKER_POSITION := Vector3(-1.45, 2.05, 1.25)
const TIER3_MARKER_POSITION := Vector3(1.45, 2.15, 1.25)
const TIER2_MARKER_COLOR := Color(0.2, 0.55, 0.95, 1)
const TIER3_MARKER_COLOR := Color(0.95, 0.75, 0.15, 1)

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
var _rally_next_slot: int = 0

var command_center_tier: int = MIN_TIER
var _is_upgrading: bool = false
var _upgrade_target_tier: int = 0
var _upgrade_session: int = 0
var _upgrade_started_at: float = 0.0
var _tier_visuals_root: Node3D = null
var _tier2_marker: MeshInstance3D = null
var _tier3_marker: MeshInstance3D = null
@onready var _health_component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()
	_ensure_dropoff_registration()
	_ensure_tier_markers()
	_apply_tier_visuals()
	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


## Keep Quaternius Town Center materials untouched; team identity comes from the selection ring.
func apply_team_visuals() -> void:
	_restore_town_center_visual_materials()


func _restore_town_center_visual_materials() -> void:
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


func complete_construction() -> void:
	super.complete_construction()
	_ensure_dropoff_registration()
	_apply_tier_visuals()


func _ensure_dropoff_registration() -> void:
	if is_in_group(&"enemy_command_center") or team_id == ENEMY_TEAM_ID:
		team_id = ENEMY_TEAM_ID
		if is_in_group(&"player_command_center"):
			remove_from_group(&"player_command_center")
		if not is_in_group(&"enemy_command_center"):
			add_to_group(&"enemy_command_center")
		return

	if team_id < 0:
		team_id = 0
	if not is_in_group(&"player_command_center"):
		add_to_group(&"player_command_center")
	if is_in_group(&"enemy_command_center"):
		remove_from_group(&"enemy_command_center")


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
	_invalidate_training_session()
	_is_training = false
	_invalidate_tier_upgrade()
	_rally_resource = null
	_tier2_marker = null
	_tier3_marker = null
	_tier_visuals_root = null

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


func is_upgrading_tier() -> bool:
	return _is_upgrading


func get_next_upgrade_tier() -> int:
	if _is_upgrading:
		return 0

	if command_center_tier >= MAX_TIER:
		return 0

	return command_center_tier + 1


func get_tier_upgrade_progress() -> float:
	if not _is_upgrading:
		return 0.0

	var duration: float = _get_upgrade_duration_for_tier(_upgrade_target_tier)
	if duration <= 0.0:
		return 0.0

	var elapsed: float = _get_time_seconds() - _upgrade_started_at
	return clampf(elapsed / duration, 0.0, 1.0)


func get_tier_upgrade_activity_label() -> String:
	if not _is_upgrading:
		return ""

	return "Upgrading to Tier %d" % _upgrade_target_tier


func can_show_tier_upgrade_button() -> bool:
	if not _can_player_upgrade_tier():
		return false

	return get_next_upgrade_tier() > 0


func can_upgrade_tier() -> bool:
	if not _can_player_upgrade_tier():
		return false

	if _is_upgrading:
		return false

	if _is_training or _worker_queue_count > 0:
		return false

	var target_tier: int = get_next_upgrade_tier()
	if target_tier <= command_center_tier:
		return false

	var costs: Dictionary = get_upgrade_costs(target_tier)
	return ResourceManager.can_afford(int(costs.gold), int(costs.wood))


func try_upgrade_tier() -> bool:
	if not _can_player_upgrade_tier():
		return false

	if _is_upgrading:
		return false

	if _is_training or _worker_queue_count > 0:
		return false

	var target_tier: int = get_next_upgrade_tier()
	if target_tier <= command_center_tier or target_tier > MAX_TIER:
		return false

	var costs: Dictionary = get_upgrade_costs(target_tier)
	var gold_cost: int = int(costs.gold)
	var wood_cost: int = int(costs.wood)
	if not ResourceManager.can_afford(gold_cost, wood_cost):
		if gold_cost > ResourceManager.gold:
			ResourceManager.show_feedback("Not enough gold")
		elif wood_cost > ResourceManager.wood:
			ResourceManager.show_feedback("Not enough wood")
		else:
			ResourceManager.show_feedback("Not enough resources")
		return false

	if not ResourceManager.try_spend(gold_cost, wood_cost):
		return false

	_begin_tier_upgrade(target_tier)
	return true


static func get_upgrade_costs(target_tier: int) -> Dictionary:
	match target_tier:
		2:
			return {
				"gold": TIER_2_GOLD_COST,
				"wood": TIER_2_WOOD_COST,
				"seconds": TIER_2_UPGRADE_SECONDS,
			}
		3:
			return {
				"gold": TIER_3_GOLD_COST,
				"wood": TIER_3_WOOD_COST,
				"seconds": TIER_3_UPGRADE_SECONDS,
			}
		_:
			return {}


func _get_upgrade_duration_for_tier(target_tier: int) -> float:
	var costs: Dictionary = get_upgrade_costs(target_tier)
	return float(costs.get("seconds", 0.0))


func _can_player_upgrade_tier() -> bool:
	if is_in_group(&"enemy_command_center") or team_id == ENEMY_TEAM_ID:
		return false

	if building_state != STATE_COMPLETED:
		return false

	if _health_component != null and _health_component.current_health <= 0:
		return false

	return true


func _begin_tier_upgrade(target_tier: int) -> void:
	_upgrade_session += 1
	var session: int = _upgrade_session
	_is_upgrading = true
	_upgrade_target_tier = target_tier
	_upgrade_started_at = _get_time_seconds()
	tier_state_changed.emit()

	var duration: float = _get_upgrade_duration_for_tier(target_tier)
	var wait_timer: SceneTreeTimer = get_tree().create_timer(duration)
	wait_timer.timeout.connect(func() -> void:
		_on_tier_upgrade_finished(session)
	, CONNECT_ONE_SHOT)


func _on_tier_upgrade_finished(session: int) -> void:
	if session != _upgrade_session:
		return

	if not is_instance_valid(self) or is_queued_for_deletion():
		return

	_is_upgrading = false
	command_center_tier = clampi(_upgrade_target_tier, MIN_TIER, MAX_TIER)
	_upgrade_target_tier = 0
	_apply_tier_visuals()
	tier_state_changed.emit()


func _invalidate_tier_upgrade() -> void:
	_upgrade_session += 1
	_is_upgrading = false
	_upgrade_target_tier = 0
	tier_state_changed.emit()


func _ensure_tier_markers() -> void:
	_cleanup_stale_tier_visual_nodes()

	var tier_visuals_root: Node3D = _get_tier_visuals_root()
	_tier2_marker = _resolve_tier_marker(
		tier_visuals_root,
		TIER2_MARKER_NAME,
		TIER2_MARKER_POSITION,
		TIER2_MARKER_COLOR
	)
	_tier3_marker = _resolve_tier_marker(
		tier_visuals_root,
		TIER3_MARKER_NAME,
		TIER3_MARKER_POSITION,
		TIER3_MARKER_COLOR
	)


func _get_tier_visuals_root() -> Node3D:
	if _tier_visuals_root != null and is_instance_valid(_tier_visuals_root):
		return _tier_visuals_root

	var existing_root: Node3D = get_node_or_null(str(TIER_VISUALS_NODE_NAME)) as Node3D
	if existing_root != null:
		_tier_visuals_root = existing_root
		return _tier_visuals_root

	_tier_visuals_root = Node3D.new()
	_tier_visuals_root.name = TIER_VISUALS_NODE_NAME
	add_child(_tier_visuals_root)
	return _tier_visuals_root


func _cleanup_stale_tier_visual_nodes() -> void:
	_remove_duplicate_named_nodes(self, TIER2_MARKER_NAME, _tier2_marker)
	_remove_duplicate_named_nodes(self, TIER3_MARKER_NAME, _tier3_marker)

	var tier_visual_roots: Array[Node3D] = []
	for child: Node in get_children():
		if child.name == TIER_VISUALS_NODE_NAME and child is Node3D:
			tier_visual_roots.append(child as Node3D)

	while tier_visual_roots.size() > 1:
		var extra_root: Node3D = tier_visual_roots.pop_back()
		if extra_root != _tier_visuals_root:
			extra_root.queue_free()

	if tier_visual_roots.size() == 1:
		_tier_visuals_root = tier_visual_roots[0]
		_remove_duplicate_named_nodes(_tier_visuals_root, TIER2_MARKER_NAME, _tier2_marker)
		_remove_duplicate_named_nodes(_tier_visuals_root, TIER3_MARKER_NAME, _tier3_marker)
	else:
		_tier_visuals_root = null

	_cleanup_legacy_tier_visual_addons()


func _cleanup_legacy_tier_visual_addons() -> void:
	var visuals: Node3D = get_node_or_null("Visuals") as Node3D
	if visuals == null:
		return

	for child: Node in visuals.get_children():
		if child.name == &"TownCenterModel":
			continue

		child.queue_free()


func _remove_duplicate_named_nodes(
	parent: Node,
	node_name: StringName,
	keep_node: Node
) -> void:
	if parent == null:
		return

	for child: Node in parent.get_children():
		if child.name != node_name:
			continue
		if child == keep_node:
			continue

		child.queue_free()


func _resolve_tier_marker(
	parent: Node3D,
	marker_name: StringName,
	local_position: Vector3,
	color: Color
) -> MeshInstance3D:
	var existing_marker: MeshInstance3D = parent.get_node_or_null(str(marker_name)) as MeshInstance3D
	if existing_marker != null:
		existing_marker.position = local_position
		_apply_tier_marker_material(existing_marker, color)
		return existing_marker

	return _create_tier_marker(parent, marker_name, local_position, color)


func _create_tier_marker(
	parent: Node3D,
	marker_name: StringName,
	local_position: Vector3,
	color: Color
) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	marker.position = local_position
	marker.visible = false

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = TIER_MARKER_RADIUS
	marker_mesh.height = TIER_MARKER_RADIUS * 2.0
	marker.mesh = marker_mesh
	_apply_tier_marker_material(marker, color)

	parent.add_child(marker)
	return marker


func _apply_tier_marker_material(marker: MeshInstance3D, color: Color) -> void:
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = color
	marker_material.emission_enabled = true
	marker_material.emission = color.darkened(0.2)
	marker.material_override = marker_material


func _apply_tier_visuals() -> void:
	_ensure_tier_markers()

	if _tier2_marker != null and is_instance_valid(_tier2_marker):
		_tier2_marker.visible = command_center_tier >= 2 and command_center_tier < 3
	elif _tier2_marker != null:
		_tier2_marker = null

	if _tier3_marker != null and is_instance_valid(_tier3_marker):
		_tier3_marker.visible = command_center_tier >= 3
	elif _tier3_marker != null:
		_tier3_marker = null


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
	_rally_next_slot = 0
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
	if _is_upgrading:
		return

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


func can_try_enemy_upgrade_tier(max_target_tier: int = 2) -> bool:
	if not is_in_group(&"enemy_command_center"):
		return false

	if building_state != STATE_COMPLETED:
		return false

	if _health_component != null and _health_component.current_health <= 0:
		return false

	if _is_upgrading:
		return false

	if _is_training or _worker_queue_count > 0:
		return false

	var target_tier: int = get_next_upgrade_tier()
	if target_tier <= command_center_tier or target_tier > MAX_TIER:
		return false

	if target_tier > max_target_tier:
		return false

	var costs: Dictionary = get_upgrade_costs(target_tier)
	return EnemyResourceManager.can_afford(int(costs.gold), int(costs.wood))


func try_upgrade_enemy_tier(max_target_tier: int = 2) -> bool:
	if not can_try_enemy_upgrade_tier(max_target_tier):
		return false

	var target_tier: int = get_next_upgrade_tier()
	if target_tier > max_target_tier:
		return false

	var costs: Dictionary = get_upgrade_costs(target_tier)
	var gold_cost: int = int(costs.gold)
	var wood_cost: int = int(costs.wood)
	if not EnemyResourceManager.try_spend(gold_cost, wood_cost):
		return false

	_begin_tier_upgrade(target_tier)
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
	_notify_enemy_worker_production_check()

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


func _notify_enemy_worker_production_check() -> void:
	if not is_in_group(&"enemy_command_center"):
		return

	for node: Node in get_tree().get_nodes_in_group(&"enemy_build_manager"):
		if node is EnemyBuildManager:
			(node as EnemyBuildManager).request_worker_production_check()
			return


func _apply_worker_rally(worker: Worker) -> void:
	if worker == null:
		return

	if _rally_target_type == RallyTargetType.RESOURCE and not _is_valid_rally_resource(_rally_resource):
		_rally_resource = null

	match _rally_target_type:
		RallyTargetType.GROUND:
			worker.set_movement_target(_claim_ground_rally_target())
		RallyTargetType.RESOURCE:
			_assign_worker_to_rally_resource(worker)


func _claim_ground_rally_target() -> Vector3:
	var slot_index: int = _rally_next_slot
	_rally_next_slot += 1
	return GroupMoveSpacing.compute_slot_target(_rally_point, slot_index, RALLY_SLOT_SPACING)


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
