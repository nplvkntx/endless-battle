class_name WorkerAiUnstuck
extends RefCounted

## Three-stage physical unstuck recovery for enemy workers blocked near buildings.

const DEBUG_AI_WORKER_UNSTUCK: bool = false

static var _reserved_escape_points: Array[Dictionary] = []


static func is_active(worker: Worker) -> bool:
	return worker._ai_unstuck_active


static func blocks_external_commands(worker: Worker) -> bool:
	return worker._ai_unstuck_active or worker._ai_unstuck_pending_stagger > 0.0


static func clear_unstuck_state(worker: Worker) -> void:
	_release_escape_reservation(worker)
	worker._ai_unstuck_active = false
	worker._ai_unstuck_target = Vector3.ZERO
	worker._ai_unstuck_time = 0.0
	worker._ai_unstuck_direction_offset = 0
	worker._ai_unstuck_attempt_number = 0
	worker._ai_unstuck_pending_stagger = 0.0
	worker._ai_unstuck_stuck_location = Vector3.ZERO
	worker._ai_unstuck_internal_move = false
	worker._ai_unstuck_saved_gather_state = Worker.GatherTripState.IDLE
	worker._ai_unstuck_saved_build_state = Worker.BuildTripState.IDLE
	reset_watch(worker)


static func reset_watch(worker: Worker) -> void:
	worker._ai_unstuck_watch_position = worker.global_position
	worker._ai_unstuck_watch_time = 0.0


static func update_detection(worker: Worker, delta: float) -> void:
	if not NodeSafety.is_alive_node(worker) or not worker.is_inside_tree():
		return

	_prune_reserved_escape_points()

	if worker._ai_unstuck_cooldown > 0.0:
		worker._ai_unstuck_cooldown = maxf(0.0, worker._ai_unstuck_cooldown - delta)

	if worker._ai_unstuck_active:
		return

	if worker._ai_unstuck_pending_stagger > 0.0:
		worker._ai_unstuck_pending_stagger = maxf(0.0, worker._ai_unstuck_pending_stagger - delta)
		if worker._ai_unstuck_pending_stagger > 0.0:
			return
		_begin_unstuck(worker)
		return

	if not _is_eligible_for_detection(worker):
		reset_watch(worker)
		return

	if not worker.has_move_target and not worker._task_has_saved_destination:
		reset_watch(worker)
		return

	var moved: Vector3 = worker.global_position - worker._ai_unstuck_watch_position
	moved.y = 0.0
	if moved.length() >= GatheringConfig.AI_UNSTUCK_MIN_MOVE_DISTANCE:
		reset_watch(worker)
		worker._ai_unstuck_attempt_number = 0
		worker._ai_unstuck_direction_offset = 0
		return

	worker._ai_unstuck_watch_time += delta
	if worker._ai_unstuck_watch_time < GatheringConfig.AI_UNSTUCK_STUCK_DELAY:
		return

	if worker._ai_unstuck_cooldown > 0.0:
		return

	_queue_unstuck(worker)


static func process_movement(worker: Worker, delta: float) -> void:
	if not NodeSafety.is_alive_node(worker) or not worker.is_inside_tree():
		return

	worker._ai_unstuck_time += delta

	var arrived: bool = WorkerTaskNavigation.process_direct_movement(
		worker,
		worker._ai_unstuck_target,
		worker.move_speed,
		worker.stopping_distance
	)
	var timed_out: bool = (
		worker._ai_unstuck_time >= GatheringConfig.AI_UNSTUCK_NUDGE_MAX_TIME
	)
	var cleared_blockage: bool = _has_cleared_blockage(worker)

	if arrived or timed_out or cleared_blockage:
		_finish_unstuck(worker)


