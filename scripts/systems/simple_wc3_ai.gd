class_name SimpleWc3AI
extends Node

## Simple WC3 melee opening — sole runtime military authority when enabled.
## Fixed sequence only:
## Farm → Altar → Barracks → Hero → 5 Pikemen → assembly → creep camps until Hero level 3 → STOP.
## Economy/build/train use existing gameplay systems; this script decides when and what.

enum State {
	BUILD_FARM,
	BUILD_ALTAR,
	BUILD_BARRACKS,
	TRAIN_HERO,
	TRAIN_PIKEMEN,
	ASSEMBLE,
	TRAVEL,
	FIGHT,
	DONE,
}

const MIN_PIKEMEN := 5
const HERO_STOP_LEVEL := 3
const TICK_SECONDS := 0.5
const ENGAGE_DISTANCE := 14.0
const ASSEMBLY_RADIUS := 12.0
const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const AUTHORITY_LOG_INTERVAL_SECONDS := 8.0
const COMMAND_SOURCE := &"simple_wc3_ai"

var _state: State = State.BUILD_FARM
var _tick_timer: float = 0.0
var _authority_log_timer: float = AUTHORITY_LOG_INTERVAL_SECONDS
var _debug_label: Label = null
var _logged_authority_once: bool = false

## One deterministic army gather point near the enemy base.
var assembly_position: Vector3 = Vector3.ZERO
## Instance IDs already given a one-shot production move (assembly or creep objective).
var _ordered_unit_ids: Dictionary = {}

var _camp_id: int = 0
var _camp_name: String = "-"
var _camp_destination: Vector3 = Vector3.ZERO
var _travel_issued: bool = false
var _fight_target_id: int = 0
var _cleared_camp_ids: Dictionary = {}
var _cleared_camp_names: Dictionary = {}

var last_hero_alive: bool = false
var last_pikeman_count: int = 0
var last_army_count: int = 0
var last_hero_level: int = 0
var last_move_handled: bool = false
var last_move_squad_size: int = 0
var last_creep_damaged: bool = false
var _tracked_creep_hp: float = -1.0
var strategic_orders_issued: int = 0


func _ready() -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return
	_ensure_debug_label()
	_observe_army()
	_update_debug_label()
	_log_authority_proof(true)
	set_process(true)


func get_state() -> State:
	return _state


func get_state_label() -> String:
	match _state:
		State.BUILD_FARM:
			return "BUILD_FARM"
		State.BUILD_ALTAR:
			return "BUILD_ALTAR"
		State.BUILD_BARRACKS:
			return "BUILD_BARRACKS"
		State.TRAIN_HERO:
			return "TRAIN_HERO"
		State.TRAIN_PIKEMEN:
			return "TRAIN_PIKEMEN"
		State.ASSEMBLE:
			return "ASSEMBLE"
		State.TRAVEL:
			return "TRAVEL"
		State.FIGHT:
			return "FIGHT"
		State.DONE:
			return "DONE"
	return "?"


func get_camp_name() -> String:
	return _camp_name


func get_camp_destination() -> Vector3:
	return _camp_destination


## Dev test only: mark camps cleared and start normal creep travel selection.
## Does not change decision logic — reuses _begin_creep_travel().
func init_test_after_camps(cleared_camp_names: Array) -> void:
	_ordered_unit_ids.clear()
	_fight_target_id = 0
	_tracked_creep_hp = -1.0
	_cleared_camp_ids.clear()
	_cleared_camp_names.clear()
	_clear_camp_target()
	for camp_name_ref: Variant in cleared_camp_names:
		_cleared_camp_names[String(camp_name_ref)] = true
	_ensure_assembly_position()
	_observe_army()
	_begin_creep_travel()
	_update_debug_label()


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return

	_tick_timer += delta
	_authority_log_timer += delta
	if _tick_timer < TICK_SECONDS:
		return
	_tick_timer = 0.0

	_observe_army()
	_dispatch_new_unit_moves()
	match _state:
		State.BUILD_FARM:
			_tick_build_farm()
		State.BUILD_ALTAR:
			_tick_build_altar()
		State.BUILD_BARRACKS:
			_tick_build_barracks()
		State.TRAIN_HERO:
			_tick_train_hero()
		State.TRAIN_PIKEMEN:
			_tick_train_pikemen()
		State.ASSEMBLE:
			_tick_assemble()
		State.TRAVEL:
			_tick_travel()
		State.FIGHT:
			_tick_fight()
		State.DONE:
			pass

	_update_debug_label()
	if _authority_log_timer >= AUTHORITY_LOG_INTERVAL_SECONDS:
		_authority_log_timer = 0.0
		_log_authority_proof(false)


