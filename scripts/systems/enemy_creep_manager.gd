class_name EnemyCreepManager
extends Node

## CREEPING-phase army: rally as one group, clear nearby camps with the hero, then advance.

const CREEP_TICK_INTERVAL_SECONDS: float = 1.25
const CREEP_SEARCH_RANGE: float = 48.0
const MAX_CREEP_DISTANCE_FROM_RALLY: float = 42.0
const CAMP_ENGAGEMENT_RADIUS: float = 20.0
const CAMP_CLEAR_RADIUS: float = 14.0
const ARMY_UNDER_ATTACK_RANGE: float = 22.0
const CAMP_POWER_MARGIN: float = 1.15
const STRONG_CAMP_POWER_MARGIN: float = 1.35
const STRONG_CAMP_POWER_THRESHOLD: int = 280
const CREEP_REGROUP_MAX_DISTANCE: float = 18.0
const CREEP_COHESION_RATIO: float = 0.75
const CREEP_DAMAGE_POWER_MULTIPLIER: float = 8.0
const MAX_CREEP_SETBACKS_BEFORE_ABANDON: int = 3
const REQUIRED_EARLY_CAMPS: int = 2
const ARMY_SAFE_STRENGTH_RATIO: float = 0.55
const HERO_RETREAT_HP_RATIO: float = 0.35
const FOCUS_REISSUE_SECONDS: float = 1.5
const REGROUP_HOLD_SECONDS: float = 2.0

var _tick_timer: float = 0.0
var _consecutive_creep_setbacks: int = 0
var _director: EnemyStrategicDirector = null
var _combat_controller: EnemyCombatController = null
var _match_start_msec: int = 0

var _active_camp: Node3D = null
var _active_camp_id: int = 0
var _focus_creep: Node3D = null
var _focus_reissue_timer: float = 0.0
var _regroup_hold_timer: float = 0.0
var _creep_push_start_power: float = 0.0
var _cleared_camp_ids: Dictionary = {}
var _last_logged_hero_level: int = 0
var _phase_entered_logged: bool = false
var _was_in_creeping_phase: bool = false
var _needs_post_camp_regroup: bool = false
var _army_moving_logged: bool = false
var _selected_camp_index: int = 0


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_director = get_parent().get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector
	_combat_controller = get_parent().get_node_or_null("EnemyCombatController") as EnemyCombatController


func _process(delta: float) -> void:
	_track_phase_entry()
	_track_hero_level()

	_tick_timer += delta
	_focus_reissue_timer += delta
	if _regroup_hold_timer > 0.0:
		_regroup_hold_timer = maxf(0.0, _regroup_hold_timer - delta)

	if _tick_timer < CREEP_TICK_INTERVAL_SECONDS:
		return

	_tick_timer = 0.0
	_update_creeping()


func should_abandon_creep_phase() -> bool:
	return _consecutive_creep_setbacks >= MAX_CREEP_SETBACKS_BEFORE_ABANDON


func has_safe_creep_camp_available() -> bool:
	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(
		tree,
		_get_match_elapsed_seconds()
	)
	if not creep_plan.get("can_launch", false):
		return false

	var army_power: int = EnemyArmyCommand.estimate_combat_strength(creep_plan.get("units", []))
	return _find_best_creep_camp(tree, rally_position, int(army_power), Vector3.ZERO) != null


func get_cleared_early_camp_count() -> int:
	return _cleared_camp_ids.size()


func is_creeping_objective_complete() -> bool:
	if _director == null:
		return false
	if not _is_creeping_phase():
		return false

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null or hero.level < EnemyStrategicDirector.CREEP_HERO_LEVEL_REQUIREMENT:
		return false

	var camps_target: int = _get_required_early_camps()
	if get_cleared_early_camp_count() < camps_target:
		var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
		if has_safe_creep_camp_available():
			return false
		if CreepCampSafety.has_uncleared_nearby_camps(
			get_tree(),
			rally_position,
			CREEP_SEARCH_RANGE
		):
			return false

	return is_army_healthy_after_creeping()


