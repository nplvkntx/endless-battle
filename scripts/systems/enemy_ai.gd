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
## Hero leash vs main soldier cluster — slightly looser than soldier packing so
## brief engage leads do not flip CREEP↔REGROUP every tick. 20m+ still breaks it.
const HERO_COHESION_RADIUS: float = 18.0
## Order-follow tolerance around the shared strategic destination (slots + path noise).
const ORDER_DEST_RADIUS: float = 16.0
## Regroup arrival — Hero/soldiers considered gathered at the cluster point.
const REGROUP_ARRIVE_RADIUS: float = 6.0
## Far attack-move standoff short of the objective (not the Town Center itself).
const ATTACK_APPROACH_STANDOFF: float = 14.0
const ATTACK_ENGAGE_RADIUS: float = 18.0
const CAMP_SEARCH_RANGE: float = 70.0
const ATTACK_POWER_RATIO: float = 1.25
## Live hero-death exception: keep pressing a winning local base fight.
const CONTINUE_ATTACK_POWER_RATIO: float = 1.0
const CONTINUE_ATTACK_MIN_SOLDIERS: int = 3
const ENEMY_BASE_COMBAT_RADIUS: float = 27.0
const FOOD_SAFETY_MARGIN: int = 4
const MIN_EARLY_SPEARMEN: int = 5
const EARLY_CAMPS_REQUIRED: int = 3
const EARLY_HERO_LEVEL_TARGET: int = 3
const GOLD_WORKER_RATIO: float = 0.6
const HOME_OFFSET: Vector3 = Vector3(-2.0, 0.0, 3.0)
const CRITICAL_WOOD_RESERVE: int = 40
const ARMY_SOFT_CAP: int = 36
const CREEP_STAGING_STANDOFF: float = 10.0
## Arrive at staging / begin camp fight — keep wider than COHESION so travel→engage does not flicker.
const CREEP_ARRIVE_RADIUS: float = 14.0
const CREEP_ENGAGE_RADIUS: float = 16.0
const HERO_MICRO_INTERVAL: float = 0.3
const MAX_CREEP_ROUTE_FAILURES: int = 3
const T3_ARMY_MINIMUM: int = 8
const T3_WORKER_MINIMUM: int = 18
const T3_GOLD_NEAR_COST: int = BuildingStats.CC_TIER_3_GOLD_COST + 200
const CONDITION_CHANGE_WINDOW_SECONDS: float = 10.0
const HERO_UNSTUCK_HOLD_RADIUS: float = 8.0

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
const CMD_CREEP: StringName = &"creep"
const CMD_ATTACK: StringName = &"attack"
const CMD_REGROUP: StringName = &"regroup"
const CMD_ATTACK_MARCH: StringName = &"attack_march"
const CMD_HERO_UNSTUCK: StringName = &"hero_unstuck"

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
var _debug_last_logged_condition: StringName = &""
var _debug_previous_condition: StringName = &""
var _debug_overlay_lines: PackedStringArray = PackedStringArray()
var _hero_micro_timer: float = 0.0
var _creep_route_failures: Dictionary = {} ## camp_id -> fail count
var _invalid_creep_camp_ids: Dictionary = {}
var _condition_change_times_msec: Array[int] = []
## Debug-only: instance ids already logged as unexpected ATTACK_PLAYER idle (edge-triggered).
var _attack_idle_logged_ids: Dictionary = {}

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
	_debug_last_logged_condition = &""
	_debug_previous_condition = &""
	_debug_overlay_lines = PackedStringArray()
	_hero_micro_timer = 0.0
	_creep_route_failures.clear()
	_invalid_creep_camp_ids.clear()
	_condition_change_times_msec.clear()
	_attack_idle_logged_ids.clear()
	_w.clear()
	_update_debug_overlay()


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

	## Economy / tech / production — may all run; do not freeze military.
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

	## Military — first true condition wins. Live facts are the only memory.
	## Defense overrides regroup / offense when the base is under real threat.
	var threat: Node3D = _find_base_threat()
	if threat != null:
		_whole_army_attack(threat, CMD_DEFEND)
		_finish_military_decision(&"DEFEND", &"DEFEND", &"DEFEND", threat)
		return

	if _w.hero == null:
		## Hero death must not auto-HOME a winning live fight already inside the player base.
		if _can_continue_current_enemy_base_fight_without_hero():
			_attack_player_with_whole_army()
			_finish_military_decision(
				&"ATTACK_PLAYER",
				&"ATTACK_NO_HERO_CONTINUE",
				&"ATTACK_PLAYER",
				_resolve_debug_target_node()
			)
			return
		_army_home()
		_finish_military_decision(&"HOME", &"HOME_NO_HERO", &"HERO", null)
		return

	if _army_below_minimum():
		_army_home()
		_finish_military_decision(&"HOME", &"HOME_ARMY_SMALL", &"BUILD_FORCE", null)
		return

	if _hero_is_physically_stuck():
		_fix_current_hero_movement()
		_finish_military_decision(&"HERO_STUCK", &"HERO_STUCK", &"UNSTUCK", null)
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
	if int(_w.tier) >= 2 and int(_w.towers) < AIDifficultyConfig.get_desired_tower_count():
		return wood < BuildingStats.TOWER_WOOD_COST
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

	## Tier 3 — economy-stable gate; expansion optional if gold near T3 cost.
	if (
		int(_w.tier) == 2
		and _w.blacksmith_completed
		and int((_w.army as Array).size()) >= T3_ARMY_MINIMUM
		and int((_w.workers as Array).size()) >= T3_WORKER_MINIMUM
		and (
			_w.expansion_cc != null
			or _w.gold >= T3_GOLD_NEAR_COST
			or EnemyResourceManager.can_afford(
				BuildingStats.CC_TIER_3_GOLD_COST,
				BuildingStats.CC_TIER_3_WOOD_COST
			)
		)
	):
		var cc_t3: CommandCenter = _w.primary_cc as CommandCenter
		if cc_t3 != null and cc_t3.can_try_enemy_upgrade_tier(3):
			cc_t3.try_upgrade_enemy_tier(3)
			return

	## Artillery Depot after unlock
	if (
		TechTree.can_build_artillery_depot(ENEMY_TEAM_ID)
		and int(_w.artillery_count) < AIDifficultyConfig.get_max_military_buildings(&"artillery_depot")
		and not _w.artillery_constructing
		and (not _w.artillery_completed or int(_w.tier) >= 3)
	):
		if EnemyResourceManager.can_afford(
			BuildingStats.ARTILLERY_DEPOT_GOLD_COST,
			BuildingStats.ARTILLERY_DEPOT_WOOD_COST
		):
			_build_manager.try_place_artillery_depot()


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


