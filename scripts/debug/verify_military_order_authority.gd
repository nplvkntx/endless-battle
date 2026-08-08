extends Node

## Focused V2 order-authority regression.
## Proves EnemyArmyCommand.tick_mission_watchdog must not overwrite ArmyCommanderV2
## strategic orders under Military AI V2.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_military_order_authority.tscn

const REPORT_PATH := "user://military_order_authority_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()

	EnemyArmyCommand.reset_match_state()
	EnemyUnitMission.reset_match_state()

	var root := Node.new()
	root.name = "MatchSystems"
	add_child(root)

	var ai_state := AIPlayerState.new()
	ai_state.name = "AIPlayerState"
	root.add_child(ai_state)

	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	root.add_child(director)
	director.reset_match_state()
	director.set_process(false)

	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	root.add_child(commander)
	commander.reset_match_state()
	commander.set_process(false)
	commander._director = director

	EnemyArmyCommand.bind_match_composition(ai_state, commander)

	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "V2 enabled", MilitaryAIConfig.is_v2_enabled())

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	hero.name = "EnemyHero"
	hero.team_id = 1
	add_child(hero)
	hero.global_position = Vector3(10, 1, 10)
	hero.add_to_group(&"enemy_combat_units")
	hero.add_to_group(&"enemy_units")

	var front: MilitaryUnit = SPEARMAN_SCENE.instantiate() as MilitaryUnit
	front.name = "FrontSoldier"
	front.team_id = 1
	add_child(front)
	front.global_position = Vector3(12, 1, 12)
	front.add_to_group(&"enemy_combat_units")
	front.add_to_group(&"enemy_units")

	var rear: MilitaryUnit = SPEARMAN_SCENE.instantiate() as MilitaryUnit
	rear.name = "RearSoldier"
	rear.team_id = 1
	add_child(rear)
	rear.global_position = Vector3(8, 1, 8)
	rear.add_to_group(&"enemy_combat_units")
	rear.add_to_group(&"enemy_units")

	var reinforce: MilitaryUnit = SPEARMAN_SCENE.instantiate() as MilitaryUnit
	reinforce.name = "Reinforcement"
	reinforce.team_id = 1
	add_child(reinforce)
	reinforce.global_position = Vector3(0, 1, 0)
	reinforce.add_to_group(&"enemy_combat_units")
	reinforce.add_to_group(&"enemy_units")

	await get_tree().process_frame

	## Build main squad + active ATTACK mission.
	director._main_squad.try_add_member(hero, ArmySquadV2.UnitRole.HERO)
	director._main_squad.try_add_member(front, ArmySquadV2.UnitRole.FRONTLINE)
	director._main_squad.try_add_member(rear, ArmySquadV2.UnitRole.FRONTLINE)
	director.debug_enqueue_pending_for_tests(reinforce)

	var objective := Vector3(80, 1, 80)
	director._state = MilitaryDirectorV2.State.ATTACK
	director._publish_new_mission(
		ArmyMissionV2.MissionType.ATTACK,
		objective,
		null,
		90,
		"authority regression attack"
	)
	var mission_gen: int = director.get_mission_generation()
	_expect(failures, "mission generation stamped", mission_gen > 0)

	var squad_units: Array = [hero, front, rear]
	EnemyArmyCommand.prepare_v2_execution(
		EnemyArmyCommand.ArmyMode.ATTACKING,
		EnemyArmyCommand.StrategicState.ATTACKING,
		"authority regression"
	)
	EnemyArmyCommand.set_executable_mission(
		EnemyArmyCommand.ExecutableMission.ATTACK_PLAYER,
		"authority regression",
		null,
		objective,
		"PlayerTarget",
		"attack-move",
		squad_units,
		false
	)

	## 1) ArmyCommanderV2 issues authoritative strategic orders (per-unit to avoid
	## shared-squad-nav requiring a baked NavigationRegion in this harness).
	EnemyArmyCommand.push_diag_order_source("ArmyCommanderV2", mission_gen)
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		for entry: Variant in squad_units:
			EnemyArmyCommand.command_attack_move(
				[entry],
				objective,
				EnemyUnitMission.Mission.ATTACK
			)
	)
	EnemyArmyCommand.pop_diag_order_source()
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	await get_tree().process_frame

	_expect_source(failures, "hero after commander", hero, "ArmyCommanderV2")
	_expect_source(failures, "front after commander", front, "ArmyCommanderV2")
	_expect_source(failures, "rear after commander", rear, "ArmyCommanderV2")
	_expect(
		failures,
		"no conflict after commander-only orders",
		hero.get_strategic_order_conflict_status() != "YES"
	)

	## Pending reinforcement may still RALLY while unowned.
	EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), reinforce)
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	await get_tree().process_frame
	_expect(
		failures,
		"pending reinforcement mission RALLY or reinforcement-sourced",
		EnemyUnitMission.get_unit_mission(reinforce) == EnemyUnitMission.Mission.RALLY
		or String(reinforce.get_strategic_order_provenance().get("source", "")).contains(
			"reinforcement"
		)
	)
	_expect_source(failures, "front unchanged by pending RALLY", front, "ArmyCommanderV2")

	## 2) Direct call of legacy EAC mission watchdog — must no-op under V2.
	## Pre-fix evidence: this path called refresh_stalled_mission_order and
	## replaced ArmyCommanderV2 provenance with EnemyArmyCommand.watchdog.
	EnemyArmyCommand._exec_last_progress_msec = (
		Time.get_ticks_msec() - int(EnemyArmyCommand.MISSION_PROGRESS_STALL_SECONDS * 1000.0) - 500
	)
	EnemyArmyCommand._exec_watchdog_refreshed = false
	EnemyArmyCommand._exec_watchdog_timer = EnemyArmyCommand.MISSION_WATCHDOG_INTERVAL_SECONDS
	EnemyArmyCommand.tick_mission_watchdog(get_tree(), 0.0)
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	await get_tree().process_frame

	var front_after: Dictionary = front.get_strategic_order_provenance()
	var front_source: String = String(front_after.get("source", ""))
	_expect(
		failures,
		"EAC watchdog does not become current source under V2",
		not front_source.contains("EnemyArmyCommand.watchdog")
	)
	_expect_source(failures, "front still ArmyCommander after watchdog tick", front, "ArmyCommanderV2")
	_expect_source(failures, "hero still ArmyCommander after watchdog tick", hero, "ArmyCommanderV2")
	_expect_source(failures, "rear still ArmyCommander after watchdog tick", rear, "ArmyCommanderV2")
	_expect(
		failures,
		"no proven conflict after gated watchdog",
		front.get_strategic_order_conflict_status() != "YES"
	)

	## 3) Admitted reinforcement inherits mission via commander.
	director.debug_admit_pending_for_tests()
	_expect(failures, "reinforcement admitted to main", director.get_main_squad().has_member(reinforce))
	EnemyArmyCommand.release_reinforcement_from_pool(reinforce)
	EnemyUnitMission.clear_unit_mission(reinforce)
	EnemyArmyCommand.push_diag_order_source("ArmyCommanderV2", mission_gen)
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_attack_move(
			[reinforce],
			objective,
			EnemyUnitMission.Mission.ATTACK
		)
	)
	EnemyArmyCommand.pop_diag_order_source()
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	await get_tree().process_frame
	_expect_source(failures, "admitted reinforcement inherits commander", reinforce, "ArmyCommanderV2")
	_expect(
		failures,
		"admitted reinforcement mission ATTACK",
		EnemyUnitMission.get_unit_mission(reinforce) == EnemyUnitMission.Mission.ATTACK
	)

	## 4) Legitimate DEFEND transition may replace ATTACK (same ArmyCommander authority).
	EnemyArmyCommand.push_diag_order_source("ArmyCommanderV2", mission_gen + 1)
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_attack_move(
			[front],
			Vector3(5, 1, 5),
			EnemyUnitMission.Mission.DEFEND
		)
	)
	EnemyArmyCommand.pop_diag_order_source()
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	await get_tree().process_frame
	_expect_source(failures, "defend transition still commander", front, "ArmyCommanderV2")
	_expect(
		failures,
		"same-authority defend refresh is not conflict",
		front.get_strategic_order_conflict_status() != "YES"
	)

	## 5) Overlay provenance fields exposed.
	_verify_overlay_provenance(failures, front)

	## 6) Source gate present on legacy watchdog.
	var eac_source := FileAccess.open(
		"res://scripts/systems/enemy_army_command.gd",
		FileAccess.READ
	)
	_expect(failures, "EAC source readable", eac_source != null)
	if eac_source != null:
		var text: String = eac_source.get_as_text()
		eac_source.close()
		var watchdog_idx: int = text.find("static func tick_mission_watchdog")
		_expect(failures, "tick_mission_watchdog present", watchdog_idx >= 0)
		if watchdog_idx >= 0:
			var snippet: String = text.substr(watchdog_idx, 280)
			_expect(
				failures,
				"tick_mission_watchdog gates under V2",
				snippet.contains("is_v2_enabled()")
			)

	## 7) Provenance conflict detector fires for distinct strategic writers.
	front.record_strategic_order_provenance_for_tests(
		"ArmyCommanderV2",
		"ATTACK_MOVE",
		objective,
		mission_gen
	)
	front.record_strategic_order_provenance_for_tests(
		"EnemyArmyCommand.watchdog",
		"ATTACK_MOVE",
		objective + Vector3(2, 0, 0),
		mission_gen
	)
	_expect(
		failures,
		"detector YES for commander→watchdog same mission gen",
		front.get_strategic_order_conflict_status() == "YES"
	)

	var report: String
	if failures.is_empty():
		report = "PASS military_order_authority\n"
	else:
		report = "FAIL military_order_authority\n" + "\n".join(failures) + "\n"

	_write_report(report)
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect_source(
	failures: PackedStringArray,
	label: String,
	unit: Node,
	expected_prefix: String
) -> void:
	if unit == null or not unit.has_method("get_strategic_order_provenance"):
		failures.append("- %s missing provenance API" % label)
		return
	var prov: Dictionary = unit.call("get_strategic_order_provenance")
	var source: String = String(prov.get("source", "UNKNOWN"))
	_expect(failures, "%s source=%s" % [label, source], source.begins_with(expected_prefix))


