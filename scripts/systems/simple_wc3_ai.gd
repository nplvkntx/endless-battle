class_name SimpleWc3AI
extends Node

## Sole enemy military decision authority — priority-rule WC3 melee loop.
## Conditions are the state. Live game facts are the memory. No strategic state machine.
## Strategic travel: PlayerRouteNavigation custom RTS only.

const MIN_PIKEMEN := 5
const MIN_WORKERS := 5
const TICK_SECONDS := 0.5
const DEFEND_RADIUS := 40.0
const ATTACK_NEARBY_RADIUS := 36.0
const ATTACK_POWER_RATIO := 1.25
const EARLY_CREEP_CAMPS := 2
## Creep fight starts only when enough of the army is near the camp together.
const CREEP_COHESION_RADIUS := 18.0
const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const ENEMY_WORKER_GROUP := &"enemy_workers"
const PLAYER_CC_GROUP := &"player_command_center"
const AUTHORITY_LOG_INTERVAL_SECONDS := 8.0
const COMMAND_SOURCE := &"simple_wc3_ai"

## Diagnostic only — which priority branch returned this tick. Not a state machine.
const PRIORITY_NONE := &"NONE"
const PRIORITY_HERO := &"HERO"
const PRIORITY_BUILD_FORCE := &"BUILD_FORCE"
const PRIORITY_DEFEND := &"DEFEND"
const PRIORITY_EARLY_CREEP := &"EARLY_CREEP"
const PRIORITY_ATTACK_PLAYER := &"ATTACK_PLAYER"
const PRIORITY_EXTRA_CREEP := &"EXTRA_CREEP"
const PRIORITY_WAIT := &"WAIT"

var _tick_timer: float = 0.0
var _authority_log_timer: float = AUTHORITY_LOG_INTERVAL_SECONDS
var _debug_label: Label = null
var _logged_authority_once: bool = false
var last_priority: StringName = PRIORITY_NONE

## One deterministic army gather point near the enemy base.
var assembly_position: Vector3 = Vector3.ZERO

## Single sticky strategic target (camp / threat / player). Null when invalid.
var current_target: Node3D = null

## Minimal order dedup — reissue when kind/target changes or army membership grows.
var _last_command_kind: StringName = &""
var _last_command_target_id: int = 0
var _last_command_army_count: int = -1

var _cleared_camp_ids: Dictionary = {}
var _cleared_camp_names: Dictionary = {}
var _camps_cleared: int = 0

## Debug / observation mirrors (live facts from last tick).
var last_hero_alive: bool = false
var last_hero_queued: bool = false
var last_pikeman_count: int = 0
var last_army_count: int = 0
var last_hero_level: int = 0
var last_ai_power: float = 0.0
var last_player_power: float = 0.0
var last_move_handled: bool = false
var last_move_squad_size: int = 0
var strategic_orders_issued: int = 0


func _ready() -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return
	_ensure_debug_label()
	_update_debug_label()
	_log_authority_proof(true)
	set_process(true)


func get_priority() -> StringName:
	return last_priority


func get_priority_label() -> String:
	return String(last_priority)


func get_camp_name() -> String:
	if current_target != null and NodeSafety.is_alive_node(current_target) and current_target is CreepCamp:
		return String(current_target.name)
	return "-"


func get_camp_destination() -> Vector3:
	if current_target != null and NodeSafety.is_alive_node(current_target) and current_target is CreepCamp:
		return Vector3(current_target.global_position.x, 0.0, current_target.global_position.z)
	return Vector3.ZERO


func get_objective_name() -> String:
	if current_target == null or not NodeSafety.is_alive_node(current_target):
		return "-"
	return _describe_target(current_target)


func get_camps_cleared() -> int:
	return _camps_cleared


