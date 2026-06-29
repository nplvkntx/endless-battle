class_name Unit
extends CharacterBody3D

## Base class for all movable units (workers, soldiers, archers, etc.).
## Owns health, movement hooks, selection state, team ownership, and death flow.
## Stat values must come from an external Resource — never hardcoded in this script.

signal health_changed(current: float, maximum: float)
signal selected_changed(is_selected: bool)
signal died(unit: Unit)

@export var unit_data: Resource
@export var move_speed: float = 5.0
@export var stopping_distance: float = 0.25

var team_id: int = -1
var is_selected: bool = false
var has_move_target: bool = false

var _current_health: float = 0.0
var _max_health: float = 0.0

var _selection_indicator: MeshInstance3D
var _movement_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = PhysicsLayers.UNITS
	collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	_selection_indicator = get_node_or_null("SelectionIndicator") as MeshInstance3D
	if _selection_indicator:
		_selection_indicator.visible = false
	_apply_unit_data()


## Updates selection state and toggles the optional SelectionIndicator child.
func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return

	is_selected = selected
	if _selection_indicator:
		_selection_indicator.visible = selected
	selected_changed.emit(is_selected)


## Sets a single move target. Called only when a move command is issued.
func set_movement_target(target: Vector3) -> void:
	_movement_target = Vector3(target.x, global_position.y, target.z)
	has_move_target = true


func _physics_process(_delta: float) -> void:
	if not has_move_target:
		velocity = Vector3.ZERO
		return

	var offset: Vector3 = _movement_target - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= stopping_distance:
		has_move_target = false
		velocity = Vector3.ZERO
		return

	var direction: Vector3 = offset.normalized()
	velocity = direction * move_speed
	velocity.y = 0.0
	move_and_slide()


## Loads runtime state from unit_data when the data pipeline is available.
func _apply_unit_data() -> void:
	# TODO: Read stats from unit_data Resource.
	pass


## Applies damage using values derived from unit_data.
func take_damage(_amount: float) -> void:
	# TODO: Implement damage handling.
	pass


## Handles unit death and notifies listeners through signals.
func die() -> void:
	died.emit(self)
