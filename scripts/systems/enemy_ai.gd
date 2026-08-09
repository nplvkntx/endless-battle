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
const OVERWHELM_POWER_RATIO: float = 1.6
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
var _debug_threat_name: String = "-"

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
	_debug_threat_name = "-"
	_w.clear()


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
		_set_priority(&"HERO")
		_update_debug_overlay()
		return

	if _army_below_minimum():
		_army_home()
		_set_priority(&"BUILD_FORCE")
		_update_debug_overlay()
		return

	var threat: Node3D = _find_base_threat()
	if threat != null:
		_debug_threat_name = threat.name
		_whole_army_attack(threat, CMD_DEFEND)
		_set_priority(&"DEFEND")
		_update_debug_overlay()
		return
	_debug_threat_name = "-"

	## Cohesion before any strategic offense — Hero must not fight alone.
	if not _hero_is_with_army():
		_regroup_whole_army()
		_set_priority(&"REGROUP")
		_update_debug_overlay()
		return

	if _needs_early_creep():
		_creep_with_whole_army()
		_set_priority(&"EARLY_CREEP")
		_update_debug_overlay()
		return

	if _should_attack_player():
		_attack_player_with_whole_army()
		_set_priority(&"ATTACK_PLAYER")
		_update_debug_overlay()
		return

	if _useful_creep_exists():
		_creep_with_whole_army()
		_set_priority(&"EXTRA_CREEP")
		_update_debug_overlay()
		return

	_army_home()
	_set_priority(&"WAIT")
	_update_debug_overlay()


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
	_w.active_camps = CreepCampSafety.collect_active_camps(tree)

	if _chosen_expansion_mine_id != 0:
		if _w.expansion_cc != null or _w.expansion_constructing:
			_chosen_expansion_mine_id = 0
		elif not is_instance_id_valid(_chosen_expansion_mine_id):
			_chosen_expansion_mine_id = 0


# ---------------------------------------------------------------------------
# Economy conditions
# ---------------------------------------------------------------------------

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
	var bases: Array = _w.command_centers as Array
	if bases.is_empty() and _w.primary_cc != null:
		bases = [_w.primary_cc]

	var best: Node3D = null
	var best_dist: float = INF
	var candidates: Array = []
	candidates.append_array(_w.player_army as Array)
	if _w.player_hero != null and not candidates.has(_w.player_hero):
		if _is_living_combatant(_w.player_hero):
			candidates.append(_w.player_hero)

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
			if dist <= DEFENSE_RADIUS and dist < best_dist:
				best_dist = dist
				best = unit
	return best


func _should_attack_player() -> bool:
	if (_w.army as Array).is_empty():
		return false
	## Do not attack suicidally.
	if float(_w.player_power) > float(_w.our_power) * 1.15 and not (_w.player_army as Array).is_empty():
		return false

	if float(_w.our_power) > float(_w.player_power) * OVERWHELM_POWER_RATIO:
		return true
	if float(_w.our_power) > float(_w.player_power) * ATTACK_POWER_RATIO:
		return true
	## Player army almost destroyed.
	if (_w.player_army as Array).is_empty() and (_w.army as Array).size() >= MIN_EARLY_SPEARMEN + 1:
		return true
	## Player Hero dead and AI has a healthy army.
	if (
		_w.player_hero == null
		and (_w.army as Array).size() >= MIN_EARLY_SPEARMEN + 2
		and float(_w.our_power) >= float(_w.player_power)
	):
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

	## Close enough: whole army may focus the live target.
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
	if (
		_last_command_kind == command_kind
		and _last_command_target_id == target_id
		and _last_command_army_count == army.size()
	):
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

	var non_hero_count: int = 0
	var soldier_sum := Vector3.ZERO
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if unit == hero or unit is Hero:
			continue
		if not NodeSafety.is_alive_node(unit):
			continue
		non_hero_count += 1
		soldier_sum += unit.global_position

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
	var soldier_centroid: Vector3 = soldier_sum / float(non_hero_count)
	if _horizontal_distance(hero.global_position, soldier_centroid) > COHESION_RADIUS:
		return false
	return true


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
	if (
		_last_command_kind == command_kind
		and _last_command_target_id == target_id
		and _last_command_army_count == army.size()
	):
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
	_debug_label.position = Vector2(12, 12)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_debug_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_debug_label)


func _update_debug_overlay() -> void:
	if not show_debug_overlay:
		return
	_ensure_debug_overlay()
	if _debug_label == null:
		return

	var hero_text: String = "none"
	if _w.hero != null:
		hero_text = "Paladin L%d" % int(_w.hero_level)

	var target_text: String = "-"
	if _current_target_id != 0 and is_instance_id_valid(_current_target_id):
		var obj: Object = instance_from_id(_current_target_id)
		if obj is Node:
			target_text = (obj as Node).name

	var worker_count: int = (_w.workers as Array).size() if _w.has("workers") else 0
	var desired_workers: int = _desired_worker_count() if _w.has("tier") else 0
	var player_military_count: int = (_w.player_army as Array).size() if _w.has("player_army") else 0
	var enemy_military_count: int = (_w.army as Array).size() if _w.has("army") else 0
	var neutral_creep_count: int = _count_living_neutral_creeps()
	var threat_faction: String = "-"
	if _debug_threat_name != "-":
		threat_faction = "player"
	_debug_label.text = "\n".join(
		PackedStringArray([
			"ENEMY AI",
			"Priority: %s" % String(_debug_priority),
			"Gold: %d" % int(_w.get("gold", 0)),
			"Wood: %d" % int(_w.get("wood", 0)),
			"Food: %d/%d" % [int(_w.get("food_used", 0)), int(_w.get("food_cap", 0))],
			"",
			"Workers: %d / %d" % [worker_count, desired_workers],
			"Gold workers: %d" % int(_w.get("gold_workers", 0)),
			"Wood workers: %d" % int(_w.get("wood_workers", 0)),
			"Tier: %d" % int(_w.get("tier", 1)),
			"",
			"Buildings:",
			"Farm %d" % int(_w.get("farms", 0)),
			"Altar %d" % (1 if bool(_w.get("altar_completed", false)) else 0),
			"Barracks %d" % int(_w.get("barracks_count", 0)),
			"Blacksmith %d" % (1 if bool(_w.get("blacksmith_completed", false)) else 0),
			"Stable %d" % (1 if bool(_w.get("stable_completed", false)) else 0),
			"Artillery %d" % (1 if bool(_w.get("artillery_completed", false)) else 0),
			"",
			"Hero:",
			hero_text,
			"",
			"Army:",
			"Pike %d" % int(_w.get("spearmen", 0)),
			"Sword %d" % int(_w.get("swordsmen", 0)),
			"Archer %d" % int(_w.get("archers", 0)),
			"Cavalry %d" % (
				int(_w.get("light_cavalry", 0)) + int(_w.get("heavy_cavalry", 0))
			),
			"Artillery %d" % int(_w.get("cannons", 0)),
			"",
			"Camps cleared: %d" % _camps_cleared,
			"AI Power: %d" % int(float(_w.get("our_power", 0.0))),
			"Player Power: %d" % int(float(_w.get("player_power", 0.0))),
			"Player military count: %d" % player_military_count,
			"Enemy military count: %d" % enemy_military_count,
			"Neutral creep count: %d" % neutral_creep_count,
			"",
			"Threat: %s" % _debug_threat_name,
			"Threat faction: %s" % threat_faction,
			"Target: %s" % target_text,
		])
	)


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