func is_early_creep_complete() -> bool:
	return _camps_cleared >= EARLY_CREEP_CAMPS


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return

	_tick_timer += delta
	_authority_log_timer += delta
	if _tick_timer < TICK_SECONDS:
		return
	_tick_timer = 0.0

	_ai_tick()
	_update_debug_label()
	if _authority_log_timer >= AUTHORITY_LOG_INTERVAL_SECONDS:
		_authority_log_timer = 0.0
		_log_authority_proof(false)


func _ai_tick() -> void:
	_invalidate_current_target_if_dead()
	_note_cleared_camp_if_needed()

	var hero: Hero = _find_living_hero()
	var pikemen: Array = _find_living_pikemen()
	var army: Array = _collect_main_army()
	_observe_force(hero, pikemen, army)
	_refresh_hero_queued()
	_update_power_estimates()

	_ensure_workers()
	_ensure_opening_buildings()

	## HERO missing — train, don't waste Hero gold on Pikemen, survivors home, stop.
	if hero == null:
		_try_ensure_hero()
		if not _hero_training_blocks_pikemen():
			_try_train_pikeman()
		_move_army_home_if_needed(army)
		last_priority = PRIORITY_HERO
		return

	## BUILD_FORCE — maintain minimum Pikemen near home.
	_ensure_pikemen(MIN_PIKEMEN)
	if pikemen.size() < MIN_PIKEMEN:
		_move_army_home_if_needed(army)
		last_priority = PRIORITY_BUILD_FORCE
		return

	## Keep producing extra Pikemen when affordable (no composition strategy).
	_try_train_pikeman()

	## DEFEND — base threat interrupts everything else.
	var threat: Node3D = _find_base_threat()
	if threat != null:
		_attack_target_with_army(army, threat)
		last_priority = PRIORITY_DEFEND
		return

	## EARLY_CREEP — before two camps cleared, creep has priority over player attack.
	if _camps_cleared < EARLY_CREEP_CAMPS:
		var early_camp: Node3D = _resolve_or_pick_creep_camp(army)
		if early_camp != null:
			_attack_camp_with_army(army, early_camp)
			last_priority = PRIORITY_EARLY_CREEP
		else:
			_move_army_home_if_needed(army)
			last_priority = PRIORITY_WAIT
		return

	## ATTACK_PLAYER — only after early creep gate + power threshold.
	if last_ai_power > last_player_power * ATTACK_POWER_RATIO:
		var player_target: Node3D = _resolve_or_pick_player_target(army)
		if player_target != null:
			_attack_target_with_army(army, player_target)
			last_priority = PRIORITY_ATTACK_PLAYER
			return

	## EXTRA_CREEP / WAIT — not strong enough: keep creeping or home.
	var extra_camp: Node3D = _resolve_or_pick_creep_camp(army)
	if extra_camp != null:
		_attack_camp_with_army(army, extra_camp)
		last_priority = PRIORITY_EXTRA_CREEP
	else:
		_move_army_home_if_needed(army)
		last_priority = PRIORITY_WAIT


# --- Opening / production ----------------------------------------------------

func _ensure_opening_buildings() -> void:
	var build: EnemyBuildManager = _resolve_build_manager()
	if build == null:
		return
	if not _has_completed_farm():
		if build.try_place_farm():
			strategic_orders_issued += 1
		return
	if not _has_completed_hero_altar():
		if build.try_place_hero_altar():
			strategic_orders_issued += 1
		return
	if not _has_completed_barracks():
		if build.try_place_barracks():
			strategic_orders_issued += 1


func _ensure_workers() -> void:
	var living: int = _count_living_workers()
	var pending: int = _count_pending_workers()
	if living + pending >= MIN_WORKERS:
		return
	var cc: CommandCenter = _find_enemy_command_center()
	if cc == null:
		return
	if cc.try_train_enemy_worker():
		strategic_orders_issued += 1


func _ensure_pikemen(desired: int) -> void:
	if _hero_training_blocks_pikemen():
		_try_ensure_hero()
		return
	var living: int = last_pikeman_count
	var pending: int = _count_pending_pikemen()
	if living + pending >= desired:
		return
	_try_train_pikeman()


