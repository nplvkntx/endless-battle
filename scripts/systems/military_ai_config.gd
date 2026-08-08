class_name MilitaryAIConfig
extends RefCounted

## Military AI authority configuration.
##
## PRODUCTION: Simple WC3 AI is the ONLY runtime military authority.
## USE_SIMPLE_WC3_AI = true → MatchCompositionRoot disables old military controllers
## and declares SimpleWc3AI as sole military_command_authority.
## No coexistence: V2 / legacy must not issue strategic military orders.
##
## USE_MILITARY_AI_V2 remains true so legacy mission owners stay suspended via
## is_v2_enabled() / is_legacy_military_suspended(). V2 nodes themselves are
## process-disabled under Simple WC3 (they do not run).
##
## Suspended under Simple WC3 (and under V2 when Simple is off):
##   - MilitaryDirectorV2 / ArmyCommanderV2 process
##   - EnemyCreepManager / EnemyWaveManager / EnemyDefenseManager process
##   - EnemyCombatController process
##   - EnemyStrategicDirector._set_main_mission / _run_recovery_checks
##   - AIHeroMastery strategic ticks (only reached via ArmyCommanderV2)
##
## Kept active (non-military / economy boundary):
##   EnemyStrategicDirector phase/desires for economy,
##   EnemyBuildManager, EnemyGatherManager, EnemyResourceManager, TechTree,
##   UpgradeManager, EnemyBuildPlacement, worker / construction / production AI.
##
## See docs/MILITARY_AI_V2.md for historical V2 ownership (inactive under Simple).

const USE_MILITARY_AI_V2: bool = true

## Sole production military authority. When true, old military runtime is OFF.
const USE_SIMPLE_WC3_AI: bool = true

## V2 readiness thresholds.
const V2_CREEP_READY_MILITARY_UNITS: int = 5
## Normal attack commit: living hero + this many non-hero military (10–12 band).
const V2_ATTACK_READY_MILITARY_UNITS: int = 10
const V2_ATTACK_READY_MILITARY_UNITS_PREFERRED: int = 12
## High-confidence lethal window may commit with a smaller formed squad.
const V2_ATTACK_LETHAL_MIN_MILITARY_UNITS: int = 6

## Early CREEP priority: prefer camps until ~hero level 3 / a few clears.
## Soft goal — after either threshold, an attack-ready army launches first pressure.
## Lethal / greed / clear strength advantage still interrupt earlier.
const V2_CREEP_TARGET_HERO_LEVEL: int = 3
const V2_CREEP_PREFERRED_CAMPS_BEFORE_ATTACK: int = 2
## Greed score (0–100) that outranks early creeping for a punish attack.
const V2_CREEP_GREED_INTERRUPT_SCORE: float = 45.0
## AI/player strength ratio that outranks early creeping (clear advantage).
## Aligned with V2_ATTACK_COMMIT_STRENGTH_RATIO so interrupt and commit agree.
const V2_CREEP_STRENGTH_ADVANTAGE_INTERRUPT: float = 1.25
const V2_CREEP_HERO_HEALTHY_RATIO: float = 0.55
## Nearby camp chaining after a clear (horizontal units).
const V2_CREEP_CHAIN_NEAR_RADIUS: float = 26.0
const V2_CREEP_CHAIN_MEDIUM_RADIUS: float = 38.0

## V2 ASSEMBLE behavior tuning.
const V2_ASSEMBLE_SLOT_TOLERANCE: float = 1.25
const V2_ASSEMBLE_SETTLE_TOLERANCE: float = 0.75
const V2_ASSEMBLE_RALLY_MIN_RADIUS: float = 8.0
const V2_ASSEMBLE_RALLY_MAX_RADIUS: float = 15.0
const V2_ASSEMBLE_PRODUCTION_EXIT_CLEARANCE: float = 4.0
const V2_ASSEMBLE_ATTACK_MOVE_DISTANCE: float = 6.0
## Hard ceiling so a healthy army cannot remain gathered forever.
## Kept aligned with the passive offense reevaluation invariant.
const V2_ASSEMBLE_MAX_PASSIVE_SECONDS: float = 15.0

## V2 DEFEND behavior tuning.
const V2_DEFEND_LEASH_RADIUS: float = 42.0
const V2_DEFEND_THREAT_CLEAR_SECONDS: float = 5.0
## Short post-defense regroup before CREEP / PRESSURE / ATTACK reevaluation.
const V2_POST_DEFEND_REGROUP_SECONDS: float = 3.0
## Recent building damage may keep defense live only within this window.
const V2_DEFEND_RECENT_DAMAGE_SECONDS: float = 8.0
## Healthy passive army must reevaluate offense at least this often.
const V2_PASSIVE_OFFENSE_REEVAL_SECONDS: float = 15.0
## Longer reissue stops Attack-Move / focus storms on large defense armies.
const V2_DEFEND_ORDER_REISSUE_SECONDS: float = 1.25
const V2_DEFEND_FOCUS_REISSUE_SECONDS: float = 1.50
const V2_DEFEND_THREAT_SEARCH_RANGE: float = 34.0
const V2_DEFEND_MELEE_INTERCEPT_OFFSET: float = 2.5
const V2_DEFEND_RANGED_STANDOFF: float = 7.0
const V2_DEFEND_SIEGE_STANDOFF: float = 12.0
const V2_DEFEND_RESERVE_OFFSET: float = 14.0
const V2_DEFEND_DAMAGED_HP_RATIO: float = 0.70
const V2_DEFEND_SCATTER_RADIUS: float = 18.0
const V2_DEFEND_SCATTER_COHESION_RATIO: float = 0.60
## Soft-hold DEFEND when destination / focus drift is within these tolerances.
const V2_DEFEND_DEST_EQUIVALENCE: float = 2.0
const V2_DEFEND_ORDER_MIN_AGE_SECONDS: float = 1.0
const V2_DEFEND_FOCUS_STICKY_RADIUS: float = 28.0

## Stable tactical squads (partition of the main army; not rebuilt every tick).
const V2_TACTICAL_SQUAD_MIN_SIZE: int = 10
const V2_TACTICAL_SQUAD_MAX_SIZE: int = 15
const V2_DEFEND_ACTIVE_SQUAD_CAP: int = 3

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
## Combat squad with no move / attack-move / fight order regenerates after this.
const V2_SQUAD_IDLE_SECONDS: float = 2.0


static func is_v2_enabled() -> bool:
	## True while the V2 stack is the configured military design path.
	## Under Simple WC3 this stays true so legacy military owners remain suspended,
	## but V2 nodes must not process (MatchCompositionRoot + is_v2_runtime_active).
	return USE_MILITARY_AI_V2


static func is_simple_wc3_ai_enabled() -> bool:
	return USE_SIMPLE_WC3_AI


static func is_v2_runtime_active() -> bool:
	## V2 may process only when it is the sole military authority (Simple off).
	return USE_MILITARY_AI_V2 and not USE_SIMPLE_WC3_AI


static func is_legacy_military_suspended() -> bool:
	## Legacy creep/wave/combat/defense mission owners stay off under Simple or V2.
	return USE_SIMPLE_WC3_AI or USE_MILITARY_AI_V2


static func ai_version_label() -> String:
	if USE_SIMPLE_WC3_AI:
		return "SimpleWC3"
	return "V2" if USE_MILITARY_AI_V2 else "Legacy"
