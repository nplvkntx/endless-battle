class_name HeroItemService
extends RefCounted

## Applies hero item purchases and range checks for completed shops.

const SHOP_PURCHASE_RANGE_PIXELS: float = 200.0
const SHOP_PURCHASE_RANGE_WORLD_FALLBACK: float = 4.5

const MSG_NO_NEARBY_HERO := "Move a hero near the shop"
const MSG_INVENTORY_FULL := "Hero inventory is full"
const MSG_NOT_ENOUGH_GOLD := "Not enough gold"
const MSG_SHOP_UNAVAILABLE := "Shop cannot sell items"
const SELL_REFUND_RATIO := 0.5


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

	if not _try_pay_for_item(shop, item.gold_cost):
		_show_feedback(MSG_NOT_ENOUGH_GOLD, shop)
		return false

	var slot_index: int = hero.find_first_empty_inventory_slot()
	if slot_index < 0:
		_show_feedback(MSG_INVENTORY_FULL, shop)
		return false

	hero.set_item_at_slot(slot_index, item)
	apply_item_to_hero(hero, item, true)
	return true


static func get_purchase_failure_reason(shop: Shop, item: HeroItemDefinition) -> String:
	if shop == null or item == null:
		return MSG_SHOP_UNAVAILABLE

	if shop.building_state != Building.STATE_COMPLETED:
		return MSG_SHOP_UNAVAILABLE

	var hero: Hero = find_closest_shop_hero(shop)
	if hero == null:
		return MSG_NO_NEARBY_HERO

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
		hero.set("attack_damage", int(hero.get("attack_damage")) + item.bonus_attack_damage)

	if item.bonus_move_speed != 0.0:
		hero.move_speed += item.bonus_move_speed

	_apply_spell_stat_bonus(hero, item)

	_apply_health_bonus(hero, item, grant_immediate_bonuses)
	_apply_mana_bonus(hero, item, grant_immediate_bonuses)


static func can_modify_player_inventory(hero: Hero) -> bool:
	if hero == null or not is_instance_valid(hero) or hero.is_queued_for_deletion():
		return false

	return TeamVisuals.resolve_team(hero, hero.team_id) == TeamVisuals.PLAYER_TEAM_ID


static func try_reorder_inventory_slot(hero: Hero, from_index: int, to_index: int) -> bool:
	if not can_modify_player_inventory(hero):
		return false

	return hero.reorder_inventory_slot(from_index, to_index)


static func try_sell_inventory_item(hero: Hero, slot_index: int) -> bool:
	if not can_modify_player_inventory(hero):
		return false

	var item = hero.get_item_at_slot(slot_index)
	if not item is HeroItemDefinition:
		return false

	var definition: HeroItemDefinition = item as HeroItemDefinition
	remove_item_from_hero(hero, definition)
	hero.remove_item_at_slot(slot_index)

	var refund: int = int(definition.gold_cost * SELL_REFUND_RATIO)
	if refund > 0:
		ResourceManager.add_gold(refund)

	return true


static func remove_item_from_hero(hero: Hero, item: HeroItemDefinition) -> void:
	if hero == null or item == null:
		return

	if item.bonus_attack_damage != 0 and "attack_damage" in hero:
		hero.set(
			"attack_damage",
			maxi(0, int(hero.get("attack_damage")) - item.bonus_attack_damage)
		)

	if item.bonus_move_speed != 0.0:
		hero.move_speed = maxf(0.0, hero.move_speed - item.bonus_move_speed)

	_remove_spell_stat_bonus(hero, item)

	_remove_health_bonus(hero, item)
	_remove_mana_bonus(hero, item)


static func restore_inventory_items(hero: Hero) -> void:
	if hero == null:
		return

	for slot_index: int in hero.get_inventory_slot_count():
		var item = hero.get_item_at_slot(slot_index)
		if item is HeroItemDefinition:
			apply_item_to_hero(hero, item as HeroItemDefinition, false)

	hero.inventory_changed.emit()


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
	if TeamVisuals.resolve_team(shop, shop.team_id) == TeamVisuals.PLAYER_TEAM_ID:
		return ResourceManager.gold >= gold_cost

	return EnemyResourceManager.gold >= gold_cost


static func _try_pay_for_item(shop: Shop, gold_cost: int) -> bool:
	if TeamVisuals.resolve_team(shop, shop.team_id) == TeamVisuals.PLAYER_TEAM_ID:
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
