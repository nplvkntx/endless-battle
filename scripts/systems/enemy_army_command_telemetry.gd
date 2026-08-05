class_name EnemyArmyCommandTelemetry
extends RefCounted

## Non-authoritative order-issue / perf / debug bookkeeping extracted from EnemyArmyCommand.
## One responsibility: telemetry for F3, console diagnostics, and verify harnesses.
## Never selects missions, never enqueues unit orders, never owns AIPlayerState bags.
## Not an autoload — call static methods; reset via EnemyArmyCommand.reset_match_state.

const PERF_DIAG_INTERVAL_SECONDS := 5.0
const PERF_OVERLAY_INTERVAL_SECONDS := 0.25

static var debug_enabled_override: bool = false
static var perf_diag_timer: float = 0.0
static var orders_issued_since_diag: int = 0
static var perf_overlay_status_timer: float = 0.0
static var last_issued_order_msec: int = 0
static var last_issued_order_label: String = ""
static var last_issued_order_destination: Vector3 = Vector3.ZERO


static func reset_match_state() -> void:
	## Clears cadence + last-issued bags. Debug override is session-scoped (not cleared).
	perf_diag_timer = 0.0
	orders_issued_since_diag = 0
	perf_overlay_status_timer = 0.0
	clear_issued_order()


static func seed_for_verify() -> void:
	debug_enabled_override = true
	perf_diag_timer = 9.0
	orders_issued_since_diag = 42
	perf_overlay_status_timer = 0.2
	last_issued_order_msec = Time.get_ticks_msec()
	last_issued_order_label = "verify-telemetry-order"
	last_issued_order_destination = Vector3(99.0, 0.0, 99.0)


static func snapshot_for_verify() -> Dictionary:
	return {
		"debug_enabled_override": debug_enabled_override,
		"perf_diag_timer": perf_diag_timer,
		"orders_issued_since_diag": orders_issued_since_diag,
		"perf_overlay_status_timer": perf_overlay_status_timer,
		"last_issued_order_msec": last_issued_order_msec,
		"last_issued_order_label": last_issued_order_label,
		"last_issued_order_destination": last_issued_order_destination,
	}


static func set_debug_override(enabled: bool) -> void:
	debug_enabled_override = enabled


static func is_debug_override_enabled() -> bool:
	return debug_enabled_override


static func record_order_issued() -> void:
	orders_issued_since_diag += 1


static func take_orders_issued_since_diag() -> int:
	var count: int = orders_issued_since_diag
	orders_issued_since_diag = 0
	return count


## Advance overlay cadence. Returns true when an overlay refresh is due.
static func tick_overlay_timer(delta: float) -> bool:
	perf_overlay_status_timer += delta
	if perf_overlay_status_timer < PERF_OVERLAY_INTERVAL_SECONDS:
		return false
	perf_overlay_status_timer = 0.0
	return true


## Advance AI PERF print cadence. Returns true when a diag print is due.
static func tick_perf_diag_timer(delta: float, combat_debug_const: bool) -> bool:
	if not combat_debug_const and not debug_enabled_override:
		return false
	perf_diag_timer += delta
	if perf_diag_timer < PERF_DIAG_INTERVAL_SECONDS:
		return false
	perf_diag_timer = 0.0
	return true


static func note_issued_order(
	order_label: String,
	destination: Vector3 = Vector3.ZERO,
	fallback_label: String = "",
	fallback_destination: Vector3 = Vector3.ZERO
) -> void:
	var now_msec: int = Time.get_ticks_msec()
	last_issued_order_msec = now_msec
	last_issued_order_label = order_label if not order_label.is_empty() else fallback_label
	if destination != Vector3.ZERO:
		last_issued_order_destination = destination
	elif fallback_destination != Vector3.ZERO:
		last_issued_order_destination = fallback_destination
	_log_issued_order(last_issued_order_label, last_issued_order_destination)


static func clear_issued_order() -> void:
	last_issued_order_msec = 0
	last_issued_order_label = ""
	last_issued_order_destination = Vector3.ZERO


static func get_seconds_since_last_order() -> float:
	if last_issued_order_msec <= 0:
		return INF
	return float(Time.get_ticks_msec() - last_issued_order_msec) / 1000.0


static func get_last_issued_order_label() -> String:
	return last_issued_order_label if not last_issued_order_label.is_empty() else "-"


static func get_last_issued_order_destination() -> Vector3:
	return last_issued_order_destination


static func _log_issued_order(order_label: String, destination: Vector3) -> void:
	var label: String = order_label if not order_label.is_empty() else "order"
	var dest_text: String = "-"
	if destination != Vector3.ZERO:
		dest_text = "(%.1f, %.1f)" % [destination.x, destination.z]
	EnemyAIDebug.log_once(
		"ai_order_%s_%s" % [label, dest_text],
		"[AI Order] %s -> %s" % [label, dest_text]
	)
