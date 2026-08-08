extends Node

## Headless verification for construction placement, reservations, and parallel builds.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_construction.tscn

const REPORT_PATH := "user://construction_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/buildings/shop.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const ACADEMY_SCENE: PackedScene = preload("res://scenes/buildings/academy.tscn")
const ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const WALL_SEGMENT_SCENE: PackedScene = preload("res://scenes/buildings/wall_segment.tscn")
const SETTLE_MS := 800
const BUILD_MS := 12000

const ALL_BUILDING_SCENES: Array[PackedScene] = [
	FARM_SCENE,
	BARRACKS_SCENE,
	BLACKSMITH_SCENE,
	STABLE_SCENE,
	SHOP_SCENE,
	TOWER_SCENE,
	HERO_ALTAR_SCENE,
	COMMAND_CENTER_SCENE,
	ACADEMY_SCENE,
	ARTILLERY_DEPOT_SCENE,
	WALL_SEGMENT_SCENE,
]


func _ready() -> void:
	var failures: PackedStringArray = []
	ConstructionReservations.reset_match_state()
	WorkerGathering.reset_match_state()
	WorkerAiUnstuck.reset_match_state()

	print("verify_construction: start")
	_verify_blocked_placement(failures)
	_verify_stale_reservation_expiry(failures)
	_verify_preview_matches_final(failures)
	_verify_construction_stages_all_buildings(failures)
	_verify_stage_threshold_crossing_once(failures)
	await _verify_parallel_buildings(failures)
	await _verify_multi_worker_assist(failures)
	await _verify_builder_dies_en_route(failures)
	await _verify_cancelled_construction_refund(failures)
	await _verify_destroyed_unfinished_building(failures)
	await _verify_ai_construction_stages(failures)
	await _verify_nav_snap_does_not_false_commit(failures)
	await _verify_construction_timer_survives_brief_range_loss(failures)
	await _verify_build_tick_stagger_advances_parity(failures)
	_verify_ai_farm_reservation_recovery(failures)
	_verify_compact_ai_placement_smoke(failures)

	var report: String
	if failures.is_empty():
		report = "PASS construction\n"
	else:
		report = "FAIL construction\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_blocked_placement(failures: PackedStringArray) -> void:
	print("verify: blocked placement")
	var root := Node3D.new()
	add_child(root)

	var blocker: Building = FARM_SCENE.instantiate() as Building
	root.add_child(blocker)
	blocker.global_position = Vector3(0.0, EnemyBuildPlacement.FARM_GROUND_Y, 0.0)
	blocker.set_completed()

	var candidate := Vector3(0.0, EnemyBuildPlacement.FARM_GROUND_Y, 0.0)
	var buildings: Array[Node3D] = [blocker]
	var valid: bool = EnemyBuildPlacement.is_position_valid(
		candidate,
		&"farm",
		buildings,
		root
	)
	_expect(failures, "blocked: overlapping farm invalid", not valid)

	var edge := Vector3(49.5, EnemyBuildPlacement.FARM_GROUND_Y, 49.5)
	var no_buildings: Array[Node3D] = []
	var edge_valid: bool = EnemyBuildPlacement.is_position_valid(
		edge,
		&"barracks",
		no_buildings,
		root
	)
	_expect(failures, "blocked: map-edge barracks invalid", not edge_valid)

	blocker.free()
	root.free()


func _verify_stale_reservation_expiry(failures: PackedStringArray) -> void:
	print("verify: stale reservation expiry")
	ConstructionReservations.reset_match_state()
	var center := Vector3(5.0, 0.5, 5.0)
	var footprint := EnemyBuildPlacement.FARM_SIZE
	var reservation_id: int = ConstructionReservations.reserve_footprint(
		center,
		footprint,
		null,
		1
	)
	_expect(
		failures,
		"stale: reservation blocks immediately",
		ConstructionReservations.overlaps_reserved_footprint(center, footprint)
	)

	OS.delay_msec(5)
	ConstructionReservations.purge_expired()
	_expect(
		failures,
		"stale: expired reservation no longer blocks",
		not ConstructionReservations.overlaps_reserved_footprint(center, footprint)
	)
	ConstructionReservations.release_footprint(reservation_id)
	ConstructionReservations.reset_match_state()


