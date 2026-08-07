extends CanvasLayer

## Toggle with F3 (compact diagnostics). Shift+F3 toggles verbose diagnostics.
## Refreshes about 4 times per second while visible.

const TOGGLE_KEY := KEY_F3
const REFRESH_INTERVAL_SECONDS := 0.25
const BLOCK_REASON_MAX_CHARS := 36
## Compact panel targets ~220–280×320–360 px at 1080p (~12–15% × ~30–33%).
const FONT_SIZE := 11

const COLOR_NORMAL := Color(0.88, 0.92, 0.88, 1.0)
const COLOR_GOOD := Color(0.45, 0.92, 0.55, 1.0)
const COLOR_WARN := Color(1.0, 0.78, 0.28, 1.0)
const COLOR_ERROR := Color(1.0, 0.42, 0.38, 1.0)

var _panel: PanelContainer
var _label: RichTextLabel
var _refresh_timer: float = 0.0
var _visible_overlay: bool = false
var _verbose_mode: bool = false


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

	var want_verbose: bool = key_event.shift_pressed

	if not _visible_overlay:
		_verbose_mode = want_verbose
		show_overlay()
		get_viewport().set_input_as_handled()
		return

	if want_verbose:
		if _verbose_mode:
			hide_overlay()
		else:
			_verbose_mode = true
			_update_label()
	else:
		if not _verbose_mode:
			hide_overlay()
		else:
			_verbose_mode = false
			_update_label()

	get_viewport().set_input_as_handled()


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
	_panel.clip_contents = true

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.08, 0.90)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.25, 0.55, 0.35, 1)
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	_label = RichTextLabel.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_label.add_theme_color_override("default_color", COLOR_NORMAL)
	_label.add_theme_constant_override("line_separation", 1)
	## Keep content from stretching past the soft width budget.
	_label.custom_minimum_size = Vector2(0.0, 0.0)
	_panel.add_child(_label)

	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 10.0
	_panel.offset_top = 10.0


func _update_label() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		_label.text = "Diagnostics (no scene tree)"
		return

	if _verbose_mode:
		_label.text = _build_verbose_text(tree)
	else:
		_label.text = _build_compact_text(tree)


func _build_compact_text(tree: SceneTree) -> String:
	var unit_stats: Dictionary = _collect_unit_stats(tree)
	var fps: float = float(Engine.get_frames_per_second())
	var frame_time_ms: float = 1000.0 / maxf(fps, 1.0)

	var state: String = PerfCounters.get_military_ai_v2_state()
	var mission: String = PerfCounters.get_military_ai_v2_mission()
	var executable: bool = PerfCounters.get_military_ai_v2_mission_executable()
	var block_reason: String = _compact_block_reason(
		PerfCounters.get_military_ai_v2_block_reason()
	)
	var hero_level: int = PerfCounters.get_military_ai_v2_hero_level()
	var army: int = PerfCounters.get_military_ai_v2_squad_size()
	var camps: int = PerfCounters.get_military_ai_v2_camps_cleared()
	var target: String = PerfCounters.get_military_ai_v2_objective()
	var distance_text: String = _format_v2_distance(
		PerfCounters.get_military_ai_v2_distance()
	)
	var defense_active: bool = state.to_upper() == "DEFEND"
	var threat_text: String = _compact_threat_text(defense_active)
	var selected_count: int = _count_selected_units(tree)

	var lines: PackedStringArray = PackedStringArray([
		"[b]PERFORMANCE[/b]",
		"FPS: %s" % _colorize_fps(int(round(fps))),
		"Frame: %.1f ms" % frame_time_ms,
		"Units: %d" % int(unit_stats.get("total_units", 0)),
		"Buildings: %d" % int(unit_stats.get("buildings", 0)),
		"",
		"[b]NAVIGATION[/b]",
		"Orders/s: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_AI_ORDERS),
		"Repaths/s: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_REPATH_REQUESTS),
		"Target searches/s: %.0f" % PerfCounters.get_rate(PerfCounters.KEY_TARGET_SEARCHES),
	])

	if selected_count >= 0:
		lines.append("Selected: %d" % selected_count)

	var exec_unit: Unit = _get_primary_selected_unit(tree)
	if exec_unit != null:
		var dbg: Dictionary = exec_unit.get_movement_execution_debug()
		lines.append_array(PackedStringArray([
			"",
			"[b]MOVE EXEC (1)[/b]",
			"ID:%d gen:%d wp:%d" % [
				int(dbg.get("unit_id", 0)),
				int(dbg.get("command_generation", -1)),
				int(dbg.get("shared_waypoint_index", -1)),
			],
			"spd:%.1f stuck:%.1f %s" % [
				float(dbg.get("actual_speed", 0.0)),
				float(dbg.get("stuck_timer", 0.0)),
				str(dbg.get("movement_state", "?")),
			],
			"sep:%.2f form:%s stall:%s" % [
				(dbg.get("separation_correction", Vector3.ZERO) as Vector3).length(),
				"Y" if bool(dbg.get("formation_correction_ran", false)) else "N",
				"Y" if bool(dbg.get("stall_recovery_ran", false)) else "N",
			],
			"%s" % _truncate(str(dbg.get("target_change_reason", "")), 28),
		]))

	lines.append_array(PackedStringArray([
		"",
		"[b]AI[/b]",
		"State: %s" % state,
		"Mission: %s" % mission,
		"Executable: %s" % _colorize_yes_no(executable),
		"Blocked: %s" % _colorize_blocked(block_reason, executable),
		"",
		"Hero: L%d" % hero_level,
		"Army: %d" % army,
		"Camps: %d" % camps,
		"",
		"Target: %s" % _truncate(target, 28),
		"Distance: %s" % distance_text,
		"",
		"Defense: %s" % _colorize_defense(defense_active),
		"Threat: %s" % _colorize_threat(threat_text, defense_active),
	]))

	return "\n".join(lines)


