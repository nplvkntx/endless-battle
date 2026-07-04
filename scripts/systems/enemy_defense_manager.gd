class_name EnemyDefenseManager
extends Node

## Intercepts player threats near the enemy base and holds DEFENDING army mode until clear.

const DEFENSE_TICK_INTERVAL_SECONDS := 1.0
const THREAT_CLEAR_SECONDS := 6.0
const DEFENSE_MIN_GROUPED_UNITS := 2
const DEFENSE_FORCE_COMMIT_MIN_UNITS := 1

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
		if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING):
			return

		var intercept_position: Vector3 = EnemyArmyCommand.resolve_defense_intercept_position(
			tree,
			threat,
			rally_position
		)
		var defense_army: Array = EnemyArmyCommand.build_defense_army(tree, intercept_position)
		if defense_army.is_empty():
			return

		var force_commit: bool = threat.get("force_commit", false)
		var min_group_size: int = (
			DEFENSE_FORCE_COMMIT_MIN_UNITS
			if force_commit
			else DEFENSE_MIN_GROUPED_UNITS
		)
		var grouped_army: Array = EnemyArmyCommand.filter_units_near_rally(
			defense_army,
			rally_position,
			EnemyArmyCommand.DEFENSE_GATHER_MAX_DISTANCE
		)

		if grouped_army.size() < min_group_size:
			EnemyArmyCommand.command_regroup_at_rally(tree, rally_position)
			return

		EnemyArmyCommand.command_attack_move(grouped_army, intercept_position)
		return

	if EnemyArmyCommand.get_army_mode() != EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	_threat_clear_timer += DEFENSE_TICK_INTERVAL_SECONDS
	if _threat_clear_timer < THREAT_CLEAR_SECONDS:
		return

	EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)
	_threat_clear_timer = 0.0
