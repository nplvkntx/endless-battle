class_name EnemyBuildManager
extends Node

## Enemy RTS build order: gather economy, place structures, train units, expand base.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const ENEMY_WORKER_GROUP := &"enemy_workers"
const TICK_INTERVAL_SECONDS: float = 2.0
const WORKER_PRODUCTION_CHECK_SECONDS: float = 1.0
const MACRO_EMERGENCY_INTERVAL_SECONDS: float = 3.0
const POP_CAP_EMERGENCY_SECONDS: float = 3.0
const TARGET_WORKERS_EARLY: int = 14
const TARGET_WORKERS_MID: int = 22
const TARGET_WORKERS_LATE: int = 30
const TARGET_WORKERS_ENDGAME: int = 36
const TARGET_WORKERS_ENDGAME_HIGH: int = 45
const HARD_WORKER_SAFETY_CAP: int = 50
const WORKER_QUEUE_TARGET: int = 2
const MIN_WORKERS_BEFORE_MILITARY: int = 6
const MIN_WORKERS_BEFORE_MILITARY_ABUNDANT: int = 4
const OPENING_FIRST_FARM_WORKER_COUNT: int = 5
const WORKER_REBUILD_THRESHOLD_RATIO: float = 0.60
const EXPANSION_CC_NEAR_MINE_DISTANCE: float = 22.0
const EXPANSION_PLACEMENT_RETRY_SECONDS: float = 10.0
const EXPANSION_UNSAFE_DISTANCE_PENALTY: float = 10000.0
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const WORKER_PHASE_MID_SECONDS: float = 180.0
const WORKER_PHASE_LATE_SECONDS: float = 360.0
const WORKER_PHASE_ENDGAME_SECONDS: float = 600.0
const WORKER_TRAIN_GOLD_COST: int = UnitStats.WORKER_GOLD_COST
const FARM_HEADROOM_EARLY: int = 4
const FARM_HEADROOM_MID: int = 7
const FARM_HEADROOM_LATE: int = 10
const MAX_FARMS: int = 8
const DEBUG_AI_WORKER_PRODUCTION: bool = false
## Legacy export default; runtime caps come from AIDifficultyConfig.
const DEFAULT_MAX_BARRACKS: int = 2
const PRODUCTION_EXPAND_FOOD_HEADROOM: int = 4
const DESIRED_ARMY_EARLY: int = 28
const DESIRED_ARMY_MID: int = 45
const DESIRED_ARMY_LATE: int = 60
const MILITARY_TRAINS_PER_BARRACKS_WHEN_LOW: int = 4
const MILITARY_TRAINS_PER_BARRACKS_SUSTAIN: int = 3
const MILITARY_TRAINS_PER_BARRACKS_ABUNDANT: int = 6
const RESOURCE_HIGH_THRESHOLD: int = 3000
const RESOURCE_AGGRESSIVE_THRESHOLD: int = 6000
const RESOURCE_WASTE_THRESHOLD: int = 10000
const MILITARY_LOW_ARMY_DEFICIT: int = 8
const MILITARY_DEFENSE_EXTRA_DESIRED: int = 6
const MILITARY_DEFENSE_TRAINS_PER_BARRACKS: int = 2
const ARMY_SIZE_MID_AFTER_SECONDS: float = 300.0
const ARMY_SIZE_LATE_AFTER_SECONDS: float = 600.0
const MILITARY_TRAIN_FOOD_COST: int = UnitStats.SWORDSMAN_FOOD_COST
const ENEMY_TEAM_ID: int = 1

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_BLACKSMITH: StringName = &"blacksmith"
const PLACEMENT_SHOP: StringName = &"shop"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"
const PLACEMENT_COMMAND_CENTER: StringName = &"command_center"
const PLACEMENT_STABLE: StringName = &"stable"
const PLACEMENT_ARTILLERY_DEPOT: StringName = &"artillery_depot"
const PLACEMENT_ACADEMY: StringName = &"academy"
const PLACEMENT_TOWER: StringName = &"tower"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/buildings/shop.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const ACADEMY_SCENE: PackedScene = preload("res://scenes/buildings/academy.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")
const HEALTH_COMPONENT_SCRIPT: Script = preload("res://scripts/components/health_component.gd")

## Building costs / HP — edit BuildingStats only (shared with player BuildManager).
const FARM_GOLD_COST: int = BuildingStats.FARM_GOLD_COST
const FARM_WOOD_COST: int = BuildingStats.FARM_WOOD_COST
const BARRACKS_GOLD_COST: int = BuildingStats.BARRACKS_GOLD_COST
const BARRACKS_WOOD_COST: int = BuildingStats.BARRACKS_WOOD_COST
const BLACKSMITH_GOLD_COST: int = BuildingStats.BLACKSMITH_GOLD_COST
const BLACKSMITH_WOOD_COST: int = BuildingStats.BLACKSMITH_WOOD_COST
const SHOP_GOLD_COST: int = BuildingStats.SHOP_GOLD_COST
const SHOP_WOOD_COST: int = BuildingStats.SHOP_WOOD_COST
const SHOP_STABLE_GOLD_BUFFER: int = 350
const SHOP_PURCHASE_COOLDOWN_TICKS: int = 7
const ACADEMY_RESEARCH_FAIL_COOLDOWN_TICKS: int = 5
const ACADEMY_RESEARCH_ARMY_GOLD_BUFFER: int = UnitStats.SWORDSMAN_GOLD_COST * 2
const SHOP_HERO_RALLY_DISTANCE: float = 18.0
const HERO_ALTAR_GOLD_COST: int = BuildingStats.HERO_ALTAR_GOLD_COST
const HERO_ALTAR_WOOD_COST: int = BuildingStats.HERO_ALTAR_WOOD_COST
const STABLE_GOLD_COST: int = BuildingStats.STABLE_GOLD_COST
const STABLE_WOOD_COST: int = BuildingStats.STABLE_WOOD_COST
const ARTILLERY_DEPOT_GOLD_COST: int = BuildingStats.ARTILLERY_DEPOT_GOLD_COST
const ARTILLERY_DEPOT_WOOD_COST: int = BuildingStats.ARTILLERY_DEPOT_WOOD_COST
const ACADEMY_GOLD_COST: int = BuildingStats.ACADEMY_GOLD_COST
const ACADEMY_WOOD_COST: int = BuildingStats.ACADEMY_WOOD_COST
const TOWER_GOLD_COST: int = BuildingStats.TOWER_GOLD_COST
const TOWER_WOOD_COST: int = BuildingStats.TOWER_WOOD_COST
const COMMAND_CENTER_GOLD_COST: int = BuildingStats.COMMAND_CENTER_GOLD_COST
const COMMAND_CENTER_WOOD_COST: int = BuildingStats.COMMAND_CENTER_WOOD_COST
const TIER_2_GOLD_COST: int = BuildingStats.CC_TIER_2_GOLD_COST
const TIER_2_WOOD_COST: int = BuildingStats.CC_TIER_2_WOOD_COST
const TIER_3_GOLD_COST: int = BuildingStats.CC_TIER_3_GOLD_COST
const TIER_3_WOOD_COST: int = BuildingStats.CC_TIER_3_WOOD_COST
const TIER_UPGRADE_STABLE_GOLD_BUFFER: int = 250
const TIER_UPGRADE_STABLE_WOOD_BUFFER: int = 150
const TIER_3_UPGRADE_STABLE_GOLD_BUFFER: int = 400
const TIER_3_UPGRADE_STABLE_WOOD_BUFFER: int = 250
const TIER_3_MIN_WORKERS: int = 14
const TIER_3_MIN_FARMS: int = 3
const TIER_3_MIN_FREE_POPULATION: int = 6
const TIER_3_MIN_ARMY: int = 18
const MAX_ENEMY_CANNONS: int = 3
const MIN_PLAYER_ARMY_FOR_CANNONS: int = 12
const CANNON_TRAIN_FOOD_COST: int = UnitStats.CANNON_FOOD_COST

const CONSTRUCTION_DURATION: float = BuildingStats.ENEMY_CONSTRUCTION_DURATION
const FARM_MAX_HEALTH: int = BuildingStats.FARM_MAX_HEALTH
const HERO_ALTAR_MAX_HEALTH: int = BuildingStats.HERO_ALTAR_MAX_HEALTH
const STABLE_MAX_HEALTH: int = BuildingStats.STABLE_MAX_HEALTH
const COMMAND_CENTER_MAX_HEALTH: int = BuildingStats.COMMAND_CENTER_MAX_HEALTH
const TOWER_MAX_HEALTH: int = BuildingStats.TOWER_MAX_HEALTH
const MAX_PARALLEL_CONSTRUCTIONS: int = 3
const STUCK_CONSTRUCTION_TIMEOUT_MSEC: int = 45000
const FARM_PLACEMENT_FAIL_COOLDOWN_SECONDS: float = 4.0
const FARM_RESOURCE_RESERVATION_TTL_MSEC: int = 30000
const TOWER_PLACEMENT_FAIL_COOLDOWN_SECONDS: float = 5.0
const TOWER_RESOURCE_RESERVATION_TTL_MSEC: int = 25000
const TOWER_ARMY_GOLD_BUFFER: int = UnitStats.SWORDSMAN_GOLD_COST * 2
const TOWER_HERO_GOLD_BUFFER: int = HeroStats.TRAIN_GOLD_COST
const MIN_ARMY_BEFORE_OPTIONAL_TOWERS: int = 4

@export var enemy_command_center_path: NodePath
@export var enemy_gather_manager_path: NodePath
@export var buildings_parent_path: NodePath = NodePath("..")
@export var max_barracks: int = DEFAULT_MAX_BARRACKS

var _primary_command_center: CommandCenter = null
var _train_swordsman_next: bool = true
var _train_cavalry_next: bool = true
var _tick_active: bool = true
var _worker_production_active: bool = true
var _shop_purchase_cooldown_ticks: int = 0
var _academy_research_complete: bool = false
var _academy_research_fail_cooldown_ticks: int = 0
var _director: EnemyStrategicDirector = null
var _last_worker_idle_reason: String = ""
var _pop_capped_since_seconds: float = -1.0
var _macro_emergency_timer: float = 0.0
var _farm_reservation_active: bool = false
var _farm_reservation_msec: int = 0
var _farm_placement_fail_cooldown_until: float = -1.0
var _tower_reservation_active: bool = false
var _tower_reservation_msec: int = 0
var _tower_placement_fail_cooldown_until: float = -1.0
var _tower_lane_bindings: Dictionary = {} ## instance_id -> lane
var _cc_worker_queue_connected: bool = false
var _building_scan_frame: int = -1
var _cached_enemy_buildings: Array = []
var _cached_worker_count: int = -1
var _cached_worker_count_frame: int = -1
var _cached_military_count: int = -1
var _cached_military_count_frame: int = -1
var _last_production_fingerprint: String = ""
var _production_skip_stale_ticks: int = 0
var _expansion_target_mine: GoldMine = null
var _expansion_placement_cooldown_until: float = -1.0
var _expansion_order_active: bool = false
var _expansion_failed_mine_cooldowns: Dictionary = {}
var _opening_first_farm_builder_logged: bool = false
var _tier_2_upgrade_was_progressing: bool = false
var _tier_2_upgrade_started_logged: bool = false
var _tier_2_last_block_reason: String = ""
var _tier_2_last_missing_building: StringName = &""


func _ready() -> void:
	call_deferred("_begin_build_order")


func _begin_build_order() -> void:
	_director = get_parent().get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector
	_primary_command_center = _resolve_primary_command_center()
	if _primary_command_center == null:
		push_warning("EnemyBuildManager: enemy Command Center not found")
		return

	_connect_command_center_worker_signals()
	_schedule_tick()
	_schedule_worker_production_check()


func _connect_command_center_worker_signals() -> void:
	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or _cc_worker_queue_connected:
		return

	if not command_center.worker_queue_changed.is_connected(_on_command_center_worker_queue_changed):
		command_center.worker_queue_changed.connect(_on_command_center_worker_queue_changed)
	_cc_worker_queue_connected = true


func _on_command_center_worker_queue_changed(_queue_count: int) -> void:
	request_worker_production_check()


func request_worker_production_check() -> void:
	call_deferred("_try_train_enemy_workers")


func _schedule_worker_production_check() -> void:
	if not _worker_production_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(WORKER_PRODUCTION_CHECK_SECONDS)
	wait_timer.timeout.connect(_on_worker_production_tick, CONNECT_ONE_SHOT)


func _on_worker_production_tick() -> void:
	if not _worker_production_active or not is_inside_tree():
		return

	if _resolve_primary_command_center() == null:
		_worker_production_active = false
		return

	_try_train_enemy_workers()
	_schedule_worker_production_check()


func _schedule_tick() -> void:
	if not _tick_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(TICK_INTERVAL_SECONDS)
	wait_timer.timeout.connect(_on_build_tick, CONNECT_ONE_SHOT)


func _on_build_tick() -> void:
	if not _tick_active or not is_inside_tree():
		return

	if _resolve_primary_command_center() == null:
		_tick_active = false
		return

	## Stagger production away from strategic fast ticks (odd process frames).
	if (Engine.get_process_frames() % 2) == 0:
		var defer_timer: SceneTreeTimer = get_tree().create_timer(0.05)
		defer_timer.timeout.connect(_on_build_tick, CONNECT_ONE_SHOT)
		return

	var fingerprint: String = _build_production_fingerprint()
	if fingerprint == _last_production_fingerprint and _production_skip_stale_ticks < 2:
		_production_skip_stale_ticks += 1
		_schedule_tick()
		return

	_production_skip_stale_ticks = 0
	_last_production_fingerprint = fingerprint
	var start_usec: int = PerfCounters.begin_section()
	_run_build_order()
	PerfCounters.end_section("Production update", start_usec)
	PerfCounters.record_ai_decision_update()
	_schedule_tick()


func _build_production_fingerprint() -> String:
	return "%d|%d|%d|%d|%d|%d" % [
		_count_enemy_workers(),
		_count_living_military_units(),
		_cached_enemy_buildings.size(),
		int(EnemyResourceManager.gold),
		int(EnemyResourceManager.wood),
		int(EnemyArmyCommand.get_strategic_state()),
	]


func _run_build_order() -> void:
	_refresh_building_cache_if_needed()
	ConstructionReservations.purge_expired()
	_release_stale_build_workers()
	_try_assign_idle_builder_to_construction()
	_cancel_stuck_unfinished_constructions()
	_run_macro_emergency_checks()

	if _is_opening_phase():
		_run_opening_build_order()
		return

	if _is_early_army_phase():
		_run_early_army_build_order()
		return

	if _is_tier_2_phase():
		_run_tier_2_build_order()
		return

	if not EnemyResourceManager.has_food_supply(1) and _needs_farm():
		if _try_place_farm(true):
			return

	_try_train_enemy_workers()

	if _needs_farm():
		_try_place_farm(false)

	var defer_military: bool = _update_enemy_hero_restoration()

	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		return

	if _should_place_barracks() and _try_place_building(PLACEMENT_BARRACKS):
		return

	if _should_build_expansion_barracks():
		if _try_place_building(PLACEMENT_BARRACKS):
			return

	if _needs_farm():
		if _try_place_farm(false):
			pass

	if not _has_completed_building(PLACEMENT_BARRACKS) and not _is_building_type_in_progress(
		PLACEMENT_BARRACKS
	):
		if _try_place_building(PLACEMENT_BARRACKS):
			return

	_try_upgrade_command_center_tier()

	if _should_build_blacksmith():
		if _try_place_building(PLACEMENT_BLACKSMITH):
			return

	_try_sustain_blacksmith_research()

	if _should_build_tower():
		if _try_place_tower():
			return

	if _should_build_hero_altar():
		if _try_place_building(PLACEMENT_HERO_ALTAR):
			return

	if _should_build_stable():
		if _try_place_building(PLACEMENT_STABLE):
			return

	_try_sustain_stable_research()

	if _should_build_shop():
		if _try_place_building(PLACEMENT_SHOP):
			return

	_try_sustain_shop_purchases()

	if _should_build_artillery_depot():
		if _try_place_building(PLACEMENT_ARTILLERY_DEPOT):
			return

	if _should_build_academy():
		if _try_place_building(PLACEMENT_ACADEMY):
			return

	_try_sustain_academy_research()

	if not defer_military and _can_train_military_units():
		_try_sustain_military_production()
		_try_sustain_stable_production()
		_try_sustain_artillery_production()

	if _should_build_expansion_command_center():
		_try_place_expansion_command_center()


func _is_opening_phase() -> bool:
	return (
		_director != null
		and _director.get_strategic_phase() == EnemyStrategicDirector.StrategicPhase.OPENING
	)


