extends Node

## Headless verification for Military AI V2 foundation + army roster.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_military_ai_v2.tscn

const REPORT_PATH := "user://military_ai_v2_verify_result.txt"
const REPORT_FALLBACK := "res://military_ai_v2_verify_run.txt"


func _ready() -> void:
	var failures: PackedStringArray = []

	_verify_toggle_default(failures)
	_verify_mission_payload(failures)
	_verify_director_states(failures)
	_verify_commander_does_not_choose_strategy(failures)
	_verify_legacy_gate_helpers(failures)
	await _verify_army_roster_and_squad(failures)
	_verify_assemble_config_and_source(failures)
	await _verify_assemble_slot_stability(failures)

	var report: String
	if failures.is_empty():
		report = "PASS military_ai_v2_roster\n"
	else:
		report = "FAIL military_ai_v2_roster\n" + "\n".join(failures) + "\n"

	_write_report(report)
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)


func _write_report(report: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	var fallback := FileAccess.open(REPORT_FALLBACK, FileAccess.WRITE)
	if fallback != null:
		fallback.store_string(report)
		fallback.close()


func _verify_toggle_default(failures: PackedStringArray) -> void:
	_expect(failures, "USE_MILITARY_AI_V2 defaults false", MilitaryAIConfig.USE_MILITARY_AI_V2 == false)
	_expect(failures, "is_v2_enabled mirrors const", MilitaryAIConfig.is_v2_enabled() == false)
	_expect(failures, "ai_version_label Legacy when disabled", MilitaryAIConfig.ai_version_label() == "Legacy")


func _verify_mission_payload(failures: PackedStringArray) -> void:
	var mission := ArmyMissionV2.new(
		ArmyMissionV2.MissionType.ATTACK,
		Vector3(10, 0, 20),
		null,
		5,
		"test attack"
	)
	_expect(failures, "mission type ATTACK", mission.mission_type == ArmyMissionV2.MissionType.ATTACK)
	_expect(failures, "mission target position", mission.target_position == Vector3(10, 0, 20))
	_expect(failures, "mission priority", mission.priority == 5)
	_expect(failures, "mission transition reason", mission.transition_reason == "test attack")
	_expect(failures, "mission creation time set", mission.creation_time_msec > 0)
	_expect(failures, "mission last progress set", mission.last_progress_time_msec > 0)
	_expect(failures, "mission type label", mission.get_mission_type_name() == "ATTACK")
	_expect(failures, "mission objective label uses position", mission.get_objective_label().contains("10"))

	mission.mark_cancelled("test cancel")
	_expect(failures, "cancellation reason stored", mission.cancellation_reason == "test cancel")
	_expect(
		failures,
		"completion cancelled",
		mission.completion_condition == ArmyMissionV2.CompletionCondition.CANCELLED
	)


func _verify_director_states(failures: PackedStringArray) -> void:
	var director := MilitaryDirectorV2.new()
	add_child(director)
	director.reset_match_state()

	_expect(failures, "director starts IDLE", director.get_state() == MilitaryDirectorV2.State.IDLE)
	_expect(failures, "director state name IDLE", director.get_state_name() == "IDLE")
	_expect(failures, "director has mission", director.get_mission() != null)
	_expect(
		failures,
		"director mission IDLE",
		director.get_mission().mission_type == ArmyMissionV2.MissionType.IDLE
	)
	_expect(
		failures,
		"request_state rejected while V2 disabled",
		director.request_state(MilitaryDirectorV2.State.ATTACK, "should fail") == false
	)
	_expect(failures, "director owns empty main squad", director.get_main_squad() != null)
	_expect(failures, "main squad starts empty", director.get_main_squad().get_size() == 0)

	## Exercise state enum coverage without enabling the feature toggle.
	for state: MilitaryDirectorV2.State in [
		MilitaryDirectorV2.State.IDLE,
		MilitaryDirectorV2.State.ASSEMBLE,
		MilitaryDirectorV2.State.CREEP,
		MilitaryDirectorV2.State.ATTACK,
		MilitaryDirectorV2.State.DEFEND,
		MilitaryDirectorV2.State.RETREAT,
		MilitaryDirectorV2.State.RECOVER,
	]:
		var label: String = MilitaryDirectorV2.state_to_string(state)
		_expect(failures, "state label non-empty for %s" % label, not label.is_empty())
		_expect(failures, "state label not UNKNOWN for %s" % int(state), label != "UNKNOWN")

	director.queue_free()


func _verify_commander_does_not_choose_strategy(failures: PackedStringArray) -> void:
	var source := FileAccess.open("res://scripts/systems/army_commander_v2.gd", FileAccess.READ)
	_expect(failures, "commander script readable", source != null)
	if source == null:
		return

	var text: String = source.get_as_text()
	source.close()
	_expect(
		failures,
		"commander documents no strategic decisions",
		text.contains("Does not choose creep / attack / defend / retreat itself")
	)
	_expect(
		failures,
		"commander does not call request_state",
		not text.contains("request_state(")
	)
	_expect(
		failures,
		"commander receives squad from director",
		text.contains("Receives the main squad from the director")
	)
	_expect(
		failures,
		"commander cannot recruit independently",
		text.contains("cannot recruit units independently")
	)
	_expect(
		failures,
		"commander does not call try_add_member",
		not text.contains("try_add_member(")
	)
	_expect(
		failures,
		"commander does not call debug_enqueue_pending",
		not text.contains("debug_enqueue_pending")
	)


func _verify_legacy_gate_helpers(failures: PackedStringArray) -> void:
	var gated_scripts: PackedStringArray = PackedStringArray([
		"res://scripts/systems/enemy_combat_controller.gd",
		"res://scripts/systems/enemy_creep_manager.gd",
		"res://scripts/systems/enemy_defense_manager.gd",
		"res://scripts/systems/enemy_wave_manager.gd",
		"res://scripts/systems/enemy_strategic_director.gd",
	])
	for path: String in gated_scripts:
		var source := FileAccess.open(path, FileAccess.READ)
		_expect(failures, "%s readable" % path.get_file(), source != null)
		if source == null:
			continue
		var text: String = source.get_as_text()
		source.close()
		_expect(
			failures,
			"%s gates on MilitaryAIConfig" % path.get_file(),
			text.contains("MilitaryAIConfig.is_v2_enabled()")
		)


func _verify_army_roster_and_squad(failures: PackedStringArray) -> void:
	_verify_role_labels(failures)
	await _verify_squad_membership_lifecycle(failures)
	await _verify_director_pending_admission(failures)
	_verify_exclusion_helpers(failures)
	_verify_perf_squad_api(failures)


func _verify_assemble_config_and_source(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"creep-ready threshold configurable",
		MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS == 5
	)
	_expect(
		failures,
		"attack-ready threshold configurable",
		MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS == 10
	)

	var director_source := FileAccess.open("res://scripts/systems/military_director_v2.gd", FileAccess.READ)
	_expect(failures, "director source readable", director_source != null)
	if director_source != null:
		var text: String = director_source.get_as_text()
		director_source.close()
		_expect(failures, "director has assemble rally helper", text.contains("get_assemble_rally_point"))
		_expect(failures, "director transitions to CREEP", text.contains("_transition_to(State.CREEP"))
		_expect(failures, "director transitions to DEFEND", text.contains("_transition_to(State.DEFEND"))
		_expect(failures, "director checks construction reservations", text.contains("ConstructionReservations.overlaps_reserved_footprint"))
		_expect(failures, "director checks construction points", text.contains("get_construction_points"))
		_expect(failures, "director checks enemy workers", text.contains("_collect_enemy_workers"))
		_expect(failures, "director checks enemy resources", text.contains("GROUP_ENEMY_RESOURCES"))

	var commander_source := FileAccess.open("res://scripts/systems/army_commander_v2.gd", FileAccess.READ)
	_expect(failures, "commander source readable", commander_source != null)
	if commander_source != null:
		var commander_text: String = commander_source.get_as_text()
		commander_source.close()
		_expect(failures, "commander has assemble executor", commander_text.contains("_execute_assemble_mission"))
		_expect(failures, "commander uses attack-move for regroup", commander_text.contains("command_attack_move"))
		_expect(failures, "commander settles assembled units", commander_text.contains("_settle_unit"))
		_expect(failures, "commander keeps stable slots", commander_text.contains("_assemble_role_slots"))


func _verify_assemble_slot_stability(failures: PackedStringArray) -> void:
	var root := Node.new()
	root.name = "AssembleHarness"
	add_child(root)

	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	root.add_child(director)
	director.reset_match_state()

	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	root.add_child(commander)
	commander.reset_match_state()

	var frontline := Node3D.new()
	frontline.name = "Frontline"
	var ranged := Node3D.new()
	ranged.name = "Ranged"
	var siege := Node3D.new()
	siege.name = "Siege"
	var hero_stub := Node3D.new()
	hero_stub.name = "HeroStub"
	root.add_child(frontline)
	root.add_child(ranged)
	root.add_child(siege)
	root.add_child(hero_stub)

	var squad: ArmySquadV2 = director.get_main_squad()
	_expect(failures, "frontline joins assemble test squad", squad.try_add_member(frontline, ArmySquadV2.UnitRole.FRONTLINE))
	_expect(failures, "ranged joins assemble test squad", squad.try_add_member(ranged, ArmySquadV2.UnitRole.RANGED))
	_expect(failures, "siege joins assemble test squad", squad.try_add_member(siege, ArmySquadV2.UnitRole.SIEGE))
	_expect(failures, "hero joins assemble test squad", squad.try_add_member(hero_stub, ArmySquadV2.UnitRole.HERO))

	var rally := Vector3(10.0, 0.0, 10.0)
	var first_slots: Dictionary = commander.debug_get_assemble_slot_positions(rally)
	_expect(failures, "assemble slots created", first_slots.size() == 4)
	_expect(
		failures,
		"frontline ahead of ranged",
		(first_slots[frontline.get_instance_id()] as Vector3).z > (first_slots[ranged.get_instance_id()] as Vector3).z
	)
	_expect(
		failures,
		"siege behind ranged",
		(first_slots[siege.get_instance_id()] as Vector3).z < (first_slots[ranged.get_instance_id()] as Vector3).z
	)

	var reinforcement := Node3D.new()
	reinforcement.name = "Reinforcement"
	root.add_child(reinforcement)
	_expect(
		failures,
		"reinforcement joins assemble test squad",
		squad.try_add_member(reinforcement, ArmySquadV2.UnitRole.RANGED)
	)

	var second_slots: Dictionary = commander.debug_get_assemble_slot_positions(rally)
	_expect(failures, "reinforcement gets a slot", second_slots.has(reinforcement.get_instance_id()))
	_expect(
		failures,
		"existing frontline slot stable after reinforcement",
		first_slots[frontline.get_instance_id()] == second_slots[frontline.get_instance_id()]
	)
	_expect(
		failures,
		"existing ranged slot stable after reinforcement",
		first_slots[ranged.get_instance_id()] == second_slots[ranged.get_instance_id()]
	)
	_expect(
		failures,
		"reinforcement does not stack on existing ranged slot",
		second_slots[reinforcement.get_instance_id()] != second_slots[ranged.get_instance_id()]
	)

	root.queue_free()
	await get_tree().process_frame


func _verify_role_labels(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"role frontline label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.FRONTLINE) == "frontline"
	)
	_expect(
		failures,
		"role melee_guard label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.MELEE_GUARD) == "melee_guard"
	)
	_expect(
		failures,
		"role ranged label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.RANGED) == "ranged"
	)
	_expect(
		failures,
		"role cavalry label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.CAVALRY) == "cavalry"
	)
	_expect(
		failures,
		"role siege label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.SIEGE) == "siege"
	)
	_expect(
		failures,
		"role hero label",
		ArmySquadV2.role_to_string(ArmySquadV2.UnitRole.HERO) == "hero"
	)


func _verify_squad_membership_lifecycle(failures: PackedStringArray) -> void:
	var squad := ArmySquadV2.new()
	var unit_a := Node3D.new()
	var unit_b := Node3D.new()
	unit_a.name = "StubA"
	unit_b.name = "StubB"
	add_child(unit_a)
	add_child(unit_b)

	_expect(
		failures,
		"units join squad",
		squad.try_add_member(unit_a, ArmySquadV2.UnitRole.FRONTLINE)
	)
	_expect(
		failures,
		"second unit joins squad",
		squad.try_add_member(unit_b, ArmySquadV2.UnitRole.RANGED)
	)
	_expect(failures, "squad size 2 after joins", squad.get_size() == 2)
	_expect(
		failures,
		"no duplicated squad members",
		squad.try_add_member(unit_a, ArmySquadV2.UnitRole.FRONTLINE) == false
	)
	_expect(failures, "squad size still 2 after dup", squad.get_size() == 2)

	squad.recompute_metrics()
	_expect(failures, "role count frontline", squad.get_role_count(ArmySquadV2.UnitRole.FRONTLINE) == 1)
	_expect(failures, "role count ranged", squad.get_role_count(ArmySquadV2.UnitRole.RANGED) == 1)
	_expect(failures, "hero absent without hero", squad.hero_present == false)
	_expect(failures, "squad has leader/anchor", squad.leader != null)

	var dead_id: int = unit_a.get_instance_id()
	unit_a.queue_free()
	await get_tree().process_frame
	var removed: int = squad.sanitize()
	_expect(failures, "dead units leave safely", removed >= 1)
	_expect(failures, "squad size 1 after death", squad.get_size() == 1)
	_expect(failures, "no stale freed member id", squad.remove_by_instance_id(dead_id) == false)
	_expect(failures, "living member remains", squad.has_member(unit_b))

	unit_b.queue_free()
	await get_tree().process_frame
	squad.sanitize()
	_expect(failures, "squad empty after all freed", squad.get_size() == 0)


func _verify_director_pending_admission(failures: PackedStringArray) -> void:
	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	add_child(director)
	director.reset_match_state()

	var pending_unit := Node3D.new()
	pending_unit.name = "PendingStub"
	add_child(pending_unit)

	_expect(
		failures,
		"director enqueues pending reinforcement",
		director.debug_enqueue_pending_for_tests(pending_unit)
	)
	_expect(
		failures,
		"pending not in squad yet",
		director.get_main_squad().has_member(pending_unit) == false
	)
	_expect(
		failures,
		"pending list contains unit",
		director.get_pending_reinforcements_copy().size() == 1
	)

	director.debug_admit_pending_for_tests()
	_expect(
		failures,
		"units join when admitted (trained join path)",
		director.get_main_squad().has_member(pending_unit)
	)
	_expect(
		failures,
		"pending cleared after admit",
		director.get_pending_reinforcements_copy().is_empty()
	)
	_expect(failures, "no duplicate after re-enqueue", director.debug_enqueue_pending_for_tests(pending_unit) == false)

	## Immediate removal on tree exit.
	var pending_id: int = pending_unit.get_instance_id()
	pending_unit.queue_free()
	await get_tree().process_frame
	director.get_main_squad().sanitize()
	_expect(
		failures,
		"freed unit removed from squad",
		director.get_main_squad().get_size() == 0
	)
	_expect(
		failures,
		"no stale id membership",
		director.get_main_squad().remove_by_instance_id(pending_id) == false
	)

	## Commander receives squad but does not own membership mutation APIs in script.
	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	add_child(commander)
	var received: ArmySquadV2 = commander.get_active_squad()
	_expect(failures, "commander receives director squad", received == director.get_main_squad())

	commander.queue_free()
	director.queue_free()


func _verify_exclusion_helpers(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"null never roster eligible",
		ArmySquadV2.is_roster_eligible(null) == false
	)

	var orphan := Node3D.new()
	_expect(
		failures,
		"out-of-tree unit not eligible",
		ArmySquadV2.is_roster_eligible(orphan) == false
	)
	orphan.free()

	## Worker / building / creep exclusion gates live in ArmySquadV2.
	var source := FileAccess.open("res://scripts/systems/army_squad_v2.gd", FileAccess.READ)
	_expect(failures, "squad script readable", source != null)
	if source != null:
		var text: String = source.get_as_text()
		source.close()
		_expect(failures, "workers never join (eligible gate)", text.contains("unit is Worker"))
		_expect(failures, "buildings excluded", text.contains("unit is Building"))
		_expect(failures, "creeps excluded", text.contains("unit is NeutralCreep"))
		_expect(failures, "combat unit required", text.contains("is_combat_unit"))
		_expect(failures, "hero joins via Hero role", text.contains("unit is Hero"))
		_expect(failures, "hero role enum present", text.contains("UnitRole.HERO"))

	var director_source := FileAccess.open("res://scripts/systems/military_director_v2.gd", FileAccess.READ)
	_expect(failures, "director script readable", director_source != null)
	if director_source != null:
		var director_text: String = director_source.get_as_text()
		director_source.close()
		_expect(
			failures,
			"director owns squad membership",
			director_text.contains("Owns the authoritative army roster")
		)
		_expect(
			failures,
			"reinforcements wait for safe states",
			director_text.contains("_can_admit_reinforcements")
		)
		_expect(
			failures,
			"never solo-push pending units",
			director_text.contains("Never send them alone across the map")
		)


func _verify_perf_squad_api(failures: PackedStringArray) -> void:
	PerfCounters.set_military_ai_v2_squad_status(7, true, "F2 G1 R2 C1 S1 H1", 420.0)
	_expect(failures, "F3 squad size", PerfCounters.get_military_ai_v2_squad_size() == 7)
	_expect(failures, "F3 hero present", PerfCounters.get_military_ai_v2_hero_present() == true)
	_expect(
		failures,
		"F3 role counts",
		PerfCounters.get_military_ai_v2_role_counts() == "F2 G1 R2 C1 S1 H1"
	)
	_expect(
		failures,
		"F3 estimated army strength",
		is_equal_approx(PerfCounters.get_military_ai_v2_army_strength(), 420.0)
	)

	var overlay_source := FileAccess.open("res://scripts/debug/perf_debug_overlay.gd", FileAccess.READ)
	_expect(failures, "overlay script readable", overlay_source != null)
	if overlay_source != null:
		var text: String = overlay_source.get_as_text()
		overlay_source.close()
		_expect(failures, "overlay shows V2 Squad Size", text.contains("V2 Squad Size"))
		_expect(failures, "overlay shows V2 Hero Present", text.contains("V2 Hero Present"))
		_expect(failures, "overlay shows V2 Role Counts", text.contains("V2 Role Counts"))
		_expect(failures, "overlay shows V2 Army Strength", text.contains("V2 Army Strength"))
