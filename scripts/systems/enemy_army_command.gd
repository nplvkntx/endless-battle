class_name EnemyArmyCommand
extends RefCounted

## Shared enemy army command helpers. Registers combat units and issues group orders.

const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMIES_GROUP := &"enemies"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const ENEMY_WORKERS_GROUP := &"enemy_workers"
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const BUILDINGS_GROUP := &"buildings"
const UNITS_GROUP := &"units"
const HEROES_GROUP := &"heroes"

const ARMY_RALLY_OFFSET := Vector3(-2.0, -0.5, 3.0)
const BASE_THREAT_DETECTION_RANGE := 60.0
const APPROACH_DETECTION_RANGE := 75.0
const WORKER_THREAT_RANGE := 36.0
const BUILDING_THREAT_RANGE := 32.0
const ENEMY_ECONOMY_AREA_RANGE := 42.0
const FORMATION_SPACING := 2.0
const RANGED_ROW_DEPTH_MULTIPLIER := 1.5
const HERO_ROW_DEPTH_MULTIPLIER := 1.25

const MIN_NON_HERO_FOR_HERO_JOIN := 5
const MIN_ARMY_UNITS_TO_CONTINUE_ATTACK := 6
const MIN_TOTAL_COMBAT_UNITS_FOR_ATTACK := 12
const MIN_MELEE_UNITS_FOR_ATTACK := 3
const MIN_RANGED_UNITS_FOR_ATTACK := 2
const ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS := 5
const ATTACK_STANDARD_MIN_NON_HERO_UNITS := 6
const ATTACK_TIMER_MIN_NON_HERO_UNITS := 12
const ATTACK_DESPERATE_MIN_NON_HERO_UNITS := 6
const ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS := 5
## Early creep escort: hero + 4 military minimum (prefer 5–7).
const CREEP_MIN_NON_HERO_UNITS := 4
const CREEP_PREFERRED_NON_HERO_UNITS := 5
const ATTACK_TIMER_STANDARD_SECONDS := 240.0
const ATTACK_TIMER_DESPERATE_SECONDS := 360.0
const DEBUG_ATTACK_GATE := false
const DEBUG_COMBAT_AI := false
const PLAYER_ARMY_STRENGTH_RATIO := 1.15
const ATTACK_AGGRESSIVE_STRENGTH_RATIO := 1.05
const ATTACK_NORMAL_STRENGTH_RATIO := 1.15
const DEFEND_FIGHT_STRENGTH_RATIO := 0.80
const RETREAT_STRENGTH_RATIO := 0.70
const EMERGENCY_RETREAT_ARMY_LOSS_RATIO := 0.40
const ASSEMBLY_RADIUS := 10.0
const ASSEMBLY_REQUIRED_PERCENT := 0.75
const ASSEMBLY_MAX_WAIT_SECONDS := 7.0
const COMBAT_EVAL_INTERVAL_SECONDS := 0.75
const MIN_STATE_DURATION_SECONDS := 0.75
const RETREAT_COOLDOWN_SECONDS := 10.0
const LOCAL_FIGHT_RADIUS := 30.0
const MAX_CHASE_DISTANCE := 25.0
const MAX_CHASE_DURATION_SECONDS := 6.0
const PLAYER_ARMY_MEMORY_DECAY_SECONDS := 45.0
const PLAYER_CREEP_DETECT_RADIUS := 28.0
const CREEP_HERO_WAIT_RADIUS := 18.0
const PHASE_EARLY_SECONDS := 300.0
const PHASE_MID_SECONDS := 600.0
const PHASE_EARLY_MIN_ARMY := 4
const PHASE_MID_MIN_ARMY := 12
const PHASE_LATE_MIN_ARMY := 20
const GROUP_MISSION_COHESION_RATIO := 0.75
const GROUP_MISSION_HERO_MAX_DISTANCE := 16.0
const KNOWN_PLAYER_SCOUT_RANGE := 55.0
const ARMY_GROUP_MAX_RADIUS := 24.0
const WAVE_REINFORCEMENT_WAIT_SECONDS := 5.0
const MIN_ATTACK_ARMY_POWER := 350
const HERO_ALONE_PLAYER_THREAT_RANGE := 18.0
const HERO_MAX_DISTANCE_FROM_ARMY := 16.0
const HERO_RETREAT_HP_RATIO := 0.35
const HERO_DEFENSE_CRITICAL_RETREAT_HP_RATIO := 0.20
const HERO_WAVE_JOIN_HP_RATIO := 0.60
## Creeping joins sooner than attack waves — do not demand near-full HP.
const HERO_CREEP_JOIN_HP_RATIO := 0.45
const HERO_DEFENSIVE_ABILITY_HP_RATIO := 0.40
const DEFENSE_GATHER_MAX_DISTANCE := 42.0
const DEFENSE_HERO_EXTRA_GATHER_DISTANCE := 14.0
const DEFENSE_THREAT_POWER_RANGE := 34.0
const DEFENSE_HOLD_FORWARD_DISTANCE := 10.0
const CORE_BASE_DEFENSE_RADIUS := BASE_THREAT_DETECTION_RANGE
const EMERGENCY_GATHER_WAIT_SECONDS := 3.0
const EMERGENCY_CLEAR_SECONDS := 5.0
const EMERGENCY_SERIOUS_THREAT_POWER := 120
const EMERGENCY_SCOUT_IGNORE_BUILDING_DISTANCE := 28.0
const EMERGENCY_HERO_JOIN_HP_RATIO := 0.35
const HERO_AOE_PLAYER_COUNT := 3
const HERO_AOE_CHECK_RANGE := 10.0
const HERO_POWER_STRIKE_SEARCH_RANGE := 14.0
const ATTACK_OBJECTIVE_REISSUE_SECONDS := 2.5
const OBJECTIVE_EVAL_INTERVAL_SECONDS := 1.0
const OBJECTIVE_STUCK_CHECK_INTERVAL_SECONDS := 0.5
const MAX_GROUP_ORDERS_PER_FRAME := 12
const FORMATION_CACHE_DEST_THRESHOLD := 3.0
const FORMATION_SLOT_SKIP_DISTANCE := 1.5
## Keep formation slots for the life of an order — do not reshuffle every AI tick.
const FORMATION_CACHE_REFRESH_SECONDS := 90.0
const GROUP_ORDER_DEST_TOLERANCE := 2.0
const GROUP_ORDER_SIGNATURE_TTL_SECONDS := 5.0
const GROUP_ORDER_MIN_REFRESH_SECONDS := 1.0
const PENDING_ORDER_DEST_BUCKET := 2.0
const DEFENSE_THREAT_CACHE_SECONDS := 0.35
const ATTACK_OBJECTIVE_STUCK_SECONDS := 3.0
const ATTACK_OBJECTIVE_NEAR_DISTANCE := 22.0
const ATTACK_OBJECTIVE_SPREAD_MULTIPLIER := 1.35
const ATTACK_CLOSE_TO_WIN_CC_HEALTH_RATIO := 0.35
const ATTACK_CLOSE_TO_WIN_ARMY_DISTANCE := 28.0
const IMPORTANT_BUILDING_SEARCH_RANGE := 200.0

const WAVE_1_MIN_NON_HERO_UNITS := 6
const WAVE_2_MIN_NON_HERO_UNITS := 12
const WAVE_3_MIN_NON_HERO_UNITS := 16
const WAVE_4_MIN_NON_HERO_UNITS := 20
const RESOURCE_HIGH_THRESHOLD := 3000
const RESOURCE_AGGRESSIVE_THRESHOLD := 6000
const REINFORCEMENT_MERGE_MIN_UNITS := 5
const WAVE_REGROUP_MAX_DISTANCE := 22.0
const WAVE_REBUILD_ARMY_RATIO := 0.40

const FINISHING_MODE_EVAL_INTERVAL := 2.0
const FINISHING_MODE_EXIT_COOLDOWN := 8.0
const FINISHING_MODE_OBJECTIVE_REISSUE_SECONDS := 1.5
const FINISHING_MODE_REINFORCEMENT_PULL_INTERVAL := 2.0
const FINISHING_MODE_MIN_AI_COMBAT_UNITS := 15
const FINISHING_MODE_MAX_PLAYER_COMBAT_UNITS := 5
const FINISHING_MODE_MAX_PLAYER_MILITARY_PRODUCTION := 1
const FINISHING_MODE_WEAK_PLAYER_COMBAT_FOR_PRODUCTION := 8
const FINISHING_MODE_IN_BASE_DISTANCE := 35.0
const FINISHING_MODE_WEAK_RESISTANCE_POWER := 80
const FINISHING_MODE_PLAYER_RECOVERY_RATIO := 0.65
const FINISHING_MODE_ARMY_DESTROYED_RATIO := 0.25
const FINISHING_MODE_MIN_PUSH_UNITS := 4
const FINISHING_MODE_TOWER_THREAT_BUFFER := 2.0
const REINFORCEMENT_EARLY_MIN := 4
const REINFORCEMENT_MID_MIN := 6
const REINFORCEMENT_LATE_MIN := 8
const EMERGENCY_BASE_RADIUS := 25.0
const CREEP_CONTEST_COOLDOWN_SECONDS := 12.0
const DEBUG_AI_ORDERS := false
const DESTROYED_ARMY_REGROUP_THRESHOLD_RATIO := 0.50
const MIN_SURVIVORS_FOR_OFFENSIVE := 4

enum ArmyMode {
	IDLE,
	OPENING,
	ASSEMBLING,
	CREEPING,
	ATTACKING,
	INTERCEPTING,
	DEFENDING,
	RETREATING,
	REGROUPING,
}

enum AttackWaveState {
	NONE,
	PREPARING,
	GATHERING,
	WAITING_FOR_HERO,
	REGROUPING,
	ADVANCING,
	ENGAGING,
	RETREATING,
	RECOVERING,
}

enum StrategicState {
	ECONOMY,
	CREEPING,
	PREPARING_ATTACK,
	ATTACKING,
	DEFENDING,
	EMERGENCY_DEFENDING,
	RETREATING,
	RECOVERING,
}

## Single authoritative army mission for F3 + execution. StrategicPhase alone must never imply CREEPING.
enum ExecutableMission {
	NONE,
	IDLE,
	CREEPING,
	ATTACK_PLAYER,
	LETHAL_PUSH,
	DEFEND,
	EMERGENCY_DEFEND,
	REGROUP,
	RETREAT,
	ASSEMBLE,
}

const STRATEGIC_THREAT_CLEAR_SECONDS := 6.0
const STRATEGIC_ATTACK_COMMITMENT_SECONDS := 8.0
const MISSION_PROGRESS_STALL_SECONDS := 6.5
const MISSION_WATCHDOG_INTERVAL_SECONDS := 1.0
const MISSION_PROGRESS_DISTANCE_EPSILON := 2.5
const HOSTILE_TERRITORY_BASE_RANGE := 38.0
const HOSTILE_TERRITORY_ENGAGE_RANGE := 32.0
const HOSTILE_TERRITORY_STRENGTH_RATIO := 0.95
const HOSTILE_TERRITORY_LETHAL_RATIO := 1.25

const ATTACK_WAVE_STAGING_OFFSET := Vector3(8.0, 0.0, 0.0)
const ATTACK_WAVE_GATHER_PERCENT := 0.75
const ATTACK_WAVE_REGROUP_PERCENT := 0.70
const ATTACK_WAVE_HERO_STAGING_DISTANCE := 12.0
const ATTACK_WAVE_HERO_WAIT_TIMEOUT_SECONDS := 15.0
const ATTACK_WAVE_REGROUP_TIMEOUT_SECONDS := 12.0
const ATTACK_WAVE_RECOVERY_COOLDOWN_SECONDS := 18.0
const ATTACK_WAVE_TARGET_COMMITMENT_SECONDS := 8.0
const ATTACK_WAVE_COMMAND_REFRESH_SECONDS := 2.5
const ATTACK_WAVE_MAX_STRAGGLERS := 2
const ATTACK_WAVE_STRAGGLER_IGNORE_SECONDS := 10.0
const ATTACK_WAVE_ENGAGE_DISTANCE := 28.0
const ATTACK_WAVE_COHESION_RADIUS := 20.0
const ATTACK_WAVE_MIN_COHESION_RATIO := 0.65
const ATTACK_WAVE_HERO_WITHOUT_ARMY_POWER := 500
const ATTACK_WAVE_MISSION_LOCK_SECONDS := 6.0
const EXPOSED_PLAYER_ARMY_SEARCH_RANGE := 90.0
const EXPOSED_PLAYER_ARMY_MIN_UNITS := 3

## Match-owned runtime host. When bound, this is the composition AIPlayerState
## (single authority). When unbound, a private offline instance is used so helpers
## never create a second live match authority.
static var _unbound_runtime: AIPlayerState = null

static func _rt() -> AIPlayerState:
	var bound: AIPlayerState = get_bound_ai_player_state()
	if bound != null:
		return bound
	if _unbound_runtime == null or not is_instance_valid(_unbound_runtime):
		_unbound_runtime = AIPlayerState.new()
		_unbound_runtime.name = "AIPlayerState_Unbound"
	return _unbound_runtime


## --- Identity / strategic (SoT: AIPlayerState) ---
static var _army_mode: ArmyMode:
	get:
		return _rt().army_mode as ArmyMode
	set(value):
		_rt().army_mode = int(value)

static var _mode_claim_msec: int:
	get:
		return _rt().mode_claim_msec
	set(value):
		_rt().mode_claim_msec = value

static var _strategic_state: StrategicState:
	get:
		return _rt().strategic_state as StrategicState
	set(value):
		_rt().strategic_state = int(value)

static var _strategic_state_msec: int:
	get:
		return _rt().strategic_state_msec
	set(value):
		_rt().strategic_state_msec = value

static var _pending_strategic_state: StrategicState:
	get:
		return _rt().pending_strategic_state as StrategicState
	set(value):
		_rt().pending_strategic_state = int(value)

static var _pending_strategic_reason: String:
	get:
		return _rt().pending_strategic_reason
	set(value):
		_rt().pending_strategic_reason = value

static var _has_pending_strategic_transition: bool:
	get:
		return _rt().has_pending_strategic_transition
	set(value):
		_rt().has_pending_strategic_transition = value

static var _orders_authorized: bool:
	get:
		return _rt().orders_authorized
	set(value):
		_rt().orders_authorized = value

static var _assembly_timer: float:
	get:
		return _rt().assembly_timer
	set(value):
		_rt().assembly_timer = value

static var _assembly_rally: Vector3:
	get:
		return _rt().assembly_rally
	set(value):
		_rt().assembly_rally = value

static var _assembly_required_count: int:
	get:
		return _rt().assembly_required_count
	set(value):
		_rt().assembly_required_count = value

static var _retreat_cooldown: float:
	get:
		return _rt().retreat_cooldown
	set(value):
		_rt().retreat_cooldown = value

static var _fight_start_strength: float:
	get:
		return _rt().fight_start_strength
	set(value):
		_rt().fight_start_strength = value

static var _fight_anchor_position: Vector3:
	get:
		return _rt().fight_anchor_position
	set(value):
		_rt().fight_anchor_position = value

static var _fight_start_msec: int:
	get:
		return _rt().fight_start_msec
	set(value):
		_rt().fight_start_msec = value

static var _last_combat_eval_msec: int = 0
static var _main_army_cache: Array = []

static var _player_army_memory: Dictionary:
	get:
		return _rt().player_army_memory
	set(value):
		_rt().player_army_memory = value

static var _is_rebuilding_army: bool:
	get:
		return _rt().is_rebuilding_army
	set(value):
		_rt().is_rebuilding_army = value

static var _active_wave_start_unit_count: int:
	get:
		return _rt().active_wave_start_unit_count
	set(value):
		_rt().active_wave_start_unit_count = value

static var _active_wave_objective: Node3D:
	get:
		return _rt().active_wave_objective
	set(value):
		_rt().active_wave_objective = value

static var _active_wave_objective_position: Vector3:
	get:
		return _rt().active_wave_objective_position
	set(value):
		_rt().active_wave_objective_position = value

static var _objective_reissue_timer: float:
	get:
		return _rt().objective_reissue_timer
	set(value):
		_rt().objective_reissue_timer = value
static var _objective_stuck_timer: float:
	get:
		return _rt().objective_stuck_timer
	set(value):
		_rt().objective_stuck_timer = value
static var _objective_last_building_health: int:
	get:
		return _rt().objective_last_building_health
	set(value):
		_rt().objective_last_building_health = value

static var _finishing_mode_active: bool:
	get:
		return _rt().finishing_mode_active
	set(value):
		_rt().finishing_mode_active = value

static var _finishing_mode_exit_cooldown: float:
	get:
		return _rt().finishing_mode_exit_cooldown
	set(value):
		_rt().finishing_mode_exit_cooldown = value

static var _finishing_mode_eval_timer: float:
	get:
		return _rt().finishing_mode_eval_timer
	set(value):
		_rt().finishing_mode_eval_timer = value

static var _last_finishing_objective: Node3D:
	get:
		return _rt().last_finishing_objective
	set(value):
		_rt().last_finishing_objective = value

static var _emergency_defense_active: bool:
	get:
		return _rt().emergency_defense_active
	set(value):
		_rt().emergency_defense_active = value

static var _emergency_threat_position: Vector3:
	get:
		return _rt().emergency_threat_position
	set(value):
		_rt().emergency_threat_position = value

static var _emergency_reason: StringName:
	get:
		return _rt().emergency_reason
	set(value):
		_rt().emergency_reason = value

static var _combat_units_cache_frame: int = -1
static var _cached_offensive_wave_units_frame: int = -1
static var _cached_offensive_wave_units: Array = []
## Command queue SoT: AIPlayerState.pending_group_orders (ArmyCommanderV2 drains).
static var _pending_group_orders: Array:
	get:
		return _rt().pending_group_orders
	set(value):
		_rt().pending_group_orders = value
## Attack-objective cadence (SoT: AIPlayerState; cleared with objective cancel).
static var _objective_eval_timer: float:
	get:
		return _rt().objective_eval_timer
	set(value):
		_rt().objective_eval_timer = value
static var _objective_stuck_check_timer: float:
	get:
		return _rt().objective_stuck_check_timer
	set(value):
		_rt().objective_stuck_check_timer = value
static var _formation_cache_unit_ids: Array[int]:
	get:
		return _rt().formation_cache_unit_ids
	set(value):
		_rt().formation_cache_unit_ids = value

static var _formation_cache_center: Vector3:
	get:
		return _rt().formation_cache_center
	set(value):
		_rt().formation_cache_center = value

static var _formation_cache_use_attack_move: bool:
	get:
		return _rt().formation_cache_use_attack_move
	set(value):
		_rt().formation_cache_use_attack_move = value

static var _formation_cache_targets: Array[Vector3]:
	get:
		return _rt().formation_cache_targets
	set(value):
		_rt().formation_cache_targets = value

static var _formation_cache_msec: int:
	get:
		return _rt().formation_cache_msec
	set(value):
		_rt().formation_cache_msec = value

static var _formation_cache_army_mode: int:
	get:
		return _rt().formation_cache_army_mode
	set(value):
		_rt().formation_cache_army_mode = value

static var _active_group_order_signature: String:
	get:
		return _rt().active_group_order_signature
	set(value):
		_rt().active_group_order_signature = value

static var _active_group_order_dest: Vector3:
	get:
		return _rt().active_group_order_dest
	set(value):
		_rt().active_group_order_dest = value

static var _active_group_order_mission: int:
	get:
		return _rt().active_group_order_mission
	set(value):
		_rt().active_group_order_mission = value

static var _active_group_order_generation: int:
	get:
		return _rt().active_group_order_generation
	set(value):
		_rt().active_group_order_generation = value

static var _active_group_order_msec: int:
	get:
		return _rt().active_group_order_msec
	set(value):
		_rt().active_group_order_msec = value

static var _group_order_generation: int:
	get:
		return _rt().group_order_generation
	set(value):
		_rt().group_order_generation = value

static var _issuing_group_order_batch: bool:
	get:
		return _rt().issuing_group_order_batch
	set(value):
		_rt().issuing_group_order_batch = value

## TTL threat scratch (SoT host: AIPlayerState). Recomputed from world; never authoritative.
static var _defense_threat_cache: Dictionary:
	get:
		return _rt().defense_threat_cache
	set(value):
		_rt().defense_threat_cache = value
static var _defense_threat_cache_msec: int:
	get:
		return _rt().defense_threat_cache_msec
	set(value):
		_rt().defense_threat_cache_msec = value
static var _emergency_threat_cache: Dictionary:
	get:
		return _rt().emergency_threat_cache
	set(value):
		_rt().emergency_threat_cache = value
static var _emergency_threat_cache_msec: int:
	get:
		return _rt().emergency_threat_cache_msec
	set(value):
		_rt().emergency_threat_cache_msec = value
## Creep contest cooldowns (SoT: AIPlayerState.creep_contest_cooldowns).
static var _creep_contest_cooldowns: Dictionary:
	get:
		return _rt().creep_contest_cooldowns
	set(value):
		_rt().creep_contest_cooldowns = value
## Reinforcement waiting registry (SoT: AIPlayerState.reinforcement_pool).
static var _reinforcement_pool: Dictionary:
	get:
		return _rt().reinforcement_pool
	set(value):
		_rt().reinforcement_pool = value

static var _attack_wave_state: AttackWaveState:
	get:
		return _rt().attack_wave_state as AttackWaveState
	set(value):
		_rt().attack_wave_state = int(value)

static var _attack_wave_state_msec: int:
	get:
		return _rt().attack_wave_state_msec
	set(value):
		_rt().attack_wave_state_msec = value

static var _attack_wave_units: Array:
	get:
		return _rt().attack_wave_units
	set(value):
		_rt().attack_wave_units = value

static var _attack_wave_staging_point: Vector3:
	get:
		return _rt().attack_wave_staging_point
	set(value):
		_rt().attack_wave_staging_point = value

static var _attack_wave_target_position: Vector3:
	get:
		return _rt().attack_wave_target_position
	set(value):
		_rt().attack_wave_target_position = value

static var _attack_wave_target_node: Node3D:
	get:
		return _rt().attack_wave_target_node
	set(value):
		_rt().attack_wave_target_node = value

static var _attack_wave_target_committed_until_msec: int:
	get:
		return _rt().attack_wave_target_committed_until_msec
	set(value):
		_rt().attack_wave_target_committed_until_msec = value

static var _attack_wave_gather_pull_timer: float:
	get:
		return _rt().attack_wave_gather_pull_timer
	set(value):
		_rt().attack_wave_gather_pull_timer = value

static var _attack_wave_hero_wait_timer: float:
	get:
		return _rt().attack_wave_hero_wait_timer
	set(value):
		_rt().attack_wave_hero_wait_timer = value

static var _attack_wave_regroup_timer: float:
	get:
		return _rt().attack_wave_regroup_timer
	set(value):
		_rt().attack_wave_regroup_timer = value

static var _attack_wave_recovery_timer: float:
	get:
		return _rt().attack_wave_recovery_timer
	set(value):
		_rt().attack_wave_recovery_timer = value

static var _attack_wave_command_refresh_timer: float:
	get:
		return _rt().attack_wave_command_refresh_timer
	set(value):
		_rt().attack_wave_command_refresh_timer = value

static var _attack_wave_hero_unreachable_retries: int:
	get:
		return _rt().attack_wave_hero_unreachable_retries
	set(value):
		_rt().attack_wave_hero_unreachable_retries = value

static var _attack_wave_min_non_hero_units: int:
	get:
		return _rt().attack_wave_min_non_hero_units
	set(value):
		_rt().attack_wave_min_non_hero_units = value

static var _attack_wave_ready_to_advance: bool:
	get:
		return _rt().attack_wave_ready_to_advance
	set(value):
		_rt().attack_wave_ready_to_advance = value

static var _attack_wave_pending_transition: AttackWaveState:
	get:
		return _rt().attack_wave_pending_transition as AttackWaveState
	set(value):
		_rt().attack_wave_pending_transition = int(value)

static var _attack_wave_pending_transition_reason: String:
	get:
		return _rt().attack_wave_pending_transition_reason
	set(value):
		_rt().attack_wave_pending_transition_reason = value

## Authoritative executable army mission (SoT: AIPlayerState when bound).
## Last shared-squad route failure reason (ephemeral; not strategic state).
static var _last_squad_route_failure_reason: String = ""

static var _exec_mission: ExecutableMission:
	get:
		return _rt().exec_mission as ExecutableMission
	set(value):
		_rt().exec_mission = int(value)

static var _exec_objective_node: Node3D:
	get:
		return _rt().exec_objective_node
	set(value):
		_rt().exec_objective_node = value
static var _exec_objective_position: Vector3:
	get:
		return _rt().exec_objective_position
	set(value):
		_rt().exec_objective_position = value

static var _exec_objective_name: String:
	get:
		return _rt().exec_objective_name
	set(value):
		_rt().exec_objective_name = value

static var _exec_mission_start_msec: int:
	get:
		return _rt().exec_mission_start_msec
	set(value):
		_rt().exec_mission_start_msec = value

static var _exec_last_progress_msec: int:
	get:
		return _rt().exec_last_progress_msec
	set(value):
		_rt().exec_last_progress_msec = value
static var _exec_last_distance: float:
	get:
		return _rt().exec_last_distance
	set(value):
		_rt().exec_last_distance = value
static var _exec_squad_ids: Array[int]:
	get:
		return _rt().exec_squad_ids
	set(value):
		_rt().exec_squad_ids = value
static var _exec_order_label: String:
	get:
		return _rt().exec_order_label
	set(value):
		_rt().exec_order_label = value

static var _exec_transition_reason: String:
	get:
		return _rt().exec_transition_reason
	set(value):
		_rt().exec_transition_reason = value

static var _exec_camp_reserved: bool:
	get:
		return _rt().exec_camp_reserved
	set(value):
		_rt().exec_camp_reserved = value

static var _exec_watchdog_timer: float:
	get:
		return _rt().exec_watchdog_timer
	set(value):
		_rt().exec_watchdog_timer = value
static var _exec_watchdog_refreshed: bool:
	get:
		return _rt().exec_watchdog_refreshed
	set(value):
		_rt().exec_watchdog_refreshed = value
static var _exec_last_report: String:
	get:
		return _rt().exec_last_report
	set(value):
		_rt().exec_last_report = value
static var _allow_hostile_engagement: bool:
	get:
		return _rt().allow_hostile_engagement
	set(value):
		_rt().allow_hostile_engagement = value

## Match composition binding. Null outside an active MatchCompositionRoot.
## Migrated bags are SoT on AIPlayerState via _rt() — no dual-write.
static var _bound_player_state: AIPlayerState = null
static var _declared_command_authority: Node = null



static func bind_match_composition(state: AIPlayerState, authority: Node) -> void:
	_bound_player_state = state
	_declared_command_authority = authority
	## SoT is the bound AIPlayerState via _rt() — no dual-write copy.
	if state != null:
		state.set_military_command_authority(authority)


static func unbind_match_composition() -> void:
	_bound_player_state = null
	_declared_command_authority = null
	## Fresh unbound host so offline helpers cannot observe the last match.
	if _unbound_runtime != null and is_instance_valid(_unbound_runtime):
		_unbound_runtime.reset()
	else:
		_unbound_runtime = null


static func get_bound_ai_player_state() -> AIPlayerState:
	if _bound_player_state != null and is_instance_valid(_bound_player_state):
		return _bound_player_state
	_bound_player_state = null
	return null


static func get_declared_command_authority() -> Node:
	if _declared_command_authority != null and is_instance_valid(_declared_command_authority):
		return _declared_command_authority
	_declared_command_authority = null
	return null


static func _sync_player_state_identity() -> void:
	## No-op: migrated bags (identity/exec/combat/wave/formation/finishing/
	## command-queue/reinforcement/threat-TTL/mission-scratch) live on _rt().
	pass


static func get_army_mode() -> ArmyMode:
	return _army_mode


static func purge_stale_runtime_caches() -> void:
	_main_army_cache = NodeSafety.clean_and_dedupe_nodes(_main_army_cache)
	_attack_wave_units = NodeSafety.clean_and_dedupe_nodes(_attack_wave_units)
	_cached_offensive_wave_units = NodeSafety.clean_and_dedupe_nodes(_cached_offensive_wave_units)
	_pending_group_orders = _pending_group_orders.filter(
		func(entry: Variant) -> bool:
			if not entry is Dictionary:
				return false
			return _pending_order_unit_is_alive(entry as Dictionary)
	)
	PerfCounters.set_pending_group_orders(_pending_group_orders.size())
	PerfCounters.set_combat_group_size(_main_army_cache.size())


static func get_strategic_state() -> StrategicState:
	return _strategic_state


static func get_strategic_state_priority(state: StrategicState) -> int:
	match state:
		StrategicState.EMERGENCY_DEFENDING:
			return 1
		StrategicState.DEFENDING:
			return 2
		StrategicState.RETREATING:
			return 3
		StrategicState.ATTACKING:
			return 4
		StrategicState.PREPARING_ATTACK:
			return 5
		StrategicState.CREEPING:
			return 6
		StrategicState.RECOVERING:
			return 7
		StrategicState.ECONOMY:
			return 8
		_:
			return 9


static func request_strategic_state(new_state: StrategicState, reason: String = "") -> bool:
	if new_state == _strategic_state:
		return false

	if _has_pending_strategic_transition:
		return false

	var elapsed_seconds: float = float(
		Time.get_ticks_msec() - _strategic_state_msec
	) / 1000.0
	var new_priority: int = get_strategic_state_priority(new_state)
	var current_priority: int = get_strategic_state_priority(_strategic_state)
	if (
		elapsed_seconds < MIN_STATE_DURATION_SECONDS
		and new_priority > current_priority
	):
		return false

	_pending_strategic_state = new_state
	_pending_strategic_reason = reason
	_has_pending_strategic_transition = true
	_sync_player_state_identity()
	return true


static func apply_pending_strategic_transition() -> void:
	if not _has_pending_strategic_transition:
		return

	var previous_state: StrategicState = _strategic_state
	_strategic_state = _pending_strategic_state
	_strategic_state_msec = Time.get_ticks_msec()
	_has_pending_strategic_transition = false
	_log_strategic_state_change(previous_state, _strategic_state, _pending_strategic_reason)
	_pending_strategic_reason = ""
	_sync_player_state_identity()


static func allows_offensive_orders() -> bool:
	return _strategic_state not in [
		StrategicState.EMERGENCY_DEFENDING,
		StrategicState.DEFENDING,
		StrategicState.RETREATING,
		StrategicState.RECOVERING,
	]


