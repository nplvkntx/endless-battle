class_name HeroProgressionStore
extends RefCounted

## Session-persistent hero progression used when a hero dies and is trained again.
## Player and enemy heroes keep separate snapshots so factions cannot overwrite each other.
## Also stores the faction-wide hero kit lock for the current match (one hero type per side).
## Living hero instances are tracked by instance ID (never stored as permanent ObjectRefs).

static var _player_snapshot: Dictionary = {}
static var _enemy_snapshot: Dictionary = {}
## Locked kit IDs for the match. Empty StringName means no hero chosen yet.
static var _player_locked_kit_id: StringName = &""
static var _enemy_locked_kit_id: StringName = &""
## Currently living hero instance IDs. 0 means no living hero.
static var _player_living_hero_id: int = 0
static var _enemy_living_hero_id: int = 0


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


## Register the currently living hero instance for a faction. Clears any prior ID.
static func register_living_hero(hero: Hero) -> void:
	if not NodeSafety.is_alive_node(hero) or not hero is Hero:
		return

	var is_enemy: bool = CombatTargetValidation.is_enemy_faction(hero)
	var hero_id: int = hero.get_instance_id()
	if is_enemy:
		_enemy_living_hero_id = hero_id
	else:
		_player_living_hero_id = hero_id

	## Living heroes reinforce the match kit lock without waiting for death.
	var kit_id: StringName = &""
	if hero.has_method(&"get_hero_kit_id"):
		kit_id = hero.get_hero_kit_id()
	if kit_id != &"":
		lock_kit(is_enemy, kit_id)


## Clear the living-hero registry entry for this hero (or faction if hero is null/invalid).
static func clear_living_hero(hero: Variant = null, is_enemy: bool = false) -> void:
	if hero != null and is_instance_valid(hero) and hero is Hero:
		is_enemy = CombatTargetValidation.is_enemy_faction(hero as Hero)
		var hero_id: int = (hero as Object).get_instance_id()
		if is_enemy:
			if _enemy_living_hero_id == hero_id:
				_enemy_living_hero_id = 0
		else:
			if _player_living_hero_id == hero_id:
				_player_living_hero_id = 0
		return

	if is_enemy:
		_enemy_living_hero_id = 0
	else:
		_player_living_hero_id = 0


static func has_living_hero(is_enemy: bool) -> bool:
	return get_living_hero(is_enemy) != null


## Safe living-hero lookup. Never returns a freed Object. Clears stale IDs automatically.
static func get_living_hero(is_enemy: bool) -> Hero:
	var hero_id: int = _enemy_living_hero_id if is_enemy else _player_living_hero_id
	if hero_id == 0:
		return null

	var node_ref: Variant = instance_from_id(hero_id)
	if not NodeSafety.is_alive_node(node_ref) or not node_ref is Hero:
		if is_enemy:
			_enemy_living_hero_id = 0
		else:
			_player_living_hero_id = 0
		return null

	var hero: Hero = node_ref as Hero
	if CombatTargetValidation.is_enemy_faction(hero) != is_enemy:
		if is_enemy:
			_enemy_living_hero_id = 0
		else:
			_player_living_hero_id = 0
		return null

	var health_component: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
	if health_component != null and health_component.current_health <= 0:
		if is_enemy:
			_enemy_living_hero_id = 0
		else:
			_player_living_hero_id = 0
		return null

	return hero


## Resolve a Variant into a living Hero without typed assignment of freed objects.
static func as_living_hero(hero_ref: Variant) -> Hero:
	if not NodeSafety.is_alive_node(hero_ref) or not hero_ref is Hero:
		return null

	var hero: Hero = hero_ref as Hero
	var health_component: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
	if health_component != null and health_component.current_health <= 0:
		return null

	return hero


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
	_player_living_hero_id = 0
	_enemy_living_hero_id = 0
