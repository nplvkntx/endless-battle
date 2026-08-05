class_name MilitaryDirectorV2
extends Node

## Sole strategic decision-maker for the main army under Military AI V2.
## Owns exactly one active state and publishes the current ArmyMissionV2.
## Owns the authoritative army roster and main-squad membership.
## Does not issue unit orders — ArmyCommanderV2 executes the mission.
##
## DEFEND overrides CREEP / ATTACK / ASSEMBLE / RECOVER for emergency base defense.
## Early opening philosophy: ASSEMBLE → CREEP → CREEP → CREEP → ATTACK (≈ hero L3).
## ATTACK preempts CREEP only on lethal / greed / clear strength advantage — never
## merely because the minimum attack squad exists.
## RETREAT pulls the squad home as one group; RECOVER rebuilds before offense resumes.
## After a clear, the director chains to another nearby safe camp when valuable,
## otherwise reassesses via RECOVER or ASSEMBLE (never resumes a stale reservation).
## Mission watchdog cancels stalled CREEP/ATTACK/DEFEND/RETREAT after ~6–8s without
## meaningful progress, refreshes orders once, then falls back safely.

enum State {
	IDLE,
	ASSEMBLE,
	CREEP,
	ATTACK,
	DEFEND,
	RETREAT,
	RECOVER,
}

const TICK_SECONDS: float = 1.0
const V2_CREEP_PLAYER_THREAT_RADIUS: float = 28.0
const V2_CREEP_PLAYER_THREAT_STRENGTH_RATIO: float = 1.10
const V2_CREEP_MEDIUM_POWER_THRESHOLD: int = 170

var _state: State = State.IDLE
var _mission: ArmyMissionV2 = null
var _last_transition_reason: String = "match start"
var _match_start_msec: int = 0
var _tick_timer: float = 0.0
var _commander: ArmyCommanderV2 = null

## Authoritative living AI military roster (validated refs only).
var _roster: Array = []
## Newly trained / discovered units waiting for a safe admission window.
var _pending_reinforcements: Array = []
## Single main squad. Commander receives this; it must not recruit independently.
var _main_squad: ArmySquadV2 = ArmySquadV2.new()
## instance_id -> true for units with lifecycle hooks connected.
var _lifecycle_bound: Dictionary = {}
var _assemble_rally_point: Vector3 = Vector3.ZERO
var _assemble_rally_base_id: int = 0
var _reserved_creep_camp_id: int = 0
var _cleared_creep_camp_ids: Dictionary = {}
var _defend_clear_timer: float = 0.0
var _defend_active: bool = false
var _defend_reason: StringName = &""
var _pre_defend_state: State = State.IDLE
var _attack_start_strength: float = 0.0
var _attack_start_frontline_count: int = 0
var _attack_is_lethal: bool = false
var _creep_start_strength: float = 0.0
var _creep_start_frontline_count: int = 0
var _retreat_elapsed: float = 0.0
var _recover_elapsed: float = 0.0
var _state_entered_msec: int = 0
var _post_retreat_attack_cooldown: float = 0.0
var _designated_recovery_point: Vector3 = Vector3.ZERO

## Mission watchdog / truthful F3 diagnostics.
var _watchdog_timer: float = 0.0
var _watchdog_diag_timer: float = 0.0
var _watchdog_order_refreshed: bool = false
var _watchdog_status: String = "idle"
var _watchdog_recent_combat: bool = false
var _watchdog_living_members: int = 0
var _watchdog_distance: float = -1.0
var _watchdog_active_order: String = "-"
var _watchdog_last_diag_signature: String = ""
var _watchdog_objective_valid: bool = true
## instance_id of the Node whose tree_exiting clears the active mission target.
var _mission_target_exit_bound_id: int = 0


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_tick_timer = TICK_SECONDS * 0.25
	_commander = get_parent().get_node_or_null("ArmyCommanderV2") as ArmyCommanderV2
	reset_match_state()
	set_process(MilitaryAIConfig.is_v2_enabled())
	_publish_perf_status()


func reset_match_state() -> void:
	_state = State.IDLE
	_last_transition_reason = "match start"
	_mission = ArmyMissionV2.new(
		ArmyMissionV2.MissionType.IDLE,
		Vector3.ZERO,
		null,
		0,
		_last_transition_reason
	)
	_tick_timer = TICK_SECONDS * 0.25
	_clear_roster_state()
	_publish_perf_status()


func _clear_roster_state() -> void:
	_roster.clear()
	_pending_reinforcements.clear()
	_main_squad.clear()
	_lifecycle_bound.clear()
	_assemble_rally_point = Vector3.ZERO
	_assemble_rally_base_id = 0
	_reserved_creep_camp_id = 0
	_cleared_creep_camp_ids.clear()
	_defend_clear_timer = 0.0
	_defend_active = false
	_defend_reason = &""
	_pre_defend_state = State.IDLE
	_attack_start_strength = 0.0
	_attack_start_frontline_count = 0
	_attack_is_lethal = false
	_creep_start_strength = 0.0
	_creep_start_frontline_count = 0
	_retreat_elapsed = 0.0
	_recover_elapsed = 0.0
	_state_entered_msec = Time.get_ticks_msec()
	_post_retreat_attack_cooldown = 0.0
	_designated_recovery_point = Vector3.ZERO
	_unbind_mission_target_exit()
	_reset_watchdog_state("match reset")


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		set_process(false)
		return

	_tick_timer += delta
	if _tick_timer < TICK_SECONDS:
		return

	_tick_timer = 0.0
	_refresh_army_roster()
	_tick_mission_watchdog(TICK_SECONDS)
	_evaluate_strategy()
	_publish_perf_status()
	PerfCounters.record_ai_decision_update()


func _evaluate_strategy() -> void:
	if _mission == null:
		_transition_to(State.ASSEMBLE, "initialize assemble mission")
		return

	_mission.sanitize_target_object()
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	if _post_retreat_attack_cooldown > 0.0:
		_post_retreat_attack_cooldown = maxf(
			0.0,
			_post_retreat_attack_cooldown - TICK_SECONDS
		)

	var rally_point: Vector3 = get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		_transition_to(State.IDLE, "awaiting safe rally point")
		return

	if _designated_recovery_point == Vector3.ZERO:
		_designated_recovery_point = rally_point

	## DEFEND always wins over CREEP / ATTACK / ASSEMBLE / RECOVER.
	if _evaluate_defend_strategy(tree, rally_point):
		return

	## Finish an in-progress retreat before resuming offense.
	if _state == State.RETREAT:
		_evaluate_retreat_strategy(tree, rally_point)
		return

	## Losing fights abort ATTACK/CREEP into RETREAT (emergency, bypasses commit).
	if _maybe_begin_retreat(tree, rally_point):
		return

	## Rebuild near base before offense; never stall forever.
	if _state == State.RECOVER:
		_evaluate_recover_strategy(tree, rally_point)
		return

	## ATTACK preempts CREEP only on lethal/greed/clear advantage (or mid-ATTACK).
	## Early openings prefer camp chaining until ~hero level 3.
	var interrupt_creep_for_attack: bool = _should_interrupt_creeping_for_attack(
		tree,
		rally_point
	)
	var prefer_early_creep: bool = _should_prefer_early_creeping(tree, rally_point)
	if _state == State.ATTACK or interrupt_creep_for_attack or not prefer_early_creep:
		if _evaluate_attack_strategy(tree, rally_point):
			return
		if _evaluate_creep_strategy(tree, rally_point):
			return
	else:
		if _evaluate_creep_strategy(tree, rally_point):
			return
		if _evaluate_attack_strategy(tree, rally_point):
			return

	_transition_to(State.ASSEMBLE, "gathering squad at base", rally_point)


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return state_to_string(_state)


static func state_to_string(state: State) -> String:
	match state:
		State.IDLE:
			return "IDLE"
		State.ASSEMBLE:
			return "ASSEMBLE"
		State.CREEP:
			return "CREEP"
		State.ATTACK:
			return "ATTACK"
		State.DEFEND:
			return "DEFEND"
		State.RETREAT:
			return "RETREAT"
		State.RECOVER:
			return "RECOVER"
		_:
			return "UNKNOWN"


func get_mission() -> ArmyMissionV2:
	return _mission


func get_last_transition_reason() -> String:
	return _last_transition_reason


func get_match_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func get_main_squad() -> ArmySquadV2:
	return _main_squad


func get_roster_copy() -> Array:
	return _roster.duplicate()


func get_pending_reinforcements_copy() -> Array:
	return _pending_reinforcements.duplicate()


func get_military_unit_count() -> int:
	return maxi(0, _main_squad.get_size() - (1 if _main_squad.hero_present else 0))


func is_creep_ready() -> bool:
	return _main_squad.hero_present and get_military_unit_count() >= MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS


func is_attack_ready() -> bool:
	return (
		_main_squad.hero_present
		and get_military_unit_count() >= MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS
	)


## Compatibility alias for older call sites / verify helpers.
func is_attack_ready_placeholder() -> bool:
	return is_attack_ready()


func is_lethal_attack_ready() -> bool:
	return (
		_main_squad.hero_present
		and get_military_unit_count() >= MilitaryAIConfig.V2_ATTACK_LETHAL_MIN_MILITARY_UNITS
	)


func is_attack_lethal_active() -> bool:
	return _attack_is_lethal


func get_assemble_rally_point() -> Vector3:
	var tree: SceneTree = get_tree()
	if tree == null:
		return Vector3.ZERO

	var base: CommandCenter = _find_primary_enemy_base(tree)
	if base == null:
		return Vector3.ZERO

	var base_id: int = base.get_instance_id()
	if _assemble_rally_point != Vector3.ZERO and _assemble_rally_base_id == base_id:
		if _is_safe_assemble_rally_candidate(tree, base, _assemble_rally_point):
			return _assemble_rally_point

	_assemble_rally_point = _find_best_assemble_rally_point(tree, base)
	_assemble_rally_base_id = base_id
	return _assemble_rally_point


func get_assemble_forward_hint() -> Vector3:
	var tree: SceneTree = get_tree()
	if tree == null:
		return Vector3.ZERO
	var base: CommandCenter = _find_primary_enemy_base(tree)
	if base == null:
		return Vector3.ZERO
	var rally_point: Vector3 = get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		return Vector3.ZERO
	var forward: Vector3 = rally_point - base.global_position
	forward.y = 0.0
	if forward.length_squared() <= 0.01:
		return Vector3.ZERO
	return forward.normalized()


func get_reserved_creep_camp_id() -> int:
	return _reserved_creep_camp_id


func has_reserved_creep_camp() -> bool:
	return _reserved_creep_camp_id != 0


func get_cleared_creep_camp_count() -> int:
	return _cleared_creep_camp_ids.size()


func get_defend_reason() -> StringName:
	return _defend_reason


func is_defend_active() -> bool:
	return _defend_active


func get_designated_recovery_point() -> Vector3:
	if _designated_recovery_point != Vector3.ZERO:
		return _designated_recovery_point
	return get_assemble_rally_point()


## Strategic API for future behavior / tests. Commander must not call this for self-decisions.
func request_state(
	next_state: State,
	reason: String,
	target_position: Vector3 = Vector3.ZERO,
	target_object: Variant = null,
	priority: int = 0
) -> bool:
	if not MilitaryAIConfig.is_v2_enabled():
		return false
	return _transition_to(next_state, reason, target_position, target_object, priority)


