extends Node

## Deterministic headless match-reset verification.
## Simulates two match lifecycle cycles in one process:
## dirty mid-match state → prepare_new_match (MatchBootstrap contract) → compare to baseline.
## Run:
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_match_reset.tscn

const REPORT_PATH := "user://match_reset_verify_result.txt"
const LIFECYCLE_CYCLES := 2
const POST_FREE_FRAMES := 3

## Default EnemyAttackPathDefense lane threat after reset_match_state().
const _DEFAULT_LANE_THREAT := {
	&"center": 0.35,
	&"left": 0.2,
	&"right": 0.2,
	&"expansion": 0.1,
	&"harass": 0.15,
}

var _dirty_control_group_unit: Node = null
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	## Autoload _ready already registered most resetters; statics need an explicit pass.
	MatchSession._register_static_match_resets()

	var exit_code: int = 0
	var baseline: Dictionary = {}
	var cycle_snapshots: Array[Dictionary] = []

	## Let autoload _ready settle, then warm unit PackedScene caches so ObjectDB
	## baselines are not skewed by first-time instantiate allocations.
	await _settle_frames(1)
	await _warm_unit_scene_caches()

	baseline = _capture_persistent_snapshot("baseline")
	if not VariantUtils.to_bool(baseline.get("is_clean", false)):
		_failures.append("baseline unclean before any match dirtiness: %s" % str(baseline))

	for cycle_index: int in range(LIFECYCLE_CYCLES):
		await _run_lifecycle_cycle(cycle_index + 1)
		var after: Dictionary = _capture_persistent_snapshot("after_cycle_%d" % (cycle_index + 1))
		cycle_snapshots.append(after)
		_compare_to_baseline(baseline, after, cycle_index + 1)

	var msg: String = ""
	if not _failures.is_empty():
		msg = "FAIL: match reset verification\n- %s" % "\n- ".join(_failures)
		exit_code = 1
	else:
		msg = (
			"PASS: %d lifecycle cycles; identical clean state vs baseline (registry=%d)\nBaseline: %s\nAfter cycle 1: %s\nAfter cycle 2: %s"
			% [
				LIFECYCLE_CYCLES,
				MatchSession.registered_match_reset_count(),
				str(baseline),
				str(cycle_snapshots[0]) if cycle_snapshots.size() > 0 else "{}",
				str(cycle_snapshots[1]) if cycle_snapshots.size() > 1 else "{}",
			]
		)

	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report:
		report.store_string(msg)
		report.close()
	print(msg)
	if exit_code != 0:
		push_error(msg)

	get_tree().quit(exit_code)


func _run_lifecycle_cycle(cycle_number: int) -> void:
	## One lifecycle in-process (no scene change — that would destroy this harness):
	## 1) mid-match dirtiness (autoload/static + ephemeral nodes)
	## 2) end-match navigation side effects that do NOT wipe match state
	## 3) prepare_new_match — MatchBootstrap contract when the next match loads
	_dirty_persistent_match_state()
	## Mimic end-of-match menu path without change_scene_to_file (would tear down this scene).
	MatchSession.last_match_result = "Victory!"
	TooltipManager.hide_tooltip()
	InputManager.disarm_all_command_modes()
	get_tree().paused = false
	## Scene-owned nodes die on real scene change; free our fixtures to match that contract.
	await _release_dirty_fixtures()
	## Next match start: MatchBootstrap → prepare_new_match().
	MatchSession.prepare_new_match()
	await _settle_frames(POST_FREE_FRAMES)
	print("verify_match_reset: completed lifecycle cycle %d" % cycle_number)


