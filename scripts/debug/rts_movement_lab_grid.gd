class_name RtsMovementLabGrid
extends RefCounted

## Experimental X/Z occupancy grid for the isolated RTS movement lab.
## Uses Godot AStarGrid2D. Not used by production movement.

const DEFAULT_CELL_SIZE := 1.0
const DEFAULT_CLEARANCE := 0.75
const DEFAULT_UNIT_RADIUS := 0.4

var cell_size: float = DEFAULT_CELL_SIZE
var building_clearance: float = DEFAULT_CLEARANCE
var unit_radius: float = DEFAULT_UNIT_RADIUS
var origin_xz: Vector2 = Vector2(-40.0, -40.0)
var grid_width: int = 80
var grid_height: int = 80

var _astar: AStarGrid2D = AStarGrid2D.new()
var _blocked: PackedByteArray = PackedByteArray()


func setup(
	p_origin_xz: Vector2 = Vector2(-40.0, -40.0),
	p_width: int = 80,
	p_height: int = 80,
	p_cell_size: float = DEFAULT_CELL_SIZE,
	p_clearance: float = DEFAULT_CLEARANCE,
	p_unit_radius: float = DEFAULT_UNIT_RADIUS
) -> void:
	origin_xz = p_origin_xz
	grid_width = p_width
	grid_height = p_height
	cell_size = p_cell_size
	building_clearance = p_clearance
	unit_radius = p_unit_radius
	_blocked.resize(grid_width * grid_height)
	_blocked.fill(0)
	_rebuild_astar()


func clear_obstacles() -> void:
	_blocked.fill(0)
	_rebuild_astar()


func mark_building_aabb(center: Vector3, half_extents: Vector3) -> void:
	var inflate: float = unit_radius + building_clearance
	var min_x: float = center.x - half_extents.x - inflate
	var max_x: float = center.x + half_extents.x + inflate
	var min_z: float = center.z - half_extents.z - inflate
	var max_z: float = center.z + half_extents.z + inflate
	var min_cell: Vector2i = world_to_cell(Vector3(min_x, 0.0, min_z))
	var max_cell: Vector2i = world_to_cell(Vector3(max_x, 0.0, max_z))
	for y: int in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x: int in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			_set_blocked(Vector2i(x, y), true)
	_rebuild_astar()


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height


func is_cell_blocked(cell: Vector2i) -> bool:
	if not is_cell_in_bounds(cell):
		return true
	return _blocked[cell.y * grid_width + cell.x] != 0


func is_world_walkable(world: Vector3) -> bool:
	return not is_cell_blocked(world_to_cell(world))


func world_to_cell(world: Vector3) -> Vector2i:
	var local_x: float = (world.x - origin_xz.x) / cell_size
	var local_z: float = (world.z - origin_xz.y) / cell_size
	return Vector2i(int(floor(local_x)), int(floor(local_z)))


func cell_to_world_center(cell: Vector2i) -> Vector3:
	return Vector3(
		origin_xz.x + (float(cell.x) + 0.5) * cell_size,
		0.0,
		origin_xz.y + (float(cell.y) + 0.5) * cell_size
	)


func nearest_walkable_world(world: Vector3) -> Vector3:
	return cell_to_world_center(_nearest_walkable(world_to_cell(world)))


func find_path(from_world: Vector3, to_world: Vector3) -> PackedVector3Array:
	var start: Vector2i = _nearest_walkable(world_to_cell(from_world))
	var goal: Vector2i = _nearest_walkable(world_to_cell(to_world))
	if not is_cell_in_bounds(start) or not is_cell_in_bounds(goal):
		return PackedVector3Array()
	if is_cell_blocked(start) or is_cell_blocked(goal):
		return PackedVector3Array()
	var id_path: Array[Vector2i] = _astar.get_id_path(start, goal)
	var out := PackedVector3Array()
	out.resize(id_path.size())
	for i: int in id_path.size():
		out[i] = cell_to_world_center(id_path[i])
	return out


func path_avoids_blocked(path: PackedVector3Array) -> bool:
	for point: Vector3 in path:
		if not is_world_walkable(point):
			return false
	return true


func get_blocked_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in grid_height:
		for x: int in grid_width:
			var cell := Vector2i(x, y)
			if is_cell_blocked(cell):
				cells.append(cell)
	return cells


func _set_blocked(cell: Vector2i, blocked: bool) -> void:
	if not is_cell_in_bounds(cell):
		return
	_blocked[cell.y * grid_width + cell.x] = 1 if blocked else 0


func _rebuild_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, grid_width, grid_height)
	_astar.cell_size = Vector2(cell_size, cell_size)
	_astar.offset = origin_xz
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y: int in grid_height:
		for x: int in grid_width:
			if _blocked[y * grid_width + x] != 0:
				_astar.set_point_solid(Vector2i(x, y), true)


func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if is_cell_in_bounds(cell) and not is_cell_blocked(cell):
		return cell
	var best: Vector2i = cell
	var best_dist: int = 999999
	for radius: int in range(1, 8):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var candidate := Vector2i(cell.x + dx, cell.y + dy)
				if not is_cell_in_bounds(candidate) or is_cell_blocked(candidate):
					continue
				var dist: int = absi(dx) + absi(dy)
				if dist < best_dist:
					best_dist = dist
					best = candidate
		if best_dist < 999999:
			return best
	return cell
