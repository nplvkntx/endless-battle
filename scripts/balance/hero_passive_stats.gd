class_name HeroPassiveStats
extends RefCounted

## Canonical balance numbers for hero innate passives.
## Change passive balance in this file only.

# --- Holy Recovery (Human Paladin) ---
const HOLY_RECOVERY_OUT_OF_COMBAT_SECONDS: float = 5.0
const HOLY_RECOVERY_REGEN_PERCENT_PER_SECOND: float = 0.015

# --- Assassin (Shadow Assassin) ---
const ASSASSIN_PASSIVE_BONUS_DAMAGE: int = ShadowAssassinStats.ASSASSIN_PASSIVE_BONUS_DAMAGE
const ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO: float = ShadowAssassinStats.ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO

# --- Hunter's Precision (Ranger) ---
const HUNTERS_PRECISION_HIT_COUNT: int = RangerStats.HUNTERS_PRECISION_HIT_COUNT
const HUNTERS_PRECISION_MAX_HEALTH_RATIO: float = RangerStats.HUNTERS_PRECISION_MAX_HEALTH_RATIO
const HUNTERS_PRECISION_DAMAGE_CAP_BASE: int = RangerStats.HUNTERS_PRECISION_DAMAGE_CAP_BASE
const HUNTERS_PRECISION_DAMAGE_CAP_PER_LEVEL: int = RangerStats.HUNTERS_PRECISION_DAMAGE_CAP_PER_LEVEL

# --- Shared framework defaults ---
const ASSIST_DAMAGE_WINDOW_SECONDS: float = 10.0
const AURA_TICK_INTERVAL_SECONDS: float = 0.5