func _ensure_towers() -> void:
	if _build_manager == null:
		return
	if int(_w.tier) < 2:
		return
	if int(_w.towers) >= AIDifficultyConfig.get_desired_tower_count():
		return
	if _w.tower_constructing:
		return
	## Do not block T2 / Hero / critical buildings.
	if int(_w.tier) < 2 and _w.gold < BuildingStats.CC_TIER_2_GOLD_COST:
		return
	if _should_reserve_hero_gold():
		return
	if not EnemyResourceManager.can_afford(BuildingStats.TOWER_GOLD_COST, BuildingStats.TOWER_WOOD_COST):
		return
	if _w.gold < BuildingStats.TOWER_GOLD_COST + 150:
		return
	var toward: Vector3 = Vector3.INF
	if _w.player_cc != null and NodeSafety.is_alive_node(_w.player_cc):
		toward = (_w.player_cc as Node3D).global_position
	_build_manager.try_place_tower(toward)


func _ensure_expansion() -> void:
	if _build_manager == null:
		return
	if int(_w.tier) < 2:
		return
	if _w.expansion_cc != null or _w.expansion_constructing:
		return
	if int((_w.workers as Array).size()) < AIDifficultyConfig.DESIRED_WORKERS_T2:
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
			if stable_prod.try_train_enemy_light_cavalry():
				_w.light_cavalry += 1
				continue
		if int(_w.tier) >= 2 and heavy < DESIRED_HEAVY_CAVALRY:
			if stable_prod.try_train_enemy_heavy_cavalry():
				_w.heavy_cavalry += 1
				continue
		if int(_w.tier) >= 2 and cav_archers < DESIRED_CAVALRY_ARCHERS:
			if stable_prod.try_train_enemy_cavalry_archer():
				_w.cavalry_archers += 1
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

func _army_below_minimum() -> bool:
	return int(_w.spearmen) < MIN_EARLY_SPEARMEN


func _needs_early_creep() -> bool:
	## Prefer creeping until Hero level 3 OR 3 camps cleared — whichever first.
	_release_cleared_committed_creep_camp()
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
	_release_cleared_committed_creep_camp()
	return _pick_safe_creep_camp() != null


func _creep_with_whole_army() -> void:
	var camp: Node3D = _resolve_creep_camp()
	if camp == null:
		return
	## Living creeps gate camp validity; individual creeps are never strategic targets.
	if _find_living_creep_in_camp(camp) == null:
		return

	var camp_id: int = camp.get_instance_id()
	var staging: Vector3 = _compute_creep_staging_point(camp)
	var hero: Hero = _w.hero as Hero
	var hero_pos: Vector3 = hero.global_position if hero != null else staging
	var near_camp: bool = (
		_horizontal_distance(hero_pos, staging) <= CREEP_ARRIVE_RADIUS
		or _horizontal_distance(hero_pos, camp.global_position) <= CREEP_ENGAGE_RADIUS
	)

	_assert_cohesive_strategic_order(CMD_CREEP)
	## Far: attack-move to staging. Near: attack-move into camp area.
	## Local Unit/Hero combat acquires individual creeps — never command_attack from EnemyAI.
	if near_camp:
		_clear_army_strategic_speed_caps()
		_issue_army_move(
			_nearest_walkable_dest(camp.global_position),
			&"attack_move",
			CMD_CREEP,
			camp_id
		)
		return
	_issue_army_move(staging, &"attack_move", CMD_CREEP, camp_id)


