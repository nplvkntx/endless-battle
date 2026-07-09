class_name WallBuildJob
extends RefCounted

## Coordinates multiple workers building a drag-placed wall line.
## Workers claim nearby unfinished segments and continue until the job is done.

var _segments: Array[Building] = []
var _workers: Array[Worker] = []
var _segment_claims: Dictionary = {}


func _init(segments: Array[Building], workers: Array[Worker]) -> void:
	for segment: Building in segments:
		if _is_unfinished_segment(segment):
			_segments.append(segment)

	for worker: Worker in workers:
		if NodeSafety.is_alive_node(worker):
			_workers.append(worker)


func start() -> void:
	_prune_invalid_segments()
	_prune_stale_claims()

	for worker: Worker in _workers.duplicate():
		if not NodeSafety.is_alive_node(worker):
			_workers.erase(worker)
			continue

		worker.assign_wall_build_job(self)
		_assign_worker_to_segment(worker)


func on_worker_segment_finished(worker: Worker, finished_segment: Building) -> void:
	if finished_segment != null and _segment_claims.get(finished_segment) == worker:
		_segment_claims.erase(finished_segment)

	_prune_invalid_segments()
	_prune_stale_claims()

	if not _has_unfinished_segments():
		_finish_worker(worker)
		return

	_assign_worker_to_segment(worker)


func on_worker_segment_lost(worker: Worker, lost_segment: Building) -> void:
	if lost_segment != null and _segment_claims.get(lost_segment) == worker:
		_segment_claims.erase(lost_segment)

	_prune_invalid_segments()
	_prune_stale_claims()

	if not _has_unfinished_segments():
		_finish_worker(worker)
		return

	_assign_worker_to_segment(worker)


func on_worker_left(worker: Worker) -> void:
	_release_claims_for_worker(worker)
	_workers.erase(worker)

	if not _has_unfinished_segments():
		_cleanup()
		return

	for remaining_worker: Worker in _workers.duplicate():
		if not NodeSafety.is_alive_node(remaining_worker):
			_workers.erase(remaining_worker)
			continue

		if remaining_worker.is_available_for_construction_assignment():
			_assign_worker_to_segment(remaining_worker)


func _assign_worker_to_segment(worker: Worker) -> void:
	if not NodeSafety.is_alive_node(worker):
		return

	if worker.get_wall_build_job() != self:
		return

	var segment: Building = _pick_segment_for_worker(worker)
	if segment == null:
		_finish_worker(worker)
		return

	_claim_segment(worker, segment)
	worker.continue_wall_build_order(segment)


func _pick_segment_for_worker(worker: Worker) -> Building:
	var nearest_unclaimed: Building = _find_nearest_segment(worker, true)
	if nearest_unclaimed != null:
		return nearest_unclaimed

	return _find_nearest_segment(worker, false)


func _find_nearest_segment(worker: Worker, skip_claimed_by_others: bool) -> Building:
	var best_segment: Building = null
	var best_distance_sq: float = INF

	for segment: Building in _segments:
		if not _is_unfinished_segment(segment):
			continue

		if skip_claimed_by_others and _is_segment_claimed_by_other(segment, worker):
			continue

		var offset: Vector3 = segment.global_position - worker.global_position
		offset.y = 0.0
		var distance_sq: float = offset.length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_segment = segment

	return best_segment


func _is_segment_claimed_by_other(segment: Building, worker: Worker) -> bool:
	if not _segment_claims.has(segment):
		return false

	var claimer: Worker = _segment_claims[segment] as Worker
	if claimer == worker:
		return false

	if not _is_active_job_worker(claimer):
		_segment_claims.erase(segment)
		return false

	if not claimer.is_assigned_to_build(segment):
		_segment_claims.erase(segment)
		return false

	return true


func _claim_segment(worker: Worker, segment: Building) -> void:
	_segment_claims[segment] = worker


func _release_claims_for_worker(worker: Worker) -> void:
	for segment: Variant in _segment_claims.keys():
		if _segment_claims.get(segment) == worker:
			_segment_claims.erase(segment)


func _is_active_job_worker(worker: Worker) -> bool:
	return NodeSafety.is_alive_node(worker) and worker.get_wall_build_job() == self


func _is_unfinished_segment(segment: Building) -> bool:
	return (
		NodeSafety.is_alive_node(segment)
		and segment.is_being_constructed()
	)


func _has_unfinished_segments() -> bool:
	_prune_invalid_segments()
	return not _segments.is_empty()


func _prune_invalid_segments() -> void:
	var remaining_segments: Array[Building] = []
	for segment: Building in _segments:
		if _is_unfinished_segment(segment):
			remaining_segments.append(segment)
		elif _segment_claims.has(segment):
			_segment_claims.erase(segment)

	_segments = remaining_segments
	NodeSafety.clean_node_dict_keys(_segment_claims)


func _prune_stale_claims() -> void:
	for segment: Variant in _segment_claims.keys():
		var claimer: Worker = _segment_claims.get(segment) as Worker
		if not _is_active_job_worker(claimer):
			_segment_claims.erase(segment)
			continue

		if not _is_unfinished_segment(segment as Building):
			_segment_claims.erase(segment)


func _finish_worker(worker: Worker) -> void:
	if NodeSafety.is_alive_node(worker):
		worker.clear_wall_build_job_assignment()

	_workers.erase(worker)

	if not _has_unfinished_segments():
		_cleanup()


func _cleanup() -> void:
	for worker: Worker in _workers.duplicate():
		if NodeSafety.is_alive_node(worker):
			worker.clear_wall_build_job_assignment()

	_workers.clear()
	_segments.clear()
	_segment_claims.clear()