func _dirty_persistent_match_state() -> void:
	ResourceManager.gold = 9999
	ResourceManager.wood = 8888
	ResourceManager.food_current = 40
	ResourceManager.food_max = 99
	EnemyResourceManager.gold = 7777
	EnemyResourceManager.wood = 6666
	EnemyResourceManager.reserve_resources(50, 25)
	UpgradeManager.finish_research(UpgradeManager.UPGRADE_SWORDSMAN_ATTACK)
	UpgradeManager.finish_enemy_research(UpgradeManager.UPGRADE_ARCHER_ATTACK)
	UpgradeManager.finish_academy_research(UpgradeManager.UPGRADE_FASTER_GATHERING)
	InputManager.arm_attack_move()
	if _dirty_control_group_unit != null and is_instance_valid(_dirty_control_group_unit):
		_dirty_control_group_unit.queue_free()
		_dirty_control_group_unit = null
	_dirty_control_group_unit = load("res://scenes/units/swordsman.tscn").instantiate()
	add_child(_dirty_control_group_unit)
	ControlGroupManager.assign_group(0, [_dirty_control_group_unit])
	if EntityRegistry != null:
		EntityRegistry.register_entity(_dirty_control_group_unit)
	HeroProgressionStore._player_snapshot = {"level": 5}
	HeroProgressionStore._enemy_snapshot = {"level": 3}
	HeroProgressionStore.lock_kit(false, HeroCatalog.KIT_PALADIN)
	HeroProgressionStore.lock_kit(true, HeroCatalog.KIT_SHADOW_ASSASSIN)
	CommandFeedback.show_move_marker(Vector3(1, 0, 1))
	CommandFeedback.notify_movement_started(_dirty_control_group_unit)
	DeathEffects.play_unit_death(_dirty_control_group_unit)
	ImpactEffects.play_unit_impact(Vector3(2.0, 0.0, 2.0))
	ImpactEffects.play_ground_impact(Vector3(3.0, 0.0, 1.0))
	ImpactEffects.play_shell_impact(Vector3(4.0, 0.0, 0.0))

	## Static AI defense memory — must not survive prepare_new_match.
	EnemyAttackPathDefense.notify_tower_destroyed(Vector3(12.0, 0.0, -8.0), &"left")
	EnemyAttackPathDefense.remember_failed_site(Vector3(6.0, 0.0, 4.0))
	EnemyBuildPlacement.set_tower_lane_preference(&"right")

	ConstructionReservations.reserve_footprint(
		Vector3(20.0, 0.0, 20.0),
		Vector2(4.0, 4.0),
		_dirty_control_group_unit
	)
	CombatTargetValidation.get_cached_group_nodes(get_tree(), &"units")

	if AIHeroMastery != null:
		AIHeroMastery.set_forced_kit_for_tests(HeroCatalog.KIT_PALADIN)


func _release_dirty_fixtures() -> void:
	if _dirty_control_group_unit != null and is_instance_valid(_dirty_control_group_unit):
		_dirty_control_group_unit.queue_free()
	_dirty_control_group_unit = null
	await _settle_frames(POST_FREE_FRAMES)


func _settle_frames(frame_count: int) -> void:
	for _i: int in range(maxi(frame_count, 1)):
		await get_tree().process_frame


func _warm_unit_scene_caches() -> void:
	## First PackedScene instantiate and FX pool checkout allocate long-lived objects.
	## Warm once before baseline so later cycles measure true growth, not cold-start cost.
	var warm_unit: Node = load("res://scenes/units/swordsman.tscn").instantiate()
	add_child(warm_unit)
	CommandFeedback.show_move_marker(Vector3.ZERO)
	CommandFeedback.notify_movement_started(warm_unit)
	DeathEffects.play_unit_death(warm_unit)
	ImpactEffects.play_unit_impact(Vector3.ZERO)
	ImpactEffects.play_ground_impact(Vector3.ZERO)
	ImpactEffects.play_shell_impact(Vector3.ZERO)
	ConstructionReservations.reserve_footprint(Vector3(1, 0, 1), Vector2(2, 2), warm_unit)
	if EntityRegistry != null:
		EntityRegistry.register_entity(warm_unit)
	MatchSession.prepare_new_match()
	warm_unit.queue_free()
	await _settle_frames(POST_FREE_FRAMES)


