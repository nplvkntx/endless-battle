class_name EnemyAI
extends Node

## ONE condition-tick enemy strategic brain.
## Live world facts are the memory. Conditions are the state.
## Mechanics live in buildings / EnemyBuildManager / EnemyGatherManager / Unit APIs.

const TICK_INTERVAL_SECONDS: float = 0.5
const ENEMY_TEAM_ID: int = 1
const DEFENSE_RADIUS: float = 36.0
const HOME_NEAR_RADIUS: float = 8.0
const CAMP_CLEAR_RADIUS: float = 14.0
const COHESION_RADIUS: float = 14.0
const ATTACK_ENGAGE_RADIUS: float = 18.0
const CAMP_SEARCH_RANGE: float = 70.0
const ATTACK_POWER_RATIO: float = 1.25
const FOOD_SAFETY_MARGIN: int = 4
const MIN_EARLY_SPEARMEN: int = 5
const MIN_CREEP_SOLDIERS_NEAR: int = 3
const MIN_SOLDIERS_NEAR_HERO: int = 3
const EARLY_CAMPS_REQUIRED: int = 3
const EARLY_HERO_LEVEL_TARGET: int = 3
const GOLD_WORKER_RATIO: float = 0.6
const HOME_OFFSET: Vector3 = Vector3(-2.0, 0.0, 3.0)
const CRITICAL_WOOD_RESERVE: int = 40
const ARMY_SOFT_CAP: int = 36
const MAX_BARRACKS_DESIRED: int = 2

const DESIRED_WORKERS_T1: int = 10
const DESIRED_WORKERS_T2: int = 16
const DESIRED_WORKERS_T3: int = 22
const DESIRED_WORKERS_EXPANSION: int = 26

const DESIRED_SPEARMEN_T1: int = 9
const DESIRED_SPEARMEN_T2: int = 6
const DESIRED_SWORDSMEN: int = 5
const DESIRED_ARCHERS: int = 5
const DESIRED_LIGHT_CAVALRY: int = 4
const DESIRED_CANNONS: int = 2

const CMD_NONE: StringName = &""
const CMD_HOME: StringName = &"home"
const CMD_DEFEND: StringName = &"defend"
const CMD_CREEP: StringName = &"creep"
const CMD_ATTACK: StringName = &"attack"
const CMD_REGROUP: StringName = &"regroup"
const CMD_ATTACK_MARCH: StringName = &"attack_march"

@export var enemy_command_center_path: NodePath
@export var enemy_build_manager_path: NodePath
@export var enemy_gather_manager_path: NodePath
@export var show_debug_overlay: bool = true

## Persistent AI memory — only what cannot be derived cleanly from live world each tick.
var _tick_timer: float = 0.0
var _camps_cleared: int = 0
var _current_target_id: int = 0
var _last_command_kind: StringName = CMD_NONE
var _last_command_target_id: int = 0
var _last_command_army_count: int = 0
var _chosen_expansion_mine_id: int = 0
var _debug_priority: StringName = &"BOOT"
var _debug_condition_bucket: StringName = &"HOME"
var _debug_condition_reason: StringName = &"BOOT"
var _debug_threat_name: String = "-"
var _debug_last_logged_condition: StringName = &""
var _debug_overlay_lines: PackedStringArray = PackedStringArray()

var _build_manager: EnemyBuildManager = null
var _gather_manager: EnemyGatherManager = null
var _debug_label: Label = null

## Fresh snapshot rebuilt every tick.
var _w: Dictionary = {}


func _ready() -> void:
	_resolve_managers()
	if show_debug_overlay:
		_ensure_debug_overlay()
	MatchSession.register_match_reset(&"EnemyAI", reset_match_state)
	set_process(true)


func reset_match_state() -> void:
	_tick_timer = 0.0
	_camps_cleared = 0
	_current_target_id = 0
	_last_command_kind = CMD_NONE
	_last_command_target_id = 0
	_last_command_army_count = 0
	_chosen_expansion_mine_id = 0
	_debug_priority = &"RESET"
	_debug_condition_bucket = &"HOME"
	_debug_condition_reason = &"RESET"
	_debug_threat_name = "-"
	_debug_last_logged_condition = &""
	_debug_overlay_lines = PackedStringArray()
	_w.clear()
	_update_debug_overlay()


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL_SECONDS:
		return
	_tick_timer = 0.0
	_ai_tick()


func _ai_tick() -> void:
	_resolve_managers()
	_read_live_world()

	## Economy / tech / production — may all run; do not freeze military.
	_staff_abandoned_construction()
	_maintain_workers()
	_maintain_worker_distribution()
	_maintain_food()
	_ensure_basic_buildings()
	_ensure_hero()
	_ensure_tech_progression()
	_ensure_extra_barracks()
	_ensure_expansion()
	_ensure_upgrades()
	_ensure_unit_production()

	## Military — first true condition wins. Live facts are the only memory.
	if _w.hero == null:
		_army_home()
		_finish_military_decision(&"HOME", &"HOME_NO_HERO", &"HERO", null)
		return

	if _army_below_minimum():
		_army_home()
		_finish_military_decision(&"HOME", &"HOME_ARMY_SMALL", &"BUILD_FORCE", null)
		return

	var threat: Node3D = _find_base_threat()
	if threat != null:
		_debug_threat_name = threat.name
		_whole_army_attack(threat, CMD_DEFEND)
		_finish_military_decision(&"DEFEND", &"DEFEND", &"DEFEND", threat)
		return
	_debug_threat_name = "-"

	## Cohesion before any strategic offense — Hero must not fight alone.
	if not _hero_is_with_army():
		_regroup_whole_army()
		_finish_military_decision(&"REGROUP", &"REGROUP", &"REGROUP", null)
		return

	if _needs_early_creep():
		_creep_with_whole_army()
		_finish_military_decision(
			&"EARLY_CREEP",
			&"EARLY_CREEP",
			&"EARLY_CREEP",
			_resolve_debug_target_node()
		)
		return

	if _should_attack_player():
		_attack_player_with_whole_army()
		_finish_military_decision(
			&"ATTACK_PLAYER",
			&"ATTACK_PLAYER",
			&"ATTACK_PLAYER",
			_resolve_debug_target_node()
		)
		return

	if _useful_creep_exists():
		_creep_with_whole_army()
		_finish_military_decision(
			&"EXTRA_CREEP",
			&"EXTRA_CREEP",
			&"EXTRA_CREEP",
			_resolve_debug_target_node()
		)
		return

	_army_home()
	_finish_military_decision(&"HOME", &"HOME_WAIT", &"WAIT", null)

# ---------------------------------------------------------------------------
# Live world snapshot
# ---------------------------------------------------------------------------

