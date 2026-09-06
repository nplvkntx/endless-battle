class_name EnemyAI
extends Node

## Brutally simple condition-tick RTS enemy AI.
## Live world facts are memory. Conditions are state. Existing systems execute mechanics.

const TICK_INTERVAL_SECONDS: float = 0.5
const ENEMY_TEAM_ID: int = 1
const DEFENSE_RADIUS: float = 36.0
const DEFENSE_RELEASE_RADIUS: float = 48.0
const DEFENSE_STANDOFF: float = 10.0
const HOME_NEAR_RADIUS: float = 8.0
const COHESION_RADIUS: float = 18.0
const CAMP_CLEAR_RADIUS: float = 14.0
const CAMP_SEARCH_RANGE: float = 70.0
const CREEP_STAGING_STANDOFF: float = 8.0
const ATTACK_APPROACH_STANDOFF: float = 10.0
const ATTACK_POWER_RATIO: float = 1.25
const MIN_EARLY_SPEARMEN: int = 5
const MIN_LATE_COMBAT_UNITS: int = 6
const EARLY_HERO_LEVEL_TARGET: int = 3
const FOOD_SAFETY_MARGIN: int = 4
const GOLD_WORKER_RATIO: float = 0.6
const HOME_OFFSET: Vector3 = Vector3(-2.0, 0.0, 3.0)
const CRITICAL_WOOD_RESERVE: int = 40
const ARMY_SOFT_CAP: int = 36
const HERO_MICRO_INTERVAL: float = 0.3
const T3_ARMY_MINIMUM: int = 8
const T3_WORKER_MINIMUM: int = 18
const T3_GOLD_NEAR_COST: int = BuildingStats.CC_TIER_3_GOLD_COST + 200

const DESIRED_SPEARMEN_T1: int = 9
const DESIRED_SPEARMEN_T2: int = 6
const DESIRED_SWORDSMEN: int = 5
const DESIRED_ARCHERS: int = 5
const DESIRED_LIGHT_CAVALRY: int = 4
const DESIRED_HEAVY_CAVALRY: int = 2
const DESIRED_CAVALRY_ARCHERS: int = 2
const DESIRED_CANNONS: int = 2

const CMD_NONE: StringName = &""
const CMD_HOME: StringName = &"home"
const CMD_DEFEND: StringName = &"defend"
const CMD_REGROUP: StringName = &"regroup"
const CMD_CREEP: StringName = &"creep"
const CMD_ATTACK: StringName = &"attack_player"

const DEBUG_CONDITION_ORDER: Array[StringName] = [
	&"BASE_THREATENED",
	&"HERO_MISSING",
	&"ARMY_TOO_SMALL",
	&"HERO_STUCK",
	&"ARMY_NOT_TOGETHER",
	&"EARLY_CREEP",
	&"ATTACK_PLAYER",
	&"EXTRA_CREEP",
	&"HOME_WAIT",
]
const DEBUG_EVENT_LIMIT: int = 8
const DEBUG_ORDER_HEALTH_WINDOW: float = 10.0
const _AI_BRAIN_PANEL_SCRIPT: GDScript = preload("res://scripts/debug/ai_brain_debug_panel.gd")

@export var enemy_command_center_path: NodePath
@export var enemy_build_manager_path: NodePath
@export var enemy_gather_manager_path: NodePath
@export var show_debug_overlay: bool = false

var _tick_timer: float = 0.0
var _hero_micro_timer: float = 0.0
var _chosen_expansion_mine_id: int = 0
var _last_command_kind: StringName = CMD_NONE
var _last_command_destination: Vector3 = Vector3.ZERO
var _strategic_group_route_requests: int = 0
var _last_condition: StringName = &"BOOT"
var _build_manager: EnemyBuildManager = null
var _gather_manager: EnemyGatherManager = null
var _w: Dictionary = {}

var _debug_enabled: bool = false
var _debug_condition_lines: Array[Dictionary] = []
var _debug_summary: Dictionary = {}
var _debug_events: Array[Dictionary] = []
var _debug_panel: CanvasLayer = null
var _dbg_tick_count: int = 0
var _dbg_threat_dist: float = INF
var _dbg_threat_name: String = ""
var _dbg_soldiers: int = 0
var _dbg_soldiers_near: int = 0
var _dbg_hero_to_centroid: float = 0.0
var _dbg_together_evaluated: bool = false
var _dbg_together: bool = false
var _dbg_army_center: Vector3 = Vector3.ZERO
var _dbg_farthest_name: String = ""
var _dbg_farthest_dist: float = 0.0
var _dbg_last_camp: Node3D = null
var _dbg_attack: Dictionary = {}
var _dbg_defense: Dictionary = {}
var _dbg_order: Dictionary = {}
var _dbg_objective_name: String = ""
var _dbg_objective_type: String = ""
var _dbg_objective_position: Vector3 = Vector3.ZERO
var _dbg_prev_decision: StringName = &""
var _dbg_prev_objective: String = ""
var _dbg_prev_attack: String = ""
var _dbg_prev_together: String = ""
var _dbg_prev_hero_missing: String = ""
var _dbg_prev_threat: String = ""
var _dbg_prev_army_small: String = ""
var _dbg_prev_early_creep: String = ""
var _dbg_prev_t2: String = ""
var _dbg_prev_t3: String = ""
var _dbg_prev_build_intent: String = ""
var _dbg_prev_prod_block: String = ""
var _dbg_prev_ratio_pass: bool = false
var _dbg_tick_prev_decision: StringName = &""
var _dbg_tick_prev_objective: String = ""
var _dbg_macro: Dictionary = {}
var _dbg_army_min: Dictionary = {}
var _dbg_power_ai: Dictionary = {}
var _dbg_power_player: Dictionary = {}
var _dbg_creep: Dictionary = {}
var _dbg_workers: Dictionary = {}
var _dbg_health_samples: Array[Dictionary] = []
var _dbg_unit_orders: Dictionary = {}
var _dbg_unit_order_changes: Array[Dictionary] = []
var _dbg_last_health_warning: String = ""

func _ready() -> void:
	_resolve_managers()
	MatchSession.register_match_reset(&"EnemyAI", reset_match_state)
	set_process(true)
	set_brain_debug(show_debug_overlay)

func reset_match_state() -> void:
	_tick_timer = 0.0
	_hero_micro_timer = 0.0
	_chosen_expansion_mine_id = 0
	_last_command_kind = CMD_NONE
	_last_command_destination = Vector3.ZERO
	_strategic_group_route_requests = 0
	_last_condition = &"RESET"
	_camps_cleared = 0
	_last_command_target_id = 0
	_last_command_army_count = 0
	_w.clear()
	_debug_clear_tick_buffers()
	_debug_events.clear()
	_debug_reset_persistent_trace()
	if _debug_panel != null:
		_debug_panel.call("set_summary_text", "AI BRAIN\n(waiting for tick)")
		_debug_panel.call("set_events_text", "")

func _process(delta: float) -> void:
	_hero_micro_timer += delta
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL_SECONDS:
		return
	_tick_timer = 0.0
	_ai_tick()

func _ai_tick() -> void:
	_resolve_managers()
	_read_live_world()
	if _debug_enabled:
		_debug_begin_tick()

	# Macro ALWAYS runs, independent of military.
	_staff_abandoned_construction()
	_maintain_workers()
	_maintain_worker_distribution()
	_maintain_food()
	_ensure_basic_buildings()
	_ensure_hero()
	_ensure_tech_progression()
	_ensure_extra_military_buildings()
	_ensure_towers()
	_ensure_expansion()
	_ensure_upgrades()
	_ensure_unit_production()
	_use_hero_combat_micro_if_relevant()

	_tick_military()

	if _debug_enabled:
		_debug_finish_tick()


func _tick_military() -> void:
	var threat: Node3D = _find_base_threat()
	var base_threatened: bool = threat != null
	_debug_record_condition(&"BASE_THREATENED", base_threatened, _dbg_defense.duplicate())
	if base_threatened:
		_set_condition(&"DEFEND")
		_defend(threat)
		return

	var hero: Hero = _w.hero as Hero
	var hero_missing: bool = hero == null
	_debug_record_condition(&"HERO_MISSING", hero_missing, {
		"hero_alive": not hero_missing,
	})
	if hero_missing:
		_set_condition(&"HOME_NO_HERO")
		_army_home()
		return

	var army_too_small: bool = _army_below_minimum()
	_debug_record_condition(&"ARMY_TOO_SMALL", army_too_small, _dbg_army_min.duplicate())
	if army_too_small:
		_set_condition(&"HOME_ARMY_SMALL")
		_army_home()
		return

	var hero_stuck: bool = _hero_is_physically_stuck()
	_debug_record_condition(&"HERO_STUCK", hero_stuck, {
		"stuck": hero_stuck,
	})
	if hero_stuck:
		_set_condition(&"HERO_STUCK")
		_free_hero_locally()
		return

	var together: bool = _army_is_together()
	_debug_record_condition(&"ARMY_NOT_TOGETHER", not together, {
		"together": together,
		"hero_to_centroid": _dbg_hero_to_centroid,
		"soldiers_near": _dbg_soldiers_near,
		"soldiers_total": _dbg_soldiers,
		"required_radius": COHESION_RADIUS,
	})
	if not together:
		_set_condition(&"REGROUP")
		_regroup()
		return

	var early_creep: bool = _needs_early_creep()
	_debug_record_condition(&"EARLY_CREEP", early_creep, {
		"hero_level": int(_w.hero_level),
		"goal_level": EARLY_HERO_LEVEL_TARGET,
		"camp": _debug_camp_name(),
	})
	if early_creep:
		_set_condition(&"EARLY_CREEP")
		_creep()
		return

	var attack_player: bool = _should_attack_player()
	_debug_record_condition(&"ATTACK_PLAYER", attack_player, _dbg_attack.duplicate())
	if attack_player:
		_set_condition(&"ATTACK_PLAYER")
		_attack_player_base()
		return

	var extra_camp: Node3D = _find_useful_creep_camp()
	var extra_creep: bool = extra_camp != null
	_debug_record_condition(&"EXTRA_CREEP", extra_creep, {
		"camp": extra_camp.name if extra_camp != null else "",
	})
	if extra_creep:
		_set_condition(&"EXTRA_CREEP")
		_creep()
		return

	_debug_record_condition(&"HOME_WAIT", true, {
		"reason": "all military conditions false",
	})
	_set_condition(&"HOME_WAIT")
	_army_home()


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
		"stable_list": [] as Array,
		"stable_count": 0,
		"stable_completed": false,
		"stable_constructing": false,
		"artillery_depot": null,
		"artillery_list": [] as Array,
		"artillery_count": 0,
		"artillery_completed": false,
		"artillery_constructing": false,
		"towers": 0,
		"tower_constructing": false,
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
				(_w.stable_list as Array).append(building)
				_w.stable_count = int(_w.stable_count) + 1
				_w.stable = building
				_w.stable_completed = true
			elif constructing:
				_w.stable_constructing = true
				_w.stable_count = int(_w.stable_count) + 1
		elif building is ArtilleryDepot:
			if completed:
				(_w.artillery_list as Array).append(building)
				_w.artillery_count = int(_w.artillery_count) + 1
				_w.artillery_depot = building
				_w.artillery_completed = true
			elif constructing:
				_w.artillery_constructing = true
				_w.artillery_count = int(_w.artillery_count) + 1
		elif building is Tower:
			if completed:
				_w.towers = int(_w.towers) + 1
			elif constructing:
				_w.tower_constructing = true
				_w.towers = int(_w.towers) + 1

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
		## Scene defaults / mis-grouped enemy CCs must never count as the player Town Hall.
		if not CombatTargetValidation.is_player_faction(pb):
			continue
		(_w.player_buildings as Array).append(pb)
		if pb is CommandCenter and _w.player_cc == null:
			_w.player_cc = pb

	_w.our_power = _calc_force_power(_w.army as Array, &"ai" if _debug_enabled else &"")
	_w.player_power = _calc_force_power(_w.player_army as Array, &"player" if _debug_enabled else &"")
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
	if _debug_enabled:
		_dbg_macro["abandoned_building"] = abandoned.name if abandoned != null else ""
	if abandoned == null:
		return
	if _build_manager.assign_builder_to(abandoned):
		if OS.is_debug_build():
			push_warning(
				"[AI CONSTRUCTION] Reassigned builder to unfinished %s" % abandoned.name
			)
		_debug_macro_intent("construction", "reassigned builder")


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
	var train: bool = false
	var reason: String = "at desired"
	if living < desired:
		var cc: CommandCenter = _w.primary_cc as CommandCenter
		if cc == null:
			reason = "no CC"
		elif not cc.can_train_enemy_worker():
			reason = "cc cannot train"
		elif cc.get_worker_queue_count() >= 1:
			reason = "queue already has worker"
		elif _should_reserve_hero_gold() and _w.gold < HeroStats.TRAIN_GOLD_COST + UnitStats.WORKER_GOLD_COST:
			reason = "reserve hero gold"
		elif int(_w.free_food) <= 0:
			reason = "no food"
		else:
			train = true
			reason = "below desired"
			cc.try_train_enemy_worker()
	_debug_macro_set("workers", {
		"desired_total": desired,
		"actual": living,
		"train_worker": train,
		"reason": reason,
	})


func _maintain_worker_distribution() -> void:
	if _gather_manager == null:
		_debug_macro_set("distribution", {
			"gold": int(_w.gold_workers),
			"wood": int(_w.wood_workers),
			"target": "60/40",
			"reassignment": "no gather manager",
		})
		return
	var gatherers: int = int(_w.gold_workers) + int(_w.wood_workers) + (_w.idle_workers as Array).size()
	if gatherers <= 0:
		_debug_macro_set("distribution", {
			"gold": int(_w.gold_workers),
			"wood": int(_w.wood_workers),
			"target": "60/40",
			"reassignment": "no gatherers",
		})
		return

	var desired_gold: int = int(round(float(gatherers) * GOLD_WORKER_RATIO))
	desired_gold = clampi(desired_gold, 1, gatherers)
	var desired_wood: int = gatherers - desired_gold
	if _wood_critically_low():
		desired_wood = maxi(desired_wood, mini(gatherers - 1, desired_wood + 1))
		desired_gold = gatherers - desired_wood

	var reassignment: String = "none"
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
				reassignment = "idle→gold"
			else:
				_w.wood_workers += 1
				reassignment = "idle→wood"

	## If Wood is still under-allocated, move one Gold gatherer (not a constant rip).
	if int(_w.wood_workers) < desired_wood:
		var wood_before: int = int(_w.wood_workers)
		_reassign_one_gold_worker_to_wood()
		if int(_w.wood_workers) > wood_before:
			reassignment = "gold→wood"
	_debug_macro_set("distribution", {
		"gold": int(_w.gold_workers),
		"wood": int(_w.wood_workers),
		"desired_gold": desired_gold,
		"desired_wood": desired_wood,
		"target": "60/40",
		"reassignment": reassignment,
	})


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
	if int(_w.tier) >= 2 and int(_w.towers) < AIDifficultyConfig.get_desired_tower_count():
		return wood < BuildingStats.TOWER_WOOD_COST
	if int(_w.free_food) <= FOOD_SAFETY_MARGIN and not _w.farm_constructing:
		return wood < BuildingStats.FARM_WOOD_COST
	return wood < CRITICAL_WOOD_RESERVE


func _maintain_food() -> void:
	var used: int = int(_w.food_used)
	var cap: int = int(_w.food_cap)
	if int(_w.free_food) > FOOD_SAFETY_MARGIN:
		_debug_macro_set("food", {
			"used": used,
			"cap": cap,
			"need_farm": false,
			"can_afford": false,
			"blocked_by": "FOOD_OK",
			"build": false,
		})
		return
	if _w.farm_constructing:
		_debug_macro_set("food", {
			"used": used,
			"cap": cap,
			"need_farm": true,
			"can_afford": false,
			"blocked_by": "FARM_CONSTRUCTING",
			"build": false,
		})
		return
	var can_afford: bool = EnemyResourceManager.can_afford(
		BuildingStats.FARM_GOLD_COST, BuildingStats.FARM_WOOD_COST
	)
	if not can_afford:
		var blocked_by: String = "GOLD"
		if int(_w.wood) < BuildingStats.FARM_WOOD_COST:
			blocked_by = "WOOD"
		_debug_macro_set("food", {
			"used": used,
			"cap": cap,
			"need_farm": true,
			"can_afford": false,
			"blocked_by": blocked_by,
			"build": false,
		})
		return
	if _build_manager == null:
		_debug_macro_set("food", {
			"used": used,
			"cap": cap,
			"need_farm": true,
			"can_afford": true,
			"blocked_by": "NO_BUILD_MANAGER",
			"build": false,
		})
		return
	_build_manager.try_place_farm()
	_debug_macro_intent("farm", "need food")
	_debug_macro_set("food", {
		"used": used,
		"cap": cap,
		"need_farm": true,
		"can_afford": true,
		"blocked_by": "NONE",
		"build": true,
	})


