extends Node3D

## Endless Battle Hunter's Precision marks — readable from RTS camera height.
## Follows the marked target; frees itself when the target dies or is invalid.

const MARK_HEIGHT := 2.35
const MARK_SPACING := 0.42
const FOLLOW_LERP := 18.0

var _target: Variant = null
var _target_tree_exiting_handler: Callable = Callable()
var _mark_count: int = 0
var _mark_meshes: Array[MeshInstance3D] = []
var _flashing: bool = false


func bind_target(target: Node3D) -> void:
	_clear_target_lifetime_watch()
	_target = NodeSafety.safe_node(target)
	if not NodeSafety.is_alive_node(_target):
		queue_free()
		return
	_watch_target_lifetime(_target as Node3D)
	_sync_position(true)


func set_mark_count(count: int) -> void:
	_mark_count = clampi(count, 0, 2)
	_ensure_marks()
	for i: int in range(_mark_meshes.size()):
		_mark_meshes[i].visible = i < _mark_count
		if i < _mark_count:
			_pulse_mark(_mark_meshes[i], i)


func play_proc_flash_and_free() -> void:
	if _flashing:
		return
	_flashing = true
	_ensure_marks()
	for mesh: MeshInstance3D in _mark_meshes:
		mesh.visible = true
		var material := mesh.get_surface_override_material(0) as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 6.0
			material.albedo_color = Color(1.0, 0.92, 0.35, 1.0)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.55, 1.55, 1.55), 0.12).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3(0.15, 0.15, 0.15), 0.18).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func clear_and_free() -> void:
	_clear_target_lifetime_watch()
	_target = null
	queue_free()


func _process(delta: float) -> void:
	if _flashing:
		return
	if not NodeSafety.is_alive_node(_target):
		clear_and_free()
		return
	if not CombatTargetValidation.is_valid_combat_target(_target):
		clear_and_free()
		return
	_sync_position(false, delta)


func _sync_position(immediate: bool = false, delta: float = 0.0) -> void:
	if not NodeSafety.is_alive_node(_target):
		return
	var desired: Vector3 = (_target as Node3D).global_position + Vector3(0.0, MARK_HEIGHT, 0.0)
	if immediate or delta <= 0.0:
		global_position = desired
		return
	global_position = global_position.lerp(desired, clampf(FOLLOW_LERP * delta, 0.0, 1.0))


func _ensure_marks() -> void:
	while _mark_meshes.size() < 2:
		var index: int = _mark_meshes.size()
		var mesh := MeshInstance3D.new()
		mesh.name = "HunterMark%d" % (index + 1)
		var diamond := BoxMesh.new()
		diamond.size = Vector3(0.28, 0.28, 0.08)
		mesh.mesh = diamond
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.95, 0.72, 0.18, 0.92)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.7, 0.15, 1.0)
		material.emission_energy_multiplier = 2.2 if index == 0 else 3.0
		material.no_depth_test = true
		mesh.set_surface_override_material(0, material)
		mesh.rotation_degrees = Vector3(45.0, 45.0, 0.0)
		var x_offset: float = -MARK_SPACING * 0.5 + float(index) * MARK_SPACING
		mesh.position = Vector3(x_offset, 0.0, 0.0)
		mesh.visible = false
		add_child(mesh)
		_mark_meshes.append(mesh)


func _pulse_mark(mesh: MeshInstance3D, index: int) -> void:
	if mesh == null:
		return
	mesh.scale = Vector3(0.35, 0.35, 0.35)
	var tween := create_tween()
	var peak: float = 1.05 if index == 0 else 1.2
	tween.tween_property(mesh, "scale", Vector3(peak, peak, peak), 0.14).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)


func _watch_target_lifetime(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_target_tree_exiting_handler = _on_target_tree_exiting.bind(target.get_instance_id())
	if not target.tree_exiting.is_connected(_target_tree_exiting_handler):
		target.tree_exiting.connect(_target_tree_exiting_handler, CONNECT_ONE_SHOT)


func _clear_target_lifetime_watch() -> void:
	if not _target_tree_exiting_handler.is_valid():
		_target_tree_exiting_handler = Callable()
		return

	var target_ref: Variant = _target
	if (
		NodeSafety.is_alive_node(target_ref)
		and target_ref is Node
		and (target_ref as Node).tree_exiting.is_connected(_target_tree_exiting_handler)
	):
		(target_ref as Node).tree_exiting.disconnect(_target_tree_exiting_handler)

	_target_tree_exiting_handler = Callable()


func _on_target_tree_exiting(expected_instance_id: int) -> void:
	_target_tree_exiting_handler = Callable()
	var target_ref: Variant = _target
	if NodeSafety.is_alive_node(target_ref) and int(target_ref.get_instance_id()) != expected_instance_id:
		return
	_target = null
	queue_free()


func _exit_tree() -> void:
	_clear_target_lifetime_watch()
	_target = null
