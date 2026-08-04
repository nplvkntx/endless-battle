class_name ItemStats
extends RefCounted

## Canonical hero shop item costs, stats, recipes, and passive magnitudes.
## HeroItemCatalog builds definitions from these values — change items here only.

const SELL_REFUND_RATIO: float = 0.5
const SHOP_PURCHASE_RANGE_PIXELS: float = 200.0
const SHOP_PURCHASE_RANGE_WORLD_FALLBACK: float = 4.5

const CRITICAL_DAMAGE_MULTIPLIER: float = 1.75
const MAX_COOLDOWN_REDUCTION: float = 0.4
const MAX_BONUS_ATTACK_SPEED: float = 1.0

const UNIQUE_BOOTS_MOVE_SPEED: StringName = &"boots_move_speed"
const UNIQUE_CLEAVE: StringName = &"cleave"
const UNIQUE_EXECUTE_BONUS: StringName = &"execute_bonus"
const UNIQUE_BATTLE_STANDARD_AURA: StringName = &"battle_standard_aura"
const UNIQUE_WARLORD_STANDARD_AURA: StringName = &"warlord_standard_aura"
const UNIQUE_FORTRESS_HEART_REGEN: StringName = &"fortress_heart_regen"
const UNIQUE_BLOODLORD_LOW_HP_LIFESTEAL: StringName = &"bloodlord_low_hp_lifesteal"

const DEFAULT_AURA_RADIUS: float = 10.0
const FORTRESS_HEART_OUT_OF_COMBAT_SECONDS: float = 6.0
const FORTRESS_HEART_REGEN_PERCENT_PER_SECOND: float = 0.01
const BLOODLORD_LOW_HP_THRESHOLD: float = 0.40
const BLOODLORD_EXTRA_LIFESTEAL: float = 0.10
const EXECUTE_HP_THRESHOLD: float = 0.35

# =============================================================================
# Tier 1 Components
# =============================================================================

const IRON_BLADE_GOLD: int = 250
const IRON_BLADE_BONUS_ATTACK_DAMAGE: int = 6

const WAR_AXE_GOLD: int = 400
const WAR_AXE_BONUS_ATTACK_DAMAGE: int = 10

const VITALITY_GEM_GOLD: int = 300
const VITALITY_GEM_BONUS_MAX_HEALTH: int = 80

const IRON_PLATE_GOLD: int = 350
const IRON_PLATE_BONUS_ARMOR: float = 2.0

const TRAVEL_BOOTS_GOLD: int = 300
const TRAVEL_BOOTS_BONUS_MOVE_SPEED: float = 0.6

const HUNTER_GLOVES_GOLD: int = 300
const HUNTER_GLOVES_BONUS_ATTACK_SPEED: float = 0.08

const LUCKY_TALISMAN_GOLD: int = 350
const LUCKY_TALISMAN_BONUS_CRIT_CHANCE: float = 0.08

const VAMPIRIC_FANG_GOLD: int = 400
const VAMPIRIC_FANG_BONUS_LIFESTEAL: float = 0.06

const SAPPHIRE_GEM_GOLD: int = 250
const SAPPHIRE_GEM_BONUS_MAX_MANA: int = 60

const MAGE_SIGIL_GOLD: int = 300
const MAGE_SIGIL_BONUS_ABILITY_POWER: int = 15

const FOCUS_CRYSTAL_GOLD: int = 350
const FOCUS_CRYSTAL_BONUS_COOLDOWN_REDUCTION: float = 0.05

const SAGE_PENDANT_GOLD: int = 300
const SAGE_PENDANT_BONUS_MANA_REGEN: float = 1.5

# =============================================================================
# Tier 2 Completed Items
# =============================================================================

const EXECUTIONER_AXE_COMBINE_GOLD: int = 300
const EXECUTIONER_AXE_TOTAL_GOLD: int = 950
const EXECUTIONER_AXE_BONUS_ATTACK_DAMAGE: int = 18
const EXECUTIONER_AXE_EXECUTE_BONUS: float = 0.15

const CRESCENT_CLEAVER_COMBINE_GOLD: int = 350
const CRESCENT_CLEAVER_TOTAL_GOLD: int = 1050
const CRESCENT_CLEAVER_BONUS_ATTACK_DAMAGE: int = 12
const CRESCENT_CLEAVER_BONUS_ATTACK_SPEED: float = 0.12
const CRESCENT_CLEAVER_CLEAVE_RATIO: float = 0.25
const CRESCENT_CLEAVER_CLEAVE_RADIUS: float = 3.5

const GUARDIAN_PLATE_COMBINE_GOLD: int = 300
const GUARDIAN_PLATE_TOTAL_GOLD: int = 950
const GUARDIAN_PLATE_BONUS_MAX_HEALTH: int = 180
const GUARDIAN_PLATE_BONUS_ARMOR: float = 4.0

