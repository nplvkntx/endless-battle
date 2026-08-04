class_name HeroItemService
extends RefCounted

## Applies hero item purchases, combines, and combat bonus helpers.

const SHOP_PURCHASE_RANGE_PIXELS: float = ItemStats.SHOP_PURCHASE_RANGE_PIXELS
const SHOP_PURCHASE_RANGE_WORLD_FALLBACK: float = ItemStats.SHOP_PURCHASE_RANGE_WORLD_FALLBACK

const MSG_NO_NEARBY_HERO := "Move a hero near the shop"
const MSG_INVENTORY_FULL := "Hero inventory is full"
const MSG_NOT_ENOUGH_GOLD := "Not enough gold"
const MSG_SHOP_UNAVAILABLE := "Shop cannot sell items"
const MSG_RECIPE_UNAVAILABLE := "Item cannot be combined"
const SELL_REFUND_RATIO := ItemStats.SELL_REFUND_RATIO


static func try_purchase_from_shop(shop: Shop, item_id: StringName) -> bool:
	var item: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if item == null:
		return false

	var failure_reason: String = get_purchase_failure_reason(shop, item)
	if not failure_reason.is_empty():
		_show_feedback(failure_reason, shop)
		return false

	var hero: Hero = find_closest_shop_hero(shop)
	if hero == null:
		_show_feedback(MSG_NO_NEARBY_HERO, shop)
		return false

	var purchased: bool = false
	if item.has_recipe() and _hero_owns_all_recipe_components(hero, item):
		purchased = _purchase_completed_from_components(shop, hero, item)
	else:
		purchased = _purchase_into_empty_slot(shop, hero, item)

	if not purchased:
		return false

	_try_auto_combine_craftable(hero)
	return true


static func get_purchase_failure_reason(shop: Shop, item: HeroItemDefinition) -> String:
	if shop == null or item == null:
		return MSG_SHOP_UNAVAILABLE

	if shop.building_state != Building.STATE_COMPLETED:
		return MSG_SHOP_UNAVAILABLE

	var hero: Hero = find_closest_shop_hero(shop)
	if hero == null:
		return MSG_NO_NEARBY_HERO

	if item.has_recipe() and _hero_owns_all_recipe_components(hero, item):
		var recipe_cost: int = item.get_recipe_gold_cost()
		if not _can_afford_item(shop, recipe_cost):
			return MSG_NOT_ENOUGH_GOLD
		return ""

	if hero.is_inventory_full():
		return MSG_INVENTORY_FULL

	if not _can_afford_item(shop, item.gold_cost):
		return MSG_NOT_ENOUGH_GOLD

	return ""


static func can_purchase_from_shop(shop: Shop, item_id: StringName) -> bool:
	var item: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if item == null:
		return false

	return get_purchase_failure_reason(shop, item).is_empty()


static func find_closest_shop_hero(shop: Shop) -> Hero:
	if shop == null or not is_instance_valid(shop):
		return null

	var tree: SceneTree = shop.get_tree()
	if tree == null:
		return null

	var shop_team: int = TeamVisuals.resolve_team(shop, shop.team_id)
	var closest_hero: Hero = null
	var closest_distance: float = INF
	var seen_heroes: Dictionary = {}

	for group_name: StringName in [&"units", &"heroes", &"enemies"]:
		for node: Node in tree.get_nodes_in_group(group_name):
			if seen_heroes.has(node.get_instance_id()):
				continue

			var candidate: Hero = _get_shop_hero_candidate(node, shop, shop_team)
			if candidate == null:
				continue

			seen_heroes[candidate.get_instance_id()] = true
			var distance: float = _get_shop_range_distance(shop, candidate)
			if distance > _get_shop_range_limit(shop):
				continue

			if distance < closest_distance:
				closest_distance = distance
				closest_hero = candidate

	return closest_hero


static func is_hero_in_shop_range(shop: Shop, hero: Hero) -> bool:
	if shop == null or hero == null or not is_instance_valid(shop) or not is_instance_valid(hero):
		return false

	var distance: float = _get_shop_range_distance(shop, hero)
	return distance <= _get_shop_range_limit(shop)