## Neutral-camp creeping is allowed while recovering/economy. Player attacks stay gated separately.
static func allows_creep_orders() -> bool:
	## V2 owns mission selection — legacy strategic gates must not soft-lock CREEP
	## after ATTACK/DEFEND left strategic state stuck on a higher-priority label.
	if MilitaryAIConfig.is_v2_enabled():
		## Live emergency flag only — stale EMERGENCY_DEFENDING labels must not block forever.
		if _emergency_defense_active:
			return false
		if _strategic_state == StrategicState.RETREATING:
			return false
		return true

	if is_defense_blocking_offense():
		return false

	if _strategic_state == StrategicState.RETREATING:
		return false

	if _strategic_state in [
		StrategicState.PREPARING_ATTACK,
		StrategicState.ATTACKING,
	]:
		return false

	return _strategic_state in [
		StrategicState.ECONOMY,
		StrategicState.CREEPING,
		StrategicState.RECOVERING,
	]


## Align legacy army mode + strategic state with a V2 mission so order issuance cannot desync.
static func prepare_v2_execution(
	mode: ArmyMode,
	strategic: StrategicState,
	reason: String
) -> bool:
	if not MilitaryAIConfig.is_v2_enabled():
		return try_claim_army_mode(mode, true)

	force_set_strategic_state_for_v2(strategic, reason)
	if _army_mode == mode:
		return true
	if try_claim_army_mode(mode, true):
		return true

	## Hard reclaim: drop a soft-blocking mode (assemble/defend/attack/creep/regroup)
	## so CREEP/ATTACK can always claim after a director transition.
	if _army_mode == ArmyMode.RETREATING and mode != ArmyMode.RETREATING:
		return false

	if _army_mode != ArmyMode.IDLE:
		var previous_mode: ArmyMode = _army_mode
		_set_army_mode(ArmyMode.IDLE, previous_mode)
		_debug_combat(
			"V2 reclaim: released %s for %s (%s)" % [
				_army_mode_label(previous_mode),
				_army_mode_label(mode),
				reason,
			]
		)
	return try_claim_army_mode(mode, true)


## Immediate strategic sync for V2 (bypasses pending/priority soft-locks).
static func force_set_strategic_state_for_v2(
	new_state: StrategicState,
	reason: String
) -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		request_strategic_state(new_state, reason)
		return

	if new_state == _strategic_state:
		_has_pending_strategic_transition = false
		_pending_strategic_reason = ""
		_sync_player_state_identity()
		return

	## Never yank an ACTIVE emergency defense into offense.
	## Once emergency flags are cleared, V2 may leave a stale EMERGENCY_DEFENDING label
	## (otherwise ASSEMBLE/CREEP/ATTACK soft-lock forever via is_defense_blocking_offense).
	if (
		_strategic_state == StrategicState.EMERGENCY_DEFENDING
		and _emergency_defense_active
		and new_state not in [
			StrategicState.EMERGENCY_DEFENDING,
			StrategicState.DEFENDING,
			StrategicState.RETREATING,
		]
	):
		return

	var previous_state: StrategicState = _strategic_state
	_strategic_state = new_state
	_strategic_state_msec = Time.get_ticks_msec()
	_has_pending_strategic_transition = false
	_pending_strategic_reason = ""
	_log_strategic_state_change(previous_state, new_state, reason)
	_sync_player_state_identity()


## Clear static army ownership between matches. Class-level state otherwise persists in-editor.
static func reset_match_state() -> void:
	## Match-owned SoT bags live on _rt() (bound AIPlayerState or unbound host).
	_rt().reset()
	_clear_executable_mission_state("match reset")
	## Frame-local caches must not survive reset or become authoritative.
	_last_combat_eval_msec = 0
	_main_army_cache.clear()
	_reset_objective_tracking()
	EnemyAggression.reset_match_state()
	_combat_units_cache_frame = -1
	_cached_offensive_wave_units_frame = -1
	_cached_offensive_wave_units.clear()
	## Telemetry lives on EnemyArmyCommandTelemetry — never match SoT.
	EnemyArmyCommandTelemetry.reset_match_state()
	EnemyUnitMission.reset_match_state()
	var bound_state: AIPlayerState = get_bound_ai_player_state()
	if bound_state != null:
		bound_state.set_military_command_authority(_declared_command_authority)


## Verify/debug: seed frame-local caches so reset can prove they do not survive.
static func seed_frame_local_caches_for_verify() -> void:
	_combat_units_cache_frame = 42
	_cached_offensive_wave_units_frame = 42
	_main_army_cache = [{"verify_seed": true}]
	_cached_offensive_wave_units = [{"verify_seed": true}]
	_last_combat_eval_msec = 999


## Verify/debug: snapshot of frame-local caches (never authoritative).
static func get_frame_local_cache_snapshot_for_verify() -> Dictionary:
	return {
		"combat_units_cache_frame": _combat_units_cache_frame,
		"offensive_wave_cache_frame": _cached_offensive_wave_units_frame,
		"main_army_cache_size": _main_army_cache.size(),
		"offensive_wave_cache_size": _cached_offensive_wave_units.size(),
		"last_combat_eval_msec": _last_combat_eval_msec,
	}


## Verify/debug: seed creep-contest + objective timers on match SoT.
static func seed_leftover_runtime_state_for_verify() -> void:
	_creep_contest_cooldowns[7777] = Time.get_ticks_msec() + 60000
	_objective_reissue_timer = 11.0
	_objective_stuck_timer = 22.0
	_objective_last_building_health = 55
	_objective_eval_timer = 3.5
	_objective_stuck_check_timer = 1.25


## Verify/debug: snapshot of match/mission leftovers now owned by AIPlayerState.
static func get_leftover_runtime_snapshot_for_verify() -> Dictionary:
	return {
		"creep_contest_count": _creep_contest_cooldowns.size(),
		"objective_reissue_timer": _objective_reissue_timer,
		"objective_stuck_timer": _objective_stuck_timer,
		"objective_last_building_health": _objective_last_building_health,
		"objective_eval_timer": _objective_eval_timer,
		"objective_stuck_check_timer": _objective_stuck_check_timer,
	}


## Pending group-order count (command queue owned by AIPlayerState).
static func get_pending_group_order_count() -> int:
	return _pending_group_orders.size()


## Reinforcement pool entry count (sole owner: AIPlayerState when bound).
static func get_reinforcement_pool_count() -> int:
	purge_stale_reinforcement_pool()
	return _reinforcement_pool.size()


## Verify only: raw pool size without living-unit purge (ownership identity checks).
static func get_reinforcement_pool_raw_count_for_verify() -> int:
	return _reinforcement_pool.size()


## Verify only: creep-contest cooldown count (SoT: AIPlayerState).
static func get_creep_contest_cooldown_count_for_verify() -> int:
	return _creep_contest_cooldowns.size()


static func find_strategic_director(tree: SceneTree) -> EnemyStrategicDirector:
	if tree == null:
		return null

	var composition: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	if composition != null and composition.enemy_strategic_director != null:
		return composition.enemy_strategic_director

	var root: Node = tree.root
	if root == null:
		return null

	return root.find_child("EnemyStrategicDirector", true, false) as EnemyStrategicDirector


## Shared player-attack gate. Fail-closed when the strategic director is missing.
## DEFEND / emergency defense intentionally bypass this — callers must allow Mission.DEFEND.
static func can_launch_player_attack(tree: SceneTree) -> bool:
	## Military AI V2 owns offense readiness (squad size / lethal window).
	## Legacy strategic-phase gates must not block V2 Attack-Move.
	if MilitaryAIConfig.is_v2_enabled():
		return true

	var director: EnemyStrategicDirector = find_strategic_director(tree)
	if director == null:
		return false
	return director.can_launch_player_attack()


## Inverse of can_launch_player_attack. Prefer can_launch_player_attack at call sites.
static func blocks_player_offense(tree: SceneTree) -> bool:
	return not can_launch_player_attack(tree)


static func get_player_offense_block_reason(tree: SceneTree) -> String:
	var director: EnemyStrategicDirector = find_strategic_director(tree)
	if director == null:
		return "phase unknown"

	if director.can_launch_player_attack():
		return ""

	return "phase %s" % director.get_strategic_phase_name()


## Validates hero + army cohesion before creep / coordinated missions.
static func can_start_group_mission(
	tree: SceneTree,
	units: Array = [],
	min_non_hero: int = ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS
) -> Dictionary:
	if tree == null:
		return {"ok": false, "reason": &"no_tree"}

	if get_army_mode() == ArmyMode.RETREATING or is_retreat_on_cooldown():
		return {"ok": false, "reason": &"retreat_active"}

	if get_army_mode() in [ArmyMode.DEFENDING, ArmyMode.INTERCEPTING]:
		return {"ok": false, "reason": &"defense_owns_army"}

	if get_army_mode() == ArmyMode.ATTACKING and is_attack_wave_active():
		return {"ok": false, "reason": &"attack_owns_army"}

	var army: Array = NodeSafety.clean_node_array(
		units if not units.is_empty() else collect_living_combat_units(tree)
	)
	if army.is_empty():
		return {"ok": false, "reason": &"no_army"}

	var hero: Hero = null
	var non_hero: Array = []
	for unit: Variant in army:
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Hero:
			hero = unit as Hero
		elif is_non_hero_combat_unit(unit as Node):
			non_hero.append(unit)

	if hero == null or not is_living_combat_unit(hero):
		return {"ok": false, "reason": &"no_hero"}

	if get_health_ratio(hero) <= 0.0:
		return {"ok": false, "reason": &"hero_dead"}

	if non_hero.size() < min_non_hero:
		return {
			"ok": false,
			"reason": &"army_too_small",
			"non_hero_count": non_hero.size(),
			"required": min_non_hero,
		}

	var army_center: Vector3 = compute_army_center(army)
	if army_center == Vector3.ZERO:
		return {"ok": false, "reason": &"no_army_center"}

	if (
		horizontal_distance(hero.global_position, army_center)
		> GROUP_MISSION_HERO_MAX_DISTANCE
	):
		return {"ok": false, "reason": &"hero_separated"}

	var near_count: int = filter_units_near_rally(
		non_hero,
		army_center,
		ASSEMBLY_RADIUS * 2.0
	).size()
	if float(near_count) / float(non_hero.size()) < GROUP_MISSION_COHESION_RATIO:
		return {
			"ok": false,
			"reason": &"army_scattered",
			"near_count": near_count,
			"non_hero_count": non_hero.size(),
		}

	return {
		"ok": true,
		"reason": &"ready",
		"units": army,
		"hero": hero,
		"non_hero_count": non_hero.size(),
		"army_center": army_center,
	}


static func allows_attack_wave_orders() -> bool:
	if not allows_offensive_orders():
		return false

	return _strategic_state in [
		StrategicState.ECONOMY,
		StrategicState.PREPARING_ATTACK,
		StrategicState.ATTACKING,
		StrategicState.RECOVERING,
	]


static func is_defense_blocking_offense() -> bool:
	if MilitaryAIConfig.is_v2_enabled():
		## V2: MilitaryDirectorV2 already prioritizes DEFEND. Only a live emergency
		## flag may block offense — stale DEFENDING/EMERGENCY_DEFENDING labels must not.
		return _emergency_defense_active
	return _strategic_state in [
		StrategicState.EMERGENCY_DEFENDING,
		StrategicState.DEFENDING,
	]


static func _log_strategic_state_change(
	from_state: StrategicState,
	to_state: StrategicState,
	reason: String
) -> void:
	var message: String = ""
	match to_state:
		StrategicState.PREPARING_ATTACK:
			message = "Preparing coordinated attack"
		StrategicState.ATTACKING:
			message = "Launching attack"
		StrategicState.EMERGENCY_DEFENDING:
			message = "Emergency defense override"
		StrategicState.DEFENDING:
			message = "Defending base"
		StrategicState.RETREATING:
			if reason.contains("Hero HP") or reason.contains("hero"):
				message = reason if reason.begins_with("Retreat:") else "Retreat: %s" % reason
			elif reason.contains("weaker") or reason.contains("strength") or reason.contains("unfavorable"):
				message = "Retreat: Army weaker than enemy"
			else:
				message = "Retreat: %s" % (reason if not reason.is_empty() else "unfavorable fight")
		StrategicState.CREEPING:
			message = "Creeping: clearing camps"
		StrategicState.RECOVERING:
			if from_state == StrategicState.RETREATING:
				message = "Retreat complete: rebuilding army"
			else:
				message = "Threat cleared, regrouping"
		_:
			pass

	if not message.is_empty():
		var log_message: String = message
		if (
			not reason.is_empty()
			and to_state != StrategicState.RETREATING
			and to_state != StrategicState.RECOVERING
		):
			log_message = "%s (%s)" % [message, reason]
		EnemyAIDebug.log_once("strategic_state", log_message)


static func _strategic_state_label(state: StrategicState) -> String:
	match state:
		StrategicState.ECONOMY:
			return "ECONOMY"
		StrategicState.CREEPING:
			return "CREEPING"
		StrategicState.PREPARING_ATTACK:
			return "PREPARING_ATTACK"
		StrategicState.ATTACKING:
			return "ATTACKING"
		StrategicState.DEFENDING:
			return "DEFENDING"
		StrategicState.EMERGENCY_DEFENDING:
			return "EMERGENCY_DEFENDING"
		StrategicState.RETREATING:
			return "RETREATING"
		StrategicState.RECOVERING:
			return "RECOVERING"
		_:
			return "UNKNOWN"


static func is_retreat_on_cooldown() -> bool:
	return _retreat_cooldown > 0.0


static func tick_retreat_cooldown(delta: float) -> void:
	if _retreat_cooldown > 0.0:
		_retreat_cooldown = maxf(0.0, _retreat_cooldown - delta)
		_sync_player_state_identity()


static func get_phase_min_army_size(match_elapsed_seconds: float) -> int:
	if match_elapsed_seconds >= PHASE_MID_SECONDS:
		return PHASE_LATE_MIN_ARMY
	if match_elapsed_seconds >= PHASE_EARLY_SECONDS:
		return PHASE_MID_MIN_ARMY
	return PHASE_EARLY_MIN_ARMY


static func get_main_army_group(tree: SceneTree) -> Array:
	purge_and_rebuild_main_army(tree)
	return _main_army_cache.duplicate()


static func _refresh_combat_units_cache_if_needed(tree: SceneTree) -> void:
	if tree == null:
		return

	var frame: int = Engine.get_process_frames()
	if frame == _combat_units_cache_frame:
		return

	_combat_units_cache_frame = frame
	_cached_offensive_wave_units_frame = -1
	var units: Array = []
	var seen_ids: Dictionary = {}

	for node: Variant in CombatTargetValidation.get_cached_group_nodes(tree, ENEMY_COMBAT_GROUP):
		if node == null or not is_instance_valid(node):
			continue
		if not is_living_combat_unit(node):
			continue
		if node is Worker:
			continue

		var unit_id: int = (node as Node).get_instance_id()
		if seen_ids.has(unit_id):
			continue

		seen_ids[unit_id] = true
		units.append(node)

	_main_army_cache = units


static func purge_and_rebuild_main_army(tree: SceneTree) -> void:
	_refresh_combat_units_cache_if_needed(tree)
	purge_stale_reinforcement_pool()
	purge_stale_creep_contest_cooldowns()


static func with_authorized_orders(callback: Callable) -> void:
	_orders_authorized = true
	_sync_player_state_identity()
	callback.call()
	_orders_authorized = false
	_sync_player_state_identity()


static func _combat_orders_allowed(mission: EnemyUnitMission.Mission) -> bool:
	if _orders_authorized or _emergency_defense_active or _allow_hostile_engagement:
		return true

	if is_attack_wave_active() and mission == EnemyUnitMission.Mission.CREEP:
		return false

	if is_defense_blocking_offense():
		if mission in [
			EnemyUnitMission.Mission.ATTACK,
			EnemyUnitMission.Mission.CREEP,
			EnemyUnitMission.Mission.ECONOMY,
			EnemyUnitMission.Mission.BUILD,
			EnemyUnitMission.Mission.IDLE,
		]:
			return false

	if _strategic_state == StrategicState.RETREATING:
		if mission in [
			EnemyUnitMission.Mission.ATTACK,
			EnemyUnitMission.Mission.CREEP,
		]:
			return false

	if _strategic_state == StrategicState.RECOVERING:
		if mission == EnemyUnitMission.Mission.ATTACK:
			return false

	if _strategic_state == StrategicState.CREEPING:
		if mission == EnemyUnitMission.Mission.ATTACK and not is_attack_wave_active():
			return false

	if _strategic_state in [
		StrategicState.PREPARING_ATTACK,
		StrategicState.ATTACKING,
	]:
		if mission == EnemyUnitMission.Mission.CREEP:
			return false

	match mission:
		EnemyUnitMission.Mission.RETREAT, EnemyUnitMission.Mission.RALLY, EnemyUnitMission.Mission.IDLE, EnemyUnitMission.Mission.SHOP:
			return true
		EnemyUnitMission.Mission.ATTACK:
			return _army_mode == ArmyMode.ATTACKING or _army_mode == ArmyMode.ASSEMBLING
		EnemyUnitMission.Mission.CREEP:
			return _army_mode == ArmyMode.CREEPING or _army_mode == ArmyMode.ASSEMBLING
		EnemyUnitMission.Mission.DEFEND:
			return (
				_army_mode == ArmyMode.DEFENDING
				or _army_mode == ArmyMode.INTERCEPTING
				or _army_mode == ArmyMode.ASSEMBLING
			)
		_:
			return false


static func set_debug_enabled(enabled: bool) -> void:
	EnemyArmyCommandTelemetry.set_debug_override(enabled)
	EnemyAIDebug.set_enabled(enabled)


static func _debug_combat(message: String) -> void:
	if DEBUG_COMBAT_AI or EnemyArmyCommandTelemetry.is_debug_override_enabled():
		print("[AI Combat] %s" % message)


static func debug_combat_log(message: String) -> void:
	_debug_combat(message)


static func _debug_state_change(from_mode: ArmyMode, to_mode: ArmyMode, reason: String = "") -> void:
	if from_mode == to_mode:
		return

	_debug_combat(
		"state %s -> %s%s"
		% [
			_army_mode_label(from_mode),
			_army_mode_label(to_mode),
			(" (%s)" % reason) if not reason.is_empty() else "",
		]
	)


static func _army_mode_label(mode: ArmyMode) -> String:
	match mode:
		ArmyMode.IDLE:
			return "IDLE"
		ArmyMode.OPENING:
			return "OPENING"
		ArmyMode.ASSEMBLING:
			return "ASSEMBLING"
		ArmyMode.CREEPING:
			return "CREEPING"
		ArmyMode.DEFENDING:
			return "DEFENDING"
		ArmyMode.INTERCEPTING:
			return "INTERCEPTING"
		ArmyMode.ATTACKING:
			return "ATTACKING"
		ArmyMode.RETREATING:
			return "RETREATING"
		ArmyMode.REGROUPING:
			return "REGROUPING"
		_:
			return "UNKNOWN"


static func get_unit_type_strength_weight(unit) -> float:
	return EnemyArmyForceMath.get_unit_type_strength_weight(unit)


static func estimate_combat_strength(units: Array) -> float:
	return EnemyArmyForceMath.estimate_combat_strength(units)


static func estimate_local_fight_balance(
	tree: SceneTree,
	position: Vector3,
	radius: float = LOCAL_FIGHT_RADIUS
) -> Dictionary:
	var ai_units: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue
		if horizontal_distance((unit as Node3D).global_position, position) <= radius:
			ai_units.append(unit)

	var player_units: Array = collect_player_military_near(tree, position, radius)
	var ai_strength: float = estimate_combat_strength(ai_units)
	var player_strength: float = estimate_combat_strength(player_units)

	return {
		"ai_strength": ai_strength,
		"player_strength": player_strength,
		"ratio": ai_strength / maxf(player_strength, 1.0),
		"ai_units": ai_units,
		"player_units": player_units,
	}


static func record_player_army_observation(tree: SceneTree, position: Vector3, radius: float) -> void:
	var player_units: Array = collect_player_military_near(tree, position, radius)
	if player_units.is_empty():
		return

	var strength: float = estimate_combat_strength(player_units)
	var hero_level: int = 0
	for unit: Variant in player_units:
		if unit is Hero:
			hero_level = maxi(hero_level, int((unit as Hero).level))

	_player_army_memory = {
		"strength": strength,
		"position": position,
		"hero_level": hero_level,
		"timestamp_msec": Time.get_ticks_msec(),
		"unit_count": player_units.size(),
	}
	_sync_player_state_identity()


static func get_effective_player_strength_at(tree: SceneTree, position: Vector3, radius: float) -> float:
	var visible: Array = collect_player_military_near(tree, position, radius)
	if not visible.is_empty():
		record_player_army_observation(tree, position, radius)
		return estimate_combat_strength(visible)

	var memory_strength: float = float(_player_army_memory.get("strength", 0.0))
	if memory_strength <= 0.0:
		return 0.0

	var memory_position: Vector3 = _player_army_memory.get("position", Vector3.ZERO)
	var age_seconds: float = float(
		Time.get_ticks_msec() - int(_player_army_memory.get("timestamp_msec", 0))
	) / 1000.0
	if age_seconds > PLAYER_ARMY_MEMORY_DECAY_SECONDS:
		return memory_strength * 0.5

	if horizontal_distance(memory_position, position) > radius * 2.5:
		return memory_strength * 0.7

	return memory_strength


static func begin_fight_tracking(units: Array, anchor_position: Vector3) -> void:
	_fight_start_strength = estimate_combat_strength(units)
	_fight_anchor_position = anchor_position
	_fight_start_msec = Time.get_ticks_msec()
	_sync_player_state_identity()


static func should_retreat_from_fight(tree: SceneTree) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_combat_eval_msec < int(COMBAT_EVAL_INTERVAL_SECONDS * 1000.0):
		return false
	_last_combat_eval_msec = now_msec

	if is_defense_blocking_offense():
		return false

	var anchor: Vector3 = _fight_anchor_position
	if anchor == Vector3.ZERO:
		anchor = compute_army_center(collect_living_combat_units(tree))

	var balance: Dictionary = estimate_local_fight_balance(tree, anchor)
	var ratio: float = float(balance.get("ratio", 1.0))
	var player_strength: float = float(balance.get("player_strength", 0.0))
	var ai_strength: float = float(balance.get("ai_strength", 0.0))

	if player_strength <= 0.0 or player_strength < ai_strength * 0.25:
		if ratio >= 1.0 and get_army_mode() == ArmyMode.ATTACKING:
			var army_center: Vector3 = compute_army_center(balance.get("ai_units", []))
			var chase_target: Vector3 = _active_wave_objective_position
			if chase_target == Vector3.ZERO:
				chase_target = army_center
			if should_stop_chase(tree, anchor, army_center, chase_target):
				_debug_combat("ending limited pursuit at chase boundary")
				return false
			_debug_combat("continuing limited pursuit while player retreats")
			return false
		if player_strength <= 0.0 and get_army_mode() in [
			ArmyMode.DEFENDING,
			ArmyMode.INTERCEPTING,
		]:
			return false

	if player_strength > 0.0 and ratio <= RETREAT_STRENGTH_RATIO:
		EnemyAIDebug.log_once("retreat", "Retreat: Army weaker than enemy")
		EnemyAIDebug.log_army_strength_decision(ai_strength, player_strength, "Retreat")
		_debug_combat("retreating: ratio %.2f" % ratio)
		return true

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and get_health_ratio(hero) < HERO_RETREAT_HP_RATIO:
		var hp_pct: int = int(round(get_health_ratio(hero) * 100.0))
		EnemyAIDebug.log_once("retreat", "Retreat: Hero HP %d%%" % hp_pct)
		EnemyAIDebug.log_army_strength_decision(ai_strength, player_strength, "Retreat")
		_debug_combat("retreating: hero low health")
		return true

	if _fight_start_strength > 0.0:
		var current_strength: float = estimate_combat_strength(balance.get("ai_units", []))
		if current_strength <= _fight_start_strength * (1.0 - EMERGENCY_RETREAT_ARMY_LOSS_RATIO):
			EnemyAIDebug.log_once("retreat", "Retreat: Army weaker than enemy")
			EnemyAIDebug.log_army_strength_decision(ai_strength, player_strength, "Retreat")
			_debug_combat("retreating: army lost %.0f%%" % (EMERGENCY_RETREAT_ARMY_LOSS_RATIO * 100.0))
			return true

	return false


static func should_stop_chase(
	tree: SceneTree,
	start_position: Vector3,
	army_center: Vector3,
	target_position: Vector3
) -> bool:
	if start_position == Vector3.ZERO:
		return false

	if horizontal_distance(army_center, start_position) > MAX_CHASE_DISTANCE:
		return true

	if (
		_fight_start_msec > 0
		and float(Time.get_ticks_msec() - _fight_start_msec) / 1000.0 > MAX_CHASE_DURATION_SECONDS
	):
		return true

	var non_hero: Array = collect_living_non_hero_combat_units(tree)
	if non_hero.size() >= 4:
		var grouped: Array = filter_units_near_rally(non_hero, army_center, ASSEMBLY_RADIUS * 2.0)
		if float(grouped.size()) / float(non_hero.size()) < 0.5:
			return true

	return horizontal_distance(army_center, target_position) > MAX_CHASE_DISTANCE * 1.25


static func get_retreat_destination(tree: SceneTree) -> Vector3:
	var rally: Vector3 = resolve_enemy_rally_position(tree)
	if rally != Vector3.ZERO:
		return rally

	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, ENEMY_COMBAT_GROUP):
		var node: Node = node_variant as Node
		if node is Barracks or node is Stable:
			if _is_living_building(node as Building):
				return (node as Node3D).global_position

	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		ENEMY_COMMAND_CENTER_GROUP
	):
		var node: Node = node_variant as Node
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			return (node as Node3D).global_position

	return Vector3.ZERO


static func initiate_group_retreat(tree: SceneTree, reason: String = "") -> bool:
	if is_attack_wave_active():
		notify_attack_wave_retreat_started(reason if not reason.is_empty() else "retreating")

	if not try_claim_army_mode(ArmyMode.RETREATING):
		return false

	var destination: Vector3 = get_retreat_destination(tree)
	if destination == Vector3.ZERO:
		release_army_mode(ArmyMode.RETREATING)
		return false

	cancel_offensive_orders(tree)
	var survivors: Array = collect_living_combat_units(tree)
	survivors = EnemyUnitMission.claim_units_for_mission(
		survivors,
		EnemyUnitMission.Mission.RETREAT,
		EnemyUnitMission.COMMITMENT_SECONDS
	)
	with_authorized_orders(func() -> void:
		command_retreat_to(survivors, destination)
	)

	_retreat_cooldown = RETREAT_COOLDOWN_SECONDS
	_fight_start_strength = 0.0
	EnemyUnitMission.set_main_army_mission(EnemyUnitMission.Mission.RETREAT, reason)
	request_strategic_state(StrategicState.RETREATING, reason)
	set_executable_mission(
		ExecutableMission.RETREAT,
		reason if not reason.is_empty() else "retreat",
		null,
		destination,
		"Rally",
		"move",
		survivors,
		false
	)
	return true


static func complete_retreat_to_regroup(tree: SceneTree) -> void:
	if get_army_mode() != ArmyMode.RETREATING:
		return

	var rally: Vector3 = get_retreat_destination(tree)
	var army: Array = collect_living_combat_units(tree)
	var assembled: int = filter_units_near_rally(army, rally, ASSEMBLY_RADIUS * 2.0).size()
	if army.size() > 0 and float(assembled) / float(army.size()) < 0.6:
		return

	release_army_mode(ArmyMode.RETREATING)
	if try_claim_army_mode(ArmyMode.REGROUPING):
		set_rebuilding_army(true)
		command_regroup_at_rally(tree, rally)
		EnemyUnitMission.set_main_army_mission(EnemyUnitMission.Mission.RALLY, "post-retreat")
		var recover_state: StrategicState = (
			StrategicState.ECONOMY
			if blocks_player_offense(tree)
			else StrategicState.RECOVERING
		)
		request_strategic_state(recover_state, "post-retreat")
		if _attack_wave_state == AttackWaveState.RETREATING:
			notify_attack_wave_retreat_complete(tree)


static func begin_assembly(
	tree: SceneTree,
	target_mode: ArmyMode,
	rally_position: Vector3,
	required_units: Array,
	hold_mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.RALLY
) -> bool:
	if rally_position == Vector3.ZERO:
		return false

	required_units = NodeSafety.clean_node_array(required_units)
	if required_units.is_empty():
		return false

	var previous_mode: ArmyMode = _army_mode
	if not try_claim_army_mode(ArmyMode.ASSEMBLING):
		return false

	_assembly_timer = 0.0
	_assembly_rally = (
		get_attack_wave_assembly_point()
		if is_attack_wave_active() and get_attack_wave_assembly_point() != Vector3.ZERO
		else rally_position
	)
	_assembly_required_count = maxi(
		1,
		int(ceil(float(required_units.size()) * ASSEMBLY_REQUIRED_PERCENT))
	)
	_sync_player_state_identity()
	_debug_state_change(previous_mode, ArmyMode.ASSEMBLING)

	## Keep creep/attack ownership during assemble — RALLY lets wave regroup steal the squad.
	var assemble_mission: EnemyUnitMission.Mission = hold_mission
	if target_mode == ArmyMode.CREEPING:
		assemble_mission = EnemyUnitMission.Mission.CREEP
	elif target_mode == ArmyMode.ATTACKING:
		assemble_mission = EnemyUnitMission.Mission.ATTACK

	with_authorized_orders(func() -> void:
		command_hold_at_rally(required_units, _assembly_rally, assemble_mission)
	)

	return true


static func is_assembly_ready(tree: SceneTree, delta: float) -> bool:
	if get_army_mode() != ArmyMode.ASSEMBLING:
		return false

	_assembly_timer += delta
	_sync_player_state_identity()
	var army: Array = collect_living_combat_units(tree)
	var assembled: Array = filter_units_near_rally(army, _assembly_rally, ASSEMBLY_RADIUS)
	var assembled_count: int = assembled.size()
	var required_count: int = _assembly_required_count

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and is_attack_wave_controlling_hero():
		var hero_near: bool = (
			horizontal_distance(hero.global_position, _assembly_rally) <= ATTACK_WAVE_HERO_STAGING_DISTANCE
		)
		if not hero_near:
			if _assembly_timer < ATTACK_WAVE_HERO_WAIT_TIMEOUT_SECONDS:
				debug_combat_log(
					"waiting for hero: %d/%d units assembled"
					% [assembled_count, army.size()]
				)
				return false
	elif hero != null:
		var hero_near: bool = (
			horizontal_distance(hero.global_position, _assembly_rally) <= ASSEMBLY_RADIUS
		)
		if not hero_near:
			if _assembly_timer < ASSEMBLY_MAX_WAIT_SECONDS:
				debug_combat_log(
					"waiting for hero: %d/%d units assembled"
					% [assembled_count, army.size()]
				)
				return false

	if assembled_count >= required_count:
		return true

	if _assembly_timer >= ASSEMBLY_MAX_WAIT_SECONDS:
		var adjusted_required: int = maxi(1, required_count - 1)
		return assembled_count >= adjusted_required

	return false


