class_name UnitFoodSupply
extends RefCounted

## Shared population food cost for trained units. Keep in sync with building train costs.


static func get_cost(unit: Node) -> int:
	if unit == null or not is_instance_valid(unit):
		return 0

	if unit is Worker:
		return CommandCenter.TRAIN_FOOD_COST
	if unit is Spearman or unit is Swordsman or unit is Archer:
		return Barracks.TRAIN_FOOD_COST
	if unit is LightCavalry or unit is CavalryArcher:
		return Stable.TRAIN_FOOD_COST
	if unit is HeavyCavalry:
		return Stable.HEAVY_CAVALRY_TRAIN_FOOD_COST
	if unit is Cannon:
		return ArtilleryDepot.CANNON_TRAIN_FOOD_COST
	if unit is Hero:
		return HeroAltar.TRAIN_FOOD_COST

	return 0
