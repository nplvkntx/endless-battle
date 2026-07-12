class_name EnemyCombatController
extends Node

## Authoritative combat coordinator. Owns final group movement orders for attack, creep,
## retreat, regroup, and assembly. Other managers request actions through this node.

const TICK_INTERVAL_SECONDS := 0.75
const PLAYER_CREEP_SCAN_RANGE := 48.0
const AMBUSH_STAGING_DISTANCE := 14.0
const OPENING_PHASE_SECONDS := 300.0

var _tick_timer: float = 0.0
var _match_start_msec: int = 0
var _assembly_target_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.ArmyMode.IDLE
var _assembly_destination: Vector3 = Vector3.ZERO
var _assembly_mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.REGROUP
var _assembly_units: Array = []
var _assembly_use_attack_move: bool = true
var _pending_player_creep_ambush: Vector3 = Vector3.ZERO
var _active_player_creep_contest_camp: Node3D = null
var _creep_manager: EnemyCreepManager = null
var _director: EnemyStrategicDirector = null


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_creep_manager = get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager
	_director = get_parent().get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector


func _process(delta: float) -> void:
	EnemyArmyCommand.apply_pending_strategic_transition()
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	EnemyArmyCommand.tick_perf_diagnostics(get_tree(), delta)
	EnemyArmyCommand.tick_retreat_cooldown(delta)
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL_SECONDS:
		return

	_tick_timer = 0.0
	_update_combat_control(delta * (1.0 / TICK_INTERVAL_SECONDS))


func get_match_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func _update_combat_control(delta: float) -> void:
	PerfCounters.record_ai_combat_update()
	var tree: SceneTree = get_tree()
	var elapsed: float = get_match_elapsed_seconds()
	EnemyArmyCommand.purge_and_rebuild_main_army(tree)
	_update_opening_phase(tree)

	if EnemyArmyCommand.check_destroyed_army_regroup(tree, elapsed):
		if _active_player_creep_contest_camp != null:
			EnemyArmyCommand.record_creep_contest_cooldown(
				_active_player_creep_contest_camp,
				"army destroyed"
			)
			_active_player_creep_contest_camp = null
	EnemyArmyCommand.tick_reinforcement_pool(tree, elapsed)

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if army_mode == EnemyArmyCommand.ArmyMode.RETREATING:
		EnemyArmyCommand.complete_retreat_to_regroup(tree)
		return

	if army_mode == EnemyArmyCommand.ArmyMode.ASSEMBLING:
		_process_assembly(tree, delta)
		return

	if army_mode in [
		EnemyArmyCommand.ArmyMode.ATTACKING,
		EnemyArmyCommand.ArmyMode.CREEPING,
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]:
		if EnemyArmyCommand.should_retreat_from_fight(tree):
			if _active_player_creep_contest_camp != null:
				EnemyArmyCommand.record_creep_contest_cooldown(
					_active_player_creep_contest_camp,
					"retreat from contest"
				)
				_active_player_creep_contest_camp = null
			EnemyArmyCommand.initiate_group_retreat(tree, "fight unfavorable")
		return

	if army_mode == EnemyArmyCommand.ArmyMode.REGROUPING:
		_maintain_regrouping(tree)
		return

	_evaluate_player_creep_opportunities(tree)


func _update_opening_phase(tree: SceneTree) -> void:
	var elapsed: float = get_match_elapsed_seconds()
	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()

	if elapsed > OPENING_PHASE_SECONDS:
		if army_mode == EnemyArmyCommand.ArmyMode.OPENING:
			EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.OPENING)
		return

	if army_mode in [
		EnemyArmyCommand.ArmyMode.ATTACKING,
		EnemyArmyCommand.ArmyMode.CREEPING,
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
		EnemyArmyCommand.ArmyMode.RETREATING,
		EnemyArmyCommand.ArmyMode.ASSEMBLING,
	]:
		return

	EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.OPENING)


func _maintain_regrouping(tree: SceneTree) -> void:
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	EnemyArmyCommand.pull_reinforcement_units_to_rally(tree, rally_position)
	var min_army: int = EnemyArmyCommand.get_phase_min_army_size(get_match_elapsed_seconds())
	var plan: Dictionary = EnemyArmyCommand.build_coordinated_combat_group(
		tree,
		rally_position,
		min_army,
		true
	)
	var ready_count: int = int(plan.get("non_hero_count", 0))
	EnemyArmyCommand.debug_combat_log(
		"regrouping: %d/%d units ready"
		% [ready_count, min_army]
	)


