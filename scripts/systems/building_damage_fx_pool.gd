class_name BuildingDamageFxPool
extends RefCounted

## Reuses GPUParticles3D smoke/fire emitters across buildings.
## One active smoke and one active fire per building — pool prevents duplicate spawns.

enum FxKind { SMOKE, FIRE }

const POOL_ROOT_NAME := &"BuildingDamageFxPoolRoot"
const MAX_IDLE_PER_KIND := 24

static var _smoke_idle: Array[GPUParticles3D] = []
static var _fire_idle: Array[GPUParticles3D] = []
static var _pool_root: Node


static func reset_match_state() -> void:
	_release_idle_array(_smoke_idle)
	_release_idle_array(_fire_idle)
	if _pool_root != null and is_instance_valid(_pool_root):
		_pool_root.queue_free()
	_pool_root = null


static func acquire(kind: FxKind, parent: Node3D) -> GPUParticles3D:
	if parent == null or not is_instance_valid(parent):
		return null

	var idle: Array[GPUParticles3D] = _smoke_idle if kind == FxKind.SMOKE else _fire_idle
	var particles: GPUParticles3D = null
	while not idle.is_empty():
		var candidate: GPUParticles3D = idle.pop_back()
		if candidate != null and is_instance_valid(candidate):
			particles = candidate
			break

	if particles == null:
		particles = _create_particles(kind)

	_detach_from_current_parent(particles)
	parent.add_child(particles)
	particles.position = Vector3.ZERO
	particles.rotation = Vector3.ZERO
	particles.scale = Vector3.ONE
	particles.visible = true
	particles.emitting = false
	particles.amount_ratio = 0.0
	return particles


static func release(particles: GPUParticles3D, kind: FxKind) -> void:
	if particles == null or not is_instance_valid(particles):
		return

	particles.emitting = false
	particles.amount_ratio = 0.0
	particles.visible = false
	particles.restart()
	_detach_from_current_parent(particles)

	var idle: Array[GPUParticles3D] = _smoke_idle if kind == FxKind.SMOKE else _fire_idle
	if idle.size() >= MAX_IDLE_PER_KIND:
		particles.queue_free()
		return

	var root: Node = _ensure_pool_root()
	if root == null:
		particles.queue_free()
		return

	root.add_child(particles)
	idle.append(particles)


static func _ensure_pool_root() -> Node:
	if _pool_root != null and is_instance_valid(_pool_root):
		return _pool_root

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null

	var existing: Node = tree.root.get_node_or_null(NodePath(String(POOL_ROOT_NAME)))
	if existing != null:
		_pool_root = existing
		return _pool_root

	_pool_root = Node.new()
	_pool_root.name = POOL_ROOT_NAME
	tree.root.add_child(_pool_root)
	return _pool_root


static func _detach_from_current_parent(particles: GPUParticles3D) -> void:
	var current_parent: Node = particles.get_parent()
	if current_parent != null:
		current_parent.remove_child(particles)


static func _release_idle_array(idle: Array[GPUParticles3D]) -> void:
	for particles: GPUParticles3D in idle:
		if particles != null and is_instance_valid(particles):
			particles.queue_free()
	idle.clear()


static func _create_particles(kind: FxKind) -> GPUParticles3D:
	if kind == FxKind.FIRE:
		return _create_fire_particles()
	return _create_smoke_particles()


static func _create_smoke_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledSmoke"
	particles.amount = 28
	particles.lifetime = 2.0
	particles.preprocess = 0.4
	particles.explosiveness = 0.05
	particles.randomness = 0.35
	particles.visibility_aabb = AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 8.0, 6.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.45
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 28.0
	process.initial_velocity_min = 0.35
	process.initial_velocity_max = 0.95
	process.gravity = Vector3(0.0, 0.55, 0.0)
	process.damping_min = 0.1
	process.damping_max = 0.35
	process.scale_min = 0.35
	process.scale_max = 0.95
	process.color = Color(0.42, 0.42, 0.45, 0.55)
	process.color_ramp = _make_alpha_ramp(
		Color(0.5, 0.5, 0.52, 0.0),
		Color(0.38, 0.38, 0.4, 0.55),
		Color(0.28, 0.28, 0.3, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(
		Color(0.4, 0.4, 0.42, 0.5),
		0.55
	)
	return particles


static func _create_fire_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledFire"
	particles.amount = 36
	particles.lifetime = 0.85
	particles.preprocess = 0.2
	particles.explosiveness = 0.15
	particles.randomness = 0.4
	particles.visibility_aabb = AABB(Vector3(-2.5, -0.25, -2.5), Vector3(5.0, 5.5, 5.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.28
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 18.0
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0.0, 1.4, 0.0)
	process.damping_min = 0.2
	process.damping_max = 0.6
	process.scale_min = 0.18
	process.scale_max = 0.55
	process.color = Color(1.0, 0.45, 0.08, 0.85)
	process.color_ramp = _make_alpha_ramp(
		Color(1.0, 0.85, 0.25, 0.0),
		Color(1.0, 0.4, 0.05, 0.9),
		Color(0.35, 0.05, 0.0, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(
		Color(1.0, 0.55, 0.12, 0.8),
		0.4,
		true
	)
	return particles


static func _make_alpha_ramp(start: Color, mid: Color, end: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([start, mid, end])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _make_billboard_mesh(
	albedo: Color,
	quad_size: float,
	emissive: bool = false
) -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(quad_size, quad_size)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = (
		BaseMaterial3D.BLEND_MODE_ADD if emissive else BaseMaterial3D.BLEND_MODE_MIX
	)
	material.albedo_color = albedo
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.particles_anim_h_frames = 1
	material.particles_anim_v_frames = 1
	material.particles_anim_loop = false
	if emissive:
		material.emission_enabled = true
		material.emission = Color(1.0, 0.45, 0.08, 1.0)
		material.emission_energy_multiplier = 2.2
	mesh.material = material
	return mesh
