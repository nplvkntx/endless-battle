class_name RtsMovementLab
extends Node3D

## Isolated RTS movement lab. Does not touch production movement systems.
## Launch: res://scenes/debug/rts_movement_lab.tscn

const UNIT_COUNT := 20
const SLOT_SPACING := 1.4
const GROUND_Y := 0.0
const DEFAULT_DESTINATION := Vector3(28.0, 0.0, 0.0)
const ARMY_ORIGIN := Vector3(-28.0, 0.0, 0.0)

var grid: RtsMovementLabGrid = RtsMovementLabGrid.new()
var units: Array[RtsMovementLabUnit] = []
var current_preset: int = 1
var shared_route: PackedVector3Array = PackedVector3Array()
var group_destination: Vector3 = DEFAULT_DESTINATION
var slot_destinations: Array[Vector3] = []

var path_calculations_this_command: int = 0
var total_path_calculations: int = 0
var command_age_sec: float = 0.0
var command_active: bool = false
var show_grid: bool = true
var show_path: bool = true

var _obstacle_root: Node3D
var _viz_root: Node3D
var _slot_root: Node3D
var _unit_root: Node3D
var _camera: Camera3D
var _hud_label: Label
var _ground: StaticBody3D
var _path_mesh: MeshInstance3D
var _dest_marker: MeshInstance3D
var _grid_multimesh: MultiMeshInstance3D


func _ready() -> void:
	_build_world()
	grid.setup(
		Vector2(-40.0, -40.0),
		80,
		80,
		RtsMovementLabGrid.DEFAULT_CELL_SIZE,
		RtsMovementLabGrid.DEFAULT_CLEARANCE,
		RtsMovementLabGrid.DEFAULT_UNIT_RADIUS
	)
	load_preset(1)
	_update_hud()


