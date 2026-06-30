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
	if building_state != STATE_COMPLETED:
		return

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	var target: Node3D = _find_closest_enemy_in_range()
	if target == null:
		return

	_fire_projectile(target)
	_attack_cooldown_timer = attack_cooldown


func _find_closest_enemy_in_range() -> Node3D:
	return CombatTargetValidation.find_closest_tower_attack_target_in_range(
		self, attack_range
	)


func _fire_projectile(target: Node3D) -> void:
	if not CombatTargetValidation.is_tower_attack_target(target):
		return

	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	get_tree().current_scene.add_child(arrow)
	var spawn_position: Vector3 = global_position + Vector3(0.0, PROJECTILE_SPAWN_HEIGHT, 0.0)
	arrow.launch(target, float(attack_damage), spawn_position)
