extends Node

## PHASE 1 #5 — crash/freed-instance regression across orders, construction,
## hero casting, and match restart.
## Godot_v4.7-stable_win64.exe --headless --path <project> \
##   res://scenes/debug/verify_freed_instance_regression.tscn

const REPORT_PATH := "user://freed_instance_regression_verify_result.txt"
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const ASSASSIN_SCENE: PackedScene = preload("res://scenes/units/shadow_assassin.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")
const PLAYER_TEAM_ID: int = 0


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	ConstructionReservations.reset_match_state()
	HeroProgressionStore.clear()
	MatchSession._register_static_match_resets()
	if EntityRegistry != null:
		EntityRegistry.clear()
	if ControlGroupManager != null:
		ControlGroupManager.clear_all_groups()
	if HeroAbilityTargetingController != null:
		HeroAbilityTargetingController.cancel_targeting()

	await _verify_orders_freed_attack_target(failures)
	await _verify_orders_queued_attack_skips_freed(failures)
	await _verify_construction_destroy_releases_worker(failures)
	await _verify_construction_raw_free_releases_slots(failures)
	await _verify_hero_cast_rejects_freed_target(failures)
	await _verify_hero_move_to_cast_clears_on_free(failures)
	await _verify_targeting_cancels_on_hero_free(failures)
	await _verify_command_feedback_reset_kills_effect_tweens(failures)
	await _verify_match_restart_clears_stale_refs(failures)
	await _verify_ai_attack_objective_clears_freed(failures)

	var report: String
	if failures.is_empty():
		report = "PASS freed_instance_regression\n"
	else:
		report = "FAIL freed_instance_regression\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- " + label)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_orders_freed_attack_target(failures: PackedStringArray) -> void:
	var unit: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(unit)
	add_child(target)
	unit.global_position = Vector3.ZERO
	target.global_position = Vector3(2.0, 0.0, 0.0)
	target.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	target.building_state = Building.STATE_COMPLETED
	await _settle()

	unit.call("_begin_attack_on_target", target, -1, true)
	_expect(failures, "orders: attack target locked", unit.get("_attack_target") == target)

	target.queue_free()
	await _settle()

	_expect(failures, "orders: attack target cleared after free", unit.get("_attack_target") == null)
	var dangling: Variant = target
	_expect(
		failures,
		"orders: attack range false for freed variant",
		not VariantUtils.to_bool(unit.call("_is_in_attack_range", dangling))
	)

	unit.queue_free()
	await _settle()


func _verify_orders_queued_attack_skips_freed(failures: PackedStringArray) -> void:
	var unit: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	var target: Building = FARM_SCENE.instantiate() as Building
	add_child(unit)
	add_child(target)
	target.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	target.building_state = Building.STATE_COMPLETED
	await _settle()

	unit.issue_order(UnitOrder.move(Vector3(20.0, 0.0, 0.0)), false)
	unit.issue_order(UnitOrder.attack(target), true)
	target.queue_free()
	await _settle()

	unit.notify_order_completed(UnitOrder.Type.MOVE)
	await get_tree().process_frame

	var active: UnitOrder = unit.get_active_order()
	if active != null and active.type == UnitOrder.Type.ATTACK:
		_expect(
			failures,
			"orders: queued attack get_alive_target null",
			active.get_alive_target() == null
		)

	unit.queue_free()
	await _settle()


func _verify_construction_destroy_releases_worker(failures: PackedStringArray) -> void:
	ConstructionReservations.reset_match_state()
	var farm: Building = FARM_SCENE.instantiate() as Building
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(farm)
	add_child(worker)
	farm.global_position = Vector3(0.0, 0.5, 0.0)
	worker.global_position = Vector3(0.0, 0.5, -3.0)
	farm.start_under_construction()
	farm.setup_construction(10.0)
	await _settle()

	worker.start_construction_order(farm)
	await get_tree().process_frame
	ConstructionReservations.claim_build_slot(farm, worker, 0)
	_expect(
		failures,
		"construction: slot claimed before destroy",
		ConstructionReservations.count_build_slot_claims(farm) >= 1
	)

	var building_id: int = farm.get_instance_id()
	farm.destroy_building()
	farm.queue_free()
	await _settle()

	_expect(
		failures,
		"construction: destroy released slot owners",
		not ConstructionReservations.has_build_slot_owners_for_id(building_id)
	)
	_expect(
		failures,
		"construction: worker no longer assigned after destroy",
		not worker.is_on_construction_trip() and worker.get_build_target() == null
	)

	worker.queue_free()
	await _settle()


