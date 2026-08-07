extends Node

## Shared player command markers and lightweight unit movement dust.
## Visual-only: never issues orders, changes targeting, or affects AI behavior.

enum MarkerKind {
	MOVE,
	ATTACK_MOVE,
	PATROL,
}

enum TrackKind {
	MARKER,
	DUST,
}

## Master switches — easy to disable or tune from the inspector / debugger.
var enabled: bool = true
var markers_enabled: bool = true
var dust_enabled: bool = true

## Marker timing (seconds).
const MARKER_DURATION := 0.85
const MARKER_FADE_START_RATIO := 0.45
const MARKER_Y := 0.06
const MAX_ACTIVE_MARKERS := 10

## Dust timing (seconds).
const DUST_START_LIFETIME := 0.32
const DUST_FOOTSTEP_LIFETIME := 0.28
const DUST_FOOTSTEP_COOLDOWN := 0.42
const DUST_MIN_SPEED_SQ := 0.35
const MAX_ACTIVE_DUST := 28
const FOOTSTEP_COOLDOWN_PRUNE_LIMIT := 256

## Colors chosen for contrast on grass/dirt; kinds also differ by shape.
const MOVE_COLOR := Color(0.92, 0.95, 1.0, 0.92)
const ATTACK_MOVE_COLOR := Color(1.0, 0.42, 0.18, 0.95)
const PATROL_COLOR := Color(1.0, 0.92, 0.25, 0.95)
const DUST_COLOR := Color(0.62, 0.52, 0.38, 0.55)

## Instance IDs only — never retain raw effect Nodes across delayed work.
var _active_markers: PackedInt64Array = []
var _active_dust: PackedInt64Array = []
## instance_id -> last footstep msec
var _footstep_last_msec: Dictionary = {}


func _ready() -> void:
	MatchSession.register_match_reset(&"CommandFeedback", clear_all)


func clear_all() -> void:
	## Free live FX immediately so any root-bound tweens die with them.
	_free_tracked(_active_markers)
	_free_tracked(_active_dust)
	_active_markers = PackedInt64Array()
	_active_dust = PackedInt64Array()
	_footstep_last_msec.clear()


func get_active_marker_count() -> int:
	_prune_invalid(_active_markers)
	return _active_markers.size()


func get_active_dust_count() -> int:
	_prune_invalid(_active_dust)
	return _active_dust.size()


## Player ground Move command marker at the accepted destination.
func show_move_marker(world_position: Vector3) -> void:
	_show_marker(world_position, MarkerKind.MOVE)


## Player Attack-Move marker (distinct X shape).
func show_attack_move_marker(world_position: Vector3) -> void:
	_show_marker(world_position, MarkerKind.ATTACK_MOVE)


## Player Patrol marker (distinct dual-chevron shape).
func show_patrol_marker(world_position: Vector3) -> void:
	_show_marker(world_position, MarkerKind.PATROL)


## Brief pulse on an attack target (unit or building). Player-path only.
func pulse_attack_target(target: Node3D) -> void:
	if not enabled or not markers_enabled:
		return
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("play_target_feedback"):
		target.call("play_target_feedback")
		return
	# Fallback ring at the target if it has no pulse API.
	_show_marker(target.global_position, MarkerKind.ATTACK_MOVE)


## Called when a ground unit transitions into moving.
func notify_movement_started(unit: Node3D) -> void:
	if not enabled or not dust_enabled:
		return
	if not _is_dust_eligible_unit(unit):
		return
	_spawn_dust_puff(unit.global_position, true)


## Lightweight footstep dust while moving (cooldown-gated, not per-frame spawn).
func notify_unit_moving(unit: Node3D) -> void:
	if not enabled or not dust_enabled:
		return
	if not _is_dust_eligible_unit(unit):
		return

	var body := unit as CharacterBody3D
	if body == null:
		return
	var horizontal: Vector3 = Vector3(body.velocity.x, 0.0, body.velocity.z)
	if horizontal.length_squared() < DUST_MIN_SPEED_SQ:
		return

	var id: int = unit.get_instance_id()
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_footstep_last_msec.get(id, 0))
	if now_msec - last_msec < int(DUST_FOOTSTEP_COOLDOWN * 1000.0):
		return

	_footstep_last_msec[id] = now_msec
	if _footstep_last_msec.size() > FOOTSTEP_COOLDOWN_PRUNE_LIMIT:
		_footstep_last_msec.clear()

	_spawn_dust_puff(unit.global_position, false)