static func _queue_unstuck(worker: Worker) -> void:
	worker._ai_unstuck_stuck_location = worker.global_position
	worker._ai_unstuck_attempt_number += 1

	var repeat_at_same_spot: bool = (
		worker._ai_unstuck_last_stuck_location.distance_squared_to(worker.global_position)
		<= GatheringConfig.AI_UNSTUCK_REPEAT_LOCATION_RADIUS
		* GatheringConfig.AI_UNSTUCK_REPEAT_LOCATION_RADIUS
	)
	if repeat_at_same_spot:
		worker._ai_unstuck_direction_offset += 1
	else:
		worker._ai_unstuck_last_stuck_location = worker.global_position

	_save_task_snapshot(worker)

	var stagger: float = _compute_stagger_delay(worker)
	if stagger > 0.0:
		worker._ai_unstuck_pending_stagger = stagger
		worker._ai_unstuck_cooldown = GatheringConfig.AI_UNSTUCK_COOLDOWN * 0.25
		reset_watch(worker)
		return

	_begin_unstuck(worker)


static func _begin_unstuck(worker: Worker) -> void:
	var nudge_target: Vector3 = _pick_escape_target(worker)
	if nudge_target == Vector3.ZERO:
		worker._ai_unstuck_direction_offset += 1
		worker._ai_unstuck_cooldown = GatheringConfig.AI_UNSTUCK_COOLDOWN
		reset_watch(worker)
		return

	worker._disable_task_navigation()
	worker.has_move_target = false
	worker._ai_unstuck_target = nudge_target
	worker._ai_unstuck_active = true
	worker._ai_unstuck_time = 0.0
	worker._ai_unstuck_cooldown = GatheringConfig.AI_UNSTUCK_COOLDOWN
	worker._ai_unstuck_direction_offset += 1
	worker.velocity = Vector3.ZERO
	_reserve_escape_point(worker, nudge_target)

	_log_unstuck(worker, &"blocked", nudge_target)
	reset_watch(worker)


static func _finish_unstuck(worker: Worker) -> void:
	_release_escape_reservation(worker)
	worker._ai_unstuck_active = false
	worker._ai_unstuck_time = 0.0
	worker._ai_unstuck_last_finish_time = (
		float(Time.get_ticks_msec()) / 1000.0
	)
	worker.velocity = Vector3.ZERO
	_resume_task_once(worker)


static func _save_task_snapshot(worker: Worker) -> void:
	worker._ai_unstuck_saved_gather_state = worker._gather_state
	worker._ai_unstuck_saved_build_state = worker._build_trip_state
	worker._ai_unstuck_saved_source_index = worker._source_approach_candidate_index
	worker._ai_unstuck_saved_dropoff_index = worker._dropoff_candidate_index
	worker._ai_unstuck_saved_build_index = worker._build_approach_candidate_index


static func _resume_task_once(worker: Worker) -> void:
	if worker._build_trip_state == Worker.BuildTripState.TO_BUILDING:
		if (
			worker._ai_unstuck_saved_build_state != Worker.BuildTripState.TO_BUILDING
			or worker._building_target == null
			or not is_instance_valid(worker._building_target)
		):
			return

		worker._build_approach_candidate_index = worker._ai_unstuck_saved_build_index + 1
		worker._assign_construction_target_point(false)
		_issue_internal_move(worker, worker._construction_target_point)
		return

	match worker._gather_state:
		Worker.GatherTripState.TO_SOURCE:
			if worker._ai_unstuck_saved_gather_state != Worker.GatherTripState.TO_SOURCE:
				return
			if not worker._has_valid_gather_source():
				return

			if worker._is_gathering_wood() and worker._wood_chop_spot_valid:
				_issue_internal_move(worker, worker._wood_chop_spot)
			else:
				worker._source_approach_candidate_index = (
					worker._ai_unstuck_saved_source_index + 1
				)
				var source: GatherableResource = worker._get_valid_gather_source()
				_issue_internal_move(
					worker,
					worker._compute_resource_approach_position_for_candidate(
						source, worker._source_approach_candidate_index
					)
				)
		Worker.GatherTripState.TO_COMMAND_CENTER:
			if worker._ai_unstuck_saved_gather_state != Worker.GatherTripState.TO_COMMAND_CENTER:
				return
			if worker._carried_amount <= 0:
				return
			var dropoff: CommandCenter = worker._get_valid_cached_return_dropoff()
			if dropoff == null:
				dropoff = worker._resolve_dropoff_target()
			if dropoff != null:
				worker._dropoff_candidate_index = worker._ai_unstuck_saved_dropoff_index + 1
				_issue_internal_move(
					worker,
					worker._compute_command_center_dropoff_position(dropoff)
				)


