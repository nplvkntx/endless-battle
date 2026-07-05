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

const MIN_NON_HERO_FOR_HERO_JOIN := 24
const MIN_ARMY_UNITS_TO_CONTINUE_ATTACK := 10
const MIN_TOTAL_COMBAT_UNITS_FOR_ATTACK := 25
const MIN_MELEE_UNITS_FOR_ATTACK := 8
const MIN_RANGED_UNITS_FOR_ATTACK := 6
const ABSOLUTE_MIN_ATTACK_NON_HERO_UNITS := 6
const ATTACK_STANDARD_MIN_NON_HERO_UNITS := 18
const ATTACK_TIMER_MIN_NON_HERO_UNITS := 12
const ATTACK_DESPERATE_MIN_NON_HERO_UNITS := 9
const ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS := 8
const ATTACK_TIMER_STANDARD_SECONDS := 240.0
const ATTACK_TIMER_DESPERATE_SECONDS := 360.0
const DEBUG_ATTACK_GATE := true
const PLAYER_ARMY_STRENGTH_RATIO := 0.8
const KNOWN_PLAYER_SCOUT_RANGE := 55.0
const ARMY_GROUP_MAX_RADIUS := 24.0
const WAVE_REINFORCEMENT_WAIT_SECONDS := 5.0
const MIN_ATTACK_ARMY_POWER := 350
const HERO_ALONE_PLAYER_THREAT_RANGE := 18.0
const HERO_MAX_DISTANCE_FROM_ARMY := 16.0
const HERO_RETREAT_HP_RATIO := 0.30
const HERO_DEFENSE_CRITICAL_RETREAT_HP_RATIO := 0.20
const HERO_WAVE_JOIN_HP_RATIO := 0.60
const HERO_DEFENSIVE_ABILITY_HP_RATIO := 0.40
const DEFENSE_GATHER_MAX_DISTANCE := 42.0
const DEFENSE_HERO_EXTRA_GATHER_DISTANCE := 14.0
const DEFENSE_THREAT_POWER_RANGE := 34.0
const DEFENSE_HOLD_FORWARD_DISTANCE := 10.0
const DEFENSE_POWER_HERO_BASE := 220
const DEFENSE_POWER_MELEE_HEALTH := 1.0
const DEFENSE_POWER_RANGED_HEALTH := 0.85
const DEFENSE_POWER_DAMAGE_MULTIPLIER := 8.0
const HERO_AOE_PLAYER_COUNT := 3
const HERO_AOE_CHECK_RANGE := 10.0
const HERO_POWER_STRIKE_SEARCH_RANGE := 14.0
const HERO_EXECUTE_SEARCH_RANGE := 14.0

const WAVE_1_MIN_NON_HERO_UNITS := 24
const WAVE_2_MIN_NON_HERO_UNITS := 24
const WAVE_3_MIN_NON_HERO_UNITS := 24
const WAVE_4_MIN_NON_HERO_UNITS := 24
const WAVE_REGROUP_MAX_DISTANCE := 22.0
const WAVE_REBUILD_ARMY_RATIO := 0.40

enum ArmyMode {
	IDLE,
	CREEPING,
	ATTACKING,
	REGROUPING,
	DEFENDING,
}

static var _army_mode: ArmyMode = ArmyMode.IDLE
static var _is_rebuilding_army: bool = false
static var _active_wave_start_unit_count: int = 0


static func get_army_mode() -> ArmyMode:
	return _army_mode


static func is_rebuilding_army() -> bool:
	return _is_rebuilding_army


static func set_rebuilding_army(rebuilding: bool) -> void:
	_is_rebuilding_army = rebuilding


static func get_active_wave_start_unit_count() -> int:
	return _active_wave_start_unit_count


static func begin_offensive_wave(wave_units: Array) -> void:
	wave_units = NodeSafety.clean_node_array(wave_units)
	_active_wave_start_unit_count = wave_units.size()


static func clear_offensive_wave_tracking() -> void:
	_active_wave_start_unit_count = 0


## Returns true when the requested mode owns the army for issuing orders.
## Pass allow_attack_override_creep when a ready wave should take over from creeping.
static func try_claim_army_mode(
	requested_mode: ArmyMode,
	allow_attack_override_creep: bool = false
) -> bool:
	if requested_mode == _army_mode:
		return true

	match _army_mode:
		ArmyMode.IDLE:
			_army_mode = requested_mode
			return true
		ArmyMode.CREEPING:
			if requested_mode == ArmyMode.ATTACKING and allow_attack_override_creep:
				_army_mode = ArmyMode.ATTACKING
				return true
			if requested_mode == ArmyMode.REGROUPING or requested_mode == ArmyMode.DEFENDING:
				_army_mode = requested_mode
				return true
			return false
		ArmyMode.ATTACKING:
			if requested_mode == ArmyMode.REGROUPING or requested_mode == ArmyMode.DEFENDING:
				_army_mode = requested_mode
				return true
			return false
		ArmyMode.REGROUPING:
			if (
				requested_mode == ArmyMode.CREEPING
				or requested_mode == ArmyMode.ATTACKING
				or requested_mode == ArmyMode.IDLE
				or requested_mode == ArmyMode.DEFENDING
			):
				_army_mode = requested_mode
				return true
			return false
		ArmyMode.DEFENDING:
			return requested_mode == ArmyMode.DEFENDING

	return false


