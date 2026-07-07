class_name EnemyWaveManager
extends Node

## Launches scaled enemy attack waves on a timer and keeps the enemy hero with the army.

const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const HERO_BEHAVIOR_INTERVAL_SECONDS := 1.0
const MIN_HERO_LEVEL_FOR_ATTACK: int = 2
const MIN_CLEARED_CAMPS_FOR_ATTACK: int = 2
const FIRST_ATTACK_FALLBACK_SECONDS: float = 240.0
const ARMY_REGROUP_INTERVAL_SECONDS: float = 5.0
const WAVE_GATHER_PULL_INTERVAL_SECONDS: float = 1.0
const FALLBACK_ATTACK_MIN_COMBAT_UNITS: int = 25
const FALLBACK_ATTACK_READY_SECONDS: float = 10.0
const HERO_EXECUTE_SEARCH_RANGE := 14.0

@export var player_command_center_path: NodePath
@export var wave_interval_seconds: float = 35.0

var _wave_active: bool = true
var _waves_launched: int = 0
var _tracked_player_command_center: CommandCenter = null
var _hero_behavior_timer: float = 0.0
var _regroup_timer: float = 0.0
var _wave_gather_timer: float = -1.0
var _wave_gather_pull_timer: float = 0.0
var _pending_wave_units: Array = []
var _pending_attack_destination: Vector3 = Vector3.ZERO
var _pending_min_non_hero_units: int = 0
var _rebuilding_army_after_wave: bool = false
var _last_wave_non_hero_count: int = 0
var _match_start_msec: int = 0
var _creep_manager: EnemyCreepManager = null
var _director: EnemyStrategicDirector = null
var _large_army_ready_timer: float = 0.0
var _cached_player_base_position: Vector3 = Vector3.ZERO
var _finishing_reinforcement_timer: float = 0.0
var _finishing_attack_retry_timer: float = 0.0
var _was_finishing_mode_active: bool = false


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_creep_manager = get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
	_director = get_parent().get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector
	_tracked_player_command_center = _resolve_player_command_center()
	if _tracked_player_command_center != null:
		_tracked_player_command_center.destroyed.connect(
			_on_player_command_center_destroyed,
			CONNECT_ONE_SHOT
		)
	_schedule_next_wave()


func _process(delta: float) -> void:
	EnemyArmyCommand.update_finishing_mode(get_tree(), delta)
	_cache_player_base_position()
	_process_wave_gather(delta)
	_process_large_army_fallback(delta)
	_process_finishing_mode(delta)

	_hero_behavior_timer += delta
	if _hero_behavior_timer >= HERO_BEHAVIOR_INTERVAL_SECONDS:
		_hero_behavior_timer = 0.0
		_update_hero_army_behavior()

	_monitor_active_offensive_push()
	EnemyArmyCommand.maintain_attack_wave_objective(get_tree(), delta)

	_regroup_timer += delta
	if _regroup_timer >= ARMY_REGROUP_INTERVAL_SECONDS:
		_regroup_timer = 0.0
		_enforce_army_regroup_when_waiting()


