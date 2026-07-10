class_name EnemyArmyCommand
extends RefCounted

## Shared enemy army command helpers. Registers combat units and issues group orders.

const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMIES_GROUP := &"enemies"
const ENEMY_COMMAND_CENTER_GROUP := &"enemy_command_center"
const ENEMY_WORKERS_GROUP := &"enemy_workers"
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const BUILDINGS_GROUP := &"buildings"
const UNITS_GROUP := &"units"
const HEROES_GROUP := &"heroes"

const ARMY_RALLY_OFFSET := Vector3(-2.0, -0.5, 3.0)
const BASE_THREAT_DETECTION_RANGE := 60.0
const APPROACH_DETECTION_RANGE := 75.0
const WORKER_THREAT_RANGE := 36.0
const BUILDING_THREAT_RANGE := 32.0
const ENEMY_ECONOMY_AREA_RANGE := 42.0
const FORMATION_SPACING := 2.0
const RANGED_ROW_DEPTH_MULTIPLIER := 1.5
const HERO_ROW_DEPTH_MULTIPLIER := 1.25

const MIN_NON_HERO_FOR_HERO_JOIN := 4
const MIN_ARMY_UNITS_TO_CONTINUE_ATTACK := 6
const MIN_TOTAL_COMBAT_UNITS_FOR_ATTACK := 12
const MIN_MELEE_UNITS_FOR_ATTACK := 3
const MIN_RANGED_UNITS_FOR_ATTACK := 2
const ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS := 4
const ATTACK_STANDARD_MIN_NON_HERO_UNITS := 6
const ATTACK_TIMER_MIN_NON_HERO_UNITS := 12
const ATTACK_DESPERATE_MIN_NON_HERO_UNITS := 6
const ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS := 4
const ATTACK_TIMER_STANDARD_SECONDS := 240.0
const ATTACK_TIMER_DESPERATE_SECONDS := 360.0
const DEBUG_ATTACK_GATE := false
const DEBUG_COMBAT_AI := false
const PLAYER_ARMY_STRENGTH_RATIO := 1.15
const ATTACK_AGGRESSIVE_STRENGTH_RATIO := 1.05
const ATTACK_NORMAL_STRENGTH_RATIO := 1.15
const DEFEND_FIGHT_STRENGTH_RATIO := 0.80
const RETREAT_STRENGTH_RATIO := 0.70
const EMERGENCY_RETREAT_ARMY_LOSS_RATIO := 0.40
const ASSEMBLY_RADIUS := 10.0
const ASSEMBLY_REQUIRED_PERCENT := 0.75
const ASSEMBLY_MAX_WAIT_SECONDS := 7.0
const COMBAT_EVAL_INTERVAL_SECONDS := 0.75
const MIN_STATE_DURATION_SECONDS := 0.75
const RETREAT_COOLDOWN_SECONDS := 10.0
const LOCAL_FIGHT_RADIUS := 30.0
const MAX_CHASE_DISTANCE := 25.0
const MAX_CHASE_DURATION_SECONDS := 6.0
const PLAYER_ARMY_MEMORY_DECAY_SECONDS := 45.0
const PLAYER_CREEP_DETECT_RADIUS := 28.0
const CREEP_HERO_WAIT_RADIUS := 18.0
const PHASE_EARLY_SECONDS := 300.0
const PHASE_MID_SECONDS := 600.0
const PHASE_EARLY_MIN_ARMY := 6
const PHASE_MID_MIN_ARMY := 12
const PHASE_LATE_MIN_ARMY := 20
const STRENGTH_SPEARMAN := 1.0
const STRENGTH_SWORDSMAN := 1.2
const STRENGTH_ARCHER := 1.2
const STRENGTH_LIGHT_CAVALRY := 1.6
const STRENGTH_HEAVY_CAVALRY := 2.2
const STRENGTH_CAVALRY_ARCHER := 1.8
const STRENGTH_CANNON := 2.0
const STRENGTH_HERO_BASE := 3.0
const STRENGTH_HERO_PER_LEVEL := 0.5
const KNOWN_PLAYER_SCOUT_RANGE := 55.0
const ARMY_GROUP_MAX_RADIUS := 24.0
const WAVE_REINFORCEMENT_WAIT_SECONDS := 5.0
const MIN_ATTACK_ARMY_POWER := 350
const HERO_ALONE_PLAYER_THREAT_RANGE := 18.0
const HERO_MAX_DISTANCE_FROM_ARMY := 16.0
const HERO_RETREAT_HP_RATIO := 0.35
const HERO_DEFENSE_CRITICAL_RETREAT_HP_RATIO := 0.20
const HERO_WAVE_JOIN_HP_RATIO := 0.60
const HERO_DEFENSIVE_ABILITY_HP_RATIO := 0.40
const DEFENSE_GATHER_MAX_DISTANCE := 42.0
const DEFENSE_HERO_EXTRA_GATHER_DISTANCE := 14.0
const DEFENSE_THREAT_POWER_RANGE := 34.0
const DEFENSE_HOLD_FORWARD_DISTANCE := 10.0
const CORE_BASE_DEFENSE_RADIUS := BASE_THREAT_DETECTION_RANGE
const EMERGENCY_GATHER_WAIT_SECONDS := 3.0
const EMERGENCY_CLEAR_SECONDS := 5.0
const EMERGENCY_SERIOUS_THREAT_POWER := 120
const EMERGENCY_SCOUT_IGNORE_BUILDING_DISTANCE := 28.0
const EMERGENCY_HERO_JOIN_HP_RATIO := 0.35
const DEFENSE_POWER_HERO_BASE := 220
const DEFENSE_POWER_MELEE_HEALTH := 1.0
const DEFENSE_POWER_RANGED_HEALTH := 0.85
const DEFENSE_POWER_DAMAGE_MULTIPLIER := 8.0
const HERO_AOE_PLAYER_COUNT := 3
const HERO_AOE_CHECK_RANGE := 10.0
const HERO_POWER_STRIKE_SEARCH_RANGE := 14.0
const ATTACK_OBJECTIVE_REISSUE_SECONDS := 2.5
const ATTACK_OBJECTIVE_STUCK_SECONDS := 3.0
const ATTACK_OBJECTIVE_NEAR_DISTANCE := 22.0
const ATTACK_OBJECTIVE_SPREAD_MULTIPLIER := 1.35
const ATTACK_CLOSE_TO_WIN_CC_HEALTH_RATIO := 0.35
const ATTACK_CLOSE_TO_WIN_ARMY_DISTANCE := 28.0
const IMPORTANT_BUILDING_SEARCH_RANGE := 200.0

const WAVE_1_MIN_NON_HERO_UNITS := 6
const WAVE_2_MIN_NON_HERO_UNITS := 12
const WAVE_3_MIN_NON_HERO_UNITS := 16
const WAVE_4_MIN_NON_HERO_UNITS := 20
const RESOURCE_HIGH_THRESHOLD := 3000
const RESOURCE_AGGRESSIVE_THRESHOLD := 6000
const REINFORCEMENT_MERGE_MIN_UNITS := 5
const WAVE_REGROUP_MAX_DISTANCE := 22.0
const WAVE_REBUILD_ARMY_RATIO := 0.40

const FINISHING_MODE_EVAL_INTERVAL := 2.0
const FINISHING_MODE_EXIT_COOLDOWN := 8.0
const FINISHING_MODE_OBJECTIVE_REISSUE_SECONDS := 1.5
const FINISHING_MODE_REINFORCEMENT_PULL_INTERVAL := 2.0
const FINISHING_MODE_MIN_AI_COMBAT_UNITS := 15
const FINISHING_MODE_MAX_PLAYER_COMBAT_UNITS := 5
const FINISHING_MODE_MAX_PLAYER_MILITARY_PRODUCTION := 1
const FINISHING_MODE_WEAK_PLAYER_COMBAT_FOR_PRODUCTION := 8
const FINISHING_MODE_IN_BASE_DISTANCE := 35.0
const FINISHING_MODE_WEAK_RESISTANCE_POWER := 80
const FINISHING_MODE_PLAYER_RECOVERY_RATIO := 0.65
const FINISHING_MODE_ARMY_DESTROYED_RATIO := 0.25
const FINISHING_MODE_MIN_PUSH_UNITS := 4
const FINISHING_MODE_TOWER_THREAT_BUFFER := 2.0

enum ArmyMode {
	IDLE,
	OPENING,
	ASSEMBLING,
	CREEPING,
	ATTACKING,
	INTERCEPTING,
	DEFENDING,
	RETREATING,
	REGROUPING,
}

static var _army_mode: ArmyMode = ArmyMode.IDLE
static var _mode_claim_msec: int = 0
static var _orders_authorized: bool = false
static var _assembly_timer: float = 0.0
static var _assembly_rally: Vector3 = Vector3.ZERO
static var _assembly_required_count: int = 0
static var _retreat_cooldown: float = 0.0
static var _fight_start_strength: float = 0.0
static var _fight_anchor_position: Vector3 = Vector3.ZERO
static var _fight_start_msec: int = 0
static var _last_combat_eval_msec: int = 0
static var _main_army_cache: Array = []
static var _player_army_memory: Dictionary = {
	"strength": 0.0,
	"position": Vector3.ZERO,
	"hero_level": 0,
	"timestamp_msec": 0,
	"unit_count": 0,
}
static var _is_rebuilding_army: bool = false
static var _active_wave_start_unit_count: int = 0
static var _active_wave_objective: Node3D = null
static var _active_wave_objective_position: Vector3 = Vector3.ZERO
static var _objective_reissue_timer: float = 0.0
static var _objective_stuck_timer: float = 0.0
static var _objective_last_building_health: int = -1
static var _finishing_mode_active: bool = false
static var _finishing_mode_exit_cooldown: float = 0.0
static var _finishing_mode_eval_timer: float = 0.0
static var _last_finishing_objective: Node3D = null
static var _emergency_defense_active: bool = false
static var _emergency_threat_position: Vector3 = Vector3.ZERO
static var _emergency_reason: StringName = &""
static var _debug_enabled_override: bool = false


static func get_army_mode() -> ArmyMode:
	return _army_mode


static func is_retreat_on_cooldown() -> bool:
	return _retreat_cooldown > 0.0


static func tick_retreat_cooldown(delta: float) -> void:
	if _retreat_cooldown > 0.0:
		_retreat_cooldown = maxf(0.0, _retreat_cooldown - delta)


static func get_phase_min_army_size(match_elapsed_seconds: float) -> int:
	if match_elapsed_seconds >= PHASE_MID_SECONDS:
		return PHASE_LATE_MIN_ARMY
	if match_elapsed_seconds >= PHASE_EARLY_SECONDS:
		return PHASE_MID_MIN_ARMY
	return PHASE_EARLY_MIN_ARMY


static func get_main_army_group(tree: SceneTree) -> Array:
	purge_and_rebuild_main_army(tree)
	return _main_army_cache.duplicate()


static func purge_and_rebuild_main_army(tree: SceneTree) -> void:
	var units: Array = []
	var seen_ids: Dictionary = {}

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if not is_living_combat_unit(node):
			continue
		if node is Worker:
			continue

		var unit_id: int = node.get_instance_id()
		if seen_ids.has(unit_id):
			continue

		seen_ids[unit_id] = true
		units.append(node)

	_main_army_cache = units


static func with_authorized_orders(callback: Callable) -> void:
	_orders_authorized = true
	callback.call()
	_orders_authorized = false


static func _combat_orders_allowed(mission: EnemyUnitMission.Mission) -> bool:
	if _orders_authorized or _emergency_defense_active:
		return true

	match mission:
		EnemyUnitMission.Mission.RETREAT, EnemyUnitMission.Mission.REGROUP, EnemyUnitMission.Mission.IDLE:
			return true
		EnemyUnitMission.Mission.ATTACK:
			return _army_mode == ArmyMode.ATTACKING or _army_mode == ArmyMode.ASSEMBLING
		EnemyUnitMission.Mission.CREEP:
			return _army_mode == ArmyMode.CREEPING or _army_mode == ArmyMode.ASSEMBLING
		EnemyUnitMission.Mission.DEFEND:
			return (
				_army_mode == ArmyMode.DEFENDING
				or _army_mode == ArmyMode.INTERCEPTING
				or _army_mode == ArmyMode.ASSEMBLING
			)
		_:
			return false


static func set_debug_enabled(enabled: bool) -> void:
	_debug_enabled_override = enabled


static func _debug_combat(message: String) -> void:
	if DEBUG_COMBAT_AI or _debug_enabled_override:
		print("[AI Combat] %s" % message)


static func debug_combat_log(message: String) -> void:
	_debug_combat(message)


static func _debug_state_change(from_mode: ArmyMode, to_mode: ArmyMode, reason: String = "") -> void:
	if from_mode == to_mode:
		return

	_debug_combat(
		"state %s -> %s%s"
		% [
			_army_mode_label(from_mode),
			_army_mode_label(to_mode),
			(" (%s)" % reason) if not reason.is_empty() else "",
		]
	)