func _transition_to(
	next_state: State,
	reason: String,
	target_position: Vector3 = Vector3.ZERO,
	target_object: Variant = null,
	priority: int = 0
) -> bool:
	## Sanitize before any typed comparison — freed refs must not enter Node3D params.
	if _mission != null:
		_mission.sanitize_target_object()
	var safe_target: Node3D = _sanitize_incoming_target(target_object)
	var previous_target_ref: Variant = null
	if _mission != null:
		previous_target_ref = _mission.target_object

	var previous_state: State = _state
	var next_mission_type: ArmyMissionV2.MissionType = _state_to_mission_type(next_state)
	if _state == next_state and _mission != null and _mission.mission_type == next_mission_type:
		var same_target_object: bool = _same_target_object(previous_target_ref, safe_target)
		var dest_delta: float = EnemyArmyCommand.horizontal_distance(
			_mission.target_position,
			target_position
		)
		var position_tolerance: float = (
			MilitaryAIConfig.V2_DEFEND_DEST_EQUIVALENCE
			if next_state == State.DEFEND
			else 0.01
		)
		var same_target_position: bool = (
			_mission.target_position == target_position
			or dest_delta <= position_tolerance
		)
		var same_priority: bool = _mission.priority == priority
		if same_target_object and same_target_position and same_priority:
			if reason != _last_transition_reason and not reason.is_empty():
				_last_transition_reason = reason
				_mission.transition_reason = reason
			## Keep defend intercept gently tracking without rebuilding the mission.
			if next_state == State.DEFEND and dest_delta > 0.01:
				_mission.target_position = target_position
			return false
		## Same living objective with a drifted position — update in place so the
		## watchdog progress clock is not reset every strategic tick.
		if same_target_object and same_priority and NodeSafety.is_alive_node(safe_target):
			_mission.target_position = target_position
			_mission.set_target_object(safe_target)
			_bind_mission_target_exit(safe_target)
			if reason != _last_transition_reason and not reason.is_empty():
				_last_transition_reason = reason
				_mission.transition_reason = reason
			if next_state == State.CREEP:
				_reserved_creep_camp_id = safe_target.get_instance_id()
			return false
		## DEFEND with no living focus (or null↔null) and small destination drift:
		## never emit DEFEND -> DEFEND or reset the watchdog.
		if (
			next_state == State.DEFEND
			and same_priority
			and dest_delta <= MilitaryAIConfig.V2_DEFEND_DEST_EQUIVALENCE * 4.0
		):
			_mission.target_position = target_position
			if NodeSafety.is_alive_node(safe_target):
				_mission.set_target_object(safe_target)
				_bind_mission_target_exit(safe_target)
			if reason != _last_transition_reason and not reason.is_empty():
				_last_transition_reason = reason
				_mission.transition_reason = reason
			return false
		if next_state == State.CREEP and not NodeSafety.is_alive_node(safe_target):
			return false
		if next_state == State.CREEP:
			_reserved_creep_camp_id = safe_target.get_instance_id()
		elif previous_state == State.CREEP:
			_release_creep_reservation()
			if EnemyArmyCommand.is_creeping_executable_active():
				EnemyArmyCommand.clear_executable_mission("creep state updated")
		_last_transition_reason = reason if not reason.is_empty() else "unspecified"
		_mission = ArmyMissionV2.new(
			next_mission_type,
			target_position,
			safe_target,
			priority,
			_last_transition_reason
		)
		_bind_mission_target_exit(safe_target)
		_watchdog_order_refreshed = false
		_watchdog_distance = -1.0
		_log_mission_transition(
			previous_state,
			next_state,
			_last_transition_reason,
			target_position,
			safe_target
		)
		_sync_legacy_authority_for_state(next_state, _last_transition_reason)
		_publish_perf_status()
		return true

	if _mission != null and _state != next_state:
		_mission.mark_cancelled("superseded: %s" % reason)

	if previous_state == State.CREEP and next_state != State.CREEP:
		_release_creep_reservation()
		if EnemyArmyCommand.is_creeping_executable_active():
			EnemyArmyCommand.clear_executable_mission("creep state ended")

	if previous_state == State.DEFEND and next_state != State.DEFEND:
		_deactivate_v2_defend("left defend: %s" % reason)

	if previous_state == State.ATTACK and next_state != State.ATTACK:
		_clear_attack_tracking()
		if EnemyArmyCommand.get_executable_mission() in [
			EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER,
			EnemyArmyCommand.ExecutableMission.LETHAL_PUSH,
		]:
			EnemyArmyCommand.clear_executable_mission("attack state ended")

	if previous_state == State.RETREAT and next_state != State.RETREAT:
		_retreat_elapsed = 0.0
		if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.RETREATING:
			EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.RETREATING)
		## Hysteresis: block immediate ATTACK re-entry after a retreat.
		_post_retreat_attack_cooldown = MilitaryAIConfig.V2_POST_RETREAT_ATTACK_COOLDOWN_SECONDS

	if previous_state == State.RECOVER and next_state != State.RECOVER:
		_recover_elapsed = 0.0

	if previous_state == State.CREEP and next_state != State.CREEP:
		_creep_start_strength = 0.0
		_creep_start_frontline_count = 0

	_state = next_state
	_last_transition_reason = reason if not reason.is_empty() else "unspecified"
	_mission = ArmyMissionV2.new(
		next_mission_type,
		target_position,
		safe_target,
		priority,
		_last_transition_reason
	)
	_bind_mission_target_exit(safe_target)
	if previous_state != next_state:
		_state_entered_msec = Time.get_ticks_msec()
		_reset_watchdog_state("entered %s" % state_to_string(next_state))
	elif next_state in [State.CREEP, State.ATTACK, State.DEFEND, State.RETREAT]:
		## Objective/target refresh mid-state still counts as a new progress baseline.
		_watchdog_order_refreshed = false
		_watchdog_distance = -1.0
	if next_state == State.CREEP and NodeSafety.is_alive_node(safe_target):
		_reserved_creep_camp_id = safe_target.get_instance_id()
	elif next_state != State.CREEP:
		_release_creep_reservation()

	if next_state == State.DEFEND:
		_defend_active = true
	elif previous_state == State.DEFEND:
		_defend_active = false

	if next_state == State.ATTACK and previous_state != State.ATTACK:
		_begin_attack_tracking(get_tree())
	elif next_state == State.ATTACK:
		## Keep lethal flag sticky while the attack continues.
		pass

	if next_state == State.CREEP and previous_state != State.CREEP:
		_begin_creep_fight_tracking()

	if next_state == State.RETREAT and previous_state != State.RETREAT:
		_retreat_elapsed = 0.0
		if target_position != Vector3.ZERO:
			_designated_recovery_point = target_position

	if next_state == State.RECOVER and previous_state != State.RECOVER:
		_recover_elapsed = 0.0
		_admit_pending_reinforcements()
		if target_position != Vector3.ZERO:
			_designated_recovery_point = target_position
		elif _designated_recovery_point == Vector3.ZERO:
			_designated_recovery_point = get_assemble_rally_point()

	## Safe admission window: join reinforcements on state transitions into idle/assemble/recover.
	if previous_state != next_state and _can_admit_reinforcements():
		_admit_pending_reinforcements()

	_log_mission_transition(
		previous_state,
		next_state,
		_last_transition_reason,
		target_position,
		safe_target
	)
	_sync_legacy_authority_for_state(next_state, _last_transition_reason)
	_publish_perf_status()
	return true


func _log_mission_transition(
	previous_state: State,
	next_state: State,
	reason: String,
	destination: Vector3,
	target_object: Variant
) -> void:
	var dest_text: String = "-"
	if NodeSafety.is_alive_node(target_object) and target_object is Node3D:
		var pos: Vector3 = (target_object as Node3D).global_position
		dest_text = "(%.1f, %.1f)" % [pos.x, pos.z]
	elif destination != Vector3.ZERO:
		dest_text = "(%.1f, %.1f)" % [destination.x, destination.z]
	EnemyAIDebug.log_once(
		"v2_mission_%s_%s_%s" % [
			state_to_string(previous_state),
			state_to_string(next_state),
			dest_text,
		],
		"[AI Mission] %s -> %s | reason=%s | dest=%s" % [
			state_to_string(previous_state),
			state_to_string(next_state),
			reason if not reason.is_empty() else "unspecified",
			dest_text,
		]
	)


func _sync_legacy_authority_for_state(state: State, reason: String) -> void:
	match state:
		State.CREEP:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.CREEPING,
				EnemyArmyCommand.StrategicState.CREEPING,
				reason
			)
		State.ATTACK:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.ATTACKING,
				EnemyArmyCommand.StrategicState.ATTACKING,
				reason
			)
		State.DEFEND:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.DEFENDING,
				EnemyArmyCommand.StrategicState.DEFENDING,
				reason
			)
		State.RETREAT:
			EnemyArmyCommand.prepare_v2_execution(
				EnemyArmyCommand.ArmyMode.RETREATING,
				EnemyArmyCommand.StrategicState.RETREATING,
				reason
			)
		State.RECOVER:
			EnemyArmyCommand.force_set_strategic_state_for_v2(
				EnemyArmyCommand.StrategicState.RECOVERING,
				reason
			)
		State.ASSEMBLE, State.IDLE:
			EnemyArmyCommand.force_set_strategic_state_for_v2(
				EnemyArmyCommand.StrategicState.ECONOMY,
				reason
			)
		_:
			pass


func _begin_attack_tracking(tree: SceneTree) -> void:
	var units: Array = _get_attack_squad_units()
	var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	_attack_start_strength = EnemyArmyCommand.estimate_combat_strength(units)
	_attack_start_frontline_count = _count_frontline_units(units)
	if tree != null and not units.is_empty():
		EnemyArmyCommand.begin_fight_tracking(units, center if center != Vector3.ZERO else Vector3.ZERO)


func _begin_creep_fight_tracking() -> void:
	var units: Array = _get_creep_squad_units()
	_creep_start_strength = EnemyArmyCommand.estimate_combat_strength(units)
	_creep_start_frontline_count = _count_frontline_units(units)


func _clear_attack_tracking() -> void:
	_attack_start_strength = 0.0
	_attack_start_frontline_count = 0
	_attack_is_lethal = false


func _count_frontline_units(units: Array) -> int:
	var count: int = 0
	for entry: Variant in units:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		if entry is Hero:
			continue
		var role: ArmySquadV2.UnitRole = _main_squad.get_role(entry as Node3D)
		if role == ArmySquadV2.UnitRole.FRONTLINE or role == ArmySquadV2.UnitRole.MELEE_GUARD:
			count += 1
	return count


func _state_commit_elapsed_seconds() -> float:
	if _state_entered_msec <= 0:
		return INF
	return float(Time.get_ticks_msec() - _state_entered_msec) / 1000.0


func _has_met_state_commitment() -> bool:
	return _state_commit_elapsed_seconds() >= MilitaryAIConfig.V2_STATE_COMMIT_SECONDS


func _state_to_mission_type(state: State) -> ArmyMissionV2.MissionType:
	match state:
		State.IDLE:
			return ArmyMissionV2.MissionType.IDLE
		State.ASSEMBLE:
			return ArmyMissionV2.MissionType.ASSEMBLE
		State.CREEP:
			return ArmyMissionV2.MissionType.CREEP
		State.ATTACK:
			return ArmyMissionV2.MissionType.ATTACK
		State.DEFEND:
			return ArmyMissionV2.MissionType.DEFEND
		State.RETREAT:
			return ArmyMissionV2.MissionType.RETREAT
		State.RECOVER:
			return ArmyMissionV2.MissionType.RECOVER
		_:
			return ArmyMissionV2.MissionType.NONE


## True while assembling / recovering / idle — never mid-fight reshuffles.
func _can_admit_reinforcements() -> bool:
	return _state in [State.IDLE, State.ASSEMBLE, State.RECOVER]


func _refresh_army_roster() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	## Purge dead/freed immediately from squad + pending, then rescan living military.
	_main_squad.sanitize()
	_sanitize_pending_reinforcements()

	var living: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	var next_roster: Array = []
	var seen_ids: Dictionary = {}

	for entry: Variant in living:
		if not ArmySquadV2.is_roster_eligible(entry as Node):
			continue
		var unit: Node = entry as Node
		var unit_id: int = unit.get_instance_id()
		if seen_ids.has(unit_id):
			continue
		seen_ids[unit_id] = true
		next_roster.append(unit)
		_bind_unit_lifecycle(unit)

		if _main_squad.has_member(unit):
			continue
		if _pending_contains(unit):
			continue
		## Newly trained / discovered living units wait for a safe join window.
		## Never send them alone across the map as a solo field group.
		_pending_reinforcements.append(unit)

	_roster = next_roster

	## Drop squad members that are no longer on the living roster.
	for member_variant: Variant in _main_squad.get_members_copy():
		if not NodeSafety.is_alive_node(member_variant):
			_main_squad.remove_member(member_variant as Node)
			continue
		var member: Node = member_variant as Node
		if not seen_ids.has(member.get_instance_id()):
			_main_squad.remove_member(member)

	if _can_admit_reinforcements():
		_admit_pending_reinforcements()

	_main_squad.recompute_metrics()


func _admit_pending_reinforcements() -> void:
	if _pending_reinforcements.is_empty():
		return

	var remaining: Array = []
	for entry: Variant in _pending_reinforcements:
		if not ArmySquadV2.is_roster_eligible(entry as Node):
			continue
		var unit: Node = entry as Node
		if _main_squad.has_member(unit):
			continue
		var role: ArmySquadV2.UnitRole = ArmySquadV2.classify_role(unit)
		if not _main_squad.try_add_member(unit, role):
			remaining.append(unit)
			continue
		_bind_unit_lifecycle(unit)
	_pending_reinforcements = remaining


func _sanitize_pending_reinforcements() -> void:
	var cleaned: Array = []
	var seen_ids: Dictionary = {}
	for entry: Variant in _pending_reinforcements:
		if not ArmySquadV2.is_roster_eligible(entry as Node):
			continue
		var unit: Node = entry as Node
		var unit_id: int = unit.get_instance_id()
		if seen_ids.has(unit_id):
			continue
		if _main_squad.has_member(unit):
			continue
		seen_ids[unit_id] = true
		cleaned.append(unit)
	_pending_reinforcements = cleaned


