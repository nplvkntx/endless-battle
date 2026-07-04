class_name GroupMoveSpacing

## Computes simple offset targets around a move command point for grouped units.

const DEFAULT_SPACING: float = 1.5
const MAP_MIN_X: float = -50.0
const MAP_MAX_X: float = 50.0
const MAP_MIN_Z: float = -50.0
const MAP_MAX_Z: float = 50.0
const WALKABLE_PROBE_RADIUS: float = 0.45
const FALLBACK_RING_COUNT: int = 4
const FALLBACK_RING_STEPS: int = 8


static func compute_line_targets(
	row_center: Vector3,
	row_right: Vector3,
	unit_count: int,
	spacing: float = DEFAULT_SPACING
) -> Array[Vector3]:
	if unit_count <= 0:
		return []

	if unit_count == 1:
		return [row_center]

	var targets: Array[Vector3] = []
	for index: int in unit_count:
		var lateral_offset: float = (float(index) - (float(unit_count) - 1.0) * 0.5) * spacing
		targets.append(row_center + row_right * lateral_offset)

	return targets


static func is_within_map_bounds(position: Vector3) -> bool:
	return (
		position.x >= MAP_MIN_X
		and position.x <= MAP_MAX_X
		and position.z >= MAP_MIN_Z
		and position.z <= MAP_MAX_Z
	)


static func clamp_to_map_bounds(position: Vector3) -> Vector3:
	return Vector3(
		clampf(position.x, MAP_MIN_X, MAP_MAX_X),
		position.y,
		clampf(position.z, MAP_MIN_Z, MAP_MAX_Z)
	)


static func is_walkable_at(position: Vector3, unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return true

	var world: World3D = unit.get_world_3d()
	if world == null:
		return true

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = WALKABLE_PROBE_RADIUS

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	query.exclude = [unit.get_rid()]

	return space_state.intersect_shape(query, 1).is_empty()


static func resolve_nearby_walkable_position(
	candidate: Vector3,
	unit: Node3D,
	fallback: Vector3,
	spacing: float = DEFAULT_SPACING
) -> Vector3:
	if is_within_map_bounds(candidate) and is_walkable_at(candidate, unit):
		return candidate

	var clamped_candidate: Vector3 = clamp_to_map_bounds(candidate)
	if is_walkable_at(clamped_candidate, unit):
		return clamped_candidate

	var ring_spacing: float = maxf(spacing * 0.5, 0.75)
	for ring: int in range(1, FALLBACK_RING_COUNT + 1):
		var ring_radius: float = ring_spacing * float(ring)
		for step: int in FALLBACK_RING_STEPS:
			var angle: float = TAU * float(step) / float(FALLBACK_RING_STEPS)
			var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * ring_radius
			var test_position: Vector3 = clamp_to_map_bounds(candidate + offset)
			if is_walkable_at(test_position, unit):
				return test_position

	return clamp_to_map_bounds(fallback)


static func compute_targets(center: Vector3, unit_count: int, spacing: float = DEFAULT_SPACING) -> Array[Vector3]:
	if unit_count <= 1:
		return [center]

	var targets: Array[Vector3] = []
	var columns: int = int(ceil(sqrt(float(unit_count))))
	var rows: int = int(ceil(float(unit_count) / float(columns)))

	var index: int = 0
	for row: int in range(rows):
		for column: int in range(columns):
			if index >= unit_count:
				break

			var offset_x: float = (float(column) - (float(columns) - 1.0) * 0.5) * spacing
			var offset_z: float = (float(row) - (float(rows) - 1.0) * 0.5) * spacing
			targets.append(Vector3(center.x + offset_x, center.y, center.z + offset_z))
			index += 1

	return targets


## Returns one grid slot around center. Slot 0 is the center; higher slots expand outward.
static func compute_slot_target(
	center: Vector3, slot_index: int, spacing: float = DEFAULT_SPACING
) -> Vector3:
	if slot_index <= 0:
		return center

	var targets: Array[Vector3] = compute_targets(center, slot_index + 1, spacing)
	return targets[slot_index]