func _update_hero_army_behavior() -> void:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null or not is_instance_valid(hero):
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var health_ratio: float = EnemyArmyCommand.get_health_ratio(hero)

	_try_enemy_hero_abilities(hero, health_ratio)

	if EnemyArmyCommand.is_emergency_defense_active():
		var emergency_objective: Vector3 = EnemyArmyCommand.get_emergency_defense_objective()
		if health_ratio < EnemyArmyCommand.HERO_DEFENSE_CRITICAL_RETREAT_HP_RATIO:
			EnemyArmyCommand.command_retreat_hero(hero, rally_position)
			return
		if (
			emergency_objective != Vector3.ZERO
			and health_ratio >= EnemyArmyCommand.EMERGENCY_HERO_JOIN_HP_RATIO
		):
			EnemyArmyCommand.command_attack_move(
				[hero],
				emergency_objective,
				EnemyUnitMission.Mission.DEFEND
			)
		return

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		if health_ratio < EnemyArmyCommand.HERO_DEFENSE_CRITICAL_RETREAT_HP_RATIO:
			EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	if EnemyArmyCommand.is_hero_isolated_near_player_threat(get_tree(), hero):
		if not EnemyArmyCommand.is_finishing_mode_active():
			_abort_active_offensive_push(rally_position)
			EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	var max_hero_distance: float = EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY
	if army_mode == EnemyArmyCommand.ArmyMode.ATTACKING:
		max_hero_distance *= 0.75

	var non_hero_units: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree())
	var finishing_mode: bool = EnemyArmyCommand.is_finishing_mode_active()

	if health_ratio < EnemyArmyCommand.HERO_RETREAT_HP_RATIO:
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	if not finishing_mode and non_hero_units.size() < EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN:
		_abort_active_offensive_push(rally_position)
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(non_hero_units)
	if army_center == Vector3.ZERO:
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	var distance_to_army: float = _horizontal_distance(hero.global_position, army_center)
	if distance_to_army > max_hero_distance:
		EnemyArmyCommand.command_retreat_hero(hero, army_center)
		return

	if non_hero_units.size() < EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN:
		if finishing_mode:
			return
		var distance_to_rally: float = _horizontal_distance(hero.global_position, rally_position)
		if distance_to_rally > EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY * 0.5:
			_abort_active_offensive_push(rally_position)
			EnemyArmyCommand.command_retreat_hero(hero, rally_position)


func _monitor_active_offensive_push() -> void:
	if EnemyArmyCommand.get_army_mode() != EnemyArmyCommand.ArmyMode.ATTACKING:
		return

	if not EnemyArmyCommand.should_abort_offensive_push(get_tree()):
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	_abort_active_offensive_push(rally_position)


func _abort_active_offensive_push(rally_position: Vector3) -> void:
	if EnemyArmyCommand.abort_offensive_and_regroup(get_tree()):
		_rebuilding_army_after_wave = true
		_cancel_pending_wave_gather()

	if rally_position == Vector3.ZERO:
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero != null and is_instance_valid(hero):
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)


func _cancel_pending_wave_gather() -> void:
	_wave_gather_timer = -1.0
	_wave_gather_pull_timer = 0.0
	_pending_wave_units.clear()
	_pending_attack_destination = Vector3.ZERO
	_pending_min_non_hero_units = 0


func _process_wave_gather(delta: float) -> void:
	if _wave_gather_timer < 0.0:
		return

	_wave_gather_timer += delta
	_wave_gather_pull_timer += delta

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	if rally_position == Vector3.ZERO:
		_cancel_pending_wave_gather()
		return

	if _wave_gather_pull_timer >= WAVE_GATHER_PULL_INTERVAL_SECONDS:
		_wave_gather_pull_timer = 0.0
		if EnemyArmyCommand.is_finishing_mode_active():
			EnemyArmyCommand.pull_finishing_reinforcements_to_attack(get_tree())
		else:
			EnemyArmyCommand.pull_straggler_units_to_rally(get_tree(), rally_position)
			EnemyArmyCommand.pull_reinforcement_units_to_rally(get_tree(), rally_position)

	var gather_wait_seconds: float = (
		0.0
		if EnemyArmyCommand.is_finishing_mode_active()
		else EnemyArmyCommand.WAVE_REINFORCEMENT_WAIT_SECONDS
	)
	if _wave_gather_timer < gather_wait_seconds:
		return

	var refreshed_plan: Dictionary = EnemyArmyCommand.build_regrouped_attack_wave_units(
		get_tree(),
		rally_position,
		_pending_min_non_hero_units
	)
	var wave_units: Array = refreshed_plan.get("units", [])
	var attack_destination: Vector3 = _pending_attack_destination
	var min_non_hero_units: int = _pending_min_non_hero_units
	var attack_commitment: Dictionary = EnemyArmyCommand.can_commit_attack_wave(
		get_tree(),
		wave_units,
		rally_position,
		min_non_hero_units,
		_get_match_elapsed_seconds()
	)
	_cancel_pending_wave_gather()

	if not attack_commitment.get("can_commit", false):
		_hold_army_when_too_weak_to_attack(rally_position)
		if _director != null:
			_director.notify_attack_failed()
		return

	_launch_attack_wave(wave_units, attack_destination)