## Walkable staging on the HOME-facing side of the camp (avoids converging into creep bodies).
func _compute_creep_staging_point(camp: Node3D) -> Vector3:
	var home: Vector3 = _w.home as Vector3
	var camp_pos: Vector3 = camp.global_position
	var away: Vector3 = home - camp_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(1.0, 0.0, 0.0)
	else:
		away = away.normalized()
	var staging: Vector3 = camp_pos + away * CREEP_STAGING_STANDOFF
	return _nearest_walkable_dest(staging)


func _hero_is_physically_stuck() -> bool:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return false
	if hero is MeleeHero:
		var target: Node3D = (hero as MeleeHero).get_attack_target()
		if NodeSafety.is_alive_node(target) and hero.has_method(&"_is_in_attack_range"):
			if VariantUtils.to_bool(hero.call(&"_is_in_attack_range", target)):
				return false
	return hero.is_physically_blocked_from_current_move()


func _fix_current_hero_movement() -> void:
	var hero: Hero = _w.hero as Hero
	if hero == null or not NodeSafety.is_alive_node(hero):
		return
	## Invalidate current creep camp after repeated route failures.
	if _last_command_kind == CMD_CREEP and _current_target_id != 0:
		var fails: int = int(_creep_route_failures.get(_current_target_id, 0)) + 1
		_creep_route_failures[_current_target_id] = fails
		if fails >= MAX_CREEP_ROUTE_FAILURES:
			_invalid_creep_camp_ids[_current_target_id] = true
			_current_target_id = 0
			_last_command_kind = CMD_NONE
			_last_command_target_id = 0

	var escape: Vector3 = _pick_hero_escape_point(hero)
	hero.set_movement_target(escape, Unit.RepathUrgency.STUCK_RECOVERY)
	hero.record_strategic_order_provenance_for_tests("EnemyAI", "HERO_UNSTUCK", escape)
	## Local Hero unstuck only — army HOLDS near the main cluster, never piles onto
	## the Hero's tiny escape cell (that recreates congestion + REGROUP thrash).
	_hold_army_during_hero_unstuck(hero, escape)


func _hold_army_during_hero_unstuck(hero: Hero, hero_escape: Vector3) -> void:
	var soldiers: Array = _get_live_soldiers()
	if soldiers.is_empty():
		_last_command_kind = CMD_HERO_UNSTUCK
		_last_command_target_id = 0
		_last_command_army_count = (_w.army as Array).size()
		_last_command_destination = hero_escape
		return

	var hold: Vector3 = _nearest_walkable_dest(_main_army_centroid())
	## If the cluster already sits on the escape cell, hold slightly off it toward home.
	if _horizontal_distance(hold, hero_escape) < 3.0:
		var home: Vector3 = _w.home as Vector3
		var away: Vector3 = hold - hero_escape
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = home - hero.global_position
			away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3(1.0, 0.0, 0.0)
		else:
			away = away.normalized()
		hold = _nearest_walkable_dest(hero_escape + away * HERO_UNSTUCK_HOLD_RADIUS)

	## Never command soldiers onto the Hero escape point — hold nearby or stop.
	var movers: Array = []
	for unit_variant: Variant in soldiers:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		var soldier: Unit = unit_variant as Unit
		if _horizontal_distance(soldier.global_position, hold) > HERO_UNSTUCK_HOLD_RADIUS:
			movers.append(soldier)
		else:
			soldier.stop_movement()
			soldier.record_strategic_order_provenance_for_tests("EnemyAI", "HERO_UNSTUCK_HOLD", hold)

	if not movers.is_empty():
		## Compatible-order skip against previous hold destination.
		if not (
			_last_command_kind == CMD_HERO_UNSTUCK
			and _horizontal_distance(_last_command_destination, hold) <= ORDER_DEST_RADIUS
			and _soldiers_following_hold(movers, hold)
		):
			var result: Dictionary = PlayerRouteNavigation.request_group_move(
				movers,
				hold,
				&"move",
				false,
				&"enemy_ai"
			)
			if not bool(result.get("handled", false)):
				for mover_variant: Variant in movers:
					(mover_variant as Unit).set_movement_target(hold)
			for mover_variant2: Variant in movers:
				(mover_variant2 as Unit).record_strategic_order_provenance_for_tests(
					"EnemyAI",
					"HERO_UNSTUCK_HOLD",
					hold
				)

	_last_command_kind = CMD_HERO_UNSTUCK
	_last_command_target_id = 0
	_last_command_army_count = (_w.army as Array).size()
	_last_command_destination = hold


func _soldiers_following_hold(soldiers: Array, hold: Vector3) -> bool:
	var ok: int = 0
	var living: int = 0
	for unit_variant: Variant in soldiers:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		living += 1
		if _unit_destination_near_expected(unit_variant as Unit, hold):
			ok += 1
	if living <= 0:
		return true
	return ok * 4 >= living * 3


