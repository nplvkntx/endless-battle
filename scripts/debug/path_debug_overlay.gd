extends CanvasLayer

## Toggle with O. Draws shared / agent navigation paths for selected player units.
## Visual and HUD only — never issues orders or changes movement.

const TOGGLE_KEY := KEY_O
const REFRESH_INTERVAL_SECONDS := 0.2
const PATH_Y := 0.18
const LINE_COLOR := Color(0.25, 0.95, 0.35, 0.55)
const WAYPOINT_COLOR := Color(0.35, 1.0, 0.45, 0.75)
const START_COLOR := Color(0.55, 1.0, 0.75, 0.9)
const DEST_COLOR := Color(1.0, 0.95, 0.2, 0.95)

var _panel: PanelContainer
var _label: Label
var _draw_root: Node3D
var _refresh_timer: float = 0.0
var _enabled: bool = false
var _line_material: StandardMaterial3D
var _marker_material_waypoint: StandardMaterial3D
var _marker_material_start: StandardMaterial3D
var _marker_material_dest: StandardMaterial3D


func _ready() -> void:
	layer = 126
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_build_materials()
	_build_ui()
	set_process(false)
	hide_overlay()
	MatchSession.register_match_reset(&"PathDebugOverlay", hide_overlay)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != TOGGLE_KEY:
		return
	if _enabled:
		hide_overlay()
	else:
		show_overlay()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL_SECONDS:
		return
	_refresh_timer = 0.0
	_refresh_visualization()


func show_overlay() -> void:
	_enabled = true
	_panel.visible = true
	_refresh_timer = REFRESH_INTERVAL_SECONDS
	set_process(true)
	_ensure_draw_root()
	_refresh_visualization()


func hide_overlay() -> void:
	_enabled = false
	_panel.visible = false
	set_process(false)
	_clear_draw_root()


func is_path_debug_enabled() -> bool:
	return _enabled


func _build_materials() -> void:
	_line_material = _make_unshaded(LINE_COLOR)
	_marker_material_waypoint = _make_unshaded(WAYPOINT_COLOR)
	_marker_material_start = _make_unshaded(START_COLOR)
	_marker_material_dest = _make_unshaded(DEST_COLOR)


func _make_unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	return mat


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.08, 0.05, 0.88)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.75, 0.4, 1)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.88, 1))
	_panel.add_child(_label)

	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -320.0
	_panel.offset_top = 12.0
	_panel.offset_right = -12.0
	_panel.offset_bottom = 12.0


func _ensure_draw_root() -> void:
	if _draw_root != null and is_instance_valid(_draw_root):
		return
	var parent: Node = _fx_parent()
	if parent == null:
		return
	_draw_root = Node3D.new()
	_draw_root.name = "PathDebugDrawRoot"
	parent.add_child(_draw_root)


func _clear_draw_root() -> void:
	if _draw_root != null and is_instance_valid(_draw_root):
		_draw_root.queue_free()
	_draw_root = null


func _fx_parent() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


func _refresh_visualization() -> void:
	_ensure_draw_root()
	if _draw_root == null or not is_instance_valid(_draw_root):
		_label.text = "Path Debug (O)\n(no scene)"
		return

	for child: Node in _draw_root.get_children():
		child.queue_free()

	var units: Array[Unit] = _get_selected_player_units()
	if units.is_empty():
		_label.text = "Path Debug (O)\nNo selected player units"
		return

	var routes: Array[Dictionary] = _collect_unique_routes(units)
	for route: Dictionary in routes:
		_draw_route(route)

	_label.text = _build_hud_text(units, routes)


func _get_selected_player_units() -> Array[Unit]:
	var result: Array[Unit] = []
	var selection: Node = _find_selection_manager()
	if selection == null:
		return result
	var selected: Variant = selection.get("selected_units")
	if not selected is Array:
		return result
	for unit_ref: Variant in selected as Array:
		if unit_ref == null or not is_instance_valid(unit_ref) or not unit_ref is Unit:
			continue
		var unit: Unit = unit_ref as Unit
		if unit.is_queued_for_deletion():
			continue
		if unit.is_in_group(&"enemies") or unit.is_in_group(&"neutral_creeps"):
			continue
		result.append(unit)
	return result


func _find_selection_manager() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.find_child("SelectionManager", true, false)


