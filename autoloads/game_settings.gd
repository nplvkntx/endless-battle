extends Node

## Authoritative game-wide settings. Display/UI preferences persist under user://.
## Also hosts hero ability cast-mode hooks used by targeting.

@warning_ignore("unused_signal")
signal settings_loaded()
@warning_ignore("unused_signal")
signal settings_changed()
signal display_settings_changed()
signal display_confirm_started(seconds: float)
signal display_confirm_tick(seconds_left: float)
signal display_confirm_finished(kept: bool)

@export var settings_data: Resource

## Mirrors HeroAbilityDefinition.CastMode — kept numeric to avoid autoload load-order issues.
const CAST_MODE_NORMAL := 0
const CAST_MODE_QUICK := 1
const CAST_MODE_QUICK_WITH_INDICATOR := 2

const CONFIG_PATH := "user://game_settings.cfg"
const CONFIG_VERSION := 1
const SECTION_META := "meta"
const SECTION_DISPLAY := "display"
const DESIGN_WIDTH := 1920
const DESIGN_HEIGHT := 1080
const MIN_WIDTH := 1280
const MIN_HEIGHT := 720
const CONFIRM_SECONDS := 15.0
const LOG_PREFIX := "GameSettings:"

## When set (tests only), read/write this path instead of CONFIG_PATH.
var config_path_override: String = ""

enum DisplayMode {
	WINDOWED = 0,
	BORDERLESS_FULLSCREEN = 1,
	EXCLUSIVE_FULLSCREEN = 2,
}

## Hero ability cast mode. Default is normal (key → preview → click).
var hero_ability_cast_mode: int = CAST_MODE_NORMAL

var display_mode: int = DisplayMode.BORDERLESS_FULLSCREEN
var resolution_width: int = DESIGN_WIDTH
var resolution_height: int = DESIGN_HEIGHT
var ui_scale: float = 1.0
var vsync_enabled: bool = true
var fps_limit: int = 144

var _applied_display_mode: int = DisplayMode.BORDERLESS_FULLSCREEN
var _applied_resolution_width: int = DESIGN_WIDTH
var _applied_resolution_height: int = DESIGN_HEIGHT
var _applied_ui_scale: float = 1.0
var _applied_vsync_enabled: bool = true
var _applied_fps_limit: int = 144

var _confirm_active: bool = false
var _confirm_seconds_left: float = 0.0
var _rollback_mode: int = DisplayMode.BORDERLESS_FULLSCREEN
var _rollback_width: int = DESIGN_WIDTH
var _rollback_height: int = DESIGN_HEIGHT
var _confirm_layer: CanvasLayer
var _confirm_label: Label
var _keep_button: Button
var _revert_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_confirm_ui()
	_load_or_init_defaults()
	_apply_all(false)
	settings_loaded.emit()


func _process(delta: float) -> void:
	if not _confirm_active:
		return
	_confirm_seconds_left = maxf(0.0, _confirm_seconds_left - delta)
	_update_confirm_label()
	display_confirm_tick.emit(_confirm_seconds_left)
	if _confirm_seconds_left <= 0.0:
		_finish_confirm(false)


func get_hero_ability_cast_mode() -> int:
	return hero_ability_cast_mode


func set_hero_ability_cast_mode(mode: int) -> void:
	hero_ability_cast_mode = mode
	settings_changed.emit()


func get_design_size() -> Vector2i:
	return Vector2i(DESIGN_WIDTH, DESIGN_HEIGHT)


func get_min_resolution() -> Vector2i:
	return Vector2i(MIN_WIDTH, MIN_HEIGHT)


func get_supported_resolutions() -> Array:
	var out: Array = []
	var screen_size: Vector2i = _get_active_screen_size()
	var candidates: Array = _resolution_candidates()
	for item: Variant in candidates:
		if typeof(item) != TYPE_VECTOR2I:
			continue
		var res: Vector2i = item
		if res.x < MIN_WIDTH or res.y < MIN_HEIGHT:
			continue
		if res.x > screen_size.x or res.y > screen_size.y:
			continue
		out.append(res)
	if out.is_empty():
		out.append(Vector2i(MIN_WIDTH, MIN_HEIGHT))
	return out


func get_ui_scale_options() -> Array:
	return [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]


func get_fps_limit_options() -> Array:
	## 0 means unlimited.
	return [30, 60, 120, 144, 165, 240, 0]


