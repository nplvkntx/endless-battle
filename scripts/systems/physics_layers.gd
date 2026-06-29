class_name PhysicsLayers

## Shared 3D physics layer and mask values for Endless Battle.

const WORLD: int = 1
const UNITS: int = 2
const BUILDINGS: int = 4

const UNIT_COLLISION_MASK: int = WORLD | BUILDINGS
const BUILDING_COLLISION_MASK: int = WORLD | UNITS
