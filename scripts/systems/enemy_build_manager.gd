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
const WORKER_REBUILD_THRESHOLD_RATIO: float = 0.60
const EXPANSION_MINE_MAX_DISTANCE: float = 36.0
const EXPANSION_CC_NEAR_MINE_DISTANCE: float = 22.0
const WORKER_PHASE_MID_SECONDS: float = 180.0
const WORKER_PHASE_LATE_SECONDS: float = 360.0
const WORKER_PHASE_ENDGAME_SECONDS: float = 600.0
const WORKER_TRAIN_GOLD_COST: int = 50
const FARM_HEADROOM_EARLY: int = 4
const FARM_HEADROOM_MID: int = 7
const FARM_HEADROOM_LATE: int = 10
const MAX_FARMS: int = 8
const DEBUG_AI_WORKER_PRODUCTION: bool = false
const DEFAULT_MAX_BARRACKS: int = 3
const MAX_BARRACKS_MID: int = 5
const MAX_BARRACKS_LATE: int = 8
const MAX_STABLES_LATE: int = 2
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
const MILITARY_TRAIN_FOOD_COST: int = 1
const ENEMY_TEAM_ID: int = 1

const PLACEMENT_FARM: StringName = &"farm"
const PLACEMENT_BARRACKS: StringName = &"barracks"
const PLACEMENT_BLACKSMITH: StringName = &"blacksmith"
const PLACEMENT_SHOP: StringName = &"shop"
const PLACEMENT_HERO_ALTAR: StringName = &"hero_altar"
const PLACEMENT_COMMAND_CENTER: StringName = &"command_center"
const PLACEMENT_STABLE: StringName = &"stable"

const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/buildings/shop.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const HEALTH_COMPONENT_SCRIPT: Script = preload("res://scripts/components/health_component.gd")

const FARM_GOLD_COST: int = 80
const FARM_WOOD_COST: int = 20
const BARRACKS_GOLD_COST: int = 150
const BARRACKS_WOOD_COST: int = 100
const BLACKSMITH_GOLD_COST: int = 100
const BLACKSMITH_WOOD_COST: int = 150
const SHOP_GOLD_COST: int = 80
const SHOP_WOOD_COST: int = 120
const SHOP_STABLE_GOLD_BUFFER: int = 350
const SHOP_PURCHASE_COOLDOWN_TICKS: int = 7
const SHOP_HERO_RALLY_DISTANCE: float = 18.0
const HERO_ALTAR_GOLD_COST: int = 180
const HERO_ALTAR_WOOD_COST: int = 110
const STABLE_GOLD_COST: int = 175
const STABLE_WOOD_COST: int = 125
const COMMAND_CENTER_GOLD_COST: int = 200
const COMMAND_CENTER_WOOD_COST: int = 400
const TIER_2_GOLD_COST: int = CommandCenter.TIER_2_GOLD_COST
const TIER_2_WOOD_COST: int = CommandCenter.TIER_2_WOOD_COST
const TIER_UPGRADE_STABLE_GOLD_BUFFER: int = 250
const TIER_UPGRADE_STABLE_WOOD_BUFFER: int = 150

const CONSTRUCTION_DURATION: float = 4.0
const BARRACKS_MAX_HEALTH: int = 300
const FARM_MAX_HEALTH: int = 250
const HERO_ALTAR_MAX_HEALTH: int = 350
const STABLE_MAX_HEALTH: int = 320
const COMMAND_CENTER_MAX_HEALTH: int = 500

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
var _director: EnemyStrategicDirector = null
var _last_worker_idle_reason: String = ""
var _pop_capped_since_seconds: float = -1.0
var _macro_emergency_timer: float = 0.0
var _farm_reservation_active: bool = false
var _cc_worker_queue_connected: bool = false
var _building_scan_frame: int = -1
var _cached_enemy_buildings: Array = []


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

	_run_build_order()
	_schedule_tick()


func _run_build_order() -> void:
	_refresh_building_cache_if_needed()
	_try_assign_idle_builder_to_construction()
	_run_macro_emergency_checks()

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

	if _should_build_hero_altar():
		if _try_place_building(PLACEMENT_HERO_ALTAR):
			return

	if _should_build_stable():
		if _try_place_building(PLACEMENT_STABLE):
			return

	if _should_build_shop():
		if _try_place_building(PLACEMENT_SHOP):
			return

	_try_sustain_shop_purchases()

	if not defer_military and _can_train_military_units():
		_try_sustain_military_production()
		_try_sustain_stable_production()

	if _should_build_expansion_command_center():
		_try_place_expansion_command_center()


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