func _read_live_world() -> void:
	var tree: SceneTree = get_tree()
	_w = {
		"tree": tree,
		"gold": EnemyResourceManager.get_spendable_gold(),
		"wood": EnemyResourceManager.get_spendable_wood(),
		"food_used": EnemyResourceManager.food_current,
		"food_cap": EnemyResourceManager.food_max,
		"free_food": EnemyResourceManager.food_max - EnemyResourceManager.food_current,
		"tier": 1,
		"primary_cc": null,
		"home": Vector3.ZERO,
		"command_centers": [] as Array,
		"farms": 0,
		"farm_constructing": false,
		"altar": null,
		"altar_completed": false,
		"altar_constructing": false,
		"barracks_list": [] as Array,
		"barracks_count": 0,
		"barracks_completed": false,
		"barracks_constructing": false,
		"blacksmith": null,
		"blacksmith_completed": false,
		"blacksmith_constructing": false,
		"stable": null,
		"stable_completed": false,
		"stable_constructing": false,
		"artillery_depot": null,
		"artillery_completed": false,
		"artillery_constructing": false,
		"expansion_cc": null,
		"expansion_constructing": false,
		"workers": [] as Array,
		"idle_workers": [] as Array,
		"gold_workers": 0,
		"wood_workers": 0,
		"building_workers": 0,
		"invalid_job_workers": 0,
		"hero": null,
		"hero_level": 0,
		"hero_training": false,
		"army": [] as Array,
		"spearmen": 0,
		"swordsmen": 0,
		"archers": 0,
		"light_cavalry": 0,
		"heavy_cavalry": 0,
		"cavalry_archers": 0,
		"cannons": 0,
		"player_hero": null,
		"player_army": [] as Array,
		"player_cc": null,
		"player_buildings": [] as Array,
		"our_power": 0.0,
		"player_power": 0.0,
		"active_camps": [] as Array,
	}

	if tree == null:
		return

	var primary_cc: CommandCenter = _resolve_primary_cc()
	_w.primary_cc = primary_cc
	if primary_cc != null:
		_w.home = primary_cc.global_position + HOME_OFFSET
		_w.tier = primary_cc.command_center_tier

	var highest_tier: int = TechTree.get_highest_command_center_tier(ENEMY_TEAM_ID)
	_w.tier = maxi(_w.tier, highest_tier)

	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if not NodeSafety.is_alive_node(node) or not node is Building:
			continue
		var building: Building = node as Building
		var constructing: bool = _is_constructing(building)
		var completed: bool = building.building_state == Building.STATE_COMPLETED

		if building is CommandCenter:
			var cc: CommandCenter = building as CommandCenter
			(_w.command_centers as Array).append(cc)
			if primary_cc != null and cc.get_instance_id() != primary_cc.get_instance_id():
				if constructing:
					_w.expansion_constructing = true
				elif completed:
					_w.expansion_cc = cc
		elif building is Farm:
			if completed:
				_w.farms += 1
			elif constructing:
				_w.farm_constructing = true
		elif building is HeroAltar:
			if completed:
				_w.altar = building
				_w.altar_completed = true
			elif constructing:
				_w.altar_constructing = true
		elif building is Barracks:
			if completed:
				(_w.barracks_list as Array).append(building)
				_w.barracks_count = int(_w.barracks_count) + 1
				_w.barracks_completed = true
			elif constructing:
				_w.barracks_constructing = true
				_w.barracks_count = int(_w.barracks_count) + 1
		elif building is Blacksmith:
			if completed:
				_w.blacksmith = building
				_w.blacksmith_completed = true
			elif constructing:
				_w.blacksmith_constructing = true
		elif building is Stable:
			if completed:
				_w.stable = building
				_w.stable_completed = true
			elif constructing:
				_w.stable_constructing = true
		elif building is ArtilleryDepot:
			if completed:
				_w.artillery_depot = building
				_w.artillery_completed = true
			elif constructing:
				_w.artillery_constructing = true

	if _w.altar_completed and _w.altar != null:
		_w.hero_training = (_w.altar as HeroAltar).is_training_hero()

	_w.hero = HeroProgressionStore.get_living_hero(true)
	if _w.hero == null:
		_w.hero = _scan_enemy_hero(tree)
	if _w.hero != null:
		_w.hero_level = (_w.hero as Hero).level

	for node: Node in tree.get_nodes_in_group(&"enemy_workers"):
		if not node is Worker or not NodeSafety.is_alive_node(node):
			continue
		var worker: Worker = node as Worker
		(_w.workers as Array).append(worker)
		if worker.is_on_construction_trip():
			_w.building_workers += 1
			continue
		if worker.is_enemy_gather_fallback_idle():
			(_w.idle_workers as Array).append(worker)
			continue
		var resource_id: StringName = worker.get_assigned_gather_resource_id()
		if resource_id == &"gold":
			_w.gold_workers += 1
		elif resource_id == &"wood":
			_w.wood_workers += 1
		else:
			## Same classification pass as AI staffing — neither gather nor build nor idle.
			_w.invalid_job_workers += 1

	for node: Node in tree.get_nodes_in_group(&"enemy_combat_units"):
		if not NodeSafety.is_alive_node(node) or not node is Unit:
			continue
		if node is Worker:
			continue
		## Strict AI combat force — never neutrals / "not player".
		if CombatTargetValidation.is_neutral_creep(node):
			continue
		if not CombatTargetValidation.is_enemy_faction(node):
			continue
		if not _is_living_combatant(node):
			continue
		var unit: Unit = node as Unit
		(_w.army as Array).append(unit)
		if unit is Spearman:
			_w.spearmen += 1
		elif unit is Swordsman:
			_w.swordsmen += 1
		elif unit is Archer:
			_w.archers += 1
		elif unit is LightCavalry:
			_w.light_cavalry += 1
		elif unit is HeavyCavalry:
			_w.heavy_cavalry += 1
		elif unit is CavalryArcher:
			_w.cavalry_archers += 1
		elif unit is Cannon:
			_w.cannons += 1

	_w.player_hero = HeroProgressionStore.get_living_hero(false)
	if _w.player_hero != null and not CombatTargetValidation.is_player_faction(_w.player_hero):
		_w.player_hero = null
	## Strict player combat force — NOT ENEMY != PLAYER (neutrals are third).
	for node: Node in tree.get_nodes_in_group(&"units"):
		if not NodeSafety.is_alive_node(node) or not node is Unit:
			continue
		if node is Worker:
			continue
		if not CombatTargetValidation.is_player_faction(node):
			continue
		if not _is_living_combatant(node):
			continue
		(_w.player_army as Array).append(node)
	for node: Node in tree.get_nodes_in_group(&"heroes"):
		if not NodeSafety.is_alive_node(node) or not node is Hero:
			continue
		if not CombatTargetValidation.is_player_faction(node):
			continue
		if not _is_living_combatant(node):
			continue
		if _w.player_hero == null:
			_w.player_hero = node
		if not (_w.player_army as Array).has(node):
			(_w.player_army as Array).append(node)

	for node: Node in tree.get_nodes_in_group(&"player_command_center"):
		if not NodeSafety.is_alive_node(node) or not node is Building:
			continue
		var pb: Building = node as Building
		(_w.player_buildings as Array).append(pb)
		if pb is CommandCenter and _w.player_cc == null:
			_w.player_cc = pb

	_w.our_power = _calc_force_power(_w.army as Array)
	_w.player_power = _calc_force_power(_w.player_army as Array)
	_validate_power_invariants()
	_w.active_camps = CreepCampSafety.collect_active_camps(tree)

	if _chosen_expansion_mine_id != 0:
		if _w.expansion_cc != null or _w.expansion_constructing:
			_chosen_expansion_mine_id = 0
		elif not is_instance_id_valid(_chosen_expansion_mine_id):
			_chosen_expansion_mine_id = 0


# ---------------------------------------------------------------------------
# Economy conditions
# ---------------------------------------------------------------------------

func _staff_abandoned_construction() -> void:
	## Condition only: unfinished enemy building with no valid builder → assign one.
	if _build_manager == null:
		return
	var abandoned: Building = _find_unfinished_building_without_builder()
	if abandoned == null:
		return
	if _build_manager.assign_builder_to(abandoned):
		if OS.is_debug_build():
			push_warning(
				"[AI CONSTRUCTION] Reassigned builder to unfinished %s" % abandoned.name
			)


func _find_unfinished_building_without_builder() -> Building:
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if not node is Building or not NodeSafety.is_alive_node(node):
			continue
		var building: Building = node as Building
		if not building.is_being_constructed():
			continue
		if building.has_assigned_builder():
			continue
		if _has_worker_en_route_to_building(building):
			continue
		return building
	return null


func _has_worker_en_route_to_building(building: Building) -> bool:
	for worker_variant: Variant in _w.workers as Array:
		if not worker_variant is Worker or not NodeSafety.is_alive_node(worker_variant):
			continue
		var worker: Worker = worker_variant as Worker
		if not worker.is_on_construction_trip():
			continue
		if worker.get_build_target() == building:
			return true
	return false