static func apply_item_to_hero(
	hero: Hero,
	item: HeroItemDefinition,
	grant_immediate_bonuses: bool
) -> void:
	if hero == null or item == null:
		return

	if item.bonus_attack_damage != 0 and "attack_damage" in hero:
		hero.set("attack_damage", float(hero.get("attack_damage")) + float(item.bonus_attack_damage))

	if item.bonus_move_speed != 0.0 and not item.is_unique_move_speed:
		hero.move_speed += item.bonus_move_speed

	_apply_spell_stat_bonus(hero, item)
	_apply_combat_stat_bonus(hero, item)
	_apply_health_bonus(hero, item, grant_immediate_bonuses)
	_apply_mana_bonus(hero, item, grant_immediate_bonuses)

	if item.is_unique_move_speed:
		_recompute_unique_move_speed(hero)


static func can_modify_player_inventory(hero: Hero) -> bool:
	if hero == null or not is_instance_valid(hero) or hero.is_queued_for_deletion():
		return false

	return TeamVisuals.resolve_team(hero, hero.team_id) == TeamVisuals.PLAYER_TEAM_ID


static func try_reorder_inventory_slot(hero: Hero, from_index: int, to_index: int) -> bool:
	if not can_modify_player_inventory(hero):
		return false

	if not hero.reorder_inventory_slot(from_index, to_index):
		return false

	_sync_item_runtime(hero)
	return true


static func try_sell_inventory_item(hero: Hero, slot_index: int) -> bool:
	if not can_modify_player_inventory(hero):
		return false

	var item = hero.get_item_at_slot(slot_index)
	if not item is HeroItemDefinition:
		return false

	var definition: HeroItemDefinition = item as HeroItemDefinition
	remove_item_from_hero(hero, definition)
	hero.remove_item_at_slot(slot_index)
	_sync_item_runtime(hero)

	var refund: int = get_sell_value(definition)
	if refund > 0:
		ResourceManager.add_gold(refund)

	return true


static func get_sell_value(item: HeroItemDefinition) -> int:
	if item == null:
		return 0
	return item.get_sell_value()


static func remove_item_from_hero(hero: Hero, item: HeroItemDefinition) -> void:
	if hero == null or item == null:
		return

	if item.bonus_attack_damage != 0 and "attack_damage" in hero:
		hero.set(
			"attack_damage",
			maxf(0.0, float(hero.get("attack_damage")) - float(item.bonus_attack_damage))
		)

	if item.bonus_move_speed != 0.0 and not item.is_unique_move_speed:
		hero.move_speed = maxf(0.0, hero.move_speed - item.bonus_move_speed)

	_remove_spell_stat_bonus(hero, item)
	_remove_combat_stat_bonus(hero, item)
	_remove_health_bonus(hero, item)
	_remove_mana_bonus(hero, item)

	if item.is_unique_move_speed:
		_recompute_unique_move_speed(hero)


static func restore_inventory_items(hero: Hero) -> void:
	if hero == null:
		return

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition:
			apply_item_to_hero(hero, item as HeroItemDefinition, false)

	_sync_item_runtime(hero)
	hero.inventory_changed.emit()


static func hero_has_unique_passive(hero: Hero, unique_key: StringName) -> bool:
	if hero == null or unique_key == &"":
		return false

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if not item is HeroItemDefinition:
			continue
		var definition: HeroItemDefinition = item as HeroItemDefinition
		if definition.get_unique_passive_id() == unique_key:
			return true
		for passive: ItemPassiveComponent in definition.get_passive_components():
			if passive.is_unique and passive.get_unique_key() == unique_key:
				return true
	return false


static func can_combine_item(hero: Hero, item_id: StringName) -> bool:
	var definition: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if hero == null or definition == null or not definition.has_recipe():
		return false

	return get_combine_failure_reason(hero, definition).is_empty()