func _tick_build_farm() -> void:
	if _has_completed_farm():
		_state = State.BUILD_ALTAR
		return
	var build: EnemyBuildManager = _resolve_build_manager()
	if build != null and build.try_place_farm():
		strategic_orders_issued += 1


func _tick_build_altar() -> void:
	if _has_completed_hero_altar():
		_state = State.BUILD_BARRACKS
		return
	if not _has_completed_farm():
		return
	var build: EnemyBuildManager = _resolve_build_manager()
	if build != null and build.try_place_hero_altar():
		strategic_orders_issued += 1


func _tick_build_barracks() -> void:
	if _has_completed_barracks():
		_state = State.TRAIN_HERO
		return
	if not _has_completed_hero_altar():
		return
	var build: EnemyBuildManager = _resolve_build_manager()
	if build != null and build.try_place_barracks():
		strategic_orders_issued += 1


func _tick_train_hero() -> void:
	if last_hero_alive:
		_ensure_assembly_position()
		_state = State.TRAIN_PIKEMEN
		return

	var altar: HeroAltar = _find_completed_hero_altar()
	if altar == null:
		return
	if altar.is_training_hero():
		return
	AIHeroMastery.ensure_enemy_hero_choice()
	if altar.try_train_enemy_hero():
		strategic_orders_issued += 1


func _tick_train_pikemen() -> void:
	if not last_hero_alive:
		_state = State.TRAIN_HERO
		return

	_ensure_assembly_position()

	if last_pikeman_count >= MIN_PIKEMEN:
		_state = State.ASSEMBLE
		return

	var living_and_pending: int = last_pikeman_count + _count_pending_pikemen()
	if living_and_pending >= MIN_PIKEMEN:
		return

	var barracks: Barracks = _find_completed_barracks()
	if barracks == null:
		return
	if barracks.try_train_enemy_spearman():
		strategic_orders_issued += 1


func _tick_assemble() -> void:
	if not last_hero_alive:
		_state = State.TRAIN_HERO
		return
	if last_pikeman_count < MIN_PIKEMEN:
		_state = State.TRAIN_PIKEMEN
		return

	_ensure_assembly_position()
	if assembly_position == Vector3.ZERO:
		return

	## Wait until Hero + 5 Pikemen are near the assembly point. No creeping early.
	if _is_army_assembled():
		_begin_creep_travel()


func _tick_travel() -> void:
	var army: Array = _collect_main_army()
	## After assembly, continue with Hero + living Pikemen (may be below 5).
	if not _has_creeping_force(army):
		_state = State.TRAIN_HERO if not last_hero_alive else State.TRAIN_PIKEMEN
		_clear_camp_target()
		return

	var camp: Node3D = _resolve_camp()
	if camp == null or not _camp_has_living_creeps(camp):
		_begin_creep_travel()
		return

	if not _travel_issued:
		_issue_army_move(army)
		_travel_issued = true
		return

	if _army_in_engage_range(army, camp):
		_state = State.FIGHT
		_fight_target_id = 0
		_tracked_creep_hp = -1.0
		_tick_fight()


func _tick_fight() -> void:
	var army: Array = _collect_main_army()
	if not _has_creeping_force(army):
		_state = State.TRAIN_HERO if not last_hero_alive else State.TRAIN_PIKEMEN
		_clear_camp_target()
		return

	var camp: Node3D = _resolve_camp()
	if camp == null or not _camp_has_living_creeps(camp):
		_on_camp_cleared(camp)
		return

	var creep: NeutralCreep = _pick_living_creep(camp)
	if creep == null:
		_on_camp_cleared(camp)
		return

	_issue_fight_orders(army, creep)