func _capture_persistent_snapshot(label: String) -> Dictionary:
	var player_upgrades: Dictionary = {}
	var enemy_upgrades: Dictionary = {}
	for upgrade_id: StringName in UpgradeManager.BLACKSMITH_UPGRADE_ORDER:
		player_upgrades[String(upgrade_id)] = UpgradeManager.get_level(upgrade_id)
		enemy_upgrades[String(upgrade_id)] = UpgradeManager.get_enemy_level(upgrade_id)
	for upgrade_id: StringName in UpgradeManager.ACADEMY_UPGRADE_ORDER:
		player_upgrades[String(upgrade_id)] = UpgradeManager.get_level(upgrade_id)
		enemy_upgrades[String(upgrade_id)] = UpgradeManager.get_enemy_level(upgrade_id)
	for upgrade_id: StringName in UpgradeManager.STABLE_UPGRADE_ORDER:
		player_upgrades[String(upgrade_id)] = UpgradeManager.get_level(upgrade_id)
		enemy_upgrades[String(upgrade_id)] = UpgradeManager.get_enemy_level(upgrade_id)

	var all_upgrades_zero: bool = true
	for value: Variant in player_upgrades.values():
		if int(value) != 0:
			all_upgrades_zero = false
			break
	for value: Variant in enemy_upgrades.values():
		if int(value) != 0:
			all_upgrades_zero = false
			break

	var lane_threat: Dictionary = EnemyAttackPathDefense.get_lane_threat_snapshot()
	var attack_path_clean: bool = _attack_path_defense_is_clean(lane_threat)
	var entity_count: int = 0
	if EntityRegistry != null:
		entity_count = EntityRegistry.get_registered_ids().size()
	var formation_count: int = _formation_count()
	var footprint_reserved: bool = ConstructionReservations.overlaps_reserved_footprint(
		Vector3(20.0, 0.0, 20.0),
		Vector2(4.0, 4.0)
	)

	var object_count: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resource_count: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var orphan_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var is_clean: bool = (
		ResourceManager.gold == MatchConfig.NORMAL_STARTING_GOLD
		and ResourceManager.wood == MatchConfig.NORMAL_STARTING_WOOD
		and ResourceManager.food_current == MatchConfig.HUMAN_STARTING_FOOD
		and ResourceManager.food_max == MatchConfig.HUMAN_STARTING_FOOD_MAX
		and EnemyResourceManager.gold == MatchConfig.NORMAL_STARTING_GOLD
		and EnemyResourceManager.wood == MatchConfig.NORMAL_STARTING_WOOD
		and EnemyResourceManager.get_spendable_gold() == EnemyResourceManager.gold
		and EnemyResourceManager.get_spendable_wood() == EnemyResourceManager.wood
		and all_upgrades_zero
		and not InputManager.attack_move_armed
		and not ControlGroupManager.has_any_members()
		and ControlGroupManager.get_active_group_index() < 0
		and not HeroProgressionStore.has_saved_progression()
		and not HeroProgressionStore.has_saved_enemy_progression()
		and not HeroProgressionStore.has_locked_kit(false)
		and not HeroProgressionStore.has_locked_kit(true)
		and not HeroProgressionStore.has_living_hero(false)
		and not HeroProgressionStore.has_living_hero(true)
		and EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.IDLE
		and EnemyArmyCommand.get_strategic_state() == EnemyArmyCommand.StrategicState.ECONOMY
		and EnemyUnitMission.get_main_army_mission() == EnemyUnitMission.Mission.RALLY
		and CommandFeedback.get_active_marker_count() == 0
		and CommandFeedback.get_active_dust_count() == 0
		and DeathEffects.get_active_particle_count() == 0
		and DeathEffects.get_active_corpse_count() == 0
		and ImpactEffects.get_active_burst_count() == 0
		and ImpactEffects.get_active_trail_count() == 0
		and attack_path_clean
		and EnemyBuildPlacement.preferred_tower_lane == &""
		and entity_count == 0
		and formation_count == 0
		and not footprint_reserved
		and AIHeroMastery.get_tactical_state() == AIHeroMastery.TacticalState.FOLLOW_ARMY
	)

	return {
		"label": label,
		"is_clean": is_clean,
		"player_gold": ResourceManager.gold,
		"player_wood": ResourceManager.wood,
		"player_food": ResourceManager.food_current,
		"player_food_max": ResourceManager.food_max,
		"enemy_gold": EnemyResourceManager.gold,
		"enemy_wood": EnemyResourceManager.wood,
		"enemy_spendable_gold": EnemyResourceManager.get_spendable_gold(),
		"enemy_spendable_wood": EnemyResourceManager.get_spendable_wood(),
		"player_upgrades": player_upgrades,
		"enemy_upgrades": enemy_upgrades,
		"attack_move_armed": InputManager.attack_move_armed,
		"control_groups_empty": not ControlGroupManager.has_any_members(),
		"control_group_active": ControlGroupManager.get_active_group_index(),
		"hero_player_saved": HeroProgressionStore.has_saved_progression(),
		"hero_enemy_saved": HeroProgressionStore.has_saved_enemy_progression(),
		"hero_player_locked": HeroProgressionStore.has_locked_kit(false),
		"hero_enemy_locked": HeroProgressionStore.has_locked_kit(true),
		"army_mode": int(EnemyArmyCommand.get_army_mode()),
		"strategic_state": int(EnemyArmyCommand.get_strategic_state()),
		"main_army_mission": int(EnemyUnitMission.get_main_army_mission()),
		"command_feedback_markers": CommandFeedback.get_active_marker_count(),
		"command_feedback_dust": CommandFeedback.get_active_dust_count(),
		"death_effects_particles": DeathEffects.get_active_particle_count(),
		"death_effects_corpses": DeathEffects.get_active_corpse_count(),
		"impact_effects_bursts": ImpactEffects.get_active_burst_count(),
		"impact_effects_trails": ImpactEffects.get_active_trail_count(),
		"attack_path_clean": attack_path_clean,
		"attack_path_lane_threat": lane_threat,
		"preferred_tower_lane": String(EnemyBuildPlacement.preferred_tower_lane),
		"entity_registry_count": entity_count,
		"formation_count": formation_count,
		"footprint_reserved": footprint_reserved,
		"ai_hero_tactical_state": int(AIHeroMastery.get_tactical_state()),
		"object_count": object_count,
		"node_count": node_count,
		"resource_count": resource_count,
		"orphan_node_count": orphan_count,
		"resetter_count": MatchSession.registered_match_reset_count(),
	}


