class_name SimpleWc3AI
extends Node

## Sole enemy military decision authority — simple WC3 melee loop.
## OPENING → ASSEMBLE → CREEP → ATTACK (DEFEND interrupt) → ASSEMBLE → repeat.
## One MAIN ARMY (living Hero + living combat units). One objective.
## Strategic travel: PlayerRouteNavigation custom RTS only.

enum State {
	OPENING,
	ASSEMBLE,
	CREEP,
	ATTACK,
	DEFEND,
}

const MIN_PIKEMEN := 5
const MIN_WORKERS := 5
const TICK_SECONDS := 0.75
const ASSEMBLY_RADIUS := 12.0
const DEFEND_RADIUS := 40.0
const ATTACK_NEARBY_RADIUS := 36.0
const ATTACK_POWER_RATIO := 1.25
const CREEP_STOP_HERO_LEVEL := 3
const CREEP_STOP_CAMPS := 3
const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const ENEMY_WORKER_GROUP := &"enemy_workers"
const PLAYER_CC_GROUP := &"player_command_center"
const AUTHORITY_LOG_INTERVAL_SECONDS := 8.0
const COMMAND_SOURCE := &"simple_wc3_ai"

var _state: State = State.OPENING
var _tick_timer: float = 0.0
var _authority_log_timer: float = AUTHORITY_LOG_INTERVAL_SECONDS
var _debug_label: Label = null
var _logged_authority_once: bool = false

## One deterministic army gather point near the enemy base.
var assembly_position: Vector3 = Vector3.ZERO
## Instance IDs already given a one-shot join order for the current objective.
var _ordered_unit_ids: Dictionary = {}

var _objective_id: int = 0
var _objective_name: String = "-"
var _objective_destination: Vector3 = Vector3.ZERO
var _objective_kind: StringName = &"none"

var _cleared_camp_ids: Dictionary = {}
var _cleared_camp_names: Dictionary = {}
var _camps_cleared: int = 0
var _creep_phase_complete: bool = false

var last_hero_alive: bool = false
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
	_observe_army()
	_update_debug_label()
	_log_authority_proof(true)
	set_process(true)


func get_state() -> State:
	return _state


func get_state_label() -> String:
	match _state:
		State.OPENING:
			return "OPENING"
		State.ASSEMBLE:
			return "ASSEMBLE"
		State.CREEP:
			return "CREEP"
		State.ATTACK:
			return "ATTACK"
		State.DEFEND:
			return "DEFEND"
	return "?"


func get_camp_name() -> String:
	return _objective_name if _objective_kind == &"camp" else "-"


func get_camp_destination() -> Vector3:
	return _objective_destination if _objective_kind == &"camp" else Vector3.ZERO


func get_objective_name() -> String:
	return _objective_name


func get_camps_cleared() -> int:
	return _camps_cleared


## Dev test only: mark camps cleared and start normal creep selection.
func init_test_after_camps(cleared_camp_names: Array) -> void:
	_ordered_unit_ids.clear()
	_cleared_camp_ids.clear()
	_cleared_camp_names.clear()
	_camps_cleared = 0
	_creep_phase_complete = false
	_clear_objective()
	for camp_name_ref: Variant in cleared_camp_names:
		_cleared_camp_names[String(camp_name_ref)] = true
		_camps_cleared += 1
	_ensure_assembly_position()
	_observe_army()
	_begin_creep()
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
	_maintain_workers()
	_update_power_estimates()

	## Defense interrupt — same MAIN ARMY, no reserved defenders.
	if _state != State.OPENING and _has_base_threat():
		if _state != State.DEFEND:
			_begin_defend()
	elif _state == State.DEFEND and not _has_base_threat():
		_reevaluate_after_defense()

	_dispatch_new_unit_orders()

	match _state:
		State.OPENING:
			_tick_opening()
		State.ASSEMBLE:
			_tick_assemble()
		State.CREEP:
			_tick_creep()
		State.ATTACK:
			_tick_attack()
		State.DEFEND:
			_tick_defend()

	_update_debug_label()
	if _authority_log_timer >= AUTHORITY_LOG_INTERVAL_SECONDS:
		_authority_log_timer = 0.0
		_log_authority_proof(false)


# --- OPENING -----------------------------------------------------------------

