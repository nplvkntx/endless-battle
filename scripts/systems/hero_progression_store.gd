class_name HeroProgressionStore
extends RefCounted

## Session-persistent hero progression used when a hero dies and is trained again.

static var _snapshot: Dictionary = {}


static func has_saved_progression() -> bool:
	return not _snapshot.is_empty()


static func save_from_hero(hero: Hero) -> void:
	if hero == null or not is_instance_valid(hero):
		return

	_snapshot = hero.export_progression_snapshot()


static func apply_to_hero(hero: Hero) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false

	if _snapshot.is_empty():
		return false

	hero.restore_progression_snapshot(_snapshot)
	return true


static func clear() -> void:
	_snapshot.clear()
