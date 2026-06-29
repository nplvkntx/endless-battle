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

var _current_health: float = 0.0
var _max_health: float = 0.0

var _selection_indicator: MeshInstance3D
var _move_target: Vector3 = Vector3.ZERO
var _is_moving: bool = false


func _ready() -> void:
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


## Commands the unit to move toward a world position on the XZ plane.
func move_to(world_position: Vector3) -> void:
	_move_target = Vector3(world_position.x, global_position.y, world_position.z)
	_is_moving = true


func _physics_process(_delta: float) -> void:
	if not _is_moving:
		velocity = Vector3.ZERO
		return

	var offset := _move_target - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= stopping_distance:
		_is_moving = false
		velocity = Vector3.ZERO
		return

	velocity = offset.normalized() * move_speed
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
