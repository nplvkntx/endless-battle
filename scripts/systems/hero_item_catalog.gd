class_name HeroItemCatalog
extends RefCounted

## Hero / neutral item registry. Numbers live in ItemStats — edit there only.

# Tier 1
const ITEM_IRON_BLADE: StringName = &"iron_blade"
const ITEM_WAR_AXE: StringName = &"war_axe"
const ITEM_VITALITY_GEM: StringName = &"vitality_gem"
const ITEM_IRON_PLATE: StringName = &"iron_plate"
const ITEM_TRAVEL_BOOTS: StringName = &"travel_boots"
const ITEM_HUNTER_GLOVES: StringName = &"hunter_gloves"
const ITEM_LUCKY_TALISMAN: StringName = &"lucky_talisman"
const ITEM_VAMPIRIC_FANG: StringName = &"vampiric_fang"
const ITEM_SAPPHIRE_GEM: StringName = &"sapphire_gem"
const ITEM_MAGE_SIGIL: StringName = &"mage_sigil"
const ITEM_FOCUS_CRYSTAL: StringName = &"focus_crystal"
const ITEM_SAGE_PENDANT: StringName = &"sage_pendant"

# Tier 2
const ITEM_EXECUTIONER_AXE: StringName = &"executioner_axe"
const ITEM_CRESCENT_CLEAVER: StringName = &"crescent_cleaver"
const ITEM_GUARDIAN_PLATE: StringName = &"guardian_plate"
const ITEM_VAMPIRE_BLADE: StringName = &"vampire_blade"
const ITEM_DEADEYE_BOW: StringName = &"deadeye_bow"
const ITEM_HUNTER_BOOTS: StringName = &"hunter_boots"
const ITEM_ARCANE_FOCUS: StringName = &"arcane_focus"
const ITEM_SAGE_ORB: StringName = &"sage_orb"
const ITEM_BATTLE_STANDARD: StringName = &"battle_standard"

# Tier 3
const ITEM_TITAN_CLEAVER: StringName = &"titan_cleaver"
const ITEM_BLOODLORD_BLADE: StringName = &"bloodlord_blade"
const ITEM_FORTRESS_HEART: StringName = &"fortress_heart"
const ITEM_PHANTOM_HUNTER: StringName = &"phantom_hunter"
const ITEM_SOUL_CROWN: StringName = &"soul_crown"
const ITEM_WARLORD_STANDARD: StringName = &"warlord_standard"

const SHOP_ITEM_ORDER: Array[StringName] = [
	# Tier 1
	ITEM_IRON_BLADE,
	ITEM_WAR_AXE,
	ITEM_VITALITY_GEM,
	ITEM_IRON_PLATE,
	ITEM_TRAVEL_BOOTS,
	ITEM_HUNTER_GLOVES,
	ITEM_LUCKY_TALISMAN,
	ITEM_VAMPIRIC_FANG,
	ITEM_SAPPHIRE_GEM,
	ITEM_MAGE_SIGIL,
	ITEM_FOCUS_CRYSTAL,
	ITEM_SAGE_PENDANT,
	# Tier 2
	ITEM_EXECUTIONER_AXE,
	ITEM_CRESCENT_CLEAVER,
	ITEM_GUARDIAN_PLATE,
	ITEM_VAMPIRE_BLADE,
	ITEM_DEADEYE_BOW,
	ITEM_HUNTER_BOOTS,
	ITEM_ARCANE_FOCUS,
	ITEM_SAGE_ORB,
	ITEM_BATTLE_STANDARD,
	# Tier 3
	ITEM_TITAN_CLEAVER,
	ITEM_BLOODLORD_BLADE,
	ITEM_FORTRESS_HEART,
	ITEM_PHANTOM_HUNTER,
	ITEM_SOUL_CROWN,
	ITEM_WARLORD_STANDARD,
]

## Reserved for future neutral drops — empty until neutrals are added.
const NEUTRAL_ITEM_ORDER: Array[StringName] = []

## Expanded shop has no fixed hotkeys.
const SHOP_HOTKEYS: Dictionary = {}

static var _definitions: Dictionary = {}


static func get_definition(item_id: StringName) -> HeroItemDefinition:
	_ensure_loaded()
	return _definitions.get(item_id) as HeroItemDefinition


static func get_hotkey_label(item_id: StringName) -> String:
	return String(SHOP_HOTKEYS.get(item_id, ""))


static func get_all_item_ids() -> Array[StringName]:
	_ensure_loaded()
	var ids: Array[StringName] = []
	for key: Variant in _definitions.keys():
		ids.append(key as StringName)
	return ids


static func get_all_definitions() -> Array[HeroItemDefinition]:
	_ensure_loaded()
	var items: Array[HeroItemDefinition] = []
	for key: Variant in _definitions.keys():
		var definition: HeroItemDefinition = _definitions[key] as HeroItemDefinition
		if definition != null:
			items.append(definition)
	return items


