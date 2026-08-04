class_name EnemyCreepManager
extends Node

## CREEPING-phase army: rally as one group, clear nearby camps with the hero, then advance.
## Owns a single creep-mission FSM so wave/attack systems cannot steal the squad mid-camp.

enum CreepMission {
	NONE,
	ASSEMBLE_CREEP_SQUAD,
	MOVE_TO_CAMP,
	FIGHT_CAMP,
	RECOVER_AFTER_CAMP,
	SELECT_NEXT_CAMP,
	RETURN_TO_BASE,
}

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
const CREEP_ENGAGE_COHESION_RATIO: float = 0.70
const CREEP_DAMAGE_POWER_MULTIPLIER: float = 8.0
const MAX_CREEP_SETBACKS_BEFORE_ABANDON: int = 3
const REQUIRED_EARLY_CAMPS: int = 2
const ARMY_SAFE_STRENGTH_RATIO: float = 0.55
const HERO_RETREAT_HP_RATIO: float = 0.35
const ESCORT_INJURED_HP_RATIO: float = 0.35
const MAX_INJURED_ESCORT_RATIO: float = 0.45
const FOCUS_REISSUE_SECONDS: float = 1.5
const REGROUP_HOLD_SECONDS: float = 2.0
const PLAYER_THREAT_ABORT_RADIUS: float = 28.0
const PLAYER_THREAT_STRENGTH_RATIO: float = 1.10
const CAMP_LEASH_CHASE_RADIUS: float = 22.0

var _tick_timer: float = 0.0
var _consecutive_creep_setbacks: int = 0
var _director: EnemyStrategicDirector = null
var _combat_controller: EnemyCombatController = null
var _match_start_msec: int = 0

var _creep_mission: CreepMission = CreepMission.NONE
var _active_camp: Node3D = null
var _active_camp_id: int = 0
var _reserved_camp_id: int = 0
var _focus_creep: Node3D = null
var _active_camp_handle: EntityHandle = EntityHandle.empty()
var _focus_creep_handle: EntityHandle = EntityHandle.empty()
var _focus_reissue_timer: float = 0.0
var _regroup_hold_timer: float = 0.0
var _creep_push_start_power: float = 0.0
var _cleared_camp_ids: Dictionary = {}
var _last_logged_hero_level: int = 0
var _phase_entered_logged: bool = false
var _was_in_creeping_phase: bool = false
var _needs_post_camp_regroup: bool = false
var _army_moving_logged: bool = false
var _squad_ready_logged: bool = false
var _mission_started_logged: bool = false
var _selected_camp_index: int = 0
var _last_safety_score: float = 0.0


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_tick_timer = CREEP_TICK_INTERVAL_SECONDS * 0.7
	_director = get_parent().get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector
	_combat_controller = get_parent().get_node_or_null("EnemyCombatController") as EnemyCombatController
	reset_match_state()


func reset_match_state() -> void:
	_consecutive_creep_setbacks = 0
	_cancel_creep_mission("match reset")
	_cleared_camp_ids.clear()
	_last_logged_hero_level = 0
	_phase_entered_logged = false
	_was_in_creeping_phase = false
	_needs_post_camp_regroup = false
	_army_moving_logged = false
	_squad_ready_logged = false
	_mission_started_logged = false
	_selected_camp_index = 0
	_last_safety_score = 0.0
	_focus_reissue_timer = 0.0
	_regroup_hold_timer = 0.0
	_creep_push_start_power = 0.0
	_focus_creep = null
	CreepCampSafety.reset_match_state()