func _pending_contains(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var unit_id: int = unit.get_instance_id()
	for entry: Variant in _pending_reinforcements:
		if NodeSafety.is_alive_node(entry) and (entry as Node).get_instance_id() == unit_id:
			return true
	return false


func _bind_unit_lifecycle(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var unit_id: int = unit.get_instance_id()
	if _lifecycle_bound.has(unit_id):
		return
	_lifecycle_bound[unit_id] = true

	if unit.has_signal("died") and not unit.died.is_connected(_on_roster_unit_died):
		unit.died.connect(_on_roster_unit_died, CONNECT_ONE_SHOT)
	if not unit.tree_exiting.is_connected(_on_roster_unit_tree_exiting):
		unit.tree_exiting.connect(_on_roster_unit_tree_exiting.bind(unit_id), CONNECT_ONE_SHOT)


func _on_roster_unit_died(unit: Unit) -> void:
	_remove_unit_everywhere(unit)


func _on_roster_unit_tree_exiting(unit_id: int) -> void:
	_remove_unit_everywhere_by_id(unit_id)


func _remove_unit_everywhere(unit: Node) -> void:
	if unit == null:
		return
	var unit_id: int = 0
	if is_instance_valid(unit):
		unit_id = unit.get_instance_id()
	_main_squad.remove_member(unit)
	_remove_from_array_by_ref(_roster, unit)
	_remove_from_array_by_ref(_pending_reinforcements, unit)
	if unit_id != 0:
		_lifecycle_bound.erase(unit_id)
		_main_squad.remove_by_instance_id(unit_id)
	_main_squad.recompute_metrics()
	_publish_perf_status()


func _remove_unit_everywhere_by_id(unit_id: int) -> void:
	if unit_id == 0:
		return
	_main_squad.remove_by_instance_id(unit_id)
	_remove_from_array_by_id(_roster, unit_id)
	_remove_from_array_by_id(_pending_reinforcements, unit_id)
	_lifecycle_bound.erase(unit_id)
	_main_squad.recompute_metrics()
	_publish_perf_status()


func _remove_from_array_by_ref(arr: Array, unit: Node) -> void:
	for i: int in range(arr.size() - 1, -1, -1):
		var entry: Variant = arr[i]
		if entry == null or not is_instance_valid(entry) or entry == unit:
			arr.remove_at(i)


func _remove_from_array_by_id(arr: Array, unit_id: int) -> void:
	for i: int in range(arr.size() - 1, -1, -1):
		var entry: Variant = arr[i]
		if entry == null or not is_instance_valid(entry) or (entry as Node).get_instance_id() == unit_id:
			arr.remove_at(i)


## Test helper: run one roster refresh without enabling the feature toggle.
func debug_refresh_roster_for_tests() -> void:
	_refresh_army_roster()


## Test helper: admit pending while pretending we are in a safe state.
## Uses the lightweight alive/type gate so stub nodes can exercise membership.
func debug_admit_pending_for_tests() -> void:
	var remaining: Array = []
	for entry: Variant in _pending_reinforcements:
		if not NodeSafety.is_alive_node(entry):
			continue
		var unit: Node = entry as Node
		if not unit.is_inside_tree():
			continue
		if unit is Worker or unit is Building or unit is NeutralCreep:
			continue
		if _main_squad.has_member(unit):
			continue
		var role: ArmySquadV2.UnitRole = ArmySquadV2.classify_role(unit)
		if not _main_squad.try_add_member(unit, role):
			remaining.append(unit)
			continue
		_bind_unit_lifecycle(unit)
	_pending_reinforcements = remaining
	_main_squad.recompute_metrics()


## Test helper: enqueue a living unit as a pending reinforcement (director-owned path).
func debug_enqueue_pending_for_tests(unit: Node) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	if unit is Worker or unit is Building or unit is NeutralCreep:
		return false
	if _main_squad.has_member(unit) or _pending_contains(unit):
		return false
	_pending_reinforcements.append(unit)
	_bind_unit_lifecycle(unit)
	return true


func debug_score_assemble_rally_candidate(candidate: Vector3) -> float:
	var tree: SceneTree = get_tree()
	if tree == null:
		return -INF
	var base: CommandCenter = _find_primary_enemy_base(tree)
	if base == null:
		return -INF
	return _score_assemble_rally_candidate(tree, base, candidate)


func _resolve_creep_manager() -> EnemyCreepManager:
	if get_parent() == null:
		return null
	return get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager


func _evaluate_defend_strategy(tree: SceneTree, rally_point: Vector3) -> bool:
	var threat: Dictionary = _resolve_v2_defense_threat(tree)
	if threat.get("threatened", false):
		_defend_clear_timer = 0.0
		var intercept: Vector3 = EnemyArmyCommand.resolve_defense_intercept_position(
			tree,
			threat,
			rally_point
		)
		if intercept == Vector3.ZERO:
			intercept = rally_point
		var focus: Node3D = _pick_defend_focus_target(tree, intercept, rally_point)
		var reason_name: StringName = threat.get("reason", &"base") as StringName
		_defend_reason = reason_name
		var reason_text: String = _format_defend_reason(reason_name, focus)
		if _state != State.DEFEND:
			_pre_defend_state = _state
			EnemyArmyCommand.prepare_defense_recall(tree)
			EnemyArmyCommand.activate_emergency_defense(threat)
			_defend_active = true
			_transition_to(
				State.DEFEND,
				reason_text,
				intercept,
				focus,
				100
			)
		else:
			## Already defending — refresh threat data without restarting the mission.
			EnemyArmyCommand.update_emergency_defense_threat(threat)
			_defend_active = true
			_soft_update_defend_mission(intercept, focus, reason_text, threat)
		return true

	if _state != State.DEFEND and not _defend_active:
		return false

	_defend_clear_timer += TICK_SECONDS
	if _defend_clear_timer < MilitaryAIConfig.V2_DEFEND_THREAT_CLEAR_SECONDS:
		## Hold DEFEND while the clear window ticks; keep F3 reason visible.
		if _mission != null and _mission.mission_type == ArmyMissionV2.MissionType.DEFEND:
			_mission.transition_reason = "holding clear: %s" % String(_defend_reason)
			_last_transition_reason = _mission.transition_reason
			_publish_perf_status()
		return true

	_exit_defend_after_clear(tree, rally_point)
	return true


## Update defend objective in place when the strategic state is already DEFEND.
## Full transitions (and log spam / watchdog resets) only occur on meaningful change.
func _soft_update_defend_mission(
	intercept: Vector3,
	focus: Node3D,
	reason_text: String,
	_threat: Dictionary
) -> void:
	if _mission == null or _mission.mission_type != ArmyMissionV2.MissionType.DEFEND:
		_transition_to(State.DEFEND, reason_text, intercept, focus, 100)
		return

	var previous_focus: Node3D = _mission.get_alive_target_object()
	var same_focus: bool = _same_target_object(previous_focus, focus)
	## Sticky focus: keep the living defended target unless it left the leash.
	if (
		not same_focus
		and NodeSafety.is_alive_node(previous_focus)
		and previous_focus is Node3D
	):
		var prev_dist: float = EnemyArmyCommand.horizontal_distance(
			intercept if intercept != Vector3.ZERO else _mission.target_position,
			(previous_focus as Node3D).global_position
		)
		if prev_dist <= MilitaryAIConfig.V2_DEFEND_FOCUS_STICKY_RADIUS:
			focus = previous_focus as Node3D
			same_focus = true
			reason_text = _format_defend_reason(_defend_reason, focus)

	var dest_delta: float = EnemyArmyCommand.horizontal_distance(
		_mission.target_position,
		intercept
	)

	## Protected structure / threat identity — only force a restart when focus flips
	## to a different living node or destination jumps far from the current intercept.
	var needs_hard_transition: bool = (
		(not same_focus and NodeSafety.is_alive_node(focus) and NodeSafety.is_alive_node(previous_focus))
		or dest_delta > MilitaryAIConfig.V2_DEFEND_DEST_EQUIVALENCE * 4.0
	)
	if needs_hard_transition:
		_transition_to(State.DEFEND, reason_text, intercept, focus, 100)
		return

	## Soft hold: update intercept / focus / reason without clearing orders or watchdog.
	if dest_delta > MilitaryAIConfig.V2_DEFEND_DEST_EQUIVALENCE:
		_mission.target_position = intercept
	if NodeSafety.is_alive_node(focus):
		_mission.set_target_object(focus)
		_bind_mission_target_exit(focus)
	if not reason_text.is_empty() and reason_text != _last_transition_reason:
		_last_transition_reason = reason_text
		_mission.transition_reason = reason_text
	_publish_perf_status()


func _resolve_v2_defense_threat(tree: SceneTree) -> Dictionary:
	var emergency: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(tree)
	if emergency.get("threatened", false):
		return emergency

	## Workers being killed / harassed near base are an emergency for V2 even when
	## the shared emergency evaluator only flags workers attacking buildings.
	var standard: Dictionary = EnemyArmyCommand.evaluate_defense_threat(tree)
	if not standard.get("threatened", false):
		return {"threatened": false}

	var reason: StringName = standard.get("reason", &"") as StringName
	if reason == &"workers" or reason == &"buildings" or reason == &"base":
		return standard
	return {"threatened": false}


func _pick_defend_focus_target(
	tree: SceneTree,
	intercept: Vector3,
	rally_point: Vector3
) -> Node3D:
	var search_origin: Vector3 = intercept if intercept != Vector3.ZERO else rally_point
	if search_origin == Vector3.ZERO:
		return null

	## Prefer keeping the current living focus to avoid DEFEND objective thrash.
	var sticky: Node3D = null
	if _mission != null and _mission.mission_type == ArmyMissionV2.MissionType.DEFEND:
		sticky = _mission.get_alive_target_object()
	if (
		NodeSafety.is_alive_node(sticky)
		and sticky is Node3D
		and not (sticky is Building)
		and EnemyArmyCommand.horizontal_distance(search_origin, sticky.global_position)
			<= MilitaryAIConfig.V2_DEFEND_FOCUS_STICKY_RADIUS
	):
		return sticky

	var candidates: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		search_origin,
		MilitaryAIConfig.V2_DEFEND_THREAT_SEARCH_RANGE
	)
	## Always consider whoever is actively hitting the Town Hall, even if slightly farther.
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if not node is CommandCenter or not NodeSafety.is_alive_node(node):
			continue
		var attacker: Node = CombatKillTracker.get_attacker(node)
		if (
			NodeSafety.is_alive_node(attacker)
			and attacker is Node3D
			and not CombatTargetValidation.is_enemy_faction(attacker)
			and EnemyArmyCommand.is_combat_unit(attacker)
		):
			if not candidates.has(attacker):
				candidates.append(attacker)

	var best: Node3D = null
	var best_priority: int = CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_INVALID
	var best_distance: float = INF
	var probe: Node3D = _find_primary_enemy_base(tree)
	if probe == null and not _main_squad.get_members_copy().is_empty():
		var first: Variant = _main_squad.get_members_copy()[0]
		if first is Node3D:
			probe = first as Node3D
	if probe == null:
		return null

	for entry: Variant in candidates:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var candidate: Node3D = entry as Node3D
		if candidate is Building:
			continue
		var distance: float = EnemyArmyCommand.horizontal_distance(search_origin, candidate.global_position)
		var priority: int = CombatTargetValidation.get_enemy_defense_target_priority(
			probe,
			candidate,
			distance
		)
		if priority >= CombatTargetValidation.ENEMY_DEFENSE_PRIORITY_INVALID:
			continue
		if priority < best_priority or (priority == best_priority and distance < best_distance):
			best_priority = priority
			best_distance = distance
			best = candidate
	return best


func _format_defend_reason(reason: StringName, focus: Node3D) -> String:
	var label: String = String(reason)
	if label.is_empty():
		label = "base"
	if NodeSafety.is_alive_node(focus):
		return "defend %s → %s" % [label, focus.name]
	return "defend %s" % label


func _exit_defend_after_clear(tree: SceneTree, rally_point: Vector3) -> void:
	if _mission != null and _mission.mission_type == ArmyMissionV2.MissionType.DEFEND:
		_mission.completion_condition = ArmyMissionV2.CompletionCondition.THREAT_CLEARED

	_deactivate_v2_defend("threat cleared")
	_defend_clear_timer = 0.0
	_defend_reason = &""

	## Never resume a stale creep/attack reservation — reassess from a safe state.
	_release_creep_reservation()
	if EnemyArmyCommand.is_creeping_executable_active():
		EnemyArmyCommand.clear_executable_mission("defense cleared")
	EnemyArmyCommand.clear_executable_mission("defense cleared")

	if EnemyArmyCommand.get_army_mode() in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]:
		EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)
		if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.INTERCEPTING:
			EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.INTERCEPTING)

	if _is_main_squad_damaged():
		_transition_to(State.RECOVER, "defense cleared, recovering damage", rally_point)
		return
	if _is_main_squad_scattered(rally_point):
		_transition_to(State.ASSEMBLE, "defense cleared, reassembling scattered squad", rally_point)
		return
	_transition_to(State.ASSEMBLE, "defense cleared, reassess strategy", rally_point)


func _deactivate_v2_defend(_reason: String) -> void:
	if EnemyArmyCommand.is_emergency_defense_active():
		EnemyArmyCommand.deactivate_emergency_defense()
	_defend_active = false


func _is_main_squad_damaged() -> bool:
	var living: int = 0
	var damaged: int = 0
	for entry: Variant in _main_squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry):
			continue
		living += 1
		if EnemyArmyCommand.get_health_ratio(entry as Node) < MilitaryAIConfig.V2_DEFEND_DAMAGED_HP_RATIO:
			damaged += 1
	if living <= 0:
		return false
	return float(damaged) / float(living) >= 0.35


func _is_main_squad_scattered(rally_point: Vector3) -> bool:
	var units: Array = []
	for entry: Variant in _main_squad.get_members_copy():
		if NodeSafety.is_alive_node(entry) and entry is Node3D:
			units.append(entry)
	units = NodeSafety.clean_node_array(units)
	if units.size() < 3:
		return false
	var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	if center == Vector3.ZERO:
		center = rally_point
	if center == Vector3.ZERO:
		return false
	var near_count: int = EnemyArmyCommand.filter_units_near_rally(
		units,
		center,
		MilitaryAIConfig.V2_DEFEND_SCATTER_RADIUS
	).size()
	return float(near_count) / float(units.size()) < MilitaryAIConfig.V2_DEFEND_SCATTER_COHESION_RATIO


func _evaluate_retreat_strategy(tree: SceneTree, rally_point: Vector3) -> void:
	_retreat_elapsed += TICK_SECONDS
	var units: Array = _get_attack_squad_units()
	var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	var destination: Vector3 = _resolve_retreat_destination(tree, rally_point, center)
	var arrived: bool = (
		destination != Vector3.ZERO
		and center != Vector3.ZERO
		and EnemyArmyCommand.horizontal_distance(center, destination)
		<= MilitaryAIConfig.V2_RETREAT_ARRIVAL_RADIUS
	)
	## Pull stragglers: do not leave isolated units fighting indefinitely.
	var stragglers_left: bool = _has_isolated_stragglers(units, destination, center)
	if (
		(arrived and not stragglers_left)
		or _retreat_elapsed >= MilitaryAIConfig.V2_RETREAT_COMPLETE_SECONDS
	):
		if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.RETREATING:
			EnemyArmyCommand.complete_retreat_to_regroup(tree)
		var reason: String = (
			"retreat complete, recovering"
			if arrived
			else "retreat hold elapsed, recovering"
		)
		if _mission != null:
			_mission.note_progress("completing retreat")
		_transition_to(State.RECOVER, reason, destination)
		return

	## Keep the original trigger reason on F3; only refresh destination / mission.
	var hold_reason: String = _last_transition_reason
	if hold_reason.is_empty():
		hold_reason = "retreating to recovery point"
	_transition_to(
		State.RETREAT,
		hold_reason,
		destination,
		null,
		90
	)


func _maybe_begin_retreat(tree: SceneTree, rally_point: Vector3) -> bool:
	if _state != State.ATTACK and _state != State.CREEP:
		return false

	var units: Array = (
		_get_attack_squad_units() if _state == State.ATTACK else _get_creep_squad_units()
	)
	var decision: Dictionary = _evaluate_retreat_triggers(tree, units)
	if not decision.get("should_retreat", false):
		return false

	var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	var destination: Vector3 = _resolve_retreat_destination(tree, rally_point, center)
	_transition_to(
		State.RETREAT,
		String(decision.get("reason", "retreating")),
		destination,
		null,
		90
	)
	return true


func _evaluate_retreat_triggers(tree: SceneTree, units: Array) -> Dictionary:
	units = NodeSafety.clean_node_array(units)
	if units.is_empty():
		return {"should_retreat": false}

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero != null and EnemyArmyCommand.get_health_ratio(hero) < MilitaryAIConfig.V2_RETREAT_HERO_HP_RATIO:
		return {"should_retreat": true, "reason": "hero in serious danger"}

	var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	if center == Vector3.ZERO:
		return {"should_retreat": false}

	var balance: Dictionary = EnemyArmyCommand.estimate_local_fight_balance(tree, center)
	var player_strength: float = float(balance.get("player_strength", 0.0))
	var ratio: float = float(balance.get("ratio", 1.0))
	if player_strength > 0.0 and ratio <= MilitaryAIConfig.V2_RETREAT_STRENGTH_RATIO:
		return {"should_retreat": true, "reason": "army clearly losing"}

	## Nearby enemy reinforcements tipping an otherwise contested fight.
	var wider: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		center,
		MilitaryAIConfig.V2_RETREAT_REINFORCEMENT_RADIUS
	)
	wider = NodeSafety.clean_node_array(wider)
	var local_player: Array = balance.get("player_units", []) as Array
	if wider.size() > local_player.size():
		var ai_strength: float = EnemyArmyCommand.estimate_combat_strength(units)
		var reinforced_strength: float = EnemyArmyCommand.estimate_combat_strength(wider)
		if (
			reinforced_strength > 0.0
			and ai_strength
			<= reinforced_strength * MilitaryAIConfig.V2_RETREAT_REINFORCEMENT_STRENGTH_RATIO
		):
			return {"should_retreat": true, "reason": "enemy reinforcements unfavorable"}

	var start_strength: float = (
		_attack_start_strength if _state == State.ATTACK else _creep_start_strength
	)
	if start_strength > 0.0:
		var current_strength: float = EnemyArmyCommand.estimate_combat_strength(units)
		if current_strength <= start_strength * (1.0 - MilitaryAIConfig.V2_ATTACK_ARMY_LOSS_RATIO):
			var fight_label: String = "attack" if _state == State.ATTACK else "creep"
			return {
				"should_retreat": true,
				"reason": "%s fight unwinnable" % fight_label,
			}

	var start_frontline: int = (
		_attack_start_frontline_count
		if _state == State.ATTACK
		else _creep_start_frontline_count
	)
	if start_frontline >= 2:
		var current_frontline: int = _count_frontline_units(units)
		var lost_ratio: float = (
			float(start_frontline - current_frontline) / float(start_frontline)
		)
		if lost_ratio >= MilitaryAIConfig.V2_RETREAT_FRONTLINE_LOSS_RATIO:
			return {"should_retreat": true, "reason": "frontline losses critical"}

	return {"should_retreat": false}