static func finish_assembly(target_mode: ArmyMode) -> void:
	if get_army_mode() != ArmyMode.ASSEMBLING:
		return

	release_army_mode(ArmyMode.ASSEMBLING)
	if target_mode == ArmyMode.ATTACKING:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and not can_launch_player_attack(tree):
			EnemyAIDebug.log_once(
				"player_attack_blocked",
				"Player attack blocked: %s" % get_player_offense_block_reason(tree)
			)
			try_claim_army_mode(ArmyMode.REGROUPING)
			return
	try_claim_army_mode(target_mode)


static func is_regroup_ready(tree: SceneTree, match_elapsed_seconds: float) -> bool:
	if is_retreat_on_cooldown():
		return false

	var min_army: int = get_phase_min_army_size(match_elapsed_seconds)
	var rally: Vector3 = resolve_enemy_rally_position(tree)
	if rally == Vector3.ZERO:
		return false

	var non_hero: Array = collect_living_non_hero_combat_units(tree)
	if non_hero.size() < min_army:
		return false

	var regrouped: Array = filter_units_near_rally(non_hero, rally, ASSEMBLY_RADIUS)
	if float(regrouped.size()) / float(non_hero.size()) < ASSEMBLY_REQUIRED_PERCENT:
		return false

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and not is_hero_healthy_enough_for_wave(hero):
		return false

	if hero != null:
		var army_center: Vector3 = compute_army_center(regrouped)
		if (
			army_center != Vector3.ZERO
			and horizontal_distance(hero.global_position, army_center) > HERO_MAX_DISTANCE_FROM_ARMY
		):
			return false

	return true


static func build_coordinated_combat_group(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero: int,
	require_hero: bool = true,
	hero_min_hp_ratio: float = HERO_WAVE_JOIN_HP_RATIO,
	hero_join_min_non_hero: int = ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS
) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var regrouped_non_hero: Array = filter_units_near_rally(
		non_hero_units,
		rally_position,
		ASSEMBLY_RADIUS * 2.5
	)
	var can_launch: bool = regrouped_non_hero.size() >= min_non_hero
	var group_units: Array = regrouped_non_hero.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		var army_center: Vector3 = compute_army_center(regrouped_non_hero)
		var hero_ready: bool = (
			hero != null
			and regrouped_non_hero.size() >= hero_join_min_non_hero
			and army_center != Vector3.ZERO
			and is_living_combat_unit(hero)
		)
		if require_hero and hero == null:
			can_launch = false
		elif hero_ready:
			if (
				get_health_ratio(hero) >= hero_min_hp_ratio
				and horizontal_distance(hero.global_position, army_center)
				<= HERO_MAX_DISTANCE_FROM_ARMY
			):
				group_units.append(hero)
			elif require_hero:
				can_launch = false
		elif require_hero:
			can_launch = false

	var hero_included: bool = false
	for unit: Variant in group_units:
		if unit is Hero:
			hero_included = true
			break

	return {
		"units": group_units,
		"can_launch": can_launch,
		"non_hero_count": regrouped_non_hero.size(),
		"total_non_hero_count": non_hero_units.size(),
		"hero_included": hero_included,
	}


static func evaluate_strength_gate(
	ai_strength: float,
	player_strength: float,
	attack_style: StringName = &"normal"
) -> Dictionary:
	if player_strength <= 0.0:
		return {"allowed": true, "reason": &"no_visible_threat"}

	var required_ratio: float = ATTACK_NORMAL_STRENGTH_RATIO
	if attack_style == &"aggressive":
		required_ratio = ATTACK_AGGRESSIVE_STRENGTH_RATIO
	elif attack_style == &"defend":
		required_ratio = DEFEND_FIGHT_STRENGTH_RATIO

	var ratio: float = ai_strength / player_strength
	return {
		"allowed": ratio >= required_ratio,
		"ratio": ratio,
		"required_ratio": required_ratio,
		"reason": &"strength_ok" if ratio >= required_ratio else &"outpowered",
	}


static func issue_group_combat_move(
	tree: SceneTree,
	units: Array,
	destination: Vector3,
	mission: EnemyUnitMission.Mission,
	mode: ArmyMode,
	allow_attack_override_creep: bool = false
) -> bool:
	units = NodeSafety.clean_node_array(units)
	units = filter_units_for_field_combat(units, mission)
	if units.is_empty() or destination == Vector3.ZERO:
		return false

	if is_retreat_on_cooldown() and mission != EnemyUnitMission.Mission.DEFEND:
		_debug_combat("order blocked: retreat cooldown")
		return false

	## V2: sync legacy authority BEFORE creep/attack gates so stale ATTACKING
	## strategic state cannot permanently block CREEP execution.
	if MilitaryAIConfig.is_v2_enabled():
		var strategic: StrategicState = StrategicState.ECONOMY
		match mission:
			EnemyUnitMission.Mission.CREEP:
				strategic = StrategicState.CREEPING
			EnemyUnitMission.Mission.ATTACK:
				strategic = StrategicState.ATTACKING
			EnemyUnitMission.Mission.DEFEND:
				strategic = (
					StrategicState.EMERGENCY_DEFENDING
					if _emergency_defense_active
					else StrategicState.DEFENDING
				)
			EnemyUnitMission.Mission.RETREAT:
				strategic = StrategicState.RETREATING
			_:
				strategic = _strategic_state
		if mission in [
			EnemyUnitMission.Mission.CREEP,
			EnemyUnitMission.Mission.ATTACK,
			EnemyUnitMission.Mission.DEFEND,
		]:
			prepare_v2_execution(mode, strategic, "v2 group combat move")

	if mission == EnemyUnitMission.Mission.CREEP and not allows_creep_orders():
		_debug_combat("order blocked: strategic state forbids creep")
		return false

	if mission == EnemyUnitMission.Mission.ATTACK:
		if not _allow_hostile_engagement and not MilitaryAIConfig.is_v2_enabled():
			if not allows_offensive_orders():
				_debug_combat("order blocked: strategic state forbids attack")
				return false
			if not can_launch_player_attack(tree):
				EnemyAIDebug.log_once(
					"player_attack_blocked",
					"Player attack blocked: %s" % get_player_offense_block_reason(tree)
				)
				return false
			# Never let a thin wave steal the army from CREEPING during early phases.
			if get_army_mode() == ArmyMode.CREEPING and not allow_attack_override_creep:
				EnemyAIDebug.log_once(
					"player_attack_blocked",
					"Player attack blocked: %s" % get_player_offense_block_reason(tree)
				)
				return false
		elif not _allow_hostile_engagement and MilitaryAIConfig.is_v2_enabled():
			## Still respect active retreat cooldown / emergency defend via other gates.
			if _strategic_state == StrategicState.EMERGENCY_DEFENDING:
				_debug_combat("order blocked: emergency defending")
				return false
			if _strategic_state == StrategicState.RETREATING:
				_debug_combat("order blocked: retreating")
				return false

	if not try_claim_army_mode(mode, allow_attack_override_creep):
		return false

	if mission == EnemyUnitMission.Mission.ATTACK:
		request_strategic_state(StrategicState.ATTACKING, "group attack move")
		if _exec_mission not in [
			ExecutableMission.ATTACK_PLAYER,
			ExecutableMission.LETHAL_PUSH,
		]:
			set_executable_mission(
				ExecutableMission.ATTACK_PLAYER,
				"group attack move",
				null,
				destination,
				"AttackObjective",
				"attack-move",
				units,
				false
			)
	elif mission == EnemyUnitMission.Mission.CREEP:
		request_strategic_state(StrategicState.CREEPING, "group creep move")
	elif mission == EnemyUnitMission.Mission.DEFEND:
		var defense_state: StrategicState = (
			StrategicState.EMERGENCY_DEFENDING
			if _emergency_defense_active
			else StrategicState.DEFENDING
		)
		request_strategic_state(defense_state, "group defense move")
		if not _emergency_defense_active:
			set_executable_mission(
				ExecutableMission.DEFEND,
				"group defense move",
				null,
				destination,
				"DefendPoint",
				"attack-move",
				units,
				false
			)

	begin_fight_tracking(units, compute_army_center(units))
	var move_ok: Array = [false]
	with_authorized_orders(func() -> void:
		move_ok[0] = command_attack_move(units, destination, mission)
	)
	if not VariantUtils.to_bool(move_ok[0]):
		return false
	note_mission_order("attack-move", destination)
	return true


static func get_last_squad_route_failure_reason() -> String:
	return _last_squad_route_failure_reason


static func is_rebuilding_army() -> bool:
	return _is_rebuilding_army


static func is_finishing_mode_active() -> bool:
	return _finishing_mode_active


static func is_aggression_mode_active() -> bool:
	return EnemyAggression.is_aggression_mode_active()


static func is_emergency_defense_active() -> bool:
	return _emergency_defense_active


static func get_emergency_defense_reason() -> StringName:
	## Read SoT directly so callers do not depend on the static property getter chain.
	return _rt().emergency_reason


static func get_emergency_defense_objective() -> Vector3:
	return _rt().emergency_threat_position


static func activate_emergency_defense(threat: Dictionary) -> void:
	var reason: StringName = threat.get("reason", &"")
	var intercept_position: Vector3 = threat.get("intercept_position", Vector3.ZERO)

	if _emergency_defense_active:
		_emergency_reason = reason
		_emergency_threat_position = intercept_position
		_sync_player_state_identity()
		set_executable_mission(
			ExecutableMission.EMERGENCY_DEFEND,
			String(reason),
			null,
			intercept_position,
			"EmergencyThreat",
			"attack-move",
			[],
			false
		)
		return

	_emergency_defense_active = true
	_emergency_reason = reason
	_emergency_threat_position = intercept_position
	_sync_player_state_identity()
	EnemyUnitMission.set_main_army_mission(
		EnemyUnitMission.Mission.DEFEND,
		"emergency defense"
	)
	request_strategic_state(StrategicState.EMERGENCY_DEFENDING, String(reason))
	set_executable_mission(
		ExecutableMission.EMERGENCY_DEFEND,
		String(reason),
		null,
		intercept_position,
		"EmergencyThreat",
		"attack-move",
		[],
		false
	)
	EnemyAIDebug.log_event("Emergency Defense (%s)" % String(reason))


static func update_emergency_defense_threat(threat: Dictionary) -> void:
	if not _emergency_defense_active:
		return

	_emergency_reason = threat.get("reason", &"")
	_emergency_threat_position = threat.get("intercept_position", Vector3.ZERO)
	_sync_player_state_identity()


static func deactivate_emergency_defense() -> void:
	if not _emergency_defense_active:
		return

	_emergency_defense_active = false
	_emergency_threat_position = Vector3.ZERO
	_emergency_reason = &""
	## Drop cached threat so the next evaluation cannot republish a stale DEFEND.
	_emergency_threat_cache.clear()
	_emergency_threat_cache_msec = 0
	_defense_threat_cache.clear()
	_defense_threat_cache_msec = 0
	_sync_player_state_identity()
	EnemyUnitMission.set_main_army_mission(
		EnemyUnitMission.Mission.RALLY,
		"emergency ended"
	)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var recover_state: StrategicState = (
		StrategicState.ECONOMY
		if tree != null and blocks_player_offense(tree)
		else StrategicState.RECOVERING
	)
	## V2: force-clear the strategic label immediately. Pending request_strategic_state
	## can be rejected by MIN_STATE_DURATION, leaving EMERGENCY_DEFENDING stuck.
	if MilitaryAIConfig.is_v2_enabled():
		force_set_strategic_state_for_v2(recover_state, "emergency ended")
	else:
		request_strategic_state(recover_state, "emergency ended")
	EnemyAIDebug.log_event("Threat cleared, regrouping")


static func update_finishing_mode(tree: SceneTree, delta: float) -> void:
	EnemyAggression.update(tree, delta)

	if _finishing_mode_exit_cooldown > 0.0:
		_finishing_mode_exit_cooldown = maxf(0.0, _finishing_mode_exit_cooldown - delta)

	_finishing_mode_eval_timer += delta
	if _finishing_mode_eval_timer < FINISHING_MODE_EVAL_INTERVAL:
		return

	_finishing_mode_eval_timer = 0.0

	if _finishing_mode_active:
		var exit_eval: Dictionary = _evaluate_finishing_exit(tree)
		if exit_eval.get("should_exit", false) or not can_launch_player_attack(tree):
			_set_finishing_mode(false, String(exit_eval.get("reason", "early_phase")))
		return

	if _finishing_mode_exit_cooldown > 0.0:
		return

	if not can_launch_player_attack(tree):
		return

	var enter_eval: Dictionary = _evaluate_finishing_activation(tree)
	if enter_eval.get("should_enter", false):
		_set_finishing_mode(true, String(enter_eval.get("reason", "unknown")))
		return

	## Very high lethal opportunity escalates into finishing (end the game).
	if (
		EnemyAggression.is_aggression_mode_active()
		and EnemyAggression.get_confidence() == EnemyAggression.Confidence.VERY_HIGH
		and EnemyAggression.get_lethal_score() >= EnemyAggression.FINISHING_LETHAL_THRESHOLD
	):
		_set_finishing_mode(true, "lethal_opportunity")


static func set_rebuilding_army(rebuilding: bool) -> void:
	_is_rebuilding_army = rebuilding
	_sync_player_state_identity()


static func get_attack_wave_state() -> AttackWaveState:
	return _attack_wave_state


static func is_attack_wave_active() -> bool:
	return _attack_wave_state not in [AttackWaveState.NONE, AttackWaveState.RECOVERING]


static func is_attack_wave_controlling_hero() -> bool:
	return _attack_wave_state in [
		AttackWaveState.PREPARING,
		AttackWaveState.GATHERING,
		AttackWaveState.WAITING_FOR_HERO,
		AttackWaveState.REGROUPING,
		AttackWaveState.ADVANCING,
		AttackWaveState.ENGAGING,
		AttackWaveState.RETREATING,
	]


static func consume_attack_wave_advance_request() -> Dictionary:
	if not _attack_wave_ready_to_advance:
		return {}

	_attack_wave_ready_to_advance = false
	return {
		"units": _sanitize_attack_wave_units(_attack_wave_units),
		"destination": _attack_wave_target_position,
		"staging": _attack_wave_staging_point,
	}


static func confirm_attack_wave_advance_started() -> void:
	if _attack_wave_state in [AttackWaveState.REGROUPING, AttackWaveState.ADVANCING]:
		_transition_attack_wave_state(AttackWaveState.ADVANCING, "advance confirmed")


static func confirm_attack_wave_engaging() -> void:
	if _attack_wave_state == AttackWaveState.ADVANCING:
		_transition_attack_wave_state(AttackWaveState.ENGAGING, "contact with objective")


static func try_begin_attack_wave_preparation(
	tree: SceneTree,
	wave_units: Array,
	attack_destination: Vector3,
	min_non_hero_units: int,
	match_elapsed_seconds: float
) -> bool:
	if is_attack_wave_active():
		return false

	if is_retreat_on_cooldown():
		return false

	if not can_launch_player_attack(tree):
		EnemyAIDebug.log_once(
			"player_attack_blocked",
			"Player attack blocked: %s" % get_player_offense_block_reason(tree)
		)
		return false

	wave_units = _sanitize_attack_wave_units(wave_units)
	if wave_units.is_empty() or attack_destination == Vector3.ZERO:
		return false

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	var attack_commitment: Dictionary = can_commit_attack_wave(
		tree,
		wave_units,
		rally_position,
		min_non_hero_units,
		match_elapsed_seconds
	)
	if not attack_commitment.get("can_commit", false):
		return false

	var objective: Dictionary = resolve_attack_objective(tree, attack_destination)
	var target_position: Vector3 = objective.get("position", attack_destination)
	var target_node_ref: Variant = objective.get("node")
	var target_node: Node3D = null
	if NodeSafety.is_alive_node(target_node_ref) and target_node_ref is Node3D:
		target_node = target_node_ref as Node3D
	if target_position == Vector3.ZERO:
		return false

	_attack_wave_units = wave_units.duplicate()
	_attack_wave_min_non_hero_units = min_non_hero_units
	_attack_wave_target_position = target_position
	_attack_wave_target_node = NodeSafety.safe_node(target_node) as Node3D
	_attack_wave_staging_point = resolve_attack_staging_point(tree, rally_position, target_position)
	_attack_wave_gather_pull_timer = 0.0
	_attack_wave_hero_wait_timer = 0.0
	_attack_wave_regroup_timer = 0.0
	_attack_wave_hero_unreachable_retries = 0
	_attack_wave_ready_to_advance = false
	_commit_attack_wave_target(target_node, target_position)

	_transition_attack_wave_state(AttackWaveState.PREPARING, "preparing wave")
	request_strategic_state(StrategicState.PREPARING_ATTACK, "attack wave preparation")
	_suspend_units_for_attack_wave(tree)
	return true


static func tick_attack_wave_state(
	tree: SceneTree,
	delta: float,
	match_elapsed_seconds: float
) -> void:
	_apply_pending_attack_wave_transition()
	if _attack_wave_state == AttackWaveState.NONE:
		return

	# Kill any stale/timer wave that started while strategic phases own the army.
	if (
		not can_launch_player_attack(tree)
		and _attack_wave_state not in [
			AttackWaveState.NONE,
			AttackWaveState.RETREATING,
			AttackWaveState.RECOVERING,
		]
	):
		abort_attack_wave(tree, get_player_offense_block_reason(tree))
		return

	_attack_wave_units = _sanitize_attack_wave_units(_attack_wave_units)
	_attack_wave_command_refresh_timer += delta

	match _attack_wave_state:
		AttackWaveState.PREPARING:
			_tick_attack_wave_preparing(tree, match_elapsed_seconds)
		AttackWaveState.GATHERING:
			_tick_attack_wave_gathering(tree, delta, match_elapsed_seconds)
		AttackWaveState.WAITING_FOR_HERO:
			_tick_attack_wave_waiting_for_hero(tree, delta)
		AttackWaveState.REGROUPING:
			_tick_attack_wave_regrouping(tree, delta, match_elapsed_seconds)
		AttackWaveState.ADVANCING:
			_tick_attack_wave_advancing(tree, delta)
		AttackWaveState.ENGAGING:
			_tick_attack_wave_engaging(tree, delta)
		AttackWaveState.RETREATING:
			_tick_attack_wave_retreating(tree, delta)
		AttackWaveState.RECOVERING:
			_tick_attack_wave_recovering(tree, delta)


static func abort_attack_wave(tree: SceneTree, reason: String) -> void:
	if _attack_wave_state == AttackWaveState.NONE:
		return

	EnemyAIDebug.log_event("Attack aborted: %s" % reason)
	_attack_wave_ready_to_advance = false
	_clear_attack_wave_unit_missions()
	clear_offensive_wave_tracking()
	_transition_attack_wave_state(AttackWaveState.RECOVERING, reason)
	set_rebuilding_army(true)
	_attack_wave_recovery_timer = 0.0
	EnemyUnitMission.set_main_army_mission(EnemyUnitMission.Mission.RALLY, "attack aborted: %s" % reason)

	if tree != null:
		cancel_offensive_orders(tree)
		if get_army_mode() == ArmyMode.ATTACKING:
			release_army_mode(ArmyMode.ATTACKING)
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		if rally_position != Vector3.ZERO and try_claim_army_mode(ArmyMode.REGROUPING):
			command_regroup_at_rally(tree, rally_position)
		if blocks_player_offense(tree):
			request_strategic_state(StrategicState.ECONOMY, "attack aborted early phase")
		else:
			request_strategic_state(StrategicState.RECOVERING, "attack aborted")


static func notify_attack_wave_retreat_started(reason: String = "") -> void:
	if not is_attack_wave_active():
		return

	_transition_attack_wave_state(AttackWaveState.RETREATING, reason if not reason.is_empty() else "retreating")
	_attack_wave_ready_to_advance = false


static func notify_attack_wave_retreat_complete(tree: SceneTree) -> void:
	if _attack_wave_state != AttackWaveState.RETREATING:
		return

	_transition_attack_wave_state(AttackWaveState.RECOVERING, "retreat complete")
	set_rebuilding_army(true)
	_attack_wave_recovery_timer = 0.0
	_clear_attack_wave_unit_missions()
	clear_offensive_wave_tracking()
	EnemyUnitMission.set_main_army_mission(EnemyUnitMission.Mission.RALLY, "post-retreat recovery")


static func resolve_attack_staging_point(
	tree: SceneTree,
	base_position: Vector3,
	target_position: Vector3
) -> Vector3:
	if base_position == Vector3.ZERO:
		return Vector3.ZERO

	var direction: Vector3 = target_position - base_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3(1.0, 0.0, 0.0)
	else:
		direction = direction.normalized()

	return base_position + direction * ATTACK_WAVE_STAGING_OFFSET.length()


static func get_attack_wave_assembly_point() -> Vector3:
	if _attack_wave_staging_point != Vector3.ZERO:
		return _attack_wave_staging_point

	return _assembly_rally


static func _transition_attack_wave_state(new_state: AttackWaveState, reason: String = "") -> void:
	if _attack_wave_state == new_state:
		return

	_attack_wave_pending_transition = new_state
	_attack_wave_pending_transition_reason = reason


static func _apply_pending_attack_wave_transition() -> void:
	if _attack_wave_pending_transition == AttackWaveState.NONE:
		return
	if _attack_wave_pending_transition == _attack_wave_state:
		_attack_wave_pending_transition = AttackWaveState.NONE
		_attack_wave_pending_transition_reason = ""
		return

	var previous_state: AttackWaveState = _attack_wave_state
	var new_state: AttackWaveState = _attack_wave_pending_transition
	var reason: String = _attack_wave_pending_transition_reason
	_attack_wave_state = new_state
	_attack_wave_state_msec = Time.get_ticks_msec()
	_attack_wave_pending_transition = AttackWaveState.NONE
	_attack_wave_pending_transition_reason = ""
	_attack_wave_command_refresh_timer = 0.0

	if reason.is_empty():
		EnemyAIDebug.log_event("Attack: %s" % _attack_wave_state_label(new_state))
	else:
		EnemyAIDebug.log_event(
			"Attack: %s (%s)" % [_attack_wave_state_label(new_state), reason]
		)

	if previous_state != new_state and new_state == AttackWaveState.GATHERING:
		EnemyAIDebug.log_event("Attack: gathering %d units" % _attack_wave_units.size())


static func _attack_wave_state_label(state: AttackWaveState) -> String:
	match state:
		AttackWaveState.PREPARING:
			return "preparing wave"
		AttackWaveState.GATHERING:
			return "gathering"
		AttackWaveState.WAITING_FOR_HERO:
			return "waiting for hero"
		AttackWaveState.REGROUPING:
			return "regrouping stragglers"
		AttackWaveState.ADVANCING:
			return "advancing toward objective"
		AttackWaveState.ENGAGING:
			return "engaging"
		AttackWaveState.RETREATING:
			return "retreating"
		AttackWaveState.RECOVERING:
			return "recovering"
		_:
			return "idle"


static func _is_valid_attack_unit(unit) -> bool:
	if not is_instance_valid(unit):
		return false

	if not unit is Node:
		return false

	return (unit as Node).is_inside_tree()


static func _sanitize_attack_wave_units(units: Array) -> Array:
	var cleaned: Array = NodeSafety.clean_node_array(units)
	var valid: Array = []
	for unit: Variant in cleaned:
		if not _is_valid_attack_unit(unit):
			continue

		if not is_combat_unit(unit):
			continue

		valid.append(unit)

	return valid


static func _suspend_units_for_attack_wave(tree: SceneTree) -> void:
	var units: Array = _sanitize_attack_wave_units(_attack_wave_units)
	if units.is_empty():
		return

	cancel_offensive_orders(tree)
	EnemyUnitMission.assign_missions_to_units(
		units,
		EnemyUnitMission.Mission.ATTACK,
		ATTACK_WAVE_MISSION_LOCK_SECONDS
	)

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and not units.has(hero) and is_living_combat_unit(hero):
		_suspend_hero_for_attack_wave(hero)


static func _suspend_hero_for_attack_wave(hero) -> void:
	if not NodeSafety.is_alive_node(hero):
		return

	_cancel_unit_offensive_orders(hero)
	EnemyUnitMission.try_set_mission(
		hero,
		EnemyUnitMission.Mission.ATTACK,
		ATTACK_WAVE_MISSION_LOCK_SECONDS
	)
	if not _attack_wave_units.has(hero):
		_attack_wave_units.append(hero)


static func _clear_attack_wave_unit_missions() -> void:
	for unit: Variant in _attack_wave_units:
		if not _is_valid_attack_unit(unit):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit)
		if mission == EnemyUnitMission.Mission.ATTACK:
			EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.RALLY, 0.0)


static func _commit_attack_wave_target(target_node: Node3D, target_position: Vector3) -> void:
	_attack_wave_target_node = NodeSafety.safe_node(target_node) as Node3D
	_attack_wave_target_position = target_position
	_attack_wave_target_committed_until_msec = (
		Time.get_ticks_msec() + int(ATTACK_WAVE_TARGET_COMMITMENT_SECONDS * 1000.0)
	)
	set_attack_objective(_attack_wave_target_node, _attack_wave_target_position)


static func _should_refresh_attack_wave_orders() -> bool:
	return _attack_wave_command_refresh_timer >= ATTACK_WAVE_COMMAND_REFRESH_SECONDS


static func _issue_attack_wave_hold_at_staging(units: Array) -> void:
	if _attack_wave_staging_point == Vector3.ZERO:
		return

	if not _should_refresh_attack_wave_orders():
		return

	with_authorized_orders(func() -> void:
		command_hold_at_rally(
			_sanitize_attack_wave_units(units),
			_attack_wave_staging_point,
			EnemyUnitMission.Mission.ATTACK
		)
	)
	_attack_wave_command_refresh_timer = 0.0


static func _issue_hero_to_staging(hero) -> void:
	if not NodeSafety.is_alive_node(hero) or _attack_wave_staging_point == Vector3.ZERO:
		return

	if not _should_refresh_attack_wave_orders():
		if not EnemyUnitMission.should_reissue_move_order(
			hero,
			_attack_wave_staging_point,
			EnemyUnitMission.Mission.ATTACK
		):
			return

	with_authorized_orders(func() -> void:
		_cancel_unit_offensive_orders(hero)
		EnemyUnitMission.try_set_mission(
			hero,
			EnemyUnitMission.Mission.ATTACK,
			ATTACK_WAVE_MISSION_LOCK_SECONDS
		)
		_issue_hold_at_rally(hero, _attack_wave_staging_point)
	)
	_attack_wave_command_refresh_timer = 0.0


static func _count_wave_units_near_staging(units: Array) -> Dictionary:
	units = _sanitize_attack_wave_units(units)
	var staging: Vector3 = _attack_wave_staging_point
	var gathered: Array = filter_units_near_rally(units, staging, ASSEMBLY_RADIUS * 1.5)
	var non_hero_gathered: int = 0
	var non_hero_total: int = 0
	for unit: Variant in units:
		if not _is_valid_attack_unit(unit):
			continue

		if is_non_hero_combat_unit(unit):
			non_hero_total += 1

	for unit: Variant in gathered:
		if not _is_valid_attack_unit(unit):
			continue

		if is_non_hero_combat_unit(unit):
			non_hero_gathered += 1

	return {
		"gathered_count": gathered.size(),
		"non_hero_gathered": non_hero_gathered,
		"non_hero_total": non_hero_total,
		"gathered_units": gathered,
	}


static func _is_hero_at_staging(hero) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	return (
		horizontal_distance(hero.global_position, _attack_wave_staging_point)
		<= ATTACK_WAVE_HERO_STAGING_DISTANCE
	)


static func _can_attack_without_hero(tree: SceneTree) -> bool:
	var non_hero: Array = []
	for unit: Variant in _attack_wave_units:
		if not _is_valid_attack_unit(unit):
			continue

		if is_non_hero_combat_unit(unit):
			non_hero.append(unit)

	return estimate_military_power(non_hero) >= ATTACK_WAVE_HERO_WITHOUT_ARMY_POWER


static func _tick_attack_wave_preparing(tree: SceneTree, match_elapsed_seconds: float) -> void:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		abort_attack_wave(tree, "no rally position")
		return

	if should_recall_offensive_for_defense(tree):
		abort_attack_wave(tree, "base defense override")
		return

	_attack_wave_units = _sanitize_attack_wave_units(_attack_wave_units)
	if _attack_wave_units.is_empty():
		abort_attack_wave(tree, "no valid units")
		return

	var commitment: Dictionary = can_commit_attack_wave(
		tree,
		_attack_wave_units,
		rally_position,
		_attack_wave_min_non_hero_units,
		match_elapsed_seconds
	)
	if not commitment.get("can_commit", false):
		abort_attack_wave(tree, "requirements not met")
		return

	if try_claim_army_mode(ArmyMode.REGROUPING):
		pass

	_suspend_units_for_attack_wave(tree)
	_transition_attack_wave_state(AttackWaveState.GATHERING, "gathering at staging")


static func _tick_attack_wave_gathering(
	tree: SceneTree,
	delta: float,
	match_elapsed_seconds: float
) -> void:
	if should_recall_offensive_for_defense(tree):
		abort_attack_wave(tree, "base defense override")
		return

	_attack_wave_gather_pull_timer += delta
	_attack_wave_units = _sanitize_attack_wave_units(_attack_wave_units)

	if _attack_wave_gather_pull_timer >= 1.0:
		_attack_wave_gather_pull_timer = 0.0
		pull_straggler_units_to_rally(tree, _attack_wave_staging_point, WAVE_REGROUP_MAX_DISTANCE)
		pull_reinforcement_units_to_rally(tree, _attack_wave_staging_point)

	var refreshed_plan: Dictionary = build_regrouped_attack_wave_units(
		tree,
		_attack_wave_staging_point,
		_attack_wave_min_non_hero_units
	)
	if refreshed_plan.get("can_launch", false):
		_attack_wave_units = _sanitize_attack_wave_units(refreshed_plan.get("units", _attack_wave_units))

	_issue_attack_wave_hold_at_staging(_attack_wave_units)

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null:
		_suspend_hero_for_attack_wave(hero)
		_issue_hero_to_staging(hero)

	var counts: Dictionary = _count_wave_units_near_staging(_attack_wave_units)
	var required_non_hero: int = maxi(
		1,
		int(ceil(float(counts.get("non_hero_total", 0)) * ATTACK_WAVE_GATHER_PERCENT))
	)
	var gather_ready: bool = (
		int(counts.get("non_hero_gathered", 0)) >= required_non_hero
		and int(counts.get("non_hero_gathered", 0)) >= _attack_wave_min_non_hero_units
	)
	var state_elapsed_seconds: float = float(
		Time.get_ticks_msec() - _attack_wave_state_msec
	) / 1000.0
	var gather_timeout: bool = state_elapsed_seconds >= WAVE_REINFORCEMENT_WAIT_SECONDS

	if not gather_ready and not gather_timeout:
		return

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var commitment: Dictionary = can_commit_attack_wave(
		tree,
		_attack_wave_units,
		rally_position,
		_attack_wave_min_non_hero_units,
		match_elapsed_seconds
	)
	if not commitment.get("can_commit", false):
		abort_attack_wave(tree, "force too weak after gather")
		return

	if hero != null and not _is_hero_at_staging(hero):
		_transition_attack_wave_state(AttackWaveState.WAITING_FOR_HERO, "hero not at staging")
		return

	_transition_attack_wave_state(AttackWaveState.REGROUPING, "army gathered")


