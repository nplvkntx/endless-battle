class_name GoldMine
extends GatherableResource

## Gold mine resource node with a finite gold supply.

@export var gold_amount: int = GatheringConfig.GOLD_MINE_STARTING_GOLD


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
