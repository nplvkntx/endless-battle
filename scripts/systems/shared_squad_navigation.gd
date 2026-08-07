extends Node

## Centralized shared squad navigation: one strategic route per group command,
## stable role slots, staggered local follower destinations.

## Temporary debug switch retained for callers — player Move/Attack-Move no longer
## uses this system. See PlayerRouteNavigation.
const DEBUG_DISABLE_PLAYER_FORMATIONS := true

const ANCHOR_TICK_INTERVAL := 0.25
const UNIT_UPDATE_BUDGET_PER_SQUAD := 5
const DEST_BUCKET_SIZE := 2.0
const WAYPOINT_REACH_DISTANCE := 3.25
const WAYPOINT_PASS_DISTANCE := 4.5
const WAYPOINT_MAJORITY_RATIO := 0.65
const FINAL_APPROACH_RADIUS := 8.0
const ANCHOR_MOVE_SPEED := 9.0
const SLOT_DEST_THRESHOLD := 2.25
const SLOT_SKIP_DISTANCE := 1.35
const STALL_TIMEOUT_SECONDS := 7.0
const PROGRESS_EPSILON := 1.75
const ROUTE_RECALC_COOLDOWN_SECONDS := 8.0
const TARGET_SEARCH_INTERVAL := 1.35
const TARGET_SEARCH_JITTER := 0.35
const NARROW_PASSAGE_WIDTH := 5.5
const COMPRESSED_SPACING_SCALE := 0.55
const FORMATION_SPACING := 2.0
const SIMPLE_SLOT_BASE_SPACING := 1.6
const ROUTE_SNAP_ACCEPT_DISTANCE := 8.0
const ROUTE_FALLBACK_RING_STEPS := 8
const ROUTE_FALLBACK_RING_COUNT := 4
const ROUTE_FALLBACK_RING_RADIUS := 2.5
const MEMBER_STALL_REFRESH_RATIO := 0.45
const MAX_INITIAL_ORDERS := 12
## Strategic corridor clearance (unit nav radius + small squad safety margin).
## Not full formation width — narrow chokepoints remain valid.
const UNIT_NAV_RADIUS := 0.55
const SQUAD_ROUTE_SAFETY_MARGIN := 0.45
const SQUAD_ROUTE_CLEARANCE := UNIT_NAV_RADIUS + SQUAD_ROUTE_SAFETY_MARGIN
## Soft lane spacing along the corridor perpendicular (optional; shrinks near obstacles).
const TRAVEL_LATERAL_SPACING := 0.85
const TRAVEL_OFFSET_CLEARANCE := UNIT_NAV_RADIUS
const TRAVEL_CORNER_DOT := 0.55
const TRAVEL_OFFSET_VALIDATE_STEPS := 4
const ROUTE_CORNER_PUSH_MAX := 1.4
const ROUTE_CLEARANCE_PROBE_COUNT := 8
const ROUTE_SEGMENT_SAMPLE_STEP := 1.15
const ROUTE_ON_MESH_TOLERANCE := 0.35
const ROUTE_MICRO_TURN_DOT := 0.985
const ROUTE_MIN_WAYPOINT_SPACING := 0.85
const ROUTE_NARROW_CLEARANCE_FLOOR := 0.28
const ROUTE_NARROW_BALANCE_TOLERANCE := 0.3
## Temporary single-file through constrained sections for small player groups only.
## Not a formation — enter near corners/narrow clearance, exit when open again.
const SMALL_GROUP_QUEUE_MAX := 6
const QUEUE_TRAIL_SPACING := 1.15
const QUEUE_ENTER_CLEARANCE := 0.72
const QUEUE_EXIT_CLEARANCE := 0.95
const QUEUE_STATIC_NEAR_DIST := 1.45
const QUEUE_STATIC_NEAR_COUNT := 2
const QUEUE_LATERAL_SCALE_ACTIVE := 0.05
const QUEUE_EXIT_HYSTERESIS_WPS := 1

## Stall recovery ownership (escalation order):
## 1. Local steering / UnitSeparation while progress exists
## 2. Per-unit confirmed stall → local repath / waypoint / yield+detour
## 3. Shared strategic route refresh (this system) when group is stalled
## 4. Cancel / finish only as final per-unit fallback when not in a squad
## Worker gather/build keep specialized task recovery; do not add extra nudges.

var _squads: Dictionary = {} ## squad_id -> SquadNavContext
var _unit_to_squad: Dictionary = {} ## unit_instance_id -> squad_id
var _unit_exit_handlers: Dictionary = {} ## unit_instance_id -> Callable
var _next_squad_id: int = 1
var _global_command_generation: int = 0
var _anchor_accum: float = 0.0
var _diag_member_count: int = 0
var _diag_stalls: int = 0
var _diag_route_failures: int = 0
## One-shot stale-reference cleanup reports (not per-frame).
var _diag_stale_reports: Array[String] = []
## Temporary player-move telemetry for one selected group command.
var _player_diag: Dictionary = {
	"command_generation": 0,
	"clicked_position": Vector3.ZERO,
	"accepted_destination": Vector3.ZERO,
	"stable_slot_count": 0,
	"shared_route_count": 0,
	"route_waypoint_count": 0,
	"raw_route_waypoint_count": 0,
	"route_clearance_radius": 0.0,
	"orders_issued": 0,
	"slot_generation_count": 0,
	"formation_refresh_count": 0,
	"target_replacements": 0,
	"repath_count": 0,
	"stall_recovery_count": 0,
	"stale_callback_blocks": 0,
}


func _ready() -> void:
	MatchSession.register_match_reset(&"SharedSquadNavigation", clear_all)
	set_process(true)


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_shared_squad_nav_enabled():
		return
	_anchor_accum += delta
	if _anchor_accum < ANCHOR_TICK_INTERVAL:
		return
	var step: float = _anchor_accum
	_anchor_accum = 0.0
	_tick_squads(step)


func clear_all() -> void:
	for unit_id: Variant in _unit_exit_handlers.keys():
		_disconnect_unit_exit_handler(int(unit_id))
	_unit_exit_handlers.clear()
	_squads.clear()
	_unit_to_squad.clear()
	_next_squad_id = 1
	_global_command_generation = 0
	_diag_member_count = 0
	_diag_stalls = 0
	_diag_route_failures = 0
	_diag_stale_reports.clear()
	_reset_player_move_telemetry()
	_publish_diag()


func reset_player_move_telemetry() -> void:
	PlayerRouteNavigation.reset_player_move_telemetry()
	_reset_player_move_telemetry()


func get_player_move_telemetry() -> Dictionary:
	return PlayerRouteNavigation.get_player_move_telemetry()


func _reset_player_move_telemetry() -> void:
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
		"slot_generation_count": 0,
		"formation_refresh_count": 0,
		"target_replacements": 0,
		"repath_count": 0,
		"stall_recovery_count": 0,
		"stale_callback_blocks": 0,
	}


func is_shared_navigation_enabled() -> bool:
	return MilitaryAIConfig.is_shared_squad_nav_enabled()


## True while player Move/Attack-Move skip formation slots (always — see PlayerRouteNavigation).
func are_player_formations_disabled() -> bool:
	return true


func get_squad_for_unit(unit: Variant) -> SquadNavContext:
	if unit == null or not is_instance_valid(unit) or not (unit is Node):
		return null
	var squad_id: int = int(_unit_to_squad.get((unit as Node).get_instance_id(), -1))
	if squad_id < 0:
		return null
	return _get_squad_context(squad_id)


func release_unit(unit: Variant) -> void:
	if unit == null or not is_instance_valid(unit) or not (unit is Node):
		return
	var unit_id: int = (unit as Node).get_instance_id()
	if unit is Unit:
		(unit as Unit).clear_player_squad_command()
	_remove_unit_by_id(unit_id, &"release")


## Canonical membership cleanup — clears every per-unit container for one ID.
func _remove_unit_by_id(unit_id: int, via: StringName = &"prune") -> void:
	var squad_id: int = int(_unit_to_squad.get(unit_id, -1))
	_unit_to_squad.erase(unit_id)
	_disconnect_unit_exit_handler(unit_id)

	if squad_id < 0:
		return

	var ctx: SquadNavContext = _get_squad_context(squad_id)
	if ctx == null:
		_squads.erase(squad_id)
		return
	ctx.clear_unit_state(unit_id)

	if via == &"prune":
		_report_stale_cleanup(squad_id, unit_id, "membership", ctx.command_generation, via)

	if ctx.member_count() <= 0:
		_dissolve_squad(squad_id)


func _get_squad_context(squad_id: int) -> SquadNavContext:
	var ctx_variant: Variant = _squads.get(squad_id)
	if ctx_variant == null or not is_instance_valid(ctx_variant):
		return null
	if not ctx_variant is SquadNavContext:
		return null
	return ctx_variant as SquadNavContext