func _collect_unique_routes(units: Array[Unit]) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	var seen_squad_ids: Dictionary = {}
	var units_without_shared: Array[Unit] = []

	for unit: Unit in units:
		var ctx: SquadNavContext = SharedSquadNavigation.get_squad_for_unit(unit)
		if ctx != null and ctx.is_player_squad and not ctx.route_waypoints.is_empty():
			if seen_squad_ids.has(ctx.squad_id):
				continue
			seen_squad_ids[ctx.squad_id] = true
			routes.append({
				"waypoints": ctx.route_waypoints,
				"waypoint_index": ctx.waypoint_index,
				"destination": ctx.strategic_destination,
				"command_generation": ctx.command_generation,
				"shared": true,
				"squad_id": ctx.squad_id,
				"unit": unit,
			})
		else:
			units_without_shared.append(unit)

	for unit: Unit in units_without_shared:
		var path: PackedVector3Array = unit.get_debug_navigation_path()
		if path.is_empty():
			continue
		## Deduplicate identical agent polylines across selected units.
		var signature: String = _path_signature(path)
		var duplicate := false
		for existing: Dictionary in routes:
			if String(existing.get("signature", "")) == signature:
				duplicate = true
				break
		if duplicate:
			continue
		var dest: Vector3 = path[path.size() - 1]
		routes.append({
			"waypoints": path,
			"waypoint_index": 0,
			"destination": dest,
			"command_generation": unit.get_player_squad_command_generation(),
			"shared": false,
			"squad_id": -1,
			"unit": unit,
			"signature": signature,
		})

	return routes


func _path_signature(path: PackedVector3Array) -> String:
	if path.is_empty():
		return ""
	var first: Vector3 = path[0]
	var last: Vector3 = path[path.size() - 1]
	return "%d|%.1f,%.1f|%.1f,%.1f" % [
		path.size(), first.x, first.z, last.x, last.z
	]


func _draw_route(route: Dictionary) -> void:
	var waypoints: PackedVector3Array = route.get("waypoints", PackedVector3Array()) as PackedVector3Array
	if waypoints.is_empty():
		return

	var lifted: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in waypoints:
		lifted.append(Vector3(point.x, PATH_Y, point.z))

	_draw_polyline(lifted)

	for index: int in lifted.size():
		var color_mat: StandardMaterial3D = _marker_material_waypoint
		var radius: float = 0.12
		if index == 0:
			color_mat = _marker_material_start
			radius = 0.18
		elif index == lifted.size() - 1:
			color_mat = _marker_material_dest
			radius = 0.2
		_draw_marker(lifted[index], radius, color_mat)

	var destination: Vector3 = route.get("destination", Vector3.ZERO) as Vector3
	if destination != Vector3.ZERO:
		var dest_lifted := Vector3(destination.x, PATH_Y, destination.z)
		var last: Vector3 = lifted[lifted.size() - 1]
		if _horizontal_distance(last, dest_lifted) > 0.35:
			_draw_marker(dest_lifted, 0.22, _marker_material_dest)


func _draw_polyline(points: PackedVector3Array) -> void:
	if points.size() < 2 or _draw_root == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _line_material)
	for point: Vector3 in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw_root.add_child(instance)


func _draw_marker(position: Vector3, radius: float, material: StandardMaterial3D) -> void:
	if _draw_root == null:
		return
	var instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	instance.mesh = sphere
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = position
	_draw_root.add_child(instance)


func _build_hud_text(units: Array[Unit], routes: Array[Dictionary]) -> String:
	var telemetry: Dictionary = SharedSquadNavigation.get_player_move_telemetry()
	var primary: Dictionary = {}
	if not routes.is_empty():
		primary = routes[0]

	var waypoints: PackedVector3Array = primary.get(
		"waypoints", PackedVector3Array()
	) as PackedVector3Array
	var waypoint_count: int = waypoints.size()
	if waypoint_count <= 0:
		waypoint_count = int(telemetry.get("route_waypoint_count", 0))

	var path_length: float = _path_length(waypoints)
	var waypoint_index: int = int(primary.get("waypoint_index", 0))
	var command_generation: int = int(primary.get(
		"command_generation",
		telemetry.get("command_generation", 0)
	))
	var repath_count: int = int(telemetry.get("repath_count", 0))
	var destination_reached: bool = _selection_destination_reached(units, primary)

	var lines: PackedStringArray = PackedStringArray([
		"Path Debug (O)",
		"Routes drawn: %d" % routes.size(),
		"Selected units: %d" % units.size(),
		"Waypoint count: %d" % waypoint_count,
		"Path length: %.1f" % path_length,
		"Repath count: %d" % repath_count,
		"Command generation: %d" % command_generation,
		"Current waypoint index: %d" % waypoint_index,
		"Destination reached: %s" % ("yes" if destination_reached else "no"),
		"Player formations: %s" % (
			"OFF (debug)" if SharedSquadNavigation.are_player_formations_disabled() else "ON"
		),
	])
	return "\n".join(lines)


func _selection_destination_reached(units: Array[Unit], primary: Dictionary) -> bool:
	if units.is_empty():
		return true
	var destination: Vector3 = primary.get("destination", Vector3.ZERO) as Vector3
	var reached: int = 0
	for unit: Unit in units:
		if unit.is_debug_destination_reached():
			reached += 1
			continue
		if destination != Vector3.ZERO:
			if _horizontal_distance(unit.global_position, destination) <= 3.5:
				reached += 1
	return reached >= units.size()


func _path_length(path: PackedVector3Array) -> float:
	if path.size() < 2:
		return 0.0
	var total: float = 0.0
	for index: int in range(1, path.size()):
		total += _horizontal_distance(path[index - 1], path[index])
	return total


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
