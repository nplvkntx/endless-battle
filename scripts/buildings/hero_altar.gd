class_name HeroAltar
extends Building

## Trains a single player Hero. Only one Hero may exist at a time.

signal hero_altar_state_changed()

## Train costs — edit HeroStats only.
const TRAIN_GOLD_COST: int = HeroStats.TRAIN_GOLD_COST
const TRAIN_FOOD_COST: int = HeroStats.TRAIN_FOOD_COST
const TRAIN_SECONDS: float = HeroStats.TRAIN_SECONDS
## Barracks/CC-style front exit (-Z). Must clear completed occupancy (~collision half + 0.15).
const HERO_SPAWN_OFFSET: Vector3 = Vector3(0.0, -0.5, -3.5)
const HERO_GROUP: StringName = &"heroes"
const ENEMY_TEAM_ID: int = 1

var _is_training: bool = false
var _training_started_at: float = 0.0
var _training_for_enemy: bool = false
var _hero_training_session: int = 0

## Kit locked in for the training session currently in progress.
var _training_kit_id: StringName = HeroCatalog.KIT_PALADIN
## Player-selected kit for the next training (UI writes this).
var selected_kit_id: StringName = HeroCatalog.KIT_PALADIN
## Enemy first-train kit pool — one random pick, then locked for the match.
const ENEMY_KIT_CHOICES: Array[StringName] = [
	HeroCatalog.KIT_PALADIN,
	HeroCatalog.KIT_SHADOW_ASSASSIN,
	HeroCatalog.KIT_RANGER,
]

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func _ready() -> void:
	super._ready()

	_sync_selected_kit_from_faction(is_in_group(&"enemy_command_center"))

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


## Keep Quaternius Temple materials untouched; team identity comes from the selection ring.
func apply_team_visuals() -> void:
	_restore_temple_visual_materials()


func _restore_temple_visual_materials() -> void:
	var visuals: Node3D = get_node_or_null("Visuals") as Node3D
	if visuals == null:
		return

	_clear_imported_mesh_overrides(visuals)


func _clear_imported_mesh_overrides(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = null
		if mesh_instance.mesh != null:
			for surface_index: int in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, null)

	for child: Node in node.get_children():
		_clear_imported_mesh_overrides(child)


func is_training_hero() -> bool:
	return _is_training


func has_active_unit_training() -> bool:
	return _is_training


func get_active_unit_training_progress() -> float:
	if not _is_training:
		return 0.0

	var elapsed: float = _get_time_seconds() - _training_started_at
	return clampf(elapsed / _get_effective_train_seconds(), 0.0, 1.0)


func get_active_unit_training_name() -> String:
	return HeroCatalog.get_display_name(_training_kit_id)


func set_selected_kit(kit_id: StringName) -> void:
	var is_enemy_owned: bool = is_in_group(&"enemy_command_center")
	var normalized: StringName = HeroCatalog.normalize_kit_id(kit_id)
	if not HeroProgressionStore.can_select_kit(is_enemy_owned, normalized):
		normalized = HeroProgressionStore.get_locked_kit_id(is_enemy_owned)
	selected_kit_id = normalized


func get_selected_kit() -> StringName:
	return selected_kit_id


## Kit that will actually be spawned for the given owner on the next training,
## accounting for faction lock and saved progression from a prior death.
func get_pending_training_kit_id(is_enemy_owned: bool = false) -> StringName:
	return _resolve_spawn_kit_id(is_enemy_owned)


## True when this faction may show/train the given kit (unlocked or matches lock).
func can_offer_kit(kit_id: StringName, is_enemy_owned: bool = false) -> bool:
	return HeroProgressionStore.can_select_kit(is_enemy_owned, kit_id)


## Resolves which kit the next training session for this owner should spawn.
## Match lock (set when training begins) wins; then death snapshot; then selection /
## enemy random first-choice. Cancelled initial training keeps the lock so hero swapping is blocked.
func _resolve_spawn_kit_id(is_enemy_owned: bool) -> StringName:
	var faction_kit: StringName = HeroProgressionStore.get_faction_kit_id(is_enemy_owned)
	if faction_kit != &"":
		return faction_kit

	if is_enemy_owned:
		return _pick_enemy_match_kit()

	return selected_kit_id


## One random kit for the match; locked via HeroProgressionStore on first train.
static func _pick_enemy_match_kit() -> StringName:
	var index: int = randi() % ENEMY_KIT_CHOICES.size()
	return ENEMY_KIT_CHOICES[index]


