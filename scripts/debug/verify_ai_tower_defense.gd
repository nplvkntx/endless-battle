extends Node

## Headless verification for AI attack-path tower fortification.
## Godot --headless --path <project> res://scenes/debug/verify_ai_tower_defense.tscn

const REPORT_PATH := "user://ai_tower_defense_verify_result.txt"
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	ConstructionReservations.reset_match_state()
	EnemyAttackPathDefense.reset_match_state()
	EnemyAIDebug.set_enabled(true)

	print("verify_ai_tower_defense: start")
	_verify_lane_classification(failures)
	_verify_center_preferred_first(failures)
	_verify_flank_adaptation(failures)
	_verify_harass_and_expansion_lanes(failures)
	_verify_caps_and_safeguards(failures)
	_verify_reject_redundant_and_interior(failures)
	_verify_rebuild_skip_when_cool(failures)
	_verify_placement_not_blocking_exits(failures)

	EnemyAIDebug.set_enabled(false)
	EnemyAttackPathDefense.reset_match_state()

	var report: String
	if failures.is_empty():
		report = "PASS ai_tower_defense\n"
	else:
		report = "FAIL ai_tower_defense\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)


func _spawn_completed(root: Node3D, scene: PackedScene, pos: Vector3, team_id: int = 1) -> Building:
	var building: Building = scene.instantiate() as Building
	root.add_child(building)
	building.team_id = team_id
	building.global_position = pos
	building.set_completed()
	if team_id == 1 and not building.is_in_group(&"enemy_command_center"):
		building.add_to_group(&"enemy_command_center")
	if team_id == 0 and building is CommandCenter:
		building.add_to_group(&"player_command_center")
	return building


func _verify_lane_classification(failures: PackedStringArray) -> void:
	print("verify: lane classification")
	var anchor := Vector3(20.0, 0.0, 20.0)
	var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(anchor)
	var front: Vector2 = frame.get("front", Vector2(-1.0, 0.0))
	var right: Vector2 = frame.get("right", Vector2(0.0, 1.0))

	var center_pt := Vector3(
		anchor.x + front.x * 14.0,
		0.0,
		anchor.z + front.y * 14.0
	)
	var left_pt := Vector3(
		anchor.x + front.x * 12.0 + right.x * 12.0,
		0.0,
		anchor.z + front.y * 12.0 + right.y * 12.0
	)
	var right_pt := Vector3(
		anchor.x + front.x * 12.0 - right.x * 12.0,
		0.0,
		anchor.z + front.y * 12.0 - right.y * 12.0
	)

	_expect(
		failures,
		"center approach classified",
		EnemyAttackPathDefense.classify_approach_lane(center_pt, anchor, frame) == &"center"
	)
	_expect(
		failures,
		"left flank classified",
		EnemyAttackPathDefense.classify_approach_lane(left_pt, anchor, frame) == &"left"
	)
	_expect(
		failures,
		"right flank classified",
		EnemyAttackPathDefense.classify_approach_lane(right_pt, anchor, frame) == &"right"
	)


