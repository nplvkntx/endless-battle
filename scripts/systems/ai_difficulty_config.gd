class_name AIDifficultyConfig
extends RefCounted

## Centralized AI difficulty settings.
## Difficulty changes AI production capacity only — not player rules,
## creeping, expansions, upgrades, towers, hero usage, or attack logic.

enum Difficulty {
	EASY,
	NORMAL,
	HARD,
}

const DEFAULT_DIFFICULTY: int = Difficulty.NORMAL

## Hard caps for military production buildings per difficulty.
const MAX_BARRACKS_BY_DIFFICULTY: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.NORMAL: 2,
	Difficulty.HARD: 4,
}

const MAX_STABLES_BY_DIFFICULTY: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.NORMAL: 2,
	Difficulty.HARD: 4,
}

const MAX_ARTILLERY_DEPOTS_BY_DIFFICULTY: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.NORMAL: 2,
	Difficulty.HARD: 4,
}


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


static func max_barracks(difficulty: int = -1) -> int:
	if difficulty < 0:
		difficulty = MatchSession.ai_difficulty
	return int(MAX_BARRACKS_BY_DIFFICULTY.get(clamp_difficulty(difficulty), 2))


static func max_stables(difficulty: int = -1) -> int:
	if difficulty < 0:
		difficulty = MatchSession.ai_difficulty
	return int(MAX_STABLES_BY_DIFFICULTY.get(clamp_difficulty(difficulty), 2))


static func max_artillery_depots(difficulty: int = -1) -> int:
	if difficulty < 0:
		difficulty = MatchSession.ai_difficulty
	return int(MAX_ARTILLERY_DEPOTS_BY_DIFFICULTY.get(clamp_difficulty(difficulty), 2))


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
