class_name WoodTree
extends GatherableResource

## Tree resource node with a finite wood supply and soft worker reservations.

@export var wood_amount: int = GatheringConfig.TREE_STARTING_WOOD

## worker_instance_id -> reservation expiry msec
var _assigned_worker_ids: Dictionary = {}


func _ready() -> void:
	super._ready()
	_activate_tree_variant()


func _activate_tree_variant() -> void:
	var visuals: Node3D = get_node_or_null("Visuals") as Node3D
	if visuals == null:
		return

	var variants: Array[Node] = []
	for child: Node in visuals.get_children():
		variants.append(child)

	if variants.is_empty():
		return

	var variant_index: int = absi(
		hash(str(global_position.snapped(Vector3(0.01, 0.01, 0.01))))
	) % variants.size()

	for index: int in variants.size():
		variants[index].visible = index == variant_index


func get_assigned_worker_count() -> int:
	purge_stale_reservations()
	return _assigned_worker_ids.size()


func register_assigned_worker(worker: Object = null) -> void:
	purge_stale_reservations()
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		return

	_assigned_worker_ids[worker_id] = (
		Time.get_ticks_msec() + GatheringConfig.WOOD_RESERVATION_TTL_MSEC
	)


func unregister_assigned_worker(worker: Object = null) -> void:
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		# Legacy no-arg unlock: clear all if caller cannot identify the worker.
		if worker == null:
			_assigned_worker_ids.clear()
		return

	_assigned_worker_ids.erase(worker_id)


func has_worker_reservation(worker: Object) -> bool:
	purge_stale_reservations()
	var worker_id: int = _resolve_worker_id(worker)
	if worker_id < 0:
		return false
	return _assigned_worker_ids.has(worker_id)


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
		Time.get_ticks_msec() + GatheringConfig.WOOD_RESERVATION_TTL_MSEC
	)


func _resolve_worker_id(worker: Object) -> int:
	if worker == null or not is_instance_valid(worker):
		return -1
	if worker is Node:
		return (worker as Node).get_instance_id()
	return -1


func get_resource_id() -> StringName:
	return &"wood"


func can_gather() -> bool:
	return wood_amount > 0


func gather(amount: int) -> int:
	if wood_amount <= 0:
		return 0

	var gathered: int = mini(amount, wood_amount)
	wood_amount -= gathered
	if wood_amount <= 0:
		depleted.emit()
	return gathered