func _verify_overlay_provenance(failures: PackedStringArray, unit: Node) -> void:
	var overlay = get_node_or_null("/root/RtsAiDebugOverlay")
	_expect(failures, "RtsAiDebugOverlay autoload present", overlay != null)
	var source := FileAccess.open("res://scripts/debug/rts_ai_debug_overlay.gd", FileAccess.READ)
	_expect(failures, "overlay source readable", source != null)
	if source != null:
		var text: String = source.get_as_text()
		source.close()
		_expect(failures, "overlay shows ORDER AUTHORITY", text.contains("ORDER AUTHORITY"))
		_expect(failures, "overlay shows CONFLICT", text.contains("CONFLICT:"))
		_expect(failures, "overlay reads provenance", text.contains("get_strategic_order_provenance"))
	if unit == null or not unit.has_method("get_strategic_order_provenance"):
		failures.append("- overlay unit missing provenance API")
		return
	var prov: Dictionary = unit.call("get_strategic_order_provenance")
	_expect(failures, "provenance has source", prov.has("source"))
	_expect(failures, "provenance has type", prov.has("type"))
	_expect(failures, "provenance has prev_source", prov.has("prev_source"))
	_expect(failures, "provenance has conflict", prov.has("conflict"))
	_expect(failures, "provenance has replacements_3s", prov.has("replacements_3s"))


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)


func _write_report(report: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
