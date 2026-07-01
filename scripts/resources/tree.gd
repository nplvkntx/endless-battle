class_name WoodTree
extends GatherableResource

## Tree resource node with a finite wood supply.

@export var wood_amount: int = GatheringConfig.TREE_STARTING_WOOD

var _assigned_worker_count: int = 0


func get_assigned_worker_count() -> int:
	return _assigned_worker_count


func register_assigned_worker() -> void:
	_assigned_worker_count += 1


func unregister_assigned_worker() -> void:
	_assigned_worker_count = maxi(0, _assigned_worker_count - 1)


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
