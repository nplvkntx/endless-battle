class_name UpgradeStats
extends RefCounted

## Canonical upgrade costs, research times, and effect multipliers.
## Runtime level state stays in UpgradeManager; numbers live here only.

const BLACKSMITH_MAX_LEVEL: int = 5
const ACADEMY_MAX_LEVEL: int = 1

## Blacksmith level gold = wood cost per next level index 0..4.
const BLACKSMITH_LEVEL_COSTS: Array[int] = [100, 150, 225, 325, 450]
const BLACKSMITH_RESEARCH_SECONDS: float = 5.0

## Stable cavalry upgrade cost formula: base + (current_level * per_level).
const STABLE_UPGRADE_BASE_GOLD: int = 150
const STABLE_UPGRADE_BASE_WOOD: int = 75
const STABLE_UPGRADE_GOLD_PER_LEVEL: int = 100
const STABLE_UPGRADE_WOOD_PER_LEVEL: int = 50
const STABLE_RESEARCH_SECONDS: float = 5.0
const CAVALRY_ATTACK_DAMAGE_PER_LEVEL: int = 3
const CAVALRY_DEFENSE_ARMOR_PER_LEVEL: int = 1

## Academy one-shot research costs / times.
const ACADEMY_FASTER_GATHERING_GOLD: int = 1000
const ACADEMY_FASTER_GATHERING_WOOD: int = 700
const ACADEMY_FASTER_GATHERING_SECONDS: float = 60.0
const ACADEMY_FASTER_UNIT_TRAINING_GOLD: int = 1200
const ACADEMY_FASTER_UNIT_TRAINING_WOOD: int = 900
const ACADEMY_FASTER_UNIT_TRAINING_SECONDS: float = 75.0
const ACADEMY_IMPROVED_TOOLS_GOLD: int = 900
const ACADEMY_IMPROVED_TOOLS_WOOD: int = 700
const ACADEMY_IMPROVED_TOOLS_SECONDS: float = 60.0
const ACADEMY_ENGINEERING_GOLD: int = 1500
const ACADEMY_ENGINEERING_WOOD: int = 1200
const ACADEMY_ENGINEERING_SECONDS: float = 90.0
const ACADEMY_BALLISTICS_GOLD: int = 1800
const ACADEMY_BALLISTICS_WOOD: int = 1200
const ACADEMY_BALLISTICS_SECONDS: float = 90.0

## Effect multipliers when researched.
const FASTER_GATHERING_SPEED_MULTIPLIER: float = 1.25
const FASTER_UNIT_TRAINING_SPEED_MULTIPLIER: float = 1.2
const IMPROVED_TOOLS_CONSTRUCTION_SPEED_MULTIPLIER: float = 1.2
const ENGINEERING_MAX_HEALTH_MULTIPLIER: float = 1.2
const BALLISTICS_DAMAGE_MULTIPLIER: float = 1.2
## Infantry blacksmith combat deltas live on UnitStats (used by unit scripts).

