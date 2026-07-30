class_name UnitCombatDamage
extends RefCounted

## Shared incoming-damage pipeline for combat units (sanitize, kill credit, apply, float text).


static func apply_incoming(
	victim: Node3D,
	health: HealthComponent,
	attacker,
	damage_amount: int
) -> Variant:
	if health == null or health.current_health <= 0:
		return null

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(victim, attacker)
	health.take_damage(damage_amount)
	FloatingDamageNumber.spawn(victim, damage_amount)
	return attacker


static func should_enemy_retaliate(victim: Node3D, attacker) -> bool:
	return (
		CombatTargetValidation.is_enemy_faction(victim)
		and attacker is Node3D
		and CombatTargetValidation.is_attack_target_for_attacker(victim, attacker)
		and EnemyUnitMission.allows_combat_micro(victim)
	)


static func compute_armored_damage(amount: float, armor: int) -> int:
	return maxi(1, int(amount) - armor)