func _tick_opening() -> void:
	_try_train_pikeman_if_ready()

	if not _has_completed_farm():
		var build: EnemyBuildManager = _resolve_build_manager()
		if build != null and build.try_place_farm():
			strategic_orders_issued += 1
		return

	if not _has_completed_hero_altar():
		var build_a: EnemyBuildManager = _resolve_build_manager()
		if build_a != null and build_a.try_place_hero_altar():
			strategic_orders_issued += 1
		return

	if not _has_completed_barracks():
		var build_b: EnemyBuildManager = _resolve_build_manager()
		if build_b != null and build_b.try_place_barracks():
			strategic_orders_issued += 1
		return

	if not last_hero_alive:
		var altar: HeroAltar = _find_completed_hero_altar()
		if altar != null and not altar.is_training_hero():
			if altar.try_train_enemy_hero():
				strategic_orders_issued += 1
		return

	_ensure_assembly_position()
	if last_pikeman_count >= MIN_PIKEMEN:
		_state = State.ASSEMBLE
		_try_train_pikeman()
		return

	var living_and_pending: int = last_pikeman_count + _count_pending_pikemen()
	if living_and_pending >= MIN_PIKEMEN:
		return
	_try_train_pikeman()


# --- ASSEMBLE ----------------------------------------------------------------

func _tick_assemble() -> void:
	_try_train_pikeman()

	if not last_hero_alive:
		_state = State.OPENING
		_clear_objective()
		return

	if last_pikeman_count < MIN_PIKEMEN:
		## Stay assembling while rebuilding force; opening already finished buildings.
		_ensure_assembly_position()
		if assembly_position != Vector3.ZERO and not _has_active_objective():
			_set_objective(&"rally", 0, "Rally", assembly_position)
			_issue_army_move(_collect_main_army(), assembly_position, &"move")
		return

	_ensure_assembly_position()
	if assembly_position == Vector3.ZERO:
		return

	if not _has_active_objective() or _objective_kind != &"rally":
		_set_objective(&"rally", 0, "Rally", assembly_position)
		_issue_army_move(_collect_main_army(), assembly_position, &"move")

	if _is_army_assembled():
		_reevaluate()


# --- CREEP -------------------------------------------------------------------

func _tick_creep() -> void:
	_try_train_pikeman()
	var army: Array = _collect_main_army()
	if _is_army_too_weak():
		_clear_objective()
		_state = State.ASSEMBLE
		return

	var camp: Node3D = _resolve_objective_node()
	if camp == null or not _camp_has_living_creeps(camp):
		_on_camp_cleared(camp)
		return

	## Current camp still alive — do not refresh army orders.


func _begin_creep() -> void:
	var army: Array = _collect_main_army()
	if _is_army_too_weak() or not _has_minimum_force(army):
		_state = State.ASSEMBLE
		_clear_objective()
		return

	if _should_stop_creeping():
		_creep_phase_complete = true
		_enter_post_creep()
		return

	var camp: Node3D = _select_creep_camp(army)
	if camp == null:
		_creep_phase_complete = true
		_enter_post_creep()
		return

	_set_objective(
		&"camp",
		camp.get_instance_id(),
		String(camp.name),
		Vector3(camp.global_position.x, 0.0, camp.global_position.z)
	)
	_state = State.CREEP
	_issue_army_move(army, _objective_destination, &"attack_move")


func _on_camp_cleared(camp: Node3D) -> void:
	if camp != null and is_instance_valid(camp):
		_cleared_camp_ids[camp.get_instance_id()] = true
		_cleared_camp_names[String(camp.name)] = true
	elif _objective_id != 0:
		_cleared_camp_ids[_objective_id] = true
		if not _objective_name.is_empty() and _objective_name != "-":
			_cleared_camp_names[_objective_name] = true
	_camps_cleared += 1

	var hero: Hero = _find_living_hero()
	if hero != null:
		last_hero_level = hero.level

	_clear_objective()
	if _should_stop_creeping():
		_creep_phase_complete = true
		_enter_post_creep()
		return
	_begin_creep()


## After initial creep stop conditions — attack if strong, else assemble / keep creeping.
func _enter_post_creep() -> void:
	_update_power_estimates()
	var army: Array = _collect_main_army()
	if _should_attack():
		_begin_attack()
		return
	var camp: Node3D = _select_creep_camp(army)
	if camp != null and not _should_attack():
		## Keep creeping if useful (still not strong enough to attack).
		_set_objective(
			&"camp",
			camp.get_instance_id(),
			String(camp.name),
			Vector3(camp.global_position.x, 0.0, camp.global_position.z)
		)
		_state = State.CREEP
		_issue_army_move(army, _objective_destination, &"attack_move")
		return
	_state = State.ASSEMBLE
	_ensure_assembly_position()
	if assembly_position != Vector3.ZERO:
		_set_objective(&"rally", 0, "Rally", assembly_position)
		_issue_army_move(army, assembly_position, &"move")


