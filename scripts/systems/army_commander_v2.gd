class_name ArmyCommanderV2
extends Node

## Executes the mission published by MilitaryDirectorV2.
## Does not choose creep / attack / defend / retreat itself.
## Receives the main squad from the director; cannot recruit units independently.
##
## Executes ASSEMBLE / CREEP / ATTACK / DEFEND / RETREAT / RECOVER orders and ticks
## hero kit micro (abilities, local targets, short positioning). Hero AI never
## chooses strategic missions — MilitaryDirectorV2 owns that authority.

const HERO_MICRO_INTERVAL_SECONDS: float = 1.0
const HERO_EXECUTE_SEARCH_RANGE: float = 14.0
const ASSEMBLE_ROW_SPACING: float = 2.35
const ASSEMBLE_COLUMN_SPACING: float = 2.1
const CREEP_REGROUP_HOLD_SECONDS: float = 2.0
const CREEP_ORDER_REISSUE_SECONDS: float = 0.35
const HERO_ROLE_FOLLOW_SPACING: float = 2.4
## Fraction of living squad members that must lack orders before counting as idle.
const SQUAD_IDLE_MEMBER_RATIO: float = 0.55

var _director: MilitaryDirectorV2 = null
var _hero_micro_timer: float = 0.0
## Read-only squad snapshot reference from the director (never mutated here).
var _active_squad: ArmySquadV2 = null
var _assemble_anchor: Vector3 = Vector3.ZERO
var _assemble_role_slots: Dictionary = {}
var _assemble_next_slot_by_role: Dictionary = {}
var _creep_focus_reissue_timer: float = 0.0
var _creep_regroup_hold_timer: float = 0.0
var _creep_order_reissue_timer: float = 0.0
var _creep_manager: EnemyCreepManager = null
var _defend_order_reissue_timer: float = 0.0
var _defend_focus_reissue_timer: float = 0.0
var _defend_focus_target: Node3D = null
var _attack_order_reissue_timer: float = 0.0
var _attack_focus_reissue_timer: float = 0.0
var _attack_chase_target: Node3D = null
var _attack_chase_anchor: Vector3 = Vector3.ZERO
var _attack_chase_start_msec: int = 0
var _retreat_order_reissue_timer: float = 0.0
var _retreat_cover_elapsed: float = 0.0
var _recover_order_reissue_timer: float = 0.0
var _squad_idle_seconds: float = 0.0
var _last_force_order_msec: int = 0


func _ready() -> void:
	_director = get_parent().get_node_or_null("MilitaryDirectorV2") as MilitaryDirectorV2
	_hero_micro_timer = HERO_MICRO_INTERVAL_SECONDS * 0.4
	_creep_manager = get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
	set_process(MilitaryAIConfig.is_v2_enabled())


func reset_match_state() -> void:
	_hero_micro_timer = HERO_MICRO_INTERVAL_SECONDS * 0.4
	_active_squad = null
	_assemble_anchor = Vector3.ZERO
	_assemble_role_slots.clear()
	_assemble_next_slot_by_role.clear()
	_creep_focus_reissue_timer = EnemyCreepManager.FOCUS_REISSUE_SECONDS
	_creep_regroup_hold_timer = 0.0
	_creep_order_reissue_timer = CREEP_ORDER_REISSUE_SECONDS
	_creep_manager = get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
	_defend_order_reissue_timer = MilitaryAIConfig.V2_DEFEND_ORDER_REISSUE_SECONDS
	_defend_focus_reissue_timer = MilitaryAIConfig.V2_DEFEND_FOCUS_REISSUE_SECONDS
	_defend_focus_target = null
	_attack_order_reissue_timer = MilitaryAIConfig.V2_ATTACK_ORDER_REISSUE_SECONDS
	_attack_focus_reissue_timer = MilitaryAIConfig.V2_ATTACK_FOCUS_REISSUE_SECONDS
	_attack_chase_target = null
	_attack_chase_anchor = Vector3.ZERO
	_attack_chase_start_msec = 0
	_retreat_order_reissue_timer = MilitaryAIConfig.V2_RETREAT_ORDER_REISSUE_SECONDS
	_retreat_cover_elapsed = 0.0
	_recover_order_reissue_timer = MilitaryAIConfig.V2_RECOVER_ORDER_REISSUE_SECONDS
	_squad_idle_seconds = 0.0
	_last_force_order_msec = 0


## Watchdog asks the commander to re-issue current mission orders once.
func request_watchdog_order_refresh() -> void:
	_creep_order_reissue_timer = CREEP_ORDER_REISSUE_SECONDS
	_creep_focus_reissue_timer = EnemyCreepManager.FOCUS_REISSUE_SECONDS
	_defend_order_reissue_timer = MilitaryAIConfig.V2_DEFEND_ORDER_REISSUE_SECONDS
	_defend_focus_reissue_timer = MilitaryAIConfig.V2_DEFEND_FOCUS_REISSUE_SECONDS
	_attack_order_reissue_timer = MilitaryAIConfig.V2_ATTACK_ORDER_REISSUE_SECONDS
	_attack_focus_reissue_timer = MilitaryAIConfig.V2_ATTACK_FOCUS_REISSUE_SECONDS
	_retreat_order_reissue_timer = MilitaryAIConfig.V2_RETREAT_ORDER_REISSUE_SECONDS
	_recover_order_reissue_timer = MilitaryAIConfig.V2_RECOVER_ORDER_REISSUE_SECONDS


