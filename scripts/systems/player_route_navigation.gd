extends Node

## Custom RTS movement authority (sole strategic movement foundation).
## One shared strategic grid route per group command + automatic formation
## slots assigned once per command + lightweight local separation.
## Used by player SelectionManager, production rally, and enemy army march.

const SLOT_SPACING := 1.7
const GROUND_Y := 0.0
const FORMATION_LINE_MAX := 5
const FORMATION_RECTANGLE_MAX := 15
const FORMATION_SHAPE_LINE := &"line"
const FORMATION_SHAPE_RECTANGLE := &"rectangle"
const FORMATION_SHAPE_SQUARE := &"square"
## Meaningful army travel chunk before briefly gathering the main force.
## Map is 100m across; Spearman 4.5 m/s, cavalry 8.5 m/s, heroes ~5.4–6.0.
const ARMY_MARCH_SEGMENT_DISTANCE := 16.0
## Cluster tolerance around the current checkpoint — not pixel-perfect overlap.
const MARCH_ARRIVAL_RADIUS := 6.0
const ARMY_MARCH_READY_FRACTION := 0.75
const ARMY_MARCH_MAX_GATHER_SECONDS := 4.0
const ARMY_MARCH_OBJECTIVE_EQUIV_RADIUS := 4.0
const ENEMY_ARMY_MARCH_SOURCE: StringName = &"enemy_ai"

var grid: PlayerRtsOccupancyGrid = PlayerRtsOccupancyGrid.new()
## Same occupancy cells, dynamic unit/building instance IDs for neighbors + acquire.
var spatial: UnitSpatialHash = UnitSpatialHash.new()

var _global_command_generation: int = 0
var path_calculations_this_command: int = 0
var total_path_calculations: int = 0
var _grid_ready: bool = false
var _scan_pending: bool = false

## Last player group-move telemetry for compact diagnostics.
var last_command_source: StringName = &""
var last_squad_size: int = 0
var last_route_waypoints: int = 0

## Enemy army cohesive-march execution (HOW). EnemyAI still owns WHAT.
var _army_march_active: bool = false
var _army_march_mode: StringName = &""
var _army_march_route: PackedVector3Array = PackedVector3Array()
var _army_march_route_cum: PackedFloat32Array = PackedFloat32Array()
var _army_march_final: Vector3 = Vector3.ZERO
var _army_march_clicked: Vector3 = Vector3.ZERO
var _army_march_order_kind: StringName = &""
var _army_march_generation: int = -1
var _army_march_checkpoint: Vector3 = Vector3.ZERO
var _army_march_checkpoint_dist: float = 0.0
var _army_march_cap_index: int = 0
var _army_march_segment_index: int = 0
var _army_march_member_ids: PackedInt64Array = PackedInt64Array()
var _army_march_prev_checkpoint: Vector3 = Vector3.ZERO
var _army_march_last_arrived: int = -1
var _army_march_last_required: int = -1
var _army_march_last_waiting_name: String = ""
var _army_march_logged_hero_ids: Dictionary = {}
var _army_march_gather_seconds: float = 0.0


func _ready() -> void:
	MatchSession.register_match_reset(&"PlayerRouteNavigation", clear_all)
	_setup_default_grid()
	set_process(false)
	set_physics_process(false)


func clear_all() -> void:
	_global_command_generation = 0
	path_calculations_this_command = 0
	total_path_calculations = 0
	last_command_source = &""
	last_squad_size = 0
	last_route_waypoints = 0
	_clear_army_march()
	grid.clear_all()
	spatial.clear()
	_grid_ready = true
	_scan_pending = true
	call_deferred("_scan_static_obstacles_if_needed")


func ensure_grid_ready() -> void:
	if not _grid_ready:
		_setup_default_grid()
	if _scan_pending:
		_scan_static_obstacles()


