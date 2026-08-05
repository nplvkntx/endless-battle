class_name ConstructionStageVisuals
extends RefCounted

## Drives multi-stage construction visuals from authoritative progress ratios.
## Stage swaps happen once when a threshold is crossed — never from frame guessing.

const STAGE_COUNT := ConstructionStageSet.STAGE_COUNT
const STAGE_HOST_NAME := &"ConstructionStageHost"
const PLACEHOLDER_NAME := &"ConstructionPlaceholder"
const STAGE_THRESHOLDS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
const REVEAL_ALPHA: Array[float] = [0.28, 0.45, 0.62, 0.8, 1.0]
const REVEAL_SCALE_Y: Array[float] = [0.22, 0.4, 0.62, 0.82, 1.0]
const PLACEHOLDER_ALPHA: Array[float] = [0.35, 0.45, 0.55, 0.7, 1.0]

var _building: Node3D
var _visuals_root: Node3D
var _mesh_instance: MeshInstance3D
var _stage_set: ConstructionStageSet
var _current_stage: int = -1
var _active: bool = false
var _uses_stage_models: bool = false

var _stage_host: Node3D
var _active_stage_instance: Node3D
var _placeholder_mesh: MeshInstance3D

var _original_nodes: Array[Node] = []
var _original_visible: Dictionary = {}
var _original_scales: Dictionary = {}
var _reveal_materials: Array[Dictionary] = []
var _material_restore_entries: Array[Dictionary] = []


static func stage_index_for_progress(progress: float) -> int:
	var clamped: float = clampf(progress, 0.0, 1.0)
	if clamped >= 1.0:
		return 4
	if clamped >= 0.75:
		return 3
	if clamped >= 0.5:
		return 2
	if clamped >= 0.25:
		return 1
	return 0


static func threshold_for_stage(stage_index: int) -> float:
	var safe_index: int = clampi(stage_index, 0, STAGE_COUNT - 1)
	return STAGE_THRESHOLDS[safe_index]


func setup(
	building: Node3D,
	visuals_root: Node3D,
	mesh_instance: MeshInstance3D,
	stage_set: ConstructionStageSet
) -> void:
	_building = building
	_visuals_root = visuals_root
	_mesh_instance = mesh_instance
	_stage_set = stage_set if stage_set != null else ConstructionStageSet.new()
	_uses_stage_models = _stage_set.has_any_stage_scene()
	_current_stage = -1
	_active = false


func get_current_stage() -> int:
	return _current_stage


func is_active() -> bool:
	return _active


func begin_construction() -> void:
	_active = true
	_cache_original_visuals()
	_apply_stage(0, true)


func update_progress(progress: float) -> void:
	if not _active:
		return

	var next_stage: int = stage_index_for_progress(progress)
	if next_stage == _current_stage:
		return

	_apply_stage(next_stage, false)


func finish_construction() -> void:
	if not _active and _current_stage < 0:
		return

	_apply_stage(STAGE_COUNT - 1, true)
	_restore_original_visuals()
	_clear_stage_host()
	_active = false
	_current_stage = STAGE_COUNT - 1


func cleanup() -> void:
	_clear_stage_host()
	_restore_reveal_materials()
	_restore_original_scales_only()
	_original_nodes.clear()
	_original_visible.clear()
	_original_scales.clear()
	_material_restore_entries.clear()
	_active = false
	_current_stage = -1


func _apply_stage(stage_index: int, force: bool) -> void:
	var safe_stage: int = clampi(stage_index, 0, STAGE_COUNT - 1)
	if not force and safe_stage == _current_stage:
		return

	_current_stage = safe_stage

	if _uses_stage_models:
		_apply_model_stage(safe_stage)
	else:
		_apply_reveal_stage(safe_stage)


func _apply_model_stage(stage_index: int) -> void:
	_hide_original_visuals()

	var stage_scene: PackedScene = _stage_set.get_stage_scene(stage_index)
	if stage_index >= STAGE_COUNT - 1 and stage_scene == null:
		_clear_stage_host()
		_show_original_visuals()
		return

	if stage_scene == null:
		_show_placeholder_for_stage(stage_index)
		return

	_ensure_stage_host()
	_clear_active_stage_instance()
	_hide_placeholder()

	var instance: Node = stage_scene.instantiate()
	if instance == null:
		_show_placeholder_for_stage(stage_index)
		return

	_stage_host.add_child(instance)
	if instance is Node3D:
		_active_stage_instance = instance as Node3D
		_active_stage_instance.transform = _stage_set.stage_model_transform
	else:
		instance.queue_free()
		_show_placeholder_for_stage(stage_index)


