extends CanvasLayer

## Development-only RTS AI / unit / order / nav / combat diagnostics.
## Toggle with O. Default OFF. READ-ONLY — never issues orders or mutates AI state.
## Separate from F3 performance overlay.

const TOGGLE_KEY := KEY_O
const REFRESH_INTERVAL_SECONDS := 0.22
const EVENT_FEED_MAX := 5
const EVENT_AGE_SECONDS := 18.0
const WORLD_LABEL_MAX := 14

var _panel: PanelContainer
var _label: RichTextLabel
var _unit_panel: PanelContainer
var _unit_label: RichTextLabel
var _refresh_timer: float = 0.0
var _visible_overlay: bool = false
var _prev_state: String = ""
var _prev_mission: String = ""
var _prev_reason: String = ""
var _prev_hero_with_main: bool = true
var _prev_exec: String = ""
var _prev_last_order: String = ""
var _event_feed: Array = []
var _world_root: Node3D = null
var _path_mesh: MeshInstance3D = null
var _label_pool: Array = []
var _order_replace_times: Array = []
var _layout_compact: bool = false
var _primary_font: int = 14
var _secondary_font: int = 11
var _event_font: int = 10
var _show_secondary: bool = true
var _panel_width: float = 360.0
## When set (tests / headless smoke), layout uses this instead of live viewport size.
var _layout_size_override: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 126
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_build_ui()
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_on_viewport_size_changed)
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
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _visible_overlay:
		return
	_refresh_timer += delta
	## Selected-unit path viz can refresh every frame cheaply.
	_update_selected_path_viz()
	if _refresh_timer < REFRESH_INTERVAL_SECONDS:
		return
	_refresh_timer = 0.0
	_update_panels()


func show_overlay() -> void:
	_visible_overlay = true
	_panel.visible = true
	_unit_panel.visible = true
	_refresh_timer = REFRESH_INTERVAL_SECONDS
	set_process(true)
	_ensure_world_root()
	_apply_layout(false)
	_update_panels()


func hide_overlay() -> void:
	_visible_overlay = false
	_panel.visible = false
	_unit_panel.visible = false
	set_process(false)
	_teardown_world_debug()


func is_overlay_visible() -> bool:
	return _visible_overlay


func _on_viewport_size_changed() -> void:
	if _visible_overlay:
		_update_panels()


func _build_ui() -> void:
	_panel = _make_panel(Color(0.04, 0.07, 0.11, 0.94), Color(0.40, 0.72, 0.92, 1.0))
	_label = _make_rich_label()
	_panel.add_child(_label)
	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.clip_contents = true

	_unit_panel = _make_panel(Color(0.06, 0.05, 0.08, 0.94), Color(0.90, 0.60, 0.38, 1.0))
	_unit_label = _make_rich_label()
	_unit_panel.add_child(_unit_label)
	add_child(_unit_panel)
	_unit_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_unit_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_unit_panel.clip_contents = true
	_panel.visible = false
	_unit_panel.visible = false
	_apply_layout(false)


