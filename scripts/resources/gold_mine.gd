class_name GoldMine
extends GatherableResource

## Gold mine resource node with a finite gold supply and soft worker tracking.

@export var gold_amount: int = GatheringConfig.GOLD_MINE_STARTING_GOLD

## worker_instance_id -> reservation expiry msec
var _assigned_worker_ids: Dictionary = {}


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
		return

	_assigned_worker_ids.erase(worker_id)


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
		removed += 1

	return removed


func refresh_worker_reservation(worker: Object) -> void:
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0 or not _assigned_worker_ids.has(worker_id):
		return

	_assigned_worker_ids[worker_id] = (
		Time.get_ticks_msec() + GatheringConfig.GOLD_RESERVATION_TTL_MSEC
	)


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
