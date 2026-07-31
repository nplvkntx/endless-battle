class_name ItemStats
extends RefCounted

## Canonical hero shop item costs and effect magnitudes.
## HeroItemCatalog builds definitions from these values — change items here only.
## Framework fields (tier / category / recipes / components) live on HeroItemDefinition.

const SELL_REFUND_RATIO: float = 0.5
const SHOP_PURCHASE_RANGE_PIXELS: float = 200.0
const SHOP_PURCHASE_RANGE_WORLD_FALLBACK: float = 4.5

# --- Starter shop ---
const LONG_SWORD_GOLD: int = 350
const LONG_SWORD_BONUS_ATTACK_DAMAGE: int = 10

const RUBY_CRYSTAL_GOLD: int = 400
const RUBY_CRYSTAL_BONUS_MAX_HEALTH: int = 100
const RUBY_CRYSTAL_HEAL_ON_PURCHASE: int = 100

const BOOTS_GOLD: int = 300
const BOOTS_BONUS_MOVE_SPEED: float = 10.0

const WIZARD_ORB_GOLD: int = 450
const WIZARD_ORB_BONUS_MAX_MANA: int = 75
const WIZARD_ORB_RESTORE_MANA_ON_PURCHASE: int = 75

# --- Extended / recipe items ---
const MAGE_RING_GOLD: int = 400
const MAGE_RING_BONUS_ABILITY_POWER: int = 20

const MANA_CRYSTAL_GOLD: int = 450
const MANA_CRYSTAL_BONUS_MAX_MANA: int = 100
const MANA_CRYSTAL_BONUS_MANA_COST_REDUCTION: float = 0.1

const SORCERER_STAFF_GOLD: int = 550
const SORCERER_STAFF_BONUS_ABILITY_POWER: int = 40
const SORCERER_STAFF_BONUS_COOLDOWN_REDUCTION: float = 0.1

const ARCANE_BOOTS_GOLD: int = 400
const ARCANE_BOOTS_BONUS_MOVE_SPEED: float = 10.0
const ARCANE_BOOTS_BONUS_COOLDOWN_REDUCTION: float = 0.1

const ARCHMAGE_ORB_GOLD: int = 700
const ARCHMAGE_ORB_BONUS_ABILITY_POWER: int = 80
const ARCHMAGE_ORB_BONUS_COOLDOWN_REDUCTION: float = 0.15
