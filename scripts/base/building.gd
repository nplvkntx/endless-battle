class_name Building
extends StaticBody3D

## Base class for all structures (command center, farms, forges, etc.).
## Owns health, construction progress, team ownership, building state, and destruction.
## Stat values must come from an external Resource — never hardcoded in this script.

signal health_changed(current: float, maximum: float)
signal construction_progress_changed(progress: float)
signal building_state_changed(state: StringName)
signal destroyed(building: Building)

@export var building_data: Resource

var team_id: int = -1
var building_state: StringName = &""

var _current_health: float = 0.0
var _max_health: float = 0.0
var _construction_progress: float = 0.0


func _ready() -> void:
	collision_layer = PhysicsLayers.BUILDINGS
	collision_mask = PhysicsLayers.BUILDING_COLLISION_MASK
	_apply_building_data()


## Loads runtime state from building_data when the data pipeline is available.
func _apply_building_data() -> void:
	# TODO: Read stats and initial state from building_data Resource.
	pass


## Applies damage using values derived from building_data.
func take_damage(_amount: float) -> void:
	# TODO: Implement damage handling.
	pass


## Handles building destruction and notifies listeners through signals.
func destroy_building() -> void:
	destroyed.emit(self)
