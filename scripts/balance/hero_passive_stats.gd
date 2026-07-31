class_name HeroPassiveStats
extends RefCounted

## Canonical balance numbers for hero innate passives.
## Change passive balance in this file only.

# --- Holy Recovery (Human Paladin) ---
const HOLY_RECOVERY_OUT_OF_COMBAT_SECONDS: float = 5.0
const HOLY_RECOVERY_REGEN_PERCENT_PER_SECOND: float = 0.02

# --- Assassin (Shadow Assassin) ---
const ASSASSIN_PASSIVE_BONUS_DAMAGE: int = ShadowAssassinStats.ASSASSIN_PASSIVE_BONUS_DAMAGE
const ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO: float = ShadowAssassinStats.ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO

# --- Shared framework defaults ---
const ASSIST_DAMAGE_WINDOW_SECONDS: float = 10.0
const AURA_TICK_INTERVAL_SECONDS: float = 0.5
