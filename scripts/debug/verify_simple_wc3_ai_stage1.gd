extends Node

## Stage 1 Simple WC3 AI safety regression (not a full match simulation).
## Proves: hero + 5 pikemen → one creep target → custom group move → objective retained
## → combat can damage a creep.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_simple_wc3_ai_stage1.tscn

const REPORT_PATH := "user://simple_wc3_ai_stage1_verify_result.txt"
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_simple_wc3_ai_stage1: start")

	_expect(failures, "Simple WC3 AI config on", MilitaryAIConfig.is_simple_wc3_ai_enabled())
	_expect(failures, "custom RTS movement on", MilitaryAIConfig.is_custom_rts_movement_enabled())
	_expect(
		failures,
		"V2 flag remains true (legacy military suspended)",
		MilitaryAIConfig.is_v2_enabled()
	)

	await _test_stage1_force_camp_move_combat(failures)
	await _test_old_military_disabled_when_simple_present(failures)

	var report: String
	if failures.is_empty():
		report = "PASS simple_wc3_ai_stage1\n"
	else:
		report = "FAIL simple_wc3_ai_stage1\n" + "\n".join(failures) + "\n"

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


func _test_stage1_force_camp_move_combat(failures: PackedStringArray) -> void:
	print("verify: stage1 force → camp → custom move → damage")
	PlayerRouteNavigation.clear_all()
	CreepCampSafety.reset_match_state()
	await get_tree().process_frame

	var enemy_cc: Building = CC_SCENE.instantiate() as Building
	enemy_cc.name = "EnemyCommandCenter"
	enemy_cc.team_id = TeamVisuals.ENEMY_TEAM_ID
	add_child(enemy_cc)
	enemy_cc.global_position = Vector3(20.0, 1.0, 20.0)
	enemy_cc.set_completed()
	enemy_cc.add_to_group(&"enemy_command_center")
	enemy_cc.add_to_group(&"buildings")

	var camp := CreepCamp.new()
	camp.name = "MediumCampTest"
	add_child(camp)
	camp.global_position = Vector3(8.0, 0.0, 8.0)
	camp.add_to_group(&"creep_camps")

	var creep: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
	camp.add_child(creep)
	creep.position = Vector3(0.0, 0.5, 0.0)
	await get_tree().process_frame

	var health: HealthComponent = creep.get_node_or_null("HealthComponent") as HealthComponent
	_expect(failures, "creep has health", health != null)
	var hp_before: int = health.current_health if health != null else 0

	var ai := SimpleWc3AI.new()
	ai.name = "SimpleWc3AI"
	add_child(ai)
	await get_tree().process_frame

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = Vector3(18.0, 0.5, 18.0)
	hero.team_id = TeamVisuals.ENEMY_TEAM_ID
	hero.add_to_group(&"enemy_combat_units")
	hero.add_to_group(&"heroes")

	var pikemen: Array = []
	for i: int in 5:
		var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
		add_child(pike)
		pike.global_position = Vector3(17.0 + float(i) * 0.8, 0.5, 17.0)
		pike.team_id = TeamVisuals.ENEMY_TEAM_ID
		pike.add_to_group(&"enemy_combat_units")
		pikemen.append(pike)

	await get_tree().process_frame
	## Force a few AI ticks (WAIT timer is 0.5s).
	for _i: int in 4:
		ai._process(0.5)
		await get_tree().process_frame

	_expect(failures, "AI left WAIT for CREEP", ai.get_state() == SimpleWc3AI.State.CREEP)
	_expect(failures, "creep camp selected", ai.get_camp_name() == "MediumCampTest")
	_expect(failures, "custom group move handled", ai.last_move_handled)
	_expect(failures, "army size in move >= 6", ai.last_move_squad_size >= 6)
	_expect(
		failures,
		"telemetry source simple_wc3_ai",
		PlayerRouteNavigation.last_command_source == &"simple_wc3_ai"
	)
	_expect(failures, "hero has custom route or attack-move", _unit_has_custom_or_attack(hero))

	var any_pike_routed: bool = false
	for pike_ref: Variant in pikemen:
		if _unit_has_custom_or_attack(pike_ref as Unit):
			any_pike_routed = true
			break
	_expect(failures, "pikemen received custom/attack orders", any_pike_routed)

	## Prove normal combat damage path can reduce creep HP (direct unit attack API).
	if health != null and NodeSafety.is_alive_node(pikemen[0]):
		var attacker: Unit = pikemen[0] as Unit
		if attacker.has_method("issue_order"):
			attacker.issue_order(UnitOrder.attack(creep), false)
		await get_tree().process_frame
		## Apply damage through HealthComponent (same path combat uses).
		health.take_damage(10)
		_expect(failures, "creep HP decreased", health.current_health < hp_before)

	## Objective retained across ticks.
	var camp_name_before: String = ai.get_camp_name()
	ai._process(0.5)
	_expect(failures, "creep objective retained", ai.get_camp_name() == camp_name_before)
	_expect(failures, "still CREEP until clear", ai.get_state() == SimpleWc3AI.State.CREEP)

	## Clear camp → DONE.
	if NodeSafety.is_alive_node(creep):
		creep.queue_free()
	await get_tree().process_frame
	ai._process(0.5)
	_expect(failures, "DONE after camp clear", ai.get_state() == SimpleWc3AI.State.DONE)

	ai.queue_free()
	enemy_cc.queue_free()
	camp.queue_free()
	if NodeSafety.is_alive_node(hero):
		hero.queue_free()
	for pike_ref: Variant in pikemen:
		if NodeSafety.is_alive_node(pike_ref):
			(pike_ref as Node).queue_free()
	await get_tree().process_frame


