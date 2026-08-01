class_name EnemyStrategicDirector
extends Node

## High-level enemy AI coordinator. Owns the strategic phase and sets parallel desires.
## Existing managers execute decisions; this node does not micromanage every unit.

enum StrategicPhase {
	OPENING,
	EARLY_ARMY,
	CREEPING,
	TIER_2,
	EXPANSION,
	MID_GAME,
	TIER_3,
	LATE_GAME,
}

const FAST_TICK_SECONDS: float = 0.75
const NORMAL_TICK_SECONDS: float = 3.0
const STRATEGIC_TICK_SECONDS: float = 12.0
const RECOVERY_TICK_SECONDS: float = 8.0
const NODE_CLEANUP_INTERVAL_SECONDS: float = 0.5

const DESIRE_HIGH: float = 0.75
const DESIRE_MEDIUM: float = 0.45
const DESIRE_LOW: float = 0.20

const EARLY_ARMY_MIN_PIKEMEN: int = 4
const EARLY_ARMY_SOFT_PIKEMEN: int = 6
const EARLY_ARMY_TARGET_PIKEMEN: int = 7
const EARLY_ARMY_RALLY_RATIO: float = 0.75
const CREEP_HERO_LEVEL_REQUIREMENT: int = 3
const CREEP_REQUIRED_EARLY_CAMPS_MIN: int = 1
const CREEP_REQUIRED_EARLY_CAMPS_MAX: int = 3
const CREEP_REQUIRED_EARLY_CAMPS: int = 2
const EXPANSION_SATURATION_WORKERS: int = 16
const EXPANSION_MINE_MIN_WORKERS: int = 5
const MID_GAME_MIN_ARMY: int = 12
const OPENING_WORKER_TARGET: int = 12
const BASE_HEAVY_DAMAGE_RATIO: float = 0.35
const RECOVERY_MIN_WORKERS: int = 4
const PHASE_MIN_ARMY_OPENING: int = 4
const PHASE_MIN_ARMY_CREEP: int = 4
const PHASE_MIN_ARMY_MID: int = 12
const PHASE_MIN_ARMY_LATE: int = 20
const ENEMY_TEAM_ID: int = 1

@export var debug_enabled: bool = true

var _fast_timer: float = 0.0
var _normal_timer: float = 0.0
var _strategic_timer: float = 0.0
var _recovery_timer: float = 0.0
var _node_cleanup_timer: float = 0.0
var _match_start_msec: int = 0
var _recent_attack_failed: bool = false
var _recent_loss_timer: float = 0.0
var _creep_target: Node3D = null
var _attack_target_position: Vector3 = Vector3.ZERO
var _last_debug_mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.IDLE
var _last_debug_desires: Dictionary = {}

## Owned progression phase. Managers must read this; only this director may change it.
var _strategic_phase: StrategicPhase = StrategicPhase.OPENING
## Highest phase reached before temporary interrupts or recovery regressions.
var _highest_phase_reached: StrategicPhase = StrategicPhase.OPENING
var _phase_changed_this_evaluation: bool = false
var _phase_eval_frame: int = -1
var _phase_interrupt_active: bool = false
var _phase_interrupt_reason: String = ""
## Camps to clear before leaving CREEPING (rolled once on phase entry, 1–3).
var _creep_camps_target: int = CREEP_REQUIRED_EARLY_CAMPS

var desires: Dictionary = {
	"economy": 0.8,
	"army": 0.5,
	"creep": 0.5,
	"attack": 0.1,
	"defense": 0.0,
	"expansion": 0.2,
	"upgrade": 0.2,
}

var snapshot: Dictionary = {}


func _ready() -> void:
	EnemyArmyCommand.reset_match_state()
	EnemyAIDebug.reset_match_state()
	EnemyAttackPathDefense.reset_match_state()
	var creep_manager: EnemyCreepManager = get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
	if creep_manager != null:
		creep_manager.reset_match_state()
	_match_start_msec = Time.get_ticks_msec()
	# Stagger strategic ticks away from combat/defense shared frames.
	_fast_timer = FAST_TICK_SECONDS * 0.2
	_normal_timer = NORMAL_TICK_SECONDS * 0.4
	_strategic_timer = STRATEGIC_TICK_SECONDS * 0.15
	_recovery_timer = RECOVERY_TICK_SECONDS * 0.6
	EnemyAIDebug.set_enabled(debug_enabled)
	EnemyArmyCommand.set_debug_enabled(debug_enabled)
	call_deferred("_run_initial_evaluation")


func _run_initial_evaluation() -> void:
	if not is_inside_tree():
		return

	_evaluate_normal()
	_evaluate_strategic()


func _process(delta: float) -> void:
	_node_cleanup_timer += delta
	if _node_cleanup_timer >= NODE_CLEANUP_INTERVAL_SECONDS:
		_node_cleanup_timer = 0.0
		_run_node_reference_cleanup()

	_sanitize_creep_target()
	_fast_timer += delta
	_normal_timer += delta
	_strategic_timer += delta
	_recovery_timer += delta

	if _recent_loss_timer > 0.0:
		_recent_loss_timer = maxf(0.0, _recent_loss_timer - delta)

	if _fast_timer >= FAST_TICK_SECONDS:
		_fast_timer = 0.0
		var start_usec: int = PerfCounters.begin_section()
		_evaluate_fast()
		PerfCounters.end_section("Strategic fast update", start_usec)
		PerfCounters.record_ai_decision_update()
		_publish_perf_status()

	if _normal_timer >= NORMAL_TICK_SECONDS:
		_normal_timer = 0.0
		var start_usec_normal: int = PerfCounters.begin_section()
		_evaluate_normal()
		PerfCounters.end_section("Strategic normal update", start_usec_normal)
		PerfCounters.record_ai_decision_update()
		_publish_perf_status()

	if _strategic_timer >= STRATEGIC_TICK_SECONDS:
		_strategic_timer = 0.0
		_evaluate_strategic()
		_publish_perf_status()

	if _recovery_timer >= RECOVERY_TICK_SECONDS:
		_recovery_timer = 0.0
		_run_recovery_checks()


func _publish_perf_status() -> void:
	PerfCounters.set_ai_status(
		get_strategic_phase_name(),
		EnemyArmyCommand.ArmyMode.keys()[EnemyArmyCommand.get_army_mode()],
		EnemyUnitMission.mission_to_label(EnemyUnitMission.get_main_army_mission())
	)


