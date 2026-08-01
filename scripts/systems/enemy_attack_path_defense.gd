class_name EnemyAttackPathDefense
extends RefCounted

## Scores likely player attack lanes and picks outer defensive tower sites.
## Threat learning is throttled; placement reuses EnemyBuildPlacement geometry.

const LANE_CENTER: StringName = &"center"
const LANE_LEFT: StringName = &"left"
const LANE_RIGHT: StringName = &"right"
const LANE_EXPANSION: StringName = &"expansion"
const LANE_HARASS: StringName = &"harass"

const THREAT_UPDATE_INTERVAL_SEC: float = 1.5
const THREAT_DECAY_PER_SEC: float = 0.06
const THREAT_HIT_WEIGHT: float = 1.0
const THREAT_REPEAT_BONUS: float = 0.55
const DEFENSE_SCAN_RADIUS: float = 58.0
const PLAYER_SIDE_MARGIN: float = 4.0

const MAX_TOWERS_EARLY: int = 2
const MAX_TOWERS_MID: int = 4
const MAX_TOWERS_LATE: int = 6
const MAX_TOWERS_HARD_CAP: int = 6
const MAX_TOWERS_PER_LANE: int = 2

const MIN_TOWER_SPACING: float = 6.5
const TOWER_FIRE_RANGE: float = BuildingStats.TOWER_ATTACK_RANGE
const PATH_COVER_MAX_DIST: float = 9.0
const STRUCTURE_COVER_MAX_DIST: float = 14.0
const REDUNDANT_RANGE_OVERLAP: float = 4.0
const FAILED_SITE_COOLDOWN_SEC: float = 18.0
const REBUILD_COOLDOWN_SEC: float = 22.0
const MAX_REBUILD_ATTEMPTS: int = 2
const DESTROYED_EXPOSURE_NUDGE: float = 1.5

const REASON_EARLY_RUSH: StringName = &"early_rush"
const REASON_REPEATED_ATTACK: StringName = &"repeated_attack"
const REASON_UNCOVERED_LANE: StringName = &"uncovered_lane"
const REASON_WEAK_EXPANSION: StringName = &"weak_expansion"
const REASON_EMERGENCY: StringName = &"emergency"
const REASON_MID_DEFENSE: StringName = &"mid_defense"

static var _lane_threat: Dictionary = {
	LANE_CENTER: 0.35,
	LANE_LEFT: 0.2,
	LANE_RIGHT: 0.2,
	LANE_EXPANSION: 0.1,
	LANE_HARASS: 0.15,
}
static var _last_threat_update_msec: int = 0
static var _last_entry_lane: StringName = &""
static var _failed_sites: Dictionary = {} ## key -> expire_msec
static var _destroyed_sites: Array[Dictionary] = [] ## {pos, lane, attempts, expire_msec}
static var _last_reason: StringName = &""
static var _last_selected_lane: StringName = &""
static var _last_lane_score: float = 0.0


static func reset_match_state() -> void:
	_lane_threat = {
		LANE_CENTER: 0.35,
		LANE_LEFT: 0.2,
		LANE_RIGHT: 0.2,
		LANE_EXPANSION: 0.1,
		LANE_HARASS: 0.15,
	}
	_last_threat_update_msec = 0
	_last_entry_lane = &""
	_failed_sites.clear()
	_destroyed_sites.clear()
	_last_reason = &""
	_last_selected_lane = &""
	_last_lane_score = 0.0
	EnemyBuildPlacement.clear_tower_lane_preference()


static func get_last_reason() -> StringName:
	return _last_reason


static func get_last_selected_lane() -> StringName:
	return _last_selected_lane


static func get_last_lane_score() -> float:
	return _last_lane_score


static func get_lane_threat_snapshot() -> Dictionary:
	return _lane_threat.duplicate()


static func get_tower_cap_for_elapsed(elapsed_seconds: float) -> int:
	if elapsed_seconds < 180.0:
		return MAX_TOWERS_EARLY
	if elapsed_seconds < 600.0:
		return MAX_TOWERS_MID
	return mini(MAX_TOWERS_LATE, MAX_TOWERS_HARD_CAP)