func _watch_unit(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var unit_id: int = unit.get_instance_id()
	if _unit_exit_handlers.has(unit_id):
		return
	var handler: Callable = _on_unit_tree_exiting.bind(unit_id)
	_unit_exit_handlers[unit_id] = handler
	unit.tree_exiting.connect(handler, CONNECT_ONE_SHOT)


func _on_unit_tree_exiting(unit_id: int) -> void:
	_unit_exit_handlers.erase(unit_id)
	_remove_unit_by_id(unit_id, &"signal")


func _disconnect_unit_exit_handler(unit_id: int) -> void:
	if not _unit_exit_handlers.has(unit_id):
		return
	var handler: Callable = _unit_exit_handlers[unit_id]
	_unit_exit_handlers.erase(unit_id)
	var node: Object = instance_from_id(unit_id)
	if node == null or not is_instance_valid(node) or not node is Node:
		return
	var unit_node: Node = node as Node
	if unit_node.tree_exiting.is_connected(handler):
		unit_node.tree_exiting.disconnect(handler)


func _report_stale_cleanup(
	squad_id: int,
	dead_id: int,
	container: String,
	command_generation: int,
	via: StringName
) -> void:
	var line: String = (
		"squad=%d dead_id=%d container=%s generation=%d via=%s"
		% [squad_id, dead_id, container, command_generation, String(via)]
	)
	if _diag_stale_reports.size() < 32:
		_diag_stale_reports.append(line)
	push_warning("SharedSquadNavigation stale cleanup: %s" % line)


func get_stale_cleanup_reports() -> Array[String]:
	return _diag_stale_reports.duplicate()


func clear_stale_cleanup_reports() -> void:
	_diag_stale_reports.clear()


## Test/debug: true when any squad or map still holds a freed unit ID.
func debug_has_stale_unit_references() -> bool:
	for unit_id: Variant in _unit_to_squad.keys():
		if SquadNavContext.resolve_living_node3d(int(unit_id)) == null:
			return true
	for squad_id: Variant in _squads.keys():
		var ctx: SquadNavContext = _get_squad_context(int(squad_id))
		if ctx == null:
			continue
		for member_id: int in ctx.member_ids:
			if SquadNavContext.resolve_living_node3d(member_id) == null:
				return true
		if ctx.shared_threat_id != 0 and SquadNavContext.resolve_living_node3d(ctx.shared_threat_id) == null:
			return true
		for key: Variant in ctx.member_threats.keys():
			if SquadNavContext.resolve_living_node3d(int(ctx.member_threats[key])) == null:
				return true
	return false


func debug_unit_to_squad_has(unit_id: int) -> bool:
	return _unit_to_squad.has(unit_id)


## Called by Unit local recovery when a squad member exhausted local stages.
## Shared route refresh is owned here — units must not cancel while still in a squad.
func notify_member_confirmed_stall(unit: Variant) -> bool:
	var ctx: SquadNavContext = get_squad_for_unit(unit)
	if ctx == null or unit == null or not is_instance_valid(unit):
		return false
	## Stale callbacks from a superseded player click must never retake control.
	if ctx.is_player_squad and unit is Unit:
		if not (unit as Unit).matches_player_squad_command(ctx.command_generation):
			_player_diag["stale_callback_blocks"] = int(_player_diag["stale_callback_blocks"]) + 1
			return false
	var unit_id: int = (unit as Node).get_instance_id()
	ctx.stalled_member_ids[unit_id] = true
	var stalled: int = ctx.stalled_member_ids.size()
	var threshold: int = maxi(1, int(ceil(float(ctx.member_count()) * MEMBER_STALL_REFRESH_RATIO)))
	if stalled >= threshold or _detect_squad_stall(ctx):
		if ctx.is_player_squad:
			_recover_player_squad_stall(ctx)
		else:
			_recover_stalled_squad(ctx)
	return true


func try_get_assigned_target(unit: Variant) -> Node3D:
	var ctx: SquadNavContext = get_squad_for_unit(unit)
	if ctx == null:
		return null
	if unit == null or not is_instance_valid(unit):
		return null
	var unit_id: int = (unit as Node).get_instance_id()
	var assigned: Node3D = ctx.get_member_threat(unit_id)
	if assigned != null and CombatTargetValidation.is_valid_combat_target(assigned):
		var search_range: float = 28.0
		if unit is MilitaryUnit:
			search_range = maxf(
				(unit as MilitaryUnit).attack_range,
				MilitaryUnit.ATTACK_MOVE_ENGAGEMENT_RANGE
			)
		if CombatTargetValidation.get_horizontal_attack_distance(unit as Node3D, assigned) <= (
			search_range + 4.0
		):
			return assigned
	var shared: Node3D = ctx.get_shared_threat_target()
	if shared != null:
		return shared
	return null


## Current travel point — redirected to PlayerRouteNavigation.
func resolve_player_travel_target(unit: Variant) -> Vector3:
	return PlayerRouteNavigation.resolve_travel_target(unit)


## Issue or refresh a squad command. Returns pending per-unit orders for the caller to drain.
func issue_group_command(
	units: Array,
	destination: Vector3,
	use_attack_move: bool,
	mission: int,
	external_generation: int = -1
) -> Dictionary:
	var result: Dictionary = {
		"handled": false,
		"equivalent_skip": false,
		"pending_orders": [],
	}
	if not is_shared_navigation_enabled():
		return result

	units = _filter_military_units(units)
	if units.size() <= 1 or destination == Vector3.ZERO:
		return result

	result["handled"] = true
	var ordered_units: Array = _order_units_for_formation(units)
	var member_ids: Array[int] = _collect_unit_ids(ordered_units)
	var generation: int = (
		external_generation if external_generation >= 0 else _global_command_generation + 1
	)
	var equiv_signature: String = _build_equivalence_signature(
		member_ids, destination, mission, use_attack_move
	)
	var signature: String = "%d|%s" % [generation, equiv_signature]

	var ctx: SquadNavContext = _find_reusable_squad(equiv_signature)
	if ctx != null:
		result["equivalent_skip"] = true
		_bind_members(ctx, ordered_units)
		PerfCounters.record_squad_route_cache_hit()
		_publish_diag()
		return result

	_global_command_generation = maxi(_global_command_generation, generation)
	ctx = _create_squad_context(
		ordered_units,
		destination,
		use_attack_move,
		mission,
		generation,
		signature,
		false
	)
	if ctx == null:
		result["handled"] = false
		return result

	result["pending_orders"] = _collect_initial_orders(ctx, ordered_units, use_attack_move, mission)
	_publish_diag()
	return result


## Player / formation-manager entry — permanently redirected to PlayerRouteNavigation.
## Do not create SharedSquadNavigation player squads / corridor state for player commands.
func issue_formation_command(
	_formation_id: int,
	members: Array,
	destination: Vector3,
	order_kind: StringName,
	_group: FormationGroup
) -> Dictionary:
	return issue_player_group_command(members, destination, order_kind, false)


## Player unformed multi-unit selection (workers + military): one shared route +
## stable final arrival slots issued once. No continuous anchor-slot following.
## Queued orders only store spaced destinations — live squad activates on current commands.
func issue_player_group_command(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	queued: bool = false
) -> Dictionary:
	## Player Move / Attack-Move / Patrol owned by PlayerRouteNavigation.
	## Keep this stub so older callers fail closed instead of re-entering corridor logic.
	return PlayerRouteNavigation.issue_command(units, destination, order_kind, queued)


func _issue_unit_ground_order(
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
				if queued and unit.get_active_order() != null and unit.get_active_order().type == UnitOrder.Type.PATROL:
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


func _create_squad_context(
	ordered_units: Array,
	destination: Vector3,
	use_attack_move: bool,
	mission: int,
	generation: int,
	signature: String,
	is_player: bool,
	group: FormationGroup = null
) -> SquadNavContext:
	var ctx := SquadNavContext.new()
	ctx.squad_id = _next_squad_id
	_next_squad_id += 1
	ctx.command_generation = generation
	ctx.command_signature = signature
	ctx.equivalence_signature = _build_equivalence_signature(
		_collect_unit_ids(ordered_units), destination, mission, use_attack_move
	)
	ctx.mission = mission
	ctx.use_attack_move = use_attack_move
	ctx.requested_destination = destination
	ctx.strategic_destination = destination
	ctx.is_player_squad = is_player
	ctx.uses_formation_layout = group != null
	ctx.route_created_msec = Time.get_ticks_msec()
	ctx.last_progress_msec = ctx.route_created_msec
	ctx.last_route_refresh_msec = ctx.route_created_msec

	for unit: Variant in ordered_units:
		if NodeSafety.is_alive_node(unit):
			ctx.member_ids.append((unit as Node).get_instance_id())

	ctx.recompute_anchor_median()
	ctx.last_progress_position = ctx.anchor_position
	if is_player and DEBUG_DISABLE_PLAYER_FORMATIONS:
		## No FormationManager shapes / continuous slot chase — still assign loose
		## corridor offsets and freeze unique finals after the shared route.
		ctx.uses_formation_layout = false
		ctx.slot_locals.clear()
		ctx.formation_size = ordered_units.size()
		_assign_player_travel_offsets(ctx, ordered_units)
	else:
		_assign_stable_slots(ctx, ordered_units, group)
		if is_player:
			_assign_player_travel_offsets(ctx, ordered_units)
	_calculate_shared_route(ctx, ordered_units)
	if is_player:
		_bootstrap_player_waypoint_index(ctx)
	_bind_members(ctx, ordered_units)
	_squads[ctx.squad_id] = ctx
	return ctx


func _assign_stable_slots(
	ctx: SquadNavContext,
	ordered_units: Array,
	group: FormationGroup = null
) -> void:
	ctx.slot_locals.clear()
	if group != null:
		group.recompute_anchor_from_members()
		group.ensure_slots_assigned()
		ctx.formation_shape = int(group.shape)
		ctx.formation_size = group.size_preset
		ctx.uses_formation_layout = true
		for unit: Variant in ordered_units:
			if not NodeSafety.is_alive_node(unit):
				continue
			var unit_id: int = (unit as Node).get_instance_id()
			if not group.slot_by_unit_id.has(unit_id):
				continue
			var slot_index: int = int(group.slot_by_unit_id[unit_id])
			var local_index: int = group.members.find(unit)
			if local_index >= 0 and local_index < group.assigned_locals.size():
				ctx.slot_locals[unit_id] = group.assigned_locals[local_index]
			else:
				var slots: Array[Dictionary] = FormationLayout.get_or_build_slots(
					group.shape, group.size_preset, group.spacing_class
				)
				if slot_index >= 0 and slot_index < slots.size():
					ctx.slot_locals[unit_id] = slots[slot_index]["local"]
		return

	# Ordinary unformed groups: simple stable grid — not player formation shapes.
	_assign_simple_group_slots(ctx, ordered_units)


func _assign_simple_group_slots(ctx: SquadNavContext, ordered_units: Array) -> void:
	ctx.uses_formation_layout = false
	ctx.formation_shape = int(FormationLayout.Shape.SQUARE)
	ctx.formation_size = ordered_units.size()
	var spacing: float = _compute_member_spacing(ordered_units)
	var locals: Array[Vector3] = GroupMoveSpacing.compute_targets(
		Vector3.ZERO, ordered_units.size(), spacing
	)
	for index: int in ordered_units.size():
		var unit: Variant = ordered_units[index]
		if not NodeSafety.is_alive_node(unit):
			continue
		var unit_id: int = (unit as Node).get_instance_id()
		if index < locals.size():
			ctx.slot_locals[unit_id] = locals[index]
		else:
			ctx.slot_locals[unit_id] = Vector3.ZERO


## Freeze each unit's final world arrival once at the click destination.
## These positions never move with the virtual anchor and are never rotated mid-travel.
func _freeze_player_arrival_slots(ctx: SquadNavContext) -> void:
	ctx.final_arrival_slots.clear()
	ctx.arrival_slots_frozen = false
	var accepted: Vector3 = ctx.strategic_destination
	var face: Vector3 = accepted - ctx.anchor_position
	face.y = 0.0
	if face.length_squared() >= 0.01:
		ctx.formation_forward = face.normalized()

	## Ordinary player travel (formations disabled): unique grid arrivals, frozen once.
	if DEBUG_DISABLE_PLAYER_FORMATIONS or not ctx.uses_formation_layout:
		var spacing: float = SIMPLE_SLOT_BASE_SPACING
		var members: Array = ctx.get_living_members()
		if not members.is_empty():
			spacing = _compute_member_spacing(members)
		var ordered_ids: Array[int] = ctx.member_ids.duplicate()
		var targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
			accepted, ordered_ids.size(), spacing
		)
		for index: int in ordered_ids.size():
			var unit_id: int = ordered_ids[index]
			var world: Vector3 = accepted
			if index < targets.size():
				world = GroupMoveSpacing.resolve_formation_position(targets[index], accepted)
			ctx.final_arrival_slots[unit_id] = world
		ctx.arrival_slots_frozen = true
		if ctx.is_player_squad:
			_player_diag["stable_slot_count"] = ctx.final_arrival_slots.size()
			_player_diag["slot_generation_count"] = int(_player_diag["slot_generation_count"]) + 1
		return

	var saved_anchor: Vector3 = ctx.anchor_position
	var saved_compressed: bool = ctx.compressed_passage
	var saved_scale: float = ctx.spacing_scale
	ctx.anchor_position = accepted
	ctx.compressed_passage = false
	ctx.spacing_scale = 1.0

	for unit_id: int in ctx.member_ids:
		var world: Vector3 = FormationLayout.world_from_local(
			ctx.slot_locals.get(unit_id, Vector3.ZERO) as Vector3,
			accepted,
			ctx.formation_forward
		)
		world = GroupMoveSpacing.resolve_formation_position(world, accepted)
		ctx.final_arrival_slots[unit_id] = world

	ctx.anchor_position = saved_anchor
	ctx.compressed_passage = saved_compressed
	ctx.spacing_scale = saved_scale
	ctx.arrival_slots_frozen = true

	if ctx.is_player_squad:
		_player_diag["stable_slot_count"] = ctx.final_arrival_slots.size()
		_player_diag["slot_generation_count"] = int(_player_diag["slot_generation_count"]) + 1


## Stable path-relative lane offsets (signed meters along corridor-right).
## Applied per waypoint with navigability validation — never raw world-axis grids.
func _assign_player_travel_offsets(ctx: SquadNavContext, ordered_units: Array) -> void:
	ctx.travel_offsets.clear()
	var count: int = ordered_units.size()
	if count <= 0:
		return
	var spacing: float = TRAVEL_LATERAL_SPACING
	if count >= 2:
		spacing = minf(_compute_member_spacing(ordered_units) * 0.55, TRAVEL_LATERAL_SPACING)
	for index: int in count:
		var unit: Variant = ordered_units[index]
		if not NodeSafety.is_alive_node(unit):
			continue
		var unit_id: int = (unit as Node).get_instance_id()
		var lane: float = (float(index) - (float(count) - 1.0) * 0.5) * spacing
		## Store signed lateral meters in x; yz unused. Applied with route tangent at issue time.
		ctx.travel_offsets[unit_id] = Vector3(lane, 0.0, 0.0)


func _bootstrap_player_waypoint_index(ctx: SquadNavContext) -> void:
	ctx.in_final_approach = false
	ctx.last_issued_waypoint_index.clear()
	if ctx.route_waypoints.is_empty():
		ctx.waypoint_index = 0
		ctx.in_final_approach = true
		return
	## Skip the start vertex — the squad already stands there.
	if (
		ctx.route_waypoints.size() >= 2
		and _horizontal_distance(ctx.anchor_position, ctx.route_waypoints[0])
		<= WAYPOINT_REACH_DISTANCE * 1.5
	):
		ctx.waypoint_index = 1
	else:
		ctx.waypoint_index = 0
	if _horizontal_distance(ctx.anchor_position, ctx.strategic_destination) <= FINAL_APPROACH_RADIUS:
		ctx.in_final_approach = true
		ctx.waypoint_index = maxi(ctx.route_waypoints.size() - 1, 0)


func _compute_member_spacing(units: Array) -> float:
	var max_radius: float = 0.55
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit) or not unit is CollisionObject3D:
			continue
		max_radius = maxf(max_radius, _estimate_unit_radius(unit as CollisionObject3D))
	return maxf(SIMPLE_SLOT_BASE_SPACING, max_radius * 2.25)