func _resolve_retreat_destination(
	tree: SceneTree,
	rally_point: Vector3,
	army_center: Vector3
) -> Vector3:
	## Prefer designated recovery point, then tower coverage, then main-base rally.
	var recovery: Vector3 = _designated_recovery_point
	if recovery == Vector3.ZERO:
		recovery = rally_point
	if recovery == Vector3.ZERO:
		recovery = EnemyArmyCommand.get_retreat_destination(tree)

	var tower_cover: Vector3 = _find_tower_cover_point(tree, army_center, recovery)
	if tower_cover != Vector3.ZERO:
		## If the army is still far from base, stage under the nearest friendly tower.
		if (
			army_center != Vector3.ZERO
			and recovery != Vector3.ZERO
			and EnemyArmyCommand.horizontal_distance(army_center, recovery)
			> MilitaryAIConfig.V2_RETREAT_ARRIVAL_RADIUS * 1.5
		):
			return tower_cover

	if recovery != Vector3.ZERO:
		return recovery
	return EnemyArmyCommand.get_retreat_destination(tree)


func _find_tower_cover_point(
	tree: SceneTree,
	army_center: Vector3,
	recovery: Vector3
) -> Vector3:
	if tree == null:
		return Vector3.ZERO

	var best: Vector3 = Vector3.ZERO
	var best_score: float = -INF
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.BUILDINGS_GROUP):
		if not node is Tower or not NodeSafety.is_alive_node(node):
			continue
		if not CombatTargetValidation.is_enemy_faction(node):
			continue
		var tower: Tower = node as Tower
		if tower.building_state != Building.STATE_COMPLETED:
			continue
		var tower_pos: Vector3 = tower.global_position
		var to_recovery: float = (
			EnemyArmyCommand.horizontal_distance(tower_pos, recovery)
			if recovery != Vector3.ZERO
			else 0.0
		)
		var to_army: float = (
			EnemyArmyCommand.horizontal_distance(tower_pos, army_center)
			if army_center != Vector3.ZERO
			else 0.0
		)
		## Prefer towers that sit between the army and the recovery point.
		var score: float = (
			MilitaryAIConfig.V2_RETREAT_SAFE_TOWER_RADIUS * 2.0
			- to_army * 0.55
			- to_recovery * 0.35
		)
		if score > best_score:
			best_score = score
			best = tower_pos

	if best == Vector3.ZERO or best_score < 0.0:
		return Vector3.ZERO
	return best


func _has_isolated_stragglers(
	units: Array,
	destination: Vector3,
	army_center: Vector3
) -> bool:
	if destination == Vector3.ZERO and army_center == Vector3.ZERO:
		return false
	var anchor: Vector3 = destination if destination != Vector3.ZERO else army_center
	var near_count: int = EnemyArmyCommand.filter_units_near_rally(
		units,
		anchor,
		MilitaryAIConfig.V2_RETREAT_STRAGGLER_RADIUS
	).size()
	if units.is_empty():
		return false
	return float(near_count) / float(units.size()) < 0.75


func _evaluate_recover_strategy(tree: SceneTree, rally_point: Vector3) -> void:
	_recover_elapsed += TICK_SECONDS
	_admit_pending_reinforcements()

	var recovery_point: Vector3 = _designated_recovery_point
	if recovery_point == Vector3.ZERO:
		recovery_point = rally_point

	var ready: bool = _is_recover_ready(tree)
	var timed_out: bool = _recover_elapsed >= MilitaryAIConfig.V2_RECOVER_MAX_SECONDS
	var min_hold_met: bool = _recover_elapsed >= MilitaryAIConfig.V2_RECOVER_MIN_SECONDS
	if (not ready and not timed_out) or (ready and not min_hold_met and not timed_out):
		## Keep publishing RECOVER so F3 shows why we are waiting.
		_transition_to(
			State.RECOVER,
			_format_recover_hold_reason(tree),
			recovery_point,
			null,
			40
		)
		return

	## Resume: prefer CREEP while early hero XP is still valuable; ATTACK on interrupt
	## or once the soft level/camp goals are met.
	var prefer_early_creep: bool = _should_prefer_early_creeping(tree, recovery_point)
	if prefer_early_creep:
		var creep_manager: EnemyCreepManager = _resolve_creep_manager()
		if (
			creep_manager != null
			and is_creep_ready()
			and _can_commit_to_creeping(tree, _get_creep_squad_units(), creep_manager)
		):
			_transition_to(State.ASSEMBLE, "recover complete, creep valuable", recovery_point)
			if _evaluate_creep_strategy(tree, recovery_point):
				return
			return

	if (
		is_attack_ready()
		and _can_reenter_attack(tree, recovery_point)
		and (
			not prefer_early_creep
			or _should_interrupt_creeping_for_attack(tree, recovery_point)
		)
	):
		_transition_to(State.ASSEMBLE, "recover complete, attack ready", recovery_point)
		if _evaluate_attack_strategy(tree, recovery_point):
			return
		return

	var creep_manager_fallback: EnemyCreepManager = _resolve_creep_manager()
	if (
		creep_manager_fallback != null
		and is_creep_ready()
		and _can_commit_to_creeping(tree, _get_creep_squad_units(), creep_manager_fallback)
	):
		_transition_to(State.ASSEMBLE, "recover complete, creep valuable", recovery_point)
		if _evaluate_creep_strategy(tree, recovery_point):
			return
		return

	if get_military_unit_count() < MilitaryAIConfig.V2_RECOVER_MIN_MILITARY_UNITS:
		_transition_to(State.ASSEMBLE, "recover complete, army incomplete", recovery_point)
		return

	_transition_to(
		State.ASSEMBLE,
		"recover complete, reassembling" if not timed_out else "recover timeout, reassembling",
		recovery_point
	)


func _format_recover_hold_reason(tree: SceneTree) -> String:
	var parts: PackedStringArray = []
	if not _main_squad.hero_present:
		parts.append("awaiting hero")
	else:
		var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
		if hero != null:
			var hp: float = EnemyArmyCommand.get_health_ratio(hero)
			if hp < MilitaryAIConfig.V2_RECOVER_HERO_HP_RATIO:
				parts.append("hero HP %.0f%%" % (hp * 100.0))
			var mana_ratio: float = float(hero.current_mana) / float(maxi(hero.max_mana, 1))
			if mana_ratio < MilitaryAIConfig.V2_RECOVER_HERO_MANA_RATIO:
				parts.append("hero mana %.0f%%" % (mana_ratio * 100.0))
	if get_military_unit_count() < MilitaryAIConfig.V2_RECOVER_MIN_MILITARY_UNITS:
		parts.append(
			"squad %d/%d"
			% [get_military_unit_count(), MilitaryAIConfig.V2_RECOVER_MIN_MILITARY_UNITS]
		)
	if not _pending_reinforcements.is_empty():
		parts.append("awaiting reinforcements")
	if parts.is_empty():
		return "recovering near base"
	return "recovering: %s" % ", ".join(parts)


func _is_recover_ready(tree: SceneTree) -> bool:
	if not _main_squad.hero_present:
		return false
	if get_military_unit_count() < MilitaryAIConfig.V2_RECOVER_MIN_MILITARY_UNITS:
		return false
	## Do not stall forever waiting on every pending unit — admit what we have.
	if _pending_reinforcements.size() >= 3:
		return false

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero == null:
		return false
	if EnemyArmyCommand.get_health_ratio(hero) < MilitaryAIConfig.V2_RECOVER_HERO_HP_RATIO:
		return false
	var mana_ratio: float = float(hero.current_mana) / float(maxi(hero.max_mana, 1))
	if mana_ratio < MilitaryAIConfig.V2_RECOVER_HERO_MANA_RATIO:
		return false
	return true


func _can_reenter_attack(tree: SceneTree, rally_point: Vector3) -> bool:
	## Hysteresis: after retreat, require cooldown OR a clearly favorable local fight.
	if _post_retreat_attack_cooldown <= 0.0:
		return true

	var units: Array = _get_attack_squad_units()
	var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	if center == Vector3.ZERO:
		center = rally_point
	if center == Vector3.ZERO:
		return false

	var balance: Dictionary = EnemyArmyCommand.estimate_local_fight_balance(tree, center)
	var player_strength: float = float(balance.get("player_strength", 0.0))
	var ratio: float = float(balance.get("ratio", 0.0))
	## No nearby enemies — allow rebuild-and-push once the squad is ready.
	if player_strength <= 0.0:
		return true
	return ratio >= MilitaryAIConfig.V2_ATTACK_REENTRY_STRENGTH_RATIO


func _evaluate_attack_strategy(tree: SceneTree, rally_point: Vector3) -> bool:
	var attack_army: Array = _get_attack_squad_units()
	if _state == State.ATTACK:
		if _maybe_exit_attack(tree, rally_point, attack_army):
			return true

	var lethal: bool = _detect_lethal_attack_window(tree, rally_point)
	var ready: bool = is_attack_ready()
	if lethal:
		ready = ready or is_lethal_attack_ready()

	if not ready:
		if _state == State.ATTACK:
			## Soft exit after commitment — not an emergency retreat.
			if not _has_met_state_commitment():
				return true
			_transition_to(State.RECOVER, "attack squad below threshold", rally_point)
			return true
		return false

	if attack_army.is_empty():
		return false

	if EnemyArmyCommand.is_defense_blocking_offense():
		return false

	if _state != State.ATTACK and not _can_reenter_attack(tree, rally_point):
		return false

	var origin: Vector3 = _main_squad.center
	if origin == Vector3.ZERO:
		origin = EnemyArmyCommand.compute_army_center(attack_army)
	if origin == Vector3.ZERO:
		origin = rally_point

	var objective: Dictionary = _select_attack_strategic_target(
		tree,
		attack_army,
		origin,
		rally_point,
		lethal
	)
	var target_node: Node3D = _sanitize_incoming_target(objective.get("node"))
	var target_position: Vector3 = objective.get("position", Vector3.ZERO) as Vector3
	if target_position == Vector3.ZERO and not NodeSafety.is_alive_node(target_node):
		if _state == State.ATTACK:
			if not _has_met_state_commitment():
				return true
			_transition_to(State.RECOVER, "no attack targets remain", rally_point)
			return true
		return false

	if NodeSafety.is_alive_node(target_node):
		target_position = target_node.global_position

	_attack_is_lethal = lethal or VariantUtils.to_bool(objective.get("commit_town_hall", false))
	var reason: String = String(objective.get("reason", "attack"))
	if _attack_is_lethal and not reason.begins_with("lethal"):
		reason = "lethal %s" % reason

	_transition_to(
		State.ATTACK,
		reason,
		target_position,
		target_node,
		int(objective.get("priority", CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_TOWN_HALL))
	)
	return true


func _maybe_exit_attack(tree: SceneTree, rally_point: Vector3, attack_army: Array) -> bool:
	if attack_army.is_empty():
		_transition_to(State.RECOVER, "attack army wiped", rally_point)
		return true

	## Emergency retreats are handled by `_maybe_begin_retreat` before this path.
	## Soft exits respect minimum ATTACK commitment to avoid ATTACK↔RETREAT flicker.
	if not _has_met_state_commitment():
		var emergency: Dictionary = _evaluate_retreat_triggers(tree, attack_army)
		if emergency.get("should_retreat", false):
			var center: Vector3 = EnemyArmyCommand.compute_army_center(attack_army)
			var destination: Vector3 = _resolve_retreat_destination(tree, rally_point, center)
			_transition_to(
				State.RETREAT,
				String(emergency.get("reason", "retreating")),
				destination,
				null,
				90
			)
			return true
		return false

	if _is_attack_army_scattered(attack_army):
		_transition_to(State.RECOVER, "attack army too scattered", rally_point)
		return true

	if _mission != null:
		_mission.sanitize_target_object()
		var mission_target_ref: Variant = _mission.target_object
		if (
			mission_target_ref != null
			and not NodeSafety.is_alive_node(mission_target_ref)
		):
			## Target destroyed — reassess for a follow-up objective this tick.
			_mission.clear_target_object()
			_unbind_mission_target_exit()
			_mission.completion_condition = ArmyMissionV2.CompletionCondition.TARGET_DESTROYED
			_mission.note_progress("killing target")
			return false

	return false


func _is_attack_army_losing(tree: SceneTree, attack_army: Array) -> bool:
	var decision: Dictionary = _evaluate_retreat_triggers(tree, attack_army)
	return VariantUtils.to_bool(decision.get("should_retreat", false))


func _is_attack_army_scattered(attack_army: Array) -> bool:
	if attack_army.size() < 4:
		return false
	var center: Vector3 = EnemyArmyCommand.compute_army_center(attack_army)
	if center == Vector3.ZERO:
		return false
	var near_count: int = EnemyArmyCommand.filter_units_near_rally(
		attack_army,
		center,
		MilitaryAIConfig.V2_ATTACK_SCATTER_RADIUS
	).size()
	return float(near_count) / float(attack_army.size()) < MilitaryAIConfig.V2_ATTACK_SCATTER_COHESION_RATIO


