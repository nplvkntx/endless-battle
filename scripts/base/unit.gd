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

const UNSTUCK_STUCK_MOVE_RATIO := 0.2
const UNSTUCK_SIDESTEP_DELAY := 0.35
const UNSTUCK_FLIP_DELAY := 0.6
const UNSTUCK_MAX_ATTEMPTS := 3
const UNSTUCK_SIDESTEP_BLEND := 1.0

var team_id: int = -1
var is_selected: bool = false
var has_move_target: bool = false

var _current_health: float = 0.0
var _max_health: float = 0.0

var _selection_indicator: MeshInstance3D
var _movement_target: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _unstuck_active: bool = false
var _unstuck_side: float = 1.0
var _unstuck_flip_timer: float = 0.0
var _unstuck_attempts: int = 0
var _unstuck_gave_up: bool = false


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
	_reset_unstuck_state()


func _physics_process(delta: float) -> void:
	if not has_move_target:
		_reset_unstuck_state()
		velocity = Vector3.ZERO
		return

	var offset: Vector3 = _movement_target - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= stopping_distance:
		_reset_unstuck_state()
		has_move_target = false
		velocity = Vector3.ZERO
		return

	var direction: Vector3 = offset.normalized()
	if _unstuck_active and not _unstuck_gave_up:
		direction = _get_unstuck_direction(direction)

	velocity = direction * move_speed
	velocity.y = 0.0

	var position_before: Vector3 = global_position
	move_and_slide()
	_update_unstuck(delta, position_before)


func _get_unstuck_direction(forward: Vector3) -> Vector3:
	var lateral: Vector3 = Vector3(-forward.z, 0.0, forward.x) * _unstuck_side
	var blended: Vector3 = forward + lateral * UNSTUCK_SIDESTEP_BLEND
	if blended.length_squared() < 0.001:
		return forward

	return blended.normalized()


func _update_unstuck(delta: float, position_before: Vector3) -> void:
	var moved: Vector3 = global_position - position_before
	moved.y = 0.0
	var moved_distance: float = moved.length()
	var expected_move: float = move_speed * delta * UNSTUCK_STUCK_MOVE_RATIO

	if moved_distance >= expected_move:
		_reset_unstuck_state()
		return

	if _unstuck_gave_up:
		return

	if _unstuck_active:
		_unstuck_flip_timer += delta
		if _unstuck_flip_timer < UNSTUCK_FLIP_DELAY:
			return

		_unstuck_flip_timer = 0.0
		if _unstuck_side > 0.0:
			_unstuck_side = -1.0
			return

		_unstuck_attempts += 1
		if _unstuck_attempts >= UNSTUCK_MAX_ATTEMPTS:
			_unstuck_gave_up = true
			_unstuck_active = false
			return

		_unstuck_side = 1.0
		return

	_stuck_time += delta
	if _stuck_time >= UNSTUCK_SIDESTEP_DELAY:
		_unstuck_active = true
		_unstuck_side = 1.0
		_unstuck_flip_timer = 0.0
		_stuck_time = 0.0


func _reset_unstuck_state() -> void:
	_stuck_time = 0.0
	_unstuck_active = false
	_unstuck_side = 1.0
	_unstuck_flip_timer = 0.0
	_unstuck_attempts = 0
	_unstuck_gave_up = false


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