func _maintain_workers() -> void:
	var desired: int = _desired_worker_count()
	var living: int = (_w.workers as Array).size()
	if living >= desired:
		return
	var cc: CommandCenter = _w.primary_cc as CommandCenter
	if cc == null:
		return
	if not cc.can_train_enemy_worker():
		return
	## Keep queue short — one pending worker is enough.
	if cc.get_worker_queue_count() >= 1:
		return
	if _should_reserve_hero_gold() and _w.gold < HeroStats.TRAIN_GOLD_COST + UnitStats.WORKER_GOLD_COST:
		return
	if int(_w.free_food) <= 0:
		return
	cc.try_train_enemy_worker()


func _maintain_worker_distribution() -> void:
	if _gather_manager == null:
		return
	var gatherers: int = int(_w.gold_workers) + int(_w.wood_workers) + (_w.idle_workers as Array).size()
	if gatherers <= 0:
		return

	var desired_gold: int = int(round(float(gatherers) * GOLD_WORKER_RATIO))
	desired_gold = clampi(desired_gold, 1, gatherers)
	var desired_wood: int = gatherers - desired_gold
	if _wood_critically_low():
		desired_wood = maxi(desired_wood, mini(gatherers - 1, desired_wood + 1))
		desired_gold = gatherers - desired_wood

	## Idle workers first — Wood before Gold when Wood is short.
	for worker_variant: Variant in _w.idle_workers as Array:
		if not worker_variant is Worker:
			continue
		var worker: Worker = worker_variant as Worker
		if not NodeSafety.is_alive_node(worker):
			continue
		var prefer_gold: bool = true
		if int(_w.wood_workers) < desired_wood:
			prefer_gold = false
		elif int(_w.gold_workers) < desired_gold:
			prefer_gold = true
		elif _wood_critically_low():
			prefer_gold = false
		if _gather_manager.assign_gather_job(worker, prefer_gold):
			if prefer_gold:
				_w.gold_workers += 1
			else:
				_w.wood_workers += 1

	## If Wood is still under-allocated, move one Gold gatherer (not a constant rip).
	if int(_w.wood_workers) < desired_wood:
		_reassign_one_gold_worker_to_wood()


func _reassign_one_gold_worker_to_wood() -> void:
	if _gather_manager == null:
		return
	for worker_variant: Variant in _w.workers as Array:
		if not worker_variant is Worker:
			continue
		var worker: Worker = worker_variant as Worker
		if not NodeSafety.is_alive_node(worker):
			continue
		if worker.is_on_construction_trip():
			continue
		if worker.get_assigned_gather_resource_id() != &"gold":
			continue
		if _gather_manager.assign_gather_job(worker, false):
			_w.gold_workers = maxi(0, int(_w.gold_workers) - 1)
			_w.wood_workers += 1
			return


func _wood_critically_low() -> bool:
	var wood: int = int(_w.wood)
	if wood >= CRITICAL_WOOD_RESERVE + 80:
		return false
	if not _w.altar_completed and not _w.altar_constructing:
		return wood < BuildingStats.HERO_ALTAR_WOOD_COST
	if not _w.barracks_completed and not _w.barracks_constructing:
		return wood < BuildingStats.BARRACKS_WOOD_COST
	if int(_w.tier) >= 2 and not _w.blacksmith_completed and not _w.blacksmith_constructing:
		return wood < BuildingStats.BLACKSMITH_WOOD_COST
	if int(_w.free_food) <= FOOD_SAFETY_MARGIN and not _w.farm_constructing:
		return wood < BuildingStats.FARM_WOOD_COST
	return wood < CRITICAL_WOOD_RESERVE


func _maintain_food() -> void:
	if int(_w.free_food) > FOOD_SAFETY_MARGIN:
		return
	if _w.farm_constructing:
		return
	if not EnemyResourceManager.can_afford(BuildingStats.FARM_GOLD_COST, BuildingStats.FARM_WOOD_COST):
		return
	if _build_manager == null:
		return
	_build_manager.try_place_farm()


func _ensure_basic_buildings() -> void:
	if _build_manager == null:
		return

	if int(_w.farms) <= 0 and not _w.farm_constructing:
		if EnemyResourceManager.can_afford(BuildingStats.FARM_GOLD_COST, BuildingStats.FARM_WOOD_COST):
			_build_manager.try_place_farm()
			return

	if not _w.altar_completed and not _w.altar_constructing:
		if EnemyResourceManager.can_afford(BuildingStats.HERO_ALTAR_GOLD_COST, BuildingStats.HERO_ALTAR_WOOD_COST):
			_build_manager.try_place_hero_altar()
			return

	if not _w.barracks_completed and not _w.barracks_constructing:
		if EnemyResourceManager.can_afford(BuildingStats.BARRACKS_GOLD_COST, BuildingStats.BARRACKS_WOOD_COST):
			_build_manager.try_place_barracks()


func _ensure_tech_progression() -> void:
	if _build_manager == null:
		return

	## Tier 2 — does not require finishing all creeps.
	if (
		_w.hero != null
		and int(_w.spearmen) >= MIN_EARLY_SPEARMEN
		and _w.altar_completed
		and _w.barracks_completed
		and int(_w.tier) < 2
	):
		var cc: CommandCenter = _w.primary_cc as CommandCenter
		if cc != null and cc.can_try_enemy_upgrade_tier(2):
			cc.try_upgrade_enemy_tier(2)
			return

	## Blacksmith after T2
	if (
		int(_w.tier) >= 2
		and TechTree.can_build_blacksmith(ENEMY_TEAM_ID)
		and not _w.blacksmith_completed
		and not _w.blacksmith_constructing
	):
		if EnemyResourceManager.can_afford(BuildingStats.BLACKSMITH_GOLD_COST, BuildingStats.BLACKSMITH_WOOD_COST):
			_build_manager.try_place_blacksmith()
			return

	## Stable after unlock
	if (
		TechTree.can_build_stable(ENEMY_TEAM_ID)
		and not _w.stable_completed
		and not _w.stable_constructing
	):
		if EnemyResourceManager.can_afford(BuildingStats.STABLE_GOLD_COST, BuildingStats.STABLE_WOOD_COST):
			_build_manager.try_place_stable()
			return

	## Tier 3
	if (
		int(_w.tier) == 2
		and _w.blacksmith_completed
		and (_w.expansion_cc != null or _w.gold >= 2200)
		and int((_w.army as Array).size()) >= 10
		and int((_w.workers as Array).size()) >= DESIRED_WORKERS_T2
	):
		var cc_t3: CommandCenter = _w.primary_cc as CommandCenter
		if cc_t3 != null and cc_t3.can_try_enemy_upgrade_tier(3):
			cc_t3.try_upgrade_enemy_tier(3)
			return

	## Artillery Depot after unlock
	if (
		TechTree.can_build_artillery_depot(ENEMY_TEAM_ID)
		and not _w.artillery_completed
		and not _w.artillery_constructing
	):
		if EnemyResourceManager.can_afford(
			BuildingStats.ARTILLERY_DEPOT_GOLD_COST,
			BuildingStats.ARTILLERY_DEPOT_WOOD_COST
		):
			_build_manager.try_place_artillery_depot()


func _ensure_extra_barracks() -> void:
	if _build_manager == null:
		return
	if int(_w.tier) < 2:
		return
	if int(_w.barracks_count) >= MAX_BARRACKS_DESIRED:
		return
	if not _w.barracks_completed:
		return
	if _w.barracks_constructing:
		return
	if int((_w.workers as Array).size()) < DESIRED_WORKERS_T2 - 2:
		return
	if _w.gold < 400 or _w.wood < 200:
		return
	if not EnemyResourceManager.can_afford(BuildingStats.BARRACKS_GOLD_COST, BuildingStats.BARRACKS_WOOD_COST):
		return
	_build_manager.try_place_barracks()