func _get_effective_train_seconds() -> float:
	if _training_for_enemy:
		return TrainingConfig.get_enemy_military_train_seconds(TRAIN_SECONDS)
	return TRAIN_SECONDS


## Lock faction kit and sync every altar so UI/AI share one choice for the match.
func _lock_faction_kit_for_training(is_enemy_owned: bool, kit_id: StringName) -> void:
	var newly_locked: bool = not HeroProgressionStore.has_locked_kit(is_enemy_owned)
	HeroProgressionStore.lock_kit(is_enemy_owned, kit_id)
	_sync_selected_kit_from_faction(is_enemy_owned)
	if newly_locked or HeroProgressionStore.get_locked_kit_id(is_enemy_owned) == kit_id:
		_notify_all_hero_altars_state_changed()


func _sync_selected_kit_from_faction(is_enemy_owned: bool) -> void:
	var locked: StringName = HeroProgressionStore.get_locked_kit_id(is_enemy_owned)
	if locked != &"":
		selected_kit_id = locked


static func _notify_all_hero_altars_state_changed() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	for node_variant: Variant in tree.get_nodes_in_group("buildings"):
		if not NodeSafety.is_alive_node(node_variant) or not node_variant is HeroAltar:
			continue
		(node_variant as HeroAltar).hero_altar_state_changed.emit()


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func is_training_hero_for_owner(is_enemy_owned: bool) -> bool:
	return _is_training and _training_for_enemy == is_enemy_owned


func has_living_owner_hero(is_enemy_owned: bool) -> bool:
	if HeroProgressionStore.has_living_hero(is_enemy_owned):
		return true

	## Fallback scan keeps AI/training correct if registry was never registered.
	if is_enemy_owned:
		var enemy_hero: Hero = _find_living_enemy_hero()
		if enemy_hero != null:
			HeroProgressionStore.register_living_hero(enemy_hero)
			return true
		return false

	return _has_living_player_hero()


func player_has_hero() -> bool:
	return has_living_owner_hero(false)


func can_train_hero() -> bool:
	return can_begin_hero_training(false)


func enemy_has_hero() -> bool:
	return has_living_owner_hero(true)


func can_train_enemy_hero() -> bool:
	return can_begin_hero_training(true)


func can_begin_hero_training(is_enemy_owned: bool) -> bool:
	if is_enemy_owned != is_in_group(&"enemy_command_center"):
		return false

	return (
		building_state == STATE_COMPLETED
		and not _is_training
		and not has_living_owner_hero(is_enemy_owned)
	)


func cancel_hero_training() -> bool:
	if not _is_training or _training_for_enemy:
		return false

	_hero_training_session += 1
	_is_training = false
	hero_altar_state_changed.emit()
	ResourceManager.add_gold(TRAIN_GOLD_COST)
	ResourceManager.release_food_used(TRAIN_FOOD_COST)
	return true


func try_train_hero() -> void:
	if not can_begin_hero_training(false):
		if building_state == STATE_COMPLETED and has_living_owner_hero(false):
			ResourceManager.show_feedback("A Hero already exists")
		return

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		ResourceManager.show_feedback(
			ResourceManager.get_training_failure_message(TRAIN_GOLD_COST, TRAIN_FOOD_COST)
		)
		return

	_training_for_enemy = false
	_training_kit_id = _resolve_spawn_kit_id(false)
	## Lock immediately on successful payment so cancel/UI cannot swap kits.
	_lock_faction_kit_for_training(false, _training_kit_id)
	_begin_hero_training()


func try_train_enemy_hero() -> bool:
	return try_begin_hero_training(true)


func try_begin_hero_training(is_enemy_owned: bool) -> bool:
	if not can_begin_hero_training(is_enemy_owned):
		return false

	if is_enemy_owned:
		if not EnemyResourceManager.try_pay_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
			return false
	else:
		if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
			return false

	_training_for_enemy = is_enemy_owned
	_training_kit_id = _resolve_spawn_kit_id(is_enemy_owned)
	## Lock immediately on successful payment so cancel/UI cannot swap kits.
	_lock_faction_kit_for_training(is_enemy_owned, _training_kit_id)
	_begin_hero_training()
	return true


func _begin_hero_training() -> void:
	_hero_training_session += 1
	var session: int = _hero_training_session
	_is_training = true
	_training_started_at = _get_time_seconds()
	hero_altar_state_changed.emit()
	var wait_timer: SceneTreeTimer = get_tree().create_timer(_get_effective_train_seconds())
	wait_timer.timeout.connect(_on_hero_training_finished.bind(session), CONNECT_ONE_SHOT)