func _pick_hero_escape_point(hero: Hero) -> Vector3:
	var home: Vector3 = _w.home as Vector3
	var away: Vector3 = hero.global_position - home
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(1.0, 0.0, 0.0)
	else:
		away = away.normalized()
	## Step sideways / homeward out of the congestion.
	var candidates: Array[Vector3] = [
		hero.global_position + away * 4.0,
		hero.global_position - away * 4.0,
		hero.global_position + Vector3(-away.z, 0.0, away.x) * 4.0,
		hero.global_position + Vector3(away.z, 0.0, -away.x) * 4.0,
		home,
	]
	for candidate: Vector3 in candidates:
		var walkable: Vector3 = _nearest_walkable_dest(candidate)
		if _horizontal_distance(hero.global_position, walkable) >= 1.5:
			return walkable
	return _nearest_walkable_dest(home)
func _attack_player_with_whole_army() -> void:
	var target: Node3D = _select_player_target()
	if target == null:
		return

	var target_pos: Vector3 = target.global_position
	var army_center: Vector3 = _main_army_centroid()
	var dist_to_target: float = _horizontal_distance(army_center, target_pos)

	## Far: shared attack-move to an approach point (not direct command_attack across the map).
	if dist_to_target > ATTACK_ENGAGE_RADIUS:
		_assert_cohesive_strategic_order(CMD_ATTACK_MARCH)
		var approach: Vector3 = _compute_attack_approach(target_pos, army_center)
		_issue_army_move(approach, &"attack_move", CMD_ATTACK_MARCH, target.get_instance_id())
		_refresh_idle_attack_participants(target)
		return

	## Close only when the army itself arrived — never focus-fire from afar.
	if _army_near_position(target_pos, ATTACK_ENGAGE_RADIUS) * 2 < (_w.army as Array).size():
		_assert_cohesive_strategic_order(CMD_ATTACK_MARCH)
		var approach_close: Vector3 = _compute_attack_approach(target_pos, army_center)
		_issue_army_move(approach_close, &"attack_move", CMD_ATTACK_MARCH, target.get_instance_id())
		_refresh_idle_attack_participants(target)
		return

	## Near: whole local force fights the objective — Hero must never be the sole attacker.
	_assert_cohesive_strategic_order(CMD_ATTACK)
	_clear_army_strategic_speed_caps()
	_whole_army_attack(target, CMD_ATTACK)
	_refresh_idle_attack_participants(target)


## Live facts only — no attack_started memory.
func _can_continue_current_enemy_base_fight_without_hero() -> bool:
	if (_w.army as Array).is_empty():
		return false
	if _count_soldiers() < CONTINUE_ATTACK_MIN_SOLDIERS:
		return false
	if not _army_is_currently_in_enemy_base_combat():
		return false
	return _remaining_army_strong_enough_to_continue_attack()


func _army_is_currently_in_enemy_base_combat() -> bool:
	var base: Node3D = null
	if (
		NodeSafety.is_alive_node(_w.player_cc)
		and CombatTargetValidation.is_player_faction(_w.player_cc)
	):
		base = _w.player_cc as Node3D
	else:
		base = _select_player_target()
	if base == null or not NodeSafety.is_alive_node(base):
		return false
	if not CombatTargetValidation.is_player_faction(base):
		return false

	var base_pos: Vector3 = base.global_position
	var centroid: Vector3 = _main_army_centroid()
	var soldiers_near: int = 0
	for unit_variant: Variant in _get_live_soldiers():
		if not unit_variant is Node3D or not NodeSafety.is_alive_node(unit_variant):
			continue
		if _horizontal_distance((unit_variant as Node3D).global_position, base_pos) <= ENEMY_BASE_COMBAT_RADIUS:
			soldiers_near += 1
	var soldiers_total: int = _count_soldiers()
	var mass_near_base: bool = (
		soldiers_near * 2 >= maxi(1, soldiers_total)
		or _horizontal_distance(centroid, base_pos) <= ENEMY_BASE_COMBAT_RADIUS
	)
	if not mass_near_base:
		return false

	## Player combatants or the structure objective must still be local.
	var local_player: Node3D = _nearest_from_list(
		_w.player_army as Array,
		centroid,
		ENEMY_BASE_COMBAT_RADIUS
	)
	var structure_local: bool = _horizontal_distance(centroid, base_pos) <= ENEMY_BASE_COMBAT_RADIUS
	if local_player == null and not structure_local:
		return false

	var intent: Dictionary = _classify_army_attack_intent(base_pos)
	## Already fighting / marching there, or sitting on the objective idle (will re-issue).
	return (
		int(intent.get("combat", 0)) > 0
		or int(intent.get("travel", 0)) > 0
		or int(intent.get("blocked", 0)) > 0
		or soldiers_near >= CONTINUE_ATTACK_MIN_SOLDIERS
	)