func _ensure_expansion() -> void:
	if _build_manager == null:
		return
	if int(_w.tier) < 2:
		return
	if _w.expansion_cc != null or _w.expansion_constructing:
		return
	if int((_w.workers as Array).size()) < DESIRED_WORKERS_T2:
		return
	if not EnemyResourceManager.can_afford(
		BuildingStats.COMMAND_CENTER_GOLD_COST,
		BuildingStats.COMMAND_CENTER_WOOD_COST
	):
		return
	if _w.gold < BuildingStats.COMMAND_CENTER_GOLD_COST + 300:
		return

	var mine: GoldMine = _find_expansion_mine()
	if mine == null:
		return
	_chosen_expansion_mine_id = mine.get_instance_id()
	_build_manager.try_place_expansion_at_mine(mine)


func _ensure_upgrades() -> void:
	if _should_reserve_hero_gold():
		return
	if int(_w.free_food) <= FOOD_SAFETY_MARGIN and not _w.farm_constructing:
		return
	if int(_w.tier) < 2:
		return

	if _w.blacksmith_completed and _w.blacksmith != null:
		var blacksmith: Blacksmith = _w.blacksmith as Blacksmith
		if not blacksmith.is_researching():
			for upgrade_id: StringName in UpgradeManager.BLACKSMITH_UPGRADE_ORDER:
				if UpgradeManager.is_enemy_max_level(upgrade_id):
					continue
				if not UpgradeManager.can_enemy_afford_upgrade(upgrade_id):
					continue
				if blacksmith.try_research_upgrade(upgrade_id):
					return

	if _w.stable_completed and _w.stable != null:
		var stable: Stable = _w.stable as Stable
		if not stable.is_researching():
			for upgrade_id: StringName in UpgradeManager.STABLE_UPGRADE_ORDER:
				if UpgradeManager.is_enemy_max_level(upgrade_id):
					continue
				if not UpgradeManager.can_enemy_afford_upgrade(upgrade_id):
					continue
				if stable.try_research_upgrade(upgrade_id):
					return


func _ensure_unit_production() -> void:
	if not _w.barracks_completed:
		return
	if _should_reserve_hero_gold() and _w.gold < HeroStats.TRAIN_GOLD_COST + UnitStats.SPEARMAN_GOLD_COST:
		if _w.hero == null and not _w.hero_training:
			return
	if int(_w.free_food) <= 0:
		return

	var army_size: int = (_w.army as Array).size()
	var desired_spearmen: int = DESIRED_SPEARMEN_T1
	if int(_w.tier) >= 2:
		desired_spearmen = DESIRED_SPEARMEN_T2

	## Produce from every completed Barracks (short queues).
	for barracks_variant: Variant in _w.barracks_list as Array:
		if not barracks_variant is Barracks:
			continue
		var barracks: Barracks = barracks_variant as Barracks
		if barracks.get_enemy_pending_unit_count() >= 2:
			continue

		if int(_w.spearmen) + _count_pending_spearmen(barracks) < desired_spearmen:
			if barracks.try_train_enemy_spearman():
				_w.spearmen += 1
				continue

		if TechTree.can_train_swordsman_or_archer(ENEMY_TEAM_ID):
			if int(_w.swordsmen) < DESIRED_SWORDSMEN:
				if barracks.try_train_enemy_swordsman():
					_w.swordsmen += 1
					continue
			if int(_w.archers) < DESIRED_ARCHERS:
				if barracks.try_train_enemy_archer():
					_w.archers += 1
					continue

		## Keep producing useful core units while economy/food allow — do not stop at 5.
		if army_size < ARMY_SOFT_CAP and _economy_supports_extra_army():
			if TechTree.can_train_swordsman_or_archer(ENEMY_TEAM_ID):
				if int(_w.spearmen) <= int(_w.swordsmen) and int(_w.spearmen) <= int(_w.archers):
					if barracks.try_train_enemy_spearman():
						_w.spearmen += 1
						continue
				elif int(_w.swordsmen) <= int(_w.archers):
					if barracks.try_train_enemy_swordsman():
						_w.swordsmen += 1
						continue
				else:
					if barracks.try_train_enemy_archer():
						_w.archers += 1
						continue
			elif int(_w.spearmen) < ARMY_SOFT_CAP:
				if barracks.try_train_enemy_spearman():
					_w.spearmen += 1
					continue

	if _w.stable_completed and _w.stable != null:
		var stable: Stable = _w.stable as Stable
		if stable.get_enemy_pending_unit_count() < 1:
			var cavalry_count: int = int(_w.light_cavalry) + int(_w.heavy_cavalry)
			if cavalry_count < DESIRED_LIGHT_CAVALRY:
				stable.try_train_enemy_light_cavalry()

	if _w.artillery_completed and _w.artillery_depot != null:
		if int(_w.spearmen) + int(_w.swordsmen) >= 4 and int(_w.cannons) < DESIRED_CANNONS:
			var depot: ArtilleryDepot = _w.artillery_depot as ArtilleryDepot
			if depot.get_enemy_pending_unit_count() < 1:
				depot.try_train_enemy_cannon()


func _economy_supports_extra_army() -> bool:
	if _should_reserve_hero_gold():
		return false
	if int(_w.free_food) <= FOOD_SAFETY_MARGIN and not _w.farm_constructing:
		return false
	if int(_w.tier) < 2 and _w.gold < BuildingStats.CC_TIER_2_GOLD_COST and int(_w.spearmen) >= DESIRED_SPEARMEN_T1:
		## Prefer saving toward T2 once early desired army exists.
		if _w.gold < 500:
			return int(_w.spearmen) < DESIRED_SPEARMEN_T1
	return _w.gold >= UnitStats.SPEARMAN_GOLD_COST + 50


func _ensure_hero() -> void:
	if _w.hero != null or _w.hero_training:
		return
	if not _w.altar_completed or _w.altar == null:
		return
	var altar: HeroAltar = _w.altar as HeroAltar
	if altar.can_train_enemy_hero():
		altar.try_train_enemy_hero()


# ---------------------------------------------------------------------------
# Military conditions
# ---------------------------------------------------------------------------

func _army_below_minimum() -> bool:
	return int(_w.spearmen) < MIN_EARLY_SPEARMEN


func _needs_early_creep() -> bool:
	## Prefer creeping until Hero level 3 OR 3 camps cleared — whichever first.
	if int(_w.hero_level) >= EARLY_HERO_LEVEL_TARGET:
		return false
	if _camps_cleared >= EARLY_CAMPS_REQUIRED:
		return false
	return _useful_creep_exists()


func _find_base_threat() -> Node3D:
	## Purely current reality — no remembered defense.
	var best: Node3D = null
	var best_dist: float = INF
	for entry: Dictionary in _collect_base_threat_entries():
		var dist: float = float(entry.get("dist", INF))
		var unit: Node3D = entry.get("unit") as Node3D
		if unit != null and dist < best_dist:
			best_dist = dist
			best = unit
	return best


func _count_base_threats() -> int:
	## Same living-player-combat filters as `_find_base_threat`.
	var seen: Dictionary = {}
	for entry: Dictionary in _collect_base_threat_entries():
		var unit: Node3D = entry.get("unit") as Node3D
		if unit == null or not NodeSafety.is_alive_node(unit):
			continue
		seen[unit.get_instance_id()] = true
	return seen.size()


func _collect_base_threat_entries() -> Array:
	var bases: Array = _w.command_centers as Array
	if bases.is_empty() and _w.primary_cc != null:
		bases = [_w.primary_cc]

	var candidates: Array = []
	candidates.append_array(_w.player_army as Array)
	if _w.player_hero != null and not candidates.has(_w.player_hero):
		if _is_living_combatant(_w.player_hero):
			candidates.append(_w.player_hero)

	var entries: Array = []
	for base_variant: Variant in bases:
		if not base_variant is Node3D:
			continue
		var base: Node3D = base_variant as Node3D
		if not NodeSafety.is_alive_node(base):
			continue
		for unit_variant: Variant in candidates:
			if not unit_variant is Node3D:
				continue
			var unit: Node3D = unit_variant as Node3D
			if not NodeSafety.is_alive_node(unit):
				continue
			## Base threat = living PLAYER combat only — never neutrals/creeps/AI.
			if not CombatTargetValidation.is_player_faction(unit):
				continue
			if unit is Worker:
				continue
			if not _is_living_combatant(unit):
				continue
			var dist: float = _horizontal_distance(base.global_position, unit.global_position)
			if dist <= DEFENSE_RADIUS:
				entries.append({"unit": unit, "dist": dist})
	return entries


