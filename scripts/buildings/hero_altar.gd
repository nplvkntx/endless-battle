class_name HeroAltar
extends Building

## Trains a single player Hero. Only one Hero may exist at a time.

signal hero_altar_state_changed()

const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const TRAIN_GOLD_COST: int = 200
const TRAIN_FOOD_COST: int = 2
const TRAIN_SECONDS: float = 6.0
const HERO_SPAWN_OFFSET: Vector3 = Vector3(3.0, -0.5, 0.0)
const RALLY_MARKER_Y: float = 0.05
const HERO_GROUP: StringName = &"heroes"
const ENEMY_TEAM_ID: int = 1

var _is_training: bool = false
var _training_for_enemy: bool = false
var _hero_training_session: int = 0
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null


func is_training_hero() -> bool:
	return _is_training


func is_training_hero_for_owner(is_enemy_owned: bool) -> bool:
	return _is_training and _training_for_enemy == is_enemy_owned


func has_living_owner_hero(is_enemy_owned: bool) -> bool:
	if is_enemy_owned:
		return EnemyArmyCommand.find_living_enemy_hero(get_tree()) != null

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


func set_rally_point(ground_position: Vector3) -> void:
	_has_rally_point = true
	_rally_point = Vector3(
		ground_position.x,
		global_position.y + HERO_SPAWN_OFFSET.y,
		ground_position.z
	)
	_update_rally_marker(Vector3(ground_position.x, RALLY_MARKER_Y, ground_position.z))


func _update_rally_marker(marker_position: Vector3) -> void:
	if _rally_marker == null:
		_rally_marker = MeshInstance3D.new()
		var marker_mesh := CylinderMesh.new()
		marker_mesh.top_radius = 0.45
		marker_mesh.bottom_radius = 0.45
		marker_mesh.height = 0.08
		_rally_marker.mesh = marker_mesh

		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = Color(0.85, 0.65, 0.15, 0.9)
		marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_rally_marker.material_override = marker_material

		var marker_parent: Node = get_parent()
		if marker_parent == null:
			return

		marker_parent.add_child(_rally_marker)

	_rally_marker.global_position = marker_position


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
	_begin_hero_training()
	return true


func _begin_hero_training() -> void:
	_hero_training_session += 1
	var session: int = _hero_training_session
	_is_training = true
	hero_altar_state_changed.emit()
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(func() -> void:
		_on_hero_training_finished(session)
	, CONNECT_ONE_SHOT)


func _on_hero_training_finished(session: int) -> void:
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
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or hero == null:
		return

	spawn_parent.add_child(hero)
	hero.global_position = global_position + HERO_SPAWN_OFFSET
	hero.collision_layer = PhysicsLayers.UNITS
	hero.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK

	if not hero.is_in_group(&"units"):
		hero.add_to_group(&"units")

	var collision_shape: CollisionShape3D = hero.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		collision_shape.disabled = false

	if _has_rally_point:
		hero.set_movement_target(_rally_point)


func _spawn_enemy_hero() -> void:
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or hero == null:
		return

	hero.team_id = ENEMY_TEAM_ID
	hero.collision_layer = PhysicsLayers.UNITS
	hero.collision_mask = PhysicsLayers.UNIT_COLLISION_MASK

	if hero.is_in_group(&"units"):
		hero.remove_from_group(&"units")

	if hero.is_in_group(&"heroes"):
		hero.remove_from_group(&"heroes")

	if not hero.is_in_group(&"enemies"):
		hero.add_to_group(&"enemies")

	EnemyArmyCommand.register_combat_unit(hero)

	spawn_parent.add_child(hero)
	hero.global_position = global_position + HERO_SPAWN_OFFSET
	hero.apply_team_visuals()

	var collision_shape: CollisionShape3D = hero.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		collision_shape.disabled = false

	EnemyArmyCommand.command_hold_at_rally(
		[hero],
		EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	)


func _has_living_player_hero() -> bool:
	for node: Node in get_tree().get_nodes_in_group(HERO_GROUP):
		if _is_living_player_hero(node):
			return true

	for node: Node in get_tree().get_nodes_in_group(&"units"):
		if _is_living_player_hero(node):
			return true

	return false


func _is_living_player_hero(node: Node) -> bool:
	if not _is_living_hero_node(node):
		return false

	return not CombatTargetValidation.is_enemy_faction(node)


func _is_living_hero_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not node is Hero:
		return false

	var health_component: HealthComponent = node.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true
