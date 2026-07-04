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


## Keep Quaternius Watch Tower materials untouched; team identity comes from the selection ring.
func apply_team_visuals() -> void:
	_restore_tower_visual_materials()


func _restore_tower_visual_materials() -> void:
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


func _physics_process(delta: float) -> void:
	if building_state != STATE_COMPLETED:
		return

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	var target: Node3D = _find_closest_enemy_in_range()
	if target == null:
		return

	if not CombatTargetValidation.is_within_attack_range(self, target, attack_range):
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

	if not CombatTargetValidation.is_within_attack_range(self, target, attack_range):
		return

	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	get_tree().current_scene.add_child(arrow)
	var spawn_position: Vector3 = global_position + Vector3(0.0, PROJECTILE_SPAWN_HEIGHT, 0.0)
	arrow.launch(target, float(attack_damage), spawn_position, self)