func _show_marker(world_position: Vector3, kind: MarkerKind) -> void:
	if not enabled or not markers_enabled:
		return
	if not world_position.is_finite():
		return

	_prune_invalid(_active_markers)
	while _active_markers.size() >= MAX_ACTIVE_MARKERS:
		_free_tracked_id(_active_markers[0])
		_active_markers.remove_at(0)

	var marker: Node3D = _build_marker(kind)
	var parent: Node = _fx_parent()
	if parent == null:
		marker.free()
		return

	parent.add_child(marker)
	marker.global_position = Vector3(world_position.x, MARKER_Y, world_position.z)
	_active_markers.append(marker.get_instance_id())
	_animate_fade_and_free(marker, MARKER_DURATION, MARKER_FADE_START_RATIO)


func _spawn_dust_puff(world_position: Vector3, is_start: bool) -> void:
	if not world_position.is_finite():
		return

	_prune_invalid(_active_dust)
	while _active_dust.size() >= MAX_ACTIVE_DUST:
		_free_tracked_id(_active_dust[0])
		_active_dust.remove_at(0)

	var puff: Node3D = _build_dust_puff(is_start)
	var parent: Node = _fx_parent()
	if parent == null:
		puff.free()
		return

	parent.add_child(puff)
	puff.global_position = Vector3(world_position.x, 0.04, world_position.z)
	_active_dust.append(puff.get_instance_id())
	var lifetime: float = DUST_START_LIFETIME if is_start else DUST_FOOTSTEP_LIFETIME
	_animate_dust(puff, lifetime)


func _is_dust_eligible_unit(unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	# Buildings and projectiles are not Unit/CharacterBody3D movers in this codebase.
	if not unit is Unit:
		return false
	if unit.is_in_group(&"buildings"):
		return false
	return true


func _fx_parent() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var current: Node = tree.current_scene
	if current != null:
		return current
	return tree.root


func _build_marker(kind: MarkerKind) -> Node3D:
	var root := Node3D.new()
	root.name = "CommandMarker"

	match kind:
		MarkerKind.MOVE:
			_add_ring(root, MOVE_COLOR, 0.55, 0.08)
			_add_chevron(root, MOVE_COLOR, 0.0)
		MarkerKind.ATTACK_MOVE:
			_add_ring(root, ATTACK_MOVE_COLOR, 0.55, 0.08)
			_add_cross_x(root, ATTACK_MOVE_COLOR)
		MarkerKind.PATROL:
			_add_ring(root, PATROL_COLOR, 0.55, 0.08)
			_add_chevron(root, PATROL_COLOR, -0.18)
			_add_chevron(root, PATROL_COLOR, 0.18)
		_:
			_add_ring(root, MOVE_COLOR, 0.55, 0.08)

	return root


func _build_dust_puff(is_start: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "MovementDust"
	var count: int = 3 if is_start else 2
	var base_scale: float = 0.22 if is_start else 0.14
	for i: int in count:
		var mesh_instance := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = base_scale * (0.7 + 0.15 * float(i))
		sphere.height = sphere.radius * 2.0
		mesh_instance.mesh = sphere
		mesh_instance.material_override = _make_fx_material(DUST_COLOR)
		mesh_instance.position = Vector3(
			randf_range(-0.12, 0.12),
			0.02,
			randf_range(-0.12, 0.12)
		)
		root.add_child(mesh_instance)
	return root


func _add_ring(parent: Node3D, color: Color, radius: float, thickness: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.05, radius - thickness)
	torus.outer_radius = radius
	torus.rings = 16
	torus.ring_segments = 24
	mesh_instance.mesh = torus
	mesh_instance.material_override = _make_fx_material(color)
	mesh_instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	parent.add_child(mesh_instance)


func _add_cross_x(parent: Node3D, color: Color) -> void:
	for angle_deg: float in [45.0, -45.0]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.85, 0.04, 0.12)
		bar.mesh = box
		bar.material_override = _make_fx_material(color)
		bar.rotation_degrees = Vector3(0.0, angle_deg, 0.0)
		bar.position.y = 0.03
		parent.add_child(bar)


func _add_chevron(parent: Node3D, color: Color, z_offset: float) -> void:
	# Two angled bars form a ">" / arrowhead readable from above.
	for side: float in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.42, 0.04, 0.1)
		bar.mesh = box
		bar.material_override = _make_fx_material(color)
		bar.rotation_degrees = Vector3(0.0, side * 35.0, 0.0)
		bar.position = Vector3(side * 0.12, 0.03, z_offset)
		parent.add_child(bar)