func get_strategic_phase() -> StrategicPhase:
	return _strategic_phase


func get_strategic_phase_name() -> String:
	return strategic_phase_to_string(_strategic_phase)


func get_highest_phase_reached() -> StrategicPhase:
	return _highest_phase_reached


func is_phase_at_least(phase: StrategicPhase) -> bool:
	return int(_strategic_phase) >= int(phase)


func is_phase_interrupted() -> bool:
	return _phase_interrupt_active


func get_phase_interrupt_reason() -> String:
	return _phase_interrupt_reason


## True while early strategic phases own the army. Player attacks must not launch.
## OPENING / EARLY_ARMY / CREEPING / TIER_2 block normal offense.
## DEFEND / emergency defense intentionally bypass this — callers must allow Mission.DEFEND.
func blocks_player_offense() -> bool:
	return not can_launch_player_attack()


## Shared offensive gate. True only from EXPANSION onward (after TIER_2).
func can_launch_player_attack() -> bool:
	return is_phase_at_least(StrategicPhase.EXPANSION)


func get_creep_camps_target() -> int:
	return _creep_camps_target


func get_min_army_size_for_current_phase() -> int:
	return get_min_army_size_for_phase(_strategic_phase)


static func get_min_army_size_for_phase(phase: StrategicPhase) -> int:
	match phase:
		StrategicPhase.OPENING, StrategicPhase.EARLY_ARMY:
			return PHASE_MIN_ARMY_OPENING
		StrategicPhase.CREEPING, StrategicPhase.TIER_2, StrategicPhase.EXPANSION:
			return PHASE_MIN_ARMY_CREEP
		StrategicPhase.MID_GAME, StrategicPhase.TIER_3:
			return PHASE_MIN_ARMY_MID
		StrategicPhase.LATE_GAME:
			return PHASE_MIN_ARMY_LATE
		_:
			return PHASE_MIN_ARMY_OPENING


static func strategic_phase_to_string(phase: StrategicPhase) -> String:
	match phase:
		StrategicPhase.OPENING:
			return "OPENING"
		StrategicPhase.EARLY_ARMY:
			return "EARLY_ARMY"
		StrategicPhase.CREEPING:
			return "CREEPING"
		StrategicPhase.TIER_2:
			return "TIER_2"
		StrategicPhase.EXPANSION:
			return "EXPANSION"
		StrategicPhase.MID_GAME:
			return "MID_GAME"
		StrategicPhase.TIER_3:
			return "TIER_3"
		StrategicPhase.LATE_GAME:
			return "LATE_GAME"
		_:
			return "OPENING"


func get_desire(key: String) -> float:
	return float(desires.get(key, 0.0))


func should_prioritize_creep() -> bool:
	if EnemyAggression.should_suspend_creeping():
		return false

	if _phase_interrupt_active or get_desire("defense") >= DESIRE_HIGH:
		return false

	if _strategic_phase in [StrategicPhase.OPENING, StrategicPhase.EARLY_ARMY]:
		return false

	if EnemyArmyCommand.get_army_mode() in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]:
		return false

	if _strategic_phase == StrategicPhase.CREEPING:
		return true

	# During TIER_2, only finish a nearby safe camp — never a major push.
	if _strategic_phase == StrategicPhase.TIER_2:
		return (
			get_desire("creep") >= DESIRE_LOW
			and snapshot.get("has_safe_creep_camp", false)
			and snapshot.get("creeping_army_healthy", false)
			and not snapshot.get("base_under_attack", false)
		)

	return (
		get_desire("creep") >= DESIRE_MEDIUM
		and is_phase_at_least(StrategicPhase.CREEPING)
		and not is_phase_at_least(StrategicPhase.TIER_2)
	)


func should_prioritize_attack() -> bool:
	if _phase_interrupt_active:
		return false

	if not can_launch_player_attack():
		return false

	if get_desire("defense") >= DESIRE_HIGH and not EnemyAggression.is_counter_pressure_active():
		return false

	if EnemyAggression.is_aggression_mode_active():
		return get_desire("attack") >= DESIRE_MEDIUM

	if is_phase_at_least(StrategicPhase.MID_GAME):
		return get_desire("attack") >= DESIRE_MEDIUM

	if is_phase_at_least(StrategicPhase.EXPANSION):
		return get_desire("attack") >= DESIRE_MEDIUM

	return get_desire("attack") >= DESIRE_HIGH


func should_prioritize_expansion() -> bool:
	if _phase_interrupt_active or _recent_attack_failed:
		return false

	if get_desire("defense") >= DESIRE_HIGH:
		return false

	if _strategic_phase == StrategicPhase.EXPANSION:
		return true

	return (
		get_desire("expansion") >= DESIRE_MEDIUM
		and is_phase_at_least(StrategicPhase.EXPANSION)
	)


func should_prioritize_tier_upgrade(target_tier: int) -> bool:
	if _phase_interrupt_active or get_desire("defense") >= DESIRE_HIGH:
		return false

	if target_tier <= 2:
		return (
			_strategic_phase == StrategicPhase.TIER_2
			or get_desire("upgrade") >= DESIRE_MEDIUM and is_phase_at_least(StrategicPhase.TIER_2)
		)

	if target_tier >= 3:
		return (
			_strategic_phase == StrategicPhase.TIER_3
			or get_desire("upgrade") >= DESIRE_MEDIUM and is_phase_at_least(StrategicPhase.TIER_3)
		)

	return false


func should_prioritize_mid_game_tech() -> bool:
	return (
		not _phase_interrupt_active
		and is_phase_at_least(StrategicPhase.MID_GAME)
		and get_desire("defense") < DESIRE_HIGH
	)


func should_prioritize_late_game_units() -> bool:
	return (
		not _phase_interrupt_active
		and is_phase_at_least(StrategicPhase.LATE_GAME)
		and get_desire("defense") < DESIRE_HIGH
	)


func should_boost_army_production() -> bool:
	return get_desire("army") >= DESIRE_MEDIUM or get_desire("defense") >= DESIRE_MEDIUM


func should_boost_worker_production() -> bool:
	return get_desire("economy") >= DESIRE_MEDIUM or _strategic_phase == StrategicPhase.OPENING


