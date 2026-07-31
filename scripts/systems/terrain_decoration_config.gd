class_name TerrainDecorationConfig
extends RefCounted

## Tunable densities, exclusion radii, and terrain rules for automatic environment decor.

enum TerrainType {
	GRASSLAND = 0,
	DIRT = 1,
	FOREST = 2,
	ROAD = 3,
	BLOCKED = 4,
}

## Matches EnemyBuildPlacement / ground plane half-extent.
const WORLD_HALF_EXTENT: float = 50.0
const WORLD_MIN_X: float = -WORLD_HALF_EXTENT
const WORLD_MAX_X: float = WORLD_HALF_EXTENT
const WORLD_MIN_Z: float = -WORLD_HALF_EXTENT
const WORLD_MAX_Z: float = WORLD_HALF_EXTENT

## Deterministic scatter seed for the default 1v1 battlefield.
const WORLD_SEED: int = 1847291

## Grid step used when sampling candidate points (meters).
const SAMPLE_CELL_SIZE: float = 2.0

## Instances attempted per sample cell (0..1+). Higher = denser. Easy editor overrides live on TerrainDecorator.
const DENSITY_GRASS: float = 0.72
const DENSITY_FLOWER: float = 0.16
const DENSITY_BUSH: float = 0.055
const DENSITY_ROCK: float = 0.045
const DENSITY_MUSHROOM: float = 0.03

## Soft weights used when a cell rolls a single decoration among competing kinds.
const WEIGHT_GRASS: float = 1.0
const WEIGHT_FLOWER: float = 0.55
const WEIGHT_BUSH: float = 0.35
const WEIGHT_ROCK: float = 0.3
const WEIGHT_MUSHROOM: float = 0.22

## Keep clear of gameplay blockers (meters from node origin / footprint edge).
const EXCLUSION_TREE: float = 2.4
const EXCLUSION_GOLD_MINE: float = 4.2
const EXCLUSION_BUILDING_PADDING: float = 1.6
const EXCLUSION_ROAD: float = 1.75
const EXCLUSION_MAP_EDGE: float = 1.0

## Group names for authored blockers / future road markers.
const GROUP_ROADS: StringName = &"roads"
const GROUP_BUILDINGS: StringName = &"buildings"
const GROUP_RESOURCE_NODES: StringName = &"resource_nodes"

## Default terrain for the flat grassland map. Override via TerrainDecorator.terrain_provider.
const DEFAULT_TERRAIN: TerrainType = TerrainType.GRASSLAND


static func world_area() -> float:
	return (WORLD_MAX_X - WORLD_MIN_X) * (WORLD_MAX_Z - WORLD_MIN_Z)


static func sample_cell_count() -> int:
	var cells_x: int = int(ceili((WORLD_MAX_X - WORLD_MIN_X) / SAMPLE_CELL_SIZE))
	var cells_z: int = int(ceili((WORLD_MAX_Z - WORLD_MIN_Z) / SAMPLE_CELL_SIZE))
	return maxi(cells_x * cells_z, 1)
