extends Node3D

## Focused ASSEMBLE → CREEP progression probe with real map camps/bases.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_creep_progression.tscn

const REPORT_PATH := "user://ai_creep_progression_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const CAMPS_SCENE: PackedScene = preload("res://scenes/world/neutral_creep_camps.tscn")
const NAV_SCRIPT: Script = preload("res://scripts/systems/navigation_region_setup.gd")


func _ready() -> void:
	var failures: PackedStringArray = []
	EnemyArmyCommand.reset_match_state()
	CreepCampSafety.reset_match_state()
	CombatTargetValidation.reset_match_state()
	EnemyAIDebug.set_enabled(true)

	var nav := NavigationRegion3D.new()
	nav.set_script(NAV_SCRIPT)
	add_child(nav)

	var camps: Node3D = CAMPS_SCENE.instantiate() as Node3D
	camps.name = "NeutralCreepCamps"
	add_child(camps)

	var enemy_cc: Building = CC_SCENE.instantiate() as Building
	enemy_cc.name = "EnemyCommandCenter"
	enemy_cc.team_id = 1
	add_child(enemy_cc)
	enemy_cc.global_position = Vector3(31, 1, 28)
	if enemy_cc.has_method("set_completed"):
		enemy_cc.call("set_completed")
	enemy_cc.add_to_group(&"enemy_command_center")
	enemy_cc.add_to_group(&"buildings")

	var player_cc: Building = CC_SCENE.instantiate() as Building
	player_cc.name = "PlayerCommandCenter"
	player_cc.team_id = 0
	add_child(player_cc)
	player_cc.global_position = Vector3(-31, 1, -28)
	if player_cc.has_method("set_completed"):
		player_cc.call("set_completed")
	player_cc.add_to_group(&"player_command_center")
	player_cc.add_to_group(&"buildings")

	var root := Node.new()
	root.name = "MatchSystems"
	add_child(root)

	var ai_state := AIPlayerState.new()
	ai_state.name = "AIPlayerState"
	root.add_child(ai_state)

	var creep_manager := EnemyCreepManager.new()
	creep_manager.name = "EnemyCreepManager"
	root.add_child(creep_manager)
	creep_manager.set_process(false)

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
	commander._creep_manager = creep_manager

	EnemyArmyCommand.bind_match_composition(ai_state, commander)

	## Wait for nav bake + map sync.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	for _i in range(8):
		await get_tree().physics_frame
	var world: World3D = get_world_3d()
	if world != null and world.navigation_map.is_valid():
		NavigationServer3D.map_force_update(world.navigation_map)
		await get_tree().physics_frame
		var sample: Vector3 = NavigationServer3D.map_get_closest_point(
			world.navigation_map,
			Vector3(10.0, 0.0, 10.0)
		)
		print(
			"[CREEP PROBE] nav_sample=(%.2f, %.2f, %.2f) active=%s"
			% [sample.x, sample.y, sample.z, str(NavigationServer3D.map_is_active(world.navigation_map))]
		)

	var rally: Vector3 = director.get_assemble_rally_point()
	if rally == Vector3.ZERO:
		rally = enemy_cc.global_position + EnemyArmyCommand.ARMY_RALLY_OFFSET
	print("[CREEP PROBE] rally=(%.1f, %.1f)" % [rally.x, rally.z])

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	hero.name = "EnemyHero"
	hero.team_id = 1
	add_child(hero)
	hero.global_position = rally + Vector3(0.0, 0.0, 0.5)
	hero.add_to_group(&"enemies")
	hero.add_to_group(&"heroes")
	hero.add_to_group(&"enemy_combat_units")

	var units: Array = [hero]
	for i in range(MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS):
		var spear: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		spear.name = "EnemySpear%d" % i
		spear.team_id = 1
		add_child(spear)
		spear.global_position = rally + Vector3(float(i) * 1.2 - 2.0, 0.0, -1.0)
		spear.add_to_group(&"enemies")
		spear.add_to_group(&"enemy_combat_units")
		units.append(spear)
		_expect(
			failures,
			"admit spear %d" % i,
			director.get_main_squad().try_add_member(spear, ArmySquadV2.UnitRole.FRONTLINE)
		)

	_expect(
		failures,
		"admit real hero",
		director.get_main_squad().try_add_member(hero, ArmySquadV2.UnitRole.HERO)
	)
	director.get_main_squad().recompute_metrics()

	_expect(failures, "hero_present", director.get_main_squad().hero_present)
	_expect(failures, "creep_ready", director.is_creep_ready())
	_expect(
		failures,
		"military escorts >= threshold",
		director.get_military_unit_count() >= MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS
	)

	var tree: SceneTree = get_tree()
	var creep_army: Array = director._get_creep_squad_units()
	var commit_block: String = director._describe_creep_commit_block(tree, creep_army, creep_manager)
	print("[CREEP PROBE] commit_block='%s' army_power=%d camps=%d" % [
		commit_block if not commit_block.is_empty() else "-",
		EnemyArmyCommand.estimate_military_power(creep_army),
		creep_manager._collect_creep_camps(tree).size(),
	])

	var origin: Vector3 = director.get_main_squad().center
	if origin == Vector3.ZERO:
		origin = EnemyArmyCommand.compute_army_center(creep_army)
	if origin == Vector3.ZERO:
		origin = rally

	for camp: Node3D in creep_manager._collect_creep_camps(tree):
		var dist: float = EnemyArmyCommand.horizontal_distance(origin, camp.global_position)
		var enemy_side: bool = creep_manager._is_enemy_side_camp(camp, rally, tree)
		var cleared: bool = creep_manager._is_camp_cleared(tree, camp)
		var contested: bool = creep_manager._is_player_contesting_camp(tree, camp)
		var reachable: bool = director._is_creep_camp_reachable(origin, camp.global_position)
		var score: float = director._score_creep_camp(
			tree,
			creep_manager,
			camp,
			creep_army,
			origin,
			rally
		)
		var power: int = creep_manager._estimate_camp_power(camp)
		var path_dbg: String = _debug_path(origin, camp.global_position)
		print(
			"[CREEP CAMP] %s dist=%.1f side=%s cleared=%s contested=%s reach=%s power=%d score=%.1f %s"
			% [
				camp.name,
				dist,
				str(enemy_side),
				str(cleared),
				str(contested),
				str(reachable),
				power,
				score,
				path_dbg,
			]
		)

	director._transition_to(MilitaryDirectorV2.State.ASSEMBLE, "creep probe assemble", rally)
	var selected: bool = director._evaluate_creep_strategy(tree, rally)
	print(
		"[CREEP PROBE] evaluate_creep=%s state=%s block='%s' reserved=%d"
		% [
			str(selected),
			director.get_state_name(),
			director._last_creep_block_reason if not director._last_creep_block_reason.is_empty() else "-",
			director.get_reserved_creep_camp_id(),
		]
	)

	_expect(failures, "MilitaryDirectorV2 selects CREEP", selected)
	_expect(
		failures,
		"director state is CREEP",
		director.get_state() == MilitaryDirectorV2.State.CREEP
	)

	var mission: ArmyMissionV2 = director.get_mission()
	_expect(failures, "executable CREEP mission published", mission != null)
	if mission != null:
		_expect(
			failures,
			"mission type CREEP",
			mission.mission_type == ArmyMissionV2.MissionType.CREEP
		)
		_expect(
			failures,
			"mission has living camp target",
			mission.get_alive_target_object() != null
		)

	## Commander executes once toward the real camp objective.
	commander._creep_order_reissue_timer = ArmyCommanderV2.CREEP_ORDER_REISSUE_SECONDS
	commander._creep_regroup_hold_timer = 0.0
	if mission != null and director.get_state() == MilitaryDirectorV2.State.CREEP:
		commander._sync_execution_authority(director, mission)
		commander._execute_creep_mission(director, mission, director.get_main_squad())
	## Drain queued group orders onto units (same path runtime uses each frame).
	for _drain in range(8):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame
	var exec_ok: bool = EnemyArmyCommand.is_creeping_executable_active()
	var pending_orders: int = EnemyArmyCommand.get_pending_group_order_count()
	print(
		"[CREEP PROBE] exec=%s creeping=%s reserved=%s pending=%d block='%s' last_route='%s'"
		% [
			EnemyArmyCommand.executable_mission_to_label(EnemyArmyCommand.get_executable_mission()),
			str(exec_ok),
			str(director.has_reserved_creep_camp()),
			pending_orders,
			director._last_creep_block_reason if not director._last_creep_block_reason.is_empty() else "-",
			EnemyArmyCommand.get_last_squad_route_failure_reason(),
		]
	)
	_expect(failures, "ArmyCommanderV2 activates CREEPING executable", exec_ok)

	var camp_target: Node3D = mission.get_alive_target_object() if mission != null else null
	var has_objective: bool = (
		director.has_reserved_creep_camp()
		and camp_target != null
		and exec_ok
	)
	_expect(failures, "creep objective reserved for squad orders", has_objective)

	## Prove at least one unit received a real creep travel order toward the camp.
	var ordered_toward_camp: int = 0
	var any_move: int = 0
	if camp_target != null:
		var camp_from_rally: float = EnemyArmyCommand.horizontal_distance(
			rally,
			camp_target.global_position
		)
		for entry: Variant in units:
			if not NodeSafety.is_alive_node(entry) or not entry is Unit:
				continue
			var unit: Unit = entry as Unit
			var dest: Vector3 = Vector3.ZERO
			if unit.has_move_target:
				dest = unit.get_movement_destination()
			print(
				"[CREEP UNIT] %s move=%s dest=(%.1f, %.1f) camp_dist=%.1f"
				% [
					unit.name,
					str(unit.has_move_target),
					dest.x,
					dest.z,
					EnemyArmyCommand.horizontal_distance(dest, camp_target.global_position) if dest != Vector3.ZERO else -1.0,
				]
			)
			if not unit.has_move_target or dest == Vector3.ZERO:
				continue
			any_move += 1
			var dest_to_camp: float = EnemyArmyCommand.horizontal_distance(
				dest,
				camp_target.global_position
			)
			## Slot targets sit on the shared route toward the camp (not only at the camp).
			if dest_to_camp < camp_from_rally - 0.5:
				ordered_toward_camp += 1
	print("[CREEP PROBE] ordered_toward_camp=%d any_move=%d" % [ordered_toward_camp, any_move])
	_expect(
		failures,
		"at least one unit ordered toward real creep camp",
		ordered_toward_camp > 0
	)

	var report: String
	if failures.is_empty():
		report = "PASS ai_creep_progression\n"
	else:
		report = "FAIL ai_creep_progression\n" + "\n".join(failures) + "\n"
	_write_report(report)
	print(report)

	for entry: Variant in units:
		if NodeSafety.is_alive_node(entry):
			(entry as Node).queue_free()
	commander.queue_free()
	director.queue_free()
	creep_manager.queue_free()
	root.queue_free()
	EnemyArmyCommand.reset_match_state()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)


func _debug_path(from_position: Vector3, to_position: Vector3) -> String:
	if not get_tree().current_scene is Node3D:
		return "path=no_scene"
	var world: World3D = (get_tree().current_scene as Node3D).get_world_3d()
	if world == null:
		return "path=no_world"
	var nav_map: RID = world.navigation_map
	if not nav_map.is_valid():
		return "path=invalid_map"
	if not NavigationServer3D.map_is_active(nav_map):
		return "path=inactive"
	var start: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, from_position)
	var target: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to_position)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start, target, true)
	if path.is_empty():
		return "path=empty start=(%.1f,%.1f,%.1f) target=(%.1f,%.1f,%.1f)" % [
			start.x, start.y, start.z, target.x, target.y, target.z
		]
	var end: Vector3 = path[path.size() - 1]
	var end_dist: float = EnemyArmyCommand.horizontal_distance(end, target)
	return "path=n=%d end_dist=%.2f start_delta=%.2f target_delta=%.2f" % [
		path.size(),
		end_dist,
		EnemyArmyCommand.horizontal_distance(start, from_position),
		EnemyArmyCommand.horizontal_distance(target, to_position),
	]


func _write_report(report: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
