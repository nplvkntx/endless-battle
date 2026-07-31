class_name UnitStats
extends RefCounted

## Canonical combat, train-cost, and mobility numbers for all trainable / army units.
## Balance units here only — consumers reference these consts (do not rebalance elsewhere).
## Scene HealthComponent.max_health / move_speed should match the values below; runtime
## scripts also pull combat defaults from here so player and AI share one table.

# --- Worker ---
const WORKER_MAX_HEALTH: int = 70
const WORKER_MOVE_SPEED: float = 5.0
const WORKER_GOLD_COST: int = 50
const WORKER_FOOD_COST: int = 1
const WORKER_TRAIN_SECONDS: float = 3.0

# --- Spearman (Barracks T1) ---
const SPEARMAN_MAX_HEALTH: int = 70
const SPEARMAN_MOVE_SPEED: float = 4.25
const SPEARMAN_ATTACK_DAMAGE: int = 6
const SPEARMAN_ATTACK_RANGE: float = 2.4
const SPEARMAN_ATTACK_COOLDOWN: float = 1.0
const SPEARMAN_ARMOR: int = 0
const SPEARMAN_GOLD_COST: int = 65
const SPEARMAN_FOOD_COST: int = 1
const SPEARMAN_TRAIN_SECONDS: float = 5.0

# --- Swordsman (Barracks) ---
const SWORDSMAN_MAX_HEALTH: int = 100
const SWORDSMAN_MOVE_SPEED: float = 5.0
const SWORDSMAN_ATTACK_DAMAGE: int = 10
const SWORDSMAN_ATTACK_RANGE: float = 2.0
const SWORDSMAN_ATTACK_COOLDOWN: float = 1.0
const SWORDSMAN_ARMOR: int = 0
const SWORDSMAN_GOLD_COST: int = 100
const SWORDSMAN_FOOD_COST: int = 1
const SWORDSMAN_TRAIN_SECONDS: float = 4.0
## Blacksmith: +damage per swordsman attack level.
const SWORDSMAN_ATTACK_DAMAGE_PER_UPGRADE_LEVEL: int = 2

# --- Archer (Barracks) ---
const ARCHER_MAX_HEALTH: int = 100
const ARCHER_MOVE_SPEED: float = 5.0
const ARCHER_ATTACK_DAMAGE: int = 7
const ARCHER_ATTACK_RANGE: float = 8.0
const ARCHER_ATTACK_COOLDOWN: float = 1.2
const ARCHER_ARMOR: int = 0
const ARCHER_GOLD_COST: int = 100
const ARCHER_FOOD_COST: int = 1
const ARCHER_TRAIN_SECONDS: float = 4.0
## Blacksmith: +damage per archer attack level.
const ARCHER_ATTACK_DAMAGE_PER_UPGRADE_LEVEL: int = 2
## Blacksmith: cooldown multiplier reduction per attack-speed level (5% each).
const ARCHER_ATTACK_SPEED_COOLDOWN_REDUCTION_PER_LEVEL: float = 0.05
## Blacksmith: +range per range level.
const ARCHER_ATTACK_RANGE_PER_UPGRADE_LEVEL: float = 8.0

# --- Light Cavalry (Stable) ---
const LIGHT_CAVALRY_MAX_HEALTH: int = 80
const LIGHT_CAVALRY_MOVE_SPEED: float = 9.0
const LIGHT_CAVALRY_ATTACK_DAMAGE: int = 8
const LIGHT_CAVALRY_ATTACK_RANGE: float = 2.0
const LIGHT_CAVALRY_ATTACK_COOLDOWN: float = 0.9
const LIGHT_CAVALRY_ARMOR: int = 0
const LIGHT_CAVALRY_GOLD_COST: int = 85
const LIGHT_CAVALRY_FOOD_COST: int = 1
const LIGHT_CAVALRY_TRAIN_SECONDS: float = 3.5

# --- Cavalry Archer (Stable) ---
const CAVALRY_ARCHER_MAX_HEALTH: int = 90
const CAVALRY_ARCHER_MOVE_SPEED: float = 7.5
const CAVALRY_ARCHER_ATTACK_DAMAGE: int = 6
const CAVALRY_ARCHER_ATTACK_RANGE: float = 7.5
const CAVALRY_ARCHER_ATTACK_COOLDOWN: float = 1.1
const CAVALRY_ARCHER_ARMOR: int = 0
const CAVALRY_ARCHER_GOLD_COST: int = 130
const CAVALRY_ARCHER_FOOD_COST: int = 1
const CAVALRY_ARCHER_TRAIN_SECONDS: float = 5.5

# --- Heavy Cavalry (Stable) ---
const HEAVY_CAVALRY_MAX_HEALTH: int = 150
const HEAVY_CAVALRY_MOVE_SPEED: float = 7.0
const HEAVY_CAVALRY_ATTACK_DAMAGE: int = 14
const HEAVY_CAVALRY_ATTACK_RANGE: float = 2.2
const HEAVY_CAVALRY_ATTACK_COOLDOWN: float = 1.1
const HEAVY_CAVALRY_ARMOR: int = 2
const HEAVY_CAVALRY_GOLD_COST: int = 150
const HEAVY_CAVALRY_FOOD_COST: int = 2
const HEAVY_CAVALRY_TRAIN_SECONDS: float = 7.0

# --- Cannon (Artillery Depot) ---
const CANNON_MAX_HEALTH: int = 120
const CANNON_MOVE_SPEED: float = 6.0
const CANNON_ATTACK_DAMAGE: int = 45
const CANNON_ATTACK_RANGE: float = 14.0
const CANNON_ATTACK_COOLDOWN: float = 5.5
const CANNON_SPLASH_RADIUS: float = 3.5
const CANNON_SPLASH_MIN_DAMAGE_RATIO: float = 0.5
const CANNON_ARMOR: int = 0
const CANNON_GOLD_COST: int = 275
const CANNON_FOOD_COST: int = 2
const CANNON_TRAIN_SECONDS: float = 14.0

# --- Neutral creep defaults (camp scenes may override damage) ---
const NEUTRAL_CREEP_MAX_HEALTH: int = 80
const NEUTRAL_CREEP_MOVE_SPEED: float = 3.5
const ENEMY_DUMMY_MAX_HEALTH: int = 100
const ENEMY_DUMMY_ATTACK_DAMAGE: int = 8
const ENEMY_DUMMY_ATTACK_RANGE: float = 2.0
const ENEMY_DUMMY_ATTACK_COOLDOWN: float = 1.2

# --- Passive regen (HealthComponent) ---
const HERO_PASSIVE_REGEN_PER_SECOND: float = 0.5
const ARMY_PASSIVE_REGEN_PER_SECOND: float = 0.25
