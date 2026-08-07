extends Node

## WC3-like player movement: validated shared route → follow waypoints → arrive → stop.
## No formations, corridor offsets, follow-the-leader, or continuous retarget loops.
## Ownership is instance-ID + command-generation only.

const WAYPOINT_PASS_DISTANCE := 4.5
const FINAL_APPROACH_RADIUS := 6.0
const ROUTE_SNAP_ACCEPT_DISTANCE := 8.0
const ROUTE_ON_MESH_TOLERANCE := 0.45
const ROUTE_SEGMENT_SAMPLE_STEP := 1.25
const UNIT_NAV_RADIUS := 0.55
const ROUTE_SAFETY_MARGIN := 0.35
const ROUTE_CLEARANCE := UNIT_NAV_RADIUS + ROUTE_SAFETY_MARGIN
const FINAL_SLOT_SPACING := 1.6
const ROUTE_FALLBACK_RING_STEPS := 8
const ROUTE_FALLBACK_RING_COUNT := 4
const ROUTE_FALLBACK_RING_RADIUS := 2.5
const TICK_INTERVAL := 0.2
const STUCK_CONFIRM_SECONDS := 2.75
const STUCK_PROGRESS_EPSILON := 0.4

var _routes: Dictionary = {} ## route_id -> PlayerRoute
var _unit_to_route: Dictionary = {} ## unit_instance_id -> route_id
var _unit_exit_handlers: Dictionary = {} ## unit_instance_id -> Callable
var _next_route_id: int = 1
var _global_command_generation: int = 0
var _tick_accum: float = 0.0
var _player_diag: Dictionary = {}


func _ready() -> void:
	MatchSession.register_match_reset(&"PlayerRouteNavigation", clear_all)
	_reset_telemetry()
	set_process(true)


func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	_tick_accum = 0.0
	_tick_routes()


func clear_all() -> void:
	for unit_id: Variant in _unit_exit_handlers.keys():
		_disconnect_unit_exit_handler(int(unit_id))
	_unit_exit_handlers.clear()
	_routes.clear()
	_unit_to_route.clear()
	_next_route_id = 1
	_global_command_generation = 0
	_tick_accum = 0.0
	_reset_telemetry()


func reset_player_move_telemetry() -> void:
	_reset_telemetry()


func get_player_move_telemetry() -> Dictionary:
	return _player_diag.duplicate()


func are_player_formations_disabled() -> bool:
	## Formations permanently bypassed for player Move / Attack-Move.
	return true


func get_route_for_unit(unit: Variant) -> PlayerRoute:
	if unit == null or not is_instance_valid(unit) or not (unit is Node):
		return null
	var route_id: int = int(_unit_to_route.get((unit as Node).get_instance_id(), -1))
	if route_id < 0:
		return null
	return _routes.get(route_id) as PlayerRoute


func release_unit(unit: Variant) -> void:
	if unit == null or not is_instance_valid(unit) or not (unit is Node):
		return
	var unit_id: int = (unit as Node).get_instance_id()
	if unit is Unit:
		(unit as Unit).clear_player_route_command()
	_remove_unit_by_id(unit_id)


## Immediately detach a unit from any prior group route. Mandatory for individual re-command.
func detach_unit_from_group_state(unit: Variant) -> void:
	release_unit(unit)


func get_active_route_count() -> int:
	return _routes.size()


