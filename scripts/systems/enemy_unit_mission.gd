class_name EnemyUnitMission
extends RefCounted

## Per-unit mission ownership for enemy AI. Prevents managers from fighting over the same units.
## Military missions: IDLE, RALLY, CREEP, ATTACK, DEFEND, RETREAT, SHOP.
## Worker-only: ECONOMY, BUILD.

enum Mission {
	IDLE,
	ECONOMY,
	BUILD,
	RALLY,
	SHOP,
	CREEP,
	ATTACK,
	RETREAT,
	DEFEND,
}

const COMMITMENT_SECONDS: float = 3.0
const BUILD_COMMITMENT_SECONDS: float = 12.0
const SHOP_COMMITMENT_SECONDS: float = 8.0
const ORDER_REISSUE_MIN_SECONDS: float = 1.0
const ORDER_FORMATION_REISSUE_SECONDS: float = 1.4
## DEFEND / RETREAT still urgent, but not so tight that large armies thrash orders.
const ORDER_URGENT_REISSUE_SECONDS: float = 1.0
const ORDER_STUCK_REFRESH_SECONDS: float = 1.75
const ORDER_MOVE_THRESHOLD: float = 2.0
const ORDER_NEAR_DESTINATION_SKIP: float = 1.5
const ORDER_UNIT_DEST_TOLERANCE: float = 2.0
const ORDER_STAGGER_OFFSET_SECONDS: float = 0.12

## Lower number = higher priority. DEFEND > RETREAT > ATTACK > CREEP > RALLY > IDLE.
const PRIORITY_DEFEND: int = 1
const PRIORITY_RETREAT: int = 2
const PRIORITY_ATTACK: int = 3
const PRIORITY_CREEP: int = 4
const PRIORITY_RALLY: int = 5
const PRIORITY_SHOP: int = 5
const PRIORITY_WORKER: int = 6
const PRIORITY_IDLE: int = 7

static var _unit_missions: Dictionary = {}
static var _mission_locked_until_msec: Dictionary = {}
static var _last_order_msec: Dictionary = {}
static var _last_order_destination: Dictionary = {}
static var _last_order_mission: Dictionary = {}
static var _main_army_mission: Mission = Mission.RALLY
static var _main_army_mission_reason: String = "initial rally"


static func get_main_army_mission() -> Mission:
	return _main_army_mission


static func get_main_army_mission_reason() -> String:
	return _main_army_mission_reason


static func set_main_army_mission(mission: Mission, reason: String = "") -> bool:
	if mission == _main_army_mission:
		return false

	var previous: Mission = _main_army_mission
	_main_army_mission = mission
	_main_army_mission_reason = reason
	EnemyAIDebug.log_mission_change(previous, mission, reason)
	return true


static func get_unit_mission(unit) -> Mission:
	if not NodeSafety.is_alive_node(unit):
		return Mission.IDLE

	return _unit_missions.get(unit.get_instance_id(), Mission.IDLE) as Mission


static func get_mission_priority(mission: Mission) -> int:
	match mission:
		Mission.DEFEND:
			return PRIORITY_DEFEND
		Mission.RETREAT:
			return PRIORITY_RETREAT
		Mission.ATTACK:
			return PRIORITY_ATTACK
		Mission.CREEP:
			return PRIORITY_CREEP
		Mission.RALLY:
			return PRIORITY_RALLY
		Mission.SHOP:
			return PRIORITY_SHOP
		Mission.BUILD, Mission.ECONOMY:
			return PRIORITY_WORKER
		Mission.IDLE:
			return PRIORITY_IDLE
		_:
			return PRIORITY_IDLE + 1


static func is_military_mission(mission: Mission) -> bool:
	return mission in [
		Mission.IDLE,
		Mission.RALLY,
		Mission.CREEP,
		Mission.ATTACK,
		Mission.DEFEND,
		Mission.RETREAT,
		Mission.SHOP,
	]


