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
var _has_rally_point: bool = false
var _rally_point: Vector3 = Vector3.ZERO
var _rally_marker: MeshInstance3D = null


func is_training_hero() -> bool:
	return _is_training


func player_has_hero() -> bool:
	for node: Node in get_tree().get_nodes_in_group(HERO_GROUP):
		if node is Hero and is_instance_valid(node):
			return true
	return false


func can_train_hero() -> bool:
	return (
		building_state == STATE_COMPLETED
		and not _is_training
		and not player_has_hero()
	)


func enemy_has_hero() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Hero and is_instance_valid(node) and not node.is_queued_for_deletion():
			return true

	return false


func can_train_enemy_hero() -> bool:
	return (
		building_state == STATE_COMPLETED
		and not _is_training
		and not enemy_has_hero()
	)


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
	if building_state != STATE_COMPLETED:
		return

	if player_has_hero():
		ResourceManager.show_feedback("A Hero already exists")
		return

	if _is_training:
		return

	if not ResourceManager.try_pay_worker_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		ResourceManager.show_feedback(
			ResourceManager.get_training_failure_message(TRAIN_GOLD_COST, TRAIN_FOOD_COST)
		)
		return

	_begin_hero_training()


func try_train_enemy_hero() -> bool:
	if not can_train_enemy_hero():
		return false

	if not EnemyResourceManager.try_pay_training(TRAIN_GOLD_COST, TRAIN_FOOD_COST):
		return false

	_begin_hero_training()
	return true


func _begin_hero_training() -> void:
	_is_training = true
	hero_altar_state_changed.emit()
	var wait_timer: SceneTreeTimer = get_tree().create_timer(TRAIN_SECONDS)
	wait_timer.timeout.connect(_on_hero_training_finished, CONNECT_ONE_SHOT)


func _on_hero_training_finished() -> void:
	_is_training = false

	if is_in_group(&"enemy_command_center"):
		if enemy_has_hero():
			hero_altar_state_changed.emit()
			return

		_spawn_enemy_hero()
		hero_altar_state_changed.emit()
		return

	if player_has_hero():
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

	var collision_shape: CollisionShape3D = hero.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		collision_shape.disabled = false

	EnemyArmyCommand.command_hold_at_rally(
		[hero],
		EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	)
