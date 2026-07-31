class_name BearTrapActivationEffect
extends Node3D

## Brief jaw-snap flash when a Bear Trap triggers.

const DURATION := 0.4

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _material: StandardMaterial3D


func _ready() -> void:
	var mesh_material := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mesh_material != null:
		_material = mesh_material.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(0, _material)

	scale = Vector3(0.4, 0.4, 0.4)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.4, 0.35, 1.4), DURATION * 0.4).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	if _material != null:
		tween.tween_property(_material, "albedo_color:a", 0.0, DURATION)
		tween.tween_property(_material, "emission_energy_multiplier", 0.0, DURATION)
	tween.chain().tween_callback(queue_free)