func _is_early_army_phase() -> bool:
	return (
		_director != null
		and _director.get_strategic_phase() == EnemyStrategicDirector.StrategicPhase.EARLY_ARMY
	)


func _is_tier_2_phase() -> bool:
	return (
		_director != null
		and _director.get_strategic_phase() == EnemyStrategicDirector.StrategicPhase.TIER_2
	)


func _run_opening_build_order() -> void:
	## Strict OPENING sequence: Farm -> Hero Altar -> Barracks, with worker growth.
	if not EnemyResourceManager.has_food_supply(1) and _needs_farm():
		_try_place_farm(true)

	# Rebuild construction assignments if the farm builder died mid-opening.
	_ensure_opening_first_farm_builder()
	_log_opening_first_farm_builder_if_needed()

	## Keep training workers toward opening target (no military yet).
	_try_train_enemy_workers()

	if _try_place_opening_first_farm():
		return

	# Extra farms before the population cap while the core sequence continues.
	if _has_completed_building(PLACEMENT_FARM) and _needs_farm():
		_try_place_farm(false)

	if not _has_completed_building(PLACEMENT_FARM):
		return

	if _try_place_opening_core_building(PLACEMENT_HERO_ALTAR):
		return

	if not _has_completed_building(PLACEMENT_HERO_ALTAR):
		return

	if _try_place_opening_core_building(PLACEMENT_BARRACKS):
		return

	if _needs_farm():
		_try_place_farm(false)


func _run_early_army_build_order() -> void:
	## EARLY_ARMY: train hero, build 5–10 Pikemen, farms, workers. No offense.
	if not EnemyResourceManager.has_food_supply(1) and _needs_farm():
		_try_place_farm(true)

	_try_train_enemy_workers()

	if _needs_farm():
		_try_place_farm(false)

	if not _has_completed_building(PLACEMENT_BARRACKS) and not _is_building_type_in_progress(
		PLACEMENT_BARRACKS
	):
		_try_place_building(PLACEMENT_BARRACKS)

	if not _has_completed_building(PLACEMENT_HERO_ALTAR) and not _is_building_type_in_progress(
		PLACEMENT_HERO_ALTAR
	):
		_try_place_building(PLACEMENT_HERO_ALTAR)

	_try_train_early_army_hero()
	_try_train_early_army_pikemen()

	## Emergency / early-rush towers only — do not spam during opening army build.
	if _should_build_tower(true):
		_try_place_tower(true)

	if _needs_farm():
		_try_place_farm(false)


func _try_train_early_army_hero() -> void:
	if _has_living_enemy_hero():
		return

	var hero_altar: HeroAltar = _find_enemy_hero_altar()
	if hero_altar == null:
		return

	if hero_altar.is_training_hero():
		return

	## Lock equal-weight random kit once before the first Altar training order.
	AIHeroMastery.ensure_enemy_hero_choice()

	if hero_altar.try_train_enemy_hero():
		EnemyAIDebug.log_early_army("Training Hero")


func _count_living_pikemen() -> int:
	var count: int = 0
	for unit: Variant in EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree()):
		if unit is Spearman:
			count += 1
	return count


func _count_pending_pikemen() -> int:
	var pending: int = 0
	for barracks: Barracks in _find_all_completed_enemy_barracks():
		if not is_instance_valid(barracks):
			continue
		pending += barracks.get_spearman_queue_count()
	return pending


func _get_early_army_pikemen_target() -> int:
	var alive: int = _count_living_pikemen()
	var pending: int = _count_pending_pikemen()
	var total: int = alive + pending

	if total < EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN:
		return EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN

	if (
		EnemyResourceManager.has_food_supply(MILITARY_TRAIN_FOOD_COST)
		and EnemyResourceManager.can_afford_training(Barracks.SPEARMAN_TRAIN_GOLD_COST, MILITARY_TRAIN_FOOD_COST)
	):
		if (
			total < EnemyStrategicDirector.EARLY_ARMY_SOFT_PIKEMEN
			or (
				total < EnemyStrategicDirector.EARLY_ARMY_TARGET_PIKEMEN
				and (
					_has_excess_resources()
					or EnemyResourceManager.gold >= Barracks.SPEARMAN_TRAIN_GOLD_COST * 2
				)
			)
		):
			return EnemyStrategicDirector.EARLY_ARMY_TARGET_PIKEMEN

	return EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN


func _try_train_early_army_pikemen() -> void:
	var alive: int = _count_living_pikemen()
	var pending: int = _count_pending_pikemen()
	var total: int = alive + pending
	var target: int = _get_early_army_pikemen_target()

	EnemyAIDebug.log_early_army_pikemen(
		alive,
		EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN
	)

	if total >= target:
		return

	if not EnemyResourceManager.has_food_supply(MILITARY_TRAIN_FOOD_COST):
		if _needs_farm() or _count_completed_farms() + _count_farms_under_construction() < MAX_FARMS:
			_try_place_farm(true)
		return

	for barracks: Barracks in _find_all_completed_enemy_barracks():
		if not is_instance_valid(barracks):
			continue

		while barracks.get_enemy_pending_unit_count() < Barracks.MAX_ENEMY_UNIT_QUEUE:
			alive = _count_living_pikemen()
			pending = _count_pending_pikemen()
			total = alive + pending
			if total >= target:
				return

			if not barracks.try_train_enemy_spearman():
				break

			EnemyAIDebug.log_early_army_pikemen(
				_count_living_pikemen(),
				EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN
			)


func _run_tier_2_build_order() -> void:
	## TIER_2: finish Tier 1 setup, save for Town Hall upgrade, keep economy alive.
	if not EnemyResourceManager.has_food_supply(1) and _needs_farm():
		_try_place_farm(true)

	# Leave the Command Center idle once the upgrade is otherwise ready.
	if not _should_hold_workers_for_imminent_tier_2_upgrade():
		_try_train_enemy_workers()

	if _needs_farm() or _needs_farm_headroom_for_tier_2_upgrade():
		_try_place_farm(false)

	var missing_tier_1: Array[StringName] = _get_missing_tier_1_setup_buildings()
	_log_tier_2_missing_buildings(missing_tier_1)
	if not missing_tier_1.is_empty():
		_try_place_missing_tier_1_building(missing_tier_1[0])
		_log_tier_2_block_reason("Missing Tier 1 buildings")
		return

	# Essential early-army replacement only — avoid spending the Tier 2 stockpile.
	_try_replace_essential_tier_2_pikemen()

	## Emergency towers only — do not drain the Tier 2 upgrade bank.
	if _should_build_tower(true):
		_try_place_tower(true)

	if _update_tier_2_town_hall_upgrade():
		return

	if _needs_farm():
		_try_place_farm(false)


func _should_hold_workers_for_imminent_tier_2_upgrade() -> bool:
	if not _is_tier_2_phase():
		return false

	if TechTree.player_has_tier_2(ENEMY_TEAM_ID) or _is_any_enemy_command_center_upgrading():
		return false

	if not _has_required_tier_1_setup_present():
		return false

	if _get_enemy_hero_level() < EnemyStrategicDirector.CREEP_HERO_LEVEL_REQUIREMENT:
		return false

	if not _is_tier_2_army_ready_for_upgrade():
		return false

	if not _is_tier_2_base_safe_for_upgrade():
		return false

	if not _can_afford_tier_2_upgrade():
		return false

	if _needs_farm_headroom_for_tier_2_upgrade():
		return false

	# Only pause once the economy target is already met (or nearly met).
	return _get_effective_worker_count() >= _get_target_worker_count() - 1


func _get_required_tier_1_setup_buildings() -> Array[StringName]:
	return TechTree.get_core_setup_buildings_for_command_center_tier(1)


func _get_missing_tier_1_setup_buildings() -> Array[StringName]:
	var missing: Array[StringName] = []
	for building_type: StringName in _get_required_tier_1_setup_buildings():
		if _has_completed_building(building_type):
			continue
		if _is_building_type_in_progress(building_type):
			continue
		missing.append(building_type)
	return missing


func _has_required_tier_1_setup_present() -> bool:
	for building_type: StringName in _get_required_tier_1_setup_buildings():
		if _has_completed_building(building_type):
			continue
		if _is_building_type_in_progress(building_type):
			continue
		return false
	return true


func _try_place_missing_tier_1_building(building_type: StringName) -> bool:
	if building_type == PLACEMENT_FARM:
		return _try_place_farm(false)

	if _has_completed_building(building_type) or _is_building_type_in_progress(building_type):
		return false

	if not _can_start_additional_construction(building_type):
		return false

	return _try_place_building(building_type)


func _log_tier_2_missing_buildings(missing: Array[StringName]) -> void:
	if missing.is_empty():
		if _tier_2_last_missing_building != &"":
			_tier_2_last_missing_building = &""
		return

	var first_missing: StringName = missing[0]
	if first_missing == _tier_2_last_missing_building:
		return

	_tier_2_last_missing_building = first_missing
	EnemyAIDebug.log_tier_2_missing_building(
		TechTree.get_building_type_display_name(first_missing)
	)


func _needs_farm_headroom_for_tier_2_upgrade() -> bool:
	if _is_any_enemy_command_center_upgrading():
		return _get_projected_free_population() <= FARM_HEADROOM_MID

	if TechTree.player_has_tier_2(ENEMY_TEAM_ID):
		return false

	# Keep spare population so workers/pikemen can still train during the 60s upgrade.
	return _get_projected_free_population() <= FARM_HEADROOM_MID + 2


func _try_replace_essential_tier_2_pikemen() -> void:
	var alive: int = _count_living_pikemen()
	var pending: int = _count_pending_pikemen()
	var total: int = alive + pending
	var min_pikemen: int = EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN
	if total >= min_pikemen:
		return

	# Do not drain the upgrade stockpile for replacements unless army is critically thin.
	if _can_afford_tier_2_upgrade() and total >= maxi(3, min_pikemen - 2):
		return

	if not EnemyResourceManager.has_food_supply(MILITARY_TRAIN_FOOD_COST):
		if _needs_farm():
			_try_place_farm(true)
		return

	for barracks: Barracks in _find_all_completed_enemy_barracks():
		if not is_instance_valid(barracks):
			continue

		while barracks.get_enemy_pending_unit_count() < Barracks.MAX_ENEMY_UNIT_QUEUE:
			alive = _count_living_pikemen()
			pending = _count_pending_pikemen()
			total = alive + pending
			if total >= min_pikemen:
				return

			if not EnemyResourceManager.can_afford_training(
				Barracks.SPEARMAN_TRAIN_GOLD_COST,
				MILITARY_TRAIN_FOOD_COST
			):
				return

			if not barracks.try_train_enemy_spearman():
				break


func _get_enemy_hero_level() -> int:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null:
		return 0
	return hero.level


func _is_tier_2_army_ready_for_upgrade() -> bool:
	if not _has_living_enemy_hero():
		return false

	if _count_living_pikemen() < EnemyStrategicDirector.EARLY_ARMY_MIN_PIKEMEN:
		return false

	if EnemyArmyCommand.is_rebuilding_army():
		return false

	if EnemyArmyCommand.get_strategic_state() == EnemyArmyCommand.StrategicState.RETREATING:
		return false

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.RETREATING:
		return false

	return true


func _is_tier_2_base_safe_for_upgrade() -> bool:
	if _director != null and _director.is_phase_interrupted():
		return false

	if EnemyArmyCommand.is_emergency_defense_active():
		return false

	if EnemyArmyCommand.is_defense_blocking_offense():
		return false

	var tree: SceneTree = get_tree()
	if EnemyArmyCommand.is_enemy_base_threatened(tree):
		return false

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or not is_instance_valid(command_center):
		return false

	var health_component: HealthComponent = (
		command_center.get_node_or_null("HealthComponent") as HealthComponent
	)
	if health_component != null:
		var max_health: float = float(health_component.max_health)
		if max_health > 0.0:
			var ratio: float = float(health_component.current_health) / max_health
			if ratio <= EnemyStrategicDirector.BASE_HEAVY_DAMAGE_RATIO:
				return false

	return true


func _can_afford_tier_2_upgrade() -> bool:
	return (
		EnemyResourceManager.gold >= TIER_2_GOLD_COST
		and EnemyResourceManager.wood >= TIER_2_WOOD_COST
	)


func _log_tier_2_block_reason(reason: String) -> void:
	if reason.is_empty() or reason == _tier_2_last_block_reason:
		return

	_tier_2_last_block_reason = reason
	match reason:
		"Base under attack":
			EnemyAIDebug.log_tier_2_upgrade("Upgrade delayed | Base under attack")
		"Hero below level 3":
			EnemyAIDebug.log_tier_2("Upgrade delayed | Hero below level 3")
		"Army recovering":
			EnemyAIDebug.log_tier_2("Upgrade delayed | Army recovering")
		"Missing Tier 1 buildings":
			pass
		_:
			EnemyAIDebug.log_tier_2(reason)


func _update_tier_2_town_hall_upgrade() -> bool:
	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or not is_instance_valid(command_center):
		_log_tier_2_block_reason("Command Center destroyed")
		_tier_2_upgrade_was_progressing = false
		_tier_2_upgrade_started_logged = false
		return true

	if command_center.command_center_tier >= 2 or TechTree.player_has_tier_2(ENEMY_TEAM_ID):
		if _tier_2_upgrade_was_progressing or _tier_2_upgrade_started_logged:
			EnemyAIDebug.log_tier_2_complete()
		_tier_2_upgrade_was_progressing = false
		_tier_2_last_block_reason = ""
		return false

	if command_center.is_upgrading_tier():
		if not _tier_2_upgrade_was_progressing:
			_tier_2_upgrade_was_progressing = true
			EnemyAIDebug.log_tier_2_upgrade("Upgrade progress started")
		_tier_2_last_block_reason = ""
		return true

	# Upgrade was interrupted (e.g. Command Center destroyed mid-upgrade and rebuilt).
	if _tier_2_upgrade_was_progressing:
		_tier_2_upgrade_was_progressing = false
		_tier_2_upgrade_started_logged = false
		EnemyAIDebug.log_tier_2_upgrade("Upgrade interrupted | Command Center lost progress")

	if _get_enemy_hero_level() < EnemyStrategicDirector.CREEP_HERO_LEVEL_REQUIREMENT:
		_log_tier_2_block_reason("Hero below level 3")
		return true

	if not _is_tier_2_army_ready_for_upgrade():
		_log_tier_2_block_reason("Army recovering")
		return true

	if not _is_tier_2_base_safe_for_upgrade():
		_log_tier_2_block_reason("Base under attack")
		return true

	if not _can_afford_tier_2_upgrade():
		if _tier_2_last_block_reason != "Saving resources":
			EnemyAIDebug.log_tier_2_saving(
				EnemyResourceManager.gold,
				TIER_2_GOLD_COST,
				EnemyResourceManager.wood,
				TIER_2_WOOD_COST
			)
		_tier_2_last_block_reason = "Saving resources"
		return true

	if _needs_farm_headroom_for_tier_2_upgrade():
		if _try_place_farm(false):
			_log_tier_2_block_reason("Building Farm for upgrade headroom")
			return true
		_log_tier_2_block_reason("Waiting for Farm headroom")
		return true

	if command_center.is_training_worker() or command_center.get_worker_queue_count() > 0:
		_log_tier_2_block_reason("Waiting for Command Center idle")
		return true

	if not command_center.can_try_enemy_upgrade_tier(2):
		# Affordable but otherwise blocked — keep gathering, do not spam requests.
		_log_tier_2_block_reason("Upgrade not ready")
		return true

	if command_center.try_upgrade_enemy_tier(2):
		_tier_2_upgrade_started_logged = true
		_tier_2_upgrade_was_progressing = true
		_tier_2_last_block_reason = ""
		EnemyAIDebug.log_tier_2_upgrade("Town Hall upgrade started")
		EnemyAIDebug.log_town_hall_upgrade(2)
		return true

	_log_tier_2_block_reason("Upgrade request failed")
	return true


func _try_place_opening_first_farm() -> bool:
	if _has_completed_building(PLACEMENT_FARM) or _is_building_type_in_progress(PLACEMENT_FARM):
		_log_opening_first_farm_builder_if_needed()
		return false

	if _count_enemy_workers() < OPENING_FIRST_FARM_WORKER_COUNT:
		return false

	if not EnemyResourceManager.can_afford(FARM_GOLD_COST, FARM_WOOD_COST):
		return false

	if not _try_place_building(PLACEMENT_FARM, false, false):
		return false

	_prefer_non_gold_opening_farm_builder()
	_log_opening_first_farm_builder_if_needed()
	return true


func _try_place_opening_core_building(building_type: StringName) -> bool:
	if _has_completed_building(building_type) or _is_building_type_in_progress(building_type):
		return false

	# Opening sequence stays serial for core tech buildings.
	if _has_unfinished_construction():
		return false

	return _try_place_building(building_type)


