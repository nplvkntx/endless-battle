class_name HeroProgressionStore
extends RefCounted

## Session-persistent hero progression used when a hero dies and is trained again.
## Player and enemy heroes keep separate snapshots so factions cannot overwrite each other.

static var _player_snapshot: Dictionary = {}
static var _enemy_snapshot: Dictionary = {}


static func has_saved_progression() -> bool:
	return not _player_snapshot.is_empty()


static func has_saved_enemy_progression() -> bool:
	return not _enemy_snapshot.is_empty()


static func save_from_hero(hero: Hero) -> void:
	if hero == null or not is_instance_valid(hero):
		return

	var snapshot: Dictionary = hero.export_progression_snapshot()
	if CombatTargetValidation.is_enemy_faction(hero):
		_enemy_snapshot = snapshot
	else:
		_player_snapshot = snapshot


static func apply_to_hero(hero: Hero) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false

	var snapshot: Dictionary = (
		_enemy_snapshot if CombatTargetValidation.is_enemy_faction(hero) else _player_snapshot
	)
	if snapshot.is_empty():
		return false

	hero.restore_progression_snapshot(snapshot)
	return true


static func clear() -> void:
	_player_snapshot.clear()
	_enemy_snapshot.clear()