func get_squad_idle_seconds() -> float:
	return _squad_idle_seconds


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		set_process(false)
		return

	## Shared order-bus drain previously owned by EnemyCombatController.
	EnemyArmyCommand.apply_pending_strategic_transition()
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	EnemyArmyCommand.tick_perf_diagnostics(get_tree(), delta)
	EnemyArmyCommand.tick_retreat_cooldown(delta)
	## Keep lethal / aggression scoring alive while the legacy wave manager is gated off.
	EnemyArmyCommand.update_finishing_mode(get_tree(), delta)
	_creep_focus_reissue_timer += delta
	_creep_order_reissue_timer += delta
	_defend_order_reissue_timer += delta
	_defend_focus_reissue_timer += delta
	_attack_order_reissue_timer += delta
	_attack_focus_reissue_timer += delta
	_retreat_order_reissue_timer += delta
	_recover_order_reissue_timer += delta
	if _creep_regroup_hold_timer > 0.0:
		_creep_regroup_hold_timer = maxf(0.0, _creep_regroup_hold_timer - delta)
	if _retreat_cover_elapsed > 0.0:
		_retreat_cover_elapsed += delta

	_hero_micro_timer += delta
	if _hero_micro_timer >= HERO_MICRO_INTERVAL_SECONDS:
		_hero_micro_timer = 0.0
		_tick_hero_micro()

	_execute_current_mission(delta)
	_tick_squad_idle_guard(delta)
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

	_sync_execution_authority(director, mission)

	## Foundation: no strategic self-decisions. Execution adapters own order issuance.
	match director.get_state():
		MilitaryDirectorV2.State.IDLE:
			_retreat_cover_elapsed = 0.0
			_stage_pending_reinforcements(director)
		MilitaryDirectorV2.State.RECOVER:
			_retreat_cover_elapsed = 0.0
			_execute_recover_mission(director, mission, squad)
		MilitaryDirectorV2.State.ASSEMBLE:
			_retreat_cover_elapsed = 0.0
			_execute_assemble_mission(director, mission, squad)
		MilitaryDirectorV2.State.CREEP:
			_retreat_cover_elapsed = 0.0
			_execute_creep_mission(director, mission, squad)
		MilitaryDirectorV2.State.DEFEND:
			_retreat_cover_elapsed = 0.0
			_execute_defend_mission(director, mission, squad)
		MilitaryDirectorV2.State.ATTACK:
			_retreat_cover_elapsed = 0.0
			_execute_attack_mission(director, mission, squad)
		MilitaryDirectorV2.State.RETREAT:
			_execute_retreat_mission(director, mission, squad)


func _sync_execution_authority(director: MilitaryDirectorV2, mission: ArmyMissionV2) -> void:
	var reason: String = mission.transition_reason if mission != null else "v2 sync"
	match director.get_state():
		MilitaryDirectorV2.State.CREEP:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.CREEPING,
				EnemyArmyCommand.StrategicState.CREEPING,
				reason
			)
		MilitaryDirectorV2.State.ATTACK:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.ATTACKING,
				EnemyArmyCommand.StrategicState.ATTACKING,
				reason
			)
		MilitaryDirectorV2.State.DEFEND:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.DEFENDING,
				EnemyArmyCommand.StrategicState.DEFENDING,
				reason
			)
		MilitaryDirectorV2.State.RETREAT:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.RETREATING,
				EnemyArmyCommand.StrategicState.RETREATING,
				reason
			)
		MilitaryDirectorV2.State.RECOVER:
			EnemyArmyCommand.force_set_strategic_state_for_v2(
				EnemyArmyCommand.StrategicState.RECOVERING,
				reason
			)
		MilitaryDirectorV2.State.ASSEMBLE:
			EnemyArmyCommand.force_set_strategic_state_for_v2(
				EnemyArmyCommand.StrategicState.ECONOMY,
				reason
			)
		_:
			pass


func _tick_squad_idle_guard(delta: float) -> void:
	var director: MilitaryDirectorV2 = _resolve_director()
	if director == null:
		_squad_idle_seconds = 0.0
		return

	var state: MilitaryDirectorV2.State = director.get_state()
	## Standing still is allowed while assembling, recovering, retreating, or idle.
	if state in [
		MilitaryDirectorV2.State.IDLE,
		MilitaryDirectorV2.State.ASSEMBLE,
		MilitaryDirectorV2.State.RECOVER,
		MilitaryDirectorV2.State.RETREAT,
	]:
		_squad_idle_seconds = 0.0
		return

	## Intentional short regroup holds during creep are not combat idle.
	if state == MilitaryDirectorV2.State.CREEP and _creep_regroup_hold_timer > 0.0:
		_squad_idle_seconds = 0.0
		return

	var squad: ArmySquadV2 = _receive_squad_from_director()
	if squad == null or squad.get_size() <= 0:
		_squad_idle_seconds = 0.0
		return

	if _squad_has_meaningful_orders(squad):
		_squad_idle_seconds = 0.0
		return

	_squad_idle_seconds += delta
	if _squad_idle_seconds < MilitaryAIConfig.V2_SQUAD_IDLE_SECONDS:
		return

	var mission: ArmyMissionV2 = director.get_mission()
	if mission == null:
		return

	_force_regenerate_squad_order(director, mission, squad)
	_squad_idle_seconds = 0.0


func _squad_has_meaningful_orders(squad: ArmySquadV2) -> bool:
	var living: int = 0
	var ordered: int = 0
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node:
			continue
		if not EnemyArmyCommand.is_living_combat_unit(entry as Node):
			continue
		living += 1
		if _unit_has_meaningful_order(entry as Node):
			ordered += 1

	if living <= 0:
		return true
	## Ordered if a clear majority still has move / attack-move / combat.
	return float(ordered) / float(living) >= (1.0 - SQUAD_IDLE_MEMBER_RATIO)


func _unit_has_meaningful_order(unit: Node) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	if unit is Unit:
		var unit_ref: Unit = unit as Unit
		if unit_ref.has_move_target:
			return true

	if bool(unit.get("_has_attack_move_destination")):
		return true

	var attack_target: Variant = unit.get("_attack_target")
	if NodeSafety.is_alive_node(attack_target):
		return true

	return false


