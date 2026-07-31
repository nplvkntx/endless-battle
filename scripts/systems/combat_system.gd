class_name CombatSystem
extends RefCounted

## Combat facade. All hit resolution goes through DamageService.
## Damage / armor types: DamageService + DamageArmorMatrix.
## Timed modifiers / CC: BuffService + BuffComponent (identity when unused).


static func apply_damage(
	target: Variant,
	amount: float,
	attacker = null,
	options: Dictionary = {}
) -> Dictionary:
	return DamageService.apply(target, amount, attacker, options)
