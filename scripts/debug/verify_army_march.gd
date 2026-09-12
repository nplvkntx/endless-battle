extends Node

## Headless regression for cohesive enemy army march execution.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_army_march.tscn

const REPORT_PATH := "user://army_march_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")

var _failures: PackedStringArray = []
var _world: Node3D
var _spawned: Array = []


func _ready() -> void:
	print("verify_army_march: start")
	_world = Node3D.new()
	_world.name = "ArmyMarchWorld"
	add_child(_world)
	PlayerRouteNavigation.clear_all()
	PlayerRouteNavigation.ensure_grid_ready()
	await get_tree().process_frame

	await _test_a_fast_unit_waits()
	await _test_b_all_arrive_releases_next_segment()
	await _test_c_all_means_all()
	await _test_d_member_dies()
	await _test_e_reinforcement_joins_wait()
	await _test_f_final_approach()
	await _test_g_combat_keeps_checkpoint()
	await _test_chase_reaches_target_during_march()
	await _test_regroup_does_not_steal_march()

	var report: String
	if _failures.is_empty():
		report = "PASS army_march\n"
	else:
		report = "FAIL army_march\n" + "\n".join(_failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures.append("- %s" % label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)


func _test_a_fast_unit_waits() -> void:
	print("--- TEST A fast unit waits at checkpoint ---")
	await _reset_world()
	var origin := Vector3(-28.0, 0.0, 0.0)
	var dest := Vector3(26.0, 0.0, 0.0)
	var hero: Hero = _spawn_enemy_hero(origin, "MarchHero")
	var spearman: Unit = _spawn_enemy_spearman(origin + Vector3(0.0, 0.0, 1.4), "MarchSpear1")
	await get_tree().process_frame
	_expect("TEST A hero faster than spearman", hero.move_speed > spearman.move_speed)
	var result: Dictionary = PlayerRouteNavigation.request_group_move(
		[hero, spearman], dest, &"attack_move", false, &"enemy_ai"
	)
	_expect("TEST A march command handled", bool(result.get("handled", false)))
	_expect("TEST A one strategic path", int(result.get("path_calculations", -1)) == 1)
	_expect("TEST A march active", PlayerRouteNavigation.is_enemy_army_march_in_progress())
	var mode: StringName = PlayerRouteNavigation.get_army_march_mode_for_test()
	_expect(
		"TEST A not final approach on long route",
		mode == &"MOVING" or mode == &"WAITING_FOR_ALL"
	)
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	_expect("TEST A checkpoint is not the final dest", _flat_dist(checkpoint, dest) > 8.0)
	_expect("TEST A hero has march cap", hero.has_army_march_checkpoint())
	_expect("TEST A spearman has march cap", spearman.has_army_march_checkpoint())

	hero.global_position = checkpoint + Vector3(0.4, 0.0, 0.0)
	if hero.is_custom_rts_movement_active():
		hero._process_custom_rts_movement(0.016)
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	_expect("TEST A hero arrived at checkpoint", hero.is_within_army_march_arrival())
	_expect("TEST A hero stopped at checkpoint", not hero.has_move_target)
	_expect("TEST A hero kept custom route", hero.has_custom_rts_route())
	_expect(
		"TEST A hero kept ATTACK_MOVE",
		hero.get_active_order() != null and hero.get_active_order().type == UnitOrder.Type.ATTACK_MOVE
	)
	_expect("TEST A spearman still approaching", spearman.has_move_target)
	_expect("TEST A spearman not yet arrived", not spearman.is_within_army_march_arrival())
	_expect(
		"TEST A still waiting, no next segment",
		PlayerRouteNavigation.get_army_march_mode_for_test() == &"WAITING_FOR_ALL"
	)
	var after_wait: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	_expect("TEST A checkpoint unchanged while waiting", _flat_dist(checkpoint, after_wait) < 0.2)
	_expect(
		"TEST A hero did not run past to the objective",
		_flat_dist(hero.global_position, dest) > 8.0
	)


func _test_b_all_arrive_releases_next_segment() -> void:
	print("--- TEST B all arrive releases next segment ---")
	await _reset_world()
	var origin := Vector3(-28.0, 0.0, 0.0)
	var dest := Vector3(26.0, 0.0, 0.0)
	var hero: Hero = _spawn_enemy_hero(origin, "MarchHeroB")
	var spearman: Unit = _spawn_enemy_spearman(origin + Vector3(0.0, 0.0, 1.4), "MarchSpearB")
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move(
		[hero, spearman], dest, &"attack_move", false, &"enemy_ai"
	)
	var first_cp: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	var first_seg: int = PlayerRouteNavigation.get_army_march_segment_index_for_test()
	hero.global_position = first_cp
	spearman.global_position = first_cp + Vector3(0.8, 0.0, 0.0)
	if hero.is_custom_rts_movement_active():
		hero._process_custom_rts_movement(0.016)
	if spearman.is_custom_rts_movement_active():
		spearman._process_custom_rts_movement(0.016)
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	var next_cp: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	_expect("TEST B released a new checkpoint", _flat_dist(first_cp, next_cp) > 4.0)
	_expect(
		"TEST B segment index advanced",
		PlayerRouteNavigation.get_army_march_segment_index_for_test() > first_seg
	)
	_expect("TEST B hero resumed moving", hero.has_move_target)
	_expect("TEST B spearman resumed moving", spearman.has_move_target)
	_expect("TEST B march still in progress", PlayerRouteNavigation.is_enemy_army_march_in_progress())


func _test_c_all_means_all() -> void:
	print("--- TEST C main force waits briefly, then advances ---")
	await _reset_world()
	var origin := Vector3(-28.0, 0.0, 0.0)
	var dest := Vector3(26.0, 0.0, 0.0)
	var units: Array = []
	for i: int in 5:
		units.append(
			_spawn_enemy_spearman(origin + Vector3(0.0, 0.0, float(i) * 1.2), "MarchC_%d" % i)
		)
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move(units, dest, &"move", false, &"enemy_ai")
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	var seg: int = PlayerRouteNavigation.get_army_march_segment_index_for_test()
	for i: int in 4:
		(units[i] as Unit).global_position = checkpoint + Vector3(float(i) * 0.5, 0.0, 0.0)
	(units[4] as Unit).global_position = origin
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	var snap: Dictionary = PlayerRouteNavigation.get_army_march_debug_snapshot()
	_expect("TEST C required is 5", int(snap.get("required", 0)) == 5)
	_expect("TEST C arrived is 4", int(snap.get("arrived", 0)) == 4)
	_expect("TEST C does not release", PlayerRouteNavigation.get_army_march_segment_index_for_test() == seg)
	_expect(
		"TEST C checkpoint unchanged",
		_flat_dist(checkpoint, PlayerRouteNavigation.get_army_march_checkpoint_for_test()) < 0.2
	)
	_expect("TEST C next release is WAITING", String(snap.get("next_segment_release", "")) == "WAITING")
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test(2.0)
	_expect("TEST C allows a catch-up window", PlayerRouteNavigation.get_army_march_segment_index_for_test() == seg)
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test(2.1)
	_expect("TEST C ready majority is not held forever", PlayerRouteNavigation.get_army_march_segment_index_for_test() > seg)
	_expect("TEST C straggler keeps its route", (units[4] as Unit).has_custom_rts_route())
	_expect("TEST C straggler follows new checkpoint", _flat_dist((units[4] as Unit).get_army_march_checkpoint(), PlayerRouteNavigation.get_army_march_checkpoint_for_test()) < 0.1)
	var next_seg: int = PlayerRouteNavigation.get_army_march_segment_index_for_test()
	for unit_v: Variant in units:
		(unit_v as Unit).global_position = origin
	(units[0] as Unit).global_position = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test(20.0)
	_expect("TEST C lone front unit cannot release the army", PlayerRouteNavigation.get_army_march_segment_index_for_test() == next_seg)


func _test_d_member_dies() -> void:
	print("--- TEST D dead member is dropped ---")
	await _reset_world()
	var origin := Vector3(-28.0, 0.0, 0.0)
	var dest := Vector3(26.0, 0.0, 0.0)
	var units: Array = []
	for i: int in 5:
		units.append(
			_spawn_enemy_spearman(origin + Vector3(0.0, 0.0, float(i) * 1.2), "MarchD_%d" % i)
		)
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move(units, dest, &"move", false, &"enemy_ai")
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	var seg: int = PlayerRouteNavigation.get_army_march_segment_index_for_test()
	for i: int in 4:
		(units[i] as Unit).global_position = checkpoint + Vector3(float(i) * 0.5, 0.0, 0.0)
	(units[4] as Unit).global_position = origin
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	_expect("TEST D still waiting with 4/5", PlayerRouteNavigation.get_army_march_segment_index_for_test() == seg)
	_kill_unit(units[4] as Unit)
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	var snap: Dictionary = PlayerRouteNavigation.get_army_march_debug_snapshot()
	_expect("TEST D living required is 4", int(snap.get("required", 0)) == 4)
	_expect("TEST D all living arrived so segment released", PlayerRouteNavigation.get_army_march_segment_index_for_test() > seg)


func _test_e_reinforcement_joins_wait() -> void:
	print("--- TEST E reinforcement joins current wait ---")
	await _reset_world()
	var origin := Vector3(-28.0, 0.0, 0.0)
	var dest := Vector3(26.0, 0.0, 0.0)
	var hero: Hero = _spawn_enemy_hero(origin, "MarchHeroE")
	var spearman: Unit = _spawn_enemy_spearman(origin + Vector3(0.0, 0.0, 1.4), "MarchSpearE")
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move(
		[hero, spearman], dest, &"attack_move", false, &"enemy_ai"
	)
	var route_before: PackedVector3Array = PlayerRouteNavigation.get_army_march_shared_route_for_test()
	var generation_before: int = PlayerRouteNavigation.get_army_march_generation_for_test()
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	var seg: int = PlayerRouteNavigation.get_army_march_segment_index_for_test()
	hero.global_position = checkpoint
	spearman.global_position = origin + Vector3(0.0, 0.0, 1.4)
	if hero.is_custom_rts_movement_active():
		hero._process_custom_rts_movement(0.016)
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	_expect(
		"TEST E waiting before recruit",
		PlayerRouteNavigation.get_army_march_mode_for_test() == &"WAITING_FOR_ALL"
	)
	var recruit: Unit = _spawn_enemy_spearman(origin + Vector3(2.0, 0.0, -2.0), "MarchRecruitE")
	await get_tree().process_frame
	var join: Dictionary = PlayerRouteNavigation.request_group_move(
		[recruit], dest, &"attack_move", false, &"enemy_ai"
	)
	_expect("TEST E join handled", bool(join.get("handled", false)))
	_expect(
		"TEST E did not rebuild the army strategic route",
		PlayerRouteNavigation.get_army_march_generation_for_test() == generation_before
	)
	var route_after: PackedVector3Array = PlayerRouteNavigation.get_army_march_shared_route_for_test()
	_expect("TEST E shared route length unchanged", route_after.size() == route_before.size())
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	var snap: Dictionary = PlayerRouteNavigation.get_army_march_debug_snapshot()
	_expect("TEST E required increased to 3", int(snap.get("required", 0)) == 3)
	_expect("TEST E still waiting for lagging members", int(snap.get("arrived", 0)) < 3)
	_expect("TEST E checkpoint not advanced", PlayerRouteNavigation.get_army_march_segment_index_for_test() == seg)
	_expect("TEST E recruit has ATTACK_MOVE", recruit.get_active_order() != null)
	_expect("TEST E recruit travels toward checkpoint", recruit.has_move_target or recruit.has_army_march_checkpoint())


func _test_f_final_approach() -> void:
	print("--- TEST F remaining distance uses final objective ---")
	await _reset_world()
	var origin := Vector3(-10.0, 0.0, 8.0)
	var dest := Vector3(-2.0, 0.0, 8.0)
	var spearman: Unit = _spawn_enemy_spearman(origin, "MarchFinal")
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move(
		[spearman], dest, &"move", false, &"enemy_ai"
	)
	_expect(
		"TEST F mode is FINAL_APPROACH",
		PlayerRouteNavigation.get_army_march_mode_for_test() == &"FINAL_APPROACH"
	)
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	_expect("TEST F checkpoint is the final objective", _flat_dist(checkpoint, dest) <= 2.5)


func _test_g_combat_keeps_checkpoint() -> void:
	print("--- TEST G combat interruption keeps march checkpoint ---")
	await _reset_world()
	var origin := Vector3(-28.0, 0.0, 0.0)
	var dest := Vector3(26.0, 0.0, 0.0)
	var fighter: Unit = _spawn_enemy_spearman(origin, "MarchFighterG")
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move(
		[fighter], dest, &"attack_move", false, &"enemy_ai"
	)
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	var generation: int = PlayerRouteNavigation.get_army_march_generation_for_test()
	var routes_before: int = PlayerRouteNavigation.total_path_calculations
	_expect("TEST G has ATTACK_MOVE", fighter.get_active_order() != null)
	var military: MilitaryUnit = fighter as MilitaryUnit
	var interrupter: Unit = _spawn_player_spearman(fighter.global_position + Vector3(1.2, 0.0, 0.0))
	await get_tree().process_frame
	military._on_combat_damage_received({DamageService.RESULT_ATTACKER: interrupter})
	_expect("TEST G entered local combat", military.get_attack_target() == interrupter)
	_expect("TEST G ATTACK_MOVE preserved", military.has_attack_move_destination())
	_expect(
		"TEST G checkpoint preserved during fight",
		_flat_dist(checkpoint, PlayerRouteNavigation.get_army_march_checkpoint_for_test()) < 0.2
	)
	var health: HealthComponent = interrupter.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.current_health = 0
	military._sanitize_attack_target()
	_expect("TEST G still ATTACK_MOVE after kill", military.has_attack_move_destination())
	_expect(
		"TEST G same march generation after combat",
		PlayerRouteNavigation.get_army_march_generation_for_test() == generation
	)
	_expect(
		"TEST G no extra strategic army path from combat",
		PlayerRouteNavigation.total_path_calculations == routes_before
	)
	_expect("TEST G march still active", PlayerRouteNavigation.is_enemy_army_march_in_progress())


func _test_chase_reaches_target_during_march() -> void:
	print("--- march combat physically reaches target ---")
	await _reset_world()
	var fighter: MilitaryUnit = _spawn_enemy_spearman(Vector3(-28, 0, 0), "MarchChaser") as MilitaryUnit
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move([fighter], Vector3(-8, 0, 0), &"attack_move", false, &"enemy_ai")
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	var target: Unit = _spawn_player_spearman(fighter.global_position + Vector3(0, 0, 7))
	target.set_physics_process(false)
	await get_tree().process_frame
	# This checks chase execution, independently of the real-time order cooldown.
	fighter._last_path_request_msec = Time.get_ticks_msec() - 1000
	fighter._begin_attack_on_target(target, -1, false)
	var health: HealthComponent = target.get_node("HealthComponent") as HealthComponent
	var before: float = health.current_health
	for frame: int in 360:
		await get_tree().physics_frame
		if health.current_health < before:
			break
	_expect("march chase reaches and damages off-route target", health.current_health < before)
	_expect("local chase preserves strategic checkpoint", _flat_dist(checkpoint, fighter.get_army_march_checkpoint()) < 0.1)
	_expect("local chase preserves ATTACK_MOVE", fighter.has_attack_move_destination())
	_kill_unit(target)
	await get_tree().process_frame
	fighter._sanitize_attack_target()
	_expect("after kill strategic route remains available", fighter.has_custom_rts_route())


func _test_regroup_does_not_steal_march() -> void:
	print("--- TEST regroup does not cancel march thinking ---")
	await _reset_world()
	var ai: EnemyAI = EnemyAI.new()
	ai.name = "EnemyAI"
	ai.set_process(false)
	_world.add_child(ai)
	_spawned.append(ai)
	var cc: Building = _spawn_completed_building(CC_SCENE, Vector3(30, 1, 28))
	ai.enemy_command_center_path = ai.get_path_to(cc)
	_spawn_completed_building(FARM_SCENE, cc.global_position + Vector3(-5, 0, 0))
	_spawn_completed_building(ALTAR_SCENE, cc.global_position + Vector3(5, 0, 0))
	_spawn_completed_building(BARRACKS_SCENE, cc.global_position + Vector3(0, 0, -5))
	var cluster := Vector3(-24.0, 0.0, -8.0)
	var hero: Hero = _spawn_enemy_hero(cluster, "MarchHeroR")
	hero.level = 1
	HeroProgressionStore.register_living_hero(hero)
	var soldiers: Array = []
	for i: int in 5:
		soldiers.append(_spawn_enemy_spearman(cluster + Vector3(float(i) * 0.9, 0.0, 1.0), "MarchR_%d" % i))
	PlayerRouteNavigation.ensure_grid_ready()
	await get_tree().process_frame
	PlayerRouteNavigation.request_group_move(
		[hero] + soldiers,
		Vector3(24.0, 0.0, -8.0),
		&"attack_move",
		false,
		&"enemy_ai"
	)
	_expect("TEST regroup march started", PlayerRouteNavigation.is_enemy_army_march_in_progress())
	var checkpoint: Vector3 = PlayerRouteNavigation.get_army_march_checkpoint_for_test()
	hero.global_position = checkpoint
	if hero.is_custom_rts_movement_active():
		hero._process_custom_rts_movement(0.016)
	PlayerRouteNavigation.evaluate_enemy_army_march_for_test()
	_expect(
		"TEST regroup is waiting for trailing members",
		PlayerRouteNavigation.is_enemy_army_march_waiting_for_all()
	)
	ai.force_tick_for_test()
	_expect(
		"TEST regroup did not become the strategic decision",
		ai.get_debug_priority() != &"REGROUP"
	)
	_expect("TEST regroup march still in progress", PlayerRouteNavigation.is_enemy_army_march_in_progress())


func _reset_world() -> void:
	PlayerRouteNavigation.clear_all()
	HeroProgressionStore.clear()
	for node_v: Variant in _spawned:
		if NodeSafety.is_alive_node(node_v):
			(node_v as Node).queue_free()
	_spawned.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()


func _spawn_enemy_hero(position: Vector3, unit_name: String) -> Hero:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	hero.name = unit_name
	_world.add_child(hero)
	hero.global_position = position
	hero.team_id = 1
	hero.add_to_group(&"enemies")
	hero.add_to_group(&"enemy_combat_units")
	_spawned.append(hero)
	return hero


func _spawn_enemy_spearman(position: Vector3, unit_name: String) -> Unit:
	var unit: Unit = SPEARMAN_SCENE.instantiate() as Unit
	unit.name = unit_name
	_world.add_child(unit)
	unit.global_position = position
	unit.team_id = 1
	unit.add_to_group(&"enemies")
	unit.add_to_group(&"enemy_combat_units")
	_spawned.append(unit)
	return unit


func _spawn_player_spearman(position: Vector3) -> Unit:
	var unit: Unit = SPEARMAN_SCENE.instantiate() as Unit
	unit.name = "PlayerPike"
	_world.add_child(unit)
	unit.global_position = position
	unit.team_id = TeamVisuals.PLAYER_TEAM_ID
	if not unit.is_in_group(&"units"):
		unit.add_to_group(&"units")
	_spawned.append(unit)
	return unit


func _spawn_completed_building(scene: PackedScene, position: Vector3) -> Building:
	var building: Building = scene.instantiate() as Building
	building.team_id = 1
	_world.add_child(building)
	building.global_position = position
	building.set_completed()
	building.add_to_group(&"buildings")
	if building.is_in_group(&"player_command_center"):
		building.remove_from_group(&"player_command_center")
	if not building.is_in_group(&"enemy_command_center"):
		building.add_to_group(&"enemy_command_center")
	_spawned.append(building)
	return building


func _kill_unit(unit: Node) -> void:
	if not NodeSafety.is_alive_node(unit):
		return
	var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.current_health = 0
	if unit.has_method(&"die"):
		unit.call(&"die")
	unit.queue_free()


func _flat_dist(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