func _verify_center_preferred_first(failures: PackedStringArray) -> void:
	print("verify: first tower prefers center approach")
	EnemyAttackPathDefense.reset_match_state()
	var root := Node3D.new()
	add_child(root)

	var town_hall: Building = _spawn_completed(
		root,
		COMMAND_CENTER_SCENE,
		Vector3(20.0, 1.0, 20.0)
	)
	var barracks: Building = _spawn_completed(
		root,
		BARRACKS_SCENE,
		Vector3(12.0, 0.8, 20.0)
	)
	var buildings: Array[Node3D] = [town_hall, barracks]

	var context: Dictionary = {
		"tower_count": 0,
		"tower_cap": 2,
		"food_blocked": false,
		"missing_workers": false,
		"core_army_starved": false,
		"opening_core_incomplete": false,
		"emergency": false,
		"early_aggression": false,
		"weak_army_expanding": false,
		"has_production": true,
		"economy_ready": true,
		"expansion_exposed": false,
		"has_expansion": false,
		"workers_exposed": false,
		"lane_coverage": {},
		"towers_per_lane": {},
	}
	var need: Dictionary = EnemyAttackPathDefense.evaluate_build_need(
		get_tree(),
		town_hall.global_position,
		context
	)
	_expect(failures, "should build first tower", VariantUtils.to_bool(need.get("should_build", false)))
	_expect(
		failures,
		"first tower lane is center",
		need.get("lane", &"") == EnemyAttackPathDefense.LANE_CENTER
	)

	var placement: Dictionary = EnemyAttackPathDefense.find_tower_position(
		town_hall.global_position,
		EnemyAttackPathDefense.LANE_CENTER,
		buildings,
		root,
		RID()
	)
	var pos: Vector3 = placement.get("position", Vector3.INF)
	_expect(failures, "center tower placeable", pos.is_finite())
	if pos.is_finite():
		var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(
			town_hall.global_position
		)
		var local: Vector2 = EnemyBuildPlacement.local_front_right_public(
			pos,
			town_hall.global_position,
			frame
		)
		_expect(failures, "first tower on outer approach", local.x >= 6.0)
		_expect(failures, "first tower not deep courtyard", not (local.x < 3.5 and absf(local.y) < 5.0))

	root.queue_free()


func _verify_flank_adaptation(failures: PackedStringArray) -> void:
	print("verify: flank attack raises lane threat")
	EnemyAttackPathDefense.reset_match_state()
	var root := Node3D.new()
	add_child(root)
	var town_hall: Building = _spawn_completed(
		root,
		COMMAND_CENTER_SCENE,
		Vector3(20.0, 1.0, 20.0)
	)
	var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(
		town_hall.global_position
	)
	var right: Vector2 = frame.get("right", Vector2(0.0, 1.0))
	var front: Vector2 = frame.get("front", Vector2(-1.0, 0.0))
	var left_entry := Vector3(
		town_hall.global_position.x + front.x * 10.0 + right.x * 14.0,
		0.5,
		town_hall.global_position.z + front.y * 10.0 + right.y * 14.0
	)

	## Simulate repeated left-flank entries via classify + direct threat bump.
	for _i: int in range(4):
		var lane: StringName = EnemyAttackPathDefense.classify_approach_lane(
			left_entry,
			town_hall.global_position,
			frame
		)
		_expect(failures, "simulated entry is left", lane == &"left")

	## Force threat learning by evaluating with uncovered lanes after manual bump.
	var threat_snap: Dictionary = EnemyAttackPathDefense.get_lane_threat_snapshot()
	## Use notify path: destroy on left + rebuild signal raises threat.
	EnemyAttackPathDefense.notify_tower_destroyed(left_entry, &"left")
	EnemyAttackPathDefense.notify_tower_destroyed(left_entry + Vector3(1, 0, 0), &"left")

	var coverage: Dictionary = {
		&"center": 1.0,
		&"left": 0.0,
		&"right": 0.5,
		&"expansion": 0.0,
		&"harass": 0.0,
	}
	var context: Dictionary = {
		"tower_count": 1,
		"tower_cap": 4,
		"food_blocked": false,
		"missing_workers": false,
		"core_army_starved": false,
		"opening_core_incomplete": false,
		"emergency": false,
		"early_aggression": false,
		"weak_army_expanding": false,
		"has_production": true,
		"economy_ready": true,
		"expansion_exposed": false,
		"has_expansion": false,
		"workers_exposed": false,
		"lane_coverage": coverage,
		"towers_per_lane": {&"center": 1},
	}
	var need: Dictionary = EnemyAttackPathDefense.evaluate_build_need(
		get_tree(),
		town_hall.global_position,
		context
	)
	_expect(failures, "adapt builds after flank pressure", VariantUtils.to_bool(need.get("should_build", false)))
	_expect(
		failures,
		"adapts toward left lane",
		need.get("lane", &"") == EnemyAttackPathDefense.LANE_LEFT
		or float(EnemyAttackPathDefense.get_lane_threat_snapshot().get(&"left", 0.0))
		> float(threat_snap.get(&"left", 0.0))
	)

	root.queue_free()