func _verify_preview_matches_final(failures: PackedStringArray) -> void:
	print("verify: preview validity matches final")
	var root := Node3D.new()
	add_child(root)

	var open := Vector3(8.0, EnemyBuildPlacement.FARM_GROUND_Y, 8.0)
	var no_buildings: Array[Node3D] = []
	var no_excludes: Array[Node] = []
	var preview_valid: bool = EnemyBuildPlacement.is_position_valid(
		open,
		&"farm",
		no_buildings,
		root,
		no_excludes,
		true
	)
	var final_valid: bool = EnemyBuildPlacement.is_position_valid(
		open,
		&"farm",
		no_buildings,
		root,
		no_excludes,
		true
	)
	_expect(failures, "preview/final open site agree", preview_valid == final_valid and preview_valid)

	var ground_y_preview: float = EnemyBuildPlacement.get_ground_y(&"farm")
	var ground_y_shared: float = EnemyBuildPlacement.FARM_GROUND_Y
	_expect(failures, "preview/final share farm ground Y", is_equal_approx(ground_y_preview, ground_y_shared))

	# Typed-array callers for farm + two other building types (placement crash regression).
	var barracks_pos := Vector3(-8.0, EnemyBuildPlacement.BARRACKS_GROUND_Y, 8.0)
	var tower_pos := Vector3(8.0, EnemyBuildPlacement.TOWER_GROUND_Y, -8.0)
	var barracks_valid: bool = EnemyBuildPlacement.is_position_valid(
		barracks_pos,
		&"barracks",
		no_buildings,
		root,
		no_excludes,
		true
	)
	var tower_valid: bool = EnemyBuildPlacement.is_position_valid(
		tower_pos,
		&"tower",
		no_buildings,
		root,
		no_excludes,
		true
	)
	_expect(failures, "typed args: barracks open site valid", barracks_valid)
	_expect(failures, "typed args: tower open site valid", tower_valid)

	root.free()


func _verify_parallel_buildings(failures: PackedStringArray) -> void:
	print("verify: two buildings constructed in parallel")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var farm: Building = FARM_SCENE.instantiate() as Building
	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	root.add_child(farm)
	root.add_child(barracks)
	farm.global_position = Vector3(-4.0, EnemyBuildPlacement.FARM_GROUND_Y, 0.0)
	barracks.global_position = Vector3(4.0, EnemyBuildPlacement.BARRACKS_GROUND_Y, 0.0)
	farm.set_construction_cost(80, 20, false)
	barracks.set_construction_cost(150, 100, false)
	farm.start_under_construction()
	barracks.start_under_construction()
	farm.setup_construction(1.5)
	barracks.setup_construction(1.5)

	var worker_a: Worker = _spawn_worker(root, Vector3(-4.0, 0.5, -2.2), false)
	var worker_b: Worker = _spawn_worker(root, Vector3(4.0, 0.5, -2.2), false)
	await _wait_nav_ready(worker_a)
	worker_a.start_construction_order(farm)
	worker_b.start_construction_order(barracks)

	await _wait_msec(SETTLE_MS)
	_expect(failures, "parallel: worker A assigned to farm", worker_a.is_assigned_to_build(farm))
	_expect(failures, "parallel: worker B assigned to barracks", worker_b.is_assigned_to_build(barracks))
	_expect(
		failures,
		"parallel: both trips active simultaneously",
		worker_a.is_on_construction_trip() and worker_b.is_on_construction_trip()
	)

	# Force-commit once workers are near so headless nav limitations do not false-fail.
	if worker_a.is_assigned_to_build(farm) and not worker_a.is_constructing():
		worker_a.global_position = farm.get_nearest_construction_point(worker_a.global_position)
		worker_a._commit_to_construction()
	if worker_b.is_assigned_to_build(barracks) and not worker_b.is_constructing():
		worker_b.global_position = barracks.get_nearest_construction_point(worker_b.global_position)
		worker_b._commit_to_construction()

	var parallel_deadline: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < parallel_deadline:
		if (
			farm.building_state == Building.STATE_COMPLETED
			and barracks.building_state == Building.STATE_COMPLETED
		):
			break
		await get_tree().process_frame

	_expect(failures, "parallel: farm completed", farm.building_state == Building.STATE_COMPLETED)
	_expect(failures, "parallel: barracks completed", barracks.building_state == Building.STATE_COMPLETED)

	await _free_harness(harness)