func _process(delta: float) -> void:
	if MilitaryAIConfig.is_v2_enabled():
		## DISABLED under Military AI V2 (legacy creep mission owner).
		## Creep camp selection / clearance is owned by MilitaryDirectorV2;
		## ArmyCommanderV2 executes CREEP orders and may call low-level helpers here.
		return

	_track_phase_entry()
	_track_hero_level()

	_tick_timer += delta
	_focus_reissue_timer += delta
	if _regroup_hold_timer > 0.0:
		_regroup_hold_timer = maxf(0.0, _regroup_hold_timer - delta)

	if _tick_timer < CREEP_TICK_INTERVAL_SECONDS:
		return

	_tick_timer = 0.0
	var start_usec: int = PerfCounters.begin_section()
	_update_creeping()
	PerfCounters.end_section("Creep update", start_usec)


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


func get_creep_mission() -> CreepMission:
	return _creep_mission


func is_creep_mission_active() -> bool:
	return _creep_mission != CreepMission.NONE


func has_camp_reserved(camp: Node3D = null) -> bool:
	if _reserved_camp_id == 0:
		return false
	if camp == null:
		return true
	if not is_instance_valid(camp):
		return false
	return camp.get_instance_id() == _reserved_camp_id


func get_reserved_camp() -> Node3D:
	if _active_camp != null and is_instance_valid(_active_camp):
		return _active_camp
	return null


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


func _set_creep_mission(mission: CreepMission) -> void:
	if _creep_mission == mission:
		return
	_creep_mission = mission


