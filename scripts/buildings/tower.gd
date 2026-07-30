class_name Tower
extends Building

## Stationary defensive tower that automatically fires projectiles at nearby enemies.

@export var attack_damage: int = 12
@export var attack_range: float = 10.0
@export var attack_cooldown: float = 1.5

const ARROW_SCENE: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
const PROJECTILE_SPAWN_HEIGHT := 2.5

var _auto_combat := TowerAutoCombat.new()

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func _ready() -> void:
	super._ready()
	_auto_combat.attack_range = attack_range
	_auto_combat.attack_cooldown = attack_cooldown
	_auto_combat.randomize_search_timer()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


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


func take_damage(amount: float, attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(self, attacker)
	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	destroy_building()
	queue_free()


func _physics_process(delta: float) -> void:
	if _health_component != null and _health_component.current_health <= 0:
		return

	if building_state != STATE_COMPLETED:
		return

	_auto_combat.attack_range = attack_range
	_auto_combat.attack_cooldown = attack_cooldown

	var target: Node3D = _auto_combat.update(delta, self)
	if target == null:
		return

	_fire_projectile(target)
	_auto_combat.mark_fired()


func _fire_projectile(target: Node3D) -> void:
	if not NodeSafety.is_alive_node(target):
		return

	if not CombatTargetValidation.is_tower_attack_target(self, target):
		return

	if not CombatTargetValidation.is_within_attack_range(self, target, attack_range):
		return

	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	get_tree().current_scene.add_child(arrow)
	var spawn_position: Vector3 = global_position + Vector3(0.0, PROJECTILE_SPAWN_HEIGHT, 0.0)
	arrow.launch(target, float(_get_effective_attack_damage()), spawn_position, self)


func _get_effective_attack_damage() -> int:
	return maxi(
		1,
		int(round(float(attack_damage) * UpgradeManager.get_ballistics_damage_multiplier(_is_enemy_owned())))
	)


func _is_enemy_owned() -> bool:
	return TeamVisuals.resolve_team(self, team_id) != TeamVisuals.PLAYER_TEAM_ID
