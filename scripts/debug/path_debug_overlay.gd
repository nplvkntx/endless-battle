extends CanvasLayer

## Toggle with O. Draws shared / agent navigation paths for selected player units.
## Visual and HUD only — never issues orders or changes movement.

const TOGGLE_KEY := KEY_O
const REFRESH_INTERVAL_SECONDS := 0.2
const PATH_Y := 0.18
const RAW_PATH_Y := 0.14
const LINE_COLOR := Color(0.25, 0.95, 0.35, 0.7)
const RAW_LINE_COLOR := Color(0.95, 0.45, 0.15, 0.45)
const WAYPOINT_COLOR := Color(0.35, 1.0, 0.45, 0.75)
const RAW_WAYPOINT_COLOR := Color(1.0, 0.55, 0.2, 0.55)
const START_COLOR := Color(0.55, 1.0, 0.75, 0.9)
const DEST_COLOR := Color(1.0, 0.95, 0.2, 0.95)
const CLEARANCE_COLOR := Color(0.35, 0.85, 1.0, 0.18)
const UNIT_PHYS_COLOR := Color(0.2, 0.75, 1.0, 0.85)
const UNIT_AGENT_COLOR := Color(0.95, 0.85, 0.2, 0.75)
const BUILDING_PHYS_COLOR := Color(1.0, 0.25, 0.2, 0.7)
const BUILDING_NAV_COLOR := Color(1.0, 0.55, 0.1, 0.55)
const FOOTPRINT_Y := 0.08
const BUILDING_DEBUG_RANGE := 18.0

