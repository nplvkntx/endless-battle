extends Node

## Temporary instrumentation for late-game performance profiling (F3 overlay).
## Tracks rates, AI order pressure, FPS samples, and section timing warnings.
## Autoload singleton: call APIs on PerfCounters (instance methods).

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
const KEY_SQUAD_STRATEGIC_ROUTES := &"squad_strategic_routes"
const KEY_SQUAD_LOCAL_REPATHS := &"squad_local_repaths"
const KEY_SQUAD_ROUTE_CACHE_HITS := &"squad_route_cache_hits"
const KEY_SQUAD_STALLS := &"squad_stalls"

const FPS_SAMPLE_WINDOW_SECONDS := 3.0
const WARN_FPS_THRESHOLD := 30.0
const WARN_FRAME_TIME_MS := 33.0
const WARN_ORDERS_PER_SEC := 40.0
const WARN_REPATHS_PER_SEC := 60.0
const WARN_TARGET_SEARCHES_PER_SEC := 80.0
const SECTION_WARN_USEC := 12000
const ORDER_BUDGET_WARN_COOLDOWN_SECONDS := 4.0
const EXCESSIVE_RATE_WARN_COOLDOWN_SECONDS := 5.0
const DUPLICATE_GROUP_ORDER_WARN_COOLDOWN_SECONDS := 12.0
const SECTION_WARN_COOLDOWN_SECONDS := 4.0

var _window_elapsed: float = 0.0
var _counts: Dictionary = {}
var _rates: Dictionary = {}
var _active_projectiles: int = 0
var _orders_this_frame: int = 0
var _orders_frame_id: int = -1
var _pending_group_orders: int = 0
var _combat_group_size: int = 0
var _ai_phase_name: String = "-"
var _ai_combat_state: String = "-"
var _ai_mission_owner: String = "-"
var _ai_mission_detail: String = "-"
var _military_ai_version: String = "Legacy"
var _military_ai_v2_state: String = "-"
var _military_ai_v2_mission: String = "-"
var _military_ai_v2_objective: String = "-"
var _military_ai_v2_mission_age: float = 0.0
var _military_ai_v2_transition_reason: String = "-"
var _military_ai_v2_squad_size: int = 0
var _military_ai_v2_hero_present: bool = false
var _military_ai_v2_role_counts: String = "-"
var _military_ai_v2_army_strength: float = 0.0
var _military_ai_v2_active_order: String = "-"
var _military_ai_v2_distance: float = -1.0
var _military_ai_v2_seconds_since_progress: float = 0.0
var _military_ai_v2_state_age: float = 0.0
var _military_ai_v2_watchdog_status: String = "-"
var _military_ai_v2_destination: String = "-"
var _military_ai_v2_last_order_time: String = "-"
var _military_ai_v2_last_mission_change: String = "-"
var _military_ai_v2_idle_time: float = 0.0
var _military_ai_v2_macro: String = "-"
var _military_ai_v2_blocked: String = "-"
var _military_ai_v2_hero_label: String = "-"
var _military_ai_v2_army_label: String = "-"
var _military_ai_v2_camps_label: String = "-"
var _military_ai_v2_target_label: String = "-"
var _military_ai_v2_defense_label: String = "-"
var _military_ai_v2_threat_label: String = "-"
var _military_ai_v2_executable_label: String = "-"
var _military_ai_v2_target_dist: float = -1.0
var _military_ai_v2_workers_label: String = "-"
var _military_ai_v2_tier_label: String = "-"
var _military_ai_v2_expansion_label: String = "-"
var _fps_samples: PackedFloat32Array = PackedFloat32Array()
var _fps_sample_times: PackedFloat32Array = PackedFloat32Array()
var _fps_sample_elapsed: float = 0.0
var _last_fps: float = 0.0
var _avg_fps: float = 0.0
var _recent_low_fps: float = 0.0
var _last_order_budget_warn_msec: int = 0
var _last_duplicate_group_order_warn_msec: int = 0
var _last_excessive_warn_msec: Dictionary = {}
var _peak_rates: Dictionary = {}
var _last_section_warn_msec: Dictionary = {}
var verbose_ai_logging: bool = false
var _squad_nav_enabled: bool = false
var _squad_nav_active_squads: int = 0
var _squad_nav_member_count: int = 0
var _squad_nav_stalls: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_military_ai_version = MilitaryAIConfig.ai_version_label()
	MatchSession.register_match_reset(&"PerfCounters", reset_all)


func _process(delta: float) -> void:
	advance_rate_window(delta)


