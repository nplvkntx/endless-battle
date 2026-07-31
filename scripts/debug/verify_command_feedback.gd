extends Node

## Headless verification for RTS command markers and movement dust feedback.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_command_feedback.tscn

const REPORT_PATH := "user://command_feedback_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CommandFeedback.clear_all()
	CommandFeedback.enabled = true
	CommandFeedback.markers_enabled = true
	CommandFeedback.dust_enabled = true

	_verify_ground_markers(failures)
	_verify_marker_spam_cleanup(failures)
	_verify_attack_pulse(failures)
	await _verify_movement_dust(failures)
	_verify_ai_does_not_spawn_markers(failures)
	_verify_match_reset_clears(failures)
	_verify_disable_toggles(failures)

	var report: String
	if failures.is_empty():
		report = "PASS command_feedback\n"
	else:
		report = "FAIL command_feedback\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_ground_markers(failures: PackedStringArray) -> void:
	CommandFeedback.clear_all()
	CommandFeedback.show_move_marker(Vector3(2, 0, 3))
	_expect(failures, "move marker spawned", CommandFeedback.get_active_marker_count() == 1)

	CommandFeedback.show_attack_move_marker(Vector3(4, 0, 1))
	_expect(failures, "attack-move marker spawned", CommandFeedback.get_active_marker_count() == 2)

	CommandFeedback.show_patrol_marker(Vector3(-2, 0, 5))
	_expect(failures, "patrol marker spawned", CommandFeedback.get_active_marker_count() == 3)


func _verify_marker_spam_cleanup(failures: PackedStringArray) -> void:
	CommandFeedback.clear_all()
	for i: int in 20:
		CommandFeedback.show_move_marker(Vector3(float(i), 0, 0))
	_expect(
		failures,
		"spam capped markers",
		CommandFeedback.get_active_marker_count() <= 10
	)


func _verify_attack_pulse(failures: PackedStringArray) -> void:
	var enemy: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(enemy)
	enemy.global_position = Vector3(8, 0, 0)
	enemy.add_to_group(&"enemies")
	enemy.play_target_feedback()
	_expect(failures, "unit has play_target_feedback", enemy.has_method("play_target_feedback"))
	CommandFeedback.pulse_attack_target(enemy)
	enemy.queue_free()


func _verify_movement_dust(failures: PackedStringArray) -> void:
	CommandFeedback.clear_all()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3.ZERO
	await get_tree().process_frame

	var applied: bool = unit.request_movement_target(Vector3(12, 0, 0), Unit.RepathUrgency.PLAYER_ORDER)
	_expect(failures, "movement request applied", applied)
	_expect(failures, "start dust spawned", CommandFeedback.get_active_dust_count() >= 1)

	# Simulate motion so footstep cooldown can fire.
	unit.velocity = Vector3(5, 0, 0)
	CommandFeedback.notify_unit_moving(unit)
	var dust_after_step: int = CommandFeedback.get_active_dust_count()
	_expect(failures, "footstep dust respects first call", dust_after_step >= 1)

	var before_cooldown: int = CommandFeedback.get_active_dust_count()
	CommandFeedback.notify_unit_moving(unit)
	_expect(
		failures,
		"footstep cooldown blocks immediate spam",
		CommandFeedback.get_active_dust_count() == before_cooldown
	)

	unit.queue_free()
	await get_tree().process_frame


func _verify_ai_does_not_spawn_markers(failures: PackedStringArray) -> void:
	CommandFeedback.clear_all()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3.ZERO
	unit.add_to_group(&"enemies")

	# AI path calls combat APIs directly — must not create player command markers.
	if unit.has_method("command_attack_move"):
		unit.command_attack_move(Vector3(10, 0, 0))
	_expect(
		failures,
		"AI attack-move creates no command markers",
		CommandFeedback.get_active_marker_count() == 0
	)

	unit.set_movement_target(Vector3(6, 0, 0))
	_expect(
		failures,
		"direct set_movement_target creates no command markers",
		CommandFeedback.get_active_marker_count() == 0
	)

	unit.queue_free()


func _verify_match_reset_clears(failures: PackedStringArray) -> void:
	CommandFeedback.show_move_marker(Vector3(1, 0, 1))
	CommandFeedback.show_patrol_marker(Vector3(2, 0, 2))
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	CommandFeedback.notify_movement_started(unit)
	_expect(failures, "pre-reset has markers", CommandFeedback.get_active_marker_count() > 0)
	_expect(failures, "pre-reset has dust", CommandFeedback.get_active_dust_count() > 0)

	CommandFeedback.clear_all()
	_expect(failures, "clear_all removes markers", CommandFeedback.get_active_marker_count() == 0)
	_expect(failures, "clear_all removes dust", CommandFeedback.get_active_dust_count() == 0)
	unit.queue_free()


func _verify_disable_toggles(failures: PackedStringArray) -> void:
	CommandFeedback.clear_all()
	CommandFeedback.markers_enabled = false
	CommandFeedback.show_move_marker(Vector3(3, 0, 3))
	_expect(failures, "markers_enabled false blocks markers", CommandFeedback.get_active_marker_count() == 0)

	CommandFeedback.markers_enabled = true
	CommandFeedback.dust_enabled = false
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	CommandFeedback.notify_movement_started(unit)
	_expect(failures, "dust_enabled false blocks dust", CommandFeedback.get_active_dust_count() == 0)

	CommandFeedback.dust_enabled = true
	CommandFeedback.enabled = false
	CommandFeedback.show_attack_move_marker(Vector3(0, 0, 4))
	CommandFeedback.notify_movement_started(unit)
	_expect(failures, "enabled false blocks markers", CommandFeedback.get_active_marker_count() == 0)
	_expect(failures, "enabled false blocks dust", CommandFeedback.get_active_dust_count() == 0)

	CommandFeedback.enabled = true
	unit.queue_free()


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
