class_name HeroItemDefinition
extends Resource

## Data for a hero / neutral inventory item.
## Flat bonus_* fields remain the live apply path for existing shop items.
## Modular components, recipes, actives, auras, and procs are framework scaffolding.

const SELL_VALUE_USE_RATIO := -1

enum Tier {
	TIER_1 = 1,
	TIER_2 = 2,
	TIER_3 = 3,
}

enum Category {
	NONE = 0,
	BASIC = 1,
	WEAPON = 2,
	ARMOR = 3,
	BOOTS = 4,
	MAGIC = 5,
	CONSUMABLE = 6,
	NEUTRAL = 7,
	ARTIFACT = 8,
}

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var gold_cost: int = 0
@export var hotkey: String = ""
@export var icon_color: Color = Color(0.55, 0.58, 0.65, 1)

@export var tier: Tier = Tier.TIER_1
@export var category: Category = Category.BASIC
## -1 = floor(gold_cost * ItemStats.SELL_REFUND_RATIO).
@export var sell_value: int = SELL_VALUE_USE_RATIO
@export var is_neutral: bool = false
@export var is_consumable: bool = false
@export var is_active_item: bool = false

## Ingredient item_ids consumed when combining into this item (empty = not craftable).
@export var recipe_component_ids: Array[StringName] = []
## Extra gold paid on combine. -1 = use gold_cost as the combine gold cost.
@export var recipe_gold_cost: int = -1

## Modular effect pieces (passives, actives, auras, procs, optional stats).
@export var components: Array[ItemComponent] = []

## Convenience unique-passive key (also discoverable via ItemPassiveComponent).
@export var unique_passive_id: StringName = &""

## Convenience active fields when is_active_item is true (or use ItemActiveComponent).
@export var active_cooldown: float = 0.0
@export var max_charges: int = 0
## -1 = start at max_charges.
@export var starting_charges: int = -1
@export var active_mana_cost: int = 0

# --- Flat stat bonuses (existing shop items; identity defaults) ---
@export var bonus_attack_damage: int = 0
@export var bonus_max_health: int = 0
@export var heal_on_purchase: int = 0
@export var bonus_move_speed: float = 0.0
@export var bonus_max_mana: int = 0
@export var restore_mana_on_purchase: int = 0
@export var bonus_ability_power: int = 0
@export var bonus_cooldown_reduction: float = 0.0
@export var bonus_mana_cost_reduction: float = 0.0
@export var bonus_spell_radius: float = 0.0


func get_sell_value() -> int:
	if sell_value >= 0:
		return sell_value
	return int(gold_cost * ItemStats.SELL_REFUND_RATIO)


func has_recipe() -> bool:
	return not recipe_component_ids.is_empty()


func get_recipe_gold_cost() -> int:
	if recipe_gold_cost >= 0:
		return recipe_gold_cost
	return gold_cost


func has_active() -> bool:
	if is_active_item:
		return true
	return get_active_component() != null


func uses_charges() -> bool:
	var active: ItemActiveComponent = get_active_component()
	if active != null:
		return active.uses_charges()
	return max_charges > 0


func get_active_cooldown() -> float:
	var active: ItemActiveComponent = get_active_component()
	if active != null:
		return active.cooldown
	return active_cooldown


func get_max_charges() -> int:
	var active: ItemActiveComponent = get_active_component()
	if active != null:
		return active.max_charges
	return max_charges


func get_starting_charges() -> int:
	var active: ItemActiveComponent = get_active_component()
	if active != null:
		return active.get_starting_charges()
	if max_charges <= 0:
		return 0
	if starting_charges < 0:
		return max_charges
	return clampi(starting_charges, 0, max_charges)


func get_unique_passive_id() -> StringName:
	if unique_passive_id != &"":
		return unique_passive_id
	for component: ItemComponent in components:
		if component is ItemPassiveComponent:
			var passive := component as ItemPassiveComponent
			if passive.is_unique:
				return passive.get_unique_key()
	return &""


func get_active_component() -> ItemActiveComponent:
	for component: ItemComponent in components:
		if component is ItemActiveComponent:
			return component as ItemActiveComponent
	return null


func get_aura_components() -> Array[ItemAuraComponent]:
	var result: Array[ItemAuraComponent] = []
	for component: ItemComponent in components:
		if component is ItemAuraComponent:
			result.append(component as ItemAuraComponent)
	return result


func get_proc_components() -> Array[ItemProcComponent]:
	var result: Array[ItemProcComponent] = []
	for component: ItemComponent in components:
		if component is ItemProcComponent:
			result.append(component as ItemProcComponent)
	return result


func get_passive_components() -> Array[ItemPassiveComponent]:
	var result: Array[ItemPassiveComponent] = []
	for component: ItemComponent in components:
		if component is ItemPassiveComponent:
			result.append(component as ItemPassiveComponent)
	return result


func get_components_of_kind(kind: ItemComponent.Kind) -> Array[ItemComponent]:
	var result: Array[ItemComponent] = []
	for component: ItemComponent in components:
		if component != null and component.get_kind() == kind:
			result.append(component)
	return result


func is_shop_item() -> bool:
	return not is_neutral and category != Category.NEUTRAL
