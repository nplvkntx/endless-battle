extends CanvasLayer

## Global custom tooltip overlay. Does not block mouse input.

const OFFSET := Vector2(16, 20)
const SCREEN_MARGIN := 8
const PANEL_MAX_WIDTH := 280

var _panel: PanelContainer
var _label: Label
var _follow_mouse: bool = false
var _anchor_control: Control = null
var _world_hover_active: bool = false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide_tooltip()


func _process(_delta: float) -> void:
	if not _panel.visible:
		return

	if _follow_mouse:
		_position_at_mouse()
	elif _anchor_control != null and is_instance_valid(_anchor_control):
		_position_near_control(_anchor_control)


func show_tooltip(text: String, anchor: Variant = null) -> void:
	if text.is_empty():
		hide_tooltip()
		return

	_world_hover_active = anchor == null
	_label.text = text
	_panel.visible = true
	_panel.reset_size()

	if anchor is Control:
		_anchor_control = anchor as Control
		_follow_mouse = false
		_position_near_control(_anchor_control)
	else:
		_anchor_control = null
		_follow_mouse = true
		_position_at_mouse()


func hide_tooltip() -> void:
	_panel.visible = false
	_follow_mouse = false
	_anchor_control = null
	_world_hover_active = false


func hide_world_tooltip() -> void:
	if _world_hover_active:
		hide_tooltip()


func is_showing_world_tooltip() -> bool:
	return _world_hover_active and _panel.visible


func bind_control(control: Control, text_callback: Callable) -> void:
	if control == null:
		return

	var hover_area: Control = _ensure_hover_area(control)
	if hover_area.has_meta("tooltip_bound"):
		return

	hover_area.set_meta("tooltip_bound", true)
	hover_area.mouse_entered.connect(
		func() -> void:
			var text: String = String(text_callback.call())
			show_tooltip(text, control)
	)
	hover_area.mouse_exited.connect(
		func() -> void:
			if _anchor_control == control:
				hide_tooltip()
	)


func bind_static_tooltip(control: Control, text: String) -> void:
	bind_control(control, func() -> String: return text)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.08, 0.94)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.35, 0.38, 0.42, 1)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(PANEL_MAX_WIDTH, 0)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95, 1))
	_panel.add_child(_label)


func _ensure_hover_area(control: Control) -> Control:
	var existing: Node = control.get_node_or_null("TooltipHoverArea")
	if existing is Control:
		return existing as Control

	var hover_area := Control.new()
	hover_area.name = "TooltipHoverArea"
	hover_area.mouse_filter = Control.MOUSE_FILTER_PASS
	hover_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	hover_area.anchor_right = 1.0
	hover_area.anchor_bottom = 1.0
	hover_area.offset_right = 0.0
	hover_area.offset_bottom = 0.0
	control.add_child(hover_area)
	control.move_child(hover_area, control.get_child_count() - 1)
	return hover_area


func _position_at_mouse() -> void:
	_position_panel(get_viewport().get_mouse_position() + OFFSET)


func _position_near_control(control: Control) -> void:
	var control_rect: Rect2 = control.get_global_rect()
	var anchor_position := Vector2(control_rect.position.x, control_rect.end.y + 4.0)
	_position_panel(anchor_position)


func _position_panel(desired_position: Vector2) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.reset_size()

	var panel_size: Vector2 = _panel.get_combined_minimum_size()
	var position := desired_position

	if position.x + panel_size.x > viewport_size.x - SCREEN_MARGIN:
		position.x = viewport_size.x - panel_size.x - SCREEN_MARGIN
	if position.y + panel_size.y > viewport_size.y - SCREEN_MARGIN:
		position.y = desired_position.y - panel_size.y - OFFSET.y

	position.x = maxf(SCREEN_MARGIN, position.x)
	position.y = maxf(SCREEN_MARGIN, position.y)
	_panel.position = position