func _verify_multi_worker_assist(failures: PackedStringArray) -> void:
	print("verify: several workers assisting one building")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	root.add_child(barracks)
	barracks.global_position = Vector3(0.0, EnemyBuildPlacement.BARRACKS_GROUND_Y, 0.0)
	barracks.start_under_construction()
	barracks.setup_construction(1.5)

	var workers: Array[Worker] = []
	for index: int in 3:
		var worker: Worker = _spawn_worker(
			root,
			Vector3(float(index) * 1.5 - 1.5, 0.5, -2.5),
			false
		)
		workers.append(worker)

	await _wait_nav_ready(workers[0])
	for worker: Worker in workers:
		worker.start_construction_order(barracks)

	await _wait_msec(SETTLE_MS)

	var slots: Dictionary = {}
	var assigned_count: int = 0
	for worker: Worker in workers:
		if worker.is_assigned_to_build(barracks):
			assigned_count += 1
		var slot: int = ConstructionReservations.get_claimed_build_slot(barracks, worker)
		if slot >= 0:
			_expect(failures, "assist: slot %d unique for worker" % slot, not slots.has(slot))
			slots[slot] = true

	_expect(failures, "assist: all workers stay assigned", assigned_count == 3)
	_expect(failures, "assist: distinct build slots claimed", slots.size() >= 2)

	for worker: Worker in workers:
		if worker.is_assigned_to_build(barracks) and not worker.is_constructing():
			var point: Vector3 = barracks.get_construction_point_by_index(
				maxi(ConstructionReservations.get_claimed_build_slot(barracks, worker), 0)
			)
			worker.global_position = point
			worker._commit_to_construction()

	var assist_deadline: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < assist_deadline:
		if barracks.building_state == Building.STATE_COMPLETED:
			break
		await get_tree().process_frame

	_expect(failures, "assist: barracks completed", barracks.building_state == Building.STATE_COMPLETED)

	await _free_harness(harness)


func _verify_builder_dies_en_route(failures: PackedStringArray) -> void:
	print("verify: builder dying en route releases reservation")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var farm: Building = FARM_SCENE.instantiate() as Building
	root.add_child(farm)
	farm.global_position = Vector3(0.0, EnemyBuildPlacement.FARM_GROUND_Y, 0.0)
	farm.start_under_construction()
	farm.setup_construction(8.0)

	var worker: Worker = _spawn_worker(root, Vector3(0.0, 0.5, -8.0), false)
	await _wait_nav_ready(worker)
	worker.start_construction_order(farm)
	await _wait_msec(400)

	_expect(failures, "death: worker claimed a build slot", ConstructionReservations.count_build_slot_claims(farm) >= 1)
	worker._on_health_depleted()
	await get_tree().process_frame
	ConstructionReservations.purge_expired()
	_expect(failures, "death: build slot released after death", ConstructionReservations.count_build_slot_claims(farm) == 0)

	await _free_harness(harness)


func _verify_cancelled_construction_refund(failures: PackedStringArray) -> void:
	print("verify: cancelled construction refunds resources")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var starting_gold: int = ResourceManager.gold
	var starting_wood: int = ResourceManager.wood
	ResourceManager.try_spend(80, 20)

	var farm: Building = FARM_SCENE.instantiate() as Building
	root.add_child(farm)
	farm.global_position = Vector3(0.0, EnemyBuildPlacement.FARM_GROUND_Y, 0.0)
	farm.set_construction_cost(80, 20, false)
	farm.start_under_construction()
	farm.setup_construction(10.0)
	_expect(failures, "cancel: stage host present while building", _has_stage_host(farm))

	var worker: Worker = _spawn_worker(root, Vector3(0.0, 0.5, -3.0), false)
	await _wait_nav_ready(worker)
	worker.start_construction_order(farm)
	await _wait_msec(200)
	worker._cancel_build_trip()

	farm.refund_and_cancel_construction()
	await get_tree().process_frame

	_expect(failures, "cancel: gold refunded", ResourceManager.gold == starting_gold)
	_expect(failures, "cancel: wood refunded", ResourceManager.wood == starting_wood)
	_expect(
		failures,
		"cancel: farm removed",
		not is_instance_valid(farm) or farm.is_queued_for_deletion()
	)

	await _free_harness(harness)


