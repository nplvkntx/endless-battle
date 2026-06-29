class_name GatherableResource
extends StaticBody3D

## Base class for worker gather targets such as gold mines and trees.

signal depleted()


func get_resource_id() -> StringName:
	push_error("GatherableResource.get_resource_id must be overridden.")
	return &""


func get_gather_chunk_size() -> int:
	match get_resource_id():
		&"gold":
			return GatheringConfig.GATHER_CHUNK_GOLD
		&"wood":
			return GatheringConfig.GATHER_CHUNK_WOOD
		_:
			return 1


func gathers_until_carry_full() -> bool:
	return get_resource_id() == &"wood"


func can_gather() -> bool:
	return true


func gather(_amount: int) -> int:
	return get_gather_chunk_size()