func display_mode_label(mode: int) -> String:
	match clampi(mode, 0, 2):
		DisplayMode.WINDOWED:
			return "Windowed"
		DisplayMode.BORDERLESS_FULLSCREEN:
			return "Borderless Fullscreen"
		_:
			return "Exclusive Fullscreen"


func fps_limit_label(limit: int) -> String:
	if limit <= 0:
		return "Unlimited"
	return str(limit)


func ui_scale_label(scale_value: float) -> String:
	return "%d%%" % int(round(scale_value * 100.0))


func get_snapshot() -> Dictionary:
	return {
		"display_mode": display_mode,
		"resolution_width": resolution_width,
		"resolution_height": resolution_height,
		"ui_scale": ui_scale,
		"vsync_enabled": vsync_enabled,
		"fps_limit": fps_limit,
	}


func is_confirm_pending() -> bool:
	return _confirm_active


func apply_immediate_settings(
	new_ui_scale: float,
	new_vsync: bool,
	new_fps_limit: int,
	persist: bool = true
) -> void:
	ui_scale = _sanitize_ui_scale(new_ui_scale)
	vsync_enabled = new_vsync
	fps_limit = _sanitize_fps_limit(new_fps_limit)
	_apply_ui_scale()
	_apply_vsync()
	_apply_fps_limit()
	_applied_ui_scale = ui_scale
	_applied_vsync_enabled = vsync_enabled
	_applied_fps_limit = fps_limit
	if persist:
		_save_config()
	settings_changed.emit()
	display_settings_changed.emit()


func apply_display_settings(
	new_mode: int,
	new_width: int,
	new_height: int,
	require_confirm: bool = true
) -> bool:
	var sanitized_mode: int = _sanitize_display_mode(new_mode)
	var sanitized_res: Vector2i = _sanitize_resolution(new_width, new_height)
	var display_changed: bool = (
		sanitized_mode != _applied_display_mode
		or sanitized_res.x != _applied_resolution_width
		or sanitized_res.y != _applied_resolution_height
	)

	if require_confirm and display_changed:
		if _confirm_active:
			_cancel_confirm_timer_only()
		_rollback_mode = _applied_display_mode
		_rollback_width = _applied_resolution_width
		_rollback_height = _applied_resolution_height

	display_mode = sanitized_mode
	resolution_width = sanitized_res.x
	resolution_height = sanitized_res.y

	var applied_ok: bool = _apply_window_mode_and_size()
	if not applied_ok and sanitized_mode == DisplayMode.EXCLUSIVE_FULLSCREEN:
		print("%s exclusive fullscreen unsupported; falling back to borderless" % LOG_PREFIX)
		display_mode = DisplayMode.BORDERLESS_FULLSCREEN
		applied_ok = _apply_window_mode_and_size()

	_applied_display_mode = display_mode
	_applied_resolution_width = resolution_width
	_applied_resolution_height = resolution_height

	print(
		"%s display mode applied=%s resolution=%dx%d"
		% [LOG_PREFIX, display_mode_label(display_mode), resolution_width, resolution_height]
	)

	if require_confirm and display_changed:
		_start_confirm()
	elif not require_confirm:
		_save_config()

	settings_changed.emit()
	display_settings_changed.emit()
	return applied_ok


func apply_all_from_draft(
	new_mode: int,
	new_width: int,
	new_height: int,
	new_ui_scale: float,
	new_vsync: bool,
	new_fps_limit: int
) -> void:
	apply_immediate_settings(new_ui_scale, new_vsync, new_fps_limit, true)
	apply_display_settings(new_mode, new_width, new_height, true)


func keep_display_changes() -> void:
	if not _confirm_active:
		return
	_finish_confirm(true)


func revert_display_changes() -> void:
	if not _confirm_active:
		return
	_finish_confirm(false)


func reset_to_defaults(require_confirm: bool = true) -> void:
	var defaults: Dictionary = _default_settings()
	apply_immediate_settings(
		float(defaults["ui_scale"]),
		bool(defaults["vsync_enabled"]),
		int(defaults["fps_limit"]),
		true
	)
	apply_display_settings(
		int(defaults["display_mode"]),
		int(defaults["resolution_width"]),
		int(defaults["resolution_height"]),
		require_confirm
	)


func reload_from_disk() -> void:
	_load_or_init_defaults()
	_apply_all(false)


## Test/helper: write values through sanitizers without touching the window.
func sanitize_resolution_for_tests(width: int, height: int) -> Vector2i:
	return _sanitize_resolution(width, height)