func notify_attack_launched() -> void:
	_recent_attack_failed = false
	_set_main_mission(EnemyUnitMission.Mission.ATTACK, "attack wave launched")
	EnemyAggression.notify_attack_succeeded_partial()


func notify_attack_failed() -> void:
	_recent_attack_failed = true
	_recent_loss_timer = 45.0
	_set_main_mission(EnemyUnitMission.Mission.RALLY, "attack failed, rebuilding")
	EnemyAggression.notify_attack_failed()


func notify_army_losses() -> void:
	_recent_loss_timer = 30.0
	desires["army"] = maxf(desires["army"], DESIRE_HIGH)
	## Keep attack desire low while rebuilding, unless aggression still owns the push.
	if not EnemyAggression.is_aggression_mode_active():
		desires["attack"] = minf(desires["attack"], DESIRE_LOW)


func set_creep_target(camp) -> void:
	_creep_target = NodeSafety.safe_node(camp) as Node3D


func clear_creep_target() -> void:
	_creep_target = null


func _sanitize_creep_target() -> void:
	if not NodeSafety.is_alive_node(_creep_target):
		_creep_target = null


func _run_node_reference_cleanup() -> void:
	var removed: int = 0
	removed += EnemyUnitMission.purge_stale_entries()
	removed += CombatTargetValidation.purge_stale_attack_slots()
	EnemyArmyCommand.purge_stale_runtime_caches()

	if debug_enabled and removed > 0 and PerfCounters.verbose_ai_logging:
		EnemyAIDebug.log_event("Cleanup: purged %d stale node references" % removed)


func set_attack_target_position(position: Vector3) -> void:
	_attack_target_position = position


func _evaluate_fast() -> void:
	EnemyArmyCommand.apply_pending_strategic_transition()
	_update_phase_interrupt()

	var tree: SceneTree = get_tree()
	var emergency_threat: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(tree)
	if emergency_threat.get("threatened", false):
		desires["defense"] = 1.0
		desires["attack"] = 0.0
		desires["creep"] = 0.0
		desires["expansion"] = 0.0
		_set_main_mission(
			EnemyUnitMission.Mission.DEFEND,
			"threat near base (%s)" % String(emergency_threat.get("reason", "unknown"))
		)
		return

	var threat: Dictionary = EnemyArmyCommand.evaluate_defense_threat(tree)
	if threat.get("threatened", false):
		desires["defense"] = 1.0
		desires["attack"] = 0.0
		desires["creep"] = 0.0
		desires["expansion"] = 0.0
		_set_main_mission(
			EnemyUnitMission.Mission.DEFEND,
			"threat near base (%s)" % String(threat.get("reason", "unknown"))
		)
	else:
		desires["defense"] = maxf(0.0, desires["defense"] - 0.25)


func _evaluate_normal() -> void:
	_begin_phase_evaluation_gate()
	snapshot = _build_world_snapshot()
	_update_phase_interrupt()
	_update_strategic_phase()
	_update_desires_from_snapshot()
	_recommend_main_army_mission()
	_maybe_log_debug()


func _evaluate_strategic() -> void:
	_begin_phase_evaluation_gate()
	if snapshot.is_empty():
		snapshot = _build_world_snapshot()

	_update_phase_interrupt()
	_update_strategic_phase()

	if desires["expansion"] >= DESIRE_MEDIUM and snapshot.get("economy_healthy", false):
		desires["expansion"] = minf(1.0, desires["expansion"] + 0.15)

	if snapshot.get("hero_alive", false) and int(snapshot.get("hero_level", 1)) >= 2:
		desires["upgrade"] = minf(1.0, desires["upgrade"] + 0.1)


func _begin_phase_evaluation_gate() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _phase_eval_frame:
		return

	_phase_eval_frame = frame
	_phase_changed_this_evaluation = false


func _update_phase_interrupt() -> void:
	var strategic_state: EnemyArmyCommand.StrategicState = EnemyArmyCommand.get_strategic_state()
	if (
		EnemyArmyCommand.is_emergency_defense_active()
		or strategic_state == EnemyArmyCommand.StrategicState.EMERGENCY_DEFENDING
	):
		_phase_interrupt_active = true
		_phase_interrupt_reason = "emergency defense"
		return

	if strategic_state == EnemyArmyCommand.StrategicState.RETREATING:
		_phase_interrupt_active = true
		_phase_interrupt_reason = "retreat"
		return

	_phase_interrupt_active = false
	_phase_interrupt_reason = ""


func _update_strategic_phase() -> void:
	if _phase_changed_this_evaluation:
		return

	if _try_recovery_phase_regression():
		return

	# Temporary interrupts must not advance or reset progression ownership.
	if _phase_interrupt_active:
		return

	match _strategic_phase:
		StrategicPhase.OPENING:
			_try_advance_phase(
				StrategicPhase.EARLY_ARMY,
				_can_leave_opening(),
				_opening_exit_reason()
			)
		StrategicPhase.EARLY_ARMY:
			_try_advance_phase(
				StrategicPhase.CREEPING,
				_can_leave_early_army(),
				_early_army_exit_reason()
			)
		StrategicPhase.CREEPING:
			_try_advance_phase(
				StrategicPhase.TIER_2,
				_can_leave_creeping(),
				_creeping_exit_reason()
			)
		StrategicPhase.TIER_2:
			_try_advance_phase(
				StrategicPhase.EXPANSION,
				_can_leave_tier_2(),
				_tier_2_exit_reason()
			)
		StrategicPhase.EXPANSION:
			_try_advance_phase(
				StrategicPhase.MID_GAME,
				_can_leave_expansion(),
				_expansion_exit_reason()
			)
		StrategicPhase.MID_GAME:
			_try_advance_phase(
				StrategicPhase.TIER_3,
				_can_leave_mid_game(),
				_mid_game_exit_reason()
			)
		StrategicPhase.TIER_3:
			_try_advance_phase(
				StrategicPhase.LATE_GAME,
				_can_leave_tier_3(),
				_tier_3_exit_reason()
			)
		StrategicPhase.LATE_GAME:
			pass


func _try_advance_phase(next_phase: StrategicPhase, can_advance: bool, reason: String) -> void:
	if _phase_changed_this_evaluation or not can_advance:
		return

	if int(next_phase) <= int(_strategic_phase):
		return

	_set_strategic_phase(next_phase, reason)


