class_name TerrainDecorationCatalog
extends RefCounted

## Registry of decoration kinds. Add PackedScene / Mesh assets via register_mesh_asset().

enum Kind {
	GRASS = 0,
	FLOWER = 1,
	BUSH = 2,
	ROCK = 3,
	MUSHROOM = 4,
}


class DecorationEntry:
	extends RefCounted

	var kind: Kind
	var id: StringName
	var density: float
	var weight: float
	var allowed_terrains: Array[int]
	var scale_min: float
	var scale_max: float
	var yaw_random: bool
	## Built-in procedural mesh, or an authored Mesh from register_mesh_asset().
	var mesh: Mesh
	var material: Material


static var _entries: Array[DecorationEntry] = []
static var _built: bool = false


static func get_entries() -> Array[DecorationEntry]:
	_ensure_built()
	return _entries


static func register_mesh_asset(
	kind: Kind,
	id: StringName,
	mesh: Mesh,
	material: Material = null,
	density: float = -1.0,
	weight: float = 1.0,
	allowed_terrains: Array[int] = [],
	scale_min: float = 0.85,
	scale_max: float = 1.2,
	yaw_random: bool = true
) -> void:
	## Call before TerrainDecorator scatters (e.g. from a map script) to add/replace assets.
	_ensure_built()
	if mesh == null:
		push_warning("TerrainDecorationCatalog: ignoring null mesh for %s" % String(id))
		return

	var entry := DecorationEntry.new()
	entry.kind = kind
	entry.id = id
	entry.density = density if density >= 0.0 else _default_density(kind)
	entry.weight = maxf(weight, 0.0)
	entry.allowed_terrains = allowed_terrains if not allowed_terrains.is_empty() else _default_terrains(kind)
	entry.scale_min = scale_min
	entry.scale_max = maxf(scale_max, scale_min)
	entry.yaw_random = yaw_random
	entry.mesh = mesh
	entry.material = material if material != null else _opaque_material(_default_color(kind))
	_entries.append(entry)


static func clear_registered_assets() -> void:
	## Test helper / match reset: drop custom assets and rebuild procedural defaults.
	_entries.clear()
	_built = false


static func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_entries.clear()
	_register_procedural_defaults()


static func _register_procedural_defaults() -> void:
	## Lightweight primitives keep MultiMesh fast and easy to swap for authored meshes later.
	_add_procedural(
		Kind.GRASS,
		&"grass_clump_a",
		_box_mesh(Vector3(0.08, 0.34, 0.04)),
		_opaque_material(Color(0.32, 0.58, 0.22)),
		TerrainDecorationConfig.DENSITY_GRASS,
		TerrainDecorationConfig.WEIGHT_GRASS,
		0.75,
		1.15
	)
	_add_procedural(
		Kind.GRASS,
		&"grass_clump_b",
		_box_mesh(Vector3(0.1, 0.28, 0.05)),
		_opaque_material(Color(0.4, 0.62, 0.26)),
		TerrainDecorationConfig.DENSITY_GRASS * 0.55,
		TerrainDecorationConfig.WEIGHT_GRASS * 0.7,
		0.7,
		1.05
	)
	_add_procedural(
		Kind.FLOWER,
		&"flower_white",
		_flower_mesh(),
		_opaque_material(Color(0.92, 0.92, 0.88)),
		TerrainDecorationConfig.DENSITY_FLOWER,
		TerrainDecorationConfig.WEIGHT_FLOWER,
		0.8,
		1.2
	)
	_add_procedural(
		Kind.FLOWER,
		&"flower_yellow",
		_flower_mesh(),
		_opaque_material(Color(0.95, 0.78, 0.22)),
		TerrainDecorationConfig.DENSITY_FLOWER * 0.7,
		TerrainDecorationConfig.WEIGHT_FLOWER * 0.65,
		0.75,
		1.15
	)
	_add_procedural(
		Kind.FLOWER,
		&"flower_violet",
		_flower_mesh(),
		_opaque_material(Color(0.62, 0.38, 0.78)),
		TerrainDecorationConfig.DENSITY_FLOWER * 0.45,
		TerrainDecorationConfig.WEIGHT_FLOWER * 0.45,
		0.7,
		1.1
	)
	_add_procedural(
		Kind.BUSH,
		&"bush_round",
		_sphere_mesh(0.28, 0.4),
		_opaque_material(Color(0.22, 0.48, 0.2)),
		TerrainDecorationConfig.DENSITY_BUSH,
		TerrainDecorationConfig.WEIGHT_BUSH,
		0.85,
		1.25
	)
	_add_procedural(
		Kind.ROCK,
		&"rock_small",
		_box_mesh(Vector3(0.34, 0.22, 0.28)),
		_opaque_material(Color(0.48, 0.46, 0.42)),
		TerrainDecorationConfig.DENSITY_ROCK,
		TerrainDecorationConfig.WEIGHT_ROCK,
		0.7,
		1.35
	)
	_add_procedural(
		Kind.ROCK,
		&"rock_flat",
		_box_mesh(Vector3(0.42, 0.12, 0.32)),
		_opaque_material(Color(0.42, 0.4, 0.38)),
		TerrainDecorationConfig.DENSITY_ROCK * 0.6,
		TerrainDecorationConfig.WEIGHT_ROCK * 0.55,
		0.8,
		1.2
	)
	_add_procedural(
		Kind.MUSHROOM,
		&"mushroom_red",
		_mushroom_mesh(),
		_opaque_material(Color(0.78, 0.22, 0.18)),
		TerrainDecorationConfig.DENSITY_MUSHROOM,
		TerrainDecorationConfig.WEIGHT_MUSHROOM,
		0.75,
		1.2
	)
	_add_procedural(
		Kind.MUSHROOM,
		&"mushroom_brown",
		_mushroom_mesh(),
		_opaque_material(Color(0.55, 0.38, 0.22)),
		TerrainDecorationConfig.DENSITY_MUSHROOM * 0.7,
		TerrainDecorationConfig.WEIGHT_MUSHROOM * 0.6,
		0.7,
		1.15
	)


