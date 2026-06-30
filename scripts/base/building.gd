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


func _ready() -> void:
	collision_layer = PhysicsLayers.BUILDINGS
	collision_mask = PhysicsLayers.BUILDING_COLLISION_MASK
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	NavigationObstacleSetup.apply_from_collision_body(self)
	_apply_building_data()


func set_selected(selected: bool) -> void:
	is_selected = selected


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
