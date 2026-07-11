class_name EnemyDefenseManager
extends Node

## Intercepts player threats near the enemy base. Emergency defense owns DEFENDING mode until clear.

const DEFENSE_TICK_INTERVAL_SECONDS := 1.0
const THREAT_CLEAR_SECONDS := 6.0
const DEFENSE_MAINTAIN_INTERVAL_SECONDS := 2.5

var _tick_timer: float = 0.0
var _threat_clear_timer: float = 0.0
var _emergency_clear_timer: float = 0.0
var _emergency_gather_timer: float = 0.0
var _defense_maintain_timer: float = 0.0
var _logged_recall: bool = false
var _logged_engagement: bool = false
var _combat_controller: EnemyCombatController = null
var _match_start_msec: int = 0


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_combat_controller = get_parent().get_node_or_null("EnemyCombatController") as EnemyCombatController


func _process(delta: float) -> void:
	EnemyArmyCommand.apply_pending_strategic_transition()
	_tick_timer += delta
	if _tick_timer < DEFENSE_TICK_INTERVAL_SECONDS:
		return

	_tick_timer = 0.0
	_update_defense()


func _get_match_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func _update_defense() -> void:
	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if EnemyArmyCommand.is_emergency_defense_active():
		_update_active_emergency_defense(tree, rally_position)
		return

	var emergency_threat: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(tree)
	if emergency_threat.get("threatened", false):
		if not EnemyArmyCommand.should_allow_finishing_during_emergency(tree, emergency_threat):
			_start_emergency_defense(tree, rally_position, emergency_threat)
			return

	_update_standard_defense(tree, rally_position)


func _start_emergency_defense(
	tree: SceneTree,
	rally_position: Vector3,
	threat: Dictionary
) -> void:
	EnemyArmyCommand.prepare_defense_recall(tree)
	EnemyArmyCommand.activate_emergency_defense(threat)
	_emergency_gather_timer = 0.0
	_emergency_clear_timer = 0.0
	_logged_recall = false
	_logged_engagement = false
	_commit_emergency_defense(tree, rally_position, threat)


func _update_active_emergency_defense(tree: SceneTree, rally_position: Vector3) -> void:
	if EnemyArmyCommand.has_meaningful_core_base_threat(tree):
		_emergency_clear_timer = 0.0
		var threat: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(tree)
		EnemyArmyCommand.update_emergency_defense_threat(threat)
		_commit_emergency_defense(tree, rally_position, threat)
		return

	_emergency_clear_timer += DEFENSE_TICK_INTERVAL_SECONDS
	if _emergency_clear_timer < EnemyArmyCommand.EMERGENCY_CLEAR_SECONDS:
		return

	_end_emergency_defense(tree, rally_position)


func _end_emergency_defense(tree: SceneTree, rally_position: Vector3) -> void:
	EnemyArmyCommand.deactivate_emergency_defense()
	_emergency_clear_timer = 0.0
	_emergency_gather_timer = 0.0
	_logged_recall = false
	_logged_engagement = false

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.INTERCEPTING:
		EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.INTERCEPTING)

	if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		EnemyArmyCommand.with_authorized_orders(func() -> void:
			EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)
		)


func _commit_emergency_defense(
	tree: SceneTree,
	rally_position: Vector3,
	threat: Dictionary
) -> void:
	var intercept_position: Vector3 = EnemyArmyCommand.resolve_defense_intercept_position(
		tree,
		threat,
		rally_position
	)
	var skip_gather: bool = (
		threat.get("reason", &"") == &"town_center"
		or threat.get("force_recall", false)
		or EnemyArmyCommand.is_critical_defense_threat(threat)
	)
	var recall_entire_army: bool = _should_emergency_recall_army(tree, threat)

	if recall_entire_army:
		EnemyArmyCommand.prepare_defense_recall(tree)
		if not _logged_recall:
			var defender_count: int = EnemyArmyCommand.collect_living_combat_units(tree).size()
			print("AI DEFENSE: recalling attack army defenders=%d" % defender_count)
			_logged_recall = true

	if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING):
		return

	if not skip_gather:
		_emergency_gather_timer += DEFENSE_TICK_INTERVAL_SECONDS
		if _emergency_gather_timer < EnemyArmyCommand.EMERGENCY_GATHER_WAIT_SECONDS:
			_gather_emergency_defenders(tree, rally_position, intercept_position)
			if recall_entire_army:
				EnemyArmyCommand.pull_emergency_defense_reinforcements(tree, intercept_position)
			return

	_issue_defense_group(tree, intercept_position, EnemyArmyCommand.ArmyMode.DEFENDING, threat)


func _gather_emergency_defenders(
	tree: SceneTree,
	rally_position: Vector3,
	intercept_position: Vector3
) -> void:
	var hold_position: Vector3 = EnemyArmyCommand.resolve_defense_hold_position(
		rally_position,
		intercept_position
	)
	var gather_units: Array = EnemyArmyCommand.build_defense_army(tree, intercept_position)
	if gather_units.is_empty():
		return

	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_hold_at_rally(
			gather_units,
			hold_position,
			EnemyUnitMission.Mission.DEFEND
		)
	)