func _track_phase_entry() -> void:
	var in_creeping: bool = _is_creeping_phase()
	if in_creeping and not _was_in_creeping_phase:
		_phase_entered_logged = false
		_last_logged_hero_level = 0
		_squad_ready_logged = false
		_mission_started_logged = false
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
		_cancel_creep_mission("phase ended")
		return

	if EnemyArmyCommand.is_attack_wave_active():
		return

	if EnemyArmyCommand.is_finishing_mode_active():
		return

	if EnemyAggression.should_suspend_creeping():
		_cancel_creep_mission("aggression mode")
		return

	if EnemyArmyCommand.is_defense_blocking_offense():
		_set_creep_mission(CreepMission.NONE)
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
	]:
		_set_creep_mission(CreepMission.NONE)
		return

	## Assembly for creeping is owned by combat controller — do not steal or clear the camp.
	if army_mode == EnemyArmyCommand.ArmyMode.ASSEMBLING:
		if _combat_controller != null and _combat_controller.is_assembling_for_creep():
			_set_creep_mission(CreepMission.ASSEMBLE_CREEP_SQUAD)
		return

	if _combat_controller != null and not _combat_controller.can_launch_offensive_action():
		if army_mode != EnemyArmyCommand.ArmyMode.CREEPING:
			return

	var min_army: int = _get_phase_min_army_size()
	var creep_army: Array = []

	if army_mode == EnemyArmyCommand.ArmyMode.CREEPING:
		creep_army = _collect_field_creep_army(tree, min_army)
		if creep_army.is_empty() or not _can_start_group_mission(creep_army):
			_set_creep_mission(CreepMission.ASSEMBLE_CREEP_SQUAD)
			_hold_army_until_rallied(tree, rally_position, creep_army)
			return
	else:
		var creep_plan: Dictionary = EnemyArmyCommand.build_creep_army(
			tree,
			_get_match_elapsed_seconds()
		)
		if not creep_plan.get("can_launch", false):
			_set_creep_mission(CreepMission.ASSEMBLE_CREEP_SQUAD)
			_hold_army_until_rallied(tree, rally_position)
			return

		creep_army = NodeSafety.clean_node_array(creep_plan.get("units", []))
		if creep_army.is_empty() or not _can_start_group_mission(creep_army):
			_set_creep_mission(CreepMission.ASSEMBLE_CREEP_SQUAD)
			_hold_army_until_rallied(tree, rally_position)
			return

		if not creep_plan.get("hero_included", false):
			_set_creep_mission(CreepMission.ASSEMBLE_CREEP_SQUAD)
			_hold_army_until_rallied(tree, rally_position)
			return

	creep_army = NodeSafety.clean_node_array(creep_army)
	if creep_army.is_empty():
		return

	_log_squad_ready_once(creep_army)

	if _should_retreat_from_creeping(tree, creep_army):
		return

	if _regroup_hold_timer > 0.0:
		_set_creep_mission(CreepMission.RECOVER_AFTER_CAMP)
		return

	if _needs_post_camp_regroup or _needs_army_regroup(creep_army):
		_set_creep_mission(CreepMission.RECOVER_AFTER_CAMP)
		_regroup_creep_army(creep_army)
		if _can_start_group_mission(creep_army) and not _needs_army_regroup(creep_army):
			_needs_post_camp_regroup = false
			_set_creep_mission(CreepMission.SELECT_NEXT_CAMP)
		else:
			return

	_sanitize_active_camp(tree)
	if _active_camp != null and _is_camp_cleared(tree, _active_camp):
		_on_camp_cleared(_active_camp)
		_clear_active_camp()
		_needs_post_camp_regroup = true
		_set_creep_mission(CreepMission.RECOVER_AFTER_CAMP)
		_regroup_creep_army(creep_army)
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(creep_army)
	if army_center == Vector3.ZERO:
		return

	if not _army_available_for_creeping(tree, army_center, rally_position):
		if _is_army_on_offensive_push(tree, army_center, rally_position):
			_handle_army_in_hostile_territory(tree, creep_army, army_center, rally_position)
		return

	# Final group validation before selecting or engaging a camp.
	if not _can_start_group_mission(creep_army):
		_set_creep_mission(CreepMission.ASSEMBLE_CREEP_SQUAD)
		EnemyArmyCommand.set_executable_mission(
			EnemyArmyCommand.ExecutableMission.ASSEMBLE,
			"creep squad incomplete",
			null,
			rally_position,
			"Rally",
			"hold",
			creep_army,
			false
		)
		_hold_army_until_rallied(tree, rally_position, creep_army)
		return

	if not _squad_safe_to_commit(tree, creep_army):
		_set_creep_mission(CreepMission.RECOVER_AFTER_CAMP)
		EnemyArmyCommand.set_executable_mission(
			EnemyArmyCommand.ExecutableMission.REGROUP,
			"squad not safe to commit",
			null,
			rally_position,
			"Rally",
			"hold",
			creep_army,
			false
		)
		_hold_army_until_rallied(tree, rally_position, creep_army)
		return

	var army_power: int = int(EnemyArmyCommand.estimate_combat_strength(creep_army))
	if _creep_push_start_power <= 0.0:
		_creep_push_start_power = float(army_power)

	var camp: Node3D = _active_camp
	if camp == null or not is_instance_valid(camp):
		_set_creep_mission(CreepMission.SELECT_NEXT_CAMP)
		camp = _find_best_creep_camp(tree, rally_position, army_power, army_center)
		if camp == null:
			if _has_uncleared_enemy_side_camps(tree, rally_position):
				_record_creep_setback()
			if _director != null:
				_director.clear_creep_target()
			# No safe camp: rally and rebuild. Never fall through to player attack.
			_set_creep_mission(CreepMission.RETURN_TO_BASE)
			EnemyArmyCommand.set_executable_mission(
				EnemyArmyCommand.ExecutableMission.REGROUP,
				"creep objective invalid",
				null,
				rally_position,
				"Rally",
				"move",
				creep_army,
				false
			)
			_hold_army_until_rallied(tree, rally_position, creep_army)
			return
		_select_camp(camp, army_center if army_center != Vector3.ZERO else rally_position, army_power)

	if not _validate_and_sync_creeping(tree, creep_army, camp, army_center):
		return

	if _is_player_contesting_camp(tree, camp):
		_retreat_creep_army(tree, "player contesting camp", true)
		return

	if _director != null:
		_director.set_creep_target(camp)

	if _is_camp_cleared(tree, camp):
		_on_camp_cleared(camp)
		_clear_active_camp()
		_reset_creep_setbacks()
		_needs_post_camp_regroup = true
		_set_creep_mission(CreepMission.RECOVER_AFTER_CAMP)
		return

	if _is_army_engaging_camp(tree, creep_army, camp):
		if not _is_squad_cohesive_for_engage(creep_army, camp):
			_set_creep_mission(CreepMission.MOVE_TO_CAMP)
			_regroup_creep_army(creep_army)
			return
		_set_creep_mission(CreepMission.FIGHT_CAMP)
		EnemyArmyCommand.note_mission_progress(army_center, true, creep_army.size())
		_engage_camp_focus_fire(tree, creep_army, camp)
		return

	var attack_destination: Vector3 = _resolve_camp_attack_destination(
		tree,
		camp,
		army_center
	)

	if _combat_controller == null:
		return

	_set_creep_mission(CreepMission.MOVE_TO_CAMP)
	_log_mission_started_once()
	_sync_creeping_executable(creep_army, camp, attack_destination, "move to camp")
	EnemyArmyCommand.note_mission_progress(army_center, false, creep_army.size())

	if not _army_moving_logged:
		_army_moving_logged = true
		EnemyAIDebug.log_creeping("Creeping: Moving to camp")

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


