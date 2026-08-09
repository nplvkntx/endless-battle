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
## Main-army cohesion — map is ~100 units (-50..50); spear pack diameter ~5 with
## SLOT_SPACING 1.4; Hero 5.4 vs Spearman 4.5 stretches ~0.9m/s. 12m catches
## mid-march separation within a few strategic ticks without spanning half the map.
const COHESION_RADIUS: float = 12.0
## Order-follow tolerance around the shared strategic destination (slots + path noise).
const ORDER_DEST_RADIUS: float = 16.0
## Regroup arrival — Hero/soldiers considered gathered at the cluster point.
const REGROUP_ARRIVE_RADIUS: float = 6.0
## Far attack-move standoff short of the objective (not the Town Center itself).
const ATTACK_APPROACH_STANDOFF: float = 14.0
const ATTACK_ENGAGE_RADIUS: float = 18.0
const CAMP_SEARCH_RANGE: float = 70.0
const ATTACK_POWER_RATIO: float = 1.25
const FOOD_SAFETY_MARGIN: int = 4
const MIN_EARLY_SPEARMEN: int = 5
const MIN_CREEP_SOLDIERS_NEAR: int = 3
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
var _last_command_destination: Vector3 = Vector3.ZERO
var _chosen_expansion_mine_id: int = 0
var _debug_priority: StringName = &"BOOT"
var _debug_condition_bucket: StringName = &"HOME"
var _debug_condition_reason: StringName = &"BOOT"
var _debug_threat_name: String = "-"
var _debug_last_logged_condition: StringName = &""
var _debug_overlay_lines: PackedStringArray = PackedStringArray()
var _debug_following_ok: int = 0
var _debug_following_living: int = 0
var _debug_army_trace_signature: String = ""

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
	_last_command_destination = Vector3.ZERO
	_chosen_expansion_mine_id = 0
	_debug_priority = &"RESET"
	_debug_condition_bucket = &"HOME"
	_debug_condition_reason = &"RESET"
	_debug_threat_name = "-"
	_debug_last_logged_condition = &""
	_debug_overlay_lines = PackedStringArray()
	_debug_following_ok = 0
	_debug_following_living = 0
	_debug_army_trace_signature = ""
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
	## Defense overrides regroup / offense when the base is under real threat.
	var threat: Node3D = _find_base_threat()
	if threat != null:
		_debug_threat_name = threat.name
		_whole_army_attack(threat, CMD_DEFEND)
		_finish_military_decision(&"DEFEND", &"DEFEND", &"DEFEND", threat)
		return
	_debug_threat_name = "-"

	if _w.hero == null:
		_army_home()
		_finish_military_decision(&"HOME", &"HOME_NO_HERO", &"HERO", null)
		return

	if _army_below_minimum():
		_army_home()
		_finish_military_decision(&"HOME", &"HOME_ARMY_SMALL", &"BUILD_FORCE", null)
		return

	## Cohesion before any strategic offense — Hero must not travel alone.
	if not _army_is_together():
		_regroup_army()
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

	## Far from camp: shared travel. Close: local focus-fire as one army.
	if not _has_creep_cohesion(camp.global_position):
		_assert_cohesive_strategic_order(CMD_CREEP)
		_issue_army_move(camp.global_position, &"attack_move", CMD_CREEP, camp.get_instance_id())
		return

	_assert_cohesive_strategic_order(CMD_CREEP)
	_clear_army_strategic_speed_caps()
	_whole_army_attack(living_creep, CMD_CREEP)


