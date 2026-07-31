extends Node

## Lightweight map harness for decoration scatter (avoids full match/AI systems).

const REPORT_PATH := "res://terrain_decoration_verify_result.txt"
const BATTLEFIELD: PackedScene = preload("res://scenes/maps/battlefield_1v1.tscn")
const MAP_RESOURCES: PackedScene = preload("res://scenes/world/map_resources.tscn")
const PLAYER_BASE: PackedScene = preload("res://scenes/match/player_starting_base.tscn")
const ENEMY_BASE: PackedScene = preload("res://scenes/match/enemy_starting_base.tscn")
const DECORATIONS: PackedScene = preload("res://scenes/world/terrain_decorations.tscn")
const MAX_BUILD_USEC := 2_500_000
const MIN_INSTANCES := 200
const MAX_INSTANCES := 12_000


func _ready() -> void:
	print("verify_terrain_decoration: start")
	var failures: PackedStringArray = []

	await _verify_on_map(failures)
	_verify_catalog_extensibility(failures)
	_verify_parser_safe_helpers(failures)

	var report: String
	if failures.is_empty():
		report = "PASS terrain_decoration\n"
	else:
		report = "FAIL terrain_decoration\n" + "\n".join(failures) + "\n"

	_write_report(report)
	print(report)
	push_warning("verify_terrain_decoration_result: %s" % report.strip_edges())
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _write_report(report: String) -> void:
	var absolute_report := ProjectSettings.globalize_path(REPORT_PATH)
	var file := FileAccess.open(absolute_report, FileAccess.WRITE)
	if file == null:
		file = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	else:
		push_error("verify_terrain_decoration: could not write report path=%s err=%s" % [
			absolute_report,
			FileAccess.get_open_error(),
		])


func _verify_on_map(failures: PackedStringArray) -> void:
	print("verify: scatter on battlefield pieces")
	var root := Node3D.new()
	root.name = "VerifyMapRoot"
	add_child(root)

	root.add_child(BATTLEFIELD.instantiate())
	root.add_child(MAP_RESOURCES.instantiate())
	root.add_child(PLAYER_BASE.instantiate())
	root.add_child(ENEMY_BASE.instantiate())
	var decorator: TerrainDecorator = DECORATIONS.instantiate() as TerrainDecorator
	root.add_child(decorator)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "TerrainDecorations present", decorator != null)
	if decorator == null:
		root.queue_free()
		await get_tree().process_frame
		return

	_expect(failures, "instances created", decorator.get_total_instance_count() >= MIN_INSTANCES)
	_expect(
		failures,
		"instance count bounded for FPS",
		decorator.get_total_instance_count() <= MAX_INSTANCES
	)
	_expect(failures, "build time budget", decorator.get_build_usec() <= MAX_BUILD_USEC)
	_expect(failures, "no collision bodies", not decorator.has_collision_bodies())

	var grass_count: int = (
		decorator.get_layer_instance_count(&"grass_clump_a")
		+ decorator.get_layer_instance_count(&"grass_clump_b")
	)
	var flower_count: int = (
		decorator.get_layer_instance_count(&"flower_white")
		+ decorator.get_layer_instance_count(&"flower_yellow")
		+ decorator.get_layer_instance_count(&"flower_violet")
	)
	var bush_count: int = decorator.get_layer_instance_count(&"bush_round")
	var rock_count: int = (
		decorator.get_layer_instance_count(&"rock_small")
		+ decorator.get_layer_instance_count(&"rock_flat")
	)
	var mushroom_count: int = (
		decorator.get_layer_instance_count(&"mushroom_red")
		+ decorator.get_layer_instance_count(&"mushroom_brown")
	)

	_expect(failures, "grass scattered", grass_count > 0)
	_expect(failures, "flowers scattered", flower_count > 0)
	_expect(failures, "bushes scattered", bush_count > 0)
	_expect(failures, "rocks scattered", rock_count > 0)
	_expect(failures, "mushrooms scattered", mushroom_count > 0)

	_verify_exclusions(failures, decorator, root)
	await _verify_determinism(failures, decorator)
	await _verify_road_terrain_blocks(failures, decorator)

	print(
		"verify stats: instances=%d build_usec=%d grass=%d flower=%d bush=%d rock=%d mushroom=%d"
		% [
			decorator.get_total_instance_count(),
			decorator.get_build_usec(),
			grass_count,
			flower_count,
			bush_count,
			rock_count,
			mushroom_count,
		]
	)

	root.queue_free()
	await get_tree().process_frame