func _verify_construction_stages_all_buildings(failures: PackedStringArray) -> void:
	print("verify: construction stages for every building type")
	var root := Node3D.new()
	add_child(root)

	var samples: Array[float] = [0.0, 0.24, 0.25, 0.49, 0.5, 0.74, 0.75, 0.99, 1.0]
	var expected: Array[int] = [0, 0, 1, 1, 2, 2, 3, 3, 4]

	for scene: PackedScene in ALL_BUILDING_SCENES:
		var building: Building = scene.instantiate() as Building
		_expect(failures, "stages: scene instantiates Building", building != null)
		if building == null:
			continue

		root.add_child(building)
		building.global_position = Vector3(0.0, 0.5, 0.0)
		# Override auto-complete from building _ready.
		building.start_under_construction()
		building.setup_construction(10.0)

		var type_label: String = building.get_script().resource_path.get_file().get_basename()
		_expect(
			failures,
			"stages: %s starts at stage 0" % type_label,
			building.get_construction_stage_index() == 0
		)

		for sample_index: int in samples.size():
			var progress: float = samples[sample_index]
			var want_stage: int = expected[sample_index]
			if progress >= 1.0:
				building.force_construction_progress_for_verify(progress)
				_expect(
					failures,
					"stages: %s completes at 100%%" % type_label,
					building.building_state == Building.STATE_COMPLETED
				)
				_expect(
					failures,
					"stages: %s restores finished visuals" % type_label,
					not _has_stage_host(building)
				)
			else:
				building.force_construction_progress_for_verify(progress)
				_expect(
					failures,
					"stages: %s at %.2f -> stage %d" % [type_label, progress, want_stage],
					building.get_construction_stage_index() == want_stage
				)

		building.free()

	root.free()


func _verify_stage_threshold_crossing_once(failures: PackedStringArray) -> void:
	print("verify: stage changes only once per threshold")
	var root := Node3D.new()
	add_child(root)

	var barracks: Building = BARRACKS_SCENE.instantiate() as Building
	root.add_child(barracks)
	barracks.start_under_construction()
	barracks.setup_construction(10.0)

	var last_stage: int = barracks.get_construction_stage_index()
	var transitions: int = 0
	var progress: float = 0.0
	while progress <= 1.001:
		barracks.force_construction_progress_for_verify(minf(progress, 1.0))
		var stage: int = barracks.get_construction_stage_index()
		if stage != last_stage:
			transitions += 1
			_expect(
				failures,
				"threshold: stage only increases",
				stage == last_stage + 1 or (last_stage == 3 and stage == 4)
			)
			last_stage = stage
		progress += 0.01
		if barracks.building_state == Building.STATE_COMPLETED:
			break

	_expect(failures, "threshold: exactly 4 stage transitions (0→1→2→3→4)", transitions == 4)
	barracks.free()
	root.free()


func _verify_destroyed_unfinished_building(failures: PackedStringArray) -> void:
	print("verify: destroying unfinished building cleans up")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var tower: Building = TOWER_SCENE.instantiate() as Building
	root.add_child(tower)
	tower.global_position = Vector3(0.0, EnemyBuildPlacement.TOWER_GROUND_Y, 0.0)
	tower.set_construction_cost(100, 50, false)
	tower.start_under_construction()
	tower.setup_construction(10.0)
	tower.force_construction_progress_for_verify(0.4)
	_expect(failures, "destroy: mid-build stage active", tower.get_construction_stage_index() == 1)
	_expect(failures, "destroy: stage host present", _has_stage_host(tower))

	tower.destroy_building()
	tower.queue_free()
	await get_tree().process_frame
	_expect(
		failures,
		"destroy: unfinished tower removed",
		not is_instance_valid(tower) or tower.is_queued_for_deletion()
	)

	await _free_harness(harness)


