class_name AreaBuffZone
extends Node3D

## Reusable ground area that applies a buff while units stand inside.
## Used by Smoke and future ground-area spells.

signal unit_entered(unit: Unit)
signal unit_exited(unit: Unit)
signal zone_expired()

const BUFF_ID_SMOKE := &"area_smoke"
const BUFF_ID_SMOKE_SPEED := &"area_smoke_speed"

@export var radius: float = 4.0
@export var duration: float = 6.0
@export var tick_interval: float = 0.1
@export var affects_enemies: bool = false
@export var affects_allies: bool = true
@export var source_team_id: int = -1
@export var move_speed_bonus: float = 0.0
@export var grants_stealth_to_source_only: bool = true

var source_unit: Unit = null
var buff_id: StringName = BUFF_ID_SMOKE
var _remaining: float = 0.0
var _tick_accumulator: float = 0.0
var _units_inside: Dictionary = {} ## instance_id -> Unit
var _speed_bonus_applied: Dictionary = {} ## instance_id -> float bonus currently applied
var _decal: MeshInstance3D = null
var _edge_ring: MeshInstance3D = null
var _smoke_particles: GPUParticles3D = null


func configure(
	zone_radius: float,
	zone_duration: float,
	source: Unit,
	speed_bonus: float = 0.0
) -> void:
	radius = zone_radius
	duration = zone_duration
	_remaining = zone_duration
	source_unit = source
	move_speed_bonus = speed_bonus
	if source != null and is_instance_valid(source):
		source_team_id = source.team_id


func _ready() -> void:
	_remaining = duration
	_build_visuals()
	set_physics_process(true)
	_refresh_occupancy()


func _physics_process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_expire()
		return

	_tick_accumulator += delta
	if _tick_accumulator < tick_interval:
		return
	_tick_accumulator = 0.0
	_refresh_occupancy()


func contains_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return _units_inside.has(unit.get_instance_id())


func get_remaining_duration() -> float:
	return maxf(_remaining, 0.0)


func _refresh_occupancy() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var still_inside: Dictionary = {}
	var radius_sq: float = radius * radius

	for group_name: StringName in [&"units", &"enemies", &"heroes"]:
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Unit:
				continue
			var unit: Unit = node_variant as Unit
			if not _is_affected_faction(unit):
				continue
			var offset: Vector3 = unit.global_position - global_position
			offset.y = 0.0
			if offset.length_squared() > radius_sq:
				continue
			still_inside[unit.get_instance_id()] = unit

	# Exits
	var exited_ids: Array = []
	for unit_id: Variant in _units_inside.keys():
		if not still_inside.has(unit_id):
			exited_ids.append(unit_id)
	for unit_id: Variant in exited_ids:
		var left: Unit = _units_inside[unit_id] as Unit
		_units_inside.erase(unit_id)
		_on_unit_exit(left)

	# Enters / stay
	for unit_id: Variant in still_inside.keys():
		var unit: Unit = still_inside[unit_id] as Unit
		if not _units_inside.has(unit_id):
			_units_inside[unit_id] = unit
			_on_unit_enter(unit)
		else:
			_on_unit_stay(unit)


func _is_affected_faction(unit: Unit) -> bool:
	if unit == null:
		return false
	var same_team: bool = unit.team_id == source_team_id
	# team_id -1 (player default) vs enemy 1
	if source_unit != null and is_instance_valid(source_unit):
		same_team = not CombatTargetValidation.are_hostile(source_unit, unit)
	if same_team:
		return affects_allies
	return affects_enemies


func _on_unit_enter(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_apply_speed_bonus(unit)
	if grants_stealth_to_source_only and unit == source_unit:
		StealthService.set_combat_hidden(unit, true)
	unit_entered.emit(unit)


func _on_unit_stay(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if grants_stealth_to_source_only and unit == source_unit:
		# Source may have briefly revealed itself; zone owner re-hides via reveal timer.
		pass


func _on_unit_exit(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_clear_speed_bonus(unit)
	if grants_stealth_to_source_only and unit == source_unit:
		StealthService.set_combat_hidden(unit, false)
	unit_exited.emit(unit)


func _apply_speed_bonus(unit: Unit) -> void:
	if move_speed_bonus == 0.0 or unit == null:
		return
	var unit_id: int = unit.get_instance_id()
	if _speed_bonus_applied.has(unit_id):
		return
	unit.move_speed += move_speed_bonus
	_speed_bonus_applied[unit_id] = move_speed_bonus

	var definition := BuffDefinition.create(BUFF_ID_SMOKE_SPEED, _remaining)
	definition.display_name = "Smoke"
	definition.move_speed_bonus = move_speed_bonus
	BuffService.apply(unit, definition, source_unit, _remaining)


func _clear_speed_bonus(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var unit_id: int = unit.get_instance_id()
	if _speed_bonus_applied.has(unit_id):
		unit.move_speed -= float(_speed_bonus_applied[unit_id])
		_speed_bonus_applied.erase(unit_id)
	BuffService.remove(unit, BUFF_ID_SMOKE_SPEED)


func _expire() -> void:
	var units: Array = _units_inside.values()
	for unit_variant: Variant in units:
		_on_unit_exit(unit_variant as Unit)
	_units_inside.clear()
	zone_expired.emit()
	queue_free()


func _build_visuals() -> void:
	# Ground decal disc
	_decal = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	_decal.mesh = disc
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.12, 0.14, 0.18, 0.55)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_decal.material_override = disc_mat
	_decal.scale = Vector3(radius, 1.0, radius)
	_decal.position = Vector3(0.0, 0.02, 0.0)
	add_child(_decal)

	# Soft edge ring
	_edge_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	_edge_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.35, 0.4, 0.48, 0.35)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_edge_ring.material_override = ring_mat
	_edge_ring.scale = Vector3(radius, 0.15, radius)
	_edge_ring.position = Vector3(0.0, 0.05, 0.0)
	add_child(_edge_ring)

	# Rising smoke particles
	_smoke_particles = GPUParticles3D.new()
	_smoke_particles.amount = 28
	_smoke_particles.lifetime = 1.8
	_smoke_particles.visibility_aabb = AABB(Vector3(-radius, 0, -radius), Vector3(radius * 2.0, 4.0, radius * 2.0))
	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = radius * 0.85
	process_mat.direction = Vector3(0, 1, 0)
	process_mat.spread = 30.0
	process_mat.initial_velocity_min = 0.4
	process_mat.initial_velocity_max = 1.2
	process_mat.gravity = Vector3(0, 0.2, 0)
	process_mat.scale_min = 0.35
	process_mat.scale_max = 0.9
	process_mat.color = Color(0.45, 0.48, 0.55, 0.55)
	_smoke_particles.process_material = process_mat
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(0.5, 0.52, 0.58, 0.4)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.3
	particle_mesh.height = 0.6
	particle_mesh.material = draw_mat
	_smoke_particles.draw_pass_1 = particle_mesh
	_smoke_particles.position = Vector3(0.0, 0.4, 0.0)
	add_child(_smoke_particles)

	# Edge fade over lifetime
	var fade := create_tween()
	fade.tween_property(disc_mat, "albedo_color:a", 0.15, duration)
	fade.parallel().tween_property(ring_mat, "albedo_color:a", 0.08, duration)
