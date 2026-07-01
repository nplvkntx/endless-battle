class_name EnemyArmyCommand
extends RefCounted

## Shared enemy army command helpers. Registers combat units and issues group orders.

const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMIES_GROUP := &"enemies"


static func is_combat_unit(node: Node) -> bool:
	return node is Swordsman or node is Archer or node is Hero


static func is_living_combat_unit(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not is_combat_unit(node):
		return false

	if not node.is_in_group(ENEMY_COMBAT_GROUP):
		return false

	var health_component: HealthComponent = node.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


static func register_combat_unit(unit: Unit) -> void:
	if unit == null or not is_combat_unit(unit):
		return

	if not unit.is_in_group(ENEMIES_GROUP):
		unit.add_to_group(ENEMIES_GROUP)

	if not unit.is_in_group(ENEMY_COMBAT_GROUP):
		unit.add_to_group(ENEMY_COMBAT_GROUP)


static func collect_living_combat_units(tree: SceneTree) -> Array:
	var units: Array = []

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node):
			units.append(node)

	return units


static func command_attack_move(units: Array, destination: Vector3) -> void:
	for unit in units:
		_issue_attack_move(unit, destination)


static func command_defend_position(units: Array, position: Vector3) -> void:
	command_attack_move(units, position)


static func command_retreat_to(units: Array, position: Vector3) -> void:
	command_attack_move(units, position)


static func _issue_attack_move(unit: Variant, destination: Vector3) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if not (unit as Object).has_method("command_attack_move"):
		return

	(unit as Object).call("command_attack_move", destination)
