class_name EnemyDefenseManager
extends Node

## Intercepts player threats near the enemy base. Emergency defense owns DEFENDING mode until clear.

const DEFENSE_TICK_INTERVAL_SECONDS := 1.0
const THREAT_CLEAR_SECONDS := 6.0

var _tick_timer: float = 0.0
var _threat_clear_timer: float = 0.0
var _emergency_clear_timer: float = 0.0
var _emergency_gather_timer: float = 0.0
var _logged_recall: bool = false


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < DEFENSE_TICK_INTERVAL_SECONDS:
		return

	_tick_timer = 0.0
	_update_defense()


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
	EnemyArmyCommand.activate_emergency_defense(threat)
	_emergency_gather_timer = 0.0
	_emergency_clear_timer = 0.0
	_logged_recall = false
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

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)

	if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)


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
	)
	var recall_entire_army: bool = _should_emergency_recall_army(tree, threat)

	if recall_entire_army:
		EnemyArmyCommand.prepare_defense_recall(tree)
		if not _logged_recall:
			var defender_count: int = EnemyArmyCommand.collect_living_combat_units(tree).size()
			print("[AI] RECALLING ARMY defenders=%d" % defender_count)
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

	var defense_army: Array = EnemyArmyCommand.build_defense_army(tree, intercept_position)
	if defense_army.is_empty():
		return

	EnemyArmyCommand.command_attack_move(
		defense_army,
		intercept_position,
		EnemyUnitMission.Mission.DEFEND
	)


func _gather_emergency_defenders(
	tree: SceneTree,
	rally_position: Vector3,
	intercept_position: Vector3
) -> void:
	var hold_position: Vector3 = EnemyArmyCommand.resolve_defense_hold_position(
		rally_position,
		intercept_position
	)
	var gather_units: Array = []
	for unit: Variant in EnemyArmyCommand.collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		if not EnemyArmyCommand.is_living_combat_unit(unit as Node):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if (
			mission != EnemyUnitMission.Mission.IDLE
			and mission != EnemyUnitMission.Mission.REGROUP
			and mission != EnemyUnitMission.Mission.DEFEND
		):
			continue

		if (
			EnemyArmyCommand.horizontal_distance(
				(unit as Node3D).global_position,
				rally_position
			)
			> EnemyArmyCommand.DEFENSE_GATHER_MAX_DISTANCE
		):
			continue

		gather_units.append(unit)

	if gather_units.is_empty():
		return

	EnemyArmyCommand.command_hold_at_rally(
		gather_units,
		hold_position,
		EnemyUnitMission.Mission.DEFEND
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
		var recall_entire_army: bool = _should_recall_entire_army_for_threat(tree, threat)

		if recall_entire_army:
			EnemyArmyCommand.prepare_defense_recall(tree)
			if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING):
				return

			var defense_army: Array = EnemyArmyCommand.build_defense_army(
				tree,
				intercept_position
			)
			if defense_army.is_empty():
				return

			EnemyArmyCommand.command_attack_move(
				defense_army,
				intercept_position,
				EnemyUnitMission.Mission.DEFEND
			)
			return

		if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
			var committed_defenders: Array = EnemyArmyCommand.build_defense_army(
				tree,
				intercept_position
			)
			if committed_defenders.is_empty():
				return

			EnemyArmyCommand.command_attack_move(
				committed_defenders,
				intercept_position,
				EnemyUnitMission.Mission.DEFEND
			)
			return

		if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING):
			return

		var nearby_defenders: Array = EnemyArmyCommand.filter_units_near_rally(
			EnemyArmyCommand.build_defense_army(tree, intercept_position),
			rally_position,
			EnemyArmyCommand.DEFENSE_GATHER_MAX_DISTANCE
		)
		if nearby_defenders.is_empty():
			EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)
			return

		EnemyArmyCommand.command_attack_move(
			nearby_defenders,
			intercept_position,
			EnemyUnitMission.Mission.DEFEND
		)
		return

	if EnemyArmyCommand.get_army_mode() != EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	_threat_clear_timer += DEFENSE_TICK_INTERVAL_SECONDS
	if _threat_clear_timer < THREAT_CLEAR_SECONDS:
		return

	EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)
	_threat_clear_timer = 0.0

	if EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.REGROUPING):
		EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)


func _should_recall_entire_army_for_threat(tree: SceneTree, threat: Dictionary) -> bool:
	if EnemyArmyCommand.should_recall_offensive_for_defense(tree):
		return true

	if threat.get("force_commit", false):
		return true

	if EnemyArmyCommand.is_finishing_mode_active():
		return false

	var reason: StringName = threat.get("reason", &"")
	return reason == &"base" or reason == &"buildings" or reason == &"workers"
