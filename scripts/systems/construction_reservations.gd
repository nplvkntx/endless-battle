class_name ConstructionReservations
extends RefCounted

## Shared footprint placement holds and construction approach-slot claims.
## All entries expire by TTL and release on death / cancel / path fail / destroy.

const FOOTPRINT_RESERVATION_TTL_MSEC: int = 15000
const BUILD_SLOT_RESERVATION_TTL_MSEC: int = 45000
const FARM_RESOURCE_RESERVATION_TTL_MSEC: int = 30000
const MAX_BUILD_SLOTS_PER_BUILDING: int = 8
const FOOTPRINT_PADDING: float = 0.4

## reservation_id -> {center: Vector3, footprint: Vector2, owner_id: int, expires_msec: int}
static var _footprint_reservations: Dictionary = {}

## building_id -> {worker_id: {slot: int, expires_msec: int}}
static var _build_slot_owners: Dictionary = {}

static var _next_footprint_id: int = 1


static func reset_match_state() -> void:
	_footprint_reservations.clear()
	_build_slot_owners.clear()
	_next_footprint_id = 1


static func purge_expired() -> void:
	var now_msec: int = Time.get_ticks_msec()
	for reservation_id: Variant in _footprint_reservations.keys():
		var entry: Dictionary = _footprint_reservations[reservation_id]
		if now_msec >= int(entry.get("expires_msec", 0)):
			_footprint_reservations.erase(reservation_id)
			continue
		var owner_id: int = int(entry.get("owner_id", 0))
		if owner_id != 0 and not _is_alive_instance_id(owner_id):
			_footprint_reservations.erase(reservation_id)

	for building_id: Variant in _build_slot_owners.keys():
		_purge_stale_build_slots_for_building(int(building_id), now_msec)


static func reserve_footprint(
	center: Vector3,
	footprint: Vector2,
	owner: Object = null,
	ttl_msec: int = FOOTPRINT_RESERVATION_TTL_MSEC,
	reservation_id: int = 0
) -> int:
	purge_expired()
	var id: int = reservation_id
	if id <= 0:
		id = _next_footprint_id
		_next_footprint_id += 1

	var owner_id: int = 0
	if owner != null and is_instance_valid(owner):
		owner_id = owner.get_instance_id()

	_footprint_reservations[id] = {
		"center": center,
		"footprint": footprint,
		"owner_id": owner_id,
		"expires_msec": Time.get_ticks_msec() + maxi(ttl_msec, 1),
	}
	return id


static func refresh_footprint(reservation_id: int, ttl_msec: int = FOOTPRINT_RESERVATION_TTL_MSEC) -> void:
	if reservation_id <= 0 or not _footprint_reservations.has(reservation_id):
		return

	var entry: Dictionary = _footprint_reservations[reservation_id]
	entry["expires_msec"] = Time.get_ticks_msec() + maxi(ttl_msec, 1)
	_footprint_reservations[reservation_id] = entry


static func release_footprint(reservation_id: int) -> void:
	if reservation_id <= 0:
		return
	_footprint_reservations.erase(reservation_id)


static func release_footprints_for_owner(owner: Object) -> void:
	if owner == null or not is_instance_valid(owner):
		return

	var owner_id: int = owner.get_instance_id()
	for reservation_id: Variant in _footprint_reservations.keys():
		var entry: Dictionary = _footprint_reservations[reservation_id]
		if int(entry.get("owner_id", 0)) == owner_id:
			_footprint_reservations.erase(reservation_id)


static func overlaps_reserved_footprint(
	center: Vector3,
	footprint: Vector2,
	padding: float = FOOTPRINT_PADDING,
	ignore_reservation_id: int = 0
) -> bool:
	purge_expired()
	for reservation_id: Variant in _footprint_reservations.keys():
		if int(reservation_id) == ignore_reservation_id:
			continue

		var entry: Dictionary = _footprint_reservations[reservation_id]
		var reserved_center: Vector3 = entry.get("center", Vector3.ZERO) as Vector3
		var reserved_footprint: Vector2 = entry.get("footprint", Vector2.ZERO) as Vector2
		if _aabb_overlaps(center, footprint, reserved_center, reserved_footprint, padding):
			return true

	return false


static func claim_build_slot(building: Building, worker: Worker, preferred_slot: int = -1) -> int:
	if not NodeSafety.is_alive_node(building) or not NodeSafety.is_alive_node(worker):
		return -1

	purge_expired()
	var building_id: int = building.get_instance_id()
	var worker_id: int = worker.get_instance_id()
	var owners: Dictionary = _build_slot_owners.get(building_id, {}) as Dictionary

	if owners.has(worker_id):
		var existing: Dictionary = owners[worker_id]
		existing["expires_msec"] = Time.get_ticks_msec() + BUILD_SLOT_RESERVATION_TTL_MSEC
		owners[worker_id] = existing
		_build_slot_owners[building_id] = owners
		return int(existing.get("slot", 0))

	var occupied: Dictionary = {}
	for other_worker_id: Variant in owners.keys():
		occupied[int((owners[other_worker_id] as Dictionary).get("slot", -1))] = true

	var slot: int = preferred_slot
	if slot < 0 or occupied.has(slot):
		slot = 0
		while occupied.has(slot) and slot < MAX_BUILD_SLOTS_PER_BUILDING:
			slot += 1

	if slot >= MAX_BUILD_SLOTS_PER_BUILDING:
		# Allow overlapping as last resort rather than blocking construction forever.
		slot = preferred_slot if preferred_slot >= 0 else 0

	owners[worker_id] = {
		"slot": slot,
		"expires_msec": Time.get_ticks_msec() + BUILD_SLOT_RESERVATION_TTL_MSEC,
	}
	_build_slot_owners[building_id] = owners
	return slot