func _should_stop_creeping() -> bool:
	if last_hero_level >= CREEP_STOP_HERO_LEVEL:
		return true
	if _camps_cleared >= CREEP_STOP_CAMPS:
		return true
	if _should_attack():
		return true
	return false


# --- ATTACK ------------------------------------------------------------------

func _tick_attack() -> void:
	_try_train_pikeman()
	if _is_army_too_weak():
		_clear_objective()
		_state = State.ASSEMBLE
		return

	var target: Node3D = _resolve_objective_node()
	if target == null or not _is_living_attack_target(target):
		_clear_objective()
		_begin_attack()
		return

	## Target still valid — leave army alone.


func _begin_attack() -> void:
	var army: Array = _collect_main_army()
	if _is_army_too_weak() or not _has_minimum_force(army):
		_state = State.ASSEMBLE
		_clear_objective()
		return

	var target: Node3D = _select_attack_target(army)
	if target == null:
		_state = State.ASSEMBLE
		_clear_objective()
		return

	_set_objective(
		&"attack",
		target.get_instance_id(),
		_describe_target(target),
		Vector3(target.global_position.x, 0.0, target.global_position.z)
	)
	_state = State.ATTACK
	_issue_army_attack(army, target)


# --- DEFEND ------------------------------------------------------------------

func _tick_defend() -> void:
	_try_train_pikeman()
	if _is_army_too_weak():
		## Still defend with whoever remains if threat exists; otherwise assemble.
		if not _has_base_threat():
			_clear_objective()
			_state = State.ASSEMBLE
			return

	var target: Node3D = _resolve_objective_node()
	if target == null or not _is_living_attack_target(target) or not _is_threat_unit(target):
		if not _has_base_threat():
			_reevaluate_after_defense()
			return
		_begin_defend()
		return


func _begin_defend() -> void:
	var army: Array = _collect_main_army()
	if army.is_empty():
		_state = State.ASSEMBLE
		_clear_objective()
		return

	var target: Node3D = _select_defend_target()
	if target == null:
		_reevaluate_after_defense()
		return

	_set_objective(
		&"defend",
		target.get_instance_id(),
		_describe_target(target),
		Vector3(target.global_position.x, 0.0, target.global_position.z)
	)
	_state = State.DEFEND
	_issue_army_attack(army, target)


func _reevaluate_after_defense() -> void:
	_clear_objective()
	_reevaluate()


# --- Reevaluation ------------------------------------------------------------

func _reevaluate() -> void:
	_update_power_estimates()
	var army: Array = _collect_main_army()

	if _is_army_too_weak() or not _has_minimum_force(army):
		_state = State.ASSEMBLE
		_ensure_assembly_position()
		if assembly_position != Vector3.ZERO:
			_set_objective(&"rally", 0, "Rally", assembly_position)
			_issue_army_move(army, assembly_position, &"move")
		return

	if _should_attack():
		_begin_attack()
		return

	if not _creep_phase_complete and not _should_stop_creeping():
		_begin_creep()
		return

	if _should_stop_creeping():
		_creep_phase_complete = true

	## Not strong enough to attack — creep if camps remain, else assemble.
	if _select_creep_camp(army) != null:
		_enter_post_creep()
		return

	_state = State.ASSEMBLE
	_ensure_assembly_position()
	if assembly_position != Vector3.ZERO:
		_set_objective(&"rally", 0, "Rally", assembly_position)
		_issue_army_move(army, assembly_position, &"move")


func _should_attack() -> bool:
	if not last_hero_alive or last_pikeman_count < MIN_PIKEMEN:
		return false
	if last_ai_power <= 0.0:
		return false
	## Player almost gone and AI has a real army.
	if last_player_power < 80.0 and last_ai_power >= 250.0:
		return true
	return last_ai_power >= last_player_power * ATTACK_POWER_RATIO


# --- Army / power ------------------------------------------------------------

func _has_minimum_force(army: Array) -> bool:
	_observe_force_counts(army)
	return last_hero_alive and last_pikeman_count >= MIN_PIKEMEN


func _is_army_too_weak() -> bool:
	return not last_hero_alive or last_pikeman_count < 3


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
		if not _is_living_enemy_combat_unit(node_variant):
			continue
		army.append(node_variant as Unit)
	return army