func sanitize_ui_scale_for_tests(scale_value: float) -> float:
	return _sanitize_ui_scale(scale_value)


func sanitize_fps_limit_for_tests(limit: int) -> int:
	return _sanitize_fps_limit(limit)


func sanitize_display_mode_for_tests(mode: int) -> int:
	return _sanitize_display_mode(mode)


func force_save_for_tests() -> bool:
	return _save_config()


func clear_config_for_tests() -> void:
	var path: String = get_config_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func get_config_path() -> String:
	if not config_path_override.is_empty():
		return config_path_override
	return CONFIG_PATH


func _load_or_init_defaults() -> void:
	var defaults: Dictionary = _default_settings()
	display_mode = int(defaults["display_mode"])
	resolution_width = int(defaults["resolution_width"])
	resolution_height = int(defaults["resolution_height"])
	ui_scale = float(defaults["ui_scale"])
	vsync_enabled = bool(defaults["vsync_enabled"])
	fps_limit = int(defaults["fps_limit"])

	if not FileAccess.file_exists(get_config_path()):
		print("%s settings loaded (defaults; no config file)" % LOG_PREFIX)
		_save_config()
		return

	var cfg := ConfigFile.new()
	var err: int = cfg.load(get_config_path())
	if err != OK:
		print("%s invalid value rejected: config load failed (%d); using defaults" % [LOG_PREFIX, err])
		_save_config()
		return

	var corrected: bool = false
	var version: int = int(cfg.get_value(SECTION_META, "version", 0))
	if version != CONFIG_VERSION:
		print("%s invalid value rejected: config version %d; migrating to defaults merge" % [LOG_PREFIX, version])
		corrected = true

	var raw_mode: int = int(cfg.get_value(SECTION_DISPLAY, "display_mode", display_mode))
	var loaded_mode: int = _sanitize_display_mode(raw_mode)
	if loaded_mode != raw_mode:
		corrected = true

	var loaded_w: int = int(cfg.get_value(SECTION_DISPLAY, "resolution_width", resolution_width))
	var loaded_h: int = int(cfg.get_value(SECTION_DISPLAY, "resolution_height", resolution_height))
	var loaded_res: Vector2i = _sanitize_resolution(loaded_w, loaded_h)
	if loaded_res.x != loaded_w or loaded_res.y != loaded_h:
		print(
			"%s invalid value rejected: resolution %dx%d -> %dx%d"
			% [LOG_PREFIX, loaded_w, loaded_h, loaded_res.x, loaded_res.y]
		)
		corrected = true

	var loaded_scale: float = float(cfg.get_value(SECTION_DISPLAY, "ui_scale", ui_scale))
	var sanitized_scale: float = _sanitize_ui_scale(loaded_scale)
	if not is_equal_approx(loaded_scale, sanitized_scale):
		print("%s invalid value rejected: ui_scale %s -> %s" % [LOG_PREFIX, str(loaded_scale), str(sanitized_scale)])
		corrected = true

	var loaded_fps: int = int(cfg.get_value(SECTION_DISPLAY, "fps_limit", fps_limit))
	var sanitized_fps: int = _sanitize_fps_limit(loaded_fps)
	if loaded_fps != sanitized_fps:
		print("%s invalid value rejected: fps_limit %d -> %d" % [LOG_PREFIX, loaded_fps, sanitized_fps])
		corrected = true

	display_mode = loaded_mode
	resolution_width = loaded_res.x
	resolution_height = loaded_res.y
	ui_scale = sanitized_scale
	vsync_enabled = VariantUtils.to_bool(
		cfg.get_value(SECTION_DISPLAY, "vsync_enabled", vsync_enabled),
		true
	)
	fps_limit = sanitized_fps
	print(
		"%s settings loaded mode=%s res=%dx%d ui_scale=%s vsync=%s fps=%s"
		% [
			LOG_PREFIX,
			display_mode_label(display_mode),
			resolution_width,
			resolution_height,
			ui_scale_label(ui_scale),
			str(vsync_enabled),
			fps_limit_label(fps_limit),
		]
	)
	if corrected:
		_save_config()


func _default_settings() -> Dictionary:
	var native: Vector2i = _get_active_screen_size()
	var res: Vector2i = _sanitize_resolution(native.x, native.y)
	return {
		"display_mode": DisplayMode.BORDERLESS_FULLSCREEN,
		"resolution_width": res.x,
		"resolution_height": res.y,
		"ui_scale": 1.0,
		"vsync_enabled": true,
		"fps_limit": 144,
	}