func _build_verbose_text(tree: SceneTree) -> String:
	## Verbose dump retained for Shift+F3 and existing verify string coverage.
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
		"Performance Debug (Shift+F3)",
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
		"AI Phase: %s" % PerfCounters.get_ai_phase(),
		"AI Combat: %s" % PerfCounters.get_ai_combat_state(),
		"Mission Owner: %s" % PerfCounters.get_ai_mission_owner(),
		"%s" % _truncate(PerfCounters.get_ai_mission_detail(), 48),
		"V2 State: %s" % PerfCounters.get_military_ai_v2_state(),
		"V2 Mission: %s" % PerfCounters.get_military_ai_v2_mission(),
		"V2 Destination: %s" % _truncate(PerfCounters.get_military_ai_v2_destination(), 40),
		"V2 Objective: %s" % _truncate(PerfCounters.get_military_ai_v2_objective(), 40),
		"V2 Order: %s" % PerfCounters.get_military_ai_v2_active_order(),
		"V2 Last Order: %s" % _truncate(PerfCounters.get_military_ai_v2_last_order_time(), 40),
		"V2 Last Mission Change: %s" % _truncate(
			PerfCounters.get_military_ai_v2_last_mission_change(), 40
		),
		"V2 Idle Time: %.1fs" % PerfCounters.get_military_ai_v2_idle_time(),
		"V2 Squad Size: %d" % PerfCounters.get_military_ai_v2_squad_size(),
		"V2 Distance: %s" % _format_v2_distance(PerfCounters.get_military_ai_v2_distance()),
		"V2 Since Progress: %.1fs" % PerfCounters.get_military_ai_v2_seconds_since_progress(),
		"V2 State Age: %.1fs" % PerfCounters.get_military_ai_v2_state_age(),
		"V2 Mission Age: %.1fs" % PerfCounters.get_military_ai_v2_mission_age(),
		"V2 Transition: %s" % _truncate(PerfCounters.get_military_ai_v2_transition_reason(), 40),
		"V2 Watchdog: %s" % _truncate(PerfCounters.get_military_ai_v2_watchdog_status(), 40),
		"V2 Mission Executable: %s" % (
			"yes" if PerfCounters.get_military_ai_v2_mission_executable() else "no"
		),
		"V2 Block: %s" % _truncate(PerfCounters.get_military_ai_v2_block_reason(), 40),
		"V2 Hero: %s L%d" % [
			("alive" if PerfCounters.get_military_ai_v2_hero_present() else "dead"),
			PerfCounters.get_military_ai_v2_hero_level(),
		],
		"V2 Escorts: %d" % PerfCounters.get_military_ai_v2_escort_count(),
		"V2 Camps Cleared: %d" % PerfCounters.get_military_ai_v2_camps_cleared(),
		"V2 Role Counts: %s" % PerfCounters.get_military_ai_v2_role_counts(),
		"V2 Army Strength: %.0f" % PerfCounters.get_military_ai_v2_army_strength(),
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
			lines.append("- %s" % _truncate(warning, 48))

	return "\n".join(lines)


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