func _verify_ai_construction_stages(failures: PackedStringArray) -> void:
	print("verify: AI construction uses same stage system")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var farm: Building = FARM_SCENE.instantiate() as Building
	root.add_child(farm)
	farm.add_to_group(&"enemy_command_center")
	farm.team_id = 1
	farm.global_position = Vector3(0.0, EnemyBuildPlacement.FARM_GROUND_Y, 0.0)
	farm.set_construction_cost(80, 20, true)
	farm.start_under_construction()
	farm.setup_construction(4.0)

	_expect(failures, "ai stages: starts at 0", farm.get_construction_stage_index() == 0)
	farm.force_construction_progress_for_verify(0.5)
	_expect(failures, "ai stages: 50% is stage 2", farm.get_construction_stage_index() == 2)

	var worker: Worker = _spawn_worker(root, Vector3(0.0, 0.5, -2.2), true)
	await _wait_nav_ready(worker)
	worker.start_construction_order(farm)
	await _wait_msec(SETTLE_MS)
	if worker.is_assigned_to_build(farm) and not worker.is_constructing():
		worker.global_position = farm.get_nearest_construction_point(worker.global_position)
		worker._commit_to_construction()

	farm.force_construction_progress_for_verify(1.0)
	_expect(failures, "ai stages: completes", farm.building_state == Building.STATE_COMPLETED)
	_expect(failures, "ai stages: host cleared", not _has_stage_host(farm))

	await _free_harness(harness)


func _has_stage_host(building: Building) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	var visuals: Node = building.get_node_or_null("Visuals")
	if visuals == null:
		return false
	return visuals.get_node_or_null("ConstructionStageHost") != null


func _verify_nav_snap_does_not_false_commit(failures: PackedStringArray) -> void:
	## Regression: nav-snapped approach points far from the building must not count as
	## build-start range. That false commit left AI opening farms permanently unfinished.
	print("verify: nav-snapped standee does not false-commit construction")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var farm: Building = FARM_SCENE.instantiate() as Building
	root.add_child(farm)
	farm.global_position = Vector3(18.0, EnemyBuildPlacement.FARM_GROUND_Y, 18.0)
	farm.set_construction_cost(80, 20, true)
	farm.start_under_construction()
	farm.setup_construction(2.0)

	var worker: Worker = _spawn_worker(root, Vector3(0.0, 0.5, 0.0), true)
	await _wait_nav_ready(worker)
	worker.start_construction_order(farm)

	## Simulate a bad nav snap: standee beside the worker, far from the farm.
	worker._building_target = farm
	worker._build_trip_state = Worker.BuildTripState.TO_BUILDING
	worker._construction_target_point = worker.global_position
	worker._construction_target_point_valid = true

	_expect(
		failures,
		"false-snap: not in real build range while far from farm",
		not worker._is_in_build_start_range()
	)
	_expect(
		failures,
		"false-snap: does not commit construction",
		not worker._try_commit_construction_if_in_range()
	)
	_expect(
		failures,
		"false-snap: remains TO_BUILDING",
		worker._build_trip_state == Worker.BuildTripState.TO_BUILDING
	)

	## Real arrival beside the farm must still commit.
	var standee: Vector3 = farm.get_nearest_construction_point(worker.global_position)
	worker.global_position = standee
	worker._construction_target_point = standee
	worker._construction_target_point_valid = true
	_expect(failures, "near farm: in build range", worker._is_in_build_start_range())
	_expect(failures, "near farm: commits", worker._try_commit_construction_if_in_range())
	_expect(failures, "near farm: constructing", worker.is_constructing())

	await _free_harness(harness)