func _is_living_enemy_combat_unit(node_variant: Variant) -> bool:
	if not _is_living_enemy_unit(node_variant):
		return false
	var unit: Unit = node_variant as Unit
	if unit is Worker:
		return false
	## MAIN ARMY = Hero + military combat units (Pikemen today; others later).
	return unit is Hero or unit is MilitaryUnit


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

func _select_attack_target(army: Array) -> Node3D:
	var origin: Vector3 = _army_centroid(army)
	if origin == Vector3.ZERO:
		origin = _enemy_base_position(get_tree())

	## 1) Nearby player military.
	var nearby: Node3D = _nearest_player_military(origin, ATTACK_NEARBY_RADIUS)
	if nearby != null:
		return nearby

	## 2) Player Hero.
	var player_hero: Node3D = _find_player_hero()
	if player_hero != null:
		return player_hero

	## 3) Player Command Center.
	var cc: Node3D = _find_player_command_center()
	if cc != null:
		return cc

	## 4) Other player production buildings.
	return _find_player_production_building()


func _select_defend_target() -> Node3D:
	var base: Vector3 = _enemy_base_position(get_tree())
	if base == Vector3.ZERO:
		return null
	return _nearest_player_military(base, DEFEND_RADIUS)


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


func _is_threat_unit(node: Node3D) -> bool:
	if not node is Unit:
		return false
	if CombatTargetValidation.is_enemy_faction(node):
		return false
	if node is Worker:
		return false
	return node is Hero or node is MilitaryUnit


func _has_base_threat() -> bool:
	var base: Vector3 = _enemy_base_position(get_tree())
	if base == Vector3.ZERO:
		return false
	return _nearest_player_military(base, DEFEND_RADIUS) != null


func _describe_target(target: Node3D) -> String:
	if target is Hero:
		return "PlayerHero"
	if target is CommandCenter:
		return "PlayerCC"
	if target is MilitaryUnit:
		return String(target.name)
	if target is Building:
		return String(target.name)
	return String(target.name)


# --- Creep camp selection ----------------------------------------------------

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

	## Prefer early-safe Medium/Easy camps; else nearest living uncleared camp.
	var best_early: Node3D = null
	var best_early_dist: float = INF
	var best_any: Node3D = null
	var best_any_dist: float = INF
	for camp: Node3D in active_camps:
		if camp == null or not is_instance_valid(camp):
			continue
		if _is_camp_cleared(camp):
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


# --- Orders / movement -------------------------------------------------------

func _has_active_objective() -> bool:
	return _objective_kind != &"none" and _objective_destination != Vector3.ZERO


func _set_objective(kind: StringName, id: int, obj_name: String, destination: Vector3) -> void:
	_objective_kind = kind
	_objective_id = id
	_objective_name = obj_name
	_objective_destination = destination
	_ordered_unit_ids.clear()


func _clear_objective() -> void:
	_objective_kind = &"none"
	_objective_id = 0
	_objective_name = "-"
	_objective_destination = Vector3.ZERO
	_ordered_unit_ids.clear()


func _resolve_objective_node() -> Node3D:
	if _objective_id != 0:
		var obj: Object = instance_from_id(_objective_id)
		if obj != null and is_instance_valid(obj) and obj is Node3D:
			return obj as Node3D
	if _objective_kind == &"camp":
		return _resolve_camp_by_name()
	return null