func _on_camp_cleared(camp: Node3D) -> void:
	if camp != null and is_instance_valid(camp):
		_cleared_camp_ids[camp.get_instance_id()] = true
		_cleared_camp_names[String(camp.name)] = true
	elif _camp_id != 0:
		_cleared_camp_ids[_camp_id] = true
		if not _camp_name.is_empty() and _camp_name != "-":
			_cleared_camp_names[_camp_name] = true

	var hero: Hero = _find_living_hero()
	if hero != null:
		last_hero_level = hero.level
		if hero.level >= HERO_STOP_LEVEL:
			_state = State.DONE
			_clear_camp_target()
			return

	_begin_creep_travel()


func _begin_creep_travel() -> void:
	## Creeping force = Hero + all currently living Pikemen (one group command).
	var army: Array = _collect_main_army()
	if not _has_creeping_force(army):
		_state = State.TRAIN_HERO if not last_hero_alive else State.TRAIN_PIKEMEN
		_clear_camp_target()
		return

	var camp: Node3D = _select_creep_camp(army)
	if camp == null:
		## No living camp left — stop military behavior.
		_state = State.DONE
		_clear_camp_target()
		return

	_camp_id = camp.get_instance_id()
	_camp_name = String(camp.name)
	_camp_destination = Vector3(camp.global_position.x, 0.0, camp.global_position.z)
	_travel_issued = false
	_fight_target_id = 0
	_tracked_creep_hp = -1.0
	_state = State.TRAVEL
	_issue_army_move(army)
	_travel_issued = true


func _clear_camp_target() -> void:
	_camp_id = 0
	_camp_name = "-"
	_camp_destination = Vector3.ZERO
	_travel_issued = false
	_fight_target_id = 0
	_tracked_creep_hp = -1.0


func _has_minimum_force(army: Array) -> bool:
	_observe_force_counts(army)
	return last_hero_alive and last_pikeman_count >= MIN_PIKEMEN


## Once creeping has started: living Hero required; bring every living Pikeman.
func _has_creeping_force(army: Array) -> bool:
	_observe_force_counts(army)
	return last_hero_alive


func _observe_force_counts(army: Array) -> void:
	var hero_alive: bool = false
	var pikemen: int = 0
	for unit_ref: Variant in army:
		if unit_ref is Hero:
			hero_alive = true
		elif unit_ref is Spearman:
			pikemen += 1
	last_hero_alive = hero_alive
	last_pikeman_count = pikemen
	last_army_count = army.size()


func _observe_army() -> void:
	var army: Array = _collect_main_army()
	var hero: Hero = null
	var pikemen: int = 0
	for unit_ref: Variant in army:
		if unit_ref is Hero:
			hero = unit_ref as Hero
		elif unit_ref is Spearman:
			pikemen += 1
	last_hero_alive = hero != null
	last_pikeman_count = pikemen
	last_army_count = army.size()
	last_hero_level = hero.level if hero != null else 0


func _collect_main_army() -> Array:
	var tree: SceneTree = get_tree()
	if tree == null:
		last_hero_alive = false
		last_pikeman_count = 0
		last_army_count = 0
		return []

	var army: Array = []
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if not _is_living_enemy_unit(node_variant):
			continue
		var unit: Unit = node_variant as Unit
		if unit is Hero or unit is Spearman:
			army.append(unit)
	return army


func _find_living_hero() -> Hero:
	for unit_ref: Variant in _collect_main_army():
		if unit_ref is Hero:
			return unit_ref as Hero
	return null


func _is_living_enemy_unit(node_variant: Variant) -> bool:
	if not NodeSafety.is_alive_node(node_variant):
		return false
	if not node_variant is Unit:
		return false
	var unit: Unit = node_variant as Unit
	if not unit.is_inside_tree():
		return false
	if not CombatTargetValidation.is_enemy_faction(unit):
		return false
	var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.current_health <= 0:
		return false
	return true


func _ensure_assembly_position() -> void:
	if assembly_position != Vector3.ZERO:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var base: Vector3 = _enemy_base_position(tree)
	if base == Vector3.ZERO:
		return

	PlayerRouteNavigation.ensure_grid_ready()
	## Deterministic candidates toward map center, outside base footprints.
	var candidates: Array[Vector3] = [
		base + Vector3(-12.0, 0.0, -12.0),
		base + Vector3(-14.0, 0.0, -8.0),
		base + Vector3(-8.0, 0.0, -14.0),
		base + Vector3(-16.0, 0.0, -10.0),
		base + Vector3(-10.0, 0.0, -16.0),
		base + Vector3(-18.0, 0.0, -6.0),
		base + Vector3(-6.0, 0.0, -18.0),
	]
	for candidate: Vector3 in candidates:
		var walkable: Vector3 = PlayerRouteNavigation.nearest_walkable_world(candidate)
		walkable.y = 0.0
		if _is_valid_assembly_site(walkable):
			assembly_position = walkable
			return

	var fallback: Vector3 = PlayerRouteNavigation.nearest_walkable_world(base + Vector3(-12.0, 0.0, -12.0))
	fallback.y = 0.0
	assembly_position = fallback