func _log_squad_ready_once(creep_army: Array) -> void:
	if _squad_ready_logged:
		return
	var non_hero: int = 0
	for unit: Variant in creep_army:
		if unit is Hero:
			continue
		if EnemyArmyCommand.is_non_hero_combat_unit(unit as Node):
			non_hero += 1
	_squad_ready_logged = true
	EnemyAIDebug.log_creep_squad_ready(non_hero)


func _log_mission_started_once() -> void:
	if _mission_started_logged:
		return
	_mission_started_logged = true
	EnemyAIDebug.log_creep_mission_started()


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


func _hold_army_until_rallied(
	tree: SceneTree,
	rally_position: Vector3,
	field_army: Array = []
) -> void:
	var pikemen: int = 0
	for unit: Variant in EnemyArmyCommand.collect_living_non_hero_combat_units(tree):
		if unit is Spearman:
			pikemen += 1
	if pikemen < EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN:
		EnemyAIDebug.log_creeping("Creeping paused: rebuilding army")
	else:
		EnemyAIDebug.log_creeping("Creeping: Regrouping Hero and %d Pikemen" % pikemen)
	_army_moving_logged = false

	## If already in the field with a reserved camp, regroup locally — not back to base.
	var cleaned_field: Array = NodeSafety.clean_node_array(field_army)
	if (
		_active_camp != null
		and is_instance_valid(_active_camp)
		and not cleaned_field.is_empty()
	):
		var field_center: Vector3 = EnemyArmyCommand.compute_army_center(cleaned_field)
		if field_center != Vector3.ZERO:
			EnemyArmyCommand.with_authorized_orders(func() -> void:
				EnemyArmyCommand.command_hold_at_rally(
					cleaned_field,
					field_center,
					EnemyUnitMission.Mission.CREEP
				)
			)
			return

	if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		if EnemyArmyCommand.get_army_mode() != EnemyArmyCommand.ArmyMode.REGROUPING:
			return

	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)
	)
	## Reinforcements wait at base — never walk one-by-one into the camp.
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


func _is_squad_cohesive_for_engage(army: Array, camp: Node3D) -> bool:
	army = NodeSafety.clean_node_array(army)
	if army.is_empty() or not NodeSafety.is_alive_node(camp):
		return false

	var near_count: int = 0
	for unit: Variant in army:
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue
		if (
			EnemyArmyCommand.horizontal_distance(
				(unit as Node3D).global_position,
				camp.global_position
			)
			<= CAMP_ENGAGEMENT_RADIUS + 8.0
		):
			near_count += 1

	return float(near_count) / float(army.size()) >= CREEP_ENGAGE_COHESION_RATIO