func _process_assembly(tree: SceneTree, delta: float) -> void:
	if not EnemyArmyCommand.is_assembly_ready(tree, delta):
		var assembled: Array = EnemyArmyCommand.filter_units_near_rally(
			_assembly_units,
			EnemyArmyCommand.resolve_enemy_rally_position(tree),
			EnemyArmyCommand.ASSEMBLY_RADIUS
		)
		EnemyArmyCommand.debug_combat_log(
			"regrouping: %d/%d units assembled"
			% [assembled.size(), _assembly_units.size()]
		)
		return

	EnemyArmyCommand.finish_assembly(_assembly_target_mode)
	if _assembly_target_mode == EnemyArmyCommand.ArmyMode.ATTACKING:
		EnemyArmyCommand.begin_offensive_wave(_assembly_units)

	if _assembly_use_attack_move:
		EnemyArmyCommand.issue_group_combat_move(
			tree,
			_assembly_units,
			_assembly_destination,
			_assembly_mission,
			_assembly_target_mode,
			_assembly_target_mode == EnemyArmyCommand.ArmyMode.ATTACKING
		)
	else:
		EnemyArmyCommand.with_authorized_orders(func() -> void:
			EnemyArmyCommand.command_hold_at_rally(
				_assembly_units,
				_assembly_destination,
				_assembly_mission
			)
		)

	_assembly_units.clear()
	_assembly_destination = Vector3.ZERO
	_assembly_use_attack_move = true


func request_assembled_group_move(
	units: Array,
	destination: Vector3,
	mode: EnemyArmyCommand.ArmyMode,
	mission: EnemyUnitMission.Mission,
	use_attack_move: bool = true,
	skip_min_army_gate: bool = false
) -> bool:
	units = NodeSafety.clean_node_array(units)
	units = EnemyArmyCommand.filter_units_for_field_combat(units, mission)
	if units.is_empty() or destination == Vector3.ZERO:
		return false

	if mission == EnemyUnitMission.Mission.DEFEND and EnemyArmyCommand.is_defense_blocking_offense():
		skip_min_army_gate = true

	if mission == EnemyUnitMission.Mission.ATTACK and not EnemyArmyCommand.allows_attack_wave_orders():
		return false

	if mission == EnemyUnitMission.Mission.CREEP and not EnemyArmyCommand.allows_creep_orders():
		EnemyArmyCommand.debug_combat_log("AI CREEP: ignoring player creep activity, no favorable interception")
		return false

	var tree: SceneTree = get_tree()
	var elapsed: float = get_match_elapsed_seconds()
	var min_army: int = EnemyArmyCommand.get_phase_min_army_size(elapsed)
	if (
		not skip_min_army_gate
		and mission in [EnemyUnitMission.Mission.ATTACK, EnemyUnitMission.Mission.CREEP]
	):
		var non_hero_count: int = 0
		for unit: Variant in units:
			if EnemyArmyCommand.is_non_hero_combat_unit(unit as Node):
				non_hero_count += 1
		if non_hero_count < min_army:
			EnemyArmyCommand.debug_combat_log(
				"assembly blocked: %d/%d units" % [non_hero_count, min_army]
			)
			return false
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.RETREATING:
		return false

	if EnemyArmyCommand.is_retreat_on_cooldown() and mission != EnemyUnitMission.Mission.DEFEND:
		return false

	var current_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if current_mode == mode and _assembly_destination.distance_to(destination) < 2.0:
		return true

	if current_mode == EnemyArmyCommand.ArmyMode.ASSEMBLING:
		return false

	_assembly_units = units.duplicate()
	_assembly_destination = destination
	_assembly_target_mode = mode
	_assembly_mission = mission
	_assembly_use_attack_move = use_attack_move
	return EnemyArmyCommand.begin_assembly(tree, mode, rally_position, units)


func issue_immediate_group_move(
	units: Array,
	destination: Vector3,
	mode: EnemyArmyCommand.ArmyMode,
	mission: EnemyUnitMission.Mission,
	allow_attack_override_creep: bool = false
) -> bool:
	return EnemyArmyCommand.issue_group_combat_move(
		get_tree(),
		units,
		destination,
		mission,
		mode,
		allow_attack_override_creep
	)


func issue_group_retreat(reason: String = "") -> bool:
	return EnemyArmyCommand.initiate_group_retreat(get_tree(), reason)


