extends CanvasLayer

## Toggle with F3. Refreshes about 4 times per second while visible.
## Performance counters only. Enemy AI reasoning is the P-key brain panel.

const TOGGLE_KEY := KEY_F3
const REFRESH_INTERVAL_SECONDS := 0.25

var _panel: PanelContainer
var _label: Label
var _refresh_timer: float = 0.0
var _visible_overlay: bool = false


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
	panel_style.bg_color = Color(0.04, 0.06, 0.08, 0.90)
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
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.90, 0.97, 0.88, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	_label.add_theme_constant_override("outline_size", 4)
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
	var fps: float = float(Engine.get_frames_per_second())
	var frame_time_ms: float = 1000.0 / maxf(fps, 1.0)
	var avg_fps: float = PerfCounters.get_average_fps()
	var low_fps: float = PerfCounters.get_recent_low_fps()
	if avg_fps <= 0.0:
		avg_fps = fps
	if low_fps <= 0.0:
		low_fps = fps

	var lines: PackedStringArray = PackedStringArray([
		"Debug (F3)",
		"FPS: %d  avg %d  low %d  %.1fms"
		% [int(round(fps)), int(round(avg_fps)), int(round(low_fps)), frame_time_ms],
		"phys %.1fms  script %.1fms"
		% [
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		],
		"Units %d | moving %d | P mil %d | E mil %d | workers %d | creeps %d"
		% [
			int(unit_stats.get("total_units", 0)),
			int(unit_stats.get("moving_units", 0)),
			int(unit_stats.get("player_military", 0)),
			int(unit_stats.get("enemy_military", 0)),
			int(unit_stats.get("workers", 0)),
			int(unit_stats.get("creeps", 0)),
		],
		"neighQ/s %.0f  neighN/s %.0f  sep/s %.0f"
		% [
			PerfCounters.get_rate(PerfCounters.KEY_UNIT_NEIGHBOR_QUERIES),
			PerfCounters.get_rate(PerfCounters.KEY_NEIGHBORS_PROCESSED),
			PerfCounters.get_rate(PerfCounters.KEY_SEPARATION_UPDATES),
		],
		"repath/s %.0f  route/s %.0f  orders/s %.0f  tgt/s %.0f"
		% [
			PerfCounters.get_rate(PerfCounters.KEY_REPATH_REQUESTS),
			PerfCounters.get_rate(PerfCounters.KEY_STRATEGIC_ROUTE_REQUESTS),
			PerfCounters.get_rate(PerfCounters.KEY_AI_ORDERS),
			PerfCounters.get_rate(PerfCounters.KEY_TARGET_SEARCHES),
		],
		"stuckChk/s %.0f  stuckRec/s %.0f"
		% [
			PerfCounters.get_rate(PerfCounters.KEY_STUCK_CHECKS),
			PerfCounters.get_rate(PerfCounters.KEY_STUCK_RECOVERIES),
		],
		"Difficulty: %s" % MatchSession.get_ai_difficulty_name(),
	])

	var warnings: PackedStringArray = PerfCounters.collect_warnings()
	if not warnings.is_empty():
		lines.append("")
		lines.append("PERF:")
		for warning: String in warnings:
			lines.append("- %s" % warning)

	_label.text = "\n".join(lines)


func _collect_unit_stats(tree: SceneTree) -> Dictionary:
	## Group arrays are valid at cache-build time only. Entries can die later in the
	## same process frame — never typed-assign or cast before is_instance_valid().
	var player_units: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"units")
	var enemy_units: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"enemies")
	var player_workers: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"workers")
	var enemy_workers: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"enemy_workers")
	var creeps: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"neutral_creeps")
	var buildings: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"buildings")

	var player_unit_count: int = _count_valid_nodes(player_units)
	var enemy_unit_count: int = _count_valid_nodes(enemy_units)
	var player_worker_count: int = _count_valid_nodes(player_workers)
	var enemy_worker_count: int = _count_valid_nodes(enemy_workers)
	var creep_count: int = _count_valid_nodes(creeps)
	var building_count: int = _count_valid_nodes(buildings)

	var workers: int = player_worker_count + enemy_worker_count
	var player_military: int = maxi(0, player_unit_count - player_worker_count)
	var enemy_military: int = maxi(0, enemy_unit_count - enemy_worker_count)
	var moving_units: int = (
		_count_moving_units(player_units)
		+ _count_moving_units(enemy_units)
		+ _count_moving_units(creeps)
	)

	return {
		"total_units": player_unit_count + enemy_unit_count + creep_count,
		"moving_units": moving_units,
		"player_military": player_military,
		"enemy_military": enemy_military,
		"workers": workers,
		"creeps": creep_count,
		"buildings": building_count,
	}


func _count_valid_nodes(nodes: Array) -> int:
	var count := 0
	for value: Variant in nodes:
		if value != null and is_instance_valid(value):
			count += 1
	return count


func _count_moving_units(nodes: Array) -> int:
	var moving := 0
	for node_variant: Variant in nodes:
		if node_variant == null:
			continue
		if not is_instance_valid(node_variant):
			continue
		if not node_variant is Unit:
			continue

		var unit: Unit = node_variant as Unit
		if unit.has_move_target:
			moving += 1
	return moving
