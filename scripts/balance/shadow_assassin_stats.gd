class_name ShadowAssassinStats
extends RefCounted

## Canonical Shadow Assassin combat, growth, and ability base numbers.
## Change assassin balance in this file only. Power target ≈ Human Paladin.

# --- Base combat / mobility (level 1) ---
const MAX_HEALTH: int = 180
const MOVE_SPEED: float = 6.0
const ATTACK_DAMAGE: int = 20
const ATTACK_RANGE: float = 2.0
const ATTACK_COOLDOWN: float = 0.75
const MAX_MANA: int = 100
const MANA_REGEN_RATE: float = 5.0

# --- Growth (same window as Paladin; slightly glassier HP curve) ---
const HEALTH_PER_LEVEL: int = 22
const MANA_PER_LEVEL: int = 10
const ATTACK_DAMAGE_PER_LEVEL: int = 2

# --- Passive: Assassin ---
## Bonus physical damage on every consecutive basic attack after the first vs same target.
const ASSASSIN_PASSIVE_BONUS_DAMAGE: int = 8
const ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO: float = 0.25

# --- Q: Axe Mark ---
const AXE_MARK_DAMAGE: int = 28
const AXE_MARK_BONUS_ON_CONSUME: int = 40
const AXE_MARK_DURATION: float = 5.0
const AXE_MARK_RANGE: float = 8.0
const AXE_MARK_PROJECTILE_SPEED: float = 16.0
const AXE_MARK_COOLDOWN: float = 10.0
const AXE_MARK_MANA_COST: int = 35
const AXE_MARK_MANA_REFUND_RATIO: float = 0.5

# --- W: Smoke ---
const SMOKE_DURATION: float = 6.0
const SMOKE_RADIUS: float = 4.0
const SMOKE_CAST_RANGE: float = 7.0
const SMOKE_MOVE_SPEED_BONUS: float = 1.5
const SMOKE_REVEAL_SECONDS: float = 1.25
const SMOKE_COOLDOWN: float = 18.0
const SMOKE_MANA_COST: int = 35

# --- E: Slash ---
const SLASH_DAMAGE: int = 38
const SLASH_RADIUS: float = 2.8
const SLASH_COOLDOWN: float = 8.0
const SLASH_MANA_COST: int = 30

# --- R: Dash ---
const DASH_DAMAGE: int = 55
const DASH_RANGE: float = 7.0
const DASH_COOLDOWN: float = 20.0
const DASH_MANA_COST: int = 40
const DASH_ARRIVAL_OFFSET: float = 1.15
