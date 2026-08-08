class_name RtsMovementLabUnit
extends Node3D

## Tiny lab-only unit. No production Unit / NavigationAgent3D / physics collision.

signal arrived
signal stuck_changed(is_stuck: bool)

const MOVE_SPEED := 6.0
const ARRIVE_RADIUS := 0.7
const WAYPOINT_RADIUS := 0.9
const SEPARATION_RADIUS := 1.35
const SEPARATION_WEIGHT := 0.35
const ROUTE_WEIGHT := 1.0
const FINAL_SLOT_WEIGHT := 0.55
const STUCK_CHECK_INTERVAL := 0.75
const STUCK_MIN_PROGRESS := 0.35

var slot_destination: Vector3 = Vector3.ZERO
var shared_route: PackedVector3Array = PackedVector3Array()
var route_index: int = 0
var is_moving: bool = false
var has_arrived: bool = false
var is_stuck: bool = false
var unit_index: int = 0

var _grid: RtsMovementLabGrid = null
var _neighbors: Array = []
var _stuck_timer: float = 0.0
var _last_progress_pos: Vector3 = Vector3.ZERO
var _best_dist_to_slot: float = INF
var _mesh: MeshInstance3D = null
var _stuck_marker: MeshInstance3D = null


func setup(grid: RtsMovementLabGrid, index: int, color: Color) -> void:
	_grid = grid
	unit_index = index
	name = "LabUnit_%02d" % index
	_build_visual(color)


func set_neighbors(units: Array) -> void:
	_neighbors = units


func issue_follow_route(route: PackedVector3Array, slot: Vector3) -> void:
	shared_route = route.duplicate()
	slot_destination = Vector3(slot.x, 0.0, slot.z)
	route_index = 0
	is_moving = true
	has_arrived = false
	_set_stuck(false)
	_stuck_timer = 0.0
	_last_progress_pos = global_position
	_best_dist_to_slot = _horizontal_distance(global_position, slot_destination)
	_update_stuck_marker()


func reset_at(pos: Vector3) -> void:
	global_position = Vector3(pos.x, 0.0, pos.z)
	shared_route = PackedVector3Array()
	route_index = 0
	is_moving = false
	has_arrived = false
	_set_stuck(false)
	_stuck_timer = 0.0
	_best_dist_to_slot = INF
	_update_stuck_marker()


func get_current_waypoint() -> Vector3:
	if shared_route.is_empty():
		return slot_destination
	if route_index >= shared_route.size():
		return slot_destination
	return shared_route[route_index]


func tick(delta: float) -> void:
	if not is_moving or has_arrived:
		return
	if _grid == null:
		return

	var to_slot: Vector3 = _flat(slot_destination - global_position)
	var dist_to_slot: float = to_slot.length()
	if dist_to_slot <= ARRIVE_RADIUS:
		_arrive()
		return

	_best_dist_to_slot = minf(_best_dist_to_slot, dist_to_slot)

	var route_dir: Vector3 = _route_direction()
	var separation: Vector3 = _separation_vector()
	var slot_dir: Vector3 = to_slot.normalized() if dist_to_slot > 0.001 else Vector3.ZERO

	# Near the end of the shared route, bias toward personal slot.
	var near_end: bool = shared_route.is_empty() or route_index >= shared_route.size() - 1
	var slot_w: float = FINAL_SLOT_WEIGHT if near_end or dist_to_slot < 4.0 else 0.15

	var desired: Vector3 = (
		route_dir * ROUTE_WEIGHT
		+ separation * SEPARATION_WEIGHT
		+ slot_dir * slot_w
	)
	if desired.length_squared() < 0.0001:
		desired = slot_dir if slot_dir.length_squared() > 0.0 else route_dir
	desired = desired.normalized()

	var step: float = MOVE_SPEED * delta
	var candidate: Vector3 = global_position + desired * step
	candidate.y = 0.0

	if not _grid.is_world_walkable(candidate):
		candidate = _safe_slide(desired, step)
		if candidate == global_position:
			_track_stuck(delta)
			return

	global_position = candidate
	_advance_waypoint()
	_track_stuck(delta)


