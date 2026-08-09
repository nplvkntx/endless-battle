class_name AIDifficultyConfig
extends RefCounted

## UI/settings difficulty labels only. Does not affect enemy AI runtime behavior.

enum Difficulty {
	EASY,
	NORMAL,
	HARD,
}

const DEFAULT_DIFFICULTY: int = Difficulty.NORMAL


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
