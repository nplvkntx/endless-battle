extends CanvasLayer

## Toggle with F3. Refreshes about 4 times per second while visible.
## Enemy AI lines come from EnemyAI's last condition-tick snapshot (same helpers).

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
		"Units %d | P mil %d | E mil %d | workers %d | creeps %d"
		% [
			int(unit_stats.get("total_units", 0)),
			int(unit_stats.get("player_military", 0)),
			int(unit_stats.get("enemy_military", 0)),
			int(unit_stats.get("workers", 0)),
			int(unit_stats.get("creeps", 0)),
		],
		"Difficulty: %s" % MatchSession.get_ai_difficulty_name(),
		"",
	])

	var ai_lines: PackedStringArray = _collect_enemy_ai_lines(tree)
	if ai_lines.is_empty():
		lines.append("ENEMY AI")
		lines.append("AI CONDITION: (EnemyAI not in match)")
	else:
		lines.append_array(ai_lines)

	var warnings: PackedStringArray = PerfCounters.collect_warnings()
	if not warnings.is_empty():
		lines.append("")
		lines.append("PERF:")
		for warning: String in warnings:
			lines.append("- %s" % warning)

	_label.text = "\n".join(lines)


func _collect_enemy_ai_lines(tree: SceneTree) -> PackedStringArray:
	var root: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	if root == null or root.enemy_ai == null:
		return PackedStringArray()
	return root.enemy_ai.get_debug_overlay_lines()


func _collect_unit_stats(tree: SceneTree) -> Dictionary:
	var player_units: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"units")
	var enemy_units: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"enemies")
	var player_workers: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"workers")
	var enemy_workers: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"enemy_workers")
	var creeps: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"neutral_creeps")
	var buildings: Array = CombatTargetValidation.get_cached_group_nodes(tree, &"buildings")

	var workers: int = player_workers.size() + enemy_workers.size()
	var player_military: int = maxi(0, player_units.size() - player_workers.size())
	var enemy_military: int = maxi(0, enemy_units.size() - enemy_workers.size())

	return {
		"total_units": player_units.size() + enemy_units.size() + creeps.size(),
		"player_military": player_military,
		"enemy_military": enemy_military,
		"workers": workers,
		"creeps": creeps.size(),
		"buildings": buildings.size(),
	}
