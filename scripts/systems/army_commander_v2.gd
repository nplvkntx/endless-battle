class_name ArmyCommanderV2
extends Node

## Executes the mission published by MilitaryDirectorV2.
## Does not choose creep / attack / defend / retreat itself.
## Receives the main squad from the director; cannot recruit units independently.
##
## Foundation task: drains shared order batch infrastructure, ticks hero micro,
## and holds the army idle. Advanced execution is not migrated yet.

const HERO_MICRO_INTERVAL_SECONDS: float = 1.0
const HERO_EXECUTE_SEARCH_RANGE: float = 14.0
const ASSEMBLE_ROW_SPACING: float = 2.35
const ASSEMBLE_COLUMN_SPACING: float = 2.1

var _director: MilitaryDirectorV2 = null
var _hero_micro_timer: float = 0.0
## Read-only squad snapshot reference from the director (never mutated here).
var _active_squad: ArmySquadV2 = null
var _assemble_anchor: Vector3 = Vector3.ZERO
var _assemble_role_slots: Dictionary = {}
var _assemble_next_slot_by_role: Dictionary = {}


func _ready() -> void:
	_director = get_parent().get_node_or_null("MilitaryDirectorV2") as MilitaryDirectorV2
	_hero_micro_timer = HERO_MICRO_INTERVAL_SECONDS * 0.4
	set_process(MilitaryAIConfig.is_v2_enabled())


func reset_match_state() -> void:
	_hero_micro_timer = HERO_MICRO_INTERVAL_SECONDS * 0.4
	_active_squad = null
	_assemble_anchor = Vector3.ZERO
	_assemble_role_slots.clear()
	_assemble_next_slot_by_role.clear()


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		set_process(false)
		return

	## Shared order-bus drain previously owned by EnemyCombatController.
	EnemyArmyCommand.apply_pending_strategic_transition()
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	EnemyArmyCommand.tick_perf_diagnostics(get_tree(), delta)
	EnemyArmyCommand.tick_retreat_cooldown(delta)

	_hero_micro_timer += delta
	if _hero_micro_timer >= HERO_MICRO_INTERVAL_SECONDS:
		_hero_micro_timer = 0.0
		_tick_hero_micro()

	_execute_current_mission(delta)
	PerfCounters.record_ai_combat_update()


func _resolve_director() -> MilitaryDirectorV2:
	if _director == null:
		_director = get_parent().get_node_or_null("MilitaryDirectorV2") as MilitaryDirectorV2
	return _director


## Commander may only receive squad membership from the director.
func _receive_squad_from_director() -> ArmySquadV2:
	var director: MilitaryDirectorV2 = _resolve_director()
	if director == null:
		_active_squad = null
		return null
	_active_squad = director.get_main_squad()
	return _active_squad


func get_active_squad() -> ArmySquadV2:
	return _receive_squad_from_director()


func _execute_current_mission(_delta: float) -> void:
	var director: MilitaryDirectorV2 = _resolve_director()
	if director == null:
		return

	var mission: ArmyMissionV2 = director.get_mission()
	if mission == null:
		return

	mission.sanitize_target_object()
	var squad: ArmySquadV2 = _receive_squad_from_director()
	## Future execution must use `squad` only — never invent membership or solo-push pending units.
	if squad == null:
		return

	## Foundation: no strategic self-decisions and no advanced order issuance yet.
	match director.get_state():
		MilitaryDirectorV2.State.IDLE, MilitaryDirectorV2.State.RECOVER:
			pass
		MilitaryDirectorV2.State.ASSEMBLE:
			_execute_assemble_mission(director, mission, squad)
		MilitaryDirectorV2.State.CREEP:
			## Creep handoff is strategic only for now; keep the squad settled until the
			## dedicated V2 creep executor lands instead of scattering the army.
			_execute_assemble_mission(director, mission, squad)
		MilitaryDirectorV2.State.ATTACK, MilitaryDirectorV2.State.DEFEND, MilitaryDirectorV2.State.RETREAT:
			## Reserved for future execution adapters. Commander still must not choose these.
			pass