var _panel: PanelContainer
var _label: Label
var _draw_root: Node3D
var _refresh_timer: float = 0.0
var _enabled: bool = false
var _line_material: StandardMaterial3D
var _raw_line_material: StandardMaterial3D
var _marker_material_waypoint: StandardMaterial3D
var _marker_material_raw_waypoint: StandardMaterial3D
var _marker_material_start: StandardMaterial3D
var _marker_material_dest: StandardMaterial3D
var _clearance_material: StandardMaterial3D
var _unit_phys_material: StandardMaterial3D
var _unit_agent_material: StandardMaterial3D
var _building_phys_material: StandardMaterial3D
var _building_nav_material: StandardMaterial3D


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
	_raw_line_material = _make_unshaded(RAW_LINE_COLOR)
	_marker_material_waypoint = _make_unshaded(WAYPOINT_COLOR)
	_marker_material_raw_waypoint = _make_unshaded(RAW_WAYPOINT_COLOR)
	_marker_material_start = _make_unshaded(START_COLOR)
	_marker_material_dest = _make_unshaded(DEST_COLOR)
	_clearance_material = _make_unshaded(CLEARANCE_COLOR)
	_unit_phys_material = _make_unshaded(UNIT_PHYS_COLOR)
	_unit_agent_material = _make_unshaded(UNIT_AGENT_COLOR)
	_building_phys_material = _make_unshaded(BUILDING_PHYS_COLOR)
	_building_nav_material = _make_unshaded(BUILDING_NAV_COLOR)


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
	_panel.offset_left = -360.0
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
	_draw_clearance_footprints(units)

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
	var seen_route_ids: Dictionary = {}
	var units_without_shared: Array[Unit] = []

	for unit: Unit in units:
		var route: PlayerRoute = PlayerRouteNavigation.get_route_for_unit(unit)
		if route != null and route.route_valid and not route.waypoints.is_empty():
			if seen_route_ids.has(route.route_id):
				continue
			seen_route_ids[route.route_id] = true
			routes.append({
				"waypoints": route.waypoints,
				"raw_waypoints": route.raw_waypoints,
				"clearance_radius": route.route_clearance_radius,
				"waypoint_index": route.get_waypoint_index(unit.get_instance_id()),
				"destination": route.accepted_destination,
				"command_generation": route.command_generation,
				"shared": true,
				"squad_id": route.route_id,
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
			"raw_waypoints": PackedVector3Array(),
			"clearance_radius": 0.0,
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
	var raw_waypoints: PackedVector3Array = route.get(
		"raw_waypoints", PackedVector3Array()
	) as PackedVector3Array
	var clearance: float = float(route.get("clearance_radius", 0.0))

	## RAW NavigationServer path (orange) — drawn first so final sits on top.
	if raw_waypoints.size() >= 2:
		var raw_lifted: PackedVector3Array = PackedVector3Array()
		for point: Vector3 in raw_waypoints:
			raw_lifted.append(Vector3(point.x, RAW_PATH_Y, point.z))
		_draw_polyline(raw_lifted, _raw_line_material)
		for index: int in raw_lifted.size():
			if index == 0 or index == raw_lifted.size() - 1:
				continue
			_draw_marker(raw_lifted[index], 0.09, _marker_material_raw_waypoint)

	if waypoints.is_empty():
		return

	var lifted: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in waypoints:
		lifted.append(Vector3(point.x, PATH_Y, point.z))

	_draw_polyline(lifted, _line_material)

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
		## Clearance rings only while path-debug is on, and only on final route.
		if clearance > 0.05 and index > 0 and index < lifted.size() - 1:
			_draw_clearance_ring(lifted[index], clearance)

	var destination: Vector3 = route.get("destination", Vector3.ZERO) as Vector3
	if destination != Vector3.ZERO:
		var dest_lifted := Vector3(destination.x, PATH_Y, destination.z)
		var last: Vector3 = lifted[lifted.size() - 1]
		if _horizontal_distance(last, dest_lifted) > 0.35:
			_draw_marker(dest_lifted, 0.22, _marker_material_dest)


func _draw_polyline(points: PackedVector3Array, material: StandardMaterial3D) -> void:
	if points.size() < 2 or _draw_root == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
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


func _draw_clearance_ring(position: Vector3, radius: float) -> void:
	if _draw_root == null or radius <= 0.05:
		return
	_draw_circle_outline(position, radius, _clearance_material)


func _draw_clearance_footprints(units: Array[Unit]) -> void:
	if units.is_empty() or _draw_root == null:
		return
	var drawn_buildings: Dictionary = {}
	for unit: Unit in units:
		var dbg: Dictionary = unit.get_movement_execution_debug()
		var col_r: float = float(dbg.get("collision_radius", 0.0))
		var agent_r: float = float(dbg.get("agent_radius", 0.0))
		var center := Vector3(unit.global_position.x, FOOTPRINT_Y, unit.global_position.z)
		if col_r > 0.05:
			_draw_circle_outline(center, col_r, _unit_phys_material)
		if agent_r > 0.05:
			_draw_circle_outline(center, agent_r, _unit_agent_material)
		_draw_nearby_building_footprints(unit.global_position, drawn_buildings)


func _draw_nearby_building_footprints(origin: Vector3, drawn_buildings: Dictionary) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var range_sq: float = BUILDING_DEBUG_RANGE * BUILDING_DEBUG_RANGE
	for node: Node in tree.get_nodes_in_group("buildings"):
		if node == null or not is_instance_valid(node) or not node is Node3D:
			continue
		var building: Node3D = node as Node3D
		var building_id: int = building.get_instance_id()
		if drawn_buildings.has(building_id):
			continue
		var delta: Vector3 = building.global_position - origin
		delta.y = 0.0
		if delta.length_squared() > range_sq:
			continue
		drawn_buildings[building_id] = true
		var phys: Vector2 = NavigationObstacleSetup.physical_half_extents(
			building as CollisionObject3D
		)
		var nav: Vector2 = NavigationObstacleSetup.navigation_half_extents(
			building as CollisionObject3D
		)
		## Prefer live NavigationObstacle vertices when already configured.
		var obstacle: NavigationObstacle3D = (
			building.get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
		)
		if obstacle != null and obstacle.vertices.size() >= 3:
			nav = _obstacle_half_extents(obstacle)
		if phys != Vector2.ZERO:
			_draw_box_outline(building.global_position, phys, _building_phys_material)
		if nav != Vector2.ZERO:
			_draw_box_outline(building.global_position, nav, _building_nav_material)


func _obstacle_half_extents(obstacle: NavigationObstacle3D) -> Vector2:
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for vertex: Vector3 in obstacle.vertices:
		min_x = minf(min_x, vertex.x)
		max_x = maxf(max_x, vertex.x)
		min_z = minf(min_z, vertex.z)
		max_z = maxf(max_z, vertex.z)
	return Vector2((max_x - min_x) * 0.5, (max_z - min_z) * 0.5)


func _draw_circle_outline(position: Vector3, radius: float, material: StandardMaterial3D) -> void:
	if _draw_root == null or radius <= 0.05:
		return
	var segments: int = 28
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for step: int in segments + 1:
		var angle: float = TAU * float(step) / float(segments)
		mesh.surface_add_vertex(
			position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw_root.add_child(instance)


func _draw_box_outline(center: Vector3, half_extents: Vector2, material: StandardMaterial3D) -> void:
	if _draw_root == null or half_extents == Vector2.ZERO:
		return
	var y: float = FOOTPRINT_Y
	var corners: PackedVector3Array = PackedVector3Array([
		Vector3(center.x - half_extents.x, y, center.z - half_extents.y),
		Vector3(center.x + half_extents.x, y, center.z - half_extents.y),
		Vector3(center.x + half_extents.x, y, center.z + half_extents.y),
		Vector3(center.x - half_extents.x, y, center.z + half_extents.y),
		Vector3(center.x - half_extents.x, y, center.z - half_extents.y),
	])
	_draw_polyline(corners, material)


func _build_hud_text(units: Array[Unit], routes: Array[Dictionary]) -> String:
	var telemetry: Dictionary = PlayerRouteNavigation.get_player_move_telemetry()
	var primary: Dictionary = {}
	if not routes.is_empty():
		primary = routes[0]

	var waypoints: PackedVector3Array = primary.get(
		"waypoints", PackedVector3Array()
	) as PackedVector3Array
	var raw_waypoints: PackedVector3Array = primary.get(
		"raw_waypoints", PackedVector3Array()
	) as PackedVector3Array
	var waypoint_count: int = waypoints.size()
	if waypoint_count <= 0:
		waypoint_count = int(telemetry.get("route_waypoint_count", 0))
	var raw_count: int = raw_waypoints.size()
	if raw_count <= 0:
		raw_count = int(telemetry.get("raw_route_waypoint_count", 0))
	var clearance: float = float(primary.get(
		"clearance_radius",
		telemetry.get("route_clearance_radius", 0.0)
	))

	var path_length: float = _path_length(waypoints)
	var raw_length: float = _path_length(raw_waypoints)
	var waypoint_index: int = int(primary.get("waypoint_index", 0))
	var command_generation: int = int(primary.get(
		"command_generation",
		telemetry.get("command_generation", 0)
	))
	var repath_count: int = int(telemetry.get("repath_count", 0))
	var destination_reached: bool = _selection_destination_reached(units, primary)

	var lines: PackedStringArray = PackedStringArray([
		"Path Debug (O)",
		"Green=final  Orange=raw",
		"Cyan=unit phys  Yellow=agentR",
		"Red=bldg phys  Orange=bldg nav",
		"Routes drawn: %d" % routes.size(),
		"Selected units: %d" % units.size(),
		"Raw waypoints: %d" % raw_count,
		"Final waypoints: %d" % waypoint_count,
		"Clearance: %.2f" % clearance,
		"Raw length: %.1f" % raw_length,
		"Final length: %.1f" % path_length,
		"Repath count: %d" % repath_count,
		"Command generation: %d" % command_generation,
		"Current waypoint index: %d" % waypoint_index,
		"Destination reached: %s" % ("yes" if destination_reached else "no"),
		"Player formations: OFF (route baseline)",
		"Orders/s: %.0f | Repaths/s: %.0f" % [
			PerfCounters.get_rate(PerfCounters.KEY_AI_ORDERS),
			PerfCounters.get_rate(PerfCounters.KEY_REPATH_REQUESTS),
		],
		"Local repaths/s: %.0f | Stall recoveries: %d" % [
			PerfCounters.get_rate(PerfCounters.KEY_SQUAD_LOCAL_REPATHS),
			int(telemetry.get("stall_recovery_count", 0)),
		],
	])
	if not units.is_empty():
		lines.append_array(_build_unit_exec_lines(units[0]))
	return "\n".join(lines)


func _build_unit_exec_lines(unit: Unit) -> PackedStringArray:
	var dbg: Dictionary = unit.get_movement_execution_debug()
	var desired: Vector3 = dbg.get("desired_velocity", Vector3.ZERO) as Vector3
	var avoid: Vector3 = dbg.get("avoidance_velocity", Vector3.ZERO) as Vector3
	var sep: Vector3 = dbg.get("separation_correction", Vector3.ZERO) as Vector3
	var final_v: Vector3 = dbg.get("final_velocity", Vector3.ZERO) as Vector3
	var target: Vector3 = dbg.get("movement_target", Vector3.ZERO) as Vector3
	var next_path: Vector3 = dbg.get("nav_next_path_position", Vector3.ZERO) as Vector3
	var queue: Dictionary = dbg.get("queue_mode", {}) as Dictionary
	return PackedStringArray([
		"",
		"— Exec (selected unit) —",
		"ID: %d  gen: %d" % [int(dbg.get("unit_id", 0)), int(dbg.get("command_generation", -1))],
		"WP idx: %d  dist: %.2f  passed: %s" % [
			int(dbg.get("shared_waypoint_index", -1)),
			float(dbg.get("distance_to_waypoint", 0.0)),
			"yes" if bool(dbg.get("waypoint_passed", false)) else "no",
		],
		"Queue: %s  leader:%d  followers:%d  latScale:%.2f  stuckRec:%s" % [
			"ON" if bool(queue.get("queue_mode", false)) else "OFF",
			int(queue.get("leader_id", 0)),
			int(queue.get("follower_count", 0)),
			float(queue.get("lateral_offset_scale", 1.0)),
			"yes" if bool(queue.get("stuck_recovery", false)) else "no",
		],
		"Travel offset: %.2f  agentR: %.2f colR: %.2f" % [
			(dbg.get("travel_offset", Vector3.ZERO) as Vector3).x,
			float(dbg.get("agent_radius", 0.0)),
			float(dbg.get("collision_radius", 0.0)),
		],
		"Target: (%.1f, %.1f)" % [target.x, target.z],
		"Nav next: (%.1f, %.1f)" % [next_path.x, next_path.z],
		"Desired v: (%.2f, %.2f) |%.2f|" % [desired.x, desired.z, desired.length()],
		"Avoid v: (%.2f, %.2f)" % [avoid.x, avoid.z],
		"Sep corr: (%.2f, %.2f) |%.2f|" % [sep.x, sep.z, sep.length()],
		"Final v: (%.2f, %.2f) speed: %.2f" % [
			final_v.x, final_v.z, float(dbg.get("actual_speed", 0.0))
		],
		"Stuck: %.2fs stage:%d  repathT: %.2f" % [
			float(dbg.get("stuck_timer", 0.0)),
			int(dbg.get("stuck_stage", 0)),
			float(dbg.get("repath_timer", 0.0)),
		],
		"Local stall: %.2fs  repaths:%d" % [
			float(dbg.get("local_stall_timer", 0.0)),
			int(dbg.get("local_stall_repaths", 0)),
		],
		"State: %s  moving: %s" % [
			str(dbg.get("movement_state", "?")),
			"yes" if bool(dbg.get("has_move_target", false)) else "no",
		],
		"Formation corr: %s  Stall: %s" % [
			"yes" if bool(dbg.get("formation_correction_ran", false)) else "no",
			"yes" if bool(dbg.get("stall_recovery_ran", false)) else "no",
		],
		"Target reason: %s" % str(dbg.get("target_change_reason", "")),
	])


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
