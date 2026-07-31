class_name EconomyStats
extends RefCounted

## Canonical match-start resources, gathering, and kill reward numbers.
## MatchConfig / GatheringConfig / HeroXpRewards re-export these for compatibility.
## Change economy balance in this file only.

# --- Match start (human and AI share gold/wood/food-max) ---
const STARTING_GOLD: int = 500
const STARTING_WOOD: int = 500
const STARTING_FOOD_MAX: int = 15
const STARTING_WORKER_COUNT: int = 5
const HUMAN_STARTING_FOOD: int = STARTING_WORKER_COUNT

# --- Gathering ---
const GATHER_WAIT_SECONDS: float = 1.0
const WORKER_CARRY_CAPACITY: int = 10
const GATHER_CHUNK_GOLD: int = 5
const GATHER_CHUNK_WOOD: int = 2
const TREE_STARTING_WOOD: int = 5000
const GOLD_MINE_STARTING_GOLD: int = 20000

# --- Kill XP / gold ---
const CREEP_XP_WEAK: int = 25
const CREEP_XP_MEDIUM: int = 50
const CREEP_XP_STRONG: int = 100
const CREEP_GOLD_WEAK: int = 5
const CREEP_GOLD_MEDIUM: int = 10
const CREEP_GOLD_STRONG: int = 20
const WORKER_XP: int = 10
const WORKER_GOLD: int = 2
const MILITARY_XP: int = 25
const MILITARY_GOLD: int = 5
const ENEMY_HERO_XP: int = 150
const ENEMY_HERO_GOLD: int = 50
const CREEP_XP_SHARE_RANGE: float = 18.0

# --- Neutral camps ---
const CREEP_CAMP_RESPAWN_DELAY_SECONDS: float = 180.0