static func _tick_attack_wave_waiting_for_hero(tree: SceneTree, delta: float) -> void:
	if should_recall_offensive_for_defense(tree):
		abort_attack_wave(tree, "base defense override")
		return

	_attack_wave_hero_wait_timer += delta
	_issue_attack_wave_hold_at_staging(_attack_wave_units)

	var hero: Hero = find_living_enemy_hero(tree)
	if hero == null:
		if _can_attack_without_hero(tree):
			_transition_attack_wave_state(AttackWaveState.REGROUPING, "hero dead, army sufficient")
		else:
			abort_attack_wave(tree, "hero dead and army too weak")
		return

	_suspend_hero_for_attack_wave(hero)
	_issue_hero_to_staging(hero)

	if _is_hero_at_staging(hero):
		EnemyAIDebug.log_event("Attack: hero joined wave")
		_transition_attack_wave_state(AttackWaveState.REGROUPING, "hero joined wave")
		return

	if _attack_wave_hero_wait_timer < ATTACK_WAVE_HERO_WAIT_TIMEOUT_SECONDS:
		return

	if _attack_wave_hero_unreachable_retries < 1:
		_attack_wave_hero_unreachable_retries += 1
		_attack_wave_hero_wait_timer = 0.0
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		_attack_wave_staging_point = resolve_attack_staging_point(
			tree,
			rally_position,
			_attack_wave_target_position
		)
		cancel_offensive_orders(tree)
		_issue_hero_to_staging(hero)
		_issue_attack_wave_hold_at_staging(_attack_wave_units)
		return

	abort_attack_wave(tree, "hero was unreachable")


static func _tick_attack_wave_regrouping(
	tree: SceneTree,
	delta: float,
	_match_elapsed_seconds: float
) -> void:
	if _attack_wave_ready_to_advance:
		return

	if should_recall_offensive_for_defense(tree):
		abort_attack_wave(tree, "base defense override")
		return

	_attack_wave_regroup_timer += delta
	var regroup_center: Vector3 = _attack_wave_staging_point
	var army_center: Vector3 = compute_army_center(_attack_wave_units)
	if army_center != Vector3.ZERO and get_army_mode() in [ArmyMode.ATTACKING, ArmyMode.CREEPING]:
		regroup_center = army_center

	_issue_attack_wave_hold_at_staging(_attack_wave_units)
	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null:
		_suspend_hero_for_attack_wave(hero)
		if not _is_hero_at_staging(hero) and regroup_center == _attack_wave_staging_point:
			_issue_hero_to_staging(hero)

	var counts: Dictionary = _count_wave_units_near_staging(_attack_wave_units)
	if regroup_center != _attack_wave_staging_point:
		counts = {
			"non_hero_gathered": filter_units_near_rally(
				_attack_wave_units,
				regroup_center,
				ATTACK_WAVE_COHESION_RADIUS
			).size(),
			"non_hero_total": _attack_wave_units.size(),
		}

	var non_hero_total: int = maxi(1, int(counts.get("non_hero_total", 1)))
	var cohesion_ratio: float = float(counts.get("non_hero_gathered", 0)) / float(non_hero_total)
	var regroup_ready: bool = cohesion_ratio >= ATTACK_WAVE_REGROUP_PERCENT
	var regroup_timeout: bool = _attack_wave_regroup_timer >= ATTACK_WAVE_REGROUP_TIMEOUT_SECONDS

	if hero != null and not _is_hero_at_staging(hero) and not _can_attack_without_hero(tree):
		_transition_attack_wave_state(AttackWaveState.WAITING_FOR_HERO, "hero separated")
		return

	if not regroup_ready and not regroup_timeout:
		return

	_attack_wave_ready_to_advance = true
	_transition_attack_wave_state(AttackWaveState.REGROUPING, "wave ready to advance")


static func _tick_attack_wave_advancing(tree: SceneTree, delta: float) -> void:
	if should_retreat_from_fight(tree) or should_abort_offensive_push(tree):
		notify_attack_wave_retreat_started("low army strength")
		initiate_group_retreat(tree, "attack wave retreat")
		return

	if should_recall_offensive_for_defense(tree):
		notify_attack_wave_retreat_started("base defense recall")
		initiate_group_retreat(tree, "defense override")
		return

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		wave_units = _sanitize_attack_wave_units(_attack_wave_units)

	var army_center: Vector3 = compute_army_center(wave_units)
	if army_center != Vector3.ZERO and _attack_wave_target_position != Vector3.ZERO:
		if horizontal_distance(army_center, _attack_wave_target_position) <= ATTACK_WAVE_ENGAGE_DISTANCE:
			confirm_attack_wave_engaging()

	var cohesion: float = _estimate_attack_wave_cohesion(wave_units)
	if cohesion < ATTACK_WAVE_MIN_COHESION_RATIO and army_center != Vector3.ZERO:
		_attack_wave_staging_point = army_center
		_attack_wave_ready_to_advance = false
		_transition_attack_wave_state(AttackWaveState.REGROUPING, "poor cohesion during advance")


static func _tick_attack_wave_engaging(tree: SceneTree, delta: float) -> void:
	if should_retreat_from_fight(tree) or should_abort_offensive_push(tree):
		notify_attack_wave_retreat_started("fight unfavorable")
		initiate_group_retreat(tree, "attack wave retreat")
		return

	if should_recall_offensive_for_defense(tree):
		notify_attack_wave_retreat_started("base defense recall")
		initiate_group_retreat(tree, "defense override")
		return

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	var cohesion: float = _estimate_attack_wave_cohesion(wave_units)
	if cohesion < ATTACK_WAVE_MIN_COHESION_RATIO * 0.85 and wave_units.size() >= 4:
		var army_center: Vector3 = compute_army_center(wave_units)
		if army_center != Vector3.ZERO:
			_attack_wave_staging_point = army_center
			_transition_attack_wave_state(AttackWaveState.REGROUPING, "fragmented during engagement")


static func _tick_attack_wave_retreating(tree: SceneTree, delta: float) -> void:
	if get_army_mode() != ArmyMode.RETREATING:
		notify_attack_wave_retreat_complete(tree)


static func _tick_attack_wave_recovering(tree: SceneTree, delta: float) -> void:
	_attack_wave_recovery_timer += delta
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position != Vector3.ZERO:
		pull_reinforcement_units_to_rally(tree, rally_position)

	if _attack_wave_recovery_timer < ATTACK_WAVE_RECOVERY_COOLDOWN_SECONDS:
		return

	_attack_wave_units.clear()
	_attack_wave_staging_point = Vector3.ZERO
	_attack_wave_target_position = Vector3.ZERO
	_attack_wave_target_node = null
	_attack_wave_ready_to_advance = false
	_attack_wave_min_non_hero_units = 0
	_transition_attack_wave_state(AttackWaveState.NONE, "recovery complete")


static func _estimate_attack_wave_cohesion(units: Array) -> float:
	units = _sanitize_attack_wave_units(units)
	if units.size() <= 1:
		return 1.0

	var center: Vector3 = compute_army_center(units)
	if center == Vector3.ZERO:
		return 0.0

	var grouped: Array = filter_units_near_rally(units, center, ATTACK_WAVE_COHESION_RADIUS)
	return float(grouped.size()) / float(units.size())


static func _find_exposed_player_army_cluster(
	tree: SceneTree,
	from_position: Vector3
) -> Dictionary:
	var player_units: Array = collect_player_military_near(
		tree,
		from_position,
		EXPOSED_PLAYER_ARMY_SEARCH_RANGE
	)
	player_units = NodeSafety.clean_node_array(player_units)
	if player_units.size() < EXPOSED_PLAYER_ARMY_MIN_UNITS:
		return {}

	var cluster_position: Vector3 = compute_army_center(player_units)
	if cluster_position == Vector3.ZERO:
		return {}

	var nearby_army: Array = collect_player_military_near(
		tree,
		cluster_position,
		LOCAL_FIGHT_RADIUS
	)
	if nearby_army.size() < EXPOSED_PLAYER_ARMY_MIN_UNITS:
		return {}

	var strongest: Node3D = null
	var strongest_power: int = 0
	for unit: Variant in nearby_army:
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		var power: int = estimate_military_power([unit])
		if power > strongest_power:
			strongest_power = power
			strongest = unit as Node3D

	return {
		"node": strongest,
		"position": cluster_position,
		"unit_count": nearby_army.size(),
	}


static func _find_player_production_building(tree: SceneTree, from_position: Vector3) -> Node3D:
	var closest_building: Node3D = null
	var closest_distance: float = INF

	for node: Variant in CombatTargetValidation.get_cached_group_nodes(tree, BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		if not (node is Barracks or node is Stable or node is ArtilleryDepot or node is Academy):
			continue

		var building: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, building.global_position)
		if distance > IMPORTANT_BUILDING_SEARCH_RANGE:
			continue

		if distance < closest_distance:
			closest_distance = distance
			closest_building = building

	return closest_building


static func get_active_wave_start_unit_count() -> int:
	return _active_wave_start_unit_count


static func begin_offensive_wave(wave_units: Array) -> void:
	wave_units = NodeSafety.clean_node_array(wave_units)
	_active_wave_start_unit_count = wave_units.size()
	_attack_wave_units = wave_units.duplicate()
	_objective_reissue_timer = 0.0
	_objective_stuck_timer = 0.0
	_objective_last_building_health = -1
	if _attack_wave_state == AttackWaveState.ADVANCING:
		_transition_attack_wave_state(AttackWaveState.ENGAGING, "offensive wave committed")


static func set_attack_objective(objective: Node3D, position: Vector3) -> void:
	_active_wave_objective = NodeSafety.safe_node(objective) as Node3D
	_active_wave_objective_position = position
	_objective_reissue_timer = 0.0
	_objective_stuck_timer = 0.0
	_objective_last_building_health = -1


static func get_attack_objective_position() -> Vector3:
	return _active_wave_objective_position


static func prepare_defense_recall(tree: SceneTree) -> void:
	if is_attack_wave_active():
		abort_attack_wave(tree, "defense override recall")
	cancel_offensive_orders(tree)
	clear_offensive_wave_tracking()


static func should_recall_offensive_for_defense(tree: SceneTree) -> bool:
	if get_army_mode() != ArmyMode.ATTACKING:
		return false

	var emergency_threat: Dictionary = evaluate_emergency_defense_threat(tree)
	if emergency_threat.get("threatened", false):
		var emergency_reason: StringName = emergency_threat.get("reason", &"")
		if emergency_reason == &"town_center":
			return true

		if _finishing_mode_active and should_allow_finishing_during_emergency(
			tree,
			emergency_threat
		):
			return false

		return (
			emergency_threat.get("force_recall", false)
			or is_emergency_threat_serious(tree, emergency_threat)
		)

	var threat: Dictionary = evaluate_defense_threat(tree)
	if not threat.get("threatened", false):
		return false

	if threat.get("force_commit", false):
		return true

	if _finishing_mode_active:
		var reason: StringName = threat.get("reason", &"")
		return reason == &"base"

	var reason: StringName = threat.get("reason", &"")
	if reason == &"base" or reason == &"buildings" or reason == &"workers":
		return true

	return not _is_attack_close_to_winning(tree)


static func _is_attack_close_to_winning(tree: SceneTree) -> bool:
	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center == null:
		return true

	if get_health_ratio(command_center) > ATTACK_CLOSE_TO_WIN_CC_HEALTH_RATIO:
		return false

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		return false

	var army_center: Vector3 = compute_army_center(wave_units)
	if army_center == Vector3.ZERO:
		return false

	return (
		horizontal_distance(army_center, command_center.global_position)
		<= ATTACK_CLOSE_TO_WIN_ARMY_DISTANCE
	)


static func maintain_attack_wave_objective(tree: SceneTree, delta: float) -> void:
	if get_army_mode() != ArmyMode.ATTACKING:
		return

	var reissue_interval: float = (
		FINISHING_MODE_OBJECTIVE_REISSUE_SECONDS
		if _finishing_mode_active
		else ATTACK_OBJECTIVE_REISSUE_SECONDS
	)

	_objective_reissue_timer += delta
	_objective_eval_timer += delta
	_objective_stuck_check_timer += delta

	var previous_objective_ref: Variant = _active_wave_objective
	var previous_objective_alive: bool = NodeSafety.is_alive_node(previous_objective_ref)
	if previous_objective_alive and previous_objective_ref is Building:
		previous_objective_alive = _is_living_building(previous_objective_ref as Building)

	var objective_died: bool = previous_objective_ref != null and not previous_objective_alive
	var objective_node: Node3D = null
	if previous_objective_alive and previous_objective_ref is Node3D:
		objective_node = previous_objective_ref as Node3D
	var objective_position: Vector3 = _active_wave_objective_position
	var objective_changed: bool = false

	var need_objective_eval: bool = (
		objective_died
		or _objective_eval_timer >= OBJECTIVE_EVAL_INTERVAL_SECONDS
	)
	if need_objective_eval:
		_objective_eval_timer = 0.0

		var fallback_position: Vector3 = _active_wave_objective_position
		if fallback_position == Vector3.ZERO:
			fallback_position = resolve_enemy_rally_position(tree)

		var objective: Dictionary = resolve_attack_objective(tree, fallback_position)
		var objective_node_ref: Variant = objective.get("node")
		objective_node = null
		if NodeSafety.is_alive_node(objective_node_ref) and objective_node_ref is Node3D:
			objective_node = objective_node_ref as Node3D
		objective_position = objective.get("position", Vector3.ZERO)
		if objective_position == Vector3.ZERO:
			return

		objective_changed = (
			NodeSafety.is_alive_node(objective_node) and objective_node != previous_objective_ref
		)

		if NodeSafety.is_alive_node(objective_node):
			_active_wave_objective = objective_node
		elif objective_died:
			_active_wave_objective = null
		_active_wave_objective_position = objective_position

		if _finishing_mode_active and NodeSafety.is_alive_node(objective_node):
			if objective_died or objective_changed:
				_log_finishing_objective(objective_node)

	if _objective_stuck_check_timer >= OBJECTIVE_STUCK_CHECK_INTERVAL_SECONDS:
		_objective_stuck_check_timer = 0.0
		_update_objective_stuck_detection(
			tree,
			objective_node,
			OBJECTIVE_STUCK_CHECK_INTERVAL_SECONDS
		)

	var should_reissue: bool = (
		_objective_reissue_timer >= reissue_interval
		or objective_died
		or objective_changed
	)
	var should_unstick: bool = _objective_stuck_timer >= ATTACK_OBJECTIVE_STUCK_SECONDS
	if not should_reissue and not should_unstick:
		return

	_objective_reissue_timer = 0.0

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		if get_army_mode() in [ArmyMode.ATTACKING, ArmyMode.CREEPING]:
			check_destroyed_army_regroup(tree)
		return

	if should_unstick and NodeSafety.is_alive_node(objective_node):
		_objective_stuck_timer = 0.0
		_command_assault_objective(wave_units, objective_node, true)
		return

	if NodeSafety.is_alive_node(objective_node):
		_command_focus_attack_objective(
			wave_units,
			objective_node,
			EnemyUnitMission.Mission.ATTACK
		)
		return

	command_attack_move(
		wave_units,
		objective_position,
		EnemyUnitMission.Mission.ATTACK
	)


static func _update_objective_stuck_detection(
	tree: SceneTree,
	objective_node: Node3D,
	delta: float
) -> void:
	if not NodeSafety.is_alive_node(objective_node) or not objective_node is Building:
		_objective_stuck_timer = 0.0
		_objective_last_building_health = -1
		return

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		return

	var army_center: Vector3 = compute_army_center(wave_units)
	if (
		army_center == Vector3.ZERO
		or horizontal_distance(army_center, objective_node.global_position)
		> ATTACK_OBJECTIVE_NEAR_DISTANCE
	):
		_objective_stuck_timer = 0.0
		return

	var building: Building = objective_node as Building
	var current_health: int = CombatTargetValidation.get_target_current_health(building)
	if _objective_last_building_health >= 0 and current_health < _objective_last_building_health:
		_objective_stuck_timer = 0.0
	else:
		_objective_stuck_timer += delta

	_objective_last_building_health = current_health


static func command_focus_attack(
	units: Array,
	objective: Node3D,
	mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.ATTACK
) -> void:
	_command_focus_attack_objective(units, objective, mission)


static func _command_focus_attack_objective(
	units: Array,
	objective: Node3D,
	mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.ATTACK
) -> void:
	if mission == EnemyUnitMission.Mission.ATTACK:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and not can_launch_player_attack(tree):
			EnemyAIDebug.log_once(
				"player_attack_blocked",
				"Player attack blocked: %s" % get_player_offense_block_reason(tree)
			)
			return

	if not NodeSafety.is_alive_node(objective):
		return

	units = NodeSafety.clean_node_array(units)
	var pending_orders: Array = []
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		## Claim DEFEND/ATTACK/CREEP before micro gates so RALLY/IDLE pending
		## defenders can focus the emergency threat instead of staying idle.
		EnemyUnitMission.try_set_mission(unit as Node, mission)

		if not _should_focus_unit_on_objective(unit as Node3D, objective):
			continue

		var objective_position: Vector3 = objective.global_position
		if not EnemyUnitMission.should_reissue_move_order(
			unit as Node,
			objective_position,
			mission
		):
			continue

		pending_orders.append({
			"unit": unit,
			"target": objective_position,
			"use_attack_move": true,
			"mission": mission,
			"focus_objective": objective,
		})

	if pending_orders.is_empty():
		return

	var had_pending: bool = not _pending_group_orders.is_empty()
	_pending_group_orders.append_array(pending_orders)
	if not had_pending and not _issuing_group_order_batch:
		tick_group_order_batch(null)


static func _command_assault_objective(
	units: Array,
	objective: Node3D,
	use_spread: bool = false
) -> void:
	if not NodeSafety.is_alive_node(objective):
		return

	units = NodeSafety.clean_node_array(units)
	if use_spread and not units.is_empty():
		var spread_targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
			objective.global_position,
			units.size(),
			FORMATION_SPACING * ATTACK_OBJECTIVE_SPREAD_MULTIPLIER
		)
		var pending_orders: Array = []
		for index: int in units.size():
			var unit: Variant = units[index]
			if not NodeSafety.is_alive_node(unit):
				continue

			if not EnemyUnitMission.should_reissue_move_order(
				unit as Node,
				spread_targets[index],
				EnemyUnitMission.Mission.ATTACK
			):
				continue

			pending_orders.append({
				"unit": unit,
				"target": spread_targets[index],
				"use_attack_move": true,
				"mission": EnemyUnitMission.Mission.ATTACK,
			})

		if not pending_orders.is_empty():
			var had_pending: bool = not _pending_group_orders.is_empty()
			_pending_group_orders.append_array(pending_orders)
			if not had_pending and not _issuing_group_order_batch:
				tick_group_order_batch(null)
		return

	_command_focus_attack_objective(units, objective, EnemyUnitMission.Mission.ATTACK)


static func _command_unit_focus_attack(unit: Variant, objective) -> void:
	if not NodeSafety.is_alive_node(unit) or not NodeSafety.is_alive_node(objective):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if not EnemyUnitMission.allows_combat_micro(unit as Node):
		return

	if objective is Building and not _is_living_building(objective as Building):
		return

	if (unit as Object).has_method("command_attack"):
		(unit as Object).call("command_attack", objective)


static func _should_focus_unit_on_objective(unit, objective) -> bool:
	if not NodeSafety.is_alive_node(unit) or not NodeSafety.is_alive_node(objective):
		return false

	if not is_living_combat_unit(unit):
		return false

	if not EnemyUnitMission.allows_combat_micro(unit):
		return false

	if objective is Building and not _is_living_building(objective):
		return false

	return true


static func clear_offensive_wave_tracking() -> void:
	_active_wave_start_unit_count = 0
	_reset_objective_tracking()


static func _reset_objective_tracking() -> void:
	_active_wave_objective = null
	_active_wave_objective_position = Vector3.ZERO
	_objective_reissue_timer = 0.0
	_objective_stuck_timer = 0.0
	_objective_last_building_health = -1
	_objective_eval_timer = 0.0
	_objective_stuck_check_timer = 0.0