func _get_required_early_camps() -> int:
	if _director != null:
		return _director.get_creep_camps_target()
	return REQUIRED_EARLY_CAMPS


func _can_start_group_mission(units: Array = []) -> bool:
	var validation: Dictionary = EnemyArmyCommand.can_start_group_mission(
		get_tree(),
		units,
		_get_phase_min_army_size()
	)
	return bool(validation.get("ok", false))


func is_army_healthy_after_creeping() -> bool:
	var tree: SceneTree = get_tree()
	var non_hero: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(tree)
	var min_army: int = _get_phase_min_army_size()
	if non_hero.size() < min_army:
		return false

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero == null:
		return false

	if EnemyArmyCommand.get_health_ratio(hero) < HERO_RETREAT_HP_RATIO:
		return false

	return true


func _track_phase_entry() -> void:
	var in_creeping: bool = _is_creeping_phase()
	if in_creeping and not _was_in_creeping_phase:
		_phase_entered_logged = false
		_last_logged_hero_level = 0
	_was_in_creeping_phase = in_creeping

	if in_creeping and not _phase_entered_logged:
		_phase_entered_logged = true
		EnemyAIDebug.log_creeping_phase()


func _track_hero_level() -> void:
	if not _is_creeping_phase():
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null:
		return

	if hero.level > _last_logged_hero_level and hero.level >= 2:
		EnemyAIDebug.log_creeping("Creeping: Hero level %d" % hero.level)
		EnemyAIDebug.log_creeping_hero_level(hero.level)
	_last_logged_hero_level = maxi(_last_logged_hero_level, hero.level)


func _is_creeping_phase() -> bool:
	return (
		_director != null
		and _director.get_strategic_phase() == EnemyStrategicDirector.StrategicPhase.CREEPING
	)


func _is_tier_2_safe_creep_phase() -> bool:
	return (
		_director != null
		and _director.get_strategic_phase() == EnemyStrategicDirector.StrategicPhase.TIER_2
		and _director.should_prioritize_creep()
	)


func _allows_creep_objective() -> bool:
	return _is_creeping_phase() or _is_tier_2_safe_creep_phase()


