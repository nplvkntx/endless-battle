extends Node3D

## Hero–main-army cohesion + combat-advantage attack decision regression.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_hero_army_cohesion.tscn

const REPORT_PATH := "user://ai_hero_army_cohesion_verify_result.txt"
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
	EnemyAggression.force_scores_for_tests(0.0, 0.0)

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

	## --- Force math must score player armies (not only enemy_combat_units) ---
	var math_probe_ai: Spearman = _spawn_enemy_spear(rally + Vector3(1, 0, 0), 900)
	var math_probe_player: Spearman = _spawn_player_spear(player_cc.global_position + Vector3(1, 0, 0), 901)
	await get_tree().process_frame
	var ai_math: float = EnemyArmyForceMath.estimate_combat_strength([math_probe_ai])
	var player_math: float = EnemyArmyForceMath.estimate_combat_strength([math_probe_player])
	_expect(failures, "force math scores enemy spearman", ai_math > 0.0)
	_expect(failures, "force math scores player spearman", player_math > 0.0)
	math_probe_ai.queue_free()
	math_probe_player.queue_free()
	await get_tree().process_frame

	## --- CASE 1: mid-CREEP reinforcements join hero squad ---
	var hero: Hero = _spawn_enemy_hero(rally + Vector3(0.0, 0.0, 0.5))
	hero.level = 2
	EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), hero)
	var creep_pikes: Array = []
	for i in range(5):
		var spear: Spearman = _spawn_enemy_spear(rally + Vector3(float(i) * 1.2, 0.0, 1.0), i)
		EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), spear)
		creep_pikes.append(spear)
	await _admit_spawned_military(director)
	_expect(failures, "case1: creep_ready", director.is_creep_ready())
	_expect(failures, "case1: hero in main squad", director.get_main_squad().hero_present)

	director._transition_to(MilitaryDirectorV2.State.ASSEMBLE, "cohesion assemble", rally)
	var creep_selected: bool = director._evaluate_creep_strategy(get_tree(), rally)
	_expect(failures, "case1: CREEP selected", creep_selected)
	_expect(failures, "case1: state CREEP", director.get_state_name() == "CREEP")

	var mission: ArmyMissionV2 = director.get_mission()
	_expect(failures, "case1: creep mission present", mission != null)
	var camp: Node3D = null
	if mission != null:
		camp = mission.get_alive_target_object()
	_expect(failures, "case1: creep camp objective", NodeSafety.is_alive_node(camp))

	var squad: ArmySquadV2 = director.get_main_squad()
	commander._creep_order_reissue_timer = ArmyCommanderV2.CREEP_ORDER_REISSUE_SECONDS
	commander._creep_regroup_hold_timer = 0.0
	commander._execute_creep_mission(director, mission, squad)
	for _drain in range(8):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame

	## Move the main body into the field so base reinforcements are true stragglers.
	if NodeSafety.is_alive_node(camp):
		var field_pos: Vector3 = camp.global_position + Vector3(2.0, 0.0, 2.0)
		hero.global_position = field_pos
		for i in range(creep_pikes.size()):
			(creep_pikes[i] as Node3D).global_position = field_pos + Vector3(float(i) * 0.8, 0.0, 0.5)

	var reinforce: Array = []
	for i in range(5):
		var extra: Spearman = _spawn_enemy_spear(rally + Vector3(-2.0 - float(i), 0.0, 2.0), 100 + i)
		EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), extra)
		reinforce.append(extra)
	await _admit_spawned_military(director, false)
	squad = director.get_main_squad()
	var joined: int = 0
	for entry: Variant in reinforce:
		if squad.has_member(entry as Node):
			joined += 1
	_expect(failures, "case1: all 5 base reinforcements admitted to hero squad", joined == 5)
	_expect(
		failures,
		"case1: pending cleared after admit",
		director.get_pending_reinforcements_copy().is_empty()
	)
	_expect(failures, "case1: no duplicate membership", squad.get_size() == 11)

	## Membership-blind min-refresh must not swallow the reinforcement refresh.
	var creep_army_pre: Array = commander._collect_creep_army(squad)
	_expect(
		failures,
		"case1: stranded base escorts need objective orders",
		commander._creep_army_needs_objective_orders(creep_army_pre, rally)
	)

	squad.recompute_metrics()
	commander._creep_order_reissue_timer = ArmyCommanderV2.CREEP_ORDER_REISSUE_SECONDS
	commander._creep_regroup_hold_timer = 0.0
	commander._execute_creep_mission(director, mission, squad)
	for _drain2 in range(10):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame

	var creep_orders: int = 0
	for entry: Variant in reinforce:
		if (
			NodeSafety.is_alive_node(entry)
			and EnemyUnitMission.get_unit_mission(entry as Node) == EnemyUnitMission.Mission.CREEP
		):
			creep_orders += 1
	_expect(failures, "case1: all 5 reinforcements receive CREEP objective", creep_orders == 5)
	_expect(failures, "case1: hero still in main squad", squad.hero_present)

	## New training while CREEP remains active — no mission restart required.
	var trained: Spearman = _spawn_enemy_spear(rally + Vector3(4.0, 0.0, -3.0), 150)
	EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), trained)
	await _admit_spawned_military(director, false)
	squad = director.get_main_squad()
	_expect(failures, "case1b: newly trained pike admitted", squad.has_member(trained))
	commander._creep_order_reissue_timer = ArmyCommanderV2.CREEP_ORDER_REISSUE_SECONDS
	commander._execute_creep_mission(director, mission, squad)
	for _drain_train in range(8):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame
	_expect(
		failures,
		"case1b: newly trained pike inherits CREEP objective",
		EnemyUnitMission.get_unit_mission(trained) == EnemyUnitMission.Mission.CREEP
	)
	var power_units: Array = director._get_attack_squad_units()
	var power_owned: int = 0
	for entry: Variant in power_units:
		if squad.has_member(entry as Node):
			power_owned += 1
	_expect(
		failures,
		"case1b: strategic available-power units are main-squad eligible",
		power_owned == power_units.size() and power_units.size() >= 10
	)

	## --- CASE 2: clear combat advantage prefers ATTACK ---
	## Grow AI to ~10 pikes + L4 hero vs player L2 + 5 pikes near player base.
	for i in range(5):
		var more: Spearman = _spawn_enemy_spear(rally + Vector3(float(i) * 1.1, 0.0, -2.0), 200 + i)
		EnemyArmyCommand.assign_reinforcement_regroup(get_tree(), more)
	await _admit_spawned_military(director, false)
	hero.level = 4
	squad.recompute_metrics()
	_expect(failures, "case2: attack-ready army size", director.is_attack_ready())

	var player_hero: Hero = _spawn_player_hero(player_cc.global_position + Vector3(2, 0, 0))
	player_hero.level = 2
	var player_pikes: Array = []
	for i in range(5):
		player_pikes.append(
			_spawn_player_spear(player_cc.global_position + Vector3(3.0 + float(i), 0.0, 1.0), 300 + i)
		)
	await get_tree().process_frame
	await get_tree().physics_frame
	CombatTargetValidation._group_cache_frame = -1

	var balance: Dictionary = director.debug_evaluate_main_army_vs_player_for_tests(rally)
	var ratio: float = float(balance.get("ratio", 0.0))
	print(
		"[HERO ARMY COHESION] advantage ai=%.1f player=%.1f ratio=%.2f need=%.2f"
		% [
			float(balance.get("ai_strength", 0.0)),
			float(balance.get("player_strength", 0.0)),
			ratio,
			MilitaryAIConfig.V2_CREEP_STRENGTH_ADVANTAGE_INTERRUPT,
		]
	)
	_expect(failures, "case2: player strength scored > 0", float(balance.get("player_strength", 0.0)) > 0.0)
	_expect(failures, "case2: AI strength scored > 0", float(balance.get("ai_strength", 0.0)) > 0.0)
	_expect(
		failures,
		"case2: clear advantage reported",
		director.debug_has_clear_combat_advantage_for_tests(rally)
	)
	_expect(
		failures,
		"case2: ratio meets interrupt threshold",
		ratio >= MilitaryAIConfig.V2_CREEP_STRENGTH_ADVANTAGE_INTERRUPT
	)

	director._cleared_creep_camp_ids.clear()
	## Stay mid-CREEP with soft early window still open — advantage must still interrupt.
	_expect(
		failures,
		"case2: interrupt CREEP for advantage",
		director._should_interrupt_creeping_for_attack(get_tree(), rally)
	)
	var attacked: bool = director._evaluate_attack_strategy(get_tree(), rally)
	_expect(failures, "case2: ATTACK preferred over low-priority creep", attacked)
	_expect(failures, "case2: state ATTACK", director.get_state_name() == "ATTACK")
	_expect(failures, "case2: hero remains in attack squad", director.get_main_squad().hero_present)

	var attack_mission: ArmyMissionV2 = director.get_mission()
	_expect(failures, "case2: attack mission present", attack_mission != null)
	squad = director.get_main_squad()
	var attack_army: Array = commander._collect_attack_army(squad)
	_expect(failures, "case2: main squad has meaningful combat force", attack_army.size() >= 10)
	_expect(failures, "case2: hero included in attack army collection", attack_army.has(hero))
	_expect(
		failures,
		"case2: director attack mission type is ATTACK",
		attack_mission != null
		and attack_mission.mission_type == ArmyMissionV2.MissionType.ATTACK
	)

	## Attempt real order issuance; nav may fail in this headless fixture.
	commander._attack_order_reissue_timer = MilitaryAIConfig.V2_ATTACK_ORDER_REISSUE_SECONDS
	commander._execute_attack_mission(director, attack_mission, squad)
	for _drain3 in range(8):
		EnemyArmyCommand.tick_group_order_batch(get_tree())
		await get_tree().process_frame
	var attack_orders: int = 0
	for entry: Variant in attack_army:
		if (
			NodeSafety.is_alive_node(entry)
			and EnemyUnitMission.get_unit_mission(entry as Node) == EnemyUnitMission.Mission.ATTACK
		):
			attack_orders += 1
	print(
		"[HERO ARMY COHESION] attack_army=%d attack_orders=%d state=%s"
		% [attack_army.size(), attack_orders, director.get_state_name()]
	)
	## If nav issued orders, they must cover the main squad — never solo-hero attack.
	if attack_orders > 0:
		_expect(failures, "case2: hero received ATTACK order", EnemyUnitMission.get_unit_mission(hero) == EnemyUnitMission.Mission.ATTACK)
		_expect(
			failures,
			"case2: ATTACK orders are army-wide not solo",
			attack_orders >= 2
		)
	_expect(
		failures,
		"case2: no large orphan pending pile",
		director.get_pending_reinforcements_copy().size() <= 1
	)

	## --- CASE 3: equal power must NOT force suicidal ATTACK ---
	## Keep the ~10-pike AI army; match player to roughly equal fighting power.
	player_hero.level = 4
	for i in range(5):
		player_pikes.append(
			_spawn_player_spear(player_cc.global_position + Vector3(-3.0 - float(i), 0.0, 2.0), 400 + i)
		)
	await get_tree().process_frame
	CombatTargetValidation._group_cache_frame = -1
	EnemyArmyCommand._combat_units_cache_frame = -1
	director.debug_refresh_roster_for_tests()
	director.get_main_squad().recompute_metrics()
	_expect(failures, "case3: still attack-ready sized", director.is_attack_ready())

	## Leave ATTACK so the new-commit gate applies.
	director._transition_to(MilitaryDirectorV2.State.ASSEMBLE, "equal power hold", rally)
	var equal_balance: Dictionary = director.debug_evaluate_main_army_vs_player_for_tests(rally)
	var equal_ratio: float = float(equal_balance.get("ratio", 0.0))
	print(
		"[HERO ARMY COHESION] equal ai=%.1f player=%.1f ratio=%.2f"
		% [
			float(equal_balance.get("ai_strength", 0.0)),
			float(equal_balance.get("player_strength", 0.0)),
			equal_ratio,
		]
	)
	## If the fixture accidentally still looks like a stomp, add player pikes until equal-ish.
	var equalize_guard: int = 0
	while (
		equalize_guard < 6
		and float(equal_balance.get("ratio", 99.0))
		>= MilitaryAIConfig.V2_CREEP_STRENGTH_ADVANTAGE_INTERRUPT
	):
		equalize_guard += 1
		player_pikes.append(
			_spawn_player_spear(
				player_cc.global_position + Vector3(-8.0 - float(equalize_guard), 0.0, -2.0),
				450 + equalize_guard
			)
		)
		await get_tree().process_frame
		CombatTargetValidation._group_cache_frame = -1
		equal_balance = director.debug_evaluate_main_army_vs_player_for_tests(rally)
		equal_ratio = float(equal_balance.get("ratio", 0.0))
		print(
			"[HERO ARMY COHESION] equalize#%d ai=%.1f player=%.1f ratio=%.2f"
			% [
				equalize_guard,
				float(equal_balance.get("ai_strength", 0.0)),
				float(equal_balance.get("player_strength", 0.0)),
				equal_ratio,
			]
		)

	_expect(
		failures,
		"case3: not a clear advantage when roughly equal",
		not director.debug_has_clear_combat_advantage_for_tests(rally)
	)
	_expect(
		failures,
		"case3: equal fight does not interrupt into ATTACK",
		not director._should_interrupt_creeping_for_attack(get_tree(), rally)
	)
	var forced_attack: bool = director._evaluate_attack_strategy(get_tree(), rally)
	_expect(failures, "case3: equal fight does not force ATTACK commit", not forced_attack)
	_expect(failures, "case3: remains non-ATTACK", director.get_state_name() != "ATTACK")

	## --- CASE 4: hero cohesion during CREEP + ATTACK membership ---
	_expect(failures, "case4: hero still rostered", NodeSafety.is_alive_node(hero))
	_expect(
		failures,
		"case4: hero belongs to authoritative main squad",
		director.get_main_squad().has_member(hero)
	)
	var available_combat: int = 0
	for entry: Variant in EnemyArmyCommand.collect_living_combat_units(get_tree()):
		if NodeSafety.is_alive_node(entry):
			available_combat += 1
	var main_size: int = director.get_main_squad().get_size()
	var pending_size: int = director.get_pending_reinforcements_copy().size()
	_expect(
		failures,
		"case4: majority of available combat is in main squad",
		main_size >= int(ceil(float(available_combat) * 0.7))
	)
	_expect(
		failures,
		"case4: no large idle pending orphan army",
		pending_size <= maxi(1, available_combat / 5)
	)

	## --- CASE 5: emergency defense reservation is not stolen by main-squad reinforce ---
	var defender: Spearman = _spawn_enemy_spear(rally + Vector3(6.0, 0.0, 6.0), 500)
	EnemyArmyCommand.register_combat_unit(defender)
	EnemyUnitMission.try_set_mission(defender, EnemyUnitMission.Mission.DEFEND, 30.0)
	EnemyArmyCommand._emergency_defense_active = true
	director.debug_enqueue_pending_for_tests(defender)
	director._state = MilitaryDirectorV2.State.CREEP
	director.debug_admit_pending_for_tests()
	_expect(
		failures,
		"case5: emergency defender not stolen into main squad",
		not director.get_main_squad().has_member(defender)
	)
	_expect(
		failures,
		"case5: defender stays DEFEND reserved",
		EnemyUnitMission.get_unit_mission(defender) == EnemyUnitMission.Mission.DEFEND
	)
	EnemyArmyCommand._emergency_defense_active = false

	var report: String
	if failures.is_empty():
		report = "PASS ai_hero_army_cohesion\n"
	else:
		report = "FAIL ai_hero_army_cohesion\n"
		for failure: String in failures:
			report += "- %s\n" % failure
			print("[HERO ARMY COHESION FAIL] %s" % failure)
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


func _spawn_player_hero(pos: Vector3) -> Hero:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	hero.name = "PlayerHero"
	hero.team_id = 0
	add_child(hero)
	hero.global_position = pos
	hero.add_to_group(&"heroes")
	hero.add_to_group(&"units")
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


func _spawn_player_spear(pos: Vector3, index: int) -> Spearman:
	var spear: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	spear.name = "PlayerSpear%d" % index
	spear.team_id = 0
	add_child(spear)
	spear.global_position = pos
	spear.add_to_group(&"units")
	return spear


func _admit_spawned_military(
	director: MilitaryDirectorV2,
	force_admit: bool = true
) -> void:
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


func _write_report(report: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