func _should_attack_player() -> bool:
	var army: Array = _w.army as Array
	if army.is_empty():
		return false
	if float(_w.our_power) <= 0.0:
		return false

	var player_army: Array = _w.player_army as Array
	var player_power: float = float(_w.player_power)
	var our_power: float = float(_w.our_power)

	## Do not suicide into a stronger living player force.
	if not player_army.is_empty() and player_power > our_power * 1.15:
		return false

	## Clear superiority — single explicit ratio.
	if our_power >= player_power * ATTACK_POWER_RATIO:
		return true

	## Player has no living combatants and AI has a real army.
	if player_army.is_empty() and army.size() >= MIN_EARLY_SPEARMEN + 1:
		return true

	return false


func _useful_creep_exists() -> bool:
	return _pick_safe_creep_camp() != null


func _creep_with_whole_army() -> void:
	var camp: Node3D = _resolve_creep_camp()
	if camp == null:
		_army_home()
		return

	var living_creep: Node3D = _find_living_creep_in_camp(camp)
	if living_creep == null:
		_army_home()
		return

	if not _has_creep_cohesion(camp.global_position):
		_issue_army_move(camp.global_position, &"attack_move", CMD_CREEP, camp.get_instance_id())
		return

	_whole_army_attack(living_creep, CMD_CREEP)


func _attack_player_with_whole_army() -> void:
	var target: Node3D = _select_player_target()
	if target == null:
		_army_home()
		return

	## Still require live cohesion — never start/continue a player attack solo.
	if not _hero_is_with_army():
		_regroup_whole_army()
		return

	## March spread mid-advance → regroup before anyone sprints alone.
	if not _army_is_cohesive(COHESION_RADIUS):
		_regroup_whole_army()
		return

	var target_pos: Vector3 = target.global_position
	var army_center: Vector3 = _army_centroid()
	var dist_to_target: float = _horizontal_distance(army_center, target_pos)

	## Far from the objective: shared attack-move so speeds do not split the force.
	if dist_to_target > ATTACK_ENGAGE_RADIUS:
		_issue_army_move(target_pos, &"attack_move", CMD_ATTACK_MARCH, target.get_instance_id())
		return

	## Close enough only if the army itself is near — never focus-fire from afar.
	if _army_near_position(target_pos, ATTACK_ENGAGE_RADIUS) * 2 < (_w.army as Array).size():
		_issue_army_move(target_pos, &"attack_move", CMD_ATTACK_MARCH, target.get_instance_id())
		return

	_whole_army_attack(target, CMD_ATTACK)


func _army_home() -> void:
	var home: Vector3 = _w.home as Vector3
	if home == Vector3.ZERO:
		return
	if _army_mostly_near(home, HOME_NEAR_RADIUS):
		return
	_issue_army_move(home, &"move", CMD_HOME, 0)


func _regroup_whole_army() -> void:
	var army: Array = _w.army as Array
	if army.is_empty():
		return

	var destination: Vector3 = _army_centroid()
	## Badly scattered → fall back to home rather than chasing a useless centroid.
	if not _army_is_cohesive(COHESION_RADIUS * 2.0):
		var home: Vector3 = _w.home as Vector3
		if home != Vector3.ZERO:
			destination = home

	if _army_mostly_near(destination, HOME_NEAR_RADIUS):
		return
	_issue_army_move(destination, &"move", CMD_REGROUP, 0)


func _whole_army_attack(target: Node3D, command_kind: StringName) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if not _is_living_combatant(target) and not target is Building:
		return
	var army: Array = _w.army as Array
	var target_id: int = target.get_instance_id()
	if _should_skip_reissue(command_kind, target_id, army):
		return

	for unit_variant: Variant in army:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if not NodeSafety.is_alive_node(unit):
			continue
		unit.command_attack(target)

	_last_command_kind = command_kind
	_last_command_target_id = target_id
	_last_command_army_count = army.size()
	_current_target_id = target_id


# ---------------------------------------------------------------------------
# Live cohesion facts (query only — no stored strategic state)
# ---------------------------------------------------------------------------

func _soldiers_near_hero(radius: float) -> int:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return 0
	var near_count: int = 0
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if unit == hero:
			continue
		if unit is Hero:
			continue
		if not NodeSafety.is_alive_node(unit):
			continue
		if _horizontal_distance(unit.global_position, hero.global_position) <= radius:
			near_count += 1
	return near_count


func _army_near_position(position: Vector3, radius: float) -> int:
	var near_count: int = 0
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Node3D:
			continue
		var unit: Node3D = unit_variant as Node3D
		if not NodeSafety.is_alive_node(unit):
			continue
		if _horizontal_distance(unit.global_position, position) <= radius:
			near_count += 1
	return near_count


func _army_is_cohesive(radius: float) -> bool:
	var army: Array = _w.army as Array
	if army.size() <= 1:
		return true
	var center: Vector3 = _army_centroid()
	var near: int = _army_near_position(center, radius)
	## Most of the force near the centroid = together enough.
	return near * 2 >= army.size()


func _hero_is_with_army() -> bool:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return false

	var non_hero_count: int = _count_soldiers()
	## Hero alone is never a strategic attack force.
	if non_hero_count <= 0:
		return false

	var near_hero: int = _soldiers_near_hero(COHESION_RADIUS)
	var soldiers_ok: bool = (
		near_hero >= MIN_SOLDIERS_NEAR_HERO
		or near_hero * 2 >= non_hero_count
	)
	if not soldiers_ok:
		return false

	## Hero must not be massively ahead of the soldier mass.
	var hero_dist: float = _hero_distance_to_soldier_centroid()
	if hero_dist < 0.0 or hero_dist > COHESION_RADIUS:
		return false
	return true


func _count_soldiers() -> int:
	var count: int = 0
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if unit is Hero:
			continue
		if not NodeSafety.is_alive_node(unit):
			continue
		count += 1
	return count


func _soldier_centroid() -> Vector3:
	var soldier_sum := Vector3.ZERO
	var non_hero_count: int = 0
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if unit is Hero:
			continue
		if not NodeSafety.is_alive_node(unit):
			continue
		non_hero_count += 1
		soldier_sum += unit.global_position
	if non_hero_count <= 0:
		return _w.home as Vector3
	return soldier_sum / float(non_hero_count)


func _hero_distance_to_soldier_centroid() -> float:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return -1.0
	if _count_soldiers() <= 0:
		return -1.0
	return _horizontal_distance(hero.global_position, _soldier_centroid())


# ---------------------------------------------------------------------------
# Army movement / targeting helpers
# ---------------------------------------------------------------------------

func _issue_army_move(
	destination: Vector3,
	order_kind: StringName,
	command_kind: StringName,
	target_id: int
) -> void:
	var army: Array = _w.army as Array
	if army.is_empty():
		return
	if _should_skip_reissue(command_kind, target_id, army):
		return

	var units: Array = []
	for unit_variant: Variant in army:
		if unit_variant is Unit and NodeSafety.is_alive_node(unit_variant):
			units.append(unit_variant)

	if units.is_empty():
		return

	var result: Dictionary = PlayerRouteNavigation.request_group_move(
		units,
		destination,
		order_kind,
		false,
		&"enemy_ai"
	)
	if not bool(result.get("handled", false)):
		for unit_variant: Variant in units:
			var unit: Unit = unit_variant as Unit
			if order_kind == &"attack_move":
				unit.command_attack_move(destination)
			else:
				unit.set_movement_target(destination)

	_last_command_kind = command_kind
	_last_command_target_id = target_id
	_last_command_army_count = army.size()
	_current_target_id = target_id