func _force_regenerate_squad_order(
	director: MilitaryDirectorV2,
	mission: ArmyMissionV2,
	squad: ArmySquadV2
) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if _last_force_order_msec > 0 and float(now_msec - _last_force_order_msec) / 1000.0 < 0.35:
		return
	_last_force_order_msec = now_msec

	## Bust reissue throttles so the next execute path cannot soft-skip.
	request_watchdog_order_refresh()
	_squad_idle_seconds = 0.0

	var destination: Vector3 = mission.target_position
	var alive_target: Node3D = mission.get_alive_target_object()
	if alive_target != null:
		destination = alive_target.global_position
	if destination == Vector3.ZERO:
		destination = director.get_assemble_rally_point()
	if destination == Vector3.ZERO:
		return

	var units: Array = []
	for entry: Variant in squad.get_members_copy():
		if NodeSafety.is_alive_node(entry) and EnemyArmyCommand.is_living_combat_unit(entry as Node):
			units.append(entry)
	units = NodeSafety.clean_node_array(units)
	if units.is_empty():
		return

	_sync_execution_authority(director, mission)
	var tree: SceneTree = get_tree()
	var issued: bool = false
	match director.get_state():
		MilitaryDirectorV2.State.CREEP:
			issued = EnemyArmyCommand.issue_group_combat_move(
				tree,
				units,
				destination,
				EnemyUnitMission.Mission.CREEP,
				EnemyArmyCommand.ArmyMode.CREEPING
			)
			if not issued:
				_force_attack_move(units, destination, EnemyUnitMission.Mission.CREEP)
				issued = true
		MilitaryDirectorV2.State.ATTACK:
			issued = EnemyArmyCommand.issue_group_combat_move(
				tree,
				units,
				destination,
				EnemyUnitMission.Mission.ATTACK,
				EnemyArmyCommand.ArmyMode.ATTACKING,
				true
			)
			if not issued:
				_force_attack_move(units, destination, EnemyUnitMission.Mission.ATTACK)
				issued = true
		MilitaryDirectorV2.State.DEFEND:
			_force_attack_move(units, destination, EnemyUnitMission.Mission.DEFEND)
			issued = true
		_:
			return

	if issued:
		EnemyAIDebug.log_once(
			"v2_idle_regen",
			"[AI Idle] regenerated %s order -> (%.1f, %.1f)" % [
				director.get_state_name(),
				destination.x,
				destination.z,
			]
		)


func _force_attack_move(
	units: Array,
	destination: Vector3,
	mission: EnemyUnitMission.Mission
) -> void:
	if units.is_empty() or destination == Vector3.ZERO:
		return
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_attack_move(units, destination, mission)
	)
	EnemyArmyCommand.note_mission_order("attack-move", destination)


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

	## Ability learning stays with hero micro ownership under V2 (legacy wave manager gated).
	AIHeroMastery.spend_ability_points(hero)
	if not NodeSafety.is_alive_node(hero):
		return

	var health_ratio: float = EnemyArmyCommand.get_health_ratio(hero)
	var state_name: String = "IDLE"
	var mission_type_name: String = "IDLE"
	var mission_target: Node3D = null
	var mission_destination: Vector3 = Vector3.ZERO
	if director != null:
		state_name = director.get_state_name()
		var mission: ArmyMissionV2 = director.get_mission()
		if mission != null:
			mission_type_name = mission.get_mission_type_name()
			mission_destination = mission.target_position
			mission_target = mission.get_alive_target_object()

	var creeping: bool = state_name == "CREEP" or mission_type_name == "CREEP"
	var attacking: bool = state_name == "ATTACK" or mission_type_name == "ATTACK"
	var retreating: bool = (
		state_name == "RETREAT"
		or mission_type_name == "RETREAT"
		or health_ratio < EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO
	)
	var defend_base: bool = state_name == "DEFEND" or mission_type_name == "DEFEND"
	var nearby_hostiles: int = AIHeroMastery.count_nearby_hostiles(hero, creeping)
	var squad_center: Vector3 = _resolve_squad_center_for_hero(squad, hero)
	var role_anchor: Vector3 = _resolve_hero_role_anchor(hero, squad_center, mission_destination, mission_target)

	AIHeroMastery.tick(
		hero,
		{
			"health_ratio": health_ratio,
			"nearby_enemy_count": nearby_hostiles,
			"aoe_needed": EnemyArmyCommand.HERO_AOE_PLAYER_COUNT,
			"defensive_hp_ratio": EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO,
			"power_strike_range": EnemyArmyCommand.HERO_POWER_STRIKE_SEARCH_RANGE,
			"execute_range": HERO_EXECUTE_SEARCH_RANGE,
			"retreating": retreating,
			"creeping": creeping,
			"attacking": attacking,
			"defend_base": defend_base,
			"mastery_owned": true,
			"military_ai_v2": true,
			"army_state": state_name,
			"army_mission": mission_type_name,
			"squad_center": squad_center,
			"role_anchor": role_anchor,
			"mission_destination": mission_destination,
			"mission_target": mission_target,
			"hero_follow_spacing": HERO_ROLE_FOLLOW_SPACING,
		}
	)


func _resolve_squad_center_for_hero(squad: ArmySquadV2, hero: Hero) -> Vector3:
	if squad == null:
		return Vector3.ZERO
	var members: Array = []
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		## Prefer non-hero center so the hero can orbit a stable squad body.
		if entry is Hero:
			continue
		members.append(entry)
	var center: Vector3 = EnemyArmyCommand.compute_army_center(members)
	if center != Vector3.ZERO:
		return center
	if NodeSafety.is_alive_node(hero):
		return hero.global_position
	return Vector3.ZERO