const VAMPIRE_BLADE_COMBINE_GOLD: int = 300
const VAMPIRE_BLADE_TOTAL_GOLD: int = 1100
const VAMPIRE_BLADE_BONUS_ATTACK_DAMAGE: int = 14
const VAMPIRE_BLADE_BONUS_LIFESTEAL: float = 0.10

const DEADEYE_BOW_COMBINE_GOLD: int = 300
const DEADEYE_BOW_TOTAL_GOLD: int = 1050
const DEADEYE_BOW_BONUS_ATTACK_DAMAGE: int = 12
const DEADEYE_BOW_BONUS_CRIT_CHANCE: float = 0.12

const HUNTER_BOOTS_COMBINE_GOLD: int = 250
const HUNTER_BOOTS_TOTAL_GOLD: int = 850
const HUNTER_BOOTS_BONUS_MOVE_SPEED: float = 0.8
const HUNTER_BOOTS_BONUS_ATTACK_SPEED: float = 0.12

const ARCANE_FOCUS_COMBINE_GOLD: int = 300
const ARCANE_FOCUS_TOTAL_GOLD: int = 950
const ARCANE_FOCUS_BONUS_ABILITY_POWER: int = 30
const ARCANE_FOCUS_BONUS_COOLDOWN_REDUCTION: float = 0.10

const SAGE_ORB_COMBINE_GOLD: int = 250
const SAGE_ORB_TOTAL_GOLD: int = 800
const SAGE_ORB_BONUS_MAX_MANA: int = 120
const SAGE_ORB_BONUS_MANA_REGEN: float = 3.0

const BATTLE_STANDARD_COMBINE_GOLD: int = 350
const BATTLE_STANDARD_TOTAL_GOLD: int = 1000
const BATTLE_STANDARD_BONUS_MAX_HEALTH: int = 120
const BATTLE_STANDARD_BONUS_ARMOR: float = 2.0
const BATTLE_STANDARD_AURA_ARMOR: float = 1.0

# =============================================================================
# Tier 3 Legendary Items
# =============================================================================

const TITAN_CLEAVER_COMBINE_GOLD: int = 700
const TITAN_CLEAVER_TOTAL_GOLD: int = 2700
const TITAN_CLEAVER_BONUS_ATTACK_DAMAGE: int = 30
const TITAN_CLEAVER_BONUS_ATTACK_SPEED: float = 0.20
const TITAN_CLEAVER_CLEAVE_RATIO: float = 0.35
const TITAN_CLEAVER_EXECUTE_BONUS: float = 0.20

const BLOODLORD_BLADE_COMBINE_GOLD: int = 750
const BLOODLORD_BLADE_TOTAL_GOLD: int = 2800
const BLOODLORD_BLADE_BONUS_ATTACK_DAMAGE: int = 32
const BLOODLORD_BLADE_BONUS_LIFESTEAL: float = 0.16

const FORTRESS_HEART_COMBINE_GOLD: int = 700
const FORTRESS_HEART_TOTAL_GOLD: int = 2650
const FORTRESS_HEART_BONUS_MAX_HEALTH: int = 400
const FORTRESS_HEART_BONUS_ARMOR: float = 8.0

const PHANTOM_HUNTER_COMBINE_GOLD: int = 700
const PHANTOM_HUNTER_TOTAL_GOLD: int = 2600
const PHANTOM_HUNTER_BONUS_ATTACK_DAMAGE: int = 18
const PHANTOM_HUNTER_BONUS_ATTACK_SPEED: float = 0.22
const PHANTOM_HUNTER_BONUS_CRIT_CHANCE: float = 0.18
const PHANTOM_HUNTER_BONUS_MOVE_SPEED: float = 1.0

const SOUL_CROWN_COMBINE_GOLD: int = 750
const SOUL_CROWN_TOTAL_GOLD: int = 2500
const SOUL_CROWN_BONUS_ABILITY_POWER: int = 65
const SOUL_CROWN_BONUS_MAX_MANA: int = 200
const SOUL_CROWN_BONUS_COOLDOWN_REDUCTION: float = 0.15
const SOUL_CROWN_BONUS_MANA_REGEN: float = 4.0

const WARLORD_STANDARD_COMBINE_GOLD: int = 800
const WARLORD_STANDARD_TOTAL_GOLD: int = 2750
const WARLORD_STANDARD_BONUS_MAX_HEALTH: int = 300
const WARLORD_STANDARD_BONUS_ARMOR: float = 6.0
const WARLORD_STANDARD_AURA_ARMOR: float = 1.0
const WARLORD_STANDARD_AURA_ATTACK_SPEED: float = 0.05