func _verify_construction_raw_free_releases_slots(failures: PackedStringArray) -> void:
	## Regression: queue_free without destroy_building must still release slots/workers.
	ConstructionReservations.reset_match_state()
	var farm: Building = FARM_SCENE.instantiate() as Building
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(farm)
	add_child(worker)
	farm.global_position = Vector3(4.0, 0.5, 0.0)
	worker.global_position = Vector3(4.0, 0.5, -3.0)
	farm.start_under_construction()
	farm.setup_construction(10.0)
	await _settle()

	worker.start_construction_order(farm)
	await get_tree().process_frame
	farm.register_builder(worker)
	ConstructionReservations.claim_build_slot(farm, worker, 1)
	var building_id: int = farm.get_instance_id()
	_expect(
		failures,
		"construction: raw-free setup has claims",
		ConstructionReservations.has_build_slot_owners_for_id(building_id)
	)

	farm.queue_free()
	await _settle()

	_expect(
		failures,
		"construction: raw free released slot owners via exit_tree",
		not ConstructionReservations.has_build_slot_owners_for_id(building_id)
	)
	_expect(
		failures,
		"construction: worker cleared after raw free",
		not worker.is_on_construction_trip() and worker.get_build_target() == null
	)

	worker.queue_free()
	await _settle()


func _unlock_ability(hero: MeleeHero, ability_id: StringName) -> void:
	hero.level = 16
	hero.ability_points = 20
	while hero.can_learn_ability(ability_id):
		hero.try_learn_ability(ability_id, false)
	hero.current_mana = hero.max_mana


func _verify_hero_cast_rejects_freed_target(failures: PackedStringArray) -> void:
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(hero)
	add_child(enemy)
	hero.global_position = Vector3.ZERO
	enemy.global_position = Vector3(1.2, 0.0, 0.0)
	await _settle()
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_E)

	var mana_before: int = hero.current_mana
	var dangling: Variant = enemy
	enemy.free()

	var cast_ok: bool = hero.try_cast_e(dangling)
	_expect(failures, "hero cast: freed E target rejected", not cast_ok)
	_expect(failures, "hero cast: freed E spends no mana", hero.current_mana == mana_before)

	var assassin: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	var dummy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(assassin)
	add_child(dummy)
	assassin.global_position = Vector3(10.0, 0.0, 0.0)
	dummy.global_position = Vector3(11.2, 0.0, 0.0)
	await _settle()
	_unlock_ability(assassin, HeroAbilityProgression.ABILITY_Q)
	mana_before = assassin.current_mana
	dangling = dummy
	dummy.free()

	cast_ok = VariantUtils.to_bool(assassin.call(&"try_axe_mark", dangling))
	_expect(failures, "hero cast: freed axe mark rejected", not cast_ok)
	_expect(failures, "hero cast: freed axe mark spends no mana", assassin.current_mana == mana_before)

	hero.queue_free()
	assassin.queue_free()
	await _settle()


func _verify_hero_move_to_cast_clears_on_free(failures: PackedStringArray) -> void:
	var hero: MeleeHero = ASSASSIN_SCENE.instantiate() as MeleeHero
	var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(hero)
	add_child(enemy)
	hero.global_position = Vector3.ZERO
	enemy.global_position = Vector3(20.0, 0.0, 0.0)
	await _settle()
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_Q)

	hero.begin_move_to_cast(HeroAbilityProgression.ABILITY_Q, enemy as Node3D)
	_expect(failures, "move-to-cast: armed", VariantUtils.to_bool(hero.get("_has_move_to_cast")))

	enemy.queue_free()
	await _settle()
	hero.call("_sanitize_move_to_cast_target")

	_expect(
		failures,
		"move-to-cast: cleared after target free",
		not VariantUtils.to_bool(hero.get("_has_move_to_cast"))
	)
	_expect(
		failures,
		"move-to-cast: target null after free",
		hero.get("_move_to_cast_target") == null
	)

	hero.queue_free()
	await _settle()


