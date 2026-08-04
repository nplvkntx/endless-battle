class_name ArmyMissionV2
extends RefCounted

## Immutable-ish mission payload owned by MilitaryDirectorV2.
## ArmyCommanderV2 reads this; it never invents strategic missions.

enum MissionType {
	NONE,
	IDLE,
	ASSEMBLE,
	CREEP,
	ATTACK,
	DEFEND,
	RETREAT,
	RECOVER,
}

enum CompletionCondition {
	NONE,
	ARRIVED,
	TARGET_DESTROYED,
	THREAT_CLEARED,
	ARMY_SAFE,
	TIMEOUT,
	CANCELLED,
	MANUAL,
}

var mission_type: MissionType = MissionType.NONE
var target_position: Vector3 = Vector3.ZERO
## Optional validated target. Cleared automatically when freed.
var target_object: Node3D = null
var priority: int = 0
var creation_time_msec: int = 0
var last_progress_time_msec: int = 0
var completion_condition: CompletionCondition = CompletionCondition.NONE
var transition_reason: String = ""
var cancellation_reason: String = ""


func _init(
	p_mission_type: MissionType = MissionType.NONE,
	p_target_position: Vector3 = Vector3.ZERO,
	p_target_object: Node3D = null,
	p_priority: int = 0,
	p_transition_reason: String = ""
) -> void:
	var now_msec: int = Time.get_ticks_msec()
	mission_type = p_mission_type
	target_position = p_target_position
	target_object = p_target_object
	priority = p_priority
	creation_time_msec = now_msec
	last_progress_time_msec = now_msec
	transition_reason = p_transition_reason
	completion_condition = CompletionCondition.NONE
	cancellation_reason = ""


static func mission_type_to_string(mission_type_value: MissionType) -> String:
	match mission_type_value:
		MissionType.NONE:
			return "NONE"
		MissionType.IDLE:
			return "IDLE"
		MissionType.ASSEMBLE:
			return "ASSEMBLE"
		MissionType.CREEP:
			return "CREEP"
		MissionType.ATTACK:
			return "ATTACK"
		MissionType.DEFEND:
			return "DEFEND"
		MissionType.RETREAT:
			return "RETREAT"
		MissionType.RECOVER:
			return "RECOVER"
		_:
			return "UNKNOWN"


static func completion_condition_to_string(condition: CompletionCondition) -> String:
	match condition:
		CompletionCondition.NONE:
			return "NONE"
		CompletionCondition.ARRIVED:
			return "ARRIVED"
		CompletionCondition.TARGET_DESTROYED:
			return "TARGET_DESTROYED"
		CompletionCondition.THREAT_CLEARED:
			return "THREAT_CLEARED"
		CompletionCondition.ARMY_SAFE:
			return "ARMY_SAFE"
		CompletionCondition.TIMEOUT:
			return "TIMEOUT"
		CompletionCondition.CANCELLED:
			return "CANCELLED"
		CompletionCondition.MANUAL:
			return "MANUAL"
		_:
			return "UNKNOWN"


func get_mission_type_name() -> String:
	return mission_type_to_string(mission_type)


func get_age_seconds() -> float:
	return float(Time.get_ticks_msec() - creation_time_msec) / 1000.0


func get_seconds_since_progress() -> float:
	return float(Time.get_ticks_msec() - last_progress_time_msec) / 1000.0


func note_progress() -> void:
	last_progress_time_msec = Time.get_ticks_msec()


func has_valid_target_object() -> bool:
	return target_object != null and is_instance_valid(target_object)


func sanitize_target_object() -> void:
	if target_object != null and not is_instance_valid(target_object):
		target_object = null


func get_objective_label() -> String:
	sanitize_target_object()
	if has_valid_target_object():
		return String(target_object.name)
	if target_position != Vector3.ZERO:
		return "(%.0f, %.0f)" % [target_position.x, target_position.z]
	return "-"


func mark_cancelled(reason: String) -> void:
	cancellation_reason = reason
	completion_condition = CompletionCondition.CANCELLED


func duplicate_mission() -> ArmyMissionV2:
	var copy := ArmyMissionV2.new(
		mission_type,
		target_position,
		target_object if has_valid_target_object() else null,
		priority,
		transition_reason
	)
	copy.creation_time_msec = creation_time_msec
	copy.last_progress_time_msec = last_progress_time_msec
	copy.completion_condition = completion_condition
	copy.cancellation_reason = cancellation_reason
	return copy