static func get_combine_failure_reason(hero: Hero, item: HeroItemDefinition) -> String:
	if hero == null or item == null:
		return MSG_RECIPE_UNAVAILABLE
	if not item.has_recipe():
		return MSG_RECIPE_UNAVAILABLE

	if not _hero_owns_all_recipe_components(hero, item):
		return MSG_RECIPE_UNAVAILABLE

	var gold_cost: int = item.get_recipe_gold_cost()
	if gold_cost > 0 and not _can_afford_for_hero(hero, gold_cost):
		return MSG_NOT_ENOUGH_GOLD

	return ""


static func try_combine_item(hero: Hero, item_id: StringName) -> bool:
	var definition: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
	if definition == null or not definition.has_recipe():
		return false

	var failure_reason: String = get_combine_failure_reason(hero, definition)
	if not failure_reason.is_empty():
		return false

	var component_slots: Array[int] = _find_recipe_component_slots(hero, definition)
	if component_slots.size() != definition.recipe_component_ids.size():
		return false

	var recipe_cost: int = definition.get_recipe_gold_cost()
	if not _try_pay_for_hero(hero, recipe_cost):
		return false

	var preferred_slot: int = component_slots[0]
	for slot_index: int in component_slots:
		preferred_slot = mini(preferred_slot, slot_index)
		var owned = hero.get_item_at_slot(slot_index)
		if owned is HeroItemDefinition:
			remove_item_from_hero(hero, owned as HeroItemDefinition)
		hero.clear_item_at_slot(slot_index)

	var place_slot: int = preferred_slot
	if hero.get_item_at_slot(place_slot) != null:
		place_slot = hero.find_first_empty_inventory_slot()
	if place_slot < 0:
		return false

	hero.set_item_at_slot(place_slot, definition)
	apply_item_to_hero(hero, definition, true)
	_sync_item_runtime(hero)
	return true


static func can_use_active(hero: Hero, slot_index: int) -> bool:
	if hero == null:
		return false
	var item = hero.get_item_at_slot(slot_index)
	if not item is HeroItemDefinition:
		return false
	var definition: HeroItemDefinition = item as HeroItemDefinition
	if not definition.has_active():
		return false
	var runtime: HeroItemRuntime = HeroItemRuntime.ensure_on(hero)
	return runtime != null and runtime.is_ready(slot_index, definition)


## Active use is framework-only — spends cooldown/charges but has no gameplay effect yet.
static func try_use_active(hero: Hero, slot_index: int) -> bool:
	if not can_use_active(hero, slot_index):
		return false
	var item = hero.get_item_at_slot(slot_index)
	var definition: HeroItemDefinition = item as HeroItemDefinition
	var runtime: HeroItemRuntime = HeroItemRuntime.ensure_on(hero)
	if runtime == null:
		return false
	return runtime.begin_activation(slot_index, definition)


static func get_item_runtime(hero: Hero) -> HeroItemRuntime:
	return HeroItemRuntime.find_on(hero)


static func get_total_crit_chance(hero: Hero) -> float:
	if hero == null:
		return 0.0
	return maxf(0.0, hero.item_bonus_crit_chance)


static func get_total_lifesteal(hero: Hero) -> float:
	if hero == null:
		return 0.0

	var total: float = maxf(0.0, hero.item_bonus_lifesteal)
	if not hero_has_unique_passive(hero, ItemStats.UNIQUE_BLOODLORD_LOW_HP_LIFESTEAL):
		return total

	var health: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.max_health <= 0:
		return total

	var hp_ratio: float = float(health.current_health) / float(health.max_health)
	if hp_ratio >= ItemStats.BLOODLORD_LOW_HP_THRESHOLD:
		return total

	var extra: float = ItemStats.BLOODLORD_EXTRA_LIFESTEAL
	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if not item is HeroItemDefinition:
			continue
		var definition: HeroItemDefinition = item as HeroItemDefinition
		if definition.get_unique_passive_id() != ItemStats.UNIQUE_BLOODLORD_LOW_HP_LIFESTEAL:
			continue
		if definition.low_hp_extra_lifesteal > extra:
			extra = definition.low_hp_extra_lifesteal

	return total + extra