func _estimate_unit_radius(body: CollisionObject3D) -> float:
	var collision_shape: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 0.55
	if collision_shape.shape is CapsuleShape3D:
		return (collision_shape.shape as CapsuleShape3D).radius
	if collision_shape.shape is CylinderShape3D:
		return (collision_shape.shape as CylinderShape3D).radius
	if collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	if collision_shape.shape is BoxShape3D:
		var box := collision_shape.shape as BoxShape3D
		return maxf(box.size.x, box.size.z) * 0.5
	return 0.55


func _calculate_shared_route(ctx: SquadNavContext, ordered_units: Array) -> void:
	var nav_map: RID = _resolve_nav_map(ordered_units)
	ctx.route_valid = false
	ctx.raw_route_waypoints = PackedVector3Array()
	ctx.route_clearance_radius = 0.0
	var requested: Vector3 = ctx.requested_destination
	if requested == Vector3.ZERO:
		requested = ctx.strategic_destination

	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		ctx.strategic_destination = requested
		var fallback_path := PackedVector3Array([ctx.anchor_position, requested])
		ctx.raw_route_waypoints = fallback_path
		ctx.route_waypoints = fallback_path
		ctx.waypoint_index = 0
		# Allow movement to begin; local agents will path once the map is ready.
		ctx.route_valid = true
		PerfCounters.record_squad_strategic_route()
		return

	var from: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, ctx.anchor_position)
	var to: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, requested)

	# Reject absurd snaps far from the click when a closer reachable point exists.
	if _horizontal_distance(requested, to) > ROUTE_SNAP_ACCEPT_DISTANCE:
		var nearest: Vector3 = _find_nearest_reachable_destination(nav_map, from, requested)
		if nearest != Vector3.ZERO:
			to = nearest
		else:
			to = GroupMoveSpacing.clamp_to_map_bounds(requested)

	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
	PerfCounters.record_squad_strategic_route()

	if path.is_empty() or path.size() < 2:
		var fallback: Vector3 = _find_nearest_reachable_destination(nav_map, from, to)
		if fallback != Vector3.ZERO:
			to = fallback
			path = NavigationServer3D.map_get_path(nav_map, from, to, true)

	if path.is_empty() or path.size() < 2:
		# Keep the intended destination rather than collapsing to world origin.
		if _horizontal_distance(to, Vector3.ZERO) < 0.5 and requested.length() > 1.0:
			to = GroupMoveSpacing.clamp_to_map_bounds(requested)
		path = PackedVector3Array([from, to])
		_diag_route_failures += 1
		push_warning(
			"SharedSquadNavigation: empty path; using direct fallback to (%.1f, %.1f)"
			% [to.x, to.z]
		)
		ctx.route_valid = true
	else:
		ctx.route_valid = true

	ctx.strategic_destination = to
	ctx.raw_route_waypoints = path.duplicate()
	## Player groups get clearance-aware corridor processing once at create/refresh.
	## AI keeps the raw NavigationServer path (no strategy change).
	if ctx.is_player_squad:
		ctx.route_clearance_radius = SQUAD_ROUTE_CLEARANCE
		ctx.route_waypoints = _process_player_squad_route(nav_map, path, SQUAD_ROUTE_CLEARANCE)
	else:
		ctx.route_waypoints = path
	ctx.waypoint_index = 0
	var face: Vector3 = ctx.strategic_destination - ctx.anchor_position
	face.y = 0.0
	if face.length_squared() >= 0.01:
		ctx.formation_forward = face.normalized()
	elif ctx.route_waypoints.size() >= 2:
		var segment: Vector3 = ctx.route_waypoints[1] - ctx.route_waypoints[0]
		segment.y = 0.0
		if segment.length_squared() >= 0.01:
			ctx.formation_forward = segment.normalized()


## Build an RTS-style squad corridor from a raw NavigationServer polyline.
## Runs once per strategic route create/refresh — never per frame / per unit.
func _process_player_squad_route(
	nav_map: RID,
	raw_path: PackedVector3Array,
	clearance: float
) -> PackedVector3Array:
	if raw_path.size() < 2 or not nav_map.is_valid():
		return raw_path
	var processed: PackedVector3Array = raw_path.duplicate()
	processed = _push_route_corners_for_clearance(nav_map, processed, clearance)
	processed = _simplify_route_with_clearance(nav_map, processed, clearance)
	processed = _smooth_route_micro_turns(nav_map, processed, clearance)
	processed = _dedupe_route_waypoints(processed)
	## Preserve the player's accepted destination exactly (last raw/strategic point).
	if processed.size() >= 1 and raw_path.size() >= 1:
		processed[processed.size() - 1] = raw_path[raw_path.size() - 1]
	if processed.size() < 2:
		return raw_path
	return processed


func _push_route_corners_for_clearance(
	nav_map: RID,
	path: PackedVector3Array,
	clearance: float
) -> PackedVector3Array:
	if path.size() < 3:
		return path
	var result: PackedVector3Array = path.duplicate()
	## Skip start (0) and final destination (last) — never move the click target.
	for index: int in range(1, result.size() - 1):
		var current: Vector3 = result[index]
		var pushed: Vector3 = _push_waypoint_into_clearance(
			nav_map, current, clearance, ROUTE_CORNER_PUSH_MAX
		)
		## Prefer a stable outward correction; reject if snap jumped sideways too far.
		if _horizontal_distance(current, pushed) > 0.05:
			result[index] = pushed
	return result


func _push_waypoint_into_clearance(
	nav_map: RID,
	point: Vector3,
	clearance: float,
	max_push: float
) -> Vector3:
	var free_sum := Vector3.ZERO
	var free_weight: float = 0.0
	var blocked_sum := Vector3.ZERO
	var blocked_weight: float = 0.0
	for step: int in ROUTE_CLEARANCE_PROBE_COUNT:
		var angle: float = TAU * float(step) / float(ROUTE_CLEARANCE_PROBE_COUNT)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var achieved: float = _radial_clearance_in_direction(nav_map, point, dir, clearance)
		if achieved >= clearance * 0.92:
			free_sum += dir * achieved
			free_weight += achieved
		else:
			var deficit: float = clearance - achieved
			blocked_sum += dir * deficit
			blocked_weight += deficit

	## Already clear on all sides — keep centerline.
	if blocked_weight <= 0.001:
		return point

	var push_dir := Vector3.ZERO
	if free_weight > 0.001:
		push_dir = free_sum / free_weight
	elif blocked_weight > 0.001:
		push_dir = -(blocked_sum / blocked_weight)
	push_dir.y = 0.0
	if push_dir.length_squared() < 0.0001:
		return point
	push_dir = push_dir.normalized()

	var best: Vector3 = point
	var best_score: float = _score_waypoint_clearance(nav_map, point, clearance)
	## Single outward step — no left/right oscillation loops.
	var push_distance: float = minf(max_push, clearance * 0.9)
	var candidate: Vector3 = point + push_dir * push_distance
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)
	if _horizontal_distance(candidate, snapped) > ROUTE_ON_MESH_TOLERANCE:
		## Back off once toward the mesh.
		candidate = point + push_dir * (push_distance * 0.5)
		snapped = NavigationServer3D.map_get_closest_point(nav_map, candidate)
	if _horizontal_distance(point, snapped) < 0.05:
		return point
	var score: float = _score_waypoint_clearance(nav_map, snapped, clearance)
	if score + 0.05 >= best_score:
		best = snapped
	return best


func _score_waypoint_clearance(nav_map: RID, point: Vector3, clearance: float) -> float:
	var min_clear: float = clearance
	var sum_clear: float = 0.0
	for step: int in ROUTE_CLEARANCE_PROBE_COUNT:
		var angle: float = TAU * float(step) / float(ROUTE_CLEARANCE_PROBE_COUNT)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var achieved: float = _radial_clearance_in_direction(nav_map, point, dir, clearance)
		min_clear = minf(min_clear, achieved)
		sum_clear += achieved
	## Prefer higher minimum clearance, with average as a mild tie-break.
	return min_clear * 2.0 + sum_clear / float(ROUTE_CLEARANCE_PROBE_COUNT)


func _radial_clearance_in_direction(
	nav_map: RID,
	point: Vector3,
	direction: Vector3,
	max_radius: float
) -> float:
	var dir: Vector3 = direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return 0.0
	dir = dir.normalized()
	var low: float = 0.0
	var high: float = max_radius
	## Binary search how far we stay on the navmesh along this ray.
	for _iter: int in 5:
		var mid: float = (low + high) * 0.5
		var probe: Vector3 = point + dir * mid
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, probe)
		if _horizontal_distance(probe, closest) <= ROUTE_ON_MESH_TOLERANCE * 0.75:
			low = mid
		else:
			high = mid
	return low