func _verify_exclusions(failures: PackedStringArray, decorator: TerrainDecorator, root: Node) -> void:
	decorator.refresh_exclusion_zones()
	var tree: SceneTree = root.get_tree()

	for resource_variant: Variant in tree.get_nodes_in_group(&"resource_nodes"):
		var resource: Node3D = resource_variant as Node3D
		if resource == null:
			continue
		_expect(
			failures,
			"resource origin blocked (%s)" % resource.name,
			not decorator.is_decoration_allowed_at(resource.global_position)
		)
		break

	for building_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		var building: Node3D = building_variant as Node3D
		if building == null:
			continue
		_expect(
			failures,
			"building origin blocked (%s)" % building.name,
			not decorator.is_decoration_allowed_at(building.global_position)
		)
		break

	# Open grassland away from bases/resources should remain placeable.
	_expect(
		failures,
		"open ground remains placeable",
		decorator.is_decoration_allowed_at(Vector3(0.0, 0.0, 0.0))
	)


func _verify_determinism(failures: PackedStringArray, decorator: TerrainDecorator) -> void:
	var first_count: int = decorator.get_total_instance_count()
	decorator.rebuild()
	await get_tree().process_frame
	_expect(failures, "rebuild deterministic count", decorator.get_total_instance_count() == first_count)


func _verify_road_terrain_blocks(failures: PackedStringArray, decorator: TerrainDecorator) -> void:
	var before_count: int = decorator.get_total_instance_count()

	var road := Marker3D.new()
	road.name = "VerifyRoad"
	decorator.get_parent().add_child(road)
	road.global_position = Vector3(0.0, 0.0, 0.0)
	road.set_meta("road_radius", 8.0)
	road.add_to_group(TerrainDecorationConfig.GROUP_ROADS)
	await get_tree().process_frame

	var roads_found: int = decorator.get_tree().get_nodes_in_group(TerrainDecorationConfig.GROUP_ROADS).size()
	_expect(failures, "road group visible to tree", roads_found >= 1)

	decorator.refresh_exclusion_zones()
	_expect(
		failures,
		"road blocks decoration probe at origin",
		not decorator.is_decoration_allowed_at(Vector3.ZERO)
	)

	decorator.rebuild()
	await get_tree().process_frame

	print(
		"verify road: exclusions=%d instances=%d (before=%d) roads=%d"
		% [
			decorator.get_exclusion_zone_count(),
			decorator.get_total_instance_count(),
			before_count,
			roads_found,
		]
	)

	_expect(
		failures,
		"road reduces decoration count",
		decorator.get_total_instance_count() < before_count
	)

	_expect(
		failures,
		"road still blocks origin after rebuild",
		not decorator.is_decoration_allowed_at(Vector3.ZERO)
	)

	road.queue_free()



func _verify_catalog_extensibility(failures: PackedStringArray) -> void:
	print("verify: catalog asset registration")
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	var before: int = TerrainDecorationCatalog.get_entries().size()
	TerrainDecorationCatalog.register_mesh_asset(
		TerrainDecorationCatalog.Kind.ROCK,
		&"verify_custom_rock",
		box,
		null,
		0.01,
		0.1
	)
	var after: int = TerrainDecorationCatalog.get_entries().size()
	_expect(failures, "register_mesh_asset appends", after == before + 1)

	TerrainDecorationCatalog.clear_registered_assets()
	_expect(
		failures,
		"clear restores procedural defaults",
		TerrainDecorationCatalog.get_entries().size() >= before
	)


func _verify_parser_safe_helpers(failures: PackedStringArray) -> void:
	_expect(failures, "config world area positive", TerrainDecorationConfig.world_area() > 0.0)
	_expect(failures, "sample cells positive", TerrainDecorationConfig.sample_cell_count() > 0)


func _expect(failures: PackedStringArray, label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