static func _army_mode_label(mode: ArmyMode) -> String:
	match mode:
		ArmyMode.IDLE:
			return "IDLE"
		ArmyMode.OPENING:
			return "OPENING"
		ArmyMode.ASSEMBLING:
			return "ASSEMBLING"
		ArmyMode.CREEPING:
			return "CREEPING"
		ArmyMode.DEFENDING:
			return "DEFENDING"
		ArmyMode.INTERCEPTING:
			return "INTERCEPTING"
		ArmyMode.ATTACKING:
			return "ATTACKING"
		ArmyMode.RETREATING:
			return "RETREATING"
		ArmyMode.REGROUPING:
			return "REGROUPING"
		_:
			return "UNKNOWN"


static func get_unit_type_strength_weight(unit: Node) -> float:
	if unit is Hero:
		var level: int = int(unit.get("level")) if "level" in unit else 1
		return STRENGTH_HERO_BASE + float(level) * STRENGTH_HERO_PER_LEVEL

	if unit is Spearman:
		return STRENGTH_SPEARMAN
	if unit is Swordsman:
		return STRENGTH_SWORDSMAN
	if unit is Archer:
		return STRENGTH_ARCHER
	if unit is LightCavalry:
		return STRENGTH_LIGHT_CAVALRY
	if unit is HeavyCavalry:
		return STRENGTH_HEAVY_CAVALRY
	if unit is CavalryArcher:
		return STRENGTH_CAVALRY_ARCHER
	if unit is Cannon:
		return STRENGTH_CANNON

	return 1.0


static func estimate_combat_strength(units: Array) -> float:
	var strength: float = 0.0

	for unit: Variant in NodeSafety.clean_node_array(units):
		if not NodeSafety.is_alive_node(unit):
			continue
		if not is_living_combat_unit(unit as Node):
			continue
		if unit is Worker:
			continue

		var base_weight: float = get_unit_type_strength_weight(unit as Node)
		var health_ratio: float = get_health_ratio(unit as Node)
		strength += base_weight * health_ratio * 100.0

	return strength


static func estimate_local_fight_balance(
	tree: SceneTree,
	position: Vector3,
	radius: float = LOCAL_FIGHT_RADIUS
) -> Dictionary:
	var ai_units: Array = collect_player_military_near(tree, position, radius)
	# Fix: collect AI units near position
	ai_units = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue
		if horizontal_distance((unit as Node3D).global_position, position) <= radius:
			ai_units.append(unit)

	var player_units: Array = collect_player_military_near(tree, position, radius)
	var ai_strength: float = estimate_combat_strength(ai_units)
	var player_strength: float = estimate_combat_strength(player_units)

	return {
		"ai_strength": ai_strength,
		"player_strength": player_strength,
		"ratio": ai_strength / maxf(player_strength, 1.0),
		"ai_units": ai_units,
		"player_units": player_units,
	}


static func record_player_army_observation(tree: SceneTree, position: Vector3, radius: float) -> void:
	var player_units: Array = collect_player_military_near(tree, position, radius)
	if player_units.is_empty():
		return

	var strength: float = estimate_combat_strength(player_units)
	var hero_level: int = 0
	for unit: Variant in player_units:
		if unit is Hero:
			hero_level = maxi(hero_level, int((unit as Hero).level))

	_player_army_memory = {
		"strength": strength,
		"position": position,
		"hero_level": hero_level,
		"timestamp_msec": Time.get_ticks_msec(),
		"unit_count": player_units.size(),
	}


static func get_effective_player_strength_at(tree: SceneTree, position: Vector3, radius: float) -> float:
	var visible: Array = collect_player_military_near(tree, position, radius)
	if not visible.is_empty():
		record_player_army_observation(tree, position, radius)
		return estimate_combat_strength(visible)

	var memory_strength: float = float(_player_army_memory.get("strength", 0.0))
	if memory_strength <= 0.0:
		return 0.0

	var memory_position: Vector3 = _player_army_memory.get("position", Vector3.ZERO)
	var age_seconds: float = float(
		Time.get_ticks_msec() - int(_player_army_memory.get("timestamp_msec", 0))
	) / 1000.0
	if age_seconds > PLAYER_ARMY_MEMORY_DECAY_SECONDS:
		return memory_strength * 0.5

	if horizontal_distance(memory_position, position) > radius * 2.5:
		return memory_strength * 0.7

	return memory_strength


static func begin_fight_tracking(units: Array, anchor_position: Vector3) -> void:
	_fight_start_strength = estimate_combat_strength(units)
	_fight_anchor_position = anchor_position
	_fight_start_msec = Time.get_ticks_msec()


static func should_retreat_from_fight(tree: SceneTree) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_combat_eval_msec < int(COMBAT_EVAL_INTERVAL_SECONDS * 1000.0):
		return false
	_last_combat_eval_msec = now_msec

	var anchor: Vector3 = _fight_anchor_position
	if anchor == Vector3.ZERO:
		anchor = compute_army_center(collect_living_combat_units(tree))

	var balance: Dictionary = estimate_local_fight_balance(tree, anchor)
	var ratio: float = float(balance.get("ratio", 1.0))
	var player_strength: float = float(balance.get("player_strength", 0.0))

	if player_strength > 0.0 and ratio <= RETREAT_STRENGTH_RATIO:
		_debug_combat("retreating: ratio %.2f" % ratio)
		return true

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and get_health_ratio(hero) < HERO_RETREAT_HP_RATIO:
		_debug_combat("retreating: hero low health")
		return true

	if _fight_start_strength > 0.0:
		var current_strength: float = estimate_combat_strength(balance.get("ai_units", []))
		if current_strength <= _fight_start_strength * (1.0 - EMERGENCY_RETREAT_ARMY_LOSS_RATIO):
			_debug_combat("retreating: army lost %.0f%%" % (EMERGENCY_RETREAT_ARMY_LOSS_RATIO * 100.0))
			return true

	return false


static func should_stop_chase(
	tree: SceneTree,
	start_position: Vector3,
	army_center: Vector3,
	target_position: Vector3
) -> bool:
	if start_position == Vector3.ZERO:
		return false

	if horizontal_distance(army_center, start_position) > MAX_CHASE_DISTANCE:
		return true

	if (
		_fight_start_msec > 0
		and float(Time.get_ticks_msec() - _fight_start_msec) / 1000.0 > MAX_CHASE_DURATION_SECONDS
	):
		return true

	var non_hero: Array = collect_living_non_hero_combat_units(tree)
	if non_hero.size() >= 4:
		var grouped: Array = filter_units_near_rally(non_hero, army_center, ASSEMBLY_RADIUS * 2.0)
		if float(grouped.size()) / float(non_hero.size()) < 0.5:
			return true

	return horizontal_distance(army_center, target_position) > MAX_CHASE_DISTANCE * 1.25


static func get_retreat_destination(tree: SceneTree) -> Vector3:
	var rally: Vector3 = resolve_enemy_rally_position(tree)
	if rally != Vector3.ZERO:
		return rally

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if node is Barracks or node is Stable:
			if _is_living_building(node as Building):
				return (node as Node3D).global_position

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_building(node as CommandCenter):
			return (node as Node3D).global_position

	return Vector3.ZERO


static func initiate_group_retreat(tree: SceneTree, reason: String = "") -> bool:
	if not try_claim_army_mode(ArmyMode.RETREATING):
		return false

	var destination: Vector3 = get_retreat_destination(tree)
	if destination == Vector3.ZERO:
		release_army_mode(ArmyMode.RETREATING)
		return false

	cancel_offensive_orders(tree)
	var survivors: Array = collect_living_combat_units(tree)
	with_authorized_orders(func() -> void:
		command_retreat_to(survivors, destination)
	)

	_retreat_cooldown = RETREAT_COOLDOWN_SECONDS
	_fight_start_strength = 0.0
	EnemyUnitMission.set_main_army_mission(EnemyUnitMission.Mission.RETREAT, reason)
	return true


static func complete_retreat_to_regroup(tree: SceneTree) -> void:
	if get_army_mode() != ArmyMode.RETREATING:
		return

	var rally: Vector3 = get_retreat_destination(tree)
	var army: Array = collect_living_combat_units(tree)
	var assembled: int = filter_units_near_rally(army, rally, ASSEMBLY_RADIUS * 2.0).size()
	if army.size() > 0 and float(assembled) / float(army.size()) < 0.6:
		return

	release_army_mode(ArmyMode.RETREATING)
	if try_claim_army_mode(ArmyMode.REGROUPING):
		set_rebuilding_army(true)
		command_regroup_at_rally(tree, rally)
		EnemyUnitMission.set_main_army_mission(EnemyUnitMission.Mission.REGROUP, "post-retreat")


static func begin_assembly(
	tree: SceneTree,
	target_mode: ArmyMode,
	rally_position: Vector3,
	required_units: Array
) -> bool:
	if rally_position == Vector3.ZERO:
		return false

	var previous_mode: ArmyMode = _army_mode
	if not try_claim_army_mode(ArmyMode.ASSEMBLING):
		return false

	_assembly_timer = 0.0
	_assembly_rally = rally_position
	_assembly_required_count = maxi(
		1,
		int(ceil(float(required_units.size()) * ASSEMBLY_REQUIRED_PERCENT))
	)
	_debug_state_change(previous_mode, ArmyMode.ASSEMBLING)

	with_authorized_orders(func() -> void:
		command_hold_at_rally(required_units, rally_position, EnemyUnitMission.Mission.REGROUP)
	)

	return true


static func is_assembly_ready(tree: SceneTree, delta: float) -> bool:
	if get_army_mode() != ArmyMode.ASSEMBLING:
		return false

	_assembly_timer += delta
	var army: Array = collect_living_combat_units(tree)
	var assembled: Array = filter_units_near_rally(army, _assembly_rally, ASSEMBLY_RADIUS)
	var assembled_count: int = assembled.size()
	var required_count: int = _assembly_required_count

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null:
		var hero_near: bool = (
			horizontal_distance(hero.global_position, _assembly_rally) <= ASSEMBLY_RADIUS
		)
		if not hero_near:
			if _assembly_timer < ASSEMBLY_MAX_WAIT_SECONDS:
				debug_combat_log(
					"waiting for hero: %d/%d units assembled"
					% [assembled_count, army.size()]
				)
				return false

	if assembled_count >= required_count:
		return true

	if _assembly_timer >= ASSEMBLY_MAX_WAIT_SECONDS:
		var adjusted_required: int = maxi(1, required_count - 1)
		return assembled_count >= adjusted_required

	return false


static func finish_assembly(target_mode: ArmyMode) -> void:
	if get_army_mode() != ArmyMode.ASSEMBLING:
		return

	release_army_mode(ArmyMode.ASSEMBLING)
	try_claim_army_mode(target_mode)


static func is_regroup_ready(tree: SceneTree, match_elapsed_seconds: float) -> bool:
	if is_retreat_on_cooldown():
		return false

	var min_army: int = get_phase_min_army_size(match_elapsed_seconds)
	var rally: Vector3 = resolve_enemy_rally_position(tree)
	if rally == Vector3.ZERO:
		return false

	var non_hero: Array = collect_living_non_hero_combat_units(tree)
	if non_hero.size() < min_army:
		return false

	var regrouped: Array = filter_units_near_rally(non_hero, rally, ASSEMBLY_RADIUS)
	if float(regrouped.size()) / float(non_hero.size()) < ASSEMBLY_REQUIRED_PERCENT:
		return false

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and not is_hero_healthy_enough_for_wave(hero):
		return false

	if hero != null:
		var army_center: Vector3 = compute_army_center(regrouped)
		if (
			army_center != Vector3.ZERO
			and horizontal_distance(hero.global_position, army_center) > HERO_MAX_DISTANCE_FROM_ARMY
		):
			return false

	return true


static func build_coordinated_combat_group(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero: int,
	require_hero: bool = true
) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var regrouped_non_hero: Array = filter_units_near_rally(
		non_hero_units,
		rally_position,
		ASSEMBLY_RADIUS * 2.5
	)
	var can_launch: bool = regrouped_non_hero.size() >= min_non_hero
	var group_units: Array = regrouped_non_hero.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		var army_center: Vector3 = compute_army_center(regrouped_non_hero)
		var hero_ready: bool = (
			hero != null
			and regrouped_non_hero.size() >= ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS
			and army_center != Vector3.ZERO
			and is_living_combat_unit(hero)
		)
		if require_hero and hero == null:
			can_launch = false
		elif hero_ready:
			if (
				is_hero_healthy_enough_for_wave(hero)
				and horizontal_distance(hero.global_position, army_center)
				<= HERO_MAX_DISTANCE_FROM_ARMY
			):
				group_units.append(hero)
			elif require_hero:
				can_launch = false

	var hero_included: bool = false
	for unit: Variant in group_units:
		if unit is Hero:
			hero_included = true
			break

	return {
		"units": group_units,
		"can_launch": can_launch,
		"non_hero_count": regrouped_non_hero.size(),
		"total_non_hero_count": non_hero_units.size(),
		"hero_included": hero_included,
	}