func _should_emergency_recall_army(tree: SceneTree, threat: Dictionary) -> bool:
	if EnemyArmyCommand.should_recall_offensive_for_defense(tree):
		return true

	if threat.get("force_recall", false):
		return true

	return EnemyArmyCommand.is_emergency_threat_serious(tree, threat)


func _update_standard_defense(tree: SceneTree, rally_position: Vector3) -> void:
	var threat: Dictionary = EnemyArmyCommand.evaluate_defense_threat(tree)
	if threat.get("threatened", false):
		_threat_clear_timer = 0.0

		var intercept_position: Vector3 = EnemyArmyCommand.resolve_defense_intercept_position(
			tree,
			threat,
			rally_position
		)

		var defense_mode: EnemyArmyCommand.ArmyMode = (
			EnemyArmyCommand.ArmyMode.INTERCEPTING
			if threat.get("reason", &"") == &"approach"
			else EnemyArmyCommand.ArmyMode.DEFENDING
		)

		var already_defending: bool = EnemyArmyCommand.get_army_mode() in [
			EnemyArmyCommand.ArmyMode.DEFENDING,
			EnemyArmyCommand.ArmyMode.INTERCEPTING,
		]
		if not already_defending:
			if not EnemyArmyCommand.try_claim_army_mode(defense_mode):
				return
			if defense_mode == EnemyArmyCommand.ArmyMode.INTERCEPTING:
				EnemyArmyCommand.debug_combat_log("intercepting player army")
			EnemyArmyCommand.request_strategic_state(
				EnemyArmyCommand.StrategicState.DEFENDING,
				String(threat.get("reason", "standard defense"))
			)
			_issue_defense_group(tree, intercept_position, defense_mode, threat)
			return

		_maintain_standard_defense(tree, intercept_position, defense_mode, threat)
		return

	if EnemyArmyCommand.get_army_mode() not in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]:
		return

	_threat_clear_timer += DEFENSE_TICK_INTERVAL_SECONDS
	if _threat_clear_timer < THREAT_CLEAR_SECONDS:
		return

	EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)
	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.INTERCEPTING:
		EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.INTERCEPTING)
	_threat_clear_timer = 0.0

	if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		EnemyArmyCommand.request_strategic_state(
			EnemyArmyCommand.StrategicState.RECOVERING,
			"local defense cleared"
		)
		EnemyArmyCommand.with_authorized_orders(func() -> void:
			EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)
		)


func _issue_defense_group(
	tree: SceneTree,
	intercept_position: Vector3,
	defense_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.ArmyMode.DEFENDING,
	threat: Dictionary = {}
) -> void:
	var defense_army: Array = EnemyArmyCommand.build_defense_army(tree, intercept_position)
	defense_army = NodeSafety.clean_node_array(defense_army)
	if defense_army.is_empty():
		return

	var force_commit: bool = EnemyArmyCommand.is_critical_defense_threat(threat)
	var commitment: Dictionary = EnemyArmyCommand.evaluate_defense_commitment(
		tree,
		defense_army,
		intercept_position
	)
	if not commitment.get("can_commit", false) and not force_commit:
		EnemyArmyCommand.debug_combat_log("defense held: threat too strong")
		var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
		EnemyArmyCommand.with_authorized_orders(func() -> void:
			EnemyArmyCommand.command_hold_at_rally(
				defense_army,
				rally_position,
				EnemyUnitMission.Mission.DEFEND
			)
		)
		return

	if not _logged_engagement:
		var enemy_count: int = EnemyArmyCommand.collect_player_military_near(
			tree,
			intercept_position,
			EnemyArmyCommand.DEFENSE_THREAT_POWER_RANGE
		).size()
		print("AI DEFENSE: engaging %d enemies near Town Center" % enemy_count)
		_logged_engagement = true

	var use_immediate: bool = (
		EnemyArmyCommand.is_emergency_defense_active()
		or force_commit
	)

	if _combat_controller != null:
		if use_immediate:
			_combat_controller.issue_immediate_group_move(
				defense_army,
				intercept_position,
				defense_mode,
				EnemyUnitMission.Mission.DEFEND
			)
		else:
			_combat_controller.request_assembled_group_move(
				defense_army,
				intercept_position,
				defense_mode,
				EnemyUnitMission.Mission.DEFEND,
				true,
				true
			)
		return

	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_attack_move(
			defense_army,
			intercept_position,
			EnemyUnitMission.Mission.DEFEND
		)
	)


func _maintain_standard_defense(
	tree: SceneTree,
	intercept_position: Vector3,
	defense_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.ArmyMode.DEFENDING,
	threat: Dictionary = {}
) -> void:
	_defense_maintain_timer += DEFENSE_TICK_INTERVAL_SECONDS
	if _defense_maintain_timer < DEFENSE_MAINTAIN_INTERVAL_SECONDS:
		return

	_defense_maintain_timer = 0.0
	_issue_defense_group(tree, intercept_position, defense_mode, threat)