func bump(key: StringName) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1


func bump_by(key: StringName, amount: int) -> void:
	if amount <= 0:
		return
	_counts[key] = int(_counts.get(key, 0)) + amount


func record_enemy_target_search() -> void:
	bump(KEY_ENEMY_TARGET_SEARCHES)
	bump(KEY_TARGET_SEARCHES)


func record_target_search() -> void:
	bump(KEY_TARGET_SEARCHES)


func record_get_nodes_in_group_call() -> void:
	bump(KEY_GET_NODES_IN_GROUP)


func record_navigation_path_request() -> void:
	## Single instrumentation point for NavigationAgent target writes.
	bump(KEY_PATH_RECALCULATIONS)
	bump(KEY_NAV_PATH_REQUESTS)
	bump(KEY_REPATH_REQUESTS)


func record_repath_request() -> void:
	## Alias kept for call sites that decide a repath without going through UnitNavigation.
	record_navigation_path_request()


func record_squad_strategic_route() -> void:
	bump(KEY_SQUAD_STRATEGIC_ROUTES)


func record_squad_local_repath() -> void:
	bump(KEY_SQUAD_LOCAL_REPATHS)
	bump(KEY_REPATH_REQUESTS)


func record_squad_route_cache_hit() -> void:
	bump(KEY_SQUAD_ROUTE_CACHE_HITS)


func record_squad_stall() -> void:
	bump(KEY_SQUAD_STALLS)


func set_squad_nav_status(
	enabled: bool,
	active_squads: int,
	member_count: int,
	stall_count: int
) -> void:
	_squad_nav_enabled = enabled
	_squad_nav_active_squads = maxi(0, active_squads)
	_squad_nav_member_count = maxi(0, member_count)
	_squad_nav_stalls = maxi(0, stall_count)


func is_squad_nav_enabled() -> bool:
	return _squad_nav_enabled


func get_squad_nav_active_squads() -> int:
	return _squad_nav_active_squads


func get_squad_nav_member_count() -> int:
	return _squad_nav_member_count


func get_squad_nav_stalls() -> int:
	return _squad_nav_stalls


func record_ai_economy_update() -> void:
	bump(KEY_AI_ECONOMY_UPDATES)


func record_ai_combat_update() -> void:
	bump(KEY_AI_COMBAT_UPDATES)


func record_ai_decision_update() -> void:
	bump(KEY_AI_DECISION_UPDATES)


func record_ai_order(count: int = 1) -> void:
	if count <= 0:
		return

	var frame: int = Engine.get_process_frames()
	if frame != _orders_frame_id:
		_orders_frame_id = frame
		_orders_this_frame = 0

	_orders_this_frame += count
	bump_by(KEY_AI_ORDERS, count)


func register_projectile() -> void:
	_active_projectiles += 1


func unregister_projectile() -> void:
	_active_projectiles = maxi(0, _active_projectiles - 1)


func get_active_projectile_count() -> int:
	return _active_projectiles


func set_pending_group_orders(count: int) -> void:
	_pending_group_orders = maxi(0, count)


func get_pending_group_orders() -> int:
	return _pending_group_orders


func get_orders_this_frame() -> int:
	if Engine.get_process_frames() != _orders_frame_id:
		return 0
	return _orders_this_frame


func set_combat_group_size(count: int) -> void:
	_combat_group_size = maxi(0, count)


func get_combat_group_size() -> int:
	return _combat_group_size


func set_ai_status(phase: String, combat_state: String, mission_owner: String) -> void:
	_ai_phase_name = phase if not phase.is_empty() else "-"
	_ai_combat_state = combat_state if not combat_state.is_empty() else "-"
	_ai_mission_owner = mission_owner if not mission_owner.is_empty() else "-"


func set_ai_mission_detail(detail: String) -> void:
	_ai_mission_detail = detail if not detail.is_empty() else "-"


func get_ai_phase() -> String:
	return _ai_phase_name


func get_ai_combat_state() -> String:
	return _ai_combat_state


func get_ai_mission_owner() -> String:
	return _ai_mission_owner


func get_ai_mission_detail() -> String:
	return _ai_mission_detail


