extends Node

## Temporary instrumentation for late-game performance profiling (F3 overlay).
## Tracks rates, AI order pressure, FPS samples, and section timing warnings.

const KEY_ENEMY_TARGET_SEARCHES := &"enemy_target_searches"
const KEY_GET_NODES_IN_GROUP := &"get_nodes_in_group_calls"
const KEY_PATH_RECALCULATIONS := &"path_recalculations"
const KEY_NAV_PATH_REQUESTS := &"nav_path_requests"
const KEY_AI_ECONOMY_UPDATES := &"ai_economy_updates"
const KEY_AI_COMBAT_UPDATES := &"ai_combat_updates"
const KEY_AI_DECISION_UPDATES := &"ai_decision_updates"
const KEY_AI_ORDERS := &"ai_orders"
const KEY_REPATH_REQUESTS := &"repath_requests"
const KEY_TARGET_SEARCHES := &"target_searches"

const FPS_SAMPLE_WINDOW_SECONDS := 3.0
const WARN_FPS_THRESHOLD := 30.0
const WARN_FRAME_TIME_MS := 33.0
const WARN_ORDERS_PER_SEC := 40.0
const WARN_REPATHS_PER_SEC := 60.0
const WARN_TARGET_SEARCHES_PER_SEC := 80.0
const SECTION_WARN_USEC := 12000
const ORDER_BUDGET_WARN_COOLDOWN_SECONDS := 2.0
const EXCESSIVE_RATE_WARN_COOLDOWN_SECONDS := 3.0

static var _window_elapsed: float = 0.0
static var _counts: Dictionary = {}
static var _rates: Dictionary = {}
static var _active_projectiles: int = 0
static var _orders_this_frame: int = 0
static var _orders_frame_id: int = -1
static var _pending_group_orders: int = 0
static var _combat_group_size: int = 0
static var _ai_phase_name: String = "-"
static var _ai_combat_state: String = "-"
static var _ai_mission_owner: String = "-"
static var _fps_samples: PackedFloat32Array = PackedFloat32Array()
static var _fps_sample_times: PackedFloat32Array = PackedFloat32Array()
static var _fps_sample_elapsed: float = 0.0
static var _last_fps: float = 0.0
static var _avg_fps: float = 0.0
static var _recent_low_fps: float = 0.0
static var _last_order_budget_warn_msec: int = 0
static var _last_excessive_warn_msec: Dictionary = {}
static var verbose_ai_logging: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(delta: float) -> void:
	advance_rate_window(delta)


static func bump(key: StringName) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1


static func bump_by(key: StringName, amount: int) -> void:
	if amount <= 0:
		return
	_counts[key] = int(_counts.get(key, 0)) + amount


static func record_enemy_target_search() -> void:
	bump(KEY_ENEMY_TARGET_SEARCHES)
	bump(KEY_TARGET_SEARCHES)


static func record_target_search() -> void:
	bump(KEY_TARGET_SEARCHES)


static func record_get_nodes_in_group_call() -> void:
	bump(KEY_GET_NODES_IN_GROUP)


static func record_navigation_path_request() -> void:
	bump(KEY_PATH_RECALCULATIONS)
	bump(KEY_NAV_PATH_REQUESTS)
	bump(KEY_REPATH_REQUESTS)


static func record_repath_request() -> void:
	bump(KEY_REPATH_REQUESTS)
	bump(KEY_PATH_RECALCULATIONS)


static func record_ai_economy_update() -> void:
	bump(KEY_AI_ECONOMY_UPDATES)


static func record_ai_combat_update() -> void:
	bump(KEY_AI_COMBAT_UPDATES)


static func record_ai_decision_update() -> void:
	bump(KEY_AI_DECISION_UPDATES)


static func record_ai_order(count: int = 1) -> void:
	if count <= 0:
		return

	var frame: int = Engine.get_process_frames()
	if frame != _orders_frame_id:
		_orders_frame_id = frame
		_orders_this_frame = 0

	_orders_this_frame += count
	bump_by(KEY_AI_ORDERS, count)


static func register_projectile() -> void:
	_active_projectiles += 1


static func unregister_projectile() -> void:
	_active_projectiles = maxi(0, _active_projectiles - 1)


static func get_active_projectile_count() -> int:
	return _active_projectiles


static func set_pending_group_orders(count: int) -> void:
	_pending_group_orders = maxi(0, count)


static func get_pending_group_orders() -> int:
	return _pending_group_orders


static func get_orders_this_frame() -> int:
	if Engine.get_process_frames() != _orders_frame_id:
		return 0
	return _orders_this_frame


static func set_combat_group_size(count: int) -> void:
	_combat_group_size = maxi(0, count)


static func get_combat_group_size() -> int:
	return _combat_group_size


static func set_ai_status(phase: String, combat_state: String, mission_owner: String) -> void:
	_ai_phase_name = phase if not phase.is_empty() else "-"
	_ai_combat_state = combat_state if not combat_state.is_empty() else "-"
	_ai_mission_owner = mission_owner if not mission_owner.is_empty() else "-"


static func get_ai_phase() -> String:
	return _ai_phase_name


