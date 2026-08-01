extends Node

## Headless verification for Warcraft III-style unified Shift command queue.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_shift_command_queue.tscn

const REPORT_PATH := "user://shift_command_queue_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/tower.tscn")
const GOLD_MINE_SCENE: PackedScene = preload("res://scenes/resources/gold_mine.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	ResourceManager.reset_to_starting_values()

	_verify_shift_build_queue(failures)
	_verify_build_then_gather_queue(failures)
	_verify_queue_while_moving(failures)
	_verify_queue_while_gathering(failures)
	_verify_stop_clears_queue(failures)
	_verify_non_shift_replaces_queue(failures)
	_verify_invalid_build_skips_to_next(failures)
	_verify_worker_death_clears_queue(failures)
	_verify_multiple_workers_queue(failures)
	_verify_reservation_on_place(failures)

	var report: String
	if failures.is_empty():
		report = "PASS shift_command_queue\n"
	else:
		report = "FAIL shift_command_queue\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_shift_build_queue(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3.ZERO

	var farm_a: Building = _make_under_construction(FARM_SCENE, Vector3(4, 0, 0))
	var farm_b: Building = _make_under_construction(FARM_SCENE, Vector3(8, 0, 0))
	var barracks: Building = _make_under_construction(BARRACKS_SCENE, Vector3(12, 0, 0))

	worker.issue_order(UnitOrder.build(farm_a), false)
	worker.issue_order(UnitOrder.build(farm_b), true)
	worker.issue_order(UnitOrder.build(barracks), true)

	_expect(failures, "build queue: active first farm", worker.get_active_order() != null and worker.get_active_order().type == UnitOrder.Type.BUILD)
	_expect(failures, "build queue: two pending", worker.get_queued_orders().size() == 2)
	_expect(failures, "build queue: awaiting visual on queued", farm_b.is_awaiting_queued_builder())

	worker.notify_order_completed(UnitOrder.Type.BUILD)
	_expect(
		failures,
		"build queue: advanced to farm_b",
		worker.get_active_order() != null
		and worker.get_active_order().get_alive_target() == farm_b
	)
	_expect(failures, "build queue: one pending after advance", worker.get_queued_orders().size() == 1)

	worker.queue_free()
	farm_a.queue_free()
	farm_b.queue_free()
	barracks.queue_free()


func _verify_build_then_gather_queue(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3.ZERO

	var farm: Building = _make_under_construction(FARM_SCENE, Vector3(5, 0, 0))
	var barracks: Building = _make_under_construction(BARRACKS_SCENE, Vector3(9, 0, 0))
	var mine: GoldMine = GOLD_MINE_SCENE.instantiate() as GoldMine
	add_child(mine)
	mine.global_position = Vector3(20, 0, 0)

	worker.issue_order(UnitOrder.build(farm), false)
	worker.issue_order(UnitOrder.build(barracks), true)
	worker.issue_order(UnitOrder.gather(mine), true)

	var queued: Array[UnitOrder] = worker.get_queued_orders()
	_expect(failures, "build→gather: two queued", queued.size() == 2)
	_expect(
		failures,
		"build→gather: gather is last",
		queued.size() == 2 and queued[1].type == UnitOrder.Type.GATHER
	)

	worker.notify_order_completed(UnitOrder.Type.BUILD)
	_expect(
		failures,
		"build→gather: advanced to barracks",
		worker.get_active_order() != null
		and worker.get_active_order().get_alive_target() == barracks
	)
	worker.notify_order_completed(UnitOrder.Type.BUILD)
	_expect(
		failures,
		"build→gather: then gather forever",
		worker.get_active_order() != null
		and worker.get_active_order().type == UnitOrder.Type.GATHER
	)

	worker.queue_free()
	farm.queue_free()
	barracks.queue_free()
	mine.queue_free()


func _verify_queue_while_moving(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3.ZERO
	var farm: Building = _make_under_construction(FARM_SCENE, Vector3(6, 0, 0))

	worker.issue_order(UnitOrder.move(Vector3(3, 0, 0)), false)
	worker.issue_order(UnitOrder.build(farm), true)
	_expect(failures, "queue while moving: active move", worker.get_active_order().type == UnitOrder.Type.MOVE)
	_expect(failures, "queue while moving: build pending", worker.get_queued_orders().size() == 1)
	_expect(failures, "queue while moving: still has move target", worker.has_move_target)

	worker.queue_free()
	farm.queue_free()


func _verify_queue_while_gathering(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3.ZERO
	var mine: GoldMine = GOLD_MINE_SCENE.instantiate() as GoldMine
	add_child(mine)
	mine.global_position = Vector3(10, 0, 0)
	var farm: Building = _make_under_construction(FARM_SCENE, Vector3(4, 0, 0))

	worker.issue_order(UnitOrder.gather(mine), false)
	_expect(
		failures,
		"queue while gathering: active gather",
		worker.get_active_order() != null and worker.get_active_order().type == UnitOrder.Type.GATHER
	)

	worker.issue_order(UnitOrder.build(farm), true)
	_expect(
		failures,
		"queue while gathering: gather uninterrupted",
		worker.get_active_order().type == UnitOrder.Type.GATHER
	)
	_expect(failures, "queue while gathering: build appended", worker.get_queued_orders().size() == 1)

	worker.queue_free()
	mine.queue_free()
	farm.queue_free()


func _verify_stop_clears_queue(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	var farm: Building = _make_under_construction(FARM_SCENE, Vector3(3, 0, 0))
	worker.issue_order(UnitOrder.move(Vector3(2, 0, 0)), false)
	worker.issue_order(UnitOrder.build(farm), true)
	worker.issue_stop()
	_expect(failures, "stop clears active", worker.get_active_order() == null)
	_expect(failures, "stop clears queue", not worker.has_queued_orders())
	worker.queue_free()
	farm.queue_free()


func _verify_non_shift_replaces_queue(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	var farm: Building = _make_under_construction(FARM_SCENE, Vector3(3, 0, 0))
	var tower: Building = _make_under_construction(TOWER_SCENE, Vector3(7, 0, 0))
	worker.issue_order(UnitOrder.build(farm), false)
	worker.issue_order(UnitOrder.move(Vector3(9, 0, 0)), true)
	worker.issue_order(UnitOrder.build(tower), false)
	_expect(failures, "replace: queue empty", not worker.has_queued_orders())
	_expect(
		failures,
		"replace: active is tower",
		worker.get_active_order() != null
		and worker.get_active_order().get_alive_target() == tower
	)
	worker.queue_free()
	farm.queue_free()
	tower.queue_free()


func _verify_invalid_build_skips_to_next(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3.ZERO

	var farm_a: Building = _make_under_construction(FARM_SCENE, Vector3(2, 0, 0))
	var farm_b: Building = _make_under_construction(FARM_SCENE, Vector3(5, 0, 0))
	var farm_c: Building = _make_under_construction(FARM_SCENE, Vector3(8, 0, 0))

	worker.issue_order(UnitOrder.build(farm_a), false)
	worker.issue_order(UnitOrder.build(farm_b), true)
	worker.issue_order(UnitOrder.build(farm_c), true)

	farm_b.free()
	worker.notify_order_completed(UnitOrder.Type.BUILD)

	_expect(
		failures,
		"invalid skip: advanced to farm_c",
		worker.get_active_order() != null
		and worker.get_active_order().get_alive_target() == farm_c
	)

	worker.queue_free()
	farm_a.queue_free()
	farm_c.queue_free()


func _verify_worker_death_clears_queue(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	var farm: Building = _make_under_construction(FARM_SCENE, Vector3(4, 0, 0))
	worker.issue_order(UnitOrder.move(Vector3(1, 0, 0)), false)
	worker.issue_order(UnitOrder.build(farm), true)
	_expect(failures, "death prep: had queue", worker.has_queued_orders())

	worker._on_health_depleted()
	await get_tree().process_frame
	_expect(failures, "death: worker freed", not is_instance_valid(worker))
	# Foundation remains for other workers (no refund leak from queue clear alone).
	_expect(failures, "death: foundation remains", is_instance_valid(farm))
	farm.queue_free()


func _verify_multiple_workers_queue(failures: PackedStringArray) -> void:
	var worker_a: Worker = WORKER_SCENE.instantiate() as Worker
	var worker_b: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker_a)
	add_child(worker_b)
	var farm: Building = _make_under_construction(FARM_SCENE, Vector3(4, 0, 0))
	var tower: Building = _make_under_construction(TOWER_SCENE, Vector3(8, 0, 0))

	worker_a.issue_order(UnitOrder.build(farm), false)
	worker_b.issue_order(UnitOrder.build(farm), false)
	worker_a.issue_order(UnitOrder.build(tower), true)
	worker_b.issue_order(UnitOrder.build(tower), true)

	_expect(failures, "multi: worker_a queued", worker_a.has_queued_orders())
	_expect(failures, "multi: worker_b queued", worker_b.has_queued_orders())

	worker_a.queue_free()
	worker_b.queue_free()
	farm.queue_free()
	tower.queue_free()


func _verify_reservation_on_place(failures: PackedStringArray) -> void:
	ResourceManager.reset_to_starting_values()
	var start_gold: int = ResourceManager.gold
	var start_wood: int = ResourceManager.wood
	_expect(failures, "reservation: can afford farm", ResourceManager.can_afford(BuildingStats.FARM_GOLD_COST, BuildingStats.FARM_WOOD_COST))

	var spent: bool = ResourceManager.try_spend(BuildingStats.FARM_GOLD_COST, BuildingStats.FARM_WOOD_COST)
	_expect(failures, "reservation: spend ok", spent)
	_expect(
		failures,
		"reservation: gold deducted once",
		ResourceManager.gold == start_gold - BuildingStats.FARM_GOLD_COST
	)
	_expect(
		failures,
		"reservation: wood deducted once",
		ResourceManager.wood == start_wood - BuildingStats.FARM_WOOD_COST
	)

	# Soft reserve + spend release path (no double-spend).
	ResourceManager.reserve_resources(10, 5)
	_expect(failures, "reservation: soft hold reduces spendable", ResourceManager.get_spendable_gold() == ResourceManager.gold - 10)
	ResourceManager.release_reservation(10, 5)
	_expect(failures, "reservation: release restores spendable", ResourceManager.get_spendable_gold() == ResourceManager.gold)

	ResourceManager.reset_to_starting_values()
	_expect(failures, "reservation: match reset clears soft holds", ResourceManager.get_spendable_gold() == ResourceManager.gold)


func _make_under_construction(scene: PackedScene, position: Vector3) -> Building:
	var building: Building = scene.instantiate() as Building
	add_child(building)
	building.global_position = position
	building.set_construction_cost(10, 10, false)
	building.start_under_construction()
	building.setup_construction(5.0)
	building.set_awaiting_queued_builder(true)
	return building


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