func _is_valid_assembly_site(world: Vector3) -> bool:
	if not PlayerRouteNavigation.is_world_walkable(world):
		return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return true
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Building:
			continue
		var building: Building = node_variant as Building
		if building is CommandCenter or building is HeroAltar or building is Barracks:
			if building.is_position_inside_footprint(world, 1.0):
				return false
	return true


func _is_army_assembled() -> bool:
	if assembly_position == Vector3.ZERO:
		return false
	var hero: Hero = _find_living_hero()
	if hero == null:
		return false
	if not _is_near_assembly(hero.global_position):
		return false

	var near_pikes: int = 0
	for unit_ref: Variant in _collect_main_army():
		if not unit_ref is Spearman:
			continue
		if _is_near_assembly((unit_ref as Spearman).global_position):
			near_pikes += 1
	return near_pikes >= MIN_PIKEMEN


func _is_near_assembly(world: Vector3) -> bool:
	return _horizontal_distance(world, assembly_position) <= ASSEMBLY_RADIUS


## One-shot: new Hero/Pikeman → assembly; during creep → current camp objective.
func _dispatch_new_unit_moves() -> void:
	if _state == State.DONE or _state == State.BUILD_FARM or _state == State.BUILD_ALTAR or _state == State.BUILD_BARRACKS:
		return
	if _state == State.TRAIN_HERO and not last_hero_alive:
		return

	_ensure_assembly_position()
	var creeping: bool = _state == State.TRAVEL or _state == State.FIGHT
	var destination: Vector3 = _camp_destination if creeping and _camp_destination != Vector3.ZERO else assembly_position
	if destination == Vector3.ZERO:
		return

	for unit_ref: Variant in _collect_main_army():
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		var unit: Unit = unit_ref as Unit
		if not (unit is Hero or unit is Spearman):
			continue
		var unit_id: int = unit.get_instance_id()
		if _ordered_unit_ids.has(unit_id):
			continue
		_issue_single_unit_move(unit, destination)
		_ordered_unit_ids[unit_id] = true


func _issue_single_unit_move(unit: Unit, destination: Vector3) -> void:
	if not NodeSafety.is_alive_node(unit) or destination == Vector3.ZERO:
		return
	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		[unit],
		destination,
		&"move",
		false,
		COMMAND_SOURCE
	)
	last_move_handled = bool(result.get("handled", false))
	last_move_squad_size = int(result.get("squad_size", 0))
	if last_move_handled:
		strategic_orders_issued += 1


func _has_completed_farm() -> bool:
	return _find_completed_farm() != null


func _has_completed_hero_altar() -> bool:
	return _find_completed_hero_altar() != null


func _has_completed_barracks() -> bool:
	return _find_completed_barracks() != null


func _find_completed_farm() -> Farm:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Farm:
			continue
		var farm: Farm = node_variant as Farm
		if farm.building_state == Building.STATE_COMPLETED:
			return farm
	return null


func _find_completed_hero_altar() -> HeroAltar:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is HeroAltar:
			continue
		var altar: HeroAltar = node_variant as HeroAltar
		if altar.building_state == Building.STATE_COMPLETED:
			return altar
	return null


func _find_completed_barracks() -> Barracks:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Barracks:
			continue
		var barracks: Barracks = node_variant as Barracks
		if barracks.building_state == Building.STATE_COMPLETED:
			return barracks
	return null


func _count_pending_pikemen() -> int:
	var pending: int = 0
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Barracks:
			continue
		var barracks: Barracks = node_variant as Barracks
		if barracks.building_state != Building.STATE_COMPLETED:
			continue
		pending += barracks.get_spearman_queue_count()
	return pending