func _simplify_route_with_clearance(
	nav_map: RID,
	path: PackedVector3Array,
	clearance: float
) -> PackedVector3Array:
	if path.size() <= 2:
		return path
	var result: PackedVector3Array = PackedVector3Array()
	result.append(path[0])
	var anchor_index: int = 0
	for index: int in range(1, path.size() - 1):
		var previous: Vector3 = path[anchor_index]
		var next_point: Vector3 = path[index + 1]
		## Only drop waypoint if previous→next is safely navigable with clearance.
		if _segment_has_squad_clearance(nav_map, previous, next_point, clearance):
			continue
		result.append(path[index])
		anchor_index = index
	result.append(path[path.size() - 1])
	return result


func _smooth_route_micro_turns(
	nav_map: RID,
	path: PackedVector3Array,
	clearance: float
) -> PackedVector3Array:
	if path.size() < 3:
		return path
	var result: PackedVector3Array = PackedVector3Array()
	result.append(path[0])
	var index: int = 1
	while index < path.size() - 1:
		var previous: Vector3 = result[result.size() - 1]
		var current: Vector3 = path[index]
		var next_point: Vector3 = path[index + 1]
		var in_dir: Vector3 = current - previous
		var out_dir: Vector3 = next_point - current
		in_dir.y = 0.0
		out_dir.y = 0.0
		var can_remove := false
		if in_dir.length_squared() >= 0.0001 and out_dir.length_squared() >= 0.0001:
			in_dir = in_dir.normalized()
			out_dir = out_dir.normalized()
			var turn_dot: float = in_dir.dot(out_dir)
			## Tiny zig-zag / micro-turn: collapse when A→C is clearance-safe.
			if (
				turn_dot >= ROUTE_MICRO_TURN_DOT
				and _segment_has_squad_clearance(nav_map, previous, next_point, clearance)
			):
				can_remove = true
		if can_remove:
			index += 1
			continue
		result.append(current)
		index += 1
	result.append(path[path.size() - 1])
	return result


func _segment_has_squad_clearance(
	nav_map: RID,
	from: Vector3,
	to: Vector3,
	clearance: float
) -> bool:
	var length: float = _horizontal_distance(from, to)
	if length < 0.05:
		return true
	var steps: int = maxi(1, int(ceil(length / ROUTE_SEGMENT_SAMPLE_STEP)))
	var dir: Vector3 = to - from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return true
	dir = dir.normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x)
	for step: int in steps + 1:
		var t: float = float(step) / float(steps)
		var sample: Vector3 = from.lerp(to, t)
		var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, sample)
		if _horizontal_distance(sample, on_mesh) > ROUTE_ON_MESH_TOLERANCE:
			return false
		if not _point_has_lateral_clearance(nav_map, on_mesh, perp, clearance):
			return false
	return true


func _point_has_lateral_clearance(
	nav_map: RID,
	point: Vector3,
	perp: Vector3,
	clearance: float
) -> bool:
	var left: float = _radial_clearance_in_direction(nav_map, point, perp, clearance)
	var right: float = _radial_clearance_in_direction(nav_map, point, -perp, clearance)
	if left >= clearance * 0.85 and right >= clearance * 0.85:
		return true
	## Narrow but centered corridor: allow compression; reject one-sided scraping.
	var balanced: bool = absf(left - right) <= ROUTE_NARROW_BALANCE_TOLERANCE
	var floor_ok: bool = mini(left, right) >= ROUTE_NARROW_CLEARANCE_FLOOR
	return balanced and floor_ok


func _dedupe_route_waypoints(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() <= 1:
		return path
	var result: PackedVector3Array = PackedVector3Array()
	result.append(path[0])
	for index: int in range(1, path.size()):
		if _horizontal_distance(result[result.size() - 1], path[index]) < ROUTE_MIN_WAYPOINT_SPACING:
			## Keep the last point so destination / end vertex is preserved when collapsing.
			if index == path.size() - 1:
				result[result.size() - 1] = path[index]
			continue
		result.append(path[index])
	return result


func _find_nearest_reachable_destination(
	nav_map: RID,
	from: Vector3,
	desired: Vector3
) -> Vector3:
	var direct: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, desired)
	var probe_path: PackedVector3Array = NavigationServer3D.map_get_path(
		nav_map, from, direct, true
	)
	if not probe_path.is_empty() and probe_path.size() >= 2:
		return direct

	for ring: int in range(1, ROUTE_FALLBACK_RING_COUNT + 1):
		var radius: float = ROUTE_FALLBACK_RING_RADIUS * float(ring)
		for step: int in ROUTE_FALLBACK_RING_STEPS:
			var angle: float = TAU * float(step) / float(ROUTE_FALLBACK_RING_STEPS)
			var candidate: Vector3 = desired + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)
			var path: PackedVector3Array = NavigationServer3D.map_get_path(
				nav_map, from, snapped, true
			)
			if not path.is_empty() and path.size() >= 2:
				return snapped
	return Vector3.ZERO


func _refresh_shared_route(ctx: SquadNavContext) -> void:
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return
	ctx.recompute_anchor_median()
	_calculate_shared_route(ctx, members)
	ctx.waypoint_index = 0
	ctx.compressed_passage = false
	ctx.spacing_scale = 1.0
	ctx.stalled_member_ids.clear()
	ctx.last_route_refresh_msec = Time.get_ticks_msec()
	ctx.note_progress(ctx.anchor_position)


func _tick_squads(delta: float) -> void:
	var remove_ids: Array[int] = []
	var total_members: int = 0

	for squad_id: Variant in _squads.keys():
		var ctx: SquadNavContext = _get_squad_context(int(squad_id))
		if ctx == null:
			remove_ids.append(int(squad_id))
			continue
		if ctx.purge_dead_members():
			_rebind_after_purge(ctx)
		if ctx.member_count() <= 0:
			remove_ids.append(int(squad_id))
			continue

		total_members += ctx.member_count()
		if ctx.is_player_squad:
			## Player squads are owned by PlayerRouteNavigation — dissolve leftovers.
			remove_ids.append(int(squad_id))
			continue
		else:
			_advance_anchor(ctx, delta)
			_update_passage_compression(ctx)
			_tick_target_search(ctx, delta)
			_issue_staggered_slot_orders(ctx)
			if _detect_squad_stall(ctx):
				_recover_stalled_squad(ctx)

	for squad_id: int in remove_ids:
		_dissolve_squad(squad_id)

	_diag_member_count = total_members
	_publish_diag()


## Attack-move threat search + shared-waypoint corridor travel (no formation chase).
func _tick_player_squad(ctx: SquadNavContext, delta: float) -> void:
	_tick_target_search(ctx, delta)
	_note_player_squad_progress(ctx)
	_update_player_queue_mode(ctx)
	var advanced: bool = _advance_player_shared_waypoints(ctx)
	if advanced:
		_retarget_player_squad_travel(ctx, true)
	else:
		_retarget_player_idle_or_stale(ctx)
	if _detect_player_squad_stall(ctx):
		_recover_player_squad_stall(ctx)


func _note_player_squad_progress(ctx: SquadNavContext) -> void:
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return
	var median: Vector3 = _compute_members_median(members)
	if _horizontal_distance(median, ctx.last_progress_position) >= PROGRESS_EPSILON:
		ctx.note_progress(median)


## Advance shared waypoint when ~65% of living members reach/pass it. Never wait for stragglers.
func _advance_player_shared_waypoints(ctx: SquadNavContext) -> bool:
	if ctx.in_final_approach:
		return false
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return false

	var median: Vector3 = _compute_members_median(members)
	if _horizontal_distance(median, ctx.strategic_destination) <= FINAL_APPROACH_RADIUS:
		ctx.in_final_approach = true
		if not ctx.route_waypoints.is_empty():
			ctx.waypoint_index = ctx.route_waypoints.size() - 1
		return true

	if ctx.route_waypoints.is_empty():
		ctx.in_final_approach = true
		return true

	var advanced: bool = false
	while ctx.waypoint_index < ctx.route_waypoints.size() - 1:
		var waypoint: Vector3 = ctx.route_waypoints[ctx.waypoint_index]
		var passed: int = 0
		for unit: Variant in members:
			if unit == null or not is_instance_valid(unit) or not unit is Node3D:
				continue
			if _unit_reached_or_passed_waypoint(unit as Node3D, waypoint, ctx):
				passed += 1
		## Single-file queue: advance with the leader — do not wait on trailing workers.
		var needed: int = maxi(1, int(ceil(float(members.size()) * WAYPOINT_MAJORITY_RATIO)))
		if ctx.queue_mode_active:
			needed = 1
			if ctx.queue_leader_id != 0:
				var leader_node: Node3D = SquadNavContext.resolve_living_node3d(
					ctx.queue_leader_id
				)
				if (
					leader_node != null
					and _unit_reached_or_passed_waypoint(leader_node, waypoint, ctx)
				):
					passed = needed
		if passed < needed:
			break
		ctx.waypoint_index += 1
		advanced = true

	if ctx.waypoint_index >= ctx.route_waypoints.size() - 1:
		var last_wp: Vector3 = ctx.route_waypoints[ctx.route_waypoints.size() - 1]
		var at_last: int = 0
		for unit: Variant in members:
			if unit == null or not is_instance_valid(unit) or not unit is Node3D:
				continue
			if _unit_reached_or_passed_waypoint(unit as Node3D, last_wp, ctx):
				at_last += 1
		var last_needed: int = maxi(
			1, int(ceil(float(members.size()) * WAYPOINT_MAJORITY_RATIO))
		)
		if (
			at_last >= last_needed
			or _horizontal_distance(median, ctx.strategic_destination) <= FINAL_APPROACH_RADIUS
		):
			ctx.in_final_approach = true
			advanced = true

	return advanced


func _unit_reached_or_passed_waypoint(
	unit: Node3D,
	waypoint: Vector3,
	ctx: SquadNavContext,
	waypoint_index: int = -1
) -> bool:
	var pos: Vector3 = unit.global_position
	if _horizontal_distance(pos, waypoint) <= WAYPOINT_PASS_DISTANCE:
		return true
	## Count as passed once beyond the waypoint plane along the route.
	var index: int = waypoint_index if waypoint_index >= 0 else ctx.waypoint_index
	var ahead: Vector3 = ctx.strategic_destination
	if index + 1 < ctx.route_waypoints.size():
		ahead = ctx.route_waypoints[index + 1]
	var route_dir: Vector3 = ahead - waypoint
	route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		route_dir = ctx.formation_forward
	route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		return false
	route_dir = route_dir.normalized()
	var from_wp: Vector3 = pos - waypoint
	from_wp.y = 0.0
	## Soft plane cross — do not U-turn to kiss an exact offset coordinate.
	if from_wp.dot(route_dir) >= 0.0:
		return true
	## Closer to the next guide than this one → already past in practice.
	if _horizontal_distance(pos, ahead) + 0.35 < _horizontal_distance(pos, waypoint):
		return true
	return false


## Personal look-ahead index: never behind the shared index; advance while passed.
func _player_personal_waypoint_index(ctx: SquadNavContext, unit_id: int) -> int:
	if ctx.route_waypoints.is_empty():
		return 0
	var last_index: int = ctx.route_waypoints.size() - 1
	var index: int = clampi(ctx.waypoint_index, 0, last_index)
	var unit_node: Node3D = SquadNavContext.resolve_living_node3d(unit_id)
	if unit_node == null:
		return index
	while index < last_index:
		if _unit_reached_or_passed_waypoint(
			unit_node, ctx.route_waypoints[index], ctx, index
		):
			index += 1
		else:
			break
	return index


