extends Node

## Headless regression for the isolated RTS movement lab.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_rts_movement_lab.tscn

const LAB_SCENE: PackedScene = preload("res://scenes/debug/rts_movement_lab.tscn")
const REPORT_PATH := "user://rts_movement_lab_verify_result.txt"
const DESTINATION := Vector3(28.0, 0.0, 0.0)
const TIMEOUT_SEC := 45.0
const PROGRESS_SAMPLE_SEC := 2.0


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_rts_movement_lab: start")

	await _run_scenario(1, "single building", failures)
	await _run_scenario(2, "chokepoint", failures)
	await _run_scenario(3, "base cluster", failures)

	var report: String
	if failures.is_empty():
		report = "PASS rts_movement_lab\n"
	else:
		report = "FAIL rts_movement_lab\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_scenario(preset: int, label: String, failures: PackedStringArray) -> void:
	print("verify: preset %d (%s)" % [preset, label])
	var lab: RtsMovementLab = LAB_SCENE.instantiate() as RtsMovementLab
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame

	lab.load_preset(preset)
	await get_tree().process_frame

	var start_centroid: Vector3 = lab.get_group_centroid()
	var status_after_command: Dictionary = lab.issue_group_move(DESTINATION)

	_expect(failures, "%s: route exists" % label, bool(status_after_command.get("route_exists", false)))
	_expect(
		failures,
		"%s: route avoids blocked cells" % label,
		bool(status_after_command.get("route_avoids_blocked", false))
	)
	_expect(
		failures,
		"%s: one strategic path calculation" % label,
		int(status_after_command.get("path_calculations_this_command", 0)) == 1
	)

	await _wait_sec(PROGRESS_SAMPLE_SEC)
	var mid: Dictionary = lab.get_status()
	var mid_centroid: Vector3 = lab.get_group_centroid()
	var progressed: bool = start_centroid.distance_to(mid_centroid) > 1.0 or int(mid.get("arrived", 0)) > 0
	_expect(failures, "%s: units make progress" % label, progressed)
	_expect(
		failures,
		"%s: no intentional blocked occupancy mid-move" % label,
		int(mid.get("blocked_occupancy", 1)) == 0
	)

	var final_status: Dictionary = await lab.await_all_arrived(TIMEOUT_SEC)
	_expect(
		failures,
		"%s: no blocked occupancy at end" % label,
		int(final_status.get("blocked_occupancy", 1)) == 0
	)
	_expect(
		failures,
		"%s: all 20 units arrived" % label,
		int(final_status.get("arrived", 0)) == 20
	)
	_expect(
		failures,
		"%s: zero stuck units" % label,
		int(final_status.get("stuck", 1)) == 0
	)

	if int(final_status.get("arrived", 0)) != 20:
		print(
			"verify detail [%s]: arrived=%s stuck=%s moving=%s path_len=%s age=%.1f"
			% [
				label,
				final_status.get("arrived", 0),
				final_status.get("stuck", 0),
				final_status.get("moving", 0),
				final_status.get("path_length", 0),
				float(final_status.get("command_age", 0.0)),
			]
		)

	lab.queue_free()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if ok:
		print("  OK  ", label)
	else:
		print("  FAIL", label)
		failures.append(label)


func _wait_sec(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
