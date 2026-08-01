class_name HeroAbilityPreview
extends Node3D

## World-space ability targeting indicators (range, AoE, skillshot, dash).

const RANGE_COLOR_VALID := Color(0.55, 0.75, 1.0, 0.28)
const RANGE_COLOR_INVALID := Color(1.0, 0.35, 0.3, 0.22)
const AOE_COLOR_VALID := Color(0.45, 0.85, 1.0, 0.35)
const AOE_COLOR_INVALID := Color(1.0, 0.3, 0.25, 0.32)
const LINE_COLOR_VALID := Color(0.7, 0.9, 1.0, 0.75)
const LINE_COLOR_INVALID := Color(1.0, 0.4, 0.3, 0.7)
const ENDPOINT_COLOR_VALID := Color(0.5, 1.0, 0.7, 0.7)
const ENDPOINT_COLOR_INVALID := Color(1.0, 0.35, 0.3, 0.7)
const TARGET_RING_VALID := Color(1.0, 0.35, 0.3, 0.85)
const TARGET_RING_INVALID := Color(0.7, 0.7, 0.7, 0.45)

var _range_mesh: MeshInstance3D
var _aoe_mesh: MeshInstance3D
var _endpoint_mesh: MeshInstance3D
var _target_ring_mesh: MeshInstance3D
var _line_mesh: MeshInstance3D
var _line_immediate: ImmediateMesh
var _range_mat: StandardMaterial3D
var _aoe_mat: StandardMaterial3D
var _endpoint_mat: StandardMaterial3D
var _target_ring_mat: StandardMaterial3D
var _line_mat: StandardMaterial3D


func _ready() -> void:
	_range_mat = _make_mat(RANGE_COLOR_VALID)
	_aoe_mat = _make_mat(AOE_COLOR_VALID)
	_endpoint_mat = _make_mat(ENDPOINT_COLOR_VALID)
	_target_ring_mat = _make_mat(TARGET_RING_VALID)
	_line_mat = _make_mat(LINE_COLOR_VALID)
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_range_mesh = _make_circle_mesh(_range_mat)
	_aoe_mesh = _make_circle_mesh(_aoe_mat)
	_endpoint_mesh = _make_circle_mesh(_endpoint_mat)
	_target_ring_mesh = _make_circle_mesh(_target_ring_mat)

	_line_immediate = ImmediateMesh.new()
	_line_mesh = MeshInstance3D.new()
	_line_mesh.mesh = _line_immediate
	_line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line_mesh)

	clear()


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	return mat


func _make_circle_mesh(mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.04
	cylinder.radial_segments = 48
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false
	add_child(mesh_instance)
	return mesh_instance


func clear() -> void:
	_range_mesh.visible = false
	_aoe_mesh.visible = false
	_endpoint_mesh.visible = false
	_target_ring_mesh.visible = false
	_line_immediate.clear_surfaces()
	_line_mesh.visible = false


func set_cast_range(origin: Vector3, radius: float, is_valid: bool) -> void:
	if radius <= 0.0:
		_range_mesh.visible = false
		return
	_range_mat.albedo_color = RANGE_COLOR_VALID if is_valid else RANGE_COLOR_INVALID
	_range_mesh.visible = true
	_range_mesh.global_position = Vector3(origin.x, 0.05, origin.z)
	_range_mesh.scale = Vector3(radius, 1.0, radius)


func set_aoe_circle(center: Vector3, radius: float, is_valid: bool) -> void:
	if radius <= 0.0:
		_aoe_mesh.visible = false
		return
	_aoe_mat.albedo_color = AOE_COLOR_VALID if is_valid else AOE_COLOR_INVALID
	_aoe_mesh.visible = true
	_aoe_mesh.global_position = Vector3(center.x, 0.06, center.z)
	_aoe_mesh.scale = Vector3(radius, 1.0, radius)


func set_endpoint(point: Vector3, radius: float, is_valid: bool) -> void:
	_endpoint_mat.albedo_color = ENDPOINT_COLOR_VALID if is_valid else ENDPOINT_COLOR_INVALID
	_endpoint_mesh.visible = true
	_endpoint_mesh.global_position = Vector3(point.x, 0.07, point.z)
	_endpoint_mesh.scale = Vector3(maxf(radius, 0.35), 1.0, maxf(radius, 0.35))


func set_target_highlight(target: Node3D, is_valid: bool) -> void:
	if target == null or not is_instance_valid(target):
		_target_ring_mesh.visible = false
		return
	_target_ring_mat.albedo_color = TARGET_RING_VALID if is_valid else TARGET_RING_INVALID
	_target_ring_mesh.visible = true
	var pos: Vector3 = target.global_position
	_target_ring_mesh.global_position = Vector3(pos.x, 0.08, pos.z)
	_target_ring_mesh.scale = Vector3(1.1, 1.0, 1.1)


func set_line(
	from: Vector3,
	to: Vector3,
	width: float,
	is_valid: bool,
	show_width_guides: bool = true
) -> void:
	_line_immediate.clear_surfaces()
	_line_mesh.visible = true
	var color: Color = LINE_COLOR_VALID if is_valid else LINE_COLOR_INVALID
	_line_mat.albedo_color = color

	var start := Vector3(from.x, 0.12, from.z)
	var end := Vector3(to.x, 0.12, to.z)
	var dir: Vector3 = end - start
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		_line_mesh.visible = false
		return

	var forward: Vector3 = dir.normalized()
	var side: Vector3 = Vector3(-forward.z, 0.0, forward.x) * maxf(width * 0.5, 0.05)

	_line_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_mat)
	_add_quad(start - side, start + side, end + side, end - side, color)
	_line_immediate.surface_end()

	if show_width_guides:
		_line_immediate.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
		_line_immediate.surface_add_vertex(start)
		_line_immediate.surface_add_vertex(end)
		_line_immediate.surface_end()


func set_target_line(from: Vector3, to: Vector3, is_valid: bool) -> void:
	set_line(from, to, 0.12, is_valid, false)


func _add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_line_immediate.surface_set_color(color)
	_line_immediate.surface_add_vertex(a)
	_line_immediate.surface_add_vertex(b)
	_line_immediate.surface_add_vertex(c)
	_line_immediate.surface_add_vertex(a)
	_line_immediate.surface_add_vertex(c)
	_line_immediate.surface_add_vertex(d)