func _player_desired_travel_target(ctx: SquadNavContext, unit_id: int) -> Vector3:
	if ctx.in_final_approach or ctx.route_waypoints.is_empty():
		return ctx.get_final_arrival_slot(unit_id)
	return _player_corridor_travel_target(ctx, unit_id)


func _player_corridor_travel_target(ctx: SquadNavContext, unit_id: int) -> Vector3:
	if ctx.route_waypoints.is_empty():
		return ctx.get_final_arrival_slot(unit_id)
	## Temporary single-file: shared centerline + longitudinal trail, no lateral lanes.
	if ctx.queue_mode_active:
		return _player_queue_travel_target(ctx, unit_id)
	var index: int = _player_personal_waypoint_index(ctx, unit_id)
	## Finished the corridor personally — proceed to frozen final slot without waiting.
	if index >= ctx.route_waypoints.size() - 1:
		var unit_node: Node3D = SquadNavContext.resolve_living_node3d(unit_id)
		var last_wp: Vector3 = ctx.route_waypoints[ctx.route_waypoints.size() - 1]
		if (
			unit_node != null
			and _unit_reached_or_passed_waypoint(
				unit_node, last_wp, ctx, ctx.route_waypoints.size() - 1
			)
		):
			return ctx.get_final_arrival_slot(unit_id)
	var waypoint: Vector3 = ctx.route_waypoints[mini(index, ctx.route_waypoints.size() - 1)]
	var lane: Vector3 = ctx.travel_offsets.get(unit_id, Vector3.ZERO) as Vector3
	var lateral: float = lane.x * ctx.queue_lateral_scale
	if absf(lateral) < 0.05:
		return waypoint
	return _safe_corridor_offset_target(ctx, index, waypoint, lateral)


## Path-relative offset with mandatory navigability. Spacing is optional; center is always safe.
func _safe_corridor_offset_target(
	ctx: SquadNavContext,
	waypoint_index: int,
	waypoint: Vector3,
	lateral_meters: float
) -> Vector3:
	var nav_map: RID = _resolve_nav_map(ctx.get_living_members())
	if not nav_map.is_valid():
		return waypoint

	var prev: Vector3 = waypoint
	if waypoint_index > 0:
		prev = ctx.route_waypoints[waypoint_index - 1]
	elif not ctx.route_waypoints.is_empty():
		prev = ctx.route_waypoints[0]
	var next: Vector3 = ctx.strategic_destination
	if waypoint_index + 1 < ctx.route_waypoints.size():
		next = ctx.route_waypoints[waypoint_index + 1]

	var route_dir: Vector3 = next - prev
	route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		route_dir = next - waypoint
		route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		route_dir = ctx.formation_forward
	route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		return waypoint
	route_dir = route_dir.normalized()
	var right: Vector3 = Vector3(-route_dir.z, 0.0, route_dir.x)

	## Inside of a sharp bend → collapse lateral toward corridor center.
	var scale: float = 1.0
	if waypoint_index > 0 and waypoint_index + 1 < ctx.route_waypoints.size():
		var in_dir: Vector3 = waypoint - prev
		var out_dir: Vector3 = next - waypoint
		in_dir.y = 0.0
		out_dir.y = 0.0
		if in_dir.length_squared() > 0.0001 and out_dir.length_squared() > 0.0001:
			in_dir = in_dir.normalized()
			out_dir = out_dir.normalized()
			var turn_dot: float = in_dir.dot(out_dir)
			if turn_dot < TRAVEL_CORNER_DOT:
				var turn_sign: float = signf(in_dir.cross(out_dir).y)
				var lane_sign: float = signf(lateral_meters)
				## Same sign as turn = inside lane around the bend.
				if turn_sign != 0.0 and lane_sign != 0.0 and turn_sign == lane_sign:
					scale = 0.0
				else:
					## Outside lane: still shrink a bit so the approach stays on-mesh.
					scale = clampf((turn_dot + 1.0) * 0.5, 0.25, 1.0)

	var desired_lateral: float = lateral_meters * scale
	if absf(desired_lateral) < 0.05:
		return waypoint

	## Shrink toward center until the offset point itself is navigable with unit clearance.
	for step: int in range(TRAVEL_OFFSET_VALIDATE_STEPS + 1):
		var t: float = 1.0 - float(step) / float(TRAVEL_OFFSET_VALIDATE_STEPS)
		var candidate: Vector3 = waypoint + right * (desired_lateral * t)
		if _corridor_offset_point_is_safe(nav_map, waypoint, candidate, right):
			return candidate
	return waypoint


## --- Temporary small-group single-file (queue) through constrained route sections ---


func is_unit_in_queue_mode(_unit: Variant) -> bool:
	## Player queue/follow-the-leader mode removed.
	return false


func get_player_queue_mode_debug(_unit: Variant) -> Dictionary:
	return {
		"queue_mode": false,
		"leader_id": 0,
		"follower_count": 0,
		"waypoint_index": -1,
		"lateral_offset_scale": 1.0,
		"stuck_recovery": false,
	}


func _update_player_queue_mode(_ctx: SquadNavContext) -> void:
	## Queue / follow-the-leader bypassed — PlayerRouteNavigation owns player travel.
	return


func _player_route_section_is_constrained(ctx: SquadNavContext) -> bool:
	if ctx.route_waypoints.is_empty():
		return false
	var last_index: int = ctx.route_waypoints.size() - 1
	var probe_index: int = clampi(ctx.waypoint_index, 0, last_index)
	## When already queued, require clearance a bit further ahead before exiting.
	if ctx.queue_mode_active:
		probe_index = clampi(
			ctx.waypoint_index + QUEUE_EXIT_HYSTERESIS_WPS, 0, last_index
		)

	var nav_map: RID = _resolve_nav_map(ctx.get_living_members())
	if not nav_map.is_valid():
		return false

	var clearance_limit: float = (
		QUEUE_EXIT_CLEARANCE if ctx.queue_mode_active else QUEUE_ENTER_CLEARANCE
	)
	if _route_waypoint_min_clearance(nav_map, ctx, probe_index) < clearance_limit:
		return true
	if _route_waypoint_has_sharp_turn(ctx, probe_index):
		return true
	## Several members scraping static geometry on the same segment → force single-file.
	if _player_squad_near_static_count(ctx) >= QUEUE_STATIC_NEAR_COUNT:
		return true
	return false


func _route_waypoint_min_clearance(
	nav_map: RID,
	ctx: SquadNavContext,
	waypoint_index: int
) -> float:
	if ctx.route_waypoints.is_empty():
		return SQUAD_ROUTE_CLEARANCE
	var index: int = clampi(waypoint_index, 0, ctx.route_waypoints.size() - 1)
	var point: Vector3 = ctx.route_waypoints[index]
	var prev: Vector3 = point
	if index > 0:
		prev = ctx.route_waypoints[index - 1]
	var next: Vector3 = ctx.strategic_destination
	if index + 1 < ctx.route_waypoints.size():
		next = ctx.route_waypoints[index + 1]
	var route_dir: Vector3 = next - prev
	route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		route_dir = ctx.formation_forward
	route_dir.y = 0.0
	if route_dir.length_squared() < 0.0001:
		return SQUAD_ROUTE_CLEARANCE
	route_dir = route_dir.normalized()
	var perp := Vector3(-route_dir.z, 0.0, route_dir.x)
	var left: float = _radial_clearance_in_direction(
		nav_map, point, perp, SQUAD_ROUTE_CLEARANCE
	)
	var right: float = _radial_clearance_in_direction(
		nav_map, point, -perp, SQUAD_ROUTE_CLEARANCE
	)
	return minf(left, right)


func _route_waypoint_has_sharp_turn(ctx: SquadNavContext, waypoint_index: int) -> bool:
	if ctx.route_waypoints.size() < 3:
		return false
	var index: int = clampi(waypoint_index, 1, ctx.route_waypoints.size() - 2)
	var prev: Vector3 = ctx.route_waypoints[index - 1]
	var current: Vector3 = ctx.route_waypoints[index]
	var next: Vector3 = ctx.route_waypoints[index + 1]
	var in_dir: Vector3 = current - prev
	var out_dir: Vector3 = next - current
	in_dir.y = 0.0
	out_dir.y = 0.0
	if in_dir.length_squared() < 0.0001 or out_dir.length_squared() < 0.0001:
		return false
	return in_dir.normalized().dot(out_dir.normalized()) < TRAVEL_CORNER_DOT


func _player_squad_near_static_count(ctx: SquadNavContext) -> int:
	var count: int = 0
	for unit: Variant in ctx.get_living_members():
		if unit == null or not is_instance_valid(unit) or not unit is CharacterBody3D:
			continue
		if _unit_near_static_obstacle(unit as CharacterBody3D):
			count += 1
	return count


func _unit_near_static_obstacle(body: CharacterBody3D) -> bool:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var world: World3D = body.get_world_3d()
	if world == null:
		return false
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var from: Vector3 = body.global_position + Vector3(0.0, 0.4, 0.0)
	## Probe four cardinals — building corner contact is enough to queue.
	var dirs: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
	]
	for dir: Vector3 in dirs:
		var to: Vector3 = from + dir * QUEUE_STATIC_NEAR_DIST
		var ray := PhysicsRayQueryParameters3D.create(from, to)
		ray.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
		ray.exclude = [body.get_rid()]
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var collider: Variant = hit.get("collider")
		## Ignore other units — only static world / buildings pin corners.
		if collider is Unit:
			continue
		return true
	return false


func _enter_player_queue_mode(ctx: SquadNavContext) -> void:
	ctx.queue_mode_active = true
	ctx.queue_lateral_scale = QUEUE_LATERAL_SCALE_ACTIVE
	ctx.queue_stuck_recovery = false
	_rebuild_player_queue_order(ctx)
	## Already-pinned members: collapse onto shared centerline (same command / route).
	for unit: Variant in ctx.get_living_members():
		if unit == null or not is_instance_valid(unit) or not unit is Unit:
			continue
		var unit_typed: Unit = unit as Unit
		if not unit_typed.matches_player_squad_command(ctx.command_generation):
			continue
		if not _unit_near_static_obstacle(unit_typed):
			continue
		collapse_unit_travel_offset_to_center(unit_typed)
		ctx.queue_stuck_recovery = true
	_retarget_player_squad_travel(ctx, true)


func _exit_player_queue_mode(ctx: SquadNavContext, retarget: bool) -> void:
	ctx.queue_mode_active = false
	ctx.queue_leader_id = 0
	ctx.queue_order_ids.clear()
	ctx.queue_lateral_scale = 1.0
	## Keep stuck_recovery flag for path-debug until the next enter / new command.
	if retarget:
		_retarget_player_squad_travel(ctx, true)