static func get_definitions_by_tier(tier: HeroItemDefinition.Tier) -> Array[HeroItemDefinition]:
	var items: Array[HeroItemDefinition] = []
	for definition: HeroItemDefinition in get_all_definitions():
		if definition.tier == tier:
			items.append(definition)
	return items


static func get_definitions_by_category(
	category: HeroItemDefinition.Category
) -> Array[HeroItemDefinition]:
	var items: Array[HeroItemDefinition] = []
	for definition: HeroItemDefinition in get_all_definitions():
		if definition.category == category:
			items.append(definition)
	return items


static func get_shop_definitions() -> Array[HeroItemDefinition]:
	var items: Array[HeroItemDefinition] = []
	for item_id: StringName in SHOP_ITEM_ORDER:
		var definition: HeroItemDefinition = get_definition(item_id)
		if definition != null:
			items.append(definition)
	return items


static func get_shop_definitions_by_tier(tier: HeroItemDefinition.Tier) -> Array[HeroItemDefinition]:
	var items: Array[HeroItemDefinition] = []
	for definition: HeroItemDefinition in get_shop_definitions():
		if definition.tier == tier:
			items.append(definition)
	return items


static func get_recipes_using_component(component_id: StringName) -> Array[StringName]:
	_ensure_loaded()
	var results: Array[StringName] = []
	for item_id: StringName in SHOP_ITEM_ORDER:
		var definition: HeroItemDefinition = _definitions.get(item_id) as HeroItemDefinition
		if definition == null:
			continue
		if definition.recipe_component_ids.has(component_id):
			results.append(item_id)
	return results