func _apply_all(_unused_persist: bool) -> void:
	_apply_ui_scale()
	_apply_vsync()
	_apply_fps_limit()
	_apply_window_mode_and_size()
	_applied_display_mode = display_mode
	_applied_resolution_width = resolution_width
	_applied_resolution_height = resolution_height
	_applied_ui_scale = ui_scale
	_applied_vsync_enabled = vsync_enabled
	_applied_fps_limit = fps_limit


func _apply_ui_scale() -> void:
	var root_window: Window = get_window()
	if root_window == null:
		return
	root_window.content_scale_size = Vector2i(DESIGN_WIDTH, DESIGN_HEIGHT)
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root_window.content_scale_factor = ui_scale


func _apply_vsync() -> void:
	if _is_headless():
		return
	var mode: int = (
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)
	DisplayServer.window_set_vsync_mode(mode)


func _apply_fps_limit() -> void:
	Engine.max_fps = maxi(0, fps_limit)


func _apply_window_mode_and_size() -> bool:
	if _is_headless():
		return true

	var root_window: Window = get_window()
	if root_window == null:
		return false

	match display_mode:
		DisplayMode.WINDOWED:
			root_window.mode = Window.MODE_WINDOWED
			root_window.borderless = false
			var size: Vector2i = Vector2i(resolution_width, resolution_height)
			root_window.size = size
			_center_window(root_window)
			print("%s resolution applied (windowed) %dx%d" % [LOG_PREFIX, size.x, size.y])
			return true
		DisplayMode.BORDERLESS_FULLSCREEN:
			root_window.borderless = true
			root_window.mode = Window.MODE_FULLSCREEN
			print("%s resolution applied (borderless native monitor)" % LOG_PREFIX)
			return true
		DisplayMode.EXCLUSIVE_FULLSCREEN:
			root_window.borderless = false
			root_window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
			## Some platforms refuse exclusive mode; caller falls back to borderless.
			if root_window.mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
				return false
			print("%s resolution applied (exclusive fullscreen)" % LOG_PREFIX)
			return true
		_:
			root_window.mode = Window.MODE_FULLSCREEN
			return true


func _center_window(root_window: Window) -> void:
	var screen: int = root_window.current_screen
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		usable = Rect2i(screen_pos, DisplayServer.screen_get_size(screen))

	var target: Vector2i = usable.position + (usable.size - root_window.size) / 2
	var max_pos: Vector2i = usable.position + usable.size - root_window.size
	target.x = clampi(target.x, usable.position.x, maxi(usable.position.x, max_pos.x))
	target.y = clampi(target.y, usable.position.y, maxi(usable.position.y, max_pos.y))
	root_window.position = target


func _start_confirm() -> void:
	_confirm_active = true
	_confirm_seconds_left = CONFIRM_SECONDS
	if _confirm_layer != null:
		_confirm_layer.visible = true
	_update_confirm_label()
	display_confirm_started.emit(CONFIRM_SECONDS)


func _finish_confirm(kept: bool) -> void:
	if not _confirm_active:
		return
	_confirm_active = false
	_confirm_seconds_left = 0.0
	if _confirm_layer != null:
		_confirm_layer.visible = false

	if kept:
		display_mode = _applied_display_mode
		resolution_width = _applied_resolution_width
		resolution_height = _applied_resolution_height
		_save_config()
		print("%s display settings kept and saved" % LOG_PREFIX)
	else:
		display_mode = _rollback_mode
		resolution_width = _rollback_width
		resolution_height = _rollback_height
		_apply_window_mode_and_size()
		_applied_display_mode = display_mode
		_applied_resolution_width = resolution_width
		_applied_resolution_height = resolution_height
		print(
			"%s display settings reverted to %s %dx%d"
			% [LOG_PREFIX, display_mode_label(display_mode), resolution_width, resolution_height]
		)

	display_confirm_finished.emit(kept)
	settings_changed.emit()
	display_settings_changed.emit()


func _cancel_confirm_timer_only() -> void:
	## Replaced by a newer pending change; do not emit finished.
	_confirm_active = false
	_confirm_seconds_left = 0.0
	if _confirm_layer != null:
		_confirm_layer.visible = false