static func can_override_mission(unit, new_mission: Mission) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	if EnemyArmyCommand.is_attack_wave_active():
		if new_mission in [Mission.CREEP, Mission.ECONOMY, Mission.BUILD, Mission.IDLE, Mission.SHOP]:
			return false

	if (
		EnemyArmyCommand.is_attack_wave_controlling_hero()
		and unit is Hero
		and new_mission in [Mission.CREEP, Mission.ECONOMY, Mission.BUILD, Mission.IDLE, Mission.SHOP]
	):
		return false

	var unit_id: int = unit.get_instance_id()
	var current: Mission = get_unit_mission(unit)
	if current == new_mission:
		return not _is_mission_locked(unit_id)

	## Attack must never interrupt defend or retreat.
	if new_mission == Mission.ATTACK and current in [Mission.DEFEND, Mission.RETREAT]:
		return false

	## Creep must never interrupt defend, retreat, or attack.
	if new_mission == Mission.CREEP and current in [Mission.DEFEND, Mission.RETREAT, Mission.ATTACK]:
		return false

	var current_priority: int = get_mission_priority(current)
	var new_priority: int = get_mission_priority(new_mission)
	if new_priority < current_priority:
		return true

	if new_priority > current_priority:
		return false

	return not _is_mission_locked(unit_id)


## True when this mission system currently owns the unit, or can claim it.
static func owns_order_authority(unit, mission: Mission) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	var current: Mission = get_unit_mission(unit)
	if current == mission:
		return true

	return can_override_mission(unit, mission)


static func try_set_mission(
	unit,
	mission: Mission,
	lock_seconds: float = COMMITMENT_SECONDS
) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	if not can_override_mission(unit, mission):
		return false

	var unit_id: int = unit.get_instance_id()
	var previous: Mission = get_unit_mission(unit)
	_unit_missions[unit_id] = mission
	if lock_seconds > 0.0:
		_mission_locked_until_msec[unit_id] = (
			Time.get_ticks_msec() + int(lock_seconds * 1000.0)
		)
	else:
		_mission_locked_until_msec.erase(unit_id)

	if previous != mission and unit is Hero:
		EnemyAIDebug.log_hero_mission(previous, mission)

	return true