func _remaining_army_strong_enough_to_continue_attack() -> bool:
	var our_power: float = float(_w.our_power)
	var player_power: float = float(_w.player_power)
	if our_power <= 0.0:
		return false
	return our_power >= player_power * CONTINUE_ATTACK_POWER_RATIO


func _classify_army_attack_intent(expected_destination: Vector3) -> Dictionary:
	var travel: int = 0
	var combat: int = 0
	var idle: int = 0
	var blocked: int = 0
	var other: int = 0
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		var unit: Unit = unit_variant as Unit
		var has_attack: bool = false
		if "_attack_target" in unit:
			var attack_target: Variant = unit.get("_attack_target")
			if NodeSafety.is_alive_node(attack_target):
				has_attack = true
		var travelling: bool = (
			unit.has_move_target
			or (
				"_has_attack_move_destination" in unit
				and bool(unit.get("_has_attack_move_destination"))
			)
		)
		var is_blocked: bool = false
		if unit.has_method(&"is_physically_blocked_from_current_move"):
			is_blocked = bool(unit.call(&"is_physically_blocked_from_current_move"))

		if has_attack:
			combat += 1
		elif is_blocked and travelling:
			blocked += 1
		elif travelling:
			travel += 1
		elif (
			not unit.has_move_target
			and not (
				"_has_attack_move_destination" in unit
				and bool(unit.get("_has_attack_move_destination"))
			)
			and not has_attack
		):
			## Idle nearby objective still counts as idle for diagnostics.
			if (
				expected_destination != Vector3.ZERO
				and _horizontal_distance(unit.global_position, expected_destination)
				<= ENEMY_BASE_COMBAT_RADIUS
			):
				idle += 1
			else:
				other += 1
		else:
			other += 1
	return {
		"travel": travel,
		"combat": combat,
		"idle": idle,
		"blocked": blocked,
		"other": other,
	}


## During ATTACK_PLAYER near the objective: refresh only unexpected IDLE members.
## Does not reissue the whole army — only units with no attack / move / attack-move intent.
func _refresh_idle_attack_participants(objective: Node3D) -> void:
	if not NodeSafety.is_alive_node(objective):
		return

	var objective_pos: Vector3 = objective.global_position
	var army: Array = _w.army as Array
	for unit_variant: Variant in army:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		var unit: Unit = unit_variant as Unit
		if _horizontal_distance(unit.global_position, objective_pos) > ENEMY_BASE_COMBAT_RADIUS:
			continue
		if "_attack_target" in unit and NodeSafety.is_alive_node(unit.get("_attack_target")):
			continue
		if unit.has_move_target:
			continue
		if (
			"_has_attack_move_destination" in unit
			and bool(unit.get("_has_attack_move_destination"))
		):
			continue
		if unit.has_method(&"is_physically_blocked_from_current_move"):
			if bool(unit.call(&"is_physically_blocked_from_current_move")):
				continue
		if not CombatTargetValidation.is_attack_target_for_attacker(unit, objective):
			## Objective temporarily invalid for this unit — attack-move into the fight area.
			unit.command_attack_move(objective_pos)
			unit.record_strategic_order_provenance_for_tests(
				"EnemyAI",
				"ATTACK_MOVE",
				objective_pos
			)
			continue
		unit.command_attack(objective)
		unit.record_strategic_order_provenance_for_tests(
			"EnemyAI",
			"ATTACK",
			objective.global_position
		)


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
	var recipients: Array = _units_needing_order_refresh(
		command_kind,
		target_id,
		army,
		target.global_position
	)
	if recipients.is_empty():
		return

	_clear_army_strategic_speed_caps()
	for unit_variant: Variant in recipients:
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
## AND Hero within HERO_COHESION of that same centroid.
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
	if _horizontal_distance(hero.global_position, centroid) > HERO_COHESION_RADIUS:
		return false
	return true


func _count_soldiers() -> int:
	return _get_live_soldiers().size()
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
	## Hero-less continue-attack is an intentional live exception.
	if _w.hero == null:
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
	var recipients: Array = _units_needing_order_refresh(
		command_kind,
		target_id,
		army,
		destination
	)
	if recipients.is_empty():
		return

	var units: Array = []
	for unit_variant: Variant in recipients:
		if unit_variant is Unit and NodeSafety.is_alive_node(unit_variant):
			units.append(unit_variant)

	if units.is_empty():
		return

	## Bound Hero strategic travel to the slowest soldier so the pack does not stretch.
	_apply_strategic_speed_caps(army)

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


## Cache match + missing units only — never skip a meaningful idle Pike because majority is fine.
func _units_needing_order_refresh(
	command_kind: StringName,
	target_id: int,
	army: Array,
	expected_destination: Vector3
) -> Array:
	var living: Array = []
	for unit_variant: Variant in army:
		if unit_variant is Unit and NodeSafety.is_alive_node(unit_variant):
			living.append(unit_variant)
	if living.is_empty():
		return []

	var cache_matches: bool = (
		_last_command_kind == command_kind
		and _last_command_target_id == target_id
		and _last_command_army_count == army.size()
	)
	if not cache_matches:
		return living

	var missing: Array = []
	for unit_variant2: Variant in living:
		var unit: Unit = unit_variant2 as Unit
		if not _unit_has_compatible_strategic_order(
			unit,
			command_kind,
			target_id,
			expected_destination
		):
			missing.append(unit)
	return missing


