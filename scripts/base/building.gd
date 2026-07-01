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

@export var building_data: Resource

var team_id: int = -1
var building_state: StringName = &""
var is_selected: bool = false

var _current_health: float = 0.0
var _max_health: float = 0.0
var _construction_progress: float = 0.0
var _construction_duration: float = 3.0
var _construction_timer_active: bool = false
var _registered_builders: Array[Worker] = []
var _mesh_instance: MeshInstance3D
var _feedback_material_ready: bool = false
var _mesh_material: StandardMaterial3D
var _base_albedo: Color
var _base_emission: Color
var _base_emission_enabled: bool
var _feedback_tween: Tween
var _selection_indicator: Node3D


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


## Applies a team-colored accent ring and subtle body tint from team_id or faction groups.
func apply_team_visuals() -> void:
	TeamVisuals.apply_to_entity(self, team_id)


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return

	is_selected = selected
	if _selection_indicator:
		_selection_indicator.visible = selected


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
func start_under_construction() -> void:
	building_state = STATE_UNDER_CONSTRUCTION
	_construction_progress = 0.0
	_apply_under_construction_visual()
	building_state_changed.emit(building_state)
	construction_progress_changed.emit(_construction_progress)


func setup_construction(duration: float) -> void:
	_construction_duration = duration


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
	from_position: Vector3, build_range: float = BUILD_RANGE
) -> bool:
	var range_sq: float = build_range * build_range
	for point: Vector3 in get_construction_points():
		var offset: Vector3 = from_position - point
		offset.y = 0.0
		if offset.length_squared() <= range_sq:
			return true

	return false


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

	if _construction_timer_active:
		return

	_construction_timer_active = true
	var wait_timer: SceneTreeTimer = get_tree().create_timer(_construction_duration)
	wait_timer.timeout.connect(_on_construction_timer_finished, CONNECT_ONE_SHOT)


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


func _apply_completed_visual() -> void:
	if _mesh_instance == null:
		return

	_mesh_instance.material_override = null
	_feedback_material_ready = false
	apply_team_visuals()
