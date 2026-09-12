class_name GoldMine
extends GatherableResource

## Gold mine resource node with a finite gold supply, occupancy blocker, and
## stable worker access slots around the perimeter.

@export var gold_amount: int = GatheringConfig.GOLD_MINE_STARTING_GOLD

## worker_instance_id -> reservation expiry msec
var _assigned_worker_ids: Dictionary = {}
## Exclusive perimeter slots 0..GOLD_ACCESS_SLOT_COUNT-1. -1 = empty.
var _slot_owner_ids: PackedInt64Array = PackedInt64Array()
var _slot_local_offsets: PackedVector3Array = PackedVector3Array()
var _slots_built: bool = false


func _ready() -> void:
	super._ready()
	_rebuild_access_slots()
	PlayerRouteNavigation.register_static_obstacle(self)


func _exit_tree() -> void:
	if PlayerRouteNavigation != null:
		PlayerRouteNavigation.unregister_static_obstacle(self)


func get_assigned_worker_count() -> int:
	purge_stale_reservations()
	return _assigned_worker_ids.size()


func register_assigned_worker(worker: Object = null) -> void:
	purge_stale_reservations()
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		return

	_assigned_worker_ids[worker_id] = (
		Time.get_ticks_msec() + GatheringConfig.GOLD_RESERVATION_TTL_MSEC
	)


func unregister_assigned_worker(worker: Object = null) -> void:
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		if worker == null:
			_assigned_worker_ids.clear()
			_clear_all_slot_owners()
		return

	_assigned_worker_ids.erase(worker_id)
	_release_slot_for_worker_id(worker_id)


func purge_stale_reservations() -> int:
	var removed: int = 0
	var now_msec: int = Time.get_ticks_msec()
	var stale_ids: Array = []

	for worker_id: Variant in _assigned_worker_ids.keys():
		var expire_msec: int = int(_assigned_worker_ids[worker_id])
		var worker_node: Variant = instance_from_id(int(worker_id))
		if expire_msec > 0 and now_msec > expire_msec:
			stale_ids.append(worker_id)
			continue
		if not NodeSafety.is_alive_node(worker_node):
			stale_ids.append(worker_id)
			continue
		if worker_node is Worker:
			var worker: Worker = worker_node as Worker
			if not worker.is_reserved_to_gather_source(self):
				stale_ids.append(worker_id)

	for worker_id: Variant in stale_ids:
		_assigned_worker_ids.erase(worker_id)
		_release_slot_for_worker_id(int(worker_id))
		removed += 1

	return removed


func refresh_worker_reservation(worker: Object) -> void:
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0 or not _assigned_worker_ids.has(worker_id):
		return

	_assigned_worker_ids[worker_id] = (
		Time.get_ticks_msec() + GatheringConfig.GOLD_RESERVATION_TTL_MSEC
	)


func get_occupancy_half_extents() -> Vector3:
	var half: Vector3 = _get_collision_half_xz()
	var pad: float = GatheringConfig.GOLD_OCCUPANCY_PADDING
	return Vector3(half.x + pad, 1.0, half.z + pad)


func get_access_slot_count() -> int:
	return GatheringConfig.GOLD_ACCESS_SLOT_COUNT


func get_claimed_access_slot(worker: Object) -> int:
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		return -1
	_ensure_slots_built()
	for index: int in _slot_owner_ids.size():
		if _slot_owner_ids[index] == worker_id:
			return index
	return -1


func claim_access_slot(worker: Object, preferred_index: int = -1) -> int:
	_ensure_slots_built()
	purge_stale_reservations()
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		return _overflow_slot_index(preferred_index, 0)

	var existing: int = get_claimed_access_slot(worker)
	if existing >= 0:
		return existing

	var from_position: Vector3 = global_position
	if worker is Node3D:
		from_position = (worker as Node3D).global_position

	var exclusive_count: int = get_access_slot_count()
	if preferred_index >= 0:
		var preferred: int = preferred_index % exclusive_count
		if _slot_owner_ids[preferred] < 0 and is_access_slot_valid(preferred):
			_slot_owner_ids[preferred] = worker_id
			return preferred

	var best_index: int = -1
	var best_distance_sq: float = INF
	for index: int in exclusive_count:
		if _slot_owner_ids[index] >= 0:
			continue
		if not is_access_slot_valid(index):
			continue
		var slot_pos: Vector3 = get_access_world_position(index)
		var offset: Vector3 = slot_pos - from_position
		offset.y = 0.0
		var distance_sq: float = offset.length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = index

	if best_index >= 0:
		_slot_owner_ids[best_index] = worker_id
		return best_index

	return _overflow_slot_index(preferred_index, worker_id)


