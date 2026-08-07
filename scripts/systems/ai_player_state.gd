class_name AIPlayerState
extends Node

## Match-owned enemy AI runtime (PHASE 2).
## Lifetime follows the match scene via MatchCompositionRoot.
## When EnemyArmyCommand is bound, this node is the sole authoritative store for
## identity / exec / combat / assembly / wave / formation / finishing fields,
## plus command-queue, reinforcement pool, TTL threat caches, mission scratch,
## creep-contest cooldowns, and attack-objective timers.
## Unbound helpers use a private offline instance — never a second live authority.
##
## TEMPORARY dual-write removed for migrated bags: accessors on EnemyArmyCommand
## read/write this object directly. Intent bus is owned here; providers publish only.
##
## Ownership rules:
## - pending_group_orders: sole command-queue owner (drained by ArmyCommanderV2 via EAC).
## - reinforcement_pool: sole match owner for waiting-unit registry.
## - creep_contest_cooldowns: match-durable camp cooldown map (blocks contest only).
## - objective_* timers: mission/wave-owned; cleared with objective cancel + match reset.
## - defense/emergency threat caches: short TTL scratch only — never authoritative SoT.
## - exec_* scratch / watchdog: mission-owned; cleared with mission and match reset.
## Frame-local army unit caches and pure telemetry stay on EnemyArmyCommand.

## --- Identity ---
var army_mode: int = 0
var mode_claim_msec: int = 0
var strategic_state: int = 0
var strategic_state_msec: int = 0
var pending_strategic_state: int = 0
var pending_strategic_reason: String = ""
var has_pending_strategic_transition: bool = false
var orders_authorized: bool = false
var emergency_defense_active: bool = false
var emergency_threat_position: Vector3 = Vector3.ZERO
var emergency_reason: StringName = &""

## --- Executable mission ---
var exec_mission: int = 0
var exec_objective_position: Vector3 = Vector3.ZERO
var exec_objective_name: String = ""
var exec_order_label: String = ""
var exec_transition_reason: String = ""
var exec_camp_reserved: bool = false
var exec_mission_start_msec: int = 0
var allow_hostile_engagement: bool = false

## --- Mission-owned transient (watchdog / scratch; not durable strategy) ---
## Variant so freed objectives can be read before NodeSafety validation (typed Node3D getters cast first).
var exec_objective_node: Variant = null
var exec_last_progress_msec: int = 0
var exec_last_distance: float = -1.0
var exec_squad_ids: Array[int] = []
var exec_watchdog_timer: float = 0.0
var exec_watchdog_refreshed: bool = false
var exec_last_report: String = ""

## --- Combat runtime ---
var assembly_timer: float = 0.0
var assembly_rally: Vector3 = Vector3.ZERO
var assembly_required_count: int = 0
var retreat_cooldown: float = 0.0
var fight_start_strength: float = 0.0
var fight_anchor_position: Vector3 = Vector3.ZERO
var fight_start_msec: int = 0
var is_rebuilding_army: bool = false
var player_army_memory: Dictionary = {
	"strength": 0.0,
	"position": Vector3.ZERO,
	"hero_level": 0,
	"timestamp_msec": 0,
	"unit_count": 0,
}

## --- Attack wave ---
var attack_wave_state: int = 0
var attack_wave_state_msec: int = 0
var attack_wave_units: Array = []
var attack_wave_staging_point: Vector3 = Vector3.ZERO
var attack_wave_target_position: Vector3 = Vector3.ZERO
## Variant so freed buildings can be read before NodeSafety validation (typed Node3D getters cast first).
var attack_wave_target_node: Variant = null
var attack_wave_target_committed_until_msec: int = 0
var attack_wave_gather_pull_timer: float = 0.0
var attack_wave_hero_wait_timer: float = 0.0
var attack_wave_regroup_timer: float = 0.0
var attack_wave_recovery_timer: float = 0.0
var attack_wave_command_refresh_timer: float = 0.0
var attack_wave_hero_unreachable_retries: int = 0
var attack_wave_min_non_hero_units: int = 0
var attack_wave_ready_to_advance: bool = false
var attack_wave_pending_transition: int = 0
var attack_wave_pending_transition_reason: String = ""
var active_wave_start_unit_count: int = 0
## Variant so freed buildings can be read before NodeSafety validation (typed Node3D getters cast first).
var active_wave_objective: Variant = null
var active_wave_objective_position: Vector3 = Vector3.ZERO

## --- Formation / group-order cache ---
var formation_cache_unit_ids: Array[int] = []
var formation_cache_center: Vector3 = Vector3.ZERO
var formation_cache_use_attack_move: bool = false
var formation_cache_targets: Array[Vector3] = []
var formation_cache_msec: int = 0
var formation_cache_army_mode: int = -1
var active_group_order_signature: String = ""
var active_group_order_dest: Vector3 = Vector3.ZERO
var active_group_order_mission: int = -1
var active_group_order_generation: int = 0
var active_group_order_msec: int = 0
var group_order_generation: int = 0