func issue_command(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	queued: bool = false
) -> Dictionary:
	var result: Dictionary = {
		"handled": false,
		"route_valid": false,
		"accepted_destination": destination,
		"failure_reason": "",
	}
	var ordered: Array = _filter_and_order_units(units)
	if ordered.is_empty() or destination == Vector3.ZERO:
		result["failure_reason"] = "no_units_or_destination"
		return result

	## Shift-queued: store destinations only — do not start a live shared route yet.
	if queued:
		result["handled"] = true
		result["route_valid"] = true
		for unit_variant: Variant in ordered:
			if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
				continue
			_issue_ground_order(unit_variant as Unit, destination, order_kind, true)
		return result

	var workers: Array = []
	var military: Array = []
	_partition_units(ordered, workers, military)

	_global_command_generation += 1
	var generation: int = _global_command_generation
	_reset_telemetry()
	_player_diag["command_generation"] = generation
	_player_diag["clicked_position"] = destination

	var accepted: Vector3 = destination
	var any_ok := false
	var failure_reason := ""

	## Workers / utility: individual NavigationAgent paths. Reliability over squad routing.
	if not workers.is_empty():
		var worker_result: Dictionary = _issue_individual_commands(
			workers, destination, order_kind, generation
		)
		if bool(worker_result.get("handled", false)):
			any_ok = true
			accepted = worker_result.get("accepted_destination", accepted) as Vector3
		else:
			failure_reason = String(worker_result.get("failure_reason", "invalid_worker_route"))

	## Military: one validated shared strategic corridor; members follow the same waypoints.
	if not military.is_empty():
		var military_result: Dictionary = _issue_shared_military_command(
			military, destination, order_kind, generation
		)
		if bool(military_result.get("handled", false)):
			any_ok = true
			accepted = military_result.get("accepted_destination", accepted) as Vector3
		else:
			if failure_reason.is_empty():
				failure_reason = String(
					military_result.get("failure_reason", "invalid_military_route")
				)

	if not any_ok:
		result["failure_reason"] = failure_reason if not failure_reason.is_empty() else "invalid_route"
		_player_diag["route_failures"] = int(_player_diag.get("route_failures", 0)) + 1
		push_warning(
			"PlayerRouteNavigation: refused move — %s"
			% result["failure_reason"]
		)
		return result

	result["handled"] = true
	result["route_valid"] = true
	result["accepted_destination"] = accepted
	_player_diag["accepted_destination"] = accepted
	return result


## True while a unit follows intermediate shared-route waypoints (not worker/final settle).
func is_following_shared_corridor(unit: Variant) -> bool:
	var route: PlayerRoute = get_route_for_unit(unit)
	if route == null or not route.route_valid or route.waypoints.size() < 2:
		return false
	if unit == null or not is_instance_valid(unit) or not unit is Unit:
		return false
	var typed: Unit = unit as Unit
	if not typed.matches_player_route_command(route.command_generation):
		return false
	var unit_id: int = typed.get_instance_id()
	var index: int = route.get_waypoint_index(unit_id)
	var last_index: int = route.waypoints.size() - 1
	if index < last_index:
		return true
	var travel: Vector3 = _desired_travel_target(route, unit_id)
	var final_dest: Vector3 = route.get_final_destination(unit_id)
	return _horizontal_distance(travel, final_dest) > 0.5


## Current authoritative travel point for a bound unit (waypoint or frozen final).
func resolve_travel_target(unit: Variant) -> Vector3:
	var route: PlayerRoute = get_route_for_unit(unit)
	if route == null or not route.route_valid:
		return Vector3.ZERO
	if unit == null or not is_instance_valid(unit) or not unit is Unit:
		return Vector3.ZERO
	var typed: Unit = unit as Unit
	if not typed.matches_player_route_command(route.command_generation):
		return Vector3.ZERO
	return _desired_travel_target(route, typed.get_instance_id())


## Advance personal waypoint when the unit reaches / passes the current guide.
## Returns true when a new travel target should be applied.
func advance_unit_waypoint(unit: Variant) -> bool:
	var route: PlayerRoute = get_route_for_unit(unit)
	if route == null or not route.route_valid or route.waypoints.is_empty():
		return false
	if unit == null or not is_instance_valid(unit) or not unit is Unit:
		return false
	var typed: Unit = unit as Unit
	if not typed.matches_player_route_command(route.command_generation):
		return false

	var unit_id: int = typed.get_instance_id()
	var index: int = route.get_waypoint_index(unit_id)
	var last_index: int = route.waypoints.size() - 1
	var advanced := false
	while index < last_index:
		var waypoint: Vector3 = route.waypoints[index]
		if not _unit_reached_or_passed_waypoint(typed, route, waypoint, index):
			break
		route.note_passed_waypoint(unit_id, index)
		index += 1
		advanced = true
	if index >= last_index:
		var last_wp: Vector3 = route.waypoints[last_index]
		if _unit_reached_or_passed_waypoint(typed, route, last_wp, last_index):
			route.note_passed_waypoint(unit_id, last_index)
	route.set_waypoint_index(unit_id, index)
	typed.set_player_route_waypoint_index(index)
	return advanced


