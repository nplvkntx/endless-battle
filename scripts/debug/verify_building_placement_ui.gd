extends Node

## Headless: switching build-UI placement must not drop the previous building.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_building_placement_ui.tscn

const REPORT_PATH := "user://building_placement_ui_verify_result.txt"
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const BUILD_MANAGER_SCRIPT: Script = preload("res://scripts/systems/build_manager.gd")


class SelectionStub extends Node:
	var selected_units: Array = []
	var selected_building: Variant = null


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_building_placement_ui: start")
	ConstructionReservations.reset_match_state()
	ResourceManager.reset_to_starting_values()

	_verify_switch_farm_to_barracks_does_not_place(failures)
	_verify_switch_farm_to_wall(failures)
	_verify_same_button_keeps_placement(failures)

	var report: String
	if failures.is_empty():
		report = "PASS building_placement_ui\n"
	else:
		report = "FAIL building_placement_ui\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- %s" % label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)


func _make_harness() -> Dictionary:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-55.0), 0.0, 0.0)),
		Vector3(0, 22, 0)
	)
	world.add_child(camera)

	var selection := SelectionStub.new()
	selection.name = "SelectionManager"
	world.add_child(selection)

	var build_manager: Node = Node.new()
	build_manager.name = "BuildManager"
	build_manager.set_script(BUILD_MANAGER_SCRIPT)
	world.add_child(build_manager)
	build_manager.set("camera_path", NodePath("../Camera3D"))
	build_manager.set("buildings_parent_path", NodePath(".."))
	build_manager.set("selection_manager_path", NodePath("../SelectionManager"))

	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	world.add_child(worker)
	worker.global_position = Vector3.ZERO
	selection.selected_units = [worker]

	return {
		"world": world,
		"build_manager": build_manager,
		"selection": selection,
	}


func _free_harness(harness: Dictionary) -> void:
	var world: Node = harness["world"] as Node
	if world != null and is_instance_valid(world):
		world.queue_free()


func _count_farms(world: Node) -> int:
	var count: int = 0
	for child: Node in world.get_children():
		if child is Farm and is_instance_valid(child) and not child.is_queued_for_deletion():
			count += 1
	return count


func _count_barracks(world: Node) -> int:
	var count: int = 0
	for child: Node in world.get_children():
		if child is Barracks and is_instance_valid(child) and not child.is_queued_for_deletion():
			count += 1
	return count


func _verify_switch_farm_to_barracks_does_not_place(failures: PackedStringArray) -> void:
	print("verify: farm → barracks UI switch")
	var harness: Dictionary = _make_harness()
	var world: Node = harness["world"] as Node
	var build_manager: Node = harness["build_manager"] as Node

	build_manager.start_farm_placement()
	_expect(
		failures,
		"farm placement starts",
		build_manager.get("_active_placement") == BUILD_MANAGER_SCRIPT.PLACEMENT_FARM
	)
	_expect(failures, "farm ghost present", _count_farms(world) == 1)

	build_manager.start_barracks_placement()
	_expect(
		failures,
		"active placement is barracks",
		build_manager.get("_active_placement") == BUILD_MANAGER_SCRIPT.PLACEMENT_BARRACKS
	)
	_expect(failures, "farm ghost cancelled on switch", _count_farms(world) == 0)
	_expect(failures, "barracks ghost present", _count_barracks(world) == 1)
	_expect(
		failures,
		"switched barracks is still a ghost (not constructing)",
		_is_ghost_only(build_manager, world)
	)

	_free_harness(harness)


func _is_ghost_only(build_manager: Node, world: Node) -> bool:
	var ghost: Node = build_manager.get("_placement_ghost") as Node
	if ghost == null or not is_instance_valid(ghost):
		return false
	if ghost is Building:
		var building := ghost as Building
		if building.building_state == Building.STATE_UNDER_CONSTRUCTION:
			return false
	for child: Node in world.get_children():
		if child is Building and child != ghost and not child.is_queued_for_deletion():
			if (child as Building).building_state == Building.STATE_UNDER_CONSTRUCTION:
				return false
	return true


func _verify_switch_farm_to_wall(failures: PackedStringArray) -> void:
	print("verify: farm → wall UI switch")
	var harness: Dictionary = _make_harness()
	var world: Node = harness["world"] as Node
	var build_manager: Node = harness["build_manager"] as Node

	build_manager.start_farm_placement()
	build_manager.start_wall_segment_placement()
	_expect(
		failures,
		"active placement is wall",
		build_manager.get("_active_placement") == BUILD_MANAGER_SCRIPT.PLACEMENT_WALL_SEGMENT
	)
	_expect(failures, "farm ghost cancelled for wall", _count_farms(world) == 0)

	_free_harness(harness)


func _verify_same_button_keeps_placement(failures: PackedStringArray) -> void:
	print("verify: same build button keeps placement")
	var harness: Dictionary = _make_harness()
	var world: Node = harness["world"] as Node
	var build_manager: Node = harness["build_manager"] as Node

	build_manager.start_farm_placement()
	var ghost_before: Node = build_manager.get("_placement_ghost") as Node
	build_manager.start_farm_placement()
	_expect(
		failures,
		"same-type click keeps farm placement",
		build_manager.get("_active_placement") == BUILD_MANAGER_SCRIPT.PLACEMENT_FARM
	)
	_expect(
		failures,
		"same-type click does not recreate ghost",
		build_manager.get("_placement_ghost") == ghost_before
	)
	_expect(failures, "same-type click does not place farm", _count_farms(world) == 1)

	_free_harness(harness)