func _verify_targeting_cancels_on_hero_free(failures: PackedStringArray) -> void:
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	add_child(hero)
	await _settle()
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_E)

	var began: bool = HeroAbilityTargetingController.begin_targeting(
		hero, HeroAbilityProgression.ABILITY_E
	)
	_expect(failures, "targeting: began for E", began)
	_expect(failures, "targeting: active after begin", HeroAbilityTargetingController.is_targeting())

	hero.queue_free()
	await _settle()
	## Controller _process must clear armed definition after hero free (not only is_targeting false).
	_expect(
		failures,
		"targeting: inactive after hero free",
		not HeroAbilityTargetingController.is_targeting()
	)
	_expect(
		failures,
		"targeting: get_active_hero null after free",
		HeroAbilityTargetingController.get_active_hero() == null
	)
	## Re-arm after clear must succeed with a new living hero (proves stale state was wiped).
	var hero2: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	add_child(hero2)
	await _settle()
	_unlock_ability(hero2, HeroAbilityProgression.ABILITY_E)
	var rearmed: bool = HeroAbilityTargetingController.begin_targeting(
		hero2, HeroAbilityProgression.ABILITY_E
	)
	_expect(failures, "targeting: can re-arm after prior hero free", rearmed)
	HeroAbilityTargetingController.cancel_targeting()
	hero2.queue_free()
	await _settle()


func _verify_command_feedback_reset_kills_effect_tweens(failures: PackedStringArray) -> void:
	## Mid-lifetime clear_all must not leave autoload tweens capturing freed FX nodes.
	CommandFeedback.clear_all()
	CommandFeedback.enabled = true
	CommandFeedback.markers_enabled = true
	CommandFeedback.dust_enabled = true

	CommandFeedback.show_move_marker(Vector3(1.0, 0.0, 1.0))
	CommandFeedback.show_attack_move_marker(Vector3(2.0, 0.0, 2.0))
	CommandFeedback.show_patrol_marker(Vector3(3.0, 0.0, 3.0))

	var unit: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	add_child(unit)
	unit.global_position = Vector3(0.0, 0.0, 0.0)
	await _settle()
	CommandFeedback.notify_movement_started(unit)

	_expect(
		failures,
		"command_feedback: markers alive before clear",
		CommandFeedback.get_active_marker_count() > 0
	)
	_expect(
		failures,
		"command_feedback: dust alive before clear",
		CommandFeedback.get_active_dust_count() > 0
	)

	CommandFeedback.clear_all()
	await _settle()
	## Allow any previously scheduled tween step to run after free.
	await get_tree().create_timer(0.2).timeout

	_expect(
		failures,
		"command_feedback: markers cleared after clear_all",
		CommandFeedback.get_active_marker_count() == 0
	)
	_expect(
		failures,
		"command_feedback: dust cleared after clear_all",
		CommandFeedback.get_active_dust_count() == 0
	)

	## Spawn again then tear down the parent scene nodes while FX tweens are live.
	CommandFeedback.show_move_marker(Vector3(4.0, 0.0, 4.0))
	CommandFeedback.notify_movement_started(unit)
	_expect(
		failures,
		"command_feedback: live fx before scene free",
		CommandFeedback.get_active_marker_count() > 0
		and CommandFeedback.get_active_dust_count() > 0
	)
	unit.queue_free()
	## Match reset must clear remaining FX without delayed freed captures.
	MatchSession.prepare_new_match()
	await _settle()
	await get_tree().create_timer(0.2).timeout
	_expect(
		failures,
		"command_feedback: prepare_new_match clears fx",
		CommandFeedback.get_active_marker_count() == 0
		and CommandFeedback.get_active_dust_count() == 0
	)