## ONE stuck recovery: re-enter the same validated route. Never regenerates formation/route.
func recover_stuck_unit(unit: Variant) -> bool:
	var route: PlayerRoute = get_route_for_unit(unit)
	if route == null or not route.route_valid:
		return false
	if unit == null or not is_instance_valid(unit) or not unit is Unit:
		return false
	var typed: Unit = unit as Unit
	var generation: int = route.command_generation
	if not typed.matches_player_route_command(generation):
		_player_diag["stale_callback_blocks"] = int(_player_diag.get("stale_callback_blocks", 0)) + 1
		return false

	var unit_id: int = typed.get_instance_id()
	var rejoin: Vector3 = _compute_route_rejoin_point(route, typed)
	if rejoin.length_squared() < 0.0001:
		rejoin = _desired_travel_target(route, unit_id)
	if rejoin.length_squared() < 0.0001:
		return false

	_player_diag["stall_recovery_count"] = int(_player_diag.get("stall_recovery_count", 0)) + 1
	typed.request_route_travel_target(
		rejoin,
		route.get_final_destination(unit_id),
		Unit.RepathUrgency.STUCK_RECOVERY
	)
	return true


func get_stuck_confirm_seconds() -> float:
	return STUCK_CONFIRM_SECONDS


func unit_has_passed_current_guide(unit: Variant) -> bool:
	var route: PlayerRoute = get_route_for_unit(unit)
	if route == null or route.waypoints.is_empty():
		return false
	if unit == null or not is_instance_valid(unit) or not unit is Unit:
		return false
	var typed: Unit = unit as Unit
	if not typed.matches_player_route_command(route.command_generation):
		return false
	var unit_id: int = typed.get_instance_id()
	var index: int = route.get_waypoint_index(unit_id)
	index = clampi(index, 0, route.waypoints.size() - 1)
	return _unit_reached_or_passed_waypoint(typed, route, route.waypoints[index], index)


func is_unit_on_active_route(unit: Variant) -> bool:
	var route: PlayerRoute = get_route_for_unit(unit)
	if route == null or not route.route_valid:
		return false
	if unit == null or not is_instance_valid(unit) or not unit is Unit:
		return false
	return (unit as Unit).matches_player_route_command(route.command_generation)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _partition_units(ordered: Array, workers_out: Array, military_out: Array) -> void:
	workers_out.clear()
	military_out.clear()
	for unit_variant: Variant in ordered:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		## Workers and non-combat utility units: individual paths.
		if unit is Worker or not unit.supports_combat_orders():
			workers_out.append(unit)
		else:
			military_out.append(unit)