static func get_tower_cap_for_phase_name(phase_name: String) -> int:
	match phase_name:
		"OPENING", "EARLY_ARMY", "CREEPING":
			return MAX_TOWERS_EARLY
		"TIER_2", "EXPANSION", "MID_GAME":
			return MAX_TOWERS_MID
		_:
			return mini(MAX_TOWERS_LATE, MAX_TOWERS_HARD_CAP)


static func update_threat_paths(tree: SceneTree, enemy_anchor: Vector3) -> void:
	if tree == null or not enemy_anchor.is_finite():
		return

	var now_msec: int = Time.get_ticks_msec()
	var elapsed_sec: float = 0.0
	if _last_threat_update_msec > 0:
		elapsed_sec = float(now_msec - _last_threat_update_msec) / 1000.0
		if elapsed_sec < THREAT_UPDATE_INTERVAL_SEC:
			return
	_last_threat_update_msec = now_msec
	_prune_failed_sites(now_msec)
	_prune_destroyed_sites(now_msec)

	if elapsed_sec > 0.0:
		_decay_threat(elapsed_sec)

	var player_base: Vector3 = _resolve_player_base_position(tree)
	var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(enemy_anchor)
	var entries: Array[Vector3] = _collect_player_entry_points(tree, enemy_anchor, player_base)
	if entries.is_empty():
		return

	for entry: Vector3 in entries:
		var lane: StringName = classify_approach_lane(entry, enemy_anchor, frame, tree)
		var weight: float = THREAT_HIT_WEIGHT
		if lane == _last_entry_lane:
			weight += THREAT_REPEAT_BONUS
		_lane_threat[lane] = minf(float(_lane_threat.get(lane, 0.0)) + weight, 8.0)
		_last_entry_lane = lane


static func classify_approach_lane(
	point: Vector3,
	anchor: Vector3,
	frame: Dictionary,
	tree: SceneTree = null
) -> StringName:
	var local: Vector2 = EnemyBuildPlacement.local_front_right_public(point, anchor, frame)
	var expansion_anchor: Vector3 = _resolve_expansion_anchor(tree, anchor)
	if expansion_anchor.is_finite():
		var expand_dist: float = _horizontal_distance(point, expansion_anchor)
		var main_dist: float = _horizontal_distance(point, anchor)
		if expand_dist + 4.0 < main_dist:
			return LANE_EXPANSION

	var mine: Vector3 = _resolve_nearest_enemy_mine(tree, anchor)
	if mine.is_finite():
		var mine_dist: float = _horizontal_distance(point, mine)
		if mine_dist <= 14.0 and local.x < 4.0:
			return LANE_HARASS

	if local.x < -2.0 and absf(local.y) > absf(local.x) * 0.65:
		return LANE_HARASS if absf(local.y) > 8.0 else (LANE_LEFT if local.y > 0.0 else LANE_RIGHT)

	if absf(local.y) <= 5.5:
		return LANE_CENTER
	if local.y > 0.0:
		return LANE_LEFT
	return LANE_RIGHT


