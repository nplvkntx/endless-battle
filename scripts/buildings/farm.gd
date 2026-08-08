class_name Farm
extends Building

## Placeholder farm building used for early 3D scene testing.

const FOOD_CAP_BONUS: int = BuildingStats.FARM_FOOD_CAP_BONUS

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func complete_construction() -> void:
	if building_state == STATE_COMPLETED:
		return

	super.complete_construction()
	if is_in_group(&"enemy_command_center"):
		EnemyResourceManager.add_food_max(FOOD_CAP_BONUS)
	else:
		ResourceManager.add_food_max(FOOD_CAP_BONUS)


func _ready() -> void:
	super._ready()
	## Map-placed farms ship completed. Runtime foundations call
	## start_under_construction() in the same frame after add_child — defer the
	## default so we do not flash-complete and emit construction_completed first.
	if building_state.is_empty():
		call_deferred("_complete_if_still_unstarted")

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


func _complete_if_still_unstarted() -> void:
	if building_state.is_empty():
		set_completed()


## Keep Quaternius Farm materials untouched; team identity comes from the selection ring.
func apply_team_visuals() -> void:
	_restore_farm_visual_materials()


func _restore_farm_visual_materials() -> void:
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




func _on_health_depleted() -> void:
	if building_state == STATE_COMPLETED:
		if is_in_group(&"enemy_command_center"):
			EnemyResourceManager.add_food_max(-FOOD_CAP_BONUS)
		else:
			ResourceManager.add_food_max(-FOOD_CAP_BONUS)
	destroy_building()
	queue_free()
