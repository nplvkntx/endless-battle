class_name SlashEffect
extends Node3D

## Placeholder expanding ring for Shadow Assassin Slash (E).

const DURATION := 0.35

@export var radius: float = 2.8

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _material: StandardMaterial3D


func _ready() -> void:
	var mesh_material := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mesh_material != null:
		_material = mesh_material.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(0, _material)

	scale = Vector3(radius * 0.15, 1.0, radius * 0.15)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		self,
		"scale",
		Vector3(radius * 2.0, 1.0, radius * 2.0),
		DURATION * 0.5
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if _material != null:
		tween.tween_property(
			_material,
			"albedo_color:a",
			0.0,
			DURATION * 0.65
		).set_delay(DURATION * 0.1)
		tween.tween_property(
			_material,
			"emission_energy_multiplier",
			0.0,
			DURATION * 0.65
		).set_delay(DURATION * 0.1)

	tween.chain().tween_callback(queue_free)