func _make_panel(bg: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.content_margin_left = 6.0
	style.content_margin_top = 4.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_color_override("default_color", Color(0.92, 0.95, 0.98, 1.0))
	label.add_theme_constant_override("line_separation", 2)
	return label


func set_layout_size_override_for_tests(size: Vector2) -> void:
	_layout_size_override = size


func _resolve_layout_size() -> Vector2:
	if _layout_size_override.x > 1.0 and _layout_size_override.y > 1.0:
		return _layout_size_override
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_visible_rect().size


func _apply_layout(has_unit: bool) -> void:
	var vp: Vector2 = _resolve_layout_size()
	if vp.x < 1.0 or vp.y < 1.0:
		return

	_layout_compact = vp.y <= 640.0 or vp.x <= 1200.0
	## Keep ~25–30% width; avoid huge panels on 1080p.
	var width_frac: float = 0.30 if _layout_compact else 0.24
	_panel_width = clampf(vp.x * width_frac, 250.0, 400.0)

	## Prefer readable primary text; shrink secondary first on tiny viewports.
	if vp.y <= 520.0:
		_primary_font = 15
		_secondary_font = 10
		_event_font = 10
		_show_secondary = false
	elif _layout_compact:
		_primary_font = 14
		_secondary_font = 11
		_event_font = 10
		_show_secondary = true
	else:
		_primary_font = 13
		_secondary_font = 11
		_event_font = 10
		_show_secondary = true

	var margin: float = 8.0
	var bottom_ui_reserve: float = maxf(vp.y * 0.22, 88.0)
	var max_total_h: float = minf(vp.y * 0.48, vp.y - margin - bottom_ui_reserve)
	max_total_h = maxf(max_total_h, 140.0)

	## Top-right anchored: height is offset_bottom - offset_top.
	_panel.offset_right = -margin
	_panel.offset_top = margin
	_panel.offset_left = -margin - _panel_width
	_panel.custom_minimum_size = Vector2(_panel_width, 0)
	_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_unit_panel.offset_right = -margin
	_unit_panel.offset_left = -margin - _panel_width
	_unit_panel.custom_minimum_size = Vector2(_panel_width, 0)
	_unit_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	if has_unit:
		var brain_h: float = max_total_h * (0.48 if _layout_compact else 0.52)
		var gap: float = 4.0
		var unit_top: float = margin + brain_h + gap
		_panel.offset_bottom = margin + brain_h
		_label.custom_maximum_size = Vector2(_panel_width - 12.0, maxf(brain_h - 12.0, 40.0))
		_unit_panel.offset_top = unit_top
		_unit_panel.offset_bottom = margin + max_total_h
		_unit_label.custom_maximum_size = Vector2(
			_panel_width - 12.0,
			maxf(max_total_h - brain_h - gap - 12.0, 40.0)
		)
		_unit_panel.visible = _visible_overlay
	else:
		_panel.offset_bottom = margin + max_total_h
		_label.custom_maximum_size = Vector2(_panel_width - 12.0, maxf(max_total_h - 12.0, 40.0))
		_unit_panel.offset_top = margin + max_total_h + 4.0
		_unit_panel.offset_bottom = margin + max_total_h + 4.0
		if _visible_overlay:
			_unit_panel.visible = false


func _update_panels() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		_label.text = _bb_primary("RTS AI Debug (O)\n(no scene tree)")
		_unit_label.text = ""
		_apply_layout(false)
		return

	var composition: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	var director: MilitaryDirectorV2 = null
	var commander: ArmyCommanderV2 = null
	var selection: Node = null
	if composition != null:
		director = composition.military_director_v2
		commander = composition.army_commander_v2
		selection = composition.selection_manager

	var snap: Dictionary = {}
	if director != null and MilitaryAIConfig.is_v2_enabled():
		snap = director.get_rts_diagnostic_snapshot()
	_note_events(snap)

	var unit: Unit = _resolve_inspected_unit(selection)
	var has_unit: bool = unit != null
	_apply_layout(has_unit)

	_label.text = _format_global_panel(snap, commander, has_unit, unit)
	_unit_label.text = _format_unit_panel(tree, unit, director, snap, has_unit)
	_update_world_labels(tree, director, selection, snap)


func _bb_primary(body: String) -> String:
	return "[font_size=%d]%s[/font_size]" % [_primary_font, body]


func _bb_secondary(body: String) -> String:
	return "[font_size=%d][color=#a8b4bc]%s[/color][/font_size]" % [_secondary_font, body]


func _bb_events(body: String) -> String:
	return "[font_size=%d][color=#c5d0d8]%s[/color][/font_size]" % [_event_font, body]


func _bb_header(text: String) -> String:
	return "[color=#7ec8ff]%s[/color]" % text


func _format_global_panel(
	snap: Dictionary,
	commander: ArmyCommanderV2,
	has_unit: bool,
	selected_unit: Unit = null
) -> String:
	if snap.is_empty():
		return _bb_primary("%s\n(V2 director unavailable)" % _bb_header("AI BRAIN"))

	var with_main: bool = bool(snap.get("hero_with_main", false))
	var hero_squad: String = "MAIN" if with_main else "AWAY"
	var primary: PackedStringArray = PackedStringArray([
		_bb_header("AI BRAIN"),
		"Mission: %s" % String(snap.get("mission", "-")),
		"Decision: %s" % String(snap.get("state", "-")),
		"Why: %s" % _short(String(snap.get("transition_reason", "-")), 36 if _layout_compact else 48),
		"Hero: %s L%d %d%%" % [
			_short(String(snap.get("hero_name", "-")), 14),
			int(snap.get("hero_level", 0)),
			int(round(float(snap.get("hero_hp_ratio", 0.0)) * 100.0)),
		],
		"WITH MAIN: %s" % ("YES" if with_main else "NO"),
		"Hero state: %s" % String(snap.get("hero_state", "-")),
		"Hero squad: %s" % hero_squad,
		"Army: %d" % int(snap.get("combat_alive", 0)),
		"Available: %d" % int(snap.get("combat_available", 0)),
		"Main: %d" % int(snap.get("main_squad", 0)),
		"Unassigned: %d" % int(snap.get("unassigned", 0)),
		"Idle: %d" % int(snap.get("idle_military", 0)),
		"Dir power: %d" % int(round(float(snap.get("director_power", 0.0)))),
		"Cmd power: %d" % int(round(float(snap.get("commander_power", 0.0)))),
		"Mismatch: %d" % int(round(float(snap.get("power_mismatch", 0.0)))),
		"Objective: %s" % _short(String(snap.get("objective", "-")), 28 if _layout_compact else 40),
		"Commander: %s" % String(snap.get("executable", "-")),
		_bb_header("MOVEMENT"),
		"Custom RTS movement: %s" % (
			"ON" if MilitaryAIConfig.is_custom_rts_movement_enabled() else "OFF"
		),
		"AI squad using custom: %s" % (
			"YES" if PlayerRouteNavigation.was_last_ai_custom_move() else "NO"
		),
		"Squad size: %d" % PlayerRouteNavigation.get_last_squad_size(),
		"Shared path calcs: %d" % PlayerRouteNavigation.get_path_calculations_this_command(),
		"Route waypoints: %d" % PlayerRouteNavigation.get_last_route_waypoints(),
	])

	## On tiny viewports with a unit panel, keep only the densest primary block.
	if _layout_compact and has_unit:
		primary = PackedStringArray([
			_bb_header("AI BRAIN"),
			"Mission: %s" % String(snap.get("mission", "-")),
			"Decision: %s" % String(snap.get("state", "-")),
			"Why: %s" % _short(String(snap.get("transition_reason", "-")), 32),
			"Hero: %s  MAIN:%s" % [
				_short(String(snap.get("hero_name", "-")), 12),
				"YES" if with_main else "NO",
			],
			"State:%s Squad:%s" % [String(snap.get("hero_state", "-")), hero_squad],
			"Avail:%d Main:%d Unas:%d Idle:%d" % [
				int(snap.get("combat_available", 0)),
				int(snap.get("main_squad", 0)),
				int(snap.get("unassigned", 0)),
				int(snap.get("idle_military", 0)),
			],
			"Dir:%d Cmd:%d Δ%d" % [
				int(round(float(snap.get("director_power", 0.0)))),
				int(round(float(snap.get("commander_power", 0.0)))),
				int(round(float(snap.get("power_mismatch", 0.0)))),
			],
			"Obj: %s" % _short(String(snap.get("objective", "-")), 26),
			"Commander: %s" % String(snap.get("executable", "-")),
			"CustomRTS:%s AI:%s" % [
				"ON" if MilitaryAIConfig.is_custom_rts_movement_enabled() else "OFF",
				"Y" if PlayerRouteNavigation.was_last_ai_custom_move() else "N",
			],
		])

	var chunks: PackedStringArray = PackedStringArray([_bb_primary("\n".join(primary))])

	var include_secondary: bool = _show_secondary and not (_layout_compact and has_unit)
	if include_secondary:
		var secondary: PackedStringArray = PackedStringArray()
		secondary.append("Prev: %s" % _short(_prev_mission if not _prev_mission.is_empty() else "-", 28))
		secondary.append("Age: %.1fs  Valid: %s" % [
			float(snap.get("mission_age", 0.0)),
			"YES" if bool(snap.get("objective_valid", false)) else "NO",
		])
		var dist: float = float(snap.get("hero_dist_main", -1.0))
		if dist >= 0.0:
			secondary.append("Hero dist: %.1fm" % dist)
		if not with_main:
			var away: String = String(snap.get("hero_away_reason", "unknown")).to_upper()
			if away.is_empty():
				away = "UNKNOWN"
			secondary.append("Away: %s" % _short(away, 28))
		secondary.append("Pending: %d  Roles: %s" % [
			int(snap.get("pending", 0)),
			_short(String(snap.get("role_counts", "-")), 24),
		])
		secondary.append("Player P: %d  Ratio: %.2f" % [
			int(round(float(snap.get("player_power", 0.0)))),
			float(snap.get("power_ratio", 0.0)),
		])
		var decision_lines: Variant = snap.get("decision_lines", PackedStringArray())
		if decision_lines is PackedStringArray:
			for line: String in decision_lines:
				secondary.append(_short(line, 40))
		elif decision_lines is Array:
			for entry: Variant in decision_lines:
				secondary.append(_short(str(entry), 40))
		secondary.append("Early creep: %s  Int.atks: %s" % [
			"Y" if bool(snap.get("prefer_early_creep", false)) else "N",
			"Y" if bool(snap.get("interrupt_for_attack", false)) else "N",
		])
		secondary.append("Exec: %s" % _short(String(snap.get("executable_reason", "-")), 36))
		secondary.append("Auth: %s" % String(snap.get("authority", "UNKNOWN")))
		var idle_s: float = float(snap.get("commander_idle_seconds", 0.0))
		if commander != null:
			idle_s = commander.get_squad_idle_seconds()
		secondary.append("Squad idle: %.1fs" % idle_s)

		secondary.append("DEF Threat:%s %s" % [
			"YES" if bool(snap.get("threat_active", false)) else "NO",
			_short(String(snap.get("threat_target", "-")), 18),
		])
		secondary.append("ThreatP:%d DefP:%d hero_def:%s" % [
			int(round(float(snap.get("threat_power", 0.0)))),
			int(round(float(snap.get("defense_power", 0.0)))),
			"Y" if bool(snap.get("hero_defending", false)) else "N",
		])
		if bool(snap.get("defend_active", false)):
			secondary.append("Def why: %s" % _short(String(snap.get("defend_reason", "-")), 32))

		var state_name: String = String(snap.get("state", ""))
		if state_name == "CREEP" or not String(snap.get("creep_block", "")).is_empty():
			secondary.append("CREEP %s alive=%s d=%.1f" % [
				_short(String(snap.get("camp", "-")), 14),
				"Y" if bool(snap.get("camp_alive", false)) else "N",
				float(snap.get("camp_distance", -1.0)),
			])
			var creep_block: String = String(snap.get("creep_block", ""))
			if not creep_block.is_empty():
				secondary.append("Creep block: %s" % _short(creep_block, 36))

		if state_name == "ATTACK":
			secondary.append("ATK move:%d idle:%d tgt:%d" % [
				int(snap.get("attack_moving", 0)),
				int(snap.get("attack_idle", 0)),
				int(snap.get("attack_with_targets", 0)),
			])
			var atk_block: String = String(snap.get("attack_block", ""))
			if not atk_block.is_empty():
				secondary.append("Atk block: %s" % _short(atk_block, 36))

		secondary.append("Last ord: %s %s" % [
			_short(String(snap.get("last_order_label", "-")), 20),
			_format_age(float(snap.get("last_order_age", INF))),
		])
		var army_conflict := "UNKNOWN"
		if selected_unit != null and selected_unit.has_method("get_strategic_order_provenance"):
			army_conflict = String(
				selected_unit.get_strategic_order_provenance().get("conflict", "UNKNOWN")
			)
		secondary.append(
			"Repl(3s):%d Conflict:%s" % [
				_count_order_replacements_2s(),
				army_conflict,
			]
		)
		chunks.append(_bb_secondary("\n".join(secondary)))

	## Events stay smaller than primary diagnostics; cap feed length by space.
	var event_cap: int = 3 if (_layout_compact and has_unit) else (4 if _layout_compact else EVENT_FEED_MAX)
	_prune_events()
	var event_lines: PackedStringArray = PackedStringArray([_bb_header("EVENTS")])
	if _event_feed.is_empty():
		event_lines.append("(none)")
	else:
		var shown: int = 0
		for entry: Variant in _event_feed:
			if shown >= event_cap:
				break
			if entry is Dictionary:
				event_lines.append(String((entry as Dictionary).get("msg", "")))
				shown += 1
	chunks.append(_bb_events("\n".join(event_lines)))

	return "\n".join(chunks)


func _format_unit_panel(
	tree: SceneTree,
	unit: Unit,
	director: MilitaryDirectorV2,
	snap: Dictionary,
	has_unit: bool
) -> String:
	if not has_unit or unit == null:
		return _bb_secondary("(select a unit)")

	var ownership: String = "UNKNOWN"
	if director != null:
		ownership = director.classify_unit_ownership_for_diagnostics(unit)
	var mission_label: String = EnemyUnitMission.mission_to_label(
		EnemyUnitMission.get_unit_mission(unit)
	)
	var squad_label: String = "-"
	if ownership == "in_main_squad":
		squad_label = "MAIN"
	elif ownership == "pending_reinforcement" or ownership == "reinforcement_pool":
		squad_label = "PENDING"
	elif ownership == "defense_reserved":
		squad_label = "DEFENSE"
	else:
		squad_label = ownership.to_upper()

	var order: UnitOrder = unit.get_active_order()
	var order_text: String = "NONE"
	var order_target: String = "-"
	if order != null:
		order_text = order.describe()
		var alive_t: Node3D = order.get_alive_target()
		if alive_t != null:
			order_target = alive_t.name

	var prov: Dictionary = {}
	if unit.has_method("get_strategic_order_provenance"):
		prov = unit.get_strategic_order_provenance()
	var src: String = String(prov.get("source", "UNKNOWN"))
	var ord_type: String = String(prov.get("type", order_text))
	var ord_age: float = float(prov.get("age", INF))
	var prev_src: String = String(prov.get("prev_source", "-"))
	var prev_type: String = String(prov.get("prev_type", "-"))
	var prev_age: float = float(prov.get("prev_age", INF))
	var repl_3s: int = int(prov.get("replacements_3s", 0))
	var conflict: String = String(prov.get("conflict", "UNKNOWN"))
	var mission_gen: int = int(snap.get("mission_generation", 0))
	var unit_mission_gen: int = int(prov.get("mission_gen", 0))
	var gen_text: String = str(unit_mission_gen) if unit_mission_gen > 0 else str(mission_gen)
	var dest: Vector3 = unit.get_movement_destination()
	var prov_target: String = "-"
	var prov_dest: Vector3 = prov.get("target", Vector3.ZERO) as Vector3
	if prov_dest != Vector3.ZERO:
		prov_target = "(%.0f, %.0f)" % [prov_dest.x, prov_dest.z]
	elif unit.has_move_target:
		prov_target = "(%.0f, %.0f)" % [dest.x, dest.z]

	var idle_reason: String = "-"
	if (
		int(snap.get("idle_military", 0)) > 0
		and not unit.is_movement_active()
		and order == null
	):
		idle_reason = _derive_idle_reason(unit, ownership, mission_label, _read_nav_state(unit))

	var dest_text: String = "-"
	if unit.has_move_target:
		dest_text = "(%.0f, %.0f)" % [dest.x, dest.z]

	var nav: Dictionary = _read_nav_state(unit)
	var combat: Dictionary = _read_combat_state(unit)

	var primary: PackedStringArray = PackedStringArray([
		_bb_header("UNIT"),
		"%s #%d" % [_short(unit.name, 16), unit.get_instance_id()],
		"Squad: %s" % squad_label,
		"Mission: %s" % mission_label,
		"Mission gen: %s" % gen_text,
		"Order: %s" % _short(order_text, 28 if _layout_compact else 40),
		"Objective: %s" % _short(String(snap.get("objective", "-")), 24),
		"Target: %s" % _read_attack_target_name(unit),
		"Idle: %s" % idle_reason,
		_bb_header("ORDER AUTHORITY"),
		"Cur: %s" % _short(ord_type, 18),
		"Source: %s" % _short(src, 22),
		"Target: %s" % prov_target,
		"Age: %s" % _format_age(ord_age),
		"Prev: %s / %s" % [_short(prev_src, 14), _short(prev_type, 12)],
		"Prev age: %s" % _format_age(prev_age),
		"Repl(3s): %d" % repl_3s,
		"CONFLICT: %s" % conflict,
		_bb_header("NAV"),
		"Backend: %s" % unit.get_movement_backend_label(),
		"Custom active: %s" % ("YES" if unit.is_custom_rts_movement_active() else "NO"),
		"Route WP: %d/%d" % [
			unit.get_custom_rts_route_index(),
			unit.get_custom_rts_route_waypoint_count(),
		],
		"Dest: %s" % dest_text,
		"Blocked: %s" % String(nav.get("blocked", "NO")),
		"Stuck: %.1fs" % float(unit.get("_stuck_time")),
		"Repath: %s" % _short(String(nav.get("repath_reason", "UNKNOWN")), 24),
		"Blocker: %s" % _short(String(nav.get("blocker", "-")), 20),
		_bb_header("COMBAT"),
		"Target: %s" % String(combat.get("target", "NONE")),
		"Type: %s" % String(combat.get("target_type", "-")),
		"Dist: %s  Rng: %s" % [String(combat.get("distance", "-")), String(combat.get("range", "-"))],
		"In rng: %s  Can: %s" % [
			String(combat.get("in_range", "-")),
			String(combat.get("can_attack", "-")),
		],
		"Atk state: %s" % String(combat.get("state", "-")),
	])

	var chunks: PackedStringArray = PackedStringArray([_bb_primary("\n".join(primary))])

	if _show_secondary and not _layout_compact:
		var secondary: PackedStringArray = PackedStringArray([
			"Owner: %s" % ownership,
			"Path: %s pts:%d" % [
				String(nav.get("path_state", "-")),
				int(nav.get("path_points", 0)),
			],
			"WP: %s  Vel: %.1f" % [
				String(nav.get("waypoint", "-")),
				unit.velocity.length(),
			],
			"Moving: %s  Stuck?: %s" % [
				"Y" if unit.is_movement_active() else "N",
				"Y" if unit.is_confirmed_stuck() else "N",
			],
			"Alive: %s Hostile: %s CD: %s" % [
				String(combat.get("target_alive", "-")),
				String(combat.get("hostile", "-")),
				String(combat.get("cooldown", "-")),
			],
			"Ord tgt: %s" % order_target,
			"Repl(3s): %d Conflict:%s" % [repl_3s, conflict],
		])
		var route_fail: String = EnemyArmyCommand.get_last_squad_route_failure_reason()
		if not route_fail.is_empty():
			secondary.append("Route fail: %s" % _short(route_fail, 32))
		chunks.append(_bb_secondary("\n".join(secondary)))

	## Silence unused tree warning while keeping signature stable for future scans.
	if tree == null:
		pass
	return "\n".join(chunks)


func _derive_idle_reason(
	unit: Unit,
	ownership: String,
	mission_label: String,
	nav: Dictionary
) -> String:
	if ownership in ["no_squad", "pending_reinforcement", "reinforcement_pool"]:
		return "no squad"
	if ownership == "defense_reserved":
		return "defense reserved"
	if ownership == "stale_squad":
		return "mission mismatch"
	if String(nav.get("blocked", "NO")) == "YES":
		return "navigation blocked"
	if mission_label == "RALLY":
		return "waiting regroup"
	if unit.get_active_order() == null:
		return "no order"
	return "UNKNOWN"


func _resolve_inspected_unit(selection: Node) -> Unit:
	if selection == null:
		return null
	if selection.has_method("get_valid_selected_units"):
		var selected: Array = selection.call("get_valid_selected_units")
		for entry: Variant in selected:
			if entry is Unit and NodeSafety.is_alive_node(entry):
				return entry as Unit
	var inspected: Variant = selection.get("inspected_unit")
	if inspected is Unit and NodeSafety.is_alive_node(inspected):
		return inspected as Unit
	return null


func _read_attack_target_name(unit: Unit) -> String:
	if not unit is MilitaryUnit:
		return "-"
	var target: Variant = unit.get("_attack_target")
	if NodeSafety.is_alive_node(target):
		return (target as Node).name
	return "NONE"


func _read_nav_state(unit: Unit) -> Dictionary:
	var result: Dictionary = {
		"path_state": "-",
		"path_points": 0,
		"waypoint": "-",
		"blocked": "NO",
		"blocker": "-",
		"repath_pending": "UNKNOWN",
		"repath_reason": "UNKNOWN",
	}
	var agent: NavigationAgent3D = unit.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent == null:
		result["path_state"] = "NO AGENT"
		return result

	var path: PackedVector3Array = agent.get_current_navigation_path()
	result["path_points"] = path.size()
	if path.is_empty():
		if unit.has_move_target:
			result["path_state"] = "NO PATH"
		else:
			result["path_state"] = "IDLE"
	elif agent.is_navigation_finished():
		result["path_state"] = "FINISHED"
	elif not agent.is_target_reachable():
		result["path_state"] = "UNREACHABLE"
		result["blocked"] = "YES"
	else:
		result["path_state"] = "FOLLOWING"

	if path.size() > 0:
		var next_pos: Vector3 = agent.get_next_path_position()
		result["waypoint"] = "(%.0f, %.0f)" % [next_pos.x, next_pos.z]

	var squad_ctx: SquadNavContext = null
	if SharedSquadNavigation != null:
		squad_ctx = SharedSquadNavigation.get_squad_for_unit(unit)
	if squad_ctx != null:
		if not squad_ctx.route_failure_reason.is_empty():
			result["repath_reason"] = squad_ctx.route_failure_reason
			if squad_ctx.route_failure_reason.contains("project"):
				result["path_state"] = "NAV PROJECTION INVALID"
			elif squad_ctx.route_failure_reason.contains("no_path"):
				result["path_state"] = "NO PATH"
		if not squad_ctx.route_valid:
			result["blocked"] = "YES"
	return result


func _read_combat_state(unit: Unit) -> Dictionary:
	var result: Dictionary = {
		"state": "-",
		"target": "NONE",
		"target_type": "-",
		"target_alive": "-",
		"hostile": "-",
		"distance": "-",
		"range": "-",
		"in_range": "-",
		"cooldown": "-",
		"can_attack": "-",
	}
	if not unit is MilitaryUnit:
		result["state"] = "non-military"
		return result
	var mu: MilitaryUnit = unit as MilitaryUnit
	var target: Variant = mu.get("_attack_target")
	var attack_range: float = float(mu.get("attack_range"))
	result["range"] = "%.1f" % attack_range
	result["cooldown"] = "%.2f" % float(mu.get("_attack_cooldown_timer"))
	if bool(mu.get("_is_holding_position")):
		result["state"] = "HOLD"
	elif bool(mu.get("_has_attack_move_destination")):
		result["state"] = "ATTACK_MOVE"
	elif bool(mu.get("_has_active_attack_order")):
		result["state"] = "ATTACK"
	elif unit.is_movement_active():
		result["state"] = "MOVE"
	else:
		result["state"] = "IDLE"

	if NodeSafety.is_alive_node(target):
		var tnode: Node3D = target as Node3D
		result["target"] = tnode.name
		result["target_type"] = tnode.get_class()
		result["target_alive"] = "YES"
		var dist: float = EnemyArmyCommand.horizontal_distance(unit.global_position, tnode.global_position)
		result["distance"] = "%.1f" % dist
		result["in_range"] = "YES" if dist <= attack_range + 0.15 else "NO"
		result["can_attack"] = result["in_range"]
		var hostile: bool = false
		if tnode is Unit:
			hostile = (tnode as Unit).team_id != unit.team_id
		elif tnode is Building:
			hostile = (tnode as Building).team_id != unit.team_id
		result["hostile"] = "YES" if hostile else "NO"
	else:
		result["target_alive"] = "NO"
	return result


func _note_events(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var state: String = String(snap.get("state", ""))
	var mission: String = String(snap.get("mission", ""))
	var reason: String = String(snap.get("transition_reason", ""))
	var exec_label: String = String(snap.get("executable", ""))
	var hero_with: bool = bool(snap.get("hero_with_main", false))
	var last_order: String = String(snap.get("last_order_label", ""))

	if not _prev_state.is_empty() and state != _prev_state:
		_push_event(now, "%s > %s" % [_short_event_token(_prev_state), _short_event_token(state)])
	elif not _prev_mission.is_empty() and mission != _prev_mission:
		_push_event(now, "%s > %s" % [_short_event_token(_prev_mission), _short_event_token(mission)])
	if not reason.is_empty() and reason != _prev_reason and state != _prev_state:
		_push_event(now, "why %s" % _short(reason, 28))
	if _prev_hero_with_main != hero_with:
		_push_event(now, "Hero > MAIN" if hero_with else "Hero < MAIN")
	if not last_order.is_empty() and last_order != _prev_last_order:
		_push_event(now, _short_order_event(last_order))
		_order_replace_times.append(now)
	if not exec_label.is_empty() and exec_label != _prev_exec:
		_push_event(now, _short_event_token(exec_label))

	_prev_state = state
	_prev_mission = mission
	_prev_reason = reason
	_prev_hero_with_main = hero_with
	_prev_exec = exec_label
	_prev_last_order = last_order


func _short_event_token(text: String) -> String:
	var t: String = text.strip_edges()
	if t.is_empty():
		return "-"
	t = t.replace("ATTACK_MOVE", "ATKMOV").replace("DEFEND", "DEFEND")
	if t.length() <= 12:
		return t.to_upper()
	return t.substr(0, 12).to_upper()


func _short_order_event(label: String) -> String:
	var t: String = label.strip_edges()
	if t.to_lower().contains("creep"):
		return "CREEP > ATTACK" if t.to_lower().contains("attack") else "CREEP"
	if t.to_lower().contains("defend"):
		return "DEFEND ON"
	if t.to_lower().begins_with("target"):
		return _short(t, 22)
	if t.to_lower().contains("attack"):
		return "ATTACK"
	return _short(t, 22)


func _push_event(now: float, message: String) -> void:
	_event_feed.push_front({"t": now, "msg": message})
	while _event_feed.size() > EVENT_FEED_MAX:
		_event_feed.pop_back()


func _prune_events() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var kept: Array = []
	for entry: Variant in _event_feed:
		if entry is Dictionary and now - float((entry as Dictionary).get("t", 0.0)) <= EVENT_AGE_SECONDS:
			kept.append(entry)
	_event_feed = kept
	var kept_times: Array = []
	for t: Variant in _order_replace_times:
		if now - float(t) <= 2.0:
			kept_times.append(t)
	_order_replace_times = kept_times


func _count_order_replacements_2s() -> int:
	_prune_events()
	return _order_replace_times.size()


func _ensure_world_root() -> void:
	if _world_root != null and is_instance_valid(_world_root):
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return
	_world_root = Node3D.new()
	_world_root.name = "RtsAiDebugWorld"
	tree.current_scene.add_child(_world_root)
	_path_mesh = MeshInstance3D.new()
	_path_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root.add_child(_path_mesh)


func _teardown_world_debug() -> void:
	if _world_root != null and is_instance_valid(_world_root):
		_world_root.queue_free()
	_world_root = null
	_path_mesh = null
	_label_pool.clear()


func _update_world_labels(
	tree: SceneTree,
	director: MilitaryDirectorV2,
	selection: Node,
	snap: Dictionary
) -> void:
	_ensure_world_root()
	if _world_root == null:
		return
	for label: Variant in _label_pool:
		if label is Label3D and is_instance_valid(label):
			(label as Label3D).visible = false

	var used: int = 0
	var selected: Unit = _resolve_inspected_unit(selection)
	if selected != null:
		used = _show_unit_marker(used, selected, "SEL", Color(1.0, 0.85, 0.2))

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero != null:
		var mission_abbr: String = String(snap.get("state", "?"))
		if mission_abbr.length() > 3:
			mission_abbr = mission_abbr.substr(0, 3)
		used = _show_unit_marker(
			used,
			hero,
			"H %s" % mission_abbr,
			Color(0.4, 0.9, 1.0)
		)

	if director == null:
		return
	var roster: Array = director.get_roster_copy()
	for entry: Variant in roster:
		if used >= WORLD_LABEL_MAX:
			break
		if not entry is Unit or not NodeSafety.is_alive_node(entry):
			continue
		var unit: Unit = entry as Unit
		if unit == selected or unit == hero:
			continue
		var ownership: String = director.classify_unit_ownership_for_diagnostics(unit)
		var mark: String = ""
		var color := Color(0.8, 0.8, 0.8)
		match ownership:
			"in_main_squad":
				continue
			"defense_reserved":
				mark = "D"
				color = Color(1.0, 0.45, 0.35)
			"pending_reinforcement", "reinforcement_pool", "no_squad":
				mark = "?"
				color = Color(1.0, 0.85, 0.2)
			"stale_squad", "mission_owned":
				mark = "R"
				color = Color(1.0, 0.6, 0.1)
			_:
				continue
		used = _show_unit_marker(used, unit, mark, color)


func _show_unit_marker(index: int, unit: Unit, text: String, color: Color) -> int:
	while _label_pool.size() <= index:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 28
		label.pixel_size = 0.012
		label.outline_size = 4
		label.modulate = Color(1, 1, 1, 0.85)
		_world_root.add_child(label)
		_label_pool.append(label)
	var marker: Label3D = _label_pool[index] as Label3D
	marker.visible = true
	marker.text = text
	marker.modulate = color
	marker.global_position = unit.global_position + Vector3(0.0, 2.4, 0.0)
	return index + 1


func _update_selected_path_viz() -> void:
	if not _visible_overlay or _path_mesh == null or not is_instance_valid(_path_mesh):
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var composition: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	var selection: Node = composition.selection_manager if composition != null else null
	var unit: Unit = _resolve_inspected_unit(selection)
	var im := ImmediateMesh.new()
	if unit == null:
		_path_mesh.mesh = im
		return

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var dest: Vector3 = unit.get_movement_destination()
	if unit.has_move_target and dest != Vector3.ZERO:
		_add_debug_line(im, unit.global_position + Vector3(0, 0.4, 0), dest + Vector3(0, 0.4, 0), Color(0.2, 1.0, 0.4))
	var agent: NavigationAgent3D = unit.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		var path: PackedVector3Array = agent.get_current_navigation_path()
		for i: int in range(path.size() - 1):
			_add_debug_line(
				im,
				path[i] + Vector3(0, 0.35, 0),
				path[i + 1] + Vector3(0, 0.35, 0),
				Color(0.3, 0.75, 1.0, 0.85)
			)
		if path.size() > 0:
			var wp: Vector3 = agent.get_next_path_position()
			_add_debug_line(
				im,
				unit.global_position + Vector3(0, 0.5, 0),
				wp + Vector3(0, 0.5, 0),
				Color(1.0, 0.9, 0.2)
			)
	var vel: Vector3 = unit.velocity
	if vel.length() > 0.05:
		var dir: Vector3 = Vector3(vel.x, 0.0, vel.z)
		if dir.length() > 0.01:
			dir = dir.normalized() * 2.0
			_add_debug_line(
				im,
				unit.global_position + Vector3(0, 0.6, 0),
				unit.global_position + dir + Vector3(0, 0.6, 0),
				Color(1.0, 0.3, 0.8)
			)
	im.surface_end()
	_path_mesh.mesh = im


func _add_debug_line(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	im.surface_set_color(color)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)


func _short(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len - 1) + "…"


func _format_age(age: float) -> String:
	if age >= INF or age < 0.0:
		return "-"
	return "%.1fs" % age
