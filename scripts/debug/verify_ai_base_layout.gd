extends Node

## Headless verification for compact AI base layout placement.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ai_base_layout.tscn

const REPORT_PATH := "user://ai_base_layout_verify_result.txt"
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const BLACKSMITH_SCENE: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/buildings/shop.tscn")
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const STABLE_SCENE: PackedScene = preload("res://scenes/buildings/stable.tscn")
const ACADEMY_SCENE: PackedScene = preload("res://scenes/buildings/academy.tscn")
const ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const COMMAND_CENTER_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")
const GOLD_MINE_SCENE: PackedScene = preload("res://scenes/resources/gold_mine.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	ConstructionReservations.reset_match_state()
	EnemyBuildPlacement.set_debug_placement_logs(true)

	print("verify_ai_base_layout: start")
	_verify_no_overlaps_and_determinism(failures)
	_verify_farms_form_compact_rows(failures)
	_verify_production_clusters_near_town_hall(failures)
	_verify_resource_routes_kept_clear(failures)
	_verify_failed_placement_recovers(failures)
	_verify_tier_expansion_stays_usable(failures)

	EnemyBuildPlacement.set_debug_placement_logs(false)

	var report: String
	if failures.is_empty():
		report = "PASS ai_base_layout\n"
	else:
		report = "FAIL ai_base_layout\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_no_overlaps_and_determinism(failures: PackedStringArray) -> void:
	print("verify: overlaps + determinism")
	var root := Node3D.new()
	add_child(root)

	var town_hall: Building = _spawn_completed(root, &"command_center", Vector3(20.0, 0.0, 20.0))
	var buildings: Array[Node3D] = [town_hall]
	var types: Array[StringName] = [
		&"barracks", &"farm", &"blacksmith", &"farm", &"shop", &"farm", &"hero_altar",
	]
	var placed: Array[Dictionary] = []

	for building_type: StringName in types:
		var pos_a: Vector3 = EnemyBuildPlacement.find_position(
			town_hall.global_position,
			building_type,
			buildings,
			false,
			root,
			RID()
		)
		var pos_b: Vector3 = EnemyBuildPlacement.find_position(
			town_hall.global_position,
			building_type,
			buildings,
			false,
			root,
			RID()
		)
		_expect(
			failures,
			"determinism: %s repeats" % String(building_type),
			pos_a.is_finite() and pos_a.is_equal_approx(pos_b)
		)
		_expect(failures, "placeable: %s found" % String(building_type), pos_a.is_finite())
		if not pos_a.is_finite():
			continue

		var footprint: Vector2 = EnemyBuildPlacement.get_footprint(building_type)
		for previous: Dictionary in placed:
			var overlaps: bool = _footprints_overlap(
				pos_a,
				footprint,
				previous["pos"],
				previous["footprint"]
			)
			_expect(failures, "no overlap: %s" % String(building_type), not overlaps)

		var ghost: Building = _spawn_completed(root, building_type, pos_a)
		buildings.append(ghost)
		placed.append({"pos": pos_a, "footprint": footprint})

	root.free()


func _verify_farms_form_compact_rows(failures: PackedStringArray) -> void:
	print("verify: farm rows/clusters")
	var root := Node3D.new()
	add_child(root)

	var town_hall: Building = _spawn_completed(
		root,
		&"command_center",
		Vector3(-15.0, 0.0, -15.0)
	)
	var buildings: Array[Node3D] = [town_hall]
	var farm_positions: Array[Vector3] = []
	for _i: int in 5:
		var pos: Vector3 = EnemyBuildPlacement.find_position(
			town_hall.global_position,
			&"farm",
			buildings,
			false,
			root,
			RID()
		)
		_expect(failures, "farm placeable", pos.is_finite())
		if not pos.is_finite():
			break

		buildings.append(_spawn_completed(root, &"farm", pos))
		farm_positions.append(pos)

	if farm_positions.size() >= 3:
		var aligned_pairs: int = 0
		var close_pairs: int = 0
		for i: int in farm_positions.size():
			for j: int in range(i + 1, farm_positions.size()):
				var a: Vector3 = farm_positions[i]
				var b: Vector3 = farm_positions[j]
				var dx: float = absf(a.x - b.x)
				var dz: float = absf(a.z - b.z)
				if dx <= 0.6 or dz <= 0.6:
					aligned_pairs += 1
				if a.distance_to(b) <= 6.5:
					close_pairs += 1

		_expect(failures, "farms: at least one aligned row/col pair", aligned_pairs >= 1)
		_expect(failures, "farms: multiple farms stay clustered", close_pairs >= 2)

		var max_dist_from_th: float = 0.0
		for pos: Vector3 in farm_positions:
			max_dist_from_th = maxf(max_dist_from_th, _horizontal(pos, town_hall.global_position))
		_expect(failures, "farms: stay within compact outer band", max_dist_from_th <= 24.0)

	root.free()


func _verify_production_clusters_near_town_hall(failures: PackedStringArray) -> void:
	print("verify: production cluster near TH")
	var root := Node3D.new()
	add_child(root)

	var town_hall: Building = _spawn_completed(root, &"command_center", Vector3.ZERO)
	var buildings: Array[Node3D] = [town_hall]
	var production_types: Array[StringName] = [
		&"barracks", &"blacksmith", &"shop", &"hero_altar", &"stable", &"academy",
	]
	var positions: Array[Vector3] = []

	for building_type: StringName in production_types:
		var pos: Vector3 = EnemyBuildPlacement.find_position(
			town_hall.global_position,
			building_type,
			buildings,
			false,
			root,
			RID()
		)
		_expect(failures, "production placeable: %s" % String(building_type), pos.is_finite())
		if not pos.is_finite():
			continue

		var dist: float = _horizontal(pos, town_hall.global_position)
		_expect(
			failures,
			"production near TH: %s (dist=%.1f)" % [String(building_type), dist],
			dist <= 16.0
		)
		positions.append(pos)
		buildings.append(_spawn_completed(root, building_type, pos))

	if positions.size() >= 3:
		var pairwise_close: int = 0
		for i: int in positions.size():
			for j: int in range(i + 1, positions.size()):
				if positions[i].distance_to(positions[j]) <= 12.0:
					pairwise_close += 1
		_expect(failures, "production buildings form a compact group", pairwise_close >= 3)

	root.free()


func _verify_resource_routes_kept_clear(failures: PackedStringArray) -> void:
	print("verify: gold/tree routes stay clear")
	var root := Node3D.new()
	add_child(root)

	var map_resources := Node3D.new()
	map_resources.name = "MapResources"
	root.add_child(map_resources)

	var town_hall: Building = _spawn_completed(
		root,
		&"command_center",
		Vector3(10.0, 0.0, 10.0)
	)
	var mine: Node3D = GOLD_MINE_SCENE.instantiate() as Node3D
	map_resources.add_child(mine)
	mine.global_position = Vector3(10.0, 0.5, 22.0)

	var buildings: Array[Node3D] = [town_hall]
	for building_type: StringName in [&"barracks", &"farm", &"blacksmith", &"farm"]:
		var pos: Vector3 = EnemyBuildPlacement.find_position(
			town_hall.global_position,
			building_type,
			buildings,
			false,
			root,
			RID()
		)
		_expect(failures, "route test placeable: %s" % String(building_type), pos.is_finite())
		if not pos.is_finite():
			continue

		var corridor_dist: float = _point_to_segment_distance(
			Vector2(pos.x, pos.z),
			Vector2(town_hall.global_position.x, town_hall.global_position.z),
			Vector2(mine.global_position.x, mine.global_position.z)
		)
		var footprint: Vector2 = EnemyBuildPlacement.get_footprint(building_type)
		var min_corridor: float = (
			EnemyBuildPlacement.DROPOFF_PATH_WIDTH + maxf(footprint.x, footprint.y) * 0.15
		)
		_expect(
			failures,
			"route clear for %s" % String(building_type),
			corridor_dist >= min_corridor * 0.95
		)
		buildings.append(_spawn_completed(root, building_type, pos))

	root.free()


func _verify_failed_placement_recovers(failures: PackedStringArray) -> void:
	print("verify: failed placement recovers to another compact spot")
	var root := Node3D.new()
	add_child(root)

	var town_hall: Building = _spawn_completed(
		root,
		&"command_center",
		Vector3(-20.0, 0.0, 20.0)
	)
	var buildings: Array[Node3D] = [town_hall]
	for _i: int in 8:
		var farm_pos: Vector3 = EnemyBuildPlacement.find_position(
			town_hall.global_position,
			&"farm",
			buildings,
			false,
			root,
			RID()
		)
		if not farm_pos.is_finite():
			break
		buildings.append(_spawn_completed(root, &"farm", farm_pos))

	var barracks_pos: Vector3 = EnemyBuildPlacement.find_position(
		town_hall.global_position,
		&"barracks",
		buildings,
		false,
		root,
		RID()
	)
	_expect(
		failures,
		"recovery: barracks still placeable after farm saturation",
		barracks_pos.is_finite()
	)
	if barracks_pos.is_finite():
		_expect(
			failures,
			"recovery: barracks remains near base",
			_horizontal(barracks_pos, town_hall.global_position) <= 28.0
		)

	root.free()


func _verify_tier_expansion_stays_usable(failures: PackedStringArray) -> void:
	print("verify: tier 2/3 style expansion remains usable")
	var root := Node3D.new()
	add_child(root)

	var town_hall: Building = _spawn_completed(
		root,
		&"command_center",
		Vector3(25.0, 0.0, -25.0)
	)
	var buildings: Array[Node3D] = [town_hall]
	var late_types: Array[StringName] = [
		&"farm", &"barracks", &"farm", &"blacksmith", &"shop", &"hero_altar",
		&"farm", &"stable", &"artillery_depot", &"academy", &"farm", &"barracks",
	]

	for building_type: StringName in late_types:
		var pos: Vector3 = EnemyBuildPlacement.find_position(
			town_hall.global_position,
			building_type,
			buildings,
			false,
			root,
			RID()
		)
		_expect(failures, "late expand placeable: %s" % String(building_type), pos.is_finite())
		if not pos.is_finite():
			continue

		_expect(
			failures,
			"late expand not soft-locked far away: %s" % String(building_type),
			_horizontal(pos, town_hall.global_position) <= 32.0
		)
		buildings.append(_spawn_completed(root, building_type, pos))

	var follow_up: Vector3 = EnemyBuildPlacement.find_position(
		town_hall.global_position,
		&"farm",
		buildings,
		false,
		root,
		RID()
	)
	if follow_up.is_finite():
		var min_clearance: float = (
			maxf(EnemyBuildPlacement.COMMAND_CENTER_SIZE.x, EnemyBuildPlacement.COMMAND_CENTER_SIZE.y)
			* 0.5
			+ maxf(EnemyBuildPlacement.FARM_SIZE.x, EnemyBuildPlacement.FARM_SIZE.y) * 0.5
			+ EnemyBuildPlacement.BUILDING_PADDING
			+ EnemyBuildPlacement.TH_ACCESS_LANE
		)
		_expect(
			failures,
			"TH access clearance preserved",
			_horizontal(follow_up, town_hall.global_position) >= min_clearance - 0.05
		)

	root.free()


func _spawn_completed(parent: Node, building_type: StringName, position: Vector3) -> Building:
	var building: Building = _instantiate_type(building_type)
	parent.add_child(building)
	building.global_position = Vector3(
		position.x,
		EnemyBuildPlacement.get_ground_y(building_type),
		position.z
	)
	building.set_completed()
	return building


func _instantiate_type(building_type: StringName) -> Building:
	match building_type:
		&"farm":
			return FARM_SCENE.instantiate() as Building
		&"barracks":
			return BARRACKS_SCENE.instantiate() as Building
		&"blacksmith":
			return BLACKSMITH_SCENE.instantiate() as Building
		&"shop":
			return SHOP_SCENE.instantiate() as Building
		&"hero_altar":
			return HERO_ALTAR_SCENE.instantiate() as Building
		&"stable":
			return STABLE_SCENE.instantiate() as Building
		&"academy":
			return ACADEMY_SCENE.instantiate() as Building
		&"artillery_depot":
			return ARTILLERY_DEPOT_SCENE.instantiate() as Building
		&"command_center":
			return COMMAND_CENTER_SCENE.instantiate() as Building
		_:
			return FARM_SCENE.instantiate() as Building


func _footprints_overlap(
	pos_a: Vector3,
	size_a: Vector2,
	pos_b: Vector3,
	size_b: Vector2
) -> bool:
	var delta_x: float = absf(pos_a.x - pos_b.x)
	var delta_z: float = absf(pos_a.z - pos_b.z)
	var min_x: float = (size_a.x + size_b.x) * 0.5 + EnemyBuildPlacement.BUILDING_PADDING
	var min_z: float = (size_a.y + size_b.y) * 0.5 + EnemyBuildPlacement.BUILDING_PADDING
	return delta_x < min_x and delta_z < min_z


func _horizontal(a: Vector3, b: Vector3) -> float:
	var offset: Vector3 = a - b
	offset.y = 0.0
	return offset.length()


func _point_to_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment: Vector2 = b - a
	var length_sq: float = segment.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(a + segment * t)


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if condition:
		print("  OK  ", label)
	else:
		print("  FAIL", label)
		failures.append(label)
