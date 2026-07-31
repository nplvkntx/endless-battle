class_name UnitFoodSupply
extends RefCounted

## Shared population food cost for trained units — edit UnitStats / HeroStats only.


static func get_cost(unit: Node) -> int:
	if unit == null or not is_instance_valid(unit):
		return 0

	if unit is Worker:
		return UnitStats.WORKER_FOOD_COST
	if unit is Spearman or unit is Swordsman or unit is Archer:
		return UnitStats.SWORDSMAN_FOOD_COST
	if unit is LightCavalry or unit is CavalryArcher:
		return UnitStats.LIGHT_CAVALRY_FOOD_COST
	if unit is HeavyCavalry:
		return UnitStats.HEAVY_CAVALRY_FOOD_COST
	if unit is Cannon:
		return UnitStats.CANNON_FOOD_COST
	if unit is Hero:
		return HeroStats.TRAIN_FOOD_COST

	return 0