func _select_creep_camp(army: Array) -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	var origin: Vector3 = _army_centroid(army)
	if origin == Vector3.ZERO:
		origin = _enemy_base_position(tree)
	if origin == Vector3.ZERO:
		return null

	var active_camps: Array[Node3D] = CreepCampSafety.collect_active_camps(tree)
	if active_camps.is_empty():
		return null

	## Prefer nearby Medium/Small early camps; otherwise nearest living camp.
	var preferred: Array[Node3D] = []
	for camp: Node3D in active_camps:
		if camp == null or not is_instance_valid(camp):
			continue
		if _is_camp_cleared(camp):
			continue
		var camp_name: String = String(camp.name)
		if (
			camp_name.begins_with("Medium")
			or camp_name.contains("Medium")
			or camp_name.begins_with("Small")
			or camp_name.contains("Small")
		):
			preferred.append(camp)

	var pool: Array[Node3D] = preferred if not preferred.is_empty() else active_camps
	var best: Node3D = null
	var best_dist: float = INF
	for camp: Node3D in pool:
		if camp == null or not is_instance_valid(camp):
			continue
		if _is_camp_cleared(camp):
			continue
		var dist: float = _horizontal_distance(origin, camp.global_position)
		if dist < best_dist:
			best_dist = dist
			best = camp
	return best


func _is_camp_cleared(camp: Node3D) -> bool:
	if camp == null or not is_instance_valid(camp):
		return true
	if _cleared_camp_ids.has(camp.get_instance_id()):
		return true
	if _cleared_camp_names.has(String(camp.name)):
		return true
	return false


func _resolve_camp() -> Node3D:
	if _camp_id != 0:
		var obj: Object = instance_from_id(_camp_id)
		if obj != null and is_instance_valid(obj) and obj is Node3D:
			return obj as Node3D
	return _resolve_camp_id_from_name()


func _resolve_camp_id_from_name() -> Node3D:
	if _camp_name.is_empty() or _camp_name == "-":
		_camp_id = 0
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for camp: Node3D in CreepCampSafety.collect_active_camps(tree):
		if camp == null or not is_instance_valid(camp):
			continue
		if String(camp.name) == _camp_name:
			_camp_id = camp.get_instance_id()
			return camp
	## Also search all camps by name (including cleared / empty).
	for node_variant: Variant in tree.get_nodes_in_group(&"creep_camps"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Node3D:
			continue
		var camp: Node3D = node_variant as Node3D
		if String(camp.name) == _camp_name:
			_camp_id = camp.get_instance_id()
			return camp
	_camp_id = 0
	return null


func _camp_has_living_creeps(camp: Node3D) -> bool:
	return _pick_living_creep(camp) != null


func _pick_living_creep(camp: Node3D) -> NeutralCreep:
	if camp == null or not is_instance_valid(camp):
		return null
	for child_variant: Variant in camp.get_children():
		if not NodeSafety.is_alive_node(child_variant):
			continue
		if not child_variant is NeutralCreep:
			continue
		var creep: NeutralCreep = child_variant as NeutralCreep
		var health: HealthComponent = creep.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.current_health <= 0:
			continue
		return creep
	return null


func _army_in_engage_range(army: Array, camp: Node3D) -> bool:
	if camp == null or not is_instance_valid(camp):
		return false
	var camp_pos: Vector3 = camp.global_position
	for unit_ref: Variant in army:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		var unit: Unit = unit_ref as Unit
		if _horizontal_distance(unit.global_position, camp_pos) <= ENGAGE_DISTANCE:
			return true
		for child_variant: Variant in camp.get_children():
			if not NodeSafety.is_alive_node(child_variant):
				continue
			if not child_variant is NeutralCreep:
				continue
			var creep: NeutralCreep = child_variant as NeutralCreep
			if _horizontal_distance(unit.global_position, creep.global_position) <= ENGAGE_DISTANCE:
				return true
	return false


func _issue_army_move(units: Array) -> void:
	if units.is_empty() or _camp_destination == Vector3.ZERO:
		return

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units,
		_camp_destination,
		&"move",
		false,
		COMMAND_SOURCE
	)
	last_move_handled = bool(result.get("handled", false))
	last_move_squad_size = int(result.get("squad_size", 0))
	if last_move_handled:
		strategic_orders_issued += 1
		for unit_ref: Variant in units:
			if NodeSafety.is_alive_node(unit_ref):
				_ordered_unit_ids[(unit_ref as Unit).get_instance_id()] = true