func _tick_hero_micro() -> void:
	## Hero AI may cast abilities, choose targets during the current mission, and survive.
	## Hero AI may not choose the army mission or override defend/retreat (see AIHeroMastery).
	var director: MilitaryDirectorV2 = _resolve_director()
	var squad: ArmySquadV2 = _receive_squad_from_director()
	var hero: Hero = null
	if squad != null and squad.hero_present:
		for entry: Variant in squad.get_members_copy():
			if entry is Hero and NodeSafety.is_alive_node(entry):
				hero = entry as Hero
				break
	if hero == null:
		hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null or not is_instance_valid(hero):
		return

	var health_ratio: float = EnemyArmyCommand.get_health_ratio(hero)
	var state_name: String = "IDLE"
	var mission_type_name: String = "IDLE"
	if director != null:
		state_name = director.get_state_name()
		var mission: ArmyMissionV2 = director.get_mission()
		if mission != null:
			mission_type_name = mission.get_mission_type_name()

	var creeping: bool = state_name == "CREEP" or mission_type_name == "CREEP"
	var retreating: bool = (
		state_name == "RETREAT"
		or mission_type_name == "RETREAT"
		or health_ratio < EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO
	)
	var defend_base: bool = state_name == "DEFEND" or mission_type_name == "DEFEND"

	AIHeroMastery.tick(
		hero,
		{
			"health_ratio": health_ratio,
			"nearby_enemy_count": 0,
			"aoe_needed": EnemyArmyCommand.HERO_AOE_PLAYER_COUNT,
			"defensive_hp_ratio": EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO,
			"power_strike_range": EnemyArmyCommand.HERO_POWER_STRIKE_SEARCH_RANGE,
			"execute_range": HERO_EXECUTE_SEARCH_RANGE,
			"retreating": retreating,
			"creeping": creeping,
			"defend_base": defend_base,
			"mastery_owned": true,
			"military_ai_v2": true,
			"army_state": state_name,
			"army_mission": mission_type_name,
		}
	)


func _execute_assemble_mission(
	director: MilitaryDirectorV2,
	mission: ArmyMissionV2,
	squad: ArmySquadV2
) -> void:
	if squad.get_size() <= 0:
		return

	var rally_point: Vector3 = mission.target_position
	if rally_point == Vector3.ZERO:
		rally_point = director.get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		return

	if _assemble_anchor == Vector3.ZERO:
		_assemble_anchor = rally_point
	elif EnemyArmyCommand.horizontal_distance(_assemble_anchor, rally_point) > 1.0:
		_assemble_anchor = rally_point

	_prune_assemble_slots(squad)

	var front: Vector3 = _resolve_assemble_forward(rally_point)
	var right: Vector3 = front.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var unit: Node3D = entry as Node3D
		var slot: Vector3 = _get_or_assign_assemble_slot(unit, squad, rally_point, front, right)
		var distance_to_slot: float = EnemyArmyCommand.horizontal_distance(unit.global_position, slot)
		if distance_to_slot <= MilitaryAIConfig.V2_ASSEMBLE_SETTLE_TOLERANCE:
			_settle_unit(unit)
			continue
		if not EnemyUnitMission.should_reissue_move_order(unit, slot, EnemyUnitMission.Mission.RALLY):
			continue
		if _should_use_attack_move_for_assemble(unit, distance_to_slot):
			EnemyArmyCommand.command_attack_move([unit], slot, EnemyUnitMission.Mission.RALLY)
		else:
			EnemyArmyCommand.command_hold_at_rally([unit], slot, EnemyUnitMission.Mission.RALLY)


func _resolve_assemble_forward(rally_point: Vector3) -> Vector3:
	var director: MilitaryDirectorV2 = _resolve_director()
	if director != null:
		var hint: Vector3 = director.get_assemble_forward_hint()
		if hint.length_squared() > 0.01:
			return hint

	var origin: Vector3 = _assemble_anchor if _assemble_anchor != Vector3.ZERO else rally_point
	var forward: Vector3 = rally_point - origin
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0.0, 0.0, 1.0)
	else:
		forward = forward.normalized()
	return forward


func _prune_assemble_slots(squad: ArmySquadV2) -> void:
	var living: Dictionary = {}
	for entry: Variant in squad.get_members_copy():
		if NodeSafety.is_alive_node(entry):
			living[(entry as Node).get_instance_id()] = true

	for unit_id: Variant in _assemble_role_slots.keys():
		if not living.has(int(unit_id)):
			_assemble_role_slots.erase(unit_id)


