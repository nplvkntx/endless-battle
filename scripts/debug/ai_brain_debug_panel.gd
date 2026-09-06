extends CanvasLayer

## Compact in-game EnemyAI brain panel. EnemyAI is the authority; this only displays.

const PANEL_WIDTH_FRACTION := 0.23
const PANEL_HEIGHT_FRACTION := 0.42
const PANEL_HEIGHT_MAX_FRACTION := 0.48
const TOP_MARGIN := 44.0
const SIDE_MARGIN := 8.0

var _panel: PanelContainer
var _summary_label: Label
var _events_label: Label


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide_panel()
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()


func show_panel() -> void:
	visible = true
	if _panel != null:
		_panel.visible = true


func hide_panel() -> void:
	visible = false
	if _panel != null:
		_panel.visible = false


func set_summary_text(text: String) -> void:
	if _summary_label != null:
		_summary_label.text = text


func set_events_text(text: String) -> void:
	if _events_label != null:
		_events_label.text = text


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.07, 0.10, 0.78)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.32, 0.62, 0.78, 0.85)
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 4)
	_panel.add_child(root)

	_summary_label = Label.new()
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_label_style(_summary_label, 12)
	_summary_label.text = "AI BRAIN\n(waiting for tick)"
	root.add_child(_summary_label)

	var events_scroll := ScrollContainer.new()
	events_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	events_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	events_scroll.custom_minimum_size = Vector2(0, 72)
	events_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(events_scroll)

	_events_label = Label.new()
	_events_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_events_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_events_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_label_style(_events_label, 11)
	_events_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92, 1))
	_events_label.text = ""
	events_scroll.add_child(_events_label)

	add_child(_panel)


func _apply_label_style(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.90, 0.95, 0.98, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	label.add_theme_constant_override("outline_size", 3)


func _layout_panel() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var width: float = clampf(viewport_size.x * PANEL_WIDTH_FRACTION, 280.0, 460.0)
	var height: float = clampf(
		viewport_size.y * PANEL_HEIGHT_FRACTION,
		220.0,
		viewport_size.y * PANEL_HEIGHT_MAX_FRACTION
	)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -width - SIDE_MARGIN
	_panel.offset_top = TOP_MARGIN
	_panel.offset_right = -SIDE_MARGIN
	_panel.offset_bottom = TOP_MARGIN + height
