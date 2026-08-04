class_name MilitaryDirectorV2
extends Node

## Sole strategic decision-maker for the main army under Military AI V2.
## Owns exactly one active state and publishes the current ArmyMissionV2.
## Owns the authoritative army roster and main-squad membership.
## Does not issue unit orders — ArmyCommanderV2 executes the mission.
##
## Foundation + roster task: stays IDLE strategically. Advanced creep/attack/defend
## behavior is not migrated yet. Squad membership still refreshes while V2 is enabled.

enum State {
	IDLE,
	ASSEMBLE,
	CREEP,
	ATTACK,
	DEFEND,
	RETREAT,
	RECOVER,
}

const TICK_SECONDS: float = 1.0

var _state: State = State.IDLE
var _mission: ArmyMissionV2 = null
var _last_transition_reason: String = "match start"
var _match_start_msec: int = 0
var _tick_timer: float = 0.0
var _commander: ArmyCommanderV2 = null

## Authoritative living AI military roster (validated refs only).
var _roster: Array = []
## Newly trained / discovered units waiting for a safe admission window.
var _pending_reinforcements: Array = []
## Single main squad. Commander receives this; it must not recruit independently.
var _main_squad: ArmySquadV2 = ArmySquadV2.new()
## instance_id -> true for units with lifecycle hooks connected.
var _lifecycle_bound: Dictionary = {}
var _assemble_rally_point: Vector3 = Vector3.ZERO
var _assemble_rally_base_id: int = 0


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_tick_timer = TICK_SECONDS * 0.25
	_commander = get_parent().get_node_or_null("ArmyCommanderV2") as ArmyCommanderV2
	reset_match_state()
	set_process(MilitaryAIConfig.is_v2_enabled())
	_publish_perf_status()


func reset_match_state() -> void:
	_state = State.IDLE
	_last_transition_reason = "match start"
	_mission = ArmyMissionV2.new(
		ArmyMissionV2.MissionType.IDLE,
		Vector3.ZERO,
		null,
		0,
		_last_transition_reason
	)
	_tick_timer = TICK_SECONDS * 0.25
	_clear_roster_state()
	_publish_perf_status()


func _clear_roster_state() -> void:
	_roster.clear()
	_pending_reinforcements.clear()
	_main_squad.clear()
	_lifecycle_bound.clear()
	_assemble_rally_point = Vector3.ZERO
	_assemble_rally_base_id = 0


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		set_process(false)
		return

	_tick_timer += delta
	if _tick_timer < TICK_SECONDS:
		return

	_tick_timer = 0.0
	_refresh_army_roster()
	_evaluate_strategy()
	_publish_perf_status()
	PerfCounters.record_ai_decision_update()


func _evaluate_strategy() -> void:
	if _mission == null:
		_transition_to(State.ASSEMBLE, "initialize assemble mission")
		return

	_mission.sanitize_target_object()
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var rally_point: Vector3 = get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		_transition_to(State.IDLE, "awaiting safe rally point")
		return

	var defend_threat: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(tree)
	if defend_threat.get("threatened", false):
		var intercept: Vector3 = defend_threat.get("intercept_position", rally_point) as Vector3
		_transition_to(State.DEFEND, "emergency base defense", intercept, null, 100)
		return

	var creep_manager: EnemyCreepManager = _resolve_creep_manager()
	var has_safe_camp: bool = (
		creep_manager != null
		and _main_squad.hero_present
		and get_military_unit_count() >= MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS
		and creep_manager.has_safe_creep_camp_available()
	)
	if has_safe_camp:
		_transition_to(State.CREEP, "creep-ready squad assembled", rally_point)
		return

	_transition_to(State.ASSEMBLE, "gathering squad at base", rally_point)


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return state_to_string(_state)


static func state_to_string(state: State) -> String:
	match state:
		State.IDLE:
			return "IDLE"
		State.ASSEMBLE:
			return "ASSEMBLE"
		State.CREEP:
			return "CREEP"
		State.ATTACK:
			return "ATTACK"
		State.DEFEND:
			return "DEFEND"
		State.RETREAT:
			return "RETREAT"
		State.RECOVER:
			return "RECOVER"
		_:
			return "UNKNOWN"