func _ensure_opening_first_farm_builder() -> void:
	var farm: Building = _find_opening_first_farm_under_construction()
	if farm == null:
		return

	# Only replace a missing builder (e.g. construction worker died).
	if _building_has_active_builder(farm):
		return

	_assign_opening_farm_builder(farm)


func _prefer_non_gold_opening_farm_builder() -> void:
	var farm: Building = _find_opening_first_farm_under_construction()
	if farm == null:
		return

	var active_builder: Worker = _find_builder_assigned_to(farm)
	if not NodeSafety.is_alive_node(active_builder):
		_assign_opening_farm_builder(farm)
		return

	if active_builder.get_assigned_gather_resource_id() != &"gold":
		return

	var preferred: Worker = _find_nearest_available_enemy_worker_matching(
		farm.global_position,
		true,
		true
	)
	if not NodeSafety.is_alive_node(preferred) or preferred == active_builder:
		return

	active_builder.prepare_for_enemy_economy_reassign(
		"opening farm prefers non-gold builder"
	)
	notify_enemy_worker_spawned(active_builder)
	preferred.command_build(farm)
	EnemyUnitMission.try_set_mission(
		preferred,
		EnemyUnitMission.Mission.BUILD,
		EnemyUnitMission.BUILD_COMMITMENT_SECONDS
	)


func _log_opening_first_farm_builder_if_needed() -> void:
	if _opening_first_farm_builder_logged:
		return

	var farm: Building = _find_opening_first_farm_under_construction()
	if farm == null:
		farm = _find_completed_opening_farm()
	if farm == null:
		return

	if not _building_has_active_builder(farm) and farm.building_state != Building.STATE_COMPLETED:
		return

	_opening_first_farm_builder_logged = true
	EnemyAIDebug.log_opening("Worker assigned to first Farm")


func _find_opening_first_farm_under_construction() -> Building:
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Farm or not _is_living_building(node as Building):
			continue

		var state: StringName = (node as Building).building_state
		if (
			state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			return node as Building

	return null


func _find_completed_opening_farm() -> Building:
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Farm or not _is_living_building(node as Building):
			continue
		if (node as Building).building_state == Building.STATE_COMPLETED:
			return node as Building

	return null


func _find_builder_assigned_to(building: Building) -> Worker:
	if not NodeSafety.is_alive_node(building):
		return null

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not NodeSafety.is_alive_node(worker):
			continue

		if worker.is_assigned_to_build(building):
			return worker

	return null


func _assign_opening_farm_builder(building: Building) -> void:
	if not NodeSafety.is_alive_node(building):
		return

	var worker: Worker = _find_opening_farm_builder(building.global_position)
	if not NodeSafety.is_alive_node(worker):
		return

	worker.command_build(building)
	EnemyUnitMission.try_set_mission(
		worker,
		EnemyUnitMission.Mission.BUILD,
		EnemyUnitMission.BUILD_COMMITMENT_SECONDS
	)


func _find_opening_farm_builder(near_position: Vector3) -> Worker:
	var preferred: Worker = _find_nearest_available_enemy_worker_matching(
		near_position,
		false,
		true
	)
	if NodeSafety.is_alive_node(preferred):
		return preferred

	preferred = _find_nearest_available_enemy_worker(near_position, false)
	if NodeSafety.is_alive_node(preferred):
		return preferred

	preferred = _find_nearest_available_enemy_worker_matching(
		near_position,
		true,
		true
	)
	if NodeSafety.is_alive_node(preferred):
		return preferred

	return _find_nearest_available_enemy_worker(near_position, true)


func _find_nearest_available_enemy_worker_matching(
	near_position: Vector3,
	allow_gather_interrupt: bool,
	prefer_non_gold: bool
) -> Worker:
	var closest_worker: Worker = null
	var closest_distance_squared: float = INF

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not NodeSafety.is_alive_node(worker):
			continue

		if WorkerAiUnstuck.blocks_external_commands(worker):
			continue

		if not worker.is_available_for_construction_assignment(allow_gather_interrupt):
			continue

		if prefer_non_gold and worker.get_assigned_gather_resource_id() == &"gold":
			continue

		var offset: Vector3 = worker.global_position - near_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_worker = worker

	return closest_worker


func _should_place_barracks() -> bool:
	if _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _is_building_type_in_progress(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < mini(MIN_WORKERS_BEFORE_MILITARY - 2, 4):
		return false

	return (
		EnemyResourceManager.can_afford(BARRACKS_GOLD_COST, BARRACKS_WOOD_COST)
		and _get_projected_free_population() > MILITARY_TRAIN_FOOD_COST + 1
	)


func _run_macro_emergency_checks() -> void:
	_sync_farm_reservation()
	_expire_tower_reservation_if_needed()

	_macro_emergency_timer += TICK_INTERVAL_SECONDS
	if _macro_emergency_timer < MACRO_EMERGENCY_INTERVAL_SECONDS:
		return

	_macro_emergency_timer = 0.0

	if _get_effective_worker_count() < _get_target_worker_count():
		var command_center: CommandCenter = _get_training_command_center()
		if command_center != null and not command_center.is_training_worker():
			if command_center.get_worker_queue_count() <= 0:
				_try_train_enemy_workers()

	if not EnemyResourceManager.has_food_supply(1):
		if _pop_capped_since_seconds < 0.0:
			_pop_capped_since_seconds = _get_match_elapsed_seconds()
		elif (
			_get_match_elapsed_seconds() - _pop_capped_since_seconds
			>= POP_CAP_EMERGENCY_SECONDS
		):
			_try_place_farm(true)
	else:
		_pop_capped_since_seconds = -1.0

	var gather_manager: EnemyGatherManager = _get_enemy_gather_manager()
	if gather_manager != null:
		gather_manager.request_gather_rebalance()

	## Throttled attack-path learning (also runs when considering towers).
	var primary_cc: CommandCenter = _resolve_primary_command_center()
	if primary_cc != null:
		EnemyAttackPathDefense.update_threat_paths(get_tree(), primary_cc.global_position)


func _update_enemy_hero_restoration() -> bool:
	if _has_living_enemy_hero():
		return false

	var hero_altar: HeroAltar = _find_enemy_hero_altar()
	if hero_altar != null and hero_altar.is_training_hero():
		return true

	if hero_altar == null and _should_build_hero_altar():
		_try_place_building(PLACEMENT_HERO_ALTAR)

	if hero_altar != null:
		## Retrain the same locked kit after death — never reroll.
		AIHeroMastery.ensure_enemy_hero_choice()
		if hero_altar.try_train_enemy_hero():
			EnemyAIDebug.log_training("Hero")

	return true


func _has_living_enemy_hero() -> bool:
	return EnemyArmyCommand.find_living_enemy_hero(get_tree()) != null


func _needs_barracks() -> bool:
	return (
		not _has_completed_building(PLACEMENT_BARRACKS)
		and not _is_building_type_in_progress(PLACEMENT_BARRACKS)
		and _count_living_military_units() > 0
	)


func _should_build_hero_altar() -> bool:
	if _has_completed_building(PLACEMENT_HERO_ALTAR):
		return false

	if _is_building_type_in_progress(PLACEMENT_HERO_ALTAR):
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < _get_target_worker_count():
		return false

	return true


func _should_build_expansion_barracks() -> bool:
	if _count_barracks() >= _get_max_barracks():
		return false

	if _count_barracks() == 0:
		return _count_enemy_workers() >= _get_min_workers_before_military()

	## Expansion only after the current barracks line is earning its keep.
	if not _can_expand_military_production(PLACEMENT_BARRACKS):
		return false

	if _has_abundant_resources():
		return EnemyResourceManager.can_afford(BARRACKS_GOLD_COST, BARRACKS_WOOD_COST)

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < mini(_get_target_worker_count(), MIN_WORKERS_BEFORE_MILITARY + 4):
		return false

	return EnemyResourceManager.can_afford(BARRACKS_GOLD_COST, BARRACKS_WOOD_COST)


func _should_build_blacksmith() -> bool:
	if not TechTree.can_build_blacksmith(ENEMY_TEAM_ID):
		return false

	if _has_completed_building(PLACEMENT_BLACKSMITH):
		return false

	if _is_building_type_in_progress(PLACEMENT_BLACKSMITH):
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if (
		_director != null
		and not _director.is_phase_at_least(EnemyStrategicDirector.StrategicPhase.CREEPING)
	):
		return false

	if _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY:
		return false

	return EnemyResourceManager.can_afford(BLACKSMITH_GOLD_COST, BLACKSMITH_WOOD_COST)


func _should_upgrade_command_center_tier() -> bool:
	if _is_any_enemy_command_center_upgrading():
		return false

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or not is_instance_valid(command_center):
		return false

	if TechTree.player_has_tier_3(ENEMY_TEAM_ID) or command_center.command_center_tier >= 3:
		return false

	if TechTree.player_has_tier_2(ENEMY_TEAM_ID) or command_center.command_center_tier >= 2:
		return _should_upgrade_command_center_to_tier_3(command_center)

	return _should_upgrade_command_center_to_tier_2(command_center)


func _should_upgrade_command_center_to_tier_2(command_center: CommandCenter) -> bool:
	if not is_instance_valid(command_center):
		return false

	if _director != null and not _director.should_prioritize_tier_upgrade(2):
		return false

	if _get_enemy_hero_level() < EnemyStrategicDirector.CREEP_HERO_LEVEL_REQUIREMENT:
		return false

	if not _has_required_tier_1_setup_present():
		return false

	if _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY:
		return false

	if not _is_tier_2_base_safe_for_upgrade():
		return false

	if not _is_tier_2_army_ready_for_upgrade():
		return false

	if not _has_stable_enemy_economy_for_tier_2_upgrade():
		return false

	return command_center.can_try_enemy_upgrade_tier(2)


func _should_upgrade_command_center_to_tier_3(command_center: CommandCenter) -> bool:
	if not is_instance_valid(command_center):
		return false

	if _director != null and not _director.should_prioritize_tier_upgrade(3):
		return false

	if command_center.command_center_tier < 2:
		return false

	if not _has_required_tier_2_buildings_for_tier_3():
		return false

	if _count_enemy_workers() < TIER_3_MIN_WORKERS:
		return false

	if _count_completed_farms() < TIER_3_MIN_FARMS:
		return false

	if _get_projected_free_population() < TIER_3_MIN_FREE_POPULATION:
		return false

	if _count_living_military_units() < TIER_3_MIN_ARMY:
		return false

	if not _has_stable_enemy_economy_for_tier_3_upgrade():
		return false

	return command_center.can_try_enemy_upgrade_tier(3)


func _has_required_tier_2_buildings_for_tier_3() -> bool:
	# Blacksmith is the Tier 2 gate required by TechTree for Tier 3 buildings.
	return (
		_has_completed_building(PLACEMENT_BLACKSMITH)
		or _is_building_type_in_progress(PLACEMENT_BLACKSMITH)
	)


func _has_stable_enemy_economy_for_tier_2_upgrade() -> bool:
	return (
		EnemyResourceManager.gold >= TIER_2_GOLD_COST + TIER_UPGRADE_STABLE_GOLD_BUFFER
		and EnemyResourceManager.wood >= TIER_2_WOOD_COST + TIER_UPGRADE_STABLE_WOOD_BUFFER
	)


func _has_stable_enemy_economy_for_tier_3_upgrade() -> bool:
	return (
		EnemyResourceManager.gold >= TIER_3_GOLD_COST + TIER_3_UPGRADE_STABLE_GOLD_BUFFER
		and EnemyResourceManager.wood >= TIER_3_WOOD_COST + TIER_3_UPGRADE_STABLE_WOOD_BUFFER
	)


func _try_upgrade_command_center_tier() -> void:
	if not _should_upgrade_command_center_tier():
		return

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or not is_instance_valid(command_center):
		return

	if _is_any_enemy_command_center_upgrading():
		return

	var target_max_tier: int = 3 if (
		TechTree.player_has_tier_2(ENEMY_TEAM_ID) or command_center.command_center_tier >= 2
	) else 2
	if command_center.try_upgrade_enemy_tier(target_max_tier):
		EnemyAIDebug.log_town_hall_upgrade(target_max_tier)


func _should_hold_workers_for_pending_tier_upgrade() -> bool:
	if _is_any_enemy_command_center_upgrading():
		return true

	if _should_hold_workers_for_imminent_tier_2_upgrade():
		return true

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or not is_instance_valid(command_center):
		return false

	if TechTree.player_has_tier_3(ENEMY_TEAM_ID) or command_center.command_center_tier >= 3:
		return false

	# Only hold workers once Tier 2 is done and Tier 3 is otherwise affordable/ready.
	if not (TechTree.player_has_tier_2(ENEMY_TEAM_ID) or command_center.command_center_tier >= 2):
		return false

	if command_center.command_center_tier < 2:
		return false

	if not _has_required_tier_2_buildings_for_tier_3():
		return false

	if _count_enemy_workers() < TIER_3_MIN_WORKERS:
		return false

	if _count_completed_farms() < TIER_3_MIN_FARMS:
		return false

	if _get_projected_free_population() < TIER_3_MIN_FREE_POPULATION:
		return false

	if _count_living_military_units() < TIER_3_MIN_ARMY:
		return false

	if not _has_stable_enemy_economy_for_tier_3_upgrade():
		return false

	return true


func _is_any_enemy_command_center_upgrading() -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is CommandCenter or not _is_living_building(node as Building):
			continue

		if (node as CommandCenter).is_upgrading_tier():
			return true

	return false


func _try_sustain_blacksmith_research() -> void:
	var blacksmith: Blacksmith = _find_completed_enemy_blacksmith()
	if blacksmith == null:
		return

	if blacksmith.is_researching():
		return

	for upgrade_id: StringName in UpgradeManager.BLACKSMITH_UPGRADE_ORDER:
		if UpgradeManager.is_enemy_max_level(upgrade_id):
			continue

		if not UpgradeManager.can_enemy_afford_upgrade(upgrade_id):
			return

		blacksmith.try_research_upgrade(upgrade_id)
		EnemyAIDebug.log_research("Blacksmith Upgrade")
		return


func _find_completed_enemy_blacksmith() -> Blacksmith:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Blacksmith or not _is_living_building(node as Building):
			continue

		var blacksmith: Blacksmith = node as Blacksmith
		if blacksmith.building_state == Building.STATE_COMPLETED:
			return blacksmith

	return null


func _try_sustain_stable_research() -> void:
	if _needs_farm():
		return

	var stable: Stable = _find_completed_enemy_stable()
	if stable == null or not is_instance_valid(stable):
		return

	if stable.is_researching():
		return

	for upgrade_id: StringName in UpgradeManager.STABLE_UPGRADE_ORDER:
		if UpgradeManager.is_enemy_max_level(upgrade_id):
			continue

		if not UpgradeManager.can_enemy_afford_upgrade(upgrade_id):
			return

		if not _can_afford_stable_research_without_starving_army(upgrade_id):
			return

		stable.try_research_upgrade(upgrade_id)
		return


func _can_afford_stable_research_without_starving_army(upgrade_id: StringName) -> bool:
	if _has_excess_resources():
		return true

	var cost: Dictionary = UpgradeManager.get_enemy_next_level_cost(upgrade_id)
	return EnemyResourceManager.can_afford(
		int(cost.gold) + Stable.LIGHT_CAVALRY_TRAIN_GOLD_COST,
		int(cost.wood)
	)


func _find_completed_enemy_stable() -> Stable:
	var stables: Array = _find_all_completed_enemy_stables()
	if stables.is_empty():
		return null

	return stables[0] as Stable


func _should_build_artillery_depot() -> bool:
	if not TechTree.can_build_artillery_depot(ENEMY_TEAM_ID):
		return false

	if _count_artillery_depots() >= _get_max_artillery_depots():
		return false

	if _is_building_type_in_progress(PLACEMENT_ARTILLERY_DEPOT):
		return false

	## Finish barracks then stables before expanding siege production.
	if _count_barracks() < AIDifficultyConfig.max_barracks():
		return false
	if _count_stables() < AIDifficultyConfig.max_stables():
		return false

	if (
		_director != null
		and not _director.is_phase_at_least(EnemyStrategicDirector.StrategicPhase.LATE_GAME)
	):
		return false

	if not (
		_has_completed_building(PLACEMENT_BLACKSMITH)
		or _is_building_type_in_progress(PLACEMENT_BLACKSMITH)
	):
		return false

	if _count_artillery_depots() > 0 and not _can_expand_military_production(PLACEMENT_ARTILLERY_DEPOT):
		return false

	return EnemyResourceManager.can_afford(ARTILLERY_DEPOT_GOLD_COST, ARTILLERY_DEPOT_WOOD_COST)


func _should_build_academy() -> bool:
	if not TechTree.can_build_academy(ENEMY_TEAM_ID):
		return false

	if _has_completed_building(PLACEMENT_ACADEMY):
		return false

	if _is_building_type_in_progress(PLACEMENT_ACADEMY):
		return false

	if (
		_director != null
		and not _director.is_phase_at_least(EnemyStrategicDirector.StrategicPhase.TIER_3)
	):
		return false

	if not (
		_has_completed_building(PLACEMENT_BLACKSMITH)
		or _is_building_type_in_progress(PLACEMENT_BLACKSMITH)
	):
		return false

	return EnemyResourceManager.can_afford(ACADEMY_GOLD_COST, ACADEMY_WOOD_COST)


func _try_sustain_academy_research() -> void:
	if _academy_research_complete:
		return

	if _are_enemy_academy_upgrades_complete():
		_academy_research_complete = true
		return

	if _academy_research_fail_cooldown_ticks > 0:
		_academy_research_fail_cooldown_ticks -= 1
		return

	if _needs_farm():
		return

	var academy: Academy = _find_completed_enemy_academy()
	if academy == null or not is_instance_valid(academy):
		return

	if academy.is_researching():
		return

	for upgrade_id: StringName in UpgradeManager.ACADEMY_UPGRADE_ORDER:
		if UpgradeManager.is_enemy_academy_max_level(upgrade_id):
			continue

		if not UpgradeManager.can_enemy_afford_academy_upgrade(upgrade_id):
			return

		if not _can_afford_academy_research_without_starving_army(upgrade_id):
			return

		if academy.try_research_upgrade(upgrade_id):
			EnemyAIDebug.log_research("Academy Upgrade")
			return

		_academy_research_fail_cooldown_ticks = ACADEMY_RESEARCH_FAIL_COOLDOWN_TICKS
		return


func _are_enemy_academy_upgrades_complete() -> bool:
	for upgrade_id: StringName in UpgradeManager.ACADEMY_UPGRADE_ORDER:
		if not UpgradeManager.is_enemy_academy_max_level(upgrade_id):
			return false

	return true


func _can_afford_academy_research_without_starving_army(upgrade_id: StringName) -> bool:
	if _has_excess_resources():
		return true

	var cost: Dictionary = UpgradeManager.get_enemy_academy_upgrade_cost(upgrade_id)
	return EnemyResourceManager.can_afford(
		int(cost.gold) + ACADEMY_RESEARCH_ARMY_GOLD_BUFFER,
		int(cost.wood) + FARM_WOOD_COST
	)


func _find_completed_enemy_academy() -> Academy:
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Academy or not _is_living_building(node as Building):
			continue

		var academy: Academy = node as Academy
		if academy.building_state == Building.STATE_COMPLETED:
			return academy

	return null


func _should_build_shop() -> bool:
	if _has_completed_building(PLACEMENT_SHOP):
		return false

	if _is_building_type_in_progress(PLACEMENT_SHOP):
		return false

	if (
		_director != null
		and not _director.is_phase_at_least(EnemyStrategicDirector.StrategicPhase.CREEPING)
	):
		return false

	if not _has_living_enemy_hero():
		return false

	if not _has_stable_enemy_economy_for_shop():
		return false

	return EnemyResourceManager.can_afford(SHOP_GOLD_COST, SHOP_WOOD_COST)


func _has_stable_enemy_economy_for_shop() -> bool:
	return (
		_count_enemy_workers() >= MIN_WORKERS_BEFORE_MILITARY
		and EnemyResourceManager.gold >= SHOP_GOLD_COST + SHOP_STABLE_GOLD_BUFFER
		and EnemyResourceManager.wood >= SHOP_WOOD_COST
	)


func _try_sustain_shop_purchases() -> void:
	if _shop_purchase_cooldown_ticks > 0:
		_shop_purchase_cooldown_ticks -= 1
		return

	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		return

	var shop: Shop = _find_completed_enemy_shop()
	if shop == null:
		return

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null:
		return

	if not HeroItemService.is_hero_in_shop_range(shop, hero):
		# Combine does not require shop range — finish craftable recipes while full.
		if hero.is_inventory_full() and _try_combine_preferred_recipes(hero):
			_shop_purchase_cooldown_ticks = SHOP_PURCHASE_COOLDOWN_TICKS
			return
		if hero.is_inventory_full():
			if EnemyUnitMission.get_unit_mission(hero) == EnemyUnitMission.Mission.SHOP:
				EnemyUnitMission.sync_hero_to_main_army(hero, true)
			return
		if _should_send_hero_to_shop(hero):
			_command_hero_to_shop(hero, shop)
		return

	if _try_buy_next_useful_shop_item(shop):
		_shop_purchase_cooldown_ticks = SHOP_PURCHASE_COOLDOWN_TICKS
		return

	if EnemyUnitMission.get_unit_mission(hero) == EnemyUnitMission.Mission.SHOP:
		EnemyUnitMission.sync_hero_to_main_army(hero, true)


func _try_buy_next_useful_shop_item(shop: Shop) -> bool:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null:
		return false

	var kit_id: StringName = hero.get_hero_kit_id()
	var is_behind: bool = _is_hero_item_shopping_behind(hero)
	var is_ahead: bool = _is_hero_item_shopping_ahead(hero)
	var goals: Array[StringName] = AIItemPreferences.get_ordered_goals(kit_id, is_behind, is_ahead)

	if _try_combine_preferred_recipes(hero, goals):
		return true

	# Purchasing a completed preferred item auto-combines when all components are owned.
	for goal_id: StringName in goals:
		if _hero_already_owns_item(hero, goal_id) or AIItemPreferences.should_skip_goal(hero, goal_id):
			continue
		if not HeroItemService.can_purchase_from_shop(shop, goal_id):
			continue
		var goal_def: HeroItemDefinition = HeroItemCatalog.get_definition(goal_id)
		if goal_def == null or not goal_def.has_recipe():
			continue
		if not HeroItemService.can_combine_item(hero, goal_id):
			continue
		if _should_skip_unique_boots_purchase(hero, goal_id):
			continue
		return shop.try_purchase_item(goal_id)

	var focus_goal: StringName = _get_highest_unfinished_goal(hero, goals)
	if focus_goal == &"":
		return false

	var next_component: StringName = _find_next_missing_component(hero, focus_goal)
	if next_component == &"":
		return false
	if _should_skip_unique_boots_purchase(hero, next_component):
		return false
	if hero.is_inventory_full():
		return false
	if not HeroItemService.can_purchase_from_shop(shop, next_component):
		return false

	return shop.try_purchase_item(next_component)


func _try_combine_preferred_recipes(
	hero: Hero,
	goals: Array[StringName] = []
) -> bool:
	if hero == null:
		return false

	var kit_id: StringName = hero.get_hero_kit_id()
	if goals.is_empty():
		goals = AIItemPreferences.get_ordered_goals(
			kit_id,
			_is_hero_item_shopping_behind(hero),
			_is_hero_item_shopping_ahead(hero)
		)

	var recipe_ids: Array[StringName] = _collect_preferred_recipe_ids(hero, goals)
	recipe_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var def_a: HeroItemDefinition = HeroItemCatalog.get_definition(a)
		var def_b: HeroItemDefinition = HeroItemCatalog.get_definition(b)
		var tier_a: int = int(def_a.tier) if def_a != null else 0
		var tier_b: int = int(def_b.tier) if def_b != null else 0
		return tier_a > tier_b
	)

	for item_id: StringName in recipe_ids:
		if _should_skip_unique_boots_purchase(hero, item_id):
			continue
		if HeroItemService.can_combine_item(hero, item_id):
			if HeroItemService.try_combine_item(hero, item_id):
				return true

	return false


func _collect_preferred_recipe_ids(
	hero: Hero,
	goals: Array[StringName]
) -> Array[StringName]:
	var recipe_ids: Array[StringName] = []
	for goal_id: StringName in goals:
		if _hero_already_owns_item(hero, goal_id) or AIItemPreferences.should_skip_goal(hero, goal_id):
			continue
		_append_recipe_tree_ids(goal_id, recipe_ids)
	return recipe_ids


func _append_recipe_tree_ids(item_id: StringName, out_ids: Array[StringName]) -> void:
	var definition: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if definition == null or not definition.has_recipe():
		return

	if not out_ids.has(item_id):
		out_ids.append(item_id)

	for component_id: StringName in definition.recipe_component_ids:
		_append_recipe_tree_ids(component_id, out_ids)


func _get_highest_unfinished_goal(hero: Hero, goals: Array[StringName]) -> StringName:
	for goal_id: StringName in goals:
		if _hero_already_owns_item(hero, goal_id):
			continue
		if AIItemPreferences.should_skip_goal(hero, goal_id):
			continue
		return goal_id
	return &""


func _find_next_missing_component(hero: Hero, item_id: StringName) -> StringName:
	var owned_counts: Dictionary = _collect_owned_item_counts(hero)
	var missing: Array[StringName] = []
	_collect_missing_components(item_id, owned_counts, missing)
	if missing.is_empty():
		return &""
	return missing[0]


func _collect_owned_item_counts(hero: Hero) -> Dictionary:
	var counts: Dictionary = {}
	if hero == null:
		return counts

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if not item is HeroItemDefinition:
			continue
		var owned_id: StringName = (item as HeroItemDefinition).item_id
		counts[owned_id] = int(counts.get(owned_id, 0)) + 1
	return counts


func _collect_missing_components(
	item_id: StringName,
	owned_counts: Dictionary,
	out_missing: Array[StringName]
) -> void:
	if int(owned_counts.get(item_id, 0)) > 0:
		owned_counts[item_id] = int(owned_counts[item_id]) - 1
		return

	var definition: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if definition == null:
		return

	if not definition.has_recipe():
		out_missing.append(item_id)
		return

	for component_id: StringName in definition.recipe_component_ids:
		_collect_missing_components(component_id, owned_counts, out_missing)


func _should_skip_unique_boots_purchase(hero: Hero, item_id: StringName) -> bool:
	if not AIItemPreferences.is_unique_move_speed_item(item_id):
		return false
	if not _hero_owns_any_unique_move_speed(hero):
		return false

	# Allow upgrading an owned boots item into a higher unique-MS recipe.
	var definition: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if definition == null or not definition.has_recipe():
		return true

	for component_id: StringName in definition.recipe_component_ids:
		var component: HeroItemDefinition = HeroItemCatalog.get_definition(component_id)
		if component != null and component.is_unique_move_speed and _hero_already_owns_item(hero, component_id):
			return false

	return true


func _hero_owns_any_unique_move_speed(hero: Hero) -> bool:
	if hero == null:
		return false

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition and (item as HeroItemDefinition).is_unique_move_speed:
			return true
	return false


func _is_hero_item_shopping_behind(hero: Hero) -> bool:
	if hero == null:
		return false

	if EnemyArmyCommand.get_health_ratio(hero) <= AIItemPreferences.BEHIND_HERO_HP_RATIO:
		return true

	var strength_ratio: float = _get_army_strength_ratio_vs_player()
	return strength_ratio >= 0.0 and strength_ratio < AIItemPreferences.BEHIND_ARMY_STRENGTH_RATIO


func _is_hero_item_shopping_ahead(hero: Hero) -> bool:
	if hero == null or _is_hero_item_shopping_behind(hero):
		return false

	var strength_ratio: float = _get_army_strength_ratio_vs_player()
	return strength_ratio >= AIItemPreferences.AHEAD_ARMY_STRENGTH_RATIO


func _get_army_strength_ratio_vs_player() -> float:
	var tree: SceneTree = get_tree()
	var ai_power: int = EnemyArmyCommand.estimate_military_power(
		EnemyArmyCommand.collect_living_combat_units(tree)
	)
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	var player_power: int = EnemyArmyCommand.estimate_known_player_army_strength(tree, rally_position)
	if player_power <= 0:
		return 1.0
	return float(ai_power) / float(maxi(player_power, 1))


func _hero_already_owns_item(hero: Hero, item_id: StringName) -> bool:
	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition and (item as HeroItemDefinition).item_id == item_id:
			return true

	return false


func _should_send_hero_to_shop(hero: Hero) -> bool:
	if EnemyArmyCommand.is_attack_wave_controlling_hero():
		return false

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if (
		army_mode == EnemyArmyCommand.ArmyMode.ATTACKING
		or army_mode == EnemyArmyCommand.ArmyMode.ASSEMBLING
		or army_mode == EnemyArmyCommand.ArmyMode.REGROUPING
		or army_mode == EnemyArmyCommand.ArmyMode.DEFENDING
		or army_mode == EnemyArmyCommand.ArmyMode.INTERCEPTING
		or army_mode == EnemyArmyCommand.ArmyMode.RETREATING
		or army_mode == EnemyArmyCommand.ArmyMode.CREEPING
	):
		return false

	var main_mission: EnemyUnitMission.Mission = EnemyUnitMission.get_main_army_mission()
	if main_mission in [
		EnemyUnitMission.Mission.ATTACK,
		EnemyUnitMission.Mission.DEFEND,
		EnemyUnitMission.Mission.RETREAT,
		EnemyUnitMission.Mission.CREEP,
	]:
		return false

	if (
		EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree()).size()
		< EnemyArmyCommand.ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS
	):
		return false

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var offset: Vector3 = hero.global_position - rally_position
	offset.y = 0.0
	if offset.length() > SHOP_HERO_RALLY_DISTANCE:
		return false

	return EnemyArmyCommand.get_health_ratio(hero) >= EnemyArmyCommand.HERO_RETREAT_HP_RATIO


