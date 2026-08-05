extends Node

## Centralized shared squad navigation: one strategic route per group command,
## stable role slots, staggered local follower destinations.

const ANCHOR_TICK_INTERVAL := 0.25
const UNIT_UPDATE_BUDGET_PER_SQUAD := 5
const DEST_BUCKET_SIZE := 2.0
const WAYPOINT_REACH_DISTANCE := 3.25
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

## Stall recovery ownership (escalation order):
## 1. Local steering / UnitSeparation while progress exists
## 2. Per-unit confirmed stall → local repath / waypoint / yield+detour
## 3. Shared strategic route refresh (this system) when group is stalled
## 4. Cancel / finish only as final per-unit fallback when not in a squad
## Worker gather/build keep specialized task recovery; do not add extra nudges.

var _squads: Dictionary = {} ## squad_id -> SquadNavContext
var _unit_to_squad: Dictionary = {} ## unit_instance_id -> squad_id
var _next_squad_id: int = 1
var _global_command_generation: int = 0
var _anchor_accum: float = 0.0
var _diag_member_count: int = 0
var _diag_stalls: int = 0
var _diag_route_failures: int = 0


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
	_squads.clear()
	_unit_to_squad.clear()
	_next_squad_id = 1
	_global_command_generation = 0
	_diag_member_count = 0
	_diag_stalls = 0
	_diag_route_failures = 0
	_publish_diag()


func is_shared_navigation_enabled() -> bool:
	return MilitaryAIConfig.is_shared_squad_nav_enabled()


func get_squad_for_unit(unit: Variant) -> SquadNavContext:
	if unit == null or not is_instance_valid(unit) or not (unit is Node):
		return null
	var squad_id: int = int(_unit_to_squad.get((unit as Node).get_instance_id(), -1))
	if squad_id < 0:
		return null
	return _squads.get(squad_id) as SquadNavContext


func release_unit(unit: Variant) -> void:
	if unit == null or not is_instance_valid(unit) or not (unit is Node):
		return
	var unit_id: int = (unit as Node).get_instance_id()
	if not _unit_to_squad.has(unit_id):
		return
	var squad_id: int = int(_unit_to_squad[unit_id])
	_unit_to_squad.erase(unit_id)
	var ctx: SquadNavContext = _squads.get(squad_id) as SquadNavContext
	if ctx == null:
		return
	ctx.member_ids.erase(unit_id)
	ctx.slot_locals.erase(unit_id)
	ctx.member_threats.erase(unit_id)
	ctx.last_issued_slots.erase(unit_id)
	ctx.stalled_member_ids.erase(unit_id)
	if ctx.member_count() <= 0:
		_squads.erase(squad_id)


## Called by Unit local recovery when a squad member exhausted local stages.
## Shared route refresh is owned here — units must not cancel while still in a squad.
func notify_member_confirmed_stall(unit: Variant) -> bool:
	var ctx: SquadNavContext = get_squad_for_unit(unit)
	if ctx == null or unit == null or not is_instance_valid(unit):
		return false
	var unit_id: int = (unit as Node).get_instance_id()
	ctx.stalled_member_ids[unit_id] = true
	var stalled: int = ctx.stalled_member_ids.size()
	var threshold: int = maxi(1, int(ceil(float(ctx.member_count()) * MEMBER_STALL_REFRESH_RATIO)))
	if stalled >= threshold or _detect_squad_stall(ctx):
		_recover_stalled_squad(ctx)
	return true


