class_name PaladinArtVisuals
extends Node

func _ready() -> void:
	apply_team((get_parent() as Unit).team_id)


func apply_team(team: int) -> void:
	var model: Node = get_parent().get_node("MeshInstance3D/PaladinModel")
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original != null and original.resource_name == "TeamCloth":
				var cloth: StandardMaterial3D = original.duplicate() as StandardMaterial3D
				cloth.albedo_color = Color(0.55, 0.065, 0.035) if team == 1 else Color(0.035, 0.13, 0.44)
				mesh.set_surface_override_material(surface, cloth)


func create_death_model() -> Node3D:
	var model: Node3D = get_parent().get_node("MeshInstance3D/PaladinModel") as Node3D
	var corpse: Node3D = model.duplicate() as Node3D
	corpse.transform = model.global_transform
	# Shared detached model lifecycle, already owned by DeathEffects.
	corpse.set_meta(&"worker_animated_corpse", true)
	return corpse


func set_protected(active: bool) -> void:
	var model: Node = get_parent().get_node("MeshInstance3D/PaladinModel")
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		for index: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.get_active_material(index) as StandardMaterial3D
			var material: StandardMaterial3D = source.duplicate() as StandardMaterial3D
			material.emission_enabled = active
			material.emission = Color(0.65, 0.43, 0.08) if active else Color.BLACK
			mesh.set_surface_override_material(index, material)