static func get_best_cleave(hero: Hero) -> Dictionary:
	var best := {"ratio": 0.0, "radius": 0.0}
	if hero == null:
		return best

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if not item is HeroItemDefinition:
			continue
		var definition: HeroItemDefinition = item as HeroItemDefinition
		if definition.cleave_ratio > float(best["ratio"]):
			best["ratio"] = definition.cleave_ratio
			best["radius"] = definition.cleave_radius

	return best


static func get_best_execute_bonus(hero: Hero) -> float:
	var best: float = 0.0
	if hero == null:
		return best

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if not item is HeroItemDefinition:
			continue
		var definition: HeroItemDefinition = item as HeroItemDefinition
		if definition.execute_bonus_ratio > best:
			best = definition.execute_bonus_ratio

	return best


static func get_aura_bonuses_for_unit(hero_carrier: Hero, ally_unit: Node) -> Dictionary:
	var result := {"armor": 0.0, "attack_speed": 0.0}
	if (
		hero_carrier == null
		or ally_unit == null
		or not is_instance_valid(hero_carrier)
		or not is_instance_valid(ally_unit)
		or not ally_unit is Node3D
	):
		return result

	# Hero receives only direct item stats — not its own aura.
	if ally_unit == hero_carrier or ally_unit is Hero:
		return result
	if not _is_normal_military_unit(ally_unit):
		return result

	var best_by_unique: Dictionary = {}
	var non_unique: Array[Dictionary] = []

	for slot_index: int in hero_carrier.get_inventory_slot_count():
		var item = hero_carrier.get_item_at_slot(slot_index)
		if not item is HeroItemDefinition:
			continue
		var definition: HeroItemDefinition = item as HeroItemDefinition
		if definition.aura_armor_bonus <= 0.0 and definition.aura_attack_speed_bonus <= 0.0:
			continue

		var radius: float = definition.aura_radius
		if radius <= 0.0:
			radius = ItemStats.DEFAULT_AURA_RADIUS

		var entry := {
			"armor": definition.aura_armor_bonus,
			"attack_speed": definition.aura_attack_speed_bonus,
			"radius": radius,
			"magnitude": definition.aura_armor_bonus + definition.aura_attack_speed_bonus,
		}
		var unique_id: StringName = definition.get_unique_passive_id()
		if unique_id == &"":
			non_unique.append(entry)
			continue

		if not best_by_unique.has(unique_id):
			best_by_unique[unique_id] = entry
			continue

		var previous: Dictionary = best_by_unique[unique_id] as Dictionary
		if float(entry["magnitude"]) > float(previous["magnitude"]):
			best_by_unique[unique_id] = entry

	var ally_position: Vector3 = (ally_unit as Node3D).global_position
	var carrier_position: Vector3 = hero_carrier.global_position

	for unique_id: Variant in best_by_unique.keys():
		var entry: Dictionary = best_by_unique[unique_id] as Dictionary
		if _is_within_horizontal_radius(carrier_position, ally_position, float(entry["radius"])):
			result["armor"] = float(result["armor"]) + float(entry["armor"])
			result["attack_speed"] = float(result["attack_speed"]) + float(entry["attack_speed"])

	for entry: Dictionary in non_unique:
		if _is_within_horizontal_radius(carrier_position, ally_position, float(entry["radius"])):
			result["armor"] = float(result["armor"]) + float(entry["armor"])
			result["attack_speed"] = float(result["attack_speed"]) + float(entry["attack_speed"])

	return result


static func hero_has_fortress_heart_regen(hero: Hero) -> bool:
	if hero == null:
		return false
	if hero_has_unique_passive(hero, ItemStats.UNIQUE_FORTRESS_HEART_REGEN):
		return true

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition and (item as HeroItemDefinition).has_out_of_combat_regen:
			return true
	return false


