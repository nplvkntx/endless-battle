class_name WorkerAiUnstuck
extends RefCounted

## Sideways nav nudge recovery for enemy workers blocked near Town Center / buildings.

const DEBUG_AI_WORKER_UNSTUCK: bool = false


static func is_active(worker: Worker) -> bool:
	return worker._ai_unstuck_active


static func reset_state(worker: Worker) -> void:
	worker._ai_unstuck_active = false
	worker._ai_unstuck_target = Vector3.ZERO
	worker._ai_unstuck_time = 0.0
	worker._ai_unstuck_direction_offset = 0
	reset_watch(worker)


static func reset_watch(worker: Worker) -> void:
	worker._ai_unstuck_watch_position = worker.global_position
	worker._ai_unstuck_watch_time = 0.0


static func update_detection(worker: Worker, delta: float) -> void:
	if worker._ai_unstuck_cooldown > 0.0:
		worker._ai_unstuck_cooldown = maxf(0.0, worker._ai_unstuck_cooldown - delta)

	if worker._ai_unstuck_active:
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
		worker._ai_unstuck_direction_offset = 0
		return

	worker._ai_unstuck_watch_time += delta
	if worker._ai_unstuck_watch_time < GatheringConfig.AI_UNSTUCK_STUCK_DELAY:
		return

	if worker._ai_unstuck_cooldown > 0.0:
		return

	_begin_unstuck(worker)


static func process_movement(worker: Worker, delta: float) -> void:
	worker._ai_unstuck_time += delta

	var arrived: bool = WorkerTaskNavigation.process_direct_movement(
		worker,
		worker._ai_unstuck_target,
		worker.move_speed,
		worker.stopping_distance
	)
	var timed_out: bool = worker._ai_unstuck_time >= GatheringConfig.AI_UNSTUCK_NUDGE_MAX_TIME

	if arrived or timed_out:
		_finish_unstuck(worker)


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


static func _begin_unstuck(worker: Worker) -> void:
	var nudge_target: Vector3 = _pick_nudge_target(worker)
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

	_log_unstuck(worker, &"blocked", nudge_target)
	reset_watch(worker)


static func _finish_unstuck(worker: Worker) -> void:
	worker._ai_unstuck_active = false
	worker._ai_unstuck_time = 0.0
	worker.velocity = Vector3.ZERO
	_resume_task(worker)


static func _resume_task(worker: Worker) -> void:
	if worker._build_trip_state == Worker.BuildTripState.TO_BUILDING:
		if worker._building_target != null and is_instance_valid(worker._building_target):
			if not worker._construction_target_point_valid:
				worker._assign_construction_target_point(false)
			worker.set_movement_target(worker._construction_target_point)
		return

	match worker._gather_state:
		Worker.GatherTripState.TO_SOURCE:
			if not worker._has_valid_gather_source():
				return
			if worker._is_gathering_wood() and worker._wood_chop_spot_valid:
				worker.set_movement_target(worker._wood_chop_spot)
			else:
				var source: GatherableResource = worker._get_valid_gather_source()
				worker.set_movement_target(
					worker._compute_resource_approach_position_for_candidate(
						source, worker._source_approach_candidate_index
					)
				)
		Worker.GatherTripState.TO_COMMAND_CENTER:
			if worker._carried_amount <= 0:
				return
			var dropoff: CommandCenter = worker._get_valid_cached_return_dropoff()
			if dropoff == null:
				dropoff = worker._resolve_dropoff_target()
			if dropoff != null:
				worker.set_movement_target(
					worker._compute_command_center_dropoff_position(dropoff)
				)


static func _pick_nudge_target(worker: Worker) -> Vector3:
	var obstacle_center: Vector3 = _get_obstacle_center(worker)
	var away: Vector3 = worker.global_position - obstacle_center
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	else:
		away = away.normalized()

	var direction_count: int = GatheringConfig.AI_UNSTUCK_DIRECTION_COUNT
	var worker_seed: int = absi(worker.get_instance_id())
	var start_index: int = (
		worker_seed + worker._ai_unstuck_direction_offset
	) % direction_count

	var best_target: Vector3 = Vector3.ZERO
	var best_score: float = -INF

	for attempt: int in direction_count:
		var dir_index: int = (start_index + attempt) % direction_count
		var angle: float = TAU * float(dir_index) / float(direction_count)
		var direction: Vector3 = away.rotated(Vector3.UP, angle - PI * 0.5)
		if direction.length_squared() < 0.001:
			continue

		var distance: float = lerpf(
			GatheringConfig.AI_UNSTUCK_DISTANCE_MIN,
			GatheringConfig.AI_UNSTUCK_DISTANCE_MAX,
			float((dir_index + worker_seed % 3) % 3) / 2.0
		)
		distance += float(worker_seed % 5) * 0.12

		var probe: Vector3 = worker.global_position + direction.normalized() * distance
		probe.y = worker.global_position.y

		var snapped: Vector3 = worker._snap_task_target_to_navigation(probe)
		if not _is_valid_nudge_point(worker, snapped):
			continue

		var score: float = _score_nudge_candidate(worker, snapped, direction, away, obstacle_center)
		if score > best_score:
			best_score = score
			best_target = snapped

	return best_target


static func _get_obstacle_center(worker: Worker) -> Vector3:
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


static func _is_valid_nudge_point(worker: Worker, point: Vector3) -> bool:
	var flat_offset: Vector3 = point - worker.global_position
	flat_offset.y = 0.0
	if flat_offset.length_squared() < 0.25:
		return false

	if _is_inside_blocked_footprint(worker, point):
		return false

	return _is_reachable_nudge_point(worker, point)


static func _is_inside_blocked_footprint(worker: Worker, point: Vector3) -> bool:
	if worker._gather_state == Worker.GatherTripState.TO_SOURCE:
		var source: GatherableResource = worker._get_valid_gather_source()
		if source != null and _is_inside_body_footprint(point, source, worker):
			return true

	if worker._build_trip_state == Worker.BuildTripState.TO_BUILDING:
		if (
			worker._building_target != null
			and _is_inside_body_footprint(point, worker._building_target, worker)
		):
			return true

	if worker._gather_state == Worker.GatherTripState.TO_COMMAND_CENTER:
		var dropoff: CommandCenter = worker._get_valid_cached_return_dropoff()
		if dropoff == null:
			dropoff = worker._assigned_dropoff
		if dropoff != null and _is_inside_body_footprint(point, dropoff, worker):
			return true

	return false


static func _is_inside_body_footprint(
	point: Vector3, body: CollisionObject3D, worker: Worker
) -> bool:
	var offset: Vector3 = point - body.global_position
	offset.y = 0.0
	var radius: float = worker._get_collision_xz_radius(body) + 0.35
	return offset.length_squared() <= radius * radius


static func _is_reachable_nudge_point(worker: Worker, point: Vector3) -> bool:
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


static func _score_nudge_candidate(
	worker: Worker,
	point: Vector3,
	direction: Vector3,
	away_from_obstacle: Vector3,
	obstacle_center: Vector3
) -> float:
	var travel: Vector3 = point - worker.global_position
	travel.y = 0.0
	var travel_distance: float = travel.length()

	var away_score: float = direction.normalized().dot(away_from_obstacle)
	var outward_score: float = (point - obstacle_center).length() - (
		worker.global_position - obstacle_center
	).length()

	return away_score * 2.0 + outward_score - travel_distance * 0.15


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
		"[AI Worker Unstuck] worker=%s reason=%s old_task=%s nudge=%s"
		% [worker.name, reason, _get_task_label(worker), nudge_pos]
	)