static func _issue_internal_move(worker: Worker, target: Vector3) -> void:
	worker._ai_unstuck_internal_move = true
	worker.set_movement_target(target)
	worker._ai_unstuck_internal_move = false


static func _is_eligible_for_detection(worker: Worker) -> bool:
	if worker._gather_state == Worker.GatherTripState.GATHER_WAIT:
		return false

	if worker._build_trip_state == Worker.BuildTripState.CONSTRUCTION_WAIT:
		return false

	if worker._task_nudge_active:
		return false

	if not worker._is_on_task_movement():
		return false

	if worker._gather_state == Worker.GatherTripState.TO_COMMAND_CENTER:
		if worker._carried_amount <= 0:
			return false
		var dropoff: CommandCenter = worker._get_valid_cached_return_dropoff()
		if dropoff == null:
			dropoff = worker._resolve_dropoff_target()
		if dropoff != null and worker._is_near_command_center_for_deposit(dropoff, true):
			return false

	if worker._gather_state == Worker.GatherTripState.TO_SOURCE:
		var source: GatherableResource = worker._get_valid_gather_source()
		if source != null and worker._is_near_resource_for_gather(source):
			return false

	if worker._build_trip_state == Worker.BuildTripState.TO_BUILDING:
		if worker._is_in_build_start_range():
			return false

	return true


static func _has_cleared_blockage(worker: Worker) -> bool:
	if worker._ai_unstuck_stuck_location == Vector3.ZERO:
		return false

	var offset: Vector3 = worker.global_position - worker._ai_unstuck_stuck_location
	offset.y = 0.0
	return offset.length() >= GatheringConfig.AI_UNSTUCK_CLEARANCE_DISTANCE


static func _compute_stagger_delay(worker: Worker) -> float:
	var nearby_count: int = _count_nearby_stuck_workers(worker)
	if nearby_count <= 0:
		return 0.0

	var worker_seed: int = absi(worker.get_instance_id())
	var base_delay: float = float(nearby_count) * GatheringConfig.AI_UNSTUCK_STAGGER_STEP
	var jitter: float = float(worker_seed % 7) * 0.04
	return clampf(
		base_delay + jitter,
		0.0,
		GatheringConfig.AI_UNSTUCK_STAGGER_MAX_DELAY
	)


static func _count_nearby_stuck_workers(worker: Worker) -> int:
	var count: int = 0
	var radius_sq: float = GatheringConfig.AI_UNSTUCK_CLUSTER_RADIUS
	radius_sq *= radius_sq

	for node: Node in worker.get_tree().get_nodes_in_group(&"enemy_workers"):
		if node == worker or not node is Worker:
			continue

		var other: Worker = node as Worker
		if not NodeSafety.is_alive_node(other):
			continue

		var offset: Vector3 = other.global_position - worker.global_position
		offset.y = 0.0
		if offset.length_squared() > radius_sq:
			continue

		if other._ai_unstuck_watch_time >= GatheringConfig.AI_UNSTUCK_STUCK_DELAY * 0.5:
			count += 1
		elif other._ai_unstuck_active or other._ai_unstuck_pending_stagger > 0.0:
			count += 1

	return count