func _try_recovery_phase_regression() -> bool:
	if _phase_changed_this_evaluation:
		return false

	if not snapshot.get("main_base_heavily_damaged", false):
		return false

	if not snapshot.get("recovery_required", false):
		return false

	var recovery_phase: StrategicPhase = StrategicPhase.EARLY_ARMY
	if (
		not snapshot.get("has_farm", false)
		or not snapshot.get("has_barracks", false)
		or not snapshot.get("has_hero_altar", false)
	):
		recovery_phase = StrategicPhase.OPENING

	if int(recovery_phase) >= int(_strategic_phase):
		return false

	_set_strategic_phase(
		recovery_phase,
		"Main base heavily damaged, recovery required"
	)
	return true


func _set_strategic_phase(new_phase: StrategicPhase, reason: String) -> void:
	if _phase_changed_this_evaluation:
		return

	if new_phase == _strategic_phase:
		return

	var previous: StrategicPhase = _strategic_phase
	_strategic_phase = new_phase
	_phase_changed_this_evaluation = true

	if int(new_phase) > int(_highest_phase_reached):
		_highest_phase_reached = new_phase

	if new_phase == StrategicPhase.CREEPING:
		_creep_camps_target = randi_range(
			CREEP_REQUIRED_EARLY_CAMPS_MIN,
			CREEP_REQUIRED_EARLY_CAMPS_MAX
		)
		# Unlock creep orders after defense/retreat recovery (RECOVERING blocked creeping).
		EnemyArmyCommand.request_strategic_state(
			EnemyArmyCommand.StrategicState.CREEPING,
			"creeping phase ownership"
		)

	if previous == StrategicPhase.OPENING:
		EnemyAIDebug.log_opening_complete(
			int(snapshot.get("workers", 0)),
			bool(snapshot.get("has_farm", false)),
			bool(snapshot.get("has_hero_altar", false)),
			bool(snapshot.get("has_barracks", false))
		)

	if previous == StrategicPhase.EARLY_ARMY:
		EnemyAIDebug.log_early_army_complete(int(snapshot.get("pikemen_count", 0)))

	if previous == StrategicPhase.CREEPING:
		EnemyAIDebug.log_creeping_complete()

	if previous == StrategicPhase.TIER_2:
		EnemyAIDebug.log_tier_2_complete()

	EnemyAIDebug.log_phase_transition(
		strategic_phase_to_string(previous),
		strategic_phase_to_string(new_phase),
		reason
	)


func _can_leave_opening() -> bool:
	return (
		snapshot.get("has_farm", false)
		and snapshot.get("has_hero_altar", false)
		and snapshot.get("has_barracks", false)
	)


func _opening_exit_reason() -> String:
	return "Farm, Altar, Barracks ready"


func _can_leave_early_army() -> bool:
	if not snapshot.get("hero_alive", false):
		return false

	## Prefer Spearmen, but any military escort of the same size is enough to start creeping.
	var escort_count: int = maxi(
		int(snapshot.get("pikemen_count", 0)),
		int(snapshot.get("combat_unit_count", 0))
	)
	if escort_count < EARLY_ARMY_MIN_PIKEMEN:
		return false

	return snapshot.get("early_army_rallied", false)


func _early_army_exit_reason() -> String:
	return "Hero ready, escort: %d" % maxi(
		int(snapshot.get("pikemen_count", 0)),
		int(snapshot.get("combat_unit_count", 0))
	)


func _can_leave_creeping() -> bool:
	if not snapshot.get("hero_alive", false):
		return false

	if int(snapshot.get("hero_level", 0)) < CREEP_HERO_LEVEL_REQUIREMENT:
		return false

	if not snapshot.get("creeping_army_healthy", false):
		return false

	var cleared_camps: int = int(snapshot.get("cleared_early_camps", 0))
	# Must clear at least one camp — never skip CREEPING into offense.
	if cleared_camps < CREEP_REQUIRED_EARLY_CAMPS_MIN:
		return false

	if cleared_camps >= _creep_camps_target:
		return true

	# Prefer more camps while safe ones remain; otherwise advance with level + 1 camp.
	return not snapshot.get("has_safe_creep_camp", true)


func _creeping_exit_reason() -> String:
	return (
		"Hero level %d, camps cleared: %d/%d"
		% [
			int(snapshot.get("hero_level", 0)),
			int(snapshot.get("cleared_early_camps", 0)),
			_creep_camps_target,
		]
	)


func _can_leave_tier_2() -> bool:
	if int(snapshot.get("town_hall_tier", 1)) < 2:
		return false

	if not _has_required_tier_1_buildings_intact():
		return false

	if not snapshot.get("economy_healthy", false):
		return false

	if _phase_interrupt_active:
		return false

	if EnemyArmyCommand.get_strategic_state() == EnemyArmyCommand.StrategicState.RETREATING:
		return false

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.RETREATING:
		return false

	return true


func _tier_2_exit_reason() -> String:
	return "Town Hall Tier 2 completed"


func _has_required_tier_1_buildings_intact() -> bool:
	for building_type: StringName in TechTree.get_core_setup_buildings_for_command_center_tier(1):
		match building_type:
			&"farm":
				if not snapshot.get("has_farm", false):
					return false
			&"barracks":
				if not snapshot.get("has_barracks", false):
					return false
			&"hero_altar":
				if not snapshot.get("has_hero_altar", false):
					return false
			&"shop":
				if not snapshot.get("has_shop", false):
					return false
			_:
				pass
	return true


func _can_leave_expansion() -> bool:
	return (
		snapshot.get("expansion_completed", false)
		and snapshot.get("expansion_saturated", false)
	)


func _expansion_exit_reason() -> String:
	return "Expansion completed and saturated"


func _can_leave_mid_game() -> bool:
	return (
		snapshot.get("has_blacksmith", false)
		and snapshot.get("economy_healthy", false)
		and int(snapshot.get("combat_unit_count", 0)) >= MID_GAME_MIN_ARMY
	)


func _mid_game_exit_reason() -> String:
	return "Blacksmith ready, army and economy stable"


func _can_leave_tier_3() -> bool:
	return int(snapshot.get("town_hall_tier", 1)) >= 3


