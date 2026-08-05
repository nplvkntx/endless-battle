extends Control

## Display / UI settings panel. Drafts changes until Apply; Cancel restores controls.

signal closed()

@onready var _display_mode_option: OptionButton = %DisplayModeOption
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _ui_scale_option: OptionButton = %UIScaleOption
@onready var _vsync_check: CheckButton = %VSyncCheck
@onready var _fps_limit_option: OptionButton = %FPSLimitOption
@onready var _apply_button: Button = %ApplyButton
@onready var _cancel_button: Button = %CancelButton
@onready var _reset_button: Button = %ResetDefaultsButton
@onready var _close_button: Button = %CloseButton
@onready var _status_label: Label = %StatusLabel

var _resolution_values: Array = []
var _ui_scale_values: Array = []
var _fps_limit_values: Array = []
var _suppress_refresh: bool = false


func _ready() -> void:
	visible = false
	_display_mode_option.item_selected.connect(_on_draft_changed)
	_resolution_option.item_selected.connect(_on_draft_changed)
	_ui_scale_option.item_selected.connect(_on_immediate_ui_scale)
	_vsync_check.toggled.connect(_on_immediate_vsync)
	_fps_limit_option.item_selected.connect(_on_immediate_fps)
	_apply_button.pressed.connect(_on_apply_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	if not GameSettings.display_settings_changed.is_connected(_on_settings_changed):
		GameSettings.display_settings_changed.connect(_on_settings_changed)
	if not GameSettings.display_confirm_finished.is_connected(_on_confirm_finished):
		GameSettings.display_confirm_finished.connect(_on_confirm_finished)


func open_panel() -> void:
	_rebuild_options()
	_sync_controls_from_settings()
	_status_label.text = "Adjust display settings, then Apply."
	visible = true


func close_panel() -> void:
	visible = false
	closed.emit()


func _on_settings_changed() -> void:
	if not visible or _suppress_refresh:
		return
	_rebuild_options()
	_sync_controls_from_settings()


func _on_confirm_finished(kept: bool) -> void:
	if not visible:
		return
	_rebuild_options()
	_sync_controls_from_settings()
	if kept:
		_status_label.text = "Display settings saved."
	else:
		_status_label.text = "Display settings reverted."


func _rebuild_options() -> void:
	_suppress_refresh = true

	_display_mode_option.clear()
	_display_mode_option.add_item(GameSettings.display_mode_label(GameSettings.DisplayMode.WINDOWED), GameSettings.DisplayMode.WINDOWED)
	_display_mode_option.add_item(
		GameSettings.display_mode_label(GameSettings.DisplayMode.BORDERLESS_FULLSCREEN),
		GameSettings.DisplayMode.BORDERLESS_FULLSCREEN
	)
	_display_mode_option.add_item(
		GameSettings.display_mode_label(GameSettings.DisplayMode.EXCLUSIVE_FULLSCREEN),
		GameSettings.DisplayMode.EXCLUSIVE_FULLSCREEN
	)

	_resolution_values = GameSettings.get_supported_resolutions()
	_resolution_option.clear()
	for i: int in range(_resolution_values.size()):
		var res: Vector2i = _resolution_values[i]
		_resolution_option.add_item("%d × %d" % [res.x, res.y], i)

	_ui_scale_values = GameSettings.get_ui_scale_options()
	_ui_scale_option.clear()
	for i: int in range(_ui_scale_values.size()):
		var scale_value: float = float(_ui_scale_values[i])
		_ui_scale_option.add_item(GameSettings.ui_scale_label(scale_value), i)

	_fps_limit_values = GameSettings.get_fps_limit_options()
	_fps_limit_option.clear()
	for i: int in range(_fps_limit_values.size()):
		var limit: int = int(_fps_limit_values[i])
		_fps_limit_option.add_item(GameSettings.fps_limit_label(limit), i)

	_suppress_refresh = false


func _sync_controls_from_settings() -> void:
	_suppress_refresh = true
	_select_id(_display_mode_option, GameSettings.display_mode)

	var res_index: int = 0
	for i: int in range(_resolution_values.size()):
		var res: Vector2i = _resolution_values[i]
		if res.x == GameSettings.resolution_width and res.y == GameSettings.resolution_height:
			res_index = i
			break
	_resolution_option.select(res_index)

	var scale_index: int = 0
	for i: int in range(_ui_scale_values.size()):
		if is_equal_approx(float(_ui_scale_values[i]), GameSettings.ui_scale):
			scale_index = i
			break
	_ui_scale_option.select(scale_index)

	_vsync_check.button_pressed = GameSettings.vsync_enabled

	var fps_index: int = 0
	for i: int in range(_fps_limit_values.size()):
		if int(_fps_limit_values[i]) == GameSettings.fps_limit:
			fps_index = i
			break
	_fps_limit_option.select(fps_index)
	_suppress_refresh = false


func _select_id(option: OptionButton, id: int) -> void:
	for i: int in range(option.item_count):
		if option.get_item_id(i) == id:
			option.select(i)
			return
	if option.item_count > 0:
		option.select(0)


func _draft_mode() -> int:
	return _display_mode_option.get_selected_id()


func _draft_resolution() -> Vector2i:
	var index: int = _resolution_option.selected
	if index < 0 or index >= _resolution_values.size():
		return Vector2i(GameSettings.resolution_width, GameSettings.resolution_height)
	return _resolution_values[index]


func _draft_ui_scale() -> float:
	var index: int = _ui_scale_option.selected
	if index < 0 or index >= _ui_scale_values.size():
		return GameSettings.ui_scale
	return float(_ui_scale_values[index])


func _draft_fps_limit() -> int:
	var index: int = _fps_limit_option.selected
	if index < 0 or index >= _fps_limit_values.size():
		return GameSettings.fps_limit
	return int(_fps_limit_values[index])


func _on_draft_changed(_index: int = 0) -> void:
	if _suppress_refresh:
		return
	_status_label.text = "Display mode/resolution changes require Apply."


func _on_immediate_ui_scale(_index: int = 0) -> void:
	if _suppress_refresh:
		return
	GameSettings.apply_immediate_settings(
		_draft_ui_scale(),
		_vsync_check.button_pressed,
		_draft_fps_limit(),
		true
	)
	_status_label.text = "UI scale applied."


func _on_immediate_vsync(pressed: bool) -> void:
	if _suppress_refresh:
		return
	GameSettings.apply_immediate_settings(
		_draft_ui_scale(),
		pressed,
		_draft_fps_limit(),
		true
	)
	_status_label.text = "VSync %s." % ("enabled" if pressed else "disabled")


func _on_immediate_fps(_index: int = 0) -> void:
	if _suppress_refresh:
		return
	GameSettings.apply_immediate_settings(
		_draft_ui_scale(),
		_vsync_check.button_pressed,
		_draft_fps_limit(),
		true
	)
	_status_label.text = "FPS limit applied."


func _on_apply_pressed() -> void:
	var res: Vector2i = _draft_resolution()
	GameSettings.apply_all_from_draft(
		_draft_mode(),
		res.x,
		res.y,
		_draft_ui_scale(),
		_vsync_check.button_pressed,
		_draft_fps_limit()
	)
	if GameSettings.is_confirm_pending():
		_status_label.text = "Confirm display changes, or wait to revert."
	else:
		_status_label.text = "Settings applied."


func _on_cancel_pressed() -> void:
	if GameSettings.is_confirm_pending():
		GameSettings.revert_display_changes()
	_rebuild_options()
	_sync_controls_from_settings()
	_status_label.text = "Reverted to current settings."


func _on_reset_pressed() -> void:
	GameSettings.reset_to_defaults(true)
	_rebuild_options()
	_sync_controls_from_settings()
	if GameSettings.is_confirm_pending():
		_status_label.text = "Defaults applied — confirm display changes."
	else:
		_status_label.text = "Defaults restored."


func _on_close_pressed() -> void:
	if GameSettings.is_confirm_pending():
		GameSettings.revert_display_changes()
	close_panel()
