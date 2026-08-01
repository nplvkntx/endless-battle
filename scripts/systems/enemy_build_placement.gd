class_name EnemyBuildPlacement
extends RefCounted

## Shared building placement rules: grid snap, map bounds, footprints, and AI position search.
## AI uses deterministic row/slot anchors relative to the Command Center (front = toward map
## center), then falls back to compact gap-fill while preserving walkable movement lanes.

const GRID_SIZE: float = 1.0
const MAP_MIN_X: float = -50.0
const MAP_MAX_X: float = 50.0
const MAP_MIN_Z: float = -50.0
const MAP_MAX_Z: float = 50.0
const MAP_CENTER_XZ := Vector2(0.0, 0.0)

## Footprint-edge safety margin shared with player placement / reservations.
## Kept small so preview, collision, and nav blocking stay visually tight.
const BUILDING_PADDING: float = 0.4
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
const PRODUCTION_EXIT_LENGTH: float = 3.5
const TH_ACCESS_LANE: float = 1.5
const ARMY_LANE_HALF_WIDTH: float = 2.0
const SLOT_OCCUPIED_TOLERANCE: float = 1.1

## Barracks defensive row (front of CC, toward map center / enemy approach).
const BARRACKS_ROW_SLOTS: int = 3
const BARRACKS_ROW_FRONT_OFFSET: float = 8.0
const BARRACKS_SLOT_SPACING: float = 4.5
const BARRACKS_ROW2_FRONT_OFFSET: float = 12.5
const BARRACKS_REAR_LANE_DEPTH: float = 2.0

## Farm rows (toward map edge / behind CC). Fill one row before starting the next.
const FARM_ROW_SLOTS: int = 4
const FARM_ROW_BACK_OFFSET: float = 9.0
const FARM_SLOT_SPACING: float = 2.6
const FARM_ROW_PITCH: float = 2.2
const FARM_MAX_ROWS: int = 3

## Tech / utility side rows (behind or beside the barracks line, not in front).
## Kept outside the central army lane half-width (~6.5).
const TECH_SIDE_OFFSET: float = 9.0
const TECH_SLOT_SPACING: float = 3.6
const TECH_BACK_BIAS: float = 2.0
const TECH_ROW_SLOTS: int = 3

## Tower outer defensive corners / approach flanks.
const TOWER_FRONT_OFFSET: float = 11.0
const TOWER_SIDE_OFFSET: float = 10.0
const TOWER_BACK_OFFSET: float = 10.5

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

## Optional bias for tower planned-slot order (set by EnemyAttackPathDefense).
static var preferred_tower_lane: StringName = &""


static func set_tower_lane_preference(lane: StringName) -> void:
	preferred_tower_lane = lane


static func clear_tower_lane_preference() -> void:
	preferred_tower_lane = &""


static func resolve_base_frame_public(anchor: Vector3) -> Dictionary:
	return _resolve_base_frame(anchor)


static func local_front_right_public(point: Vector3, anchor: Vector3, frame: Dictionary) -> Vector2:
	return _local_front_right(point, anchor, frame)


static func get_tower_slots_for_lane(
	anchor: Vector3,
	lane: StringName,
	existing_buildings: Array[Node3D]
) -> Array[Vector3]:
	var previous_lane: StringName = preferred_tower_lane
	preferred_tower_lane = lane
	var ground_y: float = get_ground_y(&"tower")
	var frame: Dictionary = _resolve_base_frame(anchor)
	var slots: Array[Vector3] = []
	var unique: Dictionary = {}
	_append_tower_slots(slots, unique, anchor, ground_y, frame, existing_buildings)
	preferred_tower_lane = previous_lane
	return slots


static func tower_blocks_reserved_lanes(
	candidate: Vector3,
	existing_buildings: Array[Node3D]
) -> bool:
	var footprint: Vector2 = get_footprint(&"tower")
	var frame: Dictionary = {}
	var anchor: Vector3 = Vector3.ZERO
	for building: Node3D in existing_buildings:
		if building is CommandCenter and is_instance_valid(building):
			anchor = building.global_position
			frame = _resolve_base_frame(anchor)
			break
	if frame.is_empty():
		return _blocks_production_exit_lane(candidate, footprint, existing_buildings)
	return (
		_blocks_reserved_movement_lanes(candidate, footprint, &"tower", anchor, frame)
		or _blocks_production_exit_lane(candidate, footprint, existing_buildings)
	)


