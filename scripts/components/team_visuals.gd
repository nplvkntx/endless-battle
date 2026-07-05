class_name TeamVisuals
extends RefCounted

## Shared team accent visuals for units and buildings.

const PLAYER_TEAM_ID := 0
const ENEMY_TEAM_ID := 1
const NEUTRAL_TEAM_ID := -1

const TEAM_ACCENT_MARKER_NAME := &"TeamAccentMarker"

const PLAYER_ACCENT := Color(0.15, 0.55, 1.0, 1.0)
const ENEMY_ACCENT := Color(1.0, 0.22, 0.18, 1.0)

const BODY_ACCENT_LERP := 0.12
const BODY_EMISSION_STRENGTH := 0.4
const IMPORTED_ART_ACCENT_LERP := 0.05
const IMPORTED_ART_EMISSION_STRENGTH := 0.1
const MARKER_ALPHA := 0.85
const MARKER_EMISSION_STRENGTH := 0.6


static func resolve_team(owner: Node, team_id: int) -> int:
	if not NodeSafety.is_alive_node(owner):
		return NEUTRAL_TEAM_ID

	if team_id >= ENEMY_TEAM_ID:
		return ENEMY_TEAM_ID
	if team_id == PLAYER_TEAM_ID:
		return PLAYER_TEAM_ID
	if _is_enemy_aligned(owner):
		return ENEMY_TEAM_ID
	if _is_player_aligned(owner):
		return PLAYER_TEAM_ID
	return NEUTRAL_TEAM_ID


static func get_accent_color(team: int) -> Color:
	if team == ENEMY_TEAM_ID:
		return ENEMY_ACCENT
	if team == PLAYER_TEAM_ID:
		return PLAYER_ACCENT
	return Color.WHITE


static func apply_to_entity(owner: Node3D, team_id: int) -> void:
	if not NodeSafety.is_alive_node(owner):
		return

	var team: int = resolve_team(owner, team_id)
	if team == NEUTRAL_TEAM_ID:
		_remove_accent_marker(owner)
		return

	if owner is Building:
		_remove_accent_marker(owner)
		var building_accent: Color = get_accent_color(team)
		_apply_building_body_accent(owner, building_accent)
		return

	var accent: Color = get_accent_color(team)
	_remove_accent_marker(owner)
	_apply_body_accent(owner, accent)


static func _is_enemy_aligned(owner: Node) -> bool:
	return (
		owner.is_in_group(&"enemies")
		or owner.is_in_group(&"enemy_workers")
		or owner.is_in_group(&"enemy_command_center")
	)


static func _is_player_aligned(owner: Node) -> bool:
	if _is_enemy_aligned(owner):
		return false
	if owner.is_in_group(&"player_command_center"):
		return true
	if owner.is_in_group(&"workers") or owner.is_in_group(&"units") or owner.is_in_group(&"heroes"):
		return true
	if owner is Building and owner.is_in_group(&"buildings"):
		return true
	return false


static func _ensure_accent_marker(owner: Node3D, accent: Color) -> void:
	var marker: MeshInstance3D = owner.get_node_or_null(str(TEAM_ACCENT_MARKER_NAME)) as MeshInstance3D
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = TEAM_ACCENT_MARKER_NAME
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 0.04
		marker.mesh = cylinder
		owner.add_child(marker)

	var radius: float = _estimate_accent_radius(owner)
	marker.scale = Vector3(radius, 1.0, radius)
	marker.position = _estimate_accent_position(owner)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(accent.r, accent.g, accent.b, MARKER_ALPHA)
	material.emission_enabled = true
	material.emission = accent * MARKER_EMISSION_STRENGTH
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.set_surface_override_material(0, material)
	marker.visible = true


static func _remove_accent_marker(owner: Node3D) -> void:
	var marker: MeshInstance3D = owner.get_node_or_null(str(TEAM_ACCENT_MARKER_NAME)) as MeshInstance3D
	if marker != null:
		marker.visible = false


static func _estimate_accent_radius(owner: Node3D) -> float:
	var mesh: MeshInstance3D = owner.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return 0.8

	var aabb: AABB = mesh.get_aabb()
	return maxf(aabb.size.x, aabb.size.z) * 0.55


static func _estimate_accent_position(owner: Node3D) -> Vector3:
	var mesh: MeshInstance3D = owner.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return Vector3(0.0, 0.02, 0.0)

	var aabb: AABB = mesh.get_aabb()
	return Vector3(0.0, aabb.position.y + 0.02, 0.0)


static func _apply_body_accent(owner: Node3D, accent: Color) -> void:
	var mesh: MeshInstance3D = owner.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return

	_tint_mesh_instance(mesh, accent)


static func _apply_building_body_accent(owner: Node3D, accent: Color) -> void:
	_tint_mesh_tree(owner, accent, owner)


static func _tint_mesh_tree(node: Node, accent: Color, owner: Node3D) -> void:
	if _should_skip_building_visual_node(node, owner):
		return

	if node is MeshInstance3D:
		var subtle_art_tint: bool = _is_imported_art_mesh(node, owner)
		_tint_mesh_instance(node as MeshInstance3D, accent, subtle_art_tint)

	for child: Node in node.get_children():
		_tint_mesh_tree(child, accent, owner)


static func _should_skip_building_visual_node(node: Node, owner: Node3D) -> bool:
	if node == owner:
		return false

	var skip_names: Array[StringName] = [
		&"SelectionIndicator",
		&"ConstructionProgressBar",
		TEAM_ACCENT_MARKER_NAME,
	]
	var current: Node = node
	while current != null and current != owner:
		if current.name in skip_names:
			return true
		current = current.get_parent()

	return false


static func _is_imported_art_mesh(node: Node, owner: Node3D) -> bool:
	var visuals: Node = owner.get_node_or_null("Visuals")
	if visuals == null:
		return false

	return visuals.is_ancestor_of(node)


static func _tint_mesh_instance(
	mesh: MeshInstance3D,
	accent: Color,
	subtle_art_tint: bool = false
) -> void:
	var material: StandardMaterial3D = HealthBarDisplay.duplicate_mesh_material(mesh)
	if material == null:
		return

	if mesh.get_surface_override_material_count() > 0:
		mesh.set_surface_override_material(0, material)
	else:
		mesh.material_override = material

	var accent_lerp: float = (
		IMPORTED_ART_ACCENT_LERP if subtle_art_tint else BODY_ACCENT_LERP
	)
	var emission_strength: float = (
		IMPORTED_ART_EMISSION_STRENGTH if subtle_art_tint else BODY_EMISSION_STRENGTH
	)
	material.emission_enabled = emission_strength > 0.0
	if material.emission_enabled:
		material.emission = accent * emission_strength
	material.albedo_color = material.albedo_color.lerp(accent, accent_lerp)
