class_name BuildingStats
extends RefCounted

## Canonical building placement costs, HP, construction times, and structure combat.
## Shared by player BuildManager and EnemyBuildManager — change costs here only.

# --- Placement gold / wood (identical for player and AI) ---
const FARM_GOLD_COST: int = 80
const FARM_WOOD_COST: int = 20
const BARRACKS_GOLD_COST: int = 150
const BARRACKS_WOOD_COST: int = 100
const BLACKSMITH_GOLD_COST: int = 100
const BLACKSMITH_WOOD_COST: int = 150
const STABLE_GOLD_COST: int = 175
const STABLE_WOOD_COST: int = 125
const ARTILLERY_DEPOT_GOLD_COST: int = 225
const ARTILLERY_DEPOT_WOOD_COST: int = 175
const ACADEMY_GOLD_COST: int = 200
const ACADEMY_WOOD_COST: int = 150
const SHOP_GOLD_COST: int = 80
const SHOP_WOOD_COST: int = 120
const TOWER_GOLD_COST: int = 120
const TOWER_WOOD_COST: int = 80
const WALL_SEGMENT_GOLD_COST: int = 0
const WALL_SEGMENT_WOOD_COST: int = 40
const HERO_ALTAR_GOLD_COST: int = 180
const HERO_ALTAR_WOOD_COST: int = 110
const COMMAND_CENTER_GOLD_COST: int = 200
const COMMAND_CENTER_WOOD_COST: int = 400

# --- Completed building max health (scene defaults; AI may override some — see below) ---
const FARM_MAX_HEALTH: int = 250
const BARRACKS_MAX_HEALTH: int = 300
const BLACKSMITH_MAX_HEALTH: int = 700
const STABLE_MAX_HEALTH: int = 700
const ARTILLERY_DEPOT_MAX_HEALTH: int = 750
const ACADEMY_MAX_HEALTH: int = 720
const SHOP_MAX_HEALTH: int = 600
const TOWER_MAX_HEALTH: int = 350
const WALL_SEGMENT_MAX_HEALTH: int = 500
const HERO_ALTAR_MAX_HEALTH: int = 350
const COMMAND_CENTER_MAX_HEALTH: int = 500
## Intentional AI-only stable HP when EnemyBuildManager places stables (not a balance drift).
const ENEMY_STABLE_MAX_HEALTH: int = 320

# --- Player construction duration by worker count ---
const CONSTRUCTION_DURATION_ONE_WORKER: float = 4.0
const CONSTRUCTION_DURATION_TWO_WORKERS: float = 2.5
const CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = 2.0
const SHOP_CONSTRUCTION_DURATION_ONE_WORKER: float = 3.5
const SHOP_CONSTRUCTION_DURATION_TWO_WORKERS: float = 2.2
const SHOP_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = 1.8
const WALL_SEGMENT_CONSTRUCTION_DURATION_ONE_WORKER: float = 8.0
const WALL_SEGMENT_CONSTRUCTION_DURATION_TWO_WORKERS: float = 5.0
const WALL_SEGMENT_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = 4.0
## Flat AI construction duration (EnemyBuildManager).
const ENEMY_CONSTRUCTION_DURATION: float = 4.0

# --- Farm / wall extras ---
const FARM_FOOD_CAP_BONUS: int = 8
const GATE_CONVERSION_WOOD_COST: int = 100

# --- Tower combat ---
const TOWER_ATTACK_DAMAGE: int = 12
const TOWER_ATTACK_RANGE: float = 10.0
const TOWER_ATTACK_COOLDOWN: float = 1.5

# --- Command Center tier upgrades ---
const CC_TIER_2_GOLD_COST: int = 800
const CC_TIER_2_WOOD_COST: int = 500
const CC_TIER_2_UPGRADE_SECONDS: float = 60.0
const CC_TIER_3_GOLD_COST: int = 2000
const CC_TIER_3_WOOD_COST: int = 1200
const CC_TIER_3_UPGRADE_SECONDS: float = 120.0

# --- Blacksmith / Stable research duration — see UpgradeStats ---