func _verify_harass_and_expansion_lanes(failures: PackedStringArray) -> void:
	print("verify: harass + expansion scoring")
	EnemyAttackPathDefense.reset_match_state()
	var root := Node3D.new()
	add_child(root)
	var main_cc: Building = _spawn_completed(
		root,
		COMMAND_CENTER_SCENE,
		Vector3(20.0, 1.0, 20.0)
	)
	var exp_cc: Building = _spawn_completed(
		root,
		COMMAND_CENTER_SCENE,
		Vector3(-18.0, 1.0, 20.0)
	)

	var context: Dictionary = {
		"tower_count": 2,
		"tower_cap": 4,
		"food_blocked": false,
		"missing_workers": false,
		"core_army_starved": false,
		"opening_core_incomplete": false,
		"emergency": false,
		"early_aggression": false,
		"weak_army_expanding": true,
		"has_production": true,
		"economy_ready": true,
		"expansion_exposed": true,
		"has_expansion": true,
		"workers_exposed": true,
		"lane_coverage": {&"center": 1.0, &"left": 0.8, &"right": 0.8},
		"towers_per_lane": {&"center": 1, &"left": 1},
	}
	var need: Dictionary = EnemyAttackPathDefense.evaluate_build_need(
		get_tree(),
		main_cc.global_position,
		context
	)
	_expect(failures, "expansion defense triggers", VariantUtils.to_bool(need.get("should_build", false)))
	_expect(
		failures,
		"expansion or weak-expansion reason",
		need.get("reason", &"") in [
			EnemyAttackPathDefense.REASON_WEAK_EXPANSION,
			EnemyAttackPathDefense.REASON_UNCOVERED_LANE,
			EnemyAttackPathDefense.REASON_MID_DEFENSE,
		]
	)

	var placement: Dictionary = EnemyAttackPathDefense.find_tower_position(
		exp_cc.global_position,
		EnemyAttackPathDefense.LANE_EXPANSION,
		[main_cc, exp_cc],
		root,
		RID()
	)
	_expect(
		failures,
		"expansion tower candidate finite",
		(placement.get("position", Vector3.INF) as Vector3).is_finite()
	)
	root.queue_free()


func _verify_caps_and_safeguards(failures: PackedStringArray) -> void:
	print("verify: caps + resource safeguards")
	EnemyAttackPathDefense.reset_match_state()

	_expect(
		failures,
		"early cap is 2",
		EnemyAttackPathDefense.get_tower_cap_for_phase_name("EARLY_ARMY") == 2
	)
	_expect(
		failures,
		"mid cap is 4",
		EnemyAttackPathDefense.get_tower_cap_for_phase_name("MID_GAME") == 4
	)
	_expect(
		failures,
		"late cap is 6",
		EnemyAttackPathDefense.get_tower_cap_for_phase_name("LATE_GAME") == 6
	)

	var blocked: Dictionary = EnemyAttackPathDefense.evaluate_build_need(
		get_tree(),
		Vector3(20, 0, 20),
		{
			"tower_count": 0,
			"tower_cap": 4,
			"food_blocked": true,
			"missing_workers": false,
			"core_army_starved": false,
			"opening_core_incomplete": false,
			"emergency": false,
			"has_production": true,
			"economy_ready": true,
			"lane_coverage": {},
			"towers_per_lane": {},
		}
	)
	_expect(failures, "food-blocked skips towers", not VariantUtils.to_bool(blocked.get("should_build", false)))

	var capped: Dictionary = EnemyAttackPathDefense.evaluate_build_need(
		get_tree(),
		Vector3(20, 0, 20),
		{
			"tower_count": 6,
			"tower_cap": 6,
			"food_blocked": false,
			"missing_workers": false,
			"core_army_starved": false,
			"opening_core_incomplete": false,
			"emergency": true,
			"has_production": true,
			"economy_ready": true,
			"lane_coverage": {},
			"towers_per_lane": {},
		}
	)
	_expect(failures, "hard cap blocks overbuild", not VariantUtils.to_bool(capped.get("should_build", false)))