func _command_hero_to_shop(hero: Hero, shop: Shop) -> void:
	if not EnemyUnitMission.try_set_mission(
		hero,
		EnemyUnitMission.Mission.SHOP,
		EnemyUnitMission.SHOP_COMMITMENT_SECONDS
	):
		return

	var target: Vector3 = shop.global_position
	target.y = hero.global_position.y
	if not EnemyUnitMission.should_reissue_move_order(
		hero,
		target,
		EnemyUnitMission.Mission.SHOP
	):
		return

	hero.set_movement_target(target)
	EnemyUnitMission.record_move_order(hero, target, EnemyUnitMission.Mission.SHOP)


func _find_completed_enemy_shop() -> Shop:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Shop or not _is_living_building(node as Building):
			continue

		var shop: Shop = node as Shop
		if shop.building_state == Building.STATE_COMPLETED:
			return shop

	return null


func _needs_farm() -> bool:
	if _count_completed_farms() + _count_farms_under_construction() >= MAX_FARMS:
		return false

	return _get_projected_free_population() <= _get_farm_headroom_threshold()


func _get_projected_free_population() -> int:
	var projected_capacity: int = (
		EnemyResourceManager.food_max
		+ _count_farms_under_construction() * Farm.FOOD_CAP_BONUS
	)
	return projected_capacity - EnemyResourceManager.food_current


func _get_farm_headroom_threshold() -> int:
	if _director == null:
		var elapsed_seconds: float = _get_match_elapsed_seconds()
		if elapsed_seconds < WORKER_PHASE_MID_SECONDS:
			return FARM_HEADROOM_EARLY
		if elapsed_seconds < WORKER_PHASE_ENDGAME_SECONDS:
			return FARM_HEADROOM_MID
		return FARM_HEADROOM_LATE

	match _director.get_strategic_phase():
		EnemyStrategicDirector.StrategicPhase.OPENING, \
		EnemyStrategicDirector.StrategicPhase.EARLY_ARMY, \
		EnemyStrategicDirector.StrategicPhase.CREEPING:
			return FARM_HEADROOM_EARLY
		EnemyStrategicDirector.StrategicPhase.TIER_2, \
		EnemyStrategicDirector.StrategicPhase.EXPANSION, \
		EnemyStrategicDirector.StrategicPhase.MID_GAME:
			return FARM_HEADROOM_MID
		_:
			return FARM_HEADROOM_LATE


func _get_match_elapsed_seconds() -> float:
	if _director != null:
		return _director.get_match_elapsed_seconds()
	return float(Time.get_ticks_msec()) / 1000.0


func _count_player_workers() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"workers"):
		if node is Worker and is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


func _try_place_farm(emergency: bool) -> bool:
	if _is_farm_placement_on_fail_cooldown():
		return false

	_ensure_farm_reservation()
	# Spend against total stockpile while the farm hold is active (avoid double-count).
	if not EnemyResourceManager.can_afford(FARM_GOLD_COST, FARM_WOOD_COST, false):
		return false

	var placed: bool = _try_place_building(PLACEMENT_FARM, false, true)
	if placed:
		# try_spend already cleared the reserved amounts from the stockpile hold.
		_farm_reservation_active = false
		_farm_reservation_msec = 0
		_farm_placement_fail_cooldown_until = -1.0
	else:
		_begin_farm_placement_fail_cooldown()
		# Failed site must not permanently starve spending.
		if not _needs_farm() and EnemyResourceManager.has_food_supply(3):
			_release_farm_reservation()
	return placed


