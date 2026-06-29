class_name Farm
extends Building

## Placeholder farm building used for early 3D scene testing.


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()