func _regroup_creep_army(army: Array) -> void:
	var center: Vector3 = EnemyArmyCommand.compute_army_center(army)
	if center == Vector3.ZERO:
		return

	var pikemen: int = 0
	for unit: Variant in army:
		if unit is Spearman:
			pikemen += 1
	EnemyAIDebug.log_creeping("Creeping: Regrouping Hero and %d Pikemen" % maxi(pikemen, 1))
	_army_moving_logged = false
	_regroup_hold_timer = REGROUP_HOLD_SECONDS
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_hold_at_rally(
			army,
			center,
			EnemyUnitMission.Mission.CREEP
		)
	)


func _squad_safe_to_commit(tree: SceneTree, creep_army: Array) -> bool:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero == null:
		return false
	if not EnemyArmyCommand.is_hero_healthy_enough_for_creep(hero):
		return false

	var injured: int = 0
	var escort: int = 0
	for unit: Variant in NodeSafety.clean_node_array(creep_army):
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Hero:
			continue
		if not EnemyArmyCommand.is_non_hero_combat_unit(unit as Node):
			continue
		escort += 1
		if EnemyArmyCommand.get_health_ratio(unit) < ESCORT_INJURED_HP_RATIO:
			injured += 1

	if escort > 0 and float(injured) / float(escort) > MAX_INJURED_ESCORT_RATIO:
		return false

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(creep_army)
	if army_center == Vector3.ZERO:
		return false

	var player_near: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		army_center,
		PLAYER_THREAT_ABORT_RADIUS
	)
	if player_near.is_empty():
		return true

	var player_power: float = float(EnemyArmyCommand.estimate_combat_strength(player_near))
	var army_power: float = float(EnemyArmyCommand.estimate_combat_strength(creep_army))
	if player_power > army_power * PLAYER_THREAT_STRENGTH_RATIO:
		return false

	return true


func _should_retreat_from_creeping(tree: SceneTree, creep_army: Array) -> bool:
	if EnemyArmyCommand.is_enemy_army_under_attack(tree, creep_army, ARMY_UNDER_ATTACK_RANGE):
		_record_creep_setback()
		EnemyAIDebug.log_creep_retreat("under attack")
		_retreat_creep_army(tree, "under attack", false)
		return true

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero != null:
		var hero_hp_ratio: float = EnemyArmyCommand.get_health_ratio(hero)
		if hero_hp_ratio < HERO_RETREAT_HP_RATIO:
			_record_creep_setback()
			EnemyAIDebug.log_creep_retreat(
				"hero HP %d%%" % int(round(hero_hp_ratio * 100.0))
			)
			_retreat_creep_army(tree, "hero low hp", false)
			return true

	if _should_abort_creep_push(tree, creep_army):
		_record_creep_setback()
		EnemyAIDebug.log_creep_retreat("army too weak")
		_retreat_creep_army(tree, "army too weak", false)
		return true

	if _creep_push_start_power > 0.0:
		var current_power: float = float(EnemyArmyCommand.estimate_combat_strength(creep_army))
		if current_power <= _creep_push_start_power * ARMY_SAFE_STRENGTH_RATIO:
			_record_creep_setback()
			EnemyAIDebug.log_creep_retreat("army strength low")
			_retreat_creep_army(tree, "army strength low", false)
			return true

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(creep_army)
	if army_center != Vector3.ZERO:
		var player_near: Array = EnemyArmyCommand.collect_player_military_near(
			tree,
			army_center,
			PLAYER_THREAT_ABORT_RADIUS
		)
		if not player_near.is_empty():
			var player_power: float = float(EnemyArmyCommand.estimate_combat_strength(player_near))
			var army_power: float = float(EnemyArmyCommand.estimate_combat_strength(creep_army))
			if player_power > army_power * PLAYER_THREAT_STRENGTH_RATIO:
				_record_creep_setback()
				EnemyAIDebug.log_creep_retreat("player army approaching")
				_retreat_creep_army(tree, "player army approaching", false)
				return true

	return false