func _route_direction() -> Vector3:
	if shared_route.is_empty():
		return _flat(slot_destination - global_position).normalized()
	while route_index < shared_route.size():
		var wp: Vector3 = shared_route[route_index]
		var to_wp: Vector3 = _flat(wp - global_position)
		if to_wp.length() <= WAYPOINT_RADIUS:
			route_index += 1
			continue
		return to_wp.normalized()
	return _flat(slot_destination - global_position).normalized()


func _advance_waypoint() -> void:
	if shared_route.is_empty():
		return
	while route_index < shared_route.size():
		var wp: Vector3 = shared_route[route_index]
		if _horizontal_distance(global_position, wp) <= WAYPOINT_RADIUS:
			route_index += 1
			continue
		break


func _separation_vector() -> Vector3:
	var push := Vector3.ZERO
	var count: int = 0
	for other_variant in _neighbors:
		if other_variant == null or other_variant == self:
			continue
		if not (other_variant is RtsMovementLabUnit):
			continue
		var other: RtsMovementLabUnit = other_variant
		if other.has_arrived and not is_moving:
			continue
		var offset: Vector3 = _flat(global_position - other.global_position)
		var dist: float = offset.length()
		if dist <= 0.0001 or dist >= SEPARATION_RADIUS:
			continue
		var strength: float = (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
		push += offset.normalized() * strength
		count += 1
	if count == 0:
		return Vector3.ZERO
	return push / float(count)


func _safe_slide(desired: Vector3, step: float) -> Vector3:
	var candidates: Array[Vector3] = [
		desired,
		Vector3(desired.x, 0.0, 0.0).normalized() if absf(desired.x) > 0.001 else Vector3.ZERO,
		Vector3(0.0, 0.0, desired.z).normalized() if absf(desired.z) > 0.001 else Vector3.ZERO,
		Vector3(-desired.z, 0.0, desired.x).normalized(),
		Vector3(desired.z, 0.0, -desired.x).normalized(),
	]
	for dir: Vector3 in candidates:
		if dir.length_squared() < 0.0001:
			continue
		var next: Vector3 = global_position + dir.normalized() * step
		next.y = 0.0
		if _grid.is_world_walkable(next):
			return next
	return global_position


func _track_stuck(delta: float) -> void:
	if has_arrived:
		return
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	_stuck_timer = 0.0
	var moved: float = _horizontal_distance(global_position, _last_progress_pos)
	var improved: bool = _horizontal_distance(global_position, slot_destination) < _best_dist_to_slot - 0.05
	_last_progress_pos = global_position
	if moved < STUCK_MIN_PROGRESS and not improved:
		_set_stuck(true)
	elif moved >= STUCK_MIN_PROGRESS or improved:
		_set_stuck(false)


func _arrive() -> void:
	has_arrived = true
	is_moving = false
	_set_stuck(false)
	global_position = Vector3(slot_destination.x, 0.0, slot_destination.z)
	_update_stuck_marker()
	arrived.emit()


func _set_stuck(value: bool) -> void:
	if is_stuck == value:
		return
	is_stuck = value
	_update_stuck_marker()
	stuck_changed.emit(is_stuck)


func _update_stuck_marker() -> void:
	if _stuck_marker == null:
		return
	_stuck_marker.visible = is_stuck
	if _mesh != null:
		var mat := _mesh.get_active_material(0) as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.95, 0.2, 0.15) if is_stuck else Color(0.25, 0.75, 1.0)


func _build_visual(color: Color) -> void:
	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.0
	_mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.set_surface_override_material(0, mat)
	_mesh.position = Vector3(0.0, 0.5, 0.0)
	add_child(_mesh)

	_stuck_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	_stuck_marker.mesh = sphere
	var stuck_mat := StandardMaterial3D.new()
	stuck_mat.albedo_color = Color(1.0, 0.1, 0.1)
	stuck_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stuck_marker.set_surface_override_material(0, stuck_mat)
	_stuck_marker.position = Vector3(0.0, 1.35, 0.0)
	_stuck_marker.visible = false
	add_child(_stuck_marker)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
