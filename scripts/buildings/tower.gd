class_name Tower
extends Building

## Stationary defensive tower that automatically fires projectiles at nearby enemies.

@export var attack_damage: int = 12
@export var attack_range: float = 10.0
@export var attack_cooldown: float = 1.5

const ARROW_SCENE: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
const PROJECTILE_SPAWN_HEIGHT := 2.5

var _attack_cooldown_timer: float = 0.0


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()


func _physics_process(delta: float) -> void:
	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	var target: EnemyDummy = _find_closest_enemy_in_range()
	if target == null:
		return

	_fire_projectile(target)
	_attack_cooldown_timer = attack_cooldown


func _find_closest_enemy_in_range() -> EnemyDummy:
	var closest_enemy: EnemyDummy = null
	var closest_distance: float = INF

	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyDummy:
			continue

		var enemy: EnemyDummy = node as EnemyDummy
		if not is_instance_valid(enemy):
			continue

		if enemy.get_current_health() <= 0:
			continue

		var distance: float = _horizontal_distance_to(enemy)
		if distance > attack_range:
			continue

		if distance < closest_distance:
			closest_distance = distance
			closest_enemy = enemy

	return closest_enemy


func _fire_projectile(target: EnemyDummy) -> void:
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	get_tree().current_scene.add_child(arrow)
	var spawn_position: Vector3 = global_position + Vector3(0.0, PROJECTILE_SPAWN_HEIGHT, 0.0)
	arrow.launch(target, float(attack_damage), spawn_position)


func _horizontal_distance_to(target: Node3D) -> float:
	var offset: Vector3 = global_position - target.global_position
	offset.y = 0.0
	return offset.length()