func _launch_attack_wave(wave_units: Array, attack_destination: Vector3) -> void:
	if not EnemyArmyCommand.try_claim_army_mode(
		EnemyArmyCommand.ArmyMode.ATTACKING,
		true
	):
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var objective: Dictionary = EnemyArmyCommand.resolve_attack_objective(
		get_tree(),
		attack_destination if attack_destination != Vector3.ZERO else rally_position
	)
	attack_destination = objective.get("position", attack_destination)
	EnemyArmyCommand.set_attack_objective(
		objective.get("node") as Node3D,
		attack_destination
	)

	EnemyArmyCommand.begin_offensive_wave(wave_units)
	EnemyArmyCommand.set_rebuilding_army(false)
	EnemyArmyCommand.command_attack_move(
		wave_units,
		attack_destination,
		EnemyUnitMission.Mission.ATTACK
	)
	print(
		"[AI Wave] launching attack with %d units to %s"
		% [wave_units.size(), str(attack_destination)]
	)
	if _director != null:
		_director.notify_attack_launched()
	_waves_launched += 1
	_last_wave_non_hero_count = 0
	for unit: Variant in wave_units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if unit is Hero:
			continue

		if EnemyArmyCommand.is_non_hero_combat_unit(unit as Node):
			_last_wave_non_hero_count += 1

	_rebuilding_army_after_wave = true
	EnemyArmyCommand.set_rebuilding_army(true)


func _try_enemy_hero_abilities(hero: Hero, health_ratio: float) -> void:
	if not NodeSafety.is_alive_node(hero):
		return
	if not CombatTargetValidation.is_enemy_faction(hero):
		return

	_ensure_enemy_hero_combat_abilities(hero)

	if (
		health_ratio < EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO
		and hero.has_method("can_use_divine_protection")
		and hero.can_use_divine_protection()
	):
		hero.try_divine_protection()

	if hero.has_method("can_use_execute") and hero.can_use_execute(
		HERO_EXECUTE_SEARCH_RANGE
	):
		hero.try_execute()
	elif hero.has_method("can_use_power_strike") and hero.can_use_power_strike(
		EnemyArmyCommand.HERO_POWER_STRIKE_SEARCH_RANGE
	):
		hero.try_power_strike()

	if (
		hero.has_method("can_use_ground_slam")
		and hero.can_use_ground_slam()
		and _count_player_military_near_hero(hero) >= EnemyArmyCommand.HERO_AOE_PLAYER_COUNT
	):
		hero.try_ground_slam()


func _ensure_enemy_hero_combat_abilities(hero: Hero) -> void:
	if hero.ability_progression == null:
		return

	for ability_id: StringName in HeroAbilityProgression.BASIC_ABILITIES:
		while hero.get_ability_rank(ability_id) < HeroAbilityProgression.MAX_BASIC_RANK:
			hero.ability_progression.learn_ability(ability_id)

	while hero.get_ability_rank(HeroAbilityProgression.ABILITY_R) < HeroAbilityProgression.MAX_ULTIMATE_RANK:
		hero.ability_progression.learn_ability(HeroAbilityProgression.ABILITY_R)


func _count_player_military_near_hero(hero: Hero) -> int:
	var count: int = 0
	var search_range: float = EnemyArmyCommand.HERO_AOE_CHECK_RANGE

	for group_name: StringName in [&"units", &"heroes"]:
		for node: Node in get_tree().get_nodes_in_group(group_name):
			if CombatTargetValidation.is_enemy_faction(node):
				continue

			if not (node is Spearman or node is Swordsman or node is Archer or node is HeavyCavalry or node is LightCavalry or node is CavalryArcher or node is Hero):
				continue

			if node is Worker:
				continue

			var health_component: HealthComponent = node.get_node_or_null(
				"HealthComponent"
			) as HealthComponent
			if health_component != null and health_component.current_health <= 0:
				continue

			var target: Node3D = node as Node3D
			if _horizontal_distance(hero.global_position, target.global_position) > search_range:
				continue

			count += 1

	return count


func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length()