func _resolve_camp_by_name() -> Node3D:
	if _objective_name.is_empty() or _objective_name == "-":
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for camp: Node3D in CreepCampSafety.collect_active_camps(tree):
		if camp == null or not is_instance_valid(camp):
			continue
		if String(camp.name) == _objective_name:
			_objective_id = camp.get_instance_id()
			return camp
	for node_variant: Variant in tree.get_nodes_in_group(&"creep_camps"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Node3D:
			continue
		var camp: Node3D = node_variant as Node3D
		if String(camp.name) == _objective_name:
			_objective_id = camp.get_instance_id()
			return camp
	return null


## New units join the current objective once; never refresh the whole army.
func _dispatch_new_unit_orders() -> void:
	if _state == State.OPENING:
		## During opening, only rally finished units toward assembly once hero exists.
		if not last_hero_alive:
			return
		_ensure_assembly_position()
		if assembly_position == Vector3.ZERO:
			return
		for unit_ref: Variant in _collect_main_army():
			if not NodeSafety.is_alive_node(unit_ref):
				continue
			var unit: Unit = unit_ref as Unit
			var unit_id: int = unit.get_instance_id()
			if _ordered_unit_ids.has(unit_id):
				continue
			_issue_single_unit_order(unit, assembly_position, &"move")
			_ordered_unit_ids[unit_id] = true
		return

	if not _has_active_objective():
		return

	var order_kind: StringName = &"move"
	if _state == State.CREEP or _state == State.ATTACK or _state == State.DEFEND:
		order_kind = &"attack_move"

	var attack_target: Node3D = null
	if _state == State.ATTACK or _state == State.DEFEND:
		attack_target = _resolve_objective_node()

	for unit_ref: Variant in _collect_main_army():
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		var unit: Unit = unit_ref as Unit
		var unit_id: int = unit.get_instance_id()
		if _ordered_unit_ids.has(unit_id):
			continue
		if attack_target != null and _is_living_attack_target(attack_target):
			_issue_single_unit_attack(unit, attack_target)
		else:
			_issue_single_unit_order(unit, _objective_destination, order_kind)
		_ordered_unit_ids[unit_id] = true


func _issue_army_move(units: Array, destination: Vector3, order_kind: StringName) -> void:
	if units.is_empty() or destination == Vector3.ZERO:
		return

	var living: Array = []
	for unit_ref: Variant in units:
		if NodeSafety.is_alive_node(unit_ref):
			living.append(unit_ref)
	if living.is_empty():
		return

	## Pikemen first, Hero immediately after — same destination.
	var pikemen: Array = []
	var heroes: Array = []
	var others: Array = []
	for unit_ref: Variant in living:
		if unit_ref is Spearman:
			pikemen.append(unit_ref)
		elif unit_ref is Hero:
			heroes.append(unit_ref)
		else:
			others.append(unit_ref)

	var total_squad: int = 0
	var any_handled: bool = false
	for batch: Array in [pikemen, others, heroes]:
		if batch.is_empty():
			continue
		var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			batch,
			destination,
			order_kind,
			false,
			COMMAND_SOURCE
		)
		any_handled = any_handled or bool(result.get("handled", false))
		total_squad += int(result.get("squad_size", 0))
		for unit_ref: Variant in batch:
			if NodeSafety.is_alive_node(unit_ref):
				_ordered_unit_ids[(unit_ref as Unit).get_instance_id()] = true

	last_move_handled = any_handled
	last_move_squad_size = total_squad
	if any_handled:
		strategic_orders_issued += 1


func _issue_army_attack(units: Array, target: Node3D) -> void:
	if units.is_empty() or not NodeSafety.is_alive_node(target):
		return

	## Custom RTS travel to target, then explicit combat commitment.
	var destination := Vector3(target.global_position.x, 0.0, target.global_position.z)
	_issue_army_move(units, destination, &"attack_move")

	for unit_ref: Variant in units:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		_issue_single_unit_attack(unit_ref as Unit, target)


func _issue_single_unit_order(unit: Unit, destination: Vector3, order_kind: StringName) -> void:
	if not NodeSafety.is_alive_node(unit) or destination == Vector3.ZERO:
		return
	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		[unit],
		destination,
		order_kind,
		false,
		COMMAND_SOURCE
	)
	last_move_handled = bool(result.get("handled", false))
	last_move_squad_size = int(result.get("squad_size", 0))
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


# --- Production / economy ----------------------------------------------------

func _try_train_pikeman_if_ready() -> void:
	if not _has_completed_barracks():
		return
	_try_train_pikeman()


func _try_train_pikeman() -> void:
	var barracks: Barracks = _find_completed_barracks()
	if barracks == null:
		return
	if barracks.try_train_enemy_spearman():
		strategic_orders_issued += 1


func _maintain_workers() -> void:
	var living: int = _count_living_workers()
	var pending: int = _count_pending_workers()
	if living + pending >= MIN_WORKERS:
		return
	var cc: CommandCenter = _find_enemy_command_center()
	if cc == null:
		return
	if cc.try_train_enemy_worker():
		strategic_orders_issued += 1


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
		"Simple WC3 AI active: YES | Old Military AI active: %s | Simple orders: %d | State: %s"
		% [
			"YES" if old_active else "NO",
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
		+ "Hero: lvl %d\n" % last_hero_level
		+ "Army: %d\n" % last_army_count
		+ "Pikemen: %d\n" % last_pikeman_count
		+ "Camps cleared: %d\n" % _camps_cleared
		+ "Target:\n%s\n" % _objective_name
		+ "AI Power: %.0f\n" % last_ai_power
		+ "Player Power: %.0f" % last_player_power
	)
