extends Node

## Headless verification for MatchCompositionRoot after total AI purge.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_match_composition_root.tscn

const REPORT_PATH := "user://match_composition_root_verify_result.txt"


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_match_composition_root: start")

	await _verify_packed_scene(failures)
	await _verify_runtime_bind(failures)

	var report: String
	if failures.is_empty():
		report = "PASS match_composition_root\n"
	else:
		report = "FAIL match_composition_root\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)


func _verify_packed_scene(failures: PackedStringArray) -> void:
	var packed: PackedScene = load("res://scenes/match/match_systems.tscn") as PackedScene
	_expect(failures, "match_systems.tscn loads", packed != null)
	if packed == null:
		return
	var systems: Node = packed.instantiate()
	add_child(systems)
	await get_tree().process_frame
	await get_tree().process_frame

	var root: MatchCompositionRoot = systems as MatchCompositionRoot
	_expect(failures, "root is MatchCompositionRoot", root != null)
	if root == null:
		systems.queue_free()
		await get_tree().process_frame
		return

	_expect(failures, "AIPlayerState child present", root.get_node_or_null("AIPlayerState") is AIPlayerState)
	_expect(failures, "SimpleWc3AI child present", root.simple_wc3_ai is SimpleWc3AI)
	_expect(failures, "authority is SimpleWc3AI", root.military_command_authority is SimpleWc3AI)
	_expect(failures, "old military inactive", not root.is_old_military_runtime_active())
	_expect(failures, "V2 inactive", not root.is_v2_military_active())
	_expect(failures, "build manager mechanics present", root.enemy_build_manager != null)
	_expect(failures, "gather manager mechanics present", root.enemy_gather_manager != null)
	_expect(failures, "no legacy military children", root.get_node_or_null("MilitaryDirectorV2") == null)

	systems.queue_free()
	await get_tree().process_frame


func _verify_runtime_bind(failures: PackedStringArray) -> void:
	EnemyArmyCommand.reset_match_state()
	var root := MatchCompositionRoot.new()
	root.name = "MatchSystems"
	var state := AIPlayerState.new()
	state.name = "AIPlayerState"
	root.add_child(state)
	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	root.add_child(simple)
	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "bound AIPlayerState", EnemyArmyCommand.get_bound_ai_player_state() == state)
	_expect(failures, "declared authority SimpleWc3AI", EnemyArmyCommand.get_declared_command_authority() is SimpleWc3AI)
	_expect(
		failures,
		"AIPlayerState records SimpleWc3AI name",
		state.military_command_authority_name == &"SimpleWc3AI"
	)

	root.queue_free()
	await get_tree().process_frame
	EnemyArmyCommand.unbind_match_composition()
