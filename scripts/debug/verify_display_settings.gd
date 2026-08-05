extends Node

## Headless display / UI settings regression checks. Run with:
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_display_settings.tscn

const REPORT_PATH := "user://display_settings_verify_result.txt"


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()

	## Isolate from the player's real user://game_settings.cfg.
	GameSettings.config_path_override = "user://display_settings_verify.cfg"
	GameSettings.clear_config_for_tests()

	_check_defaults_when_missing(failures)
	_check_load_valid_saved(failures)
	_check_reject_invalid_resolution(failures)
	_check_windowed_borderless_cycle(failures)
	_check_ui_scale_values(failures)
	_check_match_restart_preserves(failures)
	_check_main_menu_no_duplicate_scale(failures)
	_check_camera_zoom_untouched(failures)
	_check_minimap_mapping_stable(failures)

	GameSettings.clear_config_for_tests()
	GameSettings.config_path_override = ""

	var exit_code: int = 0
	var msg: String = ""
	if failures.is_empty():
		msg = "PASS display_settings\nDISPLAY_SETTINGS_OK"
	else:
		exit_code = 1
		msg = "FAIL display_settings\nDISPLAY_SETTINGS_FAIL\n - " + "\n - ".join(failures)

	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report:
		report.store_string(msg)
		report.close()

	print(msg)
	if exit_code != 0:
		push_error(msg)

	get_tree().quit(exit_code)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)


func _check_defaults_when_missing(failures: PackedStringArray) -> void:
	GameSettings.clear_config_for_tests()
	GameSettings.reload_from_disk()
	_expect(
		failures,
		"defaults display mode borderless",
		GameSettings.display_mode == GameSettings.DisplayMode.BORDERLESS_FULLSCREEN
	)
	_expect(failures, "defaults ui scale 100%", is_equal_approx(GameSettings.ui_scale, 1.0))
	_expect(failures, "defaults vsync on", GameSettings.vsync_enabled)
	_expect(failures, "defaults fps 144", GameSettings.fps_limit == 144)
	_expect(
		failures,
		"defaults resolution at least 720p",
		GameSettings.resolution_width >= 1280 and GameSettings.resolution_height >= 720
	)
	_expect(failures, "defaults wrote config", FileAccess.file_exists(GameSettings.get_config_path()))


func _check_load_valid_saved(failures: PackedStringArray) -> void:
	GameSettings.apply_immediate_settings(1.1, false, 60, true)
	GameSettings.apply_display_settings(
		GameSettings.DisplayMode.WINDOWED,
		1600,
		900,
		false
	)
	GameSettings.reload_from_disk()
	_expect(failures, "reload display mode windowed", GameSettings.display_mode == GameSettings.DisplayMode.WINDOWED)
	_expect(failures, "reload resolution 1600x900", GameSettings.resolution_width == 1600 and GameSettings.resolution_height == 900)
	_expect(failures, "reload ui scale 110%", is_equal_approx(GameSettings.ui_scale, 1.1))
	_expect(failures, "reload vsync off", not GameSettings.vsync_enabled)
	_expect(failures, "reload fps 60", GameSettings.fps_limit == 60)


func _check_reject_invalid_resolution(failures: PackedStringArray) -> void:
	var zero_res: Vector2i = GameSettings.sanitize_resolution_for_tests(0, 0)
	_expect(failures, "reject zero resolution", zero_res.x >= 1280 and zero_res.y >= 720)

	var negative_res: Vector2i = GameSettings.sanitize_resolution_for_tests(-100, -50)
	_expect(failures, "reject negative resolution", negative_res.x >= 1280 and negative_res.y >= 720)

	var tiny_res: Vector2i = GameSettings.sanitize_resolution_for_tests(640, 480)
	_expect(failures, "reject below minimum", tiny_res.x >= 1280 and tiny_res.y >= 720)

	var bad_mode: int = GameSettings.sanitize_display_mode_for_tests(99)
	_expect(
		failures,
		"reject invalid display mode",
		bad_mode == GameSettings.DisplayMode.BORDERLESS_FULLSCREEN
	)


func _check_windowed_borderless_cycle(failures: PackedStringArray) -> void:
	GameSettings.apply_display_settings(GameSettings.DisplayMode.WINDOWED, 1280, 720, false)
	_expect(failures, "cycle to windowed", GameSettings.display_mode == GameSettings.DisplayMode.WINDOWED)

	GameSettings.apply_display_settings(
		GameSettings.DisplayMode.BORDERLESS_FULLSCREEN,
		GameSettings.resolution_width,
		GameSettings.resolution_height,
		false
	)
	_expect(
		failures,
		"cycle to borderless",
		GameSettings.display_mode == GameSettings.DisplayMode.BORDERLESS_FULLSCREEN
	)

	GameSettings.apply_display_settings(GameSettings.DisplayMode.WINDOWED, 1920, 1080, false)
	_expect(failures, "cycle back to windowed", GameSettings.display_mode == GameSettings.DisplayMode.WINDOWED)
	_expect(
		failures,
		"cycle windowed resolution retained",
		GameSettings.resolution_width == 1920 and GameSettings.resolution_height == 1080
	)


