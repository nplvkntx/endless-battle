class_name HolyRecoveryEffect
extends Node3D

## Soft golden ring under the hero while Holy Recovery is regenerating.

const PULSE_DURATION := 1.1

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _material: StandardMaterial3D
var _pulse_tween: Tween


func _ready() -> void:
	var mesh_material := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mesh_material != null:
		_material = mesh_material.duplicate() as StandardMaterial3D
		_mesh.set_surface_override_material(0, _material)

	scale = Vector3(0.55, 1.0, 0.55)
	_start_pulse()


func _exit_tree() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()


func _start_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(
		self,
		"scale",
		Vector3(0.85, 1.0, 0.85),
		PULSE_DURATION * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _material != null:
		_pulse_tween.tween_property(
			_material,
			"emission_energy_multiplier",
			2.4,
			PULSE_DURATION * 0.5
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(
			_material,
			"albedo_color:a",
			0.55,
			PULSE_DURATION * 0.5
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_pulse_tween.chain().set_parallel(true)
	_pulse_tween.tween_property(
		self,
		"scale",
		Vector3(0.55, 1.0, 0.55),
		PULSE_DURATION * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _material != null:
		_pulse_tween.tween_property(
			_material,
			"emission_energy_multiplier",
			1.1,
			PULSE_DURATION * 0.5
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(
			_material,
			"albedo_color:a",
			0.28,
			PULSE_DURATION * 0.5
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