func _schedule_next_wave() -> void:
	if not _wave_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(wave_interval_seconds)
	wait_timer.timeout.connect(_on_wave_timer, CONNECT_ONE_SHOT)


func _on_wave_timer() -> void:
	if not _wave_active:
		return

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		_schedule_next_wave()
		return

	if _wave_gather_timer >= 0.0:
		_schedule_next_wave()
		return

	if not _has_any_attack_target():
		_wave_active = false
		return

	if EnemyArmyCommand.is_finishing_mode_active():
		_try_launch_finishing_wave()
		_schedule_next_wave()
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var match_elapsed_seconds: float = _get_match_elapsed_seconds()
	var min_non_hero_units: int = EnemyArmyCommand.get_effective_attack_min_non_hero_units(
		match_elapsed_seconds
	)

	if _should_delay_offensive_wave(rally_position):
		_log_wave_trigger_wait(&"creep_phase_delay", match_elapsed_seconds, min_non_hero_units)
		_hold_army_for_creep_phase(rally_position)
		_schedule_next_wave()
		return

	_update_wave_rebuild_state(rally_position, min_non_hero_units)

	if _rebuilding_army_after_wave:
		_log_wave_trigger_wait(
			&"rebuilding_after_wave",
			match_elapsed_seconds,
			min_non_hero_units
		)
		_hold_army_until_ready(rally_position, _count_regrouped_non_hero_units(rally_position))
		_schedule_next_wave()
		return

	var total_non_hero: int = EnemyArmyCommand.collect_living_non_hero_combat_units(
		get_tree()
	).size()
	if total_non_hero < min_non_hero_units:
		_log_wave_trigger_wait(
			&"army_too_small",
			match_elapsed_seconds,
			min_non_hero_units,
			{"total_non_hero": total_non_hero}
		)
		_hold_army_until_ready(rally_position, _count_regrouped_non_hero_units(rally_position))
		_schedule_next_wave()
		return

	if not EnemyArmyCommand.is_army_regrouped_at_rally(
		get_tree(),
		rally_position,
		min_non_hero_units
	):
		_log_wave_trigger_wait(
			&"not_regrouped",
			match_elapsed_seconds,
			min_non_hero_units,
			{"regrouped_non_hero": _count_regrouped_non_hero_units(rally_position)}
		)
		if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
			EnemyArmyCommand.command_regroup_at_rally(get_tree(), rally_position)
		_schedule_next_wave()
		return

	var wave_plan: Dictionary = EnemyArmyCommand.build_regrouped_attack_wave_units(
		get_tree(),
		rally_position,
		min_non_hero_units
	)

	if not wave_plan.get("can_launch", false):
		_log_wave_trigger_wait(
			&"wave_plan_not_ready",
			match_elapsed_seconds,
			min_non_hero_units,
			{
				"regrouped_non_hero": int(wave_plan.get("non_hero_count", 0)),
				"total_non_hero": int(wave_plan.get("total_non_hero_count", 0)),
			}
		)
		_hold_army_until_ready(
			rally_position,
			int(wave_plan.get("non_hero_count", 0))
		)
		_schedule_next_wave()
		return

	var wave_units: Array = wave_plan.get("units", [])
	var attack_commitment: Dictionary = EnemyArmyCommand.can_commit_attack_wave(
		get_tree(),
		wave_units,
		rally_position,
		min_non_hero_units,
		match_elapsed_seconds
	)
	if not attack_commitment.get("can_commit", false):
		_hold_army_when_too_weak_to_attack(rally_position)
		if _director != null:
			_director.notify_attack_failed()
		_schedule_next_wave()
		return

	var attack_destination: Vector3 = EnemyArmyCommand.resolve_wave_attack_destination(
		get_tree(),
		rally_position
	)
	if _director != null:
		if not _director.should_prioritize_attack() and _should_delay_offensive_wave(rally_position):
			_hold_army_for_creep_phase(rally_position)
			_schedule_next_wave()
			return
		_director.set_attack_target_position(attack_destination)

	_begin_wave_gather(wave_units, attack_destination, min_non_hero_units)
	_log_wave_trigger_wait(
		&"wave_gather_started",
		match_elapsed_seconds,
		min_non_hero_units,
		{"wave_units": wave_units.size()}
	)
	_schedule_next_wave()


