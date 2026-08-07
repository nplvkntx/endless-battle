class_name SquadNavContext
extends RefCounted

## Per-squad shared navigation state: one strategic route, stable slots, anchor progress.
## Membership and threats are instance-ID based — never long-term owners of unit Objects.

var squad_id: int = 0
var command_generation: int = 0
var command_signature: String = ""
var equivalence_signature: String = ""
var command_type: StringName = &""
var mission: int = 0
var use_attack_move: bool = true
var strategic_destination: Vector3 = Vector3.ZERO
var requested_destination: Vector3 = Vector3.ZERO
var route_waypoints: PackedVector3Array = PackedVector3Array()
var waypoint_index: int = 0
var route_valid: bool = false
var formation_forward: Vector3 = Vector3(0.0, 0.0, 1.0)
var anchor_position: Vector3 = Vector3.ZERO
var member_ids: Array[int] = []
## unit_instance_id -> local offset (stable for command lifetime; simple grid or formation)
var slot_locals: Dictionary = {}
## unit_instance_id -> frozen world arrival (player squads only; never moves with anchor)
var final_arrival_slots: Dictionary = {}
var arrival_slots_frozen: bool = false
var route_created_msec: int = 0
var last_progress_msec: int = 0
var last_progress_position: Vector3 = Vector3.ZERO
var last_route_refresh_msec: int = 0
var compressed_passage: bool = false
var spacing_scale: float = 1.0
var stagger_cursor: int = 0
var target_search_timer: float = 0.0
## Instance ID of shared attack-move threat (0 = none). Never store a typed Node3D.
var shared_threat_id: int = 0
## unit_instance_id -> threat_instance_id
var member_threats: Dictionary = {}
var last_issued_slots: Dictionary = {}
## Members that exhausted local recovery and need a shared-route refresh.
var stalled_member_ids: Dictionary = {}
var is_player_squad: bool = false
## True when slots came from a persistent FormationGroup (player formation).
var uses_formation_layout: bool = false
var formation_shape: int = int(FormationLayout.Shape.SQUARE)
var formation_size: int = 15


func member_count() -> int:
	return member_ids.size()


func contains_unit_id(unit_id: int) -> bool:
	return member_ids.has(unit_id)


## Resolve a living Node3D from an instance ID. Returns null when missing/freed/queued.
static func resolve_living_node3d(instance_id: int) -> Node3D:
	if instance_id == 0:
		return null
	var value: Variant = instance_from_id(instance_id)
	if value == null or not is_instance_valid(value):
		return null
	if not value is Node3D:
		return null
	var node: Node3D = value as Node3D
	if node.is_queued_for_deletion():
		return null
	return node


func get_shared_threat_target() -> Node3D:
	var target: Node3D = resolve_living_node3d(shared_threat_id)
	if target == null:
		shared_threat_id = 0
	return target


func set_shared_threat_target(target: Variant) -> void:
	if target == null or not is_instance_valid(target) or not target is Node3D:
		shared_threat_id = 0
		return
	var node: Node3D = target as Node3D
	if node.is_queued_for_deletion():
		shared_threat_id = 0
		return
	shared_threat_id = node.get_instance_id()


func get_member_threat(unit_id: int) -> Node3D:
	if not member_threats.has(unit_id):
		return null
	var threat_id: int = int(member_threats[unit_id])
	var target: Node3D = resolve_living_node3d(threat_id)
	if target == null:
		member_threats.erase(unit_id)
	return target


func set_member_threat(unit_id: int, threat: Variant) -> void:
	if threat == null or not is_instance_valid(threat) or not threat is Node3D:
		member_threats.erase(unit_id)
		return
	var node: Node3D = threat as Node3D
	if node.is_queued_for_deletion():
		member_threats.erase(unit_id)
		return
	member_threats[unit_id] = node.get_instance_id()


func clear_unit_state(unit_id: int) -> void:
	member_ids.erase(unit_id)
	slot_locals.erase(unit_id)
	final_arrival_slots.erase(unit_id)
	member_threats.erase(unit_id)
	last_issued_slots.erase(unit_id)
	stalled_member_ids.erase(unit_id)
	if shared_threat_id == unit_id:
		shared_threat_id = 0


func purge_dead_members() -> bool:
	var before: int = member_ids.size()
	var alive: Array[int] = []
	var removed_ids: Array[int] = []
	for unit_id: int in member_ids:
		if resolve_living_node3d(unit_id) != null:
			alive.append(unit_id)
		else:
			removed_ids.append(unit_id)

	var threat_cleared: bool = false
	if shared_threat_id != 0 and resolve_living_node3d(shared_threat_id) == null:
		shared_threat_id = 0
		threat_cleared = true

	var threat_keys: Array = member_threats.keys()
	for key: Variant in threat_keys:
		var threat_id: int = int(member_threats[key])
		if resolve_living_node3d(threat_id) == null:
			member_threats.erase(key)
			threat_cleared = true

	if alive.size() == before and removed_ids.is_empty() and not threat_cleared:
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
	for key: Variant in stalled_member_ids.keys():
		if not valid.has(int(key)):
			stalled_member_ids.erase(key)
	for key: Variant in final_arrival_slots.keys():
		if not valid.has(int(key)):
			final_arrival_slots.erase(key)
	return true


## Resolves valid Node3D members from IDs. Never returns freed Object Variants.
## Dead IDs are skipped here; call purge_dead_members() for ownership cleanup.
func get_living_members() -> Array:
	var members: Array = []
	for unit_id: int in member_ids:
		var node: Node3D = resolve_living_node3d(unit_id)
		if node == null:
			continue
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
	## Player squads chase frozen arrival slots, never a moving virtual anchor.
	if is_player_squad and arrival_slots_frozen and final_arrival_slots.has(unit_id):
		return final_arrival_slots[unit_id] as Vector3
	if not slot_locals.has(unit_id):
		return anchor_position
	var local: Vector3 = slot_locals[unit_id] as Vector3
	if compressed_passage:
		local *= spacing_scale
	return FormationLayout.world_from_local(local, anchor_position, formation_forward)


func get_final_arrival_slot(unit_id: int) -> Vector3:
	if final_arrival_slots.has(unit_id):
		return final_arrival_slots[unit_id] as Vector3
	return get_slot_world_position(unit_id)


func recompute_anchor_median() -> void:
	var members: Array = get_living_members()
	if members.is_empty():
		return
	var xs: Array[float] = []
	var zs: Array[float] = []
	var y_sum: float = 0.0
	for unit: Variant in members:
		if unit == null or not is_instance_valid(unit) or not unit is Node3D:
			continue
		var pos: Vector3 = (unit as Node3D).global_position
		xs.append(pos.x)
		zs.append(pos.z)
		y_sum += pos.y
	if xs.is_empty():
		return
	xs.sort()
	zs.sort()
	var mid: int = xs.size() / 2
	anchor_position = Vector3(xs[mid], y_sum / float(xs.size()), zs[mid])


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