func _update_enemy_hero_restoration() -> bool:
	if _has_living_enemy_hero():
		return false

	var hero_altar: HeroAltar = _find_enemy_hero_altar()
	if hero_altar != null and hero_altar.is_training_hero():
		return true

	if hero_altar == null and _should_build_hero_altar():
		_try_place_building(PLACEMENT_HERO_ALTAR)

	if hero_altar != null:
		hero_altar.try_train_enemy_hero()

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

	if _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY:
		return false

	return EnemyResourceManager.can_afford(BLACKSMITH_GOLD_COST, BLACKSMITH_WOOD_COST)


func _should_upgrade_command_center_tier() -> bool:
	if TechTree.player_has_tier_2(ENEMY_TEAM_ID):
		return false

	if _is_any_enemy_command_center_upgrading():
		return false

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or not is_instance_valid(command_center):
		return false

	if command_center.command_center_tier >= 2:
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if _count_enemy_workers() < MIN_WORKERS_BEFORE_MILITARY:
		return false

	if not _has_stable_enemy_economy_for_tier_upgrade():
		return false

	return command_center.can_try_enemy_upgrade_tier(2)


func _has_stable_enemy_economy_for_tier_upgrade() -> bool:
	return (
		EnemyResourceManager.gold >= TIER_2_GOLD_COST + TIER_UPGRADE_STABLE_GOLD_BUFFER
		and EnemyResourceManager.wood >= TIER_2_WOOD_COST + TIER_UPGRADE_STABLE_WOOD_BUFFER
	)


func _try_upgrade_command_center_tier() -> void:
	if not _should_upgrade_command_center_tier():
		return

	var command_center: CommandCenter = _resolve_primary_command_center()
	if command_center == null or not is_instance_valid(command_center):
		return

	command_center.try_upgrade_enemy_tier(2)


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
		return


func _find_completed_enemy_blacksmith() -> Blacksmith:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Blacksmith or not _is_living_building(node as Building):
			continue

		var blacksmith: Blacksmith = node as Blacksmith
		if blacksmith.building_state == Building.STATE_COMPLETED:
			return blacksmith

	return null


func _should_build_shop() -> bool:
	if _has_completed_building(PLACEMENT_SHOP):
		return false

	if _is_building_type_in_progress(PLACEMENT_SHOP):
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
	if hero == null or hero.is_inventory_full():
		return

	if not HeroItemService.is_hero_in_shop_range(shop, hero):
		if _should_send_hero_to_shop(hero):
			_command_hero_to_shop(hero, shop)
		return

	if _try_buy_next_useful_shop_item(shop):
		_shop_purchase_cooldown_ticks = SHOP_PURCHASE_COOLDOWN_TICKS


func _try_buy_next_useful_shop_item(shop: Shop) -> bool:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null:
		return false

	for item_id: StringName in HeroItemCatalog.SHOP_ITEM_ORDER:
		if _hero_already_owns_item(hero, item_id):
			continue

		if not HeroItemService.can_purchase_from_shop(shop, item_id):
			continue

		return shop.try_purchase_item(item_id)

	return false


func _hero_already_owns_item(hero: Hero, item_id: StringName) -> bool:
	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition and (item as HeroItemDefinition).item_id == item_id:
			return true

	return false


func _should_send_hero_to_shop(hero: Hero) -> bool:
	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	if (
		army_mode == EnemyArmyCommand.ArmyMode.ATTACKING
		or army_mode == EnemyArmyCommand.ArmyMode.REGROUPING
		or army_mode == EnemyArmyCommand.ArmyMode.DEFENDING
		or army_mode == EnemyArmyCommand.ArmyMode.INTERCEPTING
	):
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
	var target: Vector3 = shop.global_position
	target.y = hero.global_position.y
	hero.set_movement_target(target)


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
	var elapsed_seconds: float = _get_match_elapsed_seconds()
	if elapsed_seconds < WORKER_PHASE_MID_SECONDS:
		return FARM_HEADROOM_EARLY
	if elapsed_seconds < WORKER_PHASE_ENDGAME_SECONDS:
		return FARM_HEADROOM_MID
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
	_ensure_farm_reservation()
	if not EnemyResourceManager.can_afford(FARM_GOLD_COST, FARM_WOOD_COST):
		return false

	var placed: bool = _try_place_building(PLACEMENT_FARM, false, emergency)
	if placed:
		_release_farm_reservation()
	return placed