func _begin_wave_gather(
	wave_units: Array,
	attack_destination: Vector3,
	min_non_hero_units: int
) -> void:
	_pending_wave_units = wave_units.duplicate()
	_pending_attack_destination = attack_destination
	_pending_min_non_hero_units = min_non_hero_units
	_wave_gather_timer = 0.0
	_wave_gather_pull_timer = 0.0

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	if rally_position == Vector3.ZERO:
		return

	if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		EnemyArmyCommand.command_regroup_at_rally(get_tree(), rally_position)

	EnemyArmyCommand.pull_straggler_units_to_rally(get_tree(), rally_position)
	EnemyArmyCommand.pull_reinforcement_units_to_rally(get_tree(), rally_position)


func _should_delay_offensive_wave(rally_position: Vector3) -> bool:
	if _get_match_elapsed_seconds() >= FIRST_ATTACK_FALLBACK_SECONDS:
		return false

	if EnemyEarlyStrategy.should_attack_early(get_tree(), rally_position):
		return false

	if _creep_manager != null and _creep_manager.should_abandon_creep_phase():
		return false

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero != null and hero.level >= MIN_HERO_LEVEL_FOR_ATTACK:
		return false

	if _count_cleared_nearby_camps(rally_position) >= MIN_CLEARED_CAMPS_FOR_ATTACK:
		return false

	if not CreepCampSafety.has_uncleared_nearby_camps(
		get_tree(),
		rally_position,
		EnemyCreepManager.CREEP_SEARCH_RANGE
	):
		return false

	if _creep_manager != null and not _creep_manager.has_safe_creep_camp_available():
		return false

	return true


func _count_cleared_nearby_camps(rally_position: Vector3) -> int:
	return CreepCampSafety.count_cleared_enemy_side_camps(
		get_tree(),
		rally_position,
		EnemyCreepManager.CREEP_SEARCH_RANGE,
		EnemyCreepManager.CAMP_CLEAR_RADIUS
	)


func _get_match_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func _update_wave_rebuild_state(
	rally_position: Vector3,
	min_non_hero_units: int
) -> void:
	if not _rebuilding_army_after_wave:
		return

	var regrouped_count: int = _count_regrouped_non_hero_units(rally_position)
	if regrouped_count < min_non_hero_units:
		return

	var current_non_hero_count: int = EnemyArmyCommand.collect_living_non_hero_combat_units(
		get_tree()
	).size()
	if (
		_last_wave_non_hero_count > 0
		and EnemyArmyCommand.should_rebuild_army_after_wave(
			current_non_hero_count,
			_last_wave_non_hero_count
		)
		and regrouped_count < min_non_hero_units
	):
		EnemyArmyCommand.set_rebuilding_army(true)
		return

	_rebuilding_army_after_wave = false
	EnemyArmyCommand.set_rebuilding_army(false)


func _count_regrouped_non_hero_units(rally_position: Vector3) -> int:
	return EnemyArmyCommand.filter_units_near_rally(
		EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree()),
		rally_position
	).size()


func _enforce_army_regroup_when_waiting() -> void:
	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	if EnemyArmyCommand.is_finishing_mode_active():
		if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.ATTACKING:
			return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	if rally_position == Vector3.ZERO:
		return

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if army_mode == EnemyArmyCommand.ArmyMode.ATTACKING:
		if EnemyArmyCommand.should_abort_offensive_push(get_tree()):
			_abort_active_offensive_push(rally_position)
			if _director != null:
				_director.notify_army_losses()
		return

	var should_hold: bool = (
		_should_delay_offensive_wave(rally_position) or _rebuilding_army_after_wave
	)
	if EnemyArmyCommand.is_finishing_mode_active():
		should_hold = false
	if not should_hold and army_mode != EnemyArmyCommand.ArmyMode.REGROUPING:
		return

	_hold_army_for_creep_phase(rally_position)
	EnemyArmyCommand.pull_straggler_units_to_rally(get_tree(), rally_position)