func try_get_assigned_target(unit: Variant) -> Node3D:
	var ctx: SquadNavContext = get_squad_for_unit(unit)
	if ctx == null:
		return null
	if unit == null or not is_instance_valid(unit):
		return null
	var unit_id: int = (unit as Node).get_instance_id()
	if ctx.member_threats.has(unit_id):
		var assigned: Variant = ctx.member_threats[unit_id]
		if NodeSafety.is_alive_node(assigned) and assigned is Node3D:
			var target: Node3D = assigned as Node3D
			if CombatTargetValidation.is_valid_combat_target(target):
				var search_range: float = 28.0
				if unit is MilitaryUnit:
					search_range = maxf(
						(unit as MilitaryUnit).attack_range,
						MilitaryUnit.ATTACK_MOVE_ENGAGEMENT_RANGE
					)
				if CombatTargetValidation.get_horizontal_attack_distance(unit as Node3D, target) <= (
					search_range + 4.0
				):
					return target
	if NodeSafety.is_alive_node(ctx.shared_threat_target):
		return ctx.shared_threat_target
	return null


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


## Player / formation-manager entry: one squad per formation group.
func issue_formation_command(
	formation_id: int,
	members: Array,
	destination: Vector3,
	order_kind: StringName,
	group: FormationGroup
) -> Dictionary:
	var result: Dictionary = {
		"handled": false,
		"equivalent_skip": false,
	}
	if not is_shared_navigation_enabled():
		return result
	if members.size() <= 1 or destination == Vector3.ZERO or group == null:
		return result

	var ordered_units: Array = _filter_military_units(members)
	if ordered_units.size() <= 1:
		return result

	result["handled"] = true
	_global_command_generation += 1
	var member_ids: Array[int] = _collect_unit_ids(ordered_units)
	var mission: int = 0 if order_kind == &"move" else 1
	var use_attack_move: bool = order_kind == &"attack_move"
	var equiv_signature: String = _build_equivalence_signature(
		member_ids, destination, mission, use_attack_move
	)
	var signature: String = "player|%d|%d|%s" % [
		formation_id, _global_command_generation, equiv_signature
	]

	var ctx_existing: SquadNavContext = _find_reusable_squad(equiv_signature)
	if (
		ctx_existing != null
		and ctx_existing.is_player_squad
		and ctx_existing.command_signature.begins_with("player|%d|" % formation_id)
	):
		_bind_members(ctx_existing, ordered_units)
		result["equivalent_skip"] = true
		PerfCounters.record_squad_route_cache_hit()
		_publish_diag()
		return result

	var ctx: SquadNavContext = _create_squad_context(
		ordered_units,
		destination,
		use_attack_move,
		mission,
		_global_command_generation,
		signature,
		true,
		group
	)
	if ctx == null:
		result["handled"] = false
		return result

	_issue_player_orders(ctx, ordered_units, order_kind)
	_publish_diag()
	return result