func _verify_match_restart_clears_stale_refs(failures: PackedStringArray) -> void:
	CombatTargetValidation.reset_match_state()
	ConstructionReservations.reset_match_state()
	HeroProgressionStore.clear()
	if ControlGroupManager != null:
		ControlGroupManager.clear_all_groups()

	var unit: MilitaryUnit = SWORDSMAN_SCENE.instantiate() as MilitaryUnit
	var target: Building = FARM_SCENE.instantiate() as Building
	var hero: MeleeHero = HERO_SCENE.instantiate() as MeleeHero
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	var farm: Building = FARM_SCENE.instantiate() as Building
	add_child(unit)
	add_child(target)
	add_child(hero)
	add_child(worker)
	add_child(farm)
	target.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	target.building_state = Building.STATE_COMPLETED
	farm.start_under_construction()
	farm.setup_construction(8.0)
	await _settle()

	unit.call("_begin_attack_on_target", target, -1, true)
	_unlock_ability(hero, HeroAbilityProgression.ABILITY_E)
	HeroAbilityTargetingController.begin_targeting(hero, HeroAbilityProgression.ABILITY_E)
	HeroProgressionStore.register_living_hero(hero)
	ControlGroupManager.assign_group(0, [unit, worker])
	worker.start_construction_order(farm)
	ConstructionReservations.claim_build_slot(farm, worker, 0)
	var farm_id: int = farm.get_instance_id()

	## Tear down tracking before freeing to avoid deferred group/lambda teardown noise.
	ControlGroupManager.clear_all_groups()
	HeroProgressionStore.clear()
	HeroAbilityTargetingController.cancel_targeting()

	## Free world nodes mid-"match", then run MatchSession prepare as rematch would.
	target.queue_free()
	farm.queue_free()
	unit.queue_free()
	worker.queue_free()
	hero.queue_free()
	await _settle()

	MatchSession.prepare_new_match()
	await _settle()

	_expect(
		failures,
		"restart: targeting cancelled",
		not HeroAbilityTargetingController.is_targeting()
	)
	_expect(
		failures,
		"restart: no living hero handle",
		not HeroProgressionStore.has_living_hero(false)
	)
	_expect(
		failures,
		"restart: control groups empty",
		ControlGroupManager.get_group_size(0) == 0
	)
	_expect(
		failures,
		"restart: construction slots cleared for freed farm",
		not ConstructionReservations.has_build_slot_owners_for_id(farm_id)
	)


func _verify_ai_attack_objective_clears_freed(failures: PackedStringArray) -> void:
	## Long-lived AI attack objective must be readable as Variant after free,
	## validated before cast, and cleared by the real maintain path.
	var state := AIPlayerState.new()
	add_child(state)
	EnemyArmyCommand.bind_match_composition(state, state)
	EnemyArmyCommand.reset_match_state()
	EnemyArmyCommand.try_claim_army_mode(EnemyArmyCommand.ArmyMode.ATTACKING, true)

	var objective: Building = FARM_SCENE.instantiate() as Building
	add_child(objective)
	objective.global_position = Vector3(12.0, 0.0, 8.0)
	objective.team_id = PLAYER_TEAM_ID
	objective.building_state = Building.STATE_COMPLETED
	await _settle()

	EnemyArmyCommand.set_attack_objective(objective, objective.global_position)
	_expect(
		failures,
		"ai objective: stored through attack-objective API",
		state.active_wave_objective == objective
	)
	_expect(
		failures,
		"ai objective: position stored",
		EnemyArmyCommand.get_attack_objective_position() == objective.global_position
	)

	objective.queue_free()
	await _settle()
	await get_tree().process_frame
	await get_tree().process_frame

	## Real maintain path: Variant read + NodeSafety before cast; clears stale.
	EnemyArmyCommand.maintain_attack_wave_objective(get_tree(), 1.0)

	var stored_after: Variant = state.active_wave_objective
	_expect(
		failures,
		"ai objective: no live objective after maintain",
		not NodeSafety.is_alive_node(stored_after)
	)
	_expect(
		failures,
		"ai objective: stale objective cleared from SoT",
		stored_after == null
	)
	_expect(
		failures,
		"ai objective: position fallback retained after free",
		EnemyArmyCommand.get_attack_objective_position() != Vector3.ZERO
	)

	EnemyArmyCommand.reset_match_state()
	EnemyArmyCommand.unbind_match_composition()
	state.queue_free()
	await _settle()
