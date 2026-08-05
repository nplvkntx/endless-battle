class_name MilitaryIntent
extends RefCounted

## Match-scoped military suggestion from a provider (defense / creep / wave / aggression).
## Providers never issue unit orders under V2 — MilitaryDirectorV2 arbitrates intents.
## Priority is absolute across kinds; score breaks ties within the same kind.
## Intents expire unless refreshed; cancelled intents cannot reactivate.

enum Kind {
	NONE = 0,
	DEFEND = 1,
	RETREAT = 2,
	FINISH = 3,
	ATTACK = 4,
	CREEP = 5,
	ASSEMBLE = 6,
	SUSPEND_CREEP = 7,
}

const PRIORITY_DEFEND := 100
const PRIORITY_RETREAT := 90
const PRIORITY_FINISH := 80
const PRIORITY_ATTACK := 60
const PRIORITY_SUSPEND_CREEP := 50
const PRIORITY_CREEP := 40
const PRIORITY_ASSEMBLE := 20

## Provider suggestions must be refreshed within this window or they die.
const DEFAULT_TTL_MSEC := 2500
## How long a director-accepted intent owns the mission slot.
const ACCEPTED_HOLD_MSEC := 4000
## Sole executable owner under V2 — providers must never claim this.
const MISSION_OWNER_COMMANDER := &"ArmyCommanderV2"

var kind: int = Kind.NONE
var priority: int = 0
var score: float = 0.0
var reason: StringName = &""
var source: StringName = &""
var target_position: Vector3 = Vector3.ZERO
var target_node: Node3D = null
## Optional provider payload (e.g. full defense threat Dictionary).
var payload: Dictionary = {}
var created_msec: int = 0
var expires_msec: int = 0
var cancelled: bool = false
## Who may execute if the director accepts this intent.
var mission_owner: StringName = MISSION_OWNER_COMMANDER


static func make(
	kind_value: int,
	priority_value: int,
	reason_value: StringName,
	source_value: StringName,
	score_value: float = 0.0,
	target_position_value: Vector3 = Vector3.ZERO,
	target_node_value: Node3D = null,
	payload_value: Dictionary = {},
	ttl_msec: int = DEFAULT_TTL_MSEC
) -> MilitaryIntent:
	var intent := MilitaryIntent.new()
	intent.kind = kind_value
	intent.priority = priority_value
	intent.reason = reason_value
	intent.source = source_value
	intent.score = score_value
	intent.target_position = target_position_value
	intent.target_node = target_node_value
	intent.payload = payload_value
	intent.mission_owner = MISSION_OWNER_COMMANDER
	intent.created_msec = Time.get_ticks_msec()
	intent.expires_msec = intent.created_msec + maxi(ttl_msec, 1)
	intent.cancelled = false
	return intent


static func make_defend(
	threat: Dictionary,
	source_value: StringName = &"defense"
) -> MilitaryIntent:
	var reason_value: StringName = threat.get("reason", &"base") as StringName
	var intercept: Vector3 = threat.get("intercept_position", Vector3.ZERO) as Vector3
	var is_emergency: bool = VariantUtils.to_bool(threat.get("emergency", true))
	return make(
		Kind.DEFEND,
		PRIORITY_DEFEND,
		reason_value,
		source_value,
		100.0 if is_emergency else 70.0,
		intercept,
		null,
		threat.duplicate(true)
	)


static func make_creep(
	reason_value: StringName = &"safe_camp",
	score_value: float = 50.0,
	camp: Node3D = null,
	source_value: StringName = &"creep"
) -> MilitaryIntent:
	var position: Vector3 = Vector3.ZERO
	if camp != null and is_instance_valid(camp):
		position = camp.global_position
	return make(
		Kind.CREEP,
		PRIORITY_CREEP,
		reason_value,
		source_value,
		score_value,
		position,
		camp
	)


static func make_attack(
	reason_value: StringName,
	score_value: float,
	source_value: StringName = &"wave",
	target_position_value: Vector3 = Vector3.ZERO,
	target_node_value: Node3D = null
) -> MilitaryIntent:
	return make(
		Kind.ATTACK,
		PRIORITY_ATTACK,
		reason_value,
		source_value,
		score_value,
		target_position_value,
		target_node_value
	)


static func make_finish(
	reason_value: StringName = &"finishing",
	score_value: float = 90.0,
	source_value: StringName = &"wave"
) -> MilitaryIntent:
	return make(
		Kind.FINISH,
		PRIORITY_FINISH,
		reason_value,
		source_value,
		score_value
	)


static func make_suspend_creep(
	reason_value: StringName = &"aggression",
	source_value: StringName = &"aggression"
) -> MilitaryIntent:
	return make(
		Kind.SUSPEND_CREEP,
		PRIORITY_SUSPEND_CREEP,
		reason_value,
		source_value,
		80.0
	)


func ensure_timestamps() -> void:
	if created_msec <= 0:
		created_msec = Time.get_ticks_msec()
	if expires_msec <= 0:
		expires_msec = created_msec + DEFAULT_TTL_MSEC


func is_expired(now_msec: int = -1) -> bool:
	ensure_timestamps()
	var now: int = now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return now > expires_msec


func cancel() -> void:
	cancelled = true
	expires_msec = Time.get_ticks_msec()


func is_actionable(now_msec: int = -1) -> bool:
	if cancelled:
		return false
	if is_expired(now_msec):
		return false
	if kind == Kind.NONE:
		return false
	return true


func kind_label() -> String:
	match kind:
		Kind.DEFEND:
			return "DEFEND"
		Kind.RETREAT:
			return "RETREAT"
		Kind.FINISH:
			return "FINISH"
		Kind.ATTACK:
			return "ATTACK"
		Kind.CREEP:
			return "CREEP"
		Kind.ASSEMBLE:
			return "ASSEMBLE"
		Kind.SUSPEND_CREEP:
			return "SUSPEND_CREEP"
		_:
			return "NONE"