## Skip reissue only when cache matches AND every living unit still executes a compatible order.
func _should_skip_reissue(
	command_kind: StringName,
	target_id: int,
	army: Array,
	expected_destination: Vector3
) -> bool:
	return _units_needing_order_refresh(
		command_kind,
		target_id,
		army,
		expected_destination
	).is_empty()


func _army_is_following_command(
	command_kind: StringName,
	target_id: int,
	expected_destination: Vector3
) -> bool:
	var army: Array = _w.army as Array
	if army.is_empty():
		return true
	for unit_variant: Variant in army:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		var unit: Unit = unit_variant as Unit
		if not _unit_has_compatible_strategic_order(unit, command_kind, target_id, expected_destination):
			return false
	return true


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

	## Creep: strategic target is the camp; local combat may attack any living creep.
	if command_kind == CMD_CREEP:
		if "_attack_target" in unit:
			var creep_target: Variant = unit.get("_attack_target")
			if (
				NodeSafety.is_alive_node(creep_target)
				and CombatTargetValidation.is_neutral_creep(creep_target)
			):
				return true
		## Idle at staging with cancelled attack-move is NOT following.
		return _unit_destination_near_expected(unit, expected_destination, true)

	## Attack-march: active travel toward the shared area, or local fight near it.
	## Standing idle at the approach slot with no attack is NOT following — refresh that unit.
	if command_kind == CMD_ATTACK_MARCH:
		if "_attack_target" in unit:
			var march_target: Variant = unit.get("_attack_target")
			if (
				NodeSafety.is_alive_node(march_target)
				and CombatTargetValidation.is_attack_target_for_attacker(unit, march_target)
			):
				return true
		if unit.has_move_target:
			return _unit_destination_near_expected(unit, expected_destination, true)
		if "_has_attack_move_destination" in unit and bool(unit.get("_has_attack_move_destination")):
			var am_dest: Vector3 = unit.get("_attack_move_destination") as Vector3
			var to_am: Vector3 = unit.global_position - am_dest
			to_am.y = 0.0
			## Still marching toward the attack-move point.
			if to_am.length() > unit.get_movement_acceptance_radius():
				return _horizontal_distance(am_dest, expected_destination) <= ORDER_DEST_RADIUS
		return false

	## Move / regroup / home: standing inside the expected area counts as following.
	return _unit_destination_near_expected(unit, expected_destination, false)


func _unit_destination_near_expected(
	unit: Unit,
	expected_destination: Vector3,
	require_active_travel: bool = false
) -> bool:
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
		if require_active_travel:
			return false
		## Already standing inside the expected area counts as following for plain moves.
		return _horizontal_distance(unit.global_position, expected_destination) <= ORDER_DEST_RADIUS

	for dest: Vector3 in candidates:
		if _horizontal_distance(dest, expected_destination) <= ORDER_DEST_RADIUS:
			return true
	return false
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
	if (
		NodeSafety.is_alive_node(_w.player_cc)
		and CombatTargetValidation.is_player_faction(_w.player_cc)
	):
		return _w.player_cc as Node3D

	## 4) Production buildings
	for building_variant: Variant in _w.player_buildings as Array:
		if not building_variant is Building:
			continue
		var building: Building = building_variant as Building
		if not NodeSafety.is_alive_node(building):
			continue
		if not CombatTargetValidation.is_player_faction(building):
			continue
		if building is Barracks or building is Stable or building is ArtilleryDepot or building is HeroAltar:
			return building

	## 5) Any remaining important player building
	for building_variant: Variant in _w.player_buildings as Array:
		if not building_variant is Building or not NodeSafety.is_alive_node(building_variant):
			continue
		if not CombatTargetValidation.is_player_faction(building_variant):
			continue
		return building_variant as Node3D

	return null


func _resolve_creep_camp() -> Node3D:
	## Strategic creep target is always a CAMP id — never an individual creep.
	_release_cleared_committed_creep_camp()
	if _current_target_id != 0 and is_instance_id_valid(_current_target_id):
		var existing: Variant = instance_from_id(_current_target_id)
		if NodeSafety.is_alive_node(existing) and existing is CreepCamp:
			if _find_living_creep_in_camp(existing as Node3D) != null:
				return existing as Node3D

	var best: Node3D = _pick_safe_creep_camp()
	if best != null:
		_current_target_id = best.get_instance_id()
	return best