func _ensure_farm_reservation() -> void:
	_expire_farm_reservation_if_needed()
	if _farm_reservation_active:
		return

	EnemyResourceManager.reserve_resources(FARM_GOLD_COST, FARM_WOOD_COST)
	_farm_reservation_active = true
	_farm_reservation_msec = Time.get_ticks_msec()


func _release_farm_reservation() -> void:
	if not _farm_reservation_active:
		return

	EnemyResourceManager.release_reservation(FARM_GOLD_COST, FARM_WOOD_COST)
	_farm_reservation_active = false
	_farm_reservation_msec = 0


func _expire_farm_reservation_if_needed() -> void:
	if not _farm_reservation_active:
		return

	if (
		Time.get_ticks_msec() - _farm_reservation_msec
		>= FARM_RESOURCE_RESERVATION_TTL_MSEC
	):
		_release_farm_reservation()


func _sync_farm_reservation() -> void:
	_expire_farm_reservation_if_needed()
	if _needs_farm() or not EnemyResourceManager.has_food_supply(3):
		_ensure_farm_reservation()
	else:
		_release_farm_reservation()


func _begin_farm_placement_fail_cooldown() -> void:
	_farm_placement_fail_cooldown_until = (
		_get_match_elapsed_seconds() + FARM_PLACEMENT_FAIL_COOLDOWN_SECONDS
	)


func _is_farm_placement_on_fail_cooldown() -> bool:
	return _get_match_elapsed_seconds() < _farm_placement_fail_cooldown_until


func _should_build_tower(emergency_only: bool = false) -> bool:
	_sync_tower_reservation()
	_prune_tower_lane_bindings()

	if _is_tower_placement_on_fail_cooldown():
		return false

	if _is_building_type_in_progress(PLACEMENT_TOWER):
		return false

	if not _can_start_additional_construction(PLACEMENT_TOWER):
		return false

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null:
		return false

	var need: Dictionary = _evaluate_tower_build_need(emergency_only)
	if not VariantUtils.to_bool(need.get("should_build", false)):
		return false

	if not _can_afford_tower_without_starving_core():
		return false

	return true


func _try_place_tower(emergency_only: bool = false) -> bool:
	if _is_tower_placement_on_fail_cooldown():
		return false

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null:
		return false

	var need: Dictionary = _evaluate_tower_build_need(emergency_only)
	if not VariantUtils.to_bool(need.get("should_build", false)):
		return false

	_ensure_tower_reservation()
	var respect_reservations: bool = not _tower_reservation_active
	if not EnemyResourceManager.can_afford(TOWER_GOLD_COST, TOWER_WOOD_COST, respect_reservations):
		return false

	var parent: Node = get_node_or_null(buildings_parent_path)
	if parent == null or not parent.is_inside_tree():
		return false

	var anchor_position: Vector3 = command_center.global_position
	## Prefer expansion CC when fortifying an exposed expansion lane.
	if need.get("lane", &"") == EnemyAttackPathDefense.LANE_EXPANSION:
		var expansion_cc: CommandCenter = _find_expansion_command_center()
		if expansion_cc != null:
			anchor_position = expansion_cc.global_position

	var existing_buildings: Array[Node3D] = EnemyBuildPlacement.collect_nearby_buildings(
		anchor_position,
		parent
	)
	var lane: StringName = need.get("lane", EnemyAttackPathDefense.LANE_CENTER)
	var placement: Dictionary = EnemyAttackPathDefense.find_tower_position(
		anchor_position,
		lane,
		existing_buildings,
		parent,
		_get_navigation_map()
	)
	var position: Vector3 = placement.get("position", Vector3.INF)
	if not position.is_finite():
		var reject: StringName = placement.get("reject", &"blocked")
		_begin_tower_placement_fail_cooldown()
		_release_tower_reservation()
		if OS.is_debug_build() and EnemyAIDebug.is_enabled():
			EnemyAIDebug.log_event(
				"AI tower candidate rejected: %s" % String(reject).replace("_", " ")
			)
		return false

	if not _can_start_additional_construction(PLACEMENT_TOWER):
		_release_tower_reservation()
		return false

	var footprint: Vector2 = EnemyBuildPlacement.get_footprint(PLACEMENT_TOWER)
	var footprint_reservation_id: int = ConstructionReservations.reserve_footprint(
		position,
		footprint,
		self,
		ConstructionReservations.FOOTPRINT_RESERVATION_TTL_MSEC
	)

	if not EnemyResourceManager.try_spend(TOWER_GOLD_COST, TOWER_WOOD_COST, respect_reservations):
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	var building: Building = _instantiate_building(PLACEMENT_TOWER)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(TOWER_GOLD_COST)
		EnemyResourceManager.add_wood(TOWER_WOOD_COST)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		_release_tower_reservation()
		EnemyAttackPathDefense.remember_failed_site(position)
		return false

	_tag_enemy_building(building)
	_add_health_component_if_needed(building, PLACEMENT_TOWER)
	parent.add_child(building)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(TOWER_GOLD_COST)
		EnemyResourceManager.add_wood(TOWER_WOOD_COST)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		_release_tower_reservation()
		EnemyAttackPathDefense.remember_failed_site(position)
		return false

	building.global_position = position
	building.set_construction_cost(TOWER_GOLD_COST, TOWER_WOOD_COST, true)
	building.start_under_construction()
	building.setup_construction(
		BuildingStats.get_construction_seconds(PLACEMENT_TOWER, 1)
		/ UpgradeManager.get_construction_speed_multiplier(true)
	)
	ConstructionReservations.release_footprint(footprint_reservation_id)
	_bind_tower_lane(building, lane)
	_connect_tower_destroyed_signal(building)
	_assign_nearest_builder(building)
	## Optional second nearby builder for faster fortification under pressure.
	if need.get("reason", &"") in [
		EnemyAttackPathDefense.REASON_EMERGENCY,
		EnemyAttackPathDefense.REASON_REPEATED_ATTACK,
	]:
		_assign_nearest_builder(building)

	_tower_reservation_active = false
	_tower_reservation_msec = 0
	_tower_placement_fail_cooldown_until = -1.0
	EnemyBuildPlacement.clear_tower_lane_preference()
	_log_building_started(PLACEMENT_TOWER)
	_log_tower_placement(need, placement)
	return true


func _evaluate_tower_build_need(emergency_only: bool) -> Dictionary:
	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null:
		return {"should_build": false}

	var parent: Node = get_node_or_null(buildings_parent_path)
	var existing: Array[Node3D] = []
	if parent != null:
		existing = EnemyBuildPlacement.collect_nearby_buildings(
			command_center.global_position,
			parent
		)

	var coverage_data: Dictionary = EnemyAttackPathDefense.compute_lane_coverage(
		command_center.global_position,
		existing
	)
	var phase_name: String = "MID_GAME"
	if _director != null:
		phase_name = EnemyStrategicDirector.strategic_phase_to_string(_director.get_strategic_phase())
	var tower_count: int = _count_living_towers()
	var army_count: int = _count_living_military_units()
	var threat: Dictionary = EnemyArmyCommand.evaluate_defense_threat(get_tree())
	var emergency_threat: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(get_tree())
	var is_emergency: bool = VariantUtils.to_bool(emergency_threat.get("threatened", false)) or (
		VariantUtils.to_bool(threat.get("threatened", false))
		and threat.get("reason", &"") in [&"town_center", &"base", &"economy"]
	)
	var early_aggression: bool = (
		VariantUtils.to_bool(threat.get("threatened", false))
		and phase_name in ["OPENING", "EARLY_ARMY", "CREEPING"]
	)
	var has_expansion: bool = _count_living_command_centers() >= 2
	var expansion_exposed: bool = has_expansion and _is_expansion_route_exposed()
	var opening_incomplete: bool = (
		not _has_completed_building(PLACEMENT_BARRACKS)
		or not _has_completed_building(PLACEMENT_HERO_ALTAR)
		or not _has_living_enemy_hero()
	)
	var weak_army_expanding: bool = (
		(
			_director != null
			and _director.is_phase_at_least(EnemyStrategicDirector.StrategicPhase.EXPANSION)
		)
		and army_count < MIN_ARMY_BEFORE_OPTIONAL_TOWERS + 2
	)

	var context: Dictionary = {
		"tower_count": tower_count,
		"tower_cap": EnemyAttackPathDefense.get_tower_cap_for_phase_name(phase_name),
		"food_blocked": _needs_farm() or not EnemyResourceManager.has_food_supply(1),
		"missing_workers": _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY,
		"core_army_starved": (
			not _has_living_enemy_hero()
			or (
				army_count < MIN_ARMY_BEFORE_OPTIONAL_TOWERS
				and not is_emergency
				and not early_aggression
			)
		),
		"opening_core_incomplete": opening_incomplete,
		"emergency": is_emergency,
		"early_aggression": early_aggression,
		"weak_army_expanding": weak_army_expanding,
		"has_production": _has_completed_building(PLACEMENT_BARRACKS),
		"economy_ready": (
			_count_enemy_workers() >= MIN_WORKERS_BEFORE_MILITARY
			and _count_completed_farms() >= 1
			and EnemyResourceManager.gold >= TOWER_GOLD_COST + TOWER_ARMY_GOLD_BUFFER
		),
		"expansion_exposed": expansion_exposed,
		"has_expansion": has_expansion,
		"workers_exposed": VariantUtils.to_bool(threat.get("reason", &"") == &"workers") or early_aggression,
		"lane_coverage": coverage_data.get("coverage", {}),
		"towers_per_lane": coverage_data.get("towers_per_lane", {}),
	}

	var need: Dictionary = EnemyAttackPathDefense.evaluate_build_need(
		get_tree(),
		command_center.global_position,
		context
	)
	if emergency_only and not VariantUtils.to_bool(need.get("should_build", false)):
		return need
	if emergency_only and not (
		need.get("reason", &"") in [
			EnemyAttackPathDefense.REASON_EMERGENCY,
			EnemyAttackPathDefense.REASON_EARLY_RUSH,
			EnemyAttackPathDefense.REASON_REPEATED_ATTACK,
			EnemyAttackPathDefense.REASON_WEAK_EXPANSION,
		]
	):
		return {"should_build": false}

	return need


func _can_afford_tower_without_starving_core() -> bool:
	if _has_excess_resources():
		return EnemyResourceManager.can_afford(TOWER_GOLD_COST, TOWER_WOOD_COST, not _tower_reservation_active)

	var gold_buffer: int = TOWER_ARMY_GOLD_BUFFER
	if not _has_living_enemy_hero():
		gold_buffer = maxi(gold_buffer, TOWER_HERO_GOLD_BUFFER)

	## Emergency defense may spend closer to the raw tower cost.
	var threat: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(get_tree())
	if VariantUtils.to_bool(threat.get("threatened", false)):
		gold_buffer = UnitStats.SWORDSMAN_GOLD_COST

	return EnemyResourceManager.can_afford(
		TOWER_GOLD_COST + gold_buffer,
		TOWER_WOOD_COST + (FARM_WOOD_COST if _needs_farm() else 0),
		not _tower_reservation_active
	)


func _count_living_towers() -> int:
	var count: int = 0
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Tower or not _is_living_building(node as Building):
			continue
		count += 1
	return count


func _find_expansion_command_center() -> CommandCenter:
	var primary: CommandCenter = _resolve_primary_command_center()
	if primary == null:
		return null
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is CommandCenter or not _is_living_building(node as Building):
			continue
		var cc: CommandCenter = node as CommandCenter
		if cc == primary:
			continue
		return cc
	return null


func _is_expansion_route_exposed() -> bool:
	var primary: CommandCenter = _resolve_primary_command_center()
	var expansion: CommandCenter = _find_expansion_command_center()
	if primary == null or expansion == null:
		return false

	var parent: Node = get_node_or_null(buildings_parent_path)
	if parent == null:
		return true

	var buildings: Array[Node3D] = EnemyBuildPlacement.collect_nearby_buildings(
		expansion.global_position,
		parent
	)
	for building: Node3D in buildings:
		if building is Tower and is_instance_valid(building):
			var mid: Vector3 = (primary.global_position + expansion.global_position) * 0.5
			var to_mid: Vector3 = building.global_position - mid
			to_mid.y = 0.0
			if to_mid.length() <= BuildingStats.TOWER_ATTACK_RANGE + 4.0:
				return false
	return true


func _ensure_tower_reservation() -> void:
	_expire_tower_reservation_if_needed()
	if _tower_reservation_active:
		return
	EnemyResourceManager.reserve_resources(TOWER_GOLD_COST, TOWER_WOOD_COST)
	_tower_reservation_active = true
	_tower_reservation_msec = Time.get_ticks_msec()


func _release_tower_reservation() -> void:
	if not _tower_reservation_active:
		return
	EnemyResourceManager.release_reservation(TOWER_GOLD_COST, TOWER_WOOD_COST)
	_tower_reservation_active = false
	_tower_reservation_msec = 0


func _expire_tower_reservation_if_needed() -> void:
	if not _tower_reservation_active:
		return
	if Time.get_ticks_msec() - _tower_reservation_msec >= TOWER_RESOURCE_RESERVATION_TTL_MSEC:
		_release_tower_reservation()


func _sync_tower_reservation() -> void:
	_expire_tower_reservation_if_needed()
	if not _is_building_type_in_progress(PLACEMENT_TOWER) and not _tower_reservation_active:
		return
	if not _is_building_type_in_progress(PLACEMENT_TOWER) and _tower_reservation_active:
		## Drop stale holds when no tower is under construction and TTL already handled.
		if Time.get_ticks_msec() - _tower_reservation_msec >= TOWER_RESOURCE_RESERVATION_TTL_MSEC:
			_release_tower_reservation()


func _begin_tower_placement_fail_cooldown() -> void:
	_tower_placement_fail_cooldown_until = (
		_get_match_elapsed_seconds() + TOWER_PLACEMENT_FAIL_COOLDOWN_SECONDS
	)


func _is_tower_placement_on_fail_cooldown() -> bool:
	return _get_match_elapsed_seconds() < _tower_placement_fail_cooldown_until


func _bind_tower_lane(building: Building, lane: StringName) -> void:
	if not NodeSafety.is_alive_node(building):
		return
	_tower_lane_bindings[building.get_instance_id()] = lane


func _prune_tower_lane_bindings() -> void:
	var stale: Array[int] = []
	for instance_id: Variant in _tower_lane_bindings.keys():
		var node: Object = instance_from_id(int(instance_id))
		if node == null or not is_instance_valid(node):
			stale.append(int(instance_id))
	for instance_id: int in stale:
		_tower_lane_bindings.erase(instance_id)


func _connect_tower_destroyed_signal(building: Building) -> void:
	if not NodeSafety.is_alive_node(building):
		return
	var health: Node = building.get_node_or_null("HealthComponent")
	if health == null:
		return
	if health.has_signal("health_depleted") and not health.health_depleted.is_connected(
		_on_enemy_tower_destroyed.bind(building)
	):
		health.health_depleted.connect(_on_enemy_tower_destroyed.bind(building), CONNECT_ONE_SHOT)


func _on_enemy_tower_destroyed(building: Building) -> void:
	if building == null:
		return
	var lane: StringName = _tower_lane_bindings.get(building.get_instance_id(), &"")
	_tower_lane_bindings.erase(building.get_instance_id())
	var pos: Vector3 = building.global_position if is_instance_valid(building) else Vector3.INF
	EnemyAttackPathDefense.notify_tower_destroyed(pos, lane)


func _log_tower_placement(need: Dictionary, placement: Dictionary) -> void:
	if not OS.is_debug_build() or not EnemyAIDebug.is_enabled():
		return
	var lane: StringName = need.get("lane", placement.get("lane", &"center"))
	var reason: StringName = need.get("reason", &"")
	var score: float = float(placement.get("score", need.get("score", 0.0)))
	EnemyAIDebug.log_event("AI tower lane selected: %s" % String(lane))
	EnemyAIDebug.log_event(
		"AI tower reason: %s" % EnemyAttackPathDefense.reason_to_debug_text(reason)
	)
	EnemyAIDebug.log_event("AI tower placed at lane score: %.2f" % score)