func _update_creeping() -> void:
	if not _allows_creep_objective():
		_clear_active_camp()
		return

	if EnemyArmyCommand.is_attack_wave_active():
		return

	if EnemyArmyCommand.is_finishing_mode_active():
		return

	if EnemyArmyCommand.is_defense_blocking_offense():
		return

	if not EnemyArmyCommand.allows_creep_orders():
		return

	if _director != null and not _director.should_prioritize_creep():
		return

	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if army_mode in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
		EnemyArmyCommand.ArmyMode.RETREATING,
		EnemyArmyCommand.ArmyMode.ASSEMBLING,
	]:
		return

	if _combat_controller != null and not _combat_controller.can_launch_offensive_action():
		if army_mode != EnemyArmyCommand.ArmyMode.CREEPING:
			return

	var min_army: int = _get_phase_min_army_size()
	var creep_army: Array = []

	if army_mode == EnemyArmyCommand.ArmyMode.CREEPING:
		creep_army = _collect_field_creep_army(tree, min_army)
		if creep_army.is_empty() or not _can_start_group_mission(creep_army):
			_hold_army_until_rallied(tree, rally_position)
			return
	else:
		var creep_plan: Dictionary = EnemyArmyCommand.build_coordinated_combat_group(
			tree,
			rally_position,
			min_army,
			true
		)
		if not creep_plan.get("can_launch", false):
			_hold_army_until_rallied(tree, rally_position)
			return

		creep_army = NodeSafety.clean_node_array(creep_plan.get("units", []))
		if creep_army.is_empty() or not _can_start_group_mission(creep_army):
			_hold_army_until_rallied(tree, rally_position)
			return

		if not creep_plan.get("hero_included", false):
			_hold_army_until_rallied(tree, rally_position)
			return

	creep_army = NodeSafety.clean_node_array(creep_army)
	if creep_army.is_empty():
		return

	if _should_retreat_from_creeping(tree, creep_army):
		return

	if _regroup_hold_timer > 0.0:
		return

	if _needs_post_camp_regroup or _needs_army_regroup(creep_army):
		_regroup_creep_army(creep_army)
		if _can_start_group_mission(creep_army) and not _needs_army_regroup(creep_army):
			_needs_post_camp_regroup = false
		else:
			return

	_sanitize_active_camp(tree)
	if _active_camp != null and _is_camp_cleared(tree, _active_camp):
		_on_camp_cleared(_active_camp)
		_clear_active_camp()
		_needs_post_camp_regroup = true
		_regroup_creep_army(creep_army)
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(creep_army)
	if army_center == Vector3.ZERO:
		return

	if not _army_available_for_creeping(tree, army_center, rally_position):
		return

	# Final group validation before selecting or engaging a camp.
	if not _can_start_group_mission(creep_army):
		_hold_army_until_rallied(tree, rally_position)
		return

	var army_power: int = int(EnemyArmyCommand.estimate_combat_strength(creep_army))
	if _creep_push_start_power <= 0.0:
		_creep_push_start_power = float(army_power)

	var camp: Node3D = _active_camp
	if camp == null or not is_instance_valid(camp):
		camp = _find_best_creep_camp(tree, rally_position, army_power, army_center)
		if camp == null:
			if _has_uncleared_enemy_side_camps(tree, rally_position):
				_record_creep_setback()
			if _director != null:
				_director.clear_creep_target()
			return
		_select_camp(camp, army_center if army_center != Vector3.ZERO else rally_position)

	if _is_player_contesting_camp(tree, camp):
		return

	if _director != null:
		_director.set_creep_target(camp)

	if _is_camp_cleared(tree, camp):
		_on_camp_cleared(camp)
		_clear_active_camp()
		_reset_creep_setbacks()
		_needs_post_camp_regroup = true
		return

	if _is_army_engaging_camp(tree, creep_army, camp):
		_engage_camp_focus_fire(tree, creep_army, camp)
		return

	var attack_destination: Vector3 = _resolve_camp_attack_destination(
		tree,
		camp,
		army_center
	)

	if _combat_controller == null:
		return

	if not _army_moving_logged:
		_army_moving_logged = true
		EnemyAIDebug.log_creeping("Creeping: Army grouped, moving out")

	# First departure from base waits for a full rally; later camps keep the group moving.
	if army_mode == EnemyArmyCommand.ArmyMode.CREEPING:
		_combat_controller.issue_immediate_group_move(
			creep_army,
			attack_destination,
			EnemyArmyCommand.ArmyMode.CREEPING,
			EnemyUnitMission.Mission.CREEP
		)
		return

	_combat_controller.request_assembled_group_move(
		creep_army,
		attack_destination,
		EnemyArmyCommand.ArmyMode.CREEPING,
		EnemyUnitMission.Mission.CREEP
	)


func _collect_field_creep_army(tree: SceneTree, min_army: int) -> Array:
	var units: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	units = NodeSafety.clean_node_array(units)
	units = EnemyArmyCommand.filter_units_for_field_combat(
		units,
		EnemyUnitMission.Mission.CREEP
	)
	if units.is_empty():
		return []

	var center: Vector3 = EnemyArmyCommand.compute_army_center(units)
	if center == Vector3.ZERO:
		return []

	var grouped: Array = EnemyArmyCommand.filter_units_near_rally(
		units,
		center,
		CREEP_REGROUP_MAX_DISTANCE * 1.75
	)
	var non_hero_count: int = 0
	var hero: Hero = null
	for unit: Variant in grouped:
		if unit is Hero:
			hero = unit as Hero
		elif EnemyArmyCommand.is_non_hero_combat_unit(unit as Node):
			non_hero_count += 1

	if non_hero_count < min_army:
		return []

	if hero == null:
		return []

	if (
		EnemyArmyCommand.horizontal_distance(hero.global_position, center)
		> EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY * 1.5
	):
		return []

	return grouped