static func get_nearby_ally_aura_bonuses(ally_unit: Node) -> Dictionary:
	var result := {"armor": 0.0, "attack_speed": 0.0}
	if ally_unit == null or not is_instance_valid(ally_unit) or not ally_unit is Node3D:
		return result
	if not _is_normal_military_unit(ally_unit):
		return result

	var tree: SceneTree = ally_unit.get_tree()
	if tree == null:
		return result

	var ally_team: int = TeamVisuals.resolve_team(ally_unit, 0)

	for node: Node in tree.get_nodes_in_group(&"heroes"):
		if not node is Hero or not NodeSafety.is_alive_node(node):
			continue
		var hero: Hero = node as Hero
		if TeamVisuals.resolve_team(hero, hero.team_id) != ally_team:
			continue
		var bonuses: Dictionary = get_aura_bonuses_for_unit(hero, ally_unit)
		result["armor"] = maxf(float(result["armor"]), float(bonuses.get("armor", 0.0)))
		result["attack_speed"] = maxf(
			float(result["attack_speed"]), float(bonuses.get("attack_speed", 0.0))
		)

	return result


static func _is_normal_military_unit(unit: Node) -> bool:
	if unit == null or unit is Hero or unit is Worker or unit is Building:
		return false
	return (
		unit is MilitaryUnit
		or unit is LightCavalry
		or unit is CavalryArcher
		or unit is HeavyCavalry
		or unit is Cannon
	)


static func _purchase_into_empty_slot(shop: Shop, hero: Hero, item: HeroItemDefinition) -> bool:
	if not _try_pay_for_item(shop, item.gold_cost):
		_show_feedback(MSG_NOT_ENOUGH_GOLD, shop)
		return false

	var slot_index: int = hero.find_first_empty_inventory_slot()
	if slot_index < 0:
		_show_feedback(MSG_INVENTORY_FULL, shop)
		return false

	hero.set_item_at_slot(slot_index, item)
	apply_item_to_hero(hero, item, true)
	_sync_item_runtime(hero)
	return true


static func _purchase_completed_from_components(
	shop: Shop,
	hero: Hero,
	item: HeroItemDefinition
) -> bool:
	var component_slots: Array[int] = _find_recipe_component_slots(hero, item)
	if component_slots.size() != item.recipe_component_ids.size():
		_show_feedback(MSG_RECIPE_UNAVAILABLE, shop)
		return false

	var recipe_cost: int = item.get_recipe_gold_cost()
	if not _try_pay_for_item(shop, recipe_cost):
		_show_feedback(MSG_NOT_ENOUGH_GOLD, shop)
		return false

	var preferred_slot: int = component_slots[0]
	for slot_index: int in component_slots:
		preferred_slot = mini(preferred_slot, slot_index)
		var owned = hero.get_item_at_slot(slot_index)
		if owned is HeroItemDefinition:
			remove_item_from_hero(hero, owned as HeroItemDefinition)
		hero.clear_item_at_slot(slot_index)

	var place_slot: int = preferred_slot
	if hero.get_item_at_slot(place_slot) != null:
		place_slot = hero.find_first_empty_inventory_slot()
	if place_slot < 0:
		_show_feedback(MSG_INVENTORY_FULL, shop)
		return false

	hero.set_item_at_slot(place_slot, item)
	apply_item_to_hero(hero, item, true)
	_sync_item_runtime(hero)
	return true


static func _try_auto_combine_craftable(hero: Hero) -> void:
	if hero == null:
		return

	for _attempt: int in 12:
		var combined_any: bool = false
		for tier: HeroItemDefinition.Tier in [
			HeroItemDefinition.Tier.TIER_3,
			HeroItemDefinition.Tier.TIER_2,
		]:
			for definition: HeroItemDefinition in HeroItemCatalog.get_definitions_by_tier(tier):
				if definition == null or not definition.has_recipe():
					continue
				if try_combine_item(hero, definition.item_id):
					combined_any = true
					break
			if combined_any:
				break
		if not combined_any:
			return