## Returns true when the requested mode owns the army for issuing orders.
## Pass allow_attack_override_creep when a ready wave should take over from creeping.
static func try_claim_army_mode(
	requested_mode: ArmyMode,
	allow_attack_override_creep: bool = false
) -> bool:
	if requested_mode == _army_mode:
		return true

	# Mid-map INTERCEPTING is a player-attack bypass during early strategic phases.
	# Emergency defense uses DEFENDING; only that may override early phases.
	if requested_mode == ArmyMode.INTERCEPTING:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and not can_launch_player_attack(tree):
			return false

	# ATTACKING must never be claimed while strategic phases own the army.
	if requested_mode == ArmyMode.ATTACKING:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if (
			tree != null
			and not can_launch_player_attack(tree)
			and not _allow_hostile_engagement
		):
			EnemyAIDebug.log_once(
				"player_attack_blocked",
				"Player attack blocked: %s" % get_player_offense_block_reason(tree)
			)
			return false

	if not _can_transition_army_mode(requested_mode):
		return false

	var previous_mode: ArmyMode = _army_mode

	match _army_mode:
		ArmyMode.IDLE, ArmyMode.OPENING:
			_set_army_mode(requested_mode, previous_mode)
			return true
		ArmyMode.ASSEMBLING:
			if MilitaryAIConfig.is_v2_enabled() and requested_mode in [
				ArmyMode.CREEPING,
				ArmyMode.ATTACKING,
				ArmyMode.RETREATING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.REGROUPING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			if requested_mode in [
				ArmyMode.RETREATING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.ATTACKING,
			]:
				if requested_mode == ArmyMode.ATTACKING and not _allow_hostile_engagement:
					return requested_mode == ArmyMode.ASSEMBLING
				_set_army_mode(requested_mode, previous_mode)
				return true
			return requested_mode == ArmyMode.ASSEMBLING
		ArmyMode.CREEPING:
			if requested_mode == ArmyMode.ATTACKING and (
				allow_attack_override_creep or _allow_hostile_engagement
			):
				# Strategic early phases own the army — attack waves must not steal it.
				var tree: SceneTree = Engine.get_main_loop() as SceneTree
				if (
					tree != null
					and not can_launch_player_attack(tree)
					and not _allow_hostile_engagement
				):
					return false
				_set_army_mode(requested_mode, previous_mode)
				return true
			if requested_mode in [
				ArmyMode.REGROUPING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.RETREATING,
				ArmyMode.ASSEMBLING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.ATTACKING:
			if requested_mode in [
				ArmyMode.REGROUPING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.RETREATING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.INTERCEPTING:
			if requested_mode == ArmyMode.INTERCEPTING:
				return true
			if requested_mode in [
				ArmyMode.DEFENDING,
				ArmyMode.RETREATING,
				ArmyMode.REGROUPING,
				ArmyMode.ASSEMBLING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.RETREATING:
			if requested_mode in [
				ArmyMode.REGROUPING,
				ArmyMode.IDLE,
				ArmyMode.OPENING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return requested_mode == ArmyMode.RETREATING
		ArmyMode.REGROUPING:
			if requested_mode in [
				ArmyMode.CREEPING,
				ArmyMode.ATTACKING,
				ArmyMode.IDLE,
				ArmyMode.OPENING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.ASSEMBLING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.DEFENDING:
			if requested_mode == ArmyMode.DEFENDING:
				return true
			if MilitaryAIConfig.is_v2_enabled() and requested_mode in [
				ArmyMode.CREEPING,
				ArmyMode.ATTACKING,
				ArmyMode.RETREATING,
				ArmyMode.REGROUPING,
				ArmyMode.INTERCEPTING,
				ArmyMode.ASSEMBLING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			if requested_mode in [
				ArmyMode.RETREATING,
				ArmyMode.REGROUPING,
				ArmyMode.INTERCEPTING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false

	return false


static func _can_transition_army_mode(requested_mode: ArmyMode) -> bool:
	if requested_mode in [ArmyMode.RETREATING, ArmyMode.DEFENDING, ArmyMode.INTERCEPTING]:
		return true

	var elapsed_seconds: float = float(
		Time.get_ticks_msec() - _mode_claim_msec
	) / 1000.0
	return elapsed_seconds >= MIN_STATE_DURATION_SECONDS


static func _set_army_mode(requested_mode: ArmyMode, previous_mode: ArmyMode) -> void:
	_army_mode = requested_mode
	_mode_claim_msec = Time.get_ticks_msec()
	_active_group_order_signature = ""
	_active_group_order_dest = Vector3.ZERO
	_active_group_order_mission = -1
	_active_group_order_msec = 0
	_formation_cache_msec = 0
	_debug_state_change(previous_mode, requested_mode)
	_sync_player_state_identity()


static func release_army_mode(mode: ArmyMode) -> bool:
	if _army_mode != mode:
		return false

	var previous_mode: ArmyMode = _army_mode
	_army_mode = ArmyMode.IDLE
	_mode_claim_msec = Time.get_ticks_msec()
	_active_group_order_signature = ""
	_active_group_order_dest = Vector3.ZERO
	_active_group_order_mission = -1
	_active_group_order_msec = 0
	_debug_state_change(previous_mode, ArmyMode.IDLE)
	_sync_player_state_identity()
	return true


static func should_abort_offensive_push(tree: SceneTree) -> bool:
	if should_retreat_from_fight(tree):
		return true

	if _finishing_mode_active:
		var living_wave_units: Array = _collect_living_offensive_wave_units(tree)
		var living_count: int = living_wave_units.size()
		if _active_wave_start_unit_count > 0:
			var retreat_threshold: int = maxi(
				FINISHING_MODE_MIN_PUSH_UNITS,
				int(float(_active_wave_start_unit_count) * FINISHING_MODE_ARMY_DESTROYED_RATIO)
			)
			if living_count < retreat_threshold:
				return true
		elif living_count < FINISHING_MODE_MIN_PUSH_UNITS:
			return true
		return false

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and get_health_ratio(hero) < HERO_RETREAT_HP_RATIO:
		return true

	var living_wave_units: Array = _collect_living_offensive_wave_units(tree)
	var living_count: int = living_wave_units.size()
	if _active_wave_start_unit_count > 0:
		var retreat_threshold: int = maxi(
			MIN_ARMY_UNITS_TO_CONTINUE_ATTACK,
			int(float(_active_wave_start_unit_count) * WAVE_REBUILD_ARMY_RATIO)
		)
		if living_count < retreat_threshold:
			return true
	else:
		if living_count < MIN_ARMY_UNITS_TO_CONTINUE_ATTACK:
			return true

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	if non_hero_units.size() < MIN_NON_HERO_FOR_HERO_JOIN:
		return true

	return estimate_military_power(non_hero_units) < MIN_ATTACK_ARMY_POWER


static func _collect_living_offensive_wave_units(tree: SceneTree) -> Array:
	_refresh_combat_units_cache_if_needed(tree)
	var frame: int = Engine.get_process_frames()
	if frame == _cached_offensive_wave_units_frame:
		return _cached_offensive_wave_units

	_cached_offensive_wave_units_frame = frame
	var units: Array = []
	for unit: Variant in _main_army_cache:
		if not NodeSafety.is_alive_node(unit):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if mission != EnemyUnitMission.Mission.ATTACK:
			continue

		units.append(unit)

	_cached_offensive_wave_units = units
	return units


static func abort_offensive_and_regroup(tree: SceneTree) -> bool:
	if is_attack_wave_active():
		notify_attack_wave_retreat_started("offensive abort")

	if get_army_mode() != ArmyMode.ATTACKING and get_army_mode() != ArmyMode.CREEPING:
		if is_attack_wave_active():
			abort_attack_wave(tree, "offensive aborted")
		return false

	if initiate_group_retreat(tree, "offensive abort"):
		clear_offensive_wave_tracking()
		set_rebuilding_army(true)
		return true

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		release_army_mode(ArmyMode.ATTACKING)
		cancel_offensive_orders(tree)
		clear_offensive_wave_tracking()
		set_rebuilding_army(true)
		return true

	cancel_offensive_orders(tree)
	if try_claim_army_mode(ArmyMode.REGROUPING):
		command_regroup_at_rally(tree, rally_position)
		clear_offensive_wave_tracking()
		set_rebuilding_army(true)
		return true

	release_army_mode(ArmyMode.ATTACKING)
	clear_offensive_wave_tracking()
	set_rebuilding_army(true)
	return true


static func cancel_offensive_orders(tree: SceneTree) -> void:
	for unit: Variant in collect_living_combat_units(tree):
		_cancel_unit_offensive_orders(unit)


static func pull_straggler_units_to_rally(
	tree: SceneTree,
	rally_position: Vector3,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> void:
	if rally_position == Vector3.ZERO:
		return

	## Never yank an active creep/attack/defend squad back to base as "stragglers".
	if get_army_mode() in [
		ArmyMode.CREEPING,
		ArmyMode.ATTACKING,
		ArmyMode.DEFENDING,
		ArmyMode.INTERCEPTING,
		ArmyMode.RETREATING,
		ArmyMode.ASSEMBLING,
	]:
		return

	var main_mission: EnemyUnitMission.Mission = EnemyUnitMission.get_main_army_mission()
	if main_mission in [
		EnemyUnitMission.Mission.CREEP,
		EnemyUnitMission.Mission.ATTACK,
		EnemyUnitMission.Mission.DEFEND,
		EnemyUnitMission.Mission.RETREAT,
	]:
		return

	var stragglers: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		var unit_mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if unit_mission in [
			EnemyUnitMission.Mission.CREEP,
			EnemyUnitMission.Mission.ATTACK,
			EnemyUnitMission.Mission.DEFEND,
			EnemyUnitMission.Mission.RETREAT,
		]:
			continue

		if horizontal_distance((unit as Node3D).global_position, rally_position) > max_distance:
			stragglers.append(unit)

	if stragglers.is_empty():
		return

	command_hold_at_rally(stragglers, rally_position, EnemyUnitMission.Mission.RALLY)


static func is_hero_isolated_near_player_threat(tree: SceneTree, hero) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	if not hero is Hero:
		return false

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	if non_hero_units.size() >= MIN_NON_HERO_FOR_HERO_JOIN:
		var army_center: Vector3 = compute_army_center(non_hero_units)
		if (
			army_center != Vector3.ZERO
			and horizontal_distance(hero.global_position, army_center)
			<= HERO_MAX_DISTANCE_FROM_ARMY
		):
			return false

	if (
		collect_player_military_near(
			tree,
			hero.global_position,
			HERO_ALONE_PLAYER_THREAT_RANGE
		).is_empty()
	):
		return false

	return true


static func get_effective_attack_min_non_hero_units(match_elapsed_seconds: float) -> int:
	return get_phase_min_army_size(match_elapsed_seconds)


static func can_commit_attack_wave(
	tree: SceneTree,
	wave_units: Array,
	rally_position: Vector3,
	min_non_hero_units: int,
	match_elapsed_seconds: float = 0.0
) -> Dictionary:
	return evaluate_attack_gate(
		tree,
		rally_position,
		wave_units,
		min_non_hero_units,
		match_elapsed_seconds
	)


static func evaluate_attack_gate(
	tree: SceneTree,
	rally_position: Vector3,
	wave_units: Array = [],
	min_non_hero_units: int = WAVE_1_MIN_NON_HERO_UNITS,
	match_elapsed_seconds: float = 0.0
) -> Dictionary:
	var is_wave_commit: bool = not wave_units.is_empty()
	var effective_min_non_hero: int = get_effective_attack_min_non_hero_units(
		match_elapsed_seconds
	)
	var required_non_hero: int = maxi(min_non_hero_units, effective_min_non_hero)
	required_non_hero = maxi(required_non_hero, ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS)

	if rally_position == Vector3.ZERO:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"no_rally"},
			{},
			match_elapsed_seconds
		)

	if not can_launch_player_attack(tree):
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"early_phase"},
			{"elapsed_seconds": match_elapsed_seconds},
			match_elapsed_seconds
		)

	var hero: Hero = find_living_enemy_hero(tree)
	var hero_alive: bool = hero != null
	var rebuilding: bool = _is_rebuilding_army
	var regrouping: bool = get_army_mode() == ArmyMode.REGROUPING

	var evaluated_units: Array = (
		NodeSafety.clean_node_array(wave_units)
		if is_wave_commit
		else collect_living_combat_units(tree)
	)
	var composition: Dictionary = _count_wave_composition(evaluated_units)
	var non_hero_count: int = int(composition.get("non_hero_count", 0))
	var melee_count: int = int(composition.get("melee_count", 0))
	var ranged_count: int = int(composition.get("ranged_count", 0))
	var total_combat_count: int = int(composition.get("total_count", 0))
	var large_army_ready: bool = non_hero_count >= MIN_TOTAL_COMBAT_UNITS_FOR_ATTACK
	var grouped_required: int = mini(non_hero_count, required_non_hero)
	var army_grouped: bool = is_army_grouped_at_position(
		evaluated_units,
		rally_position,
		ARMY_GROUP_MAX_RADIUS,
		grouped_required
	)
	var debug_context: Dictionary = {
		"hero_alive": hero_alive,
		"combat_count": total_combat_count,
		"non_hero_count": non_hero_count,
		"melee_count": melee_count,
		"ranged_count": ranged_count,
		"army_grouped": army_grouped,
		"rebuilding": rebuilding,
		"regrouping": regrouping,
		"required_non_hero": required_non_hero,
		"elapsed_seconds": match_elapsed_seconds,
	}

	if _finishing_mode_active:
		if total_combat_count >= FINISHING_MODE_MIN_PUSH_UNITS:
			return _finalize_attack_gate(
				{
					"can_commit": true,
					"reason": &"finishing_mode",
					"total_combat_count": total_combat_count,
				},
				debug_context,
				match_elapsed_seconds
			)
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"finishing_too_weak"},
			debug_context,
			match_elapsed_seconds
		)

	if EnemyAggression.is_aggression_mode_active():
		var aggression_min: int = EnemyAggression.AGGRESSION_MIN_ARMY_UNITS
		if total_combat_count >= aggression_min and non_hero_count >= ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS:
			return _finalize_attack_gate(
				{
					"can_commit": true,
					"reason": &"aggression_mode",
					"total_combat_count": total_combat_count,
					"confidence": EnemyAggression.confidence_name(EnemyAggression.get_confidence()),
				},
				debug_context,
				match_elapsed_seconds
			)
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"aggression_too_weak"},
			debug_context,
			match_elapsed_seconds
		)

	if non_hero_count < ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"suicide_attack"},
			debug_context,
			match_elapsed_seconds
		)

	if not hero_alive:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"no_hero"},
			debug_context,
			match_elapsed_seconds
		)

	var hero_in_wave: bool = false
	for unit: Variant in evaluated_units:
		if unit is Hero:
			hero_in_wave = true
			break
	if is_wave_commit and not hero_in_wave:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"hero_not_in_wave"},
			debug_context,
			match_elapsed_seconds
		)

	var bypass_rebuilding: bool = (
		match_elapsed_seconds >= ATTACK_TIMER_DESPERATE_SECONDS
		and non_hero_count >= ATTACK_DESPERATE_MIN_NON_HERO_UNITS
	) or large_army_ready
	if rebuilding and not bypass_rebuilding:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"rebuilding"},
			debug_context,
			match_elapsed_seconds
		)

	if regrouping and not is_wave_commit:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"regrouping"},
			debug_context,
			match_elapsed_seconds
		)

	if non_hero_count <= 0:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"hero_only"},
			debug_context,
			match_elapsed_seconds
		)

	if non_hero_count < required_non_hero:
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"army_too_small",
				"required_non_hero": required_non_hero,
			},
			debug_context,
			match_elapsed_seconds
		)

	var wave_power: int = estimate_military_power(evaluated_units)
	var wave_strength: float = estimate_combat_strength(evaluated_units)
	var known_player_power: int = estimate_known_player_army_strength(tree, rally_position)
	var known_player_strength: float = get_effective_player_strength_at(
		tree,
		rally_position,
		KNOWN_PLAYER_SCOUT_RANGE
	)
	debug_context["player_strength"] = known_player_power
	debug_context["wave_power"] = wave_power
	debug_context["wave_strength"] = wave_strength
	debug_context["player_combat_strength"] = known_player_strength

	var required_power: int = (
		int(float(known_player_power) * PLAYER_ARMY_STRENGTH_RATIO)
		if known_player_power > 0
		else 0
	)
	var unknown_player_timeout: bool = (
		known_player_power <= 0
		and match_elapsed_seconds >= ATTACK_TIMER_STANDARD_SECONDS
	)
	var composition_relaxed: bool = (
		unknown_player_timeout
		or match_elapsed_seconds >= ATTACK_TIMER_DESPERATE_SECONDS
		or non_hero_count >= ATTACK_STANDARD_MIN_NON_HERO_UNITS
	)
	var count_ready: bool = total_combat_count >= MIN_TOTAL_COMBAT_UNITS_FOR_ATTACK
	var power_ready: bool = known_player_power > 0 and wave_power >= required_power

	if not composition_relaxed and not count_ready and not power_ready:
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"army_not_ready",
				"wave_power": wave_power,
				"known_player_power": known_player_power,
				"total_combat_count": total_combat_count,
			},
			debug_context,
			match_elapsed_seconds
		)

	if known_player_power > 0 and wave_power < required_power and not large_army_ready:
		_debug_combat("attack cancelled: human strength too high")
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"outpowered",
				"wave_power": wave_power,
				"known_player_power": known_player_power,
			},
			debug_context,
			match_elapsed_seconds
		)

	if known_player_strength > 0.0:
		var attack_style: StringName = (
			&"aggressive"
			if EnemyAggression.should_use_aggressive_strength_gate()
			else &"normal"
		)
		var strength_gate: Dictionary = evaluate_strength_gate(
			wave_strength,
			known_player_strength,
			attack_style
		)
		if not strength_gate.get("allowed", false) and not large_army_ready:
			_debug_combat(
				"attack cancelled: strength ratio %.2f < %.2f"
				% [
					float(strength_gate.get("ratio", 0.0)),
					float(strength_gate.get("required_ratio", ATTACK_NORMAL_STRENGTH_RATIO)),
				]
			)
			return _finalize_attack_gate(
				{
					"can_commit": false,
					"reason": &"strength_ratio",
					"wave_strength": wave_strength,
					"player_strength": known_player_strength,
				},
				debug_context,
				match_elapsed_seconds
			)

	if not composition_relaxed:
		if melee_count < MIN_MELEE_UNITS_FOR_ATTACK:
			return _finalize_attack_gate(
				{
					"can_commit": false,
					"reason": &"not_enough_melee",
					"melee_count": melee_count,
				},
				debug_context,
				match_elapsed_seconds
			)

		if _enemy_has_archer_capability(tree) and ranged_count < MIN_RANGED_UNITS_FOR_ATTACK:
			return _finalize_attack_gate(
				{
					"can_commit": false,
					"reason": &"not_enough_ranged",
					"ranged_count": ranged_count,
				},
				debug_context,
				match_elapsed_seconds
			)

	if not army_grouped and not large_army_ready:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"not_grouped"},
			debug_context,
			match_elapsed_seconds
		)

	if not composition_relaxed and wave_power < MIN_ATTACK_ARMY_POWER and not power_ready:
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"army_power_too_low",
				"wave_power": wave_power,
			},
			debug_context,
			match_elapsed_seconds
		)

	return _finalize_attack_gate(
		{
			"can_commit": true,
			"reason": &"ready",
			"wave_power": wave_power,
			"known_player_power": known_player_power,
			"total_combat_count": total_combat_count,
		},
		debug_context,
		match_elapsed_seconds
	)


static func _finalize_attack_gate(
	result: Dictionary,
	debug_context: Dictionary,
	match_elapsed_seconds: float
) -> Dictionary:
	var can_commit: bool = result.get("can_commit", false)
	var ai_strength: float = float(
		result.get("wave_strength", debug_context.get("wave_strength", result.get("wave_power", 0)))
	)
	var player_strength: float = float(
		result.get(
			"player_strength",
			debug_context.get("player_strength", result.get("known_player_power", 0))
		)
	)
	if can_commit:
		EnemyAIDebug.log_army_strength_decision(ai_strength, player_strength, "Attack")
	elif String(result.get("reason", &"")) in ["outpowered", "strength_ratio"]:
		EnemyAIDebug.log_army_strength_decision(ai_strength, player_strength, "Hold")

	if DEBUG_ATTACK_GATE:
		var action: String = "ATTACK" if can_commit else "WAIT"
		var player_strength_value: Variant = debug_context.get("player_strength", "unknown")
		var player_strength_text: String = (
			"unknown"
			if int(player_strength_value) <= 0
			else str(player_strength_value)
		)
		print(
			(
				"EnemyAttackGate [%s]: reason=%s hero_alive=%s combat=%d non_hero=%d "
				+ "melee=%d ranged=%d grouped=%s player_strength=%s "
				+ "rebuilding=%s regrouping=%s elapsed=%.0fs required_non_hero=%d"
			)
			% [
				action,
				String(result.get("reason", &"unknown")),
				str(debug_context.get("hero_alive", false)),
				int(debug_context.get("combat_count", 0)),
				int(debug_context.get("non_hero_count", 0)),
				int(debug_context.get("melee_count", 0)),
				int(debug_context.get("ranged_count", 0)),
				str(debug_context.get("army_grouped", false)),
				player_strength_text,
				str(debug_context.get("rebuilding", false)),
				str(debug_context.get("regrouping", false)),
				match_elapsed_seconds,
				int(debug_context.get("required_non_hero", 0)),
			]
		)

	return result


static func estimate_known_player_army_strength(tree: SceneTree, rally_position: Vector3) -> int:
	var attack_destination: Vector3 = resolve_wave_attack_destination(tree, rally_position)
	var rally_visible: Array = collect_player_military_near(
		tree,
		rally_position,
		KNOWN_PLAYER_SCOUT_RANGE
	)
	var path_visible: Array = collect_player_military_near(
		tree,
		attack_destination,
		APPROACH_DETECTION_RANGE
	)
	var combined: Array = rally_visible.duplicate()
	for unit: Variant in path_visible:
		if not NodeSafety.is_alive_node(unit):
			continue

		if combined.has(unit):
			continue

		combined.append(unit)

	return estimate_military_power(combined)


static func is_army_grouped_at_position(
	units: Array,
	anchor_position: Vector3,
	max_radius: float = ARMY_GROUP_MAX_RADIUS,
	required_grouped: int = -1
) -> bool:
	units = NodeSafety.clean_node_array(units)
	var grouped_units: Array = filter_units_near_rally(units, anchor_position, max_radius)
	var non_hero_grouped: int = 0
	for unit: Variant in grouped_units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_non_hero_combat_unit(unit as Node):
			non_hero_grouped += 1

	var non_hero_total: int = 0
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_non_hero_combat_unit(unit as Node):
			non_hero_total += 1

	if non_hero_total <= 0:
		return false

	var required: int = (
		required_grouped
		if required_grouped > 0
		else mini(non_hero_total, MIN_NON_HERO_FOR_HERO_JOIN)
	)
	return non_hero_grouped >= required


static func _count_wave_composition(units: Array) -> Dictionary:
	var non_hero_count: int = 0
	var melee_count: int = 0
	var ranged_count: int = 0
	var total_count: int = 0
	var hero_in_wave: Hero = null

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		total_count += 1
		if unit is Hero:
			hero_in_wave = unit as Hero
			continue

		if not is_non_hero_combat_unit(unit as Node):
			continue

		non_hero_count += 1
		if unit is Archer or unit is CavalryArcher or unit is Cannon:
			ranged_count += 1
		else:
			melee_count += 1

	return {
		"non_hero_count": non_hero_count,
		"melee_count": melee_count,
		"ranged_count": ranged_count,
		"total_count": total_count,
		"hero": hero_in_wave,
	}


static func _enemy_has_archer_capability(tree: SceneTree) -> bool:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node) and (node is Archer or node is CavalryArcher or node is Cannon):
			return true

	return false


static func is_combat_unit(node) -> bool:
	return EnemyArmyForceMath.is_combat_unit(node)


static func is_hero_unit(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	return node is Hero


static func is_non_hero_combat_unit(node) -> bool:
	return is_combat_unit(node) and not is_hero_unit(node)


static func is_living_combat_unit(node) -> bool:
	return EnemyArmyForceMath.is_living_combat_unit(node)


static func register_combat_unit(unit) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if not is_combat_unit(unit):
		return

	if not unit.is_in_group(ENEMIES_GROUP):
		unit.add_to_group(ENEMIES_GROUP)

	if not unit.is_in_group(ENEMY_COMBAT_GROUP):
		unit.add_to_group(ENEMY_COMBAT_GROUP)


static func collect_living_combat_units(tree: SceneTree) -> Array:
	_refresh_combat_units_cache_if_needed(tree)
	return _main_army_cache.duplicate()


static func collect_living_non_hero_combat_units(tree: SceneTree) -> Array:
	_refresh_combat_units_cache_if_needed(tree)
	var units: Array = []
	for node: Variant in _main_army_cache:
		if node == null or not is_instance_valid(node):
			continue
		if is_living_combat_unit(node) and is_non_hero_combat_unit(node):
			units.append(node)

	return units


static func find_living_enemy_hero(tree: SceneTree) -> Hero:
	_refresh_combat_units_cache_if_needed(tree)
	for node: Variant in _main_army_cache:
		if node == null or not is_instance_valid(node):
			continue
		if is_living_combat_unit(node) and is_hero_unit(node):
			return node as Hero

	return null


static func get_min_non_hero_units_for_wave(wave_number: int) -> int:
	if wave_number <= 1:
		return WAVE_1_MIN_NON_HERO_UNITS
	if wave_number == 2:
		return WAVE_2_MIN_NON_HERO_UNITS
	if wave_number == 3:
		return WAVE_3_MIN_NON_HERO_UNITS

	return WAVE_4_MIN_NON_HERO_UNITS


static func filter_units_near_rally(
	units: Array,
	rally_position: Vector3,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> Array:
	units = NodeSafety.clean_node_array(units)
	var nearby_units: Array = []

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not unit is Node3D:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		if horizontal_distance((unit as Node3D).global_position, rally_position) <= max_distance:
			nearby_units.append(unit)

	return nearby_units


static func is_army_regrouped_at_rally(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero_units: int,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> bool:
	if rally_position == Vector3.ZERO:
		return false

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	return (
		filter_units_near_rally(non_hero_units, rally_position, max_distance).size()
		>= min_non_hero_units
	)


static func command_regroup_at_rally(tree: SceneTree, rally_position: Vector3) -> void:
	if rally_position == Vector3.ZERO:
		return

	cancel_offensive_orders(tree)
	var units: Array = collect_living_combat_units(tree)
	command_hold_at_rally(units, rally_position, EnemyUnitMission.Mission.RALLY)


static func get_min_reinforcement_release_size(match_elapsed_seconds: float) -> int:
	if match_elapsed_seconds >= PHASE_MID_SECONDS:
		return REINFORCEMENT_LATE_MIN
	if match_elapsed_seconds >= PHASE_EARLY_SECONDS:
		return REINFORCEMENT_MID_MIN
	return REINFORCEMENT_EARLY_MIN


static func is_reinforcement_waiting(unit) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false

	purge_stale_reinforcement_pool()
	return _reinforcement_pool.has(unit.get_instance_id())


static func clear_stale_combat_targets(unit: Variant) -> void:
	_cancel_unit_offensive_orders(unit)


static func log_ai_order(
	unit: Variant,
	source: String,
	state: String,
	target: Variant,
	reason: String
) -> void:
	if not DEBUG_AI_ORDERS and not EnemyArmyCommandTelemetry.is_debug_override_enabled():
		return

	if not NodeSafety.is_alive_node(unit):
		return

	var unit_label: String = "unit"
	if unit is Spearman:
		unit_label = "spearman"
	elif unit is Hero:
		unit_label = "hero"
	elif unit is Swordsman:
		unit_label = "swordsman"
	elif unit is Archer:
		unit_label = "archer"

	var target_label: String = str(target)
	if target is Vector3:
		target_label = "(%.1f, %.1f)" % [target.x, target.z]

	print(
		"AI ORDER: unit=%s source=%s state=%s target=%s reason=%s"
		% [unit_label, source, state, target_label, reason]
	)


static func purge_stale_reinforcement_pool() -> void:
	var stale_ids: Array = []
	for unit_id: Variant in _reinforcement_pool.keys():
		if not _unit_id_is_alive(int(unit_id)):
			stale_ids.append(unit_id)

	for unit_id: Variant in stale_ids:
		_reinforcement_pool.erase(unit_id)


static func _unit_id_is_alive(unit_id: int) -> bool:
	return NodeSafety.is_alive_node(instance_from_id(unit_id))


static func collect_reinforcement_waiting_units(tree: SceneTree) -> Array:
	purge_stale_reinforcement_pool()
	var units: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if is_reinforcement_waiting(unit):
			units.append(unit)

	return units


static func _register_reinforcement_waiting(
	tree: SceneTree,
	unit,
	rally_position: Vector3,
	reason: String = "spawn_complete"
) -> void:
	if not _is_valid_attack_unit(unit) or not is_combat_unit(unit):
		return

	if rally_position == Vector3.ZERO:
		return

	clear_stale_combat_targets(unit)
	if not EnemyUnitMission.try_set_mission(
		unit,
		EnemyUnitMission.Mission.RALLY,
		0.0
	):
		return

	_reinforcement_pool[unit.get_instance_id()] = {
		"rally": rally_position,
		"registered_msec": Time.get_ticks_msec(),
	}
	command_hold_at_rally(
		[unit],
		rally_position,
		EnemyUnitMission.Mission.RALLY
	)
	log_ai_order(
		unit,
		"assign_reinforcement_regroup",
		"RALLY",
		rally_position,
		reason
	)


static func release_reinforcement_from_pool(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	_reinforcement_pool.erase(unit.get_instance_id())


static func filter_units_for_field_combat(
	units: Array,
	mission: EnemyUnitMission.Mission
) -> Array:
	units = NodeSafety.clean_node_array(units)
	if mission not in [EnemyUnitMission.Mission.ATTACK, EnemyUnitMission.Mission.CREEP]:
		return units

	var eligible: Array = []
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_reinforcement_waiting(unit):
			continue

		eligible.append(unit)

	return eligible


static func is_creep_contest_on_cooldown(camp) -> bool:
	if not NodeSafety.is_alive_node(camp):
		return true

	var camp_id: int = camp.get_instance_id()
	if not _creep_contest_cooldowns.has(camp_id):
		return false

	return Time.get_ticks_msec() < int(_creep_contest_cooldowns[camp_id])


static func record_creep_contest_cooldown(camp, reason: String) -> void:
	if not NodeSafety.is_alive_node(camp):
		return

	_creep_contest_cooldowns[camp.get_instance_id()] = (
		Time.get_ticks_msec() + int(CREEP_CONTEST_COOLDOWN_SECONDS * 1000.0)
	)
	debug_combat_log("creep contest cooldown (%s) for camp %s" % [reason, camp.name])


static func purge_stale_creep_contest_cooldowns() -> void:
	var stale_ids: Array = []
	for camp_id: Variant in _creep_contest_cooldowns.keys():
		var camp: Variant = instance_from_id(int(camp_id))
		if not NodeSafety.is_alive_node(camp):
			stale_ids.append(camp_id)
			continue

		if Time.get_ticks_msec() >= int(_creep_contest_cooldowns[camp_id]):
			stale_ids.append(camp_id)

	for camp_id: Variant in stale_ids:
		_creep_contest_cooldowns.erase(camp_id)


static func evaluate_creep_contest_request(
	tree: SceneTree,
	camp: Node3D,
	rally_position: Vector3,
	match_elapsed_seconds: float
) -> Dictionary:
	if not NodeSafety.is_alive_node(camp) or rally_position == Vector3.ZERO:
		return {"allowed": false, "reason": &"invalid_target"}

	if is_creep_contest_on_cooldown(camp):
		return {"allowed": false, "reason": &"cooldown"}

	if not allows_creep_orders():
		return {"allowed": false, "reason": &"strategic_blocked"}

	if is_retreat_on_cooldown():
		return {"allowed": false, "reason": &"retreat_cooldown"}

	var camp_position: Vector3 = camp.global_position
	var player_units: Array = collect_player_military_near(
		tree,
		camp_position,
		PLAYER_CREEP_DETECT_RADIUS
	)
	if player_units.is_empty():
		return {"allowed": false, "reason": &"no_player"}

	record_player_army_observation(tree, camp_position, PLAYER_CREEP_DETECT_RADIUS)

	var player_strength: float = estimate_combat_strength(player_units)
	var creep_strength: float = 0.0
	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue

		var child: Node = child_variant as Node
		if not CombatTargetValidation.is_neutral_creep(child):
			continue
		if CombatTargetValidation.get_target_current_health(child) <= 0:
			continue

		creep_strength += 80.0

	var combined_threat: float = player_strength + creep_strength * 0.35
	var min_army: int = get_phase_min_army_size(match_elapsed_seconds)
	var ai_plan: Dictionary = build_coordinated_combat_group(
		tree,
		rally_position,
		min_army,
		true
	)
	if not ai_plan.get("can_launch", false):
		return {"allowed": false, "reason": &"army_not_ready", "player_strength": player_strength}

	var total_non_hero: int = int(ai_plan.get("total_non_hero_count", 0))
	var regrouped_non_hero: int = int(ai_plan.get("non_hero_count", 0))
	if total_non_hero > 0:
		var assembled_ratio: float = float(regrouped_non_hero) / float(total_non_hero)
		if assembled_ratio < ASSEMBLY_REQUIRED_PERCENT:
			return {"allowed": false, "reason": &"not_assembled", "player_strength": player_strength}

	if not ai_plan.get("hero_included", false):
		return {"allowed": false, "reason": &"hero_missing", "player_strength": player_strength}

	var ai_units: Array = ai_plan.get("units", [])
	var ai_strength: float = estimate_combat_strength(ai_units)
	var travel_time_factor: float = horizontal_distance(rally_position, camp_position) / 12.0
	if travel_time_factor > 8.0:
		return {"allowed": false, "reason": &"arrival_too_late", "player_strength": player_strength}

	var contest_gate: Dictionary = evaluate_strength_gate(
		ai_strength,
		combined_threat,
		&"normal"
	)
	if not contest_gate.get("allowed", false):
		return {
			"allowed": false,
			"reason": &"outpowered",
			"player_strength": player_strength,
			"ai_strength": ai_strength,
		}

	if is_enemy_base_threatened(tree):
		return {"allowed": false, "reason": &"base_threatened", "player_strength": player_strength}

	return {
		"allowed": true,
		"reason": &"approved",
		"units": ai_units,
		"player_strength": player_strength,
		"ai_strength": ai_strength,
	}


static func check_destroyed_army_regroup(
	tree: SceneTree,
	match_elapsed_seconds: float = 0.0
) -> bool:
	var mode: ArmyMode = get_army_mode()
	if mode != ArmyMode.ATTACKING and mode != ArmyMode.CREEPING:
		return false

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var attack_units: Array = _collect_living_offensive_wave_units(tree)
	var phase_min: int = get_phase_min_army_size(match_elapsed_seconds)
	var hero: Hero = find_living_enemy_hero(tree)
	var should_regroup: bool = false
	var reason: String = ""

	if hero == null:
		should_regroup = true
		reason = "hero absent"
	elif non_hero_units.size() < MIN_SURVIVORS_FOR_OFFENSIVE:
		should_regroup = true
		reason = "too few survivors"
	elif non_hero_units.size() < int(float(phase_min) * DESTROYED_ARMY_REGROUP_THRESHOLD_RATIO):
		should_regroup = true
		reason = "below phase threshold"
	elif mode == ArmyMode.ATTACKING and attack_units.is_empty():
		should_regroup = true
		reason = "no attack mission units"
	elif _fight_start_strength > 0.0:
		var current_strength: float = estimate_combat_strength(
			attack_units if not attack_units.is_empty() else non_hero_units
		)
		if current_strength <= _fight_start_strength * (1.0 - EMERGENCY_RETREAT_ARMY_LOSS_RATIO):
			should_regroup = true
			reason = "army losses"

	if not should_regroup:
		return false

	clear_offensive_wave_tracking()
	cancel_offensive_orders(tree)
	release_army_mode(mode)
	if try_claim_army_mode(ArmyMode.REGROUPING):
		set_rebuilding_army(true)
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		if rally_position != Vector3.ZERO:
			command_regroup_at_rally(tree, rally_position)
		EnemyUnitMission.set_main_army_mission(
			EnemyUnitMission.Mission.RALLY,
			"destroyed army: %s" % reason
		)
	debug_combat_log("force regroup: %s" % reason)
	return true


static func tick_reinforcement_pool(tree: SceneTree, match_elapsed_seconds: float) -> void:
	purge_stale_reinforcement_pool()
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	var waiting_units: Array = collect_reinforcement_waiting_units(tree)
	if waiting_units.is_empty():
		return

	for unit: Variant in waiting_units:
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		var unit_position: Vector3 = (unit as Node3D).global_position
		if horizontal_distance(unit_position, rally_position) > WAVE_REGROUP_MAX_DISTANCE:
			if EnemyUnitMission.should_reissue_move_order(
				unit as Node,
				rally_position,
				EnemyUnitMission.Mission.RALLY
			):
				command_hold_at_rally(
					[unit],
					rally_position,
					EnemyUnitMission.Mission.RALLY
				)

	var min_release: int = get_min_reinforcement_release_size(match_elapsed_seconds)
	if waiting_units.size() < min_release:
		return

	var army_mode: ArmyMode = get_army_mode()
	if army_mode in [ArmyMode.RETREATING, ArmyMode.ASSEMBLING]:
		return

	if is_defense_blocking_offense():
		return

	if army_mode in [ArmyMode.ATTACKING, ArmyMode.CREEPING]:
		if should_abort_offensive_push(tree):
			return

		var attack_units: Array = _collect_living_offensive_wave_units(tree)
		if attack_units.is_empty():
			return

		var army_center: Vector3 = compute_army_center(attack_units)
		if (
			army_center != Vector3.ZERO
			and horizontal_distance(army_center, rally_position) > WAVE_REGROUP_MAX_DISTANCE * 2.0
		):
			return

	var hero: Hero = find_living_enemy_hero(tree)
	if hero == null:
		return

	var hero_near_rally: bool = (
		horizontal_distance(hero.global_position, rally_position) <= ASSEMBLY_RADIUS * 2.0
	)
	if not hero_near_rally and army_mode not in [ArmyMode.DEFENDING, ArmyMode.INTERCEPTING]:
		return


static func _is_emergency_threat_near_base(tree: SceneTree, rally_position: Vector3) -> bool:
	var threat_position: Vector3 = get_emergency_defense_objective()
	if threat_position == Vector3.ZERO:
		return false

	return horizontal_distance(threat_position, rally_position) <= EMERGENCY_BASE_RADIUS


static func assign_reinforcement_regroup(tree: SceneTree, unit) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if _emergency_defense_active and _is_emergency_threat_near_base(tree, rally_position):
		_assign_reinforcement_to_emergency_defense(tree, unit)
		return

	_register_reinforcement_waiting(tree, unit, rally_position, "spawn_complete")


static func _count_pending_reinforcement_units(tree: SceneTree) -> int:
	var count: int = 0
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_reinforcement_waiting(unit) or EnemyUnitMission.get_unit_mission(unit as Node) == EnemyUnitMission.Mission.RALLY:
			count += 1

	return count


static func pull_reinforcement_units_to_rally(
	tree: SceneTree,
	rally_position: Vector3,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> void:
	if rally_position == Vector3.ZERO:
		return

	var reinforcements: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if mission != EnemyUnitMission.Mission.RALLY and mission != EnemyUnitMission.Mission.IDLE:
			continue

		if horizontal_distance((unit as Node3D).global_position, rally_position) > max_distance:
			reinforcements.append(unit)

	if reinforcements.is_empty():
		return

	command_hold_at_rally(reinforcements, rally_position, EnemyUnitMission.Mission.RALLY)


static func pull_finishing_reinforcements_to_attack(tree: SceneTree) -> void:
	if not _finishing_mode_active:
		return

	if not can_launch_player_attack(tree):
		return

	var objective_position: Vector3 = get_attack_objective_position()
	if objective_position == Vector3.ZERO:
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		var objective: Dictionary = resolve_attack_objective(tree, rally_position)
		objective_position = objective.get("position", Vector3.ZERO)
		var objective_node_ref: Variant = objective.get("node")
		if NodeSafety.is_alive_node(objective_node_ref) and objective_node_ref is Node3D:
			set_attack_objective(objective_node_ref as Node3D, objective_position)

	if objective_position == Vector3.ZERO:
		return

	var reinforcements: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if mission == EnemyUnitMission.Mission.ATTACK:
			continue

		if (
			mission != EnemyUnitMission.Mission.RALLY
			and mission != EnemyUnitMission.Mission.IDLE
		):
			continue

		reinforcements.append(unit)

	if reinforcements.size() < FINISHING_MODE_MIN_PUSH_UNITS:
		return

	if find_living_enemy_hero(tree) == null:
		return

	var objective_node: Node3D = NodeSafety.safe_node(_active_wave_objective) as Node3D
	if NodeSafety.is_alive_node(objective_node):
		_command_focus_attack_objective(
			reinforcements,
			objective_node,
			EnemyUnitMission.Mission.ATTACK
		)
	else:
		command_attack_move(
			reinforcements,
			objective_position,
			EnemyUnitMission.Mission.ATTACK
		)

	for unit: Variant in reinforcements:
		release_reinforcement_from_pool(unit as Node)


static func build_regrouped_attack_wave_units(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero_units: int
) -> Dictionary:
	return build_coordinated_combat_group(tree, rally_position, min_non_hero_units, true)


static func should_rebuild_army_after_wave(
	current_non_hero_count: int,
	last_wave_non_hero_count: int
) -> bool:
	if last_wave_non_hero_count <= 0:
		return false

	return (
		current_non_hero_count
		< int(float(last_wave_non_hero_count) * WAVE_REBUILD_ARMY_RATIO)
	)


static func build_attack_wave_units(tree: SceneTree, min_non_hero_units: int) -> Dictionary:
	## Aggression mode: commit nearly the whole combat army (leave minimal home defense).
	if EnemyAggression.is_aggression_mode_active():
		var aggression_units: Array = EnemyAggression.build_aggression_attack_force(tree)
		var aggression_non_hero: int = 0
		for unit: Variant in aggression_units:
			if unit != null and is_instance_valid(unit) and not is_hero_unit(unit as Node):
				aggression_non_hero += 1
		var aggression_min: int = mini(min_non_hero_units, EnemyAggression.AGGRESSION_MIN_ARMY_UNITS)
		return {
			"units": aggression_units,
			"can_launch": aggression_non_hero >= aggression_min,
			"non_hero_count": aggression_non_hero,
		}

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var can_launch: bool = non_hero_units.size() >= min_non_hero_units
	var wave_units: Array = non_hero_units.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		var army_center: Vector3 = compute_army_center(non_hero_units)
		if (
			hero != null
			and non_hero_units.size() >= ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS
			and army_center != Vector3.ZERO
			and is_hero_healthy_enough_for_wave(hero)
			and horizontal_distance(hero.global_position, army_center)
			<= HERO_MAX_DISTANCE_FROM_ARMY
		):
			wave_units.append(hero)

	return {
		"units": wave_units,
		"can_launch": can_launch,
		"non_hero_count": non_hero_units.size(),
	}


static func build_creep_army(tree: SceneTree, match_elapsed_seconds: float = 0.0) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var director: EnemyStrategicDirector = find_strategic_director(tree)
	var min_non_hero: int = CREEP_MIN_NON_HERO_UNITS
	if director != null:
		min_non_hero = maxi(CREEP_MIN_NON_HERO_UNITS, director.get_min_army_size_for_current_phase())
	elif match_elapsed_seconds > 0.0:
		min_non_hero = maxi(CREEP_MIN_NON_HERO_UNITS, get_phase_min_army_size(match_elapsed_seconds))
	return build_coordinated_combat_group(
		tree,
		rally_position,
		min_non_hero,
		true,
		HERO_CREEP_JOIN_HP_RATIO,
		CREEP_MIN_NON_HERO_UNITS
	)


static func is_enemy_base_threatened(tree: SceneTree) -> bool:
	return evaluate_defense_threat(tree).get("threatened", false)


static func evaluate_defense_threat(tree: SceneTree) -> Dictionary:
	var now_msec: int = Time.get_ticks_msec()
	if (
		not _defense_threat_cache.is_empty()
		and now_msec - _defense_threat_cache_msec < int(DEFENSE_THREAT_CACHE_SECONDS * 1000.0)
	):
		return _defense_threat_cache.duplicate()

	var start_usec: int = PerfCounters.begin_section()
	var result: Dictionary = _evaluate_defense_threat_uncached(tree)
	PerfCounters.end_section("Defense threat eval", start_usec)
	_defense_threat_cache = result.duplicate()
	_defense_threat_cache_msec = now_msec
	return result


static func _evaluate_defense_threat_uncached(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return {"threatened": false}

	var worker_threat: Dictionary = _evaluate_worker_defense_threat(tree)
	if worker_threat.get("threatened", false):
		return worker_threat

	var building_threat: Dictionary = _evaluate_building_defense_threat(tree)
	if building_threat.get("threatened", false):
		return building_threat

	var base_threat: Node3D = _find_player_military_near_position(
		tree,
		rally_position,
		BASE_THREAT_DETECTION_RANGE
	)
	if base_threat != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, base_threat.global_position),
			&"base",
			true
		)

	var economy_threat: Node3D = _find_player_military_in_enemy_economy_area(tree)
	if economy_threat != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, economy_threat.global_position),
			&"economy"
		)

	var approach_threat: Node3D = _find_player_military_near_position(
		tree,
		rally_position,
		APPROACH_DETECTION_RANGE
	)
	if approach_threat != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, approach_threat.global_position),
			&"approach"
		)

	return {"threatened": false}