func _on_hero_training_finished(session: int) -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	if session != _hero_training_session:
		return

	var training_was_for_enemy: bool = _training_for_enemy
	_is_training = false
	_training_for_enemy = false

	if training_was_for_enemy:
		if has_living_owner_hero(true):
			hero_altar_state_changed.emit()
			return

		_spawn_enemy_hero()
		hero_altar_state_changed.emit()
		return

	if has_living_owner_hero(false):
		hero_altar_state_changed.emit()
		return

	_spawn_hero()
	hero_altar_state_changed.emit()


func _spawn_hero() -> void:
	var hero: Hero = HeroCatalog.load_scene(_training_kit_id).instantiate() as Hero
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or hero == null:
		return

	disable_spawned_unit_collision(hero)
	var spawn_pos: Vector3 = _claim_hero_spawn_position()
	spawn_parent.add_child(hero)
	hero.global_position = spawn_pos
	hero.team_id = TeamVisuals.PLAYER_TEAM_ID
	hero.collision_layer = PhysicsLayers.UNITS
	hero.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK

	if not hero.is_in_group(&"units"):
		hero.add_to_group(&"units")

	hero.apply_team_visuals()
	enable_spawned_unit_collision(hero)

	HeroProgressionStore.register_living_hero(hero)

	if has_production_rally():
		apply_production_rally(hero)


func _spawn_enemy_hero() -> Hero:
	var hero: Hero = HeroCatalog.load_scene(_training_kit_id).instantiate() as Hero
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or hero == null:
		return null

	hero.team_id = ENEMY_TEAM_ID
	hero.collision_layer = PhysicsLayers.UNITS
	hero.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK

	if hero.is_in_group(&"units"):
		hero.remove_from_group(&"units")

	if hero.is_in_group(&"heroes"):
		hero.remove_from_group(&"heroes")

	if not hero.is_in_group(&"enemies"):
		hero.add_to_group(&"enemies")

	if not hero.is_in_group(&"enemy_combat_units"):
		hero.add_to_group(&"enemy_combat_units")

	disable_spawned_unit_collision(hero)
	var spawn_pos: Vector3 = _claim_hero_spawn_position()
	spawn_parent.add_child(hero)
	hero.global_position = spawn_pos
	hero.apply_team_visuals()
	enable_spawned_unit_collision(hero)

	HeroProgressionStore.register_living_hero(hero)
	if not PlayerRouteNavigation.is_world_walkable(hero.global_position):
		_place_unit_on_walkable_custom_cell(hero)
	EnemyAI.request_spawned_military_join(hero, name)
	return hero


## Pick a deterministic exit outside the altar via the shared Building spawn helper.
func _claim_hero_spawn_position() -> Vector3:
	return claim_production_spawn_position(HERO_SPAWN_OFFSET)


func _has_living_player_hero() -> bool:
	var registered: Hero = HeroProgressionStore.get_living_hero(false)
	if registered != null:
		return true

	var tree: SceneTree = get_tree()
	if tree == null:
		return false

	for node_variant: Variant in tree.get_nodes_in_group(HERO_GROUP):
		if _is_living_player_hero_variant(node_variant):
			HeroProgressionStore.register_living_hero(node_variant as Hero)
			return true

	for node_variant: Variant in tree.get_nodes_in_group(&"units"):
		if _is_living_player_hero_variant(node_variant):
			HeroProgressionStore.register_living_hero(node_variant as Hero)
			return true

	return false


func _is_living_player_hero_variant(node_variant: Variant) -> bool:
	var hero: Hero = HeroProgressionStore.as_living_hero(node_variant)
	if hero == null:
		return false

	return not CombatTargetValidation.is_enemy_faction(hero)


func _find_living_enemy_hero() -> Hero:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(&"enemy_combat_units"):
		var hero: Hero = HeroProgressionStore.as_living_hero(node_variant)
		if hero != null and CombatTargetValidation.is_enemy_faction(hero):
			return hero
	return null


func _on_health_depleted() -> void:
	_hero_training_session += 1
	if _is_training and not _training_for_enemy:
		ResourceManager.add_gold(TRAIN_GOLD_COST)
		ResourceManager.release_food_used(TRAIN_FOOD_COST)
	elif _is_training and _training_for_enemy:
		EnemyResourceManager.add_gold(TRAIN_GOLD_COST)
		EnemyResourceManager.release_food_used(TRAIN_FOOD_COST)
	_is_training = false
	_training_for_enemy = false

	destroy_building()
	queue_free()


func _is_living_hero_node(node: Node) -> bool:
	return HeroProgressionStore.as_living_hero(node) != null