func _resolve_hero_role_anchor(
	hero: Hero,
	squad_center: Vector3,
	mission_destination: Vector3,
	mission_target: Node3D
) -> Vector3:
	if squad_center == Vector3.ZERO or not NodeSafety.is_alive_node(hero):
		return Vector3.ZERO

	var forward: Vector3 = Vector3.ZERO
	if NodeSafety.is_alive_node(mission_target):
		forward = mission_target.global_position - squad_center
	elif mission_destination != Vector3.ZERO:
		forward = mission_destination - squad_center
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		var director: MilitaryDirectorV2 = _resolve_director()
		if director != null:
			forward = director.get_assemble_forward_hint()
		if forward.length_squared() < 0.01:
			forward = Vector3(0.0, 0.0, 1.0)
		else:
			forward = forward.normalized()
	else:
		forward = forward.normalized()

	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var role: UnitFormationRole.Role = UnitFormationRole.get_role(hero)
	var local_offset: Vector3 = UnitFormationRole.hero_follow_offset(role, HERO_ROLE_FOLLOW_SPACING)
	return Vector3(
		squad_center.x + right.x * local_offset.x + forward.x * local_offset.z,
		squad_center.y,
		squad_center.z + right.z * local_offset.x + forward.z * local_offset.z
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


func _resolve_creep_manager() -> EnemyCreepManager:
	if _creep_manager == null:
		_creep_manager = get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
	return _creep_manager


func _execute_creep_mission(
	director: MilitaryDirectorV2,
	mission: ArmyMissionV2,
	squad: ArmySquadV2
) -> void:
	var creep_manager: EnemyCreepManager = _resolve_creep_manager()
	if creep_manager == null:
		EnemyArmyCommand.clear_executable_mission("creep manager unavailable")
		_execute_assemble_mission(director, mission, squad)
		return

	var camp: Node3D = mission.get_alive_target_object()
	if camp == null:
		EnemyArmyCommand.clear_executable_mission("creep camp missing")
		_execute_assemble_mission(director, mission, squad)
		return

	var creep_army: Array = _collect_creep_army(squad)
	if not _is_creep_army_ready(creep_army):
		EnemyArmyCommand.clear_executable_mission("creep squad incomplete")
		_execute_assemble_mission(director, mission, squad)
		return

	var tree: SceneTree = get_tree()
	var rally_point: Vector3 = director.get_assemble_rally_point()
	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(creep_army)
	if army_center == Vector3.ZERO:
		EnemyArmyCommand.clear_executable_mission("creep squad has no center")
		_execute_assemble_mission(director, mission, squad)
		return

	if _creep_regroup_hold_timer > 0.0 or creep_manager._needs_army_regroup(creep_army):
		EnemyArmyCommand.clear_executable_mission("creep regroup")
		if _creep_order_reissue_timer >= CREEP_ORDER_REISSUE_SECONDS:
			_regroup_creep_army(creep_manager, creep_army, rally_point)
		mission.note_progress("creep regroup")
		return

	if creep_manager._is_camp_cleared(tree, camp):
		EnemyArmyCommand.clear_executable_mission("creep camp cleared")
		_hold_creep_squad(creep_army, army_center)
		_creep_regroup_hold_timer = CREEP_REGROUP_HOLD_SECONDS
		mission.note_progress("cleared camp")
		return

	if creep_manager._is_player_contesting_camp(tree, camp):
		EnemyArmyCommand.clear_executable_mission("player contesting camp")
		if _creep_order_reissue_timer >= CREEP_ORDER_REISSUE_SECONDS:
			_regroup_creep_army(creep_manager, creep_army, rally_point)
		return

	if creep_manager._should_retreat_from_creeping(tree, creep_army):
		EnemyArmyCommand.clear_executable_mission("creep retreat")
		return

	if not creep_manager._squad_safe_to_commit(tree, creep_army):
		EnemyArmyCommand.clear_executable_mission("creep squad not safe")
		if _creep_order_reissue_timer >= CREEP_ORDER_REISSUE_SECONDS:
			_regroup_creep_army(creep_manager, creep_army, rally_point)
		return

	var engaging: bool = creep_manager._is_army_engaging_camp(tree, creep_army, camp)
	var validation: Dictionary = EnemyArmyCommand.validate_creeping_mission(
		tree,
		camp,
		director.get_reserved_creep_camp_id(),
		army_center,
		true,
		engaging
	)
	if not validation.get("valid", false):
		EnemyArmyCommand.clear_executable_mission(String(validation.get("reason", "creep invalid")))
		if _creep_order_reissue_timer >= CREEP_ORDER_REISSUE_SECONDS:
			_regroup_creep_army(creep_manager, creep_army, rally_point)
		return

	var destination: Vector3 = creep_manager._resolve_camp_attack_destination(tree, camp, army_center)
	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.CREEPING,
		"v2 creep execute",
		camp,
		destination,
		creep_manager._format_camp_name(camp),
		"attack-move",
		creep_army,
		director.has_reserved_creep_camp()
	)

	if engaging:
		if not creep_manager._is_squad_cohesive_for_engage(creep_army, camp):
			if _creep_order_reissue_timer >= CREEP_ORDER_REISSUE_SECONDS:
				_regroup_creep_army(creep_manager, creep_army, rally_point)
			return
		EnemyArmyCommand.note_mission_progress(army_center, true, creep_army.size())
		mission.note_progress("started combat")
		_execute_creep_focus_fire(creep_manager, tree, creep_army, camp)
		return

	if _creep_order_reissue_timer < CREEP_ORDER_REISSUE_SECONDS:
		EnemyArmyCommand.note_mission_progress(army_center, false, creep_army.size())
		return

	if not EnemyArmyCommand.issue_group_combat_move(
		tree,
		creep_army,
		destination,
		EnemyUnitMission.Mission.CREEP,
		EnemyArmyCommand.ArmyMode.CREEPING
	):
		## Never leave CREEP with no executable order — force Attack-Move.
		EnemyArmyCommand.prepare_v2_execution(
			EnemyArmyCommand.ArmyMode.CREEPING,
			EnemyArmyCommand.StrategicState.CREEPING,
			"creep move fallback"
		)
		_force_attack_move(creep_army, destination, EnemyUnitMission.Mission.CREEP)
		EnemyArmyCommand.note_mission_progress(army_center, false, creep_army.size())
		_creep_order_reissue_timer = 0.0
		return

	EnemyArmyCommand.note_mission_progress(army_center, false, creep_army.size())
	## Distance reduction is tracked by the director watchdog — do not fake progress here.
	_creep_order_reissue_timer = 0.0