static func _pick_escape_target(worker: Worker) -> Vector3:
	var nearest_building: Building = _find_nearest_blocking_building(worker)
	var obstacle_center: Vector3 = _get_obstacle_center(worker, nearest_building)
	var away_from_building: Vector3 = _direction_away_from_point(
		worker.global_position, obstacle_center
	)

	var intended_dir: Vector3 = _get_intended_movement_direction(worker)
	if intended_dir.length_squared() < 0.01:
		intended_dir = away_from_building

	var away_from_cluster: Vector3 = _direction_away_from_worker_cluster(worker)
	var candidates: Array[Vector3] = _build_escape_directions(
		away_from_building, intended_dir, away_from_cluster
	)

	var distance_scale: float = 1.0
	if (
		worker._ai_unstuck_last_stuck_location.distance_squared_to(worker.global_position)
		<= GatheringConfig.AI_UNSTUCK_REPEAT_LOCATION_RADIUS
		* GatheringConfig.AI_UNSTUCK_REPEAT_LOCATION_RADIUS
	):
		distance_scale = pow(
			GatheringConfig.AI_UNSTUCK_DISTANCE_REPEAT_SCALE,
			float(worker._ai_unstuck_attempt_number - 1)
		)

	var worker_seed: int = absi(worker.get_instance_id())
	var direction_count: int = candidates.size()
	var start_index: int = (
		worker_seed + worker._ai_unstuck_direction_offset
	) % maxi(direction_count, 1)

	var best_target: Vector3 = Vector3.ZERO
	var best_score: float = -INF

	for attempt: int in direction_count:
		var direction: Vector3 = candidates[(start_index + attempt) % direction_count]
		if direction.length_squared() < 0.001:
			continue

		var distance: float = lerpf(
			GatheringConfig.AI_UNSTUCK_DISTANCE_MIN,
			GatheringConfig.AI_UNSTUCK_DISTANCE_MAX,
			float((attempt + worker_seed % 3) % 3) / 2.0
		)
		distance *= distance_scale
		distance += float(worker_seed % 5) * 0.1

		var probe: Vector3 = worker.global_position + direction.normalized() * distance
		probe.y = worker.global_position.y

		var snapped: Vector3 = worker._snap_task_target_to_navigation(probe)
		snapped = GroupMoveSpacing.resolve_nearby_walkable_position(
			snapped, worker, worker.global_position, GatheringConfig.AI_UNSTUCK_ESCAPE_RESERVE_RADIUS
		)

		if not _is_valid_escape_point(worker, snapped, nearest_building, obstacle_center):
			continue

		var score: float = _score_escape_candidate(
			worker, snapped, direction, away_from_building, obstacle_center, nearest_building
		)
		if score > best_score:
			best_score = score
			best_target = snapped

	return best_target


static func _build_escape_directions(
	away_from_building: Vector3,
	intended_dir: Vector3,
	away_from_cluster: Vector3
) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	_add_unique_direction(directions, away_from_building)
	_add_unique_direction(directions, intended_dir.rotated(Vector3.UP, PI * 0.5))
	_add_unique_direction(directions, intended_dir.rotated(Vector3.UP, -PI * 0.5))
	_add_unique_direction(directions, away_from_building.rotated(Vector3.UP, PI * 0.25))
	_add_unique_direction(directions, away_from_building.rotated(Vector3.UP, -PI * 0.25))
	_add_unique_direction(directions, away_from_cluster)

	var direction_count: int = GatheringConfig.AI_UNSTUCK_DIRECTION_COUNT
	for index: int in direction_count:
		var angle: float = TAU * float(index) / float(direction_count)
		_add_unique_direction(directions, away_from_building.rotated(Vector3.UP, angle))

	return directions