func release_access_slot(worker: Object) -> void:
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		return
	_release_slot_for_worker_id(worker_id)


func reclaim_access_slot(worker: Object, avoid_index: int = -1) -> int:
	_ensure_slots_built()
	var worker_id: int = _resolve_worker_id(worker)
	var previous: int = get_claimed_access_slot(worker)
	release_access_slot(worker)

	var from_position: Vector3 = global_position
	if worker is Node3D:
		from_position = (worker as Node3D).global_position

	var exclusive_count: int = get_access_slot_count()
	var best_index: int = -1
	var best_distance_sq: float = INF
	for index: int in exclusive_count:
		if index == avoid_index or index == previous:
			continue
		if _slot_owner_ids[index] >= 0:
			continue
		if not is_access_slot_valid(index):
			continue
		var slot_pos: Vector3 = get_access_world_position(index)
		var offset: Vector3 = slot_pos - from_position
		offset.y = 0.0
		var distance_sq: float = offset.length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = index

	if best_index >= 0 and worker_id >= 0:
		_slot_owner_ids[best_index] = worker_id
		return best_index

	var overflow: int = _overflow_slot_index(avoid_index + 1, worker_id)
	if overflow == avoid_index or overflow == previous:
		overflow = _overflow_slot_index(overflow + 1, worker_id + 1)
	return overflow


func get_access_world_position(slot_index: int) -> Vector3:
	_ensure_slots_built()
	var exclusive_count: int = get_access_slot_count()
	if exclusive_count <= 0:
		return global_position
	var ring: int = 0
	var base_index: int = slot_index
	if slot_index >= exclusive_count:
		ring = slot_index / exclusive_count
		base_index = slot_index % exclusive_count
	base_index = posmod(base_index, exclusive_count)
	var offset: Vector3 = _slot_local_offsets[base_index]
	if ring > 0:
		var direction: Vector3 = offset
		direction.y = 0.0
		if direction.length_squared() < 0.001:
			direction = Vector3.FORWARD
		else:
			direction = direction.normalized()
		offset += direction * float(ring) * GatheringConfig.GOLD_ACCESS_RING_STEP
	var world: Vector3 = global_position + offset
	world.y = global_position.y
	return _snap_slot_to_walkable(world)


func is_access_slot_valid(slot_index: int, _worker: Object = null) -> bool:
	if slot_index < 0:
		return false
	var world: Vector3 = get_access_world_position(slot_index)
	if not world.is_finite():
		return false
	if _is_inside_mine_collision(world):
		return false
	if not _is_within_gather_reach(world):
		return false
	if not _is_slot_walkable(world):
		return false
	return true


func _resolve_worker_id(worker: Object) -> int:
	if worker == null or not is_instance_valid(worker):
		return -1
	if worker is Node:
		return (worker as Node).get_instance_id()
	return -1


func get_resource_id() -> StringName:
	return &"gold"


func can_gather() -> bool:
	return gold_amount > 0


func gather(amount: int) -> int:
	if gold_amount <= 0:
		return 0

	var gathered: int = mini(amount, gold_amount)
	gold_amount -= gathered
	if gold_amount <= 0:
		depleted.emit()
	return gathered


func _ensure_slots_built() -> void:
	if _slots_built and _slot_local_offsets.size() == get_access_slot_count():
		return
	_rebuild_access_slots()


func _rebuild_access_slots() -> void:
	var exclusive_count: int = get_access_slot_count()
	var previous_owners: PackedInt64Array = _slot_owner_ids.duplicate()
	_slot_owner_ids.resize(exclusive_count)
	_slot_local_offsets.resize(exclusive_count)
	for index: int in exclusive_count:
		if index < previous_owners.size() and previous_owners[index] != 0:
			_slot_owner_ids[index] = previous_owners[index]
		else:
			_slot_owner_ids[index] = -1

	var collision_half: Vector3 = _get_collision_half_xz()
	var occupancy_half: Vector3 = get_occupancy_half_extents()
	for index: int in exclusive_count:
		var angle: float = TAU * float(index) / float(exclusive_count)
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		var occupancy_edge: float = _aabb_ray_distance(occupancy_half, direction)
		var radius: float = occupancy_edge + GatheringConfig.GOLD_ACCESS_WORKER_CLEARANCE
		var offset: Vector3 = direction * radius
		_slot_local_offsets[index] = _push_offset_until_valid(
			collision_half, direction, offset
		)
	_slots_built = true


