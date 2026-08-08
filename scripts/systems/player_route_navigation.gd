extends Node

## Custom RTS movement authority (sole strategic movement foundation).
## One shared strategic grid route per group command + personal slots +
## lightweight local separation.
## Used by player SelectionManager / FormationManager, production rally, and
## SimpleWc3AI Stage 1 strategic travel (same API — AI chooses destination only).

const SLOT_SPACING := 1.4
const GROUND_Y := 0.0

var grid: PlayerRtsOccupancyGrid = PlayerRtsOccupancyGrid.new()

var _global_command_generation: int = 0
var path_calculations_this_command: int = 0
var total_path_calculations: int = 0
var _grid_ready: bool = false
var _scan_pending: bool = false

## Last player group-move telemetry for compact diagnostics.
var last_command_source: StringName = &""
var last_squad_size: int = 0
var last_route_waypoints: int = 0


func _ready() -> void:
	MatchSession.register_match_reset(&"PlayerRouteNavigation", clear_all)
	_setup_default_grid()
	set_process(false)


func clear_all() -> void:
	_global_command_generation = 0
	path_calculations_this_command = 0
	total_path_calculations = 0
	last_command_source = &""
	last_squad_size = 0
	last_route_waypoints = 0
	grid.clear_all()
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
		return
	grid.set_obstacle_aabb(
		body.get_instance_id(),
		footprint["center"] as Vector3,
		footprint["half_extents"] as Vector3
	)
	grid.commit()


func unregister_static_obstacle(body: Node3D) -> void:
	if body == null:
		return
	var obstacle_id: int = body.get_instance_id()
	if not grid.has_obstacle(obstacle_id):
		return
	grid.clear_obstacle(obstacle_id)
	grid.commit()


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
		var slot_targets: Array[Vector3] = _make_destination_slots(
			destination, ordered_units.size()
		)
		for index: int in ordered_units.size():
			var unit: Unit = ordered_units[index] as Unit
			var slot: Vector3 = slot_targets[index]
			if not grid.is_world_walkable(slot):
				slot = grid.nearest_walkable_world(slot)
			_issue_unit_ground_order(unit, slot, order_kind, true)
		_record_command_telemetry(ordered_units.size(), 0, command_source)
		return result

	_global_command_generation += 1
	path_calculations_this_command = 0

	var group_destination := Vector3(destination.x, GROUND_Y, destination.z)
	if not grid.is_world_walkable(group_destination):
		group_destination = grid.nearest_walkable_world(group_destination)

	var origin: Vector3 = _group_centroid(ordered_units)
	var shared_route: PackedVector3Array = grid.find_path(origin, group_destination)
	path_calculations_this_command += 1
	total_path_calculations += 1
	result["path_calculations"] = path_calculations_this_command
	result["route_waypoints"] = shared_route.size()

	if shared_route.is_empty():
		result["route_failure_reason"] = "no_path"
		_record_command_telemetry(ordered_units.size(), 0, command_source)
		return result

	var slots: Array[Vector3] = _make_destination_slots(
		group_destination, ordered_units.size()
	)
	for i: int in slots.size():
		if not grid.is_world_walkable(slots[i]):
			slots[i] = grid.nearest_walkable_world(slots[i])

	var slot_targets_out: Array = []
	for index: int in ordered_units.size():
		var unit: Unit = ordered_units[index] as Unit
		var slot: Vector3 = slots[index] if index < slots.size() else group_destination
		slot_targets_out.append(slot)
		unit.prepare_custom_rts_route(
			shared_route,
			slot,
			_global_command_generation,
			group_destination,
			order_kind
		)
		_issue_unit_ground_order(unit, slot, order_kind, false)

	result["handled"] = true
	result["route_valid"] = true
	result["accepted_destination"] = group_destination
	result["slot_targets"] = slot_targets_out
	_record_command_telemetry(ordered_units.size(), shared_route.size(), command_source)
	return result


## Player SelectionManager / FormationManager / production-rally entry.
func issue_player_group_command(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	queued: bool = false,
	command_source: StringName = &"player"
) -> Dictionary:
	return request_group_move(units, destination, order_kind, queued, command_source)


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


func _scan_buildings_recursive(node: Node) -> void:
	if node is Building:
		_register_building_internal(node as Building)
	for child: Node in node.get_children():
		_scan_buildings_recursive(child)


func _scan_static_bodies_recursive(node: Node) -> void:
	if node is StaticBody3D and not (node is Building) and not (node is GatherableResource):
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


func _register_building_internal(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not building.is_inside_tree():
		return
	# Open gates: still register posts-only footprint via resolver.
	var footprint: Dictionary = _resolve_footprint(building)
	if footprint.is_empty():
		return
	grid.set_obstacle_aabb(
		building.get_instance_id(),
		footprint["center"] as Vector3,
		footprint["half_extents"] as Vector3
	)


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


func _make_destination_slots(center: Vector3, count: int) -> Array[Vector3]:
	if count <= 1:
		return [Vector3(center.x, GROUND_Y, center.z)]
	var cols: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(cols)))
	var out: Array[Vector3] = []
	var index: int = 0
	for row: int in rows:
		for col: int in cols:
			if index >= count:
				break
			var ox: float = (float(col) - float(cols - 1) * 0.5) * SLOT_SPACING
			var oz: float = (float(row) - float(rows - 1) * 0.5) * SLOT_SPACING
			out.append(Vector3(center.x + ox, GROUND_Y, center.z + oz))
			index += 1
	return out


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