static func _add_unique_direction(directions: Array[Vector3], direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return

	direction = direction.normalized()
	for existing: Vector3 in directions:
		if existing.dot(direction) > 0.92:
			return

	directions.append(direction)


static func _direction_away_from_point(from: Vector3, center: Vector3) -> Vector3:
	var away: Vector3 = from - center
	away.y = 0.0
	if away.length_squared() < 0.01:
		return Vector3.FORWARD
	return away.normalized()


static func _get_intended_movement_direction(worker: Worker) -> Vector3:
	var destination: Vector3 = Vector3.ZERO
	if worker._task_has_saved_destination:
		destination = worker._task_movement_destination
	elif worker.has_move_target:
		destination = worker._movement_target

	var offset: Vector3 = destination - worker.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		return Vector3.ZERO
	return offset.normalized()


static func _direction_away_from_worker_cluster(worker: Worker) -> Vector3:
	var centroid: Vector3 = Vector3.ZERO
	var count: int = 0
	var radius_sq: float = GatheringConfig.AI_UNSTUCK_CLUSTER_RADIUS
	radius_sq *= radius_sq

	for node: Node in worker.get_tree().get_nodes_in_group(&"enemy_workers"):
		if node == worker or not node is Worker:
			continue

		var other: Worker = node as Worker
		if not NodeSafety.is_alive_node(other):
			continue

		var offset: Vector3 = other.global_position - worker.global_position
		offset.y = 0.0
		if offset.length_squared() > radius_sq:
			continue

		centroid += other.global_position
		count += 1

	if count == 0:
		return Vector3.ZERO

	centroid /= float(count)
	return _direction_away_from_point(worker.global_position, centroid)


static func _find_nearest_blocking_building(worker: Worker) -> Building:
	var nearest_building: Building = null
	var nearest_distance_sq: float = INF
	var search_radius: float = GatheringConfig.AI_UNSTUCK_BUILDING_SEARCH_RADIUS
	var search_radius_sq: float = search_radius * search_radius

	for index: int in worker.get_slide_collision_count():
		var collision: KinematicCollision3D = worker.get_slide_collision(index)
		var collider: Object = collision.get_collider()
		if collider is Building:
			var building: Building = collider as Building
			var distance_sq: float = worker.global_position.distance_squared_to(
				building.global_position
			)
			if distance_sq < nearest_distance_sq:
				nearest_distance_sq = distance_sq
				nearest_building = building

	for node: Node in worker.get_tree().get_nodes_in_group(&"buildings"):
		if not node is Building:
			continue

		var building: Building = node as Building
		if not NodeSafety.is_alive_node(building):
			continue

		if not building.is_position_inside_footprint(
			worker.global_position, GatheringConfig.AI_UNSTUCK_BUILDING_EDGE_PADDING
		):
			var edge_distance_sq: float = (
				worker.global_position.distance_squared_to(building.global_position)
			)
			if edge_distance_sq > search_radius_sq:
				continue

		var distance_sq: float = worker.global_position.distance_squared_to(
			building.global_position
		)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_building = building

	return nearest_building


static func _get_obstacle_center(worker: Worker, nearest_building: Building) -> Vector3:
	if nearest_building != null and is_instance_valid(nearest_building):
		return nearest_building.global_position

	if worker._build_trip_state == Worker.BuildTripState.TO_BUILDING:
		if worker._building_target != null and is_instance_valid(worker._building_target):
			return worker._building_target.global_position

	if worker._gather_state == Worker.GatherTripState.TO_COMMAND_CENTER:
		var dropoff: CommandCenter = worker._get_valid_cached_return_dropoff()
		if dropoff == null:
			dropoff = worker._assigned_dropoff
		if dropoff != null and is_instance_valid(dropoff):
			return dropoff.global_position

	if worker._gather_state == Worker.GatherTripState.TO_SOURCE:
		var source: GatherableResource = worker._get_valid_gather_source()
		if source != null and is_instance_valid(source):
			return source.global_position

	if worker._task_has_saved_destination:
		return worker._task_movement_destination

	return worker.global_position


static func _is_valid_escape_point(
	worker: Worker,
	point: Vector3,
	nearest_building: Building,
	obstacle_center: Vector3
) -> bool:
	var flat_offset: Vector3 = point - worker.global_position
	flat_offset.y = 0.0
	if flat_offset.length_squared() < 0.36:
		return false

	if not GroupMoveSpacing.is_within_map_bounds(point):
		return false

	if not GroupMoveSpacing.is_walkable_at(point, worker):
		return false

	if _is_inside_any_building_footprint(worker, point):
		return false

	if nearest_building != null and is_instance_valid(nearest_building):
		if nearest_building.is_position_inside_footprint(
			point, GatheringConfig.AI_UNSTUCK_BUILDING_EDGE_PADDING
		):
			return false

		var from_wall: Vector3 = point - nearest_building.global_position
		from_wall.y = 0.0
		var to_wall: Vector3 = worker.global_position - nearest_building.global_position
		to_wall.y = 0.0
		if from_wall.length_squared() < to_wall.length_squared() * 0.64:
			return false

	if _is_reserved_by_other_worker(worker, point):
		return false

	return _is_reachable_escape_point(worker, point)


static func _is_inside_any_building_footprint(worker: Worker, point: Vector3) -> bool:
	if not NodeSafety.is_alive_node(worker):
		return false

	for node: Node in worker.get_tree().get_nodes_in_group(&"buildings"):
		if not node is Building:
			continue

		var building: Building = node as Building
		if not NodeSafety.is_alive_node(building):
			continue

		if building.is_position_inside_footprint(point, 0.15):
			return true

	return false


static func _is_reachable_escape_point(worker: Worker, point: Vector3) -> bool:
	if not WorkerTaskNavigation.can_use(worker._navigation_agent):
		return true

	var nav_map: RID = worker._navigation_agent.get_navigation_map()
	if nav_map == RID():
		return false

	var from: Vector3 = NavigationServer3D.map_get_closest_point(
		nav_map, worker.global_position
	)
	var to: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, point)

	if from.distance_squared_to(worker.global_position) > 4.0:
		return false

	if to.distance_squared_to(point) > 2.25:
		return false

	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
	return path.size() >= 2