static func _hero_owns_all_recipe_components(hero: Hero, item: HeroItemDefinition) -> bool:
	if hero == null or item == null or not item.has_recipe():
		return false

	var remaining: Dictionary = {}
	for component_id: StringName in item.recipe_component_ids:
		remaining[component_id] = int(remaining.get(component_id, 0)) + 1

	for slot_index: int in hero.get_inventory_slot_count():
		var owned = hero.get_item_at_slot(slot_index)
		if not owned is HeroItemDefinition:
			continue
		var owned_id: StringName = (owned as HeroItemDefinition).item_id
		if remaining.has(owned_id) and int(remaining[owned_id]) > 0:
			remaining[owned_id] = int(remaining[owned_id]) - 1

	for component_id: Variant in remaining.keys():
		if int(remaining[component_id]) > 0:
			return false
	return true


static func _find_recipe_component_slots(hero: Hero, item: HeroItemDefinition) -> Array[int]:
	var slots: Array[int] = []
	if hero == null or item == null:
		return slots

	var remaining: Dictionary = {}
	for component_id: StringName in item.recipe_component_ids:
		remaining[component_id] = int(remaining.get(component_id, 0)) + 1

	for slot_index: int in hero.get_inventory_slot_count():
		var owned = hero.get_item_at_slot(slot_index)
		if not owned is HeroItemDefinition:
			continue
		var owned_id: StringName = (owned as HeroItemDefinition).item_id
		if remaining.has(owned_id) and int(remaining[owned_id]) > 0:
			remaining[owned_id] = int(remaining[owned_id]) - 1
			slots.append(slot_index)

	for component_id: Variant in remaining.keys():
		if int(remaining[component_id]) > 0:
			return []

	return slots


static func _recompute_unique_move_speed(hero: Hero) -> void:
	if hero == null:
		return

	var best_unique_ms: float = 0.0
	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if not item is HeroItemDefinition:
			continue
		var definition: HeroItemDefinition = item as HeroItemDefinition
		if not definition.is_unique_move_speed:
			continue
		if definition.bonus_move_speed > best_unique_ms:
			best_unique_ms = definition.bonus_move_speed

	var previous: float = hero.item_unique_move_speed
	if is_equal_approx(previous, best_unique_ms):
		return

	hero.move_speed = maxf(0.0, hero.move_speed - previous + best_unique_ms)
	hero.item_unique_move_speed = best_unique_ms


static func _is_within_horizontal_radius(
	from_position: Vector3,
	to_position: Vector3,
	radius: float
) -> bool:
	if radius < 0.0:
		return false
	var offset: Vector3 = to_position - from_position
	offset.y = 0.0
	return offset.length_squared() <= radius * radius


static func _sync_item_runtime(hero: Hero) -> void:
	if hero == null:
		return
	var runtime: HeroItemRuntime = HeroItemRuntime.ensure_on(hero)
	if runtime != null:
		runtime.sync_from_hero(hero)


static func _get_shop_hero_candidate(
	node: Node,
	shop: Shop,
	shop_team: int
) -> Hero:
	if node == null or not is_instance_valid(node) or not node is Hero:
		return null

	var hero: Hero = node as Hero
	if not _is_living_hero(hero):
		return null

	var hero_team: int = TeamVisuals.resolve_team(hero, hero.team_id)
	if hero_team != shop_team:
		return null

	return hero


static func _is_living_hero(hero: Hero) -> bool:
	if hero == null or not is_instance_valid(hero) or hero.is_queued_for_deletion():
		return false

	return CombatTargetValidation.get_target_current_health(hero) > 0


static func _get_shop_range_limit(shop: Node3D) -> float:
	var viewport: Viewport = shop.get_viewport()
	if viewport != null and viewport.get_camera_3d() != null:
		return SHOP_PURCHASE_RANGE_PIXELS

	return SHOP_PURCHASE_RANGE_WORLD_FALLBACK


static func _get_shop_range_distance(shop: Node3D, hero: Node3D) -> float:
	var viewport: Viewport = shop.get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		var shop_screen: Vector2 = camera.unproject_position(shop.global_position)
		var hero_screen: Vector2 = camera.unproject_position(hero.global_position)
		return shop_screen.distance_to(hero_screen)

	return _get_horizontal_world_distance(shop, hero)