## Skip reissue only when cache matches AND majority still executes a compatible order.
func _should_skip_reissue(command_kind: StringName, target_id: int, army: Array) -> bool:
	if (
		_last_command_kind != command_kind
		or _last_command_target_id != target_id
		or _last_command_army_count != army.size()
	):
		return false
	return _majority_army_has_compatible_order(command_kind, target_id)


func _majority_army_has_compatible_order(command_kind: StringName, target_id: int) -> bool:
	var army: Array = _w.army as Array
	if army.is_empty():
		return true
	var ok: int = 0
	var living: int = 0
	for unit_variant: Variant in army:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		living += 1
		var unit: Unit = unit_variant as Unit
		if _unit_has_compatible_strategic_order(unit, command_kind, target_id):
			ok += 1
	if living <= 0:
		return true
	return ok * 2 >= living


func _unit_has_compatible_strategic_order(unit: Unit, command_kind: StringName, target_id: int) -> bool:
	## Focus-fire / defend: must still hold the same attack target.
	if command_kind == CMD_ATTACK or command_kind == CMD_DEFEND or command_kind == CMD_CREEP:
		if not ("_attack_target" in unit):
			return unit.has_move_target
		var attack_target: Variant = unit.get("_attack_target")
		if NodeSafety.is_alive_node(attack_target) and attack_target is Object:
			if (attack_target as Object).get_instance_id() == target_id:
				return true
		## Creep/attack march may still be traveling.
		if unit.has_move_target:
			return true
		if "_has_attack_move_destination" in unit and bool(unit.get("_has_attack_move_destination")):
			return true
		return false

	## Move / regroup / attack-march: still pathing or attack-moving.
	if unit.has_move_target:
		return true
	if "_has_attack_move_destination" in unit and bool(unit.get("_has_attack_move_destination")):
		return true
	return false


func _select_player_target() -> Node3D:
	## 1) Nearby player military relative to our army centroid
	var centroid: Vector3 = _army_centroid()
	var nearby: Node3D = _nearest_from_list(_w.player_army as Array, centroid, DEFENSE_RADIUS * 1.5)
	if nearby != null:
		return nearby

	## 2) Player Hero
	if NodeSafety.is_alive_node(_w.player_hero) and _is_living_combatant(_w.player_hero):
		return _w.player_hero as Node3D

	## 3) Player Command Center
	if NodeSafety.is_alive_node(_w.player_cc):
		return _w.player_cc as Node3D

	## 4) Production buildings
	for building_variant: Variant in _w.player_buildings as Array:
		if not building_variant is Building:
			continue
		var building: Building = building_variant as Building
		if not NodeSafety.is_alive_node(building):
			continue
		if building is Barracks or building is Stable or building is ArtilleryDepot or building is HeroAltar:
			return building

	## 5) Any remaining important player building
	for building_variant: Variant in _w.player_buildings as Array:
		if building_variant is Building and NodeSafety.is_alive_node(building_variant):
			return building_variant as Node3D

	return null


func _resolve_creep_camp() -> Node3D:
	## Only continue a prior camp target if it is still an active camp.
	if _current_target_id != 0 and is_instance_id_valid(_current_target_id):
		var existing: Variant = instance_from_id(_current_target_id)
		## Validate before any `is` / cast — freed Object makes `is` itself error.
		if NodeSafety.is_alive_node(existing) and existing is Node3D:
			var existing_camp: Node3D = existing as Node3D
			if _is_active_camp(existing_camp):
				if _find_living_creep_in_camp(existing_camp) != null:
					return existing_camp
				## Committed camp is empty — count the clear, then pick another.
				_camps_cleared += 1
			_current_target_id = 0
			_last_command_kind = CMD_NONE
			_last_command_target_id = 0

	var best: Node3D = _pick_safe_creep_camp()
	if best != null:
		_current_target_id = best.get_instance_id()
	return best


func _pick_safe_creep_camp() -> Node3D:
	var home: Vector3 = _w.home as Vector3
	var best: Node3D = null
	var best_dist: float = INF
	var army_size: int = maxi(1, (_w.army as Array).size())

	for camp_variant: Variant in _w.active_camps as Array:
		## Freed camp refs in the active_camps snapshot must be ignored safely.
		if not NodeSafety.is_alive_node(camp_variant):
			continue
		if not camp_variant is Node3D:
			continue
		var camp: Node3D = camp_variant as Node3D
		var dist: float = _horizontal_distance(home, camp.global_position)
		if dist > CAMP_SEARCH_RANGE:
			continue
		var creep_count: int = _count_living_creeps_in_camp(camp)
		if creep_count <= 0:
			continue
		## Extremely simple safety: skip camps vastly above army size.
		if creep_count > army_size + 4:
			continue
		if dist < best_dist:
			best_dist = dist
			best = camp
	return best


func _is_active_camp(camp: Node3D) -> bool:
	if not NodeSafety.is_alive_node(camp):
		return false
	var camp_id: int = camp.get_instance_id()
	for camp_variant: Variant in _w.active_camps as Array:
		if not NodeSafety.is_alive_node(camp_variant):
			continue
		if not camp_variant is Node3D:
			continue
		if (camp_variant as Node3D).get_instance_id() == camp_id:
			return true
	return false


func _find_living_creep_in_camp(camp: Node3D) -> Node3D:
	if not NodeSafety.is_alive_node(camp):
		return null
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		return null
	var best: Node3D = null
	var best_dist: float = INF
	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		CombatTargetValidation.NEUTRAL_CREEP_GROUP
	):
		## Group cache can retain refs freed later in the same frame — validate first.
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Node3D:
			continue
		var creep: Node3D = node_variant as Node3D
		if not CombatTargetValidation.is_neutral_creep(creep):
			continue
		if CombatTargetValidation.get_target_current_health(creep) <= 0:
			continue
		var dist: float = _horizontal_distance(camp.global_position, creep.global_position)
		if dist <= CAMP_CLEAR_RADIUS and dist < best_dist:
			best_dist = dist
			best = creep
	return best


func _count_living_creeps_in_camp(camp: Node3D) -> int:
	if not NodeSafety.is_alive_node(camp):
		return 0
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		return 0
	var count: int = 0
	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		CombatTargetValidation.NEUTRAL_CREEP_GROUP
	):
		## Lifetime order: is_instance_valid (via NodeSafety) BEFORE any `is` / cast.
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Node3D:
			continue
		var creep: Node3D = node_variant as Node3D
		if not CombatTargetValidation.is_neutral_creep(creep):
			continue
		if CombatTargetValidation.get_target_current_health(creep) <= 0:
			continue
		if _horizontal_distance(camp.global_position, creep.global_position) <= CAMP_CLEAR_RADIUS:
			count += 1
	return count


func _has_creep_cohesion(camp_position: Vector3) -> bool:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return false
	if _horizontal_distance(hero.global_position, camp_position) > COHESION_RADIUS:
		return false

	var near_count: int = 0
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if unit == hero:
			continue
		if not NodeSafety.is_alive_node(unit):
			continue
		if _horizontal_distance(unit.global_position, camp_position) <= COHESION_RADIUS:
			near_count += 1

	if near_count >= MIN_CREEP_SOLDIERS_NEAR:
		return true
	var army_size: int = maxi(1, (_w.army as Array).size() - 1)
	return near_count * 2 >= army_size


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _desired_worker_count() -> int:
	var tier: int = int(_w.tier)
	if _w.expansion_cc != null:
		return DESIRED_WORKERS_EXPANSION
	if tier >= 3:
		return DESIRED_WORKERS_T3
	if tier >= 2:
		return DESIRED_WORKERS_T2
	return DESIRED_WORKERS_T1


func _should_reserve_hero_gold() -> bool:
	if _w.hero != null or _w.hero_training:
		return false
	return _w.altar_completed or _w.altar_constructing