func _detect_lethal_attack_window(tree: SceneTree, rally_point: Vector3) -> bool:
	if EnemyAggression.get_lethal_score() >= MilitaryAIConfig.V2_ATTACK_LETHAL_SCORE_THRESHOLD:
		return true
	if EnemyAggression.is_aggression_mode_active() and EnemyAggression.should_prefer_town_hall_focus():
		return true

	var player_cc: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	var probe: Vector3 = rally_point
	if player_cc != null:
		probe = player_cc.global_position
	elif _main_squad.center != Vector3.ZERO:
		probe = _main_squad.center

	var player_military: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		probe,
		90.0
	)
	player_military = NodeSafety.clean_node_array(player_military)
	var player_hero: Hero = null
	for entry: Variant in player_military:
		if entry is Hero and NodeSafety.is_alive_node(entry):
			player_hero = entry as Hero
			break
	if player_hero == null:
		for node: Node in tree.get_nodes_in_group(&"heroes"):
			if node is Hero and NodeSafety.is_alive_node(node) and not CombatTargetValidation.is_enemy_faction(node):
				player_hero = node as Hero
				break

	var ai_strength: float = EnemyArmyCommand.estimate_combat_strength(_get_attack_squad_units())
	var player_strength: float = EnemyArmyCommand.estimate_combat_strength(player_military)
	var hero_away: bool = false
	if player_cc != null and player_hero != null:
		hero_away = (
			EnemyArmyCommand.horizontal_distance(
				player_hero.global_position,
				player_cc.global_position
			) >= 55.0
		)
	elif player_hero == null:
		hero_away = true

	var tiny_army: bool = player_military.size() <= 2
	var collapsed: bool = (
		player_strength > 0.0
		and ai_strength >= player_strength * MilitaryAIConfig.V2_ATTACK_COMMIT_STRENGTH_RATIO
		and player_military.size() <= 4
	)
	if tiny_army and ai_strength >= player_strength * 1.1:
		return true
	if hero_away and (tiny_army or collapsed):
		return true
	return false


func _select_attack_strategic_target(
	tree: SceneTree,
	attack_army: Array,
	origin: Vector3,
	rally_point: Vector3,
	lethal: bool
) -> Dictionary:
	var player_cc: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	var commit_th: bool = _should_commit_to_town_hall(
		tree,
		attack_army,
		player_cc,
		origin,
		lethal
	)
	if commit_th and player_cc != null:
		return {
			"node": player_cc,
			"position": player_cc.global_position,
			"reason": "commit town hall",
			"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_TOWN_HALL,
			"commit_town_hall": true,
		}

	if not lethal and not commit_th:
		var blocking: Dictionary = _find_route_blocking_player_army(
			tree,
			origin,
			player_cc
		)
		if not blocking.is_empty():
			return blocking

	if player_cc != null:
		return {
			"node": player_cc,
			"position": player_cc.global_position,
			"reason": "player town hall",
			"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_TOWN_HALL,
			"commit_town_hall": commit_th,
		}

	var tower: Node3D = _find_dangerous_player_tower(tree, origin, attack_army)
	if tower != null:
		return {
			"node": tower,
			"position": tower.global_position,
			"reason": "dangerous tower",
			"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_DANGEROUS_TOWER,
			"commit_town_hall": false,
		}

	var production: Node3D = _find_player_production_building(tree, origin)
	if production != null:
		return {
			"node": production,
			"position": production.global_position,
			"reason": "production building",
			"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_PRODUCTION,
			"commit_town_hall": false,
		}

	var worker: Node3D = _find_nearest_player_worker(tree, origin)
	if worker != null:
		return {
			"node": worker,
			"position": worker.global_position,
			"reason": "worker",
			"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_WORKER,
			"commit_town_hall": false,
		}

	var other: Node3D = _find_nearest_player_structure(tree, origin)
	if other != null:
		return {
			"node": other,
			"position": other.global_position,
			"reason": "valuable structure",
			"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_OTHER_STRUCTURE,
			"commit_town_hall": false,
		}

	if rally_point != Vector3.ZERO:
		return {
			"node": null,
			"position": rally_point,
			"reason": "no target fallback",
			"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_INVALID,
			"commit_town_hall": false,
		}
	return {}


func _should_commit_to_town_hall(
	tree: SceneTree,
	attack_army: Array,
	player_cc: CommandCenter,
	_origin: Vector3,
	lethal: bool
) -> bool:
	if player_cc == null or not NodeSafety.is_alive_node(player_cc):
		return false
	if lethal:
		return true

	var defenders: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		player_cc.global_position,
		MilitaryAIConfig.V2_ATTACK_LOCAL_ENGAGE_RADIUS
	)
	defenders = NodeSafety.clean_node_array(defenders)
	var ai_strength: float = EnemyArmyCommand.estimate_combat_strength(attack_army)
	var defender_strength: float = EnemyArmyCommand.estimate_combat_strength(defenders)
	if defender_strength <= 0.0:
		return ai_strength > 0.0
	return ai_strength >= defender_strength * MilitaryAIConfig.V2_ATTACK_COMMIT_STRENGTH_RATIO


func _find_route_blocking_player_army(
	tree: SceneTree,
	origin: Vector3,
	player_cc: CommandCenter
) -> Dictionary:
	if origin == Vector3.ZERO:
		return {}

	var goal: Vector3 = player_cc.global_position if player_cc != null else origin
	var sample_points: Array[Vector3] = [origin]
	if player_cc != null:
		sample_points.append(origin.lerp(goal, 0.35))
		sample_points.append(origin.lerp(goal, 0.6))

	var best_units: Array = []
	var best_center: Vector3 = Vector3.ZERO
	for sample: Vector3 in sample_points:
		var units: Array = EnemyArmyCommand.collect_player_military_near(
			tree,
			sample,
			MilitaryAIConfig.V2_ATTACK_ROUTE_BLOCK_RADIUS
		)
		units = NodeSafety.clean_node_array(units)
		if units.size() < MilitaryAIConfig.V2_ATTACK_ROUTE_BLOCK_MIN_UNITS:
			continue
		var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
		if center == Vector3.ZERO:
			continue
		## Only treat as route-blocking when the cluster sits between army and the goal.
		if player_cc != null:
			var to_goal: float = EnemyArmyCommand.horizontal_distance(origin, goal)
			var via_cluster: float = (
				EnemyArmyCommand.horizontal_distance(origin, center)
				+ EnemyArmyCommand.horizontal_distance(center, goal)
			)
			if via_cluster > to_goal * 1.35 and EnemyArmyCommand.horizontal_distance(origin, center) > 18.0:
				continue
		if units.size() > best_units.size():
			best_units = units
			best_center = center

	if best_units.is_empty() or best_center == Vector3.ZERO:
		return {}

	var strongest: Node3D = null
	var strongest_power: int = 0
	for entry: Variant in best_units:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var power: int = EnemyArmyCommand.estimate_military_power([entry])
		if power > strongest_power:
			strongest_power = power
			strongest = entry as Node3D

	return {
		"node": strongest,
		"position": best_center,
		"reason": "route-blocking army",
		"priority": CombatTargetValidation.V2_ATTACK_STRATEGIC_PRIORITY_ROUTE_BLOCKING_ARMY,
		"commit_town_hall": false,
	}


func _find_dangerous_player_tower(
	tree: SceneTree,
	origin: Vector3,
	attack_army: Array
) -> Node3D:
	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(attack_army)
	if army_center == Vector3.ZERO:
		army_center = origin

	var best: Node3D = null
	var best_distance: float = INF
	for node: Variant in CombatTargetValidation.get_cached_group_nodes(tree, &"buildings"):
		if not node is Tower or not NodeSafety.is_alive_node(node):
			continue
		if CombatTargetValidation.is_enemy_faction(node):
			continue
		if not CombatTargetValidation.is_player_selectable_building(node):
			continue
		var tower: Tower = node as Tower
		if tower.building_state != Building.STATE_COMPLETED:
			continue
		var threat_range: float = (
			tower.attack_range + MilitaryAIConfig.V2_ATTACK_TOWER_THREAT_BUFFER
		)
		var distance: float = EnemyArmyCommand.horizontal_distance(
			army_center,
			tower.global_position
		)
		if distance > threat_range * 1.75:
			continue
		if distance < best_distance:
			best_distance = distance
			best = tower
	return best


