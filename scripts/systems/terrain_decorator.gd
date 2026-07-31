class_name TerrainDecorator
extends Node3D

## Scatters decorative MultiMesh props across the map. Visual-only: no collision, no nav carve.

signal decorations_built(instance_count: int)

@export var enabled: bool = true
@export var world_seed: int = TerrainDecorationConfig.WORLD_SEED
@export var sample_cell_size: float = TerrainDecorationConfig.SAMPLE_CELL_SIZE

@export_group("Density")
@export_range(0.0, 3.0, 0.01) var grass_density_scale: float = 1.0
@export_range(0.0, 3.0, 0.01) var flower_density_scale: float = 1.0
@export_range(0.0, 3.0, 0.01) var bush_density_scale: float = 1.0
@export_range(0.0, 3.0, 0.01) var rock_density_scale: float = 1.0
@export_range(0.0, 3.0, 0.01) var mushroom_density_scale: float = 1.0

@export_group("Exclusions")
@export var exclusion_tree: float = TerrainDecorationConfig.EXCLUSION_TREE
@export var exclusion_gold_mine: float = TerrainDecorationConfig.EXCLUSION_GOLD_MINE
@export var exclusion_building_padding: float = TerrainDecorationConfig.EXCLUSION_BUILDING_PADDING
@export var exclusion_road: float = TerrainDecorationConfig.EXCLUSION_ROAD

## Optional Callable(Vector3) -> TerrainDecorationConfig.TerrainType. Empty uses grassland + road detection.
var terrain_provider: Callable = Callable()

var _rng := RandomNumberGenerator.new()
var _layers: Dictionary = {} ## StringName id -> MultiMeshInstance3D
var _total_instances: int = 0
var _exclusion_centers: PackedVector2Array = PackedVector2Array()
var _exclusion_radii_sq: PackedFloat32Array = PackedFloat32Array()
var _build_usec: int = 0


func _ready() -> void:
	if not enabled:
		return
	# Wait one frame so authored resources / bases have valid global transforms.
	call_deferred("_build_decorations")


func rebuild() -> void:
	_clear_layers()
	if enabled:
		_build_decorations()


func get_total_instance_count() -> int:
	return _total_instances


func get_layer_instance_count(layer_id: StringName) -> int:
	var layer: MultiMeshInstance3D = _layers.get(layer_id) as MultiMeshInstance3D
	if layer == null or layer.multimesh == null:
		return 0
	return layer.multimesh.visible_instance_count


func get_build_usec() -> int:
	return _build_usec


func get_exclusion_zone_count() -> int:
	return _exclusion_centers.size()


func is_decoration_allowed_at(world_position: Vector3) -> bool:
	## Public probe used by tests / tools after exclusions have been collected.
	if _is_excluded(world_position):
		return false
	var terrain: int = _terrain_at(world_position)
	return (
		terrain != TerrainDecorationConfig.TerrainType.ROAD
		and terrain != TerrainDecorationConfig.TerrainType.BLOCKED
	)


func refresh_exclusion_zones() -> void:
	_collect_exclusion_zones()


func has_collision_bodies() -> bool:
	for child: Node in get_children():
		if child is CollisionObject3D:
			return true
		if child is MultiMeshInstance3D:
			continue
		for nested: Node in child.get_children():
			if nested is CollisionObject3D:
				return true
	return false


func _build_decorations() -> void:
	var started_usec: int = Time.get_ticks_usec()
	_clear_layers()
	_total_instances = 0

	if not enabled or not is_inside_tree():
		_build_usec = Time.get_ticks_usec() - started_usec
		decorations_built.emit(0)
		return

	_rng.seed = world_seed
	_collect_exclusion_zones()

	var entries: Array = TerrainDecorationCatalog.get_entries()
	var transforms_by_id: Dictionary = {} ## StringName -> Array[Transform3D]
	for entry_variant: Variant in entries:
		var entry: TerrainDecorationCatalog.DecorationEntry = entry_variant
		var typed_batch: Array[Transform3D] = []
		transforms_by_id[entry.id] = typed_batch

	var cell: float = maxf(sample_cell_size, 0.5)
	var x: float = TerrainDecorationConfig.WORLD_MIN_X + cell * 0.5
	while x <= TerrainDecorationConfig.WORLD_MAX_X - cell * 0.5:
		var z: float = TerrainDecorationConfig.WORLD_MIN_Z + cell * 0.5
		while z <= TerrainDecorationConfig.WORLD_MAX_Z - cell * 0.5:
			_scatter_cell(Vector3(x, 0.0, z), cell, entries, transforms_by_id)
			z += cell
		x += cell

	for entry_variant: Variant in entries:
		var entry: TerrainDecorationCatalog.DecorationEntry = entry_variant
		var transforms: Array[Transform3D] = transforms_by_id[entry.id]
		if transforms.is_empty():
			continue
		_create_layer(entry, transforms)

	_build_usec = Time.get_ticks_usec() - started_usec
	decorations_built.emit(_total_instances)