static func get_neutral_definitions() -> Array[HeroItemDefinition]:
	var items: Array[HeroItemDefinition] = []
	for item_id: StringName in NEUTRAL_ITEM_ORDER:
		var definition: HeroItemDefinition = get_definition(item_id)
		if definition != null:
			items.append(definition)
	for definition: HeroItemDefinition in get_all_definitions():
		if definition.is_neutral and not items.has(definition):
			items.append(definition)
	return items


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return

	# --- Tier 1 components ---
	_definitions[ITEM_IRON_BLADE] = _make_definition(
		ITEM_IRON_BLADE,
		"Iron Blade",
		ItemStats.IRON_BLADE_GOLD,
		"",
		Color(0.68, 0.70, 0.76, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.IRON_BLADE_BONUS_ATTACK_DAMAGE,
			"tooltip_stats": "+%d Attack Damage" % ItemStats.IRON_BLADE_BONUS_ATTACK_DAMAGE,
		}
	)
	_definitions[ITEM_WAR_AXE] = _make_definition(
		ITEM_WAR_AXE,
		"War Axe",
		ItemStats.WAR_AXE_GOLD,
		"",
		Color(0.78, 0.42, 0.28, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.WAR_AXE_BONUS_ATTACK_DAMAGE,
			"tooltip_stats": "+%d Attack Damage" % ItemStats.WAR_AXE_BONUS_ATTACK_DAMAGE,
		}
	)
	_definitions[ITEM_VITALITY_GEM] = _make_definition(
		ITEM_VITALITY_GEM,
		"Vitality Gem",
		ItemStats.VITALITY_GEM_GOLD,
		"",
		Color(0.82, 0.22, 0.28, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.BASIC,
		{
			"bonus_max_health": ItemStats.VITALITY_GEM_BONUS_MAX_HEALTH,
			"tooltip_stats": "+%d Max Health" % ItemStats.VITALITY_GEM_BONUS_MAX_HEALTH,
		}
	)
	_definitions[ITEM_IRON_PLATE] = _make_definition(
		ITEM_IRON_PLATE,
		"Iron Plate",
		ItemStats.IRON_PLATE_GOLD,
		"",
		Color(0.55, 0.58, 0.62, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.ARMOR,
		{
			"bonus_armor": ItemStats.IRON_PLATE_BONUS_ARMOR,
			"tooltip_stats": "+%.0f Armor" % ItemStats.IRON_PLATE_BONUS_ARMOR,
		}
	)
	_definitions[ITEM_TRAVEL_BOOTS] = _make_definition(
		ITEM_TRAVEL_BOOTS,
		"Travel Boots",
		ItemStats.TRAVEL_BOOTS_GOLD,
		"",
		Color(0.42, 0.30, 0.18, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.BOOTS,
		{
			"bonus_move_speed": ItemStats.TRAVEL_BOOTS_BONUS_MOVE_SPEED,
			"is_unique_move_speed": true,
			"unique_passive_id": ItemStats.UNIQUE_BOOTS_MOVE_SPEED,
			"tooltip_stats": "+%.1f Move Speed" % ItemStats.TRAVEL_BOOTS_BONUS_MOVE_SPEED,
			"tooltip_unique_rules": "Unique — only the highest boots move speed applies.",
		}
	)
	_definitions[ITEM_HUNTER_GLOVES] = _make_definition(
		ITEM_HUNTER_GLOVES,
		"Hunter Gloves",
		ItemStats.HUNTER_GLOVES_GOLD,
		"",
		Color(0.48, 0.62, 0.32, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_speed": ItemStats.HUNTER_GLOVES_BONUS_ATTACK_SPEED,
			"tooltip_stats": "+%d%% Attack Speed" % int(ItemStats.HUNTER_GLOVES_BONUS_ATTACK_SPEED * 100.0),
		}
	)
	_definitions[ITEM_LUCKY_TALISMAN] = _make_definition(
		ITEM_LUCKY_TALISMAN,
		"Lucky Talisman",
		ItemStats.LUCKY_TALISMAN_GOLD,
		"",
		Color(0.88, 0.72, 0.22, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.BASIC,
		{
			"bonus_crit_chance": ItemStats.LUCKY_TALISMAN_BONUS_CRIT_CHANCE,
			"tooltip_stats": "+%d%% Critical Strike Chance" % int(ItemStats.LUCKY_TALISMAN_BONUS_CRIT_CHANCE * 100.0),
		}
	)
	_definitions[ITEM_VAMPIRIC_FANG] = _make_definition(
		ITEM_VAMPIRIC_FANG,
		"Vampiric Fang",
		ItemStats.VAMPIRIC_FANG_GOLD,
		"",
		Color(0.72, 0.12, 0.22, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_lifesteal": ItemStats.VAMPIRIC_FANG_BONUS_LIFESTEAL,
			"tooltip_stats": "+%d%% Lifesteal" % int(ItemStats.VAMPIRIC_FANG_BONUS_LIFESTEAL * 100.0),
		}
	)
	_definitions[ITEM_SAPPHIRE_GEM] = _make_definition(
		ITEM_SAPPHIRE_GEM,
		"Sapphire Gem",
		ItemStats.SAPPHIRE_GEM_GOLD,
		"",
		Color(0.28, 0.48, 0.92, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.MAGIC,
		{
			"bonus_max_mana": ItemStats.SAPPHIRE_GEM_BONUS_MAX_MANA,
			"tooltip_stats": "+%d Max Mana" % ItemStats.SAPPHIRE_GEM_BONUS_MAX_MANA,
		}
	)
	_definitions[ITEM_MAGE_SIGIL] = _make_definition(
		ITEM_MAGE_SIGIL,
		"Mage Sigil",
		ItemStats.MAGE_SIGIL_GOLD,
		"",
		Color(0.55, 0.35, 0.92, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.MAGIC,
		{
			"bonus_ability_power": ItemStats.MAGE_SIGIL_BONUS_ABILITY_POWER,
			"tooltip_stats": "+%d Ability Power" % ItemStats.MAGE_SIGIL_BONUS_ABILITY_POWER,
		}
	)
	_definitions[ITEM_FOCUS_CRYSTAL] = _make_definition(
		ITEM_FOCUS_CRYSTAL,
		"Focus Crystal",
		ItemStats.FOCUS_CRYSTAL_GOLD,
		"",
		Color(0.42, 0.72, 0.88, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.MAGIC,
		{
			"bonus_cooldown_reduction": ItemStats.FOCUS_CRYSTAL_BONUS_COOLDOWN_REDUCTION,
			"tooltip_stats": "+%d%% Cooldown Reduction" % int(ItemStats.FOCUS_CRYSTAL_BONUS_COOLDOWN_REDUCTION * 100.0),
		}
	)
	_definitions[ITEM_SAGE_PENDANT] = _make_definition(
		ITEM_SAGE_PENDANT,
		"Sage Pendant",
		ItemStats.SAGE_PENDANT_GOLD,
		"",
		Color(0.35, 0.58, 0.78, 1),
		HeroItemDefinition.Tier.TIER_1,
		HeroItemDefinition.Category.MAGIC,
		{
			"bonus_mana_regen": ItemStats.SAGE_PENDANT_BONUS_MANA_REGEN,
			"tooltip_stats": "+%.1f Mana Regen" % ItemStats.SAGE_PENDANT_BONUS_MANA_REGEN,
		}
	)

	# --- Tier 2 completed items ---
	_definitions[ITEM_EXECUTIONER_AXE] = _make_definition(
		ITEM_EXECUTIONER_AXE,
		"Executioner Axe",
		ItemStats.EXECUTIONER_AXE_TOTAL_GOLD,
		"",
		Color(0.72, 0.28, 0.18, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.EXECUTIONER_AXE_BONUS_ATTACK_DAMAGE,
			"execute_bonus_ratio": ItemStats.EXECUTIONER_AXE_EXECUTE_BONUS,
			"unique_passive_id": ItemStats.UNIQUE_EXECUTE_BONUS,
			"recipe_component_ids": [ITEM_IRON_BLADE, ITEM_WAR_AXE],
			"recipe_gold_cost": ItemStats.EXECUTIONER_AXE_COMBINE_GOLD,
			"tooltip_stats": "+%d Attack Damage" % ItemStats.EXECUTIONER_AXE_BONUS_ATTACK_DAMAGE,
			"tooltip_passive": "Unique — Deal +%d%% damage to enemies below %d%% health." % [
				int(ItemStats.EXECUTIONER_AXE_EXECUTE_BONUS * 100.0),
				int(ItemStats.EXECUTE_HP_THRESHOLD * 100.0),
			],
			"tooltip_unique_rules": "Unique — only one execute bonus applies.",
		}
	)
	_definitions[ITEM_CRESCENT_CLEAVER] = _make_definition(
		ITEM_CRESCENT_CLEAVER,
		"Crescent Cleaver",
		ItemStats.CRESCENT_CLEAVER_TOTAL_GOLD,
		"",
		Color(0.62, 0.68, 0.78, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.CRESCENT_CLEAVER_BONUS_ATTACK_DAMAGE,
			"bonus_attack_speed": ItemStats.CRESCENT_CLEAVER_BONUS_ATTACK_SPEED,
			"cleave_ratio": ItemStats.CRESCENT_CLEAVER_CLEAVE_RATIO,
			"cleave_radius": ItemStats.CRESCENT_CLEAVER_CLEAVE_RADIUS,
			"unique_passive_id": ItemStats.UNIQUE_CLEAVE,
			"recipe_component_ids": [ITEM_WAR_AXE, ITEM_HUNTER_GLOVES],
			"recipe_gold_cost": ItemStats.CRESCENT_CLEAVER_COMBINE_GOLD,
			"tooltip_stats": "+%d Attack Damage\n+%d%% Attack Speed" % [
				ItemStats.CRESCENT_CLEAVER_BONUS_ATTACK_DAMAGE,
				int(ItemStats.CRESCENT_CLEAVER_BONUS_ATTACK_SPEED * 100.0),
			],
			"tooltip_passive": "Unique — Basic attacks cleave for %d%% damage in a %.1f radius." % [
				int(ItemStats.CRESCENT_CLEAVER_CLEAVE_RATIO * 100.0),
				ItemStats.CRESCENT_CLEAVER_CLEAVE_RADIUS,
			],
			"tooltip_unique_rules": "Unique — strongest cleave wins.",
		}
	)
	_definitions[ITEM_GUARDIAN_PLATE] = _make_definition(
		ITEM_GUARDIAN_PLATE,
		"Guardian Plate",
		ItemStats.GUARDIAN_PLATE_TOTAL_GOLD,
		"",
		Color(0.52, 0.56, 0.64, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.ARMOR,
		{
			"bonus_max_health": ItemStats.GUARDIAN_PLATE_BONUS_MAX_HEALTH,
			"bonus_armor": ItemStats.GUARDIAN_PLATE_BONUS_ARMOR,
			"recipe_component_ids": [ITEM_VITALITY_GEM, ITEM_IRON_PLATE],
			"recipe_gold_cost": ItemStats.GUARDIAN_PLATE_COMBINE_GOLD,
			"tooltip_stats": "+%d Max Health\n+%.0f Armor" % [
				ItemStats.GUARDIAN_PLATE_BONUS_MAX_HEALTH,
				ItemStats.GUARDIAN_PLATE_BONUS_ARMOR,
			],
		}
	)
	_definitions[ITEM_VAMPIRE_BLADE] = _make_definition(
		ITEM_VAMPIRE_BLADE,
		"Vampire Blade",
		ItemStats.VAMPIRE_BLADE_TOTAL_GOLD,
		"",
		Color(0.78, 0.14, 0.24, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.VAMPIRE_BLADE_BONUS_ATTACK_DAMAGE,
			"bonus_lifesteal": ItemStats.VAMPIRE_BLADE_BONUS_LIFESTEAL,
			"recipe_component_ids": [ITEM_WAR_AXE, ITEM_VAMPIRIC_FANG],
			"recipe_gold_cost": ItemStats.VAMPIRE_BLADE_COMBINE_GOLD,
			"tooltip_stats": "+%d Attack Damage\n+%d%% Lifesteal" % [
				ItemStats.VAMPIRE_BLADE_BONUS_ATTACK_DAMAGE,
				int(ItemStats.VAMPIRE_BLADE_BONUS_LIFESTEAL * 100.0),
			],
		}
	)
	_definitions[ITEM_DEADEYE_BOW] = _make_definition(
		ITEM_DEADEYE_BOW,
		"Deadeye Bow",
		ItemStats.DEADEYE_BOW_TOTAL_GOLD,
		"",
		Color(0.72, 0.58, 0.28, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.DEADEYE_BOW_BONUS_ATTACK_DAMAGE,
			"bonus_crit_chance": ItemStats.DEADEYE_BOW_BONUS_CRIT_CHANCE,
			"recipe_component_ids": [ITEM_WAR_AXE, ITEM_LUCKY_TALISMAN],
			"recipe_gold_cost": ItemStats.DEADEYE_BOW_COMBINE_GOLD,
			"tooltip_stats": "+%d Attack Damage\n+%d%% Critical Strike Chance" % [
				ItemStats.DEADEYE_BOW_BONUS_ATTACK_DAMAGE,
				int(ItemStats.DEADEYE_BOW_BONUS_CRIT_CHANCE * 100.0),
			],
		}
	)
	_definitions[ITEM_HUNTER_BOOTS] = _make_definition(
		ITEM_HUNTER_BOOTS,
		"Hunter Boots",
		ItemStats.HUNTER_BOOTS_TOTAL_GOLD,
		"",
		Color(0.38, 0.52, 0.28, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.BOOTS,
		{
			"bonus_move_speed": ItemStats.HUNTER_BOOTS_BONUS_MOVE_SPEED,
			"bonus_attack_speed": ItemStats.HUNTER_BOOTS_BONUS_ATTACK_SPEED,
			"is_unique_move_speed": true,
			"unique_passive_id": ItemStats.UNIQUE_BOOTS_MOVE_SPEED,
			"recipe_component_ids": [ITEM_TRAVEL_BOOTS, ITEM_HUNTER_GLOVES],
			"recipe_gold_cost": ItemStats.HUNTER_BOOTS_COMBINE_GOLD,
			"tooltip_stats": "+%.1f Move Speed\n+%d%% Attack Speed" % [
				ItemStats.HUNTER_BOOTS_BONUS_MOVE_SPEED,
				int(ItemStats.HUNTER_BOOTS_BONUS_ATTACK_SPEED * 100.0),
			],
			"tooltip_unique_rules": "Unique — only the highest boots move speed applies.",
		}
	)
	_definitions[ITEM_ARCANE_FOCUS] = _make_definition(
		ITEM_ARCANE_FOCUS,
		"Arcane Focus",
		ItemStats.ARCANE_FOCUS_TOTAL_GOLD,
		"",
		Color(0.48, 0.32, 0.88, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.MAGIC,
		{
			"bonus_ability_power": ItemStats.ARCANE_FOCUS_BONUS_ABILITY_POWER,
			"bonus_cooldown_reduction": ItemStats.ARCANE_FOCUS_BONUS_COOLDOWN_REDUCTION,
			"recipe_component_ids": [ITEM_MAGE_SIGIL, ITEM_FOCUS_CRYSTAL],
			"recipe_gold_cost": ItemStats.ARCANE_FOCUS_COMBINE_GOLD,
			"tooltip_stats": "+%d Ability Power\n+%d%% Cooldown Reduction" % [
				ItemStats.ARCANE_FOCUS_BONUS_ABILITY_POWER,
				int(ItemStats.ARCANE_FOCUS_BONUS_COOLDOWN_REDUCTION * 100.0),
			],
		}
	)
	_definitions[ITEM_SAGE_ORB] = _make_definition(
		ITEM_SAGE_ORB,
		"Sage Orb",
		ItemStats.SAGE_ORB_TOTAL_GOLD,
		"",
		Color(0.30, 0.52, 0.88, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.MAGIC,
		{
			"bonus_max_mana": ItemStats.SAGE_ORB_BONUS_MAX_MANA,
			"bonus_mana_regen": ItemStats.SAGE_ORB_BONUS_MANA_REGEN,
			"recipe_component_ids": [ITEM_SAPPHIRE_GEM, ITEM_SAGE_PENDANT],
			"recipe_gold_cost": ItemStats.SAGE_ORB_COMBINE_GOLD,
			"tooltip_stats": "+%d Max Mana\n+%.0f Mana Regen" % [
				ItemStats.SAGE_ORB_BONUS_MAX_MANA,
				ItemStats.SAGE_ORB_BONUS_MANA_REGEN,
			],
		}
	)
	_definitions[ITEM_BATTLE_STANDARD] = _make_definition(
		ITEM_BATTLE_STANDARD,
		"Battle Standard",
		ItemStats.BATTLE_STANDARD_TOTAL_GOLD,
		"",
		Color(0.72, 0.55, 0.22, 1),
		HeroItemDefinition.Tier.TIER_2,
		HeroItemDefinition.Category.ARTIFACT,
		{
			"bonus_max_health": ItemStats.BATTLE_STANDARD_BONUS_MAX_HEALTH,
			"bonus_armor": ItemStats.BATTLE_STANDARD_BONUS_ARMOR,
			"aura_armor_bonus": ItemStats.BATTLE_STANDARD_AURA_ARMOR,
			"aura_radius": ItemStats.DEFAULT_AURA_RADIUS,
			"unique_passive_id": ItemStats.UNIQUE_BATTLE_STANDARD_AURA,
			"recipe_component_ids": [ITEM_VITALITY_GEM, ITEM_IRON_PLATE],
			"recipe_gold_cost": ItemStats.BATTLE_STANDARD_COMBINE_GOLD,
			"tooltip_stats": "+%d Max Health\n+%.0f Armor" % [
				ItemStats.BATTLE_STANDARD_BONUS_MAX_HEALTH,
				ItemStats.BATTLE_STANDARD_BONUS_ARMOR,
			],
			"tooltip_aura": "Aura — Nearby allied military units gain +%.0f Armor (does not stack on self)." % ItemStats.BATTLE_STANDARD_AURA_ARMOR,
			"tooltip_unique_rules": "Unique — only one Battle Standard aura applies.",
		}
	)

	# --- Tier 3 legendary items ---
	_definitions[ITEM_TITAN_CLEAVER] = _make_definition(
		ITEM_TITAN_CLEAVER,
		"Titan Cleaver",
		ItemStats.TITAN_CLEAVER_TOTAL_GOLD,
		"",
		Color(0.58, 0.62, 0.72, 1),
		HeroItemDefinition.Tier.TIER_3,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.TITAN_CLEAVER_BONUS_ATTACK_DAMAGE,
			"bonus_attack_speed": ItemStats.TITAN_CLEAVER_BONUS_ATTACK_SPEED,
			"cleave_ratio": ItemStats.TITAN_CLEAVER_CLEAVE_RATIO,
			"cleave_radius": ItemStats.CRESCENT_CLEAVER_CLEAVE_RADIUS,
			"execute_bonus_ratio": ItemStats.TITAN_CLEAVER_EXECUTE_BONUS,
			"unique_passive_id": ItemStats.UNIQUE_CLEAVE,
			"recipe_component_ids": [ITEM_CRESCENT_CLEAVER, ITEM_EXECUTIONER_AXE],
			"recipe_gold_cost": ItemStats.TITAN_CLEAVER_COMBINE_GOLD,
			"tooltip_stats": "+%d Attack Damage\n+%d%% Attack Speed" % [
				ItemStats.TITAN_CLEAVER_BONUS_ATTACK_DAMAGE,
				int(ItemStats.TITAN_CLEAVER_BONUS_ATTACK_SPEED * 100.0),
			],
			"tooltip_passive": "Unique — Basic attacks cleave for %d%% damage.\nDeal +%d%% damage to enemies below %d%% health." % [
				int(ItemStats.TITAN_CLEAVER_CLEAVE_RATIO * 100.0),
				int(ItemStats.TITAN_CLEAVER_EXECUTE_BONUS * 100.0),
				int(ItemStats.EXECUTE_HP_THRESHOLD * 100.0),
			],
			"tooltip_unique_rules": "Unique — strongest cleave wins. Execute bonus is unique separately.",
		}
	)
	_definitions[ITEM_BLOODLORD_BLADE] = _make_definition(
		ITEM_BLOODLORD_BLADE,
		"Bloodlord Blade",
		ItemStats.BLOODLORD_BLADE_TOTAL_GOLD,
		"",
		Color(0.62, 0.08, 0.16, 1),
		HeroItemDefinition.Tier.TIER_3,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.BLOODLORD_BLADE_BONUS_ATTACK_DAMAGE,
			"bonus_lifesteal": ItemStats.BLOODLORD_BLADE_BONUS_LIFESTEAL,
			"low_hp_extra_lifesteal": ItemStats.BLOODLORD_EXTRA_LIFESTEAL,
			"execute_bonus_ratio": ItemStats.EXECUTIONER_AXE_EXECUTE_BONUS,
			"unique_passive_id": ItemStats.UNIQUE_BLOODLORD_LOW_HP_LIFESTEAL,
			"recipe_component_ids": [ITEM_VAMPIRE_BLADE, ITEM_EXECUTIONER_AXE],
			"recipe_gold_cost": ItemStats.BLOODLORD_BLADE_COMBINE_GOLD,
			"tooltip_stats": "+%d Attack Damage\n+%d%% Lifesteal" % [
				ItemStats.BLOODLORD_BLADE_BONUS_ATTACK_DAMAGE,
				int(ItemStats.BLOODLORD_BLADE_BONUS_LIFESTEAL * 100.0),
			],
			"tooltip_passive": "Unique — Gain +%d%% lifesteal while below %d%% health.\nDeal +%d%% damage to enemies below %d%% health." % [
				int(ItemStats.BLOODLORD_EXTRA_LIFESTEAL * 100.0),
				int(ItemStats.BLOODLORD_LOW_HP_THRESHOLD * 100.0),
				int(ItemStats.EXECUTIONER_AXE_EXECUTE_BONUS * 100.0),
				int(ItemStats.EXECUTE_HP_THRESHOLD * 100.0),
			],
			"tooltip_unique_rules": "Unique — Bloodlord low-HP lifesteal. Execute bonus is unique separately.",
		}
	)
	_definitions[ITEM_FORTRESS_HEART] = _make_definition(
		ITEM_FORTRESS_HEART,
		"Fortress Heart",
		ItemStats.FORTRESS_HEART_TOTAL_GOLD,
		"",
		Color(0.48, 0.52, 0.58, 1),
		HeroItemDefinition.Tier.TIER_3,
		HeroItemDefinition.Category.ARMOR,
		{
			"bonus_max_health": ItemStats.FORTRESS_HEART_BONUS_MAX_HEALTH,
			"bonus_armor": ItemStats.FORTRESS_HEART_BONUS_ARMOR,
			"has_out_of_combat_regen": true,
			"unique_passive_id": ItemStats.UNIQUE_FORTRESS_HEART_REGEN,
			"recipe_component_ids": [ITEM_GUARDIAN_PLATE, ITEM_BATTLE_STANDARD],
			"recipe_gold_cost": ItemStats.FORTRESS_HEART_COMBINE_GOLD,
			"tooltip_stats": "+%d Max Health\n+%.0f Armor" % [
				ItemStats.FORTRESS_HEART_BONUS_MAX_HEALTH,
				ItemStats.FORTRESS_HEART_BONUS_ARMOR,
			],
			"tooltip_passive": "Unique — After %.0f seconds out of combat, regenerate %d%% max health per second." % [
				ItemStats.FORTRESS_HEART_OUT_OF_COMBAT_SECONDS,
				int(ItemStats.FORTRESS_HEART_REGEN_PERCENT_PER_SECOND * 100.0),
			],
			"tooltip_unique_rules": "Unique — only one Fortress Heart regen applies.",
		}
	)
	_definitions[ITEM_PHANTOM_HUNTER] = _make_definition(
		ITEM_PHANTOM_HUNTER,
		"Phantom Hunter",
		ItemStats.PHANTOM_HUNTER_TOTAL_GOLD,
		"",
		Color(0.42, 0.68, 0.38, 1),
		HeroItemDefinition.Tier.TIER_3,
		HeroItemDefinition.Category.WEAPON,
		{
			"bonus_attack_damage": ItemStats.PHANTOM_HUNTER_BONUS_ATTACK_DAMAGE,
			"bonus_attack_speed": ItemStats.PHANTOM_HUNTER_BONUS_ATTACK_SPEED,
			"bonus_crit_chance": ItemStats.PHANTOM_HUNTER_BONUS_CRIT_CHANCE,
			"bonus_move_speed": ItemStats.PHANTOM_HUNTER_BONUS_MOVE_SPEED,
			"is_unique_move_speed": true,
			"unique_passive_id": ItemStats.UNIQUE_BOOTS_MOVE_SPEED,
			"recipe_component_ids": [ITEM_HUNTER_BOOTS, ITEM_DEADEYE_BOW],
			"recipe_gold_cost": ItemStats.PHANTOM_HUNTER_COMBINE_GOLD,
			"tooltip_stats": "+%d Attack Damage\n+%d%% Attack Speed\n+%d%% Critical Strike Chance\n+%.1f Move Speed" % [
				ItemStats.PHANTOM_HUNTER_BONUS_ATTACK_DAMAGE,
				int(ItemStats.PHANTOM_HUNTER_BONUS_ATTACK_SPEED * 100.0),
				int(ItemStats.PHANTOM_HUNTER_BONUS_CRIT_CHANCE * 100.0),
				ItemStats.PHANTOM_HUNTER_BONUS_MOVE_SPEED,
			],
			"tooltip_unique_rules": "Unique — only the highest boots move speed applies.",
		}
	)
	_definitions[ITEM_SOUL_CROWN] = _make_definition(
		ITEM_SOUL_CROWN,
		"Soul Crown",
		ItemStats.SOUL_CROWN_TOTAL_GOLD,
		"",
		Color(0.52, 0.28, 0.88, 1),
		HeroItemDefinition.Tier.TIER_3,
		HeroItemDefinition.Category.MAGIC,
		{
			"bonus_ability_power": ItemStats.SOUL_CROWN_BONUS_ABILITY_POWER,
			"bonus_max_mana": ItemStats.SOUL_CROWN_BONUS_MAX_MANA,
			"bonus_cooldown_reduction": ItemStats.SOUL_CROWN_BONUS_COOLDOWN_REDUCTION,
			"bonus_mana_regen": ItemStats.SOUL_CROWN_BONUS_MANA_REGEN,
			"recipe_component_ids": [ITEM_ARCANE_FOCUS, ITEM_SAGE_ORB],
			"recipe_gold_cost": ItemStats.SOUL_CROWN_COMBINE_GOLD,
			"tooltip_stats": "+%d Ability Power\n+%d Max Mana\n+%d%% Cooldown Reduction\n+%.0f Mana Regen" % [
				ItemStats.SOUL_CROWN_BONUS_ABILITY_POWER,
				ItemStats.SOUL_CROWN_BONUS_MAX_MANA,
				int(ItemStats.SOUL_CROWN_BONUS_COOLDOWN_REDUCTION * 100.0),
				ItemStats.SOUL_CROWN_BONUS_MANA_REGEN,
			],
		}
	)
	_definitions[ITEM_WARLORD_STANDARD] = _make_definition(
		ITEM_WARLORD_STANDARD,
		"Warlord Standard",
		ItemStats.WARLORD_STANDARD_TOTAL_GOLD,
		"",
		Color(0.78, 0.48, 0.18, 1),
		HeroItemDefinition.Tier.TIER_3,
		HeroItemDefinition.Category.ARTIFACT,
		{
			"bonus_max_health": ItemStats.WARLORD_STANDARD_BONUS_MAX_HEALTH,
			"bonus_armor": ItemStats.WARLORD_STANDARD_BONUS_ARMOR,
			"aura_armor_bonus": ItemStats.WARLORD_STANDARD_AURA_ARMOR,
			"aura_attack_speed_bonus": ItemStats.WARLORD_STANDARD_AURA_ATTACK_SPEED,
			"aura_radius": ItemStats.DEFAULT_AURA_RADIUS,
			"unique_passive_id": ItemStats.UNIQUE_WARLORD_STANDARD_AURA,
			"recipe_component_ids": [ITEM_BATTLE_STANDARD, ITEM_GUARDIAN_PLATE],
			"recipe_gold_cost": ItemStats.WARLORD_STANDARD_COMBINE_GOLD,
			"tooltip_stats": "+%d Max Health\n+%.0f Armor" % [
				ItemStats.WARLORD_STANDARD_BONUS_MAX_HEALTH,
				ItemStats.WARLORD_STANDARD_BONUS_ARMOR,
			],
			"tooltip_aura": "Aura — Nearby allied military units gain +%.0f Armor and +%d%% Attack Speed (does not stack on self)." % [
				ItemStats.WARLORD_STANDARD_AURA_ARMOR,
				int(ItemStats.WARLORD_STANDARD_AURA_ATTACK_SPEED * 100.0),
			],
			"tooltip_unique_rules": "Unique — only one Warlord Standard aura applies.",
		}
	)


static func _make_definition(
	item_id: StringName,
	display_name: String,
	gold_cost: int,
	hotkey: String,
	icon_color: Color,
	tier: HeroItemDefinition.Tier,
	category: HeroItemDefinition.Category,
	effects: Dictionary
) -> HeroItemDefinition:
	var definition := HeroItemDefinition.new()
	definition.item_id = item_id
	definition.display_name = display_name
	definition.gold_cost = gold_cost
	definition.hotkey = hotkey
	definition.icon_color = icon_color
	definition.tier = tier
	definition.category = category
	definition.sell_value = HeroItemDefinition.SELL_VALUE_USE_RATIO
	definition.is_neutral = false
	definition.is_consumable = false
	definition.is_active_item = false

	definition.tooltip_stats = String(effects.get("tooltip_stats", ""))
	definition.tooltip_passive = String(effects.get("tooltip_passive", ""))
	definition.tooltip_aura = String(effects.get("tooltip_aura", ""))
	definition.tooltip_unique_rules = String(effects.get("tooltip_unique_rules", ""))

	if effects.has("recipe_component_ids"):
		var components: Array = effects["recipe_component_ids"] as Array
		var recipe_ids: Array[StringName] = []
		for component: Variant in components:
			recipe_ids.append(component as StringName)
		definition.recipe_component_ids = recipe_ids
	definition.recipe_gold_cost = int(effects.get("recipe_gold_cost", -1))
	definition.unique_passive_id = effects.get("unique_passive_id", &"") as StringName

	definition.bonus_attack_damage = int(effects.get("bonus_attack_damage", 0))
	definition.bonus_max_health = int(effects.get("bonus_max_health", 0))
	definition.heal_on_purchase = int(effects.get("heal_on_purchase", 0))
	definition.bonus_move_speed = float(effects.get("bonus_move_speed", 0.0))
	definition.is_unique_move_speed = bool(effects.get("is_unique_move_speed", false))
	definition.bonus_max_mana = int(effects.get("bonus_max_mana", 0))
	definition.restore_mana_on_purchase = int(effects.get("restore_mana_on_purchase", 0))
	definition.bonus_ability_power = int(effects.get("bonus_ability_power", 0))
	definition.bonus_cooldown_reduction = float(effects.get("bonus_cooldown_reduction", 0.0))
	definition.bonus_mana_cost_reduction = float(effects.get("bonus_mana_cost_reduction", 0.0))
	definition.bonus_spell_radius = float(effects.get("bonus_spell_radius", 0.0))
	definition.bonus_armor = float(effects.get("bonus_armor", 0.0))
	definition.bonus_attack_speed = float(effects.get("bonus_attack_speed", 0.0))
	definition.bonus_crit_chance = float(effects.get("bonus_crit_chance", 0.0))
	definition.bonus_lifesteal = float(effects.get("bonus_lifesteal", 0.0))
	definition.bonus_mana_regen = float(effects.get("bonus_mana_regen", 0.0))
	definition.cleave_ratio = float(effects.get("cleave_ratio", 0.0))
	definition.cleave_radius = float(effects.get("cleave_radius", 0.0))
	definition.execute_bonus_ratio = float(effects.get("execute_bonus_ratio", 0.0))
	definition.aura_armor_bonus = float(effects.get("aura_armor_bonus", 0.0))
	definition.aura_attack_speed_bonus = float(effects.get("aura_attack_speed_bonus", 0.0))
	definition.aura_radius = float(effects.get("aura_radius", 0.0))
	definition.low_hp_extra_lifesteal = float(effects.get("low_hp_extra_lifesteal", 0.0))
	definition.has_out_of_combat_regen = bool(effects.get("has_out_of_combat_regen", false))
	return definition
