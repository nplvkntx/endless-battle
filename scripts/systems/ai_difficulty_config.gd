class_name AIDifficultyConfig
extends RefCounted

## Match difficulty labels AND runtime enemy AI economy/production knobs.
## Strategic brain stays identical; Easy/Normal/Hard only change capacity and Hard pace.

enum Difficulty {
	EASY,
	NORMAL,
	HARD,
}

const DEFAULT_DIFFICULTY: int = Difficulty.NORMAL

const HARD_RESOURCE_MULTIPLIER: float = 1.5
const HARD_TRAIN_SPEED_MULTIPLIER: float = 1.5

## Desired living workers by tech / expansion. Continuous short-queue production.
const DESIRED_WORKERS_T1: int = 13
const DESIRED_WORKERS_T2: int = 20
const DESIRED_WORKERS_T3: int = 28
const DESIRED_WORKERS_EXPANSION: int = 33

const MAX_MILITARY_EASY: int = 1
const MAX_MILITARY_NORMAL_HARD: int = 3

const DESIRED_TOWERS_EASY: int = 2
const DESIRED_TOWERS_NORMAL: int = 3
const DESIRED_TOWERS_HARD: int = 4


static func clamp_difficulty(difficulty: int) -> int:
	match difficulty:
		Difficulty.EASY, Difficulty.NORMAL, Difficulty.HARD:
			return difficulty
		_:
			return DEFAULT_DIFFICULTY


static func display_name(difficulty: int) -> String:
	match clamp_difficulty(difficulty):
		Difficulty.EASY:
			return "Easy"
		Difficulty.HARD:
			return "Hard"
		_:
			return "Normal"


static func all_display_names() -> PackedStringArray:
	return PackedStringArray(["Easy", "Normal", "Hard"])


static func difficulty_from_display_name(name: String) -> int:
	match name:
		"Easy":
			return Difficulty.EASY
		"Hard":
			return Difficulty.HARD
		_:
			return Difficulty.NORMAL


static func get_current_difficulty() -> int:
	if MatchSession == null:
		return DEFAULT_DIFFICULTY
	return clamp_difficulty(MatchSession.get_ai_difficulty())


static func get_enemy_resource_multiplier() -> float:
	if get_current_difficulty() == Difficulty.HARD:
		return HARD_RESOURCE_MULTIPLIER
	return 1.0


## Deterministic integer deposit amount after Hard income bonus.
static func scale_enemy_resource_amount(amount: int) -> int:
	if amount <= 0:
		return 0
	var multiplied: float = float(amount) * get_enemy_resource_multiplier()
	return maxi(1, int(round(multiplied)))


static func get_enemy_train_speed_multiplier() -> float:
	if get_current_difficulty() == Difficulty.HARD:
		return HARD_TRAIN_SPEED_MULTIPLIER
	return 1.0


## Max Barracks / Stable / Artillery Depot (Easy 1, Normal/Hard 3).
static func get_max_military_buildings(_building_type: StringName = &"") -> int:
	if get_current_difficulty() == Difficulty.EASY:
		return MAX_MILITARY_EASY
	return MAX_MILITARY_NORMAL_HARD


static func get_desired_worker_count(tier: int, has_expansion: bool) -> int:
	if has_expansion:
		return DESIRED_WORKERS_EXPANSION
	if tier >= 3:
		return DESIRED_WORKERS_T3
	if tier >= 2:
		return DESIRED_WORKERS_T2
	return DESIRED_WORKERS_T1


static func get_desired_tower_count() -> int:
	match get_current_difficulty():
		Difficulty.EASY:
			return DESIRED_TOWERS_EASY
		Difficulty.HARD:
			return DESIRED_TOWERS_HARD
		_:
			return DESIRED_TOWERS_NORMAL