static func clear_unit_mission(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	var unit_id: int = unit.get_instance_id()
	_erase_unit_mission_records(unit_id)


static func reset_match_state() -> void:
	_unit_missions.clear()
	_mission_locked_until_msec.clear()
	_last_order_msec.clear()
	_last_order_destination.clear()
	_last_order_mission.clear()
	_main_army_mission = Mission.RALLY
	_main_army_mission_reason = "initial rally"


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

		if owns_order_authority(unit, mission):
			result.append(unit)

	return result


## Claim mission ownership for units that can be overridden, then return those claimed.
static func claim_units_for_mission(
	units: Array,
	mission: Mission,
	lock_seconds: float = COMMITMENT_SECONDS
) -> Array:
	units = NodeSafety.clean_node_array(units)
	var claimed: Array = []
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		var current: Mission = get_unit_mission(unit)
		if current == mission:
			claimed.append(unit)
			continue

		if try_set_mission(unit, mission, lock_seconds):
			claimed.append(unit)

	return claimed


static func allows_combat_micro(unit) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	if not CombatTargetValidation.is_enemy_faction(unit):
		return true

	match get_unit_mission(unit):
		Mission.ATTACK, Mission.DEFEND, Mission.CREEP:
			return true
		_:
			return false


static func should_reissue_move_order(
	unit,
	destination: Vector3,
	mission: Mission
) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	if not owns_order_authority(unit, mission):
		return false

	var unit_id: int = unit.get_instance_id()
	if not _last_order_msec.has(unit_id):
		return true

	if _last_order_mission.get(unit_id, Mission.IDLE) != mission:
		return true

	var unit_node: Node3D = unit as Node3D
	var is_stuck: bool = false
	if unit_node != null and unit_node.has_method("is_confirmed_stuck"):
		is_stuck = VariantUtils.to_bool(unit_node.call("is_confirmed_stuck"))

	if unit_node != null:
		var distance_to_destination: float = EnemyArmyCommand.horizontal_distance(
			unit_node.global_position,
			destination
		)
		if distance_to_destination <= ORDER_NEAR_DESTINATION_SKIP and not is_stuck:
			return false

		if unit_node is Unit:
			var unit_ref: Unit = unit_node as Unit
			if unit_ref.has_move_target:
				var current_dest_delta: float = EnemyArmyCommand.horizontal_distance(
					unit_ref.get_movement_destination(),
					destination
				)
				if current_dest_delta <= ORDER_UNIT_DEST_TOLERANCE and not is_stuck:
					return false

	var elapsed_sec: float = float(Time.get_ticks_msec() - int(_last_order_msec[unit_id])) / 1000.0
	var stagger_offset: float = float(abs(unit_id) % 7) * ORDER_STAGGER_OFFSET_SECONDS
	var last_destination: Vector3 = _last_order_destination.get(unit_id, Vector3.ZERO)
	var destination_delta: float = EnemyArmyCommand.horizontal_distance(
		last_destination,
		destination
	)

	var is_urgent: bool = mission in [Mission.RETREAT, Mission.DEFEND]
	if destination_delta <= ORDER_MOVE_THRESHOLD:
		# Same/nearby destination: only reissue for confirmed stuck recovery.
		if not is_stuck:
			return false
		return elapsed_sec >= (ORDER_STUCK_REFRESH_SECONDS + stagger_offset)

	var min_cooldown: float = ORDER_REISSUE_MIN_SECONDS
	if is_urgent:
		min_cooldown = ORDER_URGENT_REISSUE_SECONDS
	elif mission in [Mission.RALLY, Mission.ATTACK, Mission.CREEP]:
		min_cooldown = ORDER_FORMATION_REISSUE_SECONDS

	return elapsed_sec >= (min_cooldown + stagger_offset)


static func record_move_order(unit, destination: Vector3, mission: Mission) -> void:
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
	claim_units_for_mission(units, mission, lock_seconds)


## Keep the enemy hero on the main army mission unless shopping or unavailable.
static func sync_hero_to_main_army(hero, force_leave_shop: bool = false) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	if not hero is Hero:
		return false

	var current: Mission = get_unit_mission(hero)
	var main_mission: Mission = get_main_army_mission()
	if main_mission == Mission.SHOP or main_mission == Mission.IDLE:
		main_mission = Mission.RALLY

	## Allow shopping while the army is idle/rallying; combat missions pull the hero back.
	if (
		current == Mission.SHOP
		and not force_leave_shop
		and get_mission_priority(main_mission) >= PRIORITY_SHOP
	):
		return false

	if current == main_mission:
		return true

	if current == Mission.SHOP and force_leave_shop:
		_mission_locked_until_msec.erase(hero.get_instance_id())

	return try_set_mission(hero, main_mission, 0.0)


static func mission_to_label(mission: Mission) -> String:
	match mission:
		Mission.ECONOMY:
			return "ECONOMY"
		Mission.BUILD:
			return "BUILD"
		Mission.CREEP:
			return "CREEP"
		Mission.RALLY:
			return "RALLY"
		Mission.SHOP:
			return "SHOP"
		Mission.ATTACK:
			return "ATTACK"
		Mission.DEFEND:
			return "DEFEND"
		Mission.RETREAT:
			return "RETREAT"
		_:
			return "IDLE"


static func mission_to_debug_phrase(mission: Mission) -> String:
	match mission:
		Mission.CREEP:
			return "Creeping"
		Mission.ATTACK:
			return "Attacking Player"
		Mission.DEFEND:
			return "Defending Base"
		Mission.RETREAT:
			return "Retreating"
		Mission.RALLY:
			return "Rallying"
		Mission.SHOP:
			return "Shopping"
		Mission.ECONOMY:
			return "Economy"
		Mission.BUILD:
			return "Building"
		_:
			return "Idle"


static func _is_mission_locked(unit_id: int) -> bool:
	if not _mission_locked_until_msec.has(unit_id):
		return false

	return Time.get_ticks_msec() < int(_mission_locked_until_msec[unit_id])