static func is_builder_reachable(from_pos: Vector3, to_pos: Vector3, nav_map: RID) -> bool:
	if not nav_map.is_valid():
		return true
	var from := Vector3(from_pos.x, WORKER_NAV_TEST_Y, from_pos.z)
	var to := Vector3(to_pos.x, WORKER_NAV_TEST_Y, to_pos.z)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
	return path.size() >= MIN_NAV_PATH_POINTS


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
	var frame: Dictionary = _resolve_base_frame(anchor)
	var debug_enabled: bool = _is_placement_debug_enabled()
	var reject_counts: Dictionary = {}
	var scored_samples: Array[Dictionary] = []

	var best_position: Vector3 = Vector3.INF
	var best_score: float = -INF
	var total_candidates: int = 0
	var chosen_source: String = "none"

	# Planned row/slot anchors first — deterministic, no random offsets.
	if not prefer_expansion and zone != LayoutZone.EXPANSION:
		var planned_slots: Array[Vector3] = _generate_planned_slots(
			anchor,
			building_type,
			footprint,
			ground_y,
			frame,
			existing_buildings
		)
		total_candidates += planned_slots.size()
		for candidate: Vector3 in planned_slots:
			var planned_reject: String = _evaluate_hard_filters(
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
				nav_from,
				frame
			)
			if not planned_reject.is_empty():
				if debug_enabled:
					_count_reject(reject_counts, planned_reject)
				continue

			best_position = candidate
			best_score = 1000.0
			chosen_source = "planned_slot"
			break

	if not best_position.is_finite():
		var candidate_phases: Array = _generate_candidate_phases(
			anchor,
			footprint,
			ground_y,
			zone,
			existing_buildings,
			prefer_expansion,
			frame,
			building_type
		)

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
					nav_from,
					frame
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
					base_bbox,
					frame
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
				chosen_source = "fallback_search"
				break

	if debug_enabled:
		last_placement_debug = {
			"building_type": String(building_type),
			"zone": _zone_name(zone),
			"anchor": Vector2(anchor.x, anchor.z),
			"front": frame.get("front", Vector2.ZERO),
			"candidates": total_candidates,
			"rejects": reject_counts.duplicate(),
			"samples": scored_samples.duplicate(),
			"source": chosen_source,
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
			return Vector2(5.0, 14.0)
		LayoutZone.FARM:
			return Vector2(8.0, 18.0)
		LayoutZone.DEFENSE:
			return Vector2(10.0, 22.0)
		LayoutZone.EXPANSION:
			return Vector2(16.0, 30.0)
		_:
			return Vector2(5.0, 18.0)


static func _resolve_base_frame(anchor: Vector3) -> Dictionary:
	## Front faces map center (likely enemy approach), snapped to nearest cardinal so
	## row anchors stay axis-aligned and deterministic.
	var to_center := Vector2(MAP_CENTER_XZ.x - anchor.x, MAP_CENTER_XZ.y - anchor.z)
	if to_center.length_squared() < 0.0001:
		to_center = Vector2(-1.0, 0.0)

	var front: Vector2
	if absf(to_center.x) >= absf(to_center.y):
		front = Vector2(signf(to_center.x), 0.0)
	else:
		front = Vector2(0.0, signf(to_center.y))

	## Clockwise perpendicular in XZ: (x, z) -> (z, -x)
	var right := Vector2(front.y, -front.x)
	return {
		"front": front,
		"right": right,
		"back": -front,
		"left": -right,
	}


static func _slot_world_position(
	anchor: Vector3,
	ground_y: float,
	frame: Dictionary,
	front_offset: float,
	right_offset: float
) -> Vector3:
	var front: Vector2 = frame.get("front", Vector2(-1.0, 0.0))
	var right: Vector2 = frame.get("right", Vector2(0.0, 1.0))
	var pos := Vector3(
		anchor.x + front.x * front_offset + right.x * right_offset,
		ground_y,
		anchor.z + front.y * front_offset + right.y * right_offset
	)
	return snap_to_grid(pos)


static func _local_front_right(point: Vector3, anchor: Vector3, frame: Dictionary) -> Vector2:
	var front: Vector2 = frame.get("front", Vector2(-1.0, 0.0))
	var right: Vector2 = frame.get("right", Vector2(0.0, 1.0))
	var delta := Vector2(point.x - anchor.x, point.z - anchor.z)
	return Vector2(delta.dot(front), delta.dot(right))


static func _is_slot_occupied(
	slot: Vector3,
	existing_buildings: Array[Node3D],
	match_type: StringName = &""
) -> bool:
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue
		if match_type != &"" and not _building_matches_type(building, match_type):
			continue
		var offset: Vector3 = building.global_position - slot
		offset.y = 0.0
		if offset.length() <= SLOT_OCCUPIED_TOLERANCE:
			return true
	return false


static func _building_matches_type(building: Node3D, building_type: StringName) -> bool:
	match building_type:
		&"farm":
			return building is Farm
		&"barracks":
			return building is Barracks
		&"blacksmith":
			return building is Blacksmith
		&"stable":
			return building is Stable
		&"artillery_depot":
			return building is ArtilleryDepot
		&"academy":
			return building is Academy
		&"shop":
			return building is Shop
		&"tower":
			return building is Tower
		&"wall_segment":
			return building is WallSegment
		&"hero_altar":
			return building is HeroAltar
		&"command_center":
			return building is CommandCenter
		_:
			return false


static func _generate_planned_slots(
	anchor: Vector3,
	building_type: StringName,
	_footprint: Vector2,
	ground_y: float,
	frame: Dictionary,
	existing_buildings: Array[Node3D]
) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var unique: Dictionary = {}

	match building_type:
		&"barracks":
			_append_barracks_row_slots(slots, unique, anchor, ground_y, frame, existing_buildings)
		&"farm":
			_append_farm_row_slots(slots, unique, anchor, ground_y, frame, existing_buildings)
		&"tower":
			_append_tower_slots(slots, unique, anchor, ground_y, frame, existing_buildings)
		&"blacksmith":
			_append_tech_row_slots(
				slots, unique, anchor, ground_y, frame, existing_buildings, building_type
			)
		&"shop":
			_append_tech_row_slots(
				slots, unique, anchor, ground_y, frame, existing_buildings, building_type
			)
		&"hero_altar":
			_append_tech_row_slots(
				slots, unique, anchor, ground_y, frame, existing_buildings, building_type
			)
		&"stable":
			_append_tech_row_slots(
				slots, unique, anchor, ground_y, frame, existing_buildings, building_type
			)
		&"academy":
			_append_tech_row_slots(
				slots, unique, anchor, ground_y, frame, existing_buildings, building_type
			)
		&"artillery_depot":
			_append_tech_row_slots(
				slots, unique, anchor, ground_y, frame, existing_buildings, building_type
			)
		_:
			pass

	return slots


static func _append_unique_slot(
	ordered: Array[Vector3],
	unique: Dictionary,
	slot: Vector3,
	existing_buildings: Array[Node3D],
	skip_if_any_building: bool = true
) -> void:
	var key: String = "%d:%d" % [int(round(slot.x)), int(round(slot.z))]
	if unique.has(key):
		return
	if skip_if_any_building and _is_slot_occupied(slot, existing_buildings):
		return
	unique[key] = true
	ordered.append(slot)


static func _append_barracks_row_slots(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	ground_y: float,
	frame: Dictionary,
	existing_buildings: Array[Node3D]
) -> void:
	## Prefer a single organized row of up to 3, then a second forward row if needed.
	var row_offsets: Array[float] = [BARRACKS_ROW_FRONT_OFFSET, BARRACKS_ROW2_FRONT_OFFSET]
	var lateral_indices: Array[int] = [0, -1, 1] ## center first, then flanks
	for front_offset: float in row_offsets:
		for index: int in lateral_indices:
			var slot: Vector3 = _slot_world_position(
				anchor,
				ground_y,
				frame,
				front_offset,
				float(index) * BARRACKS_SLOT_SPACING
			)
			_append_unique_slot(ordered, unique, slot, existing_buildings)


static func _append_farm_row_slots(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	ground_y: float,
	frame: Dictionary,
	existing_buildings: Array[Node3D]
) -> void:
	## Edge-parallel rows behind the CC. Fill row N before starting row N+1.
	var half_span: float = float(FARM_ROW_SLOTS - 1) * 0.5
	for row: int in range(FARM_MAX_ROWS):
		var back_offset: float = FARM_ROW_BACK_OFFSET + float(row) * FARM_ROW_PITCH
		var front_offset: float = -back_offset
		var row_added: int = 0
		for slot_i: int in range(FARM_ROW_SLOTS):
			var lateral: float = (float(slot_i) - half_span) * FARM_SLOT_SPACING
			var slot: Vector3 = _slot_world_position(
				anchor,
				ground_y,
				frame,
				front_offset,
				lateral
			)
			var before: int = ordered.size()
			_append_unique_slot(ordered, unique, slot, existing_buildings)
			if ordered.size() > before:
				row_added += 1
		## Keep offering later rows even if this row had blockers — recovery continues.
		if row_added == 0 and row > 0:
			## Still try remaining rows; do not abort the whole plan.
			pass


static func _append_tech_row_slots(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	ground_y: float,
	frame: Dictionary,
	existing_buildings: Array[Node3D],
	building_type: StringName
) -> void:
	## Left row: blacksmith / shop / hero altar. Right row: stable / academy / artillery.
	## Slots run beside then slightly behind the CC — never past the barracks front line.
	var prefer_left: bool = (
		building_type == &"blacksmith"
		or building_type == &"shop"
		or building_type == &"hero_altar"
	)
	var side_signs: Array[float] = []
	if prefer_left:
		side_signs.append(-1.0)
		side_signs.append(1.0)
	else:
		side_signs.append(1.0)
		side_signs.append(-1.0)

	var type_slot: int = _tech_preferred_slot_index(building_type)
	## front-local offsets: slightly beside courtyard, then stepping backward.
	var front_slots: Array[float] = []
	front_slots.append(1.0)
	front_slots.append(-TECH_BACK_BIAS)
	front_slots.append(-TECH_BACK_BIAS - TECH_SLOT_SPACING)

	for side_sign: float in side_signs:
		for slot_i: int in range(TECH_ROW_SLOTS):
			var ordered_index: int = (type_slot + slot_i) % TECH_ROW_SLOTS
			var front_offset: float = front_slots[ordered_index]
			var right_offset: float = side_sign * TECH_SIDE_OFFSET
			var slot: Vector3 = _slot_world_position(
				anchor,
				ground_y,
				frame,
				front_offset,
				right_offset
			)
			_append_unique_slot(ordered, unique, slot, existing_buildings)

		## Second column one spacing farther out if the inner column is blocked.
		for slot_i: int in range(TECH_ROW_SLOTS):
			var ordered_index: int = (type_slot + slot_i) % TECH_ROW_SLOTS
			var front_offset: float = front_slots[ordered_index]
			var right_offset: float = side_sign * (TECH_SIDE_OFFSET + TECH_SLOT_SPACING)
			var slot: Vector3 = _slot_world_position(
				anchor,
				ground_y,
				frame,
				front_offset,
				right_offset
			)
			_append_unique_slot(ordered, unique, slot, existing_buildings)


static func _tech_preferred_slot_index(building_type: StringName) -> int:
	match building_type:
		&"blacksmith", &"stable":
			return 0
		&"shop", &"academy":
			return 1
		&"hero_altar", &"artillery_depot":
			return 2
		_:
			return 0


static func _append_tower_slots(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	ground_y: float,
	frame: Dictionary,
	existing_buildings: Array[Node3D]
) -> void:
	## Outer corners / approach flanks — never courtyard center.
	## Order biased by preferred_tower_lane when set by attack-path defense.
	var tower_plan: Array[Vector2] = _tower_plan_offsets_for_lane(preferred_tower_lane)
	for offset: Vector2 in tower_plan:
		var slot: Vector3 = _slot_world_position(
			anchor,
			ground_y,
			frame,
			offset.x,
			offset.y
		)
		_append_unique_slot(ordered, unique, slot, existing_buildings)


static func _tower_plan_offsets_for_lane(lane: StringName) -> Array[Vector2]:
	var center_tip := Vector2(TOWER_FRONT_OFFSET + 2.0, 0.0)
	var left_front := Vector2(TOWER_FRONT_OFFSET, TOWER_SIDE_OFFSET)
	var right_front := Vector2(TOWER_FRONT_OFFSET, -TOWER_SIDE_OFFSET)
	var left_side := Vector2(0.0, TOWER_SIDE_OFFSET + 2.0)
	var right_side := Vector2(0.0, -(TOWER_SIDE_OFFSET + 2.0))
	var left_back := Vector2(-TOWER_BACK_OFFSET, TOWER_SIDE_OFFSET)
	var right_back := Vector2(-TOWER_BACK_OFFSET, -TOWER_SIDE_OFFSET)

	match lane:
		&"left":
			return [left_front, left_side, center_tip, left_back, right_front, right_side, right_back]
		&"right":
			return [right_front, right_side, center_tip, right_back, left_front, left_side, left_back]
		&"expansion":
			return [left_back, right_back, left_side, right_side, left_front, right_front, center_tip]
		&"harass":
			return [left_side, right_side, left_back, right_back, left_front, right_front, center_tip]
		&"center":
			return [center_tip, left_front, right_front, left_side, right_side, left_back, right_back]
		_:
			return [left_front, right_front, left_back, right_back, center_tip, left_side, right_side]


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
	prefer_expansion: bool,
	frame: Dictionary = {},
	building_type: StringName = &""
) -> Array:
	## Fallback after planned slots fail: gap-fill along rows, then expand rings.
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

	## Prefer continuing the same row pattern before free-form rings.
	if not frame.is_empty() and building_type != &"":
		var row_recovery: Array[Vector3] = _generate_planned_slots(
			anchor,
			building_type,
			footprint,
			ground_y,
			frame,
			[] ## include occupied slots as recovery probes only if clear via filters
		)
		for slot: Vector3 in row_recovery:
			_append_candidate(compact, compact_unique, slot, ground_y)
		_append_row_aligned_recovery_candidates(
			compact,
			compact_unique,
			anchor,
			footprint,
			ground_y,
			frame,
			building_type
		)

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