func _collect_creep_army(squad: ArmySquadV2) -> Array:
	var units: Array = []
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry):
			continue
		if not entry is Node:
			continue
		if not EnemyArmyCommand.is_living_combat_unit(entry as Node):
			continue
		units.append(entry)
	return NodeSafety.clean_node_array(units)


func _is_creep_army_ready(creep_army: Array) -> bool:
	var non_hero_count: int = 0
	var has_hero: bool = false
	for entry: Variant in creep_army:
		if entry is Hero:
			has_hero = true
			continue
		if EnemyArmyCommand.is_non_hero_combat_unit(entry as Node):
			non_hero_count += 1
	return has_hero and non_hero_count >= MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS


func _regroup_creep_army(
	creep_manager: EnemyCreepManager,
	creep_army: Array,
	rally_point: Vector3
) -> void:
	_creep_regroup_hold_timer = CREEP_REGROUP_HOLD_SECONDS
	_creep_order_reissue_timer = 0.0
	if rally_point != Vector3.ZERO:
		creep_manager._hold_army_until_rallied(get_tree(), rally_point, creep_army)
		return
	creep_manager._regroup_creep_army(creep_army)


func _hold_creep_squad(creep_army: Array, hold_point: Vector3) -> void:
	if hold_point == Vector3.ZERO:
		return
	_creep_order_reissue_timer = 0.0
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_hold_at_rally(
			creep_army,
			hold_point,
			EnemyUnitMission.Mission.CREEP
		)
	)


func _execute_creep_focus_fire(
	creep_manager: EnemyCreepManager,
	tree: SceneTree,
	creep_army: Array,
	camp: Node3D
) -> void:
	if _creep_focus_reissue_timer < EnemyCreepManager.FOCUS_REISSUE_SECONDS:
		return
	_creep_focus_reissue_timer = 0.0
	creep_manager._engage_camp_focus_fire(tree, creep_army, camp)


func _execute_defend_mission(
	director: MilitaryDirectorV2,
	mission: ArmyMissionV2,
	squad: ArmySquadV2
) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var defense_army: Array = _collect_defend_army(squad)
	if defense_army.is_empty():
		return

	var rally_point: Vector3 = director.get_assemble_rally_point()
	var intercept: Vector3 = mission.target_position
	if intercept == Vector3.ZERO:
		intercept = EnemyArmyCommand.get_emergency_defense_objective()
	if intercept == Vector3.ZERO:
		intercept = rally_point
	if intercept == Vector3.ZERO:
		return

	var base_anchor: Vector3 = rally_point
	if base_anchor == Vector3.ZERO:
		base_anchor = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if base_anchor == Vector3.ZERO:
		base_anchor = intercept

	var focus: Node3D = null
	var mission_focus: Node3D = mission.get_alive_target_object()
	if mission_focus != null:
		focus = mission_focus
	elif NodeSafety.is_alive_node(_defend_focus_target):
		focus = _defend_focus_target
	_defend_focus_target = focus

	var chase_point: Vector3 = intercept
	if focus != null:
		chase_point = focus.global_position

	## Configurable leash: never chase forever beyond the defense radius.
	var leashed_point: Vector3 = _clamp_defend_destination(base_anchor, chase_point)
	var beyond_leash: bool = (
		EnemyArmyCommand.horizontal_distance(base_anchor, chase_point)
		> MilitaryAIConfig.V2_DEFEND_LEASH_RADIUS
	)

	EnemyArmyCommand.set_executable_mission(
		(
			EnemyArmyCommand.ExecutableMission.EMERGENCY_DEFEND
			if EnemyArmyCommand.is_emergency_defense_active()
			else EnemyArmyCommand.ExecutableMission.DEFEND
		),
		mission.transition_reason,
		focus,
		leashed_point,
		_defend_objective_label(focus, mission),
		"attack-move",
		defense_army,
		false
	)

	## Role-aware Attack-Move keeps the squad returning together without endless chase.
	if _defend_order_reissue_timer >= MilitaryAIConfig.V2_DEFEND_ORDER_REISSUE_SECONDS:
		_defend_order_reissue_timer = 0.0
		var melee_units: Array = []
		var ranged_units: Array = []
		_split_defend_roles(squad, defense_army, melee_units, ranged_units)

		var forward: Vector3 = leashed_point - base_anchor
		forward.y = 0.0
		if forward.length_squared() < 0.01:
			forward = Vector3(0.0, 0.0, 1.0)
		else:
			forward = forward.normalized()

		var melee_destination: Vector3 = (
			leashed_point + forward * MilitaryAIConfig.V2_DEFEND_MELEE_INTERCEPT_OFFSET
		)
		var ranged_destination: Vector3 = (
			leashed_point - forward * MilitaryAIConfig.V2_DEFEND_RANGED_STANDOFF
		)

		EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)
		EnemyArmyCommand.with_authorized_orders(func() -> void:
			if not melee_units.is_empty():
				EnemyArmyCommand.command_attack_move(
					melee_units,
					melee_destination,
					EnemyUnitMission.Mission.DEFEND
				)
			if not ranged_units.is_empty():
				EnemyArmyCommand.command_attack_move(
					ranged_units,
					ranged_destination,
					EnemyUnitMission.Mission.DEFEND
				)
		)
		## Order reissue alone is not meaningful progress — watchdog tracks distance/combat.
		EnemyArmyCommand.note_mission_progress(
			EnemyArmyCommand.compute_army_center(defense_army),
			false,
			defense_army.size()
		)

	## Connect attacks on the priority target, but never past the leash.
	if (
		not beyond_leash
		and focus != null
		and _defend_focus_reissue_timer >= MilitaryAIConfig.V2_DEFEND_FOCUS_REISSUE_SECONDS
	):
		_defend_focus_reissue_timer = 0.0
		EnemyArmyCommand.with_authorized_orders(func() -> void:
			EnemyArmyCommand.command_focus_attack(
				defense_army,
				focus,
				EnemyUnitMission.Mission.DEFEND
			)
		)
		mission.note_progress("started combat")
		EnemyArmyCommand.note_mission_progress(
			EnemyArmyCommand.compute_army_center(defense_army),
			true,
			defense_army.size()
		)