func _apply_reveal_stage(stage_index: int) -> void:
	_clear_stage_host()
	_show_original_visuals()
	_ensure_reveal_materials()

	var alpha: float = REVEAL_ALPHA[stage_index]
	var scale_y: float = REVEAL_SCALE_Y[stage_index]

	for entry: Dictionary in _reveal_materials:
		var material: StandardMaterial3D = entry.get("material") as StandardMaterial3D
		if material == null:
			continue
		var base_color: Color = entry.get("base_color", Color.WHITE)
		material.albedo_color = Color(base_color.r, base_color.g, base_color.b, alpha)
		material.transparency = (
			BaseMaterial3D.TRANSPARENCY_DISABLED
			if alpha >= 0.999
			else BaseMaterial3D.TRANSPARENCY_ALPHA
		)

	for node: Node in _original_nodes:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var node_3d := node as Node3D
		var base_scale: Vector3 = _original_scales.get(node.get_instance_id(), node_3d.scale)
		node_3d.scale = Vector3(base_scale.x, base_scale.y * scale_y, base_scale.z)

	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		# Keep legacy root mesh hidden; Visuals own presentation.
		_mesh_instance.visible = false


func _show_placeholder_for_stage(stage_index: int) -> void:
	_ensure_stage_host()
	_clear_active_stage_instance()
	_ensure_placeholder_mesh()
	if _placeholder_mesh == null:
		return

	_placeholder_mesh.visible = true
	var alpha: float = PLACEHOLDER_ALPHA[stage_index]
	var scale_y: float = REVEAL_SCALE_Y[stage_index]
	_placeholder_mesh.scale = Vector3(1.0, scale_y, 1.0)

	var material := _placeholder_mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		_placeholder_mesh.set_surface_override_material(0, material)

	material.albedo_color = Color(0.55, 0.55, 0.58, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _cache_original_visuals() -> void:
	_original_nodes.clear()
	_original_visible.clear()
	_original_scales.clear()
	_reveal_materials.clear()
	_material_restore_entries.clear()

	if _visuals_root == null:
		return

	for child: Node in _visuals_root.get_children():
		if child.name == STAGE_HOST_NAME:
			continue
		_original_nodes.append(child)
		if child is Node3D:
			var node_3d := child as Node3D
			_original_visible[child.get_instance_id()] = node_3d.visible
			_original_scales[child.get_instance_id()] = node_3d.scale
		else:
			_original_visible[child.get_instance_id()] = true


func _hide_original_visuals() -> void:
	for node: Node in _original_nodes:
		if not is_instance_valid(node):
			continue
		if node is Node3D:
			(node as Node3D).visible = false


func _show_original_visuals() -> void:
	for node: Node in _original_nodes:
		if not is_instance_valid(node):
			continue
		var was_visible: bool = VariantUtils.to_bool(_original_visible.get(node.get_instance_id(), true))
		if node is Node3D:
			(node as Node3D).visible = was_visible


func _restore_original_visuals() -> void:
	_restore_reveal_materials()
	_show_original_visuals()
	_restore_original_scales_only()


func _restore_original_scales_only() -> void:
	for node: Node in _original_nodes:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var node_3d := node as Node3D
		if _original_scales.has(node.get_instance_id()):
			node_3d.scale = _original_scales[node.get_instance_id()]


func _ensure_reveal_materials() -> void:
	if not _reveal_materials.is_empty():
		return

	for node: Node in _original_nodes:
		if not is_instance_valid(node):
			continue
		_collect_reveal_materials(node)


func _collect_reveal_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		_material_restore_entries.append(
			{
				"mesh": mesh,
				"material_override": mesh.material_override,
				"surface_overrides": _capture_surface_overrides(mesh),
			}
		)

		var surface_count: int = 0
		if mesh.mesh != null:
			surface_count = mesh.mesh.get_surface_count()

		if surface_count <= 0:
			var override_material := _duplicate_as_standard(mesh.material_override)
			if override_material != null:
				mesh.material_override = override_material
				_reveal_materials.append(
					{"material": override_material, "base_color": override_material.albedo_color}
				)
		else:
			for surface_index: int in surface_count:
				var source: Material = mesh.get_active_material(surface_index)
				var duplicated := _duplicate_as_standard(source)
				if duplicated == null:
					continue
				mesh.set_surface_override_material(surface_index, duplicated)
				_reveal_materials.append(
					{"material": duplicated, "base_color": duplicated.albedo_color}
				)

	for child: Node in node.get_children():
		_collect_reveal_materials(child)


func _capture_surface_overrides(mesh: MeshInstance3D) -> Array:
	var overrides: Array = []
	if mesh.mesh == null:
		return overrides

	for surface_index: int in mesh.mesh.get_surface_count():
		overrides.append(mesh.get_surface_override_material(surface_index))
	return overrides


func _duplicate_as_standard(source: Material) -> StandardMaterial3D:
	if source == null:
		var created := StandardMaterial3D.new()
		created.albedo_color = Color(0.6, 0.6, 0.62, 1.0)
		return created

	if source is StandardMaterial3D:
		return (source as StandardMaterial3D).duplicate() as StandardMaterial3D

	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.6, 0.6, 0.62, 1.0)
	return fallback