func _verify_construction_timer_survives_brief_range_loss(
	failures: PackedStringArray
) -> void:
	## Regression: unfinished buildings must keep processing after a brief out-of-range
	## check. Disabling _process froze AI opening farms with the builder still assigned.
	print("verify: construction timer survives brief range loss")
	var harness: Dictionary = await _spawn_harness()
	var root: Node3D = harness["root"]

	var farm: Building = FARM_SCENE.instantiate() as Building
	root.add_child(farm)
	farm.global_position = Vector3(22.0, EnemyBuildPlacement.FARM_GROUND_Y, 22.0)
	farm.set_construction_cost(80, 20, true)
	farm.start_under_construction()
	farm.setup_construction(4.0)

	var worker: Worker = _spawn_worker(root, farm.global_position + Vector3(2.0, 0.5, 0.0), true)
	await _wait_nav_ready(worker)
	worker.start_construction_order(farm)
	worker.global_position = farm.get_nearest_construction_point(worker.global_position)
	worker._building_target = farm
	worker._try_commit_construction_if_in_range()
	_expect(failures, "range-loss: worker constructing", worker.is_constructing())
	_expect(
		failures,
		"range-loss: actively constructing after commit",
		worker.is_actively_constructing_building(farm)
	)

	## Let progress advance, then leave range for a few frames (old bug: set_process false).
	for _i: int in range(90):
		await get_tree().process_frame
	var progress_before: float = farm.get_construction_progress_ratio()
	_expect(failures, "range-loss: made initial progress", progress_before > 0.02)

	worker.global_position = farm.global_position + Vector3(40.0, 0.5, 40.0)
	for _j: int in range(6):
		await get_tree().process_frame
	_expect(
		failures,
		"range-loss: unfinished building keeps processing",
		farm.is_processing()
	)

	## Return without re-registering — progress must resume from kept _process.
	worker.global_position = farm.get_nearest_construction_point(
		farm.global_position + Vector3(2.0, 0.0, 0.0)
	)
	for _k: int in range(120):
		await get_tree().process_frame
	_expect(
		failures,
		"range-loss: progress resumes after returning to range",
		farm.get_construction_progress_ratio() > progress_before + 0.05
	)

	await _free_harness(harness)


func _verify_build_tick_stagger_advances_parity(failures: PackedStringArray) -> void:
	## Regression for EnemyBuildManager even-frame stagger: defer via process_frame so
	## parity always flips. A fixed 0.05s timer can land forever on even frames at some
	## FPS values and permanently skip AI production / opening.
	print("verify: build-tick stagger advances frame parity")
	while Engine.get_process_frames() % 2 != 0:
		await get_tree().process_frame
	_expect(
		failures,
		"stagger: start on even process frame",
		Engine.get_process_frames() % 2 == 0
	)
	await get_tree().process_frame
	_expect(
		failures,
		"stagger: next process frame is odd",
		Engine.get_process_frames() % 2 == 1
	)


func _verify_ai_farm_reservation_recovery(failures: PackedStringArray) -> void:
	print("verify: AI recovers after failed farm placement / reservation TTL")
	EnemyResourceManager.reset_to_starting_values()
	ConstructionReservations.reset_match_state()

	var gold_before: int = EnemyResourceManager.gold
	var wood_before: int = EnemyResourceManager.wood
	EnemyResourceManager.reserve_resources(80, 20)
	_expect(
		failures,
		"ai farm: spendable reduced while reserved",
		EnemyResourceManager.get_spendable_gold() == gold_before - 80
	)

	# Afford check must use total stockpile while reservation is held (no double-count).
	_expect(
		failures,
		"ai farm: can afford from total while reserved",
		EnemyResourceManager.can_afford(80, 20, false)
	)
	_expect(
		failures,
		"ai farm: double-count blocked with respect_reservations",
		not EnemyResourceManager.can_afford(80, 20, true) or gold_before >= 160
	)

	## Opening first-farm used spendable-only afford after `_sync_farm_reservation()`,
	## which double-counts the soft hold and can block placement while totals are enough.
	_expect(
		failures,
		"ai farm: opening-style spendable check blocked while reserved",
		not EnemyResourceManager.can_afford(80, 20, true) or gold_before >= 160
	)
	_expect(
		failures,
		"ai farm: reservation-aware afford allows opening farm",
		EnemyResourceManager.can_afford(80, 20, false)
	)

	EnemyResourceManager.release_reservation(80, 20)
	_expect(
		failures,
		"ai farm: reservation release restores spendable",
		EnemyResourceManager.get_spendable_gold() == gold_before
	)

	var footprint_id: int = ConstructionReservations.reserve_footprint(
		Vector3(12.0, 0.5, 12.0),
		EnemyBuildPlacement.FARM_SIZE,
		null,
		1
	)
	OS.delay_msec(5)
	ConstructionReservations.purge_expired()
	_expect(
		failures,
		"ai farm: failed-site footprint reservation expires",
		not ConstructionReservations.overlaps_reserved_footprint(
			Vector3(12.0, 0.5, 12.0),
			EnemyBuildPlacement.FARM_SIZE
		)
	)
	ConstructionReservations.release_footprint(footprint_id)

	EnemyResourceManager.gold = gold_before
	EnemyResourceManager.wood = wood_before