func _hold_army_until_rallied(tree: SceneTree, rally_position: Vector3, _elapsed: float = 0.0) -> void:
	EnemyAIDebug.log_creeping("Creeping: Army regrouping")
	_army_moving_logged = false
	if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		if EnemyArmyCommand.get_army_mode() != EnemyArmyCommand.ArmyMode.REGROUPING:
			return

	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)
	)
	EnemyArmyCommand.pull_straggler_units_to_rally(tree, rally_position)
	EnemyArmyCommand.pull_reinforcement_units_to_rally(tree, rally_position)


func _needs_army_regroup(army: Array) -> bool:
	army = NodeSafety.clean_node_array(army)
	if army.size() < 3:
		return false

	var center: Vector3 = EnemyArmyCommand.compute_army_center(army)
	if center == Vector3.ZERO:
		return false

	var near_count: int = EnemyArmyCommand.filter_units_near_rally(
		army,
		center,
		CREEP_REGROUP_MAX_DISTANCE
	).size()
	return float(near_count) / float(army.size()) < CREEP_COHESION_RATIO


func _regroup_creep_army(army: Array) -> void:
	var center: Vector3 = EnemyArmyCommand.compute_army_center(army)
	if center == Vector3.ZERO:
		return

	EnemyAIDebug.log_creeping("Creeping: Army regrouping")
	_army_moving_logged = false
	_regroup_hold_timer = REGROUP_HOLD_SECONDS
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_hold_at_rally(
			army,
			center,
			EnemyUnitMission.Mission.CREEP
		)
	)


func _should_retreat_from_creeping(tree: SceneTree, creep_army: Array) -> bool:
	if EnemyArmyCommand.is_enemy_army_under_attack(tree, creep_army, ARMY_UNDER_ATTACK_RANGE):
		_record_creep_setback()
		EnemyAIDebug.log_once("retreat", "Retreat: Army weaker than enemy")
		_retreat_creep_army(tree, "under attack", false)
		return true

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero != null:
		var hero_hp_ratio: float = EnemyArmyCommand.get_health_ratio(hero)
		if hero_hp_ratio < HERO_RETREAT_HP_RATIO:
			_record_creep_setback()
			EnemyAIDebug.log_once(
				"retreat",
				"Retreat: Hero HP %d%%" % int(round(hero_hp_ratio * 100.0))
			)
			_retreat_creep_army(tree, "hero low hp", false)
			return true

	if _should_abort_creep_push(tree, creep_army):
		_record_creep_setback()
		EnemyAIDebug.log_once("retreat", "Retreat: Army weaker than enemy")
		_retreat_creep_army(tree, "army too weak", false)
		return true

	if _creep_push_start_power > 0.0:
		var current_power: float = float(EnemyArmyCommand.estimate_combat_strength(creep_army))
		if current_power <= _creep_push_start_power * ARMY_SAFE_STRENGTH_RATIO:
			_record_creep_setback()
			EnemyAIDebug.log_once("retreat", "Retreat: Army weaker than enemy")
			_retreat_creep_army(tree, "army strength low", false)
			return true

	return false


func _select_camp(camp: Node3D, from_position: Vector3) -> void:
	if camp == null or not is_instance_valid(camp):
		return

	var camp_id: int = camp.get_instance_id()
	if camp_id == _active_camp_id:
		_active_camp = camp
		return

	_active_camp = camp
	_active_camp_id = camp_id
	_focus_creep = null
	_creep_push_start_power = 0.0
	_selected_camp_index = get_cleared_early_camp_count() + 1
	_army_moving_logged = false

	EnemyAIDebug.log_creeping("Creeping: Selected camp %d" % _selected_camp_index)
	var distance: float = EnemyArmyCommand.horizontal_distance(camp.global_position, from_position)
	EnemyAIDebug.log_creeping_camp_selected(_format_camp_name(camp), distance)


func _on_camp_cleared(camp: Node3D) -> void:
	if camp != null and is_instance_valid(camp):
		_cleared_camp_ids[camp.get_instance_id()] = true
	var cleared: int = get_cleared_early_camp_count()
	var target: int = _get_required_early_camps()
	EnemyAIDebug.log_creeping("Creeping: Camp cleared %d/%d" % [cleared, target])
	_reset_creep_setbacks()
	_creep_push_start_power = 0.0
	_army_moving_logged = false
	_needs_post_camp_regroup = true


