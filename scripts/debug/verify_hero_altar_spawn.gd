extends Node

## Hero Altar spawn must land on a grid-walkable, physics-clear exit outside the
## altar footprint/clearance, then actually leave via custom RTS movement.
## Godot_v4.7-stable_win64.exe --headless --path <project> --scene res://scenes/debug/verify_hero_altar_spawn.tscn

const REPORT_PATH := "user://hero_altar_spawn_verify_result.txt"
const ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const BARRACKS_SCENE: PackedScene = preload("res://scenes/buildings/barracks.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/resources/tree.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const SPAWN_LOOPS := 6
const MOVE_TIMEOUT_SEC := 20.0
const MOVE_ARRIVE_RADIUS := 1.8
const DEST_OFFSET := Vector3(0.0, 0.0, -14.0)
const ALTAR_CLEAR_DISTANCE := 5.0


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_hero_altar_spawn: start")

	_expect(failures, "autoload PlayerRouteNavigation present", PlayerRouteNavigation != null)

	await _test_grid_only_walkable_is_insufficient_with_trees(failures)
	await _test_repeated_enemy_hero_exit_reaches_destination(failures)
	await _test_player_hero_exit_reaches_destination(failures)
	await _test_barracks_pikeman_exit_compare(failures)

	var report: String
	if failures.is_empty():
		report = "PASS hero_altar_spawn\n"
	else:
		report = "FAIL hero_altar_spawn\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


## Prior false-positive: preferred/+X cell walkable on custom grid while trees
## (WORLD physics, off-grid) trap the Hero. Spawn claim must reject that cell.
func _test_grid_only_walkable_is_insufficient_with_trees(failures: PackedStringArray) -> void:
	print("verify: trees on old +X exit make grid-only spawn invalid")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var altar: HeroAltar = ALTAR_SCENE.instantiate() as HeroAltar
	add_child(altar)
	altar.global_position = Vector3(0.0, 1.0, 0.0)
	altar.set_completed()

	var trees: Array[Node] = []
	for i: int in 5:
		for j: int in 3:
			var tree: Node3D = TREE_SCENE.instantiate() as Node3D
			add_child(tree)
			tree.global_position = Vector3(2.5 + float(i) * 1.1, 0.0, -1.2 + float(j) * 1.1)
			trees.append(tree)

	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(altar)

	var old_plus_x: Vector3 = altar.global_position + Vector3(3.0, -0.5, 0.0)
	_expect(
		failures,
		"old +X offset remains grid-walkable beside trees (false-positive cell)",
		PlayerRouteNavigation.is_world_walkable(old_plus_x)
	)
	_expect(
		failures,
		"old +X offset is physically blocked by trees",
		not _physics_clear_at(old_plus_x, altar)
	)

	var claimed: Vector3 = altar._claim_hero_spawn_position()
	_expect(
		failures,
		"claim rejects tree-trapped grid-walkable cell",
		_horizontal_distance(claimed, old_plus_x) > 0.75
	)
	_expect(
		failures,
		"claimed exit is grid walkable",
		PlayerRouteNavigation.is_world_walkable(claimed)
	)
	_expect(
		failures,
		"claimed exit is physics clear",
		_physics_clear_at(claimed, altar)
	)
	_expect(
		failures,
		"claimed exit outside altar footprint",
		not altar.is_position_inside_footprint(claimed)
	)

	for tree: Node in trees:
		tree.queue_free()
	altar.queue_free()
	await get_tree().process_frame


func _test_repeated_enemy_hero_exit_reaches_destination(failures: PackedStringArray) -> void:
	print("verify: repeated enemy Hero exits clear altar and reach destination")
	for loop_index: int in SPAWN_LOOPS:
		PlayerRouteNavigation.clear_all()
		_clear_hero_store()
		await get_tree().process_frame

		var altar: HeroAltar = ALTAR_SCENE.instantiate() as HeroAltar
		add_child(altar)
		altar.global_position = Vector3(float(loop_index) * 0.15, 1.0, float(loop_index) * 0.1)
		altar.set_completed()

		var neighbor: Building = BARRACKS_SCENE.instantiate() as Building
		add_child(neighbor)
		neighbor.global_position = altar.global_position + Vector3(6.0, -1.0, 0.0)
		neighbor.set_completed()

		# Forest on world +X — the previous fixed offset direction.
		var trees: Array[Node] = []
		for i: int in 4:
			for j: int in 3:
				var tree: Node3D = TREE_SCENE.instantiate() as Node3D
				add_child(tree)
				tree.global_position = (
					altar.global_position
					+ Vector3(2.4 + float(i) * 1.05, -1.0, -1.1 + float(j) * 1.05)
				)
				trees.append(tree)

		await get_tree().process_frame
		await get_tree().process_frame
		PlayerRouteNavigation.ensure_grid_ready()
		PlayerRouteNavigation.register_static_obstacle(altar)
		PlayerRouteNavigation.register_static_obstacle(neighbor)

		var before_ids: Dictionary = _child_unit_instance_ids()
		altar._training_kit_id = HeroCatalog.KIT_SHADOW_ASSASSIN
		altar._spawn_enemy_hero()
		await get_tree().process_frame
		await get_tree().physics_frame

		var hero: Hero = _find_new_hero(before_ids)
		_expect(failures, "enemy hero loop %d spawned" % loop_index, hero != null)
		if hero == null:
			_free_nodes(trees, altar, neighbor)
			await get_tree().process_frame
			continue

		_expect(
			failures,
			"enemy hero loop %d spawn walkable" % loop_index,
			PlayerRouteNavigation.is_world_walkable(hero.global_position)
		)
		_expect(
			failures,
			"enemy hero loop %d spawn physics clear" % loop_index,
			_physics_clear_for_body(hero)
		)
		_expect(
			failures,
			"enemy hero loop %d outside altar footprint" % loop_index,
			not altar.is_position_inside_footprint(hero.global_position)
		)

		var destination: Vector3 = PlayerRouteNavigation.nearest_walkable_world(
			altar.global_position + DEST_OFFSET
		)
		# Destination must itself be physics-clear enough to approach; snap further if needed.
		if not _physics_clear_at(destination, altar):
			destination = PlayerRouteNavigation.nearest_walkable_world(
				altar.global_position + Vector3(0.0, 0.0, -18.0)
			)

		var start: Vector3 = hero.global_position
		var route_preview: PackedVector3Array = PlayerRouteNavigation.grid.find_path(
			start,
			destination
		)
		_expect(
			failures,
			"enemy hero loop %d exit path exists" % loop_index,
			not route_preview.is_empty()
		)

		var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			[hero],
			destination,
			&"move",
			false,
			&"player"
		)
		_expect(failures, "enemy hero loop %d move handled" % loop_index, result.get("handled", false))
		_expect(
			failures,
			"enemy hero loop %d route valid" % loop_index,
			result.get("route_valid", false)
		)
		_expect(
			failures,
			"enemy hero loop %d CUSTOM backend" % loop_index,
			hero.get_movement_backend_label() == "CUSTOM"
		)

		var moved := false
		var cleared_altar := false
		var reached := false
		var elapsed := 0.0
		while elapsed < MOVE_TIMEOUT_SEC:
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
			if not NodeSafety.is_alive_node(hero):
				break
			var disp: float = _horizontal_distance(hero.global_position, start)
			if disp >= 2.0:
				moved = true
			if _horizontal_distance(hero.global_position, altar.global_position) >= ALTAR_CLEAR_DISTANCE:
				cleared_altar = true
			if _horizontal_distance(hero.global_position, destination) <= MOVE_ARRIVE_RADIUS:
				reached = true
				moved = true
				cleared_altar = true
				break
			if elapsed > 6.0 and disp < 0.08:
				break

		_expect(failures, "enemy hero loop %d first step / displacement" % loop_index, moved)
		_expect(failures, "enemy hero loop %d cleared altar" % loop_index, cleared_altar)
		_expect(failures, "enemy hero loop %d reached destination" % loop_index, reached)

		if NodeSafety.is_alive_node(hero):
			hero.queue_free()
		_free_nodes(trees, altar, neighbor)
		await get_tree().process_frame