func _hold_army_when_too_weak_to_attack(rally_position: Vector3) -> void:
	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(get_tree())
	if creep_plan.get("can_launch", false):
		return

	if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		EnemyArmyCommand.command_regroup_at_rally(get_tree(), rally_position)
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero != null and is_instance_valid(hero):
		EnemyArmyCommand.command_hold_at_rally([hero], rally_position)


func _log_wave_trigger_wait(
	reason: StringName,
	elapsed_seconds: float,
	required_non_hero: int,
	extra: Dictionary = {}
) -> void:
	if not EnemyArmyCommand.DEBUG_ATTACK_GATE:
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	var non_hero_units: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(
		get_tree()
	)
	var melee_count: int = 0
	var ranged_count: int = 0
	for unit: Variant in non_hero_units:
		if unit is Archer or unit is CavalryArcher:
			ranged_count += 1
		else:
			melee_count += 1

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var regrouped_count: int = _count_regrouped_non_hero_units(rally_position)
	var player_strength: String = str(
		EnemyArmyCommand.estimate_known_player_army_strength(get_tree(), rally_position)
	)
	if int(player_strength) <= 0:
		player_strength = "unknown"

	print(
		(
			"EnemyWaveTrigger [WAIT]: reason=%s hero_alive=%s combat=%d melee=%d "
			+ "ranged=%d regrouped=%d player_strength=%s rebuilding=%s "
			+ "elapsed=%.0fs required_non_hero=%d %s"
		)
		% [
			String(reason),
			str(hero != null),
			non_hero_units.size(),
			melee_count,
			ranged_count,
			regrouped_count,
			player_strength,
			str(EnemyArmyCommand.is_rebuilding_army()),
			elapsed_seconds,
			required_non_hero,
			str(extra),
		]
	)


func _hold_army_for_creep_phase(rally_position: Vector3) -> void:
	var non_hero_units: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(
		get_tree()
	)
	if non_hero_units.size() < EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN:
		var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
		if hero != null and is_instance_valid(hero):
			EnemyArmyCommand.command_hold_at_rally([hero], rally_position)
		return

	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(get_tree())
	if creep_plan.get("can_launch", false):
		return

	if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		EnemyArmyCommand.command_regroup_at_rally(get_tree(), rally_position)


func _hold_army_until_ready(rally_position: Vector3, non_hero_count: int) -> void:
	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null or not is_instance_valid(hero):
		return

	if not EnemyArmyCommand.is_hero_healthy_enough_for_wave(hero):
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)

	var min_non_hero_units: int = EnemyArmyCommand.get_effective_attack_min_non_hero_units(
		_get_match_elapsed_seconds()
	)
	if (
		non_hero_count < min_non_hero_units
		and EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING)
	):
		EnemyArmyCommand.command_regroup_at_rally(get_tree(), rally_position)


func _has_any_attack_target() -> bool:
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	return EnemyArmyCommand.has_player_attack_targets(get_tree(), rally_position)


func _cache_player_base_position() -> void:
	var command_center: CommandCenter = _resolve_player_command_center()
	if command_center != null:
		_cached_player_base_position = command_center.global_position
		return

	if _cached_player_base_position != Vector3.ZERO:
		return

	if not player_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(player_command_center_path)
		if path_node is Node3D:
			_cached_player_base_position = (path_node as Node3D).global_position


func _process_large_army_fallback(delta: float) -> void:
	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if (
		army_mode == EnemyArmyCommand.ArmyMode.DEFENDING
		or army_mode == EnemyArmyCommand.ArmyMode.ATTACKING
	):
		_large_army_ready_timer = 0.0
		return

	if _wave_gather_timer >= 0.0:
		return

	var non_hero_count: int = EnemyArmyCommand.collect_living_non_hero_combat_units(
		get_tree()
	).size()
	if non_hero_count < FALLBACK_ATTACK_MIN_COMBAT_UNITS:
		_large_army_ready_timer = 0.0
		return

	_large_army_ready_timer += delta
	if _large_army_ready_timer < FALLBACK_ATTACK_READY_SECONDS:
		return

	_large_army_ready_timer = 0.0
	_try_launch_fallback_attack()


