class_name MilitaryAIConfig
extends RefCounted

## Feature toggle for the Military AI V2 stack.
## When false, legacy military AI runs unchanged.
## When true, legacy military decision-makers and main-army order issuers
## must not run; economy / production AI remains active.

const USE_MILITARY_AI_V2: bool = false

## V2 readiness thresholds.
const V2_CREEP_READY_MILITARY_UNITS: int = 5
## Normal attack commit: living hero + this many non-hero military (10–12 band).
const V2_ATTACK_READY_MILITARY_UNITS: int = 10
const V2_ATTACK_READY_MILITARY_UNITS_PREFERRED: int = 12
## High-confidence lethal window may commit with a smaller formed squad.
const V2_ATTACK_LETHAL_MIN_MILITARY_UNITS: int = 6

## V2 ASSEMBLE behavior tuning.
const V2_ASSEMBLE_SLOT_TOLERANCE: float = 1.25
const V2_ASSEMBLE_SETTLE_TOLERANCE: float = 0.75
const V2_ASSEMBLE_RALLY_MIN_RADIUS: float = 8.0
const V2_ASSEMBLE_RALLY_MAX_RADIUS: float = 15.0
const V2_ASSEMBLE_PRODUCTION_EXIT_CLEARANCE: float = 4.0
const V2_ASSEMBLE_ATTACK_MOVE_DISTANCE: float = 6.0

## V2 DEFEND behavior tuning.
const V2_DEFEND_LEASH_RADIUS: float = 42.0
const V2_DEFEND_THREAT_CLEAR_SECONDS: float = 5.0
const V2_DEFEND_ORDER_REISSUE_SECONDS: float = 0.45
const V2_DEFEND_FOCUS_REISSUE_SECONDS: float = 0.75
const V2_DEFEND_THREAT_SEARCH_RANGE: float = 34.0
const V2_DEFEND_MELEE_INTERCEPT_OFFSET: float = 2.5
const V2_DEFEND_RANGED_STANDOFF: float = 7.0
const V2_DEFEND_DAMAGED_HP_RATIO: float = 0.70
const V2_DEFEND_SCATTER_RADIUS: float = 18.0
const V2_DEFEND_SCATTER_COHESION_RATIO: float = 0.60

## V2 ATTACK behavior tuning.
const V2_ATTACK_ORDER_REISSUE_SECONDS: float = 0.45
const V2_ATTACK_FOCUS_REISSUE_SECONDS: float = 0.85
const V2_ATTACK_LOCAL_ENGAGE_RADIUS: float = 28.0
const V2_ATTACK_CHASE_LEASH: float = 22.0
const V2_ATTACK_CHASE_DURATION_SECONDS: float = 6.0
const V2_ATTACK_ROUTE_BLOCK_RADIUS: float = 36.0
const V2_ATTACK_ROUTE_BLOCK_MIN_UNITS: int = 3
const V2_ATTACK_COMMIT_STRENGTH_RATIO: float = 1.25
const V2_ATTACK_RETREAT_STRENGTH_RATIO: float = 0.55
const V2_ATTACK_HERO_DANGER_HP_RATIO: float = 0.35
const V2_ATTACK_ARMY_LOSS_RATIO: float = 0.40
const V2_ATTACK_SCATTER_RADIUS: float = 22.0
const V2_ATTACK_SCATTER_COHESION_RATIO: float = 0.55
const V2_ATTACK_LETHAL_SCORE_THRESHOLD: float = 70.0
const V2_ATTACK_TOWER_THREAT_BUFFER: float = 6.0

## V2 RETREAT / RECOVER behavior tuning.
const V2_RETREAT_COMPLETE_SECONDS: float = 4.0
const V2_RETREAT_ARRIVAL_RADIUS: float = 16.0
const V2_RETREAT_ORDER_REISSUE_SECONDS: float = 0.55
## Local fight AI/player strength ratio that forces retreat (clearly losing).
const V2_RETREAT_STRENGTH_RATIO: float = 0.55
## Re-enter ATTACK only when clearly stronger than the retreat trigger (hysteresis).
const V2_ATTACK_REENTRY_STRENGTH_RATIO: float = 1.15
const V2_RETREAT_HERO_HP_RATIO: float = 0.35
const V2_RETREAT_FRONTLINE_LOSS_RATIO: float = 0.45
const V2_RETREAT_REINFORCEMENT_RADIUS: float = 42.0
const V2_RETREAT_REINFORCEMENT_STRENGTH_RATIO: float = 0.70
const V2_RETREAT_COVER_OFFSET: float = 4.0
const V2_RETREAT_SAFE_TOWER_RADIUS: float = 18.0
const V2_RETREAT_STRAGGLER_RADIUS: float = 28.0
## Minimum seconds committed to a non-emergency state before voluntary exits.
const V2_STATE_COMMIT_SECONDS: float = 3.0
## After RETREAT, block immediate ATTACK re-entry (prevents retreat/attack loops).
const V2_POST_RETREAT_ATTACK_COOLDOWN_SECONDS: float = 6.0
const V2_RECOVER_MIN_SECONDS: float = 4.0
## Hard ceiling so RECOVER cannot stall forever if production is slow.
const V2_RECOVER_MAX_SECONDS: float = 18.0
## Reasonable hero resources — not full HP/mana.
const V2_RECOVER_HERO_HP_RATIO: float = 0.55
const V2_RECOVER_HERO_MANA_RATIO: float = 0.35
const V2_RECOVER_MIN_MILITARY_UNITS: int = 5
const V2_RECOVER_ORDER_REISSUE_SECONDS: float = 0.55

## V2 mission watchdog / stall recovery.
## Stall window is intentionally in the 6–8s band used by legacy missions.
const V2_WATCHDOG_INTERVAL_SECONDS: float = 1.0
const V2_WATCHDOG_STALL_SECONDS: float = 7.0
const V2_WATCHDOG_PROGRESS_DISTANCE_EPSILON: float = 2.5
const V2_WATCHDOG_NEAR_OBJECTIVE_RADIUS: float = 6.0
const V2_WATCHDOG_NEARBY_THREAT_RADIUS: float = 32.0
## Throttle F3 / console diagnostic churn (never spam identical lines).
const V2_WATCHDOG_DIAG_INTERVAL_SECONDS: float = 2.0


static func is_v2_enabled() -> bool:
	return USE_MILITARY_AI_V2


static func ai_version_label() -> String:
	return "V2" if USE_MILITARY_AI_V2 else "Legacy"