func _process(delta: float) -> void:
	if command_active:
		command_age_sec += delta
	for unit: RtsMovementLabUnit in units:
		unit.tick(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		match key.keycode:
			KEY_1:
				load_preset(1)
			KEY_2:
				load_preset(2)
			KEY_3:
				load_preset(3)
			KEY_R:
				reset_units()
			KEY_G:
				show_grid = not show_grid
				_refresh_grid_viz()
			KEY_P:
				show_path = not show_path
				_refresh_path_viz()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			var hit: Variant = _raycast_ground(mb.position)
			if hit is Vector3:
				issue_group_move(hit as Vector3)


func load_preset(preset_id: int) -> void:
	current_preset = clampi(preset_id, 1, 3)
	_clear_obstacles()
	grid.clear_obstacles()
	shared_route = PackedVector3Array()
	slot_destinations.clear()
	path_calculations_this_command = 0
	command_active = false
	command_age_sec = 0.0
	match current_preset:
		1:
			_add_building(Vector3(0.0, 1.5, 0.0), Vector3(6.0, 1.5, 8.0), Color(0.55, 0.35, 0.2))
		2:
			# Passage along Z≈0: wide enough for several units, narrow enough to compress.
			_add_building(Vector3(0.0, 1.5, -9.0), Vector3(5.0, 1.5, 5.0), Color(0.5, 0.4, 0.25))
			_add_building(Vector3(0.0, 1.5, 9.0), Vector3(5.0, 1.5, 5.0), Color(0.5, 0.4, 0.25))
		3:
			_add_building(Vector3(-2.0, 1.2, -6.0), Vector3(4.0, 1.2, 3.0), Color(0.45, 0.3, 0.2))
			_add_building(Vector3(4.0, 1.2, -1.0), Vector3(3.0, 1.2, 4.5), Color(0.45, 0.3, 0.2))
			_add_building(Vector3(-1.0, 1.2, 6.0), Vector3(5.0, 1.2, 3.0), Color(0.45, 0.3, 0.2))
			_add_building(Vector3(8.0, 1.0, 5.0), Vector3(2.5, 1.0, 2.5), Color(0.4, 0.28, 0.18))
			_add_building(Vector3(8.0, 1.0, -6.0), Vector3(2.5, 1.0, 2.5), Color(0.4, 0.28, 0.18))
	_ensure_units()
	reset_units()
	_refresh_grid_viz()
	_refresh_path_viz()
	_refresh_slot_viz()


func reset_units() -> void:
	_ensure_units()
	var spawn_positions: Array[Vector3] = _make_spawn_slots(ARMY_ORIGIN, UNIT_COUNT)
	for i: int in units.size():
		units[i].reset_at(spawn_positions[i])
	shared_route = PackedVector3Array()
	slot_destinations.clear()
	path_calculations_this_command = 0
	command_active = false
	command_age_sec = 0.0
	_refresh_path_viz()
	_refresh_slot_viz()


func issue_group_move(destination: Vector3) -> Dictionary:
	group_destination = Vector3(destination.x, GROUND_Y, destination.z)
	if not grid.is_world_walkable(group_destination):
		group_destination = grid.nearest_walkable_world(group_destination)

	var origin: Vector3 = _group_centroid()
	path_calculations_this_command = 0
	shared_route = grid.find_path(origin, group_destination)
	path_calculations_this_command += 1
	total_path_calculations += 1
	command_active = true
	command_age_sec = 0.0

	slot_destinations = _make_destination_slots(group_destination, UNIT_COUNT)
	# Nudge slots onto walkable cells.
	for i: int in slot_destinations.size():
		if not grid.is_world_walkable(slot_destinations[i]):
			slot_destinations[i] = grid.nearest_walkable_world(slot_destinations[i])

	for i: int in units.size():
		var slot: Vector3 = slot_destinations[i] if i < slot_destinations.size() else group_destination
		units[i].issue_follow_route(shared_route, slot)

	_refresh_path_viz()
	_refresh_slot_viz()
	return get_status()


func get_status() -> Dictionary:
	var arrived_count: int = 0
	var moving_count: int = 0
	var stuck_count: int = 0
	var blocked_occupancy: int = 0
	for unit: RtsMovementLabUnit in units:
		if unit.has_arrived:
			arrived_count += 1
		elif unit.is_moving:
			moving_count += 1
		if unit.is_stuck:
			stuck_count += 1
		if not grid.is_world_walkable(unit.global_position):
			blocked_occupancy += 1
	var success: bool = arrived_count == UNIT_COUNT and stuck_count == 0
	return {
		"preset": current_preset,
		"units": units.size(),
		"arrived": arrived_count,
		"moving": moving_count,
		"stuck": stuck_count,
		"blocked_occupancy": blocked_occupancy,
		"path_calculations_this_command": path_calculations_this_command,
		"total_path_calculations": total_path_calculations,
		"path_length": shared_route.size(),
		"waypoints": shared_route.size(),
		"command_age": command_age_sec,
		"route_exists": shared_route.size() > 0,
		"route_avoids_blocked": grid.path_avoids_blocked(shared_route),
		"success": success,
		"fps": Engine.get_frames_per_second(),
	}


func await_all_arrived(timeout_sec: float) -> Dictionary:
	var elapsed: float = 0.0
	while elapsed < timeout_sec:
		var status: Dictionary = get_status()
		if int(status["arrived"]) == UNIT_COUNT:
			return status
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return get_status()


func _build_world() -> void:
	_obstacle_root = Node3D.new()
	_obstacle_root.name = "Obstacles"
	add_child(_obstacle_root)

	_viz_root = Node3D.new()
	_viz_root.name = "Visualization"
	add_child(_viz_root)

	_slot_root = Node3D.new()
	_slot_root.name = "Slots"
	_viz_root.add_child(_slot_root)

	_unit_root = Node3D.new()
	_unit_root.name = "Units"
	add_child(_unit_root)

	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90.0, 90.0)
	ground_mesh.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.18, 0.22, 0.16)
	ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_mesh.set_surface_override_material(0, ground_mat)
	add_child(ground_mesh)

	_ground = StaticBody3D.new()
	_ground.name = "Ground"
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(90.0, 0.2, 90.0)
	collider.shape = shape
	collider.position = Vector3(0.0, -0.1, 0.0)
	_ground.add_child(collider)
	add_child(_ground)

	_camera = Camera3D.new()
	_camera.name = "LabCamera"
	_camera.position = Vector3(0.0, 55.0, 42.0)
	_camera.rotation_degrees = Vector3(-52.0, 0.0, 0.0)
	_camera.current = true
	add_child(_camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(light)

	_path_mesh = MeshInstance3D.new()
	_path_mesh.name = "SharedPath"
	_viz_root.add_child(_path_mesh)

	_dest_marker = MeshInstance3D.new()
	var dest_sphere := SphereMesh.new()
	dest_sphere.radius = 0.45
	dest_sphere.height = 0.9
	_dest_marker.mesh = dest_sphere
	var dest_mat := StandardMaterial3D.new()
	dest_mat.albedo_color = Color(1.0, 0.85, 0.2)
	dest_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dest_marker.set_surface_override_material(0, dest_mat)
	_dest_marker.visible = false
	_viz_root.add_child(_dest_marker)

	_grid_multimesh = MultiMeshInstance3D.new()
	_grid_multimesh.name = "BlockedGrid"
	_viz_root.add_child(_grid_multimesh)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud_label = Label.new()
	_hud_label.name = "LabHUD"
	_hud_label.position = Vector2(16, 16)
	_hud_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_hud_label)


func _ensure_units() -> void:
	while units.size() < UNIT_COUNT:
		var unit := RtsMovementLabUnit.new()
		_unit_root.add_child(unit)
		unit.setup(grid, units.size(), Color(0.25, 0.75, 1.0))
		units.append(unit)
	for unit: RtsMovementLabUnit in units:
		unit.set_neighbors(units)


func _clear_obstacles() -> void:
	for child in _obstacle_root.get_children():
		child.queue_free()


