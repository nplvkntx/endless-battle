class_name HeroPassiveComponent
extends Node

## Hosts a hero's innate passive and dispatches combat / progression hooks.
## Attach via ensure_on(hero). Passives cannot be cast.

signal passive_state_changed()

const COMPONENT_NAME := &"HeroPassiveComponent"

var definition: HeroPassiveDefinition
var passive: HeroPassive

var _time_since_combat: float = 0.0
var _is_out_of_combat: bool = true
var _basic_attack_count: int = 0
var _aura_tick_accumulator: float = 0.0
## victim_instance_id -> last damage time (seconds since engine start)
var _recent_damage_victims: Dictionary = {}
var _applied_stat_bonuses: Dictionary = {}


static func find_on(host: Node) -> HeroPassiveComponent:
	if host == null or not is_instance_valid(host):
		return null
	return host.get_node_or_null(NodePath(String(COMPONENT_NAME))) as HeroPassiveComponent


static func ensure_on(host: Node) -> HeroPassiveComponent:
	if host == null or not is_instance_valid(host):
		return null
	var existing: HeroPassiveComponent = find_on(host)
	if existing != null:
		return existing
	var component := HeroPassiveComponent.new()
	component.name = String(COMPONENT_NAME)
	host.add_child(component)
	return component


func _ready() -> void:
	set_physics_process(false)
	var hero: Hero = get_parent() as Hero
	if hero == null:
		return
	if not hero.level_changed.is_connected(_on_host_level_changed):
		hero.level_changed.connect(_on_host_level_changed)


func _physics_process(delta: float) -> void:
	if passive == null or not passive.is_enabled():
		set_physics_process(false)
		return

	_tick_combat_state(delta)
	_tick_aura(delta)
	passive.tick(delta)
	_prune_recent_damage()


func setup_passive(passive_definition: HeroPassiveDefinition) -> void:
	clear_passive()
	definition = passive_definition
	if definition == null:
		passive_state_changed.emit()
		return

	var hero: Hero = get_parent() as Hero
	if hero == null:
		return

	passive = definition.create_instance()
	passive.setup(hero, definition)
	if not passive.state_changed.is_connected(_on_passive_state_changed):
		passive.state_changed.connect(_on_passive_state_changed)

	_time_since_combat = 0.0
	_is_out_of_combat = false
	_basic_attack_count = 0
	_aura_tick_accumulator = 0.0
	_apply_stat_bonuses()
	set_physics_process(true)
	passive_state_changed.emit()


func clear_passive() -> void:
	_clear_stat_bonuses()
	if passive != null:
		if passive.state_changed.is_connected(_on_passive_state_changed):
			passive.state_changed.disconnect(_on_passive_state_changed)
		passive.teardown()
	passive = null
	definition = null
	_is_out_of_combat = true
	_basic_attack_count = 0
	_recent_damage_victims.clear()
	set_physics_process(false)
	passive_state_changed.emit()


func has_passive() -> bool:
	return passive != null and passive.is_enabled()


func get_display_name() -> String:
	if passive != null:
		return passive.get_display_name()
	return "Passive"


func get_status_text() -> String:
	if passive != null:
		return passive.get_status_text()
	return "—"


func is_effect_active() -> bool:
	return passive != null and passive.is_effect_active()


func get_tooltip() -> String:
	if passive != null:
		return passive.format_tooltip()
	return "No passive"


func get_icon_texture() -> Texture2D:
	var icon_id: StringName = &""
	if passive != null:
		icon_id = passive.get_icon_id()
	elif definition != null:
		icon_id = definition.icon_id if definition.icon_id != &"" else definition.passive_id
	return HeroPassiveIcons.get_icon_texture(icon_id)


## Passives cannot be cast.
func try_cast() -> bool:
	return false


func notify_damage_dealt(target: Object, result: Dictionary, is_basic_attack: bool = false) -> void:
	if not has_passive():
		return
	if not bool(result.get(DamageService.RESULT_APPLIED, false)):
		return
	if bool(result.get(DamageService.RESULT_BLOCKED, false)):
		return

	_mark_combat()
	_record_damage_contribution(target)
	passive.on_damage_dealt(target, result)

	if is_basic_attack and definition != null and definition.tracks_basic_attacks:
		_basic_attack_count += 1
		passive.on_basic_attack_hit(target, result, _basic_attack_count)
		if definition.attacks_per_proc > 0 and (_basic_attack_count % definition.attacks_per_proc) == 0:
			passive.on_every_x_attacks(target, result, _basic_attack_count)


func notify_damage_taken(result: Dictionary) -> void:
	if not has_passive():
		return
	if not bool(result.get(DamageService.RESULT_APPLIED, false)):
		return
	if bool(result.get(DamageService.RESULT_BLOCKED, false)):
		return

	_mark_combat()
	passive.on_damage_taken(result)


func notify_kill(victim: Node) -> void:
	if not has_passive():
		return
	passive.on_kill(victim)
	_forget_damage_contribution(victim)


func notify_assist(victim: Node) -> void:
	if not has_passive():
		return
	passive.on_assist(victim)
	_forget_damage_contribution(victim)


func contributed_to_victim(victim: Node) -> bool:
	if victim == null or not is_instance_valid(victim):
		return false
	return _recent_damage_victims.has(victim.get_instance_id())


func _tick_combat_state(delta: float) -> void:
	if definition == null or not definition.tracks_out_of_combat:
		return

	_time_since_combat += delta
	var threshold: float = definition.out_of_combat_seconds
	if threshold <= 0.0:
		threshold = HeroPassiveStats.HOLY_RECOVERY_OUT_OF_COMBAT_SECONDS

	if not _is_out_of_combat and _time_since_combat >= threshold:
		_is_out_of_combat = true
		passive.on_out_of_combat_started()
		passive_state_changed.emit()