static func evaluate_emergency_defense_threat(tree: SceneTree) -> Dictionary:
	var now_msec: int = Time.get_ticks_msec()
	if (
		not _emergency_threat_cache.is_empty()
		and now_msec - _emergency_threat_cache_msec < int(DEFENSE_THREAT_CACHE_SECONDS * 1000.0)
	):
		return _emergency_threat_cache.duplicate()

	var start_usec: int = PerfCounters.begin_section()
	var result: Dictionary = _evaluate_emergency_defense_threat_uncached(tree)
	PerfCounters.end_section("Emergency defense eval", start_usec)
	_emergency_threat_cache = result.duplicate()
	_emergency_threat_cache_msec = now_msec
	return result


static func _evaluate_emergency_defense_threat_uncached(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return {"threatened": false}

	var command_center_threat: Dictionary = _evaluate_emergency_command_center_threat(tree)
	if command_center_threat.get("threatened", false):
		return command_center_threat

	var production_threat: Dictionary = _evaluate_emergency_production_building_threat(tree)
	if production_threat.get("threatened", false):
		return production_threat

	var hero_threat: Dictionary = _evaluate_emergency_player_hero_threat(tree, rally_position)
	if hero_threat.get("threatened", false):
		return hero_threat

	var core_base_threat: Dictionary = _evaluate_emergency_core_base_threat(tree, rally_position)
	if core_base_threat.get("threatened", false):
		return core_base_threat

	var worker_threat: Dictionary = _evaluate_emergency_worker_attack_threat(tree)
	if worker_threat.get("threatened", false):
		return worker_threat

	return {"threatened": false}


static func has_meaningful_core_base_threat(tree: SceneTree) -> bool:
	var threat: Dictionary = evaluate_emergency_defense_threat(tree)
	if not threat.get("threatened", false):
		return false

	var reason: StringName = threat.get("reason", &"")
	return reason != &"worker_attack"


static func is_emergency_threat_serious(tree: SceneTree, threat: Dictionary) -> bool:
	if not threat.get("threatened", false):
		return false

	var reason: StringName = threat.get("reason", &"")
	if reason == &"town_center" or reason == &"production" or reason == &"player_hero":
		return true

	var intercept_position: Vector3 = threat.get("intercept_position", Vector3.ZERO)
	if intercept_position == Vector3.ZERO:
		return false

	var threat_power: int = estimate_player_threat_power_near(
		tree,
		intercept_position,
		DEFENSE_THREAT_POWER_RANGE
	)
	if threat_power >= EMERGENCY_SERIOUS_THREAT_POWER:
		return true

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	return (
		collect_player_military_near(tree, rally_position, CORE_BASE_DEFENSE_RADIUS).size()
		>= 3
	)


static func should_allow_finishing_during_emergency(
	tree: SceneTree,
	threat: Dictionary
) -> bool:
	## Counter-pressure: if the player hero-rushes with a tiny army while we are
	## significantly stronger, keep the main push alive instead of turtle-defending.
	if (
		EnemyAggression.is_counter_pressure_active()
		and EnemyAggression.is_aggression_mode_active()
		and not is_emergency_threat_serious(tree, threat)
	):
		var reason_cp: StringName = threat.get("reason", &"")
		if reason_cp not in [&"town_center", &"production"]:
			return true

	if not _finishing_mode_active:
		return false

	var reason: StringName = threat.get("reason", &"")
	if reason in [&"town_center", &"production", &"buildings", &"workers", &"base"]:
		return false

	if threat.get("force_recall", false):
		return false

	if not _is_attack_close_to_winning(tree):
		return false

	return not is_emergency_threat_serious(tree, threat)


static func pull_emergency_defense_reinforcements(
	tree: SceneTree,
	intercept_position: Vector3
) -> void:
	if intercept_position == Vector3.ZERO:
		return

	var reinforcements: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		if is_hero_unit(unit as Node):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if (
			mission == EnemyUnitMission.Mission.RETREAT
			or mission == EnemyUnitMission.Mission.BUILD
			or mission == EnemyUnitMission.Mission.ECONOMY
		):
			continue

		reinforcements.append(unit)

	if reinforcements.is_empty():
		return

	command_attack_move(
		reinforcements,
		intercept_position,
		EnemyUnitMission.Mission.DEFEND
	)


static func build_defense_army(
	tree: SceneTree,
	threat_anchor: Vector3 = Vector3.ZERO
) -> Array:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return []

	var defense_army: Array = collect_living_combat_units(tree)
	return ensure_defense_hero_included(tree, defense_army, threat_anchor)


static func ensure_defense_hero_included(
	tree: SceneTree,
	defense_army: Array,
	threat_anchor: Vector3 = Vector3.ZERO
) -> Array:
	defense_army = NodeSafety.clean_node_array(defense_army)
	var hero: Hero = find_living_enemy_hero(tree)
	if hero == null or not is_instance_valid(hero):
		return defense_army

	if get_health_ratio(hero) < EMERGENCY_HERO_JOIN_HP_RATIO:
		return defense_army

	if defense_army.has(hero):
		return defense_army

	if threat_anchor != Vector3.ZERO:
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		var max_distance: float = DEFENSE_GATHER_MAX_DISTANCE + DEFENSE_HERO_EXTRA_GATHER_DISTANCE
		if (
			rally_position != Vector3.ZERO
			and horizontal_distance(hero.global_position, rally_position) > max_distance
			and horizontal_distance(hero.global_position, threat_anchor) > max_distance
		):
			return defense_army

	defense_army.append(hero)
	return defense_army


static func is_critical_defense_threat(threat: Dictionary) -> bool:
	var reason: StringName = threat.get("reason", &"")
	return (
		threat.get("force_recall", false)
		or threat.get("force_commit", false)
		or reason in [
			&"town_center",
			&"production",
			&"buildings",
			&"workers",
			&"base",
		]
	)


static func is_meaningful_player_threat_to_army(
	tree: SceneTree,
	army_units: Array,
	search_range: float
) -> bool:
	army_units = NodeSafety.clean_node_array(army_units)
	var army_center: Vector3 = compute_army_center(army_units)
	if army_center == Vector3.ZERO:
		return false

	var player_units: Array = collect_player_military_near(tree, army_center, search_range)
	if player_units.is_empty():
		return false

	var ai_strength: float = estimate_combat_strength(army_units)
	var player_strength: float = estimate_combat_strength(player_units)
	if player_strength >= ai_strength * 0.3:
		return true

	return player_units.size() >= 3


static func evaluate_defense_commitment(
	tree: SceneTree,
	defense_army: Array,
	threat_position: Vector3
) -> Dictionary:
	var defender_strength: float = estimate_combat_strength(defense_army)
	var threat_units: Array = collect_player_military_near(
		tree,
		threat_position,
		DEFENSE_THREAT_POWER_RANGE
	)
	var threat_strength: float = estimate_combat_strength(threat_units)

	return {
		"defender_power": int(defender_strength),
		"threat_power": int(threat_strength),
		"can_commit": should_defense_commit_attack(
			defense_army,
			int(defender_strength),
			int(threat_strength),
			_emergency_defense_active
		),
	}


static func should_defense_commit_attack(
	defense_army: Array,
	defender_power: int,
	threat_power: int,
	force_commit: bool = false
) -> bool:
	if force_commit:
		return not defense_army.is_empty()

	if defense_army.is_empty():
		return false

	if defender_power <= 0:
		return false

	var defender_strength: float = estimate_combat_strength(defense_army)
	var threat_strength: float = float(threat_power)
	if threat_strength <= 0.0:
		return true

	return evaluate_strength_gate(
		defender_strength,
		threat_strength,
		&"defend"
	).get("allowed", false)


static func resolve_defense_intercept_position(
	tree: SceneTree,
	threat: Dictionary,
	fallback_position: Vector3
) -> Vector3:
	var anchor_position: Vector3 = threat.get("intercept_position", fallback_position)
	if anchor_position == Vector3.ZERO:
		anchor_position = fallback_position

	return _resolve_player_threat_cluster_position(tree, anchor_position)


static func estimate_military_power(units: Array) -> int:
	return EnemyArmyForceMath.estimate_military_power(units)


static func estimate_player_threat_power_near(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> int:
	return estimate_military_power(
		collect_player_military_near(tree, position, search_range)
	)


static func collect_player_military_near(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> Array:
	var targets: Array = []
	var search_range_sq: float = search_range * search_range

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if node_variant == null or not is_instance_valid(node_variant):
				continue
			if not _is_player_military_unit(node_variant):
				continue

			if not node_variant is Node3D:
				continue

			var target: Node3D = node_variant as Node3D
			if horizontal_distance_squared(position, target.global_position) > search_range_sq:
				continue

			targets.append(node_variant)

	return targets


static func resolve_defense_hold_position(
	rally_position: Vector3,
	threat_position: Vector3
) -> Vector3:
	if rally_position == Vector3.ZERO:
		return threat_position

	if threat_position == Vector3.ZERO:
		return rally_position

	var offset: Vector3 = threat_position - rally_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		return rally_position

	var forward: Vector3 = offset.normalized()
	var hold_distance: float = minf(
		DEFENSE_HOLD_FORWARD_DISTANCE,
		offset.length() * 0.35
	)
	return rally_position + forward * hold_distance


static func is_enemy_army_under_attack(
	tree: SceneTree,
	army_units: Array,
	search_range: float
) -> bool:
	return is_meaningful_player_threat_to_army(tree, army_units, search_range)


static func find_living_player_command_center(tree: SceneTree) -> CommandCenter:
	return _resolve_living_player_command_center(tree)


static func horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	return _horizontal_distance(from_position, to_position)


static func horizontal_distance_squared(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length_squared()


static func resolve_enemy_rally_position(tree: SceneTree) -> Vector3:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_building(node as Building):
			return (node as Node3D).global_position + ARMY_RALLY_OFFSET

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if node is Node3D:
			return (node as Node3D).global_position

	return Vector3.ZERO


static func has_player_attack_targets(tree: SceneTree, enemy_base_position: Vector3) -> bool:
	if _find_player_military_near_position(tree, enemy_base_position, BASE_THREAT_DETECTION_RANGE) != null:
		return true

	if _resolve_living_player_command_center(tree) != null:
		return true

	if _find_nearest_living_player_building(tree, enemy_base_position) != null:
		return true

	if _find_nearest_living_player_unit(tree, enemy_base_position) != null:
		return true

	return false


static func resolve_attack_objective(tree: SceneTree, fallback_position: Vector3) -> Dictionary:
	if _finishing_mode_active:
		return resolve_finishing_attack_objective(tree, fallback_position)

	if EnemyAggression.should_prefer_town_hall_focus():
		return EnemyAggression.resolve_aggression_attack_objective(tree, fallback_position)

	if (
		_attack_wave_target_node != null
		and NodeSafety.is_alive_node(_attack_wave_target_node)
		and Time.get_ticks_msec() < _attack_wave_target_committed_until_msec
	):
		return {
			"node": _attack_wave_target_node,
			"position": _attack_wave_target_position,
		}

	## During aggression, do not chase mid-map armies — go for the base.
	if not EnemyAggression.is_aggression_mode_active():
		var exposed_army: Dictionary = _find_exposed_player_army_cluster(tree, fallback_position)
		if not exposed_army.is_empty():
			return {
				"node": exposed_army.get("node"),
				"position": exposed_army.get("position", fallback_position),
			}

	var production_building: Node3D = _find_player_production_building(tree, fallback_position)
	if production_building != null and not EnemyAggression.should_prefer_town_hall_focus():
		return {
			"node": production_building,
			"position": production_building.global_position,
		}

	var important_building: Node3D = _find_nearest_important_player_building(
		tree,
		fallback_position
	)
	if important_building != null and not EnemyAggression.is_aggression_mode_active():
		return {
			"node": important_building,
			"position": important_building.global_position,
		}

	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return {
			"node": command_center,
			"position": command_center.global_position,
		}

	var nearest_building: Node3D = _find_nearest_living_player_building(
		tree,
		fallback_position
	)
	if nearest_building != null:
		return {
			"node": nearest_building,
			"position": nearest_building.global_position,
		}

	var nearest_worker: Node3D = _find_nearest_living_player_worker(tree, fallback_position)
	if nearest_worker != null:
		var nearby_army: Array = collect_player_military_near(
			tree,
			nearest_worker.global_position,
			LOCAL_FIGHT_RADIUS
		)
		if nearby_army.size() >= EXPOSED_PLAYER_ARMY_MIN_UNITS:
			var cluster_position: Vector3 = compute_army_center(nearby_army)
			if cluster_position != Vector3.ZERO:
				return {
					"node": nearby_army[0] as Node3D,
					"position": cluster_position,
				}

		return {
			"node": nearest_worker,
			"position": nearest_worker.global_position,
		}

	if fallback_position != Vector3.ZERO:
		return {"node": null, "position": fallback_position}

	return {"node": null, "position": Vector3.ZERO}


static func resolve_wave_attack_destination(tree: SceneTree, enemy_base_position: Vector3) -> Vector3:
	return resolve_attack_objective(tree, enemy_base_position).get("position", Vector3.ZERO)


static func is_hero_healthy_enough_for_wave(hero) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	if not hero is Hero:
		return false

	return get_health_ratio(hero) >= HERO_WAVE_JOIN_HP_RATIO


static func is_hero_healthy_enough_for_creep(hero) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	if not hero is Hero:
		return false

	return get_health_ratio(hero) >= HERO_CREEP_JOIN_HP_RATIO


static func get_health_ratio(node) -> float:
	return EnemyArmyForceMath.get_health_ratio(node)


static func command_retreat_hero(hero, rally_position: Vector3) -> void:
	if not NodeSafety.is_alive_node(hero):
		return

	if not hero is Hero:
		return

	if not is_living_combat_unit(hero):
		return

	# Prefer full-group retreat whenever any non-hero combatants still exist.
	var tree: SceneTree = hero.get_tree() if hero is Node else null
	if tree != null:
		var non_hero: Array = collect_living_non_hero_combat_units(tree)
		if not non_hero.is_empty():
			initiate_group_retreat(tree, "Retreat: keep hero with army")
			return

	_cancel_unit_offensive_orders(hero)
	EnemyUnitMission.try_set_mission(hero, EnemyUnitMission.Mission.RETREAT)
	_issue_hold_at_rally(hero, rally_position)


static func _cancel_unit_offensive_orders(unit: Variant) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if (unit as Object).has_method("cancel_attack_move"):
		(unit as Object).call("cancel_attack_move")

	if (unit as Object).has_method("cancel_attack"):
		(unit as Object).call("cancel_attack")


static func command_attack_move(
	units: Array,
	destination: Vector3,
	mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.ATTACK
) -> bool:
	if mission == EnemyUnitMission.Mission.ATTACK and not _allow_hostile_engagement:
		## V2 owns ATTACK authority — legacy early-phase offense gates must not soft-lock.
		if not MilitaryAIConfig.is_v2_enabled():
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree != null and not can_launch_player_attack(tree):
				EnemyAIDebug.log_once(
					"player_attack_blocked",
					"Player attack blocked: %s" % get_player_offense_block_reason(tree)
				)
				return false

	if not _combat_orders_allowed(mission):
		return false

	units = filter_units_for_field_combat(units, mission)
	units = EnemyUnitMission.claim_units_for_mission(units, mission)
	if units.is_empty():
		return false

	return _issue_spaced_group_orders(units, destination, true, mission)


static func command_defend_position(units: Array, position: Vector3) -> void:
	command_attack_move(units, position, EnemyUnitMission.Mission.DEFEND)


static func command_retreat_to(units: Array, position: Vector3) -> void:
	units = EnemyUnitMission.claim_units_for_mission(units, EnemyUnitMission.Mission.RETREAT)
	if units.is_empty():
		return

	_issue_spaced_group_orders(
		units,
		position,
		false,
		EnemyUnitMission.Mission.RETREAT
	)


static func command_hold_at_rally(
	units: Array,
	rally_position: Vector3,
	mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.RALLY
) -> void:
	units = EnemyUnitMission.claim_units_for_mission(units, mission)
	if units.is_empty():
		return

	_issue_spaced_group_orders(units, rally_position, false, mission)


static func _issue_attack_move(unit: Variant, destination: Vector3) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if not (unit as Object).has_method("command_attack_move"):
		return

	# AI formation moves use FORMATION urgency so they respect repath cooldowns.
	(unit as Object).call("command_attack_move", destination, Unit.RepathUrgency.FORMATION)


static func _issue_spaced_group_orders(
	units: Array,
	center: Vector3,
	use_attack_move: bool,
	mission: EnemyUnitMission.Mission
) -> bool:
	units = NodeSafety.clean_and_dedupe_nodes(units)
	var commandable_units: Array = EnemyUnitMission.filter_commandable_units(units, mission)
	var ordered_units: Array = _order_units_for_formation(commandable_units)
	if ordered_units.is_empty():
		return false

	_last_squad_route_failure_reason = ""

	if _is_duplicate_group_order(ordered_units, center, mission, use_attack_move):
		PerfCounters.warn_duplicate_group_order()
		return true

	## Fresh Attack-Move younger than 1s must not be refreshed for soft formation drift.
	if (
		use_attack_move
		and not _active_group_order_signature.is_empty()
		and int(mission) == _active_group_order_mission
		and horizontal_distance(center, _active_group_order_dest) <= GROUP_ORDER_DEST_TOLERANCE
	):
		var age_sec: float = float(Time.get_ticks_msec() - _active_group_order_msec) / 1000.0
		if age_sec < GROUP_ORDER_MIN_REFRESH_SECONDS:
			PerfCounters.warn_duplicate_group_order()
			return true

	if MilitaryAIConfig.is_shared_squad_nav_enabled() and ordered_units.size() > 1:
		var squad_result: Dictionary = SharedSquadNavigation.issue_group_command(
			ordered_units,
			center,
			use_attack_move,
			int(mission),
			_group_order_generation + 1
		)
		if squad_result.get("handled", false):
			var route_ok: bool = VariantUtils.to_bool(squad_result.get("route_valid", false))
			var equiv_skip: bool = VariantUtils.to_bool(squad_result.get("equivalent_skip", false))
			if not route_ok and not equiv_skip:
				_last_squad_route_failure_reason = String(
					squad_result.get("route_failure_reason", "no_path")
				)
				## Do not record a success signature — allow controlled reissue cadence
				## (and director reevaluation) without falling through to direct formation.
				return false
			if equiv_skip:
				_record_group_order_signature(ordered_units, center, mission, use_attack_move)
				_last_squad_route_failure_reason = ""
				return true
			var squad_pending: Array = squad_result.get("pending_orders", [])
			_record_group_order_signature(ordered_units, center, mission, use_attack_move)
			_last_squad_route_failure_reason = ""
			if squad_pending.is_empty():
				return true
			var wrapped: Array = []
			for entry: Variant in squad_pending:
				if not entry is Dictionary:
					continue
				var order: Dictionary = entry
				var unit: Variant = _resolve_pending_order_unit(order)
				if not NodeSafety.is_alive_node(unit):
					continue
				var target: Vector3 = order.get("target", Vector3.ZERO)
				wrapped.append({
					"unit": unit,
					"unit_id": (unit as Node).get_instance_id(),
					"command_generation": int(order.get("command_generation", -1)),
					"squad_id": int(order.get("squad_id", -1)),
					"target": target,
					"use_attack_move": VariantUtils.to_bool(order.get("use_attack_move", use_attack_move)),
					"mission": order.get("mission", mission),
					"dedupe_key": _build_pending_order_dedupe_key(unit, mission, target),
					"priority": _mission_order_priority(mission),
				})
			var had_pending: bool = not _pending_group_orders.is_empty()
			_enqueue_pending_group_orders(wrapped)
			if not had_pending and not _issuing_group_order_batch:
				tick_group_order_batch(null)
			return true

	var move_targets: Array[Vector3] = _get_or_compute_formation_targets(
		ordered_units,
		center,
		use_attack_move
	)

	var pending_orders: Array = []
	for index: int in ordered_units.size():
		var unit: Variant = ordered_units[index]
		if not NodeSafety.is_alive_node(unit):
			continue

		var target: Vector3 = move_targets[index]
		var unit_node: Node3D = unit as Node3D
		if unit_node != null:
			var slot_distance: float = horizontal_distance(unit_node.global_position, target)
			if slot_distance <= FORMATION_SLOT_SKIP_DISTANCE:
				var is_stuck: bool = (
					unit_node.has_method("is_confirmed_stuck")
					and VariantUtils.to_bool(unit_node.call("is_confirmed_stuck"))
				)
				if not is_stuck:
					continue

		if not EnemyUnitMission.should_reissue_move_order(unit as Node, target, mission):
			continue

		pending_orders.append({
			"unit": unit,
			"target": target,
			"use_attack_move": use_attack_move,
			"mission": mission,
			"dedupe_key": _build_pending_order_dedupe_key(unit, mission, target),
			"priority": _mission_order_priority(mission),
		})

	if pending_orders.is_empty():
		# All units individually skipped — still record signature so AI does not
		# keep recomputing identical formation destinations every tick.
		_record_group_order_signature(ordered_units, center, mission, use_attack_move)
		_last_squad_route_failure_reason = ""
		return true

	_record_group_order_signature(ordered_units, center, mission, use_attack_move)
	_last_squad_route_failure_reason = ""
	var had_pending: bool = not _pending_group_orders.is_empty()
	_enqueue_pending_group_orders(pending_orders)
	# Never recurse into batch processing while a batch is already draining.
	if not had_pending and not _issuing_group_order_batch:
		tick_group_order_batch(null)
	return true


static func _build_pending_order_dedupe_key(
	unit: Variant,
	mission: EnemyUnitMission.Mission,
	destination: Vector3
) -> String:
	var unit_id: int = 0
	if NodeSafety.is_alive_node(unit):
		unit_id = (unit as Node).get_instance_id()
	var bx: int = int(floor(destination.x / PENDING_ORDER_DEST_BUCKET))
	var bz: int = int(floor(destination.z / PENDING_ORDER_DEST_BUCKET))
	return "%d|%d|%d|%d" % [unit_id, int(mission), bx, bz]


static func _resolve_pending_order_unit(order: Dictionary) -> Variant:
	var unit: Variant = order.get("unit")
	if NodeSafety.is_alive_node(unit):
		return unit
	if not order.has("unit_id"):
		return null
	var unit_id: int = int(order.get("unit_id", 0))
	if unit_id == 0:
		return null
	var resolved: Variant = instance_from_id(unit_id)
	if resolved == null or not is_instance_valid(resolved):
		return null
	if not resolved is Node:
		return null
	if (resolved as Node).is_queued_for_deletion():
		return null
	return resolved


static func _pending_order_unit_is_alive(order: Dictionary) -> bool:
	return NodeSafety.is_alive_node(_resolve_pending_order_unit(order))


static func _mission_order_priority(mission: EnemyUnitMission.Mission) -> int:
	## Lower = drained first. Emergency defend/retreat before formation refreshes.
	match mission:
		EnemyUnitMission.Mission.DEFEND:
			return 0
		EnemyUnitMission.Mission.RETREAT:
			return 1
		EnemyUnitMission.Mission.ATTACK:
			return 2
		EnemyUnitMission.Mission.CREEP:
			return 3
		_:
			return 4


static func _enqueue_pending_group_orders(new_orders: Array) -> void:
	if new_orders.is_empty():
		return
	var existing_keys: Dictionary = {}
	for entry: Variant in _pending_group_orders:
		if entry is Dictionary:
			var key: String = str((entry as Dictionary).get("dedupe_key", ""))
			if not key.is_empty():
				existing_keys[key] = true

	for entry: Variant in new_orders:
		if not entry is Dictionary:
			continue
		var order: Dictionary = entry
		var key: String = str(order.get("dedupe_key", ""))
		if not key.is_empty() and existing_keys.has(key):
			continue
		if not key.is_empty():
			existing_keys[key] = true
		_pending_group_orders.append(order)

	_pending_group_orders.sort_custom(func(a: Variant, b: Variant) -> bool:
		var pa: int = int((a as Dictionary).get("priority", 99)) if a is Dictionary else 99
		var pb: int = int((b as Dictionary).get("priority", 99)) if b is Dictionary else 99
		return pa < pb
	)
	PerfCounters.set_pending_group_orders(_pending_group_orders.size())


static func _build_group_order_signature(
	ordered_units: Array,
	center: Vector3,
	mission: EnemyUnitMission.Mission,
	use_attack_move: bool
) -> String:
	var unit_ids: Array[int] = []
	for unit: Variant in ordered_units:
		if NodeSafety.is_alive_node(unit):
			unit_ids.append((unit as Node).get_instance_id())
	unit_ids.sort()

	return "%d|%d|%d|%.1f|%.1f|%d" % [
		int(mission),
		1 if use_attack_move else 0,
		ordered_units.size(),
		center.x,
		center.z,
		hash(unit_ids),
	]


static func _is_duplicate_group_order(
	ordered_units: Array,
	center: Vector3,
	mission: EnemyUnitMission.Mission,
	use_attack_move: bool
) -> bool:
	if _active_group_order_signature.is_empty():
		return false

	var age_sec: float = float(Time.get_ticks_msec() - _active_group_order_msec) / 1000.0
	if age_sec > GROUP_ORDER_SIGNATURE_TTL_SECONDS and _pending_group_orders.is_empty():
		_active_group_order_signature = ""
		return false

	if int(mission) != _active_group_order_mission:
		return false

	if horizontal_distance(center, _active_group_order_dest) > GROUP_ORDER_DEST_TOLERANCE:
		return false

	var signature_new: String = _build_group_order_signature(
		ordered_units,
		_active_group_order_dest,
		mission,
		use_attack_move
	)
	return signature_new == _active_group_order_signature


static func _record_group_order_signature(
	ordered_units: Array,
	center: Vector3,
	mission: EnemyUnitMission.Mission,
	use_attack_move: bool
) -> void:
	_group_order_generation += 1
	_active_group_order_generation = _group_order_generation
	_active_group_order_dest = center
	_active_group_order_mission = int(mission)
	_active_group_order_msec = Time.get_ticks_msec()
	_active_group_order_signature = _build_group_order_signature(
		ordered_units,
		center,
		mission,
		use_attack_move
	)


static func _get_or_compute_formation_targets(
	ordered_units: Array,
	center: Vector3,
	use_attack_move: bool
) -> Array[Vector3]:
	var unit_ids: Array[int] = []
	for unit: Variant in ordered_units:
		if NodeSafety.is_alive_node(unit):
			unit_ids.append((unit as Node).get_instance_id())

	var now_msec: int = Time.get_ticks_msec()
	var cache_age_sec: float = float(now_msec - _formation_cache_msec) / 1000.0
	var army_mode_value: int = int(_army_mode)
	if (
		use_attack_move == _formation_cache_use_attack_move
		and unit_ids == _formation_cache_unit_ids
		and army_mode_value == _formation_cache_army_mode
		and horizontal_distance(center, _formation_cache_center) <= FORMATION_CACHE_DEST_THRESHOLD
		and _formation_cache_targets.size() == ordered_units.size()
		and cache_age_sec < FORMATION_CACHE_REFRESH_SECONDS
	):
		return _formation_cache_targets.duplicate()

	var start_usec: int = PerfCounters.begin_section()
	var move_targets: Array[Vector3] = (
		_compute_attack_formation_targets(ordered_units, center, FORMATION_SPACING)
		if use_attack_move
		else GroupMoveSpacing.compute_targets(
			center,
			ordered_units.size(),
			FORMATION_SPACING
		)
	)
	PerfCounters.end_section("Formation update", start_usec, ordered_units.size())

	_formation_cache_unit_ids = unit_ids
	_formation_cache_center = center
	_formation_cache_use_attack_move = use_attack_move
	_formation_cache_targets = move_targets.duplicate()
	_formation_cache_msec = now_msec
	_formation_cache_army_mode = army_mode_value
	return move_targets


static func tick_group_order_batch(_tree: SceneTree) -> void:
	if _pending_group_orders.is_empty():
		PerfCounters.set_pending_group_orders(0)
		return

	if _issuing_group_order_batch:
		return

	_issuing_group_order_batch = true
	var snapshot: Array = _pending_group_orders.duplicate()
	_pending_group_orders.clear()
	var next_index: int = _issue_group_order_batch(snapshot, 0)
	if next_index < snapshot.size():
		var remaining: Array = snapshot.slice(next_index)
		remaining.append_array(_pending_group_orders)
		_pending_group_orders = remaining
		PerfCounters.warn_order_budget_reached(MAX_GROUP_ORDERS_PER_FRAME)

	_issuing_group_order_batch = false
	PerfCounters.set_pending_group_orders(_pending_group_orders.size())


static func _issue_group_order_batch(orders: Array, start_index: int) -> int:
	var issued: int = 0
	var index: int = start_index

	while index < orders.size() and issued < MAX_GROUP_ORDERS_PER_FRAME:
		var entry: Dictionary = orders[index]
		var unit: Variant = _resolve_pending_order_unit(entry)
		var target: Vector3 = entry.get("target", Vector3.ZERO)
		var use_attack_move: bool = VariantUtils.to_bool(entry.get("use_attack_move", true))
		var mission: EnemyUnitMission.Mission = entry.get(
			"mission",
			EnemyUnitMission.Mission.ATTACK
		) as EnemyUnitMission.Mission
		index += 1

		if not NodeSafety.is_alive_node(unit):
			continue

		var command_generation: int = int(entry.get("command_generation", -1))
		var squad_id: int = int(entry.get("squad_id", -1))
		if command_generation >= 0 and squad_id >= 0:
			var squad_ctx: SquadNavContext = SharedSquadNavigation.get_squad_for_unit(unit)
			if (
				squad_ctx == null
				or squad_ctx.squad_id != squad_id
				or squad_ctx.command_generation != command_generation
			):
				continue

		if (
			use_attack_move
			and mission in [
				EnemyUnitMission.Mission.ATTACK,
				EnemyUnitMission.Mission.CREEP,
				EnemyUnitMission.Mission.DEFEND,
			]
			and entry.has("focus_objective")
		):
			var focus_objective_ref: Variant = entry.get("focus_objective")
			if NodeSafety.is_alive_node(focus_objective_ref) and focus_objective_ref is Node3D:
				var focus_objective: Node3D = focus_objective_ref as Node3D
				## Mission first so allows_combat_micro permits the hard focus path.
				EnemyUnitMission.try_set_mission(unit as Node, mission)
				_command_unit_focus_attack(unit, focus_objective)
				EnemyUnitMission.record_move_order(unit as Node, target, mission)
				EnemyArmyCommandTelemetry.record_order_issued()
				PerfCounters.record_ai_order()
				issued += 1
				continue

		if (
			use_attack_move
			and mission == EnemyUnitMission.Mission.ATTACK
			and _has_living_attack_building_objective()
		):
			var wave_objective_ref: Variant = _active_wave_objective
			if NodeSafety.is_alive_node(wave_objective_ref) and wave_objective_ref is Node3D:
				_command_unit_focus_attack(unit, wave_objective_ref as Node3D)
				EnemyUnitMission.try_set_mission(unit as Node, mission)
				EnemyUnitMission.record_move_order(unit as Node, target, mission)
				EnemyArmyCommandTelemetry.record_order_issued()
				PerfCounters.record_ai_order()
				issued += 1
				continue

		if use_attack_move:
			_issue_attack_move(unit, target)
			if mission in [EnemyUnitMission.Mission.ATTACK, EnemyUnitMission.Mission.CREEP]:
				log_ai_order(
					unit,
					"issue_group_order_batch",
					EnemyUnitMission.mission_to_label(mission),
					target,
					"field_combat"
				)
		else:
			_issue_hold_at_rally(unit, target)

		EnemyUnitMission.try_set_mission(unit as Node, mission)
		EnemyUnitMission.record_move_order(unit as Node, target, mission)
		EnemyArmyCommandTelemetry.record_order_issued()
		PerfCounters.record_ai_order()
		issued += 1

	return index


static func tick_perf_diagnostics(tree: SceneTree, delta: float) -> void:
	tick_mission_watchdog(tree, delta)
	if EnemyArmyCommandTelemetry.tick_overlay_timer(delta):
		_refresh_perf_overlay_status(tree)

	if not EnemyArmyCommandTelemetry.tick_perf_diag_timer(delta, DEBUG_COMBAT_AI):
		return

	_refresh_combat_units_cache_if_needed(tree)
	var worker_count: int = CombatTargetValidation.get_cached_group_nodes(
		tree,
		ENEMY_WORKERS_GROUP
	).size()
	var building_count: int = CombatTargetValidation.get_cached_group_nodes(
		tree,
		BUILDINGS_GROUP
	).size()
	var orders_interval: int = EnemyArmyCommandTelemetry.take_orders_issued_since_diag()

	print(
		(
			"AI PERF: units=%d workers=%d buildings=%d combat_group=%d "
			+ "queued_orders=%d pending_group_orders=%d orders_interval=%d mode=%s"
		)
		% [
			_main_army_cache.size(),
			worker_count,
			building_count,
			CombatTargetValidation.get_cached_group_nodes(tree, ENEMY_COMBAT_GROUP).size(),
			0,
			_pending_group_orders.size(),
			orders_interval,
			ArmyMode.keys()[_army_mode],
		]
	)


static func get_executable_mission() -> ExecutableMission:
	return _exec_mission


static func get_executable_mission_reason() -> String:
	return _exec_transition_reason


static func get_executable_objective_position() -> Vector3:
	return _exec_objective_position


static func get_executable_order_label() -> String:
	return _exec_order_label


static func is_creeping_executable_active() -> bool:
	return _exec_mission == ExecutableMission.CREEPING


static func executable_mission_to_label(mission: ExecutableMission) -> String:
	match mission:
		ExecutableMission.CREEPING:
			return "CREEPING"
		ExecutableMission.ATTACK_PLAYER:
			return "ATTACK_PLAYER"
		ExecutableMission.LETHAL_PUSH:
			return "LETHAL_PUSH"
		ExecutableMission.DEFEND:
			return "DEFEND"
		ExecutableMission.EMERGENCY_DEFEND:
			return "EMERGENCY_DEFEND"
		ExecutableMission.REGROUP:
			return "REGROUP"
		ExecutableMission.RETREAT:
			return "RETREAT"
		ExecutableMission.ASSEMBLE:
			return "ASSEMBLE"
		ExecutableMission.IDLE:
			return "IDLE"
		_:
			return "NONE"


static func set_executable_mission(
	mission: ExecutableMission,
	reason: String,
	objective_node: Node3D = null,
	objective_position: Vector3 = Vector3.ZERO,
	objective_name: String = "",
	order_label: String = "",
	squad: Array = [],
	camp_reserved: bool = false
) -> void:
	var now_msec: int = Time.get_ticks_msec()
	var changed: bool = mission != _exec_mission
	var objective_changed: bool = false
	if objective_node != null and is_instance_valid(objective_node):
		objective_changed = (
			_exec_objective_node == null
			or not is_instance_valid(_exec_objective_node)
			or _exec_objective_node.get_instance_id() != objective_node.get_instance_id()
		)
	elif _exec_objective_node != null:
		objective_changed = true

	_exec_mission = mission
	_exec_transition_reason = reason
	_exec_order_label = order_label
	_exec_camp_reserved = camp_reserved
	_exec_objective_name = objective_name
	if objective_node != null and is_instance_valid(objective_node):
		_exec_objective_node = objective_node
		if objective_position == Vector3.ZERO and objective_node is Node3D:
			_exec_objective_position = objective_node.global_position
		else:
			_exec_objective_position = objective_position
	else:
		_exec_objective_node = null
		_exec_objective_position = objective_position

	_exec_squad_ids.clear()
	for unit_variant: Variant in NodeSafety.clean_node_array(squad):
		if NodeSafety.is_alive_node(unit_variant):
			_exec_squad_ids.append((unit_variant as Node).get_instance_id())

	if changed or objective_changed:
		_exec_mission_start_msec = now_msec
		_exec_last_progress_msec = now_msec
		_exec_last_distance = -1.0
		_exec_watchdog_refreshed = false
		EnemyAIDebug.log_once(
			"exec_mission",
			"MISSION: %s | Reason: %s" % [executable_mission_to_label(mission), reason]
		)
	_sync_player_state_identity()


static func clear_executable_mission(reason: String = "") -> void:
	set_executable_mission(
		ExecutableMission.IDLE,
		reason if not reason.is_empty() else "cleared",
		null,
		Vector3.ZERO,
		"",
		"",
		[],
		false
	)


static func _clear_executable_mission_state(reason: String) -> void:
	_exec_mission = ExecutableMission.NONE
	_exec_objective_node = null
	_exec_objective_position = Vector3.ZERO
	_exec_objective_name = ""
	_exec_mission_start_msec = 0
	_exec_last_progress_msec = 0
	_exec_last_distance = -1.0
	_exec_squad_ids.clear()
	_exec_order_label = ""
	_exec_transition_reason = reason
	_exec_camp_reserved = false
	_exec_watchdog_timer = 0.0
	_exec_watchdog_refreshed = false
	_exec_last_report = ""
	_allow_hostile_engagement = false
	EnemyArmyCommandTelemetry.clear_issued_order()
	_sync_player_state_identity()


static func note_mission_order(order_label: String, destination: Vector3 = Vector3.ZERO) -> void:
	if not order_label.is_empty():
		_exec_order_label = order_label
	if destination != Vector3.ZERO:
		_exec_objective_position = destination
	var now_msec: int = Time.get_ticks_msec()
	_exec_last_progress_msec = now_msec
	EnemyArmyCommandTelemetry.note_issued_order(
		order_label,
		destination,
		_exec_order_label,
		_exec_objective_position
	)
	_sync_player_state_identity()


static func note_mission_progress(
	army_center: Vector3,
	in_combat: bool = false,
	units_alive: int = -1
) -> void:
	if _exec_mission in [ExecutableMission.NONE, ExecutableMission.IDLE]:
		return

	var now_msec: int = Time.get_ticks_msec()
	if in_combat:
		_exec_last_progress_msec = now_msec
		_exec_watchdog_refreshed = false
		return

	if units_alive == 0:
		return

	if army_center == Vector3.ZERO or _exec_objective_position == Vector3.ZERO:
		return

	var distance: float = horizontal_distance(army_center, _exec_objective_position)
	if _exec_last_distance < 0.0:
		_exec_last_distance = distance
		_exec_last_progress_msec = now_msec
		return

	if distance < _exec_last_distance - MISSION_PROGRESS_DISTANCE_EPSILON:
		_exec_last_distance = distance
		_exec_last_progress_msec = now_msec
		_exec_watchdog_refreshed = false
	elif distance <= _exec_last_distance:
		_exec_last_distance = distance


static func get_seconds_since_mission_progress() -> float:
	if _exec_last_progress_msec <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - _exec_last_progress_msec) / 1000.0


static func get_authoritative_mission_report(tree: SceneTree) -> String:
	_sanitize_executable_objective()
	var mission_label: String = executable_mission_to_label(_exec_mission)
	if _exec_mission == ExecutableMission.NONE:
		mission_label = _derive_display_mission_from_mode()

	var parts: PackedStringArray = PackedStringArray([
		"MISSION: %s" % mission_label,
	])

	if not _exec_objective_name.is_empty():
		if _exec_mission == ExecutableMission.CREEPING:
			parts.append("Camp: %s" % _exec_objective_name)
		else:
			parts.append("Target: %s" % _exec_objective_name)

	var army_center: Vector3 = Vector3.ZERO
	if tree != null:
		army_center = compute_army_center(collect_living_combat_units(tree))
	if army_center != Vector3.ZERO and _exec_objective_position != Vector3.ZERO:
		parts.append(
			"Distance: %.1f" % horizontal_distance(army_center, _exec_objective_position)
		)

	if _exec_mission not in [ExecutableMission.NONE, ExecutableMission.IDLE]:
		parts.append("Progress: %.1fs" % get_seconds_since_mission_progress())

	if not _exec_order_label.is_empty():
		parts.append("Order: %s" % _exec_order_label)

	if _exec_mission == ExecutableMission.CREEPING:
		parts.append("Reserve: %s" % ("yes" if _exec_camp_reserved else "no"))

	if not _exec_transition_reason.is_empty():
		parts.append("Reason: %s" % _exec_transition_reason)

	var report: String = " | ".join(parts)
	_exec_last_report = report
	return report


static func _derive_display_mission_from_mode() -> String:
	match _army_mode:
		ArmyMode.ATTACKING:
			return "ATTACK_PLAYER"
		ArmyMode.DEFENDING:
			return "EMERGENCY_DEFEND" if _emergency_defense_active else "DEFEND"
		ArmyMode.INTERCEPTING:
			return "DEFEND"
		ArmyMode.RETREATING:
			return "RETREAT"
		ArmyMode.REGROUPING:
			return "REGROUP"
		ArmyMode.ASSEMBLING:
			return "ASSEMBLE"
		ArmyMode.CREEPING:
			## Never claim CREEPING from mode alone — requires executable confirmation.
			return "IDLE"
		_:
			return "IDLE"


static func _sanitize_executable_objective() -> void:
	if _exec_objective_node != null and not is_instance_valid(_exec_objective_node):
		_exec_objective_node = null
		if _exec_mission == ExecutableMission.CREEPING:
			_exec_camp_reserved = false


static func validate_creeping_mission(
	tree: SceneTree,
	camp: Node3D,
	reserved_camp_id: int,
	army_center: Vector3,
	has_active_order: bool,
	in_combat: bool
) -> Dictionary:
	if not NodeSafety.is_alive_node(camp):
		return {"valid": false, "reason": "null or dead camp"}

	if reserved_camp_id == 0 or camp.get_instance_id() != reserved_camp_id:
		return {"valid": false, "reason": "camp reservation expired"}

	if army_center == Vector3.ZERO:
		return {"valid": false, "reason": "no army"}

	var player_cc: CommandCenter = find_living_player_command_center(tree)
	if player_cc != null:
		var dist_player: float = horizontal_distance(army_center, player_cc.global_position)
		var dist_camp: float = horizontal_distance(army_center, camp.global_position)
		if (
			dist_player <= HOSTILE_TERRITORY_BASE_RANGE
			and dist_camp > CAMP_ENGAGEMENT_PROXY
		):
			return {"valid": false, "reason": "army near player base with no route to camp"}

	if not has_active_order and not in_combat:
		## Allow brief gaps between reissues; watchdog handles sustained stalls.
		if get_seconds_since_mission_progress() > MISSION_PROGRESS_STALL_SECONDS * 0.5:
			return {"valid": false, "reason": "no army order"}

	return {"valid": true, "reason": ""}


## Proxy constant kept local so creep manager engagement radius need not be imported.
const CAMP_ENGAGEMENT_PROXY := 26.0


static func is_army_in_hostile_territory(
	tree: SceneTree,
	army_center: Vector3,
	rally_position: Vector3 = Vector3.ZERO
) -> bool:
	if army_center == Vector3.ZERO:
		return false

	var player_cc: CommandCenter = find_living_player_command_center(tree)
	if player_cc == null:
		return false

	var dist_player: float = horizontal_distance(army_center, player_cc.global_position)
	if dist_player <= HOSTILE_TERRITORY_BASE_RANGE:
		return true

	if rally_position == Vector3.ZERO:
		rally_position = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	var dist_rally: float = horizontal_distance(army_center, rally_position)
	return dist_player + 12.0 < dist_rally


static func resolve_hostile_territory_target(
	tree: SceneTree,
	from_position: Vector3
) -> Dictionary:
	if from_position == Vector3.ZERO:
		return {}

	## 1) Dangerous nearby military
	var military: Array = collect_player_military_near(
		tree,
		from_position,
		HOSTILE_TERRITORY_ENGAGE_RANGE
	)
	var best_military: Node3D = null
	var best_military_score: float = -INF
	for unit_variant: Variant in military:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Node3D:
			continue
		var unit: Node3D = unit_variant as Node3D
		var score: float = get_unit_type_strength_weight(unit as Node) * 100.0
		score -= horizontal_distance(from_position, unit.global_position)
		if unit is Hero:
			score += 40.0
		if score > best_military_score:
			best_military_score = score
			best_military = unit
	if best_military != null:
		var label: String = "PlayerHero" if best_military is Hero else "PlayerMilitary"
		return {
			"node": best_military,
			"position": best_military.global_position,
			"name": label,
		}

	## 2) Nearby towers (prefer those within engagement range of the army)
	var best_tower: Tower = null
	var best_tower_distance: float = INF
	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		BUILDINGS_GROUP
	):
		if not NodeSafety.is_alive_node(node_variant) or not node_variant is Tower:
			continue
		if not CombatTargetValidation.is_player_selectable_building(node_variant as Node):
			continue
		if not _is_living_building(node_variant as Building):
			continue
		var tower: Tower = node_variant as Tower
		var tower_distance: float = horizontal_distance(from_position, tower.global_position)
		if tower_distance > HOSTILE_TERRITORY_ENGAGE_RANGE:
			continue
		if tower_distance < best_tower_distance:
			best_tower_distance = tower_distance
			best_tower = tower
	if best_tower != null:
		return {
			"node": best_tower,
			"position": best_tower.global_position,
			"name": "Tower",
		}

	## 3) Main Town Hall / Command Center
	var command_center: CommandCenter = find_living_player_command_center(tree)
	if command_center != null:
		return {
			"node": command_center,
			"position": command_center.global_position,
			"name": "MainCC",
		}

	## 4) Production buildings
	var production: Node3D = _find_player_production_building(tree, from_position)
	if production != null:
		return {
			"node": production,
			"position": production.global_position,
			"name": production.name,
		}

	## 5) Workers
	var worker: Node3D = _find_nearest_living_player_worker(tree, from_position)
	if worker != null:
		return {
			"node": worker,
			"position": worker.global_position,
			"name": "Worker",
		}

	## 6) Any other building
	var building: Node3D = _find_nearest_living_player_building(tree, from_position)
	if building != null:
		return {
			"node": building,
			"position": building.global_position,
			"name": building.name,
		}

	return {}


static func is_army_strong_enough_for_hostile_push(
	tree: SceneTree,
	units: Array,
	army_center: Vector3
) -> Dictionary:
	var ai_strength: float = estimate_combat_strength(units)
	var player_strength: float = get_effective_player_strength_at(
		tree,
		army_center,
		HOSTILE_TERRITORY_ENGAGE_RANGE
	)
	var ratio: float = ai_strength / maxf(player_strength, 1.0)
	var lethal: bool = (
		ratio >= HOSTILE_TERRITORY_LETHAL_RATIO
		or EnemyAggression.get_lethal_score() >= 70.0
		or EnemyAggression.get_confidence() >= EnemyAggression.Confidence.HIGH
	)
	return {
		"allowed": ratio >= HOSTILE_TERRITORY_STRENGTH_RATIO or lethal or player_strength <= 0.0,
		"lethal": lethal,
		"ratio": ratio,
		"ai_strength": ai_strength,
		"player_strength": player_strength,
	}


static func handle_hostile_territory_idle(
	tree: SceneTree,
	units: Array,
	army_center: Vector3,
	reason: String = "army in hostile territory"
) -> bool:
	units = NodeSafety.clean_node_array(units)
	units = filter_units_for_field_combat(units, EnemyUnitMission.Mission.ATTACK)
	if units.is_empty() or army_center == Vector3.ZERO:
		return false

	if is_defense_blocking_offense() or get_army_mode() == ArmyMode.RETREATING:
		return false

	var strength: Dictionary = is_army_strong_enough_for_hostile_push(
		tree,
		units,
		army_center
	)
	if not strength.get("allowed", false):
		return false

	var target: Dictionary = resolve_hostile_territory_target(tree, army_center)
	var destination: Vector3 = target.get("position", Vector3.ZERO)
	if destination == Vector3.ZERO:
		var player_cc: CommandCenter = find_living_player_command_center(tree)
		if player_cc != null:
			destination = player_cc.global_position
			target = {"node": player_cc, "position": destination, "name": "MainCC"}
	if destination == Vector3.ZERO:
		return false

	var lethal: bool = VariantUtils.to_bool(strength.get("lethal", false))
	var mission: ExecutableMission = (
		ExecutableMission.LETHAL_PUSH if lethal else ExecutableMission.ATTACK_PLAYER
	)
	var objective_node: Node3D = target.get("node") as Node3D
	var objective_name: String = String(target.get("name", "HostileTarget"))

	_allow_hostile_engagement = true
	var issued: bool = false
	if try_claim_army_mode(ArmyMode.ATTACKING, true):
		EnemyUnitMission.set_main_army_mission(
			EnemyUnitMission.Mission.ATTACK,
			reason
		)
		request_strategic_state(StrategicState.ATTACKING, reason)
		set_executable_mission(
			mission,
			reason,
			objective_node,
			destination,
			objective_name,
			"attack-move",
			units,
			false
		)
		with_authorized_orders(func() -> void:
			command_attack_move(units, destination, EnemyUnitMission.Mission.ATTACK)
		)
		note_mission_order("attack-move", destination)
		begin_fight_tracking(units, army_center)
		issued = true
		EnemyAIDebug.log_once(
			"hostile_territory",
			"Hostile territory attack -> %s (%s)" % [objective_name, reason]
		)
	_allow_hostile_engagement = false
	_sync_player_state_identity()
	return issued


static func refresh_stalled_mission_order(tree: SceneTree) -> bool:
	if _exec_objective_position == Vector3.ZERO:
		return false

	var units: Array = []
	if not _exec_squad_ids.is_empty():
		for unit_id: int in _exec_squad_ids:
			var node: Object = instance_from_id(unit_id)
			if NodeSafety.is_alive_node(node):
				units.append(node)
	if units.is_empty():
		units = collect_living_combat_units(tree)
	units = NodeSafety.clean_node_array(units)
	if units.is_empty():
		return false

	var mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.ATTACK
	var mode: ArmyMode = ArmyMode.ATTACKING
	match _exec_mission:
		ExecutableMission.CREEPING:
			mission = EnemyUnitMission.Mission.CREEP
			mode = ArmyMode.CREEPING
		ExecutableMission.DEFEND, ExecutableMission.EMERGENCY_DEFEND:
			mission = EnemyUnitMission.Mission.DEFEND
			mode = ArmyMode.DEFENDING
		ExecutableMission.RETREAT:
			with_authorized_orders(func() -> void:
				command_retreat_to(units, _exec_objective_position)
			)
			note_mission_order("retreat-refresh", _exec_objective_position)
			return true
		ExecutableMission.REGROUP, ExecutableMission.ASSEMBLE:
			with_authorized_orders(func() -> void:
				command_hold_at_rally(units, _exec_objective_position)
			)
			note_mission_order("hold-refresh", _exec_objective_position)
			return true
		ExecutableMission.ATTACK_PLAYER, ExecutableMission.LETHAL_PUSH:
			_allow_hostile_engagement = true
		_:
			return false

	var ok: bool = issue_group_combat_move(
		tree,
		units,
		_exec_objective_position,
		mission,
		mode,
		_allow_hostile_engagement
	)
	_allow_hostile_engagement = false
	_sync_player_state_identity()
	if ok:
		note_mission_order("%s-refresh" % _exec_order_label, _exec_objective_position)
	return ok


static func tick_mission_watchdog(tree: SceneTree, delta: float) -> void:
	_exec_watchdog_timer += delta
	if _exec_watchdog_timer < MISSION_WATCHDOG_INTERVAL_SECONDS:
		return
	_exec_watchdog_timer = 0.0

	_sanitize_executable_objective()
	if _exec_mission in [
		ExecutableMission.NONE,
		ExecutableMission.IDLE,
		ExecutableMission.ASSEMBLE,
		ExecutableMission.REGROUP,
	]:
		_maybe_recover_idle_army(tree)
		return

	if is_defense_blocking_offense() or get_army_mode() == ArmyMode.RETREATING:
		return

	var units: Array = collect_living_combat_units(tree)
	units = NodeSafety.clean_node_array(units)
	var army_center: Vector3 = compute_army_center(units)
	var in_combat: bool = is_enemy_army_under_attack(
		tree,
		units,
		LOCAL_FIGHT_RADIUS
	)
	note_mission_progress(army_center, in_combat, units.size())

	if get_seconds_since_mission_progress() < MISSION_PROGRESS_STALL_SECONDS:
		return

	## One safe refresh, then cancel and fall back.
	if not _exec_watchdog_refreshed:
		_exec_watchdog_refreshed = true
		if refresh_stalled_mission_order(tree):
			_exec_last_progress_msec = Time.get_ticks_msec()
			EnemyAIDebug.log_once(
				"mission_watchdog",
				"Mission watchdog refreshed order (%s)" % executable_mission_to_label(_exec_mission)
			)
			return

	_resolve_stalled_mission_fallback(tree, units, army_center)


static func _resolve_stalled_mission_fallback(
	tree: SceneTree,
	units: Array,
	army_center: Vector3
) -> void:
	var stalled_mission: ExecutableMission = _exec_mission
	var reason: String = "mission stalled (%s)" % executable_mission_to_label(stalled_mission)

	## 1) Emergency defense already owns higher priority elsewhere.
	if is_emergency_defense_active():
		return

	## 2) Nearby hostile / hostile territory push
	if army_center != Vector3.ZERO:
		if handle_hostile_territory_idle(tree, units, army_center, reason):
			return
		var nearby: Array = collect_player_military_near(
			tree,
			army_center,
			HOSTILE_TERRITORY_ENGAGE_RANGE
		)
		if not nearby.is_empty():
			var fight_dest: Vector3 = compute_army_center(nearby)
			if fight_dest != Vector3.ZERO and handle_hostile_territory_idle(
				tree,
				units,
				army_center,
				"attack nearby hostile"
			):
				return

	## 3) Lethal push if player is weak (phase-gated unless already hostile)
	if (
		can_launch_player_attack(tree)
		and EnemyAggression.get_confidence() >= EnemyAggression.Confidence.HIGH
	):
		var objective: Dictionary = resolve_attack_objective(
			tree,
			resolve_enemy_rally_position(tree)
		)
		var dest: Vector3 = objective.get("position", Vector3.ZERO)
		if dest != Vector3.ZERO:
			if issue_group_combat_move(
				tree,
				units,
				dest,
				EnemyUnitMission.Mission.ATTACK,
				ArmyMode.ATTACKING,
				true
			):
				set_executable_mission(
					ExecutableMission.LETHAL_PUSH,
					reason,
					objective.get("node") as Node3D,
					dest,
					"LethalTarget",
					"attack-move",
					units,
					false
				)
				return

	## 4/5/6) Leave creeping / regroup / defend at rally
	clear_executable_mission(reason)
	var rally: Vector3 = resolve_enemy_rally_position(tree)
	if rally != Vector3.ZERO:
		if try_claim_army_mode(ArmyMode.REGROUPING):
			set_executable_mission(
				ExecutableMission.REGROUP,
				reason,
				null,
				rally,
				"Rally",
				"move",
				units,
				false
			)
			with_authorized_orders(func() -> void:
				command_regroup_at_rally(tree, rally)
			)
			EnemyUnitMission.set_main_army_mission(
				EnemyUnitMission.Mission.RALLY,
				reason
			)


static func _maybe_recover_idle_army(tree: SceneTree) -> void:
	if is_defense_blocking_offense():
		return
	if is_attack_wave_active():
		return
	if get_army_mode() in [
		ArmyMode.ASSEMBLING,
		ArmyMode.RETREATING,
		ArmyMode.DEFENDING,
		ArmyMode.INTERCEPTING,
		ArmyMode.ATTACKING,
	]:
		return

	var units: Array = collect_living_combat_units(tree)
	units = NodeSafety.clean_node_array(units)
	if units.size() < CREEP_MIN_NON_HERO_UNITS:
		return

	var army_center: Vector3 = compute_army_center(units)
	if army_center == Vector3.ZERO:
		return

	## Idle army in hostile territory must never stand still.
	if is_army_in_hostile_territory(tree, army_center):
		if handle_hostile_territory_idle(
			tree,
			units,
			army_center,
			"idle army in hostile territory"
		):
			return
		initiate_group_retreat(tree, "weak idle army in hostile territory")
		return

	## Idle with nearby player threats → attack-move
	var nearby: Array = collect_player_military_near(
		tree,
		army_center,
		HOSTILE_TERRITORY_ENGAGE_RANGE
	)
	if not nearby.is_empty():
		handle_hostile_territory_idle(tree, units, army_center, "idle army near hostiles")


static func _refresh_perf_overlay_status(_tree: SceneTree) -> void:
	PerfCounters.set_combat_group_size(
		NodeSafety.clean_node_array(_main_army_cache).size()
	)
	PerfCounters.set_pending_group_orders(_pending_group_orders.size())
	var report: String = get_authoritative_mission_report(_tree)
	PerfCounters.set_ai_status(
		PerfCounters.get_ai_phase(),
		ArmyMode.keys()[_army_mode],
		executable_mission_to_label(_exec_mission)
	)
	PerfCounters.set_ai_mission_detail(report)

static func _order_units_for_formation(units: Array) -> Array:
	var eligible: Array = FormationManager.collect_eligible_units(units, true)
	var heroes: Array = FormationManager.collect_heroes(units)
	eligible.sort_custom(UnitFormationRole.compare_units_front_first)
	heroes.sort_custom(_compare_units_by_instance_id)
	var ordered_units: Array = []
	ordered_units.append_array(eligible)
	ordered_units.append_array(heroes)
	return ordered_units


static func _compare_units_by_instance_id(a: Variant, b: Variant) -> bool:
	var a_id: int = (a as Node).get_instance_id() if NodeSafety.is_alive_node(a) else 0
	var b_id: int = (b as Node).get_instance_id() if NodeSafety.is_alive_node(b) else 0
	return a_id < b_id


static func _compute_attack_formation_targets(
	units: Array,
	destination: Vector3,
	spacing: float
) -> Array[Vector3]:
	if units.is_empty():
		return []

	var mode_name: StringName = StringName(ArmyMode.keys()[_army_mode])
	var defending: bool = _army_mode in [
		ArmyMode.DEFENDING,
		ArmyMode.INTERCEPTING,
		ArmyMode.REGROUPING,
	]
	var targets: Array[Vector3] = FormationManager.ai_issue_move(
		units,
		destination,
		true,
		mode_name,
		defending
	)
	if targets.size() == units.size():
		return targets

	# Fallback to legacy line layout if AI formation returned mismatched size.
	return _compute_legacy_line_formation_targets(units, destination, spacing)


static func _compute_legacy_line_formation_targets(
	units: Array,
	destination: Vector3,
	spacing: float
) -> Array[Vector3]:
	if units.is_empty():
		return []

	var army_center: Vector3 = compute_army_center(units)
	var forward: Vector3 = destination - army_center
	forward.y = 0.0
	# Near the objective the live army center is noisy — freeze a stable world axis.
	if forward.length_squared() < 4.0:
		forward = Vector3(0.0, 0.0, 1.0 if destination.z >= army_center.z else -1.0)
	else:
		forward = forward.normalized()

	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var melee_count: int = 0
	var ranged_count: int = 0
	var hero_count: int = 0
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_hero_unit(unit as Node):
			hero_count += 1
		elif unit is Archer or unit is CavalryArcher or unit is Cannon:
			ranged_count += 1
		else:
			melee_count += 1

	var melee_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		destination,
		right,
		melee_count,
		spacing
	)
	var ranged_row_center: Vector3 = (
		destination - forward * spacing * RANGED_ROW_DEPTH_MULTIPLIER
	)
	var ranged_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		ranged_row_center,
		right,
		ranged_count,
		spacing
	)
	var hero_row_center: Vector3 = destination - forward * spacing * HERO_ROW_DEPTH_MULTIPLIER
	var hero_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		hero_row_center,
		right,
		hero_count,
		spacing
	)

	var targets: Array[Vector3] = []
	var melee_index: int = 0
	var ranged_index: int = 0
	var hero_index: int = 0

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			targets.append(destination)
			continue

		var candidate: Vector3 = destination
		if is_hero_unit(unit as Node):
			candidate = hero_targets[hero_index]
			hero_index += 1
		elif unit is Archer or unit is CavalryArcher or unit is Cannon:
			candidate = ranged_targets[ranged_index]
			ranged_index += 1
		else:
			candidate = melee_targets[melee_index]
			melee_index += 1

		targets.append(
			GroupMoveSpacing.resolve_formation_position(
				candidate,
				destination,
				spacing
			)
		)

	return targets