func _attack_player_with_whole_army() -> void:
	var target: Node3D = _select_player_target()
	if target == null:
		_army_home()
		return

	## Live cohesion again — never continue a player attack after the force splits.
	if not _army_is_together():
		_regroup_army()
		return

	var target_pos: Vector3 = target.global_position
	var army_center: Vector3 = _main_army_centroid()
	var dist_to_target: float = _horizontal_distance(army_center, target_pos)

	## Far: shared attack-move to an approach point (not direct command_attack across the map).
	if dist_to_target > ATTACK_ENGAGE_RADIUS:
		_assert_cohesive_strategic_order(CMD_ATTACK_MARCH)
		var approach: Vector3 = _compute_attack_approach(target_pos, army_center)
		_issue_army_move(approach, &"attack_move", CMD_ATTACK_MARCH, target.get_instance_id())
		return

	## Close only when the army itself arrived — never focus-fire from afar.
	if _army_near_position(target_pos, ATTACK_ENGAGE_RADIUS) * 2 < (_w.army as Array).size():
		_assert_cohesive_strategic_order(CMD_ATTACK_MARCH)
		var approach_close: Vector3 = _compute_attack_approach(target_pos, army_center)
		_issue_army_move(approach_close, &"attack_move", CMD_ATTACK_MARCH, target.get_instance_id())
		return

	_assert_cohesive_strategic_order(CMD_ATTACK)
	_clear_army_strategic_speed_caps()
	_whole_army_attack(target, CMD_ATTACK)


func _army_home() -> void:
	var home: Vector3 = _w.home as Vector3
	if home == Vector3.ZERO:
		return
	if _army_mostly_near(home, HOME_NEAR_RADIUS):
		_clear_army_strategic_speed_caps()
		return
	_issue_army_move(home, &"move", CMD_HOME, 0)


func _regroup_army() -> void:
	var army: Array = _w.army as Array
	if army.is_empty():
		return

	var soldiers: Array = _get_live_soldiers()
	var destination: Vector3 = _pick_regroup_destination(soldiers)
	var hero: Hero = _w.hero as Hero

	## True regroup complete only when Hero AND main soldiers are at the cluster.
	var hero_ready: bool = (
		hero == null
		or not NodeSafety.is_alive_node(hero)
		or _horizontal_distance(hero.global_position, destination) <= REGROUP_ARRIVE_RADIUS
	)
	var cluster_ready: bool = true
	if not soldiers.is_empty():
		var near_cluster: int = 0
		for unit_variant: Variant in soldiers:
			if not unit_variant is Node3D or not NodeSafety.is_alive_node(unit_variant):
				continue
			if _horizontal_distance((unit_variant as Node3D).global_position, destination) <= COHESION_RADIUS:
				near_cluster += 1
		cluster_ready = near_cluster * 2 >= soldiers.size()

	if hero_ready and cluster_ready:
		return

	_issue_army_move(destination, &"move", CMD_REGROUP, 0)


func _pick_regroup_destination(soldiers: Array) -> Vector3:
	var home: Vector3 = _w.home as Vector3
	if soldiers.is_empty():
		return home if home != Vector3.ZERO else Vector3.ZERO

	var facts: Dictionary = _compute_main_army_facts(soldiers)
	var destination: Vector3 = facts.get("centroid", home) as Vector3

	## Scattered beyond a usable main cluster → fall back home (not toward the player).
	if int(facts.get("main_count", 0)) * 2 < soldiers.size():
		if home != Vector3.ZERO:
			destination = home

	## Never advance the Hero farther toward the player objective while regrouping.
	destination = _clamp_regroup_away_from_player(destination)
	return _nearest_walkable_dest(destination)


func _clamp_regroup_away_from_player(destination: Vector3) -> Vector3:
	var player_ref: Node3D = null
	if NodeSafety.is_alive_node(_w.player_cc):
		player_ref = _w.player_cc as Node3D
	elif NodeSafety.is_alive_node(_w.player_hero):
		player_ref = _w.player_hero as Node3D
	if player_ref == null:
		return destination

	var soldiers: Array = _get_live_soldiers()
	if soldiers.is_empty():
		return destination

	var soldier_center: Vector3 = _average_positions(soldiers)
	var soldier_to_player: float = _horizontal_distance(soldier_center, player_ref.global_position)
	var dest_to_player: float = _horizontal_distance(destination, player_ref.global_position)
	## If the candidate is closer to the player than the soldier mass, pull it back.
	if dest_to_player + 0.5 < soldier_to_player:
		return soldier_center
	return destination