func _mark_combat() -> void:
	_time_since_combat = 0.0
	if not _is_out_of_combat:
		return
	if definition == null or not definition.tracks_out_of_combat:
		_is_out_of_combat = false
		return

	_is_out_of_combat = false
	if has_passive():
		passive.on_out_of_combat_ended()
	passive_state_changed.emit()


func _tick_aura(delta: float) -> void:
	if definition == null or not definition.has_ally_aura:
		return
	if definition.aura_radius <= 0.0:
		return

	var interval: float = definition.aura_tick_interval
	if interval <= 0.0:
		interval = HeroPassiveStats.AURA_TICK_INTERVAL_SECONDS

	_aura_tick_accumulator += delta
	if _aura_tick_accumulator < interval:
		return

	var tick_delta: float = _aura_tick_accumulator
	_aura_tick_accumulator = 0.0
	var allies: Array[Node] = _find_nearby_allies(definition.aura_radius)
	passive.on_aura_tick(allies, tick_delta)


func _find_nearby_allies(radius: float) -> Array[Node]:
	var hero: Hero = get_parent() as Hero
	var allies: Array[Node] = []
	if hero == null or not is_instance_valid(hero):
		return allies

	var radius_sq: float = radius * radius
	var tree: SceneTree = hero.get_tree()
	if tree == null:
		return allies

	for node: Node in tree.get_nodes_in_group("units"):
		if node == hero or not is_instance_valid(node):
			continue
		if not node is Node3D:
			continue
		if CombatTargetValidation.are_hostile(hero, node):
			continue
		var other: Node3D = node as Node3D
		var offset: Vector3 = other.global_position - hero.global_position
		offset.y = 0.0
		if offset.length_squared() <= radius_sq:
			allies.append(node)

	return allies


func _record_damage_contribution(target: Object) -> void:
	if target == null or not is_instance_valid(target) or not target is Node:
		return
	_recent_damage_victims[(target as Node).get_instance_id()] = Time.get_ticks_msec() * 0.001


func _forget_damage_contribution(victim: Node) -> void:
	if victim == null:
		return
	_recent_damage_victims.erase(victim.get_instance_id())


func _prune_recent_damage() -> void:
	if _recent_damage_victims.is_empty():
		return

	var now: float = Time.get_ticks_msec() * 0.001
	var window: float = HeroPassiveStats.ASSIST_DAMAGE_WINDOW_SECONDS
	var expired: Array = []
	for victim_id: Variant in _recent_damage_victims.keys():
		var stamped: float = float(_recent_damage_victims[victim_id])
		if now - stamped > window:
			expired.append(victim_id)

	for victim_id: Variant in expired:
		_recent_damage_victims.erase(victim_id)


func _apply_stat_bonuses() -> void:
	_clear_stat_bonuses()
	if not has_passive():
		return

	var hero: Hero = get_parent() as Hero
	if hero == null:
		return

	var bonuses: Dictionary = passive.get_stat_bonuses()
	_applied_stat_bonuses = bonuses.duplicate()

	var attack_bonus: int = int(bonuses.get(&"attack_damage", 0))
	if attack_bonus != 0 and hero.get("attack_damage") != null:
		hero.set("attack_damage", int(hero.get("attack_damage")) + attack_bonus)

	var move_bonus: float = float(bonuses.get(&"move_speed", 0.0))
	if move_bonus != 0.0:
		hero.move_speed += move_bonus

	var armor_bonus: float = float(bonuses.get(&"armor", 0.0))
	if armor_bonus != 0.0 and hero.get("armor") != null:
		hero.set("armor", int(hero.get("armor")) + int(round(armor_bonus)))

	var health_bonus: int = int(bonuses.get(&"max_health", 0))
	if health_bonus != 0:
		var health: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.max_health += health_bonus
			health.current_health += health_bonus
			health.health_changed.emit(health.current_health, health.max_health)


func _clear_stat_bonuses() -> void:
	if _applied_stat_bonuses.is_empty():
		return

	var hero: Hero = get_parent() as Hero
	if hero == null or not is_instance_valid(hero):
		_applied_stat_bonuses.clear()
		return

	var attack_bonus: int = int(_applied_stat_bonuses.get(&"attack_damage", 0))
	if attack_bonus != 0 and hero.get("attack_damage") != null:
		hero.set("attack_damage", int(hero.get("attack_damage")) - attack_bonus)

	var move_bonus: float = float(_applied_stat_bonuses.get(&"move_speed", 0.0))
	if move_bonus != 0.0:
		hero.move_speed -= move_bonus

	var armor_bonus: float = float(_applied_stat_bonuses.get(&"armor", 0.0))
	if armor_bonus != 0.0 and hero.get("armor") != null:
		hero.set("armor", int(hero.get("armor")) - int(round(armor_bonus)))

	var health_bonus: int = int(_applied_stat_bonuses.get(&"max_health", 0))
	if health_bonus != 0:
		var health: HealthComponent = hero.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			health.max_health = maxi(1, health.max_health - health_bonus)
			health.current_health = mini(health.current_health, health.max_health)
			health.health_changed.emit(health.current_health, health.max_health)

	_applied_stat_bonuses.clear()


func _on_host_level_changed(new_level: int) -> void:
	if has_passive():
		passive.on_level_up(new_level)


func _on_passive_state_changed() -> void:
	passive_state_changed.emit()
