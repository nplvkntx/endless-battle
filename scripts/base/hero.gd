class_name Hero
extends Unit

## Base class for hero units. Extends Unit with XP, leveling, abilities, inventory, and respawn.
## Hero-specific values must come from an external Resource — never hardcoded in this script.

signal xp_changed(current_xp: float, xp_to_next_level: float)
signal level_changed(new_level: int)
signal ability_points_changed(new_amount: int)
signal ability_progression_changed()
signal ability_ready(ability_id: StringName)
signal inventory_changed()
signal respawn_requested(hero: Hero)

const MAX_LEVEL: int = 24
const XP_PER_LEVEL_MULTIPLIER: int = 100
const MAX_ABILITY_POINT_LEVEL: int = 18
const HEALTH_PER_LEVEL: int = 25
const MANA_PER_LEVEL: int = 10
const ATTACK_DAMAGE_PER_LEVEL: int = 2
const BASE_MAX_HEALTH: int = 200
const INVENTORY_SLOT_COUNT: int = 6

@export var hero_data: Resource

var level: int = 1
var ability_points: int = 1
var ability_progression: HeroAbilityProgression = HeroAbilityProgression.new()
var inventory: Array = []
var _current_xp: float = 0.0


func _ready() -> void:
	_init_inventory()
	super._ready()
	if level < 1:
		level = 1
	if ability_progression == null:
		ability_progression = HeroAbilityProgression.new()
	_apply_hero_data()
	_emit_xp_state()


func _init_inventory() -> void:
	inventory.clear()
	inventory.resize(INVENTORY_SLOT_COUNT)
	for slot_index: int in INVENTORY_SLOT_COUNT:
		inventory[slot_index] = null


func get_inventory_slot_count() -> int:
	return INVENTORY_SLOT_COUNT


func get_item_at_slot(slot_index: int):
	if not _is_valid_inventory_slot(slot_index):
		return null

	return inventory[slot_index]


func find_first_empty_inventory_slot() -> int:
	for slot_index: int in inventory.size():
		if inventory[slot_index] == null:
			return slot_index

	return -1


func is_inventory_full() -> bool:
	return find_first_empty_inventory_slot() < 0


func set_item_at_slot(slot_index: int, item) -> bool:
	if not _is_valid_inventory_slot(slot_index):
		return false

	inventory[slot_index] = item
	inventory_changed.emit()
	return true


func clear_item_at_slot(slot_index: int) -> bool:
	return set_item_at_slot(slot_index, null)


func _is_valid_inventory_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < inventory.size()


func get_current_xp() -> float:
	return _current_xp


func get_xp_required_for_next_level() -> float:
	if level >= MAX_LEVEL:
		return 0.0

	return float(XP_PER_LEVEL_MULTIPLIER * level)


func add_xp(amount: float) -> void:
	if amount <= 0.0 or level >= MAX_LEVEL:
		return

	_current_xp += amount
	while level < MAX_LEVEL and _current_xp >= get_xp_required_for_next_level():
		_current_xp -= get_xp_required_for_next_level()
		level += 1
		_on_level_up()

	_emit_xp_state()


func is_ability_unlocked(ability_id: StringName) -> bool:
	if ability_progression == null:
		return false

	return ability_progression.is_ability_learned(ability_id)


func get_ability_rank(ability_id: StringName) -> int:
	if ability_progression == null:
		return 0

	return ability_progression.get_ability_rank(ability_id)


func can_learn_ability(ability_id: StringName) -> bool:
	if ability_progression == null:
		return false

	return ability_progression.can_learn_ability(level, ability_points, ability_id)


func can_show_ability_upgrade(ability_id: StringName) -> bool:
	if ability_progression == null:
		return false

	return ability_progression.can_show_upgrade_arrow(level, ability_points, ability_id)


func try_learn_ability(ability_id: StringName) -> bool:
	if ability_progression == null:
		push_warning("Hero.try_learn_ability: missing ability progression")
		return false

	if ability_progression.can_learn_ability(level, ability_points, ability_id):
		ability_points -= 1
		ability_progression.learn_ability(ability_id)
		ability_points_changed.emit(ability_points)
		ability_progression_changed.emit()
		print(
			"Learned ability %s (rank %d). Ability points remaining: %d"
			% [ability_id, get_ability_rank(ability_id), ability_points]
		)
		return true

	var reason: String = ability_progression.get_learn_blocked_reason(
		level, ability_points, ability_id
	)
	if ResourceManager != null:
		ResourceManager.show_feedback(reason)
	else:
		print(reason)
	return false


