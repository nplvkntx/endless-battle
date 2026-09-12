class_name UnitSpatialHash
extends RefCounted

## Sparse occupancy-cell index of combat/movement occupants (instance IDs).
## Units occupy one cell and update only when that cell changes. Buildings occupy
## every cell in their AABB. Neighbor / combat acquire query nearby cells.

var origin_xz: Vector2 = Vector2(PlayerRtsOccupancyGrid.MAP_MIN, PlayerRtsOccupancyGrid.MAP_MIN)
var cell_size: float = PlayerRtsOccupancyGrid.DEFAULT_CELL_SIZE
var grid_width: int = 100
var grid_height: int = 100

## flat cell -> Array of instance IDs
var _cells: Dictionary = {}
## instance_id -> PackedInt32Array of flats currently occupied
var _id_flats: Dictionary = {}


func setup(p_origin_xz: Vector2, p_width: int, p_height: int, p_cell_size: float) -> void:
	origin_xz = p_origin_xz
	grid_width = p_width
	grid_height = p_height
	cell_size = p_cell_size
	clear()


func clear() -> void:
	_cells.clear()
	_id_flats.clear()


func occupant_count() -> int:
	return _id_flats.size()


func world_to_cell(world: Vector3) -> Vector2i:
	var local_x: float = (world.x - origin_xz.x) / cell_size
	var local_z: float = (world.z - origin_xz.y) / cell_size
	return Vector2i(int(floor(local_x)), int(floor(local_z)))


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height


func cell_to_flat(cell: Vector2i) -> int:
	return cell.y * grid_width + cell.x


## Point occupant (units / creeps). No-op when the cell did not change.
func update_point(instance_id: int, world: Vector3) -> void:
	if instance_id <= 0:
		return
	var cell: Vector2i = world_to_cell(world)
	if not is_cell_in_bounds(cell):
		remove(instance_id)
		return
	var flat: int = cell_to_flat(cell)
	var previous: Variant = _id_flats.get(instance_id, null)
	if previous is PackedInt32Array:
		var prev_flats: PackedInt32Array = previous as PackedInt32Array
		if prev_flats.size() == 1 and prev_flats[0] == flat:
			return
	_unbind(instance_id)
	_bind_flat(instance_id, flat)
	var owned := PackedInt32Array()
	owned.append(flat)
	_id_flats[instance_id] = owned


## Multi-cell occupant (buildings). Rebinds only when the footprint set changes.
func update_aabb(instance_id: int, center: Vector3, half_extents: Vector3) -> void:
	if instance_id <= 0:
		return
	var owned := PackedInt32Array()
	var min_cell: Vector2i = world_to_cell(
		Vector3(center.x - half_extents.x, 0.0, center.z - half_extents.z)
	)
	var max_cell: Vector2i = world_to_cell(
		Vector3(center.x + half_extents.x, 0.0, center.z + half_extents.z)
	)
	for y: int in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x: int in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			var cell := Vector2i(x, y)
			if not is_cell_in_bounds(cell):
				continue
			owned.append(cell_to_flat(cell))
	if owned.is_empty():
		update_point(instance_id, center)
		return
	var previous: Variant = _id_flats.get(instance_id, null)
	if previous is PackedInt32Array and _same_flats(previous as PackedInt32Array, owned):
		return
	_unbind(instance_id)
	for flat: int in owned:
		_bind_flat(instance_id, flat)
	_id_flats[instance_id] = owned


func remove(instance_id: int) -> void:
	if instance_id <= 0:
		return
	_unbind(instance_id)
	_id_flats.erase(instance_id)


func has_id(instance_id: int) -> bool:
	return _id_flats.has(instance_id)


## Unique instance IDs in nearby cells, nearest rings first.
## max_count > 0 stops after that many IDs so a 100-unit clump stays bounded.
func query_ids(world: Vector3, radius: float, max_count: int = 0) -> Array[int]:
	var result: Array[int] = []
	if radius <= 0.0 or _cells.is_empty():
		return result
	var center: Vector2i = world_to_cell(world)
	var radius_cells: int = maxi(0, int(ceil(radius / maxf(cell_size, 0.001))))
	var seen: Dictionary = {}
	for ring: int in range(0, radius_cells + 1):
		if _collect_chebyshev_ring(center, ring, result, seen, max_count):
			return result
	return result


func query_all_ids() -> Array[int]:
	var result: Array[int] = []
	for instance_id: Variant in _id_flats.keys():
		result.append(int(instance_id))
	return result


## Returns true when max_count is satisfied.
func _collect_chebyshev_ring(
	center: Vector2i,
	ring: int,
	result: Array[int],
	seen: Dictionary,
	max_count: int
) -> bool:
	if ring <= 0:
		return _collect_cell(center, result, seen, max_count)

	for x: int in range(center.x - ring, center.x + ring + 1):
		if _collect_cell(Vector2i(x, center.y - ring), result, seen, max_count):
			return true
		if _collect_cell(Vector2i(x, center.y + ring), result, seen, max_count):
			return true
	for y: int in range(center.y - ring + 1, center.y + ring):
		if _collect_cell(Vector2i(center.x - ring, y), result, seen, max_count):
			return true
		if _collect_cell(Vector2i(center.x + ring, y), result, seen, max_count):
			return true
	return false


func _collect_cell(
	cell: Vector2i,
	result: Array[int],
	seen: Dictionary,
	max_count: int
) -> bool:
	if not is_cell_in_bounds(cell):
		return false
	var bucket: Variant = _cells.get(cell_to_flat(cell), null)
	if bucket == null:
		return false
	for occupant_id: Variant in bucket as Array:
		var id: int = int(occupant_id)
		if seen.has(id):
			continue
		seen[id] = true
		result.append(id)
		if max_count > 0 and result.size() >= max_count:
			return true
	return false


func _bind_flat(instance_id: int, flat: int) -> void:
	var bucket: Array = _cells.get(flat, [])
	if not bucket.has(instance_id):
		bucket.append(instance_id)
	_cells[flat] = bucket


func _unbind(instance_id: int) -> void:
	var previous: Variant = _id_flats.get(instance_id, null)
	if previous == null:
		return
	var flats: PackedInt32Array = previous as PackedInt32Array
	for flat: int in flats:
		var bucket: Variant = _cells.get(flat, null)
		if bucket == null:
			continue
		var ids: Array = bucket as Array
		var idx: int = ids.find(instance_id)
		if idx >= 0:
			ids.remove_at(idx)
		if ids.is_empty():
			_cells.erase(flat)
		else:
			_cells[flat] = ids


func _same_flats(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i] != b[i]:
			return false
	return true
