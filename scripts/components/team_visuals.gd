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
const MARKER_ALPHA := 0.85
const MARKER_EMISSION_STRENGTH := 0.6


static func resolve_team(owner: Node, team_id: int) -> int:
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
	if owner == null:
		return

	var team: int = resolve_team(owner, team_id)
	if team == NEUTRAL_TEAM_ID:
		_remove_accent_marker(owner)
		return

	var accent: Color = get_accent_color(team)
	_ensure_accent_marker(owner, accent)
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

	var source_material: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
	if source_material == null:
		source_material = mesh.material_override as StandardMaterial3D
	if source_material == null and mesh.mesh != null:
		source_material = mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if source_material == null:
		return

	var material: StandardMaterial3D = source_material.duplicate() as StandardMaterial3D
	if material == null:
		return

	if mesh.get_surface_override_material(0) != null:
		mesh.set_surface_override_material(0, material)
	else:
		mesh.material_override = material

	material.emission_enabled = true
	material.emission = accent * BODY_EMISSION_STRENGTH
	material.albedo_color = material.albedo_color.lerp(accent, BODY_ACCENT_LERP)