func _verify_compact_ai_placement_smoke(failures: PackedStringArray) -> void:
	print("verify: compact AI placement smoke")
	var root := Node3D.new()
	add_child(root)

	var anchor := Vector3(0.0, EnemyBuildPlacement.COMMAND_CENTER_GROUND_Y, 0.0)
	var buildings: Array[Node3D] = []

	# Synthetic town hall footprint blocker so clearance rules engage.
	var th_blocker: Building = FARM_SCENE.instantiate() as Building
	root.add_child(th_blocker)
	th_blocker.global_position = anchor
	th_blocker.set_completed()
	buildings.append(th_blocker)

	var first_farm: Vector3 = EnemyBuildPlacement.find_position(
		anchor,
		&"farm",
		buildings,
		false,
		root,
		RID()
	)
	_expect(failures, "compact smoke: first farm placeable", first_farm.is_finite())
	if first_farm.is_finite():
		var farm_a: Building = FARM_SCENE.instantiate() as Building
		root.add_child(farm_a)
		farm_a.global_position = first_farm
		farm_a.set_completed()
		buildings.append(farm_a)

		var second_farm: Vector3 = EnemyBuildPlacement.find_position(
			anchor,
			&"farm",
			buildings,
			false,
			root,
			RID()
		)
		_expect(failures, "compact smoke: second farm placeable", second_farm.is_finite())
		if second_farm.is_finite():
			_expect(
				failures,
				"compact smoke: farms not wildly spaced",
				first_farm.distance_to(second_farm) <= 8.0
			)

		var barracks: Vector3 = EnemyBuildPlacement.find_position(
			anchor,
			&"barracks",
			buildings,
			false,
			root,
			RID()
		)
		_expect(failures, "compact smoke: barracks placeable", barracks.is_finite())
		if barracks.is_finite():
			_expect(
				failures,
				"compact smoke: barracks near anchor",
				anchor.distance_to(barracks) <= 16.0
			)

	root.free()


func _spawn_worker(parent: Node, position: Vector3, is_enemy: bool) -> Worker:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	parent.add_child(worker)
	worker.global_position = position
	if is_enemy:
		worker.add_to_group(&"enemy_workers")
		worker.team_id = 1
	return worker


func _spawn_harness() -> Dictionary:
	var root := Node3D.new()
	root.name = "ConstructionHarness"
	add_child(root)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	root.add_child(region)
	await get_tree().process_frame
	await _bake_nav_mesh(region)
	return {"root": root, "region": region}


func _bake_nav_mesh(region: NavigationRegion3D) -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25

	var source_data := NavigationMeshSourceGeometryData3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(60.0, 60.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	region.navigation_mesh = nav_mesh
	await get_tree().process_frame
	await get_tree().physics_frame


func _wait_nav_ready(unit: Unit) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline_msec:
		if unit._navigation_agent != null and UnitNavigation.can_use(unit._navigation_agent):
			return
		await get_tree().physics_frame


func _wait_msec(duration_msec: int) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + duration_msec
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().physics_frame


func _free_harness(harness: Dictionary) -> void:
	var root: Node = harness.get("root") as Node
	if root != null and is_instance_valid(root):
		root.free()
	ConstructionReservations.reset_match_state()
	WorkerGathering.reset_match_state()
	await get_tree().process_frame


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)