func _scatter_cell(
	cell_center: Vector3,
	cell_size: float,
	entries: Array,
	transforms_by_id: Dictionary
) -> void:
	var terrain: int = _terrain_at(cell_center)
	if (
		terrain == TerrainDecorationConfig.TerrainType.ROAD
		or terrain == TerrainDecorationConfig.TerrainType.BLOCKED
	):
		return

	var candidates: Array[TerrainDecorationCatalog.DecorationEntry] = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total_weight: float = 0.0

	for entry_variant: Variant in entries:
		var entry: TerrainDecorationCatalog.DecorationEntry = entry_variant
		if not entry.allowed_terrains.has(terrain):
			continue
		var density: float = entry.density * _density_scale_for(entry.kind)
		if density <= 0.0:
			continue
		# Probabilistic occupancy: density is chance to attempt this entry in the cell.
		if _rng.randf() > clampf(density, 0.0, 1.0):
			continue
		var weight: float = maxf(entry.weight, 0.0) * density
		if weight <= 0.0:
			continue
		candidates.append(entry)
		weights.append(weight)
		total_weight += weight

	if candidates.is_empty() or total_weight <= 0.0:
		return

	# Weighted pick among entries that passed the density roll.
	var pick: float = _rng.randf() * total_weight
	var running: float = 0.0
	var chosen: TerrainDecorationCatalog.DecorationEntry = candidates[0]
	for index: int in candidates.size():
		running += weights[index]
		if pick <= running:
			chosen = candidates[index]
			break

	var jitter: float = cell_size * 0.42
	var position := Vector3(
		cell_center.x + _rng.randf_range(-jitter, jitter),
		0.0,
		cell_center.z + _rng.randf_range(-jitter, jitter)
	)
	position.x = clampf(
		position.x,
		TerrainDecorationConfig.WORLD_MIN_X + TerrainDecorationConfig.EXCLUSION_MAP_EDGE,
		TerrainDecorationConfig.WORLD_MAX_X - TerrainDecorationConfig.EXCLUSION_MAP_EDGE
	)
	position.z = clampf(
		position.z,
		TerrainDecorationConfig.WORLD_MIN_Z + TerrainDecorationConfig.EXCLUSION_MAP_EDGE,
		TerrainDecorationConfig.WORLD_MAX_Z - TerrainDecorationConfig.EXCLUSION_MAP_EDGE
	)

	if _is_excluded(position):
		return
	if _terrain_at(position) == TerrainDecorationConfig.TerrainType.ROAD:
		return
	if _terrain_at(position) == TerrainDecorationConfig.TerrainType.BLOCKED:
		return

	var scale: float = _rng.randf_range(chosen.scale_min, chosen.scale_max)
	var yaw: float = _rng.randf_range(0.0, TAU) if chosen.yaw_random else 0.0
	var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)).scaled(Vector3(scale, scale, scale))
	# Lift slightly so box/sphere primitives sit on the ground plane.
	position.y = 0.12 * scale
	var xform := Transform3D(basis, position)
	var batch: Array[Transform3D] = transforms_by_id[chosen.id]
	batch.append(xform)


func _create_layer(entry: TerrainDecorationCatalog.DecorationEntry, transforms: Array[Transform3D]) -> void:
	var instance_count: int = transforms.size()
	if instance_count <= 0 or entry.mesh == null:
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = entry.mesh
	multimesh.instance_count = instance_count
	multimesh.visible_instance_count = instance_count
	for index: int in range(instance_count):
		multimesh.set_instance_transform(index, transforms[index])

	var layer := MultiMeshInstance3D.new()
	layer.name = String(entry.id)
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if entry.material != null:
		layer.material_override = entry.material
	layer.multimesh = multimesh
	add_child(layer)

	_layers[entry.id] = layer
	_total_instances += instance_count


func _density_scale_for(kind: TerrainDecorationCatalog.Kind) -> float:
	match kind:
		TerrainDecorationCatalog.Kind.GRASS:
			return grass_density_scale
		TerrainDecorationCatalog.Kind.FLOWER:
			return flower_density_scale
		TerrainDecorationCatalog.Kind.BUSH:
			return bush_density_scale
		TerrainDecorationCatalog.Kind.ROCK:
			return rock_density_scale
		TerrainDecorationCatalog.Kind.MUSHROOM:
			return mushroom_density_scale
		_:
			return 1.0