func _clear_active_camp() -> void:
	_active_camp = null
	_active_camp_id = 0
	_focus_creep = null
	if _director != null:
		_director.clear_creep_target()


func _sanitize_active_camp(tree: SceneTree) -> void:
	if _active_camp == null:
		_active_camp_id = 0
		return

	if not is_instance_valid(_active_camp):
		_clear_active_camp()
		return

	if _is_player_contesting_camp(tree, _active_camp):
		_clear_active_camp()


func _engage_camp_focus_fire(tree: SceneTree, army: Array, camp: Node3D) -> void:
	EnemyAIDebug.log_creeping("Engaging creep camp")

	if not NodeSafety.is_alive_node(_focus_creep) or not _is_living_creep(_focus_creep):
		_focus_creep = _pick_focus_creep(tree, camp, army)
		_focus_reissue_timer = FOCUS_REISSUE_SECONDS

	if not NodeSafety.is_alive_node(_focus_creep):
		return

	if _focus_reissue_timer < FOCUS_REISSUE_SECONDS:
		return

	_focus_reissue_timer = 0.0
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_focus_attack(
			army,
			_focus_creep,
			EnemyUnitMission.Mission.CREEP
		)
	)


func _pick_focus_creep(tree: SceneTree, camp: Node3D, army: Array) -> Node3D:
	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(army)
	if army_center == Vector3.ZERO:
		army_center = camp.global_position

	var best_creep: Node3D = null
	var best_health: int = 1 << 30
	var best_distance: float = INF

	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node3D:
			continue

		var child: Node3D = child_variant as Node3D
		if not _is_living_creep(child):
			continue

		var health: int = CombatTargetValidation.get_target_current_health(child)
		var distance: float = EnemyArmyCommand.horizontal_distance(
			army_center,
			child.global_position
		)
		if health < best_health or (health == best_health and distance < best_distance):
			best_health = health
			best_distance = distance
			best_creep = child

	if best_creep != null:
		return best_creep

	return _find_nearest_living_creep_at_camp(tree, camp, army_center)


func _get_match_elapsed_seconds() -> float:
	if _director != null:
		return _director.get_match_elapsed_seconds()
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func _get_phase_min_army_size() -> int:
	if _director != null:
		return _director.get_min_army_size_for_current_phase()
	return EnemyArmyCommand.get_phase_min_army_size(_get_match_elapsed_seconds())


func _is_player_contesting_camp(tree: SceneTree, camp) -> bool:
	if not NodeSafety.is_alive_node(camp):
		return false
	return not EnemyArmyCommand.collect_player_military_near(
		tree,
		camp.global_position,
		EnemyArmyCommand.PLAYER_CREEP_DETECT_RADIUS
	).is_empty()


func _record_creep_setback() -> void:
	_consecutive_creep_setbacks += 1


func _reset_creep_setbacks() -> void:
	_consecutive_creep_setbacks = 0


func _has_uncleared_enemy_side_camps(tree: SceneTree, rally_position: Vector3) -> bool:
	return CreepCampSafety.has_uncleared_nearby_camps(
		tree,
		rally_position,
		CREEP_SEARCH_RANGE
	)


func _retreat_creep_army(tree: SceneTree, reason: String, log_generic: bool = true) -> void:
	_clear_active_camp()
	_creep_push_start_power = 0.0
	_army_moving_logged = false
	_needs_post_camp_regroup = true
	if log_generic and not reason.is_empty():
		EnemyAIDebug.log_creeping("Retreating from creep camp (%s)" % reason)

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if _combat_controller != null:
		_combat_controller.issue_group_retreat(reason)
		return

	# Never leave the hero behind — retreat every living combat unit together.
	var creep_army: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	creep_army = NodeSafety.clean_node_array(creep_army)
	if creep_army.is_empty():
		return

	EnemyArmyCommand.cancel_offensive_orders(tree)
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_hold_at_rally(creep_army, rally_position)
	)