func _ensure_basic_buildings() -> void:
	if _build_manager == null:
		_debug_macro_set("barracks", {
			"wanted": not bool(_w.barracks_completed) and not bool(_w.barracks_constructing),
			"current": int(_w.barracks_count),
			"build": false,
			"reason": "no build manager",
		})
		return

	if int(_w.farms) <= 0 and not _w.farm_constructing:
		if EnemyResourceManager.can_afford(BuildingStats.FARM_GOLD_COST, BuildingStats.FARM_WOOD_COST):
			_build_manager.try_place_farm()
			_debug_macro_intent("farm", "first farm")
			_debug_macro_set("barracks", {
				"wanted": not bool(_w.barracks_completed),
				"current": int(_w.barracks_count),
				"build": false,
				"reason": "waiting first farm",
			})
			return

	if not _w.altar_completed and not _w.altar_constructing:
		if EnemyResourceManager.can_afford(BuildingStats.HERO_ALTAR_GOLD_COST, BuildingStats.HERO_ALTAR_WOOD_COST):
			_build_manager.try_place_hero_altar()
			_debug_macro_intent("hero_altar", "missing altar")
			_debug_macro_set("barracks", {
				"wanted": not bool(_w.barracks_completed),
				"current": int(_w.barracks_count),
				"build": false,
				"reason": "waiting altar",
			})
			return

	var barracks_wanted: bool = not bool(_w.barracks_completed) and not bool(_w.barracks_constructing)
	var barracks_build: bool = false
	var barracks_reason: String = "have barracks" if bool(_w.barracks_completed) or bool(_w.barracks_constructing) else "cannot afford"
	if barracks_wanted:
		if EnemyResourceManager.can_afford(BuildingStats.BARRACKS_GOLD_COST, BuildingStats.BARRACKS_WOOD_COST):
			_build_manager.try_place_barracks()
			barracks_build = true
			barracks_reason = "missing barracks"
			_debug_macro_intent("barracks", "missing barracks")
	_debug_macro_set("barracks", {
		"wanted": barracks_wanted,
		"current": int(_w.barracks_count),
		"build": barracks_build,
		"reason": barracks_reason,
	})


func _ensure_tech_progression() -> void:
	if _build_manager == null:
		_debug_macro_set("t2", {
			"wanted": false,
			"allowed": false,
			"gold_required": BuildingStats.CC_TIER_2_GOLD_COST,
			"wood_required": BuildingStats.CC_TIER_2_WOOD_COST,
			"blocked_by": "NO_BUILD_MANAGER",
		})
		_debug_macro_set("t3", {
			"wanted": false,
			"reason": "no build manager",
			"blocked_by": "NO_BUILD_MANAGER",
		})
		_debug_macro_set("blacksmith", {"wanted": false})
		_debug_macro_set("stable", {"wanted": false})
		_debug_macro_set("artillery", {"wanted": false})
		return

	## Tier 2 — does not require finishing all creeps.
	var t2_wanted: bool = (
		_w.hero != null
		and int(_w.spearmen) >= MIN_EARLY_SPEARMEN
		and _w.altar_completed
		and _w.barracks_completed
		and int(_w.tier) < 2
	)
	if t2_wanted:
		var cc: CommandCenter = _w.primary_cc as CommandCenter
		var t2_allowed: bool = cc != null and cc.can_try_enemy_upgrade_tier(2)
		_debug_macro_set("t2", {
			"wanted": true,
			"allowed": t2_allowed,
			"gold_required": BuildingStats.CC_TIER_2_GOLD_COST,
			"wood_required": BuildingStats.CC_TIER_2_WOOD_COST,
			"blocked_by": "NONE" if t2_allowed else _debug_upgrade_block_reason(cc, 2),
		})
		if t2_allowed:
			cc.try_upgrade_enemy_tier(2)
			_debug_macro_intent("T2", "upgrade")
			return
	else:
		_debug_macro_set("t2", {
			"wanted": false,
			"allowed": false,
			"gold_required": BuildingStats.CC_TIER_2_GOLD_COST,
			"wood_required": BuildingStats.CC_TIER_2_WOOD_COST,
			"blocked_by": _debug_t2_unwanted_reason(),
		})

	## Blacksmith after T2
	var blacksmith_wanted: bool = (
		int(_w.tier) >= 2
		and TechTree.can_build_blacksmith(ENEMY_TEAM_ID)
		and not _w.blacksmith_completed
		and not _w.blacksmith_constructing
	)
	if blacksmith_wanted:
		if EnemyResourceManager.can_afford(BuildingStats.BLACKSMITH_GOLD_COST, BuildingStats.BLACKSMITH_WOOD_COST):
			_build_manager.try_place_blacksmith()
			_debug_macro_set("blacksmith", {"wanted": true, "build": true, "blocked_by": "NONE"})
			_debug_macro_intent("blacksmith", "T2 tech")
			return
		_debug_macro_set("blacksmith", {
			"wanted": true,
			"build": false,
			"blocked_by": _debug_cost_block(
				BuildingStats.BLACKSMITH_GOLD_COST, BuildingStats.BLACKSMITH_WOOD_COST
			),
		})
	else:
		_debug_macro_set("blacksmith", {"wanted": false, "build": false})

	## Stable after unlock
	var stable_wanted: bool = (
		TechTree.can_build_stable(ENEMY_TEAM_ID)
		and not _w.stable_completed
		and not _w.stable_constructing
	)
	if stable_wanted:
		if EnemyResourceManager.can_afford(BuildingStats.STABLE_GOLD_COST, BuildingStats.STABLE_WOOD_COST):
			_build_manager.try_place_stable()
			_debug_macro_set("stable", {"wanted": true, "build": true, "blocked_by": "NONE"})
			_debug_macro_intent("stable", "unlocked")
			return
		_debug_macro_set("stable", {
			"wanted": true,
			"build": false,
			"blocked_by": _debug_cost_block(
				BuildingStats.STABLE_GOLD_COST, BuildingStats.STABLE_WOOD_COST
			),
		})
	else:
		_debug_macro_set("stable", {"wanted": false, "build": false})

	## Tier 3 — economy-stable gate; expansion optional if gold near T3 cost.
	var t3_prereq: bool = (
		int(_w.tier) == 2
		and _w.blacksmith_completed
		and int((_w.army as Array).size()) >= T3_ARMY_MINIMUM
		and int((_w.workers as Array).size()) >= T3_WORKER_MINIMUM
	)
	if t3_prereq:
		var t3_economy_ok: bool = (
			_w.expansion_cc != null
			or _w.gold >= T3_GOLD_NEAR_COST
			or EnemyResourceManager.can_afford(
				BuildingStats.CC_TIER_3_GOLD_COST,
				BuildingStats.CC_TIER_3_WOOD_COST
			)
		)
		if t3_economy_ok:
			var cc_t3: CommandCenter = _w.primary_cc as CommandCenter
			var t3_allowed: bool = cc_t3 != null and cc_t3.can_try_enemy_upgrade_tier(3)
			_debug_macro_set("t3", {
				"wanted": true,
				"allowed": t3_allowed,
				"gold_required": BuildingStats.CC_TIER_3_GOLD_COST,
				"wood_required": BuildingStats.CC_TIER_3_WOOD_COST,
				"blocked_by": "NONE" if t3_allowed else _debug_upgrade_block_reason(cc_t3, 3),
			})
			if t3_allowed:
				cc_t3.try_upgrade_enemy_tier(3)
				_debug_macro_intent("T3", "upgrade")
				return
		else:
			_debug_macro_set("t3", {
				"wanted": false,
				"reason": "economy gate",
				"blocked_by": "ECONOMY",
				"gold_required": BuildingStats.CC_TIER_3_GOLD_COST,
				"wood_required": BuildingStats.CC_TIER_3_WOOD_COST,
			})
	else:
		_debug_macro_set("t3", {
			"wanted": false,
			"reason": _debug_t3_unwanted_reason(),
			"blocked_by": _debug_t3_unwanted_reason(),
			"gold_required": BuildingStats.CC_TIER_3_GOLD_COST,
			"wood_required": BuildingStats.CC_TIER_3_WOOD_COST,
		})

	## Artillery Depot after unlock
	var artillery_wanted: bool = (
		TechTree.can_build_artillery_depot(ENEMY_TEAM_ID)
		and int(_w.artillery_count) < AIDifficultyConfig.get_max_military_buildings(&"artillery_depot")
		and not _w.artillery_constructing
		and (not _w.artillery_completed or int(_w.tier) >= 3)
	)
	if artillery_wanted:
		if EnemyResourceManager.can_afford(
			BuildingStats.ARTILLERY_DEPOT_GOLD_COST,
			BuildingStats.ARTILLERY_DEPOT_WOOD_COST
		):
			_build_manager.try_place_artillery_depot()
			_debug_macro_set("artillery", {"wanted": true, "build": true, "blocked_by": "NONE"})
			_debug_macro_intent("artillery_depot", "unlocked")
		else:
			_debug_macro_set("artillery", {
				"wanted": true,
				"build": false,
				"blocked_by": _debug_cost_block(
					BuildingStats.ARTILLERY_DEPOT_GOLD_COST,
					BuildingStats.ARTILLERY_DEPOT_WOOD_COST
				),
			})
	else:
		_debug_macro_set("artillery", {"wanted": false, "build": false})


func _ensure_extra_military_buildings() -> void:
	if _build_manager == null:
		return
	if int(_w.tier) < 2:
		return
	if int((_w.workers as Array).size()) < AIDifficultyConfig.DESIRED_WORKERS_T2 - 2:
		return

	var max_mil: int = AIDifficultyConfig.get_max_military_buildings()
	if (
		int(_w.barracks_count) < max_mil
		and _w.barracks_completed
		and not _w.barracks_constructing
		and _w.gold >= 400
		and _w.wood >= 200
		and EnemyResourceManager.can_afford(BuildingStats.BARRACKS_GOLD_COST, BuildingStats.BARRACKS_WOOD_COST)
	):
		_build_manager.try_place_barracks()
		_debug_macro_intent("extra_barracks", "T2 extra military")
		_debug_macro_set("barracks", {
			"wanted": true,
			"current": int(_w.barracks_count),
			"build": true,
			"reason": "extra military",
		})
		return

	if (
		TechTree.can_build_stable(ENEMY_TEAM_ID)
		and int(_w.stable_count) < max_mil
		and (_w.stable_completed or int(_w.stable_count) > 0)
		and not _w.stable_constructing
		and int(_w.tier) >= 2
		and _w.gold >= 450
		and EnemyResourceManager.can_afford(BuildingStats.STABLE_GOLD_COST, BuildingStats.STABLE_WOOD_COST)
	):
		_build_manager.try_place_stable()
		_debug_macro_intent("extra_stable", "T2 extra military")
		_debug_macro_set("stable", {"wanted": true, "build": true, "reason": "extra military"})
		return

	if (
		int(_w.tier) >= 3
		and TechTree.can_build_artillery_depot(ENEMY_TEAM_ID)
		and int(_w.artillery_count) < max_mil
		and _w.artillery_completed
		and not _w.artillery_constructing
		and _w.gold >= 500
		and EnemyResourceManager.can_afford(
			BuildingStats.ARTILLERY_DEPOT_GOLD_COST,
			BuildingStats.ARTILLERY_DEPOT_WOOD_COST
		)
	):
		_build_manager.try_place_artillery_depot()
		_debug_macro_intent("extra_artillery", "T3 extra military")
		_debug_macro_set("artillery", {"wanted": true, "build": true, "reason": "extra military"})


func _ensure_towers() -> void:
	if _build_manager == null:
		_debug_macro_set("tower", {"wanted": false, "reason": "no build manager"})
		return
	if int(_w.tier) < 2:
		_debug_macro_set("tower", {"wanted": false, "reason": "need T2"})
		return
	if int(_w.towers) >= AIDifficultyConfig.get_desired_tower_count():
		_debug_macro_set("tower", {"wanted": false, "reason": "at desired count"})
		return
	if _w.tower_constructing:
		_debug_macro_set("tower", {"wanted": true, "reason": "constructing"})
		return
	## Do not block T2 / Hero / critical buildings.
	if int(_w.tier) < 2 and _w.gold < BuildingStats.CC_TIER_2_GOLD_COST:
		_debug_macro_set("tower", {"wanted": false, "reason": "reserve T2 gold"})
		return
	if _should_reserve_hero_gold():
		_debug_macro_set("tower", {"wanted": false, "reason": "reserve hero gold"})
		return
	if not EnemyResourceManager.can_afford(BuildingStats.TOWER_GOLD_COST, BuildingStats.TOWER_WOOD_COST):
		_debug_macro_set("tower", {
			"wanted": true,
			"reason": _debug_cost_block(BuildingStats.TOWER_GOLD_COST, BuildingStats.TOWER_WOOD_COST),
		})
		return
	if _w.gold < BuildingStats.TOWER_GOLD_COST + 150:
		_debug_macro_set("tower", {"wanted": true, "reason": "gold buffer"})
		return
	var toward: Vector3 = Vector3.INF
	if _w.player_cc != null and NodeSafety.is_alive_node(_w.player_cc):
		toward = (_w.player_cc as Node3D).global_position
	_build_manager.try_place_tower(toward)
	_debug_macro_intent("tower", "T2 defense")
	_debug_macro_set("tower", {"wanted": true, "reason": "placed"})


func _ensure_expansion() -> void:
	if _build_manager == null:
		_debug_macro_set("expansion", {"wanted": false, "reason": "no build manager"})
		return
	if int(_w.tier) < 2:
		_debug_macro_set("expansion", {"wanted": false, "reason": "need T2"})
		return
	if _w.expansion_cc != null or _w.expansion_constructing:
		_debug_macro_set("expansion", {"wanted": false, "reason": "already expanding"})
		return
	if int((_w.workers as Array).size()) < AIDifficultyConfig.DESIRED_WORKERS_T2:
		_debug_macro_set("expansion", {"wanted": false, "reason": "workers"})
		return
	if not EnemyResourceManager.can_afford(
		BuildingStats.COMMAND_CENTER_GOLD_COST,
		BuildingStats.COMMAND_CENTER_WOOD_COST
	):
		_debug_macro_set("expansion", {
			"wanted": true,
			"reason": _debug_cost_block(
				BuildingStats.COMMAND_CENTER_GOLD_COST,
				BuildingStats.COMMAND_CENTER_WOOD_COST
			),
		})
		return
	if _w.gold < BuildingStats.COMMAND_CENTER_GOLD_COST + 300:
		_debug_macro_set("expansion", {"wanted": true, "reason": "gold buffer"})
		return

	var mine: GoldMine = _find_expansion_mine()
	if mine == null:
		_debug_macro_set("expansion", {"wanted": true, "reason": "no expansion mine"})
		return
	_chosen_expansion_mine_id = mine.get_instance_id()
	_build_manager.try_place_expansion_at_mine(mine)
	_debug_macro_intent("expansion", mine.name)
	_debug_macro_set("expansion", {"wanted": true, "reason": "placing at mine"})


func _ensure_upgrades() -> void:
	if _should_reserve_hero_gold():
		return
	if int(_w.free_food) <= FOOD_SAFETY_MARGIN and not _w.farm_constructing:
		return
	if int(_w.tier) < 2:
		return
	## Prefer a minimum army before draining gold into upgrades.
	if int((_w.army as Array).size()) < MIN_EARLY_SPEARMEN + 2 and _w.gold < 600:
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

	for stable_variant: Variant in _w.stable_list as Array:
		if not stable_variant is Stable:
			continue
		var stable: Stable = stable_variant as Stable
		if not NodeSafety.is_alive_node(stable):
			continue
		if stable.is_researching():
			continue
		for upgrade_id2: StringName in UpgradeManager.STABLE_UPGRADE_ORDER:
			if UpgradeManager.is_enemy_max_level(upgrade_id2):
				continue
			if not UpgradeManager.can_enemy_afford_upgrade(upgrade_id2):
				continue
			if stable.try_research_upgrade(upgrade_id2):
				return


