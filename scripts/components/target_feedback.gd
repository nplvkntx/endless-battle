class_name TargetFeedback
extends RefCounted

## Shared pulse/flash feedback for selection, gather, rally, and attack targets.

const PULSE_SCALE := 1.12
const PULSE_OUT_DURATION := 0.12
const PULSE_IN_DURATION := 0.15

const _VISUAL_MATERIALS_META := &"target_feedback_visual_materials"


static func play(
	host: Node,
	mesh: MeshInstance3D,
	mesh_material: StandardMaterial3D,
	base_albedo: Color,
	base_emission: Color,
	base_emission_enabled: bool,
	existing_tween: Tween
) -> Tween:
	if host == null or mesh == null or mesh_material == null:
		return existing_tween

	if existing_tween != null and existing_tween.is_valid():
		existing_tween.kill()

	mesh.scale = Vector3.ONE
	_apply_material_flash(mesh_material, base_albedo)

	var feedback_tween: Tween = host.create_tween()
	feedback_tween.tween_property(
		mesh,
		"scale",
		Vector3.ONE * PULSE_SCALE,
		PULSE_OUT_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_property(
		mesh,
		"scale",
		Vector3.ONE,
		PULSE_IN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	feedback_tween.tween_callback(
		_reset_material.bind(
			mesh,
			mesh_material,
			base_albedo,
			base_emission,
			base_emission_enabled
		)
	)
	return feedback_tween


static func play_on_visuals(
	host: Node,
	visuals_root: Node3D,
	existing_tween: Tween
) -> Tween:
	if host == null or visuals_root == null:
		return existing_tween

	if existing_tween != null and existing_tween.is_valid():
		existing_tween.kill()

	visuals_root.scale = Vector3.ONE
	var material_entries: Array = _ensure_visual_material_entries(host, visuals_root)
	for entry: Dictionary in material_entries:
		_apply_material_flash(entry["material"], entry["base_albedo"])

	var feedback_tween: Tween = host.create_tween()
	feedback_tween.tween_property(
		visuals_root,
		"scale",
		Vector3.ONE * PULSE_SCALE,
		PULSE_OUT_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_property(
		visuals_root,
		"scale",
		Vector3.ONE,
		PULSE_IN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	feedback_tween.tween_callback(
		_reset_visuals.bind(visuals_root, material_entries)
	)
	return feedback_tween


static func play_selection_pulse(host: Node, visuals_root: Node3D, existing_tween: Tween) -> Tween:
	return play_on_visuals(host, visuals_root, existing_tween)


static func _ensure_visual_material_entries(host: Node, visuals_root: Node3D) -> Array:
	if host.has_meta(_VISUAL_MATERIALS_META):
		var cached_entries: Array = host.get_meta(_VISUAL_MATERIALS_META) as Array
		if _are_material_entries_valid(cached_entries):
			return cached_entries

	var entries: Array = []
	_collect_visible_mesh_materials(visuals_root, entries)
	host.set_meta(_VISUAL_MATERIALS_META, entries)
	return entries


static func _are_material_entries_valid(entries: Array) -> bool:
	if entries.is_empty():
		return false

	for entry: Dictionary in entries:
		var mesh: MeshInstance3D = entry.get("mesh")
		var material: StandardMaterial3D = entry.get("material")
		if mesh == null or not is_instance_valid(mesh):
			return false
		if material == null or not is_instance_valid(material):
			return false
		if mesh.get_surface_override_material(entry["surface_index"]) != material:
			return false

	return true


static func _collect_visible_mesh_materials(node: Node, entries: Array) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.visible and mesh_instance.mesh != null:
			for surface_index: int in mesh_instance.mesh.get_surface_count():
				var source_material: Material = mesh_instance.get_active_material(surface_index)
				if source_material == null or not source_material is StandardMaterial3D:
					continue

				var material: StandardMaterial3D = source_material.duplicate() as StandardMaterial3D
				mesh_instance.set_surface_override_material(surface_index, material)
				entries.append(
					{
						"mesh": mesh_instance,
						"surface_index": surface_index,
						"material": material,
						"base_albedo": material.albedo_color,
						"base_emission": material.emission,
						"base_emission_enabled": material.emission_enabled,
					}
				)

	for child: Node in node.get_children():
		_collect_visible_mesh_materials(child, entries)


static func _apply_material_flash(material: StandardMaterial3D, base_albedo: Color) -> void:
	material.albedo_color = base_albedo.lightened(0.35)
	material.emission_enabled = true
	material.emission = base_albedo.lightened(0.5)


static func _reset_material(
	mesh: MeshInstance3D,
	mesh_material: StandardMaterial3D,
	base_albedo: Color,
	base_emission: Color,
	base_emission_enabled: bool
) -> void:
	if mesh != null:
		mesh.scale = Vector3.ONE

	if mesh_material == null:
		return

	mesh_material.albedo_color = base_albedo
	mesh_material.emission = base_emission
	mesh_material.emission_enabled = base_emission_enabled


static func _reset_visuals(visuals_root: Node3D, material_entries: Array) -> void:
	if visuals_root != null:
		visuals_root.scale = Vector3.ONE

	for entry: Dictionary in material_entries:
		var material: StandardMaterial3D = entry.get("material")
		if material == null:
			continue

		material.albedo_color = entry["base_albedo"]
		material.emission = entry["base_emission"]
		material.emission_enabled = entry["base_emission_enabled"]