static func evaluate_build_need(
	tree: SceneTree,
	enemy_anchor: Vector3,
	context: Dictionary
) -> Dictionary:
	## Returns {should_build: bool, reason: StringName, lane: StringName, score: float}
	_last_reason = &""
	_last_selected_lane = &""
	_last_lane_score = 0.0

	var tower_count: int = int(context.get("tower_count", 0))
	var tower_cap: int = int(context.get("tower_cap", MAX_TOWERS_HARD_CAP))
	if tower_count >= tower_cap or tower_count >= MAX_TOWERS_HARD_CAP:
		return _need_result(false)

	if bool(context.get("food_blocked", false)):
		return _need_result(false)
	if bool(context.get("missing_workers", false)):
		return _need_result(false)
	if bool(context.get("core_army_starved", false)) and not bool(context.get("emergency", false)):
		return _need_result(false)
	if bool(context.get("opening_core_incomplete", false)) and not bool(context.get("emergency", false)):
		return _need_result(false)

	update_threat_paths(tree, enemy_anchor)

	var best_lane: StringName = pick_best_lane(tree, enemy_anchor, context)
	var lane_score: float = score_lane(best_lane, tree, enemy_anchor, context)
	_last_selected_lane = best_lane
	_last_lane_score = lane_score

	var emergency: bool = bool(context.get("emergency", false))
	var early_aggression: bool = bool(context.get("early_aggression", false))
	var weak_army_expanding: bool = bool(context.get("weak_army_expanding", false))
	var has_production: bool = bool(context.get("has_production", false))
	var economy_ready: bool = bool(context.get("economy_ready", false))
	var expansion_exposed: bool = bool(context.get("expansion_exposed", false))
	var destroyed_lane_active: bool = _has_rebuild_candidate_for_lane(best_lane)

	if emergency:
		_last_reason = REASON_EMERGENCY
		return _need_result(true, REASON_EMERGENCY, best_lane, lane_score)

	if early_aggression and tower_count < MAX_TOWERS_EARLY:
		_last_reason = REASON_EARLY_RUSH
		return _need_result(true, REASON_EARLY_RUSH, best_lane, lane_score)

	if weak_army_expanding and tower_count < MAX_TOWERS_EARLY + 1:
		_last_reason = REASON_WEAK_EXPANSION
		return _need_result(true, REASON_WEAK_EXPANSION, best_lane, lane_score)

	if expansion_exposed and best_lane == LANE_EXPANSION:
		_last_reason = REASON_WEAK_EXPANSION
		return _need_result(true, REASON_WEAK_EXPANSION, best_lane, lane_score)

	if destroyed_lane_active and float(_lane_threat.get(best_lane, 0.0)) >= 0.8:
		_last_reason = REASON_REPEATED_ATTACK
		return _need_result(true, REASON_REPEATED_ATTACK, best_lane, lane_score)

	if float(_lane_threat.get(best_lane, 0.0)) >= 1.6 and tower_count < tower_cap:
		_last_reason = REASON_REPEATED_ATTACK
		return _need_result(true, REASON_REPEATED_ATTACK, best_lane, lane_score)

	if economy_ready and has_production and lane_score >= 1.1 and tower_count < tower_cap:
		var coverage: float = float(context.get("lane_coverage", {}).get(best_lane, 0.0))
		if coverage < 0.55:
			_last_reason = REASON_UNCOVERED_LANE
			return _need_result(true, REASON_UNCOVERED_LANE, best_lane, lane_score)
		if tower_count < maxi(1, tower_cap / 2) and lane_score >= 1.4:
			_last_reason = REASON_MID_DEFENSE
			return _need_result(true, REASON_MID_DEFENSE, best_lane, lane_score)

	return _need_result(false)


static func pick_best_lane(tree: SceneTree, enemy_anchor: Vector3, context: Dictionary) -> StringName:
	var best_lane: StringName = LANE_CENTER
	var best_score: float = -INF
	for lane: StringName in [LANE_CENTER, LANE_LEFT, LANE_RIGHT, LANE_EXPANSION, LANE_HARASS]:
		var score: float = score_lane(lane, tree, enemy_anchor, context)
		if score > best_score:
			best_score = score
			best_lane = lane
	return best_lane


