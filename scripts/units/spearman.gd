class_name Spearman
extends MilitaryUnit

## Tier 1 melee infantry.


func _init() -> void:
	attack_damage = UnitStats.SPEARMAN_ATTACK_DAMAGE
	attack_range = UnitStats.SPEARMAN_ATTACK_RANGE
	attack_cooldown = UnitStats.SPEARMAN_ATTACK_COOLDOWN
	armor = UnitStats.SPEARMAN_ARMOR
	damage_type = DamageService.DamageType.PIERCE
	armor_type = DamageService.ArmorType.MEDIUM


func modify_outgoing_damage(amount: float, target: Object, _damage_type: int) -> float:
	if _is_cavalry_target(target):
		return amount * UnitStats.SPEARMAN_CAVALRY_DAMAGE_MULTIPLIER
	return amount


func _is_cavalry_target(target: Object) -> bool:
	if target == null:
		return false
	return target is LightCavalry or target is CavalryArcher or target is HeavyCavalry
