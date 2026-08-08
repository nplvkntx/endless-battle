extends CanvasLayer

## Development-only RTS AI / unit / order / nav / combat diagnostics.
## Toggle with O. Default OFF. READ-ONLY — never issues orders or mutates AI state.
## Separate from F3 performance overlay.

const TOGGLE_KEY := KEY_O
const REFRESH_INTERVAL_SECONDS := 0.22
const EVENT_FEED_MAX := 7
const EVENT_AGE_SECONDS := 18.0
const WORLD_LABEL_MAX := 14

var _panel: PanelContainer
var _label: Label
var _unit_panel: PanelContainer
var _unit_label: Label
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


func _ready() -> void:
	layer = 126
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
	_update_panels()


func hide_overlay() -> void:
	_visible_overlay = false
	_panel.visible = false
	_unit_panel.visible = false
	set_process(false)
	_teardown_world_debug()


func is_overlay_visible() -> bool:
	return _visible_overlay


func _build_ui() -> void:
	_panel = _make_panel(Color(0.05, 0.08, 0.12, 0.90), Color(0.35, 0.65, 0.85, 1.0))
	_label = _make_label(12)
	_panel.add_child(_label)
	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -10.0
	_panel.offset_top = 10.0
	_panel.offset_left = -420.0
	_panel.offset_bottom = 420.0
	_panel.custom_minimum_size = Vector2(360, 0)

	_unit_panel = _make_panel(Color(0.06, 0.05, 0.08, 0.90), Color(0.85, 0.55, 0.35, 1.0))
	_unit_label = _make_label(11)
	_unit_panel.add_child(_unit_label)
	add_child(_unit_panel)
	_unit_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_unit_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_unit_panel.offset_right = -10.0
	_unit_panel.offset_top = 430.0
	_unit_panel.offset_left = -420.0
	_unit_panel.custom_minimum_size = Vector2(360, 0)
	_panel.visible = false
	_unit_panel.visible = false


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
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.88, 0.93, 0.96, 1.0))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _update_panels() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		_label.text = "RTS AI Debug (O)\n(no scene tree)"
		_unit_label.text = ""
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
	_label.text = _format_global_panel(snap, commander)
	_unit_label.text = _format_unit_panel(tree, selection, director, snap)
	_update_world_labels(tree, director, selection, snap)