func register_static_obstacle(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	ensure_grid_ready()
	var footprint: Dictionary = _resolve_footprint(body)
	if footprint.is_empty():
		# Explicitly clear when footprint becomes walkable (e.g. open gate).
		grid.clear_obstacle(body.get_instance_id())
		grid.commit()
		update_combat_occupant(body)
		return
	grid.set_obstacle_aabb(
		body.get_instance_id(),
		footprint["center"] as Vector3,
		footprint["half_extents"] as Vector3
	)
	grid.commit()
	update_combat_occupant(body)


func unregister_static_obstacle(body: Node3D) -> void:
	if body == null:
		return
	var obstacle_id: int = body.get_instance_id()
	if not grid.has_obstacle(obstacle_id):
		return
	grid.clear_obstacle(obstacle_id)
	grid.commit()
	# Combat occupant stays until the node leaves the tree (foundations still exist).


func refresh_static_obstacle(body: Node3D) -> void:
	unregister_static_obstacle(body)
	register_static_obstacle(body)


## Canonical shared group / single-unit Move / Attack-Move / Patrol for the player.
## Returns handled=true when custom routing issued orders.
## `command_source` is telemetry/provenance context (e.g. &"player", &"rally").
func request_group_move(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	queued: bool = false,
	command_source: StringName = &"player"
) -> Dictionary:
	var result: Dictionary = {
		"handled": false,
		"route_valid": false,
		"accepted_destination": destination,
		"path_calculations": 0,
		"route_waypoints": 0,
		"squad_size": 0,
		"slot_targets": [],
		"route_failure_reason": "",
	}
	var ordered_units: Array = _filter_movable_units(units)
	if ordered_units.is_empty() or destination == Vector3.ZERO:
		return result

	ensure_grid_ready()
	result["squad_size"] = ordered_units.size()

	# Shift-queued: unique slots only; each unit paths individually when the order runs.
	if queued:
		result["handled"] = true
		var queued_origin: Vector3 = _group_centroid(ordered_units)
		var queued_plan: Dictionary = _plan_group_formation(
			ordered_units, destination, queued_origin, PackedVector3Array()
		)
		var queued_slots: Array[Vector3] = queued_plan["slots"] as Array[Vector3]
		for index: int in ordered_units.size():
			var unit: Unit = ordered_units[index] as Unit
			var slot: Vector3 = queued_slots[index] if index < queued_slots.size() else destination
			_issue_unit_ground_order(unit, slot, order_kind, true)
		_record_command_telemetry(ordered_units.size(), 0, command_source)
		return result

	if command_source == ENEMY_ARMY_MARCH_SOURCE:
		return _request_enemy_army_march_move(
			ordered_units, destination, order_kind, command_source, result
		)

	_global_command_generation += 1
	path_calculations_this_command = 0

	var group_destination := Vector3(destination.x, GROUND_Y, destination.z)
	if not grid.is_world_walkable(group_destination):
		group_destination = grid.nearest_walkable_world(group_destination)

	var origin: Vector3 = _group_centroid(ordered_units)
	## Single A* for the whole command — members follow this corridor.
	var shared_route: PackedVector3Array = grid.find_path(origin, group_destination)
	path_calculations_this_command += 1
	total_path_calculations += 1
	result["path_calculations"] = path_calculations_this_command
	result["route_waypoints"] = shared_route.size()
	PerfCounters.record_strategic_route_request()
	PerfCounters.record_navigation_path_request()

	if shared_route.is_empty():
		result["route_failure_reason"] = "no_path"
		_record_command_telemetry(ordered_units.size(), 0, command_source)
		return result

	var plan: Dictionary = _plan_group_formation(
		ordered_units, group_destination, origin, shared_route
	)
	var slots: Array[Vector3] = plan["slots"] as Array[Vector3]
	var locals: Array[Vector3] = plan["locals"] as Array[Vector3]

	var slot_targets_out: Array = []
	for index: int in ordered_units.size():
		var unit: Unit = ordered_units[index] as Unit
		var slot: Vector3 = slots[index] if index < slots.size() else group_destination
		var local: Vector3 = locals[index] if index < locals.size() else Vector3.ZERO
		slot_targets_out.append(slot)
		unit.prepare_custom_rts_route(
			shared_route,
			slot,
			_global_command_generation,
			group_destination,
			order_kind,
			local
		)
		_issue_unit_ground_order(unit, slot, order_kind, false)

	result["handled"] = true
	result["route_valid"] = true
	result["accepted_destination"] = group_destination
	result["slot_targets"] = slot_targets_out
	_record_command_telemetry(ordered_units.size(), shared_route.size(), command_source)
	return result


## Player SelectionManager / production-rally entry.
func issue_player_group_command(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	queued: bool = false,
	command_source: StringName = &"player"
) -> Dictionary:
	return request_group_move(units, destination, order_kind, queued, command_source)


## Bind a fresh custom grid route on one unit without issuing orders or
## canceling worker gather/build tasks. Used by Unit.request_movement_target
## for strategic travel that was not pre-bound by issue_player_group_command.
func bind_unit_strategic_route(
	unit: Unit,
	destination: Vector3,
	command_source: StringName = &"strategic"
) -> bool:
	if not NodeSafety.is_alive_node(unit) or not unit.is_inside_tree():
		return false

	ensure_grid_ready()
	var dest := Vector3(destination.x, GROUND_Y, destination.z)
	if not grid.is_world_walkable(dest):
		dest = grid.nearest_walkable_world(dest)

	var origin := Vector3(unit.global_position.x, GROUND_Y, unit.global_position.z)
	if not grid.is_world_walkable(origin):
		origin = grid.nearest_walkable_world(origin)

	var origin_cell: Vector2i = grid.world_to_cell(origin)
	var dest_cell: Vector2i = grid.world_to_cell(dest)
	var now_msec: int = Time.get_ticks_msec()
	if (
		unit.has_meta(&"_rts_bind_origin_cell")
		and unit.get_meta(&"_rts_bind_origin_cell") == origin_cell
		and unit.get_meta(&"_rts_bind_dest_cell") == dest_cell
		and now_msec - int(unit.get_meta(&"_rts_bind_msec", 0)) < 200
		and unit.is_custom_rts_movement_active()
	):
		return true

	var route: PackedVector3Array = grid.find_path(origin, dest)
	path_calculations_this_command += 1
	total_path_calculations += 1
	PerfCounters.record_strategic_route_request()
	PerfCounters.record_navigation_path_request()
	_global_command_generation += 1
	unit.set_meta(&"_rts_bind_origin_cell", origin_cell)
	unit.set_meta(&"_rts_bind_dest_cell", dest_cell)
	unit.set_meta(&"_rts_bind_msec", now_msec)

	if route.is_empty():
		route = PackedVector3Array([dest])

	unit.prepare_custom_rts_route(
		route,
		dest,
		_global_command_generation,
		dest,
		&"move",
		Vector3.ZERO
	)
	_record_command_telemetry(1, route.size(), command_source)
	return true


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	ensure_grid_ready()
	var start := Vector3(from.x, GROUND_Y, from.z)
	var goal := Vector3(to.x, GROUND_Y, to.z)
	if not grid.is_world_walkable(start):
		start = grid.nearest_walkable_world(start)
	if not grid.is_world_walkable(goal):
		goal = grid.nearest_walkable_world(goal)
	return grid.find_path(start, goal)


func has_path(from: Vector3, to: Vector3) -> bool:
	return not find_path(from, to).is_empty()


func get_command_generation() -> int:
	return _global_command_generation


func get_path_calculations_this_command() -> int:
	return path_calculations_this_command


func get_last_route_waypoints() -> int:
	return last_route_waypoints


func get_last_squad_size() -> int:
	return last_squad_size


func _record_command_telemetry(
	squad_size: int,
	waypoints: int,
	command_source: StringName = &"player"
) -> void:
	last_command_source = command_source
	last_squad_size = squad_size
	last_route_waypoints = waypoints


func is_world_walkable(world: Vector3) -> bool:
	ensure_grid_ready()
	return grid.is_world_walkable(world)


func nearest_walkable_world(world: Vector3) -> Vector3:
	ensure_grid_ready()
	return grid.nearest_walkable_world(world)


func combat_occupant_count() -> int:
	return spatial.occupant_count()


## Register or refresh a unit / creep at its current cell.
func update_mobile_occupant(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	ensure_grid_ready()
	spatial.update_point(body.get_instance_id(), body.global_position)


## Register a building (or other static combat body) across its footprint cells.
func update_combat_occupant(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	ensure_grid_ready()
	if body is Building:
		var footprint: Dictionary = _resolve_footprint(body)
		if footprint.is_empty():
			spatial.update_point(body.get_instance_id(), body.global_position)
			return
		spatial.update_aabb(
			body.get_instance_id(),
			footprint["center"] as Vector3,
			footprint["half_extents"] as Vector3
		)
		return
	spatial.update_point(body.get_instance_id(), body.global_position)


func remove_combat_occupant(body: Node3D) -> void:
	if body == null:
		return
	spatial.remove(body.get_instance_id())


## Nearby live Node3D occupants. Empty when nothing is indexed in range.
## max_count > 0 bounds resolve work so overlapping armies stay O(neighbors), not O(clump).
func query_nearby_nodes(world: Vector3, radius: float, max_count: int = 0) -> Array[Node3D]:
	ensure_grid_ready()
	var started_usec: int = Time.get_ticks_usec()
	var ids: Array[int] = (
		spatial.query_all_ids()
		if is_inf(radius)
		else spatial.query_ids(world, radius, max_count)
	)
	var nodes: Array[Node3D] = _resolve_occupant_nodes(ids, max_count)
	PerfCounters.record_usec(PerfCounters.KEY_QUERY_NEARBY_USEC, Time.get_ticks_usec() - started_usec)
	return nodes


func query_nearby_units(world: Vector3, radius: float, max_count: int = 0) -> Array[Unit]:
	var units: Array[Unit] = []
	for node: Node3D in query_nearby_nodes(world, radius, max_count):
		if node is Unit:
			units.append(node as Unit)
			if max_count > 0 and units.size() >= max_count:
				break
	return units


func _resolve_occupant_nodes(ids: Array[int], max_count: int = 0) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for instance_id: int in ids:
		var node_ref: Variant = instance_from_id(instance_id)
		if not NodeSafety.is_alive_node(node_ref) or not node_ref is Node3D:
			spatial.remove(instance_id)
			continue
		var node: Node3D = node_ref as Node3D
		if not node.is_inside_tree():
			spatial.remove(instance_id)
			continue
		nodes.append(node)
		if max_count > 0 and nodes.size() >= max_count:
			break
	return nodes


func _setup_default_grid() -> void:
	var extent: float = PlayerRtsOccupancyGrid.MAP_MAX - PlayerRtsOccupancyGrid.MAP_MIN
	var cells: int = int(ceil(extent / PlayerRtsOccupancyGrid.DEFAULT_CELL_SIZE))
	grid.setup(
		Vector2(PlayerRtsOccupancyGrid.MAP_MIN, PlayerRtsOccupancyGrid.MAP_MIN),
		cells,
		cells,
		PlayerRtsOccupancyGrid.DEFAULT_CELL_SIZE,
		PlayerRtsOccupancyGrid.DEFAULT_CLEARANCE,
		PlayerRtsOccupancyGrid.DEFAULT_UNIT_RADIUS
	)
	spatial.setup(grid.origin_xz, grid.grid_width, grid.grid_height, grid.cell_size)
	_grid_ready = true
	_scan_pending = true


func _scan_static_obstacles_if_needed() -> void:
	if _scan_pending:
		_scan_static_obstacles()


func _scan_static_obstacles() -> void:
	_scan_pending = false
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	grid.clear_all()

	# Buildings (completed / under construction / walls). Gates handled via footprint helper.
	var buildings: Array[Node] = tree.get_nodes_in_group("buildings")
	if buildings.is_empty():
		# Fallback: walk common building class without requiring group membership.
		for node: Node in tree.get_nodes_in_group("player_buildings"):
			buildings.append(node)
		for node: Node in tree.get_nodes_in_group("enemy_buildings"):
			buildings.append(node)

	for node: Node in buildings:
		if node is Building:
			_register_building_internal(node as Building)

	# Also catch Building nodes not in groups (verify scenes / edge cases).
	var root: Node = tree.current_scene
	if root != null:
		_scan_buildings_recursive(root)

	# Static world blockers on the BUILDINGS layer (walls already covered as Building).
	# Trees intentionally use collision_layer 0 when depleted and are gatherable —
	# only include StaticBody3D that still block the BUILDINGS physics layer.
	_scan_static_bodies_recursive(root if root != null else tree.root)

	grid.commit()
	_reindex_combat_occupants(tree)


func _scan_buildings_recursive(node: Node) -> void:
	if node is Building:
		_register_building_internal(node as Building)
	for child: Node in node.get_children():
		_scan_buildings_recursive(child)


func _scan_static_bodies_recursive(node: Node) -> void:
	if node is GoldMine:
		var mine_footprint: Dictionary = _resolve_footprint(node as Node3D)
		if not mine_footprint.is_empty():
			grid.set_obstacle_aabb(
				node.get_instance_id(),
				mine_footprint["center"] as Vector3,
				mine_footprint["half_extents"] as Vector3
			)
	elif node is StaticBody3D and not (node is Building) and not (node is GatherableResource):
		var body: StaticBody3D = node as StaticBody3D
		if (body.collision_layer & PhysicsLayers.BUILDINGS) != 0:
			var footprint: Dictionary = _resolve_footprint(body)
			if not footprint.is_empty():
				grid.set_obstacle_aabb(
					body.get_instance_id(),
					footprint["center"] as Vector3,
					footprint["half_extents"] as Vector3
				)
	for child: Node in node.get_children():
		_scan_static_bodies_recursive(child)


func _reindex_combat_occupants(tree: SceneTree) -> void:
	if tree == null:
		return
	for group_name: StringName in [&"units", &"heroes", &"enemies", &"neutral_creeps"]:
		for node_variant: Variant in tree.get_nodes_in_group(group_name):
			if node_variant is Unit:
				update_mobile_occupant(node_variant as Unit)
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if node_variant is Building:
			update_combat_occupant(node_variant as Building)


func _register_building_internal(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not building.is_inside_tree():
		return
	## Foundations under construction stay walkable for builder handoff.
	if building.is_being_constructed():
		grid.clear_obstacle(building.get_instance_id())
		update_combat_occupant(building)
		return
	# Open gates: still register posts-only footprint via resolver.
	var footprint: Dictionary = _resolve_footprint(building)
	if footprint.is_empty():
		update_combat_occupant(building)
		return
	grid.set_obstacle_aabb(
		building.get_instance_id(),
		footprint["center"] as Vector3,
		footprint["half_extents"] as Vector3
	)
	update_combat_occupant(building)


func _resolve_footprint(body: Node3D) -> Dictionary:
	if body == null or not is_instance_valid(body):
		return {}

	# Prefer Building collision/placement footprint.
	if body is Building:
		var building: Building = body as Building
		var custom: Vector3 = building.get_rts_occupancy_half_extents()
		if custom.x > 0.0 and custom.z > 0.0:
			return {
				"center": building.global_position,
				"half_extents": custom,
			}
		return {}

	if body is GoldMine:
		var mine: GoldMine = body as GoldMine
		return {
			"center": mine.global_position,
			"half_extents": mine.get_occupancy_half_extents(),
		}

	var collision_shape: CollisionShape3D = (
		body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	if collision_shape == null or collision_shape.shape == null or collision_shape.disabled:
		return {}

	var basis_scale: Vector3 = collision_shape.transform.basis.get_scale()
	var center: Vector3 = body.global_position
	if collision_shape.shape is BoxShape3D:
		var box := collision_shape.shape as BoxShape3D
		return {
			"center": center,
			"half_extents": Vector3(
				absf(box.size.x * basis_scale.x) * 0.5,
				1.0,
				absf(box.size.z * basis_scale.z) * 0.5
			),
		}
	if collision_shape.shape is CylinderShape3D:
		var cylinder := collision_shape.shape as CylinderShape3D
		var radius: float = absf(cylinder.radius * maxf(basis_scale.x, basis_scale.z))
		return {
			"center": center,
			"half_extents": Vector3(radius, 1.0, radius),
		}
	return {}


func _filter_movable_units(units: Array) -> Array:
	var ordered: Array = []
	for unit_ref: Variant in units:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		if not unit_ref is Unit:
			continue
		var unit: Unit = unit_ref as Unit
		if not unit.is_inside_tree():
			continue
		ordered.append(unit)
	ordered.sort_custom(
		func(a: Unit, b: Unit) -> bool:
			return a.get_instance_id() < b.get_instance_id()
	)
	return ordered


func _group_centroid(units: Array) -> Vector3:
	if units.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var count: int = 0
	for unit_ref: Variant in units:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		sum += (unit_ref as Unit).global_position
		count += 1
	if count <= 0:
		return Vector3.ZERO
	var c: Vector3 = sum / float(count)
	c.y = GROUND_Y
	return c


func _plan_group_formation(
	units: Array,
	destination: Vector3,
	origin: Vector3,
	route: PackedVector3Array
) -> Dictionary:
	var count: int = units.size()
	var dest := Vector3(destination.x, GROUND_Y, destination.z)
	var empty_slots: Array[Vector3] = []
	var empty_locals: Array[Vector3] = []
	var result: Dictionary = {
		"slots": empty_slots,
		"locals": empty_locals,
		"shape": FORMATION_SHAPE_LINE,
		"forward": Vector3(0.0, 0.0, 1.0),
		"right": Vector3(1.0, 0.0, 0.0),
	}
	if count <= 0:
		return result

	var forward: Vector3 = _formation_travel_forward(origin, dest, route)
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	if right.length_squared() < 0.0001:
		right = Vector3(1.0, 0.0, 0.0)
	else:
		right = right.normalized()

	var shape: StringName = choose_formation_shape(count)
	var layout: Array[Vector3] = build_formation_locals(count, shape)
	var assigned: Array[Vector3] = _assign_formation_locals(units, layout, origin, forward, right)
	var slots: Array[Vector3] = []
	slots.resize(count)
	for i: int in count:
		var local: Vector3 = assigned[i] if i < assigned.size() else Vector3.ZERO
		var world: Vector3 = dest + right * local.x + forward * local.z
		world.y = GROUND_Y
		slots[i] = _compress_slot_to_walkable(world, dest)

	result["slots"] = slots
	result["locals"] = assigned
	result["shape"] = shape
	result["forward"] = forward
	result["right"] = right
	return result


func choose_formation_shape(count: int) -> StringName:
	if count <= FORMATION_LINE_MAX:
		return FORMATION_SHAPE_LINE
	if count <= FORMATION_RECTANGLE_MAX:
		return FORMATION_SHAPE_RECTANGLE
	return FORMATION_SHAPE_SQUARE


func build_formation_locals(count: int, shape: StringName = &"") -> Array[Vector3]:
	var locals: Array[Vector3] = []
	if count <= 0:
		return locals
	if count == 1:
		locals.append(Vector3.ZERO)
		return locals

	var resolved: StringName = shape if shape != &"" else choose_formation_shape(count)
	var cols: int = 1
	var rows: int = 1
	match resolved:
		FORMATION_SHAPE_LINE:
			cols = count
			rows = 1
		FORMATION_SHAPE_RECTANGLE:
			cols = maxi(2, int(ceil(sqrt(float(count) * 1.7))))
			rows = maxi(1, int(ceil(float(count) / float(cols))))
			if rows > cols:
				var swap: int = cols
				cols = rows
				rows = swap
				rows = maxi(1, int(ceil(float(count) / float(cols))))
		_:
			cols = maxi(1, int(ceil(sqrt(float(count)))))
			rows = maxi(1, int(ceil(float(count) / float(cols))))

	var index: int = 0
	for row: int in rows:
		for col: int in cols:
			if index >= count:
				break
			var ox: float = (float(col) - float(cols - 1) * 0.5) * SLOT_SPACING
			var oz: float = (float(rows - 1) * 0.5 - float(row)) * SLOT_SPACING
			locals.append(Vector3(ox, 0.0, oz))
			index += 1
	return locals


func _formation_travel_forward(
	origin: Vector3,
	destination: Vector3,
	route: PackedVector3Array
) -> Vector3:
	if route.size() >= 2:
		var look_index: int = mini(4, route.size() - 1)
		var look: Vector3 = route[look_index] - route[0]
		look.y = 0.0
		if look.length_squared() >= 0.25:
			return look.normalized()
	var face: Vector3 = destination - origin
	face.y = 0.0
	if face.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return face.normalized()


func _assign_formation_locals(
	units: Array,
	layout: Array[Vector3],
	origin: Vector3,
	forward: Vector3,
	right: Vector3
) -> Array[Vector3]:
	var count: int = units.size()
	var assigned: Array[Vector3] = []
	assigned.resize(count)
	if count <= 0 or layout.is_empty():
		return assigned
	if count == 1:
		assigned[0] = layout[0] if not layout.is_empty() else Vector3.ZERO
		return assigned

	var used_slots: PackedByteArray = PackedByteArray()
	used_slots.resize(layout.size())
	used_slots.fill(0)
	var filled: PackedByteArray = PackedByteArray()
	filled.resize(count)
	filled.fill(0)

	var hero_index: int = -1
	for i: int in count:
		if units[i] is Hero:
			hero_index = i
			break
	if hero_index >= 0:
		var hero_slot: int = _pick_front_center_slot(layout)
		assigned[hero_index] = layout[hero_slot]
		used_slots[hero_slot] = 1
		filled[hero_index] = 1

	var remaining_units: Array[int] = []
	for i: int in count:
		if filled[i] == 1:
			continue
		remaining_units.append(i)
	remaining_units.sort_custom(
		func(a: int, b: int) -> bool:
			var pa: Vector3 = _project_local(
				(units[a] as Unit).global_position, origin, right, forward
			)
			var pb: Vector3 = _project_local(
				(units[b] as Unit).global_position, origin, right, forward
			)
			if absf(pa.x - pb.x) > 0.05:
				return pa.x < pb.x
			return pa.z > pb.z
	)

	var remaining_slots: Array[int] = []
	for slot_i: int in layout.size():
		if used_slots[slot_i] == 0:
			remaining_slots.append(slot_i)
	remaining_slots.sort_custom(
		func(a: int, b: int) -> bool:
			var la: Vector3 = layout[a]
			var lb: Vector3 = layout[b]
			if absf(la.x - lb.x) > 0.05:
				return la.x < lb.x
			return la.z > lb.z
	)

	var pair_count: int = mini(remaining_units.size(), remaining_slots.size())
	for i: int in pair_count:
		assigned[remaining_units[i]] = layout[remaining_slots[i]]
		filled[remaining_units[i]] = 1
	for i: int in count:
		if filled[i] == 0:
			assigned[i] = layout[mini(i, layout.size() - 1)]
	return assigned


func _pick_front_center_slot(layout: Array[Vector3]) -> int:
	var best: int = 0
	var best_score: float = -INF
	for i: int in layout.size():
		var local: Vector3 = layout[i]
		var score: float = local.z * 100.0 - absf(local.x)
		if score > best_score:
			best_score = score
			best = i
	return best


func _project_local(world: Vector3, origin: Vector3, right: Vector3, forward: Vector3) -> Vector3:
	var delta: Vector3 = world - origin
	delta.y = 0.0
	return Vector3(delta.dot(right), 0.0, delta.dot(forward))


func _compress_slot_to_walkable(slot: Vector3, center: Vector3) -> Vector3:
	if grid.is_world_walkable(slot):
		return Vector3(slot.x, GROUND_Y, slot.z)
	var offset: Vector3 = slot - center
	offset.y = 0.0
	for scale: float in [0.75, 0.5, 0.25, 0.0]:
		var candidate: Vector3 = center + offset * scale
		candidate.y = GROUND_Y
		if grid.is_world_walkable(candidate):
			return candidate
	return grid.nearest_walkable_world(Vector3(slot.x, GROUND_Y, slot.z))


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
					var points: Array[Vector3] = [unit.global_position, target]
					unit.issue_order(UnitOrder.patrol(points), queued)
			else:
				unit.issue_order(UnitOrder.move(target), queued)
		_:
			unit.issue_order(UnitOrder.move(target), queued)


func _physics_process(delta: float) -> void:
	if _army_march_active:
		_evaluate_army_march(delta)


func is_enemy_army_march_in_progress() -> bool:
	return _army_march_active and (
		_army_march_mode == &"MOVING"
		or _army_march_mode == &"WAITING_FOR_ALL"
		or _army_march_mode == &"FINAL_APPROACH"
	)


func is_enemy_army_march_waiting_for_all() -> bool:
	return _army_march_active and _army_march_mode == &"WAITING_FOR_ALL"


func get_army_march_debug_snapshot() -> Dictionary:
	if not _army_march_active:
		return {
			"active": false,
			"mode": &"NONE",
			"checkpoint": Vector3.ZERO,
			"final_objective": Vector3.ZERO,
			"segment_index": 0,
			"route_progress": 0.0,
			"required": 0,
			"arrived": 0,
			"waiting_for": 0,
			"farthest_name": "",
			"farthest_distance": 0.0,
			"hero_arrived": false,
			"next_segment_release": "READY",
			"waiting_examples": [],
		}
	var tally: Dictionary = _tally_army_march_members()
	var required: int = int(tally.get("required", 0))
	var arrived: int = int(tally.get("arrived", 0))
	return {
		"active": true,
		"mode": _army_march_mode,
		"checkpoint": _army_march_checkpoint,
		"final_objective": _army_march_final,
		"segment_index": _army_march_segment_index,
		"route_progress": _army_march_checkpoint_dist,
		"required": required,
		"arrived": arrived,
		"waiting_for": maxi(0, required - arrived),
		"farthest_name": String(tally.get("farthest_name", "")),
		"farthest_distance": float(tally.get("farthest_distance", 0.0)),
		"hero_arrived": bool(tally.get("hero_arrived", false)),
		"next_segment_release": (
			"READY" if required > 0 and arrived >= required else "WAITING"
		),
		"waiting_examples": tally.get("waiting_examples", []),
	}


func evaluate_enemy_army_march_for_test(delta: float = 0.0) -> void:
	_evaluate_army_march(delta)


func get_army_march_checkpoint_for_test() -> Vector3:
	return _army_march_checkpoint


func get_army_march_mode_for_test() -> StringName:
	return _army_march_mode


func get_army_march_shared_route_for_test() -> PackedVector3Array:
	return _army_march_route.duplicate()


func get_army_march_generation_for_test() -> int:
	return _army_march_generation


func get_army_march_segment_index_for_test() -> int:
	return _army_march_segment_index


func _request_enemy_army_march_move(
	ordered_units: Array,
	destination: Vector3,
	order_kind: StringName,
	command_source: StringName,
	result: Dictionary
) -> Dictionary:
	ensure_grid_ready()
	result["squad_size"] = ordered_units.size()

	var group_destination := Vector3(destination.x, GROUND_Y, destination.z)
	if not grid.is_world_walkable(group_destination):
		group_destination = grid.nearest_walkable_world(group_destination)

	if (
		_army_march_active
		and _horizontal_distance(_army_march_final, group_destination)
			<= ARMY_MARCH_OBJECTIVE_EQUIV_RADIUS
	):
		path_calculations_this_command = 0
		_join_units_to_army_march(ordered_units, order_kind, result)
		result["handled"] = true
		result["route_valid"] = not _army_march_route.is_empty()
		result["accepted_destination"] = _army_march_final
		result["route_waypoints"] = _army_march_route.size()
		result["path_calculations"] = path_calculations_this_command
		_record_command_telemetry(ordered_units.size(), _army_march_route.size(), command_source)
		return result

	_global_command_generation += 1
	path_calculations_this_command = 0

	var origin: Vector3 = _group_centroid(ordered_units)
	## Single A* for the army march — members share this corridor.
	var shared_route: PackedVector3Array = grid.find_path(origin, group_destination)
	path_calculations_this_command += 1
	total_path_calculations += 1
	result["path_calculations"] = path_calculations_this_command
	result["route_waypoints"] = shared_route.size()
	PerfCounters.record_strategic_route_request()
	PerfCounters.record_navigation_path_request()

	if shared_route.is_empty():
		result["route_failure_reason"] = "no_path"
		_record_command_telemetry(ordered_units.size(), 0, command_source)
		return result

	var plan: Dictionary = _plan_group_formation(
		ordered_units, group_destination, origin, shared_route
	)
	var slots: Array[Vector3] = plan["slots"] as Array[Vector3]
	var locals: Array[Vector3] = plan["locals"] as Array[Vector3]

	_start_army_march(
		shared_route,
		group_destination,
		order_kind,
		_global_command_generation,
		ordered_units
	)

	var slot_targets_out: Array = []
	for index: int in ordered_units.size():
		var unit: Unit = ordered_units[index] as Unit
		var slot: Vector3 = slots[index] if index < slots.size() else group_destination
		var local: Vector3 = locals[index] if index < locals.size() else Vector3.ZERO
		slot_targets_out.append(slot)
		_bind_unit_to_army_march(unit, shared_route, slot, order_kind, false, local)
		_issue_unit_ground_order(unit, slot, order_kind, false)

	result["handled"] = true
	result["route_valid"] = true
	result["accepted_destination"] = group_destination
	result["slot_targets"] = slot_targets_out
	_record_command_telemetry(ordered_units.size(), shared_route.size(), command_source)
	return result


func _start_army_march(
	shared_route: PackedVector3Array,
	final_dest: Vector3,
	order_kind: StringName,
	generation: int,
	members: Array
) -> void:
	_army_march_active = true
	_army_march_route = shared_route.duplicate()
	_army_march_route_cum = _build_route_cumulative(_army_march_route)
	_army_march_final = final_dest
	_army_march_clicked = final_dest
	_army_march_order_kind = order_kind
	_army_march_generation = generation
	_army_march_segment_index = 0
	_army_march_prev_checkpoint = Vector3.ZERO
	_army_march_last_arrived = -1
	_army_march_last_required = -1
	_army_march_last_waiting_name = ""
	_army_march_logged_hero_ids.clear()
	_army_march_member_ids = PackedInt64Array()
	for member_v: Variant in members:
		var live: Unit = _as_live_unit(member_v)
		if live == null:
			continue
		_army_march_member_ids.append(live.get_instance_id())
	_set_checkpoint_at_distance(ARMY_MARCH_SEGMENT_DISTANCE, true)
	set_physics_process(true)


func _join_units_to_army_march(
	units: Array,
	order_kind: StringName,
	result: Dictionary
) -> void:
	var slot_targets_out: Array = result.get("slot_targets", []) as Array
	for unit_v: Variant in units:
		var unit: Unit = _as_live_unit(unit_v)
		if unit == null:
			continue
		_remember_march_member(unit)
		var join_route: PackedVector3Array = grid.find_path(
			Vector3(unit.global_position.x, GROUND_Y, unit.global_position.z),
			_army_march_checkpoint
		)
		path_calculations_this_command += 1
		total_path_calculations += 1
		PerfCounters.record_navigation_path_request()
		if join_route.is_empty():
			join_route = _army_march_route.duplicate()
		var slot: Vector3 = _army_march_final
		if not grid.is_world_walkable(slot):
			slot = grid.nearest_walkable_world(slot)
		slot_targets_out.append(slot)
		_bind_unit_to_army_march(unit, join_route, slot, order_kind, true, Vector3.ZERO)
		_issue_unit_ground_order(unit, slot, order_kind, false)
	result["slot_targets"] = slot_targets_out


func _bind_unit_to_army_march(
	unit: Unit,
	route: PackedVector3Array,
	slot: Vector3,
	order_kind: StringName,
	_is_join: bool,
	formation_local: Vector3 = Vector3.ZERO
) -> void:
	unit.prepare_custom_rts_route(
		route,
		slot,
		_army_march_generation,
		_army_march_clicked,
		order_kind,
		formation_local
	)
	unit.bind_army_march_checkpoint(
		_army_march_checkpoint,
		_army_march_cap_index,
		_army_march_mode == &"FINAL_APPROACH"
	)


func _remember_march_member(unit: Unit) -> void:
	if not NodeSafety.is_alive_node(unit):
		return
	var id: int = unit.get_instance_id()
	for existing: int in _army_march_member_ids:
		if existing == id:
			return
	_army_march_member_ids.append(id)


func _set_checkpoint_at_distance(target_dist: float, is_new_march: bool) -> void:
	_army_march_gather_seconds = 0.0
	var sampled: Dictionary = _sample_route_at_distance(target_dist)
	var point: Vector3 = sampled.get("point", _army_march_final) as Vector3
	if not grid.is_world_walkable(point):
		point = grid.nearest_walkable_world(point)
	var prev: Vector3 = _army_march_checkpoint
	_army_march_prev_checkpoint = prev
	_army_march_checkpoint = point
	_army_march_checkpoint_dist = float(sampled.get("dist", 0.0))
	_army_march_cap_index = int(sampled.get("index", 0))
	if bool(sampled.get("is_end", false)):
		_army_march_checkpoint = _army_march_final
		_army_march_mode = &"FINAL_APPROACH"
	else:
		_army_march_mode = &"MOVING"
	if is_new_march:
		_army_march_segment_index = 1
	else:
		_army_march_segment_index += 1
	_army_march_last_arrived = -1
	_army_march_last_waiting_name = ""
	var dist_from_prev: float = 0.0
	if prev != Vector3.ZERO:
		dist_from_prev = _horizontal_distance(prev, _army_march_checkpoint)
	elif not _army_march_route.is_empty():
		dist_from_prev = _horizontal_distance(_army_march_route[0], _army_march_checkpoint)
	_log_march_event(
		"new checkpoint\ndistance from previous=%.1fm\nrequired=%d"
		% [dist_from_prev, _army_march_member_ids.size()]
	)
	if _army_march_mode == &"FINAL_APPROACH":
		_log_march_event("final approach")


func _build_route_cumulative(route: PackedVector3Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(route.size())
	if route.is_empty():
		return cum
	cum[0] = 0.0
	for i: int in range(1, route.size()):
		cum[i] = cum[i - 1] + _horizontal_distance(route[i - 1], route[i])
	return cum


func _sample_route_at_distance(target_dist: float) -> Dictionary:
	var route: PackedVector3Array = _army_march_route
	var cum: PackedFloat32Array = _army_march_route_cum
	if route.is_empty():
		return {
			"point": _army_march_final,
			"index": 0,
			"dist": 0.0,
			"is_end": true,
		}
	var total: float = cum[cum.size() - 1] if cum.size() > 0 else 0.0
	if total <= target_dist + 0.05:
		return {
			"point": route[route.size() - 1],
			"index": route.size() - 1,
			"dist": total,
			"is_end": true,
		}
	for i: int in range(1, route.size()):
		if cum[i] + 0.001 >= target_dist:
			var seg: float = cum[i] - cum[i - 1]
			var t: float = 0.0
			if seg > 0.001:
				t = clampf((target_dist - cum[i - 1]) / seg, 0.0, 1.0)
			var point: Vector3 = route[i - 1].lerp(route[i], t)
			point.y = GROUND_Y
			return {
				"point": point,
				"index": i,
				"dist": target_dist,
				"is_end": false,
			}
	return {
		"point": route[route.size() - 1],
		"index": route.size() - 1,
		"dist": total,
		"is_end": true,
	}


func _evaluate_army_march(delta: float = 0.0) -> void:
	if not _army_march_active:
		set_physics_process(false)
		return
	var tally: Dictionary = _tally_army_march_members()
	var required: int = int(tally.get("required", 0))
	if required <= 0:
		_clear_army_march()
		return
	var arrived: int = int(tally.get("arrived", 0))
	var waiting_name: String = String(tally.get("farthest_name", ""))
	# Give stragglers a short catch-up window, then move the ready main force.
	# New production must not hold a large army at each checkpoint forever.
	var ready_main_force: bool = arrived >= maxi(3, int(ceil(float(required) * ARMY_MARCH_READY_FRACTION)))
	if ready_main_force:
		_army_march_gather_seconds += maxf(0.0, delta)
	else:
		_army_march_gather_seconds = 0.0
	var release_main_force: bool = ready_main_force and _army_march_gather_seconds >= ARMY_MARCH_MAX_GATHER_SECONDS
	if arrived < required and not release_main_force:
		if arrived > 0 and _army_march_mode != &"FINAL_APPROACH":
			_army_march_mode = &"WAITING_FOR_ALL"
		elif arrived <= 0 and _army_march_mode != &"FINAL_APPROACH":
			_army_march_mode = &"MOVING"
		if arrived > 0:
			_log_wait_if_changed(arrived, required, waiting_name, tally)
		return
	if _army_march_mode == &"FINAL_APPROACH":
		_finish_army_march(tally.get("members", []) as Array)
		return
	_log_march_event("%s\n%d/%d\nreleasing next segment" % ["MAIN_FORCE_READY" if arrived < required else "ALL_ARRIVED", arrived, required])
	_release_next_march_segment(tally.get("members", []) as Array)


func _log_wait_if_changed(
	arrived: int,
	required: int,
	waiting_name: String,
	tally: Dictionary
) -> void:
	if (
		arrived == _army_march_last_arrived
		and required == _army_march_last_required
		and waiting_name == _army_march_last_waiting_name
	):
		return
	_army_march_last_arrived = arrived
	_army_march_last_required = required
	_army_march_last_waiting_name = waiting_name
	if bool(tally.get("hero_just_arrived", false)):
		_log_march_event("Hero arrived\n%d/%d arrived" % [arrived, required])
	_log_march_event(
		"WAITING_FOR_ALL\n%d/%d arrived\nwaiting_for=%s"
		% [arrived, required, waiting_name]
	)
	if not _march_p_debug_enabled():
		return
	var examples: Array = tally.get("waiting_examples", []) as Array
	for row_v: Variant in examples:
		if not row_v is Dictionary:
			continue
		var row: Dictionary = row_v as Dictionary
		print(
			"waiting_for=%s distance=%.1fm moving=%s stuck_flag=%s"
			% [
				String(row.get("name", "")),
				float(row.get("distance", 0.0)),
				"YES" if bool(row.get("moving", false)) else "NO",
				"YES" if bool(row.get("stuck", false)) else "NO",
			]
		)


func _release_next_march_segment(members: Array) -> void:
	var next_dist: float = _army_march_checkpoint_dist + ARMY_MARCH_SEGMENT_DISTANCE
	_set_checkpoint_at_distance(next_dist, false)
	for member_v: Variant in members:
		var unit: Unit = _as_live_unit(member_v)
		if unit == null:
			continue
		if unit.get_custom_rts_route_waypoint_count() != _army_march_route.size():
			unit.replace_custom_rts_route(_army_march_route)
		unit.bind_army_march_checkpoint(
			_army_march_checkpoint,
			_army_march_cap_index,
			_army_march_mode == &"FINAL_APPROACH"
		)
		if _unit_in_local_combat(unit):
			continue
		unit.try_resume_custom_rts_route(_army_march_clicked)


func _tally_army_march_members() -> Dictionary:
	var members: Array = _collect_live_march_members()
	var arrived: int = 0
	var farthest_name: String = ""
	var farthest_dist: float = -1.0
	var hero_arrived: bool = true
	var hero_present: bool = false
	var hero_just_arrived: bool = false
	var waiting_examples: Array = []
	for member_v: Variant in members:
		var unit: Unit = _as_live_unit(member_v)
		if unit == null:
			continue
		var dist: float = _horizontal_distance(unit.global_position, _army_march_checkpoint)
		var is_arrived: bool = dist <= MARCH_ARRIVAL_RADIUS
		if is_arrived:
			arrived += 1
			if unit is Hero:
				hero_present = true
				hero_arrived = true
				var hero_id: int = unit.get_instance_id()
				if not _army_march_logged_hero_ids.has(hero_id):
					_army_march_logged_hero_ids[hero_id] = true
					hero_just_arrived = true
		else:
			if unit is Hero:
				hero_present = true
				hero_arrived = false
			if dist >= farthest_dist:
				farthest_dist = dist
				farthest_name = unit.name
			if waiting_examples.size() < 3:
				waiting_examples.append({
					"name": unit.name,
					"distance": dist,
					"moving": unit.has_move_target,
					"stuck": unit.is_physically_blocked_from_current_move(),
				})
	if not hero_present:
		hero_arrived = false
	return {
		"members": members,
		"required": members.size(),
		"arrived": arrived,
		"farthest_name": farthest_name,
		"farthest_distance": maxf(0.0, farthest_dist),
		"hero_arrived": hero_arrived,
		"hero_just_arrived": hero_just_arrived,
		"waiting_examples": waiting_examples,
	}


func _collect_live_march_members() -> Array:
	var seen: Dictionary = {}
	var members: Array = []
	var ai: EnemyAI = _resolve_enemy_ai()
	if ai != null:
		for unit_v: Variant in ai.get_cached_strategic_army():
			var from_ai: Unit = _as_live_unit(unit_v)
			if from_ai == null:
				continue
			if not _is_living_army_member(from_ai):
				continue
			var id: int = from_ai.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			members.append(from_ai)
	for stored_id: int in _army_march_member_ids:
		if seen.has(stored_id):
			continue
		var node: Object = instance_from_id(stored_id)
		if not NodeSafety.is_alive_node(node):
			continue
		if not node is Unit:
			continue
		var stored: Unit = node as Unit
		if not _is_living_army_member(stored):
			continue
		seen[stored_id] = true
		members.append(stored)
	return members


func _as_live_unit(value: Variant) -> Unit:
	if not NodeSafety.is_alive_node(value):
		return null
	if not value is Unit:
		return null
	return value as Unit


func _is_living_army_member(unit: Unit) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	if unit is Worker:
		return false
	var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.current_health <= 0.0:
		return false
	return true


func _unit_in_local_combat(unit: Unit) -> bool:
	if unit == null or not NodeSafety.is_alive_node(unit):
		return false
	if not unit.has_method("get_attack_target"):
		return false
	return NodeSafety.is_alive_node(unit.call("get_attack_target"))


func _resolve_enemy_ai() -> EnemyAI:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(&"enemy_ai"):
		if not NodeSafety.is_alive_node(node):
			continue
		if node is EnemyAI:
			return node as EnemyAI
	return null


func _finish_army_march(members: Array) -> void:
	for member_v: Variant in members:
		var unit: Unit = _as_live_unit(member_v)
		if unit == null:
			continue
		unit.clear_army_march_checkpoint()
		if _unit_in_local_combat(unit):
			continue
		var slot: Vector3 = unit.get_player_squad_final_arrival()
		if slot == Vector3.ZERO:
			slot = _army_march_final
		if not unit.has_move_target:
			unit.try_resume_custom_rts_route(slot)
	_clear_army_march()


func _clear_army_march() -> void:
	_army_march_gather_seconds = 0.0
	_army_march_active = false
	_army_march_mode = &""
	_army_march_route = PackedVector3Array()
	_army_march_route_cum = PackedFloat32Array()
	_army_march_final = Vector3.ZERO
	_army_march_clicked = Vector3.ZERO
	_army_march_order_kind = &""
	_army_march_generation = -1
	_army_march_checkpoint = Vector3.ZERO
	_army_march_checkpoint_dist = 0.0
	_army_march_cap_index = 0
	_army_march_segment_index = 0
	_army_march_member_ids = PackedInt64Array()
	_army_march_prev_checkpoint = Vector3.ZERO
	_army_march_last_arrived = -1
	_army_march_last_required = -1
	_army_march_last_waiting_name = ""
	_army_march_logged_hero_ids.clear()
	set_physics_process(false)


func _log_march_event(text: String) -> void:
	if not _march_p_debug_enabled():
		return
	print("[MARCH]")
	print(text)
	print("")
	var compact: String = text.replace("\n", " | ")
	EnemyAI.report_brain_debug_event("[MARCH] %s" % compact)


func _march_p_debug_enabled() -> bool:
	var ai: EnemyAI = _resolve_enemy_ai()
	return ai != null and ai.is_brain_debug_enabled()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