func _require_ability_learned(ability_id: StringName) -> bool:
	if is_ability_unlocked(ability_id):
		return true

	if ResourceManager != null:
		ResourceManager.show_feedback("Ability locked")
	else:
		print("Ability locked")
	return false


func _on_level_up() -> void:
	if level <= MAX_ABILITY_POINT_LEVEL:
		ability_points += 1
		ability_points_changed.emit(ability_points)

	_apply_level_stat_gains()
	level_changed.emit(level)
	_show_level_up_feedback()
	print("Level Up! Hero reached level %d" % level)
	print("Ability points: %d" % ability_points)


func _apply_level_stat_gains() -> void:
	_apply_level_health_gain()
	_apply_level_mana_gain()
	_apply_level_attack_damage_gain()


func _apply_level_health_gain() -> void:
	var health_component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		return

	health_component.max_health += HEALTH_PER_LEVEL
	health_component.current_health = mini(
		health_component.current_health + HEALTH_PER_LEVEL,
		health_component.max_health
	)
	health_component.health_changed.emit(health_component.current_health, health_component.max_health)


func _apply_level_mana_gain() -> void:
	pass


func _apply_level_attack_damage_gain() -> void:
	pass


func _show_level_up_feedback() -> void:
	FloatingDamageNumber.spawn_message(
		self, "Level Up!", Color(0.45, 0.85, 1.0, 1.0), true
	)


func _emit_xp_state() -> void:
	xp_changed.emit(_current_xp, get_xp_required_for_next_level())


func export_progression_snapshot() -> Dictionary:
	var ability_ranks: Dictionary = {}
	if ability_progression != null:
		ability_ranks = ability_progression.export_ranks()

	return {
		"level": level,
		"current_xp": _current_xp,
		"ability_points": ability_points,
		"ability_ranks": ability_ranks,
		"inventory_item_ids": _export_inventory_item_ids(),
	}


func _export_inventory_item_ids() -> Array:
	var item_ids: Array = []
	for slot_index: int in inventory.size():
		var item = inventory[slot_index]
		if item is HeroItemDefinition:
			item_ids.append(String((item as HeroItemDefinition).item_id))
		else:
			item_ids.append("")

	return item_ids


func restore_progression_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return

	level = maxi(1, int(snapshot.get("level", 1)))
	_current_xp = maxf(0.0, float(snapshot.get("current_xp", 0.0)))
	ability_points = maxi(0, int(snapshot.get("ability_points", 0)))

	if ability_progression == null:
		ability_progression = HeroAbilityProgression.new()
	ability_progression.import_ranks(snapshot.get("ability_ranks", {}))

	_reapply_all_level_stat_scaling()
	_restore_inventory_from_snapshot(snapshot.get("inventory_item_ids", []))

	_emit_xp_state()
	ability_points_changed.emit(ability_points)
	level_changed.emit(level)
	ability_progression_changed.emit()
	_on_progression_restored()


func _reapply_all_level_stat_scaling() -> void:
	var health_component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
	if health_component != null:
		health_component.max_health = BASE_MAX_HEALTH + (level - 1) * HEALTH_PER_LEVEL
		health_component.current_health = health_component.max_health
		health_component.health_changed.emit(
			health_component.current_health, health_component.max_health
		)

	_apply_accumulated_level_combat_stats(maxi(0, level - 1))


func _apply_accumulated_level_combat_stats(_levels_gained: int) -> void:
	pass


func _on_progression_restored() -> void:
	pass


func _restore_inventory_from_snapshot(item_ids: Array) -> void:
	_init_inventory()

	for slot_index: int in inventory.size():
		if slot_index >= item_ids.size():
			break

		var item_id_text: String = String(item_ids[slot_index])
		if item_id_text.is_empty():
			continue

		var item: HeroItemDefinition = HeroItemCatalog.get_definition(StringName(item_id_text))
		if item == null:
			continue

		inventory[slot_index] = item

	HeroItemService.restore_inventory_items(self)


## Loads hero-specific runtime state from hero_data when the data pipeline is available.
func _apply_hero_data() -> void:
	# TODO: Read hero stats and ability slots from hero_data Resource.
	pass