static func evaluate_strength_gate(
	ai_strength: float,
	player_strength: float,
	attack_style: StringName = &"normal"
) -> Dictionary:
	if player_strength <= 0.0:
		return {"allowed": true, "reason": &"no_visible_threat"}

	var required_ratio: float = ATTACK_NORMAL_STRENGTH_RATIO
	if attack_style == &"aggressive":
		required_ratio = ATTACK_AGGRESSIVE_STRENGTH_RATIO
	elif attack_style == &"defend":
		required_ratio = DEFEND_FIGHT_STRENGTH_RATIO

	var ratio: float = ai_strength / player_strength
	return {
		"allowed": ratio >= required_ratio,
		"ratio": ratio,
		"required_ratio": required_ratio,
		"reason": &"strength_ok" if ratio >= required_ratio else &"outpowered",
	}


static func issue_group_combat_move(
	tree: SceneTree,
	units: Array,
	destination: Vector3,
	mission: EnemyUnitMission.Mission,
	mode: ArmyMode,
	allow_attack_override_creep: bool = false
) -> bool:
	units = NodeSafety.clean_node_array(units)
	if units.is_empty() or destination == Vector3.ZERO:
		return false

	if is_retreat_on_cooldown() and mission != EnemyUnitMission.Mission.DEFEND:
		_debug_combat("order blocked: retreat cooldown")
		return false

	if not try_claim_army_mode(mode, allow_attack_override_creep):
		return false

	begin_fight_tracking(units, compute_army_center(units))
	with_authorized_orders(func() -> void:
		command_attack_move(units, destination, mission)
	)

	return true


static func is_rebuilding_army() -> bool:
	return _is_rebuilding_army


static func is_finishing_mode_active() -> bool:
	return _finishing_mode_active


static func is_emergency_defense_active() -> bool:
	return _emergency_defense_active


static func get_emergency_defense_objective() -> Vector3:
	return _emergency_threat_position


static func activate_emergency_defense(threat: Dictionary) -> void:
	var reason: StringName = threat.get("reason", &"")
	var intercept_position: Vector3 = threat.get("intercept_position", Vector3.ZERO)

	if _emergency_defense_active:
		_emergency_reason = reason
		_emergency_threat_position = intercept_position
		return

	_emergency_defense_active = true
	_emergency_reason = reason
	_emergency_threat_position = intercept_position
	EnemyUnitMission.set_main_army_mission(
		EnemyUnitMission.Mission.DEFEND,
		"emergency defense"
	)
	print("[AI] EMERGENCY DEFENSE START threat=%s" % String(reason))


static func update_emergency_defense_threat(threat: Dictionary) -> void:
	if not _emergency_defense_active:
		return

	_emergency_reason = threat.get("reason", &"")
	_emergency_threat_position = threat.get("intercept_position", Vector3.ZERO)


static func deactivate_emergency_defense() -> void:
	if not _emergency_defense_active:
		return

	_emergency_defense_active = false
	_emergency_threat_position = Vector3.ZERO
	_emergency_reason = &""
	EnemyUnitMission.set_main_army_mission(
		EnemyUnitMission.Mission.REGROUP,
		"emergency ended"
	)
	print("[AI] EMERGENCY DEFENSE END")


static func update_finishing_mode(tree: SceneTree, delta: float) -> void:
	if _finishing_mode_exit_cooldown > 0.0:
		_finishing_mode_exit_cooldown = maxf(0.0, _finishing_mode_exit_cooldown - delta)

	_finishing_mode_eval_timer += delta
	if _finishing_mode_eval_timer < FINISHING_MODE_EVAL_INTERVAL:
		return

	_finishing_mode_eval_timer = 0.0

	if _finishing_mode_active:
		var exit_eval: Dictionary = _evaluate_finishing_exit(tree)
		if exit_eval.get("should_exit", false):
			_set_finishing_mode(false, String(exit_eval.get("reason", "unknown")))
		return

	if _finishing_mode_exit_cooldown > 0.0:
		return

	var enter_eval: Dictionary = _evaluate_finishing_activation(tree)
	if enter_eval.get("should_enter", false):
		_set_finishing_mode(true, String(enter_eval.get("reason", "unknown")))


static func set_rebuilding_army(rebuilding: bool) -> void:
	_is_rebuilding_army = rebuilding


static func get_active_wave_start_unit_count() -> int:
	return _active_wave_start_unit_count


static func begin_offensive_wave(wave_units: Array) -> void:
	wave_units = NodeSafety.clean_node_array(wave_units)
	_active_wave_start_unit_count = wave_units.size()
	_objective_reissue_timer = 0.0
	_objective_stuck_timer = 0.0
	_objective_last_building_health = -1


static func set_attack_objective(objective: Node3D, position: Vector3) -> void:
	_active_wave_objective = NodeSafety.safe_node(objective) as Node3D
	_active_wave_objective_position = position
	_objective_reissue_timer = 0.0
	_objective_stuck_timer = 0.0
	_objective_last_building_health = -1


static func get_attack_objective_position() -> Vector3:
	return _active_wave_objective_position


static func prepare_defense_recall(tree: SceneTree) -> void:
	cancel_offensive_orders(tree)
	clear_offensive_wave_tracking()


static func should_recall_offensive_for_defense(tree: SceneTree) -> bool:
	if get_army_mode() != ArmyMode.ATTACKING:
		return false

	var emergency_threat: Dictionary = evaluate_emergency_defense_threat(tree)
	if emergency_threat.get("threatened", false):
		var emergency_reason: StringName = emergency_threat.get("reason", &"")
		if emergency_reason == &"town_center":
			return true

		if _finishing_mode_active and should_allow_finishing_during_emergency(
			tree,
			emergency_threat
		):
			return false

		return (
			emergency_threat.get("force_recall", false)
			or is_emergency_threat_serious(tree, emergency_threat)
		)

	var threat: Dictionary = evaluate_defense_threat(tree)
	if not threat.get("threatened", false):
		return false

	if threat.get("force_commit", false):
		return true

	if _finishing_mode_active:
		var reason: StringName = threat.get("reason", &"")
		return reason == &"base"

	var reason: StringName = threat.get("reason", &"")
	if reason == &"base" or reason == &"buildings" or reason == &"workers":
		return true

	return not _is_attack_close_to_winning(tree)


static func _is_attack_close_to_winning(tree: SceneTree) -> bool:
	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center == null:
		return true

	if get_health_ratio(command_center) > ATTACK_CLOSE_TO_WIN_CC_HEALTH_RATIO:
		return false

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		wave_units = collect_living_combat_units(tree)

	var army_center: Vector3 = compute_army_center(wave_units)
	if army_center == Vector3.ZERO:
		return false

	return (
		horizontal_distance(army_center, command_center.global_position)
		<= ATTACK_CLOSE_TO_WIN_ARMY_DISTANCE
	)


static func maintain_attack_wave_objective(tree: SceneTree, delta: float) -> void:
	if get_army_mode() != ArmyMode.ATTACKING:
		return

	var reissue_interval: float = (
		FINISHING_MODE_OBJECTIVE_REISSUE_SECONDS
		if _finishing_mode_active
		else ATTACK_OBJECTIVE_REISSUE_SECONDS
	)

	var fallback_position: Vector3 = _active_wave_objective_position
	if fallback_position == Vector3.ZERO:
		fallback_position = resolve_enemy_rally_position(tree)

	var previous_objective: Node3D = _active_wave_objective
	var previous_objective_alive: bool = NodeSafety.is_alive_node(previous_objective)
	if previous_objective_alive and previous_objective is Building:
		previous_objective_alive = _is_living_building(previous_objective as Building)

	var objective: Dictionary = resolve_attack_objective(tree, fallback_position)
	var objective_node: Node3D = objective.get("node") as Node3D
	var objective_position: Vector3 = objective.get("position", Vector3.ZERO)
	if objective_position == Vector3.ZERO:
		return

	var objective_died: bool = previous_objective != null and not previous_objective_alive
	var objective_changed: bool = (
		NodeSafety.is_alive_node(objective_node) and objective_node != previous_objective
	)

	if NodeSafety.is_alive_node(objective_node):
		_active_wave_objective = objective_node
	_active_wave_objective_position = objective_position

	if _finishing_mode_active and NodeSafety.is_alive_node(objective_node):
		if objective_died or objective_changed:
			_log_finishing_objective(objective_node)

	_update_objective_stuck_detection(tree, objective_node, delta)

	_objective_reissue_timer += delta
	var should_reissue: bool = (
		_objective_reissue_timer >= reissue_interval
		or objective_died
		or objective_changed
	)
	var should_unstick: bool = _objective_stuck_timer >= ATTACK_OBJECTIVE_STUCK_SECONDS
	if not should_reissue and not should_unstick:
		return

	_objective_reissue_timer = 0.0

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		wave_units = collect_living_combat_units(tree)
	if wave_units.is_empty():
		return

	if should_unstick and NodeSafety.is_alive_node(objective_node):
		_objective_stuck_timer = 0.0
		_command_assault_objective(wave_units, objective_node, true)
		return

	if NodeSafety.is_alive_node(objective_node):
		_command_focus_attack_objective(
			wave_units,
			objective_node,
			EnemyUnitMission.Mission.ATTACK
		)
		return

	command_attack_move(
		wave_units,
		objective_position,
		EnemyUnitMission.Mission.ATTACK
	)


static func _update_objective_stuck_detection(
	tree: SceneTree,
	objective_node: Node3D,
	delta: float
) -> void:
	if not NodeSafety.is_alive_node(objective_node) or not objective_node is Building:
		_objective_stuck_timer = 0.0
		_objective_last_building_health = -1
		return

	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		wave_units = collect_living_combat_units(tree)

	var army_center: Vector3 = compute_army_center(wave_units)
	if (
		army_center == Vector3.ZERO
		or horizontal_distance(army_center, objective_node.global_position)
		> ATTACK_OBJECTIVE_NEAR_DISTANCE
	):
		_objective_stuck_timer = 0.0
		return

	var building: Building = objective_node as Building
	var current_health: int = CombatTargetValidation.get_target_current_health(building)
	if _objective_last_building_health >= 0 and current_health < _objective_last_building_health:
		_objective_stuck_timer = 0.0
	else:
		_objective_stuck_timer += delta

	_objective_last_building_health = current_health


static func _command_focus_attack_objective(
	units: Array,
	objective: Node3D,
	mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.ATTACK
) -> void:
	if not NodeSafety.is_alive_node(objective):
		return

	units = NodeSafety.clean_node_array(units)
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not _should_focus_unit_on_objective(unit as Node3D, objective):
			continue

		_command_unit_focus_attack(unit, objective)
		EnemyUnitMission.try_set_mission(unit as Node, mission)
		EnemyUnitMission.record_move_order(
			unit as Node,
			objective.global_position,
			mission
		)


static func _command_assault_objective(
	units: Array,
	objective: Node3D,
	use_spread: bool = false
) -> void:
	if not NodeSafety.is_alive_node(objective):
		return

	units = NodeSafety.clean_node_array(units)
	if use_spread and not units.is_empty():
		var spread_targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
			objective.global_position,
			units.size(),
			FORMATION_SPACING * ATTACK_OBJECTIVE_SPREAD_MULTIPLIER
		)
		for index: int in units.size():
			var unit: Variant = units[index]
			if not NodeSafety.is_alive_node(unit):
				continue

			if not EnemyUnitMission.should_reissue_move_order(
				unit as Node,
				spread_targets[index],
				EnemyUnitMission.Mission.ATTACK
			):
				continue

			_issue_attack_move(unit, spread_targets[index])
			EnemyUnitMission.try_set_mission(unit as Node, EnemyUnitMission.Mission.ATTACK)
			EnemyUnitMission.record_move_order(
				unit as Node,
				spread_targets[index],
				EnemyUnitMission.Mission.ATTACK
			)

	_command_focus_attack_objective(units, objective, EnemyUnitMission.Mission.ATTACK)


static func _command_unit_focus_attack(unit: Variant, objective: Node3D) -> void:
	if not NodeSafety.is_alive_node(unit) or not NodeSafety.is_alive_node(objective):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if not EnemyUnitMission.allows_combat_micro(unit as Node):
		return

	if objective is Building and not _is_living_building(objective as Building):
		return

	if (unit as Object).has_method("command_attack"):
		(unit as Object).call("command_attack", objective)


static func _should_focus_unit_on_objective(unit: Node3D, objective: Node3D) -> bool:
	if not NodeSafety.is_alive_node(unit) or not NodeSafety.is_alive_node(objective):
		return false

	if not is_living_combat_unit(unit):
		return false

	if not EnemyUnitMission.allows_combat_micro(unit):
		return false

	if objective is Building and not _is_living_building(objective as Building):
		return false

	return true


static func clear_offensive_wave_tracking() -> void:
	_active_wave_start_unit_count = 0
	_reset_objective_tracking()


static func _reset_objective_tracking() -> void:
	_active_wave_objective = null
	_active_wave_objective_position = Vector3.ZERO
	_objective_reissue_timer = 0.0
	_objective_stuck_timer = 0.0
	_objective_last_building_health = -1


