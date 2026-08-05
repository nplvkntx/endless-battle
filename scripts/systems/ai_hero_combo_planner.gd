extends RefCounted

## Small reusable non-blocking combo planner for AI hero ability sequences.
## Steps advance on each mastery tick; timeouts skip optional steps or abort mandatory ones.

const ACTION_Q := &"q"
const ACTION_W := &"w"
const ACTION_E := &"e"
const ACTION_R := &"r"
const ACTION_ATTACK := &"attack"
const ACTION_APPROACH := &"approach"

var _active: bool = false
var _steps: Array[Dictionary] = []
var _index: int = 0
var _step_started_at: float = 0.0
var _target_id: int = 0
var _abort_reason: String = ""


static func make_step(
	action: StringName,
	requires_target: bool = true,
	range_required: float = -1.0,
	timeout: float = 2.0,
	optional: bool = false,
	fallback_index: int = -1
) -> Dictionary:
	return {
		"action": action,
		"requires_target": requires_target,
		"range_required": range_required,
		"timeout": timeout,
		"optional": optional,
		"fallback_index": fallback_index,
	}


func is_active() -> bool:
	return _active


func get_abort_reason() -> String:
	return _abort_reason


func get_current_action() -> StringName:
	if not _active or _index < 0 or _index >= _steps.size():
		return &""
	return StringName(str(_steps[_index].get("action", "")))


func get_target_id() -> int:
	return _target_id


func start(steps: Array[Dictionary], target: Node3D, now_seconds: float) -> void:
	_steps = steps.duplicate()
	_index = 0
	_step_started_at = now_seconds
	_abort_reason = ""
	_target_id = target.get_instance_id() if NodeSafety.is_alive_node(target) else 0
	_active = not _steps.is_empty()


func abort(reason: String) -> void:
	_active = false
	_abort_reason = reason
	_steps.clear()
	_index = 0
	_target_id = 0


func clear() -> void:
	_active = false
	_abort_reason = ""
	_steps.clear()
	_index = 0
	_target_id = 0
	_step_started_at = 0.0


## Returns a result dictionary:
## { active, done, aborted, reason, action, requires_target, range_required }
func tick(now_seconds: float, target_valid: bool, in_range: bool) -> Dictionary:
	if not _active:
		return {"active": false, "done": false, "aborted": false}

	if _index >= _steps.size():
		_active = false
		return {"active": false, "done": true, "aborted": false}

	var step: Dictionary = _steps[_index]
	var requires_target: bool = VariantUtils.to_bool(step.get("requires_target", true))
	if requires_target and not target_valid:
		abort("target invalid")
		return {
			"active": false,
			"done": false,
			"aborted": true,
			"reason": _abort_reason,
		}

	var range_required: float = float(step.get("range_required", -1.0))
	var needs_range: bool = range_required > 0.0
	var timed_out: bool = (now_seconds - _step_started_at) >= float(step.get("timeout", 2.0))

	if needs_range and not in_range and not timed_out:
		return {
			"active": true,
			"done": false,
			"aborted": false,
			"action": StringName(str(step.get("action", ""))),
			"requires_target": requires_target,
			"range_required": range_required,
			"waiting_for_range": true,
		}

	if timed_out and needs_range and not in_range:
		return _advance_or_skip(step, now_seconds, "range timeout")

	return {
		"active": true,
		"done": false,
		"aborted": false,
		"action": StringName(str(step.get("action", ""))),
		"requires_target": requires_target,
		"range_required": range_required,
		"waiting_for_range": false,
		"optional": VariantUtils.to_bool(step.get("optional", false)),
	}


func mark_step_succeeded(now_seconds: float) -> void:
	if not _active:
		return
	_index += 1
	_step_started_at = now_seconds
	if _index >= _steps.size():
		_active = false


func mark_step_failed(now_seconds: float, reason: String = "step failed") -> Dictionary:
	if not _active or _index >= _steps.size():
		abort(reason)
		return {"active": false, "done": false, "aborted": true, "reason": reason}

	var step: Dictionary = _steps[_index]
	return _advance_or_skip(step, now_seconds, reason)


func _advance_or_skip(step: Dictionary, now_seconds: float, reason: String) -> Dictionary:
	var optional: bool = VariantUtils.to_bool(step.get("optional", false))
	var fallback_index: int = int(step.get("fallback_index", -1))

	if optional:
		if fallback_index >= 0 and fallback_index < _steps.size():
			_index = fallback_index
		else:
			_index += 1
		_step_started_at = now_seconds
		if _index >= _steps.size():
			_active = false
			return {"active": false, "done": true, "aborted": false, "reason": reason}
		return {"active": true, "done": false, "aborted": false, "skipped": true, "reason": reason}

	abort(reason)
	return {"active": false, "done": false, "aborted": true, "reason": _abort_reason}
