extends Node

## Temporary instrumentation counters for performance profiling.
## Remove this autoload and scripts/debug/ once bottlenecks are identified.

const KEY_ENEMY_TARGET_SEARCHES := &"enemy_target_searches"
const KEY_GET_NODES_IN_GROUP := &"get_nodes_in_group_calls"
const KEY_PATH_RECALCULATIONS := &"path_recalculations"
const KEY_NAV_PATH_REQUESTS := &"nav_path_requests"
const KEY_AI_ECONOMY_UPDATES := &"ai_economy_updates"
const KEY_AI_COMBAT_UPDATES := &"ai_combat_updates"
const KEY_AI_DECISION_UPDATES := &"ai_decision_updates"

static var _window_elapsed: float = 0.0
static var _counts: Dictionary = {}
static var _rates: Dictionary = {}
static var _active_projectiles: int = 0


static func bump(key: StringName) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1


static func record_enemy_target_search() -> void:
	bump(KEY_ENEMY_TARGET_SEARCHES)


static func record_get_nodes_in_group_call() -> void:
	bump(KEY_GET_NODES_IN_GROUP)


static func record_navigation_path_request() -> void:
	bump(KEY_PATH_RECALCULATIONS)
	bump(KEY_NAV_PATH_REQUESTS)


static func record_ai_economy_update() -> void:
	bump(KEY_AI_ECONOMY_UPDATES)


static func record_ai_combat_update() -> void:
	bump(KEY_AI_COMBAT_UPDATES)


static func record_ai_decision_update() -> void:
	bump(KEY_AI_DECISION_UPDATES)


static func register_projectile() -> void:
	_active_projectiles += 1


static func unregister_projectile() -> void:
	_active_projectiles = maxi(0, _active_projectiles - 1)


static func get_active_projectile_count() -> int:
	return _active_projectiles


static func advance_rate_window(delta: float) -> void:
	_window_elapsed += delta
	if _window_elapsed < 1.0:
		return

	var elapsed: float = _window_elapsed
	for key: StringName in _counts.keys():
		_rates[key] = float(_counts[key]) / elapsed

	_counts.clear()
	_window_elapsed = 0.0


static func get_rate(key: StringName) -> float:
	return float(_rates.get(key, 0.0))


static func reset_all() -> void:
	_window_elapsed = 0.0
	_counts.clear()
	_rates.clear()
	_active_projectiles = 0
