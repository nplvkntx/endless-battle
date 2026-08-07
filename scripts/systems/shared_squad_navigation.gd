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
const ROUTE_END_ACCEPT_DISTANCE := 4.0
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
	_reset_player_move_telemetry()


func get_player_move_telemetry() -> Dictionary:
	return _player_diag.duplicate()


func _reset_player_move_telemetry() -> void:
	_player_diag = {
		"command_generation": 0,
		"clicked_position": Vector3.ZERO,
		"accepted_destination": Vector3.ZERO,
		"stable_slot_count": 0,
		"shared_route_count": 0,
		"route_waypoint_count": 0,
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


## Issue or refresh a squad command. Returns pending per-unit orders for the caller to drain.
## When shared nav owns the attempt but the route is invalid: handled=true, route_valid=false,
## pending_orders empty — callers must not fall through to fabricated direct movement.
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
		"route_valid": false,
		"route_failure_reason": "",
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
		if not ctx.route_valid:
			result["route_valid"] = false
			result["route_failure_reason"] = (
				ctx.route_failure_reason if not ctx.route_failure_reason.is_empty() else "no_path"
			)
			return result
		result["equivalent_skip"] = true
		result["route_valid"] = true
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

	if not ctx.route_valid:
		var fail_reason: String = (
			ctx.route_failure_reason if not ctx.route_failure_reason.is_empty() else "no_path"
		)
		_dissolve_squad(ctx.squad_id)
		result["route_valid"] = false
		result["route_failure_reason"] = fail_reason
		result["pending_orders"] = []
		_publish_diag()
		return result

	result["route_valid"] = true
	result["pending_orders"] = _collect_initial_orders(ctx, ordered_units, use_attack_move, mission)
	_publish_diag()
	return result


## Player / formation-manager entry: one squad per formation group.
## Uses stable final arrival slots — no continuous formation steering while travelling.
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

	## Player formation: do not rewrite player movement here — if the shared route is
	## invalid, release ownership so FormationManager can use its existing path.
	if not ctx.route_valid:
		_dissolve_squad(ctx.squad_id)
		result["handled"] = false
		return result

	ctx.command_type = order_kind
	_freeze_player_arrival_slots(ctx)
	_issue_player_orders(ctx, ordered_units, order_kind)
	_publish_diag()
	return result


## Player unformed multi-unit selection (workers + military): one shared route +
## stable final arrival slots issued once. No continuous anchor-slot following.
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
		"route_failure_reason": "",
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

	## Every fresh click is authoritative — do not soft-skip equivalent destinations.
	_global_command_generation += 1
	var signature: String = "player_group|%d|%s" % [
		_global_command_generation, equiv_signature
	]
	_reset_player_move_telemetry()
	_player_diag["command_generation"] = _global_command_generation
	_player_diag["clicked_position"] = destination

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

	## Invalid shared route: release squad and let SelectionManager fall through to
	## existing per-unit orders — do not fabricate a direct corridor for the player.
	if not ctx.route_valid:
		result["route_failure_reason"] = (
			ctx.route_failure_reason if not ctx.route_failure_reason.is_empty() else "no_path"
		)
		_dissolve_squad(ctx.squad_id)
		return result

	ctx.command_type = order_kind
	_freeze_player_arrival_slots(ctx)
	result["handled"] = true
	result["route_valid"] = ctx.route_valid
	result["accepted_destination"] = ctx.strategic_destination
	_player_diag["accepted_destination"] = ctx.strategic_destination
	_player_diag["shared_route_count"] = 1
	_player_diag["route_waypoint_count"] = ctx.route_waypoints.size()
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
	ctx.route_failure_reason = ""
	ctx.route_waypoints = PackedVector3Array()
	ctx.waypoint_index = 0
	var requested: Vector3 = ctx.requested_destination
	if requested == Vector3.ZERO:
		requested = ctx.strategic_destination
	ctx.requested_destination = requested
	## Keep the original request visible even when routing fails.
	ctx.strategic_destination = requested

	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		_fail_shared_route(ctx, "nav_map_not_ready")
		return

	var from: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, ctx.anchor_position)
	if from == Vector3.ZERO and ctx.anchor_position != Vector3.ZERO:
		_fail_shared_route(ctx, "start_not_on_nav")
		return
	if _horizontal_distance(ctx.anchor_position, from) > ROUTE_SNAP_ACCEPT_DISTANCE:
		_fail_shared_route(ctx, "start_not_on_nav")
		return

	var to: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, requested)
	if to == Vector3.ZERO and requested != Vector3.ZERO:
		_fail_shared_route(ctx, "destination_not_on_nav")
		return

	## Reject absurd snaps far from the click when a closer reachable point exists.
	if _horizontal_distance(requested, to) > ROUTE_SNAP_ACCEPT_DISTANCE:
		var nearest: Vector3 = _find_nearest_reachable_destination(nav_map, from, requested)
		if nearest != Vector3.ZERO:
			to = nearest
		else:
			_fail_shared_route(ctx, "destination_projection_failed")
			return

	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
	PerfCounters.record_squad_strategic_route()

	if path.is_empty() or path.size() < 2:
		var fallback: Vector3 = _find_nearest_reachable_destination(nav_map, from, to)
		if fallback != Vector3.ZERO:
			to = fallback
			path = NavigationServer3D.map_get_path(nav_map, from, to, true)

	if path.is_empty() or path.size() < 2:
		_fail_shared_route(ctx, "no_path")
		return

	var path_end: Vector3 = path[path.size() - 1]
	if _horizontal_distance(path_end, to) > ROUTE_END_ACCEPT_DISTANCE:
		_fail_shared_route(ctx, "no_path")
		return

	ctx.route_valid = true
	ctx.route_failure_reason = ""
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


