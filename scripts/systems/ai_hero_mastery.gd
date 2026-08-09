extends Node

## Enemy hero kit selection only — once per match before first Altar train.
## No tactical micro, retreat, creeping, or strategic movement.

const AI_HERO_POOL: Array[StringName] = [
	HeroCatalog.KIT_PALADIN,
	HeroCatalog.KIT_SHADOW_ASSASSIN,
	HeroCatalog.KIT_RANGER,
]

var _selection_announced: bool = false
var _forced_kit_override: StringName = &""
var _suppress_selection_log: bool = false


func reset_match_state() -> void:
	_selection_announced = false
	_forced_kit_override = &""
	_suppress_selection_log = false


func set_forced_kit_for_tests(kit_id: StringName) -> void:
	_forced_kit_override = HeroCatalog.normalize_kit_id(kit_id) if kit_id != &"" else &""


func set_suppress_selection_log_for_tests(suppress: bool) -> void:
	_suppress_selection_log = suppress


## Choose and lock the AI hero once per match. Never rerolls.
func ensure_enemy_hero_choice() -> StringName:
	if HeroProgressionStore.has_locked_kit(true):
		var locked: StringName = HeroProgressionStore.get_locked_kit_id(true)
		_announce_selection_once(locked)
		return locked

	var kit_id: StringName = _pick_enemy_hero_kit()
	HeroProgressionStore.lock_kit(true, kit_id)
	_announce_selection_once(kit_id)
	return kit_id


func _pick_enemy_hero_kit() -> StringName:
	if _forced_kit_override != &"" and HeroCatalog.is_valid_kit(_forced_kit_override):
		return _forced_kit_override

	var saved: StringName = HeroProgressionStore.get_saved_kit_id(true)
	if saved != &"":
		return HeroCatalog.normalize_kit_id(saved)

	var index: int = randi() % AI_HERO_POOL.size()
	return AI_HERO_POOL[index]


func _announce_selection_once(kit_id: StringName) -> void:
	if _selection_announced:
		return
	_selection_announced = true
	if _suppress_selection_log:
		return
	print("AI selected hero: %s" % HeroCatalog.get_display_name(kit_id))