func _get_or_assign_assemble_slot(
	unit: Node3D,
	squad: ArmySquadV2,
	rally_point: Vector3,
	forward: Vector3,
	right: Vector3
) -> Vector3:
	var unit_id: int = unit.get_instance_id()
	if _assemble_role_slots.has(unit_id):
		return _compose_slot_position(
			rally_point,
			forward,
			right,
			_assemble_role_slots[unit_id] as Dictionary
		)

	var role: ArmySquadV2.UnitRole = squad.get_role(unit)
	var slot_index: int = int(_assemble_next_slot_by_role.get(int(role), 0))
	_assemble_next_slot_by_role[int(role)] = slot_index + 1
	var slot_meta: Dictionary = {
		"role": int(role),
		"slot_index": slot_index,
	}
	_assemble_role_slots[unit_id] = slot_meta
	return _compose_slot_position(rally_point, forward, right, slot_meta)


func _compose_slot_position(
	rally_point: Vector3,
	forward: Vector3,
	right: Vector3,
	slot_meta: Dictionary
) -> Vector3:
	var role_id: int = int(slot_meta.get("role", int(ArmySquadV2.UnitRole.FRONTLINE)))
	var slot_index: int = int(slot_meta.get("slot_index", 0))
	var lateral: float = 0.0
	if slot_index > 0:
		var column_index: int = int((slot_index + 1) / 2)
		var side: int = -1 if slot_index % 2 == 1 else 1
		lateral = float(column_index) * ASSEMBLE_COLUMN_SPACING * float(side)

	var row_offset: float = _row_offset_for_role(role_id, slot_index)
	return Vector3(
		rally_point.x + right.x * lateral + forward.x * row_offset,
		rally_point.y,
		rally_point.z + right.z * lateral + forward.z * row_offset
	)


func _row_offset_for_role(role_id: int, slot_index: int) -> float:
	match role_id:
		int(ArmySquadV2.UnitRole.FRONTLINE), int(ArmySquadV2.UnitRole.CAVALRY):
			return ASSEMBLE_ROW_SPACING * (1.0 + floorf(float(slot_index) / 6.0) * 0.35)
		int(ArmySquadV2.UnitRole.MELEE_GUARD):
			return ASSEMBLE_ROW_SPACING * 0.35
		int(ArmySquadV2.UnitRole.RANGED):
			return -ASSEMBLE_ROW_SPACING * (0.9 + floorf(float(slot_index) / 6.0) * 0.35)
		int(ArmySquadV2.UnitRole.SIEGE):
			return -ASSEMBLE_ROW_SPACING * (2.0 + floorf(float(slot_index) / 4.0) * 0.45)
		int(ArmySquadV2.UnitRole.HERO):
			return _hero_row_offset()
		_:
			return 0.0


func _hero_row_offset() -> float:
	var hero: Hero = _find_squad_hero()
	if hero == null:
		return -ASSEMBLE_ROW_SPACING * 0.25
	var role: UnitFormationRole.Role = UnitFormationRole.get_role(hero)
	if UnitFormationRole.is_ranged_role(role):
		return -ASSEMBLE_ROW_SPACING * 0.75
	if UnitFormationRole.is_siege_role(role):
		return -ASSEMBLE_ROW_SPACING * 1.25
	return ASSEMBLE_ROW_SPACING * 0.45


func _find_squad_hero() -> Hero:
	if _active_squad == null:
		return null
	for entry: Variant in _active_squad.get_members_copy():
		if entry is Hero and NodeSafety.is_alive_node(entry):
			return entry as Hero
	return null


func _settle_unit(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit is Unit and (unit as Unit).has_move_target:
		(unit as Unit).issue_stop()
		return
	if unit.has_method("cancel_attack_move"):
		unit.call("cancel_attack_move")


func _should_use_attack_move_for_assemble(unit: Node3D, distance_to_slot: float) -> bool:
	if unit is Hero:
		return false
	if _active_squad == null:
		return distance_to_slot > MilitaryAIConfig.V2_ASSEMBLE_ATTACK_MOVE_DISTANCE
	var role: ArmySquadV2.UnitRole = _active_squad.get_role(unit)
	if role == ArmySquadV2.UnitRole.SIEGE:
		return false
	return distance_to_slot > MilitaryAIConfig.V2_ASSEMBLE_ATTACK_MOVE_DISTANCE


func debug_get_assemble_slot_positions(rally_point: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var squad: ArmySquadV2 = _receive_squad_from_director()
	if squad == null:
		return result
	var front: Vector3 = Vector3(0.0, 0.0, 1.0)
	var right: Vector3 = Vector3.RIGHT
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var unit: Node3D = entry as Node3D
		result[unit.get_instance_id()] = _get_or_assign_assemble_slot(unit, squad, rally_point, front, right)
	return result