func _tier_3_exit_reason() -> String:
	return "Town Hall Tier 3 completed"


func _build_world_snapshot() -> Dictionary:
	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	var workers: Array = _collect_workers(tree)
	var idle_workers: int = 0
	var gold_workers: int = 0
	var wood_workers: int = 0

	for worker: Variant in workers:
		if not NodeSafety.is_alive_node(worker):
			continue

		if not worker is Worker:
			continue

		var w: Worker = worker as Worker
		if w.is_on_construction_trip():
			continue

		match w.get_assigned_gather_resource_id():
			&"gold":
				gold_workers += 1
			&"wood":
				wood_workers += 1

		if _is_idle_worker(w):
			idle_workers += 1

	var non_hero_army: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(tree)
	var all_combat: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	var army_power: int = EnemyArmyCommand.estimate_military_power(all_combat)
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	var visible_threat_power: int = 0
	if rally_position != Vector3.ZERO:
		visible_threat_power = EnemyArmyCommand.estimate_player_threat_power_near(
			tree,
			rally_position,
			EnemyArmyCommand.BASE_THREAT_DETECTION_RANGE
		)

	var food_headroom: int = (
		EnemyResourceManager.food_max - EnemyResourceManager.food_current
	)
	var supply_block_risk: bool = food_headroom <= 3
	var building_counts: Dictionary = _count_enemy_buildings(tree)
	var town_hall_tier: int = TechTree.get_highest_command_center_tier(ENEMY_TEAM_ID)
	var town_centers: int = int(building_counts.get("command_centers", 0))
	var expansion_count: int = maxi(0, town_centers - 1)
	var main_base_health_ratio: float = _get_primary_command_center_health_ratio(tree)
	var main_base_heavily_damaged: bool = (
		main_base_health_ratio >= 0.0
		and main_base_health_ratio <= BASE_HEAVY_DAMAGE_RATIO
	)
	var economy_healthy: bool = (
		workers.size() >= 8
		and EnemyResourceManager.gold >= 100
		and EnemyResourceManager.wood >= 80
	)
	var expansion_saturated: bool = (
		expansion_count >= 1
		and workers.size() >= EXPANSION_SATURATION_WORKERS
		and gold_workers >= EXPANSION_MINE_MIN_WORKERS
		and economy_healthy
	)
	var pikemen_count: int = _count_pikemen(non_hero_army)
	var early_army_rallied: bool = _is_early_army_rallied(
		rally_position,
		all_combat,
		hero
	)
	var recovery_required: bool = (
		main_base_heavily_damaged
		and (
			workers.size() < RECOVERY_MIN_WORKERS
			or not bool(building_counts.get("has_barracks", false))
			or army_power < 120
		)
	)
	var creep_manager: EnemyCreepManager = (
		get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
		if get_parent() != null
		else null
	)
	var cleared_early_camps: int = 0
	var has_safe_creep_camp: bool = false
	var creeping_army_healthy: bool = false
	if creep_manager != null:
		cleared_early_camps = creep_manager.get_cleared_early_camp_count()
		has_safe_creep_camp = creep_manager.has_safe_creep_camp_available()
		creeping_army_healthy = creep_manager.is_army_healthy_after_creeping()
	else:
		cleared_early_camps = CreepCampSafety.count_cleared_enemy_side_camps(
			tree,
			rally_position,
			EnemyCreepManager.CREEP_SEARCH_RANGE,
			EnemyCreepManager.CAMP_CLEAR_RADIUS
		)
		creeping_army_healthy = (
			hero != null
			and non_hero_army.size() >= get_min_army_size_for_current_phase()
			and EnemyArmyCommand.get_health_ratio(hero) >= EnemyArmyCommand.HERO_RETREAT_HP_RATIO
		)

	return {
		"workers": workers.size(),
		"idle_workers": idle_workers,
		"gold_workers": gold_workers,
		"wood_workers": wood_workers,
		"gold": EnemyResourceManager.gold,
		"wood": EnemyResourceManager.wood,
		"food_used": EnemyResourceManager.food_current,
		"food_cap": EnemyResourceManager.food_max,
		"supply_block_risk": supply_block_risk,
		"town_centers": town_centers,
		"production_buildings": int(building_counts.get("barracks", 0)),
		"expansion_count": expansion_count,
		"expansion_completed": expansion_count >= 1,
		"expansion_saturated": expansion_saturated,
		"base_under_attack": EnemyArmyCommand.is_enemy_base_threatened(tree),
		"hero_alive": hero != null,
		"hero_level": hero.level if hero != null else 0,
		"combat_unit_count": non_hero_army.size(),
		"pikemen_count": pikemen_count,
		"early_army_rallied": early_army_rallied,
		"cleared_early_camps": cleared_early_camps,
		"has_safe_creep_camp": has_safe_creep_camp,
		"creeping_army_healthy": creeping_army_healthy,
		"army_power": army_power,
		"army_mode": EnemyArmyCommand.get_army_mode(),
		"visible_enemy_power": visible_threat_power,
		"economy_healthy": economy_healthy,
		"economy_strong": (
			workers.size() >= 14
			and EnemyResourceManager.gold >= 250
			and EnemyResourceManager.wood >= 200
		),
		"match_elapsed_seconds": _get_match_elapsed_seconds(),
		"recent_losses": _recent_loss_timer > 0.0,
		"has_farm": bool(building_counts.get("has_farm", false)),
		"has_barracks": bool(building_counts.get("has_barracks", false)),
		"has_hero_altar": bool(building_counts.get("has_hero_altar", false)),
		"has_blacksmith": bool(building_counts.get("has_blacksmith", false)),
		"has_shop": bool(building_counts.get("has_shop", false)),
		"has_stable": bool(building_counts.get("has_stable", false)),
		"town_hall_tier": town_hall_tier,
		"main_base_health_ratio": main_base_health_ratio,
		"main_base_heavily_damaged": main_base_heavily_damaged,
		"recovery_required": recovery_required,
		"strategic_phase": _strategic_phase,
		"phase_interrupted": _phase_interrupt_active,
	}