## If the committed camp id has no living creeps (or is stale), count clear + drop cache.
func _release_cleared_committed_creep_camp() -> void:
	if _current_target_id == 0:
		return
	if not is_instance_id_valid(_current_target_id):
		_current_target_id = 0
		if _last_command_kind == CMD_CREEP:
			_last_command_kind = CMD_NONE
			_last_command_target_id = 0
		return
	var existing: Variant = instance_from_id(_current_target_id)
	if not NodeSafety.is_alive_node(existing) or not (existing is CreepCamp):
		_current_target_id = 0
		if _last_command_kind == CMD_CREEP:
			_last_command_kind = CMD_NONE
			_last_command_target_id = 0
		return
	if _find_living_creep_in_camp(existing as Node3D) != null:
		return
	_camps_cleared += 1
	_current_target_id = 0
	if _last_command_kind == CMD_CREEP:
		_last_command_kind = CMD_NONE
		_last_command_target_id = 0


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
		var camp_id: int = camp.get_instance_id()
		if _invalid_creep_camp_ids.has(camp_id):
			continue
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


func _finish_military_decision(
	bucket: StringName,
	_reason: StringName,
	legacy_priority: StringName,
	_target: Node3D
) -> void:
	_debug_priority = legacy_priority
	var previous_bucket: StringName = _debug_condition_bucket
	_debug_condition_bucket = bucket
	_log_condition_change_if_needed(previous_bucket)
	_rebuild_debug_overlay_lines()
	_update_debug_overlay()


func _log_condition_change_if_needed(previous_bucket: StringName) -> void:
	if _debug_condition_bucket == _debug_last_logged_condition:
		return
	var previous: String = (
		String(_debug_last_logged_condition)
		if _debug_last_logged_condition != &""
		else String(previous_bucket) if previous_bucket != &"" else "NONE"
	)
	_debug_previous_condition = (
		_debug_last_logged_condition if _debug_last_logged_condition != &"" else previous_bucket
	)
	_debug_last_logged_condition = _debug_condition_bucket
	_condition_change_times_msec.append(Time.get_ticks_msec())
	_prune_condition_change_window()
	print(
		"[AI CONDITION] %s -> %s | army=%d cohesive=%s cmd=%s tgt=%s"
		% [
			previous,
			String(_debug_condition_bucket),
			_count_soldiers(),
			str(_army_is_together()),
			String(_last_command_kind),
			_strategic_target_label(),
		]
	)


func _prune_condition_change_window() -> void:
	var cutoff: int = Time.get_ticks_msec() - int(CONDITION_CHANGE_WINDOW_SECONDS * 1000.0)
	while not _condition_change_times_msec.is_empty() and _condition_change_times_msec[0] < cutoff:
		_condition_change_times_msec.remove_at(0)


func _condition_changes_last_10s() -> int:
	_prune_condition_change_window()
	return _condition_change_times_msec.size()


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
		CMD_REGROUP, CMD_HERO_UNSTUCK:
			return "MOVE"
		CMD_ATTACK_MARCH:
			return "ATTACK_MOVE"
		CMD_CREEP:
			return "CREEP"
		CMD_ATTACK, CMD_DEFEND:
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
	if offense_intent and not army_cohesive and NodeSafety.is_alive_node(_w.get("hero", null)):
		warnings.append("SOLO HERO WARNING")
	if unfinished_without_builder > 0:
		warnings.append("BUILDING ABANDONED")
	return warnings


func _rebuild_debug_overlay_lines() -> void:
	var soldiers: int = _count_soldiers()
	var army_cohesive: bool = _army_is_together()
	var hero_centroid_dist: float = _hero_distance_to_soldier_centroid()
	var hero_dist_text: String = (
		"-" if hero_centroid_dist < 0.0 else "%.1f" % hero_centroid_dist
	)
	var prev_cond: String = (
		String(_debug_previous_condition) if _debug_previous_condition != &"" else "-"
	)
	_debug_overlay_lines = PackedStringArray([
		"AI %s (was %s) power %.0f/%.0f Δ10s=%d"
		% [
			String(_debug_condition_bucket),
			prev_cond,
			float(_w.get("our_power", 0.0)),
			float(_w.get("player_power", 0.0)),
			_condition_changes_last_10s(),
		],
		"Army %d cohesive=%s hero→cluster=%s cmd=%s tgt=%s"
		% [
			soldiers,
			"Y" if army_cohesive else "N",
			hero_dist_text,
			_strategic_order_label(),
			_strategic_target_label(),
		],
	])
	if _debug_condition_bucket == &"ATTACK_PLAYER":
		var attack_focus: Vector3 = _last_command_destination
		if attack_focus == Vector3.ZERO and NodeSafety.is_alive_node(_w.player_cc):
			attack_focus = (_w.player_cc as Node3D).global_position
		var intent: Dictionary = _classify_army_attack_intent(attack_focus)
		_debug_overlay_lines.append(
			"army attack intent: travel=%d combat=%d idle=%d blocked=%d other=%d"
			% [
				int(intent.get("travel", 0)),
				int(intent.get("combat", 0)),
				int(intent.get("idle", 0)),
				int(intent.get("blocked", 0)),
				int(intent.get("other", 0)),
			]
		)
		_log_unexpected_attack_idles(attack_focus)
	else:
		_attack_idle_logged_ids.clear()
	var warnings: PackedStringArray = _collect_invariant_warnings(
		(_w.player_army as Array).size(),
		army_cohesive,
		_count_unfinished_buildings_without_builder()
	)
	if not warnings.is_empty():
		_debug_overlay_lines.append("WARN: " + ", ".join(warnings))