func _find_player_production_building(tree: SceneTree, origin: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Variant in CombatTargetValidation.get_cached_group_nodes(tree, &"buildings"):
		if not node is Building or not NodeSafety.is_alive_node(node):
			continue
		if not CombatTargetValidation.is_player_selectable_building(node):
			continue
		if not (node is Barracks or node is Stable or node is ArtilleryDepot or node is Academy):
			continue
		var building: Node3D = node as Node3D
		var distance: float = EnemyArmyCommand.horizontal_distance(origin, building.global_position)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


func _find_nearest_player_worker(tree: SceneTree, origin: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in tree.get_nodes_in_group(&"workers"):
		if not node is Worker or not NodeSafety.is_alive_node(node):
			continue
		if CombatTargetValidation.is_enemy_faction(node):
			continue
		var worker: Node3D = node as Node3D
		var distance: float = EnemyArmyCommand.horizontal_distance(origin, worker.global_position)
		if distance < best_distance:
			best_distance = distance
			best = worker
	return best


func _find_nearest_player_structure(tree: SceneTree, origin: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Variant in CombatTargetValidation.get_cached_group_nodes(tree, &"buildings"):
		if not node is Building or not NodeSafety.is_alive_node(node):
			continue
		if not CombatTargetValidation.is_player_selectable_building(node):
			continue
		if node is Farm:
			continue
		var building: Node3D = node as Node3D
		var distance: float = EnemyArmyCommand.horizontal_distance(origin, building.global_position)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


func _get_attack_squad_units() -> Array:
	var units: Array = []
	for entry: Variant in _main_squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node:
			continue
		if not EnemyArmyCommand.is_living_combat_unit(entry as Node):
			continue
		units.append(entry)
	return NodeSafety.clean_node_array(units)


func _evaluate_creep_strategy(tree: SceneTree, rally_point: Vector3) -> bool:
	var creep_manager: EnemyCreepManager = _resolve_creep_manager()
	if creep_manager == null:
		if _state == State.CREEP:
			_transition_to(State.ASSEMBLE, "creep manager unavailable", rally_point)
			return true
		return false

	var creep_army: Array = _get_creep_squad_units()
	if not _can_commit_to_creeping(tree, creep_army, creep_manager):
		if _state == State.CREEP:
			_transition_to(State.ASSEMBLE, "creep squad unavailable", rally_point)
			return true
		return false

	var current_camp: Node3D = _get_current_creep_camp()
	var just_cleared_camp: bool = false
	if _is_camp_cleared_or_invalid(tree, current_camp, creep_manager):
		if current_camp != null and is_instance_valid(current_camp):
			_cleared_creep_camp_ids[current_camp.get_instance_id()] = true
			just_cleared_camp = true
			if _mission != null:
				_mission.note_progress("cleared camp")
		current_camp = null
		_release_creep_reservation()

	var origin: Vector3 = _main_squad.center
	if origin == Vector3.ZERO:
		origin = EnemyArmyCommand.compute_army_center(creep_army)
	if origin == Vector3.ZERO:
		origin = rally_point

	if not _is_valid_creep_camp(tree, current_camp, creep_manager, creep_army, origin, rally_point):
		current_camp = _select_best_creep_camp(tree, creep_manager, creep_army, origin, rally_point)

	if current_camp == null:
		if _state == State.CREEP:
			_transition_to(State.ASSEMBLE, "no worthwhile camps remain", rally_point)
			return true
		return false

	var score: float = _score_creep_camp(
		tree,
		creep_manager,
		current_camp,
		creep_army,
		origin,
		rally_point
	)
	var reason: String = "creep %s" % creep_manager._format_camp_name(current_camp)
	if just_cleared_camp:
		reason = "chain %s" % creep_manager._format_camp_name(current_camp)
	_transition_to(
		State.CREEP,
		reason,
		current_camp.global_position,
		current_camp,
		int(round(score))
	)
	return true


func _get_creep_squad_units() -> Array:
	var units: Array = []
	for entry: Variant in _main_squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry):
			continue
		if not entry is Node:
			continue
		if not EnemyArmyCommand.is_living_combat_unit(entry as Node):
			continue
		units.append(entry)
	return NodeSafety.clean_node_array(units)


## Soft early-game preference: keep clearing safe camps until ~hero level 3.
## Never forces CREEP through defense, retreat, or a clear winning attack.
func _should_prefer_early_creeping(tree: SceneTree, rally_point: Vector3) -> bool:
	if tree == null:
		return false
	if _should_interrupt_creeping_for_attack(tree, rally_point):
		return false
	if not is_creep_ready():
		return false

	var creep_manager: EnemyCreepManager = _resolve_creep_manager()
	if creep_manager == null:
		return false

	var creep_army: Array = _get_creep_squad_units()
	if creep_army.is_empty():
		return false
	if not creep_manager._squad_safe_to_commit(tree, creep_army):
		return false

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero == null:
		return false
	if EnemyArmyCommand.get_health_ratio(hero) < MilitaryAIConfig.V2_CREEP_HERO_HEALTHY_RATIO:
		return false

	var hero_level: int = hero.level
	var camps_cleared: int = _cleared_creep_camp_ids.size()
	var below_power_spike: bool = hero_level < MilitaryAIConfig.V2_CREEP_TARGET_HERO_LEVEL
	var under_camp_goal: bool = (
		camps_cleared < MilitaryAIConfig.V2_CREEP_PREFERRED_CAMPS_BEFORE_ATTACK
	)
	## After the soft goals, only keep preferring while already chaining camps.
	if not below_power_spike and not under_camp_goal and _state != State.CREEP:
		return false

	var origin: Vector3 = _main_squad.center
	if origin == Vector3.ZERO:
		origin = EnemyArmyCommand.compute_army_center(creep_army)
	if origin == Vector3.ZERO:
		origin = rally_point

	var next_camp: Node3D = _get_current_creep_camp()
	if not _is_valid_creep_camp(tree, next_camp, creep_manager, creep_army, origin, rally_point):
		next_camp = _select_best_creep_camp(tree, creep_manager, creep_army, origin, rally_point)
	return next_camp != null


## Immediate CREEP → ATTACK interrupt conditions (not "min attack squad ready").
func _should_interrupt_creeping_for_attack(tree: SceneTree, rally_point: Vector3) -> bool:
	if tree == null:
		return false

	## Town Hall / workers are handled by DEFEND before this path.
	if EnemyAggression.should_suspend_creeping():
		return true

	var lethal: bool = _detect_lethal_attack_window(tree, rally_point)
	if lethal and (is_attack_ready() or is_lethal_attack_ready()):
		return true

	var greed: float = EnemyAggression.get_greed_score()
	if (
		greed >= MilitaryAIConfig.V2_CREEP_GREED_INTERRUPT_SCORE
		and (is_attack_ready() or is_lethal_attack_ready())
	):
		return true

	if not is_attack_ready() and not is_lethal_attack_ready():
		return false

	## Soft early window: keep camping until ≈L3 / a few clears unless greed/lethal above.
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	var hero_level: int = hero.level if hero != null else 1
	var early_creep_window: bool = (
		hero_level < MilitaryAIConfig.V2_CREEP_TARGET_HERO_LEVEL
		and _cleared_creep_camp_ids.size()
		< MilitaryAIConfig.V2_CREEP_PREFERRED_CAMPS_BEFORE_ATTACK
	)
	if early_creep_window:
		return false

	var attack_army: Array = _get_attack_squad_units()
	if attack_army.is_empty():
		return false

	var player_cc: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	var probe: Vector3 = rally_point
	if player_cc != null:
		probe = player_cc.global_position
	elif _main_squad.center != Vector3.ZERO:
		probe = _main_squad.center

	var player_military: Array = EnemyArmyCommand.collect_player_military_near(tree, probe, 90.0)
	player_military = NodeSafety.clean_node_array(player_military)
	var ai_strength: float = EnemyArmyCommand.estimate_combat_strength(attack_army)
	var player_strength: float = EnemyArmyCommand.estimate_combat_strength(player_military)
	var known_player_strength: float = float(
		EnemyArmyCommand.estimate_known_player_army_strength(tree, rally_point)
	)
	if known_player_strength > player_strength:
		player_strength = known_player_strength

	## Player has almost no army (visible + known memory), not merely "away creeping".
	var tiny_player_army: bool = (
		player_military.size() <= 2
		and player_strength <= 120.0
	)
	if tiny_player_army and ai_strength >= maxf(player_strength, 1.0) * 1.15:
		return true

	## Army clearly stronger than the player.
	if (
		player_strength > 0.0
		and ai_strength
		>= player_strength * MilitaryAIConfig.V2_CREEP_STRENGTH_ADVANTAGE_INTERRUPT
	):
		return true

	## Player Town Hall vulnerable: undefended AND (damaged / greed / preferred army).
	## Empty TH alone while the player fields an army elsewhere is not enough —
	## that is a normal mutual-creep opening, not a punish window.
	if player_cc != null:
		var defenders: Array = EnemyArmyCommand.collect_player_military_near(
			tree,
			player_cc.global_position,
			MilitaryAIConfig.V2_ATTACK_LOCAL_ENGAGE_RADIUS
		)
		defenders = NodeSafety.clean_node_array(defenders)
		var defender_strength: float = EnemyArmyCommand.estimate_combat_strength(defenders)
		var th_hp: float = EnemyArmyCommand.get_health_ratio(player_cc)
		var preferred_army: bool = (
			get_military_unit_count()
			>= MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS_PREFERRED
		)
		var th_vulnerable: bool = (
			defenders.size() <= 1
			and defender_strength <= 80.0
			and (
				th_hp < 0.70
				or greed >= 28.0
				or (preferred_army and tiny_player_army)
			)
		)
		if th_vulnerable and ai_strength >= maxf(defender_strength, 1.0) * 1.2:
			return true

	return false


func _can_commit_to_creeping(
	tree: SceneTree,
	creep_army: Array,
	creep_manager: EnemyCreepManager
) -> bool:
	if not _main_squad.hero_present:
		return false
	if get_military_unit_count() < MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS:
		return false
	if creep_army.is_empty():
		return false
	if EnemyAggression.should_suspend_creeping():
		return false
	## Do not keep creeping while a high-confidence finish / greed punish is available.
	if _should_interrupt_creeping_for_attack(
		tree,
		EnemyArmyCommand.resolve_enemy_rally_position(tree)
	):
		return false
	if EnemyArmyCommand.is_defense_blocking_offense():
		return false
	if not EnemyArmyCommand.allows_creep_orders():
		return false
	if not creep_manager._squad_safe_to_commit(tree, creep_army):
		return false
	return true


func _get_current_creep_camp() -> Node3D:
	if _mission == null:
		return null
	return _mission.get_alive_target_object()


func _is_camp_cleared_or_invalid(
	tree: SceneTree,
	camp: Node3D,
	creep_manager: EnemyCreepManager
) -> bool:
	if camp == null or not is_instance_valid(camp):
		return true
	if creep_manager._is_camp_cleared(tree, camp):
		return true
	return false


func _is_valid_creep_camp(
	tree: SceneTree,
	camp: Node3D,
	creep_manager: EnemyCreepManager,
	creep_army: Array,
	origin: Vector3,
	rally_point: Vector3
) -> bool:
	if camp == null or not is_instance_valid(camp):
		return false
	if _cleared_creep_camp_ids.has(camp.get_instance_id()):
		return false
	if creep_manager._is_camp_cleared(tree, camp):
		return false
	if creep_manager._is_player_contesting_camp(tree, camp):
		return false
	if not creep_manager._is_enemy_side_camp(camp, rally_point, tree):
		return false
	if not _is_creep_camp_reachable(origin, camp.global_position):
		return false
	return _score_creep_camp(tree, creep_manager, camp, creep_army, origin, rally_point) > -INF


func _select_best_creep_camp(
	tree: SceneTree,
	creep_manager: EnemyCreepManager,
	creep_army: Array,
	origin: Vector3,
	rally_point: Vector3
) -> Node3D:
	var best_camp: Node3D = null
	var best_score: float = -INF
	for camp: Node3D in creep_manager._collect_creep_camps(tree):
		var score: float = _score_creep_camp(
			tree,
			creep_manager,
			camp,
			creep_army,
			origin,
			rally_point
		)
		if score > best_score:
			best_score = score
			best_camp = camp
	return best_camp


func _score_creep_camp(
	tree: SceneTree,
	creep_manager: EnemyCreepManager,
	camp: Node3D,
	creep_army: Array,
	origin: Vector3,
	rally_point: Vector3
) -> float:
	if camp == null or not is_instance_valid(camp):
		return -INF
	if _cleared_creep_camp_ids.has(camp.get_instance_id()):
		return -INF
	if not creep_manager._is_enemy_side_camp(camp, rally_point, tree):
		return -INF
	if creep_manager._is_camp_cleared(tree, camp):
		return -INF
	if creep_manager._is_player_contesting_camp(tree, camp):
		return -INF
	if not _is_creep_camp_reachable(origin, camp.global_position):
		return -INF

	var distance: float = EnemyArmyCommand.horizontal_distance(origin, camp.global_position)
	if distance > EnemyCreepManager.CREEP_SEARCH_RANGE:
		return -INF

	var camp_power: int = creep_manager._estimate_camp_power(camp)
	if camp_power <= 0:
		return -INF

	var hero: Hero = _find_creep_hero(creep_army)
	var hero_hp: float = 1.0
	var hero_mana: float = 1.0
	var hero_level: int = 1
	if hero != null:
		hero_hp = EnemyArmyCommand.get_health_ratio(hero)
		hero_mana = float(hero.current_mana) / float(maxi(hero.max_mana, 1))
		hero_level = hero.level

	var army_power: float = maxf(EnemyArmyCommand.estimate_combat_strength(creep_army), 1.0)
	var safety_ratio: float = army_power / maxf(float(camp_power), 1.0)
	var strong_camp: bool = camp_power >= EnemyCreepManager.STRONG_CAMP_POWER_THRESHOLD
	if strong_camp and hero_level < 3:
		return -INF
	var required_ratio: float = (
		EnemyCreepManager.STRONG_CAMP_POWER_MARGIN if strong_camp else EnemyCreepManager.CAMP_POWER_MARGIN
	)
	if army_power < float(camp_power) * required_ratio:
		return -INF

	var player_near: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		camp.global_position,
		V2_CREEP_PLAYER_THREAT_RADIUS
	)
	var player_power: float = EnemyArmyCommand.estimate_combat_strength(player_near)
	if player_power > army_power * V2_CREEP_PLAYER_THREAT_STRENGTH_RATIO:
		return -INF

	var reward_value: float = _estimate_camp_reward_value(camp)
	var preference_bonus: float = 0.0
	if camp_power < V2_CREEP_MEDIUM_POWER_THRESHOLD:
		preference_bonus = 145.0
	elif strong_camp:
		preference_bonus = 20.0 + maxf(safety_ratio - 1.35, 0.0) * 35.0
	else:
		preference_bonus = 85.0 if distance <= EnemyCreepManager.CREEP_SEARCH_RANGE * 0.65 else 45.0

	## Hero XP progression: L1 weak → L2 better → L3 major power spike.
	var hero_xp_priority: float = 0.0
	if hero_level < MilitaryAIConfig.V2_CREEP_TARGET_HERO_LEVEL:
		hero_xp_priority = float(MilitaryAIConfig.V2_CREEP_TARGET_HERO_LEVEL - hero_level) * 110.0
	elif hero_level == MilitaryAIConfig.V2_CREEP_TARGET_HERO_LEVEL:
		hero_xp_priority = 30.0

	## Map control: strongly prefer safe nearby camps over distant ones.
	var map_control_bonus: float = 0.0
	if distance <= EnemyCreepManager.CREEP_SEARCH_RANGE * 0.40:
		map_control_bonus = 95.0
	elif distance <= EnemyCreepManager.CREEP_SEARCH_RANGE * 0.65:
		map_control_bonus = 50.0
	elif distance <= EnemyCreepManager.CREEP_SEARCH_RANGE * 0.85:
		map_control_bonus = 20.0

	## Camp chaining: after a clear, keep valuing the next nearby safe camp.
	var chain_bonus: float = 0.0
	if _state == State.CREEP or not _cleared_creep_camp_ids.is_empty():
		if distance <= MilitaryAIConfig.V2_CREEP_CHAIN_NEAR_RADIUS:
			chain_bonus = 90.0
		elif distance <= MilitaryAIConfig.V2_CREEP_CHAIN_MEDIUM_RADIUS:
			chain_bonus = 45.0

	## Soft goal: still below preferred camps-before-attack → keep camping valuable.
	var early_clear_bonus: float = 0.0
	if _cleared_creep_camp_ids.size() < MilitaryAIConfig.V2_CREEP_PREFERRED_CAMPS_BEFORE_ATTACK:
		early_clear_bonus = 55.0

	return (
		preference_bonus
		+ reward_value * 2.25
		+ safety_ratio * 95.0
		+ hero_hp * 30.0
		+ hero_mana * 10.0
		+ hero_xp_priority
		+ map_control_bonus
		+ chain_bonus
		+ early_clear_bonus
		- distance * 1.75
		- float(camp_power) * 0.08
		- player_power * 0.18
	)


func _estimate_camp_reward_value(camp: Node3D) -> float:
	if camp == null or not is_instance_valid(camp):
		return 0.0
	var xp_total: int = 0
	var gold_total: int = 0
	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue
		var child: Node = child_variant as Node
		if not CombatTargetValidation.is_neutral_creep(child):
			continue
		xp_total += HeroXpRewards.get_xp_amount_for_victim(child)
		gold_total += HeroXpRewards.get_gold_amount_for_victim(child)
	return float(xp_total) + float(gold_total) * 1.35


func _find_creep_hero(creep_army: Array) -> Hero:
	for entry: Variant in creep_army:
		if entry is Hero and NodeSafety.is_alive_node(entry):
			return entry as Hero
	return null


func _is_creep_camp_reachable(from_position: Vector3, to_position: Vector3) -> bool:
	if from_position == Vector3.ZERO or to_position == Vector3.ZERO:
		return false
	var tree: SceneTree = get_tree()
	if tree == null or not tree.current_scene is Node3D:
		return true
	var world: World3D = (tree.current_scene as Node3D).get_world_3d()
	if world == null:
		return true
	var nav_map: RID = world.navigation_map
	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		return true
	var start: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, from_position)
	var target: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to_position)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start, target, true)
	if path.is_empty():
		return false
	return EnemyArmyCommand.horizontal_distance(path[path.size() - 1], target) <= 4.0


func _release_creep_reservation() -> void:
	_reserved_creep_camp_id = 0


## Accepts Variant so freed refs never bind into Node3D parameters.
## Validity is established before any Object cast or identity compare.
func _same_target_object(a: Variant, b: Variant) -> bool:
	var a_valid: bool = a != null and is_instance_valid(a)
	var b_valid: bool = b != null and is_instance_valid(b)
	if not a_valid and not b_valid:
		## Same only when both are true null (no objective), not freed leftovers.
		return a == null and b == null
	if not a_valid or not b_valid:
		return false
	return (a as Object).get_instance_id() == (b as Object).get_instance_id()


## Reject null / freed / non-Node3D before any typed Node3D assignment.
func _sanitize_incoming_target(value: Variant) -> Node3D:
	if value == null:
		return null
	if not is_instance_valid(value):
		return null
	if not (value is Node3D):
		return null
	return value as Node3D


func _bind_mission_target_exit(target: Node3D) -> void:
	_unbind_mission_target_exit()
	if not NodeSafety.is_alive_node(target):
		return
	_mission_target_exit_bound_id = target.get_instance_id()
	if not target.tree_exiting.is_connected(_on_mission_target_tree_exiting):
		target.tree_exiting.connect(_on_mission_target_tree_exiting)


func _unbind_mission_target_exit() -> void:
	if _mission_target_exit_bound_id == 0:
		return
	var bound_id: int = _mission_target_exit_bound_id
	_mission_target_exit_bound_id = 0
	var node: Object = instance_from_id(bound_id)
	if node == null or not is_instance_valid(node) or not (node is Node):
		return
	var as_node: Node = node as Node
	if as_node.tree_exiting.is_connected(_on_mission_target_tree_exiting):
		as_node.tree_exiting.disconnect(_on_mission_target_tree_exiting)


func _on_mission_target_tree_exiting() -> void:
	## Clear immediately — do not wait for the next AI tick.
	_mission_target_exit_bound_id = 0
	if _mission != null:
		_mission.clear_target_object()
		_mission.target_position = Vector3.ZERO
		if _mission.completion_condition == ArmyMissionV2.CompletionCondition.NONE:
			_mission.completion_condition = ArmyMissionV2.CompletionCondition.TARGET_DESTROYED
			_mission.note_progress("target exited tree")
	if _state == State.CREEP:
		_release_creep_reservation()


func _find_primary_enemy_base(tree: SceneTree) -> CommandCenter:
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if node is CommandCenter and NodeSafety.is_alive_node(node):
			return node as CommandCenter
	return null


func _find_best_assemble_rally_point(tree: SceneTree, base: CommandCenter) -> Vector3:
	var base_position: Vector3 = base.global_position
	var preferred: Vector3 = base_position + EnemyArmyCommand.ARMY_RALLY_OFFSET
	var base_to_preferred: Vector3 = preferred - base_position
	base_to_preferred.y = 0.0
	var preferred_dir: Vector3 = (
		base_to_preferred.normalized() if base_to_preferred.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
	)

	var candidate_dirs: Array[Vector3] = [
		preferred_dir,
		(preferred_dir + Vector3.RIGHT * 0.55).normalized(),
		(preferred_dir - Vector3.RIGHT * 0.55).normalized(),
		(preferred_dir + Vector3.FORWARD * 0.55).normalized(),
		(preferred_dir - Vector3.FORWARD * 0.55).normalized(),
		Vector3.RIGHT,
		-Vector3.RIGHT,
		Vector3.FORWARD,
		-Vector3.FORWARD,
	]
	var radii: Array[float] = [
		MilitaryAIConfig.V2_ASSEMBLE_RALLY_MIN_RADIUS,
		10.0,
		12.0,
		MilitaryAIConfig.V2_ASSEMBLE_RALLY_MAX_RADIUS,
	]

	var best_candidate: Vector3 = Vector3.ZERO
	var best_score: float = -INF
	for radius: float in radii:
		for dir: Vector3 in candidate_dirs:
			if dir.length_squared() < 0.01:
				continue
			var candidate: Vector3 = base_position + dir.normalized() * radius
			candidate.y = base_position.y
			var score: float = _score_assemble_rally_candidate(tree, base, candidate)
			if score > best_score:
				best_score = score
				best_candidate = candidate

	return best_candidate