static func get_ai_combat_state() -> String:
	return _ai_combat_state


static func get_ai_mission_owner() -> String:
	return _ai_mission_owner


static func sample_fps(delta: float) -> void:
	var fps: float = float(Engine.get_frames_per_second())
	_last_fps = fps
	_fps_sample_elapsed += delta
	_fps_samples.append(fps)
	_fps_sample_times.append(_fps_sample_elapsed)

	while not _fps_sample_times.is_empty():
		if _fps_sample_elapsed - _fps_sample_times[0] <= FPS_SAMPLE_WINDOW_SECONDS:
			break
		_fps_samples.remove_at(0)
		_fps_sample_times.remove_at(0)

	if _fps_samples.is_empty():
		_avg_fps = fps
		_recent_low_fps = fps
		return

	var total: float = 0.0
	var lowest: float = INF
	for sample: float in _fps_samples:
		total += sample
		lowest = minf(lowest, sample)

	_avg_fps = total / float(_fps_samples.size())
	_recent_low_fps = lowest if lowest < INF else fps


static func get_fps() -> float:
	return _last_fps


static func get_average_fps() -> float:
	return _avg_fps


static func get_recent_low_fps() -> float:
	return _recent_low_fps


static func get_frame_time_ms() -> float:
	return 1000.0 / maxf(_last_fps, 1.0)


static func advance_rate_window(delta: float) -> void:
	sample_fps(delta)
	_window_elapsed += delta
	if _window_elapsed < 1.0:
		return

	var elapsed: float = _window_elapsed
	for key: StringName in _counts.keys():
		_rates[key] = float(_counts[key]) / elapsed

	_maybe_warn_excessive_rates()
	_counts.clear()
	_window_elapsed = 0.0


static func get_rate(key: StringName) -> float:
	return float(_rates.get(key, 0.0))


static func begin_section() -> int:
	return Time.get_ticks_usec()


static func end_section(section_name: String, start_usec: int, scanned_units: int = -1) -> float:
	var elapsed_usec: int = Time.get_ticks_usec() - start_usec
	var elapsed_ms: float = float(elapsed_usec) / 1000.0
	if elapsed_usec < SECTION_WARN_USEC:
		return elapsed_ms

	print("[AI PERF WARNING] %s took %.1f ms" % [section_name, elapsed_ms])
	if scanned_units >= 0:
		print("[AI PERF WARNING] %s scanned %d units" % [section_name, scanned_units])
	return elapsed_ms


static func warn_order_budget_reached(budget: int) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_order_budget_warn_msec < int(ORDER_BUDGET_WARN_COOLDOWN_SECONDS * 1000.0):
		return

	_last_order_budget_warn_msec = now_msec
	print("[AI PERF WARNING] Order budget reached: %d" % budget)


static func _maybe_warn_excessive_rates() -> void:
	_warn_rate_once(KEY_AI_ORDERS, WARN_ORDERS_PER_SEC, "Excessive orders")
	_warn_rate_once(KEY_REPATH_REQUESTS, WARN_REPATHS_PER_SEC, "Excessive repaths")
	_warn_rate_once(KEY_TARGET_SEARCHES, WARN_TARGET_SEARCHES_PER_SEC, "Excessive target searches")


static func _warn_rate_once(key: StringName, threshold: float, label: String) -> void:
	var rate: float = get_rate(key)
	if rate < threshold:
		return

	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_excessive_warn_msec.get(key, 0))
	if now_msec - last_msec < int(EXCESSIVE_RATE_WARN_COOLDOWN_SECONDS * 1000.0):
		return

	_last_excessive_warn_msec[key] = now_msec
	print("[AI PERF WARNING] %s: %.0f/sec" % [label, rate])


static func collect_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if get_fps() > 0.0 and get_fps() < WARN_FPS_THRESHOLD:
		warnings.append("FPS below 30")
	if get_frame_time_ms() > WARN_FRAME_TIME_MS:
		warnings.append("Frame time > 33 ms")
	if get_rate(KEY_AI_ORDERS) >= WARN_ORDERS_PER_SEC:
		warnings.append("Orders/sec abnormally high")
	if get_rate(KEY_REPATH_REQUESTS) >= WARN_REPATHS_PER_SEC:
		warnings.append("Repaths/sec abnormally high")
	if get_rate(KEY_TARGET_SEARCHES) >= WARN_TARGET_SEARCHES_PER_SEC:
		warnings.append("Target searches/sec abnormally high")
	return warnings


static func reset_all() -> void:
	_window_elapsed = 0.0
	_counts.clear()
	_rates.clear()
	_active_projectiles = 0
	_orders_this_frame = 0
	_orders_frame_id = -1
	_pending_group_orders = 0
	_combat_group_size = 0
	_ai_phase_name = "-"
	_ai_combat_state = "-"
	_ai_mission_owner = "-"
	_fps_samples.clear()
	_fps_sample_times.clear()
	_fps_sample_elapsed = 0.0
	_last_fps = 0.0
	_avg_fps = 0.0
	_recent_low_fps = 0.0
	_last_order_budget_warn_msec = 0
	_last_excessive_warn_msec.clear()