## Workers: stable finals once, each unit pathfinds alone. No shared corridor.
func _issue_individual_commands(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	generation: int
) -> Dictionary:
	var result: Dictionary = {
		"handled": false,
		"accepted_destination": destination,
		"failure_reason": "",
	}
	var nav_map: RID = _resolve_nav_map(units)
	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		result["failure_reason"] = "nav_map_inactive"
		return result

	var accepted: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, destination)
	if _horizontal_distance(destination, accepted) > ROUTE_SNAP_ACCEPT_DISTANCE:
		var origin: Vector3 = _compute_group_origin(units)
		var from: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, origin)
		var nearest: Vector3 = _find_nearest_reachable_destination(nav_map, from, destination)
		if nearest == Vector3.ZERO:
			result["failure_reason"] = "destination_not_on_navigation"
			return result
		accepted = nearest

	## Detach prior group/corridor ownership before binding the new generation.
	for unit_variant: Variant in units:
		if NodeSafety.is_alive_node(unit_variant) and unit_variant is Unit:
			detach_unit_from_group_state(unit_variant)

	var route := PlayerRoute.new()
	route.route_id = _next_route_id
	_next_route_id += 1
	route.command_generation = generation
	route.order_kind = order_kind
	route.use_attack_move = order_kind == &"attack_move"
	route.clicked_destination = destination
	route.accepted_destination = accepted
	## Empty waypoints → each unit travels directly to its frozen final via NavigationAgent.
	route.waypoints = PackedVector3Array()
	route.raw_waypoints = PackedVector3Array()
	route.route_clearance_radius = 0.0
	route.route_valid = true
	route.created_msec = Time.get_ticks_msec()

	_assign_final_destinations(route, units, accepted)
	_routes[route.route_id] = route
	_issue_initial_orders(route, units)

	result["handled"] = true
	result["accepted_destination"] = accepted
	_player_diag["stable_slot_count"] = int(_player_diag.get("stable_slot_count", 0)) + route.final_destinations.size()
	_player_diag["orders_issued"] = int(_player_diag.get("orders_issued", 0)) + route.member_ids.size()
	## Workers do not consume a shared strategic corridor.
	_player_diag["shared_route_count"] = int(_player_diag.get("shared_route_count", 0))
	return result


## Military group: one validated shared corridor; members share the waypoint sequence.
func _issue_shared_military_command(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	generation: int
) -> Dictionary:
	var result: Dictionary = {
		"handled": false,
		"accepted_destination": destination,
		"failure_reason": "",
	}
	var origin: Vector3 = _compute_group_origin(units)
	var built: Dictionary = _build_validated_route(origin, destination, units)
	if not bool(built.get("valid", false)):
		result["failure_reason"] = String(built.get("failure_reason", "invalid_route"))
		return result

	for unit_variant: Variant in units:
		if NodeSafety.is_alive_node(unit_variant) and unit_variant is Unit:
			detach_unit_from_group_state(unit_variant)

	var waypoints: PackedVector3Array = built["waypoints"] as PackedVector3Array
	var raw_waypoints: PackedVector3Array = built["raw_waypoints"] as PackedVector3Array
	var accepted: Vector3 = built["accepted"] as Vector3

	var route := PlayerRoute.new()
	route.route_id = _next_route_id
	_next_route_id += 1
	route.command_generation = generation
	route.order_kind = order_kind
	route.use_attack_move = order_kind == &"attack_move"
	route.clicked_destination = destination
	route.accepted_destination = accepted
	route.waypoints = waypoints
	route.raw_waypoints = raw_waypoints
	route.route_clearance_radius = ROUTE_CLEARANCE
	route.route_valid = true
	route.created_msec = Time.get_ticks_msec()

	_assign_final_destinations(route, units, accepted)
	_bootstrap_waypoint_indices(route, units)

	_routes[route.route_id] = route
	_issue_initial_orders(route, units)
	PerfCounters.record_squad_strategic_route()

	result["handled"] = true
	result["accepted_destination"] = accepted
	_player_diag["shared_route_count"] = int(_player_diag.get("shared_route_count", 0)) + 1
	_player_diag["route_waypoint_count"] = waypoints.size()
	_player_diag["raw_route_waypoint_count"] = raw_waypoints.size()
	_player_diag["route_clearance_radius"] = ROUTE_CLEARANCE
	_player_diag["stable_slot_count"] = int(_player_diag.get("stable_slot_count", 0)) + route.final_destinations.size()
	_player_diag["orders_issued"] = int(_player_diag.get("orders_issued", 0)) + route.member_ids.size()
	return result


func _reset_telemetry() -> void:
	_player_diag = {
		"command_generation": 0,
		"clicked_position": Vector3.ZERO,
		"accepted_destination": Vector3.ZERO,
		"stable_slot_count": 0,
		"shared_route_count": 0,
		"route_waypoint_count": 0,
		"raw_route_waypoint_count": 0,
		"route_clearance_radius": 0.0,
		"orders_issued": 0,
		"stall_recovery_count": 0,
		"stale_callback_blocks": 0,
		"route_failures": 0,
		"formation_refresh_count": 0,
		"target_replacements": 0,
		"repath_count": 0,
		"slot_generation_count": 0,
	}