## Returns true when the requested mode owns the army for issuing orders.
## Pass allow_attack_override_creep when a ready wave should take over from creeping.
static func try_claim_army_mode(
	requested_mode: ArmyMode,
	allow_attack_override_creep: bool = false
) -> bool:
	if requested_mode == _army_mode:
		return true

	if not _can_transition_army_mode(requested_mode):
		return false

	var previous_mode: ArmyMode = _army_mode

	match _army_mode:
		ArmyMode.IDLE, ArmyMode.OPENING:
			_set_army_mode(requested_mode, previous_mode)
			return true
		ArmyMode.ASSEMBLING:
			if requested_mode in [
				ArmyMode.RETREATING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return requested_mode == ArmyMode.ASSEMBLING
		ArmyMode.CREEPING:
			if requested_mode == ArmyMode.ATTACKING and allow_attack_override_creep:
				_set_army_mode(requested_mode, previous_mode)
				return true
			if requested_mode in [
				ArmyMode.REGROUPING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.RETREATING,
				ArmyMode.ASSEMBLING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.ATTACKING:
			if requested_mode in [
				ArmyMode.REGROUPING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.RETREATING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.INTERCEPTING:
			if requested_mode == ArmyMode.INTERCEPTING:
				return true
			if requested_mode in [
				ArmyMode.DEFENDING,
				ArmyMode.RETREATING,
				ArmyMode.REGROUPING,
				ArmyMode.ASSEMBLING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.RETREATING:
			if requested_mode in [ArmyMode.REGROUPING, ArmyMode.IDLE, ArmyMode.OPENING]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return requested_mode == ArmyMode.RETREATING
		ArmyMode.REGROUPING:
			if requested_mode in [
				ArmyMode.CREEPING,
				ArmyMode.ATTACKING,
				ArmyMode.IDLE,
				ArmyMode.OPENING,
				ArmyMode.DEFENDING,
				ArmyMode.INTERCEPTING,
				ArmyMode.ASSEMBLING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false
		ArmyMode.DEFENDING:
			if requested_mode == ArmyMode.DEFENDING:
				return true
			if requested_mode in [
				ArmyMode.RETREATING,
				ArmyMode.REGROUPING,
				ArmyMode.INTERCEPTING,
			]:
				_set_army_mode(requested_mode, previous_mode)
				return true
			return false

	return false


static func _can_transition_army_mode(requested_mode: ArmyMode) -> bool:
	if requested_mode in [ArmyMode.RETREATING, ArmyMode.DEFENDING, ArmyMode.INTERCEPTING]:
		return true

	var elapsed_seconds: float = float(
		Time.get_ticks_msec() - _mode_claim_msec
	) / 1000.0
	return elapsed_seconds >= MIN_STATE_DURATION_SECONDS


static func _set_army_mode(requested_mode: ArmyMode, previous_mode: ArmyMode) -> void:
	_army_mode = requested_mode
	_mode_claim_msec = Time.get_ticks_msec()
	_debug_state_change(previous_mode, requested_mode)


static func release_army_mode(mode: ArmyMode) -> bool:
	if _army_mode != mode:
		return false

	var previous_mode: ArmyMode = _army_mode
	_army_mode = ArmyMode.IDLE
	_mode_claim_msec = Time.get_ticks_msec()
	_debug_state_change(previous_mode, ArmyMode.IDLE)
	return true


static func should_abort_offensive_push(tree: SceneTree) -> bool:
	if should_retreat_from_fight(tree):
		return true

	if _finishing_mode_active:
		var living_wave_units: Array = _collect_living_offensive_wave_units(tree)
		var living_count: int = living_wave_units.size()
		if _active_wave_start_unit_count > 0:
			var retreat_threshold: int = maxi(
				FINISHING_MODE_MIN_PUSH_UNITS,
				int(float(_active_wave_start_unit_count) * FINISHING_MODE_ARMY_DESTROYED_RATIO)
			)
			if living_count < retreat_threshold:
				return true
		elif living_count < FINISHING_MODE_MIN_PUSH_UNITS:
			return true
		return false

	var hero: Hero = find_living_enemy_hero(tree)
	if hero != null and get_health_ratio(hero) < HERO_RETREAT_HP_RATIO:
		return true

	var living_wave_units: Array = _collect_living_offensive_wave_units(tree)
	var living_count: int = living_wave_units.size()
	if _active_wave_start_unit_count > 0:
		var retreat_threshold: int = maxi(
			MIN_ARMY_UNITS_TO_CONTINUE_ATTACK,
			int(float(_active_wave_start_unit_count) * WAVE_REBUILD_ARMY_RATIO)
		)
		if living_count < retreat_threshold:
			return true
	else:
		if living_count < MIN_ARMY_UNITS_TO_CONTINUE_ATTACK:
			return true

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	if non_hero_units.size() < MIN_NON_HERO_FOR_HERO_JOIN:
		return true

	return estimate_military_power(non_hero_units) < MIN_ATTACK_ARMY_POWER


static func _collect_living_offensive_wave_units(tree: SceneTree) -> Array:
	var units: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if mission != EnemyUnitMission.Mission.ATTACK:
			continue

		units.append(unit)

	return units


static func abort_offensive_and_regroup(tree: SceneTree) -> bool:
	if get_army_mode() != ArmyMode.ATTACKING and get_army_mode() != ArmyMode.CREEPING:
		return false

	if initiate_group_retreat(tree, "offensive abort"):
		clear_offensive_wave_tracking()
		set_rebuilding_army(true)
		return true

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		release_army_mode(ArmyMode.ATTACKING)
		cancel_offensive_orders(tree)
		clear_offensive_wave_tracking()
		set_rebuilding_army(true)
		return true

	cancel_offensive_orders(tree)
	if try_claim_army_mode(ArmyMode.REGROUPING):
		command_regroup_at_rally(tree, rally_position)
		clear_offensive_wave_tracking()
		set_rebuilding_army(true)
		return true

	release_army_mode(ArmyMode.ATTACKING)
	clear_offensive_wave_tracking()
	set_rebuilding_army(true)
	return true


static func cancel_offensive_orders(tree: SceneTree) -> void:
	for unit: Variant in collect_living_combat_units(tree):
		_cancel_unit_offensive_orders(unit)


static func pull_straggler_units_to_rally(
	tree: SceneTree,
	rally_position: Vector3,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> void:
	if rally_position == Vector3.ZERO:
		return

	var stragglers: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		if horizontal_distance((unit as Node3D).global_position, rally_position) > max_distance:
			stragglers.append(unit)

	if stragglers.is_empty():
		return

	command_hold_at_rally(stragglers, rally_position, EnemyUnitMission.Mission.REGROUP)


static func is_hero_isolated_near_player_threat(tree: SceneTree, hero: Hero) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	if non_hero_units.size() >= MIN_NON_HERO_FOR_HERO_JOIN:
		var army_center: Vector3 = compute_army_center(non_hero_units)
		if (
			army_center != Vector3.ZERO
			and horizontal_distance(hero.global_position, army_center)
			<= HERO_MAX_DISTANCE_FROM_ARMY
		):
			return false

	if (
		collect_player_military_near(
			tree,
			hero.global_position,
			HERO_ALONE_PLAYER_THREAT_RANGE
		).is_empty()
	):
		return false

	return true


static func get_effective_attack_min_non_hero_units(match_elapsed_seconds: float) -> int:
	return get_phase_min_army_size(match_elapsed_seconds)


static func can_commit_attack_wave(
	tree: SceneTree,
	wave_units: Array,
	rally_position: Vector3,
	min_non_hero_units: int,
	match_elapsed_seconds: float = 0.0
) -> Dictionary:
	return evaluate_attack_gate(
		tree,
		rally_position,
		wave_units,
		min_non_hero_units,
		match_elapsed_seconds
	)


static func evaluate_attack_gate(
	tree: SceneTree,
	rally_position: Vector3,
	wave_units: Array = [],
	min_non_hero_units: int = WAVE_1_MIN_NON_HERO_UNITS,
	match_elapsed_seconds: float = 0.0
) -> Dictionary:
	var is_wave_commit: bool = not wave_units.is_empty()
	var effective_min_non_hero: int = get_effective_attack_min_non_hero_units(
		match_elapsed_seconds
	)
	var required_non_hero: int = mini(min_non_hero_units, effective_min_non_hero)

	if rally_position == Vector3.ZERO:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"no_rally"},
			{},
			match_elapsed_seconds
		)

	var hero: Hero = find_living_enemy_hero(tree)
	var hero_alive: bool = hero != null
	var rebuilding: bool = _is_rebuilding_army
	var regrouping: bool = get_army_mode() == ArmyMode.REGROUPING

	var evaluated_units: Array = (
		NodeSafety.clean_node_array(wave_units)
		if is_wave_commit
		else collect_living_combat_units(tree)
	)
	var composition: Dictionary = _count_wave_composition(evaluated_units)
	var non_hero_count: int = int(composition.get("non_hero_count", 0))
	var melee_count: int = int(composition.get("melee_count", 0))
	var ranged_count: int = int(composition.get("ranged_count", 0))
	var total_combat_count: int = int(composition.get("total_count", 0))
	var large_army_ready: bool = non_hero_count >= MIN_TOTAL_COMBAT_UNITS_FOR_ATTACK
	var grouped_required: int = mini(non_hero_count, required_non_hero)
	var army_grouped: bool = is_army_grouped_at_position(
		evaluated_units,
		rally_position,
		ARMY_GROUP_MAX_RADIUS,
		grouped_required
	)
	var debug_context: Dictionary = {
		"hero_alive": hero_alive,
		"combat_count": total_combat_count,
		"non_hero_count": non_hero_count,
		"melee_count": melee_count,
		"ranged_count": ranged_count,
		"army_grouped": army_grouped,
		"rebuilding": rebuilding,
		"regrouping": regrouping,
		"required_non_hero": required_non_hero,
		"elapsed_seconds": match_elapsed_seconds,
	}

	if _finishing_mode_active:
		if total_combat_count >= FINISHING_MODE_MIN_PUSH_UNITS:
			return _finalize_attack_gate(
				{
					"can_commit": true,
					"reason": &"finishing_mode",
					"total_combat_count": total_combat_count,
				},
				debug_context,
				match_elapsed_seconds
			)
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"finishing_too_weak"},
			debug_context,
			match_elapsed_seconds
		)

	if non_hero_count < ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"suicide_attack"},
			debug_context,
			match_elapsed_seconds
		)

	var bypass_rebuilding: bool = (
		match_elapsed_seconds >= ATTACK_TIMER_DESPERATE_SECONDS
		and non_hero_count >= ATTACK_DESPERATE_MIN_NON_HERO_UNITS
	) or large_army_ready
	if rebuilding and not bypass_rebuilding:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"rebuilding"},
			debug_context,
			match_elapsed_seconds
		)

	if regrouping and not is_wave_commit:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"regrouping"},
			debug_context,
			match_elapsed_seconds
		)

	if non_hero_count <= 0:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"hero_only"},
			debug_context,
			match_elapsed_seconds
		)

	if non_hero_count < required_non_hero:
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"army_too_small",
				"required_non_hero": required_non_hero,
			},
			debug_context,
			match_elapsed_seconds
		)

	var wave_power: int = estimate_military_power(evaluated_units)
	var wave_strength: float = estimate_combat_strength(evaluated_units)
	var known_player_power: int = estimate_known_player_army_strength(tree, rally_position)
	var known_player_strength: float = get_effective_player_strength_at(
		tree,
		rally_position,
		KNOWN_PLAYER_SCOUT_RANGE
	)
	debug_context["player_strength"] = known_player_power
	debug_context["wave_power"] = wave_power
	debug_context["wave_strength"] = wave_strength
	debug_context["player_combat_strength"] = known_player_strength

	var required_power: int = (
		int(float(known_player_power) * PLAYER_ARMY_STRENGTH_RATIO)
		if known_player_power > 0
		else 0
	)
	var unknown_player_timeout: bool = (
		known_player_power <= 0
		and match_elapsed_seconds >= ATTACK_TIMER_STANDARD_SECONDS
	)
	var composition_relaxed: bool = (
		unknown_player_timeout
		or match_elapsed_seconds >= ATTACK_TIMER_DESPERATE_SECONDS
		or non_hero_count >= ATTACK_STANDARD_MIN_NON_HERO_UNITS
	)
	var count_ready: bool = total_combat_count >= MIN_TOTAL_COMBAT_UNITS_FOR_ATTACK
	var power_ready: bool = known_player_power > 0 and wave_power >= required_power

	if not composition_relaxed and not count_ready and not power_ready:
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"army_not_ready",
				"wave_power": wave_power,
				"known_player_power": known_player_power,
				"total_combat_count": total_combat_count,
			},
			debug_context,
			match_elapsed_seconds
		)

	if known_player_power > 0 and wave_power < required_power and not large_army_ready:
		_debug_combat("attack cancelled: human strength too high")
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"outpowered",
				"wave_power": wave_power,
				"known_player_power": known_player_power,
			},
			debug_context,
			match_elapsed_seconds
		)

	if known_player_strength > 0.0:
		var strength_gate: Dictionary = evaluate_strength_gate(
			wave_strength,
			known_player_strength,
			&"normal"
		)
		if not strength_gate.get("allowed", false) and not large_army_ready:
			_debug_combat(
				"attack cancelled: strength ratio %.2f < %.2f"
				% [
					float(strength_gate.get("ratio", 0.0)),
					float(strength_gate.get("required_ratio", ATTACK_NORMAL_STRENGTH_RATIO)),
				]
			)
			return _finalize_attack_gate(
				{
					"can_commit": false,
					"reason": &"strength_ratio",
					"wave_strength": wave_strength,
					"player_strength": known_player_strength,
				},
				debug_context,
				match_elapsed_seconds
			)

	if not composition_relaxed:
		if melee_count < MIN_MELEE_UNITS_FOR_ATTACK:
			return _finalize_attack_gate(
				{
					"can_commit": false,
					"reason": &"not_enough_melee",
					"melee_count": melee_count,
				},
				debug_context,
				match_elapsed_seconds
			)

		if _enemy_has_archer_capability(tree) and ranged_count < MIN_RANGED_UNITS_FOR_ATTACK:
			return _finalize_attack_gate(
				{
					"can_commit": false,
					"reason": &"not_enough_ranged",
					"ranged_count": ranged_count,
				},
				debug_context,
				match_elapsed_seconds
			)

	if not army_grouped and not large_army_ready:
		return _finalize_attack_gate(
			{"can_commit": false, "reason": &"not_grouped"},
			debug_context,
			match_elapsed_seconds
		)

	if not composition_relaxed and wave_power < MIN_ATTACK_ARMY_POWER and not power_ready:
		return _finalize_attack_gate(
			{
				"can_commit": false,
				"reason": &"army_power_too_low",
				"wave_power": wave_power,
			},
			debug_context,
			match_elapsed_seconds
		)

	return _finalize_attack_gate(
		{
			"can_commit": true,
			"reason": &"ready",
			"wave_power": wave_power,
			"known_player_power": known_player_power,
			"total_combat_count": total_combat_count,
		},
		debug_context,
		match_elapsed_seconds
	)