func _collect_defend_army(squad: ArmySquadV2) -> Array:
	var units: Array = []
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node:
			continue
		if not EnemyArmyCommand.is_living_combat_unit(entry as Node):
			continue
		units.append(entry)
	return NodeSafety.clean_node_array(units)


func _split_defend_roles(
	squad: ArmySquadV2,
	defense_army: Array,
	melee_units: Array,
	ranged_units: Array
) -> void:
	for entry: Variant in defense_army:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var unit: Node3D = entry as Node3D
		var role: ArmySquadV2.UnitRole = squad.get_role(unit)
		if role == ArmySquadV2.UnitRole.RANGED or role == ArmySquadV2.UnitRole.SIEGE:
			ranged_units.append(unit)
			continue
		if role == ArmySquadV2.UnitRole.HERO:
			var hero_role: UnitFormationRole.Role = UnitFormationRole.get_role(unit)
			if UnitFormationRole.is_ranged_role(hero_role) or UnitFormationRole.is_siege_role(hero_role):
				ranged_units.append(unit)
			else:
				melee_units.append(unit)
			continue
		melee_units.append(unit)


func _clamp_defend_destination(base_anchor: Vector3, chase_point: Vector3) -> Vector3:
	if base_anchor == Vector3.ZERO:
		return chase_point
	if chase_point == Vector3.ZERO:
		return base_anchor
	var offset: Vector3 = chase_point - base_anchor
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= MilitaryAIConfig.V2_DEFEND_LEASH_RADIUS or distance <= 0.01:
		return chase_point
	return base_anchor + offset.normalized() * MilitaryAIConfig.V2_DEFEND_LEASH_RADIUS


func _defend_objective_label(focus: Node3D, mission: ArmyMissionV2) -> String:
	if NodeSafety.is_alive_node(focus):
		return String(focus.name)
	if mission != null and not mission.transition_reason.is_empty():
		return mission.transition_reason
	return "DefendPoint"


func _execute_attack_mission(
	director: MilitaryDirectorV2,
	mission: ArmyMissionV2,
	squad: ArmySquadV2
) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var attack_army: Array = _collect_attack_army(squad)
	if attack_army.is_empty():
		return

	_stage_pending_reinforcements(director)

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(attack_army)
	var strategic_target: Node3D = mission.get_alive_target_object()
	var strategic_destination: Vector3 = mission.target_position
	if strategic_target != null:
		strategic_destination = strategic_target.global_position
	if strategic_destination == Vector3.ZERO:
		strategic_destination = army_center
	if strategic_destination == Vector3.ZERO:
		return

	var local_focus: Node3D = _pick_local_attack_focus(tree, army_center, strategic_target)
	var destination: Vector3 = strategic_destination
	var focus: Node3D = strategic_target
	var engaging_local: bool = false

	if NodeSafety.is_alive_node(local_focus):
		if _should_continue_local_chase(army_center, local_focus, strategic_destination):
			engaging_local = true
			focus = local_focus
			destination = _clamp_attack_chase_destination(
				strategic_destination,
				local_focus.global_position
			)
		else:
			_clear_attack_chase()

	var lethal: bool = director.is_attack_lethal_active()
	var exec_mission: EnemyArmyCommand.ExecutableMission = (
		EnemyArmyCommand.ExecutableMission.LETHAL_PUSH
		if lethal
		else EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER
	)
	EnemyArmyCommand.set_executable_mission(
		exec_mission,
		mission.transition_reason,
		focus,
		destination,
		_attack_objective_label(focus, mission),
		"attack-move",
		attack_army,
		false
	)

	if _attack_order_reissue_timer >= MilitaryAIConfig.V2_ATTACK_ORDER_REISSUE_SECONDS:
		_attack_order_reissue_timer = 0.0
		var issued: bool = EnemyArmyCommand.issue_group_combat_move(
			tree,
			attack_army,
			destination,
			EnemyUnitMission.Mission.ATTACK,
			EnemyArmyCommand.ArmyMode.ATTACKING,
			true
		)
		if not issued:
			EnemyArmyCommand.request_strategic_state(
				EnemyArmyCommand.StrategicState.ATTACKING,
				mission.transition_reason
			)
			EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.ATTACKING, true)
			EnemyArmyCommand.with_authorized_orders(func() -> void:
				EnemyArmyCommand.command_attack_move(
					attack_army,
					destination,
					EnemyUnitMission.Mission.ATTACK
				)
			)
		if engaging_local:
			mission.note_progress("started combat")
		EnemyArmyCommand.note_mission_progress(army_center, engaging_local, attack_army.size())
		EnemyArmyCommand.begin_fight_tracking(attack_army, army_center)

	## Focus the strategic (or leashed local) target once in contact — never endless chase.
	if (
		NodeSafety.is_alive_node(focus)
		and _attack_focus_reissue_timer >= MilitaryAIConfig.V2_ATTACK_FOCUS_REISSUE_SECONDS
	):
		var focus_distance: float = EnemyArmyCommand.horizontal_distance(
			army_center,
			focus.global_position
		)
		if focus_distance <= MilitaryAIConfig.V2_ATTACK_LOCAL_ENGAGE_RADIUS:
			_attack_focus_reissue_timer = 0.0
			EnemyArmyCommand.with_authorized_orders(func() -> void:
				EnemyArmyCommand.command_focus_attack(
					attack_army,
					focus,
					EnemyUnitMission.Mission.ATTACK
				)
			)
			mission.note_progress("started combat")
			EnemyArmyCommand.note_mission_progress(army_center, true, attack_army.size())