func _rebuild_player_queue_order(ctx: SquadNavContext) -> void:
	ctx.queue_order_ids.clear()
	ctx.queue_leader_id = 0
	var scored: Array[Dictionary] = []
	for unit: Variant in ctx.get_living_members():
		if unit == null or not is_instance_valid(unit) or not unit is Node3D:
			continue
		var unit_id: int = (unit as Node).get_instance_id()
		var progress: float = _unit_route_progress_meters(ctx, unit_id)
		scored.append({"id": unit_id, "progress": progress})
	## Front-most along the shared route leads; stable secondary key = instance id.
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: float = float(a.get("progress", 0.0))
		var pb: float = float(b.get("progress", 0.0))
		if absf(pa - pb) > 0.05:
			return pa > pb
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	for entry: Dictionary in scored:
		ctx.queue_order_ids.append(int(entry.get("id", 0)))
	if not ctx.queue_order_ids.is_empty():
		ctx.queue_leader_id = ctx.queue_order_ids[0]


func _unit_route_progress_meters(ctx: SquadNavContext, unit_id: int) -> float:
	if ctx.route_waypoints.is_empty():
		return 0.0
	var unit_node: Node3D = SquadNavContext.resolve_living_node3d(unit_id)
	if unit_node == null:
		return 0.0
	var pos: Vector3 = unit_node.global_position
	var best_dist: float = INF
	var best_progress: float = 0.0
	var cumulative: float = 0.0
	for index: int in ctx.route_waypoints.size() - 1:
		var a: Vector3 = ctx.route_waypoints[index]
		var b: Vector3 = ctx.route_waypoints[index + 1]
		var seg: Vector3 = b - a
		seg.y = 0.0
		var seg_len: float = seg.length()
		if seg_len < 0.0001:
			continue
		var to_pos: Vector3 = pos - a
		to_pos.y = 0.0
		var t: float = clampf(to_pos.dot(seg) / (seg_len * seg_len), 0.0, 1.0)
		var closest: Vector3 = a + seg * t
		var dist: float = _horizontal_distance(pos, closest)
		if dist < best_dist:
			best_dist = dist
			best_progress = cumulative + seg_len * t
		cumulative += seg_len
	## Past the last waypoint → count full route length.
	if (
		_horizontal_distance(pos, ctx.route_waypoints[ctx.route_waypoints.size() - 1])
		<= WAYPOINT_PASS_DISTANCE
	):
		return maxf(best_progress, cumulative)
	return best_progress


func _sample_route_at_distance(ctx: SquadNavContext, distance: float) -> Vector3:
	if ctx.route_waypoints.is_empty():
		return ctx.strategic_destination
	if distance <= 0.0:
		return ctx.route_waypoints[0]
	var remaining: float = distance
	for index: int in ctx.route_waypoints.size() - 1:
		var a: Vector3 = ctx.route_waypoints[index]
		var b: Vector3 = ctx.route_waypoints[index + 1]
		var seg: Vector3 = b - a
		seg.y = 0.0
		var seg_len: float = seg.length()
		if seg_len < 0.0001:
			continue
		if remaining <= seg_len:
			return a.lerp(b, remaining / seg_len)
		remaining -= seg_len
	return ctx.route_waypoints[ctx.route_waypoints.size() - 1]


## Queue-mode guide: shared corridor centerline with longitudinal trailing only.
func _player_queue_travel_target(ctx: SquadNavContext, unit_id: int) -> Vector3:
	if ctx.route_waypoints.is_empty():
		return ctx.get_final_arrival_slot(unit_id)
	if ctx.queue_order_ids.is_empty() or ctx.queue_leader_id == 0:
		_rebuild_player_queue_order(ctx)

	var rank: int = ctx.queue_order_ids.find(unit_id)
	if rank < 0:
		## New member mid-command: append at the rear without reshuffling the whole order.
		ctx.queue_order_ids.append(unit_id)
		rank = ctx.queue_order_ids.size() - 1

	## Leader follows the shared route centerline (no lateral offset, no overtake cap).
	if unit_id == ctx.queue_leader_id or rank <= 0:
		var lead_index: int = _player_personal_waypoint_index(ctx, unit_id)
		if lead_index >= ctx.route_waypoints.size() - 1:
			var lead_node: Node3D = SquadNavContext.resolve_living_node3d(unit_id)
			var last_wp: Vector3 = ctx.route_waypoints[ctx.route_waypoints.size() - 1]
			if (
				lead_node != null
				and _unit_reached_or_passed_waypoint(
					lead_node, last_wp, ctx, ctx.route_waypoints.size() - 1
				)
			):
				return ctx.get_final_arrival_slot(unit_id)
		return ctx.route_waypoints[mini(lead_index, ctx.route_waypoints.size() - 1)]

	var leader_progress: float = _unit_route_progress_meters(ctx, ctx.queue_leader_id)
	## Trail behind the leader on the same polyline — never cut inside with a lateral lane.
	var trail_progress: float = maxf(0.0, leader_progress - float(rank) * QUEUE_TRAIL_SPACING)
	var trail_point: Vector3 = _sample_route_at_distance(ctx, trail_progress)
	## Soft cap: do not aim past the unit immediately ahead along the queue.
	if rank >= 1:
		var ahead_id: int = ctx.queue_order_ids[rank - 1]
		var ahead_progress: float = _unit_route_progress_meters(ctx, ahead_id)
		var capped: float = maxf(0.0, ahead_progress - QUEUE_TRAIL_SPACING * 0.65)
		if trail_progress > capped:
			trail_point = _sample_route_at_distance(ctx, capped)
	return trail_point


func _corridor_offset_point_is_safe(
	nav_map: RID,
	center: Vector3,
	candidate: Vector3,
	perp: Vector3
) -> bool:
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)
	if _horizontal_distance(candidate, snapped) > ROUTE_ON_MESH_TOLERANCE:
		return false
	## Must keep unit-radius clearance; one-sided scrape against a building is rejected.
	if not _point_has_lateral_clearance(nav_map, snapped, perp, TRAVEL_OFFSET_CLEARANCE):
		return false
	## Straight center→offset must stay on the mesh (no cutting the building corner).
	if not _segment_has_squad_clearance(nav_map, center, snapped, TRAVEL_OFFSET_CLEARANCE * 0.85):
		return false
	return true


## Lateral corridor offsets removed; rejoin validated route guide instead.
func collapse_unit_travel_offset_to_center(unit: Variant) -> Vector3:
	return PlayerRouteNavigation.resolve_travel_target(unit)


## Debug helper: travel offsets removed for player routes.
func get_unit_travel_offset(_unit: Variant) -> Vector3:
	return Vector3.ZERO


## True when the unit has passed its currently issued route guide.
func unit_has_passed_current_guide(unit: Variant) -> bool:
	return PlayerRouteNavigation.unit_has_passed_current_guide(unit)


func _retarget_player_squad_travel(ctx: SquadNavContext, force_all: bool) -> void:
	var members: Array = ctx.get_living_members()
	for unit: Variant in members:
		if unit == null or not is_instance_valid(unit) or not unit is Unit:
			continue
		var unit_typed: Unit = unit as Unit
		if not unit_typed.matches_player_squad_command(ctx.command_generation):
			continue
		## Do not yank units off active combat — they resume via attack-move afterward.
		if _player_unit_is_busy_fighting(unit_typed):
			continue
		if force_all or _player_unit_needs_travel_reissue(ctx, unit_typed):
			_issue_player_travel_target(ctx, unit_typed)


func _retarget_player_idle_or_stale(ctx: SquadNavContext) -> void:
	var members: Array = ctx.get_living_members()
	for unit: Variant in members:
		if unit == null or not is_instance_valid(unit) or not unit is Unit:
			continue
		var unit_typed: Unit = unit as Unit
		if not unit_typed.matches_player_squad_command(ctx.command_generation):
			continue
		if _player_unit_is_busy_fighting(unit_typed):
			continue
		if _player_unit_needs_travel_reissue(ctx, unit_typed):
			_issue_player_travel_target(ctx, unit_typed)


func _player_unit_is_busy_fighting(unit: Unit) -> bool:
	if not ("_attack_target" in unit):
		return false
	var attack_target: Variant = unit.get("_attack_target")
	if not NodeSafety.is_alive_node(attack_target) or not attack_target is Node3D:
		return false
	return CombatTargetValidation.is_valid_combat_target(attack_target as Node3D)


func _player_unit_needs_travel_reissue(ctx: SquadNavContext, unit: Unit) -> bool:
	var unit_id: int = unit.get_instance_id()
	var desired: Vector3 = _player_desired_travel_target(ctx, unit_id)
	## Queue followers: trail points drift with the leader — reissue by guide distance only.
	if ctx.queue_mode_active and unit_id != ctx.queue_leader_id:
		if not unit.has_move_target:
			if _horizontal_distance(unit.global_position, desired) > unit.get_soft_arrival_radius():
				return true
			return false
		if _horizontal_distance(unit.get_movement_destination(), desired) > SLOT_DEST_THRESHOLD * 0.65:
			return true
		if ctx.last_issued_slots.has(unit_id):
			var previous_q: Vector3 = ctx.last_issued_slots[unit_id] as Vector3
			if _horizontal_distance(previous_q, desired) > SLOT_DEST_THRESHOLD * 0.65:
				return true
		return false
	var personal_wp: int = _player_personal_waypoint_index(ctx, unit_id)
	var expected_wp: int = -1 if ctx.in_final_approach else personal_wp
	## Leaders that finished the corridor personally use final-slot guide (-1).
	if (
		not ctx.in_final_approach
		and personal_wp >= ctx.route_waypoints.size() - 1
		and not ctx.route_waypoints.is_empty()
	):
		var last_wp: Vector3 = ctx.route_waypoints[ctx.route_waypoints.size() - 1]
		if _unit_reached_or_passed_waypoint(unit, last_wp, ctx, personal_wp):
			expected_wp = -1
	var issued_wp: int = int(ctx.last_issued_waypoint_index.get(unit_id, -999))
	if issued_wp != expected_wp:
		return true
	if not unit.has_move_target:
		if _horizontal_distance(unit.global_position, desired) > unit.get_soft_arrival_radius():
			return true
		return false
	if ctx.last_issued_slots.has(unit_id):
		var previous: Vector3 = ctx.last_issued_slots[unit_id] as Vector3
		if _horizontal_distance(previous, desired) > SLOT_DEST_THRESHOLD:
			return true
	## Current agent target drifted from look-ahead guide.
	if _horizontal_distance(unit.get_movement_destination(), desired) > SLOT_DEST_THRESHOLD:
		return true
	return false


func _issue_player_travel_target(ctx: SquadNavContext, unit: Unit) -> bool:
	var unit_id: int = unit.get_instance_id()
	var final_slot: Vector3 = ctx.get_final_arrival_slot(unit_id)
	var travel: Vector3 = _player_desired_travel_target(ctx, unit_id)
	var personal_wp: int = _player_personal_waypoint_index(ctx, unit_id)
	var issued_index: int = -1 if ctx.in_final_approach else personal_wp
	if (
		not ctx.in_final_approach
		and personal_wp >= ctx.route_waypoints.size() - 1
		and not ctx.route_waypoints.is_empty()
	):
		var last_wp: Vector3 = ctx.route_waypoints[ctx.route_waypoints.size() - 1]
		if _unit_reached_or_passed_waypoint(unit, last_wp, ctx, personal_wp):
			issued_index = -1
	## Skip no-op reissues of the same guide.
	if (
		unit.has_move_target
		and int(ctx.last_issued_waypoint_index.get(unit_id, -999)) == issued_index
		and _horizontal_distance(unit.get_movement_destination(), travel) <= 0.35
	):
		ctx.last_issued_slots[unit_id] = travel
		ctx.last_issued_waypoint_index[unit_id] = issued_index
		return false
	var applied: bool = unit.request_corridor_travel_target(travel, final_slot)
	## Always record the intended guide so we do not reissue every tick when already near.
	ctx.last_issued_slots[unit_id] = travel
	ctx.last_issued_waypoint_index[unit_id] = issued_index
	if applied:
		_player_diag["target_replacements"] = int(_player_diag["target_replacements"]) + 1
		PerfCounters.record_squad_local_repath()
	return applied