static func release_army_mode(mode: ArmyMode) -> bool:
	if _army_mode != mode:
		return false

	_army_mode = ArmyMode.IDLE
	return true


static func should_abort_offensive_push(tree: SceneTree) -> bool:
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
	if get_army_mode() != ArmyMode.ATTACKING:
		return false

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
	if match_elapsed_seconds >= ATTACK_TIMER_DESPERATE_SECONDS:
		return ATTACK_DESPERATE_MIN_NON_HERO_UNITS
	if match_elapsed_seconds >= ATTACK_TIMER_STANDARD_SECONDS:
		return ATTACK_TIMER_MIN_NON_HERO_UNITS

	return ATTACK_STANDARD_MIN_NON_HERO_UNITS


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
	var known_player_power: int = estimate_known_player_army_strength(tree, rally_position)
	debug_context["player_strength"] = known_player_power
	debug_context["wave_power"] = wave_power

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
		if unit is Archer:
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
		if is_living_combat_unit(node) and node is Archer:
			return true

	return false


static func is_combat_unit(node: Node) -> bool:
	return node is Swordsman or node is Archer or node is Hero


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

	var rally_position: Vector3 = resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if not EnemyUnitMission.try_set_mission(unit, EnemyUnitMission.Mission.REGROUP):
		return

	command_hold_at_rally([unit], rally_position, EnemyUnitMission.Mission.REGROUP)


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


static func build_regrouped_attack_wave_units(
	tree: SceneTree,
	rally_position: Vector3,
	min_non_hero_units: int
) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var regrouped_non_hero: Array = filter_units_near_rally(
		non_hero_units,
		rally_position
	)
	var can_launch: bool = regrouped_non_hero.size() >= min_non_hero_units
	var wave_units: Array = regrouped_non_hero.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		var army_center: Vector3 = compute_army_center(regrouped_non_hero)
		if (
			hero != null
			and regrouped_non_hero.size() >= ATTACK_HERO_JOIN_MIN_NON_HERO_UNITS
			and army_center != Vector3.ZERO
			and is_hero_healthy_enough_for_wave(hero)
			and horizontal_distance(hero.global_position, army_center)
			<= HERO_MAX_DISTANCE_FROM_ARMY
			and horizontal_distance(hero.global_position, rally_position)
			<= WAVE_REGROUP_MAX_DISTANCE + 6.0
		):
			wave_units.append(hero)

	return {
		"units": wave_units,
		"can_launch": can_launch,
		"non_hero_count": regrouped_non_hero.size(),
		"total_non_hero_count": non_hero_units.size(),
	}


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
			and non_hero_units.size() >= MIN_NON_HERO_FOR_HERO_JOIN
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


static func build_creep_army(tree: SceneTree) -> Dictionary:
	var non_hero_units: Array = collect_living_non_hero_combat_units(tree)
	var can_launch: bool = non_hero_units.size() >= MIN_NON_HERO_FOR_HERO_JOIN
	var creep_units: Array = non_hero_units.duplicate()

	if can_launch:
		var hero: Hero = find_living_enemy_hero(tree)
		var army_center: Vector3 = compute_army_center(non_hero_units)
		if (
			hero != null
			and army_center != Vector3.ZERO
			and is_living_combat_unit(hero)
			and horizontal_distance(hero.global_position, army_center)
			<= HERO_MAX_DISTANCE_FROM_ARMY
		):
			creep_units.append(hero)

	return {
		"units": creep_units,
		"can_launch": can_launch,
		"non_hero_count": non_hero_units.size(),
	}


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
			&"base"
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
	var defender_power: int = estimate_military_power(defense_army)
	var threat_power: int = estimate_player_threat_power_near(
		tree,
		threat_position,
		DEFENSE_THREAT_POWER_RANGE
	)

	return {
		"defender_power": defender_power,
		"threat_power": threat_power,
		"can_commit": should_defense_commit_attack(defense_army, defender_power, threat_power),
	}


static func should_defense_commit_attack(
	defense_army: Array,
	defender_power: int,
	_threat_power: int
) -> bool:
	if defense_army.is_empty():
		return false

	# Always engage with the full gathered army; only pause if there is no army to send.
	if defender_power <= 0:
		return false

	return true


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
		if unit is Archer:
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


static func resolve_wave_attack_destination(tree: SceneTree, enemy_base_position: Vector3) -> Vector3:
	var nearby_military: Node3D = _find_player_military_near_position(
		tree,
		enemy_base_position,
		BASE_THREAT_DETECTION_RANGE
	)
	if nearby_military != null:
		return nearby_military.global_position

	var command_center: CommandCenter = _resolve_living_player_command_center(tree)
	if command_center != null:
		return command_center.global_position

	var nearest_building: Node3D = _find_nearest_living_player_building(
		tree,
		enemy_base_position
	)
	if nearest_building != null:
		return nearest_building.global_position

	var nearest_unit: Node3D = _find_nearest_living_player_unit(tree, enemy_base_position)
	if nearest_unit != null:
		return nearest_unit.global_position

	return enemy_base_position


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
		elif unit is Archer:
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
		elif unit is Archer:
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
		elif unit is Archer:
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

	if not (node is Swordsman or node is Archer or node is Hero):
		return false

	return _has_positive_health(node)


static func _resolve_living_player_command_center(tree: SceneTree) -> CommandCenter:
	for node: Node in tree.get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_building(node as Building):
			return node as CommandCenter

	return null


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