func _execute_retreat_mission(
	director: MilitaryDirectorV2,
	mission: ArmyMissionV2,
	squad: ArmySquadV2
) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var retreat_army: Array = _collect_attack_army(squad)
	if retreat_army.is_empty():
		return

	_stage_pending_reinforcements(director)

	var rally_point: Vector3 = mission.target_position
	if rally_point == Vector3.ZERO:
		rally_point = director.get_designated_recovery_point()
	if rally_point == Vector3.ZERO:
		rally_point = director.get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		rally_point = EnemyArmyCommand.get_retreat_destination(tree)
	if rally_point == Vector3.ZERO:
		return

	if _retreat_cover_elapsed <= 0.0:
		_retreat_cover_elapsed = 0.001

	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.RETREAT,
		mission.transition_reason,
		null,
		rally_point,
		"RecoveryPoint",
		"move",
		retreat_army,
		false
	)

	## Do not spam retreat destinations every frame.
	if _retreat_order_reissue_timer < MilitaryAIConfig.V2_RETREAT_ORDER_REISSUE_SECONDS:
		return
	_retreat_order_reissue_timer = 0.0

	var withdraw_units: Array = []
	var cover_units: Array = []
	_split_retreat_roles(squad, retreat_army, withdraw_units, cover_units)

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(retreat_army)
	var threat_center: Vector3 = _estimate_retreat_threat_center(tree, army_center)
	var cover_point: Vector3 = _resolve_retreat_cover_point(
		army_center,
		rally_point,
		threat_center
	)

	EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.RETREATING)
	EnemyArmyCommand.request_strategic_state(
		EnemyArmyCommand.StrategicState.RETREATING,
		mission.transition_reason
	)

	## Preserve the hero with the withdrawing group. Ranged/siege leave first.
	## Frontline may briefly cover, then also withdraw — never suicide forever.
	var cover_active: bool = (
		_retreat_cover_elapsed < 1.75
		and not cover_units.is_empty()
		and cover_point != Vector3.ZERO
	)
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		if not withdraw_units.is_empty():
			EnemyArmyCommand.command_retreat_to(withdraw_units, rally_point)
		if cover_active:
			EnemyArmyCommand.command_attack_move(
				cover_units,
				cover_point,
				EnemyUnitMission.Mission.RETREAT
			)
		elif not cover_units.is_empty():
			EnemyArmyCommand.command_retreat_to(cover_units, rally_point)
	)

	## Pull any stragglers still fighting away from the pack.
	_pull_retreat_stragglers(retreat_army, army_center, rally_point)

	mission.note_progress("completing retreat")
	EnemyArmyCommand.note_mission_progress(army_center, cover_active, retreat_army.size())


func _execute_recover_mission(
	director: MilitaryDirectorV2,
	mission: ArmyMissionV2,
	squad: ArmySquadV2
) -> void:
	_stage_pending_reinforcements(director)

	var recover_army: Array = _collect_attack_army(squad)
	var rally_point: Vector3 = mission.target_position
	if rally_point == Vector3.ZERO:
		rally_point = director.get_designated_recovery_point()
	if rally_point == Vector3.ZERO:
		rally_point = director.get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		return

	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.REGROUP,
		mission.transition_reason,
		null,
		rally_point,
		"Recover",
		"hold",
		recover_army,
		false
	)

	if _recover_order_reissue_timer < MilitaryAIConfig.V2_RECOVER_ORDER_REISSUE_SECONDS:
		return
	_recover_order_reissue_timer = 0.0

	## Regroup near base and wait — do not trickle back into the previous fight.
	if not recover_army.is_empty():
		EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING)
		EnemyArmyCommand.request_strategic_state(
			EnemyArmyCommand.StrategicState.RECOVERING,
			mission.transition_reason
		)
		EnemyArmyCommand.with_authorized_orders(func() -> void:
			EnemyArmyCommand.command_hold_at_rally(
				recover_army,
				rally_point,
				EnemyUnitMission.Mission.RALLY
			)
		)
		mission.note_progress("completing regroup")
		EnemyArmyCommand.note_mission_progress(
			EnemyArmyCommand.compute_army_center(recover_army),
			false,
			recover_army.size()
		)


func _split_retreat_roles(
	squad: ArmySquadV2,
	retreat_army: Array,
	withdraw_units: Array,
	cover_units: Array
) -> void:
	for entry: Variant in retreat_army:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var unit: Node3D = entry as Node3D
		var role: ArmySquadV2.UnitRole = squad.get_role(unit)
		if role == ArmySquadV2.UnitRole.RANGED or role == ArmySquadV2.UnitRole.SIEGE:
			withdraw_units.append(unit)
			continue
		if role == ArmySquadV2.UnitRole.HERO or unit is Hero:
			withdraw_units.append(unit)
			continue
		if role == ArmySquadV2.UnitRole.FRONTLINE or role == ArmySquadV2.UnitRole.MELEE_GUARD:
			cover_units.append(unit)
			continue
		## Cavalry / misc withdraw with the safe group.
		withdraw_units.append(unit)


func _estimate_retreat_threat_center(tree: SceneTree, army_center: Vector3) -> Vector3:
	if army_center == Vector3.ZERO:
		return Vector3.ZERO
	var threats: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		army_center,
		MilitaryAIConfig.V2_RETREAT_REINFORCEMENT_RADIUS
	)
	threats = NodeSafety.clean_node_array(threats)
	if threats.is_empty():
		return Vector3.ZERO
	return EnemyArmyCommand.compute_army_center(threats)


func _resolve_retreat_cover_point(
	army_center: Vector3,
	rally_point: Vector3,
	threat_center: Vector3
) -> Vector3:
	if army_center == Vector3.ZERO:
		return rally_point
	var away: Vector3 = rally_point - army_center
	away.y = 0.0
	if away.length_squared() < 0.01 and threat_center != Vector3.ZERO:
		away = army_center - threat_center
		away.y = 0.0
	if away.length_squared() < 0.01:
		return rally_point
	away = away.normalized()
	## Brief cover screen between threat and withdrawal path — not a death stand.
	return army_center + away * MilitaryAIConfig.V2_RETREAT_COVER_OFFSET


