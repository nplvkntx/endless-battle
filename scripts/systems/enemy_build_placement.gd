class_name EnemyBuildPlacement
extends RefCounted

## Shared building placement rules: grid snap, map bounds, footprints, and AI position search.

const GRID_SIZE: float = 1.0
const MAP_MIN_X: float = -50.0
const MAP_MAX_X: float = 50.0
const MAP_MIN_Z: float = -50.0
const MAP_MAX_Z: float = 50.0

const BUILDING_PADDING: float = 0.8
const FOOTPRINT_PROBE_HEIGHT: float = 2.5
const PLACEMENT_COLLISION_MASK: int = (
	PhysicsLayers.WORLD | PhysicsLayers.UNITS | PhysicsLayers.BUILDINGS
)
const BASE_SEARCH_RADIUS: float = 28.0
const GOLD_MINE_CLEARANCE: float = 5.0
const TREE_CLEARANCE: float = 4.0
const DROPOFF_PATH_WIDTH: float = 3.0
const MIN_NAV_PATH_POINTS: int = 2
const WORKER_NAV_TEST_Y: float = 0.5
const COMMAND_CENTER_DROP_OFF_OFFSET_X: float = 3.0

const FARM_SIZE := Vector2(2.0, 1.4)
const BARRACKS_SIZE := Vector2(3.5, 2.5)
const BLACKSMITH_SIZE := Vector2(2.2, 1.8)
const STABLE_SIZE := Vector2(3.0, 2.2)
const ARTILLERY_DEPOT_SIZE := Vector2(3.2, 2.4)
const ACADEMY_SIZE := Vector2(3.0, 2.2)
const SHOP_SIZE := Vector2(2.0, 1.6)
const TOWER_SIZE := Vector2(2.0, 2.0)
const HERO_ALTAR_SIZE := Vector2(3.0, 3.0)
const COMMAND_CENTER_SIZE := Vector2(3.5, 3.5)
const DEFAULT_FOOTPRINT := Vector2(2.5, 2.5)

const FARM_GROUND_Y: float = 0.5
const BARRACKS_GROUND_Y: float = 0.8
const BLACKSMITH_GROUND_Y: float = 0.8
const STABLE_GROUND_Y: float = 0.8
const ARTILLERY_DEPOT_GROUND_Y: float = 0.8
const ACADEMY_GROUND_Y: float = 0.8
const SHOP_GROUND_Y: float = 0.7
const TOWER_GROUND_Y: float = 1.5
const HERO_ALTAR_GROUND_Y: float = 1.0
const COMMAND_CENTER_GROUND_Y: float = 1.0

const RING_RADII: Array[float] = [6.0, 8.5, 11.0, 14.0, 17.0]
const EXPANSION_RING_RADII: Array[float] = [16.0, 19.0, 22.0]
const CANDIDATE_STEPS: int = 12


static func find_position(
	anchor: Vector3,
	building_type: StringName,
	existing_buildings: Array[Node3D],
	prefer_expansion: bool = false,
	scene_root: Node = null,
	nav_map: RID = RID()
) -> Vector3:
	var footprint: Vector2 = get_footprint(building_type)
	var ground_y: float = get_ground_y(building_type)
	var ring_radii: Array[float] = EXPANSION_RING_RADII if prefer_expansion else RING_RADII
	var gold_mines: Array[Node3D] = _collect_enemy_gold_mines(anchor, scene_root)
	var trees: Array[Node3D] = _collect_enemy_trees(anchor, scene_root)
	var tree_center: Vector2 = _compute_tree_center(trees)
	var nav_from: Vector3 = Vector3(
		anchor.x + COMMAND_CENTER_DROP_OFF_OFFSET_X,
		WORKER_NAV_TEST_Y,
		anchor.z
	)

	var best_position: Vector3 = Vector3.INF
	var best_score: float = -INF

	for radius: float in ring_radii:
		for step: int in range(CANDIDATE_STEPS):
			var angle: float = float(step) * TAU / float(CANDIDATE_STEPS)
			var offset := Vector2(cos(angle), sin(angle)) * radius
			var candidate := Vector3(anchor.x + offset.x, ground_y, anchor.z + offset.y)
			candidate = snap_to_grid(candidate)
			candidate.y = ground_y

			if anchor.distance_squared_to(candidate) > BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS:
				continue

			if not is_footprint_within_bounds(candidate, footprint):
				continue

			if not is_position_valid(
				candidate,
				building_type,
				existing_buildings,
				scene_root
			):
				continue

			if _is_too_close_to_resources(candidate, gold_mines, trees):
				continue

			if _blocks_dropoff_path(candidate, anchor, gold_mines, tree_center):
				continue

			var nav_to: Vector3 = Vector3(candidate.x, WORKER_NAV_TEST_Y, candidate.z)
			if not _is_nav_reachable(nav_map, nav_from, nav_to):
				continue

			var score: float = _score_position(candidate, anchor, gold_mines, trees)
			if score > best_score:
				best_score = score
				best_position = candidate

	return best_position