static func _score_escape_candidate(
	worker: Worker,
	point: Vector3,
	direction: Vector3,
	away_from_obstacle: Vector3,
	obstacle_center: Vector3,
	nearest_building: Building
) -> float:
	var travel: Vector3 = point - worker.global_position
	travel.y = 0.0
	var travel_distance: float = travel.length()

	var away_score: float = direction.normalized().dot(away_from_obstacle)
	var outward_score: float = (point - obstacle_center).length() - (
		worker.global_position - obstacle_center
	).length()

	var open_space_score: float = _estimate_open_space(worker, point)
	var building_clearance: float = 0.0
	if nearest_building != null and is_instance_valid(nearest_building):
		building_clearance = point.distance_to(nearest_building.global_position)

	return (
		away_score * 2.5
		+ outward_score * 1.5
		+ open_space_score
		+ building_clearance * 0.2
		- travel_distance * 0.1
	)


static func _estimate_open_space(worker: Worker, point: Vector3) -> float:
	var score: float = 0.0
	var probe_distance: float = 1.5

	for index: int in 4:
		var angle: float = PI * 0.5 * float(index)
		var probe_dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var probe_point: Vector3 = point + probe_dir * probe_distance
		if GroupMoveSpacing.is_walkable_at(probe_point, worker):
			score += 1.0

	return score


static func _reserve_escape_point(worker: Worker, point: Vector3) -> void:
	_release_escape_reservation(worker)
	_reserved_escape_points.append({
		"worker_id": worker.get_instance_id(),
		"position": point,
		"until": float(Time.get_ticks_msec()) / 1000.0 + GatheringConfig.AI_UNSTUCK_RESERVE_SECONDS,
	})


static func _release_escape_reservation(worker: Worker) -> void:
	var worker_id: int = worker.get_instance_id()
	for index: int in range(_reserved_escape_points.size() - 1, -1, -1):
		if _reserved_escape_points[index].get("worker_id", -1) == worker_id:
			_reserved_escape_points.remove_at(index)


static func _is_reserved_by_other_worker(worker: Worker, point: Vector3) -> bool:
	var radius_sq: float = GatheringConfig.AI_UNSTUCK_ESCAPE_RESERVE_RADIUS
	radius_sq *= radius_sq
	var worker_id: int = worker.get_instance_id()

	for entry: Dictionary in _reserved_escape_points:
		if entry.get("worker_id", -1) == worker_id:
			continue

		var reserved_position: Vector3 = entry.get("position", Vector3.ZERO)
		if reserved_position.distance_squared_to(point) <= radius_sq:
			return true

	return false


static func _prune_reserved_escape_points() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for index: int in range(_reserved_escape_points.size() - 1, -1, -1):
		if _reserved_escape_points[index].get("until", 0.0) <= now:
			_reserved_escape_points.remove_at(index)


static func _get_task_label(worker: Worker) -> String:
	if worker._build_trip_state == Worker.BuildTripState.TO_BUILDING:
		return "build"
	match worker._gather_state:
		Worker.GatherTripState.TO_SOURCE:
			if worker._assigned_resource_id == &"gold":
				return "gold"
			if worker._assigned_resource_id == &"wood":
				return "wood"
			return "gather"
		Worker.GatherTripState.TO_COMMAND_CENTER:
			return "return"
		_:
			return "idle"


static func _log_unstuck(worker: Worker, reason: StringName, nudge_pos: Vector3) -> void:
	if not DEBUG_AI_WORKER_UNSTUCK:
		return

	print(
		"[AI Worker Unstuck] worker=%s reason=%s attempt=%d task=%s nudge=%s"
		% [
			worker.name,
			reason,
			worker._ai_unstuck_attempt_number,
			_get_task_label(worker),
			nudge_pos,
		]
	)
