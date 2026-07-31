class_name HeroStats
extends RefCounted

## Canonical hero combat, growth, train cost, and ability base numbers.
## Ability rank multipliers stay in HeroAbilityStats; base values live here.
## Change hero balance in this file only.

# --- Train (Hero Altar) ---
const TRAIN_GOLD_COST: int = 200
const TRAIN_FOOD_COST: int = 2
const TRAIN_SECONDS: float = 6.0

# --- Base combat / mobility (level 1) ---
const MAX_HEALTH: int = 200
const MOVE_SPEED: float = 5.5
const ATTACK_DAMAGE: int = 18
const ATTACK_RANGE: float = 2.0
const ATTACK_COOLDOWN: float = 0.85
const MAX_MANA: int = 100
const MANA_REGEN_RATE: float = 5.0

# --- Level progression ---
const MAX_LEVEL: int = 30
const XP_PER_LEVEL_MULTIPLIER: int = 100
const MIN_ABILITY_POINT_LEVEL: int = 2
const MAX_ABILITY_POINT_LEVEL: int = 18
const HEALTH_PER_LEVEL: int = 25
const MANA_PER_LEVEL: int = 10
const ATTACK_DAMAGE_PER_LEVEL: int = 2
const MOVE_SPEED_PER_LEVEL_AFTER_18: float = 0.05
const INVENTORY_SLOT_COUNT: int = 6
const MAX_COOLDOWN_REDUCTION: float = 0.4
const MAX_MANA_COST_REDUCTION: float = 0.4
const ABILITY_POWER_EFFECT_SECONDS_PER_POINT: float = 0.01
const ABILITY_POWER_EXECUTE_THRESHOLD_PER_POINT: float = 0.001

# --- Ability mana costs (exported on hero unit; also default bases for HeroAbilityStats) ---
const GROUND_SLAM_MANA_COST: int = 40
const DIVINE_PROTECTION_MANA_COST: int = 30
const POWER_STRIKE_MANA_COST: int = 25
const EXECUTE_MANA_COST: int = 50

# --- Ability base stats (rank 1 before multipliers) ---
const GROUND_SLAM_DAMAGE: int = 35
const GROUND_SLAM_RADIUS: float = 3.5
const GROUND_SLAM_COOLDOWN: float = 9.0
const DIVINE_PROTECTION_DURATION: float = 4.0
const DIVINE_PROTECTION_COOLDOWN: float = 20.0
const POWER_STRIKE_DAMAGE: int = 45
const POWER_STRIKE_COOLDOWN: float = 10.0
const EXECUTE_HEALTH_THRESHOLD: float = 0.4
const EXECUTE_COOLDOWN: float = 45.0
