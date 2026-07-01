class_name Building
extends StaticBody3D

## Base class for all structures (command center, farms, forges, etc.).
## Owns health, construction progress, team ownership, building state, and destruction.
## Stat values must come from an external Resource — never hardcoded in this script.

signal health_changed(current: float, maximum: float)
signal construction_progress_changed(progress: float)
signal building_state_changed(state: StringName)
signal destroyed(building: Building)

const STATE_UNDER_CONSTRUCTION: StringName = &"under_construction"
const STATE_CONSTRUCTING: StringName = &"constructing"
const STATE_COMPLETED: StringName = &"completed"

const CONSTRUCTION_PLACEHOLDER_ALPHA: float = 0.4
const CONSTRUCTION_EDGE_STANDOFF: float = 0.75
const BUILD_RANGE: float = 2.5
const FALLBACK_FOOTPRINT_HALF_EXTENT: float = 1.5
const CONSTRUCTION_PROGRESS_BAR_NAME := &"ConstructionProgressBar"
const CONSTRUCTION_PROGRESS_BAR_WIDTH := 1.4
const CONSTRUCTION_PROGRESS_BAR_HEIGHT := 0.08
const CONSTRUCTION_PROGRESS_BAR_DEPTH := 0.02
const CONSTRUCTION_PROGRESS_BAR_HUE := 0.12
const SELECTION_PULSE_SCALE := 1.04
const SELECTION_PULSE_HALF_DURATION := 0.1

@export var building_data: Resource

var team_id: int = -1
var building_state: StringName = &""
var is_selected: bool = false

var _current_health: float = 0.0
var _max_health: float = 0.0
var _construction_progress: float = 0.0
var _construction_duration: float = 4.0
var _construction_timer_active: bool = false
var _construction_elapsed: float = 0.0
var _registered_builders: Array[Worker] = []
var _mesh_instance: MeshInstance3D
var _feedback_material_ready: bool = false
var _mesh_material: StandardMaterial3D
var _base_albedo: Color
var _base_emission: Color
var _base_emission_enabled: bool
var _feedback_tween: Tween
var _selection_pulse_tween: Tween
var _selection_indicator: Node3D
var _construction_progress_bar: Node3D
var _construction_progress_fill: MeshInstance3D
var _construction_progress_fill_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = PhysicsLayers.BUILDINGS
	collision_mask = PhysicsLayers.BUILDING_COLLISION_MASK
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	_selection_indicator = get_node_or_null("SelectionIndicator") as Node3D
	if _selection_indicator:
		_selection_indicator.visible = false
	NavigationObstacleSetup.apply_from_collision_body(self)
	_apply_building_data()
	call_deferred("apply_team_visuals")


## Applies a subtle team tint across all building meshes from team_id or faction groups.
func apply_team_visuals() -> void:
	TeamVisuals.apply_to_entity(self, team_id)


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return

	is_selected = selected
	if _selection_indicator:
		_selection_indicator.visible = selected
	if selected:
		play_selection_pulse()