func _tick_routes() -> void:
	var remove_ids: Array[int] = []
	for route_id_variant: Variant in _routes.keys():
		var route_id: int = int(route_id_variant)
		var route: PlayerRoute = _routes.get(route_id) as PlayerRoute
		if route == null:
			remove_ids.append(route_id)
			continue
		if route.purge_dead_members():
			_rebind_after_purge(route)
		if route.member_count() <= 0:
			remove_ids.append(route_id)
			continue
		## No continuous retarget / formation / queue — units advance on arrival.
		## Light pass: ensure fighting attack-move members keep route membership only.
	for route_id: int in remove_ids:
		_dissolve_route(route_id)


func _filter_and_order_units(units: Array) -> Array:
	var filtered: Array = []
	for unit_variant: Variant in units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		if unit.is_in_group(&"enemies") or unit.is_in_group(&"neutral_creeps"):
			continue
		filtered.append(unit)
	filtered.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)
	return filtered


func _compute_group_origin(units: Array) -> Vector3:
	var xs: Array[float] = []
	var zs: Array[float] = []
	var y_sum: float = 0.0
	for unit_variant: Variant in units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Node3D:
			continue
		var pos: Vector3 = (unit_variant as Node3D).global_position
		xs.append(pos.x)
		zs.append(pos.z)
		y_sum += pos.y
	if xs.is_empty():
		return Vector3.ZERO
	xs.sort()
	zs.sort()
	var mid: int = xs.size() / 2
	return Vector3(xs[mid], y_sum / float(xs.size()), zs[mid])


func _resolve_nav_map(units: Array) -> RID:
	for unit_variant: Variant in units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Node3D:
			continue
		var node: Node3D = unit_variant as Node3D
		var world: World3D = node.get_world_3d()
		if world != null and world.get_navigation_map().is_valid():
			return world.get_navigation_map()
	return RID()


func _build_validated_route(origin: Vector3, destination: Vector3, units: Array) -> Dictionary:
	var out: Dictionary = {
		"valid": false,
		"waypoints": PackedVector3Array(),
		"raw_waypoints": PackedVector3Array(),
		"accepted": destination,
		"failure_reason": "",
	}
	var nav_map: RID = _resolve_nav_map(units)
	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		out["failure_reason"] = "nav_map_inactive"
		return out

	var from: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, origin)
	if _horizontal_distance(origin, from) > ROUTE_SNAP_ACCEPT_DISTANCE:
		out["failure_reason"] = "start_not_on_navigation"
		return out

	var to: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, destination)
	if _horizontal_distance(destination, to) > ROUTE_SNAP_ACCEPT_DISTANCE:
		var nearest: Vector3 = _find_nearest_reachable_destination(nav_map, from, destination)
		if nearest == Vector3.ZERO:
			out["failure_reason"] = "destination_not_on_navigation"
			return out
		to = nearest

	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
	if path.is_empty() or path.size() < 2:
		var fallback: Vector3 = _find_nearest_reachable_destination(nav_map, from, to)
		if fallback != Vector3.ZERO:
			to = fallback
			path = NavigationServer3D.map_get_path(nav_map, from, to, true)

	if path.is_empty() or path.size() < 2:
		out["failure_reason"] = "no_valid_path"
		return out

	if not _validate_route_waypoints(nav_map, path):
		out["failure_reason"] = "waypoints_not_navigable"
		return out

	## Keep click destination as last point when it snaps cleanly.
	path = path.duplicate()
	path[path.size() - 1] = to

	out["valid"] = true
	out["raw_waypoints"] = path.duplicate()
	out["waypoints"] = path
	out["accepted"] = to
	return out