static func _finalize_attack_gate(
	result: Dictionary,
	debug_context: Dictionary,
	match_elapsed_seconds: float
) -> Dictionary:
	if DEBUG_ATTACK_GATE:
		var can_commit: bool = result.get("can_commit", false)
		var action: String = "ATTACK" if can_commit else "WAIT"
		var player_strength_value: Variant = debug_context.get("player_strength", "unknown")
		var player_strength_text: String = (
			"unknown"
			if int(player_strength_value) <= 0
			else str(player_strength_value)
		)
		print(
			(
				"EnemyAttackGate [%s]: reason=%s hero_alive=%s combat=%d non_hero=%d "
				+ "melee=%d ranged=%d grouped=%s player_strength=%s "
				+ "rebuilding=%s regrouping=%s elapsed=%.0fs required_non_hero=%d"
			)
			% [
				action,
				String(result.get("reason", &"unknown")),
				str(debug_context.get("hero_alive", false)),
				int(debug_context.get("combat_count", 0)),
				int(debug_context.get("non_hero_count", 0)),
				int(debug_context.get("melee_count", 0)),
				int(debug_context.get("ranged_count", 0)),
				str(debug_context.get("army_grouped", false)),
				player_strength_text,
				str(debug_context.get("rebuilding", false)),
				str(debug_context.get("regrouping", false)),
				match_elapsed_seconds,
				int(debug_context.get("required_non_hero", 0)),
			]
		)

	return result


static func estimate_known_player_army_strength(tree: SceneTree, rally_position: Vector3) -> int:
	var attack_destination: Vector3 = resolve_wave_attack_destination(tree, rally_position)
	var rally_visible: Array = collect_player_military_near(
		tree,
		rally_position,
		KNOWN_PLAYER_SCOUT_RANGE
	)
	var path_visible: Array = collect_player_military_near(
		tree,
		attack_destination,
		APPROACH_DETECTION_RANGE
	)
	var combined: Array = rally_visible.duplicate()
	for unit: Variant in path_visible:
		if not NodeSafety.is_alive_node(unit):
			continue

		if combined.has(unit):
			continue

		combined.append(unit)

	return estimate_military_power(combined)


static func is_army_grouped_at_position(
	units: Array,
	anchor_position: Vector3,
	max_radius: float = ARMY_GROUP_MAX_RADIUS,
	required_grouped: int = -1
) -> bool:
	units = NodeSafety.clean_node_array(units)
	var grouped_units: Array = filter_units_near_rally(units, anchor_position, max_radius)
	var non_hero_grouped: int = 0
	for unit: Variant in grouped_units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_non_hero_combat_unit(unit as Node):
			non_hero_grouped += 1

	var non_hero_total: int = 0
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_non_hero_combat_unit(unit as Node):
			non_hero_total += 1

	if non_hero_total <= 0:
		return false

	var required: int = (
		required_grouped
		if required_grouped > 0
		else mini(non_hero_total, MIN_NON_HERO_FOR_HERO_JOIN)
	)
	return non_hero_grouped >= required


static func _count_wave_composition(units: Array) -> Dictionary:
	var non_hero_count: int = 0
	var melee_count: int = 0
	var ranged_count: int = 0
	var total_count: int = 0
	var hero_in_wave: Hero = null

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		total_count += 1
		if unit is Hero:
			hero_in_wave = unit as Hero
			continue

		if not is_non_hero_combat_unit(unit as Node):
			continue

		non_hero_count += 1
		if unit is Archer or unit is CavalryArcher or unit is Cannon:
			ranged_count += 1
		else:
			melee_count += 1

	return {
		"non_hero_count": non_hero_count,
		"melee_count": melee_count,
		"ranged_count": ranged_count,
		"total_count": total_count,
		"hero": hero_in_wave,
	}


static func _enemy_has_archer_capability(tree: SceneTree) -> bool:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node) and (node is Archer or node is CavalryArcher or node is Cannon):
			return true

	return false


static func is_combat_unit(node: Node) -> bool:
	return node is Spearman or node is Swordsman or node is Archer or node is HeavyCavalry or node is LightCavalry or node is CavalryArcher or node is Cannon or node is Hero


static func is_hero_unit(node: Node) -> bool:
	return node is Hero


static func is_non_hero_combat_unit(node: Node) -> bool:
	return is_combat_unit(node) and not is_hero_unit(node)


static func is_living_combat_unit(node: Node) -> bool:
	if not NodeSafety.is_alive_node(node):
		return false

	if not is_combat_unit(node):
		return false

	if not node.is_in_group(ENEMY_COMBAT_GROUP):
		return false

	return _has_positive_health(node)


static func register_combat_unit(unit: Unit) -> void:
	if unit == null or not is_combat_unit(unit):
		return

	if not unit.is_in_group(ENEMIES_GROUP):
		unit.add_to_group(ENEMIES_GROUP)

	if not unit.is_in_group(ENEMY_COMBAT_GROUP):
		unit.add_to_group(ENEMY_COMBAT_GROUP)


static func collect_living_combat_units(tree: SceneTree) -> Array:
	var units: Array = []

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node):
			units.append(node)

	return units


static func collect_living_non_hero_combat_units(tree: SceneTree) -> Array:
	var units: Array = []

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node) and is_non_hero_combat_unit(node):
			units.append(node)

	return units


static func find_living_enemy_hero(tree: SceneTree) -> Hero:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if is_living_combat_unit(node) and is_hero_unit(node):
			return node as Hero

	return null


static func get_min_non_hero_units_for_wave(wave_number: int) -> int:
	if wave_number <= 1:
		return WAVE_1_MIN_NON_HERO_UNITS
	if wave_number == 2:
		return WAVE_2_MIN_NON_HERO_UNITS
	if wave_number == 3:
		return WAVE_3_MIN_NON_HERO_UNITS

	return WAVE_4_MIN_NON_HERO_UNITS


static func filter_units_near_rally(
	units: Array,
	rally_position: Vector3,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> Array:
	units = NodeSafety.clean_node_array(units)
	var nearby_units: Array = []

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not unit is Node3D:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		if horizontal_distance((unit as Node3D).global_position, rally_position) <= max_distance:
			nearby_units.append(unit)

	return nearby_units


static func is_army_regrouped_at_rally(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero_units: int,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> bool:
	if rally_position == Vector3.ZERO:
		return false

	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	return (
		filter_units_near_rally(non_hero_units, rally_position, max_distance).size()
		>= min_non_hero_units
	)


static func command_regroup_at_rally(tree: SceneTree, rally_position: Vector3) -> void:
	if rally_position == Vector3.ZERO:
		return

	cancel_offensive_orders(tree)
	var units: Array = collect_living_combat_units(tree)
	command_hold_at_rally(units, rally_position, EnemyUnitMission.Mission.REGROUP)


static func assign_reinforcement_regroup(tree: SceneTree, unit: Unit) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if _emergency_defense_active:
		_assign_reinforcement_to_emergency_defense(tree, unit)
		return

	if _finishing_mode_active:
		_assign_reinforcement_to_finishing_attack(tree, unit)
		return

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.REGROUP):
		return

	command_hold_at_rally([unit], rally_position, EnemyUnitMission.Mission.REGROUP)


static func _count_pending_reinforcement_units(tree: SceneTree) -> int:
	var count: int = 0
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if mission == EnemyUnitMission.Mission.REGROUP:
			count += 1

	return count


static func pull_reinforcement_units_to_rally(
	tree: SceneTree,
	rally_position: Vector3,
	max_distance: float = WAVE_REGROUP_MAX_DISTANCE
) -> void:
	if rally_position == Vector3.ZERO:
		return

	var reinforcements: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if mission != EnemyUnitMission.Mission.REGROUP and mission != EnemyUnitMission.Mission.IDLE:
			continue

		if horizontal_distance((unit as Node3D).global_position, rally_position) > max_distance:
			reinforcements.append(unit)

	if reinforcements.is_empty():
		return

	command_hold_at_rally(reinforcements, rally_position, EnemyUnitMission.Mission.REGROUP)


static func pull_finishing_reinforcements_to_attack(tree: SceneTree) -> void:
	if not _finishing_mode_active:
		return

	var objective_position: Vector3 = get_attack_objective_position()
	if objective_position == Vector3.ZERO:
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		var objective: Dictionary = resolve_attack_objective(tree, rally_position)
		objective_position = objective.get("position", Vector3.ZERO)
		var objective_node: Node3D = objective.get("node") as Node3D
		if NodeSafety.is_alive_node(objective_node):
			set_attack_objective(objective_node, objective_position)

	if objective_position == Vector3.ZERO:
		return

	var reinforcements: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if mission == EnemyUnitMission.Mission.ATTACK:
			continue

		if mission != EnemyUnitMission.Mission.REGROUP and mission != EnemyUnitMission.Mission.IDLE:
			continue

		reinforcements.append(unit)

	if reinforcements.is_empty():
		return

	var objective_node: Node3D = NodeSafety.safe_node(_active_wave_objective) as Node3D
	if NodeSafety.is_alive_node(objective_node):
		_command_focus_attack_objective(
			reinforcements,
			objective_node,
			EnemyUnitMission.Mission.ATTACK
		)
	else:
		command_attack_move(
			reinforcements,
			objective_position,
			EnemyUnitMission.Mission.ATTACK
		)


static func build_regrouped_attack_wave_units(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero_units: int
) -> Dictionary:
	return build_coordinated_combat_group(tree, rally_position, min_non_hero_units, true)


static func should_rebuild_army_after_wave(
	current_non_hero_count: int,
	last_wave_non_hero_count: int
) -> bool:
	if last_wave_non_hero_count <= 0:
		return false

	return (
		current_non_hero_count
		< int(float(last_wave_non_hero_count) * WAVE_REBUILD_ARMY_RATIO)
	)


static func build_attack_wave_units(tree: SceneTree, min_non_hero_units: int) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var can_launch: bool = non_hero_units.size() >= min_non_hero_units
	var wave_units: Array = non_hero_units.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		var army_center: Vector3 = compute_army_center(non_hero_units)
		if (
			hero != null
			and non_hero_units.size() >= ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS
			and army_center != Vector3.ZERO
			and is_hero_healthy_enough_for_wave(hero)
			and horizontal_distance(hero.global_position, army_center)
			<= HERO_MAX_DISTANCE_FROM_ARMY
		):
			wave_units.append(hero)

	return {
		"units": wave_units,
		"can_launch": can_launch,
		"non_hero_count": non_hero_units.size(),
	}


static func build_creep_army(tree: SceneTree, match_elapsed_seconds: float = 0.0) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var min_non_hero: int = get_phase_min_army_size(match_elapsed_seconds)
	return build_coordinated_combat_group(tree, rally_position, min_non_hero, true)


static func is_enemy_base_threatened(tree: SceneTree) -> bool:
	return evaluate_defense_threat(tree).get("threatened", false)


static func evaluate_defense_threat(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return {"threatened": false}

	var worker_threat: Dictionary = _evaluate_worker_defense_threat(tree)
	if worker_threat.get("threatened", false):
		return worker_threat

	var building_threat: Dictionary = _evaluate_building_defense_threat(tree)
	if building_threat.get("threatened", false):
		return building_threat

	var base_threat: Node3D = _find_player_military_near_position(
		tree,
		rally_position,
		BASE_THREAT_DETECTION_RANGE
	)
	if base_threat != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, base_threat.global_position),
			&"base",
			true
		)

	var economy_threat: Node3D = _find_player_military_in_enemy_economy_area(tree)
	if economy_threat != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, economy_threat.global_position),
			&"economy"
		)

	var approach_threat: Node3D = _find_player_military_near_position(
		tree,
		rally_position,
		APPROACH_DETECTION_RANGE
	)
	if approach_threat != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, approach_threat.global_position),
			&"approach"
		)

	return {"threatened": false}