static func _get_horizontal_world_distance(node_a: Node3D, node_b: Node3D) -> float:
	var position_a: Vector3 = node_a.global_position
	var position_b: Vector3 = node_b.global_position
	position_a.y = 0.0
	position_b.y = 0.0
	return position_a.distance_to(position_b)


static func _can_afford_item(shop: Shop, gold_cost: int) -> bool:
	if gold_cost <= 0:
		return true
	if TeamVisuals.resolve_team(shop, shop.team_id) == TeamVisuals.PLAYER_TEAM_ID:
		return ResourceManager.gold >= gold_cost

	return EnemyResourceManager.gold >= gold_cost


static func _try_pay_for_item(shop: Shop, gold_cost: int) -> bool:
	if gold_cost <= 0:
		return true
	if TeamVisuals.resolve_team(shop, shop.team_id) == TeamVisuals.PLAYER_TEAM_ID:
		return ResourceManager.try_spend_gold(gold_cost)

	return EnemyResourceManager.try_spend(gold_cost, 0)


static func _can_afford_for_hero(hero: Hero, gold_cost: int) -> bool:
	if gold_cost <= 0:
		return true
	if TeamVisuals.resolve_team(hero, hero.team_id) == TeamVisuals.PLAYER_TEAM_ID:
		return ResourceManager.gold >= gold_cost
	return EnemyResourceManager.gold >= gold_cost


static func _try_pay_for_hero(hero: Hero, gold_cost: int) -> bool:
	if gold_cost <= 0:
		return true
	if TeamVisuals.resolve_team(hero, hero.team_id) == TeamVisuals.PLAYER_TEAM_ID:
		return ResourceManager.try_spend_gold(gold_cost)
	return EnemyResourceManager.try_spend(gold_cost, 0)


static func _apply_spell_stat_bonus(hero: Hero, item: HeroItemDefinition) -> void:
	if item.bonus_ability_power != 0:
		hero.item_ability_power += item.bonus_ability_power

	if item.bonus_cooldown_reduction != 0.0:
		hero.item_cooldown_reduction += item.bonus_cooldown_reduction

	if item.bonus_mana_cost_reduction != 0.0:
		hero.item_mana_cost_reduction += item.bonus_mana_cost_reduction

	if item.bonus_spell_radius != 0.0:
		hero.item_spell_radius_bonus += item.bonus_spell_radius


static func _remove_spell_stat_bonus(hero: Hero, item: HeroItemDefinition) -> void:
	if item.bonus_ability_power != 0:
		hero.item_ability_power = maxi(0, hero.item_ability_power - item.bonus_ability_power)

	if item.bonus_cooldown_reduction != 0.0:
		hero.item_cooldown_reduction = maxf(
			0.0, hero.item_cooldown_reduction - item.bonus_cooldown_reduction
		)

	if item.bonus_mana_cost_reduction != 0.0:
		hero.item_mana_cost_reduction = maxf(
			0.0, hero.item_mana_cost_reduction - item.bonus_mana_cost_reduction
		)

	if item.bonus_spell_radius != 0.0:
		hero.item_spell_radius_bonus = maxf(
			0.0, hero.item_spell_radius_bonus - item.bonus_spell_radius
		)


static func _apply_combat_stat_bonus(hero: Hero, item: HeroItemDefinition) -> void:
	if item.bonus_armor != 0.0:
		hero.item_bonus_armor += item.bonus_armor
	if item.bonus_attack_speed != 0.0:
		hero.item_bonus_attack_speed += item.bonus_attack_speed
	if item.bonus_crit_chance != 0.0:
		hero.item_bonus_crit_chance += item.bonus_crit_chance
	if item.bonus_lifesteal != 0.0:
		hero.item_bonus_lifesteal += item.bonus_lifesteal
	if item.bonus_mana_regen != 0.0:
		hero.item_bonus_mana_regen += item.bonus_mana_regen


