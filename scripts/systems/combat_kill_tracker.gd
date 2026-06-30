class_name CombatKillTracker
extends RefCounted

## Tracks the last unit that damaged a combat target for kill credit.

const LAST_ATTACKER_META := &"_last_damage_attacker"


static func record_attacker(victim: Node, attacker: Node) -> void:
	if victim == null or attacker == null or not is_instance_valid(attacker):
		return

	victim.set_meta(LAST_ATTACKER_META, attacker)


static func get_attacker(victim: Node) -> Node:
	if victim == null or not victim.has_meta(LAST_ATTACKER_META):
		return null

	var attacker: Variant = victim.get_meta(LAST_ATTACKER_META)
	if attacker == null or not attacker is Node or not is_instance_valid(attacker as Node):
		return null

	return attacker as Node