func _score_assemble_rally_candidate(
	tree: SceneTree,
	base: CommandCenter,
	candidate: Vector3
) -> float:
	if not _is_safe_assemble_rally_candidate(tree, base, candidate):
		return -INF

	var base_position: Vector3 = base.global_position
	var preferred: Vector3 = base_position + EnemyArmyCommand.ARMY_RALLY_OFFSET
	var score: float = 1000.0
	score -= EnemyArmyCommand.horizontal_distance(candidate, preferred) * 4.0
	score -= EnemyArmyCommand.horizontal_distance(candidate, base_position) * 1.5

	for building: Building in _collect_enemy_buildings(tree):
		score += minf(
			EnemyArmyCommand.horizontal_distance(candidate, building.global_position),
			8.0
		)
	if ConstructionReservations.overlaps_reserved_footprint(candidate, Vector2(3.0, 3.0)):
		score -= 200.0
	return score


func _is_safe_assemble_rally_candidate(
	tree: SceneTree,
	base: CommandCenter,
	candidate: Vector3
) -> bool:
	if candidate == Vector3.ZERO:
		return false

	var distance_from_base: float = EnemyArmyCommand.horizontal_distance(candidate, base.global_position)
	if (
		distance_from_base < MilitaryAIConfig.V2_ASSEMBLE_RALLY_MIN_RADIUS
		or distance_from_base > MilitaryAIConfig.V2_ASSEMBLE_RALLY_MAX_RADIUS
	):
		return false

	if ConstructionReservations.overlaps_reserved_footprint(candidate, Vector2(3.0, 3.0)):
		return false

	for building: Building in _collect_enemy_buildings(tree):
		if not NodeSafety.is_alive_node(building):
			continue
		if building.is_position_inside_footprint(candidate, 2.0):
			return false
		if EnemyArmyCommand.horizontal_distance(candidate, building.global_position) <= 3.5:
			return false
		if building.is_being_constructed():
			for point: Vector3 in building.get_construction_points():
				if EnemyArmyCommand.horizontal_distance(candidate, point) <= 2.5:
					return false
			if EnemyArmyCommand.horizontal_distance(candidate, building.global_position) <= 5.0:
				return false
		for exit_point: Vector3 in _get_building_exit_points(building):
			if EnemyArmyCommand.horizontal_distance(candidate, exit_point) <= MilitaryAIConfig.V2_ASSEMBLE_PRODUCTION_EXIT_CLEARANCE:
				return false
			if _candidate_near_worker_route(building.global_position, exit_point, candidate, 2.0):
				return false

	for worker: Worker in _collect_enemy_workers(tree):
		if not NodeSafety.is_alive_node(worker):
			continue
		if EnemyArmyCommand.horizontal_distance(candidate, worker.global_position) <= 3.0:
			return false
		if worker.is_on_construction_trip():
			continue
		if _candidate_near_worker_route(base.global_position, worker.global_position, candidate, 2.2):
			return false
		var gather_source: GatherableResource = worker.get("_gather_source") as GatherableResource
		if gather_source != null and is_instance_valid(gather_source):
			if _candidate_near_worker_route(base.global_position, gather_source.global_position, candidate, 2.6):
				return false
			if EnemyArmyCommand.horizontal_distance(candidate, gather_source.global_position) <= 4.0:
				return false

	for node: Node in tree.get_nodes_in_group(GatherableResource.GROUP_ENEMY_RESOURCES):
		if not (node is GatherableResource) or not NodeSafety.is_alive_node(node):
			continue
		var resource: GatherableResource = node as GatherableResource
		if resource.get_resource_id() != &"gold":
			continue
		if EnemyArmyCommand.horizontal_distance(candidate, resource.global_position) <= 4.0:
			return false
		if _candidate_near_worker_route(base.global_position, resource.global_position, candidate, 2.8):
			return false

	return true


func _collect_enemy_buildings(tree: SceneTree) -> Array[Building]:
	var buildings: Array[Building] = []
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if node is Building and NodeSafety.is_alive_node(node):
			buildings.append(node as Building)
	var scene_root: Node = tree.current_scene
	if scene_root == null:
		return buildings
	for node_variant: Variant in scene_root.find_children("*", "", true, false):
		if not node_variant is Building or not NodeSafety.is_alive_node(node_variant):
			continue
		var building: Building = node_variant as Building
		if building.team_id == 1 and not buildings.has(building):
			buildings.append(building)
	return buildings


func _collect_enemy_workers(tree: SceneTree) -> Array[Worker]:
	var workers: Array[Worker] = []
	for node: Node in tree.get_nodes_in_group(&"enemy_workers"):
		if node is Worker and NodeSafety.is_alive_node(node):
			workers.append(node as Worker)
	return workers


func _candidate_near_worker_route(
	from_position: Vector3,
	to_position: Vector3,
	candidate: Vector3,
	clearance: float
) -> bool:
	var route: Vector2 = Vector2(to_position.x - from_position.x, to_position.z - from_position.z)
	var length_sq: float = route.length_squared()
	if length_sq <= 0.01:
		return false
	var rel: Vector2 = Vector2(candidate.x - from_position.x, candidate.z - from_position.z)
	var t: float = clampf(rel.dot(route) / length_sq, 0.0, 1.0)
	var closest: Vector2 = Vector2(from_position.x, from_position.z) + route * t
	return Vector2(candidate.x, candidate.z).distance_to(closest) <= clearance


func _get_building_exit_points(building: Building) -> Array[Vector3]:
	var exit_points: Array[Vector3] = []
	if building == null or not is_instance_valid(building):
		return exit_points

	for property_name: StringName in [
		&"worker_spawn_offset",
		&"spearman_spawn_offset",
		&"swordsman_spawn_offset",
		&"archer_spawn_offset",
		&"heavy_cavalry_spawn_offset",
		&"light_cavalry_spawn_offset",
		&"cavalry_archer_spawn_offset",
		&"cannon_spawn_offset",
	]:
		var local_offset: Variant = building.get(property_name)
		if not (local_offset is Vector3):
			continue
		exit_points.append(_building_local_offset_to_world(building, local_offset as Vector3))
	return exit_points


func _building_local_offset_to_world(building: Building, local_offset: Vector3) -> Vector3:
	var world_offset: Vector3 = building.global_transform.basis * local_offset
	return Vector3(
		building.global_position.x + world_offset.x,
		building.global_position.y,
		building.global_position.z + world_offset.z
	)


func _publish_perf_status() -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		return

	var mission: ArmyMissionV2 = _mission
	var display: Dictionary = _resolve_truthful_display(mission)
	var mission_name: String = String(display.get("mission", "-"))
	var objective: String = String(display.get("objective", "-"))
	var display_state: String = String(display.get("state", get_state_name()))
	var age_seconds: float = 0.0
	var since_progress: float = 0.0
	if mission != null:
		mission.sanitize_target_object()
		age_seconds = mission.get_age_seconds()
		since_progress = mission.get_seconds_since_progress()

	var state_age: float = _state_commit_elapsed_seconds()
	if state_age >= INF:
		state_age = 0.0

	PerfCounters.set_military_ai_v2_status(
		MilitaryAIConfig.ai_version_label(),
		display_state,
		mission_name,
		objective,
		age_seconds,
		_last_transition_reason
	)
	PerfCounters.set_military_ai_v2_squad_status(
		_main_squad.get_size(),
		_main_squad.hero_present,
		_main_squad.get_role_counts_label(),
		_main_squad.estimated_army_value
	)
	PerfCounters.set_military_ai_v2_watchdog_status(
		_watchdog_active_order,
		_watchdog_distance,
		since_progress,
		state_age,
		_watchdog_status
	)
	var destination_text: String = _format_destination_label(mission)
	var last_order_age: float = EnemyArmyCommand.get_seconds_since_last_order()
	var last_order_text: String = "-"
	if last_order_age < INF:
		last_order_text = "%.1fs ago (%s)" % [
			last_order_age,
			EnemyArmyCommand.get_last_issued_order_label(),
		]
	var last_mission_change: String = "%.1fs ago (%s)" % [
		age_seconds,
		_last_transition_reason if not _last_transition_reason.is_empty() else "-",
	]
	var idle_time: float = 0.0
	var commander: ArmyCommanderV2 = _resolve_commander()
	if commander != null:
		idle_time = commander.get_squad_idle_seconds()
	PerfCounters.set_military_ai_v2_execution_status(
		destination_text,
		last_order_text,
		last_mission_change,
		idle_time
	)
	## Keep legacy AI status fields filled so older overlay lines stay coherent under V2.
	PerfCounters.set_ai_status(display_state, mission_name, "MilitaryDirectorV2")
	PerfCounters.set_ai_mission_detail(
		"V2 %s → %s (%s)" % [display_state, objective, _last_transition_reason]
	)
	PerfCounters.set_combat_group_size(_main_squad.get_size())


func _format_destination_label(mission: ArmyMissionV2) -> String:
	if mission == null:
		return "-"
	var alive_target: Node3D = mission.get_alive_target_object()
	if alive_target != null:
		var pos: Vector3 = alive_target.global_position
		return "(%.0f, %.0f)" % [pos.x, pos.z]
	if mission.target_position != Vector3.ZERO:
		return "(%.0f, %.0f)" % [mission.target_position.x, mission.target_position.z]
	var order_dest: Vector3 = EnemyArmyCommand.get_last_issued_order_destination()
	if order_dest != Vector3.ZERO:
		return "(%.0f, %.0f)" % [order_dest.x, order_dest.z]
	return "-"


func _reset_watchdog_state(status: String = "idle") -> void:
	_watchdog_timer = 0.0
	_watchdog_order_refreshed = false
	_watchdog_status = status if not status.is_empty() else "idle"
	_watchdog_recent_combat = false
	_watchdog_living_members = _main_squad.get_size()
	_watchdog_distance = -1.0
	_watchdog_objective_valid = true


func _resolve_commander() -> ArmyCommanderV2:
	if _commander == null:
		_commander = get_parent().get_node_or_null("ArmyCommanderV2") as ArmyCommanderV2
	return _commander


func _tick_mission_watchdog(delta: float) -> void:
	_watchdog_timer += delta
	_watchdog_diag_timer += delta
	if _watchdog_timer < MilitaryAIConfig.V2_WATCHDOG_INTERVAL_SECONDS:
		_publish_watchdog_snapshot_only()
		return
	_watchdog_timer = 0.0

	var tree: SceneTree = get_tree()
	if tree == null or _mission == null:
		_watchdog_status = "idle"
		return

	_mission.sanitize_target_object()
	var units: Array = _get_watchdog_squad_units()
	_watchdog_living_members = units.size()
	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	var objective_position: Vector3 = _resolve_watchdog_objective_position()
	_watchdog_active_order = _resolve_active_order_label()
	_watchdog_objective_valid = _is_current_objective_valid(tree)

	if army_center != Vector3.ZERO and objective_position != Vector3.ZERO:
		_watchdog_distance = EnemyArmyCommand.horizontal_distance(army_center, objective_position)
	elif objective_position == Vector3.ZERO:
		_watchdog_distance = -1.0

	if not _is_watchdog_mission_active():
		_watchdog_status = "idle"
		_watchdog_order_refreshed = false
		_maybe_log_watchdog_diag()
		return

	## Track meaningful progress before deciding to intervene.
	_update_watchdog_progress(tree, units, army_center, objective_position)

	## Invalid objective / order → cancel immediately (do not freeze).
	if not _watchdog_objective_valid:
		_watchdog_status = "invalid objective"
		_cancel_stalled_mission_and_fallback(
			tree,
			"watchdog invalid objective (%s)" % get_state_name()
		)
		_maybe_log_watchdog_diag()
		return

	var since_progress: float = _mission.get_seconds_since_progress()
	if since_progress < MilitaryAIConfig.V2_WATCHDOG_STALL_SECONDS:
		_watchdog_status = "tracking (%.1fs)" % since_progress
		_maybe_log_watchdog_diag()
		return

	## 1) Validate objective and orders (already done above).
	## 2) Refresh the order once.
	if not _watchdog_order_refreshed:
		_watchdog_order_refreshed = true
		_watchdog_status = "refreshing order"
		if _refresh_stalled_mission_order(tree, units, army_center, objective_position):
			_mission.note_progress("watchdog order refresh")
			_maybe_log_watchdog_diag()
			return
		## Refresh failed — fall through to cancel.

	## 3–5) Cancel mission, release reservations, safe fallback.
	_watchdog_status = "stalled → fallback"
	_cancel_stalled_mission_and_fallback(
		tree,
		"watchdog stalled (%s, %.1fs)" % [get_state_name(), since_progress]
	)
	_maybe_log_watchdog_diag()


func _publish_watchdog_snapshot_only() -> void:
	## Keep distance / order labels fresh between watchdog intervals without acting.
	if _mission == null:
		return
	var units: Array = _get_watchdog_squad_units()
	_watchdog_living_members = units.size()
	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	var objective_position: Vector3 = _resolve_watchdog_objective_position()
	_watchdog_active_order = _resolve_active_order_label()
	if army_center != Vector3.ZERO and objective_position != Vector3.ZERO:
		_watchdog_distance = EnemyArmyCommand.horizontal_distance(army_center, objective_position)

	var since_progress: float = 0.0
	var age_seconds: float = 0.0
	if _mission != null:
		since_progress = _mission.get_seconds_since_progress()
		age_seconds = _mission.get_age_seconds()
	var state_age: float = _state_commit_elapsed_seconds()
	if state_age >= INF:
		state_age = 0.0
	PerfCounters.set_military_ai_v2_watchdog_status(
		_watchdog_active_order,
		_watchdog_distance,
		since_progress,
		state_age,
		_watchdog_status
	)
	var idle_time: float = 0.0
	var commander: ArmyCommanderV2 = _resolve_commander()
	if commander != null:
		idle_time = commander.get_squad_idle_seconds()
	var last_order_age: float = EnemyArmyCommand.get_seconds_since_last_order()
	var last_order_text: String = "-"
	if last_order_age < INF:
		last_order_text = "%.1fs ago (%s)" % [
			last_order_age,
			EnemyArmyCommand.get_last_issued_order_label(),
		]
	PerfCounters.set_military_ai_v2_execution_status(
		_format_destination_label(_mission),
		last_order_text,
		"%.1fs ago (%s)" % [
			age_seconds,
			_last_transition_reason if not _last_transition_reason.is_empty() else "-",
		],
		idle_time
	)


