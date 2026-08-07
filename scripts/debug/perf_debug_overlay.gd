extends CanvasLayer

## Toggle with F3. Refreshes about 4 times per second while visible.

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
	_label.add_theme_font_size_override("font_size", 13)
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
	var fps: float = float(Engine.get_frames_per_second())
	var frame_time_ms: float = 1000.0 / maxf(fps, 1.0)
	var avg_fps: float = PerfCounters.get_average_fps()
	var low_fps: float = PerfCounters.get_recent_low_fps()
	if avg_fps <= 0.0:
		avg_fps = fps
	if low_fps <= 0.0:
		low_fps = fps

	var lines: PackedStringArray = PackedStringArray([
		"Performance Debug (F3)",
		"FPS: %d" % int(round(fps)),
		"Average FPS: %d" % int(round(avg_fps)),
		"Recent Low: %d" % int(round(low_fps)),
		"Frame Time: %.1f ms" % frame_time_ms,
		"",
		"Units: %d" % int(unit_stats.get("total_units", 0)),
		"Player Military: %d" % int(unit_stats.get("player_military", 0)),
		"Enemy Military: %d" % int(unit_stats.get("enemy_military", 0)),
		"Workers: %d" % int(unit_stats.get("workers", 0)),
		"Creeps: %d" % int(unit_stats.get("creeps", 0)),
		"Buildings: %d" % int(unit_stats.get("buildings", 0)),
		"",
	])

	var difficulty_lines: PackedStringArray = _collect_difficulty_debug_lines(tree)
	for line: String in difficulty_lines:
		lines.append(line)
	if not difficulty_lines.is_empty():
		lines.append("")

	lines.append_array(PackedStringArray([
		"AI Version: %s" % PerfCounters.get_military_ai_version(),
		"Macro: %s" % PerfCounters.get_military_ai_v2_macro(),
		"Military: %s" % PerfCounters.get_military_ai_v2_state(),
		"Mission: %s" % PerfCounters.get_military_ai_v2_mission(),
		"Executable: %s" % PerfCounters.get_military_ai_v2_executable_label(),
		"Blocked: %s" % PerfCounters.get_military_ai_v2_blocked(),
		"Hero: %s" % PerfCounters.get_military_ai_v2_hero_label(),
		"Army: %s" % PerfCounters.get_military_ai_v2_army_label(),
		"Camps: %s" % PerfCounters.get_military_ai_v2_camps_label(),
		"Target: %s" % PerfCounters.get_military_ai_v2_target_label(),
		"Defense: %s" % PerfCounters.get_military_ai_v2_defense_label(),
		"Threat: %s" % PerfCounters.get_military_ai_v2_threat_label(),
		"Combat Group: %d" % PerfCounters.get_combat_group_size(),
		"Pending AI Orders: %d" % PerfCounters.get_pending_group_orders(),
		"Orders/sec: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_AI_ORDERS),
		"Repaths/sec: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_REPATH_REQUESTS),
		"Squad Nav: %s" % ("on" if PerfCounters.is_squad_nav_enabled() else "off"),
		"Active Squads: %d (%d members)" % [
			PerfCounters.get_squad_nav_active_squads(),
			PerfCounters.get_squad_nav_member_count(),
		],
		"Squad Routes/sec: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_SQUAD_STRATEGIC_ROUTES),
		"Local Repaths/sec: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_SQUAD_LOCAL_REPATHS),
		"Route Cache Hits/sec: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_SQUAD_ROUTE_CACHE_HITS),
		"Squad Stalls: %d" % PerfCounters.get_squad_nav_stalls(),
		"Target Searches/sec: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_TARGET_SEARCHES),
	]))

	var warnings: PackedStringArray = PerfCounters.collect_warnings()
	if not warnings.is_empty():
		lines.append("")
		lines.append("WARNINGS:")
		for warning: String in warnings:
			lines.append("- %s" % warning)

	_label.text = "\n".join(lines)


func _collect_difficulty_debug_lines(tree: SceneTree) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray([
		"Difficulty: %s" % MatchSession.get_ai_difficulty_name(),
		"Production Limit:",
	])

	var build_manager: EnemyBuildManager = _find_enemy_build_manager(tree)
	if build_manager == null:
		lines.append(
			"Barracks: - / %d" % AIDifficultyConfig.max_barracks()
		)
		lines.append(
			"Stable: - / %d" % AIDifficultyConfig.max_stables()
		)
		lines.append(
			"Artillery Depot: - / %d" % AIDifficultyConfig.max_artillery_depots()
		)
		return lines

	var info: Dictionary = build_manager.get_difficulty_debug_info()
	lines.append(
		"Barracks: %d / %d"
		% [int(info.get("barracks_current", 0)), int(info.get("barracks_max", 0))]
	)
	lines.append(
		"Stable: %d / %d"
		% [int(info.get("stables_current", 0)), int(info.get("stables_max", 0))]
	)
	lines.append(
		"Artillery Depot: %d / %d"
		% [int(info.get("artillery_current", 0)), int(info.get("artillery_max", 0))]
	)
	return lines


func _find_enemy_build_manager(tree: SceneTree) -> EnemyBuildManager:
	var nodes: Array = tree.get_nodes_in_group(&"enemy_build_manager")
	for node: Variant in nodes:
		if node is EnemyBuildManager and is_instance_valid(node):
			return node as EnemyBuildManager
	return null


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


func _format_v2_distance(distance: float) -> String:
	if distance < 0.0:
		return "-"
	return "%.1f" % distance