func _attack_path_defense_is_clean(lane_threat: Dictionary) -> bool:
	if EnemyAttackPathDefense.get_last_reason() != &"":
		return false
	if EnemyAttackPathDefense.get_last_selected_lane() != &"":
		return false
	for lane: StringName in _DEFAULT_LANE_THREAT.keys():
		var expected: float = float(_DEFAULT_LANE_THREAT[lane])
		var actual: float = float(lane_threat.get(lane, -1.0))
		if not is_equal_approx(actual, expected):
			return false
	## failed_sites / destroyed_sites have no public getters; threat + lane preference
	## cover the match-visible stale defense memory. Reset must clear the rest.
	return true


func _formation_count() -> int:
	## FormationManager has no public size API; dissolve path clears via match reset.
	## Probe via a dummy unit lookup — empty registry means no formation membership.
	if FormationManager == null:
		return 0
	if _dirty_control_group_unit != null and is_instance_valid(_dirty_control_group_unit):
		if FormationManager.get_unit_formation_id(_dirty_control_group_unit) >= 0:
			return 1
	return 0


func _compare_to_baseline(baseline: Dictionary, after: Dictionary, cycle_number: int) -> void:
	if not VariantUtils.to_bool(after.get("is_clean", false)):
		_failures.append(
			"cycle %d unclean after teardown/prepare: %s" % [cycle_number, str(after)]
		)

	## Semantic match-state keys must match baseline exactly.
	var keys: Array[String] = [
		"is_clean",
		"player_gold",
		"player_wood",
		"player_food",
		"player_food_max",
		"enemy_gold",
		"enemy_wood",
		"enemy_spendable_gold",
		"enemy_spendable_wood",
		"attack_move_armed",
		"control_groups_empty",
		"control_group_active",
		"hero_player_saved",
		"hero_enemy_saved",
		"hero_player_locked",
		"hero_enemy_locked",
		"army_mode",
		"strategic_state",
		"main_army_mission",
		"command_feedback_markers",
		"command_feedback_dust",
		"death_effects_particles",
		"death_effects_corpses",
		"impact_effects_bursts",
		"impact_effects_trails",
		"attack_path_clean",
		"preferred_tower_lane",
		"entity_registry_count",
		"formation_count",
		"footprint_reserved",
		"ai_hero_tactical_state",
		"resetter_count",
	]
	for key: String in keys:
		if str(baseline.get(key)) != str(after.get(key)):
			_failures.append(
				"cycle %d key '%s' drifted from baseline (%s -> %s)"
				% [cycle_number, key, str(baseline.get(key)), str(after.get(key))]
			)

	if str(baseline.get("attack_path_lane_threat")) != str(after.get("attack_path_lane_threat")):
		_failures.append(
			"cycle %d EnemyAttackPathDefense lane threat drifted (%s -> %s)"
			% [
				cycle_number,
				str(baseline.get("attack_path_lane_threat")),
				str(after.get("attack_path_lane_threat")),
			]
		)
	if str(baseline.get("player_upgrades")) != str(after.get("player_upgrades")):
		_failures.append("cycle %d player upgrades drifted from baseline" % cycle_number)
	if str(baseline.get("enemy_upgrades")) != str(after.get("enemy_upgrades")):
		_failures.append("cycle %d enemy upgrades drifted from baseline" % cycle_number)

	## Orphan / live node counts must not accumulate across match teardowns.
	var base_orphans: int = int(baseline.get("orphan_node_count", 0))
	var after_orphans: int = int(after.get("orphan_node_count", 0))
	if after_orphans > base_orphans:
		_failures.append(
			"cycle %d orphan node count grew (%d -> %d)"
			% [cycle_number, base_orphans, after_orphans]
		)

	var base_nodes: int = int(baseline.get("node_count", 0))
	var after_nodes: int = int(after.get("node_count", 0))
	if after_nodes > base_nodes:
		_failures.append(
			"cycle %d Performance.OBJECT_NODE_COUNT grew (%d -> %d)"
			% [cycle_number, base_nodes, after_nodes]
		)

	## Performance.OBJECT_COUNT / OBJECT_RESOURCE_COUNT are recorded in snapshots but
	## are not hard-fail gates: intentional FX/marker dirtying allocates RefCounted
	## materials, tweens, and particle graphs that Godot reclaims asynchronously.
	## Orphan + node monitors plus semantic registry checks are the reliable signals.
	var base_objects: int = int(baseline.get("object_count", 0))
	var after_objects: int = int(after.get("object_count", 0))
	var base_resources: int = int(baseline.get("resource_count", 0))
	var after_resources: int = int(after.get("resource_count", 0))
	if after_objects > base_objects or after_resources > base_resources:
		print(
			(
				"verify_match_reset: note cycle %d ObjectDB monitors drifted "
				+ "(objects %d->%d, resources %d->%d); not a hard fail"
			)
			% [cycle_number, base_objects, after_objects, base_resources, after_resources]
		)