func _should_build_expansion_command_center() -> bool:
	_sync_expansion_order_state()

	if _count_living_command_centers() >= 2:
		return false

	if _expansion_order_active or _is_building_type_in_progress(PLACEMENT_COMMAND_CENTER):
		return false

	if _is_expansion_placement_on_cooldown():
		return false

	if _director != null and not _director.should_prioritize_expansion():
		return false

	if not _has_completed_building(PLACEMENT_HERO_ALTAR) or not _has_living_enemy_hero():
		return false

	if _count_enemy_workers() < _get_target_worker_count():
		return false

	if _find_expansion_gold_mine_anchor() == null:
		return false

	return EnemyResourceManager.can_afford(COMMAND_CENTER_GOLD_COST, COMMAND_CENTER_WOOD_COST)


func _sync_expansion_order_state() -> void:
	if not NodeSafety.is_alive_node(_expansion_target_mine):
		_expansion_target_mine = null

	_prune_expansion_failed_mine_cooldowns()

	if _count_living_command_centers() >= 2 or _is_building_type_in_progress(PLACEMENT_COMMAND_CENTER):
		_expansion_order_active = true
		return

	_expansion_order_active = false


func _is_expansion_placement_on_cooldown() -> bool:
	return _get_match_elapsed_seconds() < _expansion_placement_cooldown_until


func _begin_expansion_placement_cooldown() -> void:
	_expansion_placement_cooldown_until = (
		_get_match_elapsed_seconds() + EXPANSION_PLACEMENT_RETRY_SECONDS
	)


func _mark_expansion_mine_placement_failed(mine: GoldMine) -> void:
	if not NodeSafety.is_alive_node(mine):
		return

	_expansion_failed_mine_cooldowns[mine.get_instance_id()] = (
		_get_match_elapsed_seconds() + EXPANSION_PLACEMENT_RETRY_SECONDS
	)


func _is_expansion_mine_on_failure_cooldown(mine: GoldMine) -> bool:
	if not NodeSafety.is_alive_node(mine):
		return true

	var until: float = float(
		_expansion_failed_mine_cooldowns.get(mine.get_instance_id(), -1.0)
	)
	return _get_match_elapsed_seconds() < until


func _prune_expansion_failed_mine_cooldowns() -> void:
	var now: float = _get_match_elapsed_seconds()
	for instance_id: Variant in _expansion_failed_mine_cooldowns.keys():
		var until: float = float(_expansion_failed_mine_cooldowns[instance_id])
		if now >= until:
			_expansion_failed_mine_cooldowns.erase(instance_id)
			continue

		var node: Object = instance_from_id(int(instance_id))
		if not NodeSafety.is_alive_node(node):
			_expansion_failed_mine_cooldowns.erase(instance_id)


func _try_train_enemy_workers() -> bool:
	if _should_hold_workers_for_pending_tier_upgrade():
		_log_worker_production_stopped("holding_for_tier_upgrade")
		return false

	var target_workers: int = _get_target_worker_count()
	if _get_effective_worker_count() >= target_workers:
		_log_worker_production_stopped("at_target")
		return false

	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		_log_worker_production_stopped("no_command_center")
		return false

	if not EnemyResourceManager.has_food_supply(1):
		_ensure_farm_reservation()
		if _needs_farm():
			_try_place_farm(true)
		_log_worker_production_stopped("population_cap")
		return false

	var pending_queue: int = command_center.get_worker_queue_count()
	var queue_target: int = _get_worker_queue_target()
	if pending_queue >= queue_target:
		return false

	var trained_any: bool = false
	var trained_this_tick: int = 0
	var max_trains_this_tick: int = mini(
		queue_target - pending_queue,
		mini(
			target_workers - _get_effective_worker_count(),
			CommandCenter.MAX_ENEMY_WORKER_QUEUE - pending_queue
		)
	)
	while trained_this_tick < max_trains_this_tick:
		if not command_center.try_train_enemy_worker():
			_log_worker_production_blocker(command_center, target_workers)
			break
		trained_any = true
		trained_this_tick += 1

	if trained_any and _is_opening_phase():
		EnemyAIDebug.log_opening_training(
			_get_effective_worker_count(),
			_get_target_worker_count()
		)

	return trained_any


func _get_worker_queue_target() -> int:
	if EnemyResourceManager.gold < WORKER_TRAIN_GOLD_COST * 2:
		return 1
	return WORKER_QUEUE_TARGET


func _log_worker_production_stopped(reason: String) -> void:
	if not DEBUG_AI_WORKER_PRODUCTION:
		return

	if reason == _last_worker_idle_reason:
		return

	_last_worker_idle_reason = reason
	var command_center: CommandCenter = _get_training_command_center()
	var queue_count: int = command_center.get_worker_queue_count() if command_center != null else 0
	print(
		"AI worker production stopped: workers=%d/%d gold=%d wood=%d population=%d/%d queue=%d reason=%s"
		% [
			_get_effective_worker_count(),
			_get_target_worker_count(),
			EnemyResourceManager.gold,
			EnemyResourceManager.wood,
			EnemyResourceManager.food_current,
			EnemyResourceManager.food_max,
			queue_count,
			reason,
		]
	)


func _log_worker_production_blocker(command_center: CommandCenter, target_workers: int) -> void:
	if not DEBUG_AI_WORKER_PRODUCTION:
		return

	var reason: String = "unknown"
	if command_center.is_upgrading_tier():
		reason = "upgrading"
	elif command_center.get_worker_queue_count() >= CommandCenter.MAX_ENEMY_WORKER_QUEUE:
		reason = "queue_full"
	elif EnemyResourceManager.gold < WORKER_TRAIN_GOLD_COST:
		reason = "insufficient_gold"
	elif not EnemyResourceManager.has_food_supply(1):
		reason = "population_cap"
	elif not command_center.can_train_enemy_worker():
		reason = "training_blocked"

	_log_worker_production_stopped(reason)


func _compute_base_worker_target() -> int:
	if _is_opening_phase():
		return EnemyStrategicDirector.OPENING_WORKER_TARGET

	var target: int = TARGET_WORKERS_EARLY
	if _director != null:
		match _director.get_strategic_phase():
			EnemyStrategicDirector.StrategicPhase.EARLY_ARMY, \
			EnemyStrategicDirector.StrategicPhase.CREEPING:
				target = TARGET_WORKERS_EARLY
			EnemyStrategicDirector.StrategicPhase.TIER_2, \
			EnemyStrategicDirector.StrategicPhase.EXPANSION, \
			EnemyStrategicDirector.StrategicPhase.MID_GAME:
				target = TARGET_WORKERS_MID
			EnemyStrategicDirector.StrategicPhase.TIER_3:
				target = TARGET_WORKERS_LATE
			EnemyStrategicDirector.StrategicPhase.LATE_GAME:
				target = (
					TARGET_WORKERS_ENDGAME_HIGH
					if _has_abundant_resources()
					else TARGET_WORKERS_ENDGAME
				)
			_:
				target = TARGET_WORKERS_EARLY
	else:
		var elapsed_seconds: float = _get_match_elapsed_seconds()
		if elapsed_seconds >= WORKER_PHASE_ENDGAME_SECONDS:
			target = (
				TARGET_WORKERS_ENDGAME_HIGH
				if _has_abundant_resources()
				else TARGET_WORKERS_ENDGAME
			)
		elif elapsed_seconds >= WORKER_PHASE_LATE_SECONDS:
			target = TARGET_WORKERS_LATE
		elif elapsed_seconds >= WORKER_PHASE_MID_SECONDS:
			target = TARGET_WORKERS_MID

	if _director != null and _director.should_boost_worker_production():
		target = maxi(target, TARGET_WORKERS_MID)

	var player_workers: int = _count_player_workers()
	if player_workers > 0:
		var ai_workers: int = _count_enemy_workers()
		if ai_workers < int(float(player_workers) * 0.7):
			target = maxi(target, mini(player_workers, TARGET_WORKERS_ENDGAME_HIGH))

	return target


func _get_target_worker_count() -> int:
	var target: int = _compute_base_worker_target()
	if _should_rebuild_workers():
		target = maxi(target, _get_phase_worker_target())
	return mini(target, HARD_WORKER_SAFETY_CAP)


func _get_phase_worker_target() -> int:
	if _director != null:
		match _director.get_strategic_phase():
			EnemyStrategicDirector.StrategicPhase.OPENING:
				return EnemyStrategicDirector.OPENING_WORKER_TARGET
			EnemyStrategicDirector.StrategicPhase.EARLY_ARMY, \
			EnemyStrategicDirector.StrategicPhase.CREEPING:
				return TARGET_WORKERS_EARLY
			EnemyStrategicDirector.StrategicPhase.TIER_2, \
			EnemyStrategicDirector.StrategicPhase.EXPANSION, \
			EnemyStrategicDirector.StrategicPhase.MID_GAME:
				return TARGET_WORKERS_MID
			EnemyStrategicDirector.StrategicPhase.TIER_3:
				return TARGET_WORKERS_LATE
			_:
				return TARGET_WORKERS_ENDGAME

	var elapsed_seconds: float = _get_match_elapsed_seconds()
	if elapsed_seconds >= WORKER_PHASE_ENDGAME_SECONDS:
		return TARGET_WORKERS_ENDGAME
	if elapsed_seconds >= WORKER_PHASE_LATE_SECONDS:
		return TARGET_WORKERS_LATE
	if elapsed_seconds >= WORKER_PHASE_MID_SECONDS:
		return TARGET_WORKERS_MID
	return TARGET_WORKERS_EARLY


func _should_grow_worker_economy() -> bool:
	return _get_effective_worker_count() < _get_target_worker_count()


func _can_train_military_units() -> bool:
	if _count_enemy_workers() < _get_min_workers_before_military():
		return false

	if _should_rebuild_workers() and not _has_abundant_resources():
		return false

	return true


func _get_min_workers_before_military() -> int:
	if _has_abundant_resources():
		return MIN_WORKERS_BEFORE_MILITARY_ABUNDANT
	return MIN_WORKERS_BEFORE_MILITARY


func _has_excess_resources() -> bool:
	return (
		EnemyResourceManager.gold >= RESOURCE_HIGH_THRESHOLD
		or EnemyResourceManager.wood >= RESOURCE_HIGH_THRESHOLD
	)


func _has_abundant_resources() -> bool:
	return (
		EnemyResourceManager.gold >= RESOURCE_AGGRESSIVE_THRESHOLD
		or EnemyResourceManager.wood >= RESOURCE_AGGRESSIVE_THRESHOLD
	)


func _has_wasted_resources() -> bool:
	return (
		EnemyResourceManager.gold >= RESOURCE_WASTE_THRESHOLD
		and EnemyResourceManager.wood >= RESOURCE_WASTE_THRESHOLD
	)


func _get_max_barracks() -> int:
	## Progressive unlock within the difficulty hard cap (never exceeds it).
	var hard_cap: int = AIDifficultyConfig.max_barracks()
	if hard_cap <= 1:
		return hard_cap

	var unlocked: int = _get_progressive_production_slots(hard_cap)
	return mini(unlocked, hard_cap)


func _get_max_stables() -> int:
	var hard_cap: int = AIDifficultyConfig.max_stables()
	if hard_cap <= 1:
		return hard_cap

	## Do not open stables until barracks have reached their difficulty cap.
	if _count_barracks() < AIDifficultyConfig.max_barracks():
		return 0 if _count_stables() <= 0 else mini(_count_stables(), hard_cap)

	var unlocked: int = _get_progressive_production_slots(hard_cap)
	return mini(unlocked, hard_cap)


func _get_max_artillery_depots() -> int:
	var hard_cap: int = AIDifficultyConfig.max_artillery_depots()
	if hard_cap <= 1:
		return hard_cap

	if _count_barracks() < AIDifficultyConfig.max_barracks():
		return 0 if _count_artillery_depots() <= 0 else mini(_count_artillery_depots(), hard_cap)
	if _count_stables() < AIDifficultyConfig.max_stables():
		return 0 if _count_artillery_depots() <= 0 else mini(_count_artillery_depots(), hard_cap)

	var unlocked: int = _get_progressive_production_slots(hard_cap)
	return mini(unlocked, hard_cap)


func _get_progressive_production_slots(hard_cap: int) -> int:
	## Unlock additional production buildings as the match progresses.
	var unlocked: int = 1
	if _director != null:
		match _director.get_strategic_phase():
			EnemyStrategicDirector.StrategicPhase.OPENING, \
			EnemyStrategicDirector.StrategicPhase.EARLY_ARMY:
				unlocked = 1
			EnemyStrategicDirector.StrategicPhase.CREEPING, \
			EnemyStrategicDirector.StrategicPhase.TIER_2, \
			EnemyStrategicDirector.StrategicPhase.EXPANSION:
				unlocked = 2
			EnemyStrategicDirector.StrategicPhase.MID_GAME, \
			EnemyStrategicDirector.StrategicPhase.TIER_3:
				unlocked = 3
			_:
				unlocked = 4
	else:
		var elapsed_seconds: float = _get_match_elapsed_seconds()
		if elapsed_seconds < ARMY_SIZE_MID_AFTER_SECONDS:
			unlocked = 2
		elif elapsed_seconds < ARMY_SIZE_LATE_AFTER_SECONDS:
			unlocked = 3
		else:
			unlocked = 4

	return clampi(unlocked, 1, hard_cap)


func _should_build_stable() -> bool:
	if not TechTree.can_build_stable(ENEMY_TEAM_ID):
		return false

	if _count_stables() >= _get_max_stables():
		return false

	if _is_building_type_in_progress(PLACEMENT_STABLE):
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	## Barracks-first progression: finish barracks cap before opening stables.
	if _count_barracks() < AIDifficultyConfig.max_barracks():
		return false

	if not TechTree.player_has_tier_2(ENEMY_TEAM_ID):
		return false

	if _director != null and not _director.should_prioritize_late_game_units():
		if not _director.is_phase_at_least(EnemyStrategicDirector.StrategicPhase.LATE_GAME):
			return false

	if _count_stables() > 0 and not _can_expand_military_production(PLACEMENT_STABLE):
		return false

	return (
		_has_excess_resources()
		and EnemyResourceManager.can_afford(STABLE_GOLD_COST, STABLE_WOOD_COST)
	)


func _can_expand_military_production(building_type: StringName) -> bool:
	## Extra production buildings require economy, busy queues, and food headroom.
	if not EnemyResourceManager.can_afford(
		_get_building_gold_cost(building_type),
		_get_building_wood_cost(building_type)
	):
		return false

	if _get_projected_free_population() < PRODUCTION_EXPAND_FOOD_HEADROOM:
		return false

	if not _are_production_buildings_busy(building_type):
		return false

	return true


func _get_building_gold_cost(building_type: StringName) -> int:
	match building_type:
		PLACEMENT_BARRACKS:
			return BARRACKS_GOLD_COST
		PLACEMENT_STABLE:
			return STABLE_GOLD_COST
		PLACEMENT_ARTILLERY_DEPOT:
			return ARTILLERY_DEPOT_GOLD_COST
		_:
			return 0


func _get_building_wood_cost(building_type: StringName) -> int:
	match building_type:
		PLACEMENT_BARRACKS:
			return BARRACKS_WOOD_COST
		PLACEMENT_STABLE:
			return STABLE_WOOD_COST
		PLACEMENT_ARTILLERY_DEPOT:
			return ARTILLERY_DEPOT_WOOD_COST
		_:
			return 0


func _are_production_buildings_busy(building_type: StringName) -> bool:
	var total: int = 0
	var busy: int = 0

	match building_type:
		PLACEMENT_BARRACKS:
			for barracks: Barracks in _find_all_completed_enemy_barracks():
				if not is_instance_valid(barracks):
					continue
				total += 1
				if barracks.is_enemy_training_busy() or barracks.get_enemy_pending_unit_count() > 0:
					busy += 1
		PLACEMENT_STABLE:
			for stable: Stable in _find_all_completed_enemy_stables():
				if not is_instance_valid(stable):
					continue
				total += 1
				if stable.is_enemy_training_busy() or stable.get_enemy_pending_unit_count() > 0:
					busy += 1
		PLACEMENT_ARTILLERY_DEPOT:
			for depot: ArtilleryDepot in _find_all_completed_enemy_artillery_depots():
				if not is_instance_valid(depot):
					continue
				total += 1
				if depot.has_active_unit_training() or depot.get_enemy_pending_unit_count() > 0:
					busy += 1
		_:
			return false

	if total <= 0:
		return false

	## Require most existing buildings to be actively training before expanding.
	return busy * 2 >= total


func _count_stables() -> int:
	var count: int = 0
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if node is Stable and _is_living_building(node as Building):
			count += 1
	return count


func _count_artillery_depots() -> int:
	var count: int = 0
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if node is ArtilleryDepot and _is_living_building(node as Building):
			count += 1
	return count