func _issue_fight_orders(army: Array, creep: NeutralCreep) -> void:
	if not NodeSafety.is_alive_node(creep):
		return

	var creep_id: int = creep.get_instance_id()
	var health: HealthComponent = creep.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		if _tracked_creep_hp >= 0.0 and health.current_health < _tracked_creep_hp:
			last_creep_damaged = true
		_tracked_creep_hp = health.current_health

	var new_creep_objective: bool = _fight_target_id != creep_id
	if new_creep_objective:
		## Each new creep objective initializes the same combat handoff:
		## stop camp MOVE → move onto the living creep → Pikemen attack → Hero joins.
		_fight_target_id = creep_id
		_tracked_creep_hp = health.current_health if health != null else -1.0
		strategic_orders_issued += 1
		for unit_ref: Variant in army:
			if not NodeSafety.is_alive_node(unit_ref):
				continue
			(unit_ref as Unit).clear_move_target()
		var creep_destination := Vector3(creep.global_position.x, 0.0, creep.global_position.z)
		var move_result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			army,
			creep_destination,
			&"move",
			false,
			COMMAND_SOURCE
		)
		last_move_handled = bool(move_result.get("handled", false))
		last_move_squad_size = int(move_result.get("squad_size", 0))

	## Pikemen start the fight / tank first.
	for unit_ref: Variant in army:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		if not unit_ref is Spearman:
			continue
		(unit_ref as Spearman).command_attack(creep)

	## Hero joins through normal combat.
	for unit_ref: Variant in army:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		if not unit_ref is Hero:
			continue
		(unit_ref as Hero).command_attack(creep)


func _army_centroid(army: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for unit_ref: Variant in army:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		sum += (unit_ref as Unit).global_position
		count += 1
	if count <= 0:
		return Vector3.ZERO
	var c: Vector3 = sum / float(count)
	c.y = 0.0
	return c


func _enemy_base_position(tree: SceneTree) -> Vector3:
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is CommandCenter:
			continue
		var pos: Vector3 = (node_variant as CommandCenter).global_position
		pos.y = 0.0
		return pos
	return Vector3.ZERO


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _resolve_build_manager() -> EnemyBuildManager:
	var parent: Node = get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("EnemyBuildManager") as EnemyBuildManager


func _log_authority_proof(force: bool) -> void:
	if _logged_authority_once and not force:
		pass
	_logged_authority_once = true
	var old_active: bool = false
	var composition: MatchCompositionRoot = get_parent() as MatchCompositionRoot
	if composition != null:
		old_active = composition.is_old_military_runtime_active()
	print(
		"Simple WC3 AI active: YES | Old Military AI active: %s | Old military strategic orders issued: %d | Simple orders: %d | State: %s"
		% [
			"YES" if old_active else "NO",
			EnemyArmyCommand.get_legacy_military_strategic_orders_issued(),
			strategic_orders_issued,
			get_state_label(),
		]
	)


func _ensure_debug_label() -> void:
	if _debug_label != null and is_instance_valid(_debug_label):
		return
	var layer := CanvasLayer.new()
	layer.name = "SimpleWc3AIDebugLayer"
	layer.layer = 80
	add_child(layer)
	_debug_label = Label.new()
	_debug_label.name = "SimpleWc3AIDebug"
	_debug_label.position = Vector2(12, 120)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.55, 1.0))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_debug_label)


func _update_debug_label() -> void:
	if _debug_label == null or not is_instance_valid(_debug_label):
		return
	_debug_label.text = (
		"WC3 SIMPLE AI\n"
		+ "State: %s\n" % get_state_label()
		+ "Hero: %s (L%d)\n" % [("YES" if last_hero_alive else "NO"), last_hero_level]
		+ "Pikemen: %d / %d\n" % [last_pikeman_count, MIN_PIKEMEN]
		+ "Army: %d\n" % last_army_count
		+ "Assembly: %s\n" % _format_vec(assembly_position)
		+ "Target: %s\n" % _camp_name
		+ "Movement: CUSTOM\n"
		+ "Old military: OFF"
	)


func _format_vec(v: Vector3) -> String:
	if v == Vector3.ZERO:
		return "-"
	return "(%.0f, %.0f)" % [v.x, v.z]