static func compute_army_center(units: Array) -> Vector3:
	units = NodeSafety.clean_node_array(units)
	if units.is_empty():
		return Vector3.ZERO

	var position_sum: Vector3 = Vector3.ZERO
	var count: int = 0

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not unit is Node3D:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		position_sum += (unit as Node3D).global_position
		count += 1

	if count == 0:
		return Vector3.ZERO

	return position_sum / float(count)


static func _issue_hold_at_rally(unit: Variant, rally_position: Vector3) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if (unit as Object).has_method("set_movement_target"):
		(unit as Object).call("set_movement_target", rally_position, Unit.RepathUrgency.FORMATION)
		return

	_issue_attack_move(unit, rally_position)


static func _build_defense_threat_result(
	intercept_position: Vector3,
	reason: StringName,
	force_commit: bool = false
) -> Dictionary:
	return {
		"threatened": true,
		"intercept_position": intercept_position,
		"reason": reason,
		"force_commit": force_commit,
	}


static func _assign_reinforcement_to_emergency_defense(tree: SceneTree, unit) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	var objective_position: Vector3 = get_emergency_defense_objective()
	if objective_position == Vector3.ZERO:
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		if rally_position == Vector3.ZERO:
			return
		if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.RALLY):
			return
		command_hold_at_rally([unit], rally_position, EnemyUnitMission.Mission.RALLY)
		return

	if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.DEFEND):
		return

	command_attack_move([unit], objective_position, EnemyUnitMission.Mission.DEFEND)