static func evaluate_emergency_defense_threat(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return {"threatened": false}

	var command_center_threat: Dictionary = _evaluate_emergency_command_center_threat(tree)
	if command_center_threat.get("threatened", false):
		return command_center_threat

	var production_threat: Dictionary = _evaluate_emergency_production_building_threat(tree)
	if production_threat.get("threatened", false):
		return production_threat

	var hero_threat: Dictionary = _evaluate_emergency_player_hero_threat(tree, rally_position)
	if hero_threat.get("threatened", false):
		return hero_threat

	var core_base_threat: Dictionary = _evaluate_emergency_core_base_threat(tree, rally_position)
	if core_base_threat.get("threatened", false):
		return core_base_threat

	var worker_threat: Dictionary = _evaluate_emergency_worker_attack_threat(tree)
	if worker_threat.get("threatened", false):
		return worker_threat

	return {"threatened": false}


static func has_meaningful_core_base_threat(tree: SceneTree) -> bool:
	var threat: Dictionary = evaluate_emergency_defense_threat(tree)
	if not threat.get("threatened", false):
		return false

	var reason: StringName = threat.get("reason", &"")
	return reason != &"worker_attack"


static func is_emergency_threat_serious(tree: SceneTree, threat: Dictionary) -> bool:
	if not threat.get("threatened", false):
		return false

	var reason: StringName = threat.get("reason", &"")
	if reason == &"town_center" or reason == &"production" or reason == &"player_hero":
		return true

	var intercept_position: Vector3 = threat.get("intercept_position", Vector3.ZERO)
	if intercept_position == Vector3.ZERO:
		return false

	var threat_power: int = estimate_player_threat_power_near(
		tree,
		intercept_position,
		DEFENSE_THREAT_POWER_RANGE
	)
	if threat_power >= EMERGENCY_SERIOUS_THREAT_POWER:
		return true

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	return (
		collect_player_military_near(tree, rally_position, CORE_BASE_DEFENSE_RADIUS).size()
		>= 3
	)


static func should_allow_finishing_during_emergency(
	tree: SceneTree,
	threat: Dictionary
) -> bool:
	if not _finishing_mode_active:
		return false

	var reason: StringName = threat.get("reason", &"")
	if reason == &"town_center" or reason == &"production":
		return false

	if not _is_attack_close_to_winning(tree):
		return false

	return not is_emergency_threat_serious(tree, threat)


static func pull_emergency_defense_reinforcements(
	tree: SceneTree,
	intercept_position: Vector3
) -> void:
	if intercept_position == Vector3.ZERO:
		return

	var reinforcements: Array = []
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		if is_hero_unit(unit as Node):
			continue

		var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(unit as Node)
		if (
			mission == EnemyUnitMission.Mission.RETREAT
			or mission == EnemyUnitMission.Mission.BUILD
			or mission == EnemyUnitMission.Mission.ECONOMY
		):
			continue

		reinforcements.append(unit)

	if reinforcements.is_empty():
		return

	command_attack_move(
		reinforcements,
		intercept_position,
		EnemyUnitMission.Mission.DEFEND
	)


static func build_defense_army(
	tree: SceneTree,
	_threat_anchor: Vector3 = Vector3.ZERO
) -> Array:
	if resolve_enemy_rally_position(tree) == Vector3.ZERO:
		return []

	# Rally every living combat unit so defense never trickles in one or two soldiers.
	return collect_living_combat_units(tree)


static func evaluate_defense_commitment(
	tree: SceneTree,
	defense_army: Array,
	threat_position: Vector3
) -> Dictionary:
	var defender_strength: float = estimate_combat_strength(defense_army)
	var threat_units: Array = collect_player_military_near(
		tree,
		threat_position,
		DEFENSE_THREAT_POWER_RANGE
	)
	var threat_strength: float = estimate_combat_strength(threat_units)

	return {
		"defender_power": int(defender_strength),
		"threat_power": int(threat_strength),
		"can_commit": should_defense_commit_attack(
			defense_army,
			int(defender_strength),
			int(threat_strength)
		),
	}


static func should_defense_commit_attack(
	defense_army: Array,
	defender_power: int,
	threat_power: int
) -> bool:
	if defense_army.is_empty():
		return false

	if defender_power <= 0:
		return false

	var defender_strength: float = estimate_combat_strength(defense_army)
	var threat_strength: float = float(threat_power)
	if threat_strength <= 0.0:
		return true

	return evaluate_strength_gate(
		defender_strength,
		threat_strength,
		&"defend"
	).get("allowed", false)


static func resolve_defense_intercept_position(
	tree: SceneTree,
	threat: Dictionary,
	fallback_position: Vector3
) -> Vector3:
	var anchor_position: Vector3 = threat.get("intercept_position", fallback_position)
	if anchor_position == Vector3.ZERO:
		anchor_position = fallback_position

	return _resolve_player_threat_cluster_position(tree, anchor_position)


static func estimate_military_power(units: Array) -> int:
	var power: int = 0

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		var health_component: HealthComponent = (unit as Node).get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		var current_health: int = (
			health_component.current_health
			if health_component != null
			else 0
		)

		if unit is Hero:
			power += DEFENSE_POWER_HERO_BASE + current_health
			continue

		var damage: int = (
			int((unit as Object).get("attack_damage"))
			if "attack_damage" in unit
			else 0
		)
		if unit is Archer or unit is CavalryArcher or unit is Cannon:
			power += int(float(current_health) * DEFENSE_POWER_RANGED_HEALTH)
		else:
			power += int(float(current_health) * DEFENSE_POWER_MELEE_HEALTH)
		power += damage * int(DEFENSE_POWER_DAMAGE_MULTIPLIER)

	return power


static func estimate_player_threat_power_near(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> int:
	return estimate_military_power(
		collect_player_military_near(tree, position, search_range)
	)


static func collect_player_military_near(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> Array:
	var targets: Array = []

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not _is_player_military_unit(node):
				continue

			var target: Node3D = node as Node3D
			if horizontal_distance(position, target.global_position) > search_range:
				continue

			targets.append(node)

	return targets


static func resolve_defense_hold_position(
	rally_position: Vector3,
	threat_position: Vector3
) -> Vector3:
	if rally_position == Vector3.ZERO:
		return threat_position

	if threat_position == Vector3.ZERO:
		return rally_position

	var offset: Vector3 = threat_position - rally_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		return rally_position

	var forward: Vector3 = offset.normalized()
	var hold_distance: float = minf(
		DEFENSE_HOLD_FORWARD_DISTANCE,
		offset.length() * 0.35
	)
	return rally_position + forward * hold_distance


static func is_enemy_army_under_attack(
	tree: SceneTree,
	army_units: Array,
	search_range: float
) -> bool:
	var army_center: Vector3 = compute_army_center(army_units)
	if army_center == Vector3.ZERO:
		return false

	return (
		_find_player_military_near_position(tree, army_center, search_range) != null
	)


static func find_living_player_command_center(tree: SceneTree) -> CommandCenter:
	return _resolve_living_player_command_center(tree)


static func horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	return _horizontal_distance(from_position, to_position)


static func resolve_enemy_rally_position(tree: SceneTree) -> Vector3:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_building(node as Building):
			return (node as Node3D).global_position + ARMY_RALLY_OFFSET

	for node: Node in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if node is Node3D:
			return (node as Node3D).global_position

	return Vector3.ZERO


static func has_player_attack_targets(tree: SceneTree, enemy_base_position: Vector3) -> bool:
	if _find_player_military_near_position(tree, enemy_base_position, BASE_THREAT_DETECTION_RANGE) != null:
		return true

	if _resolve_living_player_command_center(tree) != null:
		return true

	if _find_nearest_living_player_building(tree, enemy_base_position) != null:
		return true

	if _find_nearest_living_player_unit(tree, enemy_base_position) != null:
		return true

	return false


static func resolve_attack_objective(tree: SceneTree, fallback_position: Vector3) -> Dictionary:
	if _finishing_mode_active:
		return resolve_finishing_attack_objective(tree, fallback_position)

	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return {
			"node": command_center,
			"position": command_center.global_position,
		}

	var important_building: Node3D = _find_nearest_important_player_building(
		tree,
		fallback_position
	)
	if important_building != null:
		return {
			"node": important_building,
			"position": important_building.global_position,
		}

	var nearest_building: Node3D = _find_nearest_living_player_building(
		tree,
		fallback_position
	)
	if nearest_building != null:
		return {
			"node": nearest_building,
			"position": nearest_building.global_position,
		}

	var nearest_worker: Node3D = _find_nearest_living_player_worker(tree, fallback_position)
	if nearest_worker != null:
		return {
			"node": nearest_worker,
			"position": nearest_worker.global_position,
		}

	if fallback_position != Vector3.ZERO:
		return {"node": null, "position": fallback_position}

	return {"node": null, "position": Vector3.ZERO}


static func resolve_wave_attack_destination(tree: SceneTree, enemy_base_position: Vector3) -> Vector3:
	return resolve_attack_objective(tree, enemy_base_position).get("position", Vector3.ZERO)


static func is_hero_healthy_enough_for_wave(hero: Hero) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	return get_health_ratio(hero) >= HERO_WAVE_JOIN_HP_RATIO


static func get_health_ratio(node: Node) -> float:
	if not NodeSafety.is_alive_node(node):
		return 0.0

	var health_component: HealthComponent = node.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component == null or health_component.max_health <= 0:
		return 1.0

	return float(health_component.current_health) / float(health_component.max_health)


static func command_retreat_hero(hero: Hero, rally_position: Vector3) -> void:
	if not NodeSafety.is_alive_node(hero):
		return

	if not is_living_combat_unit(hero):
		return

	_cancel_unit_offensive_orders(hero)
	EnemyUnitMission.try_set_mission(hero, EnemyUnitMission.Mission.RETREAT)
	_issue_hold_at_rally(hero, rally_position)


static func _cancel_unit_offensive_orders(unit: Variant) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if (unit as Object).has_method("cancel_attack_move"):
		(unit as Object).call("cancel_attack_move")

	if (unit as Object).has_method("cancel_attack"):
		(unit as Object).call("cancel_attack")


static func command_attack_move(
	units: Array,
	destination: Vector3,
	mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.ATTACK
) -> void:
	if not _combat_orders_allowed(mission):
		return

	_issue_spaced_group_orders(units, destination, true, mission)


static func command_defend_position(units: Array, position: Vector3) -> void:
	command_attack_move(units, position, EnemyUnitMission.Mission.DEFEND)


static func command_retreat_to(units: Array, position: Vector3) -> void:
	_issue_spaced_group_orders(
		units,
		position,
		false,
		EnemyUnitMission.Mission.RETREAT
	)


static func command_hold_at_rally(
	units: Array,
	rally_position: Vector3,
	mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.REGROUP
) -> void:
	_issue_spaced_group_orders(units, rally_position, false, mission)


static func _issue_attack_move(unit: Variant, destination: Vector3) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if not (unit as Object).has_method("command_attack_move"):
		return

	(unit as Object).call("command_attack_move", destination)


static func _issue_spaced_group_orders(
	units: Array,
	center: Vector3,
	use_attack_move: bool,
	mission: EnemyUnitMission.Mission
) -> void:
	units = NodeSafety.clean_node_array(units)
	var commandable_units: Array = EnemyUnitMission.filter_commandable_units(units, mission)
	var ordered_units: Array = _order_units_for_formation(commandable_units)
	if ordered_units.is_empty():
		return

	var move_targets: Array[Vector3] = (
		_compute_attack_formation_targets(ordered_units, center, FORMATION_SPACING)
		if use_attack_move
		else GroupMoveSpacing.compute_targets(
			center,
			ordered_units.size(),
			FORMATION_SPACING
		)
	)
	for index: int in ordered_units.size():
		var unit: Variant = ordered_units[index]
		if not NodeSafety.is_alive_node(unit):
			continue

		var target: Vector3 = move_targets[index]
		if not EnemyUnitMission.should_reissue_move_order(unit as Node, target, mission):
			continue

		if (
			use_attack_move
			and mission == EnemyUnitMission.Mission.ATTACK
			and _has_living_attack_building_objective()
		):
			_command_unit_focus_attack(unit, _active_wave_objective)
			EnemyUnitMission.try_set_mission(unit as Node, mission)
			EnemyUnitMission.record_move_order(unit as Node, target, mission)
			continue

		if use_attack_move:
			_issue_attack_move(unit, target)
		else:
			_issue_hold_at_rally(unit, target)

		EnemyUnitMission.try_set_mission(unit as Node, mission)
		EnemyUnitMission.record_move_order(unit as Node, target, mission)


static func _order_units_for_formation(units: Array) -> Array:
	var melee_units: Array = []
	var ranged_units: Array = []
	var hero_units: Array = []

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if unit is Worker:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		if is_hero_unit(unit as Node):
			hero_units.append(unit)
		elif unit is Archer or unit is CavalryArcher or unit is Cannon:
			ranged_units.append(unit)
		else:
			melee_units.append(unit)

	var ordered_units: Array = []
	ordered_units.append_array(melee_units)
	ordered_units.append_array(ranged_units)
	ordered_units.append_array(hero_units)
	return ordered_units


static func _compute_attack_formation_targets(
	units: Array,
	destination: Vector3,
	spacing: float
) -> Array[Vector3]:
	if units.is_empty():
		return []

	var army_center: Vector3 = compute_army_center(units)
	var forward: Vector3 = destination - army_center
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0.0, 0.0, 1.0)
	else:
		forward = forward.normalized()

	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var melee_count: int = 0
	var ranged_count: int = 0
	var hero_count: int = 0
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if is_hero_unit(unit as Node):
			hero_count += 1
		elif unit is Archer or unit is CavalryArcher or unit is Cannon:
			ranged_count += 1
		else:
			melee_count += 1

	var melee_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		destination,
		right,
		melee_count,
		spacing
	)
	var ranged_row_center: Vector3 = (
		destination - forward * spacing * RANGED_ROW_DEPTH_MULTIPLIER
	)
	var ranged_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		ranged_row_center,
		right,
		ranged_count,
		spacing
	)
	var hero_row_center: Vector3 = destination - forward * spacing * HERO_ROW_DEPTH_MULTIPLIER
	var hero_targets: Array[Vector3] = GroupMoveSpacing.compute_line_targets(
		hero_row_center,
		right,
		hero_count,
		spacing
	)

	var targets: Array[Vector3] = []
	var melee_index: int = 0
	var ranged_index: int = 0
	var hero_index: int = 0

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			targets.append(destination)
			continue

		var candidate: Vector3 = destination
		if is_hero_unit(unit as Node):
			candidate = hero_targets[hero_index]
			hero_index += 1
		elif unit is Archer or unit is CavalryArcher or unit is Cannon:
			candidate = ranged_targets[ranged_index]
			ranged_index += 1
		else:
			candidate = melee_targets[melee_index]
			melee_index += 1

		targets.append(
			GroupMoveSpacing.resolve_nearby_walkable_position(
				candidate,
				unit as Node3D,
				destination,
				spacing
			)
		)

	return targets


