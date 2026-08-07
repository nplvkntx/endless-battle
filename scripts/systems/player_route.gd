class_name PlayerRoute
extends RefCounted

## Immutable validated shared route for one player Move / Attack-Move / Patrol generation.
## Membership uses instance IDs only — never long-lived Unit Object refs.

var route_id: int = 0
var command_generation: int = 0
var order_kind: StringName = &"move"
var use_attack_move: bool = false
var clicked_destination: Vector3 = Vector3.ZERO
var accepted_destination: Vector3 = Vector3.ZERO
## Validated corridor waypoints (immutable after create).
var waypoints: PackedVector3Array = PackedVector3Array()
## Raw NavigationServer polyline for path-debug comparison.
var raw_waypoints: PackedVector3Array = PackedVector3Array()
var route_clearance_radius: float = 0.0
var route_valid: bool = false
var created_msec: int = 0
## unit_instance_id -> frozen final world arrival (generated once).
var final_destinations: Dictionary = {}
## Living member instance IDs for this command generation.
var member_ids: Array[int] = []
## unit_instance_id -> personal waypoint index along `waypoints`.
var waypoint_index_by_unit: Dictionary = {}
## unit_instance_id -> farthest waypoint index successfully passed (for known-good rejoin).
var max_passed_waypoint_by_unit: Dictionary = {}


func member_count() -> int:
	return member_ids.size()


func contains_unit_id(unit_id: int) -> bool:
	return member_ids.has(unit_id)


func clear_unit_state(unit_id: int) -> void:
	member_ids.erase(unit_id)
	final_destinations.erase(unit_id)
	waypoint_index_by_unit.erase(unit_id)
	max_passed_waypoint_by_unit.erase(unit_id)


func get_final_destination(unit_id: int) -> Vector3:
	if final_destinations.has(unit_id):
		return final_destinations[unit_id] as Vector3
	return accepted_destination


func get_waypoint_index(unit_id: int) -> int:
	if waypoint_index_by_unit.has(unit_id):
		return int(waypoint_index_by_unit[unit_id])
	return 0


func set_waypoint_index(unit_id: int, index: int) -> void:
	if waypoints.is_empty():
		waypoint_index_by_unit[unit_id] = 0
		return
	var clamped: int = clampi(index, 0, waypoints.size() - 1)
	waypoint_index_by_unit[unit_id] = clamped
	var prev_passed: int = int(max_passed_waypoint_by_unit.get(unit_id, -1))
	if clamped > prev_passed:
		max_passed_waypoint_by_unit[unit_id] = clamped


func note_passed_waypoint(unit_id: int, index: int) -> void:
	var prev_passed: int = int(max_passed_waypoint_by_unit.get(unit_id, -1))
	if index > prev_passed:
		max_passed_waypoint_by_unit[unit_id] = index


## Highest waypoint index any living squadmate has passed (excluding `exclude_unit_id`).
func get_known_good_waypoint_index(exclude_unit_id: int = 0) -> int:
	var best: int = -1
	for unit_id: int in member_ids:
		if unit_id == exclude_unit_id:
			continue
		var passed: int = int(max_passed_waypoint_by_unit.get(unit_id, -1))
		if passed > best:
			best = passed
	return best


static func resolve_living_unit(instance_id: int) -> Unit:
	if instance_id == 0:
		return null
	var value: Variant = instance_from_id(instance_id)
	if value == null or not is_instance_valid(value):
		return null
	if not value is Unit:
		return null
	var unit: Unit = value as Unit
	if unit.is_queued_for_deletion():
		return null
	return unit


func purge_dead_members() -> bool:
	var before: int = member_ids.size()
	var alive: Array[int] = []
	for unit_id: int in member_ids:
		if resolve_living_unit(unit_id) != null:
			alive.append(unit_id)
		else:
			final_destinations.erase(unit_id)
			waypoint_index_by_unit.erase(unit_id)
			max_passed_waypoint_by_unit.erase(unit_id)
	member_ids = alive
	return member_ids.size() != before


func get_living_members() -> Array[Unit]:
	var members: Array[Unit] = []
	for unit_id: int in member_ids:
		var unit: Unit = resolve_living_unit(unit_id)
		if unit != null:
			members.append(unit)
	return members