func _compute_members_median(members: Array) -> Vector3:
	var xs: Array[float] = []
	var zs: Array[float] = []
	var y_sum: float = 0.0
	for unit: Variant in members:
		if unit == null or not is_instance_valid(unit) or not unit is Node3D:
			continue
		if (unit as Node3D).is_queued_for_deletion():
			continue
		var pos: Vector3 = (unit as Node3D).global_position
		xs.append(pos.x)
		zs.append(pos.z)
		y_sum += pos.y
	if xs.is_empty():
		return Vector3.ZERO
	xs.sort()
	zs.sort()
	var mid: int = xs.size() / 2
	return Vector3(xs[mid], y_sum / float(xs.size()), zs[mid])


func _detect_player_squad_stall(ctx: SquadNavContext) -> bool:
	if ctx.arrival_slots_frozen and _player_squad_mostly_arrived(ctx):
		return false
	if ctx.seconds_since_progress() < STALL_TIMEOUT_SECONDS:
		return false
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return false
	var median: Vector3 = _compute_members_median(members)
	return _horizontal_distance(median, ctx.last_progress_position) < PROGRESS_EPSILON


func _player_squad_mostly_arrived(ctx: SquadNavContext) -> bool:
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return true
	var arrived: int = 0
	for unit: Variant in members:
		if unit == null or not is_instance_valid(unit) or not unit is Node3D:
			continue
		var unit_node: Node3D = unit as Node3D
		if unit_node.is_queued_for_deletion():
			continue
		var unit_id: int = unit_node.get_instance_id()
		var slot: Vector3 = ctx.get_final_arrival_slot(unit_id)
		if _horizontal_distance(unit_node.global_position, slot) <= 4.0:
			arrived += 1
	return arrived >= maxi(1, int(ceil(float(members.size()) * 0.7)))


## Player stall: refresh strategic route metadata, re-issue current travel targets only.
## Never regenerates or rotates arrival slots. Never whole-group reshuffle for one blocker.
func _recover_player_squad_stall(ctx: SquadNavContext) -> void:
	var now_msec: int = Time.get_ticks_msec()
	var since_refresh: float = float(now_msec - ctx.last_route_refresh_msec) / 1000.0
	if since_refresh < ROUTE_RECALC_COOLDOWN_SECONDS:
		return
	var age_sec: float = float(now_msec - ctx.route_created_msec) / 1000.0
	if age_sec < ROUTE_RECALC_COOLDOWN_SECONDS * 0.5:
		return

	_diag_stalls += 1
	_player_diag["stall_recovery_count"] = int(_player_diag["stall_recovery_count"]) + 1
	_player_diag["repath_count"] = int(_player_diag["repath_count"]) + 1
	PerfCounters.record_squad_stall()

	## Preserve frozen arrival slots and original click across strategic refresh.
	var frozen_slots: Dictionary = ctx.final_arrival_slots.duplicate()
	var frozen_offsets: Dictionary = ctx.travel_offsets.duplicate()
	var frozen_forward: Vector3 = ctx.formation_forward
	var requested: Vector3 = ctx.requested_destination
	var accepted: Vector3 = ctx.strategic_destination
	var was_final: bool = ctx.in_final_approach
	## Drop temporary queue — next tick re-enters if the refreshed section is still tight.
	_exit_player_queue_mode(ctx, false)
	_refresh_shared_route(ctx)
	ctx.final_arrival_slots = frozen_slots
	ctx.travel_offsets = frozen_offsets
	ctx.arrival_slots_frozen = true
	ctx.formation_forward = frozen_forward
	ctx.requested_destination = requested
	ctx.strategic_destination = accepted
	_bootstrap_player_waypoint_index(ctx)
	if was_final:
		ctx.in_final_approach = true

	var stalled_ids: Dictionary = ctx.stalled_member_ids.duplicate()
	ctx.stalled_member_ids.clear()
	for unit_id: Variant in stalled_ids.keys():
		var node: Object = instance_from_id(int(unit_id))
		if node == null or not is_instance_valid(node) or not node is Unit:
			continue
		var unit: Unit = node as Unit
		if not unit.matches_player_squad_command(ctx.command_generation):
			_player_diag["stale_callback_blocks"] = int(_player_diag["stale_callback_blocks"]) + 1
			continue
		ctx.last_issued_waypoint_index.erase(int(unit_id))
		var travel: Vector3 = _player_desired_travel_target(ctx, int(unit_id))
		var final_slot: Vector3 = ctx.get_final_arrival_slot(int(unit_id))
		if unit.request_corridor_travel_target(
			travel,
			final_slot,
			Unit.RepathUrgency.STUCK_RECOVERY
		):
			ctx.last_issued_slots[int(unit_id)] = travel
			var personal_wp: int = _player_personal_waypoint_index(ctx, int(unit_id))
			ctx.last_issued_waypoint_index[int(unit_id)] = (
				-1 if ctx.in_final_approach else personal_wp
			)
			_player_diag["target_replacements"] = int(_player_diag["target_replacements"]) + 1
			PerfCounters.record_squad_local_repath()


func _advance_anchor(ctx: SquadNavContext, delta: float) -> void:
	if ctx.is_route_finished():
		ctx.anchor_position = ctx.strategic_destination
		return

	var previous: Vector3 = ctx.anchor_position
	var target_point: Vector3 = ctx.strategic_destination
	if not ctx.route_waypoints.is_empty():
		target_point = ctx.route_waypoints[mini(ctx.waypoint_index, ctx.route_waypoints.size() - 1)]
		while (
			ctx.waypoint_index < ctx.route_waypoints.size() - 1
			and _horizontal_distance(ctx.anchor_position, target_point) <= WAYPOINT_REACH_DISTANCE
		):
			ctx.waypoint_index += 1
			target_point = ctx.route_waypoints[ctx.waypoint_index]

	var move_dir: Vector3 = target_point - ctx.anchor_position
	move_dir.y = 0.0
	if move_dir.length_squared() < 0.0001:
		return
	var step: float = ANCHOR_MOVE_SPEED * delta
	if move_dir.length() <= step:
		ctx.anchor_position = target_point
	else:
		ctx.anchor_position += move_dir.normalized() * step

	var tangent: Vector3 = move_dir.normalized()
	if tangent.length_squared() >= 0.01:
		ctx.formation_forward = tangent

	if _horizontal_distance(previous, ctx.anchor_position) >= PROGRESS_EPSILON:
		ctx.note_progress(ctx.anchor_position)


func _update_passage_compression(ctx: SquadNavContext) -> void:
	var width: float = _estimate_formation_width(ctx)
	var narrow: bool = width > NARROW_PASSAGE_WIDTH and ctx.member_count() >= 6
	if narrow == ctx.compressed_passage:
		return
	ctx.compressed_passage = narrow
	ctx.spacing_scale = COMPRESSED_SPACING_SCALE if narrow else 1.0


func _estimate_formation_width(ctx: SquadNavContext) -> float:
	var max_x: float = 0.0
	for local: Variant in ctx.slot_locals.values():
		if local is Vector3:
			max_x = maxf(max_x, absf((local as Vector3).x))
	return max_x * FORMATION_SPACING * 2.0


func _tick_target_search(ctx: SquadNavContext, delta: float) -> void:
	if not ctx.use_attack_move:
		return
	ctx.target_search_timer -= delta
	if ctx.target_search_timer > 0.0:
		return
	ctx.target_search_timer = TARGET_SEARCH_INTERVAL + randf() * TARGET_SEARCH_JITTER

	var members: Array = ctx.get_living_members()
	if members.is_empty():
		ctx.set_shared_threat_target(null)
		return

	var probe_variant: Variant = members[0]
	if (
		probe_variant == null
		or not is_instance_valid(probe_variant)
		or not probe_variant is Node3D
	):
		ctx.set_shared_threat_target(null)
		return
	var probe: Node3D = probe_variant as Node3D
	if probe.is_queued_for_deletion():
		ctx.set_shared_threat_target(null)
		return

	var search_range: float = 30.0
	if probe is MilitaryUnit:
		search_range = maxf(
			(probe as MilitaryUnit).attack_range,
			MilitaryUnit.ATTACK_MOVE_ENGAGEMENT_RANGE
		)
	var found: Node3D = null
	if CombatTargetValidation.is_enemy_faction(probe):
		found = CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			probe, search_range + 8.0
		)
	else:
		found = CombatTargetValidation.find_best_auto_acquire_target_in_range(
			probe, search_range + 8.0
		)
	ctx.set_shared_threat_target(found)
	_distribute_threats(ctx, found, members)


func _distribute_threats(ctx: SquadNavContext, threat: Node3D, members: Array) -> void:
	if not NodeSafety.is_alive_node(threat):
		return
	for unit: Variant in members:
		if unit == null or not is_instance_valid(unit) or not unit is Node3D:
			continue
		if (unit as Node3D).is_queued_for_deletion():
			continue
		var unit_node: Node3D = unit as Node3D
		var unit_id: int = unit_node.get_instance_id()
		# Preserve valid existing targets.
		var existing: Node3D = ctx.get_member_threat(unit_id)
		if existing != null and CombatTargetValidation.is_valid_combat_target(existing):
			continue
		var max_range: float = 24.0
		if unit is MilitaryUnit:
			max_range = maxf(
				(unit as MilitaryUnit).attack_range,
				MilitaryUnit.ATTACK_MOVE_ENGAGEMENT_RANGE
			)
		if CombatTargetValidation.get_horizontal_attack_distance(unit_node, threat) <= max_range:
			ctx.set_member_threat(unit_id, threat)


func _issue_staggered_slot_orders(ctx: SquadNavContext) -> void:
	if ctx.is_player_squad:
		return
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return
	var budget: int = UNIT_UPDATE_BUDGET_PER_SQUAD
	var start: int = ctx.stagger_cursor % maxi(members.size(), 1)
	ctx.stagger_cursor = (start + budget) % maxi(members.size(), 1)

	for offset: int in budget:
		var index: int = (start + offset) % members.size()
		var unit_variant: Variant = members[index]
		if (
			unit_variant == null
			or not is_instance_valid(unit_variant)
			or not unit_variant is Node3D
		):
			continue
		var unit_node: Node3D = unit_variant as Node3D
		if unit_node.is_queued_for_deletion():
			continue
		## Re-check squad membership / generation before applying staggered work.
		if not ctx.contains_unit_id(unit_node.get_instance_id()):
			continue
		_issue_slot_order_for_unit(ctx, unit_node)