## Player unformed multi-unit selection (workers + military): one shared route + slots.
## Queued orders only store spaced destinations — live squad activates on current commands.
func issue_player_group_command(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	queued: bool = false
) -> Dictionary:
	var result: Dictionary = {
		"handled": false,
		"equivalent_skip": false,
		"route_valid": false,
		"accepted_destination": destination,
	}
	if not is_shared_navigation_enabled():
		return result

	var ordered_units: Array = _order_units_for_formation(_filter_movable_units(units))
	if ordered_units.size() <= 1 or destination == Vector3.ZERO:
		return result

	# Shift-queued: stable unique slots only. Do not start a live shared route yet.
	if queued:
		result["handled"] = true
		var spacing: float = _compute_member_spacing(ordered_units)
		var slot_targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
			destination, ordered_units.size(), spacing
		)
		for index: int in ordered_units.size():
			var unit: Variant = ordered_units[index]
			if not NodeSafety.is_alive_node(unit) or not unit is Unit:
				continue
			var target: Vector3 = GroupMoveSpacing.resolve_nearby_walkable_position(
				slot_targets[index], unit as Node3D, destination, spacing
			)
			_issue_unit_ground_order(unit as Unit, target, order_kind, true)
		return result

	var use_attack_move: bool = order_kind == &"attack_move"
	var mission: int = 0 if order_kind == &"move" else 1
	var member_ids: Array[int] = _collect_unit_ids(ordered_units)
	var equiv_signature: String = _build_equivalence_signature(
		member_ids, destination, mission, use_attack_move
	)

	var existing: SquadNavContext = _find_reusable_squad(equiv_signature)
	if existing != null:
		result["handled"] = true
		result["equivalent_skip"] = true
		result["route_valid"] = existing.route_valid
		result["accepted_destination"] = existing.strategic_destination
		_bind_members(existing, ordered_units)
		PerfCounters.record_squad_route_cache_hit()
		_publish_diag()
		return result

	_global_command_generation += 1
	var signature: String = "player_group|%d|%s" % [
		_global_command_generation, equiv_signature
	]
	var ctx: SquadNavContext = _create_squad_context(
		ordered_units,
		destination,
		use_attack_move,
		mission,
		_global_command_generation,
		signature,
		true,
		null
	)
	if ctx == null:
		return result

	result["handled"] = true
	result["route_valid"] = ctx.route_valid
	result["accepted_destination"] = ctx.strategic_destination
	_issue_player_orders(ctx, ordered_units, order_kind)
	_publish_diag()
	return result


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
	_assign_stable_slots(ctx, ordered_units, group)
	_calculate_shared_route(ctx, ordered_units)
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
	var requested: Vector3 = ctx.requested_destination
	if requested == Vector3.ZERO:
		requested = ctx.strategic_destination

	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		ctx.strategic_destination = requested
		ctx.route_waypoints = PackedVector3Array([ctx.anchor_position, requested])
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
	ctx.route_waypoints = path
	ctx.waypoint_index = 0
	var face: Vector3 = ctx.strategic_destination - ctx.anchor_position
	face.y = 0.0
	if face.length_squared() >= 0.01:
		ctx.formation_forward = face.normalized()
	elif path.size() >= 2:
		var segment: Vector3 = path[1] - path[0]
		segment.y = 0.0
		if segment.length_squared() >= 0.01:
			ctx.formation_forward = segment.normalized()


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
		var ctx: SquadNavContext = _squads[squad_id] as SquadNavContext
		if ctx == null:
			remove_ids.append(int(squad_id))
			continue
		if ctx.purge_dead_members():
			_rebind_after_purge(ctx)
		if ctx.member_count() <= 0:
			remove_ids.append(int(squad_id))
			continue

		total_members += ctx.member_count()
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
		return
	var probe: Node3D = members[0] as Node3D
	var search_range: float = 30.0
	if probe is MilitaryUnit:
		search_range = maxf(
			(probe as MilitaryUnit).attack_range,
			MilitaryUnit.ATTACK_MOVE_ENGAGEMENT_RANGE
		)
	var anchor_probe: Node3D = probe
	var found: Node3D = null
	if CombatTargetValidation.is_enemy_faction(probe):
		found = CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			anchor_probe, search_range + 8.0
		)
	else:
		found = CombatTargetValidation.find_best_auto_acquire_target_in_range(
			anchor_probe, search_range + 8.0
		)
	ctx.shared_threat_target = found
	_distribute_threats(ctx, found, members)


func _distribute_threats(ctx: SquadNavContext, threat: Node3D, members: Array) -> void:
	if not NodeSafety.is_alive_node(threat):
		return
	for unit: Variant in members:
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue
		var unit_node: Node3D = unit as Node3D
		# Preserve valid existing targets.
		var unit_id: int = unit_node.get_instance_id()
		if ctx.member_threats.has(unit_id):
			var existing: Variant = ctx.member_threats[unit_id]
			if NodeSafety.is_alive_node(existing) and CombatTargetValidation.is_valid_combat_target(
				existing
			):
				continue
		var max_range: float = 24.0
		if unit is MilitaryUnit:
			max_range = maxf(
				(unit as MilitaryUnit).attack_range,
				MilitaryUnit.ATTACK_MOVE_ENGAGEMENT_RANGE
			)
		if CombatTargetValidation.get_horizontal_attack_distance(unit_node, threat) <= max_range:
			ctx.member_threats[unit_id] = threat


