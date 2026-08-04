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

# --- Completed building max health (player and AI identical) ---
const FARM_MAX_HEALTH: int = 400
const BARRACKS_MAX_HEALTH: int = 800
const BLACKSMITH_MAX_HEALTH: int = 700
const STABLE_MAX_HEALTH: int = 850
const ARTILLERY_DEPOT_MAX_HEALTH: int = 900
const ACADEMY_MAX_HEALTH: int = 850
const SHOP_MAX_HEALTH: int = 600
const TOWER_MAX_HEALTH: int = 650
const WALL_SEGMENT_MAX_HEALTH: int = 700
const HERO_ALTAR_MAX_HEALTH: int = 750
const COMMAND_CENTER_MAX_HEALTH: int = 1600
## Deprecated — Stable HP is identical for player and AI.
const ENEMY_STABLE_MAX_HEALTH: int = STABLE_MAX_HEALTH

# --- Per-building one-worker construction durations ---
const FARM_CONSTRUCTION_SECONDS: float = 10.0
const BARRACKS_CONSTRUCTION_SECONDS: float = 18.0
const HERO_ALTAR_CONSTRUCTION_SECONDS: float = 20.0
const BLACKSMITH_CONSTRUCTION_SECONDS: float = 20.0
const SHOP_CONSTRUCTION_SECONDS: float = 16.0
const TOWER_CONSTRUCTION_SECONDS: float = 18.0
const STABLE_CONSTRUCTION_SECONDS: float = 24.0
const ARTILLERY_DEPOT_CONSTRUCTION_SECONDS: float = 28.0
const ACADEMY_CONSTRUCTION_SECONDS: float = 30.0
const COMMAND_CENTER_CONSTRUCTION_SECONDS: float = 35.0
const WALL_SEGMENT_CONSTRUCTION_SECONDS: float = 6.0
## Fallback when placement type is unknown.
const DEFAULT_CONSTRUCTION_SECONDS: float = 18.0

## Multi-worker construction speed fractions of one-worker time.
const CONSTRUCTION_TIME_RATIO_ONE_WORKER: float = 1.0
const CONSTRUCTION_TIME_RATIO_TWO_WORKERS: float = 0.70
const CONSTRUCTION_TIME_RATIO_THREE_PLUS_WORKERS: float = 0.55
## Floor: construction cannot become faster than this fraction of one-worker time.
const CONSTRUCTION_TIME_RATIO_MINIMUM: float = 0.45

## Legacy aliases kept for tooltip / re-export compatibility.
const CONSTRUCTION_DURATION_ONE_WORKER: float = DEFAULT_CONSTRUCTION_SECONDS
const CONSTRUCTION_DURATION_TWO_WORKERS: float = DEFAULT_CONSTRUCTION_SECONDS * CONSTRUCTION_TIME_RATIO_TWO_WORKERS
const CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = (
	DEFAULT_CONSTRUCTION_SECONDS * CONSTRUCTION_TIME_RATIO_THREE_PLUS_WORKERS
)
const SHOP_CONSTRUCTION_DURATION_ONE_WORKER: float = SHOP_CONSTRUCTION_SECONDS
const SHOP_CONSTRUCTION_DURATION_TWO_WORKERS: float = (
	SHOP_CONSTRUCTION_SECONDS * CONSTRUCTION_TIME_RATIO_TWO_WORKERS
)
const SHOP_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = (
	SHOP_CONSTRUCTION_SECONDS * CONSTRUCTION_TIME_RATIO_THREE_PLUS_WORKERS
)
const WALL_SEGMENT_CONSTRUCTION_DURATION_ONE_WORKER: float = WALL_SEGMENT_CONSTRUCTION_SECONDS
const WALL_SEGMENT_CONSTRUCTION_DURATION_TWO_WORKERS: float = (
	WALL_SEGMENT_CONSTRUCTION_SECONDS * CONSTRUCTION_TIME_RATIO_TWO_WORKERS
)
const WALL_SEGMENT_CONSTRUCTION_DURATION_THREE_PLUS_WORKERS: float = (
	WALL_SEGMENT_CONSTRUCTION_SECONDS * CONSTRUCTION_TIME_RATIO_THREE_PLUS_WORKERS
)
## AI uses the same per-building base times (scaled for one worker).
const ENEMY_CONSTRUCTION_DURATION: float = DEFAULT_CONSTRUCTION_SECONDS

# --- Farm / wall extras ---
const FARM_FOOD_CAP_BONUS: int = 8
const GATE_CONVERSION_WOOD_COST: int = 100

# --- Tower combat ---
const TOWER_ATTACK_DAMAGE: int = 18
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


static func get_base_construction_seconds(building_id: StringName) -> float:
	match building_id:
		&"farm":
			return FARM_CONSTRUCTION_SECONDS
		&"barracks":
			return BARRACKS_CONSTRUCTION_SECONDS
		&"hero_altar":
			return HERO_ALTAR_CONSTRUCTION_SECONDS
		&"blacksmith":
			return BLACKSMITH_CONSTRUCTION_SECONDS
		&"shop":
			return SHOP_CONSTRUCTION_SECONDS
		&"tower":
			return TOWER_CONSTRUCTION_SECONDS
		&"stable":
			return STABLE_CONSTRUCTION_SECONDS
		&"artillery_depot":
			return ARTILLERY_DEPOT_CONSTRUCTION_SECONDS
		&"academy":
			return ACADEMY_CONSTRUCTION_SECONDS
		&"command_center":
			return COMMAND_CENTER_CONSTRUCTION_SECONDS
		&"wall_segment":
			return WALL_SEGMENT_CONSTRUCTION_SECONDS
		_:
			return DEFAULT_CONSTRUCTION_SECONDS


static func get_construction_seconds(building_id: StringName, worker_count: int) -> float:
	var base_seconds: float = get_base_construction_seconds(building_id)
	var ratio: float = CONSTRUCTION_TIME_RATIO_ONE_WORKER
	if worker_count >= 3:
		ratio = CONSTRUCTION_TIME_RATIO_THREE_PLUS_WORKERS
	elif worker_count == 2:
		ratio = CONSTRUCTION_TIME_RATIO_TWO_WORKERS
	ratio = maxf(ratio, CONSTRUCTION_TIME_RATIO_MINIMUM)
	return base_seconds * ratio
