class_name GatherableResource
extends StaticBody3D

## Base class for worker gather targets such as gold mines and trees.

signal depleted()

const TARGET_FEEDBACK_PULSE_SCALE := 1.18
const TARGET_FEEDBACK_PULSE_DURATION := 0.1
const TARGET_FEEDBACK_PULSE_COUNT := 3

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _mesh_material: StandardMaterial3D
var _base_albedo: Color
var _base_emission: Color
var _base_emission_enabled: bool
var _feedback_tween: Tween


func _ready() -> void:
	if _mesh == null:
		return

	var surface_material := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if surface_material == null:
		return

	_mesh_material = surface_material.duplicate() as StandardMaterial3D
	_mesh.set_surface_override_material(0, _mesh_material)
	_base_albedo = _mesh_material.albedo_color
	_base_emission = _mesh_material.emission
	_base_emission_enabled = _mesh_material.emission_enabled


func play_target_feedback() -> void:
	if _mesh == null or _mesh_material == null:
		return

	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()

	_mesh.scale = Vector3.ONE
	_mesh_material.albedo_color = _base_albedo.lightened(0.35)
	_mesh_material.emission_enabled = true
	_mesh_material.emission = _base_albedo.lightened(0.5)

	_feedback_tween = create_tween()
	for _pulse_index: int in TARGET_FEEDBACK_PULSE_COUNT:
		_feedback_tween.tween_property(
			_mesh,
			"scale",
			Vector3.ONE * TARGET_FEEDBACK_PULSE_SCALE,
			TARGET_FEEDBACK_PULSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_feedback_tween.tween_property(
			_mesh,
			"scale",
			Vector3.ONE,
			TARGET_FEEDBACK_PULSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_feedback_tween.tween_callback(_reset_target_feedback_visual)


func _reset_target_feedback_visual() -> void:
	if _mesh != null:
		_mesh.scale = Vector3.ONE

	if _mesh_material == null:
		return

	_mesh_material.albedo_color = _base_albedo
	_mesh_material.emission = _base_emission
	_mesh_material.emission_enabled = _base_emission_enabled


func get_resource_id() -> StringName:
	push_error("GatherableResource.get_resource_id must be overridden.")
	return &""


func get_gather_chunk_size() -> int:
	match get_resource_id():
		&"gold":
			return GatheringConfig.GATHER_CHUNK_GOLD
		&"wood":
			return GatheringConfig.GATHER_CHUNK_WOOD
		_:
			return 1


func gathers_until_carry_full() -> bool:
	return get_resource_id() == &"wood"


func can_gather() -> bool:
	return true


func gather(_amount: int) -> int:
	return get_gather_chunk_size()