func _ensure_confirm_ui() -> void:
	if _confirm_layer != null:
		return

	_confirm_layer = CanvasLayer.new()
	_confirm_layer.layer = 200
	_confirm_layer.visible = false
	_confirm_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 160)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_confirm_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)

	_keep_button = Button.new()
	_keep_button.text = "Keep Changes"
	_keep_button.custom_minimum_size = Vector2(140, 36)
	_keep_button.pressed.connect(keep_display_changes)
	buttons.add_child(_keep_button)

	_revert_button = Button.new()
	_revert_button.text = "Revert"
	_revert_button.custom_minimum_size = Vector2(140, 36)
	_revert_button.pressed.connect(revert_display_changes)
	buttons.add_child(_revert_button)


func _update_confirm_label() -> void:
	if _confirm_label == null:
		return
	var secs: int = int(ceil(_confirm_seconds_left))
	_confirm_label.text = (
		"Keep these display settings?\nReverting in %d seconds if not confirmed." % secs
	)


func _save_config() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_META, "version", CONFIG_VERSION)
	cfg.set_value(SECTION_DISPLAY, "display_mode", display_mode)
	cfg.set_value(SECTION_DISPLAY, "resolution_width", resolution_width)
	cfg.set_value(SECTION_DISPLAY, "resolution_height", resolution_height)
	cfg.set_value(SECTION_DISPLAY, "ui_scale", ui_scale)
	cfg.set_value(SECTION_DISPLAY, "vsync_enabled", vsync_enabled)
	cfg.set_value(SECTION_DISPLAY, "fps_limit", fps_limit)
	var err: int = cfg.save(get_config_path())
	if err != OK:
		print("%s config save failure (%d)" % [LOG_PREFIX, err])
		return false
	return true


func _sanitize_display_mode(mode: int) -> int:
	if mode < DisplayMode.WINDOWED or mode > DisplayMode.EXCLUSIVE_FULLSCREEN:
		print("%s invalid value rejected: display_mode %d" % [LOG_PREFIX, mode])
		return DisplayMode.BORDERLESS_FULLSCREEN
	return mode


func _sanitize_resolution(width: int, height: int) -> Vector2i:
	if width <= 0 or height <= 0:
		print("%s invalid value rejected: non-positive resolution %dx%d" % [LOG_PREFIX, width, height])
		return _closest_supported(_get_active_screen_size())

	var screen: Vector2i = _get_active_screen_size()
	var clamped := Vector2i(mini(width, screen.x), mini(height, screen.y))
	if clamped.x < MIN_WIDTH or clamped.y < MIN_HEIGHT:
		## Prefer native if it meets minimum; otherwise minimum.
		if screen.x >= MIN_WIDTH and screen.y >= MIN_HEIGHT:
			return _closest_supported(screen)
		return Vector2i(MIN_WIDTH, MIN_HEIGHT)

	return _closest_supported(clamped)


func _sanitize_ui_scale(scale_value: float) -> float:
	var options: Array = get_ui_scale_options()
	var best: float = 1.0
	var best_dist: float = INF
	for item: Variant in options:
		var option: float = float(item)
		var dist: float = absf(option - scale_value)
		if dist < best_dist:
			best_dist = dist
			best = option
	return best


func _sanitize_fps_limit(limit: int) -> int:
	var options: Array = get_fps_limit_options()
	if limit < 0:
		return 144
	for item: Variant in options:
		if int(item) == limit:
			return limit
	## Snap to nearest positive option; 0 (unlimited) only if exact.
	var best: int = 144
	var best_dist: int = 999999
	for item: Variant in options:
		var option: int = int(item)
		if option <= 0:
			continue
		var dist: int = absi(option - limit)
		if dist < best_dist:
			best_dist = dist
			best = option
	return best


func _closest_supported(desired: Vector2i) -> Vector2i:
	var supported: Array = get_supported_resolutions()
	var best: Vector2i = supported[0]
	var best_score: int = 999999999
	for item: Variant in supported:
		var res: Vector2i = item
		## Prefer exact match, else closest area not exceeding desired when possible.
		if res == desired:
			return res
		var score: int = absi(res.x - desired.x) + absi(res.y - desired.y)
		if score < best_score:
			best_score = score
			best = res
	return best


func _resolution_candidates() -> Array:
	return [
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160),
	]


func _get_active_screen_size() -> Vector2i:
	if _is_headless():
		return Vector2i(DESIGN_WIDTH, DESIGN_HEIGHT)
	var screen: int = 0
	var root_window: Window = get_window()
	if root_window != null:
		screen = root_window.current_screen
	var size: Vector2i = DisplayServer.screen_get_size(screen)
	if size.x <= 0 or size.y <= 0:
		return Vector2i(DESIGN_WIDTH, DESIGN_HEIGHT)
	return size


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
