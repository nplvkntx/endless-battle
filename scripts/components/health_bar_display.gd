class_name HealthBarDisplay
extends RefCounted

## Shared world-space health bar fill and visibility rules.


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
	fill.scale.x = ratio
	fill.position.x = bar_width * (ratio - 1.0) * 0.5
	fill_material.albedo_color = Color.from_hsv(ratio * hue_green, 0.85, 0.9)
	health_bar.visible = should_show(current_health, max_health)