func _is_living_combatant(node: Variant) -> bool:
	if not NodeSafety.is_alive_node(node):
		return false
	if node is Building:
		return true
	return CombatTargetValidation.get_target_current_health(node) > 0


func _army_mostly_near(position: Vector3, radius: float) -> bool:
	var army: Array = _w.army as Array
	if army.is_empty():
		return true
	var near: int = 0
	for unit_variant: Variant in army:
		if unit_variant is Node3D and NodeSafety.is_alive_node(unit_variant):
			if _horizontal_distance((unit_variant as Node3D).global_position, position) <= radius:
				near += 1
	return near * 2 >= army.size()


func _army_centroid() -> Vector3:
	var army: Array = _w.army as Array
	if army.is_empty():
		return _w.home as Vector3
	var sum := Vector3.ZERO
	var count: int = 0
	for unit_variant: Variant in army:
		if unit_variant is Node3D and NodeSafety.is_alive_node(unit_variant):
			sum += (unit_variant as Node3D).global_position
			count += 1
	if count <= 0:
		return _w.home as Vector3
	return sum / float(count)


func _nearest_from_list(nodes: Array, origin: Vector3, max_range: float) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for node_variant: Variant in nodes:
		if not node_variant is Node3D:
			continue
		var node: Node3D = node_variant as Node3D
		if not NodeSafety.is_alive_node(node):
			continue
		if not _is_living_combatant(node):
			continue
		var dist: float = _horizontal_distance(origin, node.global_position)
		if dist <= max_range and dist < best_dist:
			best_dist = dist
			best = node
	return best


func _calc_force_power(units: Array) -> float:
	var total: float = 0.0
	for unit_variant: Variant in units:
		if not unit_variant is Node:
			continue
		var unit: Node = unit_variant as Node
		if not NodeSafety.is_alive_node(unit):
			continue
		if not _is_living_combatant(unit):
			continue
		var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.max_health <= 0:
			continue
		var hp_ratio: float = float(health.current_health) / float(health.max_health)
		total += float(health.max_health) * hp_ratio
		var damage_variant: Variant = unit.get("attack_damage")
		if typeof(damage_variant) == TYPE_INT or typeof(damage_variant) == TYPE_FLOAT:
			total += float(damage_variant) * 12.0
		if unit is Hero:
			total += float((unit as Hero).level) * 40.0
	return total


func _validate_power_invariants() -> void:
	if not OS.is_debug_build():
		return
	var player_count: int = (_w.player_army as Array).size()
	var enemy_count: int = (_w.army as Array).size()
	if player_count > 0 and float(_w.player_power) <= 0.0:
		push_error(
			"[POWER INVARIANT] living player combat units=%d but player_power=0" % player_count
		)
	if enemy_count > 0 and float(_w.our_power) <= 0.0:
		push_error(
			"[POWER INVARIANT] living enemy combat units=%d but our_power=0" % enemy_count
		)


func _finish_military_decision(
	bucket: StringName,
	reason: StringName,
	legacy_priority: StringName,
	_target: Node3D
) -> void:
	_debug_priority = legacy_priority
	_debug_condition_bucket = bucket
	_debug_condition_reason = reason
	_log_condition_change_if_needed()
	_rebuild_debug_overlay_lines()
	_update_debug_overlay()


func _log_condition_change_if_needed() -> void:
	if not OS.is_debug_build():
		return
	if _debug_condition_bucket == _debug_last_logged_condition:
		return
	var previous: String = (
		String(_debug_last_logged_condition)
		if _debug_last_logged_condition != &""
		else "NONE"
	)
	_debug_last_logged_condition = _debug_condition_bucket
	var target_label: String = _strategic_target_label()
	var hero_dist: float = _hero_distance_to_soldier_centroid()
	print(
		"[AI CONDITION] %s -> %s\nenemy_power=%d\nplayer_power=%d\nsoldiers=%d\nnear_hero=%d\nhero_centroid_distance=%.1f\ntarget=%s"
		% [
			previous,
			String(_debug_condition_bucket),
			int(float(_w.our_power)),
			int(float(_w.player_power)),
			_count_soldiers(),
			_soldiers_near_hero(COHESION_RADIUS),
			hero_dist,
			target_label,
		]
	)


func _resolve_debug_target_node() -> Node3D:
	if _current_target_id == 0 or not is_instance_id_valid(_current_target_id):
		return null
	var obj: Object = instance_from_id(_current_target_id)
	if not NodeSafety.is_alive_node(obj):
		return null
	if obj is Node3D:
		return obj as Node3D
	return null


func _strategic_order_label() -> String:
	match _last_command_kind:
		CMD_HOME:
			return "HOME"
		CMD_REGROUP:
			return "MOVE"
		CMD_ATTACK_MARCH:
			return "ATTACK_MOVE"
		CMD_ATTACK, CMD_DEFEND, CMD_CREEP:
			return "ATTACK"
		_:
			return "NONE"


func _strategic_target_label() -> String:
	var target: Node3D = _resolve_debug_target_node()
	if target == null:
		return "NONE"
	var type_name: String = target.get_class()
	if target.get_script() != null:
		var script_path: String = String(target.get_script().resource_path)
		if not script_path.is_empty():
			type_name = script_path.get_file().get_basename()
	return "%s/%s" % [target.name, type_name]


func _target_distance_from_army_centroid() -> float:
	var target: Node3D = _resolve_debug_target_node()
	if target == null:
		return -1.0
	return _horizontal_distance(_army_centroid(), target.global_position)


func _count_unfinished_buildings() -> int:
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		return 0
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if not node is Building or not NodeSafety.is_alive_node(node):
			continue
		var building: Building = node as Building
		if building.is_being_constructed():
			count += 1
	return count


func _count_unfinished_buildings_without_builder() -> int:
	## Same abandonment criteria as `_find_unfinished_building_without_builder`.
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		return 0
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if not node is Building or not NodeSafety.is_alive_node(node):
			continue
		var building: Building = node as Building
		if not building.is_being_constructed():
			continue
		if building.has_assigned_builder():
			continue
		if _has_worker_en_route_to_building(building):
			continue
		count += 1
	return count


func _collect_invariant_warnings(
	player_combat_units: int,
	army_cohesive: bool,
	unfinished_without_builder: int
) -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if player_combat_units > 0 and float(_w.player_power) <= 0.0:
		warnings.append("PLAYER POWER INVALID")
	var attack_intent: bool = (
		_debug_condition_bucket == &"ATTACK_PLAYER"
		or _last_command_kind == CMD_ATTACK_MARCH
		or (
			_last_command_kind == CMD_ATTACK
			and _debug_condition_bucket == &"ATTACK_PLAYER"
		)
	)
	if attack_intent and not army_cohesive:
		warnings.append("SOLO HERO STRATEGIC ATTACK")
	if unfinished_without_builder > 0:
		warnings.append("BUILDING ABANDONED")
	return warnings