func can_launch_offensive_action() -> bool:
	var mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if mode == EnemyArmyCommand.ArmyMode.RETREATING:
		return false
	if EnemyArmyCommand.is_retreat_on_cooldown():
		return false
	if mode == EnemyArmyCommand.ArmyMode.ASSEMBLING:
		return false
	return true


func _evaluate_player_creep_opportunities(tree: SceneTree) -> void:
	if not can_launch_offensive_action():
		return

	if not EnemyArmyCommand.allows_creep_orders():
		return

	if EnemyArmyCommand.is_defense_blocking_offense():
		return

	if EnemyArmyCommand.get_army_mode() not in [
		EnemyArmyCommand.ArmyMode.IDLE,
		EnemyArmyCommand.ArmyMode.OPENING,
		EnemyArmyCommand.ArmyMode.REGROUPING,
	]:
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	var elapsed: float = get_match_elapsed_seconds()
	for camp: Node3D in CreepCampSafety.collect_active_camps(tree):
		if camp == null or not is_instance_valid(camp):
			continue

		if EnemyArmyCommand.is_creep_contest_on_cooldown(camp):
			continue

		var request: Dictionary = _build_player_creep_contest_request(tree, camp, rally_position)
		var evaluation: Dictionary = _evaluate_player_creep_request(tree, camp, rally_position, request, elapsed)
		var decision: StringName = evaluation.get("decision", &"ignore")
		match decision:
			&"contest":
				_try_contest_player_creep(tree, camp, rally_position, evaluation)
			&"ambush":
				_stage_ambush_after_creep(tree, camp, rally_position, evaluation)
			&"defend":
				_hold_defense_near_base(tree, rally_position)
			&"reject":
				EnemyArmyCommand.record_creep_contest_cooldown(
					camp,
					String(evaluation.get("reason", "rejected"))
				)
			_:
				pass


func _build_player_creep_contest_request(
	tree: SceneTree,
	camp: Node3D,
	rally_position: Vector3
) -> Dictionary:
	var camp_position: Vector3 = camp.global_position
	var player_units: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		camp_position,
		EnemyArmyCommand.PLAYER_CREEP_DETECT_RADIUS
	)
	var player_strength: float = EnemyArmyCommand.estimate_combat_strength(player_units)
	var creep_strength: float = _estimate_remaining_creep_strength(camp)
	var hero_present: bool = false
	for unit: Variant in player_units:
		if unit is Hero:
			hero_present = true
			break

	return {
		"camp": camp,
		"camp_position": camp_position,
		"player_units": player_units,
		"player_strength": player_strength,
		"player_hero_present": hero_present,
		"creep_strength": creep_strength,
		"rally_position": rally_position,
	}


func _evaluate_player_creep_request(
	tree: SceneTree,
	camp: Node3D,
	rally_position: Vector3,
	request: Dictionary,
	match_elapsed_seconds: float
) -> Dictionary:
	if request.get("player_units", []).is_empty():
		return {"decision": &"ignore"}

	var contest_eval: Dictionary = EnemyArmyCommand.evaluate_creep_contest_request(
		tree,
		camp,
		rally_position,
		match_elapsed_seconds
	)
	if contest_eval.get("allowed", false):
		return {
			"decision": &"contest",
			"units": contest_eval.get("units", []),
			"player_strength": contest_eval.get("player_strength", 0.0),
			"ai_strength": contest_eval.get("ai_strength", 0.0),
		}

	var reason: StringName = contest_eval.get("reason", &"rejected")
	var camp_position: Vector3 = request.get("camp_position", camp.global_position)
	var player_strength: float = float(request.get("player_strength", 0.0))

	if reason in [&"army_not_ready", &"not_assembled", &"hero_missing", &"cooldown", &"retreat_cooldown", &"outpowered", &"arrival_too_late"]:
		EnemyArmyCommand.debug_combat_log(
			"AI CREEP: ignoring player creep activity, no favorable interception (%s)"
			% String(reason)
		)
		return {"decision": &"ignore", "reason": reason, "player_strength": player_strength}

	var ai_plan: Dictionary = EnemyArmyCommand.build_coordinated_combat_group(
		tree,
		rally_position,
		EnemyArmyCommand.get_phase_min_army_size(match_elapsed_seconds),
		true
	)
	var ai_units: Array = ai_plan.get("units", [])
	var ai_strength: float = EnemyArmyCommand.estimate_combat_strength(ai_units)
	var ambush_gate: Dictionary = EnemyArmyCommand.evaluate_strength_gate(
		ai_strength,
		player_strength * 0.65,
		&"normal"
	)
	if ambush_gate.get("allowed", false) and ai_plan.get("can_launch", false):
		return {
			"decision": &"ambush",
			"units": ai_units,
			"player_strength": player_strength,
		}

	if EnemyArmyCommand.horizontal_distance(camp_position, rally_position) < 45.0:
		EnemyArmyCommand.debug_combat_log(
			"AI CREEP: ignoring player creep activity near base, no favorable interception"
		)
		return {"decision": &"ignore", "reason": reason, "player_strength": player_strength}

	EnemyArmyCommand.debug_combat_log("ignoring creep contest: %s" % String(reason))
	return {"decision": &"reject", "reason": reason, "player_strength": player_strength}