func _validate_route_waypoints(nav_map: RID, path: PackedVector3Array) -> bool:
	if path.size() < 2:
		return false
	for point: Vector3 in path:
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, point)
		if _horizontal_distance(point, closest) > ROUTE_ON_MESH_TOLERANCE:
			return false
	for index: int in range(path.size() - 1):
		if not _segment_stays_on_mesh(nav_map, path[index], path[index + 1]):
			return false
	return true


func _segment_stays_on_mesh(nav_map: RID, from: Vector3, to: Vector3) -> bool:
	var length: float = _horizontal_distance(from, to)
	if length < 0.05:
		return true
	var steps: int = maxi(1, int(ceil(length / ROUTE_SEGMENT_SAMPLE_STEP)))
	for step: int in range(1, steps):
		var t: float = float(step) / float(steps)
		var sample: Vector3 = from.lerp(to, t)
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, sample)
		if _horizontal_distance(sample, closest) > ROUTE_ON_MESH_TOLERANCE * 1.25:
			return false
	return true


func _find_nearest_reachable_destination(
	nav_map: RID,
	from: Vector3,
	requested: Vector3
) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_dist: float = INF
	for ring: int in range(1, ROUTE_FALLBACK_RING_COUNT + 1):
		var radius: float = ROUTE_FALLBACK_RING_RADIUS * float(ring)
		for step: int in ROUTE_FALLBACK_RING_STEPS:
			var angle: float = TAU * float(step) / float(ROUTE_FALLBACK_RING_STEPS)
			var candidate: Vector3 = requested + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)
			if _horizontal_distance(candidate, snapped) > ROUTE_ON_MESH_TOLERANCE:
				continue
			var probe: PackedVector3Array = NavigationServer3D.map_get_path(
				nav_map, from, snapped, true
			)
			if probe.is_empty() or probe.size() < 2:
				continue
			var dist: float = _horizontal_distance(requested, snapped)
			if dist < best_dist:
				best_dist = dist
				best = snapped
		if best != Vector3.ZERO:
			return best
	return best


func _assign_final_destinations(route: PlayerRoute, units: Array, accepted: Vector3) -> void:
	route.final_destinations.clear()
	var spacing: float = FINAL_SLOT_SPACING
	var max_radius: float = UNIT_NAV_RADIUS
	for unit_variant: Variant in units:
		if NodeSafety.is_alive_node(unit_variant) and unit_variant is CollisionObject3D:
			max_radius = maxf(
				max_radius,
				UnitSeparation.get_unit_radius(unit_variant as CollisionObject3D)
			)
	spacing = maxf(FINAL_SLOT_SPACING, max_radius * 2.2)

	var targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
		accepted, units.size(), spacing
	)
	var nav_map: RID = _resolve_nav_map(units)
	for index: int in units.size():
		var unit_variant: Variant = units[index]
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		var world: Vector3 = accepted
		if index < targets.size():
			world = targets[index]
		world = GroupMoveSpacing.resolve_nearby_walkable_position(
			world, unit, accepted, spacing
		)
		if nav_map.is_valid():
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, world)
			if _horizontal_distance(world, snapped) <= ROUTE_SNAP_ACCEPT_DISTANCE:
				world = snapped
		route.final_destinations[unit.get_instance_id()] = world
	_player_diag["slot_generation_count"] = 1


func _bootstrap_waypoint_indices(route: PlayerRoute, units: Array) -> void:
	if route.waypoints.is_empty():
		return
	var start_index: int = 0
	if route.waypoints.size() >= 2:
		var origin: Vector3 = _compute_group_origin(units)
		if _horizontal_distance(origin, route.waypoints[0]) <= WAYPOINT_PASS_DISTANCE * 1.25:
			start_index = 1
	for unit_variant: Variant in units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		var unit_id: int = (unit_variant as Unit).get_instance_id()
		route.set_waypoint_index(unit_id, start_index)


