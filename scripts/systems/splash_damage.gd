class_name SplashDamage
extends RefCounted

## Applies radial falloff damage to valid hostile combat targets near an impact point.


static func apply_radial_damage(
	tree: SceneTree,
	center: Vector3,
	attacker: Node,
	base_damage: float,
	radius: float,
	min_damage_ratio: float = 0.5
) -> void:
	if tree == null or radius <= 0.0 or base_damage <= 0.0:
		return

	var safe_attacker: Node = CombatTargetValidation.sanitize_damage_attacker(attacker)

	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups():
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not CombatTargetValidation.is_valid_combat_target(node_variant):
				continue
			if safe_attacker != null and not CombatTargetValidation.are_hostile(safe_attacker, node_variant):
				continue

			var target_position: Vector3 = _resolve_target_position(node_variant)
			var offset: Vector3 = target_position - center
			offset.y = 0.0
			var distance: float = offset.length()
			if distance > radius:
				continue

			var edge_ratio: float = clampf(distance / radius, 0.0, 1.0)
			var falloff: float = lerpf(1.0, min_damage_ratio, edge_ratio)
			var damage_amount: float = base_damage * falloff
			if damage_amount < 1.0:
				damage_amount = 1.0

			CombatTargetValidation.apply_damage_to_target(
				node_variant, damage_amount, safe_attacker
			)


static func _resolve_target_position(target: Variant) -> Vector3:
	if target is Node3D:
		return (target as Node3D).global_position
	return Vector3.ZERO