func _add_building(center: Vector3, half_extents: Vector3, color: Color) -> void:
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = half_extents * 2.0
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.set_surface_override_material(0, mat)
	body.position = center
	_obstacle_root.add_child(body)
	grid.mark_building_aabb(center, half_extents)


func get_group_centroid() -> Vector3:
	if units.is_empty():
		return ARMY_ORIGIN
	var sum := Vector3.ZERO
	for unit: RtsMovementLabUnit in units:
		sum += unit.global_position
	var c: Vector3 = sum / float(units.size())
	c.y = GROUND_Y
	return c


func _group_centroid() -> Vector3:
	return get_group_centroid()


func _make_spawn_slots(center: Vector3, count: int) -> Array[Vector3]:
	return _make_grid_offsets(center, count, SLOT_SPACING)


func _make_destination_slots(center: Vector3, count: int) -> Array[Vector3]:
	return _make_grid_offsets(center, count, SLOT_SPACING)


func _make_grid_offsets(center: Vector3, count: int, spacing: float) -> Array[Vector3]:
	var cols: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(cols)))
	var out: Array[Vector3] = []
	var index: int = 0
	for row: int in rows:
		for col: int in cols:
			if index >= count:
				break
			var ox: float = (float(col) - float(cols - 1) * 0.5) * spacing
			var oz: float = (float(row) - float(rows - 1) * 0.5) * spacing
			out.append(Vector3(center.x + ox, GROUND_Y, center.z + oz))
			index += 1
	return out


func _raycast_ground(screen_pos: Vector2) -> Variant:
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t: float = -from.y / dir.y
	if t < 0.0:
		return null
	var hit: Vector3 = from + dir * t
	hit.y = GROUND_Y
	return hit


func _refresh_grid_viz() -> void:
	if _grid_multimesh == null:
		return
	if not show_grid:
		_grid_multimesh.multimesh = null
		return
	var blocked: Array[Vector2i] = grid.get_blocked_cells()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = blocked.size()
	var box := BoxMesh.new()
	box.size = Vector3(grid.cell_size * 0.9, 0.08, grid.cell_size * 0.9)
	mm.mesh = box
	var i: int = 0
	for cell: Vector2i in blocked:
		var center: Vector3 = grid.cell_to_world_center(cell)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(center.x, 0.04, center.z)))
		i += 1
	_grid_multimesh.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.15, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_multimesh.material_override = mat


func _refresh_path_viz() -> void:
	if _path_mesh == null:
		return
	_dest_marker.visible = command_active or shared_route.size() > 0
	_dest_marker.position = Vector3(group_destination.x, 0.5, group_destination.z)
	if not show_path or shared_route.is_empty():
		_path_mesh.mesh = null
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for point: Vector3 in shared_route:
		im.surface_add_vertex(Vector3(point.x, 0.35, point.z))
	im.surface_end()

	# Waypoint markers as small vertical ticks via extra lines.
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for point: Vector3 in shared_route:
		im.surface_add_vertex(Vector3(point.x, 0.1, point.z))
		im.surface_add_vertex(Vector3(point.x, 0.9, point.z))
	im.surface_end()
	_path_mesh.mesh = im


func _refresh_slot_viz() -> void:
	for child in _slot_root.get_children():
		child.queue_free()
	for slot: Vector3 in slot_destinations:
		var marker := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.12
		torus.outer_radius = 0.28
		marker.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.9, 0.3)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.set_surface_override_material(0, mat)
		marker.position = Vector3(slot.x, 0.08, slot.z)
		_slot_root.add_child(marker)


func _update_hud() -> void:
	if _hud_label == null:
		return
	var status: Dictionary = get_status()
	var result_line: String
	if int(status["arrived"]) == UNIT_COUNT and int(status["stuck"]) == 0:
		result_line = "SUCCESS:\n20/20 ARRIVED"
	elif command_active or int(status["arrived"]) > 0 or int(status["stuck"]) > 0:
		result_line = "FAIL:\n%d/20 ARRIVED\n%d STUCK" % [int(status["arrived"]), int(status["stuck"])]
	else:
		result_line = "WAITING FOR COMMAND"

	_hud_label.text = "\n".join([
		"RTS MOVEMENT LAB",
		"Preset: %d" % current_preset,
		"",
		"Units: %d" % int(status["units"]),
		"Arrived: %d/20" % int(status["arrived"]),
		"Moving: %d" % int(status["moving"]),
		"Stuck: %d" % int(status["stuck"]),
		"",
		"Path calculations this command: %d" % int(status["path_calculations_this_command"]),
		"Total path calculations: %d" % int(status["total_path_calculations"]),
		"",
		"Path length: %d" % int(status["path_length"]),
		"Waypoints: %d" % int(status["waypoints"]),
		"Command age: %.1fs" % float(status["command_age"]),
		"",
		"FPS: %d" % int(status["fps"]),
		"",
		result_line,
		"",
		"Controls:",
		"RMB = group move",
		"1/2/3 = presets",
		"R = reset units",
		"G = toggle grid",
		"P = toggle path",
	])