func get_mission() -> ArmyMissionV2:
	return _mission


func get_last_transition_reason() -> String:
	return _last_transition_reason


func get_match_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func get_main_squad() -> ArmySquadV2:
	return _main_squad


func get_roster_copy() -> Array:
	return _roster.duplicate()


func get_pending_reinforcements_copy() -> Array:
	return _pending_reinforcements.duplicate()


func get_military_unit_count() -> int:
	return maxi(0, _main_squad.get_size() - (1 if _main_squad.hero_present else 0))


func is_creep_ready() -> bool:
	return _main_squad.hero_present and get_military_unit_count() >= MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS


func is_attack_ready_placeholder() -> bool:
	return _main_squad.hero_present and get_military_unit_count() >= MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS


func get_assemble_rally_point() -> Vector3:
	var tree: SceneTree = get_tree()
	if tree == null:
		return Vector3.ZERO

	var base: CommandCenter = _find_primary_enemy_base(tree)
	if base == null:
		return Vector3.ZERO

	var base_id: int = base.get_instance_id()
	if _assemble_rally_point != Vector3.ZERO and _assemble_rally_base_id == base_id:
		if _is_safe_assemble_rally_candidate(tree, base, _assemble_rally_point):
			return _assemble_rally_point

	_assemble_rally_point = _find_best_assemble_rally_point(tree, base)
	_assemble_rally_base_id = base_id
	return _assemble_rally_point


func get_assemble_forward_hint() -> Vector3:
	var tree: SceneTree = get_tree()
	if tree == null:
		return Vector3.ZERO
	var base: CommandCenter = _find_primary_enemy_base(tree)
	if base == null:
		return Vector3.ZERO
	var rally_point: Vector3 = get_assemble_rally_point()
	if rally_point == Vector3.ZERO:
		return Vector3.ZERO
	var forward: Vector3 = rally_point - base.global_position
	forward.y = 0.0
	if forward.length_squared() <= 0.01:
		return Vector3.ZERO
	return forward.normalized()


## Strategic API for future behavior / tests. Commander must not call this for self-decisions.
func request_state(
	next_state: State,
	reason: String,
	target_position: Vector3 = Vector3.ZERO,
	target_object: Node3D = null,
	priority: int = 0
) -> bool:
	if not MilitaryAIConfig.is_v2_enabled():
		return false
	return _transition_to(next_state, reason, target_position, target_object, priority)


func _transition_to(
	next_state: State,
	reason: String,
	target_position: Vector3 = Vector3.ZERO,
	target_object: Node3D = null,
	priority: int = 0
) -> bool:
	var previous_state: State = _state
	if _state == next_state and _mission != null and _mission.mission_type == _state_to_mission_type(next_state):
		if reason != _last_transition_reason and not reason.is_empty():
			_last_transition_reason = reason
			_mission.transition_reason = reason
		return false

	if _mission != null and _state != next_state:
		_mission.mark_cancelled("superseded: %s" % reason)

	_state = next_state
	_last_transition_reason = reason if not reason.is_empty() else "unspecified"
	_mission = ArmyMissionV2.new(
		_state_to_mission_type(next_state),
		target_position,
		target_object,
		priority,
		_last_transition_reason
	)

	## Safe admission window: join reinforcements on state transitions into idle/assemble/recover.
	if previous_state != next_state and _can_admit_reinforcements():
		_admit_pending_reinforcements()

	_publish_perf_status()
	return true


func _state_to_mission_type(state: State) -> ArmyMissionV2.MissionType:
	match state:
		State.IDLE:
			return ArmyMissionV2.MissionType.IDLE
		State.ASSEMBLE:
			return ArmyMissionV2.MissionType.ASSEMBLE
		State.CREEP:
			return ArmyMissionV2.MissionType.CREEP
		State.ATTACK:
			return ArmyMissionV2.MissionType.ATTACK
		State.DEFEND:
			return ArmyMissionV2.MissionType.DEFEND
		State.RETREAT:
			return ArmyMissionV2.MissionType.RETREAT
		State.RECOVER:
			return ArmyMissionV2.MissionType.RECOVER
		_:
			return ArmyMissionV2.MissionType.NONE


