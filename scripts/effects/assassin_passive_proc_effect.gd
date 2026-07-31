class_name AssassinPassiveProcEffect
extends Node3D

## Placeholder spark played when the Assassin passive procs its bonus damage.

const DURATION := 0.28

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _material: StandardMaterial3D


func _ready() -> void:
	var mesh_material := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mesh_material != null:
		_material = mesh_material.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(0, _material)

	scale = Vector3(0.2, 0.2, 0.2)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(0.7, 0.7, 0.7), DURATION * 0.4).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)

	if _material != null:
		tween.tween_property(_material, "albedo_color:a", 0.0, DURATION).set_delay(DURATION * 0.1)
		tween.tween_property(_material, "emission_energy_multiplier", 0.0, DURATION).set_delay(
			DURATION * 0.1
		)

	tween.chain().tween_callback(queue_free)
