class_name HeroProgressionStore
extends RefCounted

## Session-persistent hero progression used when a hero dies and is trained again.
## Player and enemy heroes keep separate snapshots so factions cannot overwrite each other.
## Also stores the faction-wide hero kit lock for the current match (one hero type per side).

static var _player_snapshot: Dictionary = {}
static var _enemy_snapshot: Dictionary = {}
## Locked kit IDs for the match. Empty StringName means no hero chosen yet.
static var _player_locked_kit_id: StringName = &""
static var _enemy_locked_kit_id: StringName = &""


static func has_saved_progression() -> bool:
	return not _player_snapshot.is_empty()


static func has_saved_enemy_progression() -> bool:
	return not _enemy_snapshot.is_empty()


static func get_saved_kit_id(is_enemy: bool) -> StringName:
	var snapshot: Dictionary = _enemy_snapshot if is_enemy else _player_snapshot
	if snapshot.is_empty():
		return &""

	return StringName(str(snapshot.get("hero_kit_id", "")))


static func get_saved_level(is_enemy: bool) -> int:
	var snapshot: Dictionary = _enemy_snapshot if is_enemy else _player_snapshot
	if snapshot.is_empty():
		return 0
	return int(snapshot.get("level", 1))


static func has_locked_kit(is_enemy: bool) -> bool:
	return get_locked_kit_id(is_enemy) != &""


static func get_locked_kit_id(is_enemy: bool) -> StringName:
	var locked: StringName = _enemy_locked_kit_id if is_enemy else _player_locked_kit_id
	if locked == &"":
		return &""
	return HeroCatalog.normalize_kit_id(locked)


## Lock this faction to kit_id for the rest of the match.
## First successful call wins; later calls with a different kit are ignored.
## Returns true if this call newly locked (or reaffirmed the same kit).
static func lock_kit(is_enemy: bool, kit_id: StringName) -> bool:
	var normalized: StringName = HeroCatalog.normalize_kit_id(kit_id)
	var current: StringName = get_locked_kit_id(is_enemy)
	if current != &"":
		return current == normalized

	if is_enemy:
		_enemy_locked_kit_id = normalized
	else:
		_player_locked_kit_id = normalized
	return true


static func can_select_kit(is_enemy: bool, kit_id: StringName) -> bool:
	var locked: StringName = get_locked_kit_id(is_enemy)
	if locked == &"":
		return HeroCatalog.is_valid_kit(kit_id)
	return locked == HeroCatalog.normalize_kit_id(kit_id)


## Preferred kit for training: match lock > death snapshot > empty (caller chooses default).
static func get_faction_kit_id(is_enemy: bool) -> StringName:
	var locked: StringName = get_locked_kit_id(is_enemy)
	if locked != &"":
		return locked

	var saved: StringName = get_saved_kit_id(is_enemy)
	if saved != &"":
		return HeroCatalog.normalize_kit_id(saved)

	return &""


static func save_from_hero(hero: Hero) -> void:
	if hero == null or not is_instance_valid(hero):
		return

	var snapshot: Dictionary = hero.export_progression_snapshot()
	var is_enemy: bool = CombatTargetValidation.is_enemy_faction(hero)
	if is_enemy:
		_enemy_snapshot = snapshot
	else:
		_player_snapshot = snapshot

	## Death always reinforces the match lock to the hero that just died.
	var kit_id: StringName = StringName(str(snapshot.get("hero_kit_id", "")))
	if kit_id != &"":
		lock_kit(is_enemy, kit_id)


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
	_player_locked_kit_id = &""
	_enemy_locked_kit_id = &""
