class_name TargetFeedback
extends RefCounted

## Shared pulse/blink feedback for gather, rally, and attack targets.

const PULSE_SCALE := 1.18
const PULSE_DURATION := 0.1
const PULSE_COUNT := 3


static func play(
	host: Node,
	mesh: MeshInstance3D,
	mesh_material: StandardMaterial3D,
	base_albedo: Color,
	base_emission: Color,
	base_emission_enabled: bool,
	existing_tween: Tween
) -> Tween:
	if host == null or mesh == null or mesh_material == null:
		return existing_tween

	if existing_tween != null and existing_tween.is_valid():
		existing_tween.kill()

	mesh.scale = Vector3.ONE
	mesh_material.albedo_color = base_albedo.lightened(0.35)
	mesh_material.emission_enabled = true
	mesh_material.emission = base_albedo.lightened(0.5)

	var feedback_tween: Tween = host.create_tween()
	for _pulse_index: int in PULSE_COUNT:
		feedback_tween.tween_property(
			mesh,
			"scale",
			Vector3.ONE * PULSE_SCALE,
			PULSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		feedback_tween.tween_property(
			mesh,
			"scale",
			Vector3.ONE,
			PULSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	feedback_tween.tween_callback(
		_reset_visual.bind(mesh, mesh_material, base_albedo, base_emission, base_emission_enabled)
	)
	return feedback_tween


static func _reset_visual(
	mesh: MeshInstance3D,
	mesh_material: StandardMaterial3D,
	base_albedo: Color,
	base_emission: Color,
	base_emission_enabled: bool
) -> void:
	if mesh != null:
		mesh.scale = Vector3.ONE

	if mesh_material == null:
		return

	mesh_material.albedo_color = base_albedo
	mesh_material.emission = base_emission
	mesh_material.emission_enabled = base_emission_enabled
