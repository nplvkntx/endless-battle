class_name Shop
extends Building

## Hero item shop. Sells permanent stat items to nearby friendly heroes.

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


## Keep Quaternius Market materials untouched; team identity comes from the selection ring.
func apply_team_visuals() -> void:
	_restore_shop_visual_materials()


func _restore_shop_visual_materials() -> void:
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


func can_sell_items() -> bool:
	if building_state != STATE_COMPLETED:
		return false

	return TeamVisuals.resolve_team(self, team_id) == TeamVisuals.PLAYER_TEAM_ID


func can_show_purchase_ui() -> bool:
	return can_sell_items()


func try_purchase_item(item_id: StringName) -> bool:
	return HeroItemService.try_purchase_from_shop(self, item_id)


func get_nearby_shop_hero() -> Hero:
	return HeroItemService.find_closest_shop_hero(self)


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