func _push_offset_until_valid(collision_half: Vector3, direction: Vector3, offset: Vector3) -> Vector3:
	var gather_reach: float = _gather_reach_distance()
	var candidate: Vector3 = offset
	for _attempt: int in 6:
		var world: Vector3 = global_position + candidate
		world.y = global_position.y
		var snapped: Vector3 = _snap_slot_to_walkable(world)
		var snap_delta: Vector3 = snapped - world
		snap_delta.y = 0.0
		if (
			not _is_inside_mine_collision(snapped)
			and _is_within_gather_reach(snapped)
			and _is_slot_walkable(snapped)
			and snap_delta.length_squared() <= 1.0
		):
			var local: Vector3 = snapped - global_position
			local.y = 0.0
			return local
		candidate += direction * 0.35
		if candidate.length() > gather_reach:
			break
	# Last resort: sit just outside the physical box even if the grid is not ready.
	var fallback_radius: float = (
		_aabb_ray_distance(collision_half, direction)
		+ 0.5
		+ GatheringConfig.GOLD_ACCESS_WORKER_CLEARANCE
	)
	return direction * fallback_radius


func _overflow_slot_index(preferred_index: int, worker_id: int) -> int:
	var exclusive_count: int = get_access_slot_count()
	var seed: int = preferred_index if preferred_index >= 0 else worker_id
	var base: int = posmod(absi(seed), exclusive_count)
	return exclusive_count * GatheringConfig.GOLD_ACCESS_OVERFLOW_RING + base


func _clear_all_slot_owners() -> void:
	for index: int in _slot_owner_ids.size():
		_slot_owner_ids[index] = -1


func _release_slot_for_worker_id(worker_id: int) -> void:
	for index: int in _slot_owner_ids.size():
		if _slot_owner_ids[index] == worker_id:
			_slot_owner_ids[index] = -1


func _get_collision_half_xz() -> Vector3:
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return Vector3(1.5, 1.0, 1.5)
	if collision_shape.shape is BoxShape3D:
		var box := collision_shape.shape as BoxShape3D
		return Vector3(box.size.x * 0.5, 1.0, box.size.z * 0.5)
	if collision_shape.shape is CylinderShape3D:
		var cylinder := collision_shape.shape as CylinderShape3D
		return Vector3(cylinder.radius, 1.0, cylinder.radius)
	return Vector3(1.5, 1.0, 1.5)


func _aabb_ray_distance(half: Vector3, direction: Vector3) -> float:
	var dx: float = absf(direction.x)
	var dz: float = absf(direction.z)
	if dx < 0.001 and dz < 0.001:
		return maxf(half.x, half.z)
	if dx < 0.001:
		return half.z
	if dz < 0.001:
		return half.x
	return minf(half.x / dx, half.z / dz)


func _gather_reach_distance() -> float:
	var half: Vector3 = _get_collision_half_xz()
	return (
		maxf(half.x, half.z)
		+ 0.5
		+ 0.25
		+ GatheringConfig.RESOURCE_INTERACTION_REACH_BONUS
	)


func _is_within_gather_reach(world: Vector3) -> bool:
	var offset: Vector3 = world - global_position
	offset.y = 0.0
	var reach: float = _gather_reach_distance()
	return offset.length_squared() <= reach * reach


func _is_inside_mine_collision(world: Vector3) -> bool:
	var half: Vector3 = _get_collision_half_xz()
	var local: Vector3 = world - global_position
	var clearance: float = 0.5 + 0.08
	return absf(local.x) <= half.x + clearance and absf(local.z) <= half.z + clearance


func _is_slot_walkable(world: Vector3) -> bool:
	if PlayerRouteNavigation == null:
		return true
	PlayerRouteNavigation.ensure_grid_ready()
	if PlayerRouteNavigation.grid == null:
		return true
	var walkable: Vector3 = PlayerRouteNavigation.nearest_walkable_world(world)
	var snap: Vector3 = walkable - world
	snap.y = 0.0
	return snap.length_squared() <= 1.21


func _snap_slot_to_walkable(world: Vector3) -> Vector3:
	if PlayerRouteNavigation == null:
		return world
	PlayerRouteNavigation.ensure_grid_ready()
	if PlayerRouteNavigation.grid == null:
		return world
	var snapped: Vector3 = PlayerRouteNavigation.nearest_walkable_world(world)
	snapped.y = world.y
	return snapped
