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
