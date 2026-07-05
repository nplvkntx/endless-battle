class_name EnemyUnitMission
extends RefCounted

## Per-unit mission ownership for enemy AI. Prevents managers from fighting over the same units.

enum Mission {
	IDLE,
	ECONOMY,
	BUILD,
	CREEP,
	REGROUP,
	ATTACK,
	DEFEND,
	RETREAT,
}

const COMMITMENT_SECONDS: float = 3.0
const BUILD_COMMITMENT_SECONDS: float = 12.0
const ORDER_REISSUE_MIN_SECONDS: float = 2.5
const ORDER_MOVE_THRESHOLD: float = 4.0

static var _unit_missions: Dictionary = {}
static var _mission_locked_until_msec: Dictionary = {}
static var _last_order_msec: Dictionary = {}
static var _last_order_destination: Dictionary = {}
static var _last_order_mission: Dictionary = {}
static var _main_army_mission: Mission = Mission.REGROUP
static var _main_army_mission_reason: String = "initial regroup"


static func get_main_army_mission() -> Mission:
	return _main_army_mission


static func get_main_army_mission_reason() -> String:
	return _main_army_mission_reason


static func set_main_army_mission(mission: Mission, reason: String = "") -> bool:
	if mission == _main_army_mission:
		return false

	_main_army_mission = mission
	_main_army_mission_reason = reason
	return true


static func get_unit_mission(unit: Node) -> Mission:
	if not NodeSafety.is_alive_node(unit):
		return Mission.IDLE

	return _unit_missions.get(unit.get_instance_id(), Mission.IDLE) as Mission


static func get_mission_priority(mission: Mission) -> int:
	match mission:
		Mission.RETREAT:
			return 1
		Mission.DEFEND:
			return 2
		Mission.ATTACK:
			return 3
		Mission.CREEP:
			return 4
		Mission.REGROUP:
			return 6
		Mission.BUILD, Mission.ECONOMY:
			return 7
		Mission.IDLE:
			return 8
		_:
			return 9


static func can_override_mission(unit: Node, new_mission: Mission) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	var unit_id: int = unit.get_instance_id()
	var current: Mission = get_unit_mission(unit)
	if current == new_mission:
		return not _is_mission_locked(unit_id)

	var current_priority: int = get_mission_priority(current)
	var new_priority: int = get_mission_priority(new_mission)
	if new_priority < current_priority:
		return true

	if new_priority > current_priority:
		return false

	return not _is_mission_locked(unit_id)


static func try_set_mission(
	unit: Node,
	mission: Mission,
	lock_seconds: float = COMMITMENT_SECONDS
) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	if not can_override_mission(unit, mission):
		return false

	var unit_id: int = unit.get_instance_id()
	_unit_missions[unit_id] = mission
	if lock_seconds > 0.0:
		_mission_locked_until_msec[unit_id] = (
			Time.get_ticks_msec() + int(lock_seconds * 1000.0)
		)
	else:
		_mission_locked_until_msec.erase(unit_id)

	return true


static func clear_unit_mission(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	var unit_id: int = unit.get_instance_id()
	_erase_unit_mission_records(unit_id)


static func purge_stale_entries() -> int:
	var removed: int = 0
	removed += NodeSafety.purge_stale_instance_id_dict(_unit_missions)
	removed += NodeSafety.purge_stale_instance_id_dict(_mission_locked_until_msec)
	removed += NodeSafety.purge_stale_instance_id_dict(_last_order_msec)
	removed += NodeSafety.purge_stale_instance_id_dict(_last_order_destination)
	removed += NodeSafety.purge_stale_instance_id_dict(_last_order_mission)
	return removed


static func _erase_unit_mission_records(unit_id: int) -> void:
	_unit_missions.erase(unit_id)
	_mission_locked_until_msec.erase(unit_id)
	_last_order_msec.erase(unit_id)
	_last_order_destination.erase(unit_id)
	_last_order_mission.erase(unit_id)


static func filter_commandable_units(units: Array, mission: Mission) -> Array:
	units = NodeSafety.clean_node_array(units)
	var result: Array = []
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if can_override_mission(unit as Node, mission):
			result.append(unit)

	return result


static func allows_combat_micro(unit: Node) -> bool:
	if not CombatTargetValidation.is_enemy_faction(unit):
		return true

	match get_unit_mission(unit):
		Mission.RETREAT, Mission.REGROUP, Mission.ECONOMY, Mission.BUILD:
			return false
		_:
			return true


static func should_reissue_move_order(
	unit: Node,
	destination: Vector3,
	mission: Mission
) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	var unit_id: int = unit.get_instance_id()
	if not _last_order_msec.has(unit_id):
		return true

	if _last_order_mission.get(unit_id, Mission.IDLE) != mission:
		return true

	var elapsed_msec: int = Time.get_ticks_msec() - int(_last_order_msec[unit_id])
	if elapsed_msec >= int(ORDER_REISSUE_MIN_SECONDS * 1000.0):
		return true

	var last_destination: Vector3 = _last_order_destination.get(unit_id, Vector3.ZERO)
	return EnemyArmyCommand.horizontal_distance(last_destination, destination) > ORDER_MOVE_THRESHOLD


static func record_move_order(unit: Node, destination: Vector3, mission: Mission) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	var unit_id: int = unit.get_instance_id()
	_last_order_msec[unit_id] = Time.get_ticks_msec()
	_last_order_destination[unit_id] = destination
	_last_order_mission[unit_id] = mission


static func assign_missions_to_units(
	units: Array,
	mission: Mission,
	lock_seconds: float = COMMITMENT_SECONDS
) -> void:
	units = NodeSafety.clean_node_array(units)
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		try_set_mission(unit as Node, mission, lock_seconds)


static func mission_to_label(mission: Mission) -> String:
	match mission:
		Mission.ECONOMY:
			return "ECONOMY"
		Mission.BUILD:
			return "BUILD"
		Mission.CREEP:
			return "CREEP"
		Mission.REGROUP:
			return "REGROUP"
		Mission.ATTACK:
			return "ATTACK"
		Mission.DEFEND:
			return "DEFEND"
		Mission.RETREAT:
			return "RETREAT"
		_:
			return "IDLE"


static func _is_mission_locked(unit_id: int) -> bool:
	if not _mission_locked_until_msec.has(unit_id):
		return false

	return Time.get_ticks_msec() < int(_mission_locked_until_msec[unit_id])