func _should_abort_creep_push(tree: SceneTree, creep_army: Array) -> bool:
	var min_army: int = _get_phase_min_army_size()
	var non_hero_count: int = 0
	for unit: Variant in NodeSafety.clean_node_array(creep_army):
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Hero:
			continue
		if EnemyArmyCommand.is_living_combat_unit(unit as Node):
			non_hero_count += 1

	return non_hero_count < min_army


func _army_available_for_creeping(
	tree: SceneTree,
	army_center: Vector3,
	rally_position: Vector3
) -> bool:
	var distance_to_rally: float = EnemyArmyCommand.horizontal_distance(
		army_center,
		rally_position
	)
	if distance_to_rally <= MAX_CREEP_DISTANCE_FROM_RALLY:
		return true

	if _count_living_creeps_near(tree, army_center, CAMP_ENGAGEMENT_RADIUS) > 0:
		return true

	return not _is_army_on_offensive_push(tree, army_center, rally_position)


func _is_army_on_offensive_push(
	tree: SceneTree,
	army_center: Vector3,
	rally_position: Vector3
) -> bool:
	var player_command_center: CommandCenter = (
		EnemyArmyCommand.find_living_player_command_center(tree)
	)
	if player_command_center == null:
		return false

	var distance_to_player: float = EnemyArmyCommand.horizontal_distance(
		army_center,
		player_command_center.global_position
	)
	var distance_to_rally: float = EnemyArmyCommand.horizontal_distance(
		army_center,
		rally_position
	)
	return distance_to_player + 12.0 < distance_to_rally


func _find_best_creep_camp(
	tree: SceneTree,
	rally_position: Vector3,
	army_power: int,
	from_position: Vector3
) -> Node3D:
	var origin: Vector3 = from_position if from_position != Vector3.ZERO else rally_position
	var best_camp: Node3D = null
	var best_score: float = -INF

	for camp: Node3D in _collect_creep_camps(tree):
		if camp == null or not is_instance_valid(camp):
			continue

		if not _is_enemy_side_camp(camp, rally_position, tree):
			continue

		if _is_camp_cleared(tree, camp):
			continue

		if _is_player_contesting_camp(tree, camp):
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			camp.global_position,
			origin
		)
		if distance > CREEP_SEARCH_RANGE:
			continue

		var camp_power: int = _estimate_camp_power(camp)
		if camp_power <= 0:
			continue

		var power_margin: float = (
			STRONG_CAMP_POWER_MARGIN
			if camp_power >= STRONG_CAMP_POWER_THRESHOLD
			else CAMP_POWER_MARGIN
		)
		if float(camp_power) * power_margin > float(army_power):
			continue

		var camp_xp: int = _estimate_camp_xp(camp)
		var score: float = _score_camp(camp_xp, camp_power, distance, army_power)
		if score > best_score:
			best_score = score
			best_camp = camp

	return best_camp


func _score_camp(camp_xp: int, camp_power: int, distance: float, army_power: int) -> float:
	var safe_power: float = maxf(float(camp_power), 1.0)
	var risk: float = safe_power / maxf(float(army_power), 1.0)
	var xp_per_risk: float = float(camp_xp) / maxf(risk, 0.2)
	var distance_factor: float = 1.0 + distance / maxf(CREEP_SEARCH_RANGE, 1.0)
	# Prefer high XP/risk, short travel, and weaker camps.
	return (xp_per_risk / distance_factor) - safe_power * 0.002 - distance * 0.15


func _estimate_camp_xp(camp) -> int:
	if not NodeSafety.is_alive_node(camp):
		return 0

	var total_xp: int = 0
	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue

		var child: Node = child_variant as Node
		if not _is_living_creep(child):
			continue

		total_xp += HeroXpRewards.get_xp_amount_for_victim(child)

	return total_xp


