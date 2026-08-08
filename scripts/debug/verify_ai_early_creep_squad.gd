extends Node3D

## Focused early CREEP squad formation + execution regression.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_early_creep_squad.tscn

const REPORT_PATH := "user://ai_early_creep_squad_verify_result.txt"
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

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	for _i in range(8):
		await get_tree().physics_frame
	var world: World3D = get_world_3d()
	if world != null and world.navigation_map.is_valid():
		NavigationServer3D.map_force_update(world.navigation_map)
		await get_tree().physics_frame

	var rally: Vector3 = director.get_assemble_rally_point()
	if rally == Vector3.ZERO:
		rally = enemy_cc.global_position + EnemyArmyCommand.ARMY_RALLY_OFFSET

	## --- Gate: hero only / thin escort must NOT start normal early CREEP ---
	var lone_hero: Hero = _spawn_enemy_hero(rally + Vector3(0.0, 0.0, 0.5))
	EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), lone_hero)
	await _admit_spawned_military(director)
	_expect(failures, "thin: hero present", director.get_main_squad().hero_present)
	_expect(failures, "thin: not creep_ready with 0 escorts", not director.is_creep_ready())
	director._transition_to(MilitaryDirectorV2.State.ASSEMBLE, "thin gate", rally)
	var thin_selected: bool = director._evaluate_creep_strategy(get_tree(), rally)
	_expect(failures, "thin: CREEP rejected with hero only", not thin_selected)
	_expect(
		failures,
		"thin: remains ASSEMBLE",
		director.get_state() == MilitaryDirectorV2.State.ASSEMBLE
	)

	var thin_spears: Array = []
	for i in range(MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS - 1):
		var spear: Spearman = _spawn_enemy_spear(rally + Vector3(float(i) * 1.1 - 1.5, 0.0, -1.0), i)
		EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), spear)
		thin_spears.append(spear)
	await _admit_spawned_military(director)
	print(
		"[EARLY CREEP SQUAD] thin4 ready=%s mil=%d squad=%d pending=%d pool=%d state=%s"
		% [
			str(director.is_creep_ready()),
			director.get_military_unit_count(),
			director.get_main_squad().get_size(),
			director.get_pending_reinforcements_copy().size(),
			EnemyArmyCommand.get_reinforcement_pool_count(),
			director.get_state_name(),
		]
	)
	_expect(
		failures,
		"thin: still not creep_ready at 4 escorts",
		not director.is_creep_ready()
	)
	thin_selected = director._evaluate_creep_strategy(get_tree(), rally)
	print(
		"[EARLY CREEP SQUAD] thin4 evaluate=%s state=%s block='%s'"
		% [
			str(thin_selected),
			director.get_state_name(),
			director._last_creep_block_reason if not director._last_creep_block_reason.is_empty() else "-",
		]
	)
	_expect(failures, "thin: CREEP rejected with 4 escorts", not thin_selected)
	_expect(
		failures,
		"thin: still ASSEMBLE after 4-escort reject",
		director.get_state() == MilitaryDirectorV2.State.ASSEMBLE
	)

	## --- Ready force: hero + 5 via real spawn reinforcement hold ---
	var fifth: Spearman = _spawn_enemy_spear(rally + Vector3(4.0, 0.0, -1.0), 99)
	EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), fifth)
	await _admit_spawned_military(director)
	print(
		"[EARLY CREEP SQUAD] ready mil=%d squad=%d pending=%d pool=%d members=%s"
		% [
			director.get_military_unit_count(),
			director.get_main_squad().get_size(),
			director.get_pending_reinforcements_copy().size(),
			EnemyArmyCommand.get_reinforcement_pool_count(),
			_squad_member_names(director.get_main_squad()),
		]
	)

	## Prove the pre-fix failure mode is gone: admitted squad members leave the hold pool.
	var still_held: int = 0
	for entry: Variant in director.get_main_squad().get_members_copy():
		if EnemyArmyCommand.is_reinforcement_waiting(entry):
			still_held += 1
	_expect(failures, "admitted squad released from reinforcement pool", still_held == 0)

	_expect(failures, "ready: creep_ready with hero+5", director.is_creep_ready())
	_expect(
		failures,
		"ready: military count >= threshold",
		director.get_military_unit_count() >= MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS
	)

	director._transition_to(MilitaryDirectorV2.State.ASSEMBLE, "ready assemble", rally)
	var selected: bool = director._evaluate_creep_strategy(get_tree(), rally)
	_expect(failures, "ready: CREEP mission selected", selected)
	_expect(failures, "ready: state CREEP", director.get_state() == MilitaryDirectorV2.State.CREEP)

	var squad: ArmySquadV2 = director.get_main_squad()
	var squad_has_hero: bool = false
	var squad_pikemen: int = 0
	for entry: Variant in squad.get_members_copy():
		if entry is Hero:
			squad_has_hero = true
		elif entry is Spearman:
			squad_pikemen += 1
	_expect(failures, "squad contains hero", squad_has_hero)
	_expect(
		failures,
		"squad contains 5 pikemen",
		squad_pikemen >= MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS
	)

	var mission: ArmyMissionV2 = director.get_mission()
	_expect(failures, "CREEP mission published", mission != null)
	var camp_target: Node3D = null
	if mission != null:
		_expect(
			failures,
			"mission type CREEP",
			mission.mission_type == ArmyMissionV2.MissionType.CREEP
		)
		camp_target = mission.get_alive_target_object()
		_expect(failures, "mission has living camp", camp_target != null)

	commander._creep_order_reissue_timer = ArmyCommanderV2.CREEP_ORDER_REISSUE_SECONDS
	commander._creep_regroup_hold_timer = 0.0
	if mission != null and director.get_state() == MilitaryDirectorV2.State.CREEP:
		commander._sync_execution_authority(director, mission)
		commander._execute_creep_mission(director, mission, squad)
	for _drain in range(10):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame

	_expect(
		failures,
		"CREEPING executable active",
		EnemyArmyCommand.is_creeping_executable_active()
	)

	var ordered_toward_camp: int = 0
	var hero_ordered: bool = false
	var pikeman_ordered: bool = false
	if camp_target != null:
		var camp_from_rally: float = EnemyArmyCommand.horizontal_distance(
			rally,
			camp_target.global_position
		)
		for entry: Variant in squad.get_members_copy():
			if not NodeSafety.is_alive_node(entry) or not entry is Unit:
				continue
			var unit: Unit = entry as Unit
			var dest: Vector3 = Vector3.ZERO
			if unit.has_move_target:
				dest = unit.get_movement_destination()
			if not unit.has_move_target or dest == Vector3.ZERO:
				continue
			var dest_to_camp: float = EnemyArmyCommand.horizontal_distance(
				dest,
				camp_target.global_position
			)
			if dest_to_camp < camp_from_rally - 0.5:
				ordered_toward_camp += 1
				if unit is Hero:
					hero_ordered = true
				elif unit is Spearman:
					pikeman_ordered = true
	_expect(failures, "squad received movement toward camp", ordered_toward_camp > 0)
	_expect(
		failures,
		"hero or pikeman ordered toward camp",
		hero_ordered or pikeman_ordered
	)
	_expect(failures, "pikeman ordered toward camp", pikeman_ordered)

	## Teleport squad onto the camp so engage/focus-fire path is reachable.
	if camp_target != null:
		var idx: int = 0
		for entry: Variant in squad.get_members_copy():
			if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
				continue
			(entry as Node3D).global_position = (
				camp_target.global_position
				+ Vector3(float(idx) * 0.8 - 1.5, 0.0, 1.5)
			)
			idx += 1
		squad.recompute_metrics()

	commander._creep_order_reissue_timer = ArmyCommanderV2.CREEP_ORDER_REISSUE_SECONDS
	commander._creep_focus_reissue_timer = EnemyCreepManager.FOCUS_REISSUE_SECONDS
	commander._creep_regroup_hold_timer = 0.0
	commander._execute_creep_mission(director, mission, squad)
	for _drain2 in range(10):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame

	var hero_has_combat: bool = false
	var pike_has_combat: bool = false
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Unit:
			continue
		var unit: Unit = entry as Unit
		var has_target: bool = (
			NodeSafety.is_alive_node(unit.get("_attack_target"))
			or VariantUtils.to_bool(unit.get("_has_attack_move_destination"))
			or unit.has_move_target
			or EnemyUnitMission.get_unit_mission(unit) == EnemyUnitMission.Mission.CREEP
		)
		if unit is Hero and has_target:
			hero_has_combat = true
		elif unit is Spearman and has_target:
			pike_has_combat = true
	_expect(failures, "hero holds combat/creep behavior at camp", hero_has_combat)
	_expect(failures, "pikeman holds combat/creep behavior at camp", pike_has_combat)

	## Mid-CREEP reinforcement joins and receives the active objective.
	var reinforce: Spearman = _spawn_enemy_spear(rally + Vector3(-2.0, 0.0, 2.0), 200)
	EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), reinforce)
	_expect(
		failures,
		"new unit starts in reinforcement pool",
		EnemyArmyCommand.is_reinforcement_waiting(reinforce)
	)
	await _admit_spawned_military(director, false)
	_expect(
		failures,
		"CREEP admits reinforcement into squad",
		squad.has_member(reinforce)
	)
	_expect(
		failures,
		"reinforcement released from pool on admit",
		not EnemyArmyCommand.is_reinforcement_waiting(reinforce)
	)
	squad.recompute_metrics()
	commander._creep_order_reissue_timer = ArmyCommanderV2.CREEP_ORDER_REISSUE_SECONDS
	commander._creep_regroup_hold_timer = 0.0
	commander._execute_creep_mission(director, mission, squad)
	for _drain3 in range(10):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame
	_expect(
		failures,
		"reinforcement receives CREEP mission",
		EnemyUnitMission.get_unit_mission(reinforce) == EnemyUnitMission.Mission.CREEP
	)

	## Clear first camp → continue to another valid camp without fake completion flags.
	var first_camp_id: int = camp_target.get_instance_id() if camp_target != null else 0
	var first_camp_name: String = String(camp_target.name) if camp_target != null else "-"
	if camp_target != null:
		await _clear_camp_creeps(camp_target)
	## Return the squad toward base rally so remaining enemy-side camps remain scorable.
	var member_i: int = 0
	for entry: Variant in squad.get_members_copy():
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		(entry as Node3D).global_position = rally + Vector3(float(member_i) * 0.9 - 1.5, 0.0, 0.5)
		member_i += 1
	squad.recompute_metrics()
	await get_tree().process_frame
	await get_tree().physics_frame
	CombatTargetValidation._group_cache_frame = -1
	var cleared_now: bool = (
		camp_target != null and creep_manager._is_camp_cleared(get_tree(), camp_target)
	)
	print("[EARLY CREEP SQUAD] camp_cleared_probe=%s" % str(cleared_now))
	_expect(failures, "first camp actually cleared", cleared_now)
	var continued: bool = director._evaluate_creep_strategy(get_tree(), rally)
	var next_mission: ArmyMissionV2 = director.get_mission()
	var next_camp: Node3D = (
		next_mission.get_alive_target_object() if next_mission != null else null
	)
	var next_name: String = String(next_camp.name) if next_camp != null else "-"
	print(
		"[EARLY CREEP SQUAD] after_clear continued=%s state=%s first=%s next=%s cleared_ids=%d"
		% [
			str(continued),
			director.get_state_name(),
			first_camp_name,
			next_name,
			director._cleared_creep_camp_ids.size(),
		]
	)
	_expect(failures, "after clear: strategy handled camp death", continued)
	_expect(
		failures,
		"after clear: recorded cleared camp progress",
		director._cleared_creep_camp_ids.has(first_camp_id)
	)
	if director.get_state() == MilitaryDirectorV2.State.CREEP:
		_expect(failures, "after clear: living next camp", next_camp != null)
		if next_camp != null and first_camp_id != 0:
			_expect(
				failures,
				"after clear: different living camp selected",
				next_camp.get_instance_id() != first_camp_id
			)
	else:
		## No second scorable camp from this fixture — still must leave the dead objective safely.
		_expect(
			failures,
			"after clear: left dead camp objective safely",
			director.get_reserved_creep_camp_id() != first_camp_id
		)

	var report: String
	if failures.is_empty():
		report = "PASS ai_early_creep_squad\n"
	else:
		report = "FAIL ai_early_creep_squad\n"
		for failure: String in failures:
			report += "- %s\n" % failure
			print("[EARLY CREEP SQUAD FAIL] %s" % failure)
	print(report.strip_edges())
	_write_report(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _spawn_enemy_hero(pos: Vector3) -> Hero:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	hero.name = "EnemyHero"
	hero.team_id = 1
	add_child(hero)
	hero.global_position = pos
	hero.add_to_group(&"enemies")
	hero.add_to_group(&"heroes")
	hero.add_to_group(&"enemy_combat_units")
	EnemyArmyCommand.register_combat_unit(hero)
	return hero


func _spawn_enemy_spear(pos: Vector3, index: int) -> Spearman:
	var spear: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	spear.name = "EnemySpear%d" % index
	spear.team_id = 1
	add_child(spear)
	spear.global_position = pos
	spear.add_to_group(&"enemies")
	spear.add_to_group(&"enemy_combat_units")
	EnemyArmyCommand.register_combat_unit(spear)
	return spear


func _clear_camp_creeps(camp: Node3D) -> void:
	if not NodeSafety.is_alive_node(camp):
		return
	var tree: SceneTree = get_tree()
	## Match EnemyCreepManager clear semantics: no living neutrals near the camp.
	for node_variant: Variant in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if not NodeSafety.is_alive_node(node_variant) or not node_variant is Node3D:
			continue
		var creep_node: Node3D = node_variant as Node3D
		if (
			EnemyArmyCommand.horizontal_distance(creep_node.global_position, camp.global_position)
			> EnemyCreepManager.CAMP_CLEAR_RADIUS
		):
			continue
		var health: HealthComponent = creep_node.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.current_health = 0
		creep_node.queue_free()
	## Flush deferred frees so camp-clear queries see an empty radius.
	await tree.process_frame
	await tree.process_frame


func _admit_spawned_military(
	director: MilitaryDirectorV2,
	force_admit: bool = true
) -> void:
	## Spawn + group membership must cross a frame so combat/group caches rebuild.
	await get_tree().process_frame
	await get_tree().physics_frame
	EnemyArmyCommand._combat_units_cache_frame = -1
	CombatTargetValidation._group_cache_frame = -1
	director.debug_refresh_roster_for_tests()
	if force_admit:
		director.debug_admit_pending_for_tests()
	director.get_main_squad().recompute_metrics()


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)


func _squad_member_names(squad: ArmySquadV2) -> String:
	var names: PackedStringArray = []
	for entry: Variant in squad.get_members_copy():
		if NodeSafety.is_alive_node(entry) and entry is Node:
			names.append(String((entry as Node).name))
		else:
			names.append("?")
	return ", ".join(names)


func _write_report(report: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
