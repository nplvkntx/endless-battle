class_name EnemyBuildPlacement
extends RefCounted

## Finds valid build positions near the enemy base without overlapping structures.

const BUILDING_PADDING: float = 1.25
const BASE_SEARCH_RADIUS: float = 28.0

const FARM_SIZE := Vector2(3.0, 2.0)
const BARRACKS_SIZE := Vector2(4.0, 3.0)
const HERO_ALTAR_SIZE := Vector2(3.5, 3.5)
const COMMAND_CENTER_SIZE := Vector2(4.0, 4.0)

const FARM_GROUND_Y: float = 0.75
const BARRACKS_GROUND_Y: float = 1.0
const HERO_ALTAR_GROUND_Y: float = 1.25
const COMMAND_CENTER_GROUND_Y: float = 1.25

const RING_RADII: Array[float] = [6.0, 8.5, 11.0, 14.0, 17.0]
const EXPANSION_RING_RADII: Array[float] = [16.0, 19.0, 22.0]


static func find_position(
	anchor: Vector3,
	building_type: StringName,
	existing_buildings: Array[Node3D],
	prefer_expansion: bool = false
) -> Vector3:
	var footprint: Vector2 = get_footprint(building_type)
	var ground_y: float = get_ground_y(building_type)
	var ring_radii: Array[float] = EXPANSION_RING_RADII if prefer_expansion else RING_RADII

	for radius: float in ring_radii:
		for step: int in range(8):
			var angle: float = float(step) * TAU / 8.0
			var offset := Vector2(cos(angle), sin(angle)) * radius
			var candidate := Vector3(anchor.x + offset.x, ground_y, anchor.z + offset.y)

			if anchor.distance_squared_to(candidate) > BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS:
				continue

			if not _is_position_clear(candidate, footprint, existing_buildings):
				continue

			return candidate

	return Vector3.INF


static func get_footprint(building_type: StringName) -> Vector2:
	match building_type:
		&"farm":
			return FARM_SIZE
		&"barracks":
			return BARRACKS_SIZE
		&"hero_altar":
			return HERO_ALTAR_SIZE
		&"command_center":
			return COMMAND_CENTER_SIZE
		_:
			return Vector2(3.0, 3.0)


static func get_ground_y(building_type: StringName) -> float:
	match building_type:
		&"farm":
			return FARM_GROUND_Y
		&"barracks":
			return BARRACKS_GROUND_Y
		&"hero_altar":
			return HERO_ALTAR_GROUND_Y
		&"command_center":
			return COMMAND_CENTER_GROUND_Y
		_:
			return 0.0


static func collect_nearby_buildings(anchor: Vector3, scene_root: Node) -> Array[Node3D]:
	var buildings: Array[Node3D] = []
	if scene_root == null:
		return buildings

	for child: Node in scene_root.get_children():
		if not child is Node3D:
			continue
		if not child is Building:
			continue

		var building_3d: Node3D = child as Node3D
		if building_3d.global_position.distance_squared_to(anchor) > BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS:
			continue

		buildings.append(building_3d)

	return buildings


static func _is_position_clear(
	candidate: Vector3,
	footprint: Vector2,
	existing_buildings: Array[Node3D]
) -> bool:
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue

		var other_footprint: Vector2 = _resolve_footprint(building)
		if _overlaps(candidate, footprint, building.global_position, other_footprint):
			return false

	return true


static func _resolve_footprint(building: Node3D) -> Vector2:
	if building is Farm:
		return FARM_SIZE
	if building is Barracks:
		return BARRACKS_SIZE
	if building is HeroAltar:
		return HERO_ALTAR_SIZE
	if building is CommandCenter:
		return COMMAND_CENTER_SIZE

	return Vector2(3.0, 3.0)


static func _overlaps(
	position_a: Vector3,
	size_a: Vector2,
	position_b: Vector3,
	size_b: Vector2
) -> bool:
	var delta_x: float = absf(position_a.x - position_b.x)
	var delta_z: float = absf(position_a.z - position_b.z)
	var min_distance_x: float = (size_a.x + size_b.x) * 0.5 + BUILDING_PADDING
	var min_distance_z: float = (size_a.y + size_b.y) * 0.5 + BUILDING_PADDING
	return delta_x < min_distance_x and delta_z < min_distance_z