func _rebuild_debug_overlay_lines() -> void:
	var soldiers: int = _count_soldiers()
	var near_hero: int = _soldiers_near_hero(COHESION_RADIUS)
	var hero_centroid_dist: float = _hero_distance_to_soldier_centroid()
	var army_cohesive: bool = _hero_is_with_army()
	var threat_count: int = _count_base_threats()
	var base_threatened: bool = threat_count > 0
	var power_says_attack: bool = _should_attack_player()
	var early_creep_needed: bool = _needs_early_creep()
	var useful_creep: bool = _useful_creep_exists()
	var unfinished: int = _count_unfinished_buildings()
	var unfinished_no_builder: int = _count_unfinished_buildings_without_builder()
	var player_combat: int = (_w.player_army as Array).size()
	var target_dist: float = _target_distance_from_army_centroid()
	var hero_yes: String = "YES" if _w.hero != null else "NO"
	var hero_dist_text: String = (
		"-" if hero_centroid_dist < 0.0 else "%.1f" % hero_centroid_dist
	)
	var target_dist_text: String = (
		"-" if target_dist < 0.0 else "%.1f" % target_dist
	)
	var warnings: PackedStringArray = _collect_invariant_warnings(
		player_combat,
		army_cohesive,
		unfinished_no_builder
	)

	var lines: PackedStringArray = PackedStringArray([
		"ENEMY AI",
		"AI CONDITION: %s" % String(_debug_condition_bucket),
		"Why: %s" % String(_debug_condition_reason),
		"Enemy hero: %s" % hero_yes,
		"Enemy soldiers: %d" % soldiers,
		"Player combat units: %d" % player_combat,
		"Enemy power: %d" % int(float(_w.our_power)),
		"Player power: %d" % int(float(_w.player_power)),
		"Attack ratio required: %.2f" % ATTACK_POWER_RATIO,
		"Power says attack: %s" % ("YES" if power_says_attack else "NO"),
		"Soldiers near hero: %d / %d" % [near_hero, soldiers],
		"Hero → army centroid: %s" % hero_dist_text,
		"Army cohesive: %s" % ("YES" if army_cohesive else "NO"),
		"Base threatened: %s" % ("YES" if base_threatened else "NO"),
		"Threat count: %d" % threat_count,
		"Early creep needed: %s" % ("YES" if early_creep_needed else "NO"),
		"Hero level: %d" % int(_w.hero_level),
		"Useful creep camp: %s" % ("YES" if useful_creep else "NO"),
		"Current strategic order: %s" % _strategic_order_label(),
		"Current strategic target: %s" % _strategic_target_label(),
		"Target distance from army centroid: %s" % target_dist_text,
		"Unfinished AI buildings: %d" % unfinished,
		"Unfinished without builder: %d" % unfinished_no_builder,
		"Enemy workers:",
		"gold=%d wood=%d building=%d idle=%d invalid-job=%d"
		% [
			int(_w.gold_workers),
			int(_w.wood_workers),
			int(_w.building_workers),
			(_w.idle_workers as Array).size(),
			int(_w.invalid_job_workers),
		],
	])
	if not warnings.is_empty():
		lines.append("")
		lines.append("WARNINGS:")
		for warning: String in warnings:
			lines.append("- %s" % warning)
	_debug_overlay_lines = lines


func get_debug_overlay_lines() -> PackedStringArray:
	return _debug_overlay_lines


func _count_pending_spearmen(barracks: Barracks) -> int:
	var count: int = 0
	for train_id: StringName in barracks.get_training_queue():
		if train_id == Barracks.TRAIN_ID_SPEARMAN:
			count += 1
	return count


func _is_constructing(building: Building) -> bool:
	var state: StringName = building.building_state
	return (
		state == Building.STATE_UNDER_CONSTRUCTION
		or state == Building.STATE_CONSTRUCTING
	)


func _scan_enemy_hero(tree: SceneTree) -> Hero:
	for node: Node in tree.get_nodes_in_group(&"enemy_combat_units"):
		if node is Hero and NodeSafety.is_alive_node(node) and _is_living_combatant(node):
			return node as Hero
	return null


func _resolve_primary_cc() -> CommandCenter:
	if enemy_command_center_path != NodePath(""):
		var via_path: CommandCenter = get_node_or_null(enemy_command_center_path) as CommandCenter
		if via_path != null and NodeSafety.is_alive_node(via_path):
			return via_path
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if node is CommandCenter and NodeSafety.is_alive_node(node):
			var cc: CommandCenter = node as CommandCenter
			if cc.building_state == Building.STATE_COMPLETED:
				return cc
	return null


func _find_expansion_mine() -> GoldMine:
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		return null
	var primary: CommandCenter = _w.primary_cc as CommandCenter
	var origin: Vector3 = primary.global_position if primary != null else Vector3.ZERO
	var best: GoldMine = null
	var best_dist: float = INF

	for node: Node in tree.get_nodes_in_group(&"gold_mines"):
		if not node is GoldMine:
			continue
		var mine: GoldMine = node as GoldMine
		if not NodeSafety.is_alive_node(mine) or not mine.can_gather():
			continue
		var dist_to_base: float = _horizontal_distance(origin, mine.global_position)
		if dist_to_base < 22.0:
			continue
		if _mine_has_nearby_enemy_cc(mine):
			continue
		if dist_to_base < best_dist:
			best_dist = dist_to_base
			best = mine
	return best


func _mine_has_nearby_enemy_cc(mine: GoldMine) -> bool:
	for cc_variant: Variant in _w.command_centers as Array:
		if not cc_variant is CommandCenter:
			continue
		var cc: CommandCenter = cc_variant as CommandCenter
		if _horizontal_distance(cc.global_position, mine.global_position) <= 22.0:
			return true
	return false


func _resolve_managers() -> void:
	if _build_manager == null:
		if enemy_build_manager_path != NodePath(""):
			_build_manager = get_node_or_null(enemy_build_manager_path) as EnemyBuildManager
		if _build_manager == null and get_parent() != null:
			_build_manager = get_parent().get_node_or_null("EnemyBuildManager") as EnemyBuildManager
	if _gather_manager == null:
		if enemy_gather_manager_path != NodePath(""):
			_gather_manager = get_node_or_null(enemy_gather_manager_path) as EnemyGatherManager
		if _gather_manager == null and get_parent() != null:
			_gather_manager = get_parent().get_node_or_null("EnemyGatherManager") as EnemyGatherManager


func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var dx: float = from_position.x - to_position.x
	var dz: float = from_position.z - to_position.z
	return sqrt(dx * dx + dz * dz)


func _set_priority(priority: StringName) -> void:
	_debug_priority = priority


# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

func _ensure_debug_overlay() -> void:
	if _debug_label != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "EnemyAIDebugLayer"
	layer.layer = 126
	add_child(layer)
	_debug_label = Label.new()
	_debug_label.name = "EnemyAIDebugLabel"
	_debug_label.position = Vector2(10, 10)
	_debug_label.add_theme_font_size_override("font_size", 16)
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	_debug_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_debug_label)


func _update_debug_overlay() -> void:
	if not show_debug_overlay:
		return
	_ensure_debug_overlay()
	if _debug_label == null:
		return
	if _debug_overlay_lines.is_empty():
		_debug_label.text = "ENEMY AI\nAI CONDITION: -"
		return
	_debug_label.text = "\n".join(_debug_overlay_lines)


## Test helpers — expose last winning condition / camps for condition harnesses.
func get_debug_priority() -> StringName:
	return _debug_priority


func get_camps_cleared() -> int:
	return _camps_cleared


func set_camps_cleared_for_test(value: int) -> void:
	_camps_cleared = value


func force_tick_for_test() -> void:
	_ai_tick()


func get_player_army_for_test() -> Array:
	return (_w.player_army as Array).duplicate() if _w.has("player_army") else []


func get_enemy_army_for_test() -> Array:
	return (_w.army as Array).duplicate() if _w.has("army") else []


func get_player_power_for_test() -> float:
	return float(_w.get("player_power", 0.0))


func get_our_power_for_test() -> float:
	return float(_w.get("our_power", 0.0))


func find_base_threat_for_test() -> Node3D:
	_read_live_world()
	return _find_base_threat()


func select_player_target_for_test() -> Node3D:
	_read_live_world()
	return _select_player_target()


func count_neutral_creeps_for_test() -> int:
	return _count_living_neutral_creeps()


func _count_living_neutral_creeps() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	var count: int = 0
	for node_variant: Variant in tree.get_nodes_in_group(CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Node:
			continue
		var node: Node = node_variant as Node
		if not CombatTargetValidation.is_neutral_creep(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		count += 1
	return count


func count_living_creeps_in_camp_for_test(camp: Node3D) -> int:
	_read_live_world()
	return _count_living_creeps_in_camp(camp)


func find_living_creep_in_camp_for_test(camp: Node3D) -> Node3D:
	_read_live_world()
	return _find_living_creep_in_camp(camp)


func pick_safe_creep_camp_for_test() -> Node3D:
	_read_live_world()
	return _pick_safe_creep_camp()