static func refresh_build_slot(building: Building, worker: Worker) -> void:
	if not NodeSafety.is_alive_node(building) or not NodeSafety.is_alive_node(worker):
		return

	var building_id: int = building.get_instance_id()
	if not _build_slot_owners.has(building_id):
		return

	var owners: Dictionary = _build_slot_owners[building_id]
	var worker_id: int = worker.get_instance_id()
	if not owners.has(worker_id):
		return

	var entry: Dictionary = owners[worker_id]
	entry["expires_msec"] = Time.get_ticks_msec() + BUILD_SLOT_RESERVATION_TTL_MSEC
	owners[worker_id] = entry
	_build_slot_owners[building_id] = owners


static func release_build_slot(building: Building, worker: Worker) -> void:
	if building == null or not is_instance_valid(building):
		return
	if worker == null or not is_instance_valid(worker):
		return

	var building_id: int = building.get_instance_id()
	if not _build_slot_owners.has(building_id):
		return

	var owners: Dictionary = _build_slot_owners[building_id]
	owners.erase(worker.get_instance_id())
	if owners.is_empty():
		_build_slot_owners.erase(building_id)
	else:
		_build_slot_owners[building_id] = owners


static func release_build_slots_for_worker(worker: Worker) -> void:
	if worker == null or not is_instance_valid(worker):
		return

	var worker_id: int = worker.get_instance_id()
	for building_id: Variant in _build_slot_owners.keys():
		var owners: Dictionary = _build_slot_owners[building_id]
		if owners.has(worker_id):
			owners.erase(worker_id)
		if owners.is_empty():
			_build_slot_owners.erase(building_id)
		else:
			_build_slot_owners[building_id] = owners


static func release_build_slots_for_building(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	_build_slot_owners.erase(building.get_instance_id())


static func get_claimed_build_slot(building: Building, worker: Worker) -> int:
	if not NodeSafety.is_alive_node(building) or not NodeSafety.is_alive_node(worker):
		return -1

	var building_id: int = building.get_instance_id()
	if not _build_slot_owners.has(building_id):
		return -1

	var owners: Dictionary = _build_slot_owners[building_id]
	var worker_id: int = worker.get_instance_id()
	if not owners.has(worker_id):
		return -1

	return int((owners[worker_id] as Dictionary).get("slot", -1))


static func count_build_slot_claims(building: Building) -> int:
	if not NodeSafety.is_alive_node(building):
		return 0

	purge_expired()
	var building_id: int = building.get_instance_id()
	if not _build_slot_owners.has(building_id):
		return 0

	return (_build_slot_owners[building_id] as Dictionary).size()


## Diagnostic for freed-building cleanup: claims keyed by instance id after free.
static func has_build_slot_owners_for_id(building_instance_id: int) -> bool:
	if building_instance_id == 0:
		return false
	if not _build_slot_owners.has(building_instance_id):
		return false
	return not (_build_slot_owners[building_instance_id] as Dictionary).is_empty()


static func _purge_stale_build_slots_for_building(building_id: int, now_msec: int) -> void:
	if not _build_slot_owners.has(building_id):
		return

	if not _is_alive_instance_id(building_id):
		_build_slot_owners.erase(building_id)
		return

	var owners: Dictionary = _build_slot_owners[building_id]
	for worker_id: Variant in owners.keys():
		var entry: Dictionary = owners[worker_id]
		if now_msec >= int(entry.get("expires_msec", 0)):
			owners.erase(worker_id)
			continue
		if not _is_alive_instance_id(int(worker_id)):
			owners.erase(worker_id)

	if owners.is_empty():
		_build_slot_owners.erase(building_id)
	else:
		_build_slot_owners[building_id] = owners


static func _is_alive_instance_id(instance_id: int) -> bool:
	if instance_id == 0:
		return false
	var obj: Object = instance_from_id(instance_id)
	return NodeSafety.is_alive_node(obj)


static func _aabb_overlaps(
	position_a: Vector3,
	size_a: Vector2,
	position_b: Vector3,
	size_b: Vector2,
	padding: float
) -> bool:
	var delta_x: float = absf(position_a.x - position_b.x)
	var delta_z: float = absf(position_a.z - position_b.z)
	var min_distance_x: float = (size_a.x + size_b.x) * 0.5 + padding
	var min_distance_z: float = (size_a.y + size_b.y) * 0.5 + padding
	return delta_x < min_distance_x and delta_z < min_distance_z