func _pull_retreat_stragglers(
	retreat_army: Array,
	army_center: Vector3,
	rally_point: Vector3
) -> void:
	if army_center == Vector3.ZERO and rally_point == Vector3.ZERO:
		return
	var anchor: Vector3 = army_center if army_center != Vector3.ZERO else rally_point
	var stragglers: Array = []
	for entry: Variant in retreat_army:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var unit: Node3D = entry as Node3D
		if (
			EnemyArmyCommand.horizontal_distance(unit.global_position, anchor)
			> MilitaryAIConfig.V2_RETREAT_STRAGGLER_RADIUS
		):
			stragglers.append(unit)
	if stragglers.is_empty():
		return
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_retreat_to(stragglers, rally_point)
	)


func _stage_pending_reinforcements(director: MilitaryDirectorV2) -> void:
	if director == null:
		return
	var pending: Array = director.get_pending_reinforcements_copy()
	pending = NodeSafety.clean_node_array(pending)
	if pending.is_empty():
		return
	var rally_point: Vector3 = director.get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		return
	## Reinforcements assemble safely at base instead of trickling into the field fight.
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_hold_at_rally(
			pending,
			rally_point,
			EnemyUnitMission.Mission.RALLY
		)
	)


func _collect_attack_army(squad: ArmySquadV2) -> Array:
	var units: Array = []
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node:
			continue
		if not EnemyArmyCommand.is_living_combat_unit(entry as Node):
			continue
		units.append(entry)
	return NodeSafety.clean_node_array(units)


func _pick_local_attack_focus(
	tree: SceneTree,
	army_center: Vector3,
	strategic_target: Node3D
) -> Node3D:
	if army_center == Vector3.ZERO:
		return null

	var candidates: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		army_center,
		MilitaryAIConfig.V2_ATTACK_LOCAL_ENGAGE_RADIUS
	)
	candidates = NodeSafety.clean_node_array(candidates)
	if candidates.is_empty():
		return null

	## Prefer the current chase target while it remains nearby and alive.
	if (
		NodeSafety.is_alive_node(_attack_chase_target)
		and candidates.has(_attack_chase_target)
	):
		return _attack_chase_target

	var best: Node3D = null
	var best_priority: int = CombatTargetValidation.ENEMY_ATTACK_PRIORITY_INVALID
	var best_distance: float = INF
	var probe: Node3D = strategic_target
	if probe == null and not candidates.is_empty() and candidates[0] is Node3D:
		probe = candidates[0] as Node3D
	if probe == null:
		return null

	for entry: Variant in candidates:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		## Do not abandon a town-hall commit to chase a lone scout forever.
		if (
			strategic_target is CommandCenter
			and entry is Unit
			and not entry is Hero
			and candidates.size() == 1
		):
			var lone_distance: float = EnemyArmyCommand.horizontal_distance(
				army_center,
				(entry as Node3D).global_position
			)
			if lone_distance > MilitaryAIConfig.V2_ATTACK_CHASE_LEASH * 0.75:
				continue
		var candidate: Node3D = entry as Node3D
		var distance: float = EnemyArmyCommand.horizontal_distance(army_center, candidate.global_position)
		var priority: int = CombatTargetValidation.get_enemy_attack_target_priority(
			probe,
			candidate,
			distance
		)
		if priority >= CombatTargetValidation.ENEMY_ATTACK_PRIORITY_INVALID:
			continue
		if priority < best_priority or (priority == best_priority and distance < best_distance):
			best_priority = priority
			best_distance = distance
			best = candidate

	if best != null:
		_begin_attack_chase(best, army_center)
	return best


func _begin_attack_chase(target: Node3D, army_center: Vector3) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if _attack_chase_target == target and _attack_chase_start_msec > 0:
		return
	_attack_chase_target = target
	_attack_chase_anchor = army_center
	_attack_chase_start_msec = Time.get_ticks_msec()


func _clear_attack_chase() -> void:
	_attack_chase_target = null
	_attack_chase_anchor = Vector3.ZERO
	_attack_chase_start_msec = 0


func _should_continue_local_chase(
	army_center: Vector3,
	local_focus: Node3D,
	strategic_destination: Vector3
) -> bool:
	if not NodeSafety.is_alive_node(local_focus):
		return false
	if _attack_chase_start_msec <= 0:
		_begin_attack_chase(local_focus, army_center)

	var chase_age: float = float(Time.get_ticks_msec() - _attack_chase_start_msec) / 1000.0
	if chase_age >= MilitaryAIConfig.V2_ATTACK_CHASE_DURATION_SECONDS:
		return false

	var from_anchor: Vector3 = (
		_attack_chase_anchor if _attack_chase_anchor != Vector3.ZERO else army_center
	)
	if (
		from_anchor != Vector3.ZERO
		and EnemyArmyCommand.horizontal_distance(from_anchor, local_focus.global_position)
		> MilitaryAIConfig.V2_ATTACK_CHASE_LEASH
	):
		return false

	## Resume the strategic route once the skirmish drifts too far from the objective path.
	if (
		strategic_destination != Vector3.ZERO
		and EnemyArmyCommand.horizontal_distance(local_focus.global_position, strategic_destination)
		> MilitaryAIConfig.V2_ATTACK_CHASE_LEASH * 1.5
		and EnemyArmyCommand.horizontal_distance(army_center, strategic_destination)
		> MilitaryAIConfig.V2_ATTACK_LOCAL_ENGAGE_RADIUS
	):
		return false

	return true


func _clamp_attack_chase_destination(
	strategic_destination: Vector3,
	chase_point: Vector3
) -> Vector3:
	if strategic_destination == Vector3.ZERO:
		return chase_point
	if chase_point == Vector3.ZERO:
		return strategic_destination
	var offset: Vector3 = chase_point - strategic_destination
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= MilitaryAIConfig.V2_ATTACK_CHASE_LEASH or distance <= 0.01:
		return chase_point
	return strategic_destination + offset.normalized() * MilitaryAIConfig.V2_ATTACK_CHASE_LEASH


func _attack_objective_label(focus: Node3D, mission: ArmyMissionV2) -> String:
	if NodeSafety.is_alive_node(focus):
		return String(focus.name)
	if mission != null and not mission.transition_reason.is_empty():
		return mission.transition_reason
	return "AttackObjective"


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