func set_military_ai_v2_status(
	ai_version: String,
	v2_state: String,
	mission: String,
	objective: String,
	mission_age_seconds: float,
	transition_reason: String
) -> void:
	_military_ai_version = ai_version if not ai_version.is_empty() else "-"
	_military_ai_v2_state = v2_state if not v2_state.is_empty() else "-"
	_military_ai_v2_mission = mission if not mission.is_empty() else "-"
	_military_ai_v2_objective = objective if not objective.is_empty() else "-"
	_military_ai_v2_mission_age = maxf(0.0, mission_age_seconds)
	_military_ai_v2_transition_reason = (
		transition_reason if not transition_reason.is_empty() else "-"
	)


func get_military_ai_version() -> String:
	return _military_ai_version


func get_military_ai_v2_state() -> String:
	return _military_ai_v2_state


func get_military_ai_v2_mission() -> String:
	return _military_ai_v2_mission


func get_military_ai_v2_objective() -> String:
	return _military_ai_v2_objective


func get_military_ai_v2_mission_age() -> float:
	return _military_ai_v2_mission_age


func get_military_ai_v2_transition_reason() -> String:
	return _military_ai_v2_transition_reason


func set_military_ai_v2_squad_status(
	squad_size: int,
	hero_present: bool,
	role_counts: String,
	estimated_army_strength: float
) -> void:
	_military_ai_v2_squad_size = maxi(0, squad_size)
	_military_ai_v2_hero_present = hero_present
	_military_ai_v2_role_counts = role_counts if not role_counts.is_empty() else "-"
	_military_ai_v2_army_strength = maxf(0.0, estimated_army_strength)


func get_military_ai_v2_squad_size() -> int:
	return _military_ai_v2_squad_size


func get_military_ai_v2_hero_present() -> bool:
	return _military_ai_v2_hero_present


func get_military_ai_v2_role_counts() -> String:
	return _military_ai_v2_role_counts


func get_military_ai_v2_army_strength() -> float:
	return _military_ai_v2_army_strength


func set_military_ai_v2_watchdog_status(
	active_order: String,
	distance_to_objective: float,
	seconds_since_progress: float,
	state_age_seconds: float,
	watchdog_status: String
) -> void:
	_military_ai_v2_active_order = active_order if not active_order.is_empty() else "-"
	_military_ai_v2_distance = distance_to_objective
	_military_ai_v2_seconds_since_progress = maxf(0.0, seconds_since_progress)
	_military_ai_v2_state_age = maxf(0.0, state_age_seconds)
	_military_ai_v2_watchdog_status = (
		watchdog_status if not watchdog_status.is_empty() else "-"
	)


func get_military_ai_v2_active_order() -> String:
	return _military_ai_v2_active_order


func get_military_ai_v2_distance() -> float:
	return _military_ai_v2_distance


func get_military_ai_v2_seconds_since_progress() -> float:
	return _military_ai_v2_seconds_since_progress


func get_military_ai_v2_state_age() -> float:
	return _military_ai_v2_state_age


func get_military_ai_v2_watchdog_status() -> String:
	return _military_ai_v2_watchdog_status


func set_military_ai_v2_execution_status(
	destination: String,
	last_order_time: String,
	last_mission_change: String,
	idle_time_seconds: float
) -> void:
	_military_ai_v2_destination = destination if not destination.is_empty() else "-"
	_military_ai_v2_last_order_time = (
		last_order_time if not last_order_time.is_empty() else "-"
	)
	_military_ai_v2_last_mission_change = (
		last_mission_change if not last_mission_change.is_empty() else "-"
	)
	_military_ai_v2_idle_time = maxf(0.0, idle_time_seconds)


func get_military_ai_v2_destination() -> String:
	return _military_ai_v2_destination


func get_military_ai_v2_last_order_time() -> String:
	return _military_ai_v2_last_order_time


func get_military_ai_v2_last_mission_change() -> String:
	return _military_ai_v2_last_mission_change


func get_military_ai_v2_idle_time() -> float:
	return _military_ai_v2_idle_time


func set_military_ai_v2_compact_status(
	macro_phase: String,
	military_state: String,
	mission: String,
	executable: String,
	blocked: String,
	hero_label: String,
	army_label: String,
	camps_label: String,
	target_label: String,
	defense_label: String,
	threat_label: String,
	target_dist: float = -1.0
) -> void:
	_military_ai_v2_macro = macro_phase if not macro_phase.is_empty() else "-"
	_military_ai_v2_state = military_state if not military_state.is_empty() else "-"
	_military_ai_v2_mission = mission if not mission.is_empty() else "-"
	_military_ai_v2_executable_label = executable if not executable.is_empty() else "-"
	_military_ai_v2_blocked = blocked if not blocked.is_empty() else "-"
	_military_ai_v2_hero_label = hero_label if not hero_label.is_empty() else "-"
	_military_ai_v2_army_label = army_label if not army_label.is_empty() else "-"
	_military_ai_v2_camps_label = camps_label if not camps_label.is_empty() else "-"
	_military_ai_v2_target_label = target_label if not target_label.is_empty() else "-"
	_military_ai_v2_defense_label = defense_label if not defense_label.is_empty() else "-"
	_military_ai_v2_threat_label = threat_label if not threat_label.is_empty() else "-"
	_military_ai_v2_target_dist = target_dist