func _compute_attack_approach(target_pos: Vector3, army_center: Vector3) -> Vector3:
	var away: Vector3 = army_center - target_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(1.0, 0.0, 0.0)
	else:
		away = away.normalized()
	var approach: Vector3 = target_pos + away * ATTACK_APPROACH_STANDOFF
	return _nearest_walkable_dest(approach)


func _nearest_walkable_dest(destination: Vector3) -> Vector3:
	if not PlayerRouteNavigation.is_world_walkable(destination):
		return PlayerRouteNavigation.nearest_walkable_world(destination)
	return destination


func _whole_army_attack(target: Node3D, command_kind: StringName) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if not _is_living_combatant(target) and not target is Building:
		return
	var army: Array = _w.army as Array
	var target_id: int = target.get_instance_id()
	if _should_skip_reissue(command_kind, target_id, army, target.global_position):
		return

	_clear_army_strategic_speed_caps()
	for unit_variant: Variant in army:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if not NodeSafety.is_alive_node(unit):
			continue
		unit.command_attack(target)
		unit.record_strategic_order_provenance_for_tests(
			"EnemyAI",
			"ATTACK",
			target.global_position
		)

	_last_command_kind = command_kind
	_last_command_target_id = target_id
	_last_command_army_count = army.size()
	_last_command_destination = target.global_position
	_current_target_id = target_id
	_log_army_trace_if_needed(command_kind, target.global_position)


# ---------------------------------------------------------------------------
# Live cohesion facts (query only — no stored strategic state)
# ---------------------------------------------------------------------------

func _get_live_soldiers() -> Array:
	var soldiers: Array = []
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if unit is Hero:
			continue
		if not NodeSafety.is_alive_node(unit):
			continue
		soldiers.append(unit)
	return soldiers