func _ensure_unit_production() -> void:
	if not _w.barracks_completed:
		_debug_macro_set("production", {
			"wanted_unit": "",
			"train": false,
			"reason": "no barracks",
		})
		return
	if _should_reserve_hero_gold() and _w.gold < HeroStats.TRAIN_GOLD_COST + UnitStats.SPEARMAN_GOLD_COST:
		if _w.hero == null and not _w.hero_training:
			_debug_macro_set("production", {
				"wanted_unit": "",
				"train": false,
				"reason": "reserve hero gold",
				"blocked_by": "HERO_GOLD",
			})
			return
	if int(_w.free_food) <= 0:
		_debug_macro_set("production", {
			"wanted_unit": "",
			"train": false,
			"reason": "no food",
			"blocked_by": "FOOD",
		})
		return

	var army_size: int = (_w.army as Array).size()
	var desired_spearmen: int = DESIRED_SPEARMEN_T1
	if int(_w.tier) >= 2:
		desired_spearmen = DESIRED_SPEARMEN_T2
	var trained: String = ""
	var wanted: String = ""
	var blocked: String = ""

	## Produce from every completed Barracks (short queues).
	for barracks_variant: Variant in _w.barracks_list as Array:
		if not barracks_variant is Barracks:
			continue
		var barracks: Barracks = barracks_variant as Barracks
		if barracks.get_enemy_pending_unit_count() >= 2:
			if blocked.is_empty():
				blocked = "queue"
			continue

		if int(_w.spearmen) + _count_pending_spearmen(barracks) < desired_spearmen:
			if wanted.is_empty():
				wanted = "Spearman"
			if barracks.try_train_enemy_spearman():
				_w.spearmen += 1
				trained = "Spearman"
				continue

		if TechTree.can_train_swordsman_or_archer(ENEMY_TEAM_ID):
			if int(_w.swordsmen) < DESIRED_SWORDSMEN:
				if wanted.is_empty():
					wanted = "Swordsman"
				if barracks.try_train_enemy_swordsman():
					_w.swordsmen += 1
					trained = "Swordsman"
					continue
			if int(_w.archers) < DESIRED_ARCHERS:
				if wanted.is_empty():
					wanted = "Archer"
				if barracks.try_train_enemy_archer():
					_w.archers += 1
					trained = "Archer"
					continue

		## Keep producing useful core units while economy/food allow — do not stop at 5.
		if army_size < ARMY_SOFT_CAP and _economy_supports_extra_army():
			if TechTree.can_train_swordsman_or_archer(ENEMY_TEAM_ID):
				if int(_w.spearmen) <= int(_w.swordsmen) and int(_w.spearmen) <= int(_w.archers):
					if wanted.is_empty():
						wanted = "Spearman"
					if barracks.try_train_enemy_spearman():
						_w.spearmen += 1
						trained = "Spearman"
						continue
				elif int(_w.swordsmen) <= int(_w.archers):
					if wanted.is_empty():
						wanted = "Swordsman"
					if barracks.try_train_enemy_swordsman():
						_w.swordsmen += 1
						trained = "Swordsman"
						continue
				else:
					if wanted.is_empty():
						wanted = "Archer"
					if barracks.try_train_enemy_archer():
						_w.archers += 1
						trained = "Archer"
						continue
			elif int(_w.spearmen) < ARMY_SOFT_CAP:
				if wanted.is_empty():
					wanted = "Spearman"
				if barracks.try_train_enemy_spearman():
					_w.spearmen += 1
					trained = "Spearman"
					continue

	for stable_variant: Variant in _w.stable_list as Array:
		if not stable_variant is Stable:
			continue
		var stable_prod: Stable = stable_variant as Stable
		if not NodeSafety.is_alive_node(stable_prod):
			continue
		if stable_prod.get_enemy_pending_unit_count() >= 1:
			continue
		var light: int = int(_w.light_cavalry)
		var heavy: int = int(_w.heavy_cavalry)
		var cav_archers: int = int(_w.cavalry_archers)
		if light < DESIRED_LIGHT_CAVALRY:
			if wanted.is_empty():
				wanted = "LightCavalry"
			if stable_prod.try_train_enemy_light_cavalry():
				_w.light_cavalry += 1
				trained = "LightCavalry"
				continue
		if int(_w.tier) >= 2 and heavy < DESIRED_HEAVY_CAVALRY:
			if wanted.is_empty():
				wanted = "HeavyCavalry"
			if stable_prod.try_train_enemy_heavy_cavalry():
				_w.heavy_cavalry += 1
				trained = "HeavyCavalry"
				continue
		if int(_w.tier) >= 2 and cav_archers < DESIRED_CAVALRY_ARCHERS:
			if wanted.is_empty():
				wanted = "CavalryArcher"
			if stable_prod.try_train_enemy_cavalry_archer():
				_w.cavalry_archers += 1
				trained = "CavalryArcher"
				continue

	for depot_variant: Variant in _w.artillery_list as Array:
		if not depot_variant is ArtilleryDepot:
			continue
		var depot: ArtilleryDepot = depot_variant as ArtilleryDepot
		if not NodeSafety.is_alive_node(depot):
			continue
		if int(_w.spearmen) + int(_w.swordsmen) < 4:
			continue
		if int(_w.cannons) >= DESIRED_CANNONS:
			continue
		if depot.get_enemy_pending_unit_count() >= 1:
			continue
		if depot.try_train_enemy_cannon():
			_w.cannons += 1
			trained = "Cannon"
			wanted = "Cannon" if wanted.is_empty() else wanted
	_debug_macro_set("production", {
		"wanted_unit": trained if not trained.is_empty() else wanted,
		"train": not trained.is_empty(),
		"trained_unit": trained,
		"can_afford": trained.is_empty() == false or blocked != "FOOD",
		"queue_available": blocked != "queue",
		"blocked_by": "" if not trained.is_empty() else blocked,
		"reason": "trained %s" % trained if not trained.is_empty() else ("wanted %s" % wanted if not wanted.is_empty() else "no train this tick"),
	})


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
		_debug_macro_set("hero", {
			"exists": _w.hero != null,
			"train_hero": false,
			"reason": "already alive" if _w.hero != null else "already training",
		})
		return
	if not _w.altar_completed or _w.altar == null:
		_debug_macro_set("hero", {
			"exists": false,
			"train_hero": false,
			"reason": "no altar",
		})
		return
	var altar: HeroAltar = _w.altar as HeroAltar
	if altar.can_train_enemy_hero():
		altar.try_train_enemy_hero()
		_debug_macro_set("hero", {
			"exists": false,
			"train_hero": true,
			"reason": "altar ready",
		})
		_debug_macro_intent("hero", "train")
	else:
		_debug_macro_set("hero", {
			"exists": false,
			"train_hero": false,
			"reason": "altar cannot train",
		})


func _use_hero_combat_micro_if_relevant() -> void:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return
	## Spend ability points deterministically (kit priority).
	while hero.ability_points > 0:
		if not hero.try_ai_spend_ability_point():
			break
	if _hero_micro_timer < HERO_MICRO_INTERVAL:
		return
	_hero_micro_timer = 0.0
	if not hero.has_method(&"try_ai_cast_abilities"):
		return
	hero.call(&"try_ai_cast_abilities", _build_hero_ability_context(hero))


func _build_hero_ability_context(hero: Hero) -> Dictionary:
	var health_ratio: float = 1.0
	var hc: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
	if hc != null and hc.max_health > 0:
		health_ratio = float(hc.current_health) / float(hc.max_health)
	var nearby_enemies: int = 0
	var attack_target: Node3D = null
	if hero is MeleeHero:
		attack_target = (hero as MeleeHero).get_attack_target()
	var tree: SceneTree = _w.tree as SceneTree
	if tree != null:
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
			tree,
			CombatTargetValidation.NEUTRAL_CREEP_GROUP
		):
			if not NodeSafety.is_alive_node(node_variant) or not node_variant is Node3D:
				continue
			var creep: Node3D = node_variant as Node3D
			if _horizontal_distance(hero.global_position, creep.global_position) <= 8.0:
				nearby_enemies += 1
		for unit_variant: Variant in _w.player_army as Array:
			if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Node3D:
				continue
			if _horizontal_distance(hero.global_position, (unit_variant as Node3D).global_position) <= 8.0:
				nearby_enemies += 1
	return {
		"health_ratio": health_ratio,
		"nearby_enemy_count": nearby_enemies,
		"aoe_needed": 3,
		"defensive_hp_ratio": 0.4,
		"retreating": _last_command_kind == CMD_HOME or _last_command_kind == CMD_REGROUP,
		"current_target": attack_target,
		"allied_army_nearby": _soldiers_near_hero(COHESION_RADIUS),
	}


# ---------------------------------------------------------------------------
# Military conditions
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Military — small live conditions only
# ---------------------------------------------------------------------------

func _army_below_minimum() -> bool:
	var soldiers: Array = _get_live_soldiers()
	var below: bool
	var minimum: int
	if int(_w.tier) < 2:
		minimum = MIN_EARLY_SPEARMEN
		below = int(_w.spearmen) < MIN_EARLY_SPEARMEN
	else:
		minimum = MIN_LATE_COMBAT_UNITS
		below = soldiers.size() < MIN_LATE_COMBAT_UNITS
	if _debug_enabled:
		_dbg_army_min = {
			"soldiers": soldiers.size(),
			"spearmen": int(_w.spearmen),
			"minimum": minimum,
			"tier": int(_w.tier),
			"below": below,
		}
	return below


func _needs_early_creep() -> bool:
	if int(_w.hero_level) >= EARLY_HERO_LEVEL_TARGET:
		if _debug_enabled:
			_dbg_creep["early_creep_needed"] = false
			_dbg_creep["hero_level"] = int(_w.hero_level)
			_dbg_creep["hero_level_goal"] = EARLY_HERO_LEVEL_TARGET
		return false
	var camp: Node3D = _find_useful_creep_camp()
	var needed: bool = camp != null
	if _debug_enabled:
		_dbg_creep["early_creep_needed"] = needed
		_dbg_creep["hero_level"] = int(_w.hero_level)
		_dbg_creep["hero_level_goal"] = EARLY_HERO_LEVEL_TARGET
	return needed

func _defense_scan_radius() -> float:
	if _last_command_kind == CMD_DEFEND:
		return DEFENSE_RELEASE_RADIUS
	return DEFENSE_RADIUS


func _find_base_threat() -> Node3D:
	var scan_radius: float = _defense_scan_radius()
	var currently_defending: bool = _last_command_kind == CMD_DEFEND
	var best: Node3D = null
	var best_base: Node3D = null
	var best_dist: float = INF
	var nearest_any: float = INF
	var nearest_any_unit: Node3D = null
	var bases: Array = _w.command_centers as Array
	if bases.is_empty() and _w.primary_cc != null:
		bases = [_w.primary_cc]
	for base_v: Variant in bases:
		if not base_v is Node3D or not NodeSafety.is_alive_node(base_v):
			continue
		var base: Node3D = base_v as Node3D
		for unit_v: Variant in _w.player_army as Array:
			if not unit_v is Node3D or not NodeSafety.is_alive_node(unit_v):
				continue
			var unit: Node3D = unit_v as Node3D
			if not CombatTargetValidation.is_player_faction(unit):
				continue
			var d: float = _horizontal_distance(base.global_position, unit.global_position)
			if d < nearest_any:
				nearest_any = d
				nearest_any_unit = unit
			if d <= scan_radius and d < best_dist:
				best_dist = d
				best = unit
				best_base = base
	var hysteresis: bool = (
		currently_defending
		and best != null
		and nearest_any > DEFENSE_RADIUS
	)
	_dbg_defense = {
		"nearest_threat": nearest_any,
		"required": scan_radius,
		"entry_radius": DEFENSE_RADIUS,
		"release_radius": DEFENSE_RELEASE_RADIUS,
		"currently_defending": currently_defending,
		"hysteresis": hysteresis,
		"reason": "DEFENSE_RELEASE_HYSTERESIS" if hysteresis else "",
		"threat_name": best.name if best != null else (nearest_any_unit.name if nearest_any_unit != null else ""),
		"threatened_base": best_base.name if best_base != null else "",
	}
	if _debug_enabled:
		_dbg_threat_dist = nearest_any
		_dbg_threat_name = String(_dbg_defense.get("threat_name", ""))
	return best

func _should_attack_player() -> bool:
	var army_size: int = (_w.army as Array).size()
	var target: Node3D = _get_player_base_target()
	if target == null:
		if _debug_enabled:
			_debug_store_attack(false, &"NO_PLAYER_TARGET", 0, army_size)
		return false
	if (_w.army as Array).is_empty() or float(_w.our_power) <= 0.0:
		if _debug_enabled:
			var blocked: StringName = &"NO_ARMY" if (_w.army as Array).is_empty() else &"NO_POWER"
			_debug_store_attack(false, blocked, 0, army_size)
		return false
	var player_army: Array = _w.player_army as Array
	var player_power: float = float(_w.player_power)
	var our_power: float = float(_w.our_power)
	if player_army.is_empty():
		var soldiers: int = _get_live_soldiers().size()
		var enough_army: bool = soldiers >= MIN_LATE_COMBAT_UNITS
		if _debug_enabled:
			_debug_store_attack(enough_army, &"" if enough_army else &"MIN_ARMY", soldiers, army_size)
		return enough_army
	var strong_enough: bool = our_power >= player_power * ATTACK_POWER_RATIO
	if _debug_enabled:
		_debug_store_attack(strong_enough, &"" if strong_enough else &"POWER_RATIO", 0, army_size)
	return strong_enough

func _defend(threat: Node3D) -> void:
	if not NodeSafety.is_alive_node(threat):
		return
	var base: Node3D = _nearest_own_command_center(threat.global_position)
	if base == null or not NodeSafety.is_alive_node(base):
		return
	var dest: Vector3 = _defense_intercept_point(base, threat)
	_debug_set_objective(base)
	if _debug_enabled:
		_dbg_objective_type = "THREATENED_BASE"
	_dbg_defense["threatened_base"] = base.name
	_dbg_defense["threat_name"] = threat.name
	_dbg_defense["strategic_point"] = dest
	_dbg_defense["point_type"] = "base_intercept"
	_dbg_defense["threat_position"] = threat.global_position
	_dbg_defense["threat_position_is_not_route_target"] = true
	_issue_army_move(dest, &"attack_move", CMD_DEFEND, base.get_instance_id())

func _army_home() -> void:
	var home: Vector3 = _w.home as Vector3
	if home == Vector3.ZERO:
		return
	if _majority_near(home, HOME_NEAR_RADIUS):
		_remember_strategic_command(CMD_HOME, home, (_w.army as Array).size(), 0)
		_debug_record_order(&"move", CMD_HOME, false, "already at home", true)
		return
	_debug_set_objective_name("Home")
	_issue_army_move(home, &"move", CMD_HOME, 0)

func _regroup() -> void:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return
	var soldiers: Array = _get_live_soldiers()
	if soldiers.is_empty():
		_army_home()
		return
	var facts: Dictionary = _main_army_facts(soldiers)
	var center: Vector3 = facts.get("center", _w.home) as Vector3
	var main_count: int = int(facts.get("main_count", 0))
	if main_count * 2 < soldiers.size():
		_army_home()
		return
	# Important: when Hero is ahead, move ONLY Hero back to the soldier mass.
	if _horizontal_distance(hero.global_position, center) > COHESION_RADIUS:
		_debug_set_objective_name("Army centroid")
		var dest: Vector3 = _nearest_walkable(center)
		if _unit_has_matching_strategic_order(hero, &"move", dest):
			_remember_strategic_command(CMD_REGROUP, dest, 1, 0)
			_debug_record_order(&"move", CMD_REGROUP, false, "hero regroup order still valid", true)
			return
		_request_strategic_group_move([hero], dest, &"move", &"enemy_ai_regroup")
		_remember_strategic_command(CMD_REGROUP, dest, 1, 0)
		_debug_record_order(&"move", CMD_REGROUP, true, "hero only")

func _creep() -> void:
	var camp: Node3D = _find_useful_creep_camp()
	if camp == null:
		return
	_debug_set_objective(camp)
	var staging: Vector3 = _creep_staging_point(camp)
	_issue_army_move(staging, &"attack_move", CMD_CREEP, camp.get_instance_id())

func _attack_player_base() -> void:
	var target: Node3D = _get_player_base_target()
	if target == null:
		return
	_debug_set_objective(target)
	var center: Vector3 = _main_army_center()
	var approach: Vector3 = _attack_approach(target.global_position, center)
	_issue_army_move(approach, &"attack_move", CMD_ATTACK, target.get_instance_id())

func _get_player_base_target() -> Node3D:
	if NodeSafety.is_alive_node(_w.player_cc) and CombatTargetValidation.is_player_faction(_w.player_cc):
		return _w.player_cc as Node3D
	for b_v: Variant in _w.player_buildings as Array:
		if not b_v is Building or not NodeSafety.is_alive_node(b_v):
			continue
		if CombatTargetValidation.is_player_faction(b_v):
			return b_v as Node3D
	return null

func _find_useful_creep_camp() -> Node3D:
	var origin: Vector3 = _main_army_center()
	if origin == Vector3.ZERO:
		origin = _w.home as Vector3
	var army_size: int = maxi(1, (_w.army as Array).size())
	var best: Node3D = null
	var best_dist: float = INF
	var best_creeps: int = 0
	var scanned: int = 0
	var useful: int = 0
	var rejected_far: int = 0
	var rejected_cleared: int = 0
	var rejected_too_big: int = 0
	var rejected_unwalkable: int = 0
	for camp_v: Variant in _w.active_camps as Array:
		if not camp_v is Node3D or not NodeSafety.is_alive_node(camp_v):
			continue
		var camp: Node3D = camp_v as Node3D
		scanned += 1
		var creeps: int = _count_living_creeps_in_camp(camp)
		if creeps <= 0:
			rejected_cleared += 1
			continue
		if creeps > army_size + 4:
			rejected_too_big += 1
			continue
		if _horizontal_distance(_w.home as Vector3, camp.global_position) > CAMP_SEARCH_RANGE:
			rejected_far += 1
			continue
		var staging: Vector3 = _creep_staging_point(camp)
		if not PlayerRouteNavigation.is_world_walkable(staging):
			rejected_unwalkable += 1
			continue
		useful += 1
		var d: float = _horizontal_distance(origin, camp.global_position)
		if d < best_dist:
			best_dist = d
			best = camp
			best_creeps = creeps
	if _debug_enabled:
		_dbg_last_camp = best
		_dbg_creep["useful_camps_found"] = useful
		_dbg_creep["scanned"] = scanned
		_dbg_creep["rejected_too_far"] = rejected_far
		_dbg_creep["rejected_cleared"] = rejected_cleared
		_dbg_creep["rejected_not_useful"] = rejected_too_big
		_dbg_creep["rejected_invalid"] = rejected_unwalkable
		if best != null and NodeSafety.is_alive_node(best):
			_dbg_creep["selected"] = best.name
			_dbg_creep["distance_from_home"] = _horizontal_distance(_w.home as Vector3, best.global_position)
			_dbg_creep["distance_from_army"] = best_dist
			_dbg_creep["camp_alive_units"] = best_creeps
			_dbg_creep["camp_valid"] = true
			_dbg_creep["objective_point"] = best.global_position
		else:
			_dbg_creep["selected"] = ""
			_dbg_creep["camp_valid"] = false
	return best