func _make_fx_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 1.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	return material


func _animate_fade_and_free(root: Node3D, duration: float, fade_start_ratio: float) -> void:
	## Bind tween to the effect node so freeing/reset kills the tween with it.
	var effect_id: int = root.get_instance_id()
	var materials: Array[StandardMaterial3D] = _collect_materials(root)
	var tween: Tween = root.create_tween()
	var fade_delay: float = duration * fade_start_ratio
	var fade_duration: float = maxf(0.05, duration - fade_delay)
	tween.tween_interval(fade_delay)
	for material: StandardMaterial3D in materials:
		tween.parallel().tween_property(material, "albedo_color:a", 0.0, fade_duration)
		tween.parallel().tween_property(
			material,
			"emission_energy_multiplier",
			0.0,
			fade_duration
		)
	## Immutable id + track kind — never capture the effect Node in a delayed lambda.
	tween.chain().tween_callback(_finish_tracked_by_id.bind(effect_id, TrackKind.MARKER))


func _animate_dust(root: Node3D, lifetime: float) -> void:
	var effect_id: int = root.get_instance_id()
	var materials: Array[StandardMaterial3D] = _collect_materials(root)
	var tween: Tween = root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(root, "position:y", root.position.y + 0.35, lifetime)
	tween.tween_property(root, "scale", Vector3.ONE * 1.8, lifetime)
	for material: StandardMaterial3D in materials:
		tween.tween_property(material, "albedo_color:a", 0.0, lifetime)
	tween.chain().tween_callback(_finish_tracked_by_id.bind(effect_id, TrackKind.DUST))


func _collect_materials(root: Node) -> Array[StandardMaterial3D]:
	var materials: Array[StandardMaterial3D] = []
	_collect_materials_recursive(root, materials)
	return materials


func _collect_materials_recursive(node: Node, out: Array[StandardMaterial3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var material: Material = mesh_instance.material_override
		if material is StandardMaterial3D:
			out.append(material as StandardMaterial3D)
	for child: Node in node.get_children():
		_collect_materials_recursive(child, out)


func _finish_tracked_by_id(effect_id: int, track_kind: TrackKind) -> void:
	match track_kind:
		TrackKind.MARKER:
			_remove_tracked_id(_active_markers, effect_id)
		TrackKind.DUST:
			_remove_tracked_id(_active_dust, effect_id)
		_:
			pass
	var obj: Object = instance_from_id(effect_id)
	if obj == null or not is_instance_valid(obj):
		return
	if obj is Node:
		(obj as Node).queue_free()


func _remove_tracked_id(track: PackedInt64Array, effect_id: int) -> void:
	for i: int in range(track.size() - 1, -1, -1):
		if track[i] == effect_id:
			track.remove_at(i)
			return


func _prune_invalid(track: PackedInt64Array) -> void:
	var write: int = 0
	for i: int in track.size():
		var effect_id: int = track[i]
		var obj: Object = instance_from_id(effect_id)
		if obj != null and is_instance_valid(obj):
			track[write] = effect_id
			write += 1
	track.resize(write)


func _free_tracked(track: PackedInt64Array) -> void:
	for effect_id: int in track:
		_free_tracked_id(effect_id)


func _free_tracked_id(effect_id: int) -> void:
	var obj: Object = instance_from_id(effect_id)
	if obj == null or not is_instance_valid(obj):
		return
	if not obj is Node:
		return
	var node: Node = obj as Node
	## Detach + free now so root-bound tweens cannot outlive the effect.
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