func _try_launch_fallback_attack() -> void:
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var attack_destination: Vector3 = _resolve_fallback_attack_destination(rally_position)
	if attack_destination == Vector3.ZERO:
		return

	var wave_units: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(
		get_tree()
	)
	if wave_units.size() < FALLBACK_ATTACK_MIN_COMBAT_UNITS:
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero != null and NodeSafety.is_alive_node(hero):
		wave_units.append(hero)

	_rebuilding_army_after_wave = false
	EnemyArmyCommand.set_rebuilding_army(false)
	_cancel_pending_wave_gather()

	if _director != null:
		_director.set_attack_target_position(attack_destination)

	_launch_attack_wave(wave_units, attack_destination)


func _resolve_fallback_attack_destination(rally_position: Vector3) -> Vector3:
	return EnemyArmyCommand.resolve_attack_objective(get_tree(), rally_position).get(
		"position",
		Vector3.ZERO
	)


func _resolve_player_command_center() -> CommandCenter:
	if not NodeSafety.is_alive_node(_tracked_player_command_center):
		_tracked_player_command_center = null

	if _tracked_player_command_center != null and _is_living_command_center(
		_tracked_player_command_center
	):
		return _tracked_player_command_center

	if not player_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(player_command_center_path)
		if path_node is CommandCenter and _is_living_command_center(path_node as CommandCenter):
			return path_node as CommandCenter

	for node: Node in get_tree().get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_command_center(node as CommandCenter):
			return node as CommandCenter

	return null


func _is_living_command_center(command_center: CommandCenter) -> bool:
	if command_center == null or not is_instance_valid(command_center):
		return false

	if command_center.is_queued_for_deletion():
		return false

	var health_component: HealthComponent = command_center.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


func _on_player_command_center_destroyed(_building: Building) -> void:
	_tracked_player_command_center = null


func _process_finishing_mode(delta: float) -> void:
	if not EnemyArmyCommand.is_finishing_mode_active():
		_finishing_reinforcement_timer = 0.0
		_finishing_attack_retry_timer = 0.0
		_was_finishing_mode_active = false
		return

	if EnemyArmyCommand.is_emergency_defense_active():
		return

	if not _was_finishing_mode_active:
		_was_finishing_mode_active = true
		_try_launch_finishing_attack()

	_rebuilding_army_after_wave = false
	EnemyArmyCommand.set_rebuilding_army(false)

	_finishing_reinforcement_timer += delta
	if (
		_finishing_reinforcement_timer
		>= EnemyArmyCommand.FINISHING_MODE_REINFORCEMENT_PULL_INTERVAL
	):
		_finishing_reinforcement_timer = 0.0
		EnemyArmyCommand.pull_finishing_reinforcements_to_attack(get_tree())

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.ATTACKING:
		_finishing_attack_retry_timer = 0.0
		return

	_finishing_attack_retry_timer += delta
	if _finishing_attack_retry_timer < 3.0:
		return

	_finishing_attack_retry_timer = 0.0
	_try_launch_finishing_attack()


func _try_launch_finishing_wave() -> void:
	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.ATTACKING:
		EnemyArmyCommand.pull_finishing_reinforcements_to_attack(get_tree())
		return

	_try_launch_finishing_attack()


func _try_launch_finishing_attack() -> void:
	if not EnemyArmyCommand.is_finishing_mode_active():
		return

	if EnemyArmyCommand.is_emergency_defense_active():
		return

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	if _wave_gather_timer >= 0.0:
		_cancel_pending_wave_gather()

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	if rally_position == Vector3.ZERO:
		return

	var wave_units: Array = EnemyArmyCommand.collect_living_combat_units(get_tree())
	if wave_units.size() < EnemyArmyCommand.FINISHING_MODE_MIN_PUSH_UNITS:
		return

	var objective: Dictionary = EnemyArmyCommand.resolve_attack_objective(
		get_tree(),
		rally_position
	)
	var attack_destination: Vector3 = objective.get("position", Vector3.ZERO)
	if attack_destination == Vector3.ZERO:
		return

	_rebuilding_army_after_wave = false
	EnemyArmyCommand.set_rebuilding_army(false)

	if _director != null:
		_director.set_attack_target_position(attack_destination)

	_launch_attack_wave(wave_units, attack_destination)
