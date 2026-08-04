class_name MilitaryDirectorV2
extends Node

## Sole strategic decision-maker for the main army under Military AI V2.
## Owns exactly one active state and publishes the current ArmyMissionV2.
## Does not issue unit orders — ArmyCommanderV2 executes the mission.
##
## Foundation task: stays IDLE. Advanced creep/attack/defend behavior is not migrated yet.

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

var _state: State = State.IDLE
var _mission: ArmyMissionV2 = null
var _last_transition_reason: String = "match start"
var _match_start_msec: int = 0
var _tick_timer: float = 0.0
var _commander: ArmyCommanderV2 = null


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
	_publish_perf_status()


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		set_process(false)
		return

	_tick_timer += delta
	if _tick_timer < TICK_SECONDS:
		return

	_tick_timer = 0.0
	_evaluate_strategy()
	_publish_perf_status()
	PerfCounters.record_ai_decision_update()


func _evaluate_strategy() -> void:
	## Foundation: hold IDLE. No advanced mission selection yet.
	if _mission == null:
		_transition_to(State.IDLE, "initialize idle mission")
		return

	_mission.sanitize_target_object()
	if _state != State.IDLE:
		_transition_to(State.IDLE, "foundation holds idle (advanced behavior not migrated)")


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


## Strategic API for future behavior / tests. Commander must not call this for self-decisions.
func request_state(
	next_state: State,
	reason: String,
	target_position: Vector3 = Vector3.ZERO,
	target_object: Node3D = null,
	priority: int = 0
) -> bool:
	if not MilitaryAIConfig.is_v2_enabled():
		return false
	return _transition_to(next_state, reason, target_position, target_object, priority)


func _transition_to(
	next_state: State,
	reason: String,
	target_position: Vector3 = Vector3.ZERO,
	target_object: Node3D = null,
	priority: int = 0
) -> bool:
	if _state == next_state and _mission != null and _mission.mission_type == _state_to_mission_type(next_state):
		if reason != _last_transition_reason and not reason.is_empty():
			_last_transition_reason = reason
			_mission.transition_reason = reason
		return false

	if _mission != null and _state != next_state:
		_mission.mark_cancelled("superseded: %s" % reason)

	_state = next_state
	_last_transition_reason = reason if not reason.is_empty() else "unspecified"
	_mission = ArmyMissionV2.new(
		_state_to_mission_type(next_state),
		target_position,
		target_object,
		priority,
		_last_transition_reason
	)
	_publish_perf_status()
	return true


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


func _publish_perf_status() -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		return

	var mission: ArmyMissionV2 = _mission
	var mission_name: String = "-"
	var objective: String = "-"
	var age_seconds: float = 0.0
	if mission != null:
		mission.sanitize_target_object()
		mission_name = mission.get_mission_type_name()
		objective = mission.get_objective_label()
		age_seconds = mission.get_age_seconds()

	PerfCounters.set_military_ai_v2_status(
		MilitaryAIConfig.ai_version_label(),
		get_state_name(),
		mission_name,
		objective,
		age_seconds,
		_last_transition_reason
	)
	## Keep legacy AI status fields filled so older overlay lines stay coherent under V2.
	PerfCounters.set_ai_status(get_state_name(), mission_name, "MilitaryDirectorV2")
	PerfCounters.set_ai_mission_detail(
		"V2 %s → %s (%s)" % [get_state_name(), objective, _last_transition_reason]
	)