func get_difficulty_debug_info() -> Dictionary:
	return {
		"difficulty": MatchSession.get_ai_difficulty_name(),
		"barracks_current": _count_barracks(),
		"barracks_max": AIDifficultyConfig.max_barracks(),
		"stables_current": _count_stables(),
		"stables_max": AIDifficultyConfig.max_stables(),
		"artillery_current": _count_artillery_depots(),
		"artillery_max": AIDifficultyConfig.max_artillery_depots(),
	}


func _is_within_difficulty_production_cap(building_type: StringName) -> bool:
	## Absolute hard-cap guard — never exceed difficulty production limits.
	match building_type:
		PLACEMENT_BARRACKS:
			return _count_barracks() < AIDifficultyConfig.max_barracks()
		PLACEMENT_STABLE:
			return _count_stables() < AIDifficultyConfig.max_stables()
		PLACEMENT_ARTILLERY_DEPOT:
			return _count_artillery_depots() < AIDifficultyConfig.max_artillery_depots()
		_:
			return true


func _should_rebuild_workers() -> bool:
	var target_workers: int = _compute_base_worker_target()
	if target_workers <= 0:
		return false

	var rebuild_threshold: int = maxi(
		MIN_WORKERS_BEFORE_MILITARY - 2,
		int(float(target_workers) * WORKER_REBUILD_THRESHOLD_RATIO)
	)
	return _get_effective_worker_count() < rebuild_threshold


func _get_effective_worker_count() -> int:
	return _count_enemy_workers() + _get_pending_worker_count()


func _get_pending_worker_count() -> int:
	var command_center: CommandCenter = _get_training_command_center()
	if command_center == null:
		return 0

	return command_center.get_worker_queue_count()


func _try_sustain_military_production() -> void:
	if not _can_train_military_units():
		return

	if not EnemyResourceManager.has_food_supply(MILITARY_TRAIN_FOOD_COST):
		if _count_completed_farms() + _count_farms_under_construction() < MAX_FARMS:
			_try_place_farm(true)
		return

	var army_deficit: int = (
		_get_effective_desired_army_size()
		- _count_living_military_units()
		- _count_pending_military_units()
	)
	var defending: bool = EnemyArmyCommand.get_army_mode() in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]
	var sustain_pressure: bool = (
		army_deficit > 0
		or _director != null and _director.should_boost_army_production()
		or EnemyArmyCommand.is_rebuilding_army()
		or _has_excess_resources()
		or _has_wasted_resources()
	)
	if not sustain_pressure:
		_log_idle_production_if_needed()
		return

	var trains_per_barracks: int = mini(
		MILITARY_DEFENSE_TRAINS_PER_BARRACKS
		if defending
		else (
			MILITARY_TRAINS_PER_BARRACKS_ABUNDANT
			if _has_abundant_resources()
			else (
				MILITARY_TRAINS_PER_BARRACKS_WHEN_LOW
				if army_deficit >= MILITARY_LOW_ARMY_DEFICIT
				else MILITARY_TRAINS_PER_BARRACKS_SUSTAIN
			)
		),
		Barracks.MAX_ENEMY_UNIT_QUEUE
	)

	var trained_any: bool = false
	for barracks: Barracks in _find_all_completed_enemy_barracks():
		var queue_attempts: int = trains_per_barracks
		while queue_attempts > 0:
			if barracks.get_enemy_pending_unit_count() >= Barracks.MAX_ENEMY_UNIT_QUEUE:
				break

			if not _try_train_military(barracks):
				break

			trained_any = true
			queue_attempts -= 1

	if not trained_any and _has_wasted_resources():
		EnemyArmyCommand.debug_combat_log("production idle unexpectedly with excess resources")


func _try_sustain_stable_production() -> void:
	if not TechTree.can_build_stable(ENEMY_TEAM_ID):
		return

	if not EnemyResourceManager.has_food_supply(1):
		return

	for stable: Stable in _find_all_completed_enemy_stables():
		if not is_instance_valid(stable):
			continue

		var queue_attempts: int = 2 if _has_excess_resources() else 1
		while queue_attempts > 0:
			if not _try_train_cavalry(stable):
				break
			queue_attempts -= 1


func _try_sustain_artillery_production() -> void:
	if not TechTree.can_build_artillery_depot(ENEMY_TEAM_ID):
		return

	if not _should_train_cannons():
		return

	if not EnemyResourceManager.has_food_supply(CANNON_TRAIN_FOOD_COST):
		return

	for depot: ArtilleryDepot in _find_all_completed_enemy_artillery_depots():
		if not is_instance_valid(depot):
			continue

		if depot.get_enemy_pending_unit_count() >= ArtilleryDepot.MAX_ENEMY_UNIT_QUEUE:
			continue

		if (
			_count_living_cannons() + _count_pending_cannons()
			>= MAX_ENEMY_CANNONS
		):
			return

		depot.try_train_enemy_cannon()
		return


func _should_train_cannons() -> bool:
	if _count_living_cannons() + _count_pending_cannons() >= MAX_ENEMY_CANNONS:
		return false

	# Prefer siege when attacking player buildings.
	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.ATTACKING:
		return true

	# Counter large player armies with artillery.
	if _count_player_military_units() >= MIN_PLAYER_ARMY_FOR_CANNONS:
		return true

	# Seed at least one cannon once the depot is online and economy is healthy.
	if (
		_count_living_cannons() + _count_pending_cannons() <= 0
		and _has_excess_resources()
	):
		return true

	if _has_abundant_resources() and _count_living_military_units() >= TIER_3_MIN_ARMY:
		return true

	return false


func _find_all_completed_enemy_artillery_depots() -> Array:
	var depots: Array = []
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is ArtilleryDepot or not _is_living_building(node as Building):
			continue

		var depot: ArtilleryDepot = node as ArtilleryDepot
		if depot.building_state == Building.STATE_COMPLETED:
			depots.append(depot)

	return depots


func _count_living_cannons() -> int:
	var count: int = 0
	for unit: Variant in EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree()):
		if unit is Cannon and is_instance_valid(unit as Node):
			count += 1
	return count


func _count_pending_cannons() -> int:
	var pending: int = 0
	for depot: ArtilleryDepot in _find_all_completed_enemy_artillery_depots():
		if is_instance_valid(depot):
			pending += depot.get_enemy_pending_unit_count()
	return pending


func _count_player_military_units() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is Worker or node is Hero:
			continue
		if (
			node is Spearman
			or node is Swordsman
			or node is Archer
			or node is HeavyCavalry
			or node is LightCavalry
			or node is CavalryArcher
			or node is Cannon
		):
			count += 1
	return count


func _find_all_completed_enemy_stables() -> Array:
	var stables: Array = []
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Stable or not _is_living_building(node as Building):
			continue

		var stable: Stable = node as Stable
		if stable.building_state == Building.STATE_COMPLETED:
			stables.append(stable)

	return stables


func _try_train_cavalry(stable: Stable) -> bool:
	if not is_instance_valid(stable):
		return false

	if _train_cavalry_next:
		if stable.try_train_enemy_light_cavalry():
			_train_cavalry_next = false
			return true
		if stable.try_train_enemy_cavalry_archer():
			_train_cavalry_next = true
			return true
	else:
		if stable.try_train_enemy_cavalry_archer():
			_train_cavalry_next = true
			return true
		if stable.try_train_enemy_light_cavalry():
			_train_cavalry_next = false
			return true

	return stable.try_train_enemy_heavy_cavalry()


func _log_idle_production_if_needed() -> void:
	if not _has_wasted_resources():
		return

	for barracks: Barracks in _find_all_completed_enemy_barracks():
		if barracks.get_enemy_pending_unit_count() <= 0:
			EnemyArmyCommand.debug_combat_log(
				"production idle unexpectedly at barracks with excess resources"
			)
			return


func _get_desired_army_size() -> int:
	if _director != null:
		match _director.get_strategic_phase():
			EnemyStrategicDirector.StrategicPhase.OPENING, \
			EnemyStrategicDirector.StrategicPhase.EARLY_ARMY, \
			EnemyStrategicDirector.StrategicPhase.CREEPING, \
			EnemyStrategicDirector.StrategicPhase.TIER_2, \
			EnemyStrategicDirector.StrategicPhase.EXPANSION:
				return DESIRED_ARMY_EARLY
			EnemyStrategicDirector.StrategicPhase.MID_GAME, \
			EnemyStrategicDirector.StrategicPhase.TIER_3:
				return DESIRED_ARMY_MID
			_:
				return DESIRED_ARMY_LATE

	var elapsed_seconds: float = _get_match_elapsed_seconds()
	if elapsed_seconds < ARMY_SIZE_MID_AFTER_SECONDS:
		return DESIRED_ARMY_EARLY
	if elapsed_seconds < ARMY_SIZE_LATE_AFTER_SECONDS:
		return DESIRED_ARMY_MID

	return DESIRED_ARMY_LATE


func _count_living_military_units() -> int:
	var frame: int = Engine.get_process_frames()
	if frame == _cached_military_count_frame and _cached_military_count >= 0:
		return _cached_military_count
	_cached_military_count_frame = frame
	_cached_military_count = EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree()).size()
	return _cached_military_count


func _count_pending_military_units() -> int:
	var pending: int = 0
	for barracks: Barracks in _find_all_completed_enemy_barracks():
		pending += barracks.get_enemy_pending_unit_count()

	return pending


func _get_effective_desired_army_size() -> int:
	var desired: int = _get_desired_army_size()
	if EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.DEFENDING:
		desired += MILITARY_DEFENSE_EXTRA_DESIRED
	elif _director != null and _director.should_boost_army_production():
		desired += 8
	elif EnemyArmyCommand.is_rebuilding_army():
		desired += 6

	return desired


func _needs_more_military_units() -> bool:
	return (
		_count_living_military_units() + _count_pending_military_units()
		< _get_effective_desired_army_size()
	)


func _try_train_military(barracks: Barracks) -> bool:
	if not is_instance_valid(barracks):
		return false

	if TechTree.can_train_swordsman_or_archer(ENEMY_TEAM_ID):
		if _train_swordsman_next:
			if barracks.try_train_enemy_swordsman():
				_train_swordsman_next = false
				EnemyAIDebug.log_training("Swordsman")
				return true
			if barracks.try_train_enemy_archer():
				_train_swordsman_next = true
				EnemyAIDebug.log_training("Archer")
				return true
		else:
			if barracks.try_train_enemy_archer():
				_train_swordsman_next = true
				EnemyAIDebug.log_training("Archer")
				return true
			if barracks.try_train_enemy_swordsman():
				_train_swordsman_next = false
				EnemyAIDebug.log_training("Swordsman")
				return true

		if barracks.try_train_enemy_spearman():
			EnemyAIDebug.log_training("Pikeman")
			return true
		return false

	if barracks.try_train_enemy_spearman():
		EnemyAIDebug.log_training("Pikeman")
		return true
	return false


func _try_place_expansion_command_center() -> bool:
	_sync_expansion_order_state()
	if _expansion_order_active or _is_expansion_placement_on_cooldown():
		return false

	# Wait for other builds without entering the retry cooldown.
	if not _can_start_additional_construction(PLACEMENT_COMMAND_CENTER):
		return false

	var expansion_mine: GoldMine = _find_expansion_gold_mine_anchor()
	if not NodeSafety.is_alive_node(expansion_mine):
		_expansion_target_mine = null
		_begin_expansion_placement_cooldown()
		return false

	_expansion_target_mine = expansion_mine as GoldMine
	var placed: bool = _try_place_building_at_anchor(
		PLACEMENT_COMMAND_CENTER,
		_expansion_target_mine.global_position,
		true
	)
	if placed:
		_expansion_order_active = true
		_expansion_placement_cooldown_until = -1.0
		return true

	# Placement failed: cool down this mine and clear the sticky target so the
	# next attempt can pick another reachable mine / nearby build spot.
	_mark_expansion_mine_placement_failed(_expansion_target_mine)
	_expansion_target_mine = null
	_expansion_order_active = false
	_begin_expansion_placement_cooldown()
	return false


func _find_expansion_gold_mine_anchor() -> GoldMine:
	if NodeSafety.is_alive_node(_expansion_target_mine):
		var sticky_mine: GoldMine = _expansion_target_mine as GoldMine
		if (
			_is_valid_expansion_gold_mine(sticky_mine)
			and not _is_expansion_mine_on_failure_cooldown(sticky_mine)
		):
			return sticky_mine
		_expansion_target_mine = null

	var origin_position: Vector3 = _get_expansion_search_origin()
	if origin_position == Vector3.ZERO:
		return null

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	var starting_mine: GoldMine = _resolve_enemy_starting_gold_mine()
	var nav_map: RID = _get_navigation_map()
	var best_mine: GoldMine = null
	var best_score: float = INF

	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if not NodeSafety.is_alive_node(child) or not child is GoldMine:
			continue

		var mine: GoldMine = child as GoldMine
		if starting_mine != null and mine == starting_mine:
			continue

		if not _is_valid_expansion_gold_mine(mine):
			continue

		if _is_expansion_mine_on_failure_cooldown(mine):
			continue

		if not _is_expansion_mine_reachable(mine, origin_position, nav_map):
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			mine.global_position,
			origin_position
		)
		var score: float = distance
		if not WorkerGathering.is_safe_gather_source(mine, get_tree()):
			score += EXPANSION_UNSAFE_DISTANCE_PENALTY

		if score < best_score:
			best_score = score
			best_mine = mine

	return best_mine


func _is_valid_expansion_gold_mine(mine: GoldMine) -> bool:
	if not NodeSafety.is_alive_node(mine):
		return false

	if not mine.can_gather():
		return false

	if _has_command_center_near_position(mine.global_position):
		return false

	return true


func _get_expansion_search_origin() -> Vector3:
	var primary: CommandCenter = _resolve_primary_command_center()
	if primary != null and NodeSafety.is_alive_node(primary):
		return primary.global_position

	return EnemyArmyCommand.resolve_enemy_rally_position(get_tree())


func _resolve_enemy_starting_gold_mine() -> GoldMine:
	var primary: CommandCenter = _resolve_primary_command_center()
	if primary == null or not NodeSafety.is_alive_node(primary):
		return null

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	var closest_mine: GoldMine = null
	var closest_distance: float = INF
	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if not NodeSafety.is_alive_node(child) or not child is GoldMine:
			continue

		var mine: GoldMine = child as GoldMine
		if not mine.can_gather():
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			mine.global_position,
			primary.global_position
		)
		if distance > EXPANSION_CC_NEAR_MINE_DISTANCE:
			continue

		if distance < closest_distance:
			closest_distance = distance
			closest_mine = mine

	return closest_mine


func _is_expansion_mine_reachable(
	mine: GoldMine, from_position: Vector3, nav_map: RID
) -> bool:
	if not NodeSafety.is_alive_node(mine):
		return false

	if nav_map == RID():
		return true

	if not NavigationServer3D.map_is_active(nav_map):
		return true

	var from: Vector3 = Vector3(from_position.x, 0.5, from_position.z)
	var to: Vector3 = Vector3(mine.global_position.x, 0.5, mine.global_position.z)
	var start: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, from)
	var end: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start, end, true)
	return path.size() >= 2


func _has_command_center_near_position(position: Vector3) -> bool:
	if _has_command_center_near_position_in_group(position, ENEMY_BUILDING_GROUP):
		return true

	return _has_command_center_near_position_in_group(position, PLAYER_COMMAND_CENTER_GROUP)


func _has_command_center_near_position_in_group(position: Vector3, group_name: StringName) -> bool:
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if not NodeSafety.is_alive_node(node) or not node is CommandCenter:
			continue

		if not _is_living_building(node as Building):
			continue

		if (
			EnemyArmyCommand.horizontal_distance(
				position,
				(node as Node3D).global_position
			)
			<= EXPANSION_CC_NEAR_MINE_DISTANCE
		):
			return true

	return false


func _try_place_building(
	building_type: StringName, prefer_expansion: bool = false, allow_parallel: bool = false
) -> bool:
	if not is_inside_tree():
		return false

	var anchor: CommandCenter = _resolve_primary_command_center()
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return false

	return _try_place_building_at_anchor(
		building_type,
		anchor.global_position,
		prefer_expansion,
		allow_parallel
	)