func _ensure_farm_reservation() -> void:
	if _farm_reservation_active:
		return

	EnemyResourceManager.reserve_resources(FARM_GOLD_COST, FARM_WOOD_COST)
	_farm_reservation_active = true


func _release_farm_reservation() -> void:
	if not _farm_reservation_active:
		return

	EnemyResourceManager.release_reservation(FARM_GOLD_COST, FARM_WOOD_COST)
	_farm_reservation_active = false


func _sync_farm_reservation() -> void:
	if _needs_farm() or not EnemyResourceManager.has_food_supply(3):
		_ensure_farm_reservation()
	else:
		_release_farm_reservation()


func _should_build_expansion_command_center() -> bool:
	if _count_living_command_centers() >= 2:
		return false

	if _director != null and not _director.should_prioritize_expansion():
		return false

	if _is_building_type_in_progress(PLACEMENT_COMMAND_CENTER):
		return false

	if not _has_completed_building(PLACEMENT_HERO_ALTAR) or not _has_living_enemy_hero():
		return false

	if _count_enemy_workers() < _get_target_worker_count():
		return false

	if _find_expansion_gold_mine_anchor() == null:
		return false

	return EnemyResourceManager.can_afford(COMMAND_CENTER_GOLD_COST, COMMAND_CENTER_WOOD_COST)


func _try_train_enemy_workers() -> bool:
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
	var elapsed_seconds: float = _get_match_elapsed_seconds()
	var target: int = TARGET_WORKERS_EARLY
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
	var elapsed_seconds: float = _get_match_elapsed_seconds()
	if elapsed_seconds < ARMY_SIZE_MID_AFTER_SECONDS:
		return maxi(max_barracks, 3)
	if elapsed_seconds < ARMY_SIZE_LATE_AFTER_SECONDS:
		return MAX_BARRACKS_MID
	return MAX_BARRACKS_LATE


func _should_build_stable() -> bool:
	if not TechTree.can_build_stable(ENEMY_TEAM_ID):
		return false

	if _count_stables() >= _get_max_stables():
		return false

	if _is_building_type_in_progress(PLACEMENT_STABLE):
		return false

	if not _has_completed_building(PLACEMENT_BARRACKS):
		return false

	if not TechTree.player_has_tier_2(ENEMY_TEAM_ID):
		return false

	return (
		_has_excess_resources()
		and EnemyResourceManager.can_afford(STABLE_GOLD_COST, STABLE_WOOD_COST)
	)


func _get_max_stables() -> int:
	var elapsed_seconds: float = _get_match_elapsed_seconds()
	if elapsed_seconds < ARMY_SIZE_LATE_AFTER_SECONDS:
		return 1
	return MAX_STABLES_LATE


func _count_stables() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if node is Stable and _is_living_building(node as Building):
			count += 1
	return count


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
		var queue_attempts: int = 2 if _has_excess_resources() else 1
		while queue_attempts > 0:
			if not _try_train_cavalry(stable):
				break
			queue_attempts -= 1


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
	var elapsed_seconds: float = _get_match_elapsed_seconds()
	if elapsed_seconds < ARMY_SIZE_MID_AFTER_SECONDS:
		return DESIRED_ARMY_EARLY
	if elapsed_seconds < ARMY_SIZE_LATE_AFTER_SECONDS:
		return DESIRED_ARMY_MID

	return DESIRED_ARMY_LATE


func _count_living_military_units() -> int:
	return EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree()).size()


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
				return true
			if barracks.try_train_enemy_archer():
				_train_swordsman_next = true
				return true
		else:
			if barracks.try_train_enemy_archer():
				_train_swordsman_next = true
				return true
			if barracks.try_train_enemy_swordsman():
				_train_swordsman_next = false
				return true

		return barracks.try_train_enemy_spearman()

	return barracks.try_train_enemy_spearman()


