class_name GatherableResource
extends StaticBody3D

## Base class for worker gather targets such as gold mines and trees.

signal depleted()

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _mesh_material: StandardMaterial3D
var _base_albedo: Color
var _base_emission: Color
var _base_emission_enabled: bool
var _feedback_tween: Tween
var _pending_removal: bool = false


func _ready() -> void:
	depleted.connect(_on_depleted, CONNECT_ONE_SHOT)
	NavigationObstacleSetup.apply_from_collision_body(self)

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

	_feedback_tween = TargetFeedback.play(
		self,
		_mesh,
		_mesh_material,
		_base_albedo,
		_base_emission,
		_base_emission_enabled,
		_feedback_tween
	)


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


func _on_depleted() -> void:
	if _pending_removal:
		return

	_pending_removal = true
	call_deferred("_remove_from_world")


func _remove_from_world() -> void:
	if not is_inside_tree():
		return

	_disable_world_presence()
	queue_free()


func _disable_world_presence() -> void:
	visible = false
	collision_layer = 0
	collision_mask = 0

	var collision_shape: CollisionShape3D = (
		get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	if collision_shape != null:
		collision_shape.disabled = true

	var obstacle: NavigationObstacle3D = (
		get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
	)
	if obstacle != null:
		obstacle.queue_free()