func get_military_ai_v2_macro() -> String:
	return _military_ai_v2_macro


func get_military_ai_v2_blocked() -> String:
	return _military_ai_v2_blocked


func get_military_ai_v2_hero_label() -> String:
	return _military_ai_v2_hero_label


func get_military_ai_v2_army_label() -> String:
	return _military_ai_v2_army_label


func get_military_ai_v2_camps_label() -> String:
	return _military_ai_v2_camps_label


func get_military_ai_v2_target_label() -> String:
	return _military_ai_v2_target_label


func get_military_ai_v2_target_dist_label() -> String:
	if _military_ai_v2_target_dist < 0.0:
		return "-"
	return "%.0f" % _military_ai_v2_target_dist


func get_military_ai_v2_defense_label() -> String:
	return _military_ai_v2_defense_label


func get_military_ai_v2_threat_label() -> String:
	return _military_ai_v2_threat_label


func get_military_ai_v2_executable_label() -> String:
	return _military_ai_v2_executable_label


func set_military_ai_v2_macro_economy_status(
	workers_label: String,
	tier_label: String,
	expansion_label: String
) -> void:
	_military_ai_v2_workers_label = workers_label if not workers_label.is_empty() else "-"
	_military_ai_v2_tier_label = tier_label if not tier_label.is_empty() else "-"
	_military_ai_v2_expansion_label = expansion_label if not expansion_label.is_empty() else "-"


func get_military_ai_v2_workers_label() -> String:
	return _military_ai_v2_workers_label


func get_military_ai_v2_tier_label() -> String:
	return _military_ai_v2_tier_label


func get_military_ai_v2_expansion_label() -> String:
	return _military_ai_v2_expansion_label


func sample_fps(delta: float) -> void:
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


func get_fps() -> float:
	return _last_fps


func get_average_fps() -> float:
	return _avg_fps


func get_recent_low_fps() -> float:
	return _recent_low_fps


func get_frame_time_ms() -> float:
	return 1000.0 / maxf(_last_fps, 1.0)


func advance_rate_window(delta: float) -> void:
	sample_fps(delta)
	_window_elapsed += delta
	if _window_elapsed < 1.0:
		return

	var elapsed: float = _window_elapsed
	for key: StringName in _counts.keys():
		var rate: float = float(_counts[key]) / elapsed
		_rates[key] = rate
		_peak_rates[key] = maxf(float(_peak_rates.get(key, 0.0)), rate)

	_maybe_warn_excessive_rates()
	_counts.clear()
	_window_elapsed = 0.0


func get_rate(key: StringName) -> float:
	return float(_rates.get(key, 0.0))


func get_peak_rate(key: StringName) -> float:
	return float(_peak_rates.get(key, 0.0))


func begin_section() -> int:
	return Time.get_ticks_usec()


func end_section(section_name: String, start_usec: int, scanned_units: int = -1) -> float:
	var elapsed_usec: int = Time.get_ticks_usec() - start_usec
	var elapsed_ms: float = float(elapsed_usec) / 1000.0
	if elapsed_usec < SECTION_WARN_USEC:
		return elapsed_ms

	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_section_warn_msec.get(section_name, 0))
	if now_msec - last_msec < int(SECTION_WARN_COOLDOWN_SECONDS * 1000.0):
		return elapsed_ms
	_last_section_warn_msec[section_name] = now_msec

	print("[AI PERF] %s took %.1f ms" % [section_name, elapsed_ms])
	if scanned_units >= 0:
		print("[AI PERF] %s scanned %d units" % [section_name, scanned_units])
	return elapsed_ms


func warn_order_budget_reached(budget: int) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_order_budget_warn_msec < int(ORDER_BUDGET_WARN_COOLDOWN_SECONDS * 1000.0):
		return

	_last_order_budget_warn_msec = now_msec
	print(
		"[AI PERF] Order budget reached: %d | pending=%d | orders/sec=%.0f peak=%.0f"
		% [
			budget,
			_pending_group_orders,
			get_rate(KEY_AI_ORDERS),
			get_peak_rate(KEY_AI_ORDERS),
		]
	)