func _is_watchdog_mission_active() -> bool:
	return _state in [State.CREEP, State.ATTACK, State.DEFEND, State.RETREAT]


func _get_watchdog_squad_units() -> Array:
	match _state:
		State.CREEP:
			return _get_creep_squad_units()
		_:
			return _get_attack_squad_units()


func _resolve_watchdog_objective_position() -> Vector3:
	if _mission == null:
		return Vector3.ZERO
	var alive_target: Node3D = _mission.get_alive_target_object()
	if alive_target != null:
		return alive_target.global_position
	return _mission.target_position


func _resolve_active_order_label() -> String:
	var order: String = EnemyArmyCommand.get_executable_order_label()
	if not order.is_empty():
		return order
	var last_issued: String = EnemyArmyCommand.get_last_issued_order_label()
	if last_issued != "-" and not last_issued.is_empty():
		var age: float = EnemyArmyCommand.get_seconds_since_last_order()
		if age < MilitaryAIConfig.V2_SQUAD_IDLE_SECONDS:
			return last_issued
	match _state:
		State.ASSEMBLE:
			return "rally"
		State.RECOVER:
			return "hold"
		State.RETREAT:
			return "retreat"
		State.CREEP, State.ATTACK, State.DEFEND:
			## Do not claim a combat order exists when none was issued.
			return "none"
		_:
			return "-"


func _is_current_objective_valid(tree: SceneTree) -> bool:
	if _mission == null:
		return false
	## Detect freed refs via Variant before any typed Node3D binding.
	var target_ref: Variant = _mission.target_object
	var target_freed: bool = target_ref != null and not is_instance_valid(target_ref)
	_mission.sanitize_target_object()
	match _state:
		State.CREEP:
			if target_freed:
				return false
			var camp: Node3D = _mission.get_alive_target_object()
			if not NodeSafety.is_alive_node(camp):
				return false
			var creep_manager: EnemyCreepManager = _resolve_creep_manager()
			if creep_manager == null:
				return false
			if creep_manager._is_camp_cleared(tree, camp):
				return false
			## Truthful CREEP requires a living uncleared camp; order may briefly lag.
			return true
		State.ATTACK:
			if target_freed:
				return false
			if NodeSafety.is_alive_node(_mission.get_alive_target_object()):
				return true
			## Position-only attacks are allowed, but a freed node objective is not.
			return _mission.get_alive_target_object() == null and _mission.target_position != Vector3.ZERO
		State.DEFEND:
			var threat: Dictionary = _resolve_v2_defense_threat(tree)
			return VariantUtils.to_bool(threat.get("threatened", false)) or _defend_clear_timer > 0.0
		State.RETREAT:
			return _mission.target_position != Vector3.ZERO
		_:
			return true


func _update_watchdog_progress(
	tree: SceneTree,
	units: Array,
	army_center: Vector3,
	objective_position: Vector3
) -> void:
	if _mission == null:
		return

	var in_combat: bool = EnemyArmyCommand.is_enemy_army_under_attack(
		tree,
		units,
		EnemyArmyCommand.LOCAL_FIGHT_RADIUS
	)
	var creep_camp: Node3D = _mission.get_alive_target_object()
	if not in_combat and _state == State.CREEP and NodeSafety.is_alive_node(creep_camp):
		var creep_manager: EnemyCreepManager = _resolve_creep_manager()
		if creep_manager != null:
			in_combat = creep_manager._is_army_engaging_camp(
				tree,
				units,
				creep_camp
			)
	if in_combat and not _watchdog_recent_combat:
		_mission.note_progress("started combat")
		_watchdog_order_refreshed = false
	elif in_combat:
		## Continuous fighting is real progress — never stall-refresh mid-combat.
		_mission.note_progress("active combat")
		_watchdog_order_refreshed = false
	_watchdog_recent_combat = in_combat
	if in_combat:
		return

	if army_center == Vector3.ZERO or objective_position == Vector3.ZERO:
		return

	if _mission.note_distance_progress(
		_watchdog_distance if _watchdog_distance >= 0.0 else EnemyArmyCommand.horizontal_distance(
			army_center,
			objective_position
		),
		MilitaryAIConfig.V2_WATCHDOG_PROGRESS_DISTANCE_EPSILON
	):
		_watchdog_order_refreshed = false

	if (
		_watchdog_distance >= 0.0
		and _watchdog_distance <= MilitaryAIConfig.V2_WATCHDOG_NEAR_OBJECTIVE_RADIUS
	):
		## Only note arrival once per approach so the stall clock can still fire
		## when the squad is stuck at the wrong near-point.
		if _mission.last_progress_reason != "reached objective":
			_mission.note_progress("reached objective")
			_watchdog_order_refreshed = false


func _refresh_stalled_mission_order(
	tree: SceneTree,
	units: Array,
	_army_center: Vector3,
	objective_position: Vector3
) -> bool:
	var commander: ArmyCommanderV2 = _resolve_commander()
	if commander != null:
		commander.request_watchdog_order_refresh()

	## Always treat a commander refresh request as the one allowed reissue.
	## Order issuance may still fail without a formed squad / nav map.
	var refreshed: bool = false
	if objective_position != Vector3.ZERO and not units.is_empty():
		refreshed = EnemyArmyCommand.refresh_stalled_mission_order(tree)
		if not refreshed:
			match _state:
				State.CREEP:
					refreshed = EnemyArmyCommand.issue_group_combat_move(
						tree,
						units,
						objective_position,
						EnemyUnitMission.Mission.CREEP,
						EnemyArmyCommand.ArmyMode.CREEPING
					)
				State.ATTACK:
					refreshed = EnemyArmyCommand.issue_group_combat_move(
						tree,
						units,
						objective_position,
						EnemyUnitMission.Mission.ATTACK,
						EnemyArmyCommand.ArmyMode.ATTACKING,
						true
					)
				State.DEFEND:
					EnemyArmyCommand.with_authorized_orders(func() -> void:
						EnemyArmyCommand.command_attack_move(
							units,
							objective_position,
							EnemyUnitMission.Mission.DEFEND
						)
					)
					refreshed = true
				State.RETREAT:
					EnemyArmyCommand.with_authorized_orders(func() -> void:
						EnemyArmyCommand.command_retreat_to(units, objective_position)
					)
					refreshed = true
				_:
					pass
	## Empty-squad / harness cases: still consume the single refresh attempt.
	return refreshed or commander != null


func _cancel_stalled_mission_and_fallback(tree: SceneTree, reason: String) -> void:
	if _mission != null:
		_mission.mark_cancelled(reason)

	## 4) Release reservations / executable ownership.
	_release_creep_reservation()
	if EnemyArmyCommand.is_creeping_executable_active():
		EnemyArmyCommand.clear_executable_mission(reason)
	elif EnemyArmyCommand.get_executable_mission() not in [
		EnemyArmyCommand.ExecutableMission.NONE,
		EnemyArmyCommand.ExecutableMission.IDLE,
	]:
		EnemyArmyCommand.clear_executable_mission(reason)

	_watchdog_order_refreshed = false
	_resolve_watchdog_fallback(tree, reason)


func _resolve_watchdog_fallback(tree: SceneTree, reason: String) -> void:
	var rally_point: Vector3 = get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		rally_point = EnemyArmyCommand.resolve_enemy_rally_position(tree)

	## 1) DEFEND
	var threat: Dictionary = _resolve_v2_defense_threat(tree)
	if threat.get("threatened", false):
		_evaluate_defend_strategy(tree, rally_point)
		_watchdog_status = "fallback DEFEND"
		return

	var units: Array = _get_watchdog_squad_units()
	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(units)

	## 2) Fight nearby hostile threat
	if army_center != Vector3.ZERO:
		var nearby: Array = EnemyArmyCommand.collect_player_military_near(
			tree,
			army_center,
			MilitaryAIConfig.V2_WATCHDOG_NEARBY_THREAT_RADIUS
		)
		nearby = NodeSafety.clean_node_array(nearby)
		if not nearby.is_empty() and (is_attack_ready() or is_lethal_attack_ready()):
			var focus: Node3D = nearby[0] as Node3D if nearby[0] is Node3D else null
			var fight_point: Vector3 = EnemyArmyCommand.compute_army_center(nearby)
			if fight_point == Vector3.ZERO and focus != null:
				fight_point = focus.global_position
			if fight_point != Vector3.ZERO:
				var safe_focus: Node3D = _sanitize_incoming_target(focus)
				_transition_to(
					State.ATTACK,
					"%s → fight nearby" % reason,
					fight_point,
					safe_focus,
					80
				)
				_watchdog_status = "fallback ATTACK nearby"
				return

	## 3) RETREAT if unsafe
	var retreat_decision: Dictionary = _evaluate_retreat_triggers(tree, units)
	if retreat_decision.get("should_retreat", false):
		var destination: Vector3 = _resolve_retreat_destination(tree, rally_point, army_center)
		_transition_to(
			State.RETREAT,
			"%s → %s" % [reason, String(retreat_decision.get("reason", "unsafe"))],
			destination,
			null,
			90
		)
		_watchdog_status = "fallback RETREAT"
		return

	## 4) Select another valid camp
	var creep_manager: EnemyCreepManager = _resolve_creep_manager()
	if creep_manager != null and is_creep_ready():
		var origin: Vector3 = army_center if army_center != Vector3.ZERO else rally_point
		var next_camp: Node3D = _select_best_creep_camp(
			tree,
			creep_manager,
			_get_creep_squad_units(),
			origin,
			rally_point
		)
		if next_camp != null and _can_commit_to_creeping(tree, _get_creep_squad_units(), creep_manager):
			_transition_to(
				State.CREEP,
				"%s → next camp" % reason,
				next_camp.global_position,
				next_camp,
				50
			)
			_watchdog_status = "fallback CREEP"
			return

	## 5) ASSEMBLE
	if rally_point != Vector3.ZERO and _main_squad.get_size() > 0:
		_transition_to(State.ASSEMBLE, "%s → assemble" % reason, rally_point)
		_watchdog_status = "fallback ASSEMBLE"
		return

	## 6) RECOVER
	_transition_to(
		State.RECOVER,
		"%s → recover" % reason,
		rally_point if rally_point != Vector3.ZERO else get_designated_recovery_point()
	)
	_watchdog_status = "fallback RECOVER"


func _resolve_truthful_display(mission: ArmyMissionV2) -> Dictionary:
	var state_name: String = get_state_name()
	var mission_name: String = "-"
	var objective: String = "-"
	if mission != null:
		mission.sanitize_target_object()
		mission_name = mission.get_mission_type_name()
		objective = mission.get_objective_label()

	var tree: SceneTree = get_tree()
	var has_order: bool = not _watchdog_active_order.is_empty() and _watchdog_active_order != "-"

	## Never claim CREEP without a valid camp/order.
	if _state == State.CREEP:
		var camp_ok: bool = mission != null and mission.get_alive_target_object() != null
		if not camp_ok:
			state_name = "ASSEMBLE" if _main_squad.get_size() > 0 else "IDLE"
			mission_name = state_name
			objective = "invalid camp"
		elif tree != null and not _is_current_objective_valid(tree) and not has_order:
			state_name = "ASSEMBLE"
			mission_name = "ASSEMBLE"
			objective = "awaiting creep order"

	## Never claim ATTACK without an attack objective/order.
	if _state == State.ATTACK:
		var attack_ok: bool = (
			mission != null
			and (
				mission.get_alive_target_object() != null
				or mission.target_position != Vector3.ZERO
			)
		)
		if not attack_ok:
			state_name = "ASSEMBLE" if _main_squad.get_size() > 0 else "IDLE"
			mission_name = state_name
			objective = "no attack objective"

	## Never claim DEFEND without a current threat (or clear hold window).
	if _state == State.DEFEND:
		var defend_ok: bool = _defend_active or _defend_clear_timer > 0.0
		if tree != null:
			var threat: Dictionary = _resolve_v2_defense_threat(tree)
			defend_ok = defend_ok or VariantUtils.to_bool(threat.get("threatened", false))
		if not defend_ok:
			state_name = "ASSEMBLE" if _main_squad.get_size() > 0 else "IDLE"
			mission_name = state_name
			objective = "no active threat"

	return {
		"state": state_name,
		"mission": mission_name,
		"objective": objective,
	}


func _maybe_log_watchdog_diag() -> void:
	if _watchdog_diag_timer < MilitaryAIConfig.V2_WATCHDOG_DIAG_INTERVAL_SECONDS:
		return
	_watchdog_diag_timer = 0.0
	var signature: String = "%s|%s|%s|%.1f" % [
		get_state_name(),
		_watchdog_status,
		_watchdog_active_order,
		_watchdog_distance,
	]
	if signature == _watchdog_last_diag_signature:
		return
	_watchdog_last_diag_signature = signature
	EnemyAIDebug.log_once(
		"v2_watchdog",
		"V2 Watchdog: %s | order=%s | dist=%.1f | living=%d | combat=%s"
		% [
			_watchdog_status,
			_watchdog_active_order,
			_watchdog_distance,
			_watchdog_living_members,
			"yes" if _watchdog_recent_combat else "no",
		]
	)


## Test helpers for watchdog recovery scenarios.
func debug_get_watchdog_status() -> String:
	return _watchdog_status


func debug_get_watchdog_distance() -> float:
	return _watchdog_distance


func debug_force_watchdog_stall_for_tests() -> void:
	if _mission != null:
		_mission.last_progress_time_msec = (
			Time.get_ticks_msec()
			- int(MilitaryAIConfig.V2_WATCHDOG_STALL_SECONDS * 1000.0)
			- 500
		)
	_watchdog_timer = MilitaryAIConfig.V2_WATCHDOG_INTERVAL_SECONDS


func debug_tick_watchdog_for_tests() -> void:
	_tick_mission_watchdog(MilitaryAIConfig.V2_WATCHDOG_INTERVAL_SECONDS)


func debug_set_watchdog_refreshed_for_tests(value: bool) -> void:
	_watchdog_order_refreshed = value


func debug_is_watchdog_order_refreshed() -> bool:
	return _watchdog_order_refreshed


func debug_resolve_truthful_display_for_tests() -> Dictionary:
	return _resolve_truthful_display(_mission)