func _format_camp_name(camp: Node3D) -> String:
	if camp == null:
		return "Creep Camp"

	var camp_name: String = String(camp.name)
	if camp_name.begins_with("Strong"):
		return "Strong Camp"
	if camp_name.begins_with("Medium"):
		return "Medium Camp"
	if camp_name.begins_with("Small"):
		return "Small Camp"
	return camp_name


func _collect_creep_camps(tree: SceneTree) -> Array[Node3D]:
	return CreepCampSafety.collect_active_camps(tree)


func _is_enemy_side_camp(camp, enemy_rally: Vector3, tree: SceneTree) -> bool:
	if not NodeSafety.is_alive_node(camp):
		return false
	var player_command_center: CommandCenter = (
		EnemyArmyCommand.find_living_player_command_center(tree)
	)
	if player_command_center == null:
		return true

	var camp_position: Vector3 = camp.global_position
	var distance_to_enemy: float = EnemyArmyCommand.horizontal_distance(
		camp_position,
		enemy_rally
	)
	var distance_to_player: float = EnemyArmyCommand.horizontal_distance(
		camp_position,
		player_command_center.global_position
	)
	return distance_to_enemy <= distance_to_player


func _is_camp_cleared(tree: SceneTree, camp) -> bool:
	if not NodeSafety.is_alive_node(camp):
		return true

	return _count_living_creeps_near(tree, camp.global_position, CAMP_CLEAR_RADIUS) == 0


func _resolve_camp_attack_destination(
	tree: SceneTree,
	camp: Node3D,
	from_position: Vector3
) -> Vector3:
	if camp == null or not is_instance_valid(camp):
		return from_position

	var nearest_creep: Node3D = _find_nearest_living_creep_at_camp(tree, camp, from_position)
	if nearest_creep != null:
		return nearest_creep.global_position

	return camp.global_position


func _find_nearest_living_creep_at_camp(
	tree: SceneTree,
	camp: Node3D,
	from_position: Vector3
) -> Node3D:
	var nearest_creep: Node3D = null
	var nearest_distance: float = INF

	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue

		if not _is_living_creep(child_variant):
			continue

		if not child_variant is Node3D:
			continue

		var child: Node3D = child_variant as Node3D
		var distance: float = EnemyArmyCommand.horizontal_distance(
			from_position,
			child.global_position
		)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_creep = child as Node3D

	return nearest_creep


func _is_army_engaging_camp(tree: SceneTree, army: Array, camp) -> bool:
	if not NodeSafety.is_alive_node(camp):
		return false

	if _count_living_creeps_near(tree, camp.global_position, CAMP_ENGAGEMENT_RADIUS) == 0:
		return false

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(army)
	if army_center == Vector3.ZERO:
		return false

	return (
		EnemyArmyCommand.horizontal_distance(army_center, camp.global_position)
		<= CAMP_ENGAGEMENT_RADIUS + 6.0
	)


func _count_living_creeps_near(tree: SceneTree, position: Vector3, radius: float) -> int:
	var count: int = 0

	for node_variant: Variant in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if node_variant == null or not is_instance_valid(node_variant) or not node_variant is Node:
			continue

		var node: Node = node_variant as Node
		if not _is_living_creep(node):
			continue

		if not node is Node3D:
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			position,
			(node as Node3D).global_position
		)
		if distance <= radius:
			count += 1

	return count


func _estimate_camp_power(camp) -> int:
	if not NodeSafety.is_alive_node(camp):
		return 0

	var power: int = 0

	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue

		var child: Node = child_variant as Node
		if not _is_living_creep(child):
			continue

		var health_component: HealthComponent = child.get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		if health_component == null:
			continue

		var damage: int = 8
		if "attack_damage" in child:
			damage = int(child.get("attack_damage"))

		power += health_component.max_health + damage * int(CREEP_DAMAGE_POWER_MULTIPLIER)

	return power


func _is_living_creep(node: Variant) -> bool:
	if not NodeSafety.is_alive_node(node):
		return false

	if not node is Node:
		return false

	if not CombatTargetValidation.is_neutral_creep(node):
		return false

	return CombatTargetValidation.get_target_current_health(node) > 0
