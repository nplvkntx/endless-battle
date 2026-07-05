class_name SelectionGlow
extends RefCounted

## Team-colored selection glow for units. Uses the existing SelectionIndicator node.

const INDICATOR_NODE_NAME := &"SelectionIndicator"
const RING_NODE_NAME := &"Ring"
const GLOW_MATERIAL_PATH := "res://assets/materials/unit_selection_glow.tres"
const CONFIGURED_META_KEY := &"_selection_glow_configured"

const GLOW_PLAYER := Color(0.15, 0.55, 1.0, 1.0)
const GLOW_ENEMY := Color(1.0, 0.22, 0.18, 1.0)
const GLOW_NEUTRAL := Color(0.55, 0.38, 0.18, 1.0)

const GLOW_ALPHA := 0.22
const EMISSION_STRENGTH := 0.45
const GLOW_HEIGHT := 0.02
const FOOTPRINT_RADIUS_SCALE := 0.48
const DEFAULT_FOOTPRINT_RADIUS := 0.42


static func set_selection_glow_selected(entity: Node, selected: bool) -> void:
	if entity == null or not is_instance_valid(entity):
		return

	var indicator := entity.get_node_or_null(str(INDICATOR_NODE_NAME)) as Node3D
	if indicator == null:
		return

	if selected:
		_apply_team_glow(entity, indicator)
		_hide_team_accent_marker(entity)

	indicator.visible = selected

	var ring := indicator.get_node_or_null(str(RING_NODE_NAME)) as MeshInstance3D
	if ring != null:
		ring.visible = selected


static func _hide_team_accent_marker(entity: Node) -> void:
	var accent_marker := entity.get_node_or_null(str(TeamVisuals.TEAM_ACCENT_MARKER_NAME)) as MeshInstance3D
	if accent_marker != null:
		accent_marker.visible = false


static func _apply_team_glow(entity: Node, indicator: Node3D) -> void:
	var glow_mesh := _find_glow_mesh(indicator)
	if glow_mesh == null:
		return

	_configure_glow_mesh(entity, glow_mesh)

	var glow_color: Color = _resolve_glow_color(entity)
	var material := _build_glow_material(glow_color)
	glow_mesh.set_surface_override_material(0, material)


static func _find_glow_mesh(indicator: Node3D) -> MeshInstance3D:
	var ring := indicator.get_node_or_null(str(RING_NODE_NAME)) as MeshInstance3D
	if ring != null:
		return ring

	for child: Node in indicator.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D

	return null


static func _configure_glow_mesh(entity: Node, glow_mesh: MeshInstance3D) -> void:
	if glow_mesh.get_meta(CONFIGURED_META_KEY, false):
		return

	var radius: float = _estimate_footprint_radius(entity)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = GLOW_HEIGHT
	glow_mesh.mesh = cylinder
	glow_mesh.transform = Transform3D.IDENTITY
	glow_mesh.position = Vector3(0.0, GLOW_HEIGHT * 0.5, 0.0)
	glow_mesh.set_meta(CONFIGURED_META_KEY, true)


static func _estimate_footprint_radius(entity: Node) -> float:
	if not entity is Node3D:
		return DEFAULT_FOOTPRINT_RADIUS

	var owner := entity as Node3D
	var mesh := owner.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return DEFAULT_FOOTPRINT_RADIUS

	var aabb: AABB = mesh.get_aabb()
	return maxf(aabb.size.x, aabb.size.z) * FOOTPRINT_RADIUS_SCALE


static func _resolve_glow_color(entity: Node) -> Color:
	if CombatTargetValidation.is_neutral_creep(entity):
		return GLOW_NEUTRAL

	if entity.is_in_group(&"enemies") or entity.is_in_group(&"enemy_workers"):
		return GLOW_ENEMY

	var team_id: int = _read_team_id(entity)
	if team_id >= TeamVisuals.ENEMY_TEAM_ID:
		return GLOW_ENEMY
	if team_id == TeamVisuals.PLAYER_TEAM_ID:
		return GLOW_PLAYER

	if entity.is_in_group(&"player_command_center"):
		return GLOW_PLAYER
	if entity.is_in_group(&"workers") or entity.is_in_group(&"units") or entity.is_in_group(&"heroes"):
		return GLOW_PLAYER

	return GLOW_PLAYER


static func _read_team_id(entity: Node) -> int:
	var team_value: Variant = entity.get("team_id")
	if team_value == null:
		return TeamVisuals.NEUTRAL_TEAM_ID
	return int(team_value)


static func _build_glow_material(base_color: Color) -> StandardMaterial3D:
	var template: StandardMaterial3D = load(GLOW_MATERIAL_PATH) as StandardMaterial3D
	var material: StandardMaterial3D
	if template != null:
		material = template.duplicate() as StandardMaterial3D
	else:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.emission_enabled = true

	material.albedo_color = Color(base_color.r, base_color.g, base_color.b, GLOW_ALPHA)
	material.emission = Color(base_color.r, base_color.g, base_color.b) * EMISSION_STRENGTH
	return material