## True while assembling / recovering / idle — never mid-fight reshuffles.
func _can_admit_reinforcements() -> bool:
	return _state in [State.IDLE, State.ASSEMBLE, State.RECOVER]


func _refresh_army_roster() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	## Purge dead/freed immediately from squad + pending, then rescan living military.
	_main_squad.sanitize()
	_sanitize_pending_reinforcements()

	var living: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	var next_roster: Array = []
	var seen_ids: Dictionary = {}

	for entry: Variant in living:
		if not ArmySquadV2.is_roster_eligible(entry as Node):
			continue
		var unit: Node = entry as Node
		var unit_id: int = unit.get_instance_id()
		if seen_ids.has(unit_id):
			continue
		seen_ids[unit_id] = true
		next_roster.append(unit)
		_bind_unit_lifecycle(unit)

		if _main_squad.has_member(unit):
			continue
		if _pending_contains(unit):
			continue
		## Newly trained / discovered living units wait for a safe join window.
		## Never send them alone across the map as a solo field group.
		_pending_reinforcements.append(unit)

	_roster = next_roster

	## Drop squad members that are no longer on the living roster.
	for member_variant: Variant in _main_squad.get_members_copy():
		if not NodeSafety.is_alive_node(member_variant):
			_main_squad.remove_member(member_variant as Node)
			continue
		var member: Node = member_variant as Node
		if not seen_ids.has(member.get_instance_id()):
			_main_squad.remove_member(member)

	if _can_admit_reinforcements():
		_admit_pending_reinforcements()

	_main_squad.recompute_metrics()


func _admit_pending_reinforcements() -> void:
	if _pending_reinforcements.is_empty():
		return

	var remaining: Array = []
	for entry: Variant in _pending_reinforcements:
		if not ArmySquadV2.is_roster_eligible(entry as Node):
			continue
		var unit: Node = entry as Node
		if _main_squad.has_member(unit):
			continue
		var role: ArmySquadV2.UnitRole = ArmySquadV2.classify_role(unit)
		if not _main_squad.try_add_member(unit, role):
			remaining.append(unit)
			continue
		_bind_unit_lifecycle(unit)
	_pending_reinforcements = remaining


func _sanitize_pending_reinforcements() -> void:
	var cleaned: Array = []
	var seen_ids: Dictionary = {}
	for entry: Variant in _pending_reinforcements:
		if not ArmySquadV2.is_roster_eligible(entry as Node):
			continue
		var unit: Node = entry as Node
		var unit_id: int = unit.get_instance_id()
		if seen_ids.has(unit_id):
			continue
		if _main_squad.has_member(unit):
			continue
		seen_ids[unit_id] = true
		cleaned.append(unit)
	_pending_reinforcements = cleaned