static func _append_row_aligned_recovery_candidates(
	ordered: Array[Vector3],
	unique: Dictionary,
	anchor: Vector3,
	footprint: Vector2,
	ground_y: float,
	frame: Dictionary,
	building_type: StringName
) -> void:
	## Shift along the row axis by one footprint step when the exact slot is blocked.
	var step: float = maxf(footprint.x, footprint.y) + BUILDING_PADDING + 0.5
	match building_type:
		&"farm":
			for row: int in range(FARM_MAX_ROWS + 1):
				var front_offset: float = -(FARM_ROW_BACK_OFFSET + float(row) * FARM_ROW_PITCH)
				for lateral_i: int in range(-FARM_ROW_SLOTS, FARM_ROW_SLOTS + 1):
					_append_candidate(
						ordered,
						unique,
						_slot_world_position(
							anchor,
							ground_y,
							frame,
							front_offset,
							float(lateral_i) * FARM_SLOT_SPACING
						),
						ground_y
					)
		&"barracks":
			for front_offset: float in [
				BARRACKS_ROW_FRONT_OFFSET,
				BARRACKS_ROW2_FRONT_OFFSET,
				BARRACKS_ROW_FRONT_OFFSET + step,
			]:
				for lateral_i: int in range(-2, 3):
					_append_candidate(
						ordered,
						unique,
						_slot_world_position(
							anchor,
							ground_y,
							frame,
							front_offset,
							float(lateral_i) * BARRACKS_SLOT_SPACING
						),
						ground_y
					)
		&"blacksmith", &"shop", &"hero_altar", &"stable", &"academy", &"artillery_depot":
			for side_sign: float in [-1.0, 1.0]:
				for slot_i: int in range(TECH_ROW_SLOTS + 2):
					_append_candidate(
						ordered,
						unique,
						_slot_world_position(
							anchor,
							ground_y,
							frame,
							-TECH_BACK_BIAS - float(slot_i) * TECH_SLOT_SPACING,
							side_sign * TECH_SIDE_OFFSET
						),
						ground_y
					)
		&"tower":
			for front_i: int in range(-1, 2):
				for side_i: int in [-1, 1]:
					_append_candidate(
						ordered,
						unique,
						_slot_world_position(
							anchor,
							ground_y,
							frame,
							TOWER_FRONT_OFFSET + float(front_i) * step,
							float(side_i) * TOWER_SIDE_OFFSET
						),
						ground_y
					)
		_:
			pass


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
	nav_from: Vector3,
	frame: Dictionary = {}
) -> String:
	if anchor.distance_squared_to(candidate) > BASE_SEARCH_RADIUS * BASE_SEARCH_RADIUS:
		return "out_of_search_radius"

	if not is_footprint_within_bounds(candidate, footprint):
		return "out_of_bounds"

	if _horizontal_distance(candidate, anchor) < _min_town_hall_clearance(footprint):
		return "blocks_town_hall_access"

	if not frame.is_empty() and _blocks_reserved_movement_lanes(
		candidate,
		footprint,
		building_type,
		anchor,
		frame
	):
		return "blocks_movement_lane"

	if not is_position_valid(candidate, building_type, existing_buildings, scene_root):
		return "overlap_or_blocked"

	if _is_too_close_to_resources(candidate, gold_mines, trees):
		return "too_close_to_resources"

	if _blocks_dropoff_path(candidate, footprint, anchor, gold_mines, tree_center):
		return "blocks_resource_route"

	if _blocks_gate_opening(candidate, footprint, existing_buildings):
		return "blocks_gate"

	## Production buildings may sit beside each other in a row; only non-production
	## (farms/towers/tech) are hard-blocked from sealing their exits.
	if not _is_production_building_type(building_type):
		if _blocks_production_exit_lane(candidate, footprint, existing_buildings):
			return "blocks_production_exit"

	var nav_to: Vector3 = Vector3(candidate.x, WORKER_NAV_TEST_Y, candidate.z)
	if not _is_nav_reachable(nav_map, nav_from, nav_to):
		return "nav_unreachable"

	return ""


