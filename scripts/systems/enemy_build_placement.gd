class_name EnemyBuildPlacement
extends RefCounted

## Shared building placement rules: grid snap, map bounds, footprints, and AI position search.
## AI placement prefers compact, zone-aware clusters around the town hall while preserving
## walkable lanes to resources, construction points, and production exits.

const GRID_SIZE: float = 1.0
const MAP_MIN_X: float = -50.0
const MAP_MAX_X: float = 50.0
const MAP_MIN_Z: float = -50.0
const MAP_MAX_Z: float = 50.0

## Footprint-edge gap shared with player placement / reservations (keeps walk lanes).
const BUILDING_PADDING: float = 0.8
const FOOTPRINT_PROBE_HEIGHT: float = 2.5
const PLACEMENT_COLLISION_MASK: int = (
	PhysicsLayers.WORLD | PhysicsLayers.UNITS | PhysicsLayers.BUILDINGS
)
## Soft-ignore mobile units so crowded bases can still place; static blockers remain hard.
const PLACEMENT_STATIC_COLLISION_MASK: int = PhysicsLayers.WORLD | PhysicsLayers.BUILDINGS
const BASE_SEARCH_RADIUS: float = 36.0
const GOLD_MINE_CLEARANCE: float = 5.0
const TREE_CLEARANCE: float = 4.0
const DROPOFF_PATH_WIDTH: float = 3.0
const MIN_NAV_PATH_POINTS: int = 2
const WORKER_NAV_TEST_Y: float = 0.5
const COMMAND_CENTER_DROP_OFF_OFFSET_X: float = 3.0

## Extra clear space around the town hall and production exits for workers / trained units.
const LANE_CLEARANCE: float = 1.5
const PRODUCTION_EXIT_LENGTH: float = 3.0
const TH_ACCESS_LANE: float = 1.2

const FARM_SIZE := Vector2(2.0, 1.4)
const BARRACKS_SIZE := Vector2(3.5, 2.5)
const BLACKSMITH_SIZE := Vector2(2.2, 1.8)
const STABLE_SIZE := Vector2(3.0, 2.2)
const ARTILLERY_DEPOT_SIZE := Vector2(3.2, 2.4)
const ACADEMY_SIZE := Vector2(3.0, 2.2)
const SHOP_SIZE := Vector2(2.0, 1.6)
const TOWER_SIZE := Vector2(2.0, 2.0)
const WALL_SEGMENT_SIZE := Vector2(1.0, 1.0)
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
const WALL_SEGMENT_GROUND_Y: float = 0.75
const HERO_ALTAR_GROUND_Y: float = 1.0
const COMMAND_CENTER_GROUND_Y: float = 1.0

## Legacy ring radii kept for expansion CC search (mine-anchored).
const RING_RADII: Array[float] = [5.0, 7.0, 9.0, 11.0, 13.0, 16.0, 20.0, 25.0, 31.0]
const EXPANSION_RING_RADII: Array[float] = [16.0, 19.0, 22.0, 26.0, 30.0]
const CANDIDATE_STEPS: int = 16

## Compact grid search: fill near base first, then expand outward.
const GRID_SEARCH_MAX_RADIUS: float = 28.0
const GAP_FILL_MAX_NEIGHBORS: int = 24

## Scoring weights (higher is better).
const SCORE_CLUSTER_WEIGHT: float = 14.0
const SCORE_CLUSTER_FALLOFF: float = 8.0
const SCORE_ALIGNMENT_BONUS: float = 9.0
const SCORE_FOOTPRINT_REUSE: float = 16.0
const SCORE_EARLY_EXPAND_PENALTY: float = 2.8
const SCORE_ISOLATION_DIST: float = 7.5
const SCORE_ISOLATION_PENALTY: float = 22.0
const SCORE_RESOURCE_SOFT_CAP: float = 12.0
const SCORE_RESOURCE_SOFT_WEIGHT: float = 0.08
const SCORE_FARM_ROW_BONUS: float = 20.0
const SCORE_FARM_OUTER_BONUS: float = 7.0
const SCORE_TOWER_APPROACH_BONUS: float = 12.0
const SCORE_PRODUCTION_EXIT_PENALTY: float = 28.0
const SCORE_ZONE_BAND_PENALTY: float = 3.5
const SCORE_TRAPPED_POCKET_PENALTY: float = 18.0
const SCORE_CORE_GROUP_BONUS: float = 10.0
const ALIGNMENT_TOLERANCE: float = 0.51
const BASE_BBOX_MARGIN: float = 2.0

enum LayoutZone {
	CORE,
	FARM,
	DEFENSE,
	EXPANSION,
}

