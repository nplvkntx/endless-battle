class_name UnitStats
extends RefCounted

## Canonical combat, train-cost, and mobility numbers for all trainable / army units.
## Balance units here only — consumers reference these consts (do not rebalance elsewhere).
## Scene HealthComponent.max_health / move_speed should match the values below; runtime
## scripts also pull combat defaults from here so player and AI share one table.

# --- Worker ---
const WORKER_MAX_HEALTH: int = 90
const WORKER_MOVE_SPEED: float = 5.0
const WORKER_ARMOR: int = 0
const WORKER_GOLD_COST: int = 50
const WORKER_FOOD_COST: int = 1
const WORKER_TRAIN_SECONDS: float = 6.0

# --- Spearman / Pikeman (Barracks T1) ---
const SPEARMAN_MAX_HEALTH: int = 110
const SPEARMAN_MOVE_SPEED: float = 4.5
const SPEARMAN_ATTACK_DAMAGE: int = 8
const SPEARMAN_ATTACK_RANGE: float = 2.4
const SPEARMAN_ATTACK_COOLDOWN: float = 1.0
const SPEARMAN_ARMOR: int = 1
const SPEARMAN_GOLD_COST: int = 70
const SPEARMAN_FOOD_COST: int = 1
const SPEARMAN_TRAIN_SECONDS: float = 7.0
## Bonus basic-attack damage vs Light Cavalry / Cavalry Archer / Heavy Cavalry.
const SPEARMAN_CAVALRY_DAMAGE_MULTIPLIER: float = 1.5

# --- Swordsman (Barracks) ---
const SWORDSMAN_MAX_HEALTH: int = 150
const SWORDSMAN_MOVE_SPEED: float = 5.0
const SWORDSMAN_ATTACK_DAMAGE: int = 12
const SWORDSMAN_ATTACK_RANGE: float = 2.0
const SWORDSMAN_ATTACK_COOLDOWN: float = 1.1
const SWORDSMAN_ARMOR: int = 2
const SWORDSMAN_GOLD_COST: int = 100
const SWORDSMAN_FOOD_COST: int = 1
const SWORDSMAN_TRAIN_SECONDS: float = 7.0
## Blacksmith: +damage per swordsman attack level.
const SWORDSMAN_ATTACK_DAMAGE_PER_UPGRADE_LEVEL: int = 2

# --- Archer (Barracks) ---
const ARCHER_MAX_HEALTH: int = 85
const ARCHER_MOVE_SPEED: float = 5.0
const ARCHER_ATTACK_DAMAGE: int = 9
const ARCHER_ATTACK_RANGE: float = 8.0
const ARCHER_ATTACK_COOLDOWN: float = 1.1
const ARCHER_ARMOR: int = 0
const ARCHER_GOLD_COST: int = 95
const ARCHER_FOOD_COST: int = 1
const ARCHER_TRAIN_SECONDS: float = 7.0
const ARCHER_PROJECTILE_SPEED: float = 20.0
## Blacksmith: +damage per archer attack level.
const ARCHER_ATTACK_DAMAGE_PER_UPGRADE_LEVEL: int = 2
## Blacksmith: bonus attack speed fraction per level (4% each). Applied via AS pipeline.
const ARCHER_ATTACK_SPEED_BONUS_PER_LEVEL: float = 0.04
## Legacy alias — prefer ARCHER_ATTACK_SPEED_BONUS_PER_LEVEL.
const ARCHER_ATTACK_SPEED_COOLDOWN_REDUCTION_PER_LEVEL: float = ARCHER_ATTACK_SPEED_BONUS_PER_LEVEL
## Blacksmith: +range per range level. Level 5 → 8.0 + 5×0.75 = 11.75.
const ARCHER_ATTACK_RANGE_PER_UPGRADE_LEVEL: float = 0.75

# --- Light Cavalry (Stable) ---
const LIGHT_CAVALRY_MAX_HEALTH: int = 140
const LIGHT_CAVALRY_MOVE_SPEED: float = 8.5
const LIGHT_CAVALRY_ATTACK_DAMAGE: int = 12
const LIGHT_CAVALRY_ATTACK_RANGE: float = 2.0
const LIGHT_CAVALRY_ATTACK_COOLDOWN: float = 0.9
const LIGHT_CAVALRY_ARMOR: int = 1
const LIGHT_CAVALRY_GOLD_COST: int = 105
const LIGHT_CAVALRY_FOOD_COST: int = 2
const LIGHT_CAVALRY_TRAIN_SECONDS: float = 8.0

# --- Cavalry Archer (Stable) ---
const CAVALRY_ARCHER_MAX_HEALTH: int = 120
const CAVALRY_ARCHER_MOVE_SPEED: float = 7.5
const CAVALRY_ARCHER_ATTACK_DAMAGE: int = 10
const CAVALRY_ARCHER_ATTACK_RANGE: float = 7.5
const CAVALRY_ARCHER_ATTACK_COOLDOWN: float = 1.0
const CAVALRY_ARCHER_ARMOR: int = 1
const CAVALRY_ARCHER_GOLD_COST: int = 130
const CAVALRY_ARCHER_FOOD_COST: int = 2
const CAVALRY_ARCHER_TRAIN_SECONDS: float = 9.0

# --- Heavy Cavalry (Stable) ---
const HEAVY_CAVALRY_MAX_HEALTH: int = 220
const HEAVY_CAVALRY_MOVE_SPEED: float = 7.0
const HEAVY_CAVALRY_ATTACK_DAMAGE: int = 20
const HEAVY_CAVALRY_ATTACK_RANGE: float = 2.2
const HEAVY_CAVALRY_ATTACK_COOLDOWN: float = 1.1
const HEAVY_CAVALRY_ARMOR: int = 4
const HEAVY_CAVALRY_GOLD_COST: int = 180
const HEAVY_CAVALRY_FOOD_COST: int = 3
const HEAVY_CAVALRY_TRAIN_SECONDS: float = 12.0

# --- Cannon (Artillery Depot) ---
const CANNON_MAX_HEALTH: int = 160
const CANNON_MOVE_SPEED: float = 5.0
const CANNON_ATTACK_DAMAGE: int = 70
const CANNON_ATTACK_RANGE: float = 14.0
const CANNON_ATTACK_COOLDOWN: float = 5.0
const CANNON_SPLASH_RADIUS: float = 3.5
const CANNON_SPLASH_MIN_DAMAGE_RATIO: float = 0.35
const CANNON_ARMOR: int = 0
const CANNON_GOLD_COST: int = 300
const CANNON_FOOD_COST: int = 3
const CANNON_TRAIN_SECONDS: float = 18.0
const CANNON_PROJECTILE_SPEED: float = 14.0

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

# --- Shared attack-speed cap (heroes, items, upgrades) ---
const MAX_BONUS_ATTACK_SPEED: float = 1.0


static func get_final_attack_cooldown(base_cooldown: float, bonus_attack_speed: float) -> float:
	var capped: float = clampf(bonus_attack_speed, 0.0, MAX_BONUS_ATTACK_SPEED)
	return base_cooldown / (1.0 + capped)