func _format_global_panel(snap: Dictionary, commander: ArmyCommanderV2) -> String:
	if snap.is_empty():
		return "RTS AI Debug (O)\nAI BRAIN\n(V2 director unavailable)"

	var lines: PackedStringArray = PackedStringArray([
		"RTS AI Debug (O)",
		"AI BRAIN",
		"Mission: %s" % String(snap.get("mission", "-")),
		"State: %s" % String(snap.get("state", "-")),
		"Prev reason: %s" % _short(_prev_reason if not _prev_reason.is_empty() else String(snap.get("transition_reason", "-")), 42),
		"Objective: %s" % String(snap.get("objective", "-")),
		"Mission age: %.1fs" % float(snap.get("mission_age", 0.0)),
		"Objective valid: %s" % ("YES" if bool(snap.get("objective_valid", false)) else "NO"),
		"",
		"HERO: %s L%d HP=%d%%" % [
			String(snap.get("hero_name", "-")),
			int(snap.get("hero_level", 0)),
			int(round(float(snap.get("hero_hp_ratio", 0.0)) * 100.0)),
		],
		"state=%s squad=%s" % [
			String(snap.get("hero_state", "-")),
			"MAIN" if bool(snap.get("hero_with_main", false)) else "NO",
		],
		"WITH MAIN ARMY: %s" % ("YES" if bool(snap.get("hero_with_main", false)) else "NO"),
	])
	if not bool(snap.get("hero_with_main", false)):
		var away: String = String(snap.get("hero_away_reason", "unknown")).to_upper()
		if away.is_empty():
			away = "UNKNOWN"
		lines.append("reason=%s" % away)
	var dist: float = float(snap.get("hero_dist_main", -1.0))
	if dist >= 0.0:
		lines.append("distance_to_main: %.1f" % dist)

	lines.append("")
	lines.append(
		"Army alive:%d avail:%d main:%d def:%d other:%d unassign:%d idle:%d" % [
			int(snap.get("combat_alive", 0)),
			int(snap.get("combat_available", 0)),
			int(snap.get("main_squad", 0)),
			int(snap.get("defense_reserved", 0)),
			int(snap.get("other_owned", 0)),
			int(snap.get("unassigned", 0)),
			int(snap.get("idle_military", 0)),
		]
	)
	lines.append("Pending: %d  Roles: %s" % [
		int(snap.get("pending", 0)),
		String(snap.get("role_counts", "-")),
	])
	lines.append("IDLE MILITARY: %d" % int(snap.get("idle_military", 0)))
	lines.append("")
	lines.append("POWER")
	lines.append(
		"Director avail: %d  Power: %.0f" % [
			int(snap.get("director_unit_count", 0)),
			float(snap.get("director_power", 0.0)),
		]
	)
	lines.append(
		"Commander squad: %d  Power: %.0f" % [
			int(snap.get("commander_unit_count", 0)),
			float(snap.get("commander_power", 0.0)),
		]
	)
	lines.append(
		"Player power: %.0f  Ratio: %.2f" % [
			float(snap.get("player_power", 0.0)),
			float(snap.get("power_ratio", 0.0)),
		]
	)
	lines.append("Mismatch: %.0f" % float(snap.get("power_mismatch", 0.0)))
	lines.append("")
	lines.append("Decision: %s" % String(snap.get("state", "-")))
	lines.append("Why: %s" % _short(String(snap.get("transition_reason", "-")), 48))
	var decision_lines: Variant = snap.get("decision_lines", PackedStringArray())
	if decision_lines is PackedStringArray:
		for line: String in decision_lines:
			lines.append(line)
	elif decision_lines is Array:
		for entry: Variant in decision_lines:
			lines.append(str(entry))
	lines.append("prefer_early_creep=%s interrupt_atk=%s" % [
		str(bool(snap.get("prefer_early_creep", false))),
		str(bool(snap.get("interrupt_for_attack", false))),
	])
	lines.append("")
	lines.append("Commander: %s" % String(snap.get("executable", "-")))
	lines.append("Exec reason: %s" % _short(String(snap.get("executable_reason", "-")), 40))
	lines.append("Authority: %s" % String(snap.get("authority", "UNKNOWN")))
	var idle_s: float = float(snap.get("commander_idle_seconds", 0.0))
	if commander != null:
		idle_s = commander.get_squad_idle_seconds()
	lines.append("Squad idle: %.1fs" % idle_s)

	lines.append("")
	lines.append("DEFENSE")
	lines.append("Threat: %s  target=%s" % [
		"YES" if bool(snap.get("threat_active", false)) else "NO",
		String(snap.get("threat_target", "-")),
	])
	lines.append(
		"ThreatP:%.0f DefP:%.0f mission=%s hero_def=%s" % [
			float(snap.get("threat_power", 0.0)),
			float(snap.get("defense_power", 0.0)),
			String(snap.get("defend_reason", "-")) if bool(snap.get("defend_active", false)) else "-",
			"YES" if bool(snap.get("hero_defending", false)) else "NO",
		]
	)
	lines.append("Defenders assigned: %d" % int(snap.get("defense_reserved", 0)))

	var state_name: String = String(snap.get("state", ""))
	if state_name == "CREEP" or not String(snap.get("creep_block", "")).is_empty():
		lines.append("")
		lines.append("CREEP")
		lines.append("Camp: %s alive=%s dist=%.1f" % [
			String(snap.get("camp", "-")),
			"YES" if bool(snap.get("camp_alive", false)) else "NO",
			float(snap.get("camp_distance", -1.0)),
		])
		lines.append(
			"Ready=%s squad=%d hero_in=%s cleared=%d" % [
				str(bool(snap.get("creep_ready", false))),
				int(snap.get("main_squad", 0)),
				"YES" if bool(snap.get("hero_with_main", false)) else "NO",
				int(snap.get("cleared_camps", 0)),
			]
		)
		var creep_block: String = String(snap.get("creep_block", ""))
		if not creep_block.is_empty():
			lines.append("Block: %s" % _short(creep_block, 48))

	if state_name == "ATTACK":
		lines.append("")
		lines.append("ATTACK")
		lines.append("Target: %s" % String(snap.get("objective", "-")))
		lines.append(
			"Squad:%d hero=%s power:%.0f moving:%d idle:%d targets:%d" % [
				int(snap.get("attack_members", 0)),
				"YES" if bool(snap.get("hero_with_main", false)) else "NO",
				float(snap.get("director_power", 0.0)),
				int(snap.get("attack_moving", 0)),
				int(snap.get("attack_idle", 0)),
				int(snap.get("attack_with_targets", 0)),
			]
		)
		var atk_block: String = String(snap.get("attack_block", ""))
		if not atk_block.is_empty():
			lines.append("Block: %s" % _short(atk_block, 48))

	lines.append("")
	lines.append("LAST ORDER: %s age=%s" % [
		String(snap.get("last_order_label", "-")),
		_format_age(float(snap.get("last_order_age", INF))),
	])
	lines.append("Order source: UNKNOWN")
	var replacements: int = _count_order_replacements_2s()
	lines.append("ORDER REPLACEMENTS (2s): %d" % replacements)
	## Without durable per-issuer metadata, never claim CONFLICT: YES.
	lines.append("CONFLICT: UNKNOWN")

	lines.append("")
	lines.append("EVENTS")
	_prune_events()
	if _event_feed.is_empty():
		lines.append("(none)")
	else:
		for entry: Variant in _event_feed:
			if entry is Dictionary:
				lines.append(
					"%.1f %s" % [
						float((entry as Dictionary).get("t", 0.0)),
						String((entry as Dictionary).get("msg", "")),
					]
				)

	return "\n".join(lines)