## Debug: last AI placement search summary (debug builds / EnemyAIDebug).
static var last_placement_debug: Dictionary = {}
static var debug_placement_logs: bool = false


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
	var zone: LayoutZone = _get_layout_zone(building_type, prefer_expansion)
	var gold_mines: Array[Node3D] = _collect_enemy_gold_mines(anchor, scene_root)
	var trees: Array[Node3D] = _collect_enemy_trees(anchor, scene_root)
	var tree_center: Vector2 = _compute_tree_center(trees)
	var nav_from: Vector3 = Vector3(
		anchor.x + COMMAND_CENTER_DROP_OFF_OFFSET_X,
		WORKER_NAV_TEST_Y,
		anchor.z
	)
	var base_bbox: Rect2 = _compute_base_bbox(anchor, existing_buildings)
	var debug_enabled: bool = _is_placement_debug_enabled()
	var reject_counts: Dictionary = {}
	var scored_samples: Array[Dictionary] = []

	var candidate_phases: Array = _generate_candidate_phases(
		anchor,
		footprint,
		ground_y,
		zone,
		existing_buildings,
		prefer_expansion
	)

	var best_position: Vector3 = Vector3.INF
	var best_score: float = -INF
	var total_candidates: int = 0

	for phase_candidates: Variant in candidate_phases:
		var candidates: Array[Vector3] = phase_candidates
		total_candidates += candidates.size()
		var phase_best: Vector3 = Vector3.INF
		var phase_best_score: float = -INF

		for candidate: Vector3 in candidates:
			var reject_reason: String = _evaluate_hard_filters(
				candidate,
				building_type,
				footprint,
				anchor,
				existing_buildings,
				scene_root,
				gold_mines,
				trees,
				tree_center,
				nav_map,
				nav_from
			)
			if not reject_reason.is_empty():
				if debug_enabled:
					_count_reject(reject_counts, reject_reason)
				continue

			var score: float = _score_compact_position(
				candidate,
				anchor,
				building_type,
				footprint,
				zone,
				existing_buildings,
				gold_mines,
				trees,
				tree_center,
				base_bbox
			)
			if debug_enabled and scored_samples.size() < 12:
				scored_samples.append({
					"pos": Vector2(candidate.x, candidate.z),
					"score": snappedf(score, 0.01),
				})

			if _is_better_placement(
				candidate,
				score,
				phase_best,
				phase_best_score,
				anchor
			):
				phase_best_score = score
				phase_best = candidate

		# Prefer filling nearby / preferred-zone gaps before expanding outward.
		if phase_best.is_finite():
			best_position = phase_best
			best_score = phase_best_score
			break

	if debug_enabled:
		last_placement_debug = {
			"building_type": String(building_type),
			"zone": _zone_name(zone),
			"anchor": Vector2(anchor.x, anchor.z),
			"candidates": total_candidates,
			"rejects": reject_counts.duplicate(),
			"samples": scored_samples.duplicate(),
			"chosen": (
				Vector2(best_position.x, best_position.z) if best_position.is_finite()
				else Vector2(INF, INF)
			),
			"score": best_score if best_position.is_finite() else -INF,
		}
		_log_placement_debug(last_placement_debug)

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
	exclude_nodes: Array[Node] = [],
	ignore_mobile_units: bool = true,
	ignore_reservation_id: int = 0
) -> bool:
	var footprint: Vector2 = get_footprint(building_type)
	if not is_footprint_within_bounds(candidate, footprint):
		return false

	if not _is_position_clear(candidate, footprint, existing_buildings):
		return false

	if ConstructionReservations.overlaps_reserved_footprint(
		candidate,
		footprint,
		BUILDING_PADDING,
		ignore_reservation_id
	):
		return false

	if scene_root != null and _footprint_overlaps_blocked_colliders(
		candidate,
		footprint,
		scene_root,
		exclude_nodes,
		ignore_mobile_units
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
		&"wall_segment":
			return WALL_SEGMENT_SIZE
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
		&"wall_segment":
			return WALL_SEGMENT_GROUND_Y
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


static func get_last_placement_debug() -> Dictionary:
	return last_placement_debug.duplicate(true)


static func set_debug_placement_logs(enabled: bool) -> void:
	debug_placement_logs = enabled


static func _get_layout_zone(building_type: StringName, prefer_expansion: bool) -> LayoutZone:
	if prefer_expansion and building_type == &"command_center":
		return LayoutZone.EXPANSION

	match building_type:
		&"farm":
			return LayoutZone.FARM
		&"tower", &"wall_segment":
			return LayoutZone.DEFENSE
		_:
			return LayoutZone.CORE


static func _zone_name(zone: LayoutZone) -> String:
	match zone:
		LayoutZone.CORE:
			return "core"
		LayoutZone.FARM:
			return "farm"
		LayoutZone.DEFENSE:
			return "defense"
		LayoutZone.EXPANSION:
			return "expansion"
		_:
			return "unknown"


static func _zone_preferred_radius(zone: LayoutZone) -> Vector2:
	## Returns (min_preferred, max_preferred) distance from the town-hall anchor.
	match zone:
		LayoutZone.CORE:
			return Vector2(5.0, 13.0)
		LayoutZone.FARM:
			return Vector2(11.0, 20.0)
		LayoutZone.DEFENSE:
			return Vector2(13.0, 22.0)
		LayoutZone.EXPANSION:
			return Vector2(16.0, 30.0)
		_:
			return Vector2(5.0, 18.0)


static func _min_town_hall_clearance(footprint: Vector2) -> float:
	var cc_half: float = maxf(COMMAND_CENTER_SIZE.x, COMMAND_CENTER_SIZE.y) * 0.5
	var build_half: float = maxf(footprint.x, footprint.y) * 0.5
	return cc_half + build_half + BUILDING_PADDING + TH_ACCESS_LANE


static func _is_better_placement(
	candidate: Vector3,
	score: float,
	best_position: Vector3,
	best_score: float,
	anchor: Vector3
) -> bool:
	if not best_position.is_finite():
		return true
	if score > best_score + 0.0001:
		return true
	if score < best_score - 0.0001:
		return false

	# Deterministic tie-break: closer to anchor, then lower X, then lower Z.
	var cand_dist: float = _horizontal_distance(candidate, anchor)
	var best_dist: float = _horizontal_distance(best_position, anchor)
	if cand_dist < best_dist - 0.01:
		return true
	if cand_dist > best_dist + 0.01:
		return false
	if candidate.x < best_position.x - 0.01:
		return true
	if candidate.x > best_position.x + 0.01:
		return false
	return candidate.z < best_position.z


static func _generate_candidate_phases(
	anchor: Vector3,
	footprint: Vector2,
	ground_y: float,
	zone: LayoutZone,
	existing_buildings: Array[Node3D],
	prefer_expansion: bool
) -> Array:
	## Phase 0 = compact nearby/gap-fill; phase 1 = expanded recovery. First non-empty
	## successful phase wins so the base fills inward before sprawling.
	var phases: Array = []

	if prefer_expansion or zone == LayoutZone.EXPANSION:
		var expansion: Array[Vector3] = []
		var expansion_unique: Dictionary = {}
		_append_ring_candidates(
			expansion,
			expansion_unique,
			anchor,
			ground_y,
			EXPANSION_RING_RADII,
			CANDIDATE_STEPS
		)
		phases.append(expansion)
		return phases

	var band: Vector2 = _zone_preferred_radius(zone)
	var min_clearance: float = _min_town_hall_clearance(footprint)
	var compact: Array[Vector3] = []
	var compact_unique: Dictionary = {}

	_append_gap_fill_candidates(
		compact,
		compact_unique,
		anchor,
		footprint,
		ground_y,
		existing_buildings,
		zone
	)

	var compact_start: int = maxi(1, int(ceil(maxf(min_clearance, band.x - 2.0) / GRID_SIZE)))
	var compact_end: int = maxi(compact_start, int(ceil((band.y + 2.0) / GRID_SIZE)))
	for ring: int in range(compact_start, compact_end + 1):
		_append_chebyshev_ring_candidates(compact, compact_unique, anchor, ground_y, ring)

	phases.append(compact)

	var expanded: Array[Vector3] = []
	var expanded_unique: Dictionary = compact_unique.duplicate()
	var max_radius: float = mini(GRID_SEARCH_MAX_RADIUS, BASE_SEARCH_RADIUS)
	var expand_start: int = compact_end + 1
	var expand_end: int = int(ceil(max_radius / GRID_SIZE))
	for ring: int in range(expand_start, expand_end + 1):
		_append_chebyshev_ring_candidates(expanded, expanded_unique, anchor, ground_y, ring)
	_append_ring_candidates(expanded, expanded_unique, anchor, ground_y, RING_RADII, CANDIDATE_STEPS)
	phases.append(expanded)

	return phases


static func _compare_buildings_by_anchor_distance(
	a: Node3D,
	b: Node3D,
	anchor: Vector3
) -> bool:
	return _horizontal_distance(a.global_position, anchor) < _horizontal_distance(
		b.global_position,
		anchor
	)


static func _append_candidate(
	ordered: Array[Vector3],
	unique: Dictionary,
	candidate: Vector3,
	ground_y: float
) -> void:
	var snapped: Vector3 = snap_to_grid(candidate)
	snapped.y = ground_y
	var key: String = "%d:%d" % [int(round(snapped.x)), int(round(snapped.z))]
	if unique.has(key):
		return
	unique[key] = true
	ordered.append(snapped)


static func _append_ring_candidates(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	ground_y: float,
	ring_radii: Array[float],
	steps: int
) -> void:
	for radius: float in ring_radii:
		for step: int in range(steps):
			var angle: float = float(step) * TAU / float(steps)
			var offset := Vector2(cos(angle), sin(angle)) * radius
			_append_candidate(
				ordered,
				unique,
				Vector3(anchor.x + offset.x, ground_y, anchor.z + offset.y),
				ground_y
			)


static func _append_chebyshev_ring_candidates(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	ground_y: float,
	ring: int
) -> void:
	## Walk the square ring at chebyshev distance `ring` in a fixed clockwise order.
	var ax: int = int(round(anchor.x / GRID_SIZE))
	var az: int = int(round(anchor.z / GRID_SIZE))
	for dx: int in range(-ring, ring + 1):
		_append_candidate(
			ordered,
			unique,
			Vector3(float(ax + dx) * GRID_SIZE, ground_y, float(az - ring) * GRID_SIZE),
			ground_y
		)
		_append_candidate(
			ordered,
			unique,
			Vector3(float(ax + dx) * GRID_SIZE, ground_y, float(az + ring) * GRID_SIZE),
			ground_y
		)
	for dz: int in range(-ring + 1, ring):
		_append_candidate(
			ordered,
			unique,
			Vector3(float(ax - ring) * GRID_SIZE, ground_y, float(az + dz) * GRID_SIZE),
			ground_y
		)
		_append_candidate(
			ordered,
			unique,
			Vector3(float(ax + ring) * GRID_SIZE, ground_y, float(az + dz) * GRID_SIZE),
			ground_y
		)


static func _append_gap_fill_candidates(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	footprint: Vector2,
	ground_y: float,
	existing_buildings: Array[Node3D],
	zone: LayoutZone = LayoutZone.CORE
) -> void:
	var neighbors: Array[Node3D] = []
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue
		# Farms pack against other farms (rows); core buildings pack against core/production.
		if zone == LayoutZone.FARM and not (building is Farm):
			continue
		if zone == LayoutZone.CORE and building is Farm:
			continue
		if zone == LayoutZone.DEFENSE and building is Farm:
			continue
		neighbors.append(building)

	neighbors.sort_custom(_compare_buildings_by_anchor_distance.bind(anchor))

	var count: int = mini(neighbors.size(), GAP_FILL_MAX_NEIGHBORS)
	var cardinals: Array[Vector2] = [
		Vector2(1.0, 0.0),
		Vector2(-1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(0.0, -1.0),
	]

	for index: int in range(count):
		var building: Node3D = neighbors[index]
		var other_fp: Vector2 = _resolve_footprint(building)
		var other_pos: Vector3 = building.global_position
		for dir: Vector2 in cardinals:
			var gap_x: float = (footprint.x + other_fp.x) * 0.5 + BUILDING_PADDING
			var gap_z: float = (footprint.y + other_fp.y) * 0.5 + BUILDING_PADDING
			var offset := Vector3(dir.x * gap_x, 0.0, dir.y * gap_z)
			_append_candidate(
				ordered,
				unique,
				Vector3(other_pos.x + offset.x, ground_y, other_pos.z + offset.z),
				ground_y
			)


static func _evaluate_hard_filters(
	candidate: Vector3,
	building_type: StringName,
	footprint: Vector2,
	anchor: Vector3,
	existing_buildings: Array[Node3D],
	scene_root: Node,
	gold_mines: Array[Node3D],
	trees: Array[Node3D],
	tree_center: Vector2,
	nav_map: RID,
	nav_from: Vector3
) -> String:
	if anchor.distance_squared_to(candidate) > BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS:
		return "out_of_search_radius"

	if not is_footprint_within_bounds(candidate, footprint):
		return "out_of_bounds"

	if _horizontal_distance(candidate, anchor) < _min_town_hall_clearance(footprint):
		return "blocks_town_hall_access"

	if not is_position_valid(candidate, building_type, existing_buildings, scene_root):
		return "overlap_or_blocked"

	if _is_too_close_to_resources(candidate, gold_mines, trees):
		return "too_close_to_resources"

	if _blocks_dropoff_path(candidate, footprint, anchor, gold_mines, tree_center):
		return "blocks_resource_route"

	if _blocks_gate_opening(candidate, footprint, existing_buildings):
		return "blocks_gate"

	var nav_to: Vector3 = Vector3(candidate.x, WORKER_NAV_TEST_Y, candidate.z)
	if not _is_nav_reachable(nav_map, nav_from, nav_to):
		return "nav_unreachable"

	return ""


static func _score_compact_position(
	candidate: Vector3,
	anchor: Vector3,
	building_type: StringName,
	footprint: Vector2,
	zone: LayoutZone,
	existing_buildings: Array[Node3D],
	gold_mines: Array[Node3D],
	trees: Array[Node3D],
	tree_center: Vector2,
	base_bbox: Rect2
) -> float:
	var score: float = 0.0
	var cand_xz := Vector2(candidate.x, candidate.z)
	var anchor_dist: float = _horizontal_distance(candidate, anchor)

	# Soft preference to stay inside the zone band (not a hard reject — recovery expands out).
	var band: Vector2 = _zone_preferred_radius(zone)
	if anchor_dist < band.x:
		score -= (band.x - anchor_dist) * SCORE_ZONE_BAND_PENALTY
	elif anchor_dist > band.y:
		score -= (anchor_dist - band.y) * SCORE_ZONE_BAND_PENALTY

	# Pull core buildings toward the town hall; farms/towers less so.
	match zone:
		LayoutZone.CORE:
			score -= anchor_dist * 1.6
		LayoutZone.FARM:
			score -= anchor_dist * 0.2
			if anchor_dist >= band.x and anchor_dist <= band.y:
				score += SCORE_FARM_OUTER_BONUS
				# Prefer the outer half of the farm band for the first farms.
				var band_mid: float = (band.x + band.y) * 0.5
				if anchor_dist >= band_mid:
					score += SCORE_FARM_OUTER_BONUS * 0.75
		LayoutZone.DEFENSE:
			score -= anchor_dist * 0.25
		LayoutZone.EXPANSION:
			score -= absf(anchor_dist - 20.0) * 0.4
		_:
			score -= anchor_dist * 0.8

	var nearest_dist: float = INF
	var cluster_score: float = 0.0
	var aligned: bool = false
	var core_neighbors: int = 0
	var farm_row_bonus: float = 0.0
	var surround_hits: int = 0
	var surround_dirs: Array[Vector2] = [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
	]

	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue

		var other_fp: Vector2 = _resolve_footprint(building)
		var other_pos: Vector3 = building.global_position
		var dist: float = _horizontal_distance(candidate, other_pos)
		if dist < nearest_dist:
			nearest_dist = dist

		if dist < SCORE_CLUSTER_FALLOFF:
			var weight: float = SCORE_CLUSTER_WEIGHT * (1.0 - dist / SCORE_CLUSTER_FALLOFF)
			if zone == LayoutZone.CORE and _is_core_building_node(building):
				weight *= 1.35
				core_neighbors += 1
			elif zone == LayoutZone.FARM and building is Farm:
				weight *= 1.45
			elif zone == LayoutZone.FARM:
				# Farms should not glue onto barracks / town-hall clusters.
				weight *= 0.25
			elif zone == LayoutZone.CORE and building is Farm:
				weight *= 0.35
			cluster_score += weight

		if (
			absf(candidate.x - other_pos.x) <= ALIGNMENT_TOLERANCE
			or absf(candidate.z - other_pos.z) <= ALIGNMENT_TOLERANCE
		):
			aligned = true

		if zone == LayoutZone.FARM and building is Farm:
			var row_gap_x: float = (footprint.x + other_fp.x) * 0.5 + BUILDING_PADDING
			var row_gap_z: float = (footprint.y + other_fp.y) * 0.5 + BUILDING_PADDING
			var dx: float = absf(candidate.x - other_pos.x)
			var dz: float = absf(candidate.z - other_pos.z)
			if (
				(absf(dx - row_gap_x) <= GRID_SIZE * 0.6 and dz <= ALIGNMENT_TOLERANCE)
				or (absf(dz - row_gap_z) <= GRID_SIZE * 0.6 and dx <= ALIGNMENT_TOLERANCE)
			):
				farm_row_bonus = maxf(farm_row_bonus, SCORE_FARM_ROW_BONUS)

		for dir: Vector2 in surround_dirs:
			var probe := Vector2(
				candidate.x + dir.x * (footprint.x * 0.5 + BUILDING_PADDING + 0.5),
				candidate.z + dir.y * (footprint.y * 0.5 + BUILDING_PADDING + 0.5)
			)
			var other_xz := Vector2(other_pos.x, other_pos.z)
			if probe.distance_to(other_xz) < maxf(other_fp.x, other_fp.y) * 0.65 + 0.5:
				surround_hits += 1
				break

	score += cluster_score
	if aligned:
		score += SCORE_ALIGNMENT_BONUS
	if core_neighbors >= 2:
		score += SCORE_CORE_GROUP_BONUS
	score += farm_row_bonus

	if nearest_dist > SCORE_ISOLATION_DIST and not existing_buildings.is_empty():
		score -= SCORE_ISOLATION_PENALTY * minf(
			1.0,
			(nearest_dist - SCORE_ISOLATION_DIST) / SCORE_ISOLATION_DIST
		)

	# Prefer reusing the current base footprint before expanding outward.
	if base_bbox.has_point(cand_xz):
		score += SCORE_FOOTPRINT_REUSE
	else:
		var expand_dist: float = _distance_outside_rect(cand_xz, base_bbox)
		score -= expand_dist * SCORE_EARLY_EXPAND_PENALTY

	# Mild preference to stay clear of resources (hard filters already enforce clearance).
	for mine: Node3D in gold_mines:
		if mine == null or not is_instance_valid(mine):
			continue
		score += minf(_horizontal_distance(candidate, mine.global_position), SCORE_RESOURCE_SOFT_CAP) * SCORE_RESOURCE_SOFT_WEIGHT

	for tree: Node3D in trees:
		if tree == null or not is_instance_valid(tree):
			continue
		score += minf(_horizontal_distance(candidate, tree.global_position), SCORE_RESOURCE_SOFT_CAP) * SCORE_RESOURCE_SOFT_WEIGHT * 0.35

	if zone == LayoutZone.DEFENSE:
		score += _score_tower_approach(candidate, anchor, gold_mines, tree_center, base_bbox)

	if _blocks_production_exit_lane(candidate, footprint, existing_buildings):
		score -= SCORE_PRODUCTION_EXIT_PENALTY

	# Penalize positions that would sit in a nearly enclosed pocket.
	if surround_hits >= 5:
		score -= SCORE_TRAPPED_POCKET_PENALTY

	return score


static func _score_tower_approach(
	candidate: Vector3,
	anchor: Vector3,
	gold_mines: Array[Node3D],
	tree_center: Vector2,
	base_bbox: Rect2
) -> float:
	var score: float = 0.0
	var cand := Vector2(candidate.x, candidate.z)
	var anchor_xz := Vector2(anchor.x, anchor.z)

	# Prefer base rim / approaches rather than deep interior.
	if not base_bbox.grow(1.0).has_point(cand):
		score += SCORE_TOWER_APPROACH_BONUS * 0.35
	else:
		var rim_dist: float = _distance_outside_rect(cand, base_bbox.grow(-2.0))
		if rim_dist <= 0.01:
			score += SCORE_TOWER_APPROACH_BONUS * 0.5

	for mine: Node3D in gold_mines:
		if mine == null or not is_instance_valid(mine):
			continue
		var mine_xz := Vector2(mine.global_position.x, mine.global_position.z)
		var corridor_dist: float = _distance_point_to_segment(cand, anchor_xz, mine_xz)
		# Sit near the approach, but outside the hard dropoff corridor width.
		if corridor_dist >= DROPOFF_PATH_WIDTH and corridor_dist <= DROPOFF_PATH_WIDTH + 4.0:
			score += SCORE_TOWER_APPROACH_BONUS

	if tree_center.is_finite():
		var tree_corridor: float = _distance_point_to_segment(cand, anchor_xz, tree_center)
		if tree_corridor >= DROPOFF_PATH_WIDTH and tree_corridor <= DROPOFF_PATH_WIDTH + 4.0:
			score += SCORE_TOWER_APPROACH_BONUS * 0.65

	return score


static func _blocks_production_exit_lane(
	candidate: Vector3,
	footprint: Vector2,
	existing_buildings: Array[Node3D]
) -> bool:
	var cardinals: Array[Vector2] = [
		Vector2(1.0, 0.0),
		Vector2(-1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(0.0, -1.0),
	]
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue
		if not _is_production_building_node(building):
			continue

		var other_fp: Vector2 = _resolve_footprint(building)
		var other_pos: Vector3 = building.global_position
		for dir: Vector2 in cardinals:
			var lane_start := Vector2(
				other_pos.x + dir.x * (other_fp.x * 0.5 + BUILDING_PADDING * 0.5),
				other_pos.z + dir.y * (other_fp.y * 0.5 + BUILDING_PADDING * 0.5)
			)
			var lane_end := lane_start + dir * PRODUCTION_EXIT_LENGTH
			var cand_point := Vector2(candidate.x, candidate.z)
			if _distance_point_to_segment(cand_point, lane_start, lane_end) < LANE_CLEARANCE:
				# Only treat as blocked if the candidate actually sits on that exit side.
				var side_dot: float = (cand_point - Vector2(other_pos.x, other_pos.z)).dot(dir)
				if side_dot > 0.0:
					var overlap_probe := Vector3(
						other_pos.x + dir.x * ((other_fp.x + footprint.x) * 0.5 + BUILDING_PADDING),
						candidate.y,
						other_pos.z + dir.y * ((other_fp.y + footprint.y) * 0.5 + BUILDING_PADDING)
					)
					if _horizontal_distance(candidate, overlap_probe) < maxf(footprint.x, footprint.y):
						return true

	return false


static func _blocks_gate_opening(
	candidate: Vector3,
	footprint: Vector2,
	existing_buildings: Array[Node3D]
) -> bool:
	var walls: Array[Vector3] = []
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue
		if building is WallSegment:
			walls.append(building.global_position)

	if walls.size() < 2:
		return false

	for i: int in range(walls.size()):
		for j: int in range(i + 1, walls.size()):
			var a: Vector3 = walls[i]
			var b: Vector3 = walls[j]
			var dx: float = absf(a.x - b.x)
			var dz: float = absf(a.z - b.z)
			# Gate gap: two wall cells two grid steps apart on the same row/column.
			var is_gate_row: bool = is_zero_approx(dz) and is_equal_approx(dx, GRID_SIZE * 2.0)
			var is_gate_col: bool = is_zero_approx(dx) and is_equal_approx(dz, GRID_SIZE * 2.0)
			if not is_gate_row and not is_gate_col:
				continue

			var gate_mid := Vector3((a.x + b.x) * 0.5, candidate.y, (a.z + b.z) * 0.5)
			if _overlaps(candidate, footprint, gate_mid, WALL_SEGMENT_SIZE):
				return true

	return false


static func _is_core_building_node(building: Node3D) -> bool:
	return (
		building is Barracks
		or building is Blacksmith
		or building is Shop
		or building is HeroAltar
		or building is Academy
		or building is Stable
		or building is ArtilleryDepot
	)


static func _is_production_building_node(building: Node3D) -> bool:
	return (
		building is Barracks
		or building is Stable
		or building is ArtilleryDepot
		or building is Academy
		or building is CommandCenter
		or building is HeroAltar
	)


static func _compute_base_bbox(anchor: Vector3, existing_buildings: Array[Node3D]) -> Rect2:
	var min_x: float = anchor.x
	var max_x: float = anchor.x
	var min_z: float = anchor.z
	var max_z: float = anchor.z
	var any: bool = false

	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue
		if building is WallSegment:
			continue

		var fp: Vector2 = _resolve_footprint(building)
		var pos: Vector3 = building.global_position
		min_x = minf(min_x, pos.x - fp.x * 0.5)
		max_x = maxf(max_x, pos.x + fp.x * 0.5)
		min_z = minf(min_z, pos.z - fp.y * 0.5)
		max_z = maxf(max_z, pos.z + fp.y * 0.5)
		any = true

	if not any:
		var seed: float = maxf(COMMAND_CENTER_SIZE.x, COMMAND_CENTER_SIZE.y) * 0.5 + 4.0
		return Rect2(anchor.x - seed, anchor.z - seed, seed * 2.0, seed * 2.0)

	return Rect2(
		min_x - BASE_BBOX_MARGIN,
		min_z - BASE_BBOX_MARGIN,
		(max_x - min_x) + BASE_BBOX_MARGIN * 2.0,
		(max_z - min_z) + BASE_BBOX_MARGIN * 2.0
	)


static func _distance_outside_rect(point: Vector2, rect: Rect2) -> float:
	if rect.has_point(point):
		return 0.0

	var dx: float = 0.0
	if point.x < rect.position.x:
		dx = rect.position.x - point.x
	elif point.x > rect.end.x:
		dx = point.x - rect.end.x

	var dy: float = 0.0
	if point.y < rect.position.y:
		dy = rect.position.y - point.y
	elif point.y > rect.end.y:
		dy = point.y - rect.end.y

	return sqrt(dx * dx + dy * dy)


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset: Vector3 = a - b
	offset.y = 0.0
	return offset.length()


static func _is_placement_debug_enabled() -> bool:
	if debug_placement_logs:
		return true
	if not OS.is_debug_build():
		return false
	return EnemyAIDebug.is_enabled()


static func _count_reject(reject_counts: Dictionary, reason: String) -> void:
	reject_counts[reason] = int(reject_counts.get(reason, 0)) + 1


static func _log_placement_debug(info: Dictionary) -> void:
	var rejects: Dictionary = info.get("rejects", {})
	var reject_parts: PackedStringArray = []
	for key: Variant in rejects.keys():
		reject_parts.append("%s=%s" % [str(key), str(rejects[key])])

	var chosen: Vector2 = info.get("chosen", Vector2(INF, INF))
	var chosen_text: String = "none"
	if chosen.is_finite():
		chosen_text = "(%.0f, %.0f) score=%.2f" % [
			chosen.x,
			chosen.y,
			float(info.get("score", 0.0)),
		]

	print(
		"[AI Placement] %s zone=%s candidates=%s chosen=%s rejects={%s}"
		% [
			str(info.get("building_type", "?")),
			str(info.get("zone", "?")),
			str(info.get("candidates", 0)),
			chosen_text,
			", ".join(reject_parts),
		]
	)

	var samples: Array = info.get("samples", [])
	for sample: Variant in samples:
		if sample is Dictionary:
			var sample_pos: Vector2 = sample.get("pos", Vector2.ZERO)
			print(
				"  candidate (%.0f, %.0f) compactness=%.2f"
				% [sample_pos.x, sample_pos.y, float(sample.get("score", 0.0))]
			)


static func _collect_enemy_gold_mines(anchor: Vector3, scene_root: Node) -> Array[Node3D]:
	var mines: Array[Node3D] = []
	if scene_root == null:
		return mines

	var radius_sq: float = BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS
	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if child == null or not is_instance_valid(child) or not child is GoldMine:
			continue
		if child.global_position.distance_squared_to(anchor) > radius_sq:
			continue

		mines.append(child as Node3D)

	return mines


static func _collect_enemy_trees(anchor: Vector3, scene_root: Node) -> Array[Node3D]:
	var trees: Array[Node3D] = []
	if scene_root == null:
		return trees

	var radius_sq: float = BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS
	for child: Node in WorkerGathering._map_resource_children(scene_root):
		if child == null or not is_instance_valid(child) or not child is WoodTree:
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
	footprint: Vector2,
	anchor: Vector3,
	gold_mines: Array[Node3D],
	tree_center: Vector2
) -> bool:
	var point := Vector2(candidate.x, candidate.z)
	var command_center := Vector2(anchor.x, anchor.z)
	## Widen corridor slightly by footprint so larger buildings cannot clip the lane edges.
	var corridor_width: float = DROPOFF_PATH_WIDTH + maxf(footprint.x, footprint.y) * 0.15

	for mine: Node3D in gold_mines:
		if mine == null or not is_instance_valid(mine):
			continue

		var mine_point := Vector2(mine.global_position.x, mine.global_position.z)
		if _distance_point_to_segment(point, command_center, mine_point) < corridor_width:
			return true

	if tree_center.is_finite():
		if _distance_point_to_segment(point, command_center, tree_center) < corridor_width:
			return true

	return false


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
	exclude_nodes: Array[Node] = [],
	ignore_mobile_units: bool = true
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
	query.collision_mask = (
		PLACEMENT_STATIC_COLLISION_MASK if ignore_mobile_units else PLACEMENT_COLLISION_MASK
	)
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
		if _collider_blocks_placement(collider, ignore_mobile_units):
			return true

	return false


static func _collider_blocks_placement(
	collider: Object,
	ignore_mobile_units: bool = true
) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false

	if collider is CharacterBody3D:
		return not ignore_mobile_units

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
	if building is WallSegment:
		return WALL_SEGMENT_SIZE
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


static func get_wall_segment_line_positions(
	start: Vector3,
	end: Vector3,
	ground_y: float,
	max_segments: int = 30
) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if max_segments <= 0:
		return positions

	var snapped_start: Vector3 = snap_to_grid(start)
	var snapped_end: Vector3 = snap_to_grid(end)
	snapped_start.y = ground_y
	snapped_end.y = ground_y

	var delta_x: float = snapped_end.x - snapped_start.x
	var delta_z: float = snapped_end.z - snapped_start.z
	var along_x: bool = absf(delta_x) >= absf(delta_z)

	if along_x:
		var step_x: int = 1 if delta_x >= 0.0 else -1
		var segment_count: int = int(absf(delta_x) / GRID_SIZE) + 1
		segment_count = mini(segment_count, max_segments)
		for step_index: int in range(segment_count):
			var x: float = snapped_start.x + float(step_index * step_x) * GRID_SIZE
			positions.append(Vector3(x, ground_y, snapped_start.z))
	else:
		var step_z: int = 1 if delta_z >= 0.0 else -1
		var segment_count: int = int(absf(delta_z) / GRID_SIZE) + 1
		segment_count = mini(segment_count, max_segments)
		for step_index: int in range(segment_count):
			var z: float = snapped_start.z + float(step_index * step_z) * GRID_SIZE
			positions.append(Vector3(snapped_start.x, ground_y, z))

	return positions


static func is_wall_segment_line_position_valid(
	candidate: Vector3,
	line_positions: Array[Vector3],
	existing_buildings: Array[Node3D],
	scene_root: Node = null,
	exclude_nodes: Array[Node] = [],
	ignore_mobile_units: bool = true,
	ignore_reservation_id: int = 0
) -> bool:
	var footprint: Vector2 = WALL_SEGMENT_SIZE
	if not is_footprint_within_bounds(candidate, footprint):
		return false

	if not _is_wall_position_clear_of_buildings(candidate, footprint, existing_buildings):
		return false

	if not _is_wall_position_clear_of_line_siblings(candidate, footprint, line_positions):
		return false

	if ConstructionReservations.overlaps_reserved_footprint(
		candidate,
		footprint,
		BUILDING_PADDING,
		ignore_reservation_id
	):
		return false

	if scene_root != null and _footprint_overlaps_blocked_colliders(
		candidate,
		footprint,
		scene_root,
		exclude_nodes,
		ignore_mobile_units
	):
		return false

	return true


static func _are_adjacent_wall_cells(position_a: Vector3, position_b: Vector3) -> bool:
	var delta_x: float = absf(position_a.x - position_b.x)
	var delta_z: float = absf(position_a.z - position_b.z)
	return (
		(is_equal_approx(delta_x, GRID_SIZE) and is_zero_approx(delta_z))
		or (is_equal_approx(delta_z, GRID_SIZE) and is_zero_approx(delta_x))
	)


static func _is_wall_position_clear_of_buildings(
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


static func _is_wall_position_clear_of_line_siblings(
	candidate: Vector3,
	footprint: Vector2,
	line_positions: Array[Vector3]
) -> bool:
	for sibling: Vector3 in line_positions:
		if is_equal_approx(candidate.x, sibling.x) and is_equal_approx(candidate.z, sibling.z):
			continue

		if _are_adjacent_wall_cells(candidate, sibling):
			continue

		if _overlaps(candidate, footprint, sibling, WALL_SEGMENT_SIZE):
			return false

	return true