func _creep_staging_point(camp: Node3D) -> Vector3:
	var camp_pos: Vector3 = camp.global_position
	var toward_home: Vector3 = (_w.home as Vector3) - camp_pos
	toward_home.y = 0.0
	if toward_home.length_squared() < 0.01:
		toward_home = Vector3(1, 0, 0)
	else:
		toward_home = toward_home.normalized()
	return _nearest_walkable(camp_pos + toward_home * CREEP_STAGING_STANDOFF)


## Compat alias for older headless helpers that still call the previous private name.
func _compute_creep_staging_point(camp: Node3D) -> Vector3:
	return _creep_staging_point(camp)

func _attack_approach(target: Vector3, army_center: Vector3) -> Vector3:
	var away: Vector3 = army_center - target
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(1, 0, 0)
	else:
		away = away.normalized()
	return _nearest_walkable(target + away * ATTACK_APPROACH_STANDOFF)


func _nearest_own_command_center(to_position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	var bases: Array = _w.command_centers as Array
	if bases.is_empty() and _w.primary_cc != null:
		bases = [_w.primary_cc]
	for base_v: Variant in bases:
		if not base_v is Node3D or not NodeSafety.is_alive_node(base_v):
			continue
		var base: Node3D = base_v as Node3D
		var d: float = _horizontal_distance(base.global_position, to_position)
		if d < best_dist:
			best_dist = d
			best = base
	return best


func _defense_intercept_point(base: Node3D, threat: Node3D) -> Vector3:
	var base_pos: Vector3 = base.global_position
	var toward: Vector3 = threat.global_position - base_pos
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		toward = Vector3(1, 0, 0)
	else:
		toward = toward.normalized()
	return _nearest_walkable(base_pos + toward * DEFENSE_STANDOFF)

func _nearest_walkable(pos: Vector3) -> Vector3:
	if PlayerRouteNavigation.is_world_walkable(pos):
		return pos
	return PlayerRouteNavigation.nearest_walkable_world(pos)

func _get_live_soldiers() -> Array:
	var out: Array = []
	for unit_v: Variant in _w.army as Array:
		if not unit_v is Unit or not NodeSafety.is_alive_node(unit_v):
			continue
		var unit: Unit = unit_v as Unit
		if unit is Hero or unit is Worker:
			continue
		out.append(unit)
	return out

func _average_positions(nodes: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for n_v: Variant in nodes:
		if not n_v is Node3D or not NodeSafety.is_alive_node(n_v):
			continue
		sum += (n_v as Node3D).global_position
		count += 1
	return sum / float(count) if count > 0 else (_w.home as Vector3)

func _main_army_facts(soldiers: Array) -> Dictionary:
	if soldiers.is_empty():
		return {"center": _w.home as Vector3, "main_count": 0}
	var first_center: Vector3 = _average_positions(soldiers)
	var main: Array = []
	for u_v: Variant in soldiers:
		if not u_v is Node3D or not NodeSafety.is_alive_node(u_v):
			continue
		if _horizontal_distance((u_v as Node3D).global_position, first_center) <= COHESION_RADIUS:
			main.append(u_v)
	var center: Vector3 = _average_positions(main) if not main.is_empty() else first_center
	return {"center": center, "main_count": main.size()}

func _main_army_center() -> Vector3:
	var soldiers: Array = _get_live_soldiers()
	if soldiers.is_empty():
		var hero: Hero = _w.hero as Hero
		return hero.global_position if hero != null and NodeSafety.is_alive_node(hero) else (_w.home as Vector3)
	return _main_army_facts(soldiers).get("center", _w.home) as Vector3

func _army_is_together() -> bool:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		if _debug_enabled:
			_dbg_together_evaluated = true
			_dbg_together = false
			_dbg_soldiers = 0
			_dbg_soldiers_near = 0
			_dbg_hero_to_centroid = 0.0
		return false
	var soldiers: Array = _get_live_soldiers()
	if soldiers.is_empty():
		if _debug_enabled:
			_dbg_together_evaluated = true
			_dbg_together = false
			_dbg_soldiers = 0
			_dbg_soldiers_near = 0
			_dbg_hero_to_centroid = 0.0
		return false
	var facts: Dictionary = _main_army_facts(soldiers)
	var main_count: int = int(facts.get("main_count", 0))
	var center: Vector3 = facts.get("center", hero.global_position) as Vector3
	var hero_to_centroid: float = _horizontal_distance(hero.global_position, center)
	if _debug_enabled:
		_dbg_together_evaluated = true
		_dbg_soldiers = soldiers.size()
		_dbg_soldiers_near = main_count
		_dbg_hero_to_centroid = hero_to_centroid
	if main_count * 2 < soldiers.size():
		if _debug_enabled:
			_dbg_together = false
		return false
	var result: bool = hero_to_centroid <= COHESION_RADIUS
	if _debug_enabled:
		_dbg_together = result
		_dbg_army_center = center
		_dbg_farthest_name = ""
		_dbg_farthest_dist = 0.0
		for u_v: Variant in soldiers:
			if not u_v is Node3D or not NodeSafety.is_alive_node(u_v):
				continue
			var unit_n: Node3D = u_v as Node3D
			var dist: float = _horizontal_distance(unit_n.global_position, center)
			if dist >= _dbg_farthest_dist:
				_dbg_farthest_dist = dist
				_dbg_farthest_name = unit_n.name
	return result

func _hero_is_physically_stuck() -> bool:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return false
	if not hero.has_method(&"is_physically_blocked_from_current_move"):
		return false
	return bool(hero.call(&"is_physically_blocked_from_current_move"))

func _free_hero_locally() -> void:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return
	var target: Vector3 = _main_army_center()
	var dir: Vector3 = target - hero.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = (_w.home as Vector3) - hero.global_position
		dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var escape: Vector3 = _nearest_walkable(hero.global_position + dir * 4.0)
	_debug_set_objective_name("Unstuck")
	if _unit_has_matching_strategic_order(hero, &"move", escape):
		_remember_strategic_command(CMD_HOME, escape, 1, 0)
		_debug_record_order(&"move", CMD_HOME, false, "hero unstuck order still valid", true)
		return
	_request_strategic_group_move([hero], escape, &"move", &"enemy_ai_unstuck")
	_remember_strategic_command(CMD_HOME, escape, 1, 0)
	_debug_record_order(&"move", CMD_HOME, true, "hero unstuck")

func _majority_near(position: Vector3, radius: float) -> bool:
	var army: Array = _w.army as Array
	if army.is_empty():
		return true
	var valid: int = 0
	var near: int = 0
	for u_v: Variant in army:
		if not u_v is Node3D or not NodeSafety.is_alive_node(u_v):
			continue
		valid += 1
		if _horizontal_distance((u_v as Node3D).global_position, position) <= radius:
			near += 1
	return valid == 0 or near * 2 >= valid

func _issue_army_move(
	destination: Vector3,
	order_kind: StringName,
	command_kind: StringName,
	objective_id: int = 0
) -> void:
	var army: Array = []
	for u_v: Variant in _w.army as Array:
		if u_v is Unit and NodeSafety.is_alive_node(u_v) and _is_living_combatant(u_v):
			army.append(u_v)
	if army.is_empty():
		_debug_record_order(order_kind, command_kind, false, "empty army")
		return
	var dest: Vector3 = _nearest_walkable(destination)
	var prev_dest: Vector3 = _last_command_destination
	var dest_change: float = 0.0
	if prev_dest != Vector3.ZERO:
		dest_change = _horizontal_distance(prev_dest, dest)
	var objective_changed: bool = (
		objective_id != 0
		and _last_command_target_id != 0
		and objective_id != _last_command_target_id
	)
	var dest_equivalent: bool = (
		_last_command_kind == command_kind
		and not objective_changed
		and prev_dest != Vector3.ZERO
		and dest_change <= ORDER_DEST_RADIUS
	)
	if dest_equivalent:
		dest = prev_dest
		dest_change = 0.0
	var needs_order: Array = []
	var combat_overwrote: int = 0
	for u_v: Variant in army:
		var unit: Unit = u_v as Unit
		if _unit_has_matching_strategic_order(unit, order_kind, dest):
			continue
		needs_order.append(unit)
		if _unit_combat_overwrote_strategic_order(unit):
			combat_overwrote += 1
	_remember_strategic_command(command_kind, dest, army.size(), objective_id)
	if needs_order.is_empty():
		_debug_record_issued_move(
			order_kind,
			command_kind,
			army,
			needs_order,
			false,
			"current group order still valid",
			dest,
			prev_dest,
			dest_change,
			combat_overwrote
		)
		return
	var issue_reason: String = "new army order"
	if combat_overwrote == needs_order.size():
		issue_reason = "combat overwrote strategic order"
	elif army.size() - needs_order.size() > 0:
		issue_reason = "new reinforcement needed existing order"
	elif dest_change > ORDER_DEST_RADIUS:
		issue_reason = "destination changed"
	_request_strategic_group_move(needs_order, dest, order_kind, &"enemy_ai")
	_debug_record_issued_move(
		order_kind,
		command_kind,
		army,
		needs_order,
		true,
		issue_reason,
		dest,
		prev_dest,
		dest_change,
		combat_overwrote
	)

func _can_keep_current_group_order(army: Array, order_kind: StringName, command_kind: StringName, destination: Vector3) -> bool:
	if army.is_empty():
		return false
	if _last_command_kind != command_kind:
		return false
	if _horizontal_distance(_last_command_destination, destination) > ORDER_DEST_RADIUS:
		return false
	for u_v: Variant in army:
		if not u_v is Unit or not NodeSafety.is_alive_node(u_v) or not _is_living_combatant(u_v):
			return false
		if not _unit_has_matching_strategic_order(u_v as Unit, order_kind, destination):
			return false
	return true

func _unit_has_matching_strategic_order(unit: Unit, order_kind: StringName, destination: Vector3) -> bool:
	if not NodeSafety.is_alive_node(unit) or not _is_living_combatant(unit):
		return false
	var required_type: int = UnitOrder.Type.ATTACK_MOVE if order_kind == &"attack_move" else UnitOrder.Type.MOVE
	var at_destination: bool = _horizontal_distance(unit.global_position, destination) <= ORDER_DEST_RADIUS
	var active: UnitOrder = unit.get_active_order()
	if active == null:
		## Travel already finished on this destination — do not mint a new route.
		return at_destination
	if active.type != required_type:
		return false
	if _horizontal_distance(active.destination, destination) <= ORDER_DEST_RADIUS:
		return true
	## Group commands store per-unit slots; compare the shared clicked destination.
	var clicked: Vector3 = unit.get_player_squad_clicked_destination()
	if clicked != Vector3.ZERO and _horizontal_distance(clicked, destination) <= ORDER_DEST_RADIUS:
		return true
	return at_destination

func _unit_combat_overwrote_strategic_order(unit: Unit) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	var active: UnitOrder = unit.get_active_order()
	if active == null:
		return false
	return active.type == UnitOrder.Type.ATTACK

func _remember_strategic_command(
	command_kind: StringName,
	destination: Vector3,
	army_count: int,
	objective_id: int
) -> void:
	_last_command_kind = command_kind
	_last_command_destination = destination
	_last_command_army_count = army_count
	_last_command_target_id = objective_id

func _request_strategic_group_move(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	command_source: StringName
) -> void:
	if units.is_empty():
		return
	_strategic_group_route_requests += 1
	PlayerRouteNavigation.request_group_move(units, destination, order_kind, false, command_source)

func _count_living_creeps_in_camp(camp: Node3D) -> int:
	if not NodeSafety.is_alive_node(camp):
		return 0
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		return 0
	var count: int = 0
	for v: Variant in CombatTargetValidation.get_cached_group_nodes(tree, CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if not NodeSafety.is_alive_node(v) or not v is Node3D:
			continue
		var creep: Node3D = v as Node3D
		if not CombatTargetValidation.is_neutral_creep(creep):
			continue
		if CombatTargetValidation.get_target_current_health(creep) <= 0:
			continue
		if _horizontal_distance(camp.global_position, creep.global_position) <= CAMP_CLEAR_RADIUS:
			count += 1
	return count

func _set_condition(condition: StringName) -> void:
	if condition == _last_condition:
		return
	_last_condition = condition

func get_debug_priority() -> StringName:
	return _last_condition

func get_debug_condition_bucket_for_test() -> StringName:
	return _last_condition

func force_tick_for_test() -> void:
	_ai_tick()

func is_army_together_for_test() -> bool:
	_read_live_world()
	return _army_is_together()

func get_player_power_for_test() -> float:
	_read_live_world()
	return float(_w.player_power)

func get_our_power_for_test() -> float:
	_read_live_world()
	return float(_w.our_power)

func select_player_target_for_test() -> Node3D:
	_read_live_world()
	return _get_player_base_target()

func pick_safe_creep_camp_for_test() -> Node3D:
	_read_live_world()
	return _find_useful_creep_camp()


func _desired_worker_count() -> int:
	return AIDifficultyConfig.get_desired_worker_count(
		int(_w.tier),
		_w.expansion_cc != null
	)


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


func _calc_force_power(units: Array, debug_bucket: StringName = &"") -> float:
	var total: float = 0.0
	var capture: bool = _debug_enabled and debug_bucket != &""
	var groups: Dictionary = {}
	var hero_line: Dictionary = {}
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
		var contribution: float = float(health.max_health) * hp_ratio
		var damage_variant: Variant = unit.get("attack_damage")
		if typeof(damage_variant) == TYPE_INT or typeof(damage_variant) == TYPE_FLOAT:
			contribution += float(damage_variant) * 12.0
		if unit is Hero:
			contribution += float((unit as Hero).level) * 40.0
		total += contribution
		if capture:
			if unit is Hero:
				hero_line = {
					"name": _debug_node_display_name(unit),
					"level": (unit as Hero).level,
					"hp_pct": int(round(100.0 * hp_ratio)),
					"contribution": contribution,
				}
			else:
				var type_key: String = _debug_unit_type_key(unit)
				var bucket: Dictionary = groups.get(type_key, {
					"count": 0,
					"contribution": 0.0,
				}) as Dictionary
				bucket["count"] = int(bucket.get("count", 0)) + 1
				bucket["contribution"] = float(bucket.get("contribution", 0.0)) + contribution
				groups[type_key] = bucket
	if capture:
		var payload := {
			"total": total,
			"hero": hero_line,
			"groups": groups,
		}
		if debug_bucket == &"ai":
			_dbg_power_ai = payload
		else:
			_dbg_power_player = payload
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


func _soldiers_near_hero(radius: float) -> int:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return 0
	var count: int = 0
	for unit_v: Variant in _get_live_soldiers():
		if not unit_v is Node3D or not NodeSafety.is_alive_node(unit_v):
			continue
		if _horizontal_distance((unit_v as Node3D).global_position, hero.global_position) <= radius:
			count += 1
	return count


# ---------------------------------------------------------------------------
# Compatibility surface for existing typed callers / headless harnesses.
# Thin wrappers only — no restored old strategy architecture.
# ---------------------------------------------------------------------------

const MAIN_CLUSTER_RADIUS: float = COHESION_RADIUS
const HERO_FAR_THRESHOLD: float = COHESION_RADIUS
const ORDER_DEST_RADIUS: float = 4.0

var _camps_cleared: int = 0
var _last_command_target_id: int = 0
var _last_command_army_count: int = 0


func get_debug_overlay_lines() -> PackedStringArray:
	if _debug_summary.is_empty():
		return PackedStringArray([
			"AI BRAIN",
			"Decision: %s" % String(_last_condition),
		])
	return PackedStringArray(_debug_panel_text().split("\n"))


func get_camps_cleared() -> int:
	return _camps_cleared


func set_camps_cleared_for_test(value: int) -> void:
	_camps_cleared = value


func get_last_command_kind_for_test() -> StringName:
	return _last_command_kind


func get_defense_debug_for_test() -> Dictionary:
	return _dbg_defense.duplicate()


func get_last_command_target_id_for_test() -> int:
	return _last_command_target_id


func get_current_creep_camp_id_for_test() -> int:
	return _last_command_target_id if _last_command_kind == CMD_CREEP else 0


func get_current_target_id_for_test() -> int:
	return _last_command_target_id


func get_strategic_order_label_for_test() -> String:
	match _last_command_kind:
		CMD_HOME:
			return "HOME"
		CMD_DEFEND:
			return "DEFEND"
		CMD_REGROUP:
			return "REGROUP"
		CMD_CREEP:
			return "CREEP"
		CMD_ATTACK:
			return "ATTACK"
		_:
			return "NONE"


func get_last_command_destination_for_test() -> Vector3:
	return _last_command_destination


func get_strategic_group_route_request_count_for_test() -> int:
	return _strategic_group_route_requests


func get_last_order_debug_for_test() -> Dictionary:
	return _dbg_order.duplicate()


func get_order_health_totals_for_test() -> Dictionary:
	return _debug_order_health_totals()


func get_creep_staging_point_for_test(camp: Node3D) -> Vector3:
	_read_live_world()
	if not NodeSafety.is_alive_node(camp):
		return Vector3.ZERO
	return _creep_staging_point(camp)


func get_player_army_for_test() -> Array:
	_read_live_world()
	return (_w.player_army as Array).duplicate()


func get_enemy_army_for_test() -> Array:
	_read_live_world()
	return (_w.army as Array).duplicate()


func find_base_threat_for_test() -> Node3D:
	_read_live_world()
	return _find_base_threat()


func count_neutral_creeps_for_test() -> int:
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


func get_cohesion_snapshot_for_test() -> Dictionary:
	_read_live_world()
	var hero: Hero = _w.hero as Hero
	var soldiers: Array = _get_live_soldiers()
	var facts: Dictionary = _main_army_facts(soldiers)
	var center: Vector3 = facts.get("center", _w.home) as Vector3
	var hero_to_center: float = 0.0
	if hero != null and NodeSafety.is_alive_node(hero):
		hero_to_center = _horizontal_distance(hero.global_position, center)
	return {
		"result": _army_is_together(),
		"army_count": soldiers.size(),
		"soldiers_total": soldiers.size(),
		"soldiers_in_main_cluster": int(facts.get("main_count", 0)),
		"required_cluster_count": 0,
		"hero_inside": hero_to_center <= COHESION_RADIUS,
		"majority_inside": int(facts.get("main_count", 0)) * 2 >= soldiers.size(),
		"hero_to_center": hero_to_center,
		"cohesion_radius": MAIN_CLUSTER_RADIUS,
		"hero_cohesion_radius": HERO_FAR_THRESHOLD,
		"hero_pos": hero.global_position if hero != null and NodeSafety.is_alive_node(hero) else Vector3.ZERO,
		"main_center": center,
	}


func get_hero_cohesion_radius_for_test() -> float:
	return HERO_FAR_THRESHOLD


func get_regroup_destination_for_test() -> Vector3:
	_read_live_world()
	return _nearest_walkable(_main_army_center())


func get_main_army_centroid_for_test() -> Vector3:
	_read_live_world()
	return _main_army_center()


func _find_living_creep_in_camp(camp: Node3D) -> Node3D:
	if not NodeSafety.is_alive_node(camp):
		return null
	var tree: SceneTree = _w.tree as SceneTree
	if tree == null:
		tree = get_tree()
	if tree == null:
		return null
	for v: Variant in CombatTargetValidation.get_cached_group_nodes(tree, CombatTargetValidation.NEUTRAL_CREEP_GROUP):
		if not NodeSafety.is_alive_node(v) or not v is Node3D:
			continue
		var creep: Node3D = v as Node3D
		if not CombatTargetValidation.is_neutral_creep(creep):
			continue
		if CombatTargetValidation.get_target_current_health(creep) <= 0:
			continue
		if _horizontal_distance(camp.global_position, creep.global_position) <= CAMP_CLEAR_RADIUS:
			return creep
	return null


# ---------------------------------------------------------------------------
# AI brain debug (P toggle). Observability only — uses live condition results.
# ---------------------------------------------------------------------------

func toggle_brain_debug() -> void:
	set_brain_debug(not _debug_enabled)


func set_brain_debug(enabled: bool) -> void:
	_debug_enabled = enabled
	show_debug_overlay = enabled
	if enabled:
		_ensure_debug_panel()
		if _debug_panel != null:
			_debug_panel.call("show_panel")
			_debug_update_panel()
	else:
		_debug_clear_tick_buffers()
		_debug_reset_persistent_trace()
		if _debug_panel != null:
			_debug_panel.call("hide_panel")


func is_brain_debug_enabled() -> bool:
	return _debug_enabled


func _debug_reset_persistent_trace() -> void:
	_dbg_tick_count = 0
	_dbg_prev_decision = &""
	_dbg_prev_objective = ""
	_dbg_prev_attack = ""
	_dbg_prev_together = ""
	_dbg_prev_hero_missing = ""
	_dbg_prev_threat = ""
	_dbg_prev_army_small = ""
	_dbg_prev_early_creep = ""
	_dbg_prev_t2 = ""
	_dbg_prev_t3 = ""
	_dbg_prev_build_intent = ""
	_dbg_prev_prod_block = ""
	_dbg_prev_ratio_pass = false
	_dbg_tick_prev_decision = &""
	_dbg_tick_prev_objective = ""
	_dbg_health_samples.clear()
	_dbg_unit_orders.clear()
	_dbg_unit_order_changes.clear()
	_dbg_last_health_warning = ""
	_dbg_power_ai.clear()
	_dbg_power_player.clear()


func _debug_begin_tick() -> void:
	_dbg_tick_prev_decision = _dbg_prev_decision
	_dbg_tick_prev_objective = _dbg_prev_objective
	_dbg_tick_count += 1
	_debug_clear_tick_buffers()


func _debug_clear_tick_buffers() -> void:
	_debug_condition_lines.clear()
	_debug_summary.clear()
	_dbg_threat_dist = INF
	_dbg_threat_name = ""
	_dbg_soldiers = 0
	_dbg_soldiers_near = 0
	_dbg_hero_to_centroid = 0.0
	_dbg_together_evaluated = false
	_dbg_together = false
	_dbg_army_center = Vector3.ZERO
	_dbg_farthest_name = ""
	_dbg_farthest_dist = 0.0
	_dbg_last_camp = null
	_dbg_attack.clear()
	_dbg_defense.clear()
	_dbg_order.clear()
	_dbg_objective_name = ""
	_dbg_objective_type = ""
	_dbg_objective_position = Vector3.ZERO
	_dbg_macro.clear()
	_dbg_army_min.clear()
	_dbg_creep.clear()
	_dbg_workers.clear()
	_dbg_unit_order_changes.clear()


func _debug_macro_set(key: String, data: Dictionary) -> void:
	if not _debug_enabled:
		return
	_dbg_macro[key] = data


func _debug_macro_intent(kind: String, detail: String) -> void:
	if not _debug_enabled:
		return
	_dbg_macro["intent"] = "%s:%s" % [kind, detail]


func _debug_t2_unwanted_reason() -> String:
	if not _debug_enabled:
		return ""
	if int(_w.tier) >= 2:
		return "ALREADY_T2_PLUS"
	if _w.hero == null:
		return "NO_HERO"
	if int(_w.spearmen) < MIN_EARLY_SPEARMEN:
		return "SPEARMEN"
	if not _w.altar_completed:
		return "ALTAR"
	if not _w.barracks_completed:
		return "BARRACKS"
	return "UNKNOWN"


func _debug_t3_unwanted_reason() -> String:
	if not _debug_enabled:
		return ""
	if int(_w.tier) < 2:
		return "NEED_T2"
	if int(_w.tier) >= 3:
		return "ALREADY_T3"
	if not _w.blacksmith_completed:
		return "BLACKSMITH"
	if int((_w.army as Array).size()) < T3_ARMY_MINIMUM:
		return "ARMY"
	if int((_w.workers as Array).size()) < T3_WORKER_MINIMUM:
		return "WORKERS"
	return "UNKNOWN"


func _debug_upgrade_block_reason(cc: CommandCenter, _tier: int) -> String:
	if not _debug_enabled:
		return ""
	if cc == null:
		return "NO_CC"
	if not cc.can_try_enemy_upgrade_tier(_tier):
		var costs: Dictionary = CommandCenter.get_upgrade_costs(_tier)
		var gold_need: int = int(costs.get("gold", 0))
		var wood_need: int = int(costs.get("wood", 0))
		if gold_need > 0 or wood_need > 0:
			var cost_block: String = _debug_cost_block(gold_need, wood_need)
			if cost_block != "NONE":
				return cost_block
		return "CC_BUSY"
	return "UNKNOWN"


func _debug_cost_block(gold_need: int, wood_need: int) -> String:
	if not _debug_enabled:
		return ""
	if int(_w.wood) < wood_need:
		return "WOOD"
	if int(_w.gold) < gold_need:
		return "GOLD"
	return "NONE"


func _debug_record_condition(condition_name: StringName, result: bool, facts: Dictionary = {}) -> void:
	if not _debug_enabled:
		return
	_debug_condition_lines.append({
		"name": condition_name,
		"state": "TRUE" if result else "FALSE",
		"facts": facts,
		"reason": _debug_reason_for(condition_name, result, facts),
	})


func _debug_reason_for(condition_name: StringName, result: bool, facts: Dictionary = {}) -> String:
	match condition_name:
		&"BASE_THREATENED":
			var nearest: float = float(facts.get("nearest_threat", _dbg_threat_dist))
			var entry: float = float(facts.get("entry_radius", DEFENSE_RADIUS))
			var release: float = float(facts.get("release_radius", DEFENSE_RELEASE_RADIUS))
			if nearest == INF:
				return "no player army near bases"
			if bool(facts.get("hysteresis", false)):
				return "DEFENSE_RELEASE_HYSTERESIS nearest=%.1fm entry=%.0fm release=%.0fm" % [
					nearest,
					entry,
					release,
				]
			if result:
				return "nearest=%.1fm entry_radius=%.0fm" % [nearest, entry]
			return "nearest=%.1fm entry_radius=%.0fm release_radius=%.0fm currently_defending=%s" % [
				nearest,
				entry,
				release,
				"YES" if bool(facts.get("currently_defending", false)) else "NO",
			]
		&"HERO_MISSING":
			return "hero_alive=%s" % ("NO" if result else "YES")
		&"ARMY_TOO_SMALL":
			if int(facts.get("tier", int(_w.tier))) < 2:
				return "spearmen=%d minimum=%d" % [
					int(facts.get("spearmen", int(_w.spearmen))),
					int(facts.get("minimum", MIN_EARLY_SPEARMEN)),
				]
			return "soldiers=%d minimum=%d" % [
				int(facts.get("soldiers", 0)),
				int(facts.get("minimum", MIN_LATE_COMBAT_UNITS)),
			]
		&"HERO_STUCK":
			return "stuck=%s" % ("YES" if result else "NO")
		&"ARMY_NOT_TOGETHER":
			if not _dbg_together_evaluated:
				return "not evaluated"
			return "hero_to_centroid=%.1fm soldiers_near_group=%d/%d required_radius=%.0fm" % [
				float(facts.get("hero_to_centroid", _dbg_hero_to_centroid)),
				int(facts.get("soldiers_near", _dbg_soldiers_near)),
				int(facts.get("soldiers_total", _dbg_soldiers)),
				float(facts.get("required_radius", COHESION_RADIUS)),
			]
		&"EARLY_CREEP":
			var camp_name: String = String(facts.get("camp", _debug_camp_name()))
			var hero_lvl: int = int(facts.get("hero_level", int(_w.hero_level)))
			var goal: int = int(facts.get("goal_level", EARLY_HERO_LEVEL_TARGET))
			if hero_lvl >= goal:
				return "hero_lvl=%d goal_lvl=%d" % [hero_lvl, goal]
			if camp_name.is_empty():
				return "hero_lvl=%d goal_lvl=%d no useful camp" % [hero_lvl, goal]
			return "hero_lvl=%d goal_lvl=%d useful camp=%s" % [hero_lvl, goal, camp_name]
		&"ATTACK_PLAYER":
			return _debug_attack_reason(result)
		&"EXTRA_CREEP":
			var extra_name: String = String(facts.get("camp", _debug_camp_name()))
			if result:
				return "useful camp exists (%s)" % extra_name
			return "no useful camp"
		&"HOME_WAIT":
			return String(facts.get("reason", "all military conditions false"))
		_:
			return ""


func _debug_attack_reason(result: bool) -> String:
	if _dbg_attack.is_empty():
		return "not evaluated"
	var blocked_by: StringName = _dbg_attack.get("blocked_by", &"") as StringName
	var ratio: float = float(_dbg_attack.get("ratio", 0.0))
	var required: float = float(_dbg_attack.get("required", ATTACK_POWER_RATIO))
	if result:
		return "ratio=%.2f >= %.2f, all attack checks passed" % [ratio, required]
	if blocked_by == &"POWER_RATIO":
		return "ratio=%.2f < required=%.2f" % [ratio, required]
	if blocked_by == &"MIN_ARMY":
		return "soldiers=%d minimum=%d (player army empty)" % [
			int(_dbg_attack.get("soldiers", 0)),
			int(_dbg_attack.get("min_army", MIN_LATE_COMBAT_UNITS)),
		]
	if blocked_by == &"NO_PLAYER_TARGET":
		return "no player base target"
	if blocked_by == &"NO_ARMY":
		return "AI army empty"
	if blocked_by == &"NO_POWER":
		return "AI power <= 0"
	return "blocked_by=%s" % String(blocked_by)


func _debug_store_attack(result: bool, blocked_by: StringName, soldiers: int, army_size: int = 0) -> void:
	var our_power: float = float(_w.our_power)
	var player_power: float = float(_w.player_power)
	var ratio: float = 0.0 if player_power <= 0.0 else our_power / player_power
	var player_empty: bool = (_w.player_army as Array).is_empty()
	_dbg_attack = {
		"result": result,
		"blocked_by": blocked_by if not result else &"",
		"ai_power": our_power,
		"player_power": player_power,
		"ratio": ratio,
		"required": ATTACK_POWER_RATIO,
		"min_army": MIN_LATE_COMBAT_UNITS,
		"hero_present": _w.hero != null,
		"hero_exists": _w.hero != null,
		"cohesion": _dbg_together if _dbg_together_evaluated else false,
		"soldiers": soldiers,
		"army_size": army_size if army_size > 0 else (_w.army as Array).size(),
		"army_minimum_pass": soldiers >= MIN_LATE_COMBAT_UNITS if player_empty else true,
		"player_army_empty": player_empty,
	}


func _debug_camp_name() -> String:
	if NodeSafety.is_alive_node(_dbg_last_camp):
		return _dbg_last_camp.name
	return ""


func _debug_set_objective(node: Node) -> void:
	if not _debug_enabled:
		return
	if node != null and NodeSafety.is_alive_node(node):
		_dbg_objective_name = node.name
		_dbg_objective_position = (node as Node3D).global_position if node is Node3D else Vector3.ZERO
		if node is CommandCenter and CombatTargetValidation.is_player_faction(node):
			_dbg_objective_type = "PLAYER_COMMAND_CENTER"
		elif CombatTargetValidation.is_player_faction(node):
			_dbg_objective_type = "PLAYER_TARGET"
		elif node is CreepCamp or String(node.name).begins_with("Camp") or node.is_in_group(&"creep_camps"):
			_dbg_objective_type = "CREEP_CAMP"
		else:
			_dbg_objective_type = node.get_class()
	else:
		_dbg_objective_name = ""
		_dbg_objective_type = ""
		_dbg_objective_position = Vector3.ZERO


func _debug_set_objective_name(label: String) -> void:
	if not _debug_enabled:
		return
	_dbg_objective_name = label
	_dbg_objective_type = label.to_upper().replace(" ", "_")
	if label == "Home":
		_dbg_objective_position = _w.home as Vector3
		_dbg_objective_type = "HOME"
	elif label == "Army centroid":
		_dbg_objective_position = _dbg_army_center
		_dbg_objective_type = "ARMY_CENTROID"
	elif label == "Unstuck":
		_dbg_objective_type = "HERO_UNSTUCK"


func _debug_record_order(
	order_kind: StringName,
	command_kind: StringName,
	route_request: bool,
	reason: String,
	identical_skipped: bool = false
) -> void:
	if not _debug_enabled:
		return
	var army_size: int = (_w.army as Array).size()
	_dbg_order = {
		"command": String(order_kind).to_upper(),
		"command_kind": String(command_kind),
		"objective": _dbg_objective_name,
		"army": army_size,
		"hero_included": _w.hero != null,
		"already_correct": army_size if not route_request else 0,
		"needs_order": 0 if not route_request else 1,
		"ordered": 1 if route_request else 0,
		"route_request": route_request,
		"identical_skipped": identical_skipped,
		"combat_overwrote": 0,
		"source": "enemy_ai",
		"reason": reason,
		"destination": _last_command_destination,
		"previous_destination": _last_command_destination,
		"destination_change": 0.0,
	}


func _debug_record_issued_move(
	order_kind: StringName,
	command_kind: StringName,
	army: Array,
	needs_order: Array,
	route_request: bool,
	reason: String,
	destination: Vector3 = Vector3.ZERO,
	previous_destination: Vector3 = Vector3.ZERO,
	destination_change: float = 0.0,
	combat_overwrote: int = 0
) -> void:
	if not _debug_enabled:
		return
	var hero_included: bool = false
	for unit_v: Variant in army:
		if unit_v is Hero:
			hero_included = true
			break
	_dbg_order = {
		"command": String(order_kind).to_upper(),
		"command_kind": String(command_kind),
		"objective": _dbg_objective_name,
		"army": army.size(),
		"hero_included": hero_included,
		"already_correct": army.size() - needs_order.size(),
		"needs_order": needs_order.size(),
		"ordered": needs_order.size() if route_request else 0,
		"route_request": route_request,
		"identical_skipped": not route_request,
		"combat_overwrote": combat_overwrote,
		"source": "enemy_ai",
		"reason": reason,
		"destination": destination,
		"previous_destination": previous_destination,
		"destination_change": destination_change,
	}


func _debug_finish_tick() -> void:
	_debug_fill_skipped_conditions()
	_debug_fill_macro_gaps()
	_debug_snapshot_workers()
	_debug_trace_unit_order_changes()
	_debug_record_order_health()
	_debug_build_summary()
	_debug_emit_change_events()
	_debug_print_tick()
	_debug_update_panel()


func _debug_fill_macro_gaps() -> void:
	if not _debug_enabled:
		return
	if not _dbg_macro.has("t3"):
		_dbg_macro["t3"] = {
			"wanted": false,
			"reason": "not reached this tick",
			"blocked_by": "EARLIER_MACRO",
			"gold_required": BuildingStats.CC_TIER_3_GOLD_COST,
			"wood_required": BuildingStats.CC_TIER_3_WOOD_COST,
		}
	if not _dbg_macro.has("stable"):
		_dbg_macro["stable"] = {"wanted": false, "reason": "not reached this tick"}
	if not _dbg_macro.has("artillery"):
		_dbg_macro["artillery"] = {"wanted": false, "reason": "not reached this tick"}
	if not _dbg_macro.has("expansion"):
		_dbg_macro["expansion"] = {"wanted": false, "reason": "not reached this tick"}
	if not _dbg_macro.has("tower"):
		_dbg_macro["tower"] = {"wanted": false, "reason": "not reached this tick"}
	if not _dbg_macro.has("hero"):
		_dbg_macro["hero"] = {
			"exists": _w.hero != null,
			"train_hero": false,
			"reason": "not reached this tick",
		}


func _debug_fill_skipped_conditions() -> void:
	var seen: Dictionary = {}
	for line: Dictionary in _debug_condition_lines:
		seen[line.get("name", &"")] = true
	var winning: String = String(_last_condition)
	for condition_name: StringName in DEBUG_CONDITION_ORDER:
		if seen.has(condition_name):
			continue
		_debug_condition_lines.append({
			"name": condition_name,
			"state": "SKIPPED",
			"facts": {},
			"reason": "earlier priority won (%s)" % winning,
		})


func _debug_build_summary() -> void:
	var hero: Hero = _w.hero as Hero
	var army: Array = _w.army as Array
	var soldiers: int = _get_live_soldiers().size()
	var our_power: float = float(_w.our_power)
	var player_power: float = float(_w.player_power)
	var ratio: float = 0.0 if player_power <= 0.0 else our_power / player_power
	_debug_summary = {
		"decision": String(_last_condition),
		"hero_present": hero != null,
		"hero_level": int(_w.hero_level),
		"hero_hp_pct": _debug_hero_hp_pct(),
		"soldiers": soldiers,
		"army": army.size(),
		"together": _dbg_together if _dbg_together_evaluated else false,
		"together_evaluated": _dbg_together_evaluated,
		"ai_power": our_power,
		"player_power": player_power,
		"ratio": ratio,
		"required": ATTACK_POWER_RATIO,
		"objective": _dbg_objective_name,
		"order": _dbg_order.duplicate(),
	}


func _debug_hero_hp_pct() -> int:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return 0
	var health: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.max_health <= 0:
		return 0
	return int(round(100.0 * float(health.current_health) / float(health.max_health)))


func _debug_emit_change_events() -> void:
	var decision: StringName = _last_condition
	var objective: String = _dbg_objective_name
	var attack_state: String = _debug_condition_state(&"ATTACK_PLAYER")
	var together_state: String = _debug_condition_state(&"ARMY_NOT_TOGETHER")
	var hero_missing_state: String = _debug_condition_state(&"HERO_MISSING")
	var threat_state: String = _debug_condition_state(&"BASE_THREATENED")
	var army_small_state: String = _debug_condition_state(&"ARMY_TOO_SMALL")
	var early_creep_state: String = _debug_condition_state(&"EARLY_CREEP")
	var ratio: float = float(_debug_summary.get("ratio", 0.0))
	var ratio_pass: bool = ratio >= ATTACK_POWER_RATIO and not _dbg_attack.is_empty()

	if decision != _dbg_prev_decision:
		if objective.is_empty():
			_debug_event("%s" % String(decision))
		else:
			_debug_event("%s → %s" % [String(decision), objective])
	elif not objective.is_empty() and objective != _dbg_prev_objective:
		_debug_event("objective → %s" % objective)

	if threat_state == "TRUE" and _dbg_prev_threat != "TRUE":
		_debug_event("base threat started")
	elif threat_state == "FALSE" and _dbg_prev_threat == "TRUE":
		_debug_event("base threat ended")

	if hero_missing_state == "TRUE" and _dbg_prev_hero_missing != "TRUE":
		_debug_event("hero missing")
	elif hero_missing_state == "FALSE" and _dbg_prev_hero_missing == "TRUE":
		_debug_event("hero returned")

	if army_small_state == "TRUE" and _dbg_prev_army_small == "FALSE":
		_debug_event("army minimum FAIL")
	elif army_small_state == "FALSE" and _dbg_prev_army_small == "TRUE":
		_debug_event("army minimum PASS")

	if together_state == "TRUE" and _dbg_prev_together == "FALSE":
		_debug_event("Cohesion YES -> NO")
	elif together_state == "FALSE" and _dbg_prev_together == "TRUE":
		_debug_event("Cohesion NO -> YES")

	if early_creep_state == "TRUE" and _dbg_prev_early_creep != "TRUE":
		_debug_event("early creep started")
	elif early_creep_state == "FALSE" and _dbg_prev_early_creep == "TRUE":
		_debug_event("early creep finished")

	if attack_state == "TRUE" and _dbg_prev_attack != "TRUE":
		_debug_event("Attack allowed %.2f" % ratio)
	elif attack_state == "FALSE" and _dbg_prev_attack == "TRUE":
		_debug_event("Attack blocked %s" % _debug_attack_reason(false))

	if ratio_pass and not _dbg_prev_ratio_pass:
		_debug_event("power ratio crossed %.2f" % ATTACK_POWER_RATIO)
	elif not ratio_pass and _dbg_prev_ratio_pass:
		_debug_event("power ratio dropped below %.2f" % ATTACK_POWER_RATIO)

	var t2: Dictionary = _dbg_macro.get("t2", {}) as Dictionary
	var t2_key: String = "%s/%s" % [t2.get("wanted", false), t2.get("blocked_by", "")]
	if not t2.is_empty() and t2_key != _dbg_prev_t2 and not _dbg_prev_t2.is_empty():
		_debug_event("T2 wanted=%s block=%s" % [t2.get("wanted", false), t2.get("blocked_by", "")])
	var t3: Dictionary = _dbg_macro.get("t3", {}) as Dictionary
	var t3_key: String = "%s/%s" % [t3.get("wanted", false), t3.get("blocked_by", t3.get("reason", ""))]
	if not t3.is_empty() and t3_key != _dbg_prev_t3 and not _dbg_prev_t3.is_empty():
		_debug_event("T3 wanted=%s block=%s" % [t3.get("wanted", false), t3.get("blocked_by", t3.get("reason", ""))])

	var intent: String = String(_dbg_macro.get("intent", ""))
	if not intent.is_empty() and intent != _dbg_prev_build_intent:
		_debug_event("build %s" % intent)

	var prod: Dictionary = _dbg_macro.get("production", {}) as Dictionary
	var prod_block: String = String(prod.get("blocked_by", ""))
	if not prod_block.is_empty() and bool(prod.get("train", true)) == false and prod_block != _dbg_prev_prod_block:
		_debug_event("production blocked %s" % prod_block)

	var needs_order: int = int(_dbg_order.get("needs_order", 0))
	var already_correct: int = int(_dbg_order.get("already_correct", 0))
	var route_request: bool = bool(_dbg_order.get("route_request", false))
	if route_request and needs_order > 0 and already_correct > 0:
		_debug_event("New reinforcement ordered")
	elif route_request and needs_order > 0:
		_debug_event("route request %s" % String(_dbg_order.get("command", "")))

	for change: Dictionary in _dbg_unit_order_changes:
		_debug_event(
			"%s -> %s" % [
				String(change.get("unit", "")),
				String(change.get("new_source", change.get("new", ""))),
			]
		)

	var workers: Dictionary = _dbg_workers
	if int(workers.get("invalid", 0)) > 0:
		_debug_event("worker invalid job")
	if int(workers.get("idle", 0)) > 0:
		_debug_event("worker unexpectedly idle")

	var health: Dictionary = _debug_order_health_totals()
	var health_warning: String = String(health.get("warning", ""))
	if health_warning == "REPEATED_ROUTE_REQUESTS":
		_debug_event("repeated route-request warning")
	elif health_warning == "COMBAT_OVERWROTE_STRATEGIC_ORDER":
		_debug_event("combat overwrote strategic order")
	elif health_warning == "MOVING_STRATEGIC_DESTINATION":
		_debug_event("moving strategic destination")

	_dbg_prev_decision = decision
	_dbg_prev_objective = objective
	_dbg_prev_attack = attack_state
	_dbg_prev_together = together_state
	_dbg_prev_hero_missing = hero_missing_state
	_dbg_prev_threat = threat_state
	_dbg_prev_army_small = army_small_state
	_dbg_prev_early_creep = early_creep_state
	_dbg_prev_t2 = t2_key
	_dbg_prev_t3 = t3_key
	_dbg_prev_build_intent = intent
	_dbg_prev_prod_block = prod_block
	_dbg_prev_ratio_pass = ratio_pass


func _debug_condition_state(condition_name: StringName) -> String:
	for line: Dictionary in _debug_condition_lines:
		if line.get("name", &"") == condition_name:
			return String(line.get("state", "SKIPPED"))
	return "SKIPPED"


func _debug_event(text: String) -> void:
	if not _debug_enabled or text.is_empty():
		return
	if not _debug_events.is_empty():
		var last: Dictionary = _debug_events[_debug_events.size() - 1]
		if String(last.get("text", "")) == text:
			return
	var clock: Dictionary = Time.get_time_dict_from_system()
	_debug_events.append({
		"time": "%02d:%02d" % [int(clock.get("hour", 0)), int(clock.get("minute", 0))],
		"text": text,
	})
	while _debug_events.size() > DEBUG_EVENT_LIMIT:
		_debug_events.remove_at(0)


func _debug_print_tick() -> void:
	print("============================================================")
	print("[AI BLACK BOX]")
	print("tick=%d" % _dbg_tick_count)
	print("time=%.1f" % (float(Time.get_ticks_msec()) / 1000.0))
	print("")
	_debug_print_world()
	print("")
	_debug_print_if_tree()
	print("DECISION=%s" % String(_last_condition))
	print("")
	_debug_print_defense()
	_debug_print_attack()
	_debug_print_power()
	_debug_print_creep()
	_debug_print_macro()
	_debug_print_strategy()
	_debug_print_order()
	_debug_print_order_health()
	_debug_print_unit_order_changes()
	_debug_print_cohesion()
	_debug_print_army_members()
	_debug_print_workers()
	_debug_print_diagnosis()


func _debug_print_world() -> void:
	var hero: Hero = _w.hero as Hero
	print("ECONOMY")
	print("gold=%d" % int(_w.gold))
	print("wood=%d" % int(_w.wood))
	print("food=%d/%d" % [int(_w.food_used), int(_w.food_cap)])
	print("tier=T%d" % int(_w.tier))
	print("")
	print("workers_total=%d" % (_w.workers as Array).size())
	print("gold_workers=%d" % int(_w.gold_workers))
	print("wood_workers=%d" % int(_w.wood_workers))
	print("builders=%d" % int(_w.building_workers))
	print("idle_workers=%d" % (_w.idle_workers as Array).size())
	print("")
	print("HERO")
	if hero != null and NodeSafety.is_alive_node(hero):
		print("exists=YES")
		print("name=%s" % _debug_node_display_name(hero))
		print("level=%d" % int(_w.hero_level))
		print("hp=%d%%" % _debug_hero_hp_pct())
		print("position=%s" % _debug_fmt_vec(hero.global_position))
		if _dbg_together_evaluated:
			print("distance_from_army_center=%.1f" % _dbg_hero_to_centroid)
	else:
		print("exists=NO")
	print("")
	print("ARMY")
	print("total=%d" % (_w.army as Array).size())
	print("soldiers=%d" % _get_live_soldiers().size())
	print("hero=%d" % (1 if hero != null else 0))
	print("")
	print("composition:")
	print("spearman=%d" % int(_w.spearmen))
	print("swordsman=%d" % int(_w.swordsmen))
	print("archer=%d" % int(_w.archers))
	print("light_cavalry=%d" % int(_w.light_cavalry))
	print("heavy_cavalry=%d" % int(_w.heavy_cavalry))
	print("cavalry_archer=%d" % int(_w.cavalry_archers))
	print("cannon=%d" % int(_w.cannons))
	print("")
	print("PLAYER")
	var ph: Hero = _w.player_hero as Hero
	if ph != null and NodeSafety.is_alive_node(ph):
		print(
			"hero=yes lvl=%d hp=%d%%"
			% [ph.level, _debug_hp_pct(ph)]
		)
	else:
		print("hero=no")
	var player_military: int = (_w.player_army as Array).size()
	if ph != null:
		player_military = maxi(0, player_military - 1)
	print("military=%d" % player_military)


func _debug_print_if_tree() -> void:
	var idx: int = 1
	for line: Dictionary in _debug_condition_lines:
		var name: String = String(line.get("name", ""))
		var state: String = String(line.get("state", ""))
		print("[%d] %s = %s" % [idx, name, state])
		if state == "SKIPPED":
			print("reason=%s" % String(line.get("reason", "")))
			print("")
			idx += 1
			continue
		var facts: Dictionary = line.get("facts", {}) as Dictionary
		match StringName(name):
			&"BASE_THREATENED":
				var nearest: float = float(facts.get("nearest_threat", _dbg_threat_dist))
				var entry: float = float(facts.get("entry_radius", DEFENSE_RADIUS))
				var release: float = float(facts.get("release_radius", DEFENSE_RELEASE_RADIUS))
				var currently_defending: bool = bool(facts.get("currently_defending", false))
				if nearest == INF:
					print("nearest=none")
				else:
					print("nearest=%.1fm" % nearest)
				print("entry_radius=%.0fm" % entry)
				print("release_radius=%.0fm" % release)
				print("currently_defending=%s" % _debug_yes(currently_defending))
				if state == "TRUE":
					var threatened_base: String = String(facts.get("threatened_base", ""))
					if not threatened_base.is_empty():
						print("threatened_base=%s" % threatened_base)
					var threat_name: String = String(facts.get("threat_name", _dbg_threat_name))
					if not threat_name.is_empty():
						print("nearest_threat=%s" % threat_name)
					if nearest != INF:
						print("distance=%.1fm" % nearest)
					if bool(facts.get("hysteresis", false)):
						print("reason=DEFENSE_RELEASE_HYSTERESIS")
			&"HERO_MISSING":
				print("hero_alive=%s" % ("NO" if state == "TRUE" else "YES"))
			&"ARMY_TOO_SMALL":
				if int(facts.get("tier", int(_w.tier))) < 2:
					print("spearmen=%d" % int(facts.get("spearmen", int(_w.spearmen))))
				else:
					print("soldiers=%d" % int(facts.get("soldiers", 0)))
				print("minimum=%d" % int(facts.get("minimum", 0)))
			&"HERO_STUCK":
				print("stuck=%s" % ("YES" if state == "TRUE" else "NO"))
			&"ARMY_NOT_TOGETHER":
				if state != "SKIPPED":
					print("hero_to_centroid=%.1fm" % float(facts.get("hero_to_centroid", _dbg_hero_to_centroid)))
					print(
						"soldiers_near_group=%d/%d"
						% [
							int(facts.get("soldiers_near", _dbg_soldiers_near)),
							int(facts.get("soldiers_total", _dbg_soldiers)),
						]
					)
					print("required_radius=%.0fm" % float(facts.get("required_radius", COHESION_RADIUS)))
			&"EARLY_CREEP":
				if state != "SKIPPED":
					print("hero_lvl=%d" % int(facts.get("hero_level", int(_w.hero_level))))
					print("goal_lvl=%d" % int(facts.get("goal_level", EARLY_HERO_LEVEL_TARGET)))
			&"ATTACK_PLAYER":
				if state == "TRUE":
					print("reason=all prerequisites passed")
				elif state == "FALSE":
					print("reason=%s" % _debug_attack_reason(false))
			&"EXTRA_CREEP":
				print("camp=%s" % String(facts.get("camp", "")))
			&"HOME_WAIT":
				print("reason=%s" % String(line.get("reason", "")))
		print("")
		idx += 1


func _debug_print_defense() -> void:
	print("BASE_THREATENED = %s" % ("TRUE" if _debug_condition_state(&"BASE_THREATENED") == "TRUE" else "FALSE"))
	var nearest: float = float(_dbg_defense.get("nearest_threat", _dbg_threat_dist))
	if nearest == INF:
		print("nearest=none")
	else:
		print("nearest=%.1fm" % nearest)
	print("entry_radius=%.0fm" % float(_dbg_defense.get("entry_radius", DEFENSE_RADIUS)))
	print("release_radius=%.0fm" % float(_dbg_defense.get("release_radius", DEFENSE_RELEASE_RADIUS)))
	print("currently_defending=%s" % _debug_yes(bool(_dbg_defense.get("currently_defending", false))))
	if _last_condition == &"DEFEND":
		var threatened_base: String = String(_dbg_defense.get("threatened_base", _dbg_objective_name))
		if not threatened_base.is_empty():
			print("threatened_base=%s" % threatened_base)
		var threat_name: String = String(_dbg_defense.get("threat_name", _dbg_threat_name))
		if not threat_name.is_empty():
			print("nearest_threat=%s" % threat_name)
		if bool(_dbg_defense.get("hysteresis", false)):
			print("reason=DEFENSE_RELEASE_HYSTERESIS")
		print("")
		print("DEFENSE")
		print("strategic_point=%s" % _debug_fmt_vec(_dbg_defense.get("strategic_point", _last_command_destination) as Vector3))
		print("point_type=%s" % String(_dbg_defense.get("point_type", "base_intercept")))
		print("threat_position=%s" % _debug_fmt_vec(_dbg_defense.get("threat_position", Vector3.ZERO) as Vector3))
		print("threat_position_is_not_route_target=%s" % _debug_yes(bool(_dbg_defense.get("threat_position_is_not_route_target", true))))
	print("")


func _debug_print_order() -> void:
	print("[AI ORDER]")
	if _dbg_order.is_empty():
		print("decision=%s" % String(_last_condition))
		print("command=NONE")
		print("source=enemy_ai")
		print("reason=no army order this tick")
		print("")
		return
	print("decision=%s" % String(_last_condition))
	print("objective=%s" % String(_dbg_order.get("objective", _dbg_objective_name)))
	print("command=%s" % String(_dbg_order.get("command", "")))
	print("strategic_destination=%s" % _debug_fmt_vec(_dbg_order.get("destination", _last_command_destination) as Vector3))
	print("source=%s" % String(_dbg_order.get("source", "enemy_ai")))
	print("army_total=%d" % int(_dbg_order.get("army", 0)))
	print("hero_included=%s" % _debug_yes(bool(_dbg_order.get("hero_included", false))))
	print("already_correct=%d" % int(_dbg_order.get("already_correct", 0)))
	print("needs_order=%d" % int(_dbg_order.get("needs_order", 0)))
	print("ordered=%d" % int(_dbg_order.get("ordered", 0)))
	print("route_request=%s" % _debug_yes(bool(_dbg_order.get("route_request", false))))
	print("identical_skipped=%s" % _debug_yes(bool(_dbg_order.get("identical_skipped", false))))
	print("combat_overwrote=%d" % int(_dbg_order.get("combat_overwrote", 0)))
	print("destination=%s" % _debug_fmt_vec(_dbg_order.get("destination", Vector3.ZERO) as Vector3))
	print("previous_destination=%s" % _debug_fmt_vec(_dbg_order.get("previous_destination", Vector3.ZERO) as Vector3))
	print("destination_change=%.1fm" % float(_dbg_order.get("destination_change", 0.0)))
	print("reason:")
	print("%s" % String(_dbg_order.get("reason", "")))
	print("")


func _debug_panel_text() -> String:
	var decision: String = String(_debug_summary.get("decision", _last_condition))
	var hero_present: bool = bool(_debug_summary.get("hero_present", false))
	var hero_line: String = "none"
	if hero_present:
		hero_line = "L%d %d%%" % [
			int(_debug_summary.get("hero_level", 0)),
			int(_debug_summary.get("hero_hp_pct", 0)),
		]
	var together_line: String = "n/a"
	if bool(_debug_summary.get("together_evaluated", false)):
		together_line = "YES" if bool(_debug_summary.get("together", false)) else "NO"
	var objective: String = _dbg_objective_name if not _dbg_objective_name.is_empty() else "-"
	var t3: Dictionary = _dbg_macro.get("t3", {}) as Dictionary
	var workers: Dictionary = _dbg_macro.get("workers", {}) as Dictionary
	var food: Dictionary = _dbg_macro.get("food", {}) as Dictionary
	var production: Dictionary = _dbg_macro.get("production", {}) as Dictionary
	var train_label: String = String(production.get("trained_unit", production.get("wanted_unit", "-")))
	if train_label.is_empty():
		train_label = "-"
	var t3_line: String = "NO"
	if bool(t3.get("wanted", false)):
		t3_line = "YES" if bool(t3.get("allowed", false)) else String(t3.get("blocked_by", "WAIT"))
	var order: Dictionary = _dbg_order
	var health: Dictionary = _debug_order_health_totals()
	var order_cmd: String = String(order.get("command", "NONE"))
	if order_cmd.is_empty():
		order_cmd = "NONE"
	var lines: PackedStringArray = PackedStringArray([
		"AI BRAIN",
		decision,
		"Target: %s" % objective,
		"",
		"Hero %s" % hero_line,
		"Army %d" % int(_debug_summary.get("army", 0)),
		"Together %s" % together_line,
		"",
		"Power",
		"%.0f / %.0f" % [
			float(_debug_summary.get("ai_power", 0.0)),
			float(_debug_summary.get("player_power", 0.0)),
		],
		"%.2f / %.2f" % [
			float(_debug_summary.get("ratio", 0.0)),
			float(_debug_summary.get("required", ATTACK_POWER_RATIO)),
		],
		"",
		"IF",
		"Threat %s" % _debug_check_short(&"BASE_THREATENED", true),
		_debug_threat_radius_short(),
		"Hero %s" % _debug_check_short(&"HERO_MISSING", false),
		"Army %s" % _debug_army_size_short(),
		"Together %s" % _debug_check_short(&"ARMY_NOT_TOGETHER", false),
		"Creep %s" % _debug_check_short(&"EARLY_CREEP", true),
		"Attack %s" % _debug_check_short(&"ATTACK_PLAYER", true),
		"",
		"Macro",
		"T%d" % int(_w.tier),
		"W %d | F %d/%d" % [
			int(workers.get("actual", (_w.workers as Array).size())),
			int(food.get("used", int(_w.food_used))),
			int(food.get("cap", int(_w.food_cap))),
		],
		"Train: %s" % train_label,
		"T3: %s" % t3_line,
		"",
		"Order",
		order_cmd,
		"OK=%d need=%d ordered=%d" % [
			int(order.get("already_correct", 0)),
			int(order.get("needs_order", 0)),
			int(order.get("ordered", 0)),
		],
		"route=%s" % ("YES" if bool(order.get("route_request", false)) else "NO"),
	])
	if int(order.get("combat_overwrote", 0)) > 0:
		lines.append("combat_overwrote=%d" % int(order.get("combat_overwrote", 0)))
	lines.append_array(PackedStringArray([
		"Health 10s",
		"ticks=%d req=%d" % [
			int(health.get("ticks", 0)),
			int(health.get("route_requests", 0)),
		],
		"ordered=%d skip=%d destΔ=%d" % [
			int(health.get("units_ordered", 0)),
			int(health.get("identical_skipped", 0)),
			int(health.get("destination_changes", 0)),
		],
	]))
	var health_warning: String = String(health.get("warning", ""))
	if not health_warning.is_empty():
		lines.append(health_warning)
	return "\n".join(lines)


func _debug_check_short(condition_name: StringName, true_means_yes: bool) -> String:
	var state: String = _debug_condition_state(condition_name)
	if state == "SKIPPED":
		return "skip"
	if state == "TRUE":
		return "YES" if true_means_yes else "NO"
	return "NO" if true_means_yes else "YES"


func _debug_threat_radius_short() -> String:
	var nearest: float = float(_dbg_defense.get("nearest_threat", _dbg_threat_dist))
	var entry: float = float(_dbg_defense.get("entry_radius", DEFENSE_RADIUS))
	var release: float = float(_dbg_defense.get("release_radius", DEFENSE_RELEASE_RADIUS))
	var currently_defending: bool = bool(_dbg_defense.get("currently_defending", false))
	if nearest == INF:
		return "no combat threat e%.0f r%.0f" % [entry, release]
	if currently_defending and bool(_dbg_defense.get("hysteresis", false)):
		return "%.0fm hold r%.0f" % [nearest, release]
	return "%.0fm e%.0f r%.0f" % [nearest, entry, release]


func _debug_army_size_short() -> String:
	var state: String = _debug_condition_state(&"ARMY_TOO_SMALL")
	if state == "SKIPPED":
		return "skip"
	if state == "TRUE":
		return "LOW"
	return "OK"


func _debug_events_text() -> String:
	if _debug_events.is_empty():
		return "Events"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Events")
	for event: Dictionary in _debug_events:
		lines.append("%s %s" % [String(event.get("time", "")), String(event.get("text", ""))])
	return "\n".join(lines)


func _debug_update_panel() -> void:
	if not _debug_enabled:
		return
	_ensure_debug_panel()
	if _debug_panel == null:
		return
	_debug_panel.call("set_summary_text", _debug_panel_text())
	_debug_panel.call("set_events_text", _debug_events_text())


func _ensure_debug_panel() -> void:
	if _debug_panel != null and is_instance_valid(_debug_panel):
		return
	_debug_panel = _AI_BRAIN_PANEL_SCRIPT.new() as CanvasLayer
	_debug_panel.name = "AIBrainDebugPanel"
	add_child(_debug_panel)


func _debug_print_attack() -> void:
	if _dbg_attack.is_empty():
		print("ATTACK_PLAYER")
		print("result=SKIPPED")
		print("reason=production did not evaluate this condition")
		print("")
		return
	print("ATTACK_PLAYER")
	print("result=%s" % ("TRUE" if bool(_dbg_attack.get("result", false)) else "FALSE"))
	print("")
	print("hero_exists=%s" % _debug_yes(bool(_dbg_attack.get("hero_exists", false))))
	print("army_size=%d" % int(_dbg_attack.get("army_size", 0)))
	print("minimum_army=%d" % int(_dbg_attack.get("min_army", MIN_LATE_COMBAT_UNITS)))
	print("army_minimum_pass=%s" % _debug_yes(bool(_dbg_attack.get("army_minimum_pass", false))))
	print("")
	print("ai_power=%.0f" % float(_dbg_attack.get("ai_power", 0.0)))
	print("player_power=%.0f" % float(_dbg_attack.get("player_power", 0.0)))
	print("ratio=%.3f" % float(_dbg_attack.get("ratio", 0.0)))
	print("required_ratio=%.2f" % float(_dbg_attack.get("required", ATTACK_POWER_RATIO)))
	print("")
	print("player_army_empty=%s" % _debug_yes(bool(_dbg_attack.get("player_army_empty", false))))
	var blocked: String = String(_dbg_attack.get("blocked_by", &""))
	print("blocked_by=%s" % (blocked if not blocked.is_empty() else "NONE"))
	print("")


func _debug_print_power_side(title: String, payload: Dictionary, fallback_total: float) -> void:
	print("%s = %.0f" % [title, float(payload.get("total", fallback_total))])
	var hero_line: Dictionary = payload.get("hero", {}) as Dictionary
	if not hero_line.is_empty():
		print(
			"%s lvl=%d hp=%d%% contribution=%.0f"
			% [
				String(hero_line.get("name", "Hero")),
				int(hero_line.get("level", 0)),
				int(hero_line.get("hp_pct", 0)),
				float(hero_line.get("contribution", 0.0)),
			]
		)
	var groups: Dictionary = payload.get("groups", {}) as Dictionary
	for type_key: Variant in groups.keys():
		var bucket: Dictionary = groups[type_key] as Dictionary
		print(
			"%s x%d contribution=%.0f"
			% [String(type_key), int(bucket.get("count", 0)), float(bucket.get("contribution", 0.0))]
		)


func _debug_print_power() -> void:
	print("POWER")
	print("")
	_debug_print_power_side("AI TOTAL", _dbg_power_ai, float(_w.our_power))
	print("")
	_debug_print_power_side("PLAYER TOTAL", _dbg_power_player, float(_w.player_power))
	print("")
	var player_power: float = float(_w.player_power)
	var ratio: float = 0.0 if player_power <= 0.0 else float(_w.our_power) / player_power
	print("ratio=%.3f" % ratio)
	print("required=%.2f" % ATTACK_POWER_RATIO)
	print("")


func _debug_print_creep() -> void:
	print("CREEP")
	if _dbg_creep.is_empty() and _debug_condition_state(&"EARLY_CREEP") == "SKIPPED" and _debug_condition_state(&"EXTRA_CREEP") == "SKIPPED":
		print("evaluated=NO")
		print("reason=production did not search camps")
		print("")
		return
	print("early_creep_needed=%s" % _debug_yes(bool(_dbg_creep.get("early_creep_needed", false))))
	print("hero_level=%d" % int(_dbg_creep.get("hero_level", int(_w.hero_level))))
	print("hero_level_goal=%d" % int(_dbg_creep.get("hero_level_goal", EARLY_HERO_LEVEL_TARGET)))
	print("")
	print("useful_camps_found=%d" % int(_dbg_creep.get("useful_camps_found", 0)))
	print(
		"rejected too_far=%d cleared=%d not_useful=%d invalid=%d"
		% [
			int(_dbg_creep.get("rejected_too_far", 0)),
			int(_dbg_creep.get("rejected_cleared", 0)),
			int(_dbg_creep.get("rejected_not_useful", 0)),
			int(_dbg_creep.get("rejected_invalid", 0)),
		]
	)
	var selected: String = String(_dbg_creep.get("selected", ""))
	if selected.is_empty():
		print("selected=NONE")
	else:
		print("selected=%s" % selected)
		print("distance_from_home=%.1fm" % float(_dbg_creep.get("distance_from_home", 0.0)))
		print("distance_from_army=%.1fm" % float(_dbg_creep.get("distance_from_army", 0.0)))
		print("camp_valid=%s" % _debug_yes(bool(_dbg_creep.get("camp_valid", false))))
		print("camp_alive_units=%d" % int(_dbg_creep.get("camp_alive_units", 0)))
		print("objective_point=%s" % _debug_fmt_vec(_dbg_creep.get("objective_point", Vector3.ZERO) as Vector3))
	print("")


func _debug_print_macro() -> void:
	print("MACRO")
	var workers: Dictionary = _dbg_macro.get("workers", {}) as Dictionary
	print("WORKERS")
	print("desired_total=%s" % workers.get("desired_total", "-"))
	print("actual=%s" % workers.get("actual", (_w.workers as Array).size()))
	print("train_worker=%s" % _debug_yes(bool(workers.get("train_worker", false))))
	print("reason=%s" % String(workers.get("reason", "")))
	var dist: Dictionary = _dbg_macro.get("distribution", {}) as Dictionary
	print("RESOURCE DISTRIBUTION")
	print("gold=%s" % dist.get("gold", int(_w.gold_workers)))
	print("wood=%s" % dist.get("wood", int(_w.wood_workers)))
	print("target=%s" % String(dist.get("target", "60/40")))
	print("reassignment=%s" % String(dist.get("reassignment", "none")))
	var food: Dictionary = _dbg_macro.get("food", {}) as Dictionary
	print("FOOD")
	print("used=%s" % food.get("used", int(_w.food_used)))
	print("cap=%s" % food.get("cap", int(_w.food_cap)))
	print("need_farm=%s" % _debug_yes(bool(food.get("need_farm", false))))
	print("can_afford=%s" % _debug_yes(bool(food.get("can_afford", false))))
	print("blocked_by=%s" % String(food.get("blocked_by", "NONE")))
	var hero_m: Dictionary = _dbg_macro.get("hero", {}) as Dictionary
	print("HERO")
	print("exists=%s" % _debug_yes(bool(hero_m.get("exists", _w.hero != null))))
	print("train_hero=%s" % _debug_yes(bool(hero_m.get("train_hero", false))))
	print("reason=%s" % String(hero_m.get("reason", "")))
	var barracks: Dictionary = _dbg_macro.get("barracks", {}) as Dictionary
	print("BARRACKS")
	print("wanted=%s" % _debug_yes(bool(barracks.get("wanted", false))))
	print("current=%s" % barracks.get("current", int(_w.barracks_count)))
	print("build=%s" % _debug_yes(bool(barracks.get("build", false))))
	var prod: Dictionary = _dbg_macro.get("production", {}) as Dictionary
	print("MILITARY PRODUCTION")
	print("wanted_unit=%s" % String(prod.get("wanted_unit", "-")))
	print("can_afford=%s" % _debug_yes(bool(prod.get("can_afford", false))))
	print("queue_available=%s" % _debug_yes(bool(prod.get("queue_available", true))))
	print("train=%s" % _debug_yes(bool(prod.get("train", false))))
	var t2: Dictionary = _dbg_macro.get("t2", {}) as Dictionary
	print("T2")
	print("wanted=%s" % _debug_yes(bool(t2.get("wanted", false))))
	print("allowed=%s" % _debug_yes(bool(t2.get("allowed", false))))
	print("gold_required=%s" % t2.get("gold_required", BuildingStats.CC_TIER_2_GOLD_COST))
	print("wood_required=%s" % t2.get("wood_required", BuildingStats.CC_TIER_2_WOOD_COST))
	print("blocked_by=%s" % String(t2.get("blocked_by", "NONE")))
	var t3: Dictionary = _dbg_macro.get("t3", {}) as Dictionary
	print("T3")
	print("wanted=%s" % _debug_yes(bool(t3.get("wanted", false))))
	print("reason=%s" % String(t3.get("reason", t3.get("blocked_by", ""))))
	print("BLACKSMITH wanted=%s" % _debug_yes(bool((_dbg_macro.get("blacksmith", {}) as Dictionary).get("wanted", false))))
	print("STABLE wanted=%s" % _debug_yes(bool((_dbg_macro.get("stable", {}) as Dictionary).get("wanted", false))))
	print("ARTILLERY wanted=%s" % _debug_yes(bool((_dbg_macro.get("artillery", {}) as Dictionary).get("wanted", false))))
	var expansion: Dictionary = _dbg_macro.get("expansion", {}) as Dictionary
	print("EXPANSION wanted=%s reason=%s" % [
		_debug_yes(bool(expansion.get("wanted", false))),
		String(expansion.get("reason", "")),
	])
	var tower: Dictionary = _dbg_macro.get("tower", {}) as Dictionary
	print("TOWER wanted=%s reason=%s" % [
		_debug_yes(bool(tower.get("wanted", false))),
		String(tower.get("reason", "")),
	])
	print("")


func _debug_print_strategy() -> void:
	print("STRATEGY")
	print("decision=%s" % String(_last_condition))
	print("objective_type=%s" % (_dbg_objective_type if not _dbg_objective_type.is_empty() else "-"))
	print("objective_name=%s" % (_dbg_objective_name if not _dbg_objective_name.is_empty() else "-"))
	print("objective_position=%s" % _debug_fmt_vec(_dbg_objective_position))
	var obj_dist: float = 0.0
	if _dbg_objective_position != Vector3.ZERO:
		var origin: Vector3 = _dbg_army_center if _dbg_together_evaluated else (_w.home as Vector3)
		obj_dist = _horizontal_distance(origin, _dbg_objective_position)
	print("objective_distance=%.1fm" % obj_dist)
	print("command=%s" % String(_dbg_order.get("command", "NONE")))
	print("previous_decision=%s" % String(_dbg_tick_prev_decision))
	print("previous_objective=%s" % (_dbg_tick_prev_objective if not _dbg_tick_prev_objective.is_empty() else "-"))
	print("decision_changed=%s" % _debug_yes(_last_condition != _dbg_tick_prev_decision and _dbg_tick_prev_decision != &""))
	print("objective_changed=%s" % _debug_yes(not _dbg_objective_name.is_empty() and _dbg_objective_name != _dbg_tick_prev_objective and not _dbg_tick_prev_objective.is_empty()))
	print("")


func _debug_print_order_health() -> void:
	var health: Dictionary = _debug_order_health_totals()
	print("ORDER HEALTH (10s)")
	print("ticks=%d" % int(health.get("ticks", 0)))
	print("route_requests=%d" % int(health.get("route_requests", 0)))
	print("units_ordered=%d" % int(health.get("units_ordered", 0)))
	print("identical_skipped=%d" % int(health.get("identical_skipped", 0)))
	print("destination_changes=%d" % int(health.get("destination_changes", 0)))
	print("combat_overwrote_ticks=%d" % int(health.get("combat_overwrote_ticks", 0)))
	var warning: String = String(health.get("warning", ""))
	if not warning.is_empty():
		print("warning=%s" % warning)
	print("")


func _debug_print_unit_order_changes() -> void:
	for change: Dictionary in _dbg_unit_order_changes:
		print("[UNIT ORDER CHANGE]")
		print("unit=%s" % String(change.get("unit", "")))
		print("old=%s" % String(change.get("old", "")))
		print("new=%s" % String(change.get("new", "")))
		print("old_source=%s" % String(change.get("old_source", "unknown")))
		print("new_source=%s" % String(change.get("new_source", "unknown")))
		print("strategic_objective=%s" % String(_last_condition))
		print("")


func _debug_print_cohesion() -> void:
	print("COHESION")
	if not _dbg_together_evaluated:
		print("evaluated=NO")
		print("reason=earlier priority won")
		print("")
		return
	print("army_center=%s" % _debug_fmt_vec(_dbg_army_center))
	print("hero_distance=%.1fm" % _dbg_hero_to_centroid)
	print("required_hero_distance<=%.0fm" % COHESION_RADIUS)
	print("soldiers_total=%d" % _dbg_soldiers)
	print("soldiers_near=%d" % _dbg_soldiers_near)
	print("soldiers_far=%d" % maxi(0, _dbg_soldiers - _dbg_soldiers_near))
	print("together=%s" % _debug_yes(_dbg_together))
	if not _dbg_farthest_name.is_empty():
		print("farthest_unit=%s" % _dbg_farthest_name)
		print("farthest_distance=%.1fm" % _dbg_farthest_dist)
	print("")


func _debug_print_army_members() -> void:
	print("ARMY MEMBERS")
	var center: Vector3 = _dbg_army_center
	if not _dbg_together_evaluated:
		center = _w.home as Vector3
	var objective: Vector3 = _dbg_objective_position
	for unit_v: Variant in _w.army as Array:
		if not unit_v is Unit or not NodeSafety.is_alive_node(unit_v):
			continue
		var unit: Unit = unit_v as Unit
		var order: UnitOrder = unit.get_active_order()
		var order_name: String = _debug_order_type_name(order)
		var source: String = _debug_unit_source(unit)
		var dist_army: float = _horizontal_distance(unit.global_position, center)
		var dist_obj: float = 0.0
		if objective != Vector3.ZERO:
			dist_obj = _horizontal_distance(unit.global_position, objective)
		print(_debug_node_display_name(unit))
		print("order=%s" % order_name)
		print("source=%s" % source)
		print("dist_to_army=%.1f" % dist_army)
		if objective != Vector3.ZERO:
			print("dist_to_objective=%.1f" % dist_obj)
		print("moving=%s" % _debug_yes(unit.has_move_target))
		print("combat=%s" % _debug_yes(_debug_unit_in_combat(unit)))
		if unit.has_method("get_custom_rts_route_index") and unit.has_custom_rts_route():
			print(
				"route_index=%d/%d"
				% [unit.get_custom_rts_route_index(), unit.get_custom_rts_route_waypoint_count()]
			)
	print("")


func _debug_print_workers() -> void:
	var w: Dictionary = _dbg_workers
	print("WORKERS")
	print("total=%d" % int(w.get("total", 0)))
	print("gold=%d" % int(w.get("gold", 0)))
	print("wood=%d" % int(w.get("wood", 0)))
	print("building=%d" % int(w.get("building", 0)))
	print("returning=%d" % int(w.get("returning", 0)))
	print("moving_to_resource=%d" % int(w.get("moving_to_resource", 0)))
	print("idle=%d" % int(w.get("idle", 0)))
	var invalid: Array = w.get("invalid_list", []) as Array
	print("INVALID JOBS")
	print("count=%d" % invalid.size())
	for item: Variant in invalid:
		var row: Dictionary = item as Dictionary
		print("%s:" % String(row.get("name", "")))
		print("job=%s" % String(row.get("job", "")))
		print("target_valid=%s" % _debug_yes(bool(row.get("target_valid", false))))
	var problems: Array = w.get("problem_list", []) as Array
	for item2: Variant in problems:
		var row2: Dictionary = item2 as Dictionary
		print("%s: %s" % [String(row2.get("name", "")), String(row2.get("issue", ""))])
	print("CONSTRUCTION")
	print("active_builders=%d" % int(w.get("building", 0)))
	print("unfinished_buildings=%d" % int(w.get("unfinished", 0)))
	print("abandoned=%d" % int(w.get("abandoned", 0)))
	print("")


func _debug_print_diagnosis() -> void:
	var army: Array = _w.army as Array
	var wanted: String = String(_dbg_order.get("command", ""))
	var matching: int = 0
	var different: int = 0
	var none: int = 0
	for unit_v: Variant in army:
		if not unit_v is Unit or not NodeSafety.is_alive_node(unit_v):
			continue
		var order: UnitOrder = (unit_v as Unit).get_active_order()
		var label: String = _debug_order_type_name(order)
		if label == "NONE":
			none += 1
		elif wanted.is_empty() or label == wanted:
			matching += 1
		else:
			different += 1
	print("DIAGNOSIS SNAPSHOT")
	print("")
	print("THINKING:")
	print("decision=%s" % String(_last_condition))
	print("objective=%s" % (_dbg_objective_name if not _dbg_objective_name.is_empty() else "-"))
	print("")
	print("EXECUTION:")
	print("strategic_order=%s" % (wanted if not wanted.is_empty() else "NONE"))
	print("army_members=%d" % army.size())
	print("matching_order=%d" % matching)
	print("different_order=%d" % different)
	print("no_order=%d" % none)
	print("")
	print("THINKING=%s" % String(_last_condition))
	print("EXECUTION_MATCH=%d/%d" % [matching, army.size()])
	if int(_dbg_order.get("combat_overwrote", 0)) > 0:
		print("combat_overwrote_strategic_order=%d" % int(_dbg_order.get("combat_overwrote", 0)))
	print("")


func _debug_snapshot_workers() -> void:
	if not _debug_enabled:
		return
	var gold: int = 0
	var wood: int = 0
	var building: int = 0
	var returning: int = 0
	var moving: int = 0
	var idle: int = 0
	var invalid_list: Array = []
	var problem_list: Array = []
	var unfinished: int = 0
	var abandoned: int = 0
	for worker_v: Variant in _w.workers as Array:
		if not worker_v is Worker or not NodeSafety.is_alive_node(worker_v):
			continue
		var worker: Worker = worker_v as Worker
		var resource_id: StringName = worker.get_assigned_gather_resource_id()
		if worker.is_on_construction_trip():
			building += 1
			continue
		if worker.is_carrying_gathered_resources():
			returning += 1
		if worker.is_enemy_gather_fallback_idle():
			idle += 1
			problem_list.append({"name": worker.name, "issue": "unexpectedly idle"})
			continue
		if resource_id == &"gold":
			gold += 1
		elif resource_id == &"wood":
			wood += 1
		else:
			invalid_list.append({
				"name": worker.name,
				"job": String(resource_id) if not String(resource_id).is_empty() else "NONE",
				"target_valid": not worker.needs_gather_target_reassignment(),
			})
			continue
		if worker.has_move_target and not worker.is_carrying_gathered_resources():
			moving += 1
		if worker.is_physically_blocked_from_current_move():
			problem_list.append({"name": worker.name, "issue": "stuck"})
		if worker.needs_gather_target_reassignment():
			invalid_list.append({
				"name": worker.name,
				"job": String(resource_id),
				"target_valid": false,
			})
	var tree: SceneTree = _w.tree as SceneTree
	if tree != null:
		for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
			if not node is Building or not NodeSafety.is_alive_node(node):
				continue
			var building_n: Building = node as Building
			if building_n.is_being_constructed():
				unfinished += 1
				if not building_n.has_assigned_builder() and not _has_worker_en_route_to_building(building_n):
					abandoned += 1
	_dbg_workers = {
		"total": (_w.workers as Array).size(),
		"gold": gold,
		"wood": wood,
		"building": building,
		"returning": returning,
		"moving_to_resource": moving,
		"idle": idle,
		"invalid": invalid_list.size(),
		"invalid_list": invalid_list,
		"problem_list": problem_list,
		"unfinished": unfinished,
		"abandoned": abandoned,
	}


func _debug_trace_unit_order_changes() -> void:
	if not _debug_enabled:
		return
	var seen: Dictionary = {}
	for unit_v: Variant in _w.army as Array:
		if not unit_v is Unit or not NodeSafety.is_alive_node(unit_v):
			continue
		var unit: Unit = unit_v as Unit
		var id: int = unit.get_instance_id()
		seen[id] = true
		var order: UnitOrder = unit.get_active_order()
		var order_name: String = _debug_order_type_name(order)
		var source: String = _debug_unit_source(unit)
		var dest: Vector3 = order.destination if order != null else Vector3.ZERO
		var prev: Dictionary = _dbg_unit_orders.get(id, {}) as Dictionary
		if not prev.is_empty():
			var old_name: String = String(prev.get("order", "NONE"))
			var old_source: String = String(prev.get("source", "unknown"))
			var old_dest: Vector3 = prev.get("dest", Vector3.ZERO) as Vector3
			var dest_changed: bool = _horizontal_distance(old_dest, dest) > ORDER_DEST_RADIUS
			if old_name != order_name or old_source != source or dest_changed:
				_dbg_unit_order_changes.append({
					"unit": _debug_node_display_name(unit),
					"old": old_name,
					"new": order_name,
					"old_source": old_source,
					"new_source": source,
				})
		_dbg_unit_orders[id] = {
			"order": order_name,
			"source": source,
			"dest": dest,
		}
	var stale: Array = []
	for key: Variant in _dbg_unit_orders.keys():
		if not seen.has(key):
			stale.append(key)
	for stale_id: Variant in stale:
		_dbg_unit_orders.erase(stale_id)


func _debug_record_order_health() -> void:
	if not _debug_enabled:
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	_dbg_health_samples.append({
		"t": now,
		"decision": String(_last_condition),
		"objective": _dbg_objective_name,
		"route": 1 if bool(_dbg_order.get("route_request", false)) else 0,
		"ordered": int(_dbg_order.get("ordered", 0)),
		"skipped": 1 if bool(_dbg_order.get("identical_skipped", false)) else 0,
		"dest_change": 1 if float(_dbg_order.get("destination_change", 0.0)) > ORDER_DEST_RADIUS else 0,
		"combat": 1 if int(_dbg_order.get("combat_overwrote", 0)) > 0 else 0,
	})
	var cutoff: float = now - DEBUG_ORDER_HEALTH_WINDOW
	while not _dbg_health_samples.is_empty() and float(_dbg_health_samples[0].get("t", 0.0)) < cutoff:
		_dbg_health_samples.remove_at(0)


func _debug_order_health_totals() -> Dictionary:
	var ticks: int = _dbg_health_samples.size()
	var routes: int = 0
	var ordered: int = 0
	var skipped: int = 0
	var dest_changes: int = 0
	var combat_ticks: int = 0
	var same_decision: bool = true
	var first_decision: String = ""
	var first_objective: String = ""
	for sample: Dictionary in _dbg_health_samples:
		routes += int(sample.get("route", 0))
		ordered += int(sample.get("ordered", 0))
		skipped += int(sample.get("skipped", 0))
		dest_changes += int(sample.get("dest_change", 0))
		combat_ticks += int(sample.get("combat", 0))
		var decision: String = String(sample.get("decision", ""))
		var objective: String = String(sample.get("objective", ""))
		if first_decision.is_empty():
			first_decision = decision
			first_objective = objective
		elif decision != first_decision or objective != first_objective:
			same_decision = false
	var warning: String = ""
	if ticks >= 4 and same_decision and routes >= int(ceil(float(ticks) * 0.7)):
		if combat_ticks * 2 >= routes:
			warning = "COMBAT_OVERWROTE_STRATEGIC_ORDER"
		elif dest_changes * 2 >= routes:
			warning = "MOVING_STRATEGIC_DESTINATION"
		else:
			warning = "REPEATED_ROUTE_REQUESTS"
	return {
		"ticks": ticks,
		"route_requests": routes,
		"units_ordered": ordered,
		"identical_skipped": skipped,
		"destination_changes": dest_changes,
		"combat_overwrote_ticks": combat_ticks,
		"warning": warning,
	}


func _debug_node_display_name(node: Node) -> String:
	if node.has_method("get_display_name"):
		return String(node.call("get_display_name"))
	return node.name


func _debug_unit_type_key(unit: Node) -> String:
	if unit is Spearman:
		return "Spearman"
	if unit is Swordsman:
		return "Swordsman"
	if unit is Archer:
		return "Archer"
	if unit is LightCavalry:
		return "LightCavalry"
	if unit is HeavyCavalry:
		return "HeavyCavalry"
	if unit is CavalryArcher:
		return "CavalryArcher"
	if unit is Cannon:
		return "Cannon"
	return unit.get_class()


func _debug_order_type_name(order: UnitOrder) -> String:
	if order == null:
		return "NONE"
	match order.type:
		UnitOrder.Type.MOVE:
			return "MOVE"
		UnitOrder.Type.ATTACK:
			return "ATTACK"
		UnitOrder.Type.ATTACK_MOVE:
			return "ATTACK_MOVE"
		UnitOrder.Type.PATROL:
			return "PATROL"
		UnitOrder.Type.HOLD_POSITION:
			return "HOLD_POSITION"
		UnitOrder.Type.STOP:
			return "STOP"
		UnitOrder.Type.BUILD:
			return "BUILD"
		UnitOrder.Type.GATHER:
			return "GATHER"
		_:
			return "OTHER"


func _debug_unit_source(unit: Unit) -> String:
	var prov: Dictionary = unit.get_strategic_order_provenance()
	var source: String = String(prov.get("source", "UNKNOWN"))
	if source.is_empty() or source == "UNKNOWN":
		var order: UnitOrder = unit.get_active_order()
		if order != null and order.type == UnitOrder.Type.ATTACK:
			return "unknown(attack-order; provenance often unset)"
		return "unknown(strategic provenance often unset)"
	return source


func _debug_unit_in_combat(unit: Unit) -> bool:
	if unit.has_method("get_attack_target"):
		return NodeSafety.is_alive_node(unit.call("get_attack_target"))
	if unit is MilitaryUnit:
		return NodeSafety.is_alive_node((unit as MilitaryUnit)._attack_target)
	return false


func _debug_hp_pct(node: Node) -> int:
	var health: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.max_health <= 0:
		return 0
	return int(round(100.0 * float(health.current_health) / float(health.max_health)))


func _debug_fmt_vec(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]


func _debug_yes(value: bool) -> String:
	return "YES" if value else "NO"