func _format_unit_panel(
	tree: SceneTree,
	selection: Node,
	director: MilitaryDirectorV2,
	snap: Dictionary
) -> String:
	var unit: Unit = _resolve_inspected_unit(selection)
	if unit == null:
		return "UNIT DEBUG\n(select a unit)"

	var lines: PackedStringArray = PackedStringArray([
		"UNIT DEBUG",
		"%s #%d" % [unit.name, unit.get_instance_id()],
		"Team: %d  Type: %s" % [unit.team_id, unit.get_class()],
	])
	var hp_text: String = "-"
	if unit is MilitaryUnit:
		var mu: MilitaryUnit = unit as MilitaryUnit
		hp_text = str(mu.get_current_health())
	elif unit.get("_current_health") != null:
		hp_text = "%.0f/%.0f" % [
			float(unit.get("_current_health")),
			float(unit.get("_max_health")),
		]
	lines.append("HP: %s" % hp_text)

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

	lines.append("AI owner: %s" % ownership)
	lines.append("Squad: %s" % squad_label)
	lines.append("Mission: %s" % mission_label)

	var order: UnitOrder = unit.get_active_order()
	var order_text: String = "NONE"
	var order_target: String = "-"
	if order != null:
		order_text = order.describe()
		var alive_t: Node3D = order.get_alive_target()
		if alive_t != null:
			order_target = alive_t.name
	lines.append("Current order: %s" % order_text)
	lines.append("Current objective: %s" % String(snap.get("objective", "-")))
	lines.append("Attack target: %s" % _read_attack_target_name(unit))

	var dest: Vector3 = unit.get_movement_destination()
	var dist_rem: float = -1.0
	if unit.has_move_target and dest != Vector3.ZERO:
		dist_rem = EnemyArmyCommand.horizontal_distance(unit.global_position, dest)
	lines.append(
		"Move dest: %s" % (
			"(%.0f, %.0f)" % [dest.x, dest.z] if unit.has_move_target else "-"
		)
	)
	lines.append("Distance remaining: %s" % ("%.1f" % dist_rem if dist_rem >= 0.0 else "-"))

	var nav: Dictionary = _read_nav_state(unit)
	lines.append("")
	lines.append("NAV")
	lines.append("Path state: %s" % String(nav.get("path_state", "-")))
	lines.append("Path points: %d" % int(nav.get("path_points", 0)))
	lines.append("Waypoint: %s" % String(nav.get("waypoint", "-")))
	lines.append("Blocked: %s" % String(nav.get("blocked", "NO")))
	lines.append("Blocker: %s" % String(nav.get("blocker", "-")))
	lines.append(
		"Moving: %s  Vel: %.1f" % [
			"yes" if unit.is_movement_active() else "no",
			unit.velocity.length(),
		]
	)
	lines.append(
		"Stuck: %s  time=%.2f" % [
			"yes" if unit.is_confirmed_stuck() else "no",
			float(unit.get("_stuck_time")),
		]
	)
	lines.append("Repath pending: %s" % String(nav.get("repath_pending", "UNKNOWN")))
	lines.append("Last repath reason: %s" % String(nav.get("repath_reason", "UNKNOWN")))
	var route_fail: String = EnemyArmyCommand.get_last_squad_route_failure_reason()
	if not route_fail.is_empty():
		lines.append("Squad route fail: %s" % route_fail)

	lines.append("")
	lines.append("COMBAT")
	var combat: Dictionary = _read_combat_state(unit)
	lines.append("State: %s" % String(combat.get("state", "-")))
	lines.append("Target: %s" % String(combat.get("target", "NONE")))
	lines.append("Target type: %s" % String(combat.get("target_type", "-")))
	lines.append("Target alive: %s" % String(combat.get("target_alive", "-")))
	lines.append("Hostile: %s" % String(combat.get("hostile", "-")))
	lines.append("Distance: %s" % String(combat.get("distance", "-")))
	lines.append("Attack range: %s" % String(combat.get("range", "-")))
	lines.append("In range: %s" % String(combat.get("in_range", "-")))
	lines.append("Cooldown: %s" % String(combat.get("cooldown", "-")))
	lines.append("Can attack: %s" % String(combat.get("can_attack", "-")))
	lines.append("Last damage time: UNKNOWN")

	lines.append("")
	lines.append("LAST ORDER:")
	lines.append("source=UNKNOWN")
	lines.append("type=%s" % order_text)
	lines.append("target=%s" % order_target)
	lines.append("age=UNKNOWN")
	lines.append("PREVIOUS ORDER: UNKNOWN")
	lines.append("Order replacements (2s): %d" % _count_order_replacements_2s())
	lines.append("CONFLICT: UNKNOWN")

	if (
		int(snap.get("idle_military", 0)) > 0
		and not unit.is_movement_active()
		and order == null
	):
		lines.append("")
		lines.append("Idle reason: %s" % _derive_idle_reason(unit, ownership, mission_label, nav))

	## Silence unused tree warning while keeping signature stable for future scans.
	if tree == null:
		pass
	return "\n".join(lines)


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
		_push_event(now, "%s → %s" % [_prev_state, state])
	elif not _prev_mission.is_empty() and mission != _prev_mission:
		_push_event(now, "mission %s → %s" % [_prev_mission, mission])
	if not reason.is_empty() and reason != _prev_reason and state != _prev_state:
		_push_event(now, "why: %s" % _short(reason, 36))
	if _prev_hero_with_main != hero_with:
		_push_event(now, "hero %s MAIN" % ("joined" if hero_with else "left"))
	if not last_order.is_empty() and last_order != _prev_last_order:
		_push_event(now, "order %s" % last_order)
		_order_replace_times.append(now)
	if not exec_label.is_empty() and exec_label != _prev_exec:
		_push_event(now, "exec %s" % exec_label)

	_prev_state = state
	_prev_mission = mission
	_prev_reason = reason
	_prev_hero_with_main = hero_with
	_prev_exec = exec_label
	_prev_last_order = last_order


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
