class_name HeroXpRewards
extends RefCounted

## Grants hero XP and kill gold when valid combat targets are killed.

const CREEP_XP_WEAK: int = 25
const CREEP_XP_MEDIUM: int = 50
const CREEP_XP_STRONG: int = 100
const CREEP_GOLD_WEAK: int = 5
const CREEP_GOLD_MEDIUM: int = 10
const CREEP_GOLD_STRONG: int = 20

const WORKER_XP: int = 10
const WORKER_GOLD: int = 2
const MILITARY_XP: int = 25
const MILITARY_GOLD: int = 5
const ENEMY_HERO_XP: int = 150
const ENEMY_HERO_GOLD: int = 50

const CREEP_XP_SHARE_RANGE: float = 18.0


static func notify_unit_killed(victim: Node) -> void:
	var killer: Node = CombatKillTracker.get_attacker(victim)
	grant_for_kill(victim, killer)


static func grant_for_kill(victim: Node, killer: Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return

	var xp_amount: int = get_xp_amount_for_victim(victim)
	if xp_amount > 0:
		var hero: Hero = _resolve_hero_recipient(victim, killer)
		if hero != null and is_instance_valid(hero):
			hero.add_xp(float(xp_amount))

	var gold_amount: int = get_gold_amount_for_victim(victim)
	if gold_amount > 0 and _should_grant_player_gold(victim, killer):
		ResourceManager.add_gold(gold_amount)


static func get_xp_amount_for_victim(victim: Node) -> int:
	if victim == null:
		return 0

	if CombatTargetValidation.is_neutral_creep(victim):
		return _get_creep_reward_tier(victim).get("xp", 0)

	if victim is Worker:
		if CombatTargetValidation.is_enemy_faction(victim):
			return WORKER_XP
		return 0

	if victim is Hero:
		if CombatTargetValidation.is_enemy_faction(victim):
			return ENEMY_HERO_XP
		return 0

	if victim is Swordsman or victim is Archer:
		if CombatTargetValidation.is_enemy_faction(victim):
			return MILITARY_XP
		return 0

	if victim is EnemyDummy:
		return MILITARY_XP

	return 0


static func get_gold_amount_for_victim(victim: Node) -> int:
	if victim == null:
		return 0

	if CombatTargetValidation.is_neutral_creep(victim):
		return _get_creep_reward_tier(victim).get("gold", 0)

	if victim is Worker:
		if CombatTargetValidation.is_enemy_faction(victim):
			return WORKER_GOLD
		return 0

	if victim is Hero:
		if CombatTargetValidation.is_enemy_faction(victim):
			return ENEMY_HERO_GOLD
		return 0

	if victim is Swordsman or victim is Archer:
		if CombatTargetValidation.is_enemy_faction(victim):
			return MILITARY_GOLD
		return 0

	if victim is EnemyDummy:
		return MILITARY_GOLD

	return 0


static func _get_creep_reward_tier(victim: Node) -> Dictionary:
	var attack_damage: int = 8
	if "attack_damage" in victim:
		attack_damage = int(victim.get("attack_damage"))

	if attack_damage <= 8:
		return {"xp": CREEP_XP_WEAK, "gold": CREEP_GOLD_WEAK}
	if attack_damage <= 12:
		return {"xp": CREEP_XP_MEDIUM, "gold": CREEP_GOLD_MEDIUM}

	return {"xp": CREEP_XP_STRONG, "gold": CREEP_GOLD_STRONG}


static func _should_grant_player_gold(victim: Node, killer: Node) -> bool:
	if killer != null and CombatTargetValidation.is_enemy_faction(killer):
		return false

	if CombatTargetValidation.is_neutral_creep(victim):
		return _is_player_controlled_unit(killer) or _is_player_hero(killer)

	return _is_enemy_army_victim(victim) and (
		_is_player_controlled_unit(killer) or _is_player_hero(killer)
	)


static func _resolve_hero_recipient(victim: Node, killer: Node) -> Hero:
	if victim != null and CombatTargetValidation.is_neutral_creep(victim):
		return _resolve_player_hero_for_creep_kill(victim, killer)

	if not _is_enemy_army_victim(victim):
		return null

	if killer != null and CombatTargetValidation.is_enemy_faction(killer):
		return null

	if not _is_player_controlled_unit(killer) and not _is_player_hero(killer):
		return null

	return _find_living_player_hero(victim)


static func _is_enemy_army_victim(victim: Node) -> bool:
	if victim == null or not is_instance_valid(victim):
		return false

	if victim is Worker or victim is Swordsman or victim is Archer or victim is Hero:
		return CombatTargetValidation.is_enemy_faction(victim)

	if victim is EnemyDummy and not CombatTargetValidation.is_neutral_creep(victim):
		return true

	return false


static func _resolve_player_hero_for_creep_kill(victim: Node, killer: Node) -> Hero:
	var hero: Hero = _find_living_player_hero(victim)
	if hero == null:
		return null

	if _is_player_hero(killer):
		return hero

	if killer != null and CombatTargetValidation.is_enemy_faction(killer):
		return null

	if not _is_within_creep_xp_range(hero, victim):
		return null

	if _is_player_controlled_unit(killer):
		return hero

	return hero


static func _find_living_player_hero(context: Node) -> Hero:
	if context == null or not is_instance_valid(context):
		return null

	var tree: SceneTree = context.get_tree()
	if tree == null:
		return null

	for node: Node in tree.get_nodes_in_group(&"heroes"):
		if not _is_player_hero(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		return node as Hero

	return null


static func _is_player_hero(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if not node is Hero:
		return false

	return (node as Node).is_in_group(&"heroes")


static func _is_player_controlled_unit(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if CombatTargetValidation.is_enemy_faction(node):
		return false

	if node is Hero:
		return _is_player_hero(node)

	if node is Swordsman or node is Archer or node is Worker:
		return (node as Node).is_in_group(&"units")

	return false


static func _is_within_creep_xp_range(hero: Node3D, victim: Node) -> bool:
	if hero == null or victim == null:
		return false

	if not is_instance_valid(hero) or not is_instance_valid(victim):
		return false

	var hero_position: Vector3 = hero.global_position
	var victim_position: Vector3 = victim.global_position
	if victim is Node3D:
		victim_position = (victim as Node3D).global_position

	var offset: Vector3 = hero_position - victim_position
	offset.y = 0.0
	return offset.length_squared() <= CREEP_XP_SHARE_RANGE * CREEP_XP_SHARE_RANGE
