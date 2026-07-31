class_name DamageArmorMatrix
extends RefCounted

## Damage-type × armor-type multipliers for combat.
## Temporary identity table (all 1.0) — live combat numbers stay unchanged.
## Rebalance values here later; do not scatter type multipliers elsewhere.
##
## Row order matches DamageService.DamageType:
##   PHYSICAL, PIERCE, MAGIC, SIEGE, TRUE
## Column order matches DamageService.ArmorType:
##   LIGHT, MEDIUM, HEAVY, HERO, BUILDING

const MULTIPLIERS: Array[Array] = [
	# LIGHT  MEDIUM  HEAVY  HERO  BUILDING
	[1.0, 1.0, 1.0, 1.0, 1.0], # PHYSICAL
	[1.0, 1.0, 1.0, 1.0, 1.0], # PIERCE
	[1.0, 1.0, 1.0, 1.0, 1.0], # MAGIC
	[1.0, 1.0, 1.0, 1.0, 1.0], # SIEGE
	[1.0, 1.0, 1.0, 1.0, 1.0], # TRUE
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