func _test_player_hero_exit_reaches_destination(failures: PackedStringArray) -> void:
	print("verify: player Hero Altar exit reaches destination")
	PlayerRouteNavigation.clear_all()
	_clear_hero_store()
	await get_tree().process_frame

	var altar: HeroAltar = ALTAR_SCENE.instantiate() as HeroAltar
	add_child(altar)
	altar.global_position = Vector3(2.0, 1.0, 2.0)
	altar.set_completed()

	var neighbor: Building = BARRACKS_SCENE.instantiate() as Building
	add_child(neighbor)
	neighbor.global_position = altar.global_position + Vector3(6.0, -1.0, 0.0)
	neighbor.set_completed()

	var trees: Array[Node] = []
	for i: int in 4:
		for j: int in 3:
			var tree: Node3D = TREE_SCENE.instantiate() as Node3D
			add_child(tree)
			tree.global_position = (
				altar.global_position + Vector3(2.4 + float(i) * 1.05, -1.0, -1.1 + float(j) * 1.05)
			)
			trees.append(tree)

	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(altar)
	PlayerRouteNavigation.register_static_obstacle(neighbor)

	var before_ids: Dictionary = _child_unit_instance_ids()
	altar._training_kit_id = HeroCatalog.KIT_PALADIN
	altar._spawn_hero()
	await get_tree().process_frame
	await get_tree().physics_frame

	var hero: Hero = _find_new_hero(before_ids)
	_expect(failures, "player hero spawned", hero != null)
	if hero != null:
		_expect(
			failures,
			"player hero spawn walkable",
			PlayerRouteNavigation.is_world_walkable(hero.global_position)
		)
		_expect(failures, "player hero spawn physics clear", _physics_clear_for_body(hero))
		var destination: Vector3 = PlayerRouteNavigation.nearest_walkable_world(
			altar.global_position + DEST_OFFSET
		)
		var start: Vector3 = hero.global_position
		var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			[hero],
			destination,
			&"move",
			false,
			&"player"
		)
		_expect(failures, "player hero move handled", result.get("handled", false))
		var reached := false
		var cleared := false
		var elapsed := 0.0
		while elapsed < MOVE_TIMEOUT_SEC:
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
			if not NodeSafety.is_alive_node(hero):
				break
			if _horizontal_distance(hero.global_position, altar.global_position) >= ALTAR_CLEAR_DISTANCE:
				cleared = true
			if _horizontal_distance(hero.global_position, destination) <= MOVE_ARRIVE_RADIUS:
				reached = true
				break
			if elapsed > 6.0 and _horizontal_distance(hero.global_position, start) < 0.08:
				break
		_expect(failures, "player hero cleared altar", cleared)
		_expect(failures, "player hero reached destination", reached)
		if NodeSafety.is_alive_node(hero):
			hero.queue_free()

	_free_nodes(trees, altar, neighbor)
	await get_tree().process_frame