func _refresh_hero_queued() -> void:
	var altar: HeroAltar = _find_completed_hero_altar()
	last_hero_queued = altar != null and altar.is_training_hero()


func _try_ensure_hero() -> bool:
	if last_hero_alive:
		_refresh_hero_queued()
		return false
	var altar: HeroAltar = _find_completed_hero_altar()
	if altar == null:
		last_hero_queued = false
		return false
	if altar.is_training_hero():
		last_hero_queued = true
		return true
	if altar.try_train_enemy_hero():
		strategic_orders_issued += 1
		last_hero_queued = true
		return true
	last_hero_queued = false
	return false


func _hero_training_blocks_pikemen() -> bool:
	## While Hero is missing and not yet queued, do not spend gold/food on more Pikemen.
	if last_hero_alive:
		return false
	var altar: HeroAltar = _find_completed_hero_altar()
	if altar == null:
		return false
	if altar.is_training_hero():
		return false
	return true


func _try_train_pikeman() -> void:
	if _hero_training_blocks_pikemen():
		_try_ensure_hero()
		return
	var barracks: Barracks = _find_completed_barracks()
	if barracks == null:
		return
	if barracks.try_train_enemy_spearman():
		strategic_orders_issued += 1


# --- Live army / facts -------------------------------------------------------

func _observe_force(hero: Hero, pikemen: Array, army: Array) -> void:
	last_hero_alive = hero != null
	last_pikeman_count = pikemen.size()
	last_army_count = army.size()
	last_hero_level = hero.level if hero != null else 0


func _collect_main_army() -> Array:
	var tree: SceneTree = get_tree()
	if tree == null:
		return []
	var army: Array = []
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if not _is_living_enemy_combat_unit(node_variant):
			continue
		army.append(node_variant as Unit)
	return army


func _find_living_hero() -> Hero:
	for unit_ref: Variant in _collect_main_army():
		if unit_ref is Hero:
			return unit_ref as Hero
	return null


func _find_living_pikemen() -> Array:
	var pikemen: Array = []
	for unit_ref: Variant in _collect_main_army():
		if unit_ref is Spearman:
			pikemen.append(unit_ref)
	return pikemen


func _is_living_enemy_combat_unit(node_variant: Variant) -> bool:
	if not _is_living_enemy_unit(node_variant):
		return false
	var unit: Unit = node_variant as Unit
	if unit is Worker:
		return false
	return unit is Hero or unit is MilitaryUnit


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


func _update_power_estimates() -> void:
	last_ai_power = _force_power(_collect_main_army())
	last_player_power = _force_power(_collect_player_army())


func _force_power(units: Array) -> float:
	var total: float = 0.0
	for unit_ref: Variant in units:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		total += _unit_power(unit_ref as Unit)
	return total


func _unit_power(unit: Unit) -> float:
	var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	var current_hp: float = float(health.current_health) if health != null else 0.0
	var max_hp: float = float(health.max_health) if health != null else 1.0
	var damage: float = _read_attack_damage(unit)
	var hp_factor: float = current_hp / maxf(1.0, max_hp)
	var power: float = hp_factor * max_hp + damage * 12.0
	if unit is Hero:
		power += float((unit as Hero).level) * 40.0
	return power


func _read_attack_damage(unit: Unit) -> float:
	if "attack_damage" in unit:
		return float(unit.get("attack_damage"))
	return 0.0


