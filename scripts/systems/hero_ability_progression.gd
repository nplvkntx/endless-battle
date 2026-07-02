class_name HeroAbilityProgression
extends RefCounted

## Warcraft III-style ability rank rules for heroes. Reusable for player and AI heroes.

const ABILITY_Q := &"q"
const ABILITY_W := &"w"
const ABILITY_E := &"e"
const ABILITY_R := &"r"

const BASIC_ABILITIES: Array[StringName] = [ABILITY_Q, ABILITY_W, ABILITY_E]

const R_FIRST_RANK_LEVEL: int = 6
const R_SECOND_RANK_LEVEL: int = 11
const R_THIRD_RANK_LEVEL: int = 16

const MAX_BASIC_RANK: int = 5
const MAX_ULTIMATE_RANK: int = 3

var _ranks: Dictionary = {
	ABILITY_Q: 0,
	ABILITY_W: 0,
	ABILITY_E: 0,
	ABILITY_R: 0,
}


func get_ability_rank(ability_id: StringName) -> int:
	return int(_ranks.get(ability_id, 0))


func get_max_rank(ability_id: StringName) -> int:
	if ability_id == ABILITY_R:
		return MAX_ULTIMATE_RANK

	return MAX_BASIC_RANK


func is_ability_learned(ability_id: StringName) -> bool:
	return get_ability_rank(ability_id) > 0


func can_learn_ability(hero_level: int, ability_points: int, ability_id: StringName) -> bool:
	if ability_points <= 0:
		return false

	if not _is_valid_ability_id(ability_id):
		return false

	var current_rank: int = get_ability_rank(ability_id)
	if ability_id == ABILITY_R:
		return _can_learn_ultimate_rank(hero_level, current_rank)

	if current_rank >= MAX_BASIC_RANK:
		return false

	return hero_level >= 1


func can_show_upgrade_arrow(hero_level: int, ability_points: int, ability_id: StringName) -> bool:
	return can_learn_ability(hero_level, ability_points, ability_id)


func get_learn_blocked_reason(hero_level: int, ability_points: int, ability_id: StringName) -> String:
	if not _is_valid_ability_id(ability_id):
		return "Unknown ability"

	if ability_points <= 0:
		return "Not enough ability points"

	var current_rank: int = get_ability_rank(ability_id)
	if ability_id == ABILITY_R:
		return _get_ultimate_learn_blocked_reason(hero_level, current_rank)

	if current_rank >= MAX_BASIC_RANK:
		return "Ability is max rank"

	return "Cannot learn ability"


func learn_ability(ability_id: StringName) -> void:
	if not _is_valid_ability_id(ability_id):
		return

	_ranks[ability_id] = get_ability_rank(ability_id) + 1


func export_ranks() -> Dictionary:
	return _ranks.duplicate()


func import_ranks(data: Variant) -> void:
	if data == null or not data is Dictionary:
		return

	for ability_id: StringName in _ranks.keys():
		_ranks[ability_id] = int((data as Dictionary).get(ability_id, 0))


func get_ultimate_rank_unlock_level(target_rank: int) -> int:
	match target_rank:
		1:
			return R_FIRST_RANK_LEVEL
		2:
			return R_SECOND_RANK_LEVEL
		3:
			return R_THIRD_RANK_LEVEL
		_:
			return R_THIRD_RANK_LEVEL


func _can_learn_ultimate_rank(hero_level: int, current_rank: int) -> bool:
	var target_rank: int = current_rank + 1
	if target_rank > MAX_ULTIMATE_RANK:
		return false

	return hero_level >= get_ultimate_rank_unlock_level(target_rank)


func _get_ultimate_learn_blocked_reason(hero_level: int, current_rank: int) -> String:
	var target_rank: int = current_rank + 1
	if target_rank > MAX_ULTIMATE_RANK:
		return "Ultimate is max rank"

	var required_level: int = get_ultimate_rank_unlock_level(target_rank)
	if hero_level < required_level:
		return "Ultimate rank %d unlocks at level %d" % [target_rank, required_level]

	return "Cannot learn ultimate"


func _is_valid_ability_id(ability_id: StringName) -> bool:
	return _ranks.has(ability_id)