func get_debug_overlay_lines() -> PackedStringArray:
	return _debug_overlay_lines


func _log_unexpected_attack_idles(attack_focus: Vector3) -> void:
	if not OS.is_debug_build():
		return
	var living_ids: Dictionary = {}
	for unit_variant: Variant in _w.army as Array:
		if not unit_variant is Unit or not NodeSafety.is_alive_node(unit_variant):
			continue
		var unit: Unit = unit_variant as Unit
		var unit_id: int = unit.get_instance_id()
		living_ids[unit_id] = true
		var has_attack: bool = (
			"_attack_target" in unit and NodeSafety.is_alive_node(unit.get("_attack_target"))
		)
		var has_am: bool = (
			"_has_attack_move_destination" in unit
			and bool(unit.get("_has_attack_move_destination"))
		)
		var is_blocked: bool = false
		if unit.has_method(&"is_physically_blocked_from_current_move"):
			is_blocked = bool(unit.call(&"is_physically_blocked_from_current_move"))
		var is_unexpected_idle: bool = (
			not has_attack
			and not has_am
			and not unit.has_move_target
			and not is_blocked
			and attack_focus != Vector3.ZERO
			and _horizontal_distance(unit.global_position, attack_focus) <= ENEMY_BASE_COMBAT_RADIUS
		)
		if not is_unexpected_idle:
			_attack_idle_logged_ids.erase(unit_id)
			continue
		if _attack_idle_logged_ids.has(unit_id):
			continue
		_attack_idle_logged_ids[unit_id] = true
		var attack_target_label: String = "-"
		if "_attack_target" in unit:
			var at: Variant = unit.get("_attack_target")
			if NodeSafety.is_alive_node(at) and at is Node:
				attack_target_label = (at as Node).name
		var move_label: String = "-"
		if unit.has_move_target:
			move_label = str(unit.get_movement_destination())
		elif has_am:
			move_label = str(unit.get("_attack_move_destination"))
		var order_label: String = "-"
		var active: UnitOrder = unit.get_active_order()
		if active != null:
			order_label = str(active.type)
		var provenance: Dictionary = unit.get_strategic_order_provenance()
		var reason: String = _debug_reason_no_attack_target(unit)
		print(
			"[ATTACK IDLE]\nunit=%s\nposition=%s\nstrategic_condition=%s\nstrategic_command=%s\nactual_order=%s\nmove_target=%s\nattack_target=%s\nlast_order_source=%s\nreason_no_target=%s"
			% [
				unit.name,
				str(unit.global_position),
				String(_debug_condition_bucket),
				_strategic_order_label(),
				order_label,
				move_label,
				attack_target_label,
				str(provenance.get("source", "-")),
				reason,
			]
		)
	## Drop logs for units that left the army.
	var stale_ids: Array = []
	for logged_id: Variant in _attack_idle_logged_ids.keys():
		if not living_ids.has(logged_id):
			stale_ids.append(logged_id)
	for stale_id: Variant in stale_ids:
		_attack_idle_logged_ids.erase(stale_id)


func _debug_reason_no_attack_target(unit: Unit) -> String:
	if not NodeSafety.is_alive_node(unit):
		return "unit_invalid"
	var search_range: float = 26.0
	if "attack_range" in unit:
		search_range = maxf(float(unit.get("attack_range")) + 3.5, search_range)
	var found: Node3D = CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
		unit, search_range
	)
	if found != null:
		return "has_valid_target_but_no_order:%s" % found.name
	return "no_valid_target_in_range"


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


func get_last_command_target_id_for_test() -> int:
	return _last_command_target_id


func get_current_target_id_for_test() -> int:
	return _current_target_id


func get_strategic_order_label_for_test() -> String:
	return _strategic_order_label()


func can_continue_enemy_base_fight_without_hero_for_test() -> bool:
	_read_live_world()
	return _can_continue_current_enemy_base_fight_without_hero()


func classify_army_attack_intent_for_test(expected_destination: Vector3 = Vector3.ZERO) -> Dictionary:
	_read_live_world()
	var dest: Vector3 = expected_destination
	if dest == Vector3.ZERO:
		dest = _last_command_destination
		if dest == Vector3.ZERO and NodeSafety.is_alive_node(_w.player_cc):
			dest = (_w.player_cc as Node3D).global_position
	return _classify_army_attack_intent(dest)


func units_needing_attack_refresh_for_test(target: Node3D) -> Array:
	_read_live_world()
	if not NodeSafety.is_alive_node(target):
		return []
	return _units_needing_order_refresh(
		CMD_ATTACK,
		target.get_instance_id(),
		_w.army as Array,
		target.global_position
	)


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