static func snap_to_grid(position: Vector3) -> Vector3:
	if GRID_SIZE <= 0.0:
		return position

	return Vector3(
		snapped(position.x, GRID_SIZE),
		position.y,
		snapped(position.z, GRID_SIZE)
	)


static func is_footprint_within_bounds(center: Vector3, footprint: Vector2) -> bool:
	var half_x: float = footprint.x * 0.5
	var half_z: float = footprint.y * 0.5
	return (
		center.x - half_x >= MAP_MIN_X
		and center.x + half_x <= MAP_MAX_X
		and center.z - half_z >= MAP_MIN_Z
		and center.z + half_z <= MAP_MAX_Z
	)


static func is_position_valid(
	candidate: Vector3,
	building_type: StringName,
	existing_buildings: Array[Node3D],
	scene_root: Node = null,
	exclude_nodes: Array[Node] = []
) -> bool:
	var footprint: Vector2 = get_footprint(building_type)
	if not is_footprint_within_bounds(candidate, footprint):
		return false

	if not _is_position_clear(candidate, footprint, existing_buildings):
		return false

	if scene_root != null and _footprint_overlaps_blocked_colliders(
		candidate,
		footprint,
		scene_root,
		exclude_nodes
	):
		return false

	return true


static func get_footprint(building_type: StringName) -> Vector2:
	match building_type:
		&"farm":
			return FARM_SIZE
		&"barracks":
			return BARRACKS_SIZE
		&"blacksmith":
			return BLACKSMITH_SIZE
		&"stable":
			return STABLE_SIZE
		&"artillery_depot":
			return ARTILLERY_DEPOT_SIZE
		&"academy":
			return ACADEMY_SIZE
		&"shop":
			return SHOP_SIZE
		&"tower":
			return TOWER_SIZE
		&"hero_altar":
			return HERO_ALTAR_SIZE
		&"command_center":
			return COMMAND_CENTER_SIZE
		_:
			return DEFAULT_FOOTPRINT


static func get_ground_y(building_type: StringName) -> float:
	match building_type:
		&"farm":
			return FARM_GROUND_Y
		&"barracks":
			return BARRACKS_GROUND_Y
		&"blacksmith":
			return BLACKSMITH_GROUND_Y
		&"stable":
			return STABLE_GROUND_Y
		&"artillery_depot":
			return ARTILLERY_DEPOT_GROUND_Y
		&"academy":
			return ACADEMY_GROUND_Y
		&"shop":
			return SHOP_GROUND_Y
		&"tower":
			return TOWER_GROUND_Y
		&"hero_altar":
			return HERO_ALTAR_GROUND_Y
		&"command_center":
			return COMMAND_CENTER_GROUND_Y
		_:
			return 0.0


static func collect_all_buildings(scene_root: Node) -> Array[Node3D]:
	var buildings: Array[Node3D] = []
	if scene_root == null:
		return buildings

	for child: Node in scene_root.get_children():
		if child is Building:
			buildings.append(child as Node3D)

	return buildings


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
		if (
			building_3d.global_position.distance_squared_to(anchor)
			> BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS
		):
			continue

		buildings.append(building_3d)

	return buildings


static func _collect_enemy_gold_mines(anchor: Vector3, scene_root: Node) -> Array[Node3D]:
	var mines: Array[Node3D] = []
	if scene_root == null:
		return mines

	var radius_sq: float = BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS
	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if not child is GoldMine:
			continue
		if child.global_position.distance_squared_to(anchor) > radius_sq:
			continue
		if not child.name.begins_with("Enemy"):
			continue

		mines.append(child as Node3D)

	return mines


static func _collect_enemy_trees(anchor: Vector3, scene_root: Node) -> Array[Node3D]:
	var trees: Array[Node3D] = []
	if scene_root == null:
		return trees

	var radius_sq: float = BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS
	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if not child is WoodTree:
			continue
		if not child.name.begins_with("EnemyTree"):
			continue
		if child.global_position.distance_squared_to(anchor) > radius_sq:
			continue

		trees.append(child as Node3D)

	return trees


static func _compute_tree_center(trees: Array[Node3D]) -> Vector2:
	if trees.is_empty():
		return Vector2(INF, INF)

	var sum := Vector2.ZERO
	for tree: Node3D in trees:
		sum += Vector2(tree.global_position.x, tree.global_position.z)

	return sum / float(trees.size())