static func _remove_combat_stat_bonus(hero: Hero, item: HeroItemDefinition) -> void:
	if item.bonus_armor != 0.0:
		hero.item_bonus_armor = maxf(0.0, hero.item_bonus_armor - item.bonus_armor)
	if item.bonus_attack_speed != 0.0:
		hero.item_bonus_attack_speed = maxf(0.0, hero.item_bonus_attack_speed - item.bonus_attack_speed)
	if item.bonus_crit_chance != 0.0:
		hero.item_bonus_crit_chance = maxf(0.0, hero.item_bonus_crit_chance - item.bonus_crit_chance)
	if item.bonus_lifesteal != 0.0:
		hero.item_bonus_lifesteal = maxf(0.0, hero.item_bonus_lifesteal - item.bonus_lifesteal)
	if item.bonus_mana_regen != 0.0:
		hero.item_bonus_mana_regen = maxf(0.0, hero.item_bonus_mana_regen - item.bonus_mana_regen)


static func _apply_health_bonus(
	hero: Hero,
	item: HeroItemDefinition,
	grant_immediate_bonuses: bool
) -> void:
	if item.bonus_max_health == 0 and item.heal_on_purchase == 0:
		return

	var health_component: HealthComponent = hero.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component == null:
		return

	if item.bonus_max_health != 0:
		health_component.max_health += item.bonus_max_health

	if grant_immediate_bonuses:
		var heal_amount: int = item.heal_on_purchase
		if heal_amount <= 0 and item.bonus_max_health > 0:
			heal_amount = item.bonus_max_health
		if heal_amount > 0:
			health_component.current_health = mini(
				health_component.current_health + heal_amount,
				health_component.max_health
			)

	health_component.health_changed.emit(
		health_component.current_health,
		health_component.max_health
	)


static func _apply_mana_bonus(
	hero: Hero,
	item: HeroItemDefinition,
	grant_immediate_bonuses: bool
) -> void:
	if item.bonus_max_mana == 0 and item.restore_mana_on_purchase == 0:
		return

	if not ("max_mana" in hero) or not ("current_mana" in hero):
		return

	var max_mana: int = int(hero.get("max_mana"))
	if item.bonus_max_mana != 0:
		max_mana += item.bonus_max_mana
		hero.set("max_mana", max_mana)

	if not grant_immediate_bonuses:
		return

	var restore_amount: int = item.restore_mana_on_purchase
	if restore_amount <= 0 and item.bonus_max_mana > 0:
		restore_amount = item.bonus_max_mana

	if restore_amount > 0 and hero.has_signal("mana_changed"):
		var current_mana: int = mini(int(hero.get("current_mana")) + restore_amount, max_mana)
		hero.set("current_mana", current_mana)
		hero.mana_changed.emit(current_mana, max_mana)


static func _remove_health_bonus(hero: Hero, item: HeroItemDefinition) -> void:
	if item.bonus_max_health == 0:
		return

	var health_component: HealthComponent = hero.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component == null:
		return

	health_component.max_health = maxi(1, health_component.max_health - item.bonus_max_health)
	health_component.current_health = maxi(
		1,
		mini(health_component.current_health, health_component.max_health)
	)
	health_component.health_changed.emit(
		health_component.current_health,
		health_component.max_health
	)


static func _remove_mana_bonus(hero: Hero, item: HeroItemDefinition) -> void:
	if item.bonus_max_mana == 0:
		return

	if not ("max_mana" in hero) or not ("current_mana" in hero):
		return

	var max_mana: int = maxi(0, int(hero.get("max_mana")) - item.bonus_max_mana)
	hero.set("max_mana", max_mana)

	var current_mana: int = mini(int(hero.get("current_mana")), max_mana)
	hero.set("current_mana", current_mana)

	if hero.has_signal("mana_changed"):
		hero.mana_changed.emit(current_mana, max_mana)


static func _show_feedback(message: String, shop: Shop = null) -> void:
	if shop != null and TeamVisuals.resolve_team(shop, shop.team_id) != TeamVisuals.PLAYER_TEAM_ID:
		return

	if ResourceManager != null:
		ResourceManager.show_feedback(message)
	else:
		print(message)
