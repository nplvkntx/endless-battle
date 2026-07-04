class_name FloatingRewardText
extends RefCounted

## Displays floating XP and gold labels at a kill location using the damage number visuals.

const XP_COLOR := Color(0.35, 0.65, 1.0, 1.0)
const GOLD_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const HORIZONTAL_OFFSET := 0.35


static func spawn(victim: Node, xp_amount: int, gold_amount: int) -> void:
	if victim == null or not is_instance_valid(victim):
		return

	if xp_amount <= 0 and gold_amount <= 0:
		return

	if not victim is Node3D:
		return

	var victim_3d: Node3D = victim as Node3D
	var spawn_base: Vector3 = victim_3d.global_position + Vector3(0.0, FloatingDamageNumber.SPAWN_HEIGHT, 0.0)

	if xp_amount > 0 and gold_amount > 0:
		FloatingDamageNumber.spawn_message_at_position(
			victim,
			"+%d XP" % xp_amount,
			spawn_base + Vector3(-HORIZONTAL_OFFSET, 0.0, 0.0),
			XP_COLOR
		)
		FloatingDamageNumber.spawn_message_at_position(
			victim,
			"+%d Gold" % gold_amount,
			spawn_base + Vector3(HORIZONTAL_OFFSET, 0.0, 0.0),
			GOLD_COLOR
		)
		return

	if xp_amount > 0:
		FloatingDamageNumber.spawn_message_at_position(
			victim,
			"+%d XP" % xp_amount,
			spawn_base,
			XP_COLOR
		)

	if gold_amount > 0:
		FloatingDamageNumber.spawn_message_at_position(
			victim,
			"+%d Gold" % gold_amount,
			spawn_base,
			GOLD_COLOR
		)