static func _is_too_close_to_resources(
	candidate: Vector3,
	gold_mines: Array[Node3D],
	trees: Array[Node3D]
) -> bool:
	for mine: Node3D in gold_mines:
		if mine == null or not is_instance_valid(mine):
			continue

		var mine_offset: Vector3 = candidate - mine.global_position
		mine_offset.y = 0.0
		if mine_offset.length() < GOLD_MINE_CLEARANCE:
			return true

	for tree: Node3D in trees:
		if tree == null or not is_instance_valid(tree):
			continue

		var tree_offset: Vector3 = candidate - tree.global_position
		tree_offset.y = 0.0
		if tree_offset.length() < TREE_CLEARANCE:
			return true

	return false


static func _blocks_dropoff_path(
	candidate: Vector3,
	anchor: Vector3,
	gold_mines: Array[Node3D],
	tree_center: Vector2
) -> bool:
	var point := Vector2(candidate.x, candidate.z)
	var command_center := Vector2(anchor.x, anchor.z)

	for mine: Node3D in gold_mines:
		if mine == null or not is_instance_valid(mine):
			continue

		var mine_point := Vector2(mine.global_position.x, mine.global_position.z)
		if _distance_point_to_segment(point, command_center, mine_point) < DROPOFF_PATH_WIDTH:
			return true

	if tree_center.is_finite():
		if _distance_point_to_segment(point, command_center, tree_center) < DROPOFF_PATH_WIDTH:
			return true

	return false


static func _score_position(
	candidate: Vector3,
	anchor: Vector3,
	gold_mines: Array[Node3D],
	trees: Array[Node3D]
) -> float:
	var score: float = 0.0

	for mine: Node3D in gold_mines:
		if mine == null or not is_instance_valid(mine):
			continue
		score += candidate.distance_to(mine.global_position)

	for tree: Node3D in trees:
		if tree == null or not is_instance_valid(tree):
			continue
		score += candidate.distance_to(tree.global_position)

	var anchor_offset: Vector3 = candidate - anchor
	anchor_offset.y = 0.0
	score -= anchor_offset.length() * 0.15

	return score


static func _is_nav_reachable(nav_map: RID, from: Vector3, to: Vector3) -> bool:
	if nav_map == RID():
		return true

	if not NavigationServer3D.map_is_active(nav_map):
		return true

	var start: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, from)
	var end: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start, end, true)
	return path.size() >= MIN_NAV_PATH_POINTS


static func _distance_point_to_segment(point: Vector2, segment_a: Vector2, segment_b: Vector2) -> float:
	var segment: Vector2 = segment_b - segment_a
	var length_sq: float = segment.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(segment_a)

	var t: float = clampf((point - segment_a).dot(segment) / length_sq, 0.0, 1.0)
	var projection: Vector2 = segment_a + segment * t
	return point.distance_to(projection)


static func _footprint_overlaps_blocked_colliders(
	candidate: Vector3,
	footprint: Vector2,
	scene_root: Node,
	exclude_nodes: Array[Node] = []
) -> bool:
	var world: World3D = scene_root.get_world_3d()
	if world == null:
		return false

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return false

	var shape := BoxShape3D.new()
	shape.size = Vector3(
		footprint.x + BUILDING_PADDING * 2.0,
		FOOTPRINT_PROBE_HEIGHT,
		footprint.y + BUILDING_PADDING * 2.0
	)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(
		Basis.IDENTITY,
		Vector3(
			candidate.x,
			candidate.y + FOOTPRINT_PROBE_HEIGHT * 0.5,
			candidate.z
		)
	)
	query.collision_mask = PLACEMENT_COLLISION_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var exclude_rids: Array[RID] = []
	for node: Node in exclude_nodes:
		if node == null or not is_instance_valid(node):
			continue
		if node is CollisionObject3D:
			exclude_rids.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude_rids

	for hit: Dictionary in space_state.intersect_shape(query, 32):
		var collider: Object = hit.get("collider")
		if _collider_blocks_placement(collider):
			return true

	return false


static func _collider_blocks_placement(collider: Object) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false

	if collider is CharacterBody3D:
		return true

	if collider is StaticBody3D:
		return true

	return false


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
	if building is Blacksmith:
		return BLACKSMITH_SIZE
	if building is Stable:
		return STABLE_SIZE
	if building is ArtilleryDepot:
		return ARTILLERY_DEPOT_SIZE
	if building is Academy:
		return ACADEMY_SIZE
	if building is Shop:
		return SHOP_SIZE
	if building is Tower:
		return TOWER_SIZE
	if building is HeroAltar:
		return HERO_ALTAR_SIZE
	if building is CommandCenter:
		return COMMAND_CENTER_SIZE

	return DEFAULT_FOOTPRINT


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