func _restore_reveal_materials() -> void:
	_reveal_materials.clear()
	for entry: Dictionary in _material_restore_entries:
		var mesh: MeshInstance3D = entry.get("mesh") as MeshInstance3D
		if mesh == null or not is_instance_valid(mesh):
			continue
		mesh.material_override = entry.get("material_override") as Material
		var surface_overrides: Array = entry.get("surface_overrides", [])
		for surface_index: int in surface_overrides.size():
			mesh.set_surface_override_material(
				surface_index,
				surface_overrides[surface_index] as Material
			)
	_material_restore_entries.clear()


func _ensure_stage_host() -> void:
	if _stage_host != null and is_instance_valid(_stage_host):
		return

	if _visuals_root == null:
		return

	var existing: Node = _visuals_root.get_node_or_null(NodePath(String(STAGE_HOST_NAME)))
	if existing is Node3D:
		_stage_host = existing as Node3D
		return

	_stage_host = Node3D.new()
	_stage_host.name = STAGE_HOST_NAME
	_visuals_root.add_child(_stage_host)


func _ensure_placeholder_mesh() -> void:
	_ensure_stage_host()
	if _stage_host == null:
		return

	if _placeholder_mesh != null and is_instance_valid(_placeholder_mesh):
		return

	var existing: Node = _stage_host.get_node_or_null(NodePath(String(PLACEHOLDER_NAME)))
	if existing is MeshInstance3D:
		_placeholder_mesh = existing as MeshInstance3D
		return

	var half_extents := Vector2(1.2, 1.2)
	if _building != null and _building.has_method(&"_get_footprint_half_extents"):
		half_extents = _building.call(&"_get_footprint_half_extents") as Vector2

	var box := BoxMesh.new()
	box.size = Vector3(maxf(half_extents.x * 1.6, 0.8), 1.2, maxf(half_extents.y * 1.6, 0.8))

	_placeholder_mesh = MeshInstance3D.new()
	_placeholder_mesh.name = PLACEHOLDER_NAME
	_placeholder_mesh.mesh = box
	_placeholder_mesh.position.y = box.size.y * 0.5 - 0.6

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.55, 0.58, 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_placeholder_mesh.set_surface_override_material(0, material)
	_stage_host.add_child(_placeholder_mesh)


func _hide_placeholder() -> void:
	if _placeholder_mesh != null and is_instance_valid(_placeholder_mesh):
		_placeholder_mesh.visible = false


func _clear_active_stage_instance() -> void:
	_active_stage_instance = null
	if _stage_host == null or not is_instance_valid(_stage_host):
		return

	var to_free: Array[Node] = []
	for child: Node in _stage_host.get_children():
		if child.name == PLACEHOLDER_NAME:
			continue
		to_free.append(child)
	for node: Node in to_free:
		if is_instance_valid(node):
			node.free()


func _clear_stage_host() -> void:
	_clear_active_stage_instance()
	_placeholder_mesh = null
	if _stage_host != null and is_instance_valid(_stage_host):
		_stage_host.free()
	_stage_host = null
