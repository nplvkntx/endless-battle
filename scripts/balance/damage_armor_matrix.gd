class_name DamageArmorMatrix
extends RefCounted

## Damage-type × armor-type multipliers for combat.
## Rebalance values here only; do not scatter type multipliers elsewhere.
##
## Row order matches DamageService.DamageType:
##   PHYSICAL, PIERCE, MAGIC, SIEGE, TRUE
## Column order matches DamageService.ArmorType:
##   LIGHT, MEDIUM, HEAVY, HERO, BUILDING

const MULTIPLIERS: Array[Array] = [
	# LIGHT  MEDIUM  HEAVY  HERO  BUILDING
	[1.00, 1.00, 0.90, 0.90, 0.70], # PHYSICAL
	[1.25, 1.00, 0.75, 0.80, 0.50], # PIERCE
	[1.00, 1.10, 1.20, 0.85, 0.50], # MAGIC
	[0.60, 0.60, 0.75, 0.50, 1.50], # SIEGE
	[1.00, 1.00, 1.00, 1.00, 1.00], # TRUE (ignores armor after matrix)
]


static func get_multiplier(damage_type: int, armor_type: int) -> float:
	if (
		damage_type < 0
		or damage_type >= MULTIPLIERS.size()
		or armor_type < 0
		or armor_type >= MULTIPLIERS[damage_type].size()
	):
		return 1.0
	return float(MULTIPLIERS[damage_type][armor_type])