func _fail_shared_route(ctx: SquadNavContext, reason: String) -> void:
	ctx.route_valid = false
	ctx.route_failure_reason = reason
	ctx.route_waypoints = PackedVector3Array()
	ctx.waypoint_index = 0
	## Preserve the original request; never invent a traversable direct segment.
	if ctx.requested_destination != Vector3.ZERO:
		ctx.strategic_destination = ctx.requested_destination
	_diag_route_failures += 1


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
			## Player squads: no continuous formation steering.
			## Units keep their one-shot stable arrival destinations.
			_tick_player_squad(ctx, delta)
		elif not ctx.route_valid:
			## Invalid strategic route: hold membership/tokens, do not invent movement.
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


## Attack-move threat search + real-unit progress tracking. Never reissues formation targets.
func _tick_player_squad(ctx: SquadNavContext, delta: float) -> void:
	_tick_target_search(ctx, delta)
	_note_player_squad_progress(ctx)
	if _detect_player_squad_stall(ctx):
		_recover_player_squad_stall(ctx)


func _note_player_squad_progress(ctx: SquadNavContext) -> void:
	var members: Array = ctx.get_living_members()
	if members.is_empty():
		return
	var median: Vector3 = _compute_members_median(members)
	if _horizontal_distance(median, ctx.last_progress_position) >= PROGRESS_EPSILON:
		ctx.note_progress(median)


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


## Player stall: refresh strategic route metadata, re-issue original frozen slots only.
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
	var frozen_forward: Vector3 = ctx.formation_forward
	var requested: Vector3 = ctx.requested_destination
	var accepted: Vector3 = ctx.strategic_destination
	_refresh_shared_route(ctx)
	ctx.final_arrival_slots = frozen_slots
	ctx.arrival_slots_frozen = true
	ctx.formation_forward = frozen_forward
	ctx.requested_destination = requested
	ctx.strategic_destination = accepted

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
		var target: Vector3 = ctx.get_final_arrival_slot(int(unit_id))
		if unit.request_movement_target(target, Unit.RepathUrgency.STUCK_RECOVERY):
			ctx.last_issued_slots[int(unit_id)] = target
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
	if not ctx.route_valid:
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
		var target: Vector3 = ctx.get_final_arrival_slot(unit_id)
		unit_typed.bind_player_squad_command(
			ctx.command_generation,
			ctx.requested_destination,
			target,
			order_kind
		)
		_issue_unit_ground_order(unit_typed, target, order_kind, false)
		ctx.last_issued_slots[unit_id] = target
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
	if not ctx.route_valid:
		return
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
		if ctx.equivalence_signature == equiv_signature and ctx.route_valid:
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
