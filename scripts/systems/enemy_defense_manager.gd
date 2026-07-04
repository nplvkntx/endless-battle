class_name EnemyDefenseManager
extends Node

## Intercepts player threats near the enemy base and holds DEFENDING army mode until clear.

const DEFENSE_TICK_INTERVAL_SECONDS := 1.5
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
		if not EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING):
			return

		var intercept_position: Vector3 = threat.get("intercept_position", rally_position)
		var defense_army: Array = EnemyArmyCommand.build_defense_army(tree, intercept_position)
		if defense_army.is_empty():
			return

		var commitment: Dictionary = EnemyArmyCommand.evaluate_defense_commitment(
			tree,
			defense_army,
			intercept_position
		)
		if commitment.get("can_commit", false):
			EnemyArmyCommand.command_attack_move(defense_army, intercept_position)
		else:
			var hold_position: Vector3 = EnemyArmyCommand.resolve_defense_hold_position(
				rally_position,
				intercept_position
			)
			EnemyArmyCommand.command_defend_position(defense_army, hold_position)
		return

	if EnemyArmyCommand.get_army_mode() != EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	_threat_clear_timer += DEFENSE_TICK_INTERVAL_SECONDS
	if _threat_clear_timer < THREAT_CLEAR_SECONDS:
		return

	EnemyArmyCommand.release_army_mode(EnemyArmyCommand.ArmyMode.DEFENDING)
	_threat_clear_timer = 0.0