## --- Finishing / endgame ---
var finishing_mode_active: bool = false
var finishing_mode_exit_cooldown: float = 0.0
var finishing_mode_eval_timer: float = 0.0
## Variant so freed buildings can be read before NodeSafety validation (typed Node3D getters cast first).
var last_finishing_objective: Variant = null

## --- Command queue (sole owner; lifecycle = match + drain by ArmyCommanderV2) ---
var pending_group_orders: Array = []
var issuing_group_order_batch: bool = false

## --- Reinforcement pool (sole match owner) ---
var reinforcement_pool: Dictionary = {}

## --- TTL threat caches (scratch only; recomputed from world; never SoT) ---
var defense_threat_cache: Dictionary = {}
var defense_threat_cache_msec: int = 0
var emergency_threat_cache: Dictionary = {}
var emergency_threat_cache_msec: int = 0

## --- Creep contest cooldowns (match-durable; blocks camp contest eligibility) ---
var creep_contest_cooldowns: Dictionary = {}

## --- Attack-objective timers (mission/wave-owned; not durable strategy) ---
var objective_reissue_timer: float = 0.0
var objective_stuck_timer: float = 0.0
var objective_last_building_health: int = -1
var objective_eval_timer: float = 0.0
var objective_stuck_check_timer: float = 0.0

## Declared sole military order issuer for this match (ArmyCommanderV2 under V2).
var _military_command_authority: Node = null
var military_command_authority_name: StringName = &""

## Intent bus — providers publish; director arbitrates (priority / TTL / ownership).
var _pending_intents: Array = []
var accepted_intent_kind: int = 0
var accepted_intent_source: StringName = &""
var accepted_intent_reason: StringName = &""
var accepted_intent_expires_msec: int = 0
var accepted_intent_mission_owner: StringName = &""


func reset() -> void:
	army_mode = 0
	mode_claim_msec = 0
	strategic_state = 0
	strategic_state_msec = 0
	pending_strategic_state = 0
	pending_strategic_reason = ""
	has_pending_strategic_transition = false
	orders_authorized = false
	emergency_defense_active = false
	emergency_threat_position = Vector3.ZERO
	emergency_reason = &""
	exec_mission = 0
	exec_objective_position = Vector3.ZERO
	exec_objective_name = ""
	exec_order_label = ""
	exec_transition_reason = ""
	exec_camp_reserved = false
	exec_mission_start_msec = 0
	allow_hostile_engagement = false
	exec_objective_node = null
	exec_last_progress_msec = 0
	exec_last_distance = -1.0
	exec_squad_ids.clear()
	exec_watchdog_timer = 0.0
	exec_watchdog_refreshed = false
	exec_last_report = ""
	assembly_timer = 0.0
	assembly_rally = Vector3.ZERO
	assembly_required_count = 0
	retreat_cooldown = 0.0
	fight_start_strength = 0.0
	fight_anchor_position = Vector3.ZERO
	fight_start_msec = 0
	is_rebuilding_army = false
	player_army_memory = {
		"strength": 0.0,
		"position": Vector3.ZERO,
		"hero_level": 0,
		"timestamp_msec": 0,
		"unit_count": 0,
	}
	attack_wave_state = 0
	attack_wave_state_msec = 0
	attack_wave_units.clear()
	attack_wave_staging_point = Vector3.ZERO
	attack_wave_target_position = Vector3.ZERO
	attack_wave_target_node = null
	attack_wave_target_committed_until_msec = 0
	attack_wave_gather_pull_timer = 0.0
	attack_wave_hero_wait_timer = 0.0
	attack_wave_regroup_timer = 0.0
	attack_wave_recovery_timer = 0.0
	attack_wave_command_refresh_timer = 0.0
	attack_wave_hero_unreachable_retries = 0
	attack_wave_min_non_hero_units = 0
	attack_wave_ready_to_advance = false
	attack_wave_pending_transition = 0
	attack_wave_pending_transition_reason = ""
	active_wave_start_unit_count = 0
	active_wave_objective = null
	active_wave_objective_position = Vector3.ZERO
	formation_cache_unit_ids.clear()
	formation_cache_center = Vector3.ZERO
	formation_cache_use_attack_move = false
	formation_cache_targets.clear()
	formation_cache_msec = 0
	formation_cache_army_mode = -1
	active_group_order_signature = ""
	active_group_order_dest = Vector3.ZERO
	active_group_order_mission = -1
	active_group_order_generation = 0
	active_group_order_msec = 0
	group_order_generation = 0
	finishing_mode_active = false
	finishing_mode_exit_cooldown = 0.0
	finishing_mode_eval_timer = 0.0
	last_finishing_objective = null
	pending_group_orders.clear()
	issuing_group_order_batch = false
	reinforcement_pool.clear()
	defense_threat_cache.clear()
	defense_threat_cache_msec = 0
	emergency_threat_cache.clear()
	emergency_threat_cache_msec = 0
	creep_contest_cooldowns.clear()
	objective_reissue_timer = 0.0
	objective_stuck_timer = 0.0
	objective_last_building_health = -1
	objective_eval_timer = 0.0
	objective_stuck_check_timer = 0.0
	clear_accepted_intent()
	clear_intents()


