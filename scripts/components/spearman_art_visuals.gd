class_name SpearmanArtVisuals
extends Node

func _ready() -> void:
	apply_team((get_parent() as Unit).team_id)


func apply_team(team: int) -> void:
	var model: Node = get_parent().get_node("MeshInstance3D/SpearmanModel")
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original != null and original.resource_name == "TeamCloth":
				var cloth: StandardMaterial3D = original.duplicate() as StandardMaterial3D
				cloth.albedo_color = Color(0.55, 0.065, 0.035) if team == 1 else Color(0.035, 0.13, 0.44)
				mesh.set_surface_override_material(surface, cloth)


func create_death_model() -> Node3D:
	var model: Node3D = get_parent().get_node("MeshInstance3D/SpearmanModel") as Node3D
	var corpse: Node3D = model.duplicate() as Node3D
	corpse.transform = model.global_transform
	# Shared detached model lifecycle, already owned by DeathEffects.
	corpse.set_meta(&"worker_animated_corpse", true)
	return corpse
