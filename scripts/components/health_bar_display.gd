class_name HealthBarDisplay
extends RefCounted

## Shared world-space health bar fill and visibility rules.


static func duplicate_mesh_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh == null or not is_instance_valid(mesh):
		return StandardMaterial3D.new()

	if mesh.get_surface_override_material_count() > 0:
		var override_material: Material = mesh.get_surface_override_material(0)
		if override_material is StandardMaterial3D:
			return (override_material as StandardMaterial3D).duplicate()

	if mesh.material_override is StandardMaterial3D:
		return (mesh.material_override as StandardMaterial3D).duplicate()

	if mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		var surface_material: Material = mesh.mesh.surface_get_material(0)
		if surface_material is StandardMaterial3D:
			return (surface_material as StandardMaterial3D).duplicate()

	return StandardMaterial3D.new()


static func should_show(current_health: int, max_health: int) -> bool:
	if max_health <= 0:
		return false

	return current_health < max_health


static func update_world_bar(
	health_bar: Node3D,
	fill: MeshInstance3D,
	fill_material: StandardMaterial3D,
	current_health: int,
	max_health: int,
	bar_width: float,
	hue_green: float = 0.333333
) -> void:
	if health_bar == null or fill == null or fill_material == null:
		return

	if max_health <= 0:
		health_bar.visible = false
		return

	var ratio: float = float(current_health) / float(max_health)
	update_fraction_bar(
		health_bar,
		fill,
		fill_material,
		ratio,
		bar_width,
		should_show(current_health, max_health),
		hue_green
	)


static func update_fraction_bar(
	bar: Node3D,
	fill: MeshInstance3D,
	fill_material: StandardMaterial3D,
	fraction: float,
	bar_width: float,
	visible: bool = true,
	hue_green: float = 0.333333
) -> void:
	if bar == null or fill == null or fill_material == null:
		return

	var ratio: float = clampf(fraction, 0.0, 1.0)
	fill.scale.x = ratio
	fill.position.x = bar_width * (ratio - 1.0) * 0.5
	fill_material.albedo_color = Color.from_hsv(ratio * hue_green, 0.85, 0.9)
	bar.visible = visible