static func score_lane(
	lane: StringName,
	tree: SceneTree,
	enemy_anchor: Vector3,
	context: Dictionary
) -> float:
	var score: float = float(_lane_threat.get(lane, 0.0))

	## Baseline approach likelihood from map geometry.
	match lane:
		LANE_CENTER:
			score += 0.55
		LANE_LEFT, LANE_RIGHT:
			score += 0.35
		LANE_HARASS:
			score += 0.25
		LANE_EXPANSION:
			if bool(context.get("has_expansion", false)):
				score += 0.45
			else:
				score -= 0.35

	var coverage: float = float(context.get("lane_coverage", {}).get(lane, 0.0))
	score -= coverage * 1.2

	var towers_on_lane: int = int(context.get("towers_per_lane", {}).get(lane, 0))
	if towers_on_lane >= MAX_TOWERS_PER_LANE:
		score -= 2.5

	## Prefer lanes that expose workers / production / town hall.
	if lane == LANE_HARASS and bool(context.get("workers_exposed", true)):
		score += 0.35
	if lane in [LANE_CENTER, LANE_LEFT, LANE_RIGHT] and bool(context.get("has_production", false)):
		score += 0.2
	if bool(context.get("expansion_exposed", false)) and lane == LANE_EXPANSION:
		score += 0.7

	## Gentle pull toward player-base / map-center approach.
	var player_base: Vector3 = _resolve_player_base_position(tree)
	if player_base.is_finite():
		var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(enemy_anchor)
		var player_lane: StringName = classify_approach_lane(player_base, enemy_anchor, frame, tree)
		if player_lane == lane:
			score += 0.4

	return score


static func find_tower_position(
	anchor: Vector3,
	lane: StringName,
	existing_buildings: Array[Node3D],
	scene_root: Node,
	nav_map: RID = RID()
) -> Dictionary:
	## Returns {position: Vector3, lane: StringName, score: float, reject: StringName}
	EnemyBuildPlacement.set_tower_lane_preference(lane)

	var rebuild: Dictionary = _take_rebuild_candidate(lane, anchor)
	if not rebuild.is_empty():
		var rebuild_pos: Vector3 = rebuild.get("pos", Vector3.INF)
		if rebuild_pos.is_finite():
			var nudged: Vector3 = _nudge_exposed_position(rebuild_pos, anchor, lane)
			var rebuild_check: StringName = validate_tower_candidate(
				nudged,
				anchor,
				lane,
				existing_buildings,
				scene_root,
				nav_map
			)
			if rebuild_check == &"":
				return {
					"position": nudged,
					"lane": lane,
					"score": float(_lane_threat.get(lane, 0.0)) + 1.0,
					"reject": &"",
					"rebuild": true,
				}
			_log_reject(rebuild_check)

	var planned: Array[Vector3] = EnemyBuildPlacement.get_tower_slots_for_lane(
		anchor,
		lane,
		existing_buildings
	)
	var best_pos: Vector3 = Vector3.INF
	var best_score: float = -INF
	var last_reject: StringName = &"blocked"

	for candidate: Vector3 in planned:
		if _is_failed_site(candidate):
			last_reject = &"blocked"
			continue

		var reject: StringName = validate_tower_candidate(
			candidate,
			anchor,
			lane,
			existing_buildings,
			scene_root,
			nav_map
		)
		if reject != &"":
			last_reject = reject
			if reject == &"blocked" or reject == &"path_conflict":
				remember_failed_site(candidate)
			continue

		var cand_score: float = _score_candidate_for_lane(candidate, anchor, lane, existing_buildings)
		if cand_score > best_score:
			best_score = cand_score
			best_pos = candidate

	if best_pos.is_finite():
		return {
			"position": best_pos,
			"lane": lane,
			"score": best_score,
			"reject": &"",
			"rebuild": false,
		}

	## Fallback: general placement search biased by lane preference.
	var fallback: Vector3 = EnemyBuildPlacement.find_position(
		anchor,
		&"tower",
		existing_buildings,
		false,
		scene_root,
		nav_map
	)
	if fallback.is_finite() and not _is_failed_site(fallback):
		var fallback_reject: StringName = validate_tower_candidate(
			fallback,
			anchor,
			lane,
			existing_buildings,
			scene_root,
			nav_map
		)
		if fallback_reject == &"":
			return {
				"position": fallback,
				"lane": lane,
				"score": _score_candidate_for_lane(fallback, anchor, lane, existing_buildings),
				"reject": &"",
				"rebuild": false,
			}
		last_reject = fallback_reject

	_log_reject(last_reject)
	return {
		"position": Vector3.INF,
		"lane": lane,
		"score": 0.0,
		"reject": last_reject,
		"rebuild": false,
	}


