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
const UNSTUCK_DETOUR_START_DELAY := 0.25
const UNSTUCK_DETOUR_COMMIT_TIME := 0.75
const UNSTUCK_DETOUR_MAX_TIME := 2.0
const UNSTUCK_MAX_SIDE_FLIPS := 1
const UNSTUCK_LATERAL_FORWARD_BLEND := 0.12
const UNSTUCK_PROBE_DISTANCE := 2.5
const UNSTUCK_PATH_CHECK_DISTANCE := 3.0

var team_id: int = -1
var is_selected: bool = false
var has_move_target: bool = false

var _current_health: float = 0.0
var _max_health: float = 0.0

var _selection_indicator: MeshInstance3D
var _movement_target: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _detour_active: bool = false
var _detour_side: float = 1.0
var _detour_time: float = 0.0
var _detour_flips: int = 0
var _detour_gave_up: bool = false
var _distance_at_detour_start: float = 0.0


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = PhysicsLayers.UNITS
	collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	_selection_indicator = get_node_or_null("SelectionIndicator") as MeshInstance3D
	if _selection_indicator:
		_selection_indicator.visible = false
	_apply_unit_data()
	call_deferred("apply_team_visuals")


## Applies a team-colored accent ring and subtle body tint from team_id or faction groups.
func apply_team_visuals() -> void:
	TeamVisuals.apply_to_entity(self, team_id)


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
	if _detour_active and not _detour_gave_up:
		direction = _get_detour_direction(direction)

	velocity = direction * move_speed
	velocity.y = 0.0

	var position_before: Vector3 = global_position
	move_and_slide()
	_update_unstuck(delta, position_before, direction, distance)


func _get_detour_direction(forward: Vector3) -> Vector3:
	var lateral: Vector3 = Vector3(-forward.z, 0.0, forward.x).normalized() * _detour_side
	var blended: Vector3 = lateral + forward * UNSTUCK_LATERAL_FORWARD_BLEND
	if blended.length_squared() < 0.001:
		return lateral

	return blended.normalized()


func _begin_detour(forward: Vector3, distance: float) -> void:
	_detour_active = true
	_detour_side = _choose_detour_side(forward)
	_detour_time = 0.0
	_detour_flips = 0
	_distance_at_detour_start = distance
	_stuck_time = 0.0


func _choose_detour_side(forward: Vector3) -> float:
	var lateral_right: Vector3 = Vector3(-forward.z, 0.0, forward.x).normalized()
	var lateral_left: Vector3 = -lateral_right

	var right_clearance: float = _probe_clearance(lateral_right)
	var left_clearance: float = _probe_clearance(lateral_left)
	if absf(right_clearance - left_clearance) > 0.15:
		if right_clearance >= left_clearance:
			return 1.0
		return -1.0

	if get_slide_collision_count() > 0:
		var collision_normal: Vector3 = get_slide_collision(0).get_normal()
		collision_normal.y = 0.0
		if collision_normal.length_squared() > 0.001:
			collision_normal = collision_normal.normalized()
			if lateral_right.dot(collision_normal) >= lateral_left.dot(collision_normal):
				return -1.0
			return 1.0

	return 1.0


func _probe_clearance(direction: Vector3) -> float:
	var world: World3D = get_world_3d()
	if world == null:
		return 0.0

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var ray_origin: Vector3 = global_position
	var ray_end: Vector3 = ray_origin + direction * UNSTUCK_PROBE_DISTANCE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end
	)
	query.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	query.exclude = [get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return UNSTUCK_PROBE_DISTANCE

	return ray_origin.distance_to(result.position)


func _is_direct_path_clear(forward: Vector3, distance: float) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return false

	var check_distance: float = minf(distance, UNSTUCK_PATH_CHECK_DISTANCE)
	if check_distance <= stopping_distance:
		return true

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var ray_origin: Vector3 = global_position
	var ray_end: Vector3 = ray_origin + forward * check_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end
	)
	query.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	query.exclude = [get_rid()]

	return space_state.intersect_ray(query).is_empty()


func _update_unstuck(
	delta: float, position_before: Vector3, forward: Vector3, distance: float
) -> void:
	var moved: Vector3 = global_position - position_before
	moved.y = 0.0
	var moved_distance: float = moved.length()
	var expected_move: float = move_speed * delta * UNSTUCK_STUCK_MOVE_RATIO
	var hit_obstacle: bool = get_slide_collision_count() > 0
	var making_progress: bool = moved_distance >= expected_move
	var moving_toward_target: bool = making_progress and moved.dot(forward) > 0.0

	if _detour_active:
		_detour_time += delta

		if _is_direct_path_clear(forward, distance) and _detour_time >= UNSTUCK_DETOUR_COMMIT_TIME * 0.5:
			_reset_unstuck_state()
			return

		if moving_toward_target and distance < _distance_at_detour_start - stopping_distance:
			_reset_unstuck_state()
			return

		if _detour_time < UNSTUCK_DETOUR_COMMIT_TIME:
			return

		if _detour_time >= UNSTUCK_DETOUR_MAX_TIME:
			if _detour_flips < UNSTUCK_MAX_SIDE_FLIPS:
				_detour_side *= -1.0
				_detour_flips += 1
				_detour_time = 0.0
				_distance_at_detour_start = distance
			else:
				_detour_gave_up = true
				_detour_active = false

		return

	if _detour_gave_up:
		if making_progress:
			_reset_unstuck_state()
		return

	if moving_toward_target or _is_direct_path_clear(forward, distance):
		_stuck_time = 0.0
		return

	if not hit_obstacle and _stuck_time <= 0.0:
		return

	_stuck_time += delta
	if _stuck_time >= UNSTUCK_DETOUR_START_DELAY:
		_begin_detour(forward, distance)


func _reset_unstuck_state() -> void:
	_stuck_time = 0.0
	_detour_active = false
	_detour_side = 1.0
	_detour_time = 0.0
	_detour_flips = 0
	_detour_gave_up = false
	_distance_at_detour_start = 0.0


## Loads runtime state from unit_data when the data pipeline is available.
func _apply_unit_data() -> void:
	# TODO: Read stats from unit_data Resource.
	pass


## Applies damage using values derived from unit_data.
func take_damage(_amount: float, _attacker = null) -> void:
	# TODO: Implement damage handling.
	pass


## Handles unit death and notifies listeners through signals.
func die() -> void:
	died.emit(self)