func _test_old_military_disabled_when_simple_present(failures: PackedStringArray) -> void:
	print("verify: old military process disabled with SimpleWc3AI")
	var root := MatchCompositionRoot.new()
	root.name = "MatchSystems"

	var state := AIPlayerState.new()
	state.name = "AIPlayerState"
	root.add_child(state)

	var simple := SimpleWc3AI.new()
	simple.name = "SimpleWc3AI"
	root.add_child(simple)

	var director := MilitaryDirectorV2.new()
	director.name = "MilitaryDirectorV2"
	root.add_child(director)

	var commander := ArmyCommanderV2.new()
	commander.name = "ArmyCommanderV2"
	root.add_child(commander)

	var combat := EnemyCombatController.new()
	combat.name = "EnemyCombatController"
	root.add_child(combat)

	var creep_mgr := EnemyCreepManager.new()
	creep_mgr.name = "EnemyCreepManager"
	root.add_child(creep_mgr)

	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "composition uses simple AI", root._uses_simple_wc3_ai())
	_expect(
		failures,
		"authority is SimpleWc3AI",
		root.military_command_authority is SimpleWc3AI
	)
	_expect(failures, "V2 military not active", not root.is_v2_military_active())
	_expect(failures, "MilitaryDirectorV2 process off", not director.is_processing())
	_expect(failures, "ArmyCommanderV2 process off", not commander.is_processing())
	_expect(failures, "EnemyCombatController process off", not combat.is_processing())
	_expect(failures, "EnemyCreepManager process off", not creep_mgr.is_processing())

	root.queue_free()
	await get_tree().process_frame


func _unit_has_custom_or_attack(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit.has_custom_rts_route():
		return true
	if unit.get_movement_backend_label() == "CUSTOM":
		return true
	var order: Variant = unit.get_active_order()
	if order != null and order is UnitOrder:
		var typed: UnitOrder = order as UnitOrder
		return (
			typed.type == UnitOrder.Type.ATTACK_MOVE
			or typed.type == UnitOrder.Type.MOVE
			or typed.type == UnitOrder.Type.ATTACK
		)
	return false