static func validate_tower_candidate(
	candidate: Vector3,
	anchor: Vector3,
	lane: StringName,
	existing_buildings: Array[Node3D],
	scene_root: Node,
	nav_map: RID = RID()
) -> StringName:
	if not candidate.is_finite():
		return &"blocked"

	var towers: Array[Node3D] = _collect_towers(existing_buildings)
	for tower: Node3D in towers:
		if _horizontal_distance(candidate, tower.global_position) < MIN_TOWER_SPACING:
			return &"redundant"

	if not EnemyBuildPlacement.is_position_valid(
		candidate,
		&"tower",
		existing_buildings,
		scene_root
	):
		return &"blocked"

	if EnemyBuildPlacement.tower_blocks_reserved_lanes(candidate, existing_buildings):
		return &"path_conflict"

	## Reject deep courtyard placements that only fire after TH is already hit.
	var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(anchor)
	var local: Vector2 = EnemyBuildPlacement.local_front_right_public(candidate, anchor, frame)
	if local.x < 3.5 and absf(local.y) < 5.0:
		return &"unsafe"

	## Must cover approach or a valuable structure.
	var path_point: Vector3 = _lane_approach_point(anchor, lane, frame)
	var dist_path: float = _horizontal_distance(candidate, path_point)
	var dist_anchor: float = _horizontal_distance(candidate, anchor)
	var near_structure: bool = dist_anchor <= STRUCTURE_COVER_MAX_DIST
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building):
			continue
		if building is Farm:
			continue
		if _horizontal_distance(candidate, building.global_position) <= STRUCTURE_COVER_MAX_DIST:
			near_structure = true
			break

	if dist_path > PATH_COVER_MAX_DIST + 4.0 and not near_structure:
		return &"unsafe"

	## Redundant overlapping coverage on the same lane tip.
	var overlapping: int = 0
	for tower: Node3D in towers:
		var tower_local: Vector2 = EnemyBuildPlacement.local_front_right_public(
			tower.global_position,
			anchor,
			frame
		)
		var same_lane: bool = _local_matches_lane(tower_local, lane)
		if (
			same_lane
			and _horizontal_distance(candidate, tower.global_position)
			<= TOWER_FIRE_RANGE - REDUNDANT_RANGE_OVERLAP
		):
			overlapping += 1
	if overlapping >= MAX_TOWERS_PER_LANE:
		return &"redundant"

	if nav_map.is_valid() and not EnemyBuildPlacement.is_builder_reachable(
		anchor,
		candidate,
		nav_map
	):
		return &"blocked"

	return &""


static func remember_failed_site(position: Vector3) -> void:
	if not position.is_finite():
		return
	var key: String = _site_key(position)
	_failed_sites[key] = Time.get_ticks_msec() + int(FAILED_SITE_COOLDOWN_SEC * 1000.0)


static func notify_tower_destroyed(position: Vector3, lane: StringName = &"") -> void:
	if not position.is_finite():
		return
	var resolved_lane: StringName = lane
	if resolved_lane == &"":
		resolved_lane = _last_selected_lane if _last_selected_lane != &"" else LANE_CENTER

	## Destruction itself is evidence the lane mattered — raise threat first.
	_lane_threat[resolved_lane] = minf(float(_lane_threat.get(resolved_lane, 0.0)) + 0.8, 8.0)

	## Skip endless rebuild if the lane is still not worth fortifying.
	if float(_lane_threat.get(resolved_lane, 0.0)) < 0.55:
		_debug_log("AI tower rebuild skipped: lane no longer threatened")
		return

	var attempts: int = 0
	for entry: Dictionary in _destroyed_sites:
		var pos: Vector3 = entry.get("pos", Vector3.INF)
		if pos.is_finite() and _horizontal_distance(pos, position) <= 2.5:
			attempts = int(entry.get("attempts", 0))
			break

	if attempts >= MAX_REBUILD_ATTEMPTS:
		_debug_log("AI tower rebuild skipped: lane no longer threatened")
		return

	_destroyed_sites.append({
		"pos": position,
		"lane": resolved_lane,
		"attempts": attempts + 1,
		"expire_msec": Time.get_ticks_msec() + int(REBUILD_COOLDOWN_SEC * 1000.0),
	})


