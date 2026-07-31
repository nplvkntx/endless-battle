class_name UnitCombatDamage
extends RefCounted

## Compatibility helpers for combat-unit intake. Prefer DamageService.apply.


static func apply_incoming(
	victim: Node3D,
	_health: HealthComponent,
	attacker,
	damage_amount: int
) -> Variant:
	var result: Dictionary = DamageService.apply(
		victim,
		float(damage_amount),
		attacker,
		{
			DamageService.OPT_IGNORE_HOSTILITY: true,
			DamageService.OPT_BYPASS_ARMOR: true,
		}
	)
	if not bool(result.get(DamageService.RESULT_APPLIED, false)):
		return null
	return result.get(DamageService.RESULT_ATTACKER)


static func should_enemy_retaliate(victim: Node3D, attacker) -> bool:
	return (
		CombatTargetValidation.is_enemy_faction(victim)
		and attacker is Node3D
		and CombatTargetValidation.is_attack_target_for_attacker(victim, attacker)
		and EnemyUnitMission.allows_combat_micro(victim)
	)


static func compute_armored_damage(amount: float, armor: int) -> int:
	return DamageService.compute_armored_damage(amount, armor)