func _terrain_at(position: Vector3) -> int:
	if terrain_provider.is_valid():
		var custom: Variant = terrain_provider.call(position)
		if custom is int:
			return int(custom)

	# Authored road markers (future maps): nodes in group "roads".
	var tree: SceneTree = get_tree()
	if tree != null:
		for road_variant: Variant in tree.get_nodes_in_group(TerrainDecorationConfig.GROUP_ROADS):
			var road: Node3D = road_variant as Node3D
			if road == null or not is_instance_valid(road):
				continue
			var radius: float = exclusion_road
			if road.has_meta("road_radius"):
				radius = float(road.get_meta("road_radius"))
			var delta: Vector3 = road.global_position - position
			delta.y = 0.0
			if delta.length_squared() <= radius * radius:
				return TerrainDecorationConfig.TerrainType.ROAD

	return TerrainDecorationConfig.DEFAULT_TERRAIN


func _collect_exclusion_zones() -> void:
	_exclusion_centers.clear()
	_exclusion_radii_sq.clear()

	var tree: SceneTree = get_tree()
	if tree == null:
		return

	for resource_variant: Variant in tree.get_nodes_in_group(TerrainDecorationConfig.GROUP_RESOURCE_NODES):
		var resource: Node3D = resource_variant as Node3D
		if resource == null or not is_instance_valid(resource):
			continue
		var radius: float = exclusion_tree
		if resource is GoldMine:
			radius = exclusion_gold_mine
		elif resource is WoodTree:
			radius = exclusion_tree
		_add_exclusion(resource.global_position, radius)

	for building_variant: Variant in tree.get_nodes_in_group(TerrainDecorationConfig.GROUP_BUILDINGS):
		var building: Node3D = building_variant as Node3D
		if building == null or not is_instance_valid(building):
			continue
		var footprint: Vector2 = _building_footprint(building)
		var half: float = maxf(footprint.x, footprint.y) * 0.5
		_add_exclusion(building.global_position, half + exclusion_building_padding)

	for road_variant: Variant in tree.get_nodes_in_group(TerrainDecorationConfig.GROUP_ROADS):
		var road: Node3D = road_variant as Node3D
		if road == null or not is_instance_valid(road):
			continue
		var road_radius: float = exclusion_road
		if road.has_meta("road_radius"):
			road_radius = float(road.get_meta("road_radius"))
		_add_exclusion(road.global_position, road_radius)


func _building_footprint(building: Node3D) -> Vector2:
	if building is Farm:
		return EnemyBuildPlacement.FARM_SIZE
	if building is Barracks:
		return EnemyBuildPlacement.BARRACKS_SIZE
	if building is Blacksmith:
		return EnemyBuildPlacement.BLACKSMITH_SIZE
	if building is Stable:
		return EnemyBuildPlacement.STABLE_SIZE
	if building is ArtilleryDepot:
		return EnemyBuildPlacement.ARTILLERY_DEPOT_SIZE
	if building is Academy:
		return EnemyBuildPlacement.ACADEMY_SIZE
	if building is Shop:
		return EnemyBuildPlacement.SHOP_SIZE
	if building is Tower:
		return EnemyBuildPlacement.TOWER_SIZE
	if building is WallSegment:
		return EnemyBuildPlacement.WALL_SEGMENT_SIZE
	if building is HeroAltar:
		return EnemyBuildPlacement.HERO_ALTAR_SIZE
	if building is CommandCenter:
		return EnemyBuildPlacement.COMMAND_CENTER_SIZE
	return EnemyBuildPlacement.DEFAULT_FOOTPRINT


func _add_exclusion(world_position: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	_exclusion_centers.append(Vector2(world_position.x, world_position.z))
	_exclusion_radii_sq.append(radius * radius)


func _is_excluded(position: Vector3) -> bool:
	var point := Vector2(position.x, position.z)
	for index: int in _exclusion_centers.size():
		if point.distance_squared_to(_exclusion_centers[index]) <= _exclusion_radii_sq[index]:
			return true
	return false


func _clear_layers() -> void:
	for key: Variant in _layers.keys():
		var layer: MultiMeshInstance3D = _layers[key] as MultiMeshInstance3D
		if layer != null and is_instance_valid(layer):
			remove_child(layer)
			layer.free()
	_layers.clear()
	_total_instances = 0
	var stray: Array[Node] = get_children()
	for child: Node in stray:
		if child is MultiMeshInstance3D and is_instance_valid(child):
			remove_child(child)
			child.free()