func _test_barracks_pikeman_exit_compare(failures: PackedStringArray) -> void:
	print("verify: Barracks pikeman exit still works in same environment")
	PlayerRouteNavigation.clear_all()
	await get_tree().process_frame

	var barracks: Barracks = BARRACKS_SCENE.instantiate() as Barracks
	add_child(barracks)
	barracks.global_position = Vector3(-12.0, 0.0, 0.0)
	barracks.set_completed()
	barracks.set_rally_point(barracks.global_position + Vector3(0.0, 0.0, -10.0))

	# Trees on +X of barracks — pikeman exits -Z, must still leave.
	var trees: Array[Node] = []
	for i: int in 4:
		var tree: Node3D = TREE_SCENE.instantiate() as Node3D
		add_child(tree)
		tree.global_position = barracks.global_position + Vector3(3.0 + float(i) * 1.0, 0.0, 0.0)
		trees.append(tree)

	await get_tree().process_frame
	await get_tree().process_frame
	PlayerRouteNavigation.ensure_grid_ready()
	PlayerRouteNavigation.register_static_obstacle(barracks)

	var before_ids: Dictionary = _child_unit_instance_ids()
	barracks._spawn_trained_unit(SPEARMAN_SCENE, barracks.spearman_spawn_offset)
	await get_tree().process_frame
	await get_tree().physics_frame
	var unit: Unit = _find_new_non_hero_unit(before_ids)
	_expect(failures, "pikeman spawned", unit != null)
	if unit != null:
		_expect(
			failures,
			"pikeman spawn/rally walkable",
			PlayerRouteNavigation.is_world_walkable(unit.global_position)
		)
		var destination: Vector3 = PlayerRouteNavigation.nearest_walkable_world(
			barracks.global_position + DEST_OFFSET
		)
		var start: Vector3 = unit.global_position
		if not unit.has_custom_rts_route():
			PlayerRouteNavigation.issue_player_group_command(
				[unit],
				destination,
				&"move",
				false,
				&"player"
			)
		var moved := false
		var elapsed := 0.0
		while elapsed < MOVE_TIMEOUT_SEC:
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
			if not NodeSafety.is_alive_node(unit):
				break
			if (
				_horizontal_distance(unit.global_position, start) >= 2.0
				or _horizontal_distance(unit.global_position, destination) <= MOVE_ARRIVE_RADIUS
			):
				moved = true
				break
			if elapsed > 6.0 and _horizontal_distance(unit.global_position, start) < 0.08:
				break
		_expect(failures, "pikeman left spawn", moved)
		unit.queue_free()

	_free_nodes(trees, barracks, null)
	await get_tree().process_frame