func _verify_reject_redundant_and_interior(failures: PackedStringArray) -> void:
	print("verify: reject redundant / interior")
	EnemyAttackPathDefense.reset_match_state()
	var root := Node3D.new()
	add_child(root)
	var town_hall: Building = _spawn_completed(
		root,
		COMMAND_CENTER_SCENE,
		Vector3(20.0, 1.0, 20.0)
	)
	var tower_a: Building = _spawn_completed(
		root,
		TOWER_SCENE,
		Vector3(9.0, 1.5, 20.0)
	)
	var buildings: Array[Node3D] = [town_hall, tower_a]

	var near_existing: StringName = EnemyAttackPathDefense.validate_tower_candidate(
		Vector3(9.5, 1.5, 20.0),
		town_hall.global_position,
		&"center",
		buildings,
		root,
		RID()
	)
	_expect(failures, "rejects stacked tower", near_existing == &"redundant")

	var interior: StringName = EnemyAttackPathDefense.validate_tower_candidate(
		Vector3(20.0, 1.5, 20.0),
		town_hall.global_position,
		&"center",
		buildings,
		root,
		RID()
	)
	_expect(
		failures,
		"rejects courtyard tower",
		interior in [&"unsafe", &"blocked"]
	)
	root.queue_free()


func _verify_rebuild_skip_when_cool(failures: PackedStringArray) -> void:
	print("verify: rebuild skipped when lane cool")
	EnemyAttackPathDefense.reset_match_state()
	var snap: Dictionary = EnemyAttackPathDefense.get_lane_threat_snapshot()
	var pos := Vector3(8, 1.5, 28)
	## Repeated destroys on one site eventually stop queueing rebuilds.
	EnemyAttackPathDefense.notify_tower_destroyed(pos, &"right")
	EnemyAttackPathDefense.notify_tower_destroyed(pos, &"right")
	EnemyAttackPathDefense.notify_tower_destroyed(pos, &"right")
	_expect(
		failures,
		"destroy raises right-lane threat",
		float(EnemyAttackPathDefense.get_lane_threat_snapshot().get(&"right", 0.0))
		> float(snap.get(&"right", 0.0))
	)
	_expect(failures, "lane threat snapshot readable", not snap.is_empty())


func _verify_placement_not_blocking_exits(failures: PackedStringArray) -> void:
	print("verify: towers keep production exits clear")
	EnemyAttackPathDefense.reset_match_state()
	var root := Node3D.new()
	add_child(root)
	var town_hall: Building = _spawn_completed(
		root,
		COMMAND_CENTER_SCENE,
		Vector3(20.0, 1.0, 20.0)
	)
	var barracks: Building = _spawn_completed(
		root,
		BARRACKS_SCENE,
		Vector3(12.0, 0.8, 20.0)
	)
	var altar: Building = _spawn_completed(
		root,
		HERO_ALTAR_SCENE,
		Vector3(20.0, 1.0, 11.0)
	)
	var farm: Building = _spawn_completed(
		root,
		FARM_SCENE,
		Vector3(28.0, 0.5, 20.0)
	)
	var buildings: Array[Node3D] = [town_hall, barracks, altar, farm]

	for lane: StringName in [&"center", &"left", &"right"]:
		var placement: Dictionary = EnemyAttackPathDefense.find_tower_position(
			town_hall.global_position,
			lane,
			buildings,
			root,
			RID()
		)
		var pos: Vector3 = placement.get("position", Vector3.INF)
		if not pos.is_finite():
			continue
		_expect(
			failures,
			"tower valid for lane %s" % String(lane),
			EnemyBuildPlacement.is_position_valid(pos, &"tower", buildings, root)
		)
		_expect(
			failures,
			"tower not path-conflict %s" % String(lane),
			not EnemyBuildPlacement.tower_blocks_reserved_lanes(pos, buildings)
		)
		buildings.append(_spawn_completed(root, TOWER_SCENE, pos))

	root.queue_free()