func _desired_travel_target(route: PlayerRoute, unit_id: int) -> Vector3:
	if route.waypoints.is_empty():
		return route.get_final_destination(unit_id)
	var index: int = route.get_waypoint_index(unit_id)
	var last_index: int = route.waypoints.size() - 1
	var unit: Unit = PlayerRoute.resolve_living_unit(unit_id)
	if unit != null and index >= last_index:
		var last_wp: Vector3 = route.waypoints[last_index]
		if _unit_reached_or_passed_waypoint(unit, route, last_wp, last_index):
			return route.get_final_destination(unit_id)
		## Near final destination — settle on frozen slot.
		if _horizontal_distance(unit.global_position, route.accepted_destination) <= FINAL_APPROACH_RADIUS:
			return route.get_final_destination(unit_id)
	index = clampi(index, 0, last_index)
	return route.waypoints[index]


func _unit_reached_or_passed_waypoint(
	unit: Node3D,
	route: PlayerRoute,
	waypoint: Vector3,
	waypoint_index: int
) -> bool:
	var pos: Vector3 = unit.global_position
	if _horizontal_distance(pos, waypoint) <= WAYPOINT_PASS_DISTANCE:
		return true
	var ahead: Vector3 = route.accepted_destination
	if waypoint_index + 1 < route.waypoints.size():
		ahead = route.waypoints[waypoint_index + 1]
	var route_dir: Vector3 = ahead - waypoint
	route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		return false
	route_dir = route_dir.normalized()
	var from_wp: Vector3 = pos - waypoint
	from_wp.y = 0.0
	if from_wp.dot(route_dir) >= 0.0:
		return true
	if _horizontal_distance(pos, ahead) + 0.35 < _horizontal_distance(pos, waypoint):
		return true
	return false


func _compute_route_rejoin_point(route: PlayerRoute, unit: Unit) -> Vector3:
	if route.waypoints.is_empty():
		return route.get_final_destination(unit.get_instance_id())

	var unit_id: int = unit.get_instance_id()
	var current_index: int = route.get_waypoint_index(unit_id)
	var last_index: int = route.waypoints.size() - 1

	## Known-good: another member already cleared further along the same corridor.
	var known_good: int = route.get_known_good_waypoint_index(unit_id)
	if known_good > current_index:
		current_index = mini(known_good, last_index)
		route.set_waypoint_index(unit_id, current_index)
		unit.set_player_route_waypoint_index(current_index)
		return route.waypoints[current_index]

	var next_index: int = mini(current_index + 1, last_index)
	var a: Vector3 = route.waypoints[clampi(current_index, 0, last_index)]
	var b: Vector3 = route.waypoints[next_index]
	var rejoin: Vector3 = _nearest_point_on_segment_xz(unit.global_position, a, b)

	var nav_map: RID = _resolve_nav_map([unit])
	if nav_map.is_valid():
		var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, rejoin)
		if _horizontal_distance(rejoin, snapped) <= ROUTE_SNAP_ACCEPT_DISTANCE:
			rejoin = snapped
	return rejoin