func _pending_contains(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var unit_id: int = unit.get_instance_id()
	for entry: Variant in _pending_reinforcements:
		if NodeSafety.is_alive_node(entry) and (entry as Node).get_instance_id() == unit_id:
			return true
	return false


func _bind_unit_lifecycle(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var unit_id: int = unit.get_instance_id()
	if _lifecycle_bound.has(unit_id):
		return
	_lifecycle_bound[unit_id] = true

	if unit.has_signal("died") and not unit.died.is_connected(_on_roster_unit_died):
		unit.died.connect(_on_roster_unit_died, CONNECT_ONE_SHOT)
	if not unit.tree_exiting.is_connected(_on_roster_unit_tree_exiting):
		unit.tree_exiting.connect(_on_roster_unit_tree_exiting.bind(unit_id), CONNECT_ONE_SHOT)


func _on_roster_unit_died(unit: Unit) -> void:
	_remove_unit_everywhere(unit)


func _on_roster_unit_tree_exiting(unit_id: int) -> void:
	_remove_unit_everywhere_by_id(unit_id)


func _remove_unit_everywhere(unit: Node) -> void:
	if unit == null:
		return
	var unit_id: int = 0
	if is_instance_valid(unit):
		unit_id = unit.get_instance_id()
	_main_squad.remove_member(unit)
	_remove_from_array_by_ref(_roster, unit)
	_remove_from_array_by_ref(_pending_reinforcements, unit)
	if unit_id != 0:
		_lifecycle_bound.erase(unit_id)
		_main_squad.remove_by_instance_id(unit_id)
	_main_squad.recompute_metrics()
	_publish_perf_status()


func _remove_unit_everywhere_by_id(unit_id: int) -> void:
	if unit_id == 0:
		return
	_main_squad.remove_by_instance_id(unit_id)
	_remove_from_array_by_id(_roster, unit_id)
	_remove_from_array_by_id(_pending_reinforcements, unit_id)
	_lifecycle_bound.erase(unit_id)
	_main_squad.recompute_metrics()
	_publish_perf_status()


func _remove_from_array_by_ref(arr: Array, unit: Node) -> void:
	for i: int in range(arr.size() - 1, -1, -1):
		var entry: Variant = arr[i]
		if entry == null or not is_instance_valid(entry) or entry == unit:
			arr.remove_at(i)


func _remove_from_array_by_id(arr: Array, unit_id: int) -> void:
	for i: int in range(arr.size() - 1, -1, -1):
		var entry: Variant = arr[i]
		if entry == null or not is_instance_valid(entry) or (entry as Node).get_instance_id() == unit_id:
			arr.remove_at(i)


## Test helper: run one roster refresh without enabling the feature toggle.
func debug_refresh_roster_for_tests() -> void:
	_refresh_army_roster()


## Test helper: admit pending while pretending we are in a safe state.
## Uses the lightweight alive/type gate so stub nodes can exercise membership.
func debug_admit_pending_for_tests() -> void:
	var remaining: Array = []
	for entry: Variant in _pending_reinforcements:
		if not NodeSafety.is_alive_node(entry):
			continue
		var unit: Node = entry as Node
		if not unit.is_inside_tree():
			continue
		if unit is Worker or unit is Building or unit is NeutralCreep:
			continue
		if _main_squad.has_member(unit):
			continue
		var role: ArmySquadV2.UnitRole = ArmySquadV2.classify_role(unit)
		if not _main_squad.try_add_member(unit, role):
			remaining.append(unit)
			continue
		_bind_unit_lifecycle(unit)
	_pending_reinforcements = remaining
	_main_squad.recompute_metrics()


## Test helper: enqueue a living unit as a pending reinforcement (director-owned path).
func debug_enqueue_pending_for_tests(unit: Node) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	if unit is Worker or unit is Building or unit is NeutralCreep:
		return false
	if _main_squad.has_member(unit) or _pending_contains(unit):
		return false
	_pending_reinforcements.append(unit)
	_bind_unit_lifecycle(unit)
	return true


func debug_score_assemble_rally_candidate(candidate: Vector3) -> float:
	var tree: SceneTree = get_tree()
	if tree == null:
		return -INF
	var base: CommandCenter = _find_primary_enemy_base(tree)
	if base == null:
		return -INF
	return _score_assemble_rally_candidate(tree, base, candidate)


func _resolve_creep_manager() -> EnemyCreepManager:
	if get_parent() == null:
		return null
	return get_parent().get_node_or_null("EnemyCreepManager") as EnemyCreepManager


func _find_primary_enemy_base(tree: SceneTree) -> CommandCenter:
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if node is CommandCenter and NodeSafety.is_alive_node(node):
			return node as CommandCenter
	return null


func _find_best_assemble_rally_point(tree: SceneTree, base: CommandCenter) -> Vector3:
	var base_position: Vector3 = base.global_position
	var preferred: Vector3 = base_position + EnemyArmyCommand.ARMY_RALLY_OFFSET
	var base_to_preferred: Vector3 = preferred - base_position
	base_to_preferred.y = 0.0
	var preferred_dir: Vector3 = (
		base_to_preferred.normalized() if base_to_preferred.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
	)

	var candidate_dirs: Array[Vector3] = [
		preferred_dir,
		(preferred_dir + Vector3.RIGHT * 0.55).normalized(),
		(preferred_dir - Vector3.RIGHT * 0.55).normalized(),
		(preferred_dir + Vector3.FORWARD * 0.55).normalized(),
		(preferred_dir - Vector3.FORWARD * 0.55).normalized(),
		Vector3.RIGHT,
		-Vector3.RIGHT,
		Vector3.FORWARD,
		-Vector3.FORWARD,
	]
	var radii: Array[float] = [
		MilitaryAIConfig.V2_ASSEMBLE_RALLY_MIN_RADIUS,
		10.0,
		12.0,
		MilitaryAIConfig.V2_ASSEMBLE_RALLY_MAX_RADIUS,
	]

	var best_candidate: Vector3 = Vector3.ZERO
	var best_score: float = -INF
	for radius: float in radii:
		for dir: Vector3 in candidate_dirs:
			if dir.length_squared() < 0.01:
				continue
			var candidate: Vector3 = base_position + dir.normalized() * radius
			candidate.y = base_position.y
			var score: float = _score_assemble_rally_candidate(tree, base, candidate)
			if score > best_score:
				best_score = score
				best_candidate = candidate

	return best_candidate


func _score_assemble_rally_candidate(
	tree: SceneTree,
	base: CommandCenter,
	candidate: Vector3
) -> float:
	if not _is_safe_assemble_rally_candidate(tree, base, candidate):
		return -INF

	var base_position: Vector3 = base.global_position
	var preferred: Vector3 = base_position + EnemyArmyCommand.ARMY_RALLY_OFFSET
	var score: float = 1000.0
	score -= EnemyArmyCommand.horizontal_distance(candidate, preferred) * 4.0
	score -= EnemyArmyCommand.horizontal_distance(candidate, base_position) * 1.5

	for building: Building in _collect_enemy_buildings(tree):
		score += minf(
			EnemyArmyCommand.horizontal_distance(candidate, building.global_position),
			8.0
		)
	if ConstructionReservations.overlaps_reserved_footprint(candidate, Vector2(3.0, 3.0)):
		score -= 200.0
	return score


func _is_safe_assemble_rally_candidate(
	tree: SceneTree,
	base: CommandCenter,
	candidate: Vector3
) -> bool:
	if candidate == Vector3.ZERO:
		return false

	var distance_from_base: float = EnemyArmyCommand.horizontal_distance(candidate, base.global_position)
	if (
		distance_from_base < MilitaryAIConfig.V2_ASSEMBLE_RALLY_MIN_RADIUS
		or distance_from_base > MilitaryAIConfig.V2_ASSEMBLE_RALLY_MAX_RADIUS
	):
		return false

	if ConstructionReservations.overlaps_reserved_footprint(candidate, Vector2(3.0, 3.0)):
		return false

	for building: Building in _collect_enemy_buildings(tree):
		if not NodeSafety.is_alive_node(building):
			continue
		if building.is_position_inside_footprint(candidate, 2.0):
			return false
		if EnemyArmyCommand.horizontal_distance(candidate, building.global_position) <= 3.5:
			return false
		if building.is_being_constructed():
			for point: Vector3 in building.get_construction_points():
				if EnemyArmyCommand.horizontal_distance(candidate, point) <= 2.5:
					return false
			if EnemyArmyCommand.horizontal_distance(candidate, building.global_position) <= 5.0:
				return false
		for exit_point: Vector3 in _get_building_exit_points(building):
			if EnemyArmyCommand.horizontal_distance(candidate, exit_point) <= MilitaryAIConfig.V2_ASSEMBLE_PRODUCTION_EXIT_CLEARANCE:
				return false
			if _candidate_near_worker_route(building.global_position, exit_point, candidate, 2.0):
				return false

	for worker: Worker in _collect_enemy_workers(tree):
		if not NodeSafety.is_alive_node(worker):
			continue
		if EnemyArmyCommand.horizontal_distance(candidate, worker.global_position) <= 3.0:
			return false
		if worker.is_on_construction_trip():
			continue
		if _candidate_near_worker_route(base.global_position, worker.global_position, candidate, 2.2):
			return false
		var gather_source: GatherableResource = worker.get("_gather_source") as GatherableResource
		if gather_source != null and is_instance_valid(gather_source):
			if _candidate_near_worker_route(base.global_position, gather_source.global_position, candidate, 2.6):
				return false
			if EnemyArmyCommand.horizontal_distance(candidate, gather_source.global_position) <= 4.0:
				return false

	for node: Node in tree.get_nodes_in_group(GatherableResource.GROUP_ENEMY_RESOURCES):
		if not (node is GatherableResource) or not NodeSafety.is_alive_node(node):
			continue
		var resource: GatherableResource = node as GatherableResource
		if resource.get_resource_id() != &"gold":
			continue
		if EnemyArmyCommand.horizontal_distance(candidate, resource.global_position) <= 4.0:
			return false
		if _candidate_near_worker_route(base.global_position, resource.global_position, candidate, 2.8):
			return false

	return true


func _collect_enemy_buildings(tree: SceneTree) -> Array[Building]:
	var buildings: Array[Building] = []
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if node is Building and NodeSafety.is_alive_node(node):
			buildings.append(node as Building)
	var scene_root: Node = tree.current_scene
	if scene_root == null:
		return buildings
	for node_variant: Variant in scene_root.find_children("*", "", true, false):
		if not node_variant is Building or not NodeSafety.is_alive_node(node_variant):
			continue
		var building: Building = node_variant as Building
		if building.team_id == 1 and not buildings.has(building):
			buildings.append(building)
	return buildings


func _collect_enemy_workers(tree: SceneTree) -> Array[Worker]:
	var workers: Array[Worker] = []
	for node: Node in tree.get_nodes_in_group(&"enemy_workers"):
		if node is Worker and NodeSafety.is_alive_node(node):
			workers.append(node as Worker)
	return workers


func _candidate_near_worker_route(
	from_position: Vector3,
	to_position: Vector3,
	candidate: Vector3,
	clearance: float
) -> bool:
	var route: Vector2 = Vector2(to_position.x - from_position.x, to_position.z - from_position.z)
	var length_sq: float = route.length_squared()
	if length_sq <= 0.01:
		return false
	var rel: Vector2 = Vector2(candidate.x - from_position.x, candidate.z - from_position.z)
	var t: float = clampf(rel.dot(route) / length_sq, 0.0, 1.0)
	var closest: Vector2 = Vector2(from_position.x, from_position.z) + route * t
	return Vector2(candidate.x, candidate.z).distance_to(closest) <= clearance


func _get_building_exit_points(building: Building) -> Array[Vector3]:
	var exit_points: Array[Vector3] = []
	if building == null or not is_instance_valid(building):
		return exit_points

	for property_name: StringName in [
		&"worker_spawn_offset",
		&"spearman_spawn_offset",
		&"swordsman_spawn_offset",
		&"archer_spawn_offset",
		&"heavy_cavalry_spawn_offset",
		&"light_cavalry_spawn_offset",
		&"cavalry_archer_spawn_offset",
		&"cannon_spawn_offset",
	]:
		var local_offset: Variant = building.get(property_name)
		if not (local_offset is Vector3):
			continue
		exit_points.append(_building_local_offset_to_world(building, local_offset as Vector3))
	return exit_points


func _building_local_offset_to_world(building: Building, local_offset: Vector3) -> Vector3:
	var world_offset: Vector3 = building.global_transform.basis * local_offset
	return Vector3(
		building.global_position.x + world_offset.x,
		building.global_position.y,
		building.global_position.z + world_offset.z
	)


func _publish_perf_status() -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		return

	var mission: ArmyMissionV2 = _mission
	var mission_name: String = "-"
	var objective: String = "-"
	var age_seconds: float = 0.0
	if mission != null:
		mission.sanitize_target_object()
		mission_name = mission.get_mission_type_name()
		objective = mission.get_objective_label()
		age_seconds = mission.get_age_seconds()

	PerfCounters.set_military_ai_v2_status(
		MilitaryAIConfig.ai_version_label(),
		get_state_name(),
		mission_name,
		objective,
		age_seconds,
		_last_transition_reason
	)
	PerfCounters.set_military_ai_v2_squad_status(
		_main_squad.get_size(),
		_main_squad.hero_present,
		_main_squad.get_role_counts_label(),
		_main_squad.estimated_army_value
	)
	## Keep legacy AI status fields filled so older overlay lines stay coherent under V2.
	PerfCounters.set_ai_status(get_state_name(), mission_name, "MilitaryDirectorV2")
	PerfCounters.set_ai_mission_detail(
		"V2 %s → %s (%s)" % [get_state_name(), objective, _last_transition_reason]
	)
	PerfCounters.set_combat_group_size(_main_squad.get_size())
