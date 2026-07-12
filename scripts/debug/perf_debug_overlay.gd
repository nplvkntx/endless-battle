extends CanvasLayer

## Toggle with F3. Updates a few times per second, not every frame.
## Remove this autoload and scripts/debug/ once profiling is complete.

const TOGGLE_KEY := KEY_F3
const REFRESH_INTERVAL_SECONDS := 0.25

var _panel: PanelContainer
var _label: Label
var _refresh_timer: float = 0.0
var _visible_overlay: bool = false
var _last_frame_time_ms: float = 0.0


func _ready() -> void:
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_build_ui()
	set_process(false)
	hide_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return

	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode != TOGGLE_KEY:
		return

	if _visible_overlay:
		hide_overlay()
	else:
		show_overlay()


func _process(delta: float) -> void:
	_last_frame_time_ms = delta * 1000.0
	PerfCounters.advance_rate_window(delta)

	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL_SECONDS:
		return

	_refresh_timer = 0.0
	_update_label()


func show_overlay() -> void:
	_visible_overlay = true
	_panel.visible = true
	_refresh_timer = REFRESH_INTERVAL_SECONDS
	set_process(true)
	_update_label()


func hide_overlay() -> void:
	_visible_overlay = false
	_panel.visible = false
	set_process(false)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.08, 0.88)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.25, 0.55, 0.35, 1)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85, 1))
	_panel.add_child(_label)

	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 12.0
	_panel.offset_top = 12.0


func _update_label() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		_label.text = "Performance overlay (no scene tree)"
		return

	var unit_stats: Dictionary = _collect_unit_stats(tree)
	var lines: PackedStringArray = PackedStringArray([
		"Performance Debug (F3)",
		"FPS: %d" % Engine.get_frames_per_second(),
		"Frame time: %.1f ms" % _last_frame_time_ms,
		"",
		"Total units: %d" % int(unit_stats.get("total_units", 0)),
		"Player units: %d" % int(unit_stats.get("player_units", 0)),
		"AI units: %d" % int(unit_stats.get("ai_units", 0)),
		"Workers: %d" % int(unit_stats.get("workers", 0)),
		"Military units: %d" % int(unit_stats.get("military", 0)),
		"Projectiles: %d" % PerfCounters.get_active_projectile_count(),
		"Nav path requests/s: %.1f" % PerfCounters.get_rate(PerfCounters.KEY_NAV_PATH_REQUESTS),
		"AI decision updates/s: %.1f"
		% PerfCounters.get_rate(PerfCounters.KEY_AI_DECISION_UPDATES),
		"",
		"--- counters / sec ---",
		"Enemy target searches: %.1f"
		% PerfCounters.get_rate(PerfCounters.KEY_ENEMY_TARGET_SEARCHES),
		"get_nodes_in_group: %.1f"
		% PerfCounters.get_rate(PerfCounters.KEY_GET_NODES_IN_GROUP),
		"Path recalculations: %.1f"
		% PerfCounters.get_rate(PerfCounters.KEY_PATH_RECALCULATIONS),
		"AI economy updates: %.1f"
		% PerfCounters.get_rate(PerfCounters.KEY_AI_ECONOMY_UPDATES),
		"AI combat updates: %.1f"
		% PerfCounters.get_rate(PerfCounters.KEY_AI_COMBAT_UPDATES),
	])
	_label.text = "\n".join(lines)


func _collect_unit_stats(tree: SceneTree) -> Dictionary:
	var player_units: int = tree.get_nodes_in_group(&"units").size()
	var ai_units: int = tree.get_nodes_in_group(&"enemies").size()
	var player_workers: int = tree.get_nodes_in_group(&"workers").size()
	var ai_workers: int = tree.get_nodes_in_group(&"enemy_workers").size()
	var workers: int = player_workers + ai_workers
	var military: int = maxi(0, player_units + ai_units - workers)

	return {
		"player_units": player_units,
		"ai_units": ai_units,
		"workers": workers,
		"military": military,
		"total_units": player_units + ai_units,
	}