func warn_duplicate_group_order() -> void:
	## Throttled: duplicate skips are expected after the fix; only log occasionally.
	if not verbose_ai_logging:
		var now_msec: int = Time.get_ticks_msec()
		if (
			now_msec - _last_duplicate_group_order_warn_msec
			< int(DUPLICATE_GROUP_ORDER_WARN_COOLDOWN_SECONDS * 1000.0)
		):
			return
		_last_duplicate_group_order_warn_msec = now_msec
	_warn_rate_once(&"duplicate_group_order", 0.0, "Group order skipped: duplicate destination")


func _maybe_warn_excessive_rates() -> void:
	if get_fps() > 0.0 and get_fps() < WARN_FPS_THRESHOLD:
		_warn_rate_once(
			&"low_fps",
			0.0,
			"FPS below 30: %.0f (recent low %.0f)" % [get_fps(), get_recent_low_fps()]
		)
	_warn_rate_once(KEY_AI_ORDERS, WARN_ORDERS_PER_SEC, "Excessive orders")
	_warn_rate_once(KEY_REPATH_REQUESTS, WARN_REPATHS_PER_SEC, "Excessive repaths")
	_warn_rate_once(KEY_TARGET_SEARCHES, WARN_TARGET_SEARCHES_PER_SEC, "Excessive target searches")


func _warn_rate_once(key: StringName, threshold: float, label: String) -> void:
	var rate: float = get_rate(key)
	if threshold > 0.0 and rate < threshold:
		return

	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_excessive_warn_msec.get(key, 0))
	if now_msec - last_msec < int(EXCESSIVE_RATE_WARN_COOLDOWN_SECONDS * 1000.0):
		return

	_last_excessive_warn_msec[key] = now_msec
	if threshold <= 0.0:
		print("[AI PERF] %s" % label)
	else:
		print(
			"[AI PERF] %s: %.0f/sec (peak %.0f/sec)"
			% [label, rate, get_peak_rate(key)]
		)


func collect_warnings() -> PackedStringArray:
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


func reset_all() -> void:
	_window_elapsed = 0.0
	_counts.clear()
	_rates.clear()
	_peak_rates.clear()
	_last_section_warn_msec.clear()
	_active_projectiles = 0
	_orders_this_frame = 0
	_orders_frame_id = -1
	_pending_group_orders = 0
	_combat_group_size = 0
	_ai_phase_name = "-"
	_ai_combat_state = "-"
	_ai_mission_owner = "-"
	_ai_mission_detail = "-"
	_military_ai_version = MilitaryAIConfig.ai_version_label()
	_military_ai_v2_state = "-"
	_military_ai_v2_mission = "-"
	_military_ai_v2_objective = "-"
	_military_ai_v2_mission_age = 0.0
	_military_ai_v2_transition_reason = "-"
	_military_ai_v2_squad_size = 0
	_military_ai_v2_hero_present = false
	_military_ai_v2_role_counts = "-"
	_military_ai_v2_army_strength = 0.0
	_military_ai_v2_active_order = "-"
	_military_ai_v2_distance = -1.0
	_military_ai_v2_seconds_since_progress = 0.0
	_military_ai_v2_state_age = 0.0
	_military_ai_v2_watchdog_status = "-"
	_military_ai_v2_destination = "-"
	_military_ai_v2_last_order_time = "-"
	_military_ai_v2_last_mission_change = "-"
	_military_ai_v2_idle_time = 0.0
	_military_ai_v2_macro = "-"
	_military_ai_v2_blocked = "-"
	_military_ai_v2_hero_label = "-"
	_military_ai_v2_army_label = "-"
	_military_ai_v2_camps_label = "-"
	_military_ai_v2_target_label = "-"
	_military_ai_v2_defense_label = "-"
	_military_ai_v2_threat_label = "-"
	_military_ai_v2_executable_label = "-"
	_squad_nav_enabled = MilitaryAIConfig.is_shared_squad_nav_enabled()
	_squad_nav_active_squads = 0
	_squad_nav_member_count = 0
	_squad_nav_stalls = 0
	_fps_samples.clear()
	_fps_sample_times.clear()
	_fps_sample_elapsed = 0.0
	_last_fps = 0.0
	_avg_fps = 0.0
	_recent_low_fps = 0.0
	_last_order_budget_warn_msec = 0
	_last_excessive_warn_msec.clear()
