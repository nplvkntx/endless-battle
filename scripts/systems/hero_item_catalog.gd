class_name HeroItemCatalog
extends RefCounted

## Starter hero shop catalog. Add recipes and legendary items here later.

const ITEM_LONG_SWORD: StringName = &"long_sword"
const ITEM_RUBY_CRYSTAL: StringName = &"ruby_crystal"
const ITEM_BOOTS: StringName = &"boots"
const ITEM_WIZARD_ORB: StringName = &"wizard_orb"

const SHOP_ITEM_ORDER: Array[StringName] = [
	ITEM_LONG_SWORD,
	ITEM_RUBY_CRYSTAL,
	ITEM_BOOTS,
	ITEM_WIZARD_ORB,
]

const SHOP_HOTKEYS: Dictionary = {
	ITEM_LONG_SWORD: "Q",
	ITEM_RUBY_CRYSTAL: "W",
	ITEM_BOOTS: "E",
	ITEM_WIZARD_ORB: "R",
}

static var _definitions: Dictionary = {}


static func get_definition(item_id: StringName) -> HeroItemDefinition:
	_ensure_loaded()
	return _definitions.get(item_id) as HeroItemDefinition


static func get_hotkey_label(item_id: StringName) -> String:
	return String(SHOP_HOTKEYS.get(item_id, ""))


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return

	_definitions[ITEM_LONG_SWORD] = _make_definition(
		ITEM_LONG_SWORD,
		"Long Sword",
		350,
		"Q",
		Color(0.72, 0.74, 0.82, 1),
		{"bonus_attack_damage": 10}
	)
	_definitions[ITEM_RUBY_CRYSTAL] = _make_definition(
		ITEM_RUBY_CRYSTAL,
		"Ruby Crystal",
		400,
		"W",
		Color(0.82, 0.18, 0.2, 1),
		{"bonus_max_health": 100, "heal_on_purchase": 100}
	)
	_definitions[ITEM_BOOTS] = _make_definition(
		ITEM_BOOTS,
		"Boots",
		300,
		"E",
		Color(0.42, 0.3, 0.18, 1),
		{"bonus_move_speed": 10.0}
	)
	_definitions[ITEM_WIZARD_ORB] = _make_definition(
		ITEM_WIZARD_ORB,
		"Wizard Orb",
		450,
		"R",
		Color(0.35, 0.45, 0.92, 1),
		{"bonus_max_mana": 75, "restore_mana_on_purchase": 75}
	)


static func _make_definition(
	item_id: StringName,
	display_name: String,
	gold_cost: int,
	hotkey: String,
	icon_color: Color,
	effects: Dictionary
) -> HeroItemDefinition:
	var definition := HeroItemDefinition.new()
	definition.item_id = item_id
	definition.display_name = display_name
	definition.gold_cost = gold_cost
	definition.hotkey = hotkey
	definition.icon_color = icon_color
	definition.bonus_attack_damage = int(effects.get("bonus_attack_damage", 0))
	definition.bonus_max_health = int(effects.get("bonus_max_health", 0))
	definition.heal_on_purchase = int(effects.get("heal_on_purchase", 0))
	definition.bonus_move_speed = float(effects.get("bonus_move_speed", 0.0))
	definition.bonus_max_mana = int(effects.get("bonus_max_mana", 0))
	definition.restore_mana_on_purchase = int(effects.get("restore_mana_on_purchase", 0))
	return definition