static func _is_important_enemy_production_building(building) -> bool:
	if building == null or not is_instance_valid(building):
		return false

	return (
		building is Barracks
		or building is HeroAltar
		or building is Blacksmith
		or building is Shop
	)


static func _is_important_enemy_building(building) -> bool:
	if building == null or not is_instance_valid(building):
		return false

	return building is CommandCenter or _is_important_enemy_production_building(building)


static func _evaluate_emergency_command_center_threat(tree: SceneTree) -> Dictionary:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is CommandCenter or not _is_living_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: CommandCenter = node as CommandCenter
		var building_position: Vector3 = (node as Node3D).global_position
		var live_attacker: Node3D = _resolve_live_building_attacker(
			tree,
			building,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if live_attacker != null:
			return _build_emergency_threat_result(
				_resolve_player_threat_cluster_position(
					tree,
					live_attacker.global_position
				),
				&"town_center",
				true
			)

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if nearby_threat != null:
			return _build_emergency_threat_result(
				_resolve_player_threat_cluster_position(tree, nearby_threat.global_position),
				&"town_center",
				true
			)

	return {"threatened": false}


static func _evaluate_emergency_production_building_threat(tree: SceneTree) -> Dictionary:
	var closest_attacker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not _is_important_enemy_production_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: Building = node as Building
		var building_position: Vector3 = (node as Node3D).global_position
		var live_attacker: Node3D = _resolve_live_building_attacker(
			tree,
			building,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if live_attacker != null:
			var distance: float = _horizontal_distance(
				building_position,
				live_attacker.global_position
			)
			if distance < closest_distance:
				closest_distance = distance
				closest_attacker = live_attacker
			continue

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if nearby_threat == null:
			continue

		var nearby_distance: float = _horizontal_distance(
			building_position,
			nearby_threat.global_position
		)
		if nearby_distance < closest_distance:
			closest_distance = nearby_distance
			closest_attacker = nearby_threat

	if closest_attacker != null:
		return _build_emergency_threat_result(
			_resolve_player_threat_cluster_position(tree, closest_attacker.global_position),
			&"production",
			true
		)

	return {"threatened": false}


static func _evaluate_emergency_player_hero_threat(
	tree: SceneTree,
	rally_position: Vector3
) -> Dictionary:
	for node_variant: Variant in tree.get_nodes_in_group(HEROES_GROUP):
		if node_variant == null or not is_instance_valid(node_variant):
			continue
		if not node_variant is Hero or not _is_player_military_unit(node_variant):
			continue

		if not node_variant is Node3D:
			continue

		var hero_position: Vector3 = (node_variant as Node3D).global_position
		if _horizontal_distance(rally_position, hero_position) > CORE_BASE_DEFENSE_RADIUS:
			continue

		return _build_emergency_threat_result(
			_resolve_player_threat_cluster_position(tree, hero_position),
			&"player_hero",
			true
		)

	return {"threatened": false}


static func _evaluate_emergency_core_base_threat(
	tree: SceneTree,
	rally_position: Vector3
) -> Dictionary:
	var units_in_base: Array = collect_player_military_near(
		tree,
		rally_position,
		CORE_BASE_DEFENSE_RADIUS
	)
	if units_in_base.is_empty():
		return {"threatened": false}

	if _is_irrelevant_lone_scout(tree, units_in_base):
		return {"threatened": false}

	var anchor: Node3D = units_in_base[0] as Node3D
	if anchor == null:
		return {"threatened": false}

	var intercept_position: Vector3 = _resolve_player_threat_cluster_position(
		tree,
		anchor.global_position
	)
	return _build_emergency_threat_result(
		intercept_position,
		&"core_base",
		is_emergency_threat_serious(
			tree,
			_build_emergency_threat_result(intercept_position, &"core_base")
		)
	)


static func _evaluate_emergency_worker_attack_threat(tree: SceneTree) -> Dictionary:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not _is_important_enemy_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: Building = node as Building
		var building_position: Vector3 = (node as Node3D).global_position
		var attacker: Variant = CombatKillTracker.get_attacker(building)
		if not NodeSafety.is_alive_node(attacker):
			continue

		if not attacker is Worker:
			continue

		if CombatTargetValidation.is_enemy_faction(attacker):
			continue

		if not attacker is Node3D:
			CombatKillTracker.clear_attacker_record(building)
			continue

		var attacker_node: Node3D = attacker as Node3D
		var distance: float = _horizontal_distance(building_position, attacker_node.global_position)
		var actively_targeting: bool = _is_unit_actively_targeting(attacker_node, building)
		var damaged_recently: bool = CombatKillTracker.was_damaged_recently(
			building,
			MilitaryAIConfig.V2_DEFEND_RECENT_DAMAGE_SECONDS
		)
		if distance > BUILDING_THREAT_RANGE and not actively_targeting:
			if not damaged_recently or distance > BUILDING_THREAT_RANGE * 1.75:
				CombatKillTracker.clear_attacker_record(building)
			continue

		return _build_emergency_threat_result(
			_resolve_player_threat_cluster_position(tree, attacker_node.global_position),
			&"worker_attack"
		)

	return {"threatened": false}


static func _is_irrelevant_lone_scout(tree: SceneTree, units_in_base: Array) -> bool:
	if units_in_base.size() != 1:
		return false

	var unit: Node = units_in_base[0] as Node
	if not NodeSafety.is_alive_node(unit):
		return false

	if unit is Hero:
		return false

	if not unit is Node3D:
		return false

	var unit_position: Vector3 = (unit as Node3D).global_position
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not _is_important_enemy_building(node as Building):
			continue

		if not node is Node3D:
			continue

		if (
			_horizontal_distance(unit_position, (node as Node3D).global_position)
			<= EMERGENCY_SCOUT_IGNORE_BUILDING_DISTANCE
		):
			return false

	return true


static func _build_emergency_threat_result(
	intercept_position: Vector3,
	reason: StringName,
	force_recall: bool = false
) -> Dictionary:
	return {
		"threatened": true,
		"intercept_position": intercept_position,
		"reason": reason,
		"force_recall": force_recall,
	}


## Living player military that is a *current* danger to a building.
## Prunes CombatKillTracker entries that are dead, distant, or expired.
static func _resolve_live_building_attacker(
	_tree: SceneTree,
	building: Node,
	building_position: Vector3,
	threat_range: float
) -> Node3D:
	if building == null or not is_instance_valid(building) or building_position == Vector3.ZERO:
		return null

	var damage_window: float = MilitaryAIConfig.V2_DEFEND_RECENT_DAMAGE_SECONDS
	if not MilitaryAIConfig.is_v2_enabled():
		damage_window = STRATEGIC_THREAT_CLEAR_SECONDS

	var attacker: Variant = CombatKillTracker.get_attacker(building)
	if not NodeSafety.is_alive_node(attacker) or not attacker is Node3D:
		if attacker != null:
			CombatKillTracker.clear_attacker_record(building)
		return null

	if not _is_player_military_unit(attacker):
		CombatKillTracker.clear_attacker_record(building)
		return null

	var attacker_node: Node3D = attacker as Node3D
	var distance: float = _horizontal_distance(building_position, attacker_node.global_position)
	var actively_targeting: bool = _is_unit_actively_targeting(attacker_node, building)
	var damaged_recently: bool = CombatKillTracker.was_damaged_recently(building, damage_window)

	## Live danger: inside the defense radius, or still swinging at the building.
	if distance <= threat_range or actively_targeting:
		return attacker_node

	## Recent damage alone is not enough once the attacker has left the area.
	## Clear the stale kill-credit pointer so DEFEND cannot stick forever.
	if not damaged_recently or distance > threat_range * 1.75:
		CombatKillTracker.clear_attacker_record(building)
	return null


static func _is_unit_actively_targeting(unit: Node, target: Node) -> bool:
	if not NodeSafety.is_alive_node(unit) or not NodeSafety.is_alive_node(target):
		return false
	var attack_target: Variant = unit.get("_attack_target")
	if NodeSafety.is_alive_node(attack_target) and attack_target == target:
		return true
	if unit.has_method("get_attack_target"):
		var via_method: Variant = unit.call("get_attack_target")
		if NodeSafety.is_alive_node(via_method) and via_method == target:
			return true
	return false


static func _evaluate_worker_defense_threat(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_attacker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_WORKERS_GROUP):
		if not node is Worker or not _has_positive_health(node):
			continue

		if not node is Node3D:
			continue

		var worker: Worker = node as Worker
		var worker_position: Vector3 = (node as Node3D).global_position
		var live_attacker: Node3D = _resolve_live_building_attacker(
			tree,
			worker,
			worker_position,
			WORKER_THREAT_RANGE
		)
		if live_attacker != null:
			var distance: float = _horizontal_distance(
				rally_position,
				live_attacker.global_position
			)
			if distance < closest_distance:
				closest_distance = distance
				closest_attacker = live_attacker
			continue

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			worker_position,
			WORKER_THREAT_RANGE
		)
		if nearby_threat == null:
			continue

		var nearby_distance: float = _horizontal_distance(
			rally_position,
			nearby_threat.global_position
		)
		if nearby_distance < closest_distance:
			closest_distance = nearby_distance
			closest_attacker = nearby_threat

	if closest_attacker != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, closest_attacker.global_position),
			&"workers",
			true
		)

	return {"threatened": false}


static func _evaluate_building_defense_threat(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_attacker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: Building = node as Building
		var building_position: Vector3 = (node as Node3D).global_position
		var live_attacker: Node3D = _resolve_live_building_attacker(
			tree,
			building,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if live_attacker != null:
			var distance: float = _horizontal_distance(
				rally_position,
				live_attacker.global_position
			)
			if distance < closest_distance:
				closest_distance = distance
				closest_attacker = live_attacker
			continue

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if nearby_threat == null:
			continue

		var nearby_distance: float = _horizontal_distance(
			rally_position,
			nearby_threat.global_position
		)
		if nearby_distance < closest_distance:
			closest_distance = nearby_distance
			closest_attacker = nearby_threat

	if closest_attacker != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, closest_attacker.global_position),
			&"buildings",
			true
		)

	return {"threatened": false}


static func _find_player_military_in_enemy_economy_area(tree: SceneTree) -> Node3D:
	var closest_target: Node3D = null
	var closest_distance: float = INF
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)

	for node: Node in tree.get_nodes_in_group(ENEMY_WORKERS_GROUP):
		if not node is Worker or not _has_positive_health(node):
			continue

		if not node is Node3D:
			continue

		var worker_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			worker_position,
			ENEMY_ECONOMY_AREA_RANGE
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = threat

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if node is CommandCenter:
			continue

		if not node is Node3D:
			continue

		var building_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			ENEMY_ECONOMY_AREA_RANGE
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = threat

	return closest_target


static func _resolve_player_threat_cluster_position(
	tree: SceneTree,
	anchor_position: Vector3
) -> Vector3:
	var nearby_units: Array = collect_player_military_near(
		tree,
		anchor_position,
		DEFENSE_THREAT_POWER_RANGE
	)
	if nearby_units.is_empty():
		return anchor_position

	var position_sum: Vector3 = Vector3.ZERO
	var count: int = 0

	for unit: Variant in nearby_units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not unit is Node3D:
			continue

		position_sum += (unit as Node3D).global_position
		count += 1

	if count == 0:
		return anchor_position

	return position_sum / float(count)


static func _find_player_military_near_enemy_workers(
	tree: SceneTree,
	search_range: float
) -> Vector3:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_threat: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_WORKERS_GROUP):
		if not node is Worker or not _has_positive_health(node):
			continue

		if not node is Node3D:
			continue

		var worker_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			worker_position,
			search_range
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_threat = threat

	if closest_threat != null:
		return closest_threat.global_position

	return Vector3.ZERO


static func _find_player_military_near_enemy_buildings(
	tree: SceneTree,
	search_range: float
) -> Vector3:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_threat: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			search_range
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_threat = threat

	if closest_threat != null:
		return closest_threat.global_position

	return Vector3.ZERO


static func _find_player_military_near_position(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> Node3D:
	var closest_target: Node3D = null
	var closest_distance: float = INF

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node_variant: Variant in tree.get_nodes_in_group(group_name):
			if node_variant == null or not is_instance_valid(node_variant):
				continue
			if not _is_player_military_unit(node_variant):
				continue

			if not node_variant is Node3D:
				continue

			var target: Node3D = node_variant as Node3D
			var distance: float = _horizontal_distance(position, target.global_position)
			if distance > search_range:
				continue

			if distance < closest_distance:
				closest_distance = distance
				closest_target = target

	return closest_target


static func _is_player_military_unit(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if not NodeSafety.is_alive_node(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if CombatTargetValidation.is_enemy_faction(node):
		return false

	if not (node is Spearman or node is Swordsman or node is Archer or node is HeavyCavalry or node is LightCavalry or node is CavalryArcher or node is Cannon or node is Hero):
		return false

	return _has_positive_health(node)


static func _resolve_living_player_command_center(tree: SceneTree) -> CommandCenter:
	for node: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		PLAYER_COMMAND_CENTER_GROUP
	):
		if node is CommandCenter and _is_living_building(node as Building):
			return node as CommandCenter

	return null


static func _find_nearest_important_player_building(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_building: Node3D = null
	var closest_distance: float = INF

	for node: Variant in CombatTargetValidation.get_cached_group_nodes(tree, BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		if node is Farm:
			continue

		var building: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, building.global_position)
		if distance > IMPORTANT_BUILDING_SEARCH_RANGE:
			continue

		if distance < closest_distance:
			closest_distance = distance
			closest_building = building

	return closest_building


static func _find_nearest_living_player_building(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_building: Node3D = null
	var closest_distance: float = INF

	for node: Variant in CombatTargetValidation.get_cached_group_nodes(tree, BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		var building: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, building.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_building = building

	return closest_building


static func _find_nearest_living_player_unit(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_unit: Node3D = null
	var closest_distance: float = INF

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not node is Node3D:
				continue

			if CombatTargetValidation.is_enemy_faction(node):
				continue

			if not CombatTargetValidation.is_valid_combat_target(node):
				continue

			if node is Worker:
				continue

			var target: Node3D = node as Node3D
			var distance: float = _horizontal_distance(from_position, target.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_unit = target

	return closest_unit


static func _find_nearest_living_player_worker(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_worker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(UNITS_GROUP):
		if not node is Worker or not node is Node3D:
			continue

		if CombatTargetValidation.is_enemy_faction(node):
			continue

		if not CombatTargetValidation.is_valid_combat_target(node):
			continue

		var worker: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, worker.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_worker = worker

	return closest_worker


static func _has_living_attack_building_objective() -> bool:
	if not NodeSafety.is_alive_node(_active_wave_objective):
		return false

	if not _active_wave_objective is Building:
		return false

	return _is_living_building(_active_wave_objective as Building)


static func _is_living_building(building) -> bool:
	if building == null or not is_instance_valid(building):
		return false

	if not building is Building:
		return false

	if not NodeSafety.is_alive_node(building):
		return false

	if building.is_queued_for_deletion():
		return false

	return _has_positive_health(building)


static func _has_positive_health(node) -> bool:
	return EnemyArmyForceMath.has_positive_health(node)


static func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length()


static func resolve_finishing_attack_objective(
	tree: SceneTree,
	fallback_position: Vector3
) -> Dictionary:
	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return {
			"node": command_center,
			"position": command_center.global_position,
		}

	var reference_position: Vector3 = fallback_position
	if reference_position == Vector3.ZERO:
		reference_position = _resolve_player_base_reference_position(tree, fallback_position)

	var finishing_building: Node3D = _find_highest_priority_finishing_building(
		tree,
		reference_position
	)
	if finishing_building != null:
		return {
			"node": finishing_building,
			"position": finishing_building.global_position,
		}

	var nearest_worker: Node3D = _find_nearest_living_player_worker(tree, reference_position)
	if nearest_worker != null:
		return {
			"node": nearest_worker,
			"position": nearest_worker.global_position,
		}

	if fallback_position != Vector3.ZERO:
		return {"node": null, "position": fallback_position}

	return {"node": null, "position": Vector3.ZERO}


static func _set_finishing_mode(active: bool, reason: String) -> void:
	if active == _finishing_mode_active:
		return

	_finishing_mode_active = active
	_last_finishing_objective = null

	if active:
		print("[AI] ENTER FINISHING MODE reason=%s" % reason)
	else:
		print("[AI] EXIT FINISHING MODE reason=%s" % reason)
		_finishing_mode_exit_cooldown = FINISHING_MODE_EXIT_COOLDOWN


static func _evaluate_finishing_activation(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return {"should_enter": false}

	if not has_player_attack_targets(tree, rally_position):
		return {"should_enter": false}

	var ai_combat_count: int = collect_living_combat_units(tree).size()
	var player_combat_count: int = _count_living_player_combat_units(tree)

	if _resolve_living_player_command_center(tree) == null:
		if ai_combat_count >= FINISHING_MODE_MIN_PUSH_UNITS:
			return {
				"should_enter": true,
				"reason": "player_command_center_destroyed",
			}

	if (
		player_combat_count <= FINISHING_MODE_MAX_PLAYER_COMBAT_UNITS
		and ai_combat_count >= FINISHING_MODE_MIN_AI_COMBAT_UNITS
	):
		return {
			"should_enter": true,
			"reason": "player_army_crippled",
		}

	var military_production_count: int = _count_living_player_military_production_buildings(tree)
	if (
		military_production_count <= FINISHING_MODE_MAX_PLAYER_MILITARY_PRODUCTION
		and player_combat_count <= FINISHING_MODE_WEAK_PLAYER_COMBAT_FOR_PRODUCTION
		and ai_combat_count >= FINISHING_MODE_MIN_AI_COMBAT_UNITS
	):
		return {
			"should_enter": true,
			"reason": "player_production_crippled",
		}

	if ai_combat_count >= FINISHING_MODE_MIN_PUSH_UNITS and _is_finishing_army_inside_player_base(
		tree
	):
		var base_reference: Vector3 = _resolve_player_base_reference_position(
			tree,
			rally_position
		)
		var player_power: int = estimate_player_threat_power_near(
			tree,
			base_reference,
			FINISHING_MODE_IN_BASE_DISTANCE
		)
		if player_power <= FINISHING_MODE_WEAK_RESISTANCE_POWER:
			return {
				"should_enter": true,
				"reason": "army_in_base_weak_resistance",
			}

	return {"should_enter": false}


static func _evaluate_finishing_exit(tree: SceneTree) -> Dictionary:
	var ai_units: Array = _collect_living_offensive_wave_units(tree)
	if ai_units.is_empty():
		ai_units = collect_living_combat_units(tree)

	var ai_power: int = estimate_military_power(ai_units)
	var player_units: Array = _collect_living_player_combat_unit_nodes(tree)
	var player_power: int = estimate_military_power(player_units)
	var player_combat_count: int = player_units.size()

	if (
		player_combat_count >= 3
		and ai_power > 0
		and player_power >= int(float(ai_power) * FINISHING_MODE_PLAYER_RECOVERY_RATIO)
	):
		return {"should_exit": true, "reason": "player_recovered_strength"}

	var living_count: int = ai_units.size()
	if _active_wave_start_unit_count > 0:
		var retreat_threshold: int = maxi(
			FINISHING_MODE_MIN_PUSH_UNITS,
			int(float(_active_wave_start_unit_count) * FINISHING_MODE_ARMY_DESTROYED_RATIO)
		)
		if living_count < retreat_threshold:
			return {"should_exit": true, "reason": "ai_army_destroyed"}
	elif get_army_mode() == ArmyMode.ATTACKING and living_count < FINISHING_MODE_MIN_PUSH_UNITS:
		return {"should_exit": true, "reason": "ai_army_destroyed"}

	return {"should_exit": false}


static func _assign_reinforcement_to_finishing_attack(tree: SceneTree, unit) -> void:
	if not NodeSafety.is_alive_node(unit):
		return
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	_register_reinforcement_waiting(tree, unit, rally_position, "finishing_mode_hold")


static func _log_finishing_objective(objective_node: Node3D) -> void:
	if not NodeSafety.is_alive_node(objective_node):
		return

	if objective_node == _last_finishing_objective:
		return

	_last_finishing_objective = objective_node
	print(
		"[AI] FINISH OBJECTIVE %s"
		% _get_finishing_objective_display_name(objective_node)
	)


static func _get_finishing_objective_display_name(node) -> String:
	if not NodeSafety.is_alive_node(node):
		return "unknown"

	if node is CommandCenter:
		return "CommandCenter"
	if node is Barracks:
		return "Barracks"
	if node is HeroAltar:
		return "HeroAltar"
	if node is Tower:
		return "Tower"
	if node is Blacksmith:
		return "Blacksmith"
	if node is Shop:
		return "Shop"
	if node is Worker:
		return "Worker"
	if node is Building:
		return "Building"

	return node.name


static func _count_living_player_combat_units(tree: SceneTree) -> int:
	return _collect_living_player_combat_unit_nodes(tree).size()


static func _collect_living_player_combat_unit_nodes(tree: SceneTree) -> Array:
	var units: Array = []
	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node_variant: Variant in tree.get_nodes_in_group(group_name):
			if node_variant == null or not is_instance_valid(node_variant):
				continue
			if not node_variant is Node3D:
				continue

			if CombatTargetValidation.is_enemy_faction(node_variant):
				continue

			if node_variant is Worker:
				continue

			if not (node_variant is Spearman or node_variant is Swordsman or node_variant is Archer or node_variant is HeavyCavalry or node_variant is LightCavalry or node_variant is CavalryArcher or node_variant is Cannon or node_variant is Hero):
				continue

			if not CombatTargetValidation.is_valid_combat_target(node_variant):
				continue

			units.append(node_variant)

	return units


static func _count_living_player_military_production_buildings(tree: SceneTree) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		if node is Barracks or node is HeroAltar:
			count += 1

	return count


static func _resolve_player_base_reference_position(
	tree: SceneTree,
	fallback_position: Vector3
) -> Vector3:
	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return command_center.global_position

	var nearest_building: Node3D = _find_nearest_living_player_building(
		tree,
		fallback_position
	)
	if nearest_building != null:
		return nearest_building.global_position

	return fallback_position


static func _is_finishing_army_inside_player_base(tree: SceneTree) -> bool:
	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		return false

	var army_center: Vector3 = compute_army_center(wave_units)
	if army_center == Vector3.ZERO:
		return false

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var base_reference: Vector3 = _resolve_player_base_reference_position(
		tree,
		rally_position
	)
	if base_reference == Vector3.ZERO:
		return false

	return (
		horizontal_distance(army_center, base_reference)
		<= FINISHING_MODE_IN_BASE_DISTANCE
	)


static func _find_highest_priority_finishing_building(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var best_building: Node3D = null
	var best_priority: int = 999
	var best_distance: float = INF

	for node: Node in tree.get_nodes_in_group(BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		var building: Building = node as Building
		var priority: int = _get_finishing_building_priority(building, tree)
		var building_position: Vector3 = (building as Node3D).global_position
		var distance: float = _horizontal_distance(from_position, building_position)

		if priority < best_priority or (priority == best_priority and distance < best_distance):
			best_priority = priority
			best_distance = distance
			best_building = building as Node3D

	return best_building


static func _get_finishing_building_priority(building, tree: SceneTree) -> int:
	if building == null or not is_instance_valid(building):
		return 999
	if building is Barracks:
		return 1
	if building is HeroAltar:
		return 2
	if building is Tower and _is_actively_dangerous_tower(building as Tower, tree):
		return 3
	if building is Blacksmith or building is Shop:
		return 4
	if building is Farm:
		return 6
	if building is Tower:
		return 5

	return 5


static func _is_actively_dangerous_tower(tower, tree: SceneTree) -> bool:
	if not NodeSafety.is_alive_node(tower):
		return false

	if not tower is Tower:
		return false

	if tower.building_state != Building.STATE_COMPLETED:
		return false

	var threat_range: float = tower.attack_range + FINISHING_MODE_TOWER_THREAT_BUFFER
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		if horizontal_distance((unit as Node3D).global_position, tower.global_position) <= threat_range:
			return true

	return false
