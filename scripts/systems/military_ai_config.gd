class_name MilitaryAIConfig
extends RefCounted

## Feature toggle for the Military AI V2 stack.
## When false, legacy military AI runs unchanged.
## When true, legacy military decision-makers and main-army order issuers
## must not run; economy / production AI remains active.

const USE_MILITARY_AI_V2: bool = false

## V2 readiness thresholds.
const V2_CREEP_READY_MILITARY_UNITS: int = 5
const V2_ATTACK_READY_MILITARY_UNITS: int = 10

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


static func is_v2_enabled() -> bool:
	return USE_MILITARY_AI_V2


static func ai_version_label() -> String:
	return "V2" if USE_MILITARY_AI_V2 else "Legacy"