func _physics_clear_at(world: Vector3, exclude_building: Building) -> bool:
	var space: PhysicsDirectSpaceState3D = get_viewport().find_world_3d().direct_space_state
	if space == null:
		return true
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 1.2)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.transform = Transform3D(Basis.IDENTITY, world)
	params.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	if exclude_building != null and is_instance_valid(exclude_building):
		params.exclude = [exclude_building.get_rid()]
	return space.intersect_shape(params, 1).is_empty()


func _physics_clear_for_body(body: CharacterBody3D) -> bool:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var shape_node: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if space == null or shape_node == null or shape_node.shape == null:
		return true
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform
	params.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK
	params.exclude = [body.get_rid()]
	return space.intersect_shape(params, 1).is_empty()


func _clear_hero_store() -> void:
	var living_player: Hero = HeroProgressionStore.get_living_hero(false)
	if living_player != null:
		living_player.queue_free()
	var living_enemy: Hero = HeroProgressionStore.get_living_hero(true)
	if living_enemy != null:
		living_enemy.queue_free()
	HeroProgressionStore.clear()


func _child_unit_instance_ids() -> Dictionary:
	var ids: Dictionary = {}
	for i: int in get_child_count():
		var child: Node = get_child(i)
		if child is Unit:
			ids[child.get_instance_id()] = true
	return ids


func _find_new_hero(before_ids: Dictionary) -> Hero:
	for i: int in get_child_count():
		var child: Node = get_child(i)
		if child is Hero and not before_ids.has(child.get_instance_id()):
			return child as Hero
	return null


func _find_new_non_hero_unit(before_ids: Dictionary) -> Unit:
	for i: int in get_child_count():
		var child: Node = get_child(i)
		if child is Unit and not (child is Hero) and not before_ids.has(child.get_instance_id()):
			return child as Unit
	return null


func _free_nodes(trees: Array[Node], a: Node, b: Node) -> void:
	for tree: Node in trees:
		if is_instance_valid(tree):
			tree.queue_free()
	if a != null and is_instance_valid(a):
		a.queue_free()
	if b != null and is_instance_valid(b):
		b.queue_free()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if condition:
		return
	failures.append(label)
	print("FAIL: ", label)