func _collect_initial_orders(
	ctx: SquadNavContext,
	ordered_units: Array,
	use_attack_move: bool,
	mission: int
) -> Array:
	var orders: Array = []
	var budget: int = mini(ordered_units.size(), MAX_INITIAL_ORDERS)
	for index: int in budget:
		var unit: Variant = ordered_units[index]
		if unit == null or not is_instance_valid(unit) or not unit is Node:
			continue
		if (unit as Node).is_queued_for_deletion():
			continue
		var unit_id: int = (unit as Node).get_instance_id()
		var target: Vector3 = ctx.get_slot_world_position(unit_id)
		orders.append({
			"unit_id": unit_id,
			"command_generation": ctx.command_generation,
			"squad_id": ctx.squad_id,
			"target": target,
			"use_attack_move": use_attack_move,
			"mission": mission,
		})
		ctx.last_issued_slots[unit_id] = target
	return orders


func _issue_slot_order_for_unit(ctx: SquadNavContext, unit: Node3D) -> void:
	## Player squads never chase live formation slots.
	if ctx.is_player_squad:
		return

	var unit_id: int = unit.get_instance_id()
	var slot_target: Vector3 = ctx.get_slot_world_position(unit_id)
	slot_target = GroupMoveSpacing.resolve_formation_position(
		slot_target, ctx.strategic_destination
	)

	var dist_to_slot: float = _horizontal_distance(unit.global_position, slot_target)
	if dist_to_slot <= SLOT_SKIP_DISTANCE:
		if unit.has_method("is_confirmed_stuck") and VariantUtils.to_bool(unit.call("is_confirmed_stuck")):
			pass
		else:
			return

	if ctx.last_issued_slots.has(unit_id):
		var previous: Vector3 = ctx.last_issued_slots[unit_id] as Vector3
		if _horizontal_distance(previous, slot_target) < SLOT_DEST_THRESHOLD:
			return

	if unit.has_method("_should_skip_repath_while_engaged"):
		if VariantUtils.to_bool(unit.call("_should_skip_repath_while_engaged")):
			return

	var applied := false
	if ctx.use_attack_move and unit.has_method("command_attack_move"):
		applied = VariantUtils.to_bool(
			unit.call(
				"command_attack_move",
				slot_target,
				Unit.RepathUrgency.FORMATION
			)
		)
	elif unit.has_method("request_movement_target"):
		applied = VariantUtils.to_bool(
			unit.call("request_movement_target", slot_target, Unit.RepathUrgency.FORMATION)
		)
	elif unit.has_method("set_movement_target"):
		applied = VariantUtils.to_bool(
			unit.call("set_movement_target", slot_target, Unit.RepathUrgency.FORMATION)
		)

	if applied:
		ctx.last_issued_slots[unit_id] = slot_target
		PerfCounters.record_squad_local_repath()
		PerfCounters.record_ai_order()


func _issue_player_orders(ctx: SquadNavContext, members: Array, order_kind: StringName) -> void:
	if not ctx.arrival_slots_frozen:
		_freeze_player_arrival_slots(ctx)

	var issued: int = 0
	for index: int in members.size():
		var unit: Variant = members[index]
		if not NodeSafety.is_alive_node(unit) or not unit is Unit:
			continue
		var unit_typed: Unit = unit as Unit
		var unit_id: int = unit_typed.get_instance_id()
		var final_slot: Vector3 = ctx.get_final_arrival_slot(unit_id)
		var travel: Vector3 = _player_desired_travel_target(ctx, unit_id)
		unit_typed.bind_player_squad_command(
			ctx.command_generation,
			ctx.requested_destination,
			final_slot,
			order_kind
		)
		## Order bookkeeping uses the frozen final; navigation follows the corridor guide.
		if order_kind == &"attack_move" and unit_typed.supports_combat_orders():
			unit_typed.issue_order(UnitOrder.attack_move(final_slot), false)
		else:
			_issue_unit_ground_order(unit_typed, travel, order_kind, false)
		unit_typed.request_corridor_travel_target(travel, final_slot)
		ctx.last_issued_slots[unit_id] = travel
		var personal_wp: int = _player_personal_waypoint_index(ctx, unit_id)
		ctx.last_issued_waypoint_index[unit_id] = (
			-1 if ctx.in_final_approach else personal_wp
		)
		issued += 1

	if ctx.is_player_squad:
		_player_diag["orders_issued"] = issued
		## Initial issue is not a continuous formation refresh.
		_player_diag["formation_refresh_count"] = 0
		_player_diag["target_replacements"] = 0


func _detect_squad_stall(ctx: SquadNavContext) -> bool:
	if ctx.is_route_finished():
		return false
	if ctx.seconds_since_progress() < STALL_TIMEOUT_SECONDS:
		return false
	return _horizontal_distance(ctx.anchor_position, ctx.last_progress_position) < PROGRESS_EPSILON


func _recover_stalled_squad(ctx: SquadNavContext) -> void:
	var now_msec: int = Time.get_ticks_msec()
	var since_refresh: float = float(now_msec - ctx.last_route_refresh_msec) / 1000.0
	if since_refresh < ROUTE_RECALC_COOLDOWN_SECONDS:
		return
	var age_sec: float = float(now_msec - ctx.route_created_msec) / 1000.0
	if age_sec < ROUTE_RECALC_COOLDOWN_SECONDS * 0.5:
		return
	_diag_stalls += 1
	PerfCounters.record_squad_stall()
	_refresh_shared_route(ctx)
	# Re-issue a bounded batch of local slot targets after strategic refresh.
	var members: Array = ctx.get_living_members()
	var budget: int = mini(members.size(), UNIT_UPDATE_BUDGET_PER_SQUAD)
	for index: int in budget:
		var unit_variant: Variant = members[index]
		if (
			unit_variant == null
			or not is_instance_valid(unit_variant)
			or not unit_variant is Node3D
		):
			continue
		var unit_node: Node3D = unit_variant as Node3D
		if unit_node.is_queued_for_deletion():
			continue
		ctx.last_issued_slots.erase(unit_node.get_instance_id())
		_issue_slot_order_for_unit(ctx, unit_node)


func _find_reusable_squad(equiv_signature: String) -> SquadNavContext:
	for squad_id: Variant in _squads.keys():
		var ctx: SquadNavContext = _get_squad_context(int(squad_id))
		if ctx == null:
			continue
		if ctx.equivalence_signature == equiv_signature:
			return ctx
	return null


func _bind_members(ctx: SquadNavContext, units: Array) -> void:
	for unit: Variant in units:
		if unit == null or not is_instance_valid(unit) or not unit is Node:
			continue
		var unit_node: Node = unit as Node
		if unit_node.is_queued_for_deletion():
			continue
		var unit_id: int = unit_node.get_instance_id()
		var existing_squad: int = int(_unit_to_squad.get(unit_id, -1))
		if existing_squad >= 0 and existing_squad != ctx.squad_id:
			_remove_unit_by_id(unit_id, &"rebind")
		_unit_to_squad[unit_id] = ctx.squad_id
		if not ctx.member_ids.has(unit_id):
			ctx.member_ids.append(unit_id)
		_watch_unit(unit_node)


func _rebind_after_purge(ctx: SquadNavContext) -> void:
	for unit_id: int in ctx.member_ids:
		_unit_to_squad[unit_id] = ctx.squad_id
	var stale: Array = []
	for unit_id: Variant in _unit_to_squad.keys():
		if int(_unit_to_squad[unit_id]) == ctx.squad_id and not ctx.member_ids.has(int(unit_id)):
			stale.append(unit_id)
	for unit_id: Variant in stale:
		_report_stale_cleanup(
			ctx.squad_id,
			int(unit_id),
			"_unit_to_squad",
			ctx.command_generation,
			&"prune"
		)
		_unit_to_squad.erase(unit_id)
		_disconnect_unit_exit_handler(int(unit_id))


func _dissolve_squad(squad_id: int) -> void:
	var ctx: SquadNavContext = _get_squad_context(squad_id)
	if ctx == null:
		_squads.erase(squad_id)
		return
	var member_snapshot: Array[int] = ctx.member_ids.duplicate()
	for unit_id: int in member_snapshot:
		_unit_to_squad.erase(unit_id)
		_disconnect_unit_exit_handler(unit_id)
		var node: Object = instance_from_id(unit_id)
		if node != null and is_instance_valid(node) and node is Unit:
			(node as Unit).clear_player_squad_command()
	ctx.member_ids.clear()
	ctx.slot_locals.clear()
	ctx.final_arrival_slots.clear()
	ctx.travel_offsets.clear()
	ctx.last_issued_waypoint_index.clear()
	ctx.member_threats.clear()
	ctx.last_issued_slots.clear()
	ctx.stalled_member_ids.clear()
	ctx.shared_threat_id = 0
	_squads.erase(squad_id)


func _build_equivalence_signature(
	member_ids: Array[int],
	destination: Vector3,
	mission: int,
	use_attack_move: bool
) -> String:
	var ids: Array[int] = member_ids.duplicate()
	ids.sort()
	var bx: int = int(floor(destination.x / DEST_BUCKET_SIZE))
	var bz: int = int(floor(destination.z / DEST_BUCKET_SIZE))
	return "%d|%d|%d|%d|%d" % [
		mission,
		1 if use_attack_move else 0,
		bx,
		bz,
		hash(ids),
	]


func _build_command_signature(
	member_ids: Array[int],
	destination: Vector3,
	mission: int,
	use_attack_move: bool,
	generation: int
) -> String:
	return "%d|%s" % [
		generation,
		_build_equivalence_signature(member_ids, destination, mission, use_attack_move),
	]


func _filter_military_units(units: Array) -> Array:
	var result: Array = []
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Worker:
			continue
		if unit is Unit:
			result.append(unit)
	return result


## All movable units for ordinary player group ground commands (includes workers).
func _filter_movable_units(units: Array) -> Array:
	var result: Array = []
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Unit:
			result.append(unit)
	return result


func _order_units_for_formation(units: Array) -> Array:
	var keyed: Array = []
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue
		keyed.append({
			"id": (unit as Node).get_instance_id(),
			"unit": unit,
		})
	keyed.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return int(a["id"]) < int(b["id"])
	)
	var result: Array = []
	for entry: Variant in keyed:
		result.append(entry["unit"])
	return result


func _collect_unit_ids(units: Array) -> Array[int]:
	var ids: Array[int] = []
	for unit: Variant in units:
		if NodeSafety.is_alive_node(unit):
			ids.append((unit as Node).get_instance_id())
	ids.sort()
	return ids


func _has_siege(units: Array) -> bool:
	for unit: Variant in units:
		if NodeSafety.is_alive_node(unit):
			if UnitFormationRole.get_role(unit as Node) == UnitFormationRole.Role.SIEGE:
				return true
	return false


func _resolve_nav_map(units: Array) -> RID:
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue
		var world: World3D = (unit as Node3D).get_world_3d()
		if world != null:
			var nav_map: RID = world.navigation_map
			if nav_map.is_valid():
				return nav_map
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.current_scene is Node3D:
		var world: World3D = (tree.current_scene as Node3D).get_world_3d()
		if world != null:
			return world.navigation_map
	return RID()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _publish_diag() -> void:
	PerfCounters.set_squad_nav_status(
		is_shared_navigation_enabled(),
		_squads.size(),
		_diag_member_count,
		_diag_stalls
	)


func get_active_squad_count() -> int:
	return _squads.size()


func get_active_member_count() -> int:
	return _diag_member_count


func get_route_failure_count() -> int:
	return _diag_route_failures


func get_stall_count() -> int:
	return _diag_stalls
