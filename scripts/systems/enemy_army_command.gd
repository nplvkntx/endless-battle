class_name EnemyArmyCommand
extends RefCounted

## Thin enemy army helpers — registration, queries, geometry.
## Does not decide missions, issue strategic orders, or run recovery.

const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMIES_GROUP := &"enemies"
const UNITS_GROUP := &"units"
const HEROES_GROUP := &"heroes"
const BUILDINGS_GROUP := &"buildings"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"

## Kept for MatchSession / legacy assertions — always idle after purge.
enum ArmyMode { IDLE, ASSEMBLING, MOVING, FIGHTING, RETREATING }
enum StrategicState { ECONOMY, CREEP, ATTACK, DEFEND, RETREAT }

static var _bound_ai_player_state: AIPlayerState = null
static var _bound_command_authority: Variant = null
static var _diag_order_source_stack: Array[String] = []
static var _diag_order_mission_generation_stack: Array[int] = []
static var _legacy_military_strategic_orders_issued: int = 0


static func bind_match_composition(state: AIPlayerState, authority: Variant) -> void:
	_bound_ai_player_state = state
	_bound_command_authority = authority
	if state != null and is_instance_valid(state):
		state.set_military_command_authority(authority)


static func unbind_match_composition() -> void:
	_bound_ai_player_state = null
	_bound_command_authority = null


static func get_bound_ai_player_state() -> AIPlayerState:
	var raw: Variant = _bound_ai_player_state
	if raw != null and is_instance_valid(raw) and raw is AIPlayerState:
		return raw as AIPlayerState
	_bound_ai_player_state = null
	return null


static func get_declared_command_authority() -> Node:
	var raw: Variant = _bound_command_authority
	if raw != null and is_instance_valid(raw) and raw is Node:
		return raw as Node
	_bound_command_authority = null
	return null


static func reset_match_state() -> void:
	_bound_ai_player_state = null
	_bound_command_authority = null
	_diag_order_source_stack.clear()
	_diag_order_mission_generation_stack.clear()
	_legacy_military_strategic_orders_issued = 0


static func get_legacy_military_strategic_orders_issued() -> int:
	return _legacy_military_strategic_orders_issued


static func get_army_mode() -> ArmyMode:
	return ArmyMode.IDLE


static func get_strategic_state() -> StrategicState:
	return StrategicState.ECONOMY


static func reset_legacy_military_strategic_order_counter() -> void:
	_legacy_military_strategic_orders_issued = 0


static func is_attack_wave_active() -> bool:
	return false


static func is_attack_wave_controlling_hero() -> bool:
	return false


## Legacy authorize gate — always refused after purge (no old military orders).
static func with_authorized_orders(_callback: Callable) -> void:
	pass


static func register_combat_unit(unit) -> void:
	if not NodeSafety.is_alive_node(unit):
		return
	if not is_combat_unit(unit):
		return
	if not unit.is_in_group(ENEMIES_GROUP):
		unit.add_to_group(ENEMIES_GROUP)
	if not unit.is_in_group(ENEMY_COMBAT_GROUP):
		unit.add_to_group(ENEMY_COMBAT_GROUP)


## Old strategic regroup removed — units spawn idle until SimpleWc3AI orders them.
static func assign_reinforcement_regroup(_tree: SceneTree, _unit) -> void:
	pass


static func release_reinforcement_from_pool(_unit) -> void:
	pass


static func is_combat_unit(node) -> bool:
	return EnemyArmyForceMath.is_combat_unit(node)


static func is_living_combat_unit(node) -> bool:
	return EnemyArmyForceMath.is_living_combat_unit(node)


static func is_hero_unit(node) -> bool:
	return NodeSafety.is_alive_node(node) and node is Hero


static func is_non_hero_combat_unit(node) -> bool:
	return is_combat_unit(node) and not is_hero_unit(node)


static func get_health_ratio(node) -> float:
	return EnemyArmyForceMath.get_health_ratio(node)


static func estimate_military_power(units: Array) -> int:
	return EnemyArmyForceMath.estimate_military_power(units)


static func estimate_combat_strength(units: Array) -> float:
	return EnemyArmyForceMath.estimate_combat_strength(units)


static func collect_living_combat_units(tree: SceneTree) -> Array:
	var units: Array = []
	if tree == null:
		return units
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node_variant):
			units.append(node_variant)
	return units


static func collect_living_non_hero_combat_units(tree: SceneTree) -> Array:
	var units: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if is_non_hero_combat_unit(unit):
			units.append(unit)
	return units


static func find_living_enemy_hero(tree: SceneTree) -> Hero:
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if not is_living_combat_unit(node_variant):
			continue
		if node_variant is Hero:
			return node_variant as Hero
	return null


static func find_living_player_command_center(tree: SceneTree) -> CommandCenter:
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if node is CommandCenter and NodeSafety.is_alive_node(node):
			var health: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
			if health != null and health.current_health <= 0:
				continue
			return node as CommandCenter
	return null


static func resolve_enemy_rally_position(tree: SceneTree) -> Vector3:
	if tree == null:
		return Vector3.ZERO
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter and NodeSafety.is_alive_node(node):
			var pos: Vector3 = (node as CommandCenter).global_position
			pos.y = 0.0
			return pos
	return Vector3.ZERO


static func horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var dx: float = from_position.x - to_position.x
	var dz: float = from_position.z - to_position.z
	return sqrt(dx * dx + dz * dz)


static func horizontal_distance_squared(from_position: Vector3, to_position: Vector3) -> float:
	var dx: float = from_position.x - to_position.x
	var dz: float = from_position.z - to_position.z
	return dx * dx + dz * dz


static func push_diag_order_source(source: String, mission_gen: int = 0) -> void:
	_diag_order_source_stack.append(source)
	_diag_order_mission_generation_stack.append(mission_gen)


static func pop_diag_order_source() -> void:
	if not _diag_order_source_stack.is_empty():
		_diag_order_source_stack.pop_back()
	if not _diag_order_mission_generation_stack.is_empty():
		_diag_order_mission_generation_stack.pop_back()


static func get_diag_order_source() -> String:
	if _diag_order_source_stack.is_empty():
		return ""
	return _diag_order_source_stack[_diag_order_source_stack.size() - 1]


static func get_diag_order_mission_generation() -> int:
	if _diag_order_mission_generation_stack.is_empty():
		return 0
	return _diag_order_mission_generation_stack[_diag_order_mission_generation_stack.size() - 1]