func _update_desires_from_snapshot() -> void:
	var workers: int = int(snapshot.get("workers", 0))
	var idle_workers: int = int(snapshot.get("idle_workers", 0))
	var army_power: int = int(snapshot.get("army_power", 0))
	var hero_alive: bool = snapshot.get("hero_alive", false)
	var hero_level: int = int(snapshot.get("hero_level", 0))
	var base_under_attack: bool = snapshot.get("base_under_attack", false)
	var supply_block_risk: bool = snapshot.get("supply_block_risk", false)
	var economy_healthy: bool = snapshot.get("economy_healthy", false)
	var visible_enemy_power: int = int(snapshot.get("visible_enemy_power", 0))
	var combat_units: int = int(snapshot.get("combat_unit_count", 0))
	var pikemen_count: int = int(snapshot.get("pikemen_count", 0))

	if _phase_interrupt_active or base_under_attack or get_desire("defense") >= DESIRE_HIGH:
		desires["defense"] = maxf(desires["defense"], DESIRE_HIGH)
		desires["attack"] = DESIRE_LOW
		desires["creep"] = DESIRE_LOW
		desires["expansion"] = 0.0
	else:
		desires["defense"] = maxf(0.0, desires["defense"] - 0.15)

	_apply_phase_desire_baseline()

	desires["economy"] = clampf(
		desires["economy"]
		+ float(maxi(0, 14 - workers)) * 0.04
		+ float(idle_workers) * 0.08
		+ (0.15 if supply_block_risk else 0.0),
		0.0,
		1.0
	)

	var army_target_power: float = float(EnemyArmyCommand.MIN_ATTACK_ARMY_POWER)
	var phase_army_desire: float = desires["army"]
	desires["army"] = clampf(
		maxf(phase_army_desire, float(army_power) / army_target_power),
		0.0,
		1.0
	)
	if _strategic_phase == StrategicPhase.EARLY_ARMY and pikemen_count < EARLY_ARMY_TARGET_PIKEMEN:
		desires["army"] = maxf(desires["army"], DESIRE_HIGH)
	if _recent_loss_timer > 0.0:
		desires["army"] = maxf(desires["army"], DESIRE_HIGH)

	if _strategic_phase == StrategicPhase.CREEPING:
		desires["creep"] = DESIRE_HIGH if hero_alive else DESIRE_LOW
		## First military objective: keep army desire high enough to finish the escort,
		## but do not stall creeping waiting for a large attack army.
		if combat_units < EnemyArmyCommand.CREEP_PREFERRED_NON_HERO_UNITS:
			desires["army"] = maxf(desires["army"], DESIRE_MEDIUM)
	elif (
		_strategic_phase != StrategicPhase.EARLY_ARMY
		and _strategic_phase != StrategicPhase.OPENING
		and hero_alive
		and army_power >= int(army_target_power * 0.6)
		and not is_phase_at_least(StrategicPhase.MID_GAME)
	):
		desires["creep"] = clampf(
			0.35 + float(hero_level) * 0.08 + (0.2 if army_power >= 400 else 0.0),
			0.0,
			1.0
		)
	else:
		desires["creep"] = minf(desires["creep"], DESIRE_LOW)

	if (
		_phase_interrupt_active
		or not hero_alive
		or EnemyArmyCommand.is_rebuilding_army()
		or (_recent_loss_timer > 0.0 and not EnemyAggression.is_aggression_mode_active())
		or (_recent_attack_failed and not EnemyAggression.is_aggression_mode_active())
		or not is_phase_at_least(StrategicPhase.EXPANSION)
	):
		desires["attack"] = minf(desires["attack"], DESIRE_LOW)
	elif not _can_launch_offensive_attack() and not EnemyAggression.is_aggression_mode_active():
		desires["attack"] = DESIRE_LOW
	elif EnemyAggression.should_boost_attack_desire():
		var confidence: EnemyAggression.Confidence = EnemyAggression.get_confidence()
		match confidence:
			EnemyAggression.Confidence.VERY_HIGH:
				desires["attack"] = 1.0
			EnemyAggression.Confidence.HIGH:
				desires["attack"] = maxf(desires["attack"], 0.9)
			EnemyAggression.Confidence.MEDIUM:
				desires["attack"] = maxf(desires["attack"], DESIRE_HIGH)
			_:
				desires["attack"] = maxf(desires["attack"], DESIRE_MEDIUM)
		desires["creep"] = minf(desires["creep"], DESIRE_LOW)
		desires["army"] = maxf(desires["army"], DESIRE_HIGH)
	elif visible_enemy_power > 0 and army_power >= int(float(visible_enemy_power) * EnemyArmyCommand.PLAYER_ARMY_STRENGTH_RATIO):
		desires["attack"] = clampf(
			0.5 + float(army_power - visible_enemy_power) / 600.0,
			DESIRE_MEDIUM,
			1.0
		)
	elif is_phase_at_least(StrategicPhase.LATE_GAME) and army_power >= EnemyArmyCommand.MIN_ATTACK_ARMY_POWER:
		desires["attack"] = maxf(desires["attack"], DESIRE_HIGH)
	elif is_phase_at_least(StrategicPhase.MID_GAME) and army_power >= EnemyArmyCommand.MIN_ATTACK_ARMY_POWER:
		desires["attack"] = maxf(desires["attack"], DESIRE_MEDIUM)
	else:
		desires["attack"] = clampf(
			float(army_power) / (army_target_power * 1.4),
			DESIRE_LOW,
			DESIRE_MEDIUM
		)

	if EnemyAggression.should_suspend_creeping():
		desires["creep"] = 0.0
		desires["expansion"] = minf(desires["expansion"], DESIRE_LOW)

	if _strategic_phase == StrategicPhase.EXPANSION:
		desires["expansion"] = DESIRE_HIGH if economy_healthy else DESIRE_MEDIUM
	elif economy_healthy and is_phase_at_least(StrategicPhase.EXPANSION) and desires["defense"] < DESIRE_MEDIUM:
		desires["expansion"] = clampf(
			0.25
			+ float(snapshot.get("expansion_count", 0)) * -0.1
			+ (0.2 if workers >= 16 else 0.0),
			0.0,
			0.85
		)
	else:
		desires["expansion"] = minf(desires["expansion"], DESIRE_LOW)

	if _strategic_phase in [StrategicPhase.TIER_2, StrategicPhase.TIER_3]:
		desires["upgrade"] = DESIRE_HIGH
	elif hero_alive and hero_level >= 2 and economy_healthy and is_phase_at_least(StrategicPhase.TIER_2):
		desires["upgrade"] = clampf(0.3 + float(hero_level) * 0.05, DESIRE_LOW, 0.9)
	else:
		desires["upgrade"] = minf(desires["upgrade"], DESIRE_LOW)

	if combat_units < get_min_army_size_for_current_phase():
		desires["army"] = maxf(desires["army"], DESIRE_MEDIUM)


