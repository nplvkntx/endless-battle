class_name PlayerRtsOccupancyGrid
extends RefCounted

## Production X/Z occupancy grid for custom player RTS routing.
## Adapted from the Movement Lab (AStarGrid2D + inflated static footprints).
## Dynamic units are never marked as blocked cells.

const DEFAULT_CELL_SIZE := 1.0
const DEFAULT_CLEARANCE := 0.75
const DEFAULT_UNIT_RADIUS := 0.4
const MAP_MIN := -50.0
const MAP_MAX := 50.0

var cell_size: float = DEFAULT_CELL_SIZE
var building_clearance: float = DEFAULT_CLEARANCE
var unit_radius: float = DEFAULT_UNIT_RADIUS
var origin_xz: Vector2 = Vector2(MAP_MIN, MAP_MIN)
var grid_width: int = 100
var grid_height: int = 100

var _astar: AStarGrid2D = AStarGrid2D.new()
## Refcount per cell so overlapping footprints can be added/removed independently.
var _cell_refcount: PackedInt32Array = PackedInt32Array()
## obstacle_id -> PackedInt32Array of flat cell indices owned by that obstacle.
var _obstacle_cells: Dictionary = {}
var _dirty: bool = true


func setup(
	p_origin_xz: Vector2 = Vector2(MAP_MIN, MAP_MIN),
	p_width: int = 100,
	p_height: int = 100,
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
	_cell_refcount.resize(grid_width * grid_height)
	_cell_refcount.fill(0)
	_obstacle_cells.clear()
	_dirty = true
	_rebuild_astar()


func clear_all() -> void:
	_cell_refcount.fill(0)
	_obstacle_cells.clear()
	_dirty = true
	_rebuild_astar()


## Registers or refreshes a static obstacle footprint. Uses instance id as key.
func set_obstacle_aabb(obstacle_id: int, center: Vector3, half_extents: Vector3) -> void:
	if obstacle_id < 0:
		return
	clear_obstacle(obstacle_id)

	var inflate: float = unit_radius + building_clearance
	var min_x: float = center.x - half_extents.x - inflate
	var max_x: float = center.x + half_extents.x + inflate
	var min_z: float = center.z - half_extents.z - inflate
	var max_z: float = center.z + half_extents.z + inflate
	var min_cell: Vector2i = world_to_cell(Vector3(min_x, 0.0, min_z))
	var max_cell: Vector2i = world_to_cell(Vector3(max_x, 0.0, max_z))

	var owned := PackedInt32Array()
	for y: int in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x: int in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			var cell := Vector2i(x, y)
			if not is_cell_in_bounds(cell):
				continue
			var flat: int = cell.y * grid_width + cell.x
			_cell_refcount[flat] += 1
			owned.append(flat)
	_obstacle_cells[obstacle_id] = owned
	_dirty = true


func clear_obstacle(obstacle_id: int) -> void:
	if not _obstacle_cells.has(obstacle_id):
		return
	var owned: PackedInt32Array = _obstacle_cells[obstacle_id] as PackedInt32Array
	for flat: int in owned:
		if flat < 0 or flat >= _cell_refcount.size():
			continue
		_cell_refcount[flat] = maxi(0, _cell_refcount[flat] - 1)
	_obstacle_cells.erase(obstacle_id)
	_dirty = true


## Call after batched obstacle edits so A* solids stay in sync.
func commit() -> void:
	if _dirty:
		_rebuild_astar()


func has_obstacle(obstacle_id: int) -> bool:
	return _obstacle_cells.has(obstacle_id)


func obstacle_count() -> int:
	return _obstacle_cells.size()


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height


func is_cell_blocked(cell: Vector2i) -> bool:
	if not is_cell_in_bounds(cell):
		return true
	return _cell_refcount[cell.y * grid_width + cell.x] > 0


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
	if _dirty:
		_rebuild_astar()
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
			if _cell_refcount[y * grid_width + x] > 0:
				_astar.set_point_solid(Vector2i(x, y), true)
	_dirty = false


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
