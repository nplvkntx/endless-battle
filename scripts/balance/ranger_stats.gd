class_name RangerStats
extends RefCounted

## Canonical Ranger combat, growth, and ability base numbers.
## Change ranger balance in this file only. Power target ≈ Human Paladin / Shadow Assassin.
## Fragile ranged ADC: high sustained DPS, excellent kiting, dies if caught.

# --- Base combat / mobility (level 1) ---
const MAX_HEALTH: int = 160
const MOVE_SPEED: float = 5.8
const ATTACK_DAMAGE: int = 22
const ATTACK_RANGE: float = 8.0
const ATTACK_COOLDOWN: float = 0.9
const MAX_MANA: int = 100
const MANA_REGEN_RATE: float = 5.0

# --- Growth (glassier HP, stronger AD curve than melee kits) ---
const HEALTH_PER_LEVEL: int = 18
const MANA_PER_LEVEL: int = 10
const ATTACK_DAMAGE_PER_LEVEL: int = 3

# --- Passive: Hunter's Precision ---
## Every Nth consecutive basic attack vs the same non-building target.
const HUNTERS_PRECISION_HIT_COUNT: int = 3
const HUNTERS_PRECISION_MAX_HEALTH_RATIO: float = 0.10

# --- Q: Combat Roll ---
const COMBAT_ROLL_DISTANCE: float = 5.0
const COMBAT_ROLL_COOLDOWN: float = 10.0
const COMBAT_ROLL_MANA_COST: int = 25
const COMBAT_ROLL_MOVE_SPEED_MULT: float = 2.8
const COMBAT_ROLL_MAX_DURATION: float = 0.55

# --- W: Bear Trap ---
const BEAR_TRAP_MAX_CHARGES: int = 3
const BEAR_TRAP_RECHARGE_SECONDS: float = 14.0
const BEAR_TRAP_DAMAGE: int = 18
const BEAR_TRAP_ROOT_DURATION: float = 2.0
const BEAR_TRAP_LIFETIME: float = 45.0
const BEAR_TRAP_TRIGGER_RADIUS: float = 0.85
const BEAR_TRAP_MANA_COST: int = 20
const BEAR_TRAP_PLACE_RANGE: float = 6.0
## Cooldown between placements (charges still gate spam).
const BEAR_TRAP_COOLDOWN: float = 1.0

# --- E: Crossbow Bolt ---
const CROSSBOW_BOLT_DAMAGE: int = 48
const CROSSBOW_BOLT_RANGE: float = 12.0
const CROSSBOW_BOLT_COOLDOWN: float = 12.0
const CROSSBOW_BOLT_MANA_COST: int = 40
const CROSSBOW_BOLT_SPEED: float = 22.0
const CROSSBOW_BOLT_HIT_RADIUS: float = 0.55
const CROSSBOW_BOLT_PIERCE_DAMAGE_MULT: float = 0.7
const CROSSBOW_BOLT_MAX_PIERCES: int = 6

# --- R: Camouflage ---
## Explicit per-rank durations (12 / 18 / 24) — not the shared ultimate effect curve.
const CAMOUFLAGE_DURATION_RANK_1: float = 12.0
const CAMOUFLAGE_DURATION_RANK_2: float = 18.0
const CAMOUFLAGE_DURATION_RANK_3: float = 24.0
const CAMOUFLAGE_MOVE_SPEED_BONUS: float = 1.5
const CAMOUFLAGE_COOLDOWN: float = 40.0
const CAMOUFLAGE_MANA_COST: int = 50
const CAMOUFLAGE_ROLL_RESTORE_SECONDS: float = 3.0

# --- Basic attack projectile ---
const BASIC_ARROW_SPEED: float = 20.0
const BASIC_ARROW_SPAWN_HEIGHT: float = 0.55


static func get_camouflage_duration(rank: int) -> float:
	match clampi(rank, 1, 3):
		2:
			return CAMOUFLAGE_DURATION_RANK_2
		3:
			return CAMOUFLAGE_DURATION_RANK_3
		_:
			return CAMOUFLAGE_DURATION_RANK_1
