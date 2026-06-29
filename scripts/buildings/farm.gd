class_name Farm
extends Building

## Placeholder farm building used for early 3D scene testing.

const FOOD_CAP_BONUS: int = 8


func complete_construction() -> void:
	if building_state == STATE_COMPLETED:
		return

	super.complete_construction()
	ResourceManager.add_food_max(FOOD_CAP_BONUS)


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()