func _nearest_point_on_segment_xz(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ap := Vector3(point.x - a.x, 0.0, point.z - a.z)
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 0.0001:
		return a
	var t: float = clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	return Vector3(a.x + ab.x * t, point.y, a.z + ab.z * t)


func _issue_initial_orders(route: PlayerRoute, members: Array) -> void:
	for unit_variant: Variant in members:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		var unit_id: int = unit.get_instance_id()
		var final_dest: Vector3 = route.get_final_destination(unit_id)
		## Order bookkeeping first (detaches any stale group membership).
		if route.order_kind == &"attack_move" and unit.supports_combat_orders():
			unit.issue_order(UnitOrder.attack_move(final_dest), false)
		elif route.order_kind == &"patrol" and unit.supports_patrol():
			unit.issue_order(
				UnitOrder.patrol([unit.global_position, final_dest]),
				false
			)
		else:
			_issue_ground_order(unit, final_dest, route.order_kind, false)
		## Join this route only after prepare cleared prior membership.
		if not route.member_ids.has(unit_id):
			route.member_ids.append(unit_id)
		_unit_to_route[unit_id] = route.route_id
		_watch_unit(unit)
		unit.bind_player_route_command(
			route.command_generation,
			route.route_id,
			route.get_waypoint_index(unit_id),
			route.clicked_destination,
			final_dest,
			route.order_kind
		)
		var travel: Vector3 = _desired_travel_target(route, unit_id)
		unit.request_route_travel_target(travel, final_dest, Unit.RepathUrgency.PLAYER_ORDER)


func _issue_ground_order(
	unit: Unit,
	target: Vector3,
	order_kind: StringName,
	queued: bool
) -> void:
	if unit is Worker and not queued:
		(unit as Worker).cancel_gathering()
	match order_kind:
		&"attack_move":
			if unit.supports_combat_orders():
				unit.issue_order(UnitOrder.attack_move(target), queued)
			else:
				unit.issue_order(UnitOrder.move(target), queued)
		&"patrol":
			if unit.supports_patrol():
				if (
					queued
					and unit.get_active_order() != null
					and unit.get_active_order().type == UnitOrder.Type.PATROL
				):
					unit.append_patrol_point(target)
				else:
					unit.issue_order(
						UnitOrder.patrol([unit.global_position, target]),
						queued
					)
			else:
				unit.issue_order(UnitOrder.move(target), queued)
		_:
			unit.issue_order(UnitOrder.move(target), queued)


func _watch_unit(unit: Node) -> void:
	var unit_id: int = unit.get_instance_id()
	if _unit_exit_handlers.has(unit_id):
		return
	var handler: Callable = _on_unit_tree_exiting.bind(unit_id)
	_unit_exit_handlers[unit_id] = handler
	if not unit.tree_exiting.is_connected(handler):
		unit.tree_exiting.connect(handler, CONNECT_ONE_SHOT)


func _on_unit_tree_exiting(unit_id: int) -> void:
	_remove_unit_by_id(unit_id)


func _disconnect_unit_exit_handler(unit_id: int) -> void:
	if not _unit_exit_handlers.has(unit_id):
		return
	var handler: Callable = _unit_exit_handlers[unit_id] as Callable
	_unit_exit_handlers.erase(unit_id)
	var node: Object = instance_from_id(unit_id)
	if node != null and is_instance_valid(node) and node is Node:
		var typed: Node = node as Node
		if typed.tree_exiting.is_connected(handler):
			typed.tree_exiting.disconnect(handler)


func _remove_unit_by_id(unit_id: int) -> void:
	var route_id: int = int(_unit_to_route.get(unit_id, -1))
	_unit_to_route.erase(unit_id)
	_disconnect_unit_exit_handler(unit_id)
	if route_id < 0:
		return
	var route: PlayerRoute = _routes.get(route_id) as PlayerRoute
	if route == null:
		return
	route.clear_unit_state(unit_id)
	if route.member_count() <= 0:
		_dissolve_route(route_id)


func _rebind_after_purge(route: PlayerRoute) -> void:
	var valid: Dictionary = {}
	for unit_id: int in route.member_ids:
		valid[unit_id] = true
		_unit_to_route[unit_id] = route.route_id
	var stale_ids: Array[int] = []
	for mapped_id: Variant in _unit_to_route.keys():
		if int(_unit_to_route[mapped_id]) != route.route_id:
			continue
		if not valid.has(int(mapped_id)):
			stale_ids.append(int(mapped_id))
	for stale_id: int in stale_ids:
		_unit_to_route.erase(stale_id)
		_disconnect_unit_exit_handler(stale_id)


func _dissolve_route(route_id: int) -> void:
	var route: PlayerRoute = _routes.get(route_id) as PlayerRoute
	if route != null:
		for unit_id: int in route.member_ids.duplicate():
			_unit_to_route.erase(unit_id)
			_disconnect_unit_exit_handler(unit_id)
			var unit: Unit = PlayerRoute.resolve_living_unit(unit_id)
			if unit != null and unit.matches_player_route_command(route.command_generation):
				unit.clear_player_route_command()
	_routes.erase(route_id)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