func _try_place_building_at_anchor(
	building_type: StringName,
	anchor_position: Vector3,
	prefer_expansion: bool = false,
	allow_parallel: bool = false
) -> bool:
	if not is_inside_tree():
		return false

	if not _is_within_difficulty_production_cap(building_type):
		return false

	var is_farm: bool = building_type == PLACEMENT_FARM
	if is_farm:
		if _is_building_type_in_progress(PLACEMENT_FARM):
			return false
	elif not allow_parallel and not _can_start_additional_construction(building_type):
		return false

	var gold_cost: int = 0
	var wood_cost: int = 0
	match building_type:
		PLACEMENT_FARM:
			gold_cost = FARM_GOLD_COST
			wood_cost = FARM_WOOD_COST
		PLACEMENT_BARRACKS:
			gold_cost = BARRACKS_GOLD_COST
			wood_cost = BARRACKS_WOOD_COST
		PLACEMENT_BLACKSMITH:
			gold_cost = BLACKSMITH_GOLD_COST
			wood_cost = BLACKSMITH_WOOD_COST
		PLACEMENT_SHOP:
			gold_cost = SHOP_GOLD_COST
			wood_cost = SHOP_WOOD_COST
		PLACEMENT_HERO_ALTAR:
			gold_cost = HERO_ALTAR_GOLD_COST
			wood_cost = HERO_ALTAR_WOOD_COST
		PLACEMENT_COMMAND_CENTER:
			gold_cost = COMMAND_CENTER_GOLD_COST
			wood_cost = COMMAND_CENTER_WOOD_COST
		PLACEMENT_STABLE:
			gold_cost = STABLE_GOLD_COST
			wood_cost = STABLE_WOOD_COST
		PLACEMENT_ARTILLERY_DEPOT:
			gold_cost = ARTILLERY_DEPOT_GOLD_COST
			wood_cost = ARTILLERY_DEPOT_WOOD_COST
		PLACEMENT_ACADEMY:
			gold_cost = ACADEMY_GOLD_COST
			wood_cost = ACADEMY_WOOD_COST
		PLACEMENT_TOWER:
			gold_cost = TOWER_GOLD_COST
			wood_cost = TOWER_WOOD_COST
		_:
			return false

	# Farm/tower holds already reserve the cost; spend from total while reserved.
	var respect_reservations: bool = true
	if is_farm and _farm_reservation_active:
		respect_reservations = false
	elif building_type == PLACEMENT_TOWER and _tower_reservation_active:
		respect_reservations = false
	if not EnemyResourceManager.can_afford(gold_cost, wood_cost, respect_reservations):
		return false

	var parent: Node = get_node_or_null(buildings_parent_path)
	if parent == null or not parent.is_inside_tree():
		return false

	var existing_buildings: Array[Node3D] = EnemyBuildPlacement.collect_nearby_buildings(
		anchor_position,
		parent
	)
	var position: Vector3 = EnemyBuildPlacement.find_position(
		anchor_position,
		building_type,
		existing_buildings,
		prefer_expansion,
		parent,
		_get_navigation_map()
	)
	if not position.is_finite():
		return false

	var footprint: Vector2 = EnemyBuildPlacement.get_footprint(building_type)
	var footprint_reservation_id: int = ConstructionReservations.reserve_footprint(
		position,
		footprint,
		self,
		ConstructionReservations.FOOTPRINT_RESERVATION_TTL_MSEC
	)

	if not EnemyResourceManager.try_spend(gold_cost, wood_cost, respect_reservations):
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	var building: Building = _instantiate_building(building_type)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(gold_cost)
		EnemyResourceManager.add_wood(wood_cost)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	_tag_enemy_building(building)
	_add_health_component_if_needed(building, building_type)
	parent.add_child(building)
	if not NodeSafety.is_alive_node(building):
		EnemyResourceManager.add_gold(gold_cost)
		EnemyResourceManager.add_wood(wood_cost)
		ConstructionReservations.release_footprint(footprint_reservation_id)
		return false

	building.global_position = position
	building.set_construction_cost(gold_cost, wood_cost, true)
	building.start_under_construction()
	building.setup_construction(
		BuildingStats.get_construction_seconds(building_type, 1)
		/ UpgradeManager.get_construction_speed_multiplier(true)
	)
	ConstructionReservations.release_footprint(footprint_reservation_id)
	_assign_nearest_builder(building)
	_log_building_started(building_type)
	if building_type == PLACEMENT_BARRACKS and _has_excess_resources():
		EnemyArmyCommand.debug_combat_log("building additional barracks: excess resources")
	return true


func _can_start_additional_construction(building_type: StringName) -> bool:
	if building_type == PLACEMENT_FARM:
		return not _is_building_type_in_progress(PLACEMENT_FARM)

	return _count_unfinished_buildings() < MAX_PARALLEL_CONSTRUCTIONS


func _count_unfinished_buildings() -> int:
	return _collect_unfinished_buildings().size()


func _cancel_stuck_unfinished_constructions() -> void:
	var now_msec: int = Time.get_ticks_msec()
	for building: Building in _collect_unfinished_buildings():
		if not NodeSafety.is_alive_node(building):
			continue

		if _building_has_active_builder(building):
			continue

		var started_msec: int = building.get_construction_started_msec()
		if started_msec <= 0:
			continue

		if now_msec - started_msec < STUCK_CONSTRUCTION_TIMEOUT_MSEC:
			continue

		# No builder for too long — refund and clear the soft-lock site.
		building.refund_and_cancel_construction()
		if building is Farm:
			_begin_farm_placement_fail_cooldown()
			_release_farm_reservation()
			_ensure_farm_reservation()


func _log_building_started(building_type: StringName) -> void:
	if _is_opening_phase():
		match building_type:
			PLACEMENT_HERO_ALTAR:
				EnemyAIDebug.log_opening("Building Hero Altar")
				return
			PLACEMENT_BARRACKS:
				EnemyAIDebug.log_opening("Building Barracks")
				return
			PLACEMENT_FARM:
				# First farm uses Opening: Worker assigned to first Farm.
				if _count_completed_farms() == 0:
					return
				EnemyAIDebug.log_opening("Building Farm")
				return
			_:
				pass

	match building_type:
		PLACEMENT_HERO_ALTAR:
			EnemyAIDebug.log_building("Hero Altar")
		PLACEMENT_BARRACKS:
			EnemyAIDebug.log_building("Barracks")
		PLACEMENT_BLACKSMITH:
			EnemyAIDebug.log_building("Blacksmith")
		PLACEMENT_ACADEMY:
			EnemyAIDebug.log_building("Academy")
		PLACEMENT_SHOP:
			EnemyAIDebug.log_building("Shop")
		PLACEMENT_STABLE:
			EnemyAIDebug.log_building("Stable")
		PLACEMENT_ARTILLERY_DEPOT:
			EnemyAIDebug.log_building("Artillery Depot")
		PLACEMENT_COMMAND_CENTER:
			EnemyAIDebug.log_expanding()
		PLACEMENT_FARM:
			EnemyAIDebug.log_building("Farm")
		PLACEMENT_TOWER:
			EnemyAIDebug.log_building("Tower")
		_:
			pass


func _instantiate_building(building_type: StringName) -> Building:
	match building_type:
		PLACEMENT_FARM:
			return FARM_SCENE.instantiate() as Building
		PLACEMENT_BARRACKS:
			return BARRACKS_SCENE.instantiate() as Building
		PLACEMENT_BLACKSMITH:
			return BLACKSMITH_SCENE.instantiate() as Building
		PLACEMENT_SHOP:
			return SHOP_SCENE.instantiate() as Building
		PLACEMENT_HERO_ALTAR:
			return HERO_ALTAR_SCENE.instantiate() as Building
		PLACEMENT_COMMAND_CENTER:
			return COMMAND_CENTER_SCENE.instantiate() as Building
		PLACEMENT_STABLE:
			return STABLE_SCENE.instantiate() as Building
		PLACEMENT_ARTILLERY_DEPOT:
			return ARTILLERY_DEPOT_SCENE.instantiate() as Building
		PLACEMENT_ACADEMY:
			return ACADEMY_SCENE.instantiate() as Building
		PLACEMENT_TOWER:
			return TOWER_SCENE.instantiate() as Building
		_:
			return null


func _tag_enemy_building(building: Building) -> void:
	building.team_id = ENEMY_TEAM_ID

	if building.is_in_group(&"player_command_center"):
		building.remove_from_group(&"player_command_center")

	if not building.is_in_group(ENEMY_BUILDING_GROUP):
		building.add_to_group(ENEMY_BUILDING_GROUP)

	building.apply_team_visuals()


func _add_health_component_if_needed(building: Building, building_type: StringName) -> void:
	if building.get_node_or_null("HealthComponent") != null:
		return

	var max_health: int = 0
	match building_type:
		PLACEMENT_FARM:
			max_health = FARM_MAX_HEALTH
		PLACEMENT_HERO_ALTAR:
			max_health = HERO_ALTAR_MAX_HEALTH
		PLACEMENT_COMMAND_CENTER:
			max_health = COMMAND_CENTER_MAX_HEALTH
		PLACEMENT_STABLE:
			max_health = STABLE_MAX_HEALTH
		PLACEMENT_TOWER:
			max_health = TOWER_MAX_HEALTH
		_:
			return

	var health_component: Node = HEALTH_COMPONENT_SCRIPT.new()
	health_component.name = "HealthComponent"
	health_component.set("max_health", max_health)
	building.add_child(health_component)


func _try_assign_idle_builder_to_construction() -> void:
	for building: Building in _collect_unfinished_buildings():
		if not NodeSafety.is_alive_node(building) or not _is_living_building(building):
			continue

		if _building_has_active_builder(building):
			continue

		if (
			_is_opening_phase()
			and building is Farm
			and not _has_completed_building(PLACEMENT_FARM)
		):
			_assign_opening_farm_builder(building)
			_log_opening_first_farm_builder_if_needed()
		else:
			_assign_nearest_builder(building)


func _release_stale_build_workers() -> void:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not NodeSafety.is_alive_node(worker):
			continue

		if not worker.is_on_construction_trip():
			continue

		var build_target: Building = worker.get_build_target()
		if not NodeSafety.is_alive_node(build_target):
			worker.prepare_for_enemy_economy_reassign(
				"build task invalid, returning worker to economy"
			)
			notify_enemy_worker_spawned(worker)
			continue

		if build_target.building_state == Building.STATE_COMPLETED:
			worker.on_building_construction_finished()
			continue

		if worker.needs_enemy_worker_recovery() and worker.can_enemy_economy_force_reassign():
			worker.prepare_for_enemy_economy_reassign(
				"build task invalid, returning worker to economy"
			)
			notify_enemy_worker_spawned(worker)


func _collect_unfinished_buildings() -> Array[Building]:
	var buildings: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node) or not node is Building:
			continue

		var building: Building = node as Building
		if not _is_living_building(building):
			continue

		var state: StringName = building.building_state
		if (
			state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			buildings.append(building)

	return buildings


func _has_unfinished_construction() -> bool:
	return not _collect_unfinished_buildings().is_empty()


func _building_has_active_builder(building: Building) -> bool:
	if not NodeSafety.is_alive_node(building):
		return false

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not NodeSafety.is_alive_node(worker):
			continue

		if worker.is_assigned_to_build(building):
			return true

	return false


func _assign_nearest_builder(building: Building) -> void:
	if not NodeSafety.is_alive_node(building):
		return

	var worker: Worker = _find_nearest_available_enemy_worker(building.global_position, false)
	if (
		not NodeSafety.is_alive_node(worker)
		and building.building_state == Building.STATE_UNDER_CONSTRUCTION
	):
		worker = _find_nearest_available_enemy_worker(building.global_position, true)
	if not NodeSafety.is_alive_node(worker):
		return

	worker.command_build(building)
	EnemyUnitMission.try_set_mission(
		worker,
		EnemyUnitMission.Mission.BUILD,
		EnemyUnitMission.BUILD_COMMITMENT_SECONDS
	)


func _find_nearest_available_enemy_worker(
	near_position: Vector3, allow_gather_interrupt: bool = false
) -> Worker:
	var closest_worker: Worker = null
	var closest_distance_squared: float = INF

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not NodeSafety.is_alive_node(worker):
			continue

		if WorkerAiUnstuck.blocks_external_commands(worker):
			continue

		if not worker.is_available_for_construction_assignment(allow_gather_interrupt):
			continue

		var offset: Vector3 = worker.global_position - near_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_worker = worker

	return closest_worker


func _get_navigation_map() -> RID:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var agent: NavigationAgent3D = (
			node.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		)
		if agent != null and WorkerTaskNavigation.can_use(agent):
			return agent.get_navigation_map()

	return RID()


func _resolve_primary_command_center() -> CommandCenter:
	if _primary_command_center != null and _is_living_building(_primary_command_center):
		return _primary_command_center

	_primary_command_center = null

	if not enemy_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(enemy_command_center_path)
		if path_node is CommandCenter and _is_living_building(path_node as CommandCenter):
			_primary_command_center = path_node as CommandCenter
			return _primary_command_center

	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			_primary_command_center = node as CommandCenter
			return _primary_command_center

	return null


func _get_training_command_center() -> CommandCenter:
	var primary: CommandCenter = _resolve_primary_command_center()
	if primary != null:
		return primary

	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			return node as CommandCenter

	return null


func _refresh_building_cache_if_needed() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _building_scan_frame:
		return

	_building_scan_frame = frame
	_cached_enemy_buildings.clear()
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node != null and is_instance_valid(node):
			_cached_enemy_buildings.append(node)


func _find_all_completed_enemy_barracks() -> Array[Barracks]:
	var barracks_list: Array[Barracks] = []
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Barracks or not _is_living_building(node as Building):
			continue

		var barracks: Barracks = node as Barracks
		if barracks.building_state == Building.STATE_COMPLETED:
			barracks_list.append(barracks)

	return barracks_list


func _count_barracks() -> int:
	var count: int = 0
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if node is Barracks and _is_living_building(node as Building):
			count += 1

	return count


func _find_enemy_hero_altar() -> HeroAltar:
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if node is HeroAltar and _is_living_building(node as Building):
			if (node as HeroAltar).building_state == Building.STATE_COMPLETED:
				return node as HeroAltar

	return null


func _node_matches_building_type(node: Node, building_type: StringName) -> bool:
	match building_type:
		PLACEMENT_FARM:
			return node is Farm
		PLACEMENT_BARRACKS:
			return node is Barracks
		PLACEMENT_BLACKSMITH:
			return node is Blacksmith
		PLACEMENT_SHOP:
			return node is Shop
		PLACEMENT_HERO_ALTAR:
			return node is HeroAltar
		PLACEMENT_COMMAND_CENTER:
			return node is CommandCenter
		PLACEMENT_STABLE:
			return node is Stable
		PLACEMENT_ARTILLERY_DEPOT:
			return node is ArtilleryDepot
		PLACEMENT_ACADEMY:
			return node is Academy
		PLACEMENT_TOWER:
			return node is Tower
		_:
			return false


func _has_completed_building(building_type: StringName) -> bool:
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not _node_matches_building_type(node, building_type):
			continue
		if not _is_living_building(node as Building):
			continue
		if (node as Building).building_state == Building.STATE_COMPLETED:
			return true

	return false


func _is_building_type_in_progress(building_type: StringName) -> bool:
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not _node_matches_building_type(node, building_type):
			continue
		if not _is_living_building(node as Building):
			continue

		var state: StringName = (node as Building).building_state
		if (
			state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			return true

	return false


func _count_enemy_workers() -> int:
	var frame: int = Engine.get_process_frames()
	if frame == _cached_worker_count_frame and _cached_worker_count >= 0:
		return _cached_worker_count
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if node is Worker and is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	_cached_worker_count_frame = frame
	_cached_worker_count = count
	return count


func _count_farms() -> int:
	return _count_completed_farms() + _count_farms_under_construction()


func _count_completed_farms() -> int:
	var count: int = 0
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Farm or not _is_living_building(node as Building):
			continue
		if (node as Building).building_state == Building.STATE_COMPLETED:
			count += 1

	return count


func _count_farms_under_construction() -> int:
	var count: int = 0
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if not node is Farm or not _is_living_building(node as Building):
			continue

		var state: StringName = (node as Building).building_state
		if (
			state == Building.STATE_UNDER_CONSTRUCTION
			or state == Building.STATE_CONSTRUCTING
		):
			count += 1

	return count


func _count_living_command_centers() -> int:
	var count: int = 0
	_refresh_building_cache_if_needed()
	for node: Variant in _cached_enemy_buildings:
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			count += 1

	return count


func _is_living_building(building: Building) -> bool:
	if not NodeSafety.is_alive_node(building):
		return false

	var health_component: HealthComponent = building.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


func _get_enemy_gather_manager() -> EnemyGatherManager:
	if not enemy_gather_manager_path.is_empty():
		var manager: Node = get_node_or_null(enemy_gather_manager_path)
		if manager is EnemyGatherManager:
			return manager as EnemyGatherManager

	return null


func notify_enemy_worker_spawned(worker: Worker) -> void:
	var gather_manager: EnemyGatherManager = _get_enemy_gather_manager()
	if gather_manager != null:
		gather_manager.assign_worker_adaptively(worker)
		gather_manager.request_gather_rebalance()

	request_worker_production_check()