func _apply_phase_desire_baseline() -> void:
	match _strategic_phase:
		StrategicPhase.OPENING:
			desires["economy"] = 0.9
			desires["army"] = 0.15
			desires["creep"] = 0.0
			desires["attack"] = 0.0
			desires["expansion"] = 0.0
			desires["upgrade"] = 0.0
		StrategicPhase.EARLY_ARMY:
			desires["economy"] = 0.55
			desires["army"] = 0.85
			desires["creep"] = 0.0
			desires["attack"] = 0.0
			desires["expansion"] = 0.0
			desires["upgrade"] = 0.0
		StrategicPhase.CREEPING:
			desires["economy"] = 0.55
			desires["army"] = 0.55
			desires["creep"] = 0.85
			desires["attack"] = 0.0
			desires["expansion"] = 0.05
			desires["upgrade"] = 0.35
		StrategicPhase.TIER_2:
			desires["economy"] = 0.5
			desires["army"] = 0.45
			desires["creep"] = 0.2
			desires["attack"] = 0.15
			desires["expansion"] = 0.15
			desires["upgrade"] = 0.85
		StrategicPhase.EXPANSION:
			desires["economy"] = 0.8
			desires["army"] = 0.4
			desires["creep"] = 0.15
			desires["attack"] = 0.2
			desires["expansion"] = 0.9
			desires["upgrade"] = 0.25
		StrategicPhase.MID_GAME:
			desires["economy"] = 0.55
			desires["army"] = 0.7
			desires["creep"] = 0.2
			desires["attack"] = 0.45
			desires["expansion"] = 0.25
			desires["upgrade"] = 0.55
		StrategicPhase.TIER_3:
			desires["economy"] = 0.5
			desires["army"] = 0.55
			desires["creep"] = 0.1
			desires["attack"] = 0.35
			desires["expansion"] = 0.2
			desires["upgrade"] = 0.9
		StrategicPhase.LATE_GAME:
			desires["economy"] = 0.45
			desires["army"] = 0.8
			desires["creep"] = 0.1
			desires["attack"] = 0.75
			desires["expansion"] = 0.3
			desires["upgrade"] = 0.6


func _recommend_main_army_mission() -> void:
	if (
		_phase_interrupt_active
		or EnemyArmyCommand.get_strategic_state() == EnemyArmyCommand.StrategicState.EMERGENCY_DEFENDING
	):
		_set_main_mission(EnemyUnitMission.Mission.DEFEND, "emergency defending")
		return

	if EnemyArmyCommand.get_strategic_state() == EnemyArmyCommand.StrategicState.RETREATING:
		_set_main_mission(EnemyUnitMission.Mission.RETREAT, "retreating")
		return

	if desires["defense"] >= DESIRE_HIGH:
		return

	if _strategic_phase in [StrategicPhase.OPENING, StrategicPhase.EARLY_ARMY]:
		_set_main_mission(
			EnemyUnitMission.Mission.RALLY,
			"early army assembling at rally"
		)
		return

	if _strategic_phase == StrategicPhase.CREEPING:
		_set_main_mission(
			EnemyUnitMission.Mission.CREEP,
			"creeping phase owns army"
		)
		return

	if _strategic_phase == StrategicPhase.TIER_2:
		var army_mode_tier_2: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
		if army_mode_tier_2 in [
			EnemyArmyCommand.ArmyMode.DEFENDING,
			EnemyArmyCommand.ArmyMode.INTERCEPTING,
		]:
			_set_main_mission(EnemyUnitMission.Mission.DEFEND, "tier 2 defending")
			return
		if army_mode_tier_2 == EnemyArmyCommand.ArmyMode.CREEPING or should_prioritize_creep():
			_set_main_mission(
				EnemyUnitMission.Mission.CREEP,
				"tier 2 safe creep camp"
			)
			return
		_set_main_mission(
			EnemyUnitMission.Mission.RALLY,
			"tier 2 holding hero and army together"
		)
		return

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	match army_mode:
		EnemyArmyCommand.ArmyMode.DEFENDING, EnemyArmyCommand.ArmyMode.INTERCEPTING:
			_set_main_mission(EnemyUnitMission.Mission.DEFEND, "army defending")
			return
		EnemyArmyCommand.ArmyMode.ATTACKING:
			_set_main_mission(EnemyUnitMission.Mission.ATTACK, "army attacking")
			return
		EnemyArmyCommand.ArmyMode.CREEPING:
			_set_main_mission(EnemyUnitMission.Mission.CREEP, "army clearing creep camp")
			return

	if _recent_loss_timer > 0.0 or desires["army"] >= DESIRE_HIGH:
		_set_main_mission(
			EnemyUnitMission.Mission.RALLY,
			"rebuilding army (power %d)" % int(snapshot.get("army_power", 0))
		)
		return

	if should_prioritize_creep():
		_set_main_mission(
			EnemyUnitMission.Mission.CREEP,
			"safe creep available, army power %d" % int(snapshot.get("army_power", 0))
		)
		return

	if should_prioritize_attack():
		if not _can_launch_offensive_attack():
			_set_main_mission(
				EnemyUnitMission.Mission.RALLY,
				"attack gate not met, army power %d" % int(snapshot.get("army_power", 0))
			)
			return

		_set_main_mission(
			EnemyUnitMission.Mission.ATTACK,
			"attack desire %.2f, hero %s" % [
				get_desire("attack"),
				"alive" if snapshot.get("hero_alive", false) else "dead",
			]
		)
		return

	_set_main_mission(
		EnemyUnitMission.Mission.RALLY,
		"holding at rally, army power %d" % int(snapshot.get("army_power", 0))
	)


func _set_main_mission(mission: EnemyUnitMission.Mission, reason: String) -> void:
	if not EnemyUnitMission.set_main_army_mission(mission, reason):
		return

	_last_debug_mission = mission
	_sync_hero_to_main_mission()


