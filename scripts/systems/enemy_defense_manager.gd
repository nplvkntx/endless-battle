class_name EnemyDefenseManager
extends Node

## Intercepts player threats near the enemy base and holds DEFENDING army mode until clear.

const DEFENSE_TICK_INTERVAL_SECONDS := 1.0
const THREAT_CLEAR_SECONDS := 6.0

var _tick_timer: float = 0.0
var _threat_clear_timer: float = 0.0


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

	var reason: StringName = threat.get("reason", &"")
	return reason == &"base" or reason == &"buildings" or reason == &"workers"