func _try_contest_player_creep(
	tree: SceneTree,
	camp: Node3D,
	rally_position: Vector3,
	evaluation: Dictionary
) -> void:
	if _director != null and not _director.should_prioritize_attack():
		if _creep_manager != null and _creep_manager.has_safe_creep_camp_available():
			EnemyArmyCommand.record_creep_contest_cooldown(camp, "neutral creep priority")
			return

	var units: Array = evaluation.get("units", [])
	if units.is_empty():
		EnemyArmyCommand.record_creep_contest_cooldown(camp, "empty contest group")
		return

	var contest_eval: Dictionary = EnemyArmyCommand.evaluate_creep_contest_request(
		tree,
		camp,
		rally_position,
		get_match_elapsed_seconds()
	)
	if not contest_eval.get("allowed", false):
		EnemyArmyCommand.record_creep_contest_cooldown(
			camp,
			String(contest_eval.get("reason", "revalidation_failed"))
		)
		return

	units = contest_eval.get("units", units)
	var destination: Vector3 = camp.global_position
	_active_player_creep_contest_camp = camp
	EnemyArmyCommand.debug_combat_log(
		"creep contest approved: %d units vs player strength %.1f"
		% [units.size(), float(evaluation.get("player_strength", 0.0))]
	)
	request_assembled_group_move(
		units,
		destination,
		EnemyArmyCommand.ArmyMode.ATTACKING,
		EnemyUnitMission.Mission.ATTACK
	)


func _stage_ambush_after_creep(
	tree: SceneTree,
	camp: Node3D,
	rally_position: Vector3,
	evaluation: Dictionary
) -> void:
	var units: Array = evaluation.get("units", [])
	if units.is_empty():
		return

	var camp_position: Vector3 = camp.global_position
	var direction: Vector3 = (rally_position - camp_position)
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3(1.0, 0.0, 0.0)
	else:
		direction = direction.normalized()

	var staging_position: Vector3 = camp_position + direction * AMBUSH_STAGING_DISTANCE
	_pending_player_creep_ambush = camp_position
	request_assembled_group_move(
		units,
		staging_position,
		EnemyArmyCommand.ArmyMode.REGROUPING,
		EnemyUnitMission.Mission.REGROUP,
		false
	)


func _hold_defense_near_base(tree: SceneTree, rally_position: Vector3) -> void:
	if EnemyArmyCommand.get_army_mode() in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]:
		return

	var min_army: int = EnemyArmyCommand.get_phase_min_army_size(get_match_elapsed_seconds())
	var plan: Dictionary = EnemyArmyCommand.build_coordinated_combat_group(
		tree,
		rally_position,
		min_army,
		true
	)
	if not plan.get("can_launch", false):
		if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
			EnemyArmyCommand.with_authorized_orders(func() -> void:
				EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)
			)
		return

	request_assembled_group_move(
		plan.get("units", []),
		rally_position,
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyUnitMission.Mission.DEFEND
	)


func _estimate_remaining_creep_strength(camp) -> float:
	if not NodeSafety.is_alive_node(camp):
		return 0.0

	var strength: float = 0.0
	for child_variant: Variant in camp.get_children():
		if child_variant == null or not is_instance_valid(child_variant) or not child_variant is Node:
			continue

		var child: Node = child_variant as Node
		if not CombatTargetValidation.is_neutral_creep(child):
			continue
		if CombatTargetValidation.get_target_current_health(child) <= 0:
			continue

		strength += 80.0

	return strength
