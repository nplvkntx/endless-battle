class_name CombatKillTracker
extends RefCounted

## Tracks the last unit that damaged a combat target for kill credit.

const LAST_ATTACKER_META := &"_last_damage_attacker"


static func record_attacker(victim, attacker) -> void:
	if not NodeSafety.is_alive_node(victim):
		return

	attacker = NodeSafety.safe_node(attacker) as Node
	if attacker == null:
		return

	victim.set_meta(LAST_ATTACKER_META, attacker)


static func get_attacker(victim) -> Node:
	if not NodeSafety.is_alive_node(victim):
		return null

	if not victim.has_meta(LAST_ATTACKER_META):
		return null

	var attacker: Variant = victim.get_meta(LAST_ATTACKER_META)
	if not NodeSafety.is_alive_node(attacker):
		return null

	return attacker as Node


static func clear_attacker_record(victim) -> void:
	if victim == null or not is_instance_valid(victim):
		return

	if victim.has_meta(LAST_ATTACKER_META):
		victim.remove_meta(LAST_ATTACKER_META)