func _issue_staggered_slot_orders(ctx: SquadNavContext) -> void:
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return
	var budget: int = UNIT_UPDATE_BUDGET_PER_SQUAD
	var start: int = ctx.stagger_cursor % maxi(members.size(), 1)
	ctx.stagger_cursor = (start + budget) % maxi(members.size(), 1)

	for offset: int in budget:
		var index: int = (start + offset) % members.size()
		var unit: Variant = members[index]
		if not NodeSafety.is_alive_node(unit):
			continue
		_issue_slot_order_for_unit(ctx, unit as Node3D)


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
		if not NodeSafety.is_alive_node(unit):
			continue
		var target: Vector3 = ctx.get_slot_world_position((unit as Node).get_instance_id())
		orders.append({
			"unit": unit,
			"target": target,
			"use_attack_move": use_attack_move,
			"mission": mission,
		})
		ctx.last_issued_slots[(unit as Node).get_instance_id()] = target
	return orders


func _issue_slot_order_for_unit(ctx: SquadNavContext, unit: Node3D) -> void:
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
	var accepted: Vector3 = ctx.strategic_destination
	for index: int in members.size():
		var unit: Variant = members[index]
		if not NodeSafety.is_alive_node(unit) or not unit is Unit:
			continue
		var target: Vector3 = ctx.get_slot_world_position((unit as Node).get_instance_id())
		target = GroupMoveSpacing.resolve_formation_position(target, accepted)
		_issue_unit_ground_order(unit as Unit, target, order_kind, false)
		ctx.last_issued_slots[(unit as Node).get_instance_id()] = target


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
		var unit: Variant = members[index]
		if NodeSafety.is_alive_node(unit) and unit is Node3D:
			ctx.last_issued_slots.erase((unit as Node).get_instance_id())
			_issue_slot_order_for_unit(ctx, unit as Node3D)


func _find_reusable_squad(equiv_signature: String) -> SquadNavContext:
	for squad_id: Variant in _squads.keys():
		var ctx: SquadNavContext = _squads[squad_id] as SquadNavContext
		if ctx == null:
			continue
		if ctx.equivalence_signature == equiv_signature:
			return ctx
	return null


func _bind_members(ctx: SquadNavContext, units: Array) -> void:
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue
		var unit_id: int = (unit as Node).get_instance_id()
		var existing_squad: int = int(_unit_to_squad.get(unit_id, -1))
		if existing_squad >= 0 and existing_squad != ctx.squad_id:
			_remove_unit_from_squad(unit_id, existing_squad)
		_unit_to_squad[unit_id] = ctx.squad_id
		if not ctx.member_ids.has(unit_id):
			ctx.member_ids.append(unit_id)


func _remove_unit_from_squad(unit_id: int, squad_id: int) -> void:
	_unit_to_squad.erase(unit_id)
	var ctx: SquadNavContext = _squads.get(squad_id) as SquadNavContext
	if ctx == null:
		return
	ctx.member_ids.erase(unit_id)
	ctx.slot_locals.erase(unit_id)
	ctx.member_threats.erase(unit_id)
	ctx.last_issued_slots.erase(unit_id)
	ctx.stalled_member_ids.erase(unit_id)
	if ctx.member_count() <= 0:
		_squads.erase(squad_id)


func _rebind_after_purge(ctx: SquadNavContext) -> void:
	for unit_id: int in ctx.member_ids:
		_unit_to_squad[unit_id] = ctx.squad_id
	var stale: Array = []
	for unit_id: Variant in _unit_to_squad.keys():
		if int(_unit_to_squad[unit_id]) == ctx.squad_id and not ctx.member_ids.has(int(unit_id)):
			stale.append(unit_id)
	for unit_id: Variant in stale:
		_unit_to_squad.erase(unit_id)


func _dissolve_squad(squad_id: int) -> void:
	var ctx: SquadNavContext = _squads.get(squad_id) as SquadNavContext
	if ctx == null:
		_squads.erase(squad_id)
		return
	for unit_id: int in ctx.member_ids:
		_unit_to_squad.erase(unit_id)
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