func _collect_player_army() -> Array:
	var tree: SceneTree = get_tree()
	if tree == null:
		return []
	var seen: Dictionary = {}
	var army: Array = []
	for group_name: StringName in [&"units", &"heroes"]:
		for node_variant: Variant in tree.get_nodes_in_group(group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Unit:
				continue
			var unit: Unit = node_variant as Unit
			if CombatTargetValidation.is_enemy_faction(unit):
				continue
			if unit is Worker:
				continue
			if not (unit is Hero or unit is MilitaryUnit):
				continue
			var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
			if health != null and health.current_health <= 0:
				continue
			var id: int = unit.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			army.append(unit)
	return army


# --- Targets -----------------------------------------------------------------

func _invalidate_current_target_if_dead() -> void:
	if current_target == null:
		return
	if not NodeSafety.is_alive_node(current_target):
		current_target = null
		return
	if current_target is CreepCamp:
		if not _camp_has_living_creeps(current_target):
			## Cleared-camp accounting happens in _note_cleared_camp_if_needed.
			return
	elif not _is_living_attack_target(current_target):
		current_target = null


func _note_cleared_camp_if_needed() -> void:
	if current_target == null or not NodeSafety.is_alive_node(current_target):
		return
	if not current_target is CreepCamp:
		return
	if _camp_has_living_creeps(current_target):
		return
	_mark_camp_cleared(current_target)
	current_target = null


func _mark_camp_cleared(camp: Node3D) -> void:
	if camp == null or not is_instance_valid(camp):
		return
	var id: int = camp.get_instance_id()
	var camp_name: String = String(camp.name)
	if _cleared_camp_ids.has(id) or _cleared_camp_names.has(camp_name):
		return
	_cleared_camp_ids[id] = true
	_cleared_camp_names[camp_name] = true
	_camps_cleared += 1


func _resolve_or_pick_creep_camp(army: Array) -> Node3D:
	if current_target != null and NodeSafety.is_alive_node(current_target) and current_target is CreepCamp:
		if _camp_has_living_creeps(current_target) and not _is_camp_cleared(current_target):
			return current_target
		current_target = null
	var camp: Node3D = _select_creep_camp(army)
	current_target = camp
	return camp


func _resolve_or_pick_player_target(army: Array) -> Node3D:
	if current_target != null and NodeSafety.is_alive_node(current_target):
		if _is_living_attack_target(current_target) and not current_target is CreepCamp:
			return current_target
		current_target = null
	var target: Node3D = _select_attack_target(army)
	current_target = target
	return target


func _find_base_threat() -> Node3D:
	var base: Vector3 = _enemy_base_position(get_tree())
	if base == Vector3.ZERO:
		return null
	return _nearest_player_military(base, DEFEND_RADIUS)


func _select_attack_target(army: Array) -> Node3D:
	var origin: Vector3 = _army_centroid(army)
	if origin == Vector3.ZERO:
		origin = _enemy_base_position(get_tree())

	var nearby: Node3D = _nearest_player_military(origin, ATTACK_NEARBY_RADIUS)
	if nearby != null:
		return nearby

	var player_hero: Node3D = _find_player_hero()
	if player_hero != null:
		return player_hero

	var cc: Node3D = _find_player_command_center()
	if cc != null:
		return cc

	return _find_player_production_building()


func _nearest_player_military(origin: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for unit_ref: Variant in _collect_player_army():
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		var unit: Unit = unit_ref as Unit
		var dist: float = _horizontal_distance(origin, unit.global_position)
		if dist > radius:
			continue
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best


func _find_player_hero() -> Node3D:
	for unit_ref: Variant in _collect_player_army():
		if unit_ref is Hero:
			return unit_ref as Node3D
	return null


func _find_player_command_center() -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(PLAYER_CC_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is CommandCenter:
			continue
		var building: Building = node_variant as Building
		if building.building_state != Building.STATE_COMPLETED:
			continue
		var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.current_health <= 0:
			continue
		return building
	return null


func _find_player_production_building() -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_dist: float = INF
	var origin: Vector3 = _army_centroid(_collect_main_army())
	if origin == Vector3.ZERO:
		origin = _enemy_base_position(tree)
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Building:
			continue
		var building: Building = node_variant as Building
		if CombatTargetValidation.is_enemy_faction(building):
			continue
		if not _is_player_production_building(building):
			continue
		if building.building_state != Building.STATE_COMPLETED:
			continue
		var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.current_health <= 0:
			continue
		var dist: float = _horizontal_distance(origin, building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best


func _is_player_production_building(building: Building) -> bool:
	return (
		building is Barracks
		or building is Stable
		or building is ArtilleryDepot
		or building is HeroAltar
		or building is Academy
		or building is Blacksmith
	)


func _is_living_attack_target(target: Node3D) -> bool:
	if not NodeSafety.is_alive_node(target):
		return false
	if target is Unit:
		var health: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.current_health <= 0:
			return false
		return true
	if target is Building:
		var b_health: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
		if b_health != null and b_health.current_health <= 0:
			return false
		return true
	return false


func _describe_target(target: Node3D) -> String:
	if target is Hero:
		return "PlayerHero"
	if target is CommandCenter:
		return "PlayerCC"
	if target is CreepCamp:
		return String(target.name)
	if target is MilitaryUnit:
		return String(target.name)
	if target is Building:
		return String(target.name)
	return String(target.name)


# --- Creep camps -------------------------------------------------------------

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

	var best_early: Node3D = null
	var best_early_dist: float = INF
	var best_any: Node3D = null
	var best_any_dist: float = INF
	for camp: Node3D in active_camps:
		if camp == null or not is_instance_valid(camp):
			continue
		if _is_camp_cleared(camp):
			continue
		if not _camp_has_living_creeps(camp):
			continue
		var dist: float = _horizontal_distance(origin, camp.global_position)
		if dist < best_any_dist:
			best_any_dist = dist
			best_any = camp
		if _is_early_safe_camp(camp) and dist < best_early_dist:
			best_early_dist = dist
			best_early = camp
	return best_early if best_early != null else best_any


func _is_early_safe_camp(camp: Node3D) -> bool:
	var n: String = String(camp.name)
	if n.contains("Strong") or n.contains("Hard"):
		return false
	return n.contains("Medium") or n.contains("Easy") or n.contains("Small")


func _is_camp_cleared(camp: Node3D) -> bool:
	if camp == null or not is_instance_valid(camp):
		return true
	if _cleared_camp_ids.has(camp.get_instance_id()):
		return true
	if _cleared_camp_names.has(String(camp.name)):
		return true
	return false


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


func _is_creep_army_cohesive(camp: Node3D, army: Array) -> bool:
	if camp == null or not is_instance_valid(camp):
		return false
	var origin := Vector3(camp.global_position.x, 0.0, camp.global_position.z)
	var hero_near: bool = false
	var total_units: int = 0
	var near_units: int = 0
	for unit_ref: Variant in army:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		var unit: Unit = unit_ref as Unit
		total_units += 1
		var near: bool = _horizontal_distance(unit.global_position, origin) <= CREEP_COHESION_RADIUS
		if near:
			near_units += 1
		if unit is Hero and near:
			hero_near = true
	if not hero_near or total_units <= 0:
		return false
	## Simple majority of the live army near the camp.
	var needed: int = maxi(2, (total_units + 1) / 2)
	return near_units >= needed


# --- Orders / movement -------------------------------------------------------

func _attack_camp_with_army(army: Array, camp: Node3D) -> void:
	if camp == null or not NodeSafety.is_alive_node(camp):
		return
	current_target = camp
	var destination := Vector3(camp.global_position.x, 0.0, camp.global_position.z)
	if not _is_creep_army_cohesive(camp, army):
		_issue_army_move(army, destination, &"move", camp)
		return
	_issue_army_move(army, destination, &"attack_move", camp)
	var creep: NeutralCreep = _pick_living_creep(camp)
	if creep != null:
		for unit_ref: Variant in army:
			if NodeSafety.is_alive_node(unit_ref):
				_issue_single_unit_attack(unit_ref as Unit, creep)


func _attack_target_with_army(army: Array, target: Node3D) -> void:
	if target == null or not NodeSafety.is_alive_node(target):
		return
	current_target = target
	var destination := Vector3(target.global_position.x, 0.0, target.global_position.z)
	_issue_army_move(army, destination, &"attack_move", target)
	for unit_ref: Variant in army:
		if NodeSafety.is_alive_node(unit_ref):
			_issue_single_unit_attack(unit_ref as Unit, target)


func _move_army_home_if_needed(army: Array) -> void:
	if army.is_empty():
		return
	_ensure_assembly_position()
	if assembly_position == Vector3.ZERO:
		return
	current_target = null
	_issue_army_move(army, assembly_position, &"move", null)


func _should_reissue(army: Array, order_kind: StringName, target: Node3D) -> bool:
	var target_id: int = target.get_instance_id() if target != null and NodeSafety.is_alive_node(target) else 0
	if _last_command_kind != order_kind:
		return true
	if _last_command_target_id != target_id:
		return true
	## New unit appeared — include it in the group order.
	if army.size() > _last_command_army_count:
		return true
	return false


func _mark_command_issued(army: Array, order_kind: StringName, target: Node3D) -> void:
	_last_command_kind = order_kind
	_last_command_target_id = target.get_instance_id() if target != null and NodeSafety.is_alive_node(target) else 0
	_last_command_army_count = army.size()


func _issue_army_move(units: Array, destination: Vector3, order_kind: StringName, target: Node3D) -> void:
	if units.is_empty() or destination == Vector3.ZERO:
		return
	var living: Array = []
	for unit_ref: Variant in units:
		if NodeSafety.is_alive_node(unit_ref):
			living.append(unit_ref)
	if living.is_empty():
		return
	if not _should_reissue(living, order_kind, target):
		return

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		living,
		destination,
		order_kind,
		false,
		COMMAND_SOURCE
	)
	last_move_handled = bool(result.get("handled", false))
	last_move_squad_size = int(result.get("squad_size", 0))
	_mark_command_issued(living, order_kind, target)
	if last_move_handled:
		strategic_orders_issued += 1


func _issue_single_unit_attack(unit: Unit, target: Node3D) -> void:
	if not NodeSafety.is_alive_node(unit) or not NodeSafety.is_alive_node(target):
		return
	if unit.has_method("command_attack"):
		unit.call("command_attack", target)
		strategic_orders_issued += 1


# --- Assembly / base ---------------------------------------------------------

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


# --- Building / economy lookups ----------------------------------------------

func _count_living_workers() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0
	var count: int = 0
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_WORKER_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if node_variant is Worker:
			count += 1
	return count


func _count_pending_workers() -> int:
	var cc: CommandCenter = _find_enemy_command_center()
	if cc == null:
		return 0
	return cc.get_worker_queue_count()


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


func _find_enemy_command_center() -> CommandCenter:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_BUILDING_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if node_variant is CommandCenter:
			return node_variant as CommandCenter
	return null


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
	if tree == null:
		return Vector3.ZERO
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


# --- Debug -------------------------------------------------------------------

func _log_authority_proof(force: bool) -> void:
	if _logged_authority_once and not force:
		pass
	_logged_authority_once = true
	var old_active: bool = false
	var composition: MatchCompositionRoot = get_parent() as MatchCompositionRoot
	if composition != null:
		old_active = composition.is_old_military_runtime_active()
	print(
		"Simple WC3 AI active: YES | Old Military AI active: %s | Simple orders: %d | Priority: %s"
		% [
			"YES" if old_active else "NO",
			strategic_orders_issued,
			get_priority_label(),
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
	var hero_txt: String = ("lvl %d" % last_hero_level) if last_hero_alive else "none"
	_debug_label.text = (
		"WC3 SIMPLE AI\n"
		+ "Priority: %s\n" % get_priority_label()
		+ "Hero: %s\n" % hero_txt
		+ "Pikemen: %d\n" % last_pikeman_count
		+ "Army: %d\n" % last_army_count
		+ "Camps: %d/%d\n" % [_camps_cleared, EARLY_CREEP_CAMPS]
		+ "Target: %s\n" % get_objective_name()
		+ "Power: %.0f / %.0f" % [last_ai_power, last_player_power]
	)