static func compute_lane_coverage(
	anchor: Vector3,
	existing_buildings: Array[Node3D]
) -> Dictionary:
	var coverage: Dictionary = {
		LANE_CENTER: 0.0,
		LANE_LEFT: 0.0,
		LANE_RIGHT: 0.0,
		LANE_EXPANSION: 0.0,
		LANE_HARASS: 0.0,
	}
	var towers_per_lane: Dictionary = {
		LANE_CENTER: 0,
		LANE_LEFT: 0,
		LANE_RIGHT: 0,
		LANE_EXPANSION: 0,
		LANE_HARASS: 0,
	}
	var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(anchor)
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building) or not (building is Tower):
			continue
		var local: Vector2 = EnemyBuildPlacement.local_front_right_public(
			building.global_position,
			anchor,
			frame
		)
		var lane: StringName = _lane_from_local(local)
		towers_per_lane[lane] = int(towers_per_lane.get(lane, 0)) + 1
		var approach: Vector3 = _lane_approach_point(anchor, lane, frame)
		var dist: float = _horizontal_distance(building.global_position, approach)
		var amount: float = clampf(1.0 - dist / (TOWER_FIRE_RANGE + 2.0), 0.0, 1.0)
		coverage[lane] = minf(float(coverage.get(lane, 0.0)) + amount, 1.5)
	return {"coverage": coverage, "towers_per_lane": towers_per_lane}


static func reason_to_debug_text(reason: StringName) -> String:
	match reason:
		REASON_EARLY_RUSH:
			return "early rush"
		REASON_REPEATED_ATTACK:
			return "repeated attack"
		REASON_UNCOVERED_LANE:
			return "uncovered lane"
		REASON_WEAK_EXPANSION:
			return "weak expansion"
		REASON_EMERGENCY:
			return "emergency"
		REASON_MID_DEFENSE:
			return "mid defense"
		_:
			return String(reason)


static func _need_result(
	should_build: bool,
	reason: StringName = &"",
	lane: StringName = &"",
	score: float = 0.0
) -> Dictionary:
	return {
		"should_build": should_build,
		"reason": reason,
		"lane": lane,
		"score": score,
	}


static func _decay_threat(elapsed_sec: float) -> void:
	var decay: float = THREAT_DECAY_PER_SEC * elapsed_sec
	for lane: Variant in _lane_threat.keys():
		_lane_threat[lane] = maxf(float(_lane_threat[lane]) - decay, 0.0)


static func _collect_player_entry_points(
	tree: SceneTree,
	enemy_anchor: Vector3,
	player_base: Vector3
) -> Array[Vector3]:
	var entries: Array[Vector3] = []
	if tree == null:
		return entries

	var search_range_sq: float = DEFENSE_SCAN_RADIUS * DEFENSE_SCAN_RADIUS
	for group_name: StringName in [&"units", &"heroes"]:
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if node_variant == null or not is_instance_valid(node_variant):
				continue
			if not node_variant is Node3D:
				continue
			var unit := node_variant as Node3D
			if unit is Worker:
				continue
			if not ("team_id" in unit) or int(unit.get("team_id")) != 0:
				continue
			if unit is Building:
				continue
			if horizontal_distance_squared_to(enemy_anchor, unit.global_position) > search_range_sq:
				continue
			var pos: Vector3 = unit.global_position
			if player_base.is_finite():
				var to_enemy: float = _horizontal_distance(pos, enemy_anchor)
				var to_player: float = _horizontal_distance(pos, player_base)
				if to_enemy + PLAYER_SIDE_MARGIN >= to_player and to_enemy > 28.0:
					continue
			entries.append(pos)

	return entries


