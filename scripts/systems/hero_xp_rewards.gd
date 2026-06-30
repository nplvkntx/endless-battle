class_name HeroXpRewards
extends RefCounted

## Grants hero XP when valid combat targets are killed. Reusable for player and future AI heroes.

const NEUTRAL_CREEP_XP: int = 50
const ENEMY_UNIT_XP: int = 75


static func notify_unit_killed(victim: Node) -> void:
	grant_for_kill(victim, CombatKillTracker.get_attacker(victim))


static func grant_for_kill(victim: Node, killer: Node) -> void:
	var hero: Hero = _resolve_hero_recipient(killer)
	if hero == null:
		return

	var xp_amount: int = get_xp_amount_for_victim(victim)
	if xp_amount <= 0:
		return

	hero.add_xp(float(xp_amount))


static func get_xp_amount_for_victim(victim: Node) -> int:
	if victim == null:
		return 0

	if CombatTargetValidation.is_neutral_creep(victim):
		return NEUTRAL_CREEP_XP

	if victim is Swordsman or victim is Archer:
		if CombatTargetValidation.is_enemy_faction(victim):
			return ENEMY_UNIT_XP
		return 0

	if victim is EnemyDummy:
		return ENEMY_UNIT_XP

	return 0


static func _resolve_hero_recipient(killer: Node) -> Hero:
	if killer is Hero:
		return killer as Hero

	return null
