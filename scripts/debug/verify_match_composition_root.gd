extends Node

## Headless verification for MatchCompositionRoot after enemy AI purge.
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

	_expect(failures, "no SimpleWc3AI child", root.get_node_or_null("SimpleWc3AI") == null)
	_expect(failures, "no AIPlayerState child", root.get_node_or_null("AIPlayerState") == null)
	_expect(failures, "build manager mechanics present", root.enemy_build_manager != null)
	_expect(failures, "gather manager mechanics present", root.enemy_gather_manager != null)
	_expect(failures, "no MilitaryDirectorV2 child", root.get_node_or_null("MilitaryDirectorV2") == null)
	_expect(failures, "no ArmyCommanderV2 child", root.get_node_or_null("ArmyCommanderV2") == null)
	_expect(failures, "no EnemyStrategicDirector child", root.get_node_or_null("EnemyStrategicDirector") == null)
	_expect(failures, "no EnemyWaveManager child", root.get_node_or_null("EnemyWaveManager") == null)
	_expect(failures, "no EnemyCreepManager child", root.get_node_or_null("EnemyCreepManager") == null)
	_expect(failures, "no EnemyDefenseManager child", root.get_node_or_null("EnemyDefenseManager") == null)
	_expect(failures, "no EnemyCombatController child", root.get_node_or_null("EnemyCombatController") == null)

	systems.queue_free()
	await get_tree().process_frame


func _verify_runtime_bind(failures: PackedStringArray) -> void:
	var root := MatchCompositionRoot.new()
	root.name = "MatchSystems"
	var build := EnemyBuildManager.new()
	build.name = "EnemyBuildManager"
	root.add_child(build)
	var gather := EnemyGatherManager.new()
	gather.name = "EnemyGatherManager"
	root.add_child(gather)
	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "runtime resolves build manager", root.enemy_build_manager == build)
	_expect(failures, "runtime resolves gather manager", root.enemy_gather_manager == gather)
	_expect(failures, "runtime has no SimpleWc3AI", root.get_node_or_null("SimpleWc3AI") == null)

	root.queue_free()
	await get_tree().process_frame
