class_name CombatKillTracker
extends RefCounted

## Tracks the last unit that damaged a combat target for kill credit.
## Also stores damage time so defense AI can expire stale attacker memory.

const LAST_ATTACKER_META := &"_last_damage_attacker"
const LAST_DAMAGE_MSEC_META := &"_last_damage_msec"


static func record_attacker(victim, attacker) -> void:
	if not NodeSafety.is_alive_node(victim):
		return

	attacker = NodeSafety.safe_node(attacker) as Node
	if attacker == null:
		return

	victim.set_meta(LAST_ATTACKER_META, attacker)
	victim.set_meta(LAST_DAMAGE_MSEC_META, Time.get_ticks_msec())


static func get_attacker(victim) -> Node:
	if not NodeSafety.is_alive_node(victim):
		return null

	if not victim.has_meta(LAST_ATTACKER_META):
		return null

	var attacker: Variant = victim.get_meta(LAST_ATTACKER_META)
	if not NodeSafety.is_alive_node(attacker):
		return null

	return attacker as Node


## Seconds since the last recorded hit, or INF when unknown / never hit.
static func get_last_damage_age_seconds(victim) -> float:
	if not NodeSafety.is_alive_node(victim):
		return INF
	if not victim.has_meta(LAST_DAMAGE_MSEC_META):
		return INF
	var msec: int = int(victim.get_meta(LAST_DAMAGE_MSEC_META))
	if msec <= 0:
		return INF
	return float(Time.get_ticks_msec() - msec) / 1000.0


static func was_damaged_recently(victim, window_seconds: float) -> bool:
	if window_seconds <= 0.0:
		return false
	return get_last_damage_age_seconds(victim) <= window_seconds


static func clear_attacker_record(victim) -> void:
	if victim == null or not is_instance_valid(victim):
		return

	if victim.has_meta(LAST_ATTACKER_META):
		victim.remove_meta(LAST_ATTACKER_META)
	if victim.has_meta(LAST_DAMAGE_MSEC_META):
		victim.remove_meta(LAST_DAMAGE_MSEC_META)