static func _add_procedural(
	kind: Kind,
	id: StringName,
	mesh: Mesh,
	material: Material,
	density: float,
	weight: float,
	scale_min: float,
	scale_max: float
) -> void:
	var entry := DecorationEntry.new()
	entry.kind = kind
	entry.id = id
	entry.density = density
	entry.weight = weight
	entry.allowed_terrains = _default_terrains(kind)
	entry.scale_min = scale_min
	entry.scale_max = scale_max
	entry.yaw_random = true
	entry.mesh = mesh
	entry.material = material
	_entries.append(entry)


static func _default_density(kind: Kind) -> float:
	match kind:
		Kind.GRASS:
			return TerrainDecorationConfig.DENSITY_GRASS
		Kind.FLOWER:
			return TerrainDecorationConfig.DENSITY_FLOWER
		Kind.BUSH:
			return TerrainDecorationConfig.DENSITY_BUSH
		Kind.ROCK:
			return TerrainDecorationConfig.DENSITY_ROCK
		Kind.MUSHROOM:
			return TerrainDecorationConfig.DENSITY_MUSHROOM
		_:
			return 0.05


static func _default_color(kind: Kind) -> Color:
	match kind:
		Kind.GRASS:
			return Color(0.34, 0.58, 0.24)
		Kind.FLOWER:
			return Color(0.9, 0.85, 0.55)
		Kind.BUSH:
			return Color(0.22, 0.48, 0.2)
		Kind.ROCK:
			return Color(0.45, 0.43, 0.4)
		Kind.MUSHROOM:
			return Color(0.7, 0.3, 0.22)
		_:
			return Color(0.5, 0.5, 0.5)


static func _default_terrains(kind: Kind) -> Array[int]:
	match kind:
		Kind.GRASS, Kind.FLOWER:
			return [
				TerrainDecorationConfig.TerrainType.GRASSLAND,
				TerrainDecorationConfig.TerrainType.FOREST,
			]
		Kind.BUSH:
			return [
				TerrainDecorationConfig.TerrainType.GRASSLAND,
				TerrainDecorationConfig.TerrainType.FOREST,
				TerrainDecorationConfig.TerrainType.DIRT,
			]
		Kind.ROCK:
			return [
				TerrainDecorationConfig.TerrainType.GRASSLAND,
				TerrainDecorationConfig.TerrainType.DIRT,
				TerrainDecorationConfig.TerrainType.FOREST,
			]
		Kind.MUSHROOM:
			return [
				TerrainDecorationConfig.TerrainType.FOREST,
				TerrainDecorationConfig.TerrainType.GRASSLAND,
			]
		_:
			return [TerrainDecorationConfig.TerrainType.GRASSLAND]


static func _opaque_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.metallic = 0.0
	return material


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _sphere_mesh(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


static func _flower_mesh() -> CapsuleMesh:
	## Stem-like capsule; color comes from material_override.
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.28
	mesh.radial_segments = 6
	return mesh


static func _mushroom_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.04
	mesh.height = 0.2
	mesh.radial_segments = 8
	return mesh