func _sync_hero_to_main_mission() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero == null:
		return

	EnemyUnitMission.sync_hero_to_main_army(hero)


func _run_recovery_checks() -> void:
	if EnemyArmyCommand.is_attack_wave_controlling_hero():
		return

	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if EnemyArmyCommand.get_army_mode() in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]:
		return

	var main_mission: EnemyUnitMission.Mission = EnemyUnitMission.get_main_army_mission()
	var creep_manager: EnemyCreepManager = (
		get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
		if get_parent() != null
		else null
	)
	var creep_mission_active: bool = (
		creep_manager != null and creep_manager.is_creep_mission_active()
	)
	if (
		main_mission == EnemyUnitMission.Mission.RALLY
		or main_mission == EnemyUnitMission.Mission.ATTACK
		or (
			main_mission == EnemyUnitMission.Mission.CREEP
			and not creep_mission_active
		)
	):
		EnemyArmyCommand.pull_reinforcement_units_to_rally(tree, rally_position)

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero == null:
		return

	EnemyUnitMission.sync_hero_to_main_army(hero)
	if EnemyUnitMission.get_unit_mission(hero) == EnemyUnitMission.Mission.SHOP:
		return

	var non_hero: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(tree)
	if non_hero.is_empty():
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(non_hero)
	if army_center == Vector3.ZERO:
		return

	if (
		EnemyArmyCommand.horizontal_distance(hero.global_position, army_center)
		> EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY * 1.5
		and main_mission != EnemyUnitMission.Mission.RETREAT
	):
		EnemyArmyCommand.assign_reinforcement_regroup(tree, hero)


func _maybe_log_debug() -> void:
	if not debug_enabled:
		return

	EnemyAIDebug.set_enabled(true)

	for key: String in desires.keys():
		var current: float = float(desires[key])
		var previous: float = float(_last_debug_desires.get(key, -1.0))
		if absf(current - previous) >= 0.15:
			_last_debug_desires = desires.duplicate()
			return


func _collect_workers(tree: SceneTree) -> Array:
	var workers: Array = []
	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, &"enemy_workers"):
		var node: Node = node_variant as Node
		if not NodeSafety.is_alive_node(node):
			continue

		if node is Worker and (node as Worker).get_current_health() > 0:
			workers.append(node)
	return NodeSafety.clean_node_array(workers)


func _is_idle_worker(worker) -> bool:
	if not NodeSafety.is_alive_node(worker):
		return false

	if not worker is Worker:
		return false

	if worker.is_on_construction_trip() or worker.is_carrying_gathered_resources():
		return false

	if worker.has_method(&"is_enemy_gather_fallback_idle"):
		return worker.is_enemy_gather_fallback_idle()

	return worker.needs_gather_target_reassignment()


func _count_group(tree: SceneTree, group_name: StringName) -> int:
	return CombatTargetValidation.get_cached_group_nodes(tree, group_name).size()


func _count_barracks(tree: SceneTree) -> int:
	var count: int = 0
	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		&"enemy_command_center"
	):
		var node: Node = node_variant as Node
		if node is Barracks:
			count += 1
	return count


func _count_enemy_buildings(tree: SceneTree) -> Dictionary:
	var farms: int = 0
	var barracks: int = 0
	var altars: int = 0
	var blacksmiths: int = 0
	var shops: int = 0
	var stables: int = 0
	var command_centers: int = 0

	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		&"enemy_command_center"
	):
		var node: Node = node_variant as Node
		if not NodeSafety.is_alive_node(node):
			continue

		if not node is Building:
			continue

		var building: Building = node as Building
		if building.building_state != Building.STATE_COMPLETED:
			continue

		var health_component: HealthComponent = building.get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		if health_component != null and health_component.current_health <= 0:
			continue

		if building is CommandCenter:
			command_centers += 1
		elif building is Farm:
			farms += 1
		elif building is Barracks:
			barracks += 1
		elif building is HeroAltar:
			altars += 1
		elif building is Blacksmith:
			blacksmiths += 1
		elif building is Shop:
			shops += 1
		elif building is Stable:
			stables += 1

	return {
		"command_centers": command_centers,
		"farms": farms,
		"barracks": barracks,
		"has_farm": farms > 0,
		"has_barracks": barracks > 0,
		"has_hero_altar": altars > 0,
		"has_blacksmith": blacksmiths > 0,
		"has_shop": shops > 0,
		"has_stable": stables > 0,
	}


func _count_pikemen(units: Array) -> int:
	var count: int = 0
	for unit: Variant in units:
		if unit is Spearman:
			count += 1
	return count


func _is_early_army_rallied(
	rally_position: Vector3,
	combat_units: Array,
	hero: Hero
) -> bool:
	if rally_position == Vector3.ZERO:
		return false

	if combat_units.is_empty():
		return false

	var nearby: Array = EnemyArmyCommand.filter_units_near_rally(
		combat_units,
		rally_position,
		EnemyArmyCommand.ASSEMBLY_RADIUS * 2.0
	)
	var required_nearby: int = maxi(
		1,
		int(ceil(float(combat_units.size()) * EARLY_ARMY_RALLY_RATIO))
	)
	if nearby.size() < required_nearby:
		return false

	if hero != null:
		if (
			EnemyArmyCommand.horizontal_distance(hero.global_position, rally_position)
			> EnemyArmyCommand.ASSEMBLY_RADIUS * 2.0
		):
			return false

	return true


func _get_primary_command_center_health_ratio(tree: SceneTree) -> float:
	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		&"enemy_command_center"
	):
		var node: Node = node_variant as Node
		if not node is CommandCenter:
			continue

		var command_center: CommandCenter = node as CommandCenter
		if not NodeSafety.is_alive_node(command_center):
			continue

		if command_center.building_state != Building.STATE_COMPLETED:
			continue

		var health_component: HealthComponent = command_center.get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		if health_component == null or health_component.max_health <= 0:
			return 1.0

		return float(health_component.current_health) / float(health_component.max_health)

	return 1.0


func get_match_elapsed_seconds() -> float:
	return _get_match_elapsed_seconds()


func _get_match_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func _can_launch_offensive_attack() -> bool:
	if not can_launch_player_attack():
		return false

	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	return EnemyArmyCommand.evaluate_attack_gate(tree, rally_position).get("can_commit", false)