func _select_camp(camp: Node3D, from_position: Vector3, army_power: int = 0) -> void:
	if camp == null or not is_instance_valid(camp):
		return

	var camp_id: int = camp.get_instance_id()
	_active_camp_handle = EntityHandle.from_node(camp)
	if EntityRegistry != null:
		_active_camp_handle = EntityRegistry.make_handle_for(camp)
	if camp_id == _active_camp_id:
		_active_camp = camp
		_reserved_camp_id = camp_id
		return

	_active_camp = camp
	_active_camp_id = camp_id
	_reserved_camp_id = camp_id
	_focus_creep = null
	_focus_creep_handle = EntityHandle.empty()
	_creep_push_start_power = 0.0
	_selected_camp_index = get_cleared_early_camp_count() + 1
	_army_moving_logged = false
	_mission_started_logged = false

	var camp_power: int = _estimate_camp_power(camp)
	var safe_army: float = maxf(float(army_power), 1.0)
	_last_safety_score = safe_army / maxf(float(camp_power), 1.0)
	EnemyAIDebug.log_creep_camp_selected_safety(
		_format_camp_name(camp),
		_last_safety_score
	)
	var distance: float = EnemyArmyCommand.horizontal_distance(camp.global_position, from_position)
	EnemyAIDebug.log_creeping_camp_selected(_format_camp_name(camp), distance)


func _on_camp_cleared(camp: Node3D) -> void:
	if camp != null and is_instance_valid(camp):
		_cleared_camp_ids[camp.get_instance_id()] = true
		EnemyAIDebug.log_creep_camp_cleared(_format_camp_name(camp))
	var cleared: int = get_cleared_early_camp_count()
	var target: int = _get_required_early_camps()
	EnemyAIDebug.log_creeping("Creeping: Camp cleared %d/%d" % [cleared, target])
	_reset_creep_setbacks()
	_creep_push_start_power = 0.0
	_army_moving_logged = false
	_needs_post_camp_regroup = true
	_release_camp_reservation()


func _clear_active_camp() -> void:
	_active_camp = null
	_active_camp_id = 0
	_focus_creep = null
	_active_camp_handle = EntityHandle.empty()
	_focus_creep_handle = EntityHandle.empty()
	_release_camp_reservation()
	if _director != null:
		_director.clear_creep_target()


func _release_camp_reservation() -> void:
	_reserved_camp_id = 0


func _cancel_creep_mission(_reason: String = "") -> void:
	_clear_active_camp()
	_set_creep_mission(CreepMission.NONE)
	_creep_push_start_power = 0.0
	_needs_post_camp_regroup = false
	_army_moving_logged = false
	_mission_started_logged = false
	if (
		EnemyArmyCommand.get_executable_mission()
		== EnemyArmyCommand.ExecutableMission.CREEPING
	):
		EnemyArmyCommand.clear_executable_mission(
			_reason if not _reason.is_empty() else "creep cancelled"
		)


func _sync_creeping_executable(
	army: Array,
	camp: Node3D,
	destination: Vector3,
	reason: String
) -> void:
	if not NodeSafety.is_alive_node(camp):
		return
	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.CREEPING,
		reason,
		camp,
		destination,
		_format_camp_name(camp),
		"attack-move",
		army,
		_reserved_camp_id != 0 and camp.get_instance_id() == _reserved_camp_id
	)