func _count_selected_units(tree: SceneTree) -> int:
	if tree == null or tree.root == null:
		return -1
	var selection: Node = tree.root.find_child("SelectionManager", true, false)
	if selection == null:
		return -1
	var selected: Variant = selection.get("selected_units")
	if not selected is Array:
		return 0
	return (selected as Array).size()


func _get_primary_selected_unit(tree: SceneTree) -> Unit:
	if tree == null or tree.root == null:
		return null
	var selection: Node = tree.root.find_child("SelectionManager", true, false)
	if selection == null:
		return null
	var selected: Variant = selection.get("selected_units")
	if not selected is Array:
		return null
	for unit_ref: Variant in selected as Array:
		if unit_ref == null or not is_instance_valid(unit_ref) or not unit_ref is Unit:
			continue
		var unit: Unit = unit_ref as Unit
		if unit.is_queued_for_deletion():
			continue
		if unit.is_in_group(&"enemies") or unit.is_in_group(&"neutral_creeps"):
			continue
		return unit
	return null


func _compact_threat_text(defense_active: bool) -> String:
	if not defense_active:
		return "none"
	var reason: String = PerfCounters.get_military_ai_v2_transition_reason()
	if reason.is_empty() or reason == "-":
		return "active"
	return _truncate(reason, BLOCK_REASON_MAX_CHARS)


func _compact_block_reason(reason: String) -> String:
	if reason.is_empty() or reason == "-":
		return "none"
	return _truncate(reason, BLOCK_REASON_MAX_CHARS)


func _truncate(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, maxi(0, max_chars - 1)) + "…"


func _format_v2_distance(distance: float) -> String:
	if distance < 0.0:
		return "-"
	return "%.0f" % distance


func _colorize_fps(fps: int) -> String:
	if fps < 30:
		return "[color=#%s]%d[/color]" % [_color_to_hex(COLOR_ERROR), fps]
	if fps < 45:
		return "[color=#%s]%d[/color]" % [_color_to_hex(COLOR_WARN), fps]
	return "[color=#%s]%d[/color]" % [_color_to_hex(COLOR_GOOD), fps]


func _colorize_yes_no(ok: bool) -> String:
	if ok:
		return "[color=#%s]YES[/color]" % _color_to_hex(COLOR_GOOD)
	return "[color=#%s]NO[/color]" % _color_to_hex(COLOR_WARN)


func _colorize_blocked(reason: String, executable: bool) -> String:
	if reason == "none" or executable:
		return reason
	return "[color=#%s]%s[/color]" % [_color_to_hex(COLOR_WARN), reason]


func _colorize_defense(active: bool) -> String:
	if active:
		return "[color=#%s]YES[/color]" % _color_to_hex(COLOR_WARN)
	return "NO"


func _colorize_threat(threat: String, defense_active: bool) -> String:
	if not defense_active or threat == "none":
		return threat
	return "[color=#%s]%s[/color]" % [_color_to_hex(COLOR_WARN), threat]


func _color_to_hex(color: Color) -> String:
	return "%02x%02x%02x" % [
		int(round(color.r * 255.0)),
		int(round(color.g * 255.0)),
		int(round(color.b * 255.0)),
	]