static func _blocks_reserved_movement_lanes(
	candidate: Vector3,
	_footprint: Vector2,
	building_type: StringName,
	anchor: Vector3,
	frame: Dictionary
) -> bool:
	## Keep courtyard, barracks rear lane, side army passages, and retreat corridor clear.
	## Planned barracks/tower slots that intentionally sit on the defensive line are exempt
	## from the front-lane check only.
	var local: Vector2 = _local_front_right(candidate, anchor, frame)
	var front_dot: float = local.x
	var right_dot: float = local.y

	## Central courtyard around the town hall (center distance; half-extent handled by
	## `_min_town_hall_clearance` already).
	var courtyard_radius: float = (
		maxf(COMMAND_CENTER_SIZE.x, COMMAND_CENTER_SIZE.y) * 0.5 + TH_ACCESS_LANE
	)
	if Vector2(front_dot, right_dot).length() < courtyard_radius:
		return true

	var is_barracks: bool = building_type == &"barracks"
	var is_tower: bool = building_type == &"tower"

	## Lane between CC and barracks row — army + worker rally path.
	var rear_lane_min: float = courtyard_radius * 0.5
	var rear_lane_max: float = (
		BARRACKS_ROW_FRONT_OFFSET - BARRACKS_SIZE.y * 0.5 - BUILDING_PADDING
	)
	var rear_lane_half_width: float = (
		BARRACKS_SLOT_SPACING * float(BARRACKS_ROW_SLOTS - 1) * 0.5 + ARMY_LANE_HALF_WIDTH
	)
	if not is_barracks and front_dot > rear_lane_min and front_dot < rear_lane_max:
		if absf(right_dot) < rear_lane_half_width:
			return true

	## Do not place farms / tech in front of the barracks defensive line.
	var is_tech_or_farm: bool = (
		building_type == &"farm"
		or building_type == &"blacksmith"
		or building_type == &"shop"
		or building_type == &"hero_altar"
		or building_type == &"stable"
		or building_type == &"academy"
		or building_type == &"artillery_depot"
	)
	if is_tech_or_farm and front_dot > BARRACKS_ROW_FRONT_OFFSET - 1.0:
		return true

	## Front production exit strip ahead of the barracks row (units leave toward the enemy).
	if not is_barracks and not is_tower:
		var exit_min: float = BARRACKS_ROW_FRONT_OFFSET + BARRACKS_SIZE.y * 0.5 + BUILDING_PADDING
		var exit_max: float = exit_min + PRODUCTION_EXIT_LENGTH
		if front_dot > exit_min and front_dot < exit_max and absf(right_dot) < rear_lane_half_width:
			return true

	return false


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
	base_bbox: Rect2,
	frame: Dictionary = {}
) -> float:
	var score: float = 0.0
	var cand_xz := Vector2(candidate.x, candidate.z)
	var anchor_dist: float = _horizontal_distance(candidate, anchor)
	var local: Vector2 = Vector2.ZERO
	if not frame.is_empty():
		local = _local_front_right(candidate, anchor, frame)

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
			## Prefer behind/beside the barracks line, not past it toward the enemy.
			if not frame.is_empty() and local.x > BARRACKS_ROW_FRONT_OFFSET + 1.0:
				score -= (local.x - BARRACKS_ROW_FRONT_OFFSET) * 4.0
		LayoutZone.FARM:
			score -= anchor_dist * 0.2
			if not frame.is_empty():
				## Prefer map-edge / back side and edge-parallel alignment.
				if local.x < -FARM_ROW_BACK_OFFSET + 2.0:
					score += SCORE_FARM_OUTER_BONUS * 1.5
				score -= absf(local.x + FARM_ROW_BACK_OFFSET) * 0.35
			elif anchor_dist >= band.x and anchor_dist <= band.y:
				score += SCORE_FARM_OUTER_BONUS
		LayoutZone.DEFENSE:
			score -= anchor_dist * 0.25
			if not frame.is_empty():
				## Prefer outer corners over interior.
				score += minf(absf(local.x), absf(local.y)) * 0.15
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
	var frame: Dictionary = _resolve_base_frame(anchor)
	var local: Vector2 = _local_front_right(candidate, anchor, frame)

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

	## Bias toward the attack-path lane currently selected by the fortify planner.
	match preferred_tower_lane:
		&"center":
			if absf(local.y) <= 5.5 and local.x >= 6.0:
				score += SCORE_TOWER_APPROACH_BONUS * 1.1
		&"left":
			if local.y > 3.0 and local.x >= 4.0:
				score += SCORE_TOWER_APPROACH_BONUS * 1.1
		&"right":
			if local.y < -3.0 and local.x >= 4.0:
				score += SCORE_TOWER_APPROACH_BONUS * 1.1
		&"expansion":
			if local.x <= -4.0:
				score += SCORE_TOWER_APPROACH_BONUS * 1.0
		&"harass":
			if absf(local.y) >= 8.0:
				score += SCORE_TOWER_APPROACH_BONUS * 0.9
		_:
			pass

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


static func _is_production_building_type(building_type: StringName) -> bool:
	return building_type in [
		&"barracks",
		&"stable",
		&"artillery_depot",
		&"academy",
		&"command_center",
		&"hero_altar",
	]


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
		"[AI Placement] %s zone=%s source=%s candidates=%s chosen=%s rejects={%s}"
		% [
			str(info.get("building_type", "?")),
			str(info.get("zone", "?")),
			str(info.get("source", "?")),
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