func _validate_and_sync_creeping(
	tree: SceneTree,
	army: Array,
	camp: Node3D,
	army_center: Vector3
) -> bool:
	var in_combat: bool = (
		_is_army_engaging_camp(tree, army, camp)
		or EnemyArmyCommand.is_enemy_army_under_attack(
			tree,
			army,
			ARMY_UNDER_ATTACK_RANGE
		)
	)
	var has_order: bool = (
		EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.CREEPING
		or _creep_mission in [CreepMission.MOVE_TO_CAMP, CreepMission.FIGHT_CAMP]
	)
	var validation: Dictionary = EnemyArmyCommand.validate_creeping_mission(
		tree,
		camp,
		_reserved_camp_id,
		army_center,
		has_order,
		in_combat
	)
	if validation.get("valid", false):
		_sync_creeping_executable(
			army,
			camp,
			camp.global_position if NodeSafety.is_alive_node(camp) else army_center,
			"creeping validated"
		)
		return true

	var reason: String = String(validation.get("reason", "creep objective invalid"))
	_clear_active_camp()
	_set_creep_mission(CreepMission.NONE)
	EnemyArmyCommand.clear_executable_mission(reason)

	if EnemyArmyCommand.is_army_in_hostile_territory(tree, army_center):
		_handle_army_in_hostile_territory(
			tree,
			army,
			army_center,
			EnemyArmyCommand.resolve_enemy_rally_position(tree)
		)
		return false

	## Pick a new mission rather than staying falsely CREEPING.
	_set_creep_mission(CreepMission.SELECT_NEXT_CAMP)
	return false


func _handle_army_in_hostile_territory(
	tree: SceneTree,
	army: Array,
	army_center: Vector3,
	rally_position: Vector3
) -> void:
	_cancel_creep_mission("army reached hostile base")

	if EnemyArmyCommand.handle_hostile_territory_idle(
		tree,
		army,
		army_center,
		"army reached hostile base"
	):
		return

	## Too weak to push — retreat or repath toward a real creep objective.
	var army_power: int = int(EnemyArmyCommand.estimate_combat_strength(army))
	var alternate_camp: Node3D = _find_best_creep_camp(
		tree,
		rally_position,
		army_power,
		army_center
	)
	if alternate_camp != null and is_instance_valid(alternate_camp):
		_select_camp(alternate_camp, army_center, army_power)
		var destination: Vector3 = _resolve_camp_attack_destination(
			tree,
			alternate_camp,
			army_center
		)
		_set_creep_mission(CreepMission.MOVE_TO_CAMP)
		_sync_creeping_executable(army, alternate_camp, destination, "repath to creep camp")
		if _combat_controller != null:
			_combat_controller.issue_immediate_group_move(
				army,
				destination,
				EnemyArmyCommand.ArmyMode.CREEPING,
				EnemyUnitMission.Mission.CREEP
			)
		return

	_retreat_creep_army(tree, "weak army in hostile territory", true)


func _sanitize_active_camp(tree: SceneTree) -> void:
	if _active_camp_handle != null and not _active_camp_handle.is_empty():
		var resolved: Node = _active_camp_handle.resolve()
		if resolved is Node3D:
			_active_camp = resolved as Node3D
			_active_camp_id = resolved.get_instance_id()
			_reserved_camp_id = _active_camp_id
		else:
			_clear_active_camp()
			return

	if _active_camp == null:
		_active_camp_id = 0
		_reserved_camp_id = 0
		_active_camp_handle = EntityHandle.empty()
		return

	if not is_instance_valid(_active_camp):
		_clear_active_camp()
		return

	if _is_player_contesting_camp(tree, _active_camp):
		_clear_active_camp()


