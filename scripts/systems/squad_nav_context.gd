class_name SquadNavContext
extends RefCounted

## Per-squad shared navigation state: one strategic route, stable slots, anchor progress.

var squad_id: int = 0
var command_generation: int = 0
var command_signature: String = ""
var equivalence_signature: String = ""
var command_type: StringName = &""
var mission: int = 0
var use_attack_move: bool = true
var strategic_destination: Vector3 = Vector3.ZERO
var route_waypoints: PackedVector3Array = PackedVector3Array()
var waypoint_index: int = 0
var formation_forward: Vector3 = Vector3(0.0, 0.0, 1.0)
var anchor_position: Vector3 = Vector3.ZERO
var member_ids: Array[int] = []
## unit_instance_id -> local formation offset (stable for command lifetime)
var slot_locals: Dictionary = {}
var route_created_msec: int = 0
var last_progress_msec: int = 0
var last_progress_position: Vector3 = Vector3.ZERO
var compressed_passage: bool = false
var spacing_scale: float = 1.0
var stagger_cursor: int = 0
var target_search_timer: float = 0.0
var shared_threat_target: Node3D = null
## unit_instance_id -> assigned threat (may equal shared target)
var member_threats: Dictionary = {}
var last_issued_slots: Dictionary = {}
var is_player_squad: bool = false
var formation_shape: int = int(FormationLayout.Shape.SQUARE)
var formation_size: int = 15


func member_count() -> int:
	return member_ids.size()


func contains_unit_id(unit_id: int) -> bool:
	return member_ids.has(unit_id)


func purge_dead_members() -> bool:
	var before: int = member_ids.size()
	var alive: Array[int] = []
	for unit_id: int in member_ids:
		var node: Object = instance_from_id(unit_id)
		if node != null and is_instance_valid(node) and node is Node3D:
			alive.append(unit_id)
	if alive.size() == before:
		return false
	member_ids = alive
	var valid: Dictionary = {}
	for unit_id: int in alive:
		valid[unit_id] = true
	for key: Variant in slot_locals.keys():
		if not valid.has(int(key)):
			slot_locals.erase(key)
	for key: Variant in member_threats.keys():
		if not valid.has(int(key)):
			member_threats.erase(key)
	for key: Variant in last_issued_slots.keys():
		if not valid.has(int(key)):
			last_issued_slots.erase(key)
	return true


func get_living_members() -> Array:
	var members: Array = []
	for unit_id: int in member_ids:
		var node: Object = instance_from_id(unit_id)
		if node != null and is_instance_valid(node):
			members.append(node)
	return members


func note_progress(position: Vector3) -> void:
	last_progress_msec = Time.get_ticks_msec()
	last_progress_position = position


func seconds_since_progress() -> float:
	return float(Time.get_ticks_msec() - last_progress_msec) / 1000.0


func is_route_finished() -> bool:
	if route_waypoints.is_empty():
		return _horizontal_distance(anchor_position, strategic_destination) <= 3.0
	return (
		waypoint_index >= route_waypoints.size() - 1
		and _horizontal_distance(anchor_position, strategic_destination) <= 3.5
	)


func get_slot_world_position(unit_id: int) -> Vector3:
	if not slot_locals.has(unit_id):
		return anchor_position
	var local: Vector3 = slot_locals[unit_id] as Vector3
	if compressed_passage:
		local *= spacing_scale
	return FormationLayout.world_from_local(local, anchor_position, formation_forward)


func recompute_anchor_median() -> void:
	var members: Array = get_living_members()
	if members.is_empty():
		return
	var xs: Array[float] = []
	var zs: Array[float] = []
	var y_sum: float = 0.0
	for unit: Variant in members:
		var pos: Vector3 = (unit as Node3D).global_position
		xs.append(pos.x)
		zs.append(pos.z)
		y_sum += pos.y
	xs.sort()
	zs.sort()
	var mid: int = xs.size() / 2
	anchor_position = Vector3(xs[mid], y_sum / float(members.size()), zs[mid])


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