static func compute_army_center(units: Array) -> Vector3:
	units = NodeSafety.clean_node_array(units)
	if units.is_empty():
		return Vector3.ZERO

	var position_sum: Vector3 = Vector3.ZERO
	var count: int = 0

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not unit is Node3D:
			continue

		if not is_living_combat_unit(unit as Node):
			continue

		position_sum += (unit as Node3D).global_position
		count += 1

	if count == 0:
		return Vector3.ZERO

	return position_sum / float(count)


static func _issue_hold_at_rally(unit: Variant, rally_position: Vector3) -> void:
	if not NodeSafety.is_alive_node(unit):
		return

	if not is_living_combat_unit(unit as Node):
		return

	if (unit as Object).has_method("set_movement_target"):
		(unit as Object).call("set_movement_target", rally_position)
		return

	_issue_attack_move(unit, rally_position)


static func _build_defense_threat_result(
	intercept_position: Vector3,
	reason: StringName,
	force_commit: bool = false
) -> Dictionary:
	return {
		"threatened": true,
		"intercept_position": intercept_position,
		"reason": reason,
		"force_commit": force_commit,
	}


static func _assign_reinforcement_to_emergency_defense(tree: SceneTree, unit: Unit) -> void:
	var objective_position: Vector3 = get_emergency_defense_objective()
	if objective_position == Vector3.ZERO:
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		if rally_position == Vector3.ZERO:
			return
		if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.REGROUP):
			return
		command_hold_at_rally([unit], rally_position, EnemyUnitMission.Mission.REGROUP)
		return

	if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.DEFEND):
		return

	command_attack_move([unit], objective_position, EnemyUnitMission.Mission.DEFEND)


static func _is_important_enemy_production_building(building: Building) -> bool:
	return (
		building is Barracks
		or building is HeroAltar
		or building is Blacksmith
		or building is Shop
	)


static func _is_important_enemy_building(building: Building) -> bool:
	return building is CommandCenter or _is_important_enemy_production_building(building)


static func _evaluate_emergency_command_center_threat(tree: SceneTree) -> Dictionary:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is CommandCenter or not _is_living_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: CommandCenter = node as CommandCenter
		var building_position: Vector3 = (node as Node3D).global_position
		var attacker: Node = CombatKillTracker.get_attacker(building)
		if _is_player_military_unit(attacker) and attacker is Node3D:
			return _build_emergency_threat_result(
				_resolve_player_threat_cluster_position(
					tree,
					(attacker as Node3D).global_position
				),
				&"town_center",
				true
			)

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if nearby_threat != null:
			return _build_emergency_threat_result(
				_resolve_player_threat_cluster_position(tree, nearby_threat.global_position),
				&"town_center",
				true
			)

	return {"threatened": false}


static func _evaluate_emergency_production_building_threat(tree: SceneTree) -> Dictionary:
	var closest_attacker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not _is_important_enemy_production_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: Building = node as Building
		var building_position: Vector3 = (node as Node3D).global_position
		var attacker: Node = CombatKillTracker.get_attacker(building)
		if _is_player_military_unit(attacker) and attacker is Node3D:
			var distance: float = _horizontal_distance(
				building_position,
				(attacker as Node3D).global_position
			)
			if distance < closest_distance:
				closest_distance = distance
				closest_attacker = attacker as Node3D
			continue

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if nearby_threat == null:
			continue

		var nearby_distance: float = _horizontal_distance(
			building_position,
			nearby_threat.global_position
		)
		if nearby_distance < closest_distance:
			closest_distance = nearby_distance
			closest_attacker = nearby_threat

	if closest_attacker != null:
		return _build_emergency_threat_result(
			_resolve_player_threat_cluster_position(tree, closest_attacker.global_position),
			&"production",
			true
		)

	return {"threatened": false}


static func _evaluate_emergency_player_hero_threat(
	tree: SceneTree,
	rally_position: Vector3
) -> Dictionary:
	for node: Node in tree.get_nodes_in_group(HEROES_GROUP):
		if not node is Hero or not _is_player_military_unit(node):
			continue

		if not node is Node3D:
			continue

		var hero_position: Vector3 = (node as Node3D).global_position
		if _horizontal_distance(rally_position, hero_position) > CORE_BASE_DEFENSE_RADIUS:
			continue

		return _build_emergency_threat_result(
			_resolve_player_threat_cluster_position(tree, hero_position),
			&"player_hero",
			true
		)

	return {"threatened": false}


static func _evaluate_emergency_core_base_threat(
	tree: SceneTree,
	rally_position: Vector3
) -> Dictionary:
	var units_in_base: Array = collect_player_military_near(
		tree,
		rally_position,
		CORE_BASE_DEFENSE_RADIUS
	)
	if units_in_base.is_empty():
		return {"threatened": false}

	if _is_irrelevant_lone_scout(tree, units_in_base):
		return {"threatened": false}

	var anchor: Node3D = units_in_base[0] as Node3D
	if anchor == null:
		return {"threatened": false}

	var intercept_position: Vector3 = _resolve_player_threat_cluster_position(
		tree,
		anchor.global_position
	)
	return _build_emergency_threat_result(
		intercept_position,
		&"core_base",
		is_emergency_threat_serious(
			tree,
			_build_emergency_threat_result(intercept_position, &"core_base")
		)
	)


static func _evaluate_emergency_worker_attack_threat(tree: SceneTree) -> Dictionary:
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not _is_important_enemy_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: Building = node as Building
		var attacker: Node = CombatKillTracker.get_attacker(building)
		if not NodeSafety.is_alive_node(attacker):
			continue

		if not attacker is Worker:
			continue

		if CombatTargetValidation.is_enemy_faction(attacker):
			continue

		return _build_emergency_threat_result(
			_resolve_player_threat_cluster_position(
				tree,
				(node as Node3D).global_position
			),
			&"worker_attack"
		)

	return {"threatened": false}


static func _is_irrelevant_lone_scout(tree: SceneTree, units_in_base: Array) -> bool:
	if units_in_base.size() != 1:
		return false

	var unit: Node = units_in_base[0] as Node
	if not NodeSafety.is_alive_node(unit):
		return false

	if unit is Hero:
		return false

	if not unit is Node3D:
		return false

	var unit_position: Vector3 = (unit as Node3D).global_position
	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not _is_important_enemy_building(node as Building):
			continue

		if not node is Node3D:
			continue

		if (
			_horizontal_distance(unit_position, (node as Node3D).global_position)
			<= EMERGENCY_SCOUT_IGNORE_BUILDING_DISTANCE
		):
			return false

	return true


static func _build_emergency_threat_result(
	intercept_position: Vector3,
	reason: StringName,
	force_recall: bool = false
) -> Dictionary:
	return {
		"threatened": true,
		"intercept_position": intercept_position,
		"reason": reason,
		"force_recall": force_recall,
	}


static func _evaluate_worker_defense_threat(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_attacker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_WORKERS_GROUP):
		if not node is Worker or not _has_positive_health(node):
			continue

		if not node is Node3D:
			continue

		var worker: Worker = node as Worker
		var worker_position: Vector3 = (node as Node3D).global_position
		var attacker: Node = CombatKillTracker.get_attacker(worker)
		if _is_player_military_unit(attacker) and attacker is Node3D:
			var distance: float = _horizontal_distance(
				rally_position,
				(attacker as Node3D).global_position
			)
			if distance < closest_distance:
				closest_distance = distance
				closest_attacker = attacker as Node3D
			continue

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			worker_position,
			WORKER_THREAT_RANGE
		)
		if nearby_threat == null:
			continue

		var nearby_distance: float = _horizontal_distance(
			rally_position,
			nearby_threat.global_position
		)
		if nearby_distance < closest_distance:
			closest_distance = nearby_distance
			closest_attacker = nearby_threat

	if closest_attacker != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, closest_attacker.global_position),
			&"workers",
			true
		)

	return {"threatened": false}


static func _evaluate_building_defense_threat(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_attacker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building: Building = node as Building
		var building_position: Vector3 = (node as Node3D).global_position
		var attacker: Node = CombatKillTracker.get_attacker(building)
		if _is_player_military_unit(attacker) and attacker is Node3D:
			var distance: float = _horizontal_distance(
				rally_position,
				(attacker as Node3D).global_position
			)
			if distance < closest_distance:
				closest_distance = distance
				closest_attacker = attacker as Node3D
			continue

		var nearby_threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			BUILDING_THREAT_RANGE
		)
		if nearby_threat == null:
			continue

		var nearby_distance: float = _horizontal_distance(
			rally_position,
			nearby_threat.global_position
		)
		if nearby_distance < closest_distance:
			closest_distance = nearby_distance
			closest_attacker = nearby_threat

	if closest_attacker != null:
		return _build_defense_threat_result(
			_resolve_player_threat_cluster_position(tree, closest_attacker.global_position),
			&"buildings",
			true
		)

	return {"threatened": false}


static func _find_player_military_in_enemy_economy_area(tree: SceneTree) -> Node3D:
	var closest_target: Node3D = null
	var closest_distance: float = INF
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)

	for node: Node in tree.get_nodes_in_group(ENEMY_WORKERS_GROUP):
		if not node is Worker or not _has_positive_health(node):
			continue

		if not node is Node3D:
			continue

		var worker_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			worker_position,
			ENEMY_ECONOMY_AREA_RANGE
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = threat

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if node is CommandCenter:
			continue

		if not node is Node3D:
			continue

		var building_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			ENEMY_ECONOMY_AREA_RANGE
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = threat

	return closest_target


static func _resolve_player_threat_cluster_position(
	tree: SceneTree,
	anchor_position: Vector3
) -> Vector3:
	var nearby_units: Array = collect_player_military_near(
		tree,
		anchor_position,
		DEFENSE_THREAT_POWER_RANGE
	)
	if nearby_units.is_empty():
		return anchor_position

	var position_sum: Vector3 = Vector3.ZERO
	var count: int = 0

	for unit: Variant in nearby_units:
		if not NodeSafety.is_alive_node(unit):
			continue

		if not unit is Node3D:
			continue

		position_sum += (unit as Node3D).global_position
		count += 1

	if count == 0:
		return anchor_position

	return position_sum / float(count)


static func _find_player_military_near_enemy_workers(
	tree: SceneTree,
	search_range: float
) -> Vector3:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_threat: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_WORKERS_GROUP):
		if not node is Worker or not _has_positive_health(node):
			continue

		if not node is Node3D:
			continue

		var worker_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			worker_position,
			search_range
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_threat = threat

	if closest_threat != null:
		return closest_threat.global_position

	return Vector3.ZERO