func _try_place_expansion_command_center() -> bool:
	var expansion_mine: GoldMine = _find_expansion_gold_mine_anchor()
	if expansion_mine == null:
		return false

	return _try_place_building_at_anchor(
		PLACEMENT_COMMAND_CENTER,
		expansion_mine.global_position,
		true
	)


func _find_expansion_gold_mine_anchor() -> GoldMine:
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	if rally_position == Vector3.ZERO:
		return null

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	var best_mine: GoldMine = null
	var best_distance: float = INF

	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if not child is GoldMine:
			continue

		if not child.name.begins_with("Enemy"):
			continue

		var mine: GoldMine = child as GoldMine
		if not mine.can_gather():
			continue

		if not WorkerGathering.is_safe_gather_source(mine, get_tree()):
			continue

		if _has_command_center_near_position(mine.global_position):
			continue

		var distance: float = EnemyArmyCommand.horizontal_distance(
			mine.global_position,
			rally_position
		)
		if distance > EXPANSION_MINE_MAX_DISTANCE:
			continue

		if distance < best_distance:
			best_distance = distance
			best_mine = mine

	return best_mine


func _has_command_center_near_position(position: Vector3) -> bool:
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is CommandCenter or not _is_living_building(node as Building):
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

	var is_farm: bool = building_type == PLACEMENT_FARM
	if is_farm:
		if _is_building_type_in_progress(PLACEMENT_FARM):
			return false
	elif _has_unfinished_construction():
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
		_:
			return false

	if not EnemyResourceManager.can_afford(gold_cost, wood_cost):
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

	if not EnemyResourceManager.try_spend(gold_cost, wood_cost):
		return false

	var building: Building = _instantiate_building(building_type)
	if building == null:
		return false

	_tag_enemy_building(building)
	_add_health_component_if_needed(building, building_type)
	parent.add_child(building)
	building.global_position = position
	building.start_under_construction()
	building.setup_construction(
		CONSTRUCTION_DURATION / UpgradeManager.get_construction_speed_multiplier(true)
	)
	_assign_nearest_builder(building)
	if building_type == PLACEMENT_BARRACKS and _has_excess_resources():
		EnemyArmyCommand.debug_combat_log("building additional barracks: excess resources")
	return true


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
		PLACEMENT_BARRACKS:
			max_health = BARRACKS_MAX_HEALTH
		PLACEMENT_FARM:
			max_health = FARM_MAX_HEALTH
		PLACEMENT_HERO_ALTAR:
			max_health = HERO_ALTAR_MAX_HEALTH
		PLACEMENT_COMMAND_CENTER:
			max_health = COMMAND_CENTER_MAX_HEALTH
		PLACEMENT_STABLE:
			max_health = STABLE_MAX_HEALTH
		_:
			return

	var health_component: Node = HEALTH_COMPONENT_SCRIPT.new()
	health_component.name = "HealthComponent"
	health_component.set("max_health", max_health)
	building.add_child(health_component)


func _try_assign_idle_builder_to_construction() -> void:
	for building: Building in _collect_unfinished_buildings():
		if not is_instance_valid(building) or not _is_living_building(building):
			continue

		if _building_has_active_builder(building):
			continue

		_assign_nearest_builder(building)


func _collect_unfinished_buildings() -> Array[Building]:
	var buildings: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not node is Building:
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
	if building == null or not is_instance_valid(building):
		return false

	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not node is Worker:
			continue

		var worker: Worker = node as Worker
		if not is_instance_valid(worker) or worker.is_queued_for_deletion():
			continue

		if worker.is_assigned_to_build(building):
			return true

	return false


func _assign_nearest_builder(building: Building) -> void:
	var worker: Worker = _find_nearest_available_enemy_worker(building.global_position, false)
	if (
		worker == null
		and building.building_state == Building.STATE_UNDER_CONSTRUCTION
	):
		worker = _find_nearest_available_enemy_worker(building.global_position, true)
	if worker == null:
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
		if not is_instance_valid(worker) or worker.is_queued_for_deletion():
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
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ENEMY_WORKER_GROUP):
		if node is Worker and is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1

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
	if building == null or not is_instance_valid(building):
		return false

	if building.is_queued_for_deletion():
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