func play_selection_pulse() -> void:
	if _mesh_instance == null:
		return

	if _selection_pulse_tween != null and _selection_pulse_tween.is_valid():
		_selection_pulse_tween.kill()

	_mesh_instance.scale = Vector3.ONE

	_selection_pulse_tween = create_tween()
	_selection_pulse_tween.tween_property(
		_mesh_instance,
		"scale",
		Vector3.ONE * SELECTION_PULSE_SCALE,
		SELECTION_PULSE_HALF_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_selection_pulse_tween.tween_property(
		_mesh_instance,
		"scale",
		Vector3.ONE,
		SELECTION_PULSE_HALF_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func set_inspected(inspected: bool) -> void:
	if _selection_indicator:
		_selection_indicator.visible = inspected


func play_target_feedback() -> void:
	_ensure_feedback_material_ready()
	if _mesh_instance == null or _mesh_material == null:
		return

	_feedback_tween = TargetFeedback.play(
		self,
		_mesh_instance,
		_mesh_material,
		_base_albedo,
		_base_emission,
		_base_emission_enabled,
		_feedback_tween
	)


func _ensure_feedback_material_ready() -> void:
	if _feedback_material_ready:
		return

	if _mesh_instance == null:
		return

	var source_material: StandardMaterial3D = (
		_mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	)
	if source_material == null:
		source_material = _mesh_instance.material_override as StandardMaterial3D
	if source_material == null:
		return

	_mesh_material = source_material.duplicate() as StandardMaterial3D
	if _mesh_instance.get_surface_override_material(0) != null:
		_mesh_instance.set_surface_override_material(0, _mesh_material)
	else:
		_mesh_instance.material_override = _mesh_material

	_base_albedo = _mesh_material.albedo_color
	_base_emission = _mesh_material.emission
	_base_emission_enabled = _mesh_material.emission_enabled
	_feedback_material_ready = true


## Loads runtime state from building_data when the data pipeline is available.
func _apply_building_data() -> void:
	# TODO: Read stats and initial state from building_data Resource.
	pass


## Applies damage using values derived from building_data.
func take_damage(_amount: float) -> void:
	# TODO: Implement damage handling.
	pass


## Handles building destruction and notifies listeners through signals.
func destroy_building() -> void:
	destroyed.emit(self)


## Shows an unfinished placeholder until a worker finishes construction.
func _process(delta: float) -> void:
	if building_state == STATE_COMPLETED:
		return

	_prune_invalid_builders()
	if not _has_active_builder_in_range():
		_pause_construction_timer()
		return

	_construction_timer_active = true
	_construction_elapsed += delta
	_construction_progress = clampf(
		_construction_elapsed / maxf(_construction_duration, 0.001),
		0.0,
		1.0
	)
	construction_progress_changed.emit(_construction_progress)
	_update_construction_progress_bar()

	if _construction_progress >= 1.0:
		_on_construction_timer_finished()


func start_under_construction() -> void:
	building_state = STATE_UNDER_CONSTRUCTION
	_construction_progress = 0.0
	_construction_elapsed = 0.0
	_apply_under_construction_visual()
	_show_construction_progress_bar()
	building_state_changed.emit(building_state)
	construction_progress_changed.emit(_construction_progress)
	play_selection_pulse()


func setup_construction(duration: float) -> void:
	_construction_duration = duration


func get_construction_progress_ratio() -> float:
	return _construction_progress


func is_being_constructed() -> bool:
	return (
		building_state == STATE_UNDER_CONSTRUCTION
		or building_state == STATE_CONSTRUCTING
	)


## Returns standoff positions around the building footprint for worker construction.
func get_construction_points() -> Array[Vector3]:
	var half_extents: Vector2 = _get_footprint_half_extents()
	var edge_x: float = half_extents.x + CONSTRUCTION_EDGE_STANDOFF
	var edge_z: float = half_extents.y + CONSTRUCTION_EDGE_STANDOFF
	var local_offsets: Array[Vector3] = [
		Vector3(edge_x, 0.0, edge_z),
		Vector3(0.0, 0.0, edge_z),
		Vector3(-edge_x, 0.0, edge_z),
		Vector3(-edge_x, 0.0, 0.0),
		Vector3(-edge_x, 0.0, -edge_z),
		Vector3(0.0, 0.0, -edge_z),
		Vector3(edge_x, 0.0, -edge_z),
		Vector3(edge_x, 0.0, 0.0),
	]

	var points: Array[Vector3] = []
	for local_offset: Vector3 in local_offsets:
		points.append(_footprint_offset_to_world(local_offset))

	return points


func get_nearest_construction_point(from_position: Vector3) -> Vector3:
	return get_construction_point_by_index(
		get_nearest_construction_point_index(from_position)
	)


func get_construction_point_by_index(point_index: int) -> Vector3:
	var points: Array[Vector3] = get_construction_points()
	if points.is_empty():
		return global_position

	var safe_index: int = posmod(point_index, points.size())
	return points[safe_index]


func get_nearest_construction_point_index(from_position: Vector3) -> int:
	var points: Array[Vector3] = get_construction_points()
	if points.is_empty():
		return 0

	var best_index: int = 0
	var best_distance_sq: float = INF
	for point_index: int in points.size():
		var offset: Vector3 = from_position - points[point_index]
		offset.y = 0.0
		var distance_sq: float = offset.length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = point_index

	return best_index


func get_construction_point_by_rank(from_position: Vector3, rank: int) -> Vector3:
	var ranked_points: Array[Vector3] = _get_construction_points_sorted_by_distance(from_position)
	if ranked_points.is_empty():
		return global_position

	var safe_rank: int = posmod(rank, ranked_points.size())
	return ranked_points[safe_rank]


func is_position_in_construction_range(
	from_position: Vector3,
	build_range: float = BUILD_RANGE,
	worker_radius: float = 0.0
) -> bool:
	var effective_range: float = build_range + worker_radius
	if _is_within_xz_range_of_footprint(from_position, effective_range):
		return true

	var range_sq: float = effective_range * effective_range
	for point: Vector3 in get_construction_points():
		var offset: Vector3 = from_position - point
		offset.y = 0.0
		if offset.length_squared() <= range_sq:
			return true

	return false


func is_position_inside_footprint(from_position: Vector3, padding: float = 0.0) -> bool:
	var half_extents: Vector2 = _get_footprint_half_extents()
	var local_position: Vector3 = global_transform.affine_inverse() * from_position
	return (
		absf(local_position.x) <= half_extents.x + padding
		and absf(local_position.z) <= half_extents.y + padding
	)


func _is_within_xz_range_of_footprint(from_position: Vector3, range: float) -> bool:
	var half_extents: Vector2 = _get_footprint_half_extents()
	var local_position: Vector3 = global_transform.affine_inverse() * from_position
	var dx: float = maxf(absf(local_position.x) - half_extents.x, 0.0)
	var dz: float = maxf(absf(local_position.z) - half_extents.y, 0.0)
	return dx * dx + dz * dz <= range * range


func _get_construction_points_sorted_by_distance(from_position: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = get_construction_points()
	points.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			var offset_a: Vector3 = a - from_position
			offset_a.y = 0.0
			var offset_b: Vector3 = b - from_position
			offset_b.y = 0.0
			return offset_a.length_squared() < offset_b.length_squared()
	)
	return points


func _get_footprint_half_extents() -> Vector2:
	var collision_shape: CollisionShape3D = (
		get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	if collision_shape == null or collision_shape.shape == null:
		return Vector2(FALLBACK_FOOTPRINT_HALF_EXTENT, FALLBACK_FOOTPRINT_HALF_EXTENT)

	var basis_scale: Vector3 = collision_shape.transform.basis.get_scale()
	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		return Vector2(
			absf(box_shape.size.x * basis_scale.x) * 0.5,
			absf(box_shape.size.z * basis_scale.z) * 0.5
		)

	if collision_shape.shape is CylinderShape3D:
		var cylinder_shape := collision_shape.shape as CylinderShape3D
		var radius: float = absf(
			cylinder_shape.radius * maxf(basis_scale.x, basis_scale.z)
		)
		return Vector2(radius, radius)

	return Vector2(FALLBACK_FOOTPRINT_HALF_EXTENT, FALLBACK_FOOTPRINT_HALF_EXTENT)


func _footprint_offset_to_world(local_offset: Vector3) -> Vector3:
	var world_offset: Vector3 = global_transform.basis * local_offset
	return Vector3(
		global_position.x + world_offset.x,
		global_position.y,
		global_position.z + world_offset.z
	)


func unregister_builder(worker: Worker) -> void:
	if worker == null:
		return

	var index: int = _registered_builders.find(worker)
	if index >= 0:
		_registered_builders.remove_at(index)

	_sync_construction_timer_state()


## Called when a worker arrives at the build site.
func register_builder(worker: Worker) -> void:
	if building_state == STATE_COMPLETED:
		if worker != null:
			worker.on_building_construction_finished()
		return

	if worker != null and worker not in _registered_builders:
		_registered_builders.append(worker)

	if building_state == STATE_UNDER_CONSTRUCTION:
		begin_construction()

	_sync_construction_timer_state()
	_update_construction_progress_bar()


## Called when a worker arrives and begins the build timer.
func begin_construction() -> void:
	if building_state == STATE_COMPLETED:
		return

	building_state = STATE_CONSTRUCTING
	building_state_changed.emit(building_state)


## Marks the building as finished and restores its normal appearance.
func complete_construction() -> void:
	building_state = STATE_COMPLETED
	_construction_progress = 1.0
	_apply_completed_visual()
	building_state_changed.emit(building_state)
	construction_progress_changed.emit(_construction_progress)


func set_completed() -> void:
	building_state = STATE_COMPLETED
	_construction_progress = 1.0
	_apply_completed_visual()
	building_state_changed.emit(building_state)
	construction_progress_changed.emit(_construction_progress)


func _on_construction_timer_finished() -> void:
	_construction_timer_active = false
	if building_state == STATE_COMPLETED:
		return

	complete_construction()
	for builder: Worker in _registered_builders:
		if is_instance_valid(builder):
			builder.on_building_construction_finished()
	_registered_builders.clear()


func _apply_under_construction_visual() -> void:
	if _mesh_instance == null:
		return

	var placeholder_material := StandardMaterial3D.new()
	placeholder_material.albedo_color = Color(0.6, 0.6, 0.6, CONSTRUCTION_PLACEHOLDER_ALPHA)
	placeholder_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance.material_override = placeholder_material


func _ensure_construction_progress_bar() -> void:
	if _construction_progress_bar != null:
		return

	_construction_progress_bar = Node3D.new()
	_construction_progress_bar.name = CONSTRUCTION_PROGRESS_BAR_NAME
	add_child(_construction_progress_bar)

	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(
		CONSTRUCTION_PROGRESS_BAR_WIDTH,
		CONSTRUCTION_PROGRESS_BAR_HEIGHT,
		CONSTRUCTION_PROGRESS_BAR_DEPTH
	)

	var background_material := StandardMaterial3D.new()
	background_material.albedo_color = Color(0.15, 0.15, 0.15, 1.0)

	var background := MeshInstance3D.new()
	background.name = &"Background"
	background.mesh = bar_mesh
	background.set_surface_override_material(0, background_material)
	_construction_progress_bar.add_child(background)

	_construction_progress_fill = MeshInstance3D.new()
	_construction_progress_fill.name = &"Fill"
	_construction_progress_fill.mesh = bar_mesh
	_construction_progress_fill.position.z = 0.015

	_construction_progress_fill_material = StandardMaterial3D.new()
	_construction_progress_fill_material.albedo_color = Color(0.55, 0.35, 0.15, 1.0)
	_construction_progress_fill.set_surface_override_material(
		0,
		_construction_progress_fill_material
	)
	_construction_progress_bar.add_child(_construction_progress_fill)

	_construction_progress_bar.position.y = _estimate_construction_progress_bar_height()


func _estimate_construction_progress_bar_height() -> float:
	return _collect_mesh_top_local_y(self, 0.75) + 0.25


func _collect_mesh_top_local_y(node: Node, top_y: float) -> float:
	if node.name == CONSTRUCTION_PROGRESS_BAR_NAME or node.name == &"SelectionIndicator":
		return top_y

	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null:
			var aabb: AABB = mesh.get_aabb()
			var mesh_top: float = mesh.position.y + aabb.position.y + aabb.size.y
			top_y = maxf(top_y, mesh_top)

	for child: Node in node.get_children():
		top_y = _collect_mesh_top_local_y(child, top_y)

	return top_y


func _show_construction_progress_bar() -> void:
	_ensure_construction_progress_bar()
	if _construction_progress_bar == null:
		return

	_construction_progress_bar.visible = true
	_update_construction_progress_bar()


func _hide_construction_progress_bar() -> void:
	if _construction_progress_bar != null:
		_construction_progress_bar.visible = false


func _update_construction_progress_bar() -> void:
	if _construction_progress_bar == null or _construction_progress_fill == null:
		return

	HealthBarDisplay.update_fraction_bar(
		_construction_progress_bar,
		_construction_progress_fill,
		_construction_progress_fill_material,
		_construction_progress,
		CONSTRUCTION_PROGRESS_BAR_WIDTH,
		_construction_progress < 1.0,
		CONSTRUCTION_PROGRESS_BAR_HUE
	)


func _prune_invalid_builders() -> void:
	for index: int in range(_registered_builders.size() - 1, -1, -1):
		var builder: Worker = _registered_builders[index]
		if builder == null or not is_instance_valid(builder):
			_registered_builders.remove_at(index)


func _has_active_builder_in_range() -> bool:
	for builder: Worker in _registered_builders:
		if builder == null or not is_instance_valid(builder):
			continue
		if builder.is_actively_constructing_building(self):
			return true
	return false


func _sync_construction_timer_state() -> void:
	_prune_invalid_builders()
	if _has_active_builder_in_range():
		_construction_timer_active = true
		set_process(true)
	else:
		_pause_construction_timer()


func _pause_construction_timer() -> void:
	_construction_timer_active = false
	set_process(false)


func _apply_completed_visual() -> void:
	_pause_construction_timer()
	_hide_construction_progress_bar()

	if _mesh_instance == null:
		apply_team_visuals()
		return

	_mesh_instance.material_override = null
	_feedback_material_ready = false
	apply_team_visuals()
