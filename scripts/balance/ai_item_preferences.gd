class_name AIItemPreferences
extends RefCounted

## Centralized AI shop goal lists and situational reorder helpers.
## EnemyBuildManager reads this — keep shop logic out of hero scripts.

const BEHIND_HERO_HP_RATIO: float = 0.45
const BEHIND_ARMY_STRENGTH_RATIO: float = 0.75
const AHEAD_ARMY_STRENGTH_RATIO: float = 1.25

## Mutually exclusive finished items — owning one skips the other.
const ALTERNATIVE_GOAL_GROUPS: Array[Array] = [
	[HeroItemCatalog.ITEM_FORTRESS_HEART, HeroItemCatalog.ITEM_WARLORD_STANDARD],
]


static func get_base_goals(kit_id: StringName) -> Array[StringName]:
	match HeroCatalog.normalize_kit_id(kit_id):
		HeroCatalog.KIT_SHADOW_ASSASSIN:
			return [
				HeroItemCatalog.ITEM_EXECUTIONER_AXE,
				HeroItemCatalog.ITEM_VAMPIRE_BLADE,
				HeroItemCatalog.ITEM_CRESCENT_CLEAVER,
				HeroItemCatalog.ITEM_BLOODLORD_BLADE,
				HeroItemCatalog.ITEM_TITAN_CLEAVER,
			]
		HeroCatalog.KIT_RANGER:
			return [
				HeroItemCatalog.ITEM_HUNTER_BOOTS,
				HeroItemCatalog.ITEM_DEADEYE_BOW,
				HeroItemCatalog.ITEM_CRESCENT_CLEAVER,
				HeroItemCatalog.ITEM_PHANTOM_HUNTER,
			]
		_:
			return [
				HeroItemCatalog.ITEM_GUARDIAN_PLATE,
				HeroItemCatalog.ITEM_BATTLE_STANDARD,
				HeroItemCatalog.ITEM_FORTRESS_HEART,
				HeroItemCatalog.ITEM_WARLORD_STANDARD,
			]


static func get_survivability_goals(kit_id: StringName) -> Array[StringName]:
	match HeroCatalog.normalize_kit_id(kit_id):
		HeroCatalog.KIT_PALADIN:
			return [
				HeroItemCatalog.ITEM_GUARDIAN_PLATE,
				HeroItemCatalog.ITEM_BATTLE_STANDARD,
				HeroItemCatalog.ITEM_FORTRESS_HEART,
			]
		HeroCatalog.KIT_SHADOW_ASSASSIN:
			return [
				HeroItemCatalog.ITEM_VAMPIRE_BLADE,
				HeroItemCatalog.ITEM_BLOODLORD_BLADE,
			]
		HeroCatalog.KIT_RANGER:
			return [
				HeroItemCatalog.ITEM_VAMPIRE_BLADE,
				HeroItemCatalog.ITEM_HUNTER_BOOTS,
			]
		_:
			return []


static func get_damage_goals(kit_id: StringName) -> Array[StringName]:
	match HeroCatalog.normalize_kit_id(kit_id):
		HeroCatalog.KIT_PALADIN:
			return [
				HeroItemCatalog.ITEM_WARLORD_STANDARD,
				HeroItemCatalog.ITEM_ARCANE_FOCUS,
			]
		HeroCatalog.KIT_SHADOW_ASSASSIN:
			return [
				HeroItemCatalog.ITEM_EXECUTIONER_AXE,
				HeroItemCatalog.ITEM_CRESCENT_CLEAVER,
				HeroItemCatalog.ITEM_TITAN_CLEAVER,
				HeroItemCatalog.ITEM_BLOODLORD_BLADE,
			]
		HeroCatalog.KIT_RANGER:
			return [
				HeroItemCatalog.ITEM_DEADEYE_BOW,
				HeroItemCatalog.ITEM_CRESCENT_CLEAVER,
				HeroItemCatalog.ITEM_PHANTOM_HUNTER,
			]
		_:
			return []


static func get_situational_goals(kit_id: StringName, is_behind: bool, is_ahead: bool) -> Array[StringName]:
	var situational: Array[StringName] = []
	match HeroCatalog.normalize_kit_id(kit_id):
		HeroCatalog.KIT_PALADIN:
			if is_ahead:
				situational.append(HeroItemCatalog.ITEM_ARCANE_FOCUS)
		HeroCatalog.KIT_RANGER:
			if is_behind:
				situational.append(HeroItemCatalog.ITEM_VAMPIRE_BLADE)
	return situational


static func get_ordered_goals(
	kit_id: StringName,
	is_behind: bool,
	is_ahead: bool
) -> Array[StringName]:
	var base_goals: Array[StringName] = get_base_goals(kit_id)
	var situational: Array[StringName] = get_situational_goals(kit_id, is_behind, is_ahead)
	var combined: Array[StringName] = []
	for item_id: StringName in base_goals:
		if not combined.has(item_id):
			combined.append(item_id)
	for item_id: StringName in situational:
		if not combined.has(item_id):
			combined.append(item_id)

	if is_behind:
		return _prioritize_subset(combined, get_survivability_goals(kit_id))
	if is_ahead:
		return _prioritize_subset(combined, get_damage_goals(kit_id))
	return combined


static func should_skip_goal(hero: Hero, goal_id: StringName) -> bool:
	if hero == null:
		return true

	for group: Array in ALTERNATIVE_GOAL_GROUPS:
		if not group.has(goal_id):
			continue
		for other_id: Variant in group:
			var other: StringName = other_id as StringName
			if other == goal_id:
				continue
			if _hero_owns_item_id(hero, other):
				return true
	return false


static func is_unique_move_speed_item(item_id: StringName) -> bool:
	var definition: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	return definition != null and definition.is_unique_move_speed


static func _prioritize_subset(
	goals: Array[StringName],
	priority_ids: Array[StringName]
) -> Array[StringName]:
	var ordered: Array[StringName] = []
	for item_id: StringName in priority_ids:
		if goals.has(item_id) and not ordered.has(item_id):
			ordered.append(item_id)
	for item_id: StringName in goals:
		if not ordered.has(item_id):
			ordered.append(item_id)
	return ordered


static func _hero_owns_item_id(hero: Hero, item_id: StringName) -> bool:
	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition and (item as HeroItemDefinition).item_id == item_id:
			return true
	return false