func _engage_camp_focus_fire(tree: SceneTree, army: Array, camp: Node3D) -> void:
	EnemyAIDebug.log_creeping("Creeping: Engaging camp")

	if _focus_creep_handle != null and not _focus_creep_handle.is_empty():
		var focus_node: Node = _focus_creep_handle.resolve()
		_focus_creep = focus_node as Node3D if focus_node is Node3D else null
		if _focus_creep == null:
			_focus_creep_handle = EntityHandle.empty()

	if not NodeSafety.is_alive_node(_focus_creep) or not _is_living_creep(_focus_creep):
		_focus_creep = _pick_focus_creep(tree, camp, army)
		_focus_creep_handle = EntityHandle.from_node(_focus_creep)
		_focus_reissue_timer = FOCUS_REISSUE_SECONDS

	## Do not chase leashed creeps far from the camp.
	if (
		NodeSafety.is_alive_node(_focus_creep)
		and _focus_creep is Node3D
		and EnemyArmyCommand.horizontal_distance(
			(_focus_creep as Node3D).global_position,
			camp.global_position
		) > CAMP_LEASH_CHASE_RADIUS
	):
		_focus_creep = _pick_focus_creep(tree, camp, army)
		_focus_creep_handle = EntityHandle.from_node(_focus_creep)
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
	var best_score: float = -INF

	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node3D:
			continue

		var child: Node3D = child_variant as Node3D
		if not _is_living_creep(child):
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			army_center,
			child.global_position
		)
		if distance > CAMP_LEASH_CHASE_RADIUS:
			continue

		var damage: int = 8
		if "attack_damage" in child:
			damage = int(child.get("attack_damage"))
		var health: int = CombatTargetValidation.get_target_current_health(child)
		## Dangerous creeps first; low-HP finishes as a tie-breaker.
		var score: float = float(damage) * 10.0 - float(health) * 0.02 - distance * 0.5
		if score > best_score:
			best_score = score
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
		return maxi(
			EnemyArmyCommand.CREEP_MIN_NON_HERO_UNITS,
			_director.get_min_army_size_for_current_phase()
		)
	return EnemyArmyCommand.CREEP_MIN_NON_HERO_UNITS


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
	_set_creep_mission(CreepMission.RETURN_TO_BASE)
	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.RETREAT,
		reason if not reason.is_empty() else "creep retreat",
		null,
		EnemyArmyCommand.resolve_enemy_rally_position(tree),
		"Rally",
		"move",
		[],
		false
	)
	if log_generic and not reason.is_empty():
		EnemyAIDebug.log_creep_retreat(reason)

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


func _should_abort_creep_push(_tree: SceneTree, creep_army: Array) -> bool:
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
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	var hero_hp: float = 1.0
	var hero_mana: float = 1.0
	var hero_level: int = 1
	if hero != null:
		hero_hp = EnemyArmyCommand.get_health_ratio(hero)
		hero_mana = float(hero.current_mana) / float(maxi(hero.max_mana, 1))
		hero_level = hero.level

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
		## Stronger camps only after the hero/squad has leveled.
		if camp_power >= STRONG_CAMP_POWER_THRESHOLD and hero_level < 3:
			continue

		if float(camp_power) * power_margin > float(army_power):
			continue

		var player_near_power: int = EnemyArmyCommand.estimate_combat_strength(
			EnemyArmyCommand.collect_player_military_near(
				tree,
				camp.global_position,
				PLAYER_THREAT_ABORT_RADIUS
			)
		)
		if float(player_near_power) > float(army_power) * PLAYER_THREAT_STRENGTH_RATIO:
			continue

		var camp_xp: int = _estimate_camp_xp(camp)
		var score: float = _score_camp(
			camp_xp,
			camp_power,
			distance,
			army_power,
			hero_hp,
			hero_mana,
			player_near_power
		)
		if score > best_score:
			best_score = score
			best_camp = camp

	return best_camp


func _score_camp(
	camp_xp: int,
	camp_power: int,
	distance: float,
	army_power: int,
	hero_hp: float = 1.0,
	hero_mana: float = 1.0,
	player_near_power: int = 0
) -> float:
	var safe_power: float = maxf(float(camp_power), 1.0)
	var risk: float = safe_power / maxf(float(army_power), 1.0)
	var xp_per_risk: float = float(camp_xp) / maxf(risk, 0.2)
	var distance_factor: float = 1.0 + distance / maxf(CREEP_SEARCH_RANGE, 1.0)
	var hero_factor: float = 0.65 + 0.25 * hero_hp + 0.10 * hero_mana
	var player_penalty: float = float(player_near_power) * 0.01
	# Prefer high XP/risk, short travel, weaker camps, healthy hero, away from player.
	return (
		(xp_per_risk / distance_factor) * hero_factor
		- safe_power * 0.002
		- distance * 0.15
		- player_penalty
	)


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
	_tree: SceneTree,
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