func _average_positions(nodes: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for node_variant: Variant in nodes:
		if not node_variant is Node3D or not NodeSafety.is_alive_node(node_variant):
			continue
		sum += (node_variant as Node3D).global_position
		count += 1
	if count <= 0:
		return _w.home as Vector3
	return sum / float(count)


func _compute_main_army_facts(soldiers: Array) -> Dictionary:
	var empty := {
		"centroid": _w.home as Vector3,
		"main_count": 0,
		"near_hero": 0,
	}
	if soldiers.is_empty():
		return empty

	var centroid: Vector3 = _average_positions(soldiers)
	var main: Array = []
	for unit_variant: Variant in soldiers:
		if not unit_variant is Node3D or not NodeSafety.is_alive_node(unit_variant):
			continue
		if _horizontal_distance((unit_variant as Node3D).global_position, centroid) <= COHESION_RADIUS:
			main.append(unit_variant)

	## Refine centroid from the majority cluster so one distant reinforcement
	## does not drag the "main army" home.
	if main.size() * 2 >= soldiers.size() and not main.is_empty():
		centroid = _average_positions(main)
		main.clear()
		for unit_variant2: Variant in soldiers:
			if not unit_variant2 is Node3D or not NodeSafety.is_alive_node(unit_variant2):
				continue
			if _horizontal_distance((unit_variant2 as Node3D).global_position, centroid) <= COHESION_RADIUS:
				main.append(unit_variant2)

	var hero: Hero = _w.hero as Hero
	var near_hero: int = 0
	if hero != null and NodeSafety.is_alive_node(hero):
		for unit_variant3: Variant in soldiers:
			if not unit_variant3 is Node3D or not NodeSafety.is_alive_node(unit_variant3):
				continue
			if _horizontal_distance((unit_variant3 as Node3D).global_position, hero.global_position) <= COHESION_RADIUS:
				near_hero += 1

	return {
		"centroid": centroid,
		"main_count": main.size(),
		"near_hero": near_hero,
	}


func _main_army_centroid() -> Vector3:
	var soldiers: Array = _get_live_soldiers()
	if soldiers.is_empty():
		var hero: Hero = _w.hero as Hero
		if hero != null and NodeSafety.is_alive_node(hero):
			return hero.global_position
		return _w.home as Vector3
	return _compute_main_army_facts(soldiers).get("centroid", _w.home) as Vector3


func _soldiers_near_hero(radius: float) -> int:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return 0
	var near_count: int = 0
	for unit_variant: Variant in _get_live_soldiers():
		if not unit_variant is Node3D or not NodeSafety.is_alive_node(unit_variant):
			continue
		if _horizontal_distance((unit_variant as Node3D).global_position, hero.global_position) <= radius:
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


## Majority of combat soldiers within COHESION of the main soldier centroid,
## AND Hero within COHESION of that same centroid.
func _army_is_together() -> bool:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return false

	var soldiers: Array = _get_live_soldiers()
	## Hero alone is never a strategic attack force.
	if soldiers.is_empty():
		return false

	var facts: Dictionary = _compute_main_army_facts(soldiers)
	var main_count: int = int(facts.get("main_count", 0))
	## Main-force majority — one fresh spawn at base must not cancel a cohesive field army,
	## and a tiny escort with Hero must not count while the bulk lags behind.
	if main_count * 2 < soldiers.size():
		return false

	var centroid: Vector3 = facts.get("centroid", hero.global_position) as Vector3
	if _horizontal_distance(hero.global_position, centroid) > COHESION_RADIUS:
		return false
	return true


func _count_soldiers() -> int:
	return _get_live_soldiers().size()


func _soldier_centroid() -> Vector3:
	return _main_army_centroid()


func _hero_distance_to_soldier_centroid() -> float:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return -1.0
	if _count_soldiers() <= 0:
		return -1.0
	return _horizontal_distance(hero.global_position, _main_army_centroid())


func _assert_cohesive_strategic_order(command_kind: StringName) -> void:
	if not OS.is_debug_build():
		return
	if command_kind != CMD_ATTACK and command_kind != CMD_ATTACK_MARCH and command_kind != CMD_CREEP:
		return
	if _army_is_together():
		return
	push_error(
		"INVALID STRATEGIC ORDER: hero/army not cohesive (cmd=%s)" % String(command_kind)
	)


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
	if _should_skip_reissue(command_kind, target_id, army, destination):
		return

	var units: Array = []
	for unit_variant: Variant in army:
		if unit_variant is Unit and NodeSafety.is_alive_node(unit_variant):
			units.append(unit_variant)

	if units.is_empty():
		return

	## Bound Hero strategic travel to the slowest soldier so the pack does not stretch.
	_apply_strategic_speed_caps(units)

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

	var order_label: String = "ATTACK_MOVE" if order_kind == &"attack_move" else "MOVE"
	for unit_variant2: Variant in units:
		var stamped: Unit = unit_variant2 as Unit
		stamped.record_strategic_order_provenance_for_tests("EnemyAI", order_label, destination)

	_last_command_kind = command_kind
	_last_command_target_id = target_id
	_last_command_army_count = army.size()
	_last_command_destination = destination
	_current_target_id = target_id
	_log_army_trace_if_needed(command_kind, destination)


func _apply_strategic_speed_caps(units: Array) -> void:
	var slowest_soldier: float = INF
	for unit_variant: Variant in units:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		var unit: Unit = unit_variant as Unit
		if unit is Hero:
			continue
		slowest_soldier = minf(slowest_soldier, unit.move_speed)

	if slowest_soldier == INF:
		_clear_army_strategic_speed_caps()
		return

	for unit_variant2: Variant in units:
		if not unit_variant2 is Unit or not NodeSafety.is_alive_node(unit_variant2):
			continue
		var member: Unit = unit_variant2 as Unit
		if member is Hero:
			member.set_strategic_move_speed_cap(slowest_soldier)
		else:
			member.clear_strategic_move_speed_cap()


func _clear_army_strategic_speed_caps() -> void:
	for unit_variant: Variant in _w.army as Array:
		if unit_variant is Unit and NodeSafety.is_alive_node(unit_variant):
			(unit_variant as Unit).clear_strategic_move_speed_cap()


## Skip reissue only when cache matches AND the army still executes a compatible order
## toward the expected destination area (idle / drifted units force refresh).
func _should_skip_reissue(
	command_kind: StringName,
	target_id: int,
	army: Array,
	expected_destination: Vector3
) -> bool:
	if (
		_last_command_kind != command_kind
		or _last_command_target_id != target_id
		or _last_command_army_count != army.size()
	):
		return false
	return _army_is_following_command(command_kind, target_id, expected_destination)


func _army_is_following_command(
	command_kind: StringName,
	target_id: int,
	expected_destination: Vector3
) -> bool:
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
		if _unit_has_compatible_strategic_order(unit, command_kind, target_id, expected_destination):
			ok += 1
	_debug_following_ok = ok
	_debug_following_living = living
	if living <= 0:
		return true
	## Require ~75% still on the order — majority alone hid idle pikemen.
	return ok * 4 >= living * 3


func _unit_has_compatible_strategic_order(
	unit: Unit,
	command_kind: StringName,
	target_id: int,
	expected_destination: Vector3
) -> bool:
	## Focus-fire / defend: must still hold the same attack target.
	if command_kind == CMD_ATTACK or command_kind == CMD_DEFEND:
		if not ("_attack_target" in unit):
			return false
		var attack_target: Variant = unit.get("_attack_target")
		if NodeSafety.is_alive_node(attack_target) and attack_target is Object:
			return (attack_target as Object).get_instance_id() == target_id
		return false

	## Creep close-in may be focus-firing the camp creep.
	if command_kind == CMD_CREEP:
		if "_attack_target" in unit:
			var creep_target: Variant = unit.get("_attack_target")
			if NodeSafety.is_alive_node(creep_target) and creep_target is Object:
				if (creep_target as Object).get_instance_id() == target_id:
					return true
		return _unit_destination_near_expected(unit, expected_destination)

	## Move / regroup / attack-march: must still be pathing toward the shared area.
	return _unit_destination_near_expected(unit, expected_destination)


func _unit_destination_near_expected(unit: Unit, expected_destination: Vector3) -> bool:
	if expected_destination == Vector3.ZERO:
		## No dest to compare — require any active travel intent.
		if unit.has_move_target:
			return true
		if "_has_attack_move_destination" in unit and bool(unit.get("_has_attack_move_destination")):
			return true
		return false

	var candidates: Array[Vector3] = []
	if unit.has_move_target:
		candidates.append(unit.get_movement_destination())
	if "_has_attack_move_destination" in unit and bool(unit.get("_has_attack_move_destination")):
		candidates.append(unit.get("_attack_move_destination") as Vector3)
	if unit.has_method("get_player_squad_clicked_destination"):
		var clicked: Vector3 = unit.get_player_squad_clicked_destination()
		if clicked != Vector3.ZERO:
			candidates.append(clicked)

	## Idle with no destination bookkeeping = dropped strategic intent.
	if candidates.is_empty():
		## Already standing inside the expected area counts as following.
		return _horizontal_distance(unit.global_position, expected_destination) <= ORDER_DEST_RADIUS

	for dest: Vector3 in candidates:
		if _horizontal_distance(dest, expected_destination) <= ORDER_DEST_RADIUS:
			return true
	return false


func _log_army_trace_if_needed(command_kind: StringName, destination: Vector3) -> void:
	if not OS.is_debug_build():
		return
	var hero: Hero = _w.hero as Hero
	var pike: Unit = null
	for unit_variant: Variant in _get_live_soldiers():
		if unit_variant is Unit and NodeSafety.is_alive_node(unit_variant):
			pike = unit_variant as Unit
			break

	var hero_order: String = _unit_order_label(hero)
	var pike_order: String = _unit_order_label(pike)
	var hero_dist: float = 0.0
	var pike_dist: float = -1.0
	if hero != null and NodeSafety.is_alive_node(hero) and pike != null:
		pike_dist = _horizontal_distance(pike.global_position, hero.global_position)
	var signature: String = "%s|%s|%s|%.0f|%.0f" % [
		String(command_kind),
		hero_order,
		pike_order,
		destination.x,
		pike_dist,
	]
	if signature == _debug_army_trace_signature:
		return
	_debug_army_trace_signature = signature

	var centroid: Vector3 = _main_army_centroid()
	print(
		"[ARMY TRACE]\ncondition=%s\nunit=%s\norder=%s\nsource=EnemyAI\nhero_distance=%.1f\ndestination=(%.1f, %.1f, %.1f)\ncentroid=(%.1f, %.1f, %.1f)"
		% [
			String(command_kind),
			hero.name if hero != null and NodeSafety.is_alive_node(hero) else "EnemyHero",
			hero_order,
			hero_dist,
			destination.x,
			destination.y,
			destination.z,
			centroid.x,
			centroid.y,
			centroid.z,
		]
	)
	if pike != null and NodeSafety.is_alive_node(pike):
		var pike_source: String = str(pike.get_strategic_order_provenance().get("source", "UNKNOWN"))
		print(
			"[ARMY TRACE]\ncondition=%s\nunit=%s\norder=%s\nsource=%s\nhero_distance=%.1f\ndestination=(%.1f, %.1f, %.1f)"
			% [
				String(command_kind),
				pike.name,
				pike_order,
				pike_source,
				pike_dist,
				destination.x,
				destination.y,
				destination.z,
			]
		)


func _unit_order_label(unit: Unit) -> String:
	if unit == null or not NodeSafety.is_alive_node(unit):
		return "NONE"
	if "_attack_target" in unit and NodeSafety.is_alive_node(unit.get("_attack_target")):
		var committed: bool = false
		if "_committed_attack_order" in unit:
			committed = bool(unit.get("_committed_attack_order"))
		return "ATTACK" if committed else "ATTACK_CHASE"
	if "_has_attack_move_destination" in unit and bool(unit.get("_has_attack_move_destination")):
		return "ATTACK_MOVE"
	if unit.has_move_target:
		return "MOVE"
	return "IDLE"


func _select_player_target() -> Node3D:
	## 1) Nearby player military relative to our main army centroid
	var centroid: Vector3 = _main_army_centroid()
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
	var facts: Dictionary = _compute_main_army_facts(_get_live_soldiers())
	print(
		"[AI] %s -> %s\nhero_to_centroid=%.1f\nsoldiers=%d\nmain_cluster=%d\nenemy_power=%d\nplayer_power=%d\ntarget=%s"
		% [
			previous,
			String(_debug_condition_bucket),
			hero_dist,
			_count_soldiers(),
			int(facts.get("main_count", 0)),
			int(float(_w.our_power)),
			int(float(_w.player_power)),
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
	return _horizontal_distance(_main_army_centroid(), target.global_position)


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
	var offense_intent: bool = (
		_debug_condition_bucket == &"ATTACK_PLAYER"
		or _debug_condition_bucket == &"EARLY_CREEP"
		or _debug_condition_bucket == &"EXTRA_CREEP"
	)
	if offense_intent and not army_cohesive:
		warnings.append("SOLO HERO WARNING")
	if unfinished_without_builder > 0:
		warnings.append("BUILDING ABANDONED")
	return warnings


func _rebuild_debug_overlay_lines() -> void:
	var soldiers: int = _count_soldiers()
	var near_hero: int = _soldiers_near_hero(COHESION_RADIUS)
	var hero_centroid_dist: float = _hero_distance_to_soldier_centroid()
	var army_cohesive: bool = _army_is_together()
	var facts: Dictionary = _compute_main_army_facts(_get_live_soldiers())
	var main_cluster: int = int(facts.get("main_count", 0))
	var centroid: Vector3 = facts.get("centroid", Vector3.ZERO) as Vector3
	var threat_count: int = _count_base_threats()
	var base_threatened: bool = threat_count > 0
	var power_says_attack: bool = _should_attack_player()
	var early_creep_needed: bool = _needs_early_creep()
	var useful_creep: bool = _useful_creep_exists()
	var unfinished: int = _count_unfinished_buildings()
	var unfinished_no_builder: int = _count_unfinished_buildings_without_builder()
	var player_combat: int = (_w.player_army as Array).size()
	var target_dist: float = _target_distance_from_army_centroid()
	var hero: Hero = _w.hero as Hero
	var hero_yes: String = "YES" if hero != null else "NO"
	var hero_pos_text: String = "-"
	if hero != null and NodeSafety.is_alive_node(hero):
		hero_pos_text = "(%.1f, %.1f)" % [hero.global_position.x, hero.global_position.z]
	var hero_dist_text: String = (
		"-" if hero_centroid_dist < 0.0 else "%.1f" % hero_centroid_dist
	)
	var target_dist_text: String = (
		"-" if target_dist < 0.0 else "%.1f" % target_dist
	)
	var pike: Unit = null
	for unit_variant: Variant in _get_live_soldiers():
		if unit_variant is Unit and NodeSafety.is_alive_node(unit_variant):
			pike = unit_variant as Unit
			break
	var hero_order: String = _unit_order_label(hero)
	var pike_order: String = _unit_order_label(pike)
	var hero_source: String = "-"
	var pike_source: String = "-"
	var pike_to_hero: String = "-"
	if hero != null and NodeSafety.is_alive_node(hero):
		hero_source = str(hero.get_strategic_order_provenance().get("source", "UNKNOWN"))
	if pike != null and NodeSafety.is_alive_node(pike):
		pike_source = str(pike.get_strategic_order_provenance().get("source", "UNKNOWN"))
		if hero != null and NodeSafety.is_alive_node(hero):
			pike_to_hero = "%.1f" % _horizontal_distance(pike.global_position, hero.global_position)

	## Refresh follow counts against the last strategic destination.
	if _last_command_kind != CMD_NONE:
		_army_is_following_command(
			_last_command_kind,
			_last_command_target_id,
			_last_command_destination
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
		"Hero pos: %s" % hero_pos_text,
		"Enemy hero: %s" % hero_yes,
		"Soldier count: %d" % soldiers,
		"Enemy power: %d" % int(float(_w.our_power)),
		"Player power: %d" % int(float(_w.player_power)),
		"Main army centroid: (%.1f, %.1f)" % [centroid.x, centroid.z],
		"Hero → centroid: %s" % hero_dist_text,
		"Soldiers in main cluster: %d / %d" % [main_cluster, soldiers],
		"Soldiers near hero: %d / %d" % [near_hero, soldiers],
		"Army cohesive: %s" % ("YES" if army_cohesive else "NO"),
		"Strategic command: %s" % _strategic_order_label(),
		"Strategic target: %s" % _strategic_target_label(),
		"Army following command: %d / %d" % [_debug_following_ok, _debug_following_living],
		"Hero order: %s (%s)" % [hero_order, hero_source],
		"Pike order: %s (%s)" % [pike_order, pike_source],
		"Pike → hero: %s" % pike_to_hero,
		"Attack ratio required: %.2f" % ATTACK_POWER_RATIO,
		"Power says attack: %s" % ("YES" if power_says_attack else "NO"),
		"Base threatened: %s" % ("YES" if base_threatened else "NO"),
		"Threat count: %d" % threat_count,
		"Early creep needed: %s" % ("YES" if early_creep_needed else "NO"),
		"Hero level: %d" % int(_w.hero_level),
		"Useful creep camp: %s" % ("YES" if useful_creep else "NO"),
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


func get_debug_condition_bucket_for_test() -> StringName:
	return _debug_condition_bucket


func is_army_together_for_test() -> bool:
	_read_live_world()
	return _army_is_together()


func get_regroup_destination_for_test() -> Vector3:
	_read_live_world()
	return _pick_regroup_destination(_get_live_soldiers())


func get_main_army_centroid_for_test() -> Vector3:
	_read_live_world()
	return _main_army_centroid()


func get_last_command_kind_for_test() -> StringName:
	return _last_command_kind


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