static func horizontal_distance_squared_to(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return dx * dx + dz * dz


static func _resolve_player_base_position(tree: SceneTree) -> Vector3:
	if tree == null:
		return Vector3.INF
	for node: Node in tree.get_nodes_in_group(&"player_command_center"):
		if node is Node3D and is_instance_valid(node):
			return (node as Node3D).global_position
	return Vector3.INF


static func _resolve_expansion_anchor(tree: SceneTree, main_anchor: Vector3) -> Vector3:
	if tree == null:
		return Vector3.INF
	var best: Vector3 = Vector3.INF
	var best_dist: float = -1.0
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if not (node is CommandCenter) or not is_instance_valid(node):
			continue
		var cc := node as CommandCenter
		if cc.team_id != 1:
			continue
		var dist: float = _horizontal_distance(cc.global_position, main_anchor)
		if dist > 12.0 and dist > best_dist:
			best_dist = dist
			best = cc.global_position
	return best


static func _resolve_nearest_enemy_mine(tree: SceneTree, anchor: Vector3) -> Vector3:
	if tree == null:
		return Vector3.INF
	var best: Vector3 = Vector3.INF
	var best_dist: float = INF
	var root: Node = tree.get_root()
	if root == null:
		return Vector3.INF
	for child: Node in WorkerGathering._map_resource_children(root):
		if child == null or not is_instance_valid(child) or not child is GoldMine:
			continue
		var dist: float = _horizontal_distance((child as Node3D).global_position, anchor)
		if dist < best_dist:
			best_dist = dist
			best = (child as Node3D).global_position
	return best


static func _lane_approach_point(anchor: Vector3, lane: StringName, frame: Dictionary) -> Vector3:
	var front: Vector2 = frame.get("front", Vector2(-1.0, 0.0))
	var right: Vector2 = frame.get("right", Vector2(0.0, 1.0))
	var front_off: float = EnemyBuildPlacement.TOWER_FRONT_OFFSET
	var side_off: float = 0.0
	match lane:
		LANE_LEFT:
			side_off = EnemyBuildPlacement.TOWER_SIDE_OFFSET
		LANE_RIGHT:
			side_off = -EnemyBuildPlacement.TOWER_SIDE_OFFSET
		LANE_HARASS:
			front_off = 2.0
			side_off = EnemyBuildPlacement.TOWER_SIDE_OFFSET + 2.0
		LANE_EXPANSION:
			front_off = -EnemyBuildPlacement.TOWER_BACK_OFFSET
			side_off = EnemyBuildPlacement.TOWER_SIDE_OFFSET
		_:
			front_off = EnemyBuildPlacement.TOWER_FRONT_OFFSET + 2.0
			side_off = 0.0
	return Vector3(
		anchor.x + front.x * front_off + right.x * side_off,
		EnemyBuildPlacement.TOWER_GROUND_Y,
		anchor.z + front.y * front_off + right.y * side_off
	)


static func _lane_from_local(local: Vector2) -> StringName:
	if local.x < -2.0:
		return LANE_EXPANSION if absf(local.y) > 4.0 else LANE_HARASS
	if absf(local.y) <= 5.5:
		return LANE_CENTER
	return LANE_LEFT if local.y > 0.0 else LANE_RIGHT


static func _local_matches_lane(local: Vector2, lane: StringName) -> bool:
	return _lane_from_local(local) == lane


static func _score_candidate_for_lane(
	candidate: Vector3,
	anchor: Vector3,
	lane: StringName,
	existing_buildings: Array[Node3D]
) -> float:
	var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(anchor)
	var approach: Vector3 = _lane_approach_point(anchor, lane, frame)
	var score: float = 4.0 - _horizontal_distance(candidate, approach) * 0.35
	score += float(_lane_threat.get(lane, 0.0)) * 0.5

	## Prefer slight overlap with an existing tower without stacking.
	for building: Node3D in existing_buildings:
		if building == null or not is_instance_valid(building) or not (building is Tower):
			continue
		var dist: float = _horizontal_distance(candidate, building.global_position)
		if dist >= MIN_TOWER_SPACING and dist <= TOWER_FIRE_RANGE * 1.35:
			score += 0.8
		elif dist < MIN_TOWER_SPACING:
			score -= 3.0

	## Keep some distance from town hall interior.
	var local: Vector2 = EnemyBuildPlacement.local_front_right_public(candidate, anchor, frame)
	if local.x >= 8.0:
		score += 0.6
	return score


static func _collect_towers(existing_buildings: Array[Node3D]) -> Array[Node3D]:
	var towers: Array[Node3D] = []
	for building: Node3D in existing_buildings:
		if building != null and is_instance_valid(building) and building is Tower:
			towers.append(building)
	return towers


static func _nudge_exposed_position(pos: Vector3, anchor: Vector3, lane: StringName) -> Vector3:
	var frame: Dictionary = EnemyBuildPlacement.resolve_base_frame_public(anchor)
	var front: Vector2 = frame.get("front", Vector2(-1.0, 0.0))
	## Pull slightly toward base so rebuild is less exposed.
	var nudged := Vector3(
		pos.x - front.x * DESTROYED_EXPOSURE_NUDGE,
		EnemyBuildPlacement.TOWER_GROUND_Y,
		pos.z - front.y * DESTROYED_EXPOSURE_NUDGE
	)
	return EnemyBuildPlacement.snap_to_grid(nudged)


static func _take_rebuild_candidate(lane: StringName, anchor: Vector3) -> Dictionary:
	var now_msec: int = Time.get_ticks_msec()
	for i: int in range(_destroyed_sites.size() - 1, -1, -1):
		var entry: Dictionary = _destroyed_sites[i]
		if int(entry.get("expire_msec", 0)) < now_msec:
			_destroyed_sites.remove_at(i)
			continue
		if entry.get("lane", &"") != lane:
			continue
		var pos: Vector3 = entry.get("pos", Vector3.INF)
		if not pos.is_finite():
			continue
		if _horizontal_distance(pos, anchor) > 40.0:
			continue
		_destroyed_sites.remove_at(i)
		return entry
	return {}


static func _has_rebuild_candidate_for_lane(lane: StringName) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	for entry: Dictionary in _destroyed_sites:
		if int(entry.get("expire_msec", 0)) < now_msec:
			continue
		if entry.get("lane", &"") == lane:
			return true
	return false


static func _is_failed_site(position: Vector3) -> bool:
	_prune_failed_sites(Time.get_ticks_msec())
	return _failed_sites.has(_site_key(position))


static func _prune_failed_sites(now_msec: int) -> void:
	var stale: Array[String] = []
	for key: Variant in _failed_sites.keys():
		if int(_failed_sites[key]) < now_msec:
			stale.append(String(key))
	for key: String in stale:
		_failed_sites.erase(key)


static func _prune_destroyed_sites(now_msec: int) -> void:
	for i: int in range(_destroyed_sites.size() - 1, -1, -1):
		if int(_destroyed_sites[i].get("expire_msec", 0)) < now_msec:
			_destroyed_sites.remove_at(i)


static func _site_key(position: Vector3) -> String:
	return "%d:%d" % [int(round(position.x)), int(round(position.z))]


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


static func _log_reject(reason: StringName) -> void:
	if reason == &"":
		return
	var text: String = String(reason).replace("_", " ")
	_debug_log("AI tower candidate rejected: %s" % text)


static func _debug_log(message: String) -> void:
	if not OS.is_debug_build():
		return
	if EnemyAIDebug.is_enabled():
		EnemyAIDebug.log_event(message)
	elif OS.is_debug_build():
		## Keep quiet unless AI debug is on; placement verify can enable it.
		pass