func set_military_command_authority(authority: Node) -> void:
	if authority == null or not is_instance_valid(authority):
		_military_command_authority = null
		military_command_authority_name = &""
		return
	_military_command_authority = authority
	military_command_authority_name = authority.name


func get_military_command_authority() -> Node:
	if _military_command_authority != null and is_instance_valid(_military_command_authority):
		return _military_command_authority
	_military_command_authority = null
	return null


func publish_intent(intent: MilitaryIntent) -> void:
	if intent == null or intent.cancelled:
		return
	intent.ensure_timestamps()
	if intent.is_expired():
		return
	_purge_expired_intents()
	## Keep one slot per kind+source — providers refresh, they do not stack forever.
	for index: int in range(_pending_intents.size()):
		var existing: Variant = _pending_intents[index]
		if not existing is MilitaryIntent:
			continue
		var prior: MilitaryIntent = existing as MilitaryIntent
		if prior.kind != intent.kind or prior.source != intent.source:
			continue
		if (
			intent.priority > prior.priority
			or (
				intent.priority == prior.priority
				and intent.score >= prior.score
			)
		):
			_pending_intents[index] = intent
		return
	_pending_intents.append(intent)


func clear_intents() -> void:
	_pending_intents.clear()


func cancel_intents_of_kind(kind: int) -> void:
	for entry: Variant in _pending_intents:
		if entry is MilitaryIntent and (entry as MilitaryIntent).kind == kind:
			(entry as MilitaryIntent).cancel()
	_purge_expired_intents()


func pending_intent_count() -> int:
	_purge_expired_intents()
	return _pending_intents.size()


func peek_intents() -> Array:
	_purge_expired_intents()
	return _pending_intents.duplicate()


## Drain actionable intents for one director arbitration pass.
func consume_intents() -> Array:
	_purge_expired_intents()
	var snapshot: Array = []
	for entry: Variant in _pending_intents:
		if entry is MilitaryIntent and (entry as MilitaryIntent).is_actionable():
			snapshot.append(entry)
	_pending_intents.clear()
	return snapshot


func has_intent_kind(kind: int) -> bool:
	_purge_expired_intents()
	for entry: Variant in _pending_intents:
		if entry is MilitaryIntent and (entry as MilitaryIntent).kind == kind:
			return true
	return false


func peek_best_intent(kind: int = -1) -> MilitaryIntent:
	_purge_expired_intents()
	var best: MilitaryIntent = null
	for entry: Variant in _pending_intents:
		if not entry is MilitaryIntent:
			continue
		var intent: MilitaryIntent = entry as MilitaryIntent
		if not intent.is_actionable():
			continue
		if kind >= 0 and intent.kind != kind:
			continue
		if best == null:
			best = intent
			continue
		if (
			intent.priority > best.priority
			or (intent.priority == best.priority and intent.score > best.score)
		):
			best = intent
	return best


func accept_intent(intent: MilitaryIntent, hold_msec: int = MilitaryIntent.ACCEPTED_HOLD_MSEC) -> void:
	if intent == null or not intent.is_actionable():
		clear_accepted_intent()
		return
	accepted_intent_kind = intent.kind
	accepted_intent_source = intent.source
	accepted_intent_reason = intent.reason
	accepted_intent_mission_owner = intent.mission_owner
	accepted_intent_expires_msec = Time.get_ticks_msec() + maxi(hold_msec, 1)


func clear_accepted_intent() -> void:
	accepted_intent_kind = 0
	accepted_intent_source = &""
	accepted_intent_reason = &""
	accepted_intent_mission_owner = &""
	accepted_intent_expires_msec = 0


func has_live_accepted_intent(kind: int = -1) -> bool:
	if accepted_intent_expires_msec <= 0:
		return false
	if Time.get_ticks_msec() > accepted_intent_expires_msec:
		clear_accepted_intent()
		return false
	if kind >= 0 and accepted_intent_kind != kind:
		return false
	return true


func _purge_expired_intents() -> void:
	if _pending_intents.is_empty():
		return
	var kept: Array = []
	for entry: Variant in _pending_intents:
		if entry is MilitaryIntent and (entry as MilitaryIntent).is_actionable():
			kept.append(entry)
	_pending_intents = kept