func _check_ui_scale_values(failures: PackedStringArray) -> void:
	for scale_value: Variant in GameSettings.get_ui_scale_options():
		var scale_f: float = float(scale_value)
		GameSettings.apply_immediate_settings(scale_f, true, 144, true)
		_expect(
			failures,
			"ui scale applied %s" % GameSettings.ui_scale_label(scale_f),
			is_equal_approx(GameSettings.ui_scale, scale_f)
		)
		var root_window: Window = get_window()
		if root_window != null:
			_expect(
				failures,
				"content_scale_factor %s" % GameSettings.ui_scale_label(scale_f),
				is_equal_approx(root_window.content_scale_factor, scale_f)
			)

	var snapped: float = GameSettings.sanitize_ui_scale_for_tests(1.37)
	_expect(failures, "ui scale snaps to allowed option", snapped == 1.25 or snapped == 1.5)


func _check_match_restart_preserves(failures: PackedStringArray) -> void:
	GameSettings.apply_immediate_settings(1.25, true, 120, true)
	GameSettings.apply_display_settings(GameSettings.DisplayMode.WINDOWED, 1366, 768, false)
	var before: Dictionary = GameSettings.get_snapshot()

	## Match reset must not wipe display preferences.
	MatchSession.prepare_new_match()
	var after: Dictionary = GameSettings.get_snapshot()
	_expect(failures, "match prepare keeps display mode", int(before["display_mode"]) == int(after["display_mode"]))
	_expect(failures, "match prepare keeps resolution w", int(before["resolution_width"]) == int(after["resolution_width"]))
	_expect(failures, "match prepare keeps resolution h", int(before["resolution_height"]) == int(after["resolution_height"]))
	_expect(failures, "match prepare keeps ui scale", is_equal_approx(float(before["ui_scale"]), float(after["ui_scale"])))
	_expect(failures, "match prepare keeps vsync", bool(before["vsync_enabled"]) == bool(after["vsync_enabled"]))
	_expect(failures, "match prepare keeps fps", int(before["fps_limit"]) == int(after["fps_limit"]))


func _check_main_menu_no_duplicate_scale(failures: PackedStringArray) -> void:
	GameSettings.apply_immediate_settings(0.9, true, 144, true)
	var root_window: Window = get_window()
	_expect(failures, "root window present", root_window != null)
	if root_window == null:
		return

	var scale_before: float = root_window.content_scale_factor
	## Re-applying the same settings must not stack multipliers.
	GameSettings.apply_immediate_settings(0.9, true, 144, true)
	GameSettings.apply_immediate_settings(0.9, true, 144, true)
	_expect(
		failures,
		"ui scale not duplicated on reapply",
		is_equal_approx(root_window.content_scale_factor, scale_before)
		and is_equal_approx(root_window.content_scale_factor, 0.9)
	)
	_expect(
		failures,
		"design content size stable",
		root_window.content_scale_size == Vector2i(1920, 1080)
	)


func _check_camera_zoom_untouched(failures: PackedStringArray) -> void:
	var camera := Camera3D.new()
	camera.name = "VerifyCamera"
	add_child(camera)
	camera.global_position = Vector3(0.0, 20.0, 0.0)
	var height_before: float = camera.global_position.y

	GameSettings.apply_display_settings(GameSettings.DisplayMode.WINDOWED, 1280, 720, false)
	GameSettings.apply_immediate_settings(1.5, true, 60, true)
	GameSettings.apply_display_settings(
		GameSettings.DisplayMode.BORDERLESS_FULLSCREEN,
		1920,
		1080,
		false
	)

	_expect(
		failures,
		"resolution change does not modify camera height/zoom",
		is_equal_approx(camera.global_position.y, height_before)
	)
	remove_child(camera)
	camera.free()


func _check_minimap_mapping_stable(failures: PackedStringArray) -> void:
	var minimap_script: Script = load("res://scripts/ui/minimap.gd") as Script
	_expect(failures, "minimap script loads", minimap_script != null)
	if minimap_script == null:
		return

	var minimap := Control.new()
	minimap.set_script(minimap_script)
	minimap.size = Vector2(160, 160)
	add_child(minimap)

	var world_a: Vector3 = minimap.call("_minimap_to_world", Vector2(80, 80))
	GameSettings.apply_immediate_settings(1.5, true, 144, true)
	GameSettings.apply_display_settings(GameSettings.DisplayMode.WINDOWED, 1280, 720, false)
	var world_b: Vector3 = minimap.call("_minimap_to_world", Vector2(80, 80))

	_expect(
		failures,
		"minimap local mapping unchanged after resolution/ui scale",
		world_a.is_equal_approx(world_b)
	)
	remove_child(minimap)
	minimap.free()