static func _find_player_military_near_enemy_buildings(
	tree: SceneTree,
	search_range: float
) -> Vector3:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var closest_threat: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building or not _is_living_building(node as Building):
			continue

		if not node is Node3D:
			continue

		var building_position: Vector3 = (node as Node3D).global_position
		var threat: Node3D = _find_player_military_near_position(
			tree,
			building_position,
			search_range
		)
		if threat == null:
			continue

		var distance: float = _horizontal_distance(rally_position, threat.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_threat = threat

	if closest_threat != null:
		return closest_threat.global_position

	return Vector3.ZERO


static func _find_player_military_near_position(
	tree: SceneTree,
	position: Vector3,
	search_range: float
) -> Node3D:
	var closest_target: Node3D = null
	var closest_distance: float = INF

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not _is_player_military_unit(node):
				continue

			var target: Node3D = node as Node3D
			var distance: float = _horizontal_distance(position, target.global_position)
			if distance > search_range:
				continue

			if distance < closest_distance:
				closest_distance = distance
				closest_target = target

	return closest_target


static func _is_player_military_unit(node: Node) -> bool:
	if not NodeSafety.is_alive_node(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if CombatTargetValidation.is_enemy_faction(node):
		return false

	if not (node is Spearman or node is Swordsman or node is Archer or node is HeavyCavalry or node is LightCavalry or node is CavalryArcher or node is Cannon or node is Hero):
		return false

	return _has_positive_health(node)


static func _resolve_living_player_command_center(tree: SceneTree) -> CommandCenter:
	for node: Node in tree.get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_building(node as Building):
			return node as CommandCenter

	return null


static func _find_nearest_important_player_building(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_building: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		if node is Farm:
			continue

		var building: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, building.global_position)
		if distance > IMPORTANT_BUILDING_SEARCH_RANGE:
			continue

		if distance < closest_distance:
			closest_distance = distance
			closest_building = building

	return closest_building


static func _find_nearest_living_player_building(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_building: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		var building: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, building.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_building = building

	return closest_building


static func _find_nearest_living_player_unit(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_unit: Node3D = null
	var closest_distance: float = INF

	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not node is Node3D:
				continue

			if CombatTargetValidation.is_enemy_faction(node):
				continue

			if not CombatTargetValidation.is_valid_combat_target(node):
				continue

			if node is Worker:
				continue

			var target: Node3D = node as Node3D
			var distance: float = _horizontal_distance(from_position, target.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_unit = target

	return closest_unit


static func _find_nearest_living_player_worker(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var closest_worker: Node3D = null
	var closest_distance: float = INF

	for node: Node in tree.get_nodes_in_group(UNITS_GROUP):
		if not node is Worker or not node is Node3D:
			continue

		if CombatTargetValidation.is_enemy_faction(node):
			continue

		if not CombatTargetValidation.is_valid_combat_target(node):
			continue

		var worker: Node3D = node as Node3D
		var distance: float = _horizontal_distance(from_position, worker.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_worker = worker

	return closest_worker


static func _has_living_attack_building_objective() -> bool:
	if not NodeSafety.is_alive_node(_active_wave_objective):
		return false

	if not _active_wave_objective is Building:
		return false

	return _is_living_building(_active_wave_objective as Building)


static func _is_living_building(building: Building) -> bool:
	if not NodeSafety.is_alive_node(building):
		return false

	if building.is_queued_for_deletion():
		return false

	return _has_positive_health(building)


static func _has_positive_health(node: Node) -> bool:
	var health_component: HealthComponent = node.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


static func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length()


static func resolve_finishing_attack_objective(
	tree: SceneTree,
	fallback_position: Vector3
) -> Dictionary:
	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return {
			"node": command_center,
			"position": command_center.global_position,
		}

	var reference_position: Vector3 = fallback_position
	if reference_position == Vector3.ZERO:
		reference_position = _resolve_player_base_reference_position(tree, fallback_position)

	var finishing_building: Node3D = _find_highest_priority_finishing_building(
		tree,
		reference_position
	)
	if finishing_building != null:
		return {
			"node": finishing_building,
			"position": finishing_building.global_position,
		}

	var nearest_worker: Node3D = _find_nearest_living_player_worker(tree, reference_position)
	if nearest_worker != null:
		return {
			"node": nearest_worker,
			"position": nearest_worker.global_position,
		}

	if fallback_position != Vector3.ZERO:
		return {"node": null, "position": fallback_position}

	return {"node": null, "position": Vector3.ZERO}


static func _set_finishing_mode(active: bool, reason: String) -> void:
	if active == _finishing_mode_active:
		return

	_finishing_mode_active = active
	_last_finishing_objective = null

	if active:
		print("[AI] ENTER FINISHING MODE reason=%s" % reason)
	else:
		print("[AI] EXIT FINISHING MODE reason=%s" % reason)
		_finishing_mode_exit_cooldown = FINISHING_MODE_EXIT_COOLDOWN


static func _evaluate_finishing_activation(tree: SceneTree) -> Dictionary:
	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return {"should_enter": false}

	if not has_player_attack_targets(tree, rally_position):
		return {"should_enter": false}

	var ai_combat_count: int = collect_living_combat_units(tree).size()
	var player_combat_count: int = _count_living_player_combat_units(tree)

	if _resolve_living_player_command_center(tree) == null:
		if ai_combat_count >= FINISHING_MODE_MIN_PUSH_UNITS:
			return {
				"should_enter": true,
				"reason": "player_command_center_destroyed",
			}

	if (
		player_combat_count <= FINISHING_MODE_MAX_PLAYER_COMBAT_UNITS
		and ai_combat_count >= FINISHING_MODE_MIN_AI_COMBAT_UNITS
	):
		return {
			"should_enter": true,
			"reason": "player_army_crippled",
		}

	var military_production_count: int = _count_living_player_military_production_buildings(tree)
	if (
		military_production_count <= FINISHING_MODE_MAX_PLAYER_MILITARY_PRODUCTION
		and player_combat_count <= FINISHING_MODE_WEAK_PLAYER_COMBAT_FOR_PRODUCTION
		and ai_combat_count >= FINISHING_MODE_MIN_AI_COMBAT_UNITS
	):
		return {
			"should_enter": true,
			"reason": "player_production_crippled",
		}

	if ai_combat_count >= FINISHING_MODE_MIN_PUSH_UNITS and _is_finishing_army_inside_player_base(
		tree
	):
		var base_reference: Vector3 = _resolve_player_base_reference_position(
			tree,
			rally_position
		)
		var player_power: int = estimate_player_threat_power_near(
			tree,
			base_reference,
			FINISHING_MODE_IN_BASE_DISTANCE
		)
		if player_power <= FINISHING_MODE_WEAK_RESISTANCE_POWER:
			return {
				"should_enter": true,
				"reason": "army_in_base_weak_resistance",
			}

	return {"should_enter": false}


static func _evaluate_finishing_exit(tree: SceneTree) -> Dictionary:
	var ai_units: Array = _collect_living_offensive_wave_units(tree)
	if ai_units.is_empty():
		ai_units = collect_living_combat_units(tree)

	var ai_power: int = estimate_military_power(ai_units)
	var player_units: Array = _collect_living_player_combat_unit_nodes(tree)
	var player_power: int = estimate_military_power(player_units)
	var player_combat_count: int = player_units.size()

	if (
		player_combat_count >= 3
		and ai_power > 0
		and player_power >= int(float(ai_power) * FINISHING_MODE_PLAYER_RECOVERY_RATIO)
	):
		return {"should_exit": true, "reason": "player_recovered_strength"}

	var living_count: int = ai_units.size()
	if _active_wave_start_unit_count > 0:
		var retreat_threshold: int = maxi(
			FINISHING_MODE_MIN_PUSH_UNITS,
			int(float(_active_wave_start_unit_count) * FINISHING_MODE_ARMY_DESTROYED_RATIO)
		)
		if living_count < retreat_threshold:
			return {"should_exit": true, "reason": "ai_army_destroyed"}
	elif get_army_mode() == ArmyMode.ATTACKING and living_count < FINISHING_MODE_MIN_PUSH_UNITS:
		return {"should_exit": true, "reason": "ai_army_destroyed"}

	return {"should_exit": false}


static func _assign_reinforcement_to_finishing_attack(tree: SceneTree, unit: Unit) -> void:
	var objective_position: Vector3 = get_attack_objective_position()
	var objective_node: Node3D = NodeSafety.safe_node(_active_wave_objective) as Node3D

	if objective_position == Vector3.ZERO or not NodeSafety.is_alive_node(objective_node):
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		var objective: Dictionary = resolve_attack_objective(tree, rally_position)
		objective_position = objective.get("position", Vector3.ZERO)
		objective_node = objective.get("node") as Node3D
		if NodeSafety.is_alive_node(objective_node):
			set_attack_objective(objective_node, objective_position)

	if objective_position == Vector3.ZERO:
		var rally_position: Vector3 = resolve_enemy_rally_position(tree)
		if rally_position == Vector3.ZERO:
			return

		if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.REGROUP):
			return

		command_hold_at_rally([unit], rally_position, EnemyUnitMission.Mission.REGROUP)
		return

	if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.ATTACK):
		return

	if NodeSafety.is_alive_node(objective_node):
		_command_unit_focus_attack(unit, objective_node)
	else:
		_issue_attack_move(unit, objective_position)

	EnemyUnitMission.record_move_order(
		unit,
		objective_position,
		EnemyUnitMission.Mission.ATTACK
	)


static func _log_finishing_objective(objective_node: Node3D) -> void:
	if not NodeSafety.is_alive_node(objective_node):
		return

	if objective_node == _last_finishing_objective:
		return

	_last_finishing_objective = objective_node
	print(
		"[AI] FINISH OBJECTIVE %s"
		% _get_finishing_objective_display_name(objective_node)
	)


static func _get_finishing_objective_display_name(node: Node) -> String:
	if not NodeSafety.is_alive_node(node):
		return "unknown"

	if node is CommandCenter:
		return "CommandCenter"
	if node is Barracks:
		return "Barracks"
	if node is HeroAltar:
		return "HeroAltar"
	if node is Tower:
		return "Tower"
	if node is Blacksmith:
		return "Blacksmith"
	if node is Shop:
		return "Shop"
	if node is Worker:
		return "Worker"
	if node is Building:
		return "Building"

	return node.name


static func _count_living_player_combat_units(tree: SceneTree) -> int:
	return _collect_living_player_combat_unit_nodes(tree).size()


static func _collect_living_player_combat_unit_nodes(tree: SceneTree) -> Array:
	var units: Array = []
	for group_name: StringName in [UNITS_GROUP, HEROES_GROUP]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if not node is Node3D:
				continue

			if CombatTargetValidation.is_enemy_faction(node):
				continue

			if node is Worker:
				continue

			if not (node is Spearman or node is Swordsman or node is Archer or node is HeavyCavalry or node is LightCavalry or node is CavalryArcher or node is Cannon or node is Hero):
				continue

			if not CombatTargetValidation.is_valid_combat_target(node):
				continue

			units.append(node)

	return units


static func _count_living_player_military_production_buildings(tree: SceneTree) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		if node is Barracks or node is HeroAltar:
			count += 1

	return count


static func _resolve_player_base_reference_position(
	tree: SceneTree,
	fallback_position: Vector3
) -> Vector3:
	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return command_center.global_position

	var nearest_building: Node3D = _find_nearest_living_player_building(
		tree,
		fallback_position
	)
	if nearest_building != null:
		return nearest_building.global_position

	return fallback_position


static func _is_finishing_army_inside_player_base(tree: SceneTree) -> bool:
	var wave_units: Array = _collect_living_offensive_wave_units(tree)
	if wave_units.is_empty():
		wave_units = collect_living_combat_units(tree)

	var army_center: Vector3 = compute_army_center(wave_units)
	if army_center == Vector3.ZERO:
		return false

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	var base_reference: Vector3 = _resolve_player_base_reference_position(
		tree,
		rally_position
	)
	if base_reference == Vector3.ZERO:
		return false

	return (
		horizontal_distance(army_center, base_reference)
		<= FINISHING_MODE_IN_BASE_DISTANCE
	)


static func _find_highest_priority_finishing_building(
	tree: SceneTree,
	from_position: Vector3
) -> Node3D:
	var best_building: Node3D = null
	var best_priority: int = 999
	var best_distance: float = INF

	for node: Node in tree.get_nodes_in_group(BUILDINGS_GROUP):
		if not node is Building:
			continue

		if not CombatTargetValidation.is_player_selectable_building(node):
			continue

		if not _is_living_building(node as Building):
			continue

		var building: Building = node as Building
		var priority: int = _get_finishing_building_priority(building, tree)
		var building_position: Vector3 = (building as Node3D).global_position
		var distance: float = _horizontal_distance(from_position, building_position)

		if priority < best_priority or (priority == best_priority and distance < best_distance):
			best_priority = priority
			best_distance = distance
			best_building = building as Node3D

	return best_building


static func _get_finishing_building_priority(building: Building, tree: SceneTree) -> int:
	if building is Barracks:
		return 1
	if building is HeroAltar:
		return 2
	if building is Tower and _is_actively_dangerous_tower(building as Tower, tree):
		return 3
	if building is Blacksmith or building is Shop:
		return 4
	if building is Farm:
		return 6
	if building is Tower:
		return 5

	return 5


static func _is_actively_dangerous_tower(tower: Tower, tree: SceneTree) -> bool:
	if not NodeSafety.is_alive_node(tower):
		return false

	if tower.building_state != Building.STATE_COMPLETED:
		return false

	var threat_range: float = tower.attack_range + FINISHING_MODE_TOWER_THREAT_BUFFER
	for unit: Variant in collect_living_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue

		if horizontal_distance((unit as Node3D).global_position, tower.global_position) <= threat_range:
			return true

	return false
