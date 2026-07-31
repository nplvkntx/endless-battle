class_name ImpactFxPool
extends RefCounted

## Reuses lightweight projectile trail and impact particle emitters.
## Visual-only — does not affect combat, targeting, or AI.

enum FxKind { ARROW_TRAIL, SHELL_SMOKE, GROUND_DUST, HIT_SPARKS, SHELL_BURST }

const POOL_ROOT_NAME := &"ImpactFxPoolRoot"
const MAX_IDLE_PER_KIND := 32

static var _arrow_trail_idle: Array[GPUParticles3D] = []
static var _shell_smoke_idle: Array[GPUParticles3D] = []
static var _ground_dust_idle: Array[GPUParticles3D] = []
static var _hit_sparks_idle: Array[GPUParticles3D] = []
static var _shell_burst_idle: Array[GPUParticles3D] = []
static var _pool_root: Node


static func reset_match_state() -> void:
	_release_idle_particles(_arrow_trail_idle)
	_release_idle_particles(_shell_smoke_idle)
	_release_idle_particles(_ground_dust_idle)
	_release_idle_particles(_hit_sparks_idle)
	_release_idle_particles(_shell_burst_idle)
	if _pool_root != null and is_instance_valid(_pool_root):
		_pool_root.queue_free()
	_pool_root = null


static func acquire_particles(kind: FxKind) -> GPUParticles3D:
	var idle: Array[GPUParticles3D] = _idle_particles_for(kind)
	var particles: GPUParticles3D = null
	while not idle.is_empty():
		var candidate: GPUParticles3D = idle.pop_back()
		if candidate != null and is_instance_valid(candidate):
			particles = candidate
			break

	if particles == null:
		particles = _create_particles(kind)

	_detach_from_current_parent(particles)
	particles.visible = true
	particles.emitting = false
	particles.amount_ratio = 1.0
	particles.restart()
	return particles


static func release_particles(particles: GPUParticles3D, kind: FxKind) -> void:
	if particles == null or not is_instance_valid(particles):
		return

	particles.emitting = false
	particles.amount_ratio = 1.0
	particles.visible = false
	particles.restart()
	_detach_from_current_parent(particles)

	var idle: Array[GPUParticles3D] = _idle_particles_for(kind)
	if idle.size() >= MAX_IDLE_PER_KIND:
		particles.queue_free()
		return

	var root: Node = _ensure_pool_root()
	if root == null:
		particles.queue_free()
		return

	root.add_child(particles)
	idle.append(particles)


static func get_idle_count(kind: FxKind) -> int:
	return _idle_particles_for(kind).size()


static func _idle_particles_for(kind: FxKind) -> Array[GPUParticles3D]:
	match kind:
		FxKind.SHELL_SMOKE:
			return _shell_smoke_idle
		FxKind.GROUND_DUST:
			return _ground_dust_idle
		FxKind.HIT_SPARKS:
			return _hit_sparks_idle
		FxKind.SHELL_BURST:
			return _shell_burst_idle
		_:
			return _arrow_trail_idle


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


static func _detach_from_current_parent(node: Node) -> void:
	if node == null:
		return
	var current_parent: Node = node.get_parent()
	if current_parent != null:
		current_parent.remove_child(node)


static func _release_idle_particles(idle: Array[GPUParticles3D]) -> void:
	for particles: GPUParticles3D in idle:
		if particles != null and is_instance_valid(particles):
			particles.queue_free()
	idle.clear()


static func _create_particles(kind: FxKind) -> GPUParticles3D:
	match kind:
		FxKind.SHELL_SMOKE:
			return _make_shell_smoke()
		FxKind.GROUND_DUST:
			return _make_ground_dust()
		FxKind.HIT_SPARKS:
			return _make_hit_sparks()
		FxKind.SHELL_BURST:
			return _make_shell_burst()
		_:
			return _make_arrow_trail()


static func _make_arrow_trail() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledArrowTrail"
	particles.amount = 10
	particles.lifetime = 0.28
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.randomness = 0.25
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-1.5, -1.0, -1.5), Vector3(3.0, 2.0, 3.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process.direction = Vector3(0.0, 0.0, 1.0)
	process.spread = 12.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.2
	process.gravity = Vector3(0.0, -0.4, 0.0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_min = 0.06
	process.scale_max = 0.14
	process.color = Color(0.72, 0.62, 0.42, 0.45)
	process.color_ramp = _make_alpha_ramp(
		Color(0.78, 0.68, 0.48, 0.0),
		Color(0.7, 0.58, 0.38, 0.4),
		Color(0.55, 0.45, 0.3, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(0.72, 0.62, 0.42, 0.4), 0.12)
	return particles


static func _make_shell_smoke() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledShellSmoke"
	particles.amount = 14
	particles.lifetime = 0.55
	particles.one_shot = false
	particles.explosiveness = 0.05
	particles.randomness = 0.35
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 3.0, 4.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.08
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 35.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0.0, 0.35, 0.0)
	process.damping_min = 0.2
	process.damping_max = 0.5
	process.scale_min = 0.2
	process.scale_max = 0.55
	process.color = Color(0.4, 0.4, 0.42, 0.5)
	process.color_ramp = _make_alpha_ramp(
		Color(0.48, 0.48, 0.5, 0.0),
		Color(0.36, 0.36, 0.38, 0.45),
		Color(0.26, 0.26, 0.28, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(0.38, 0.38, 0.4, 0.45), 0.35)
	return particles


static func _make_ground_dust() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledGroundDust"
	particles.amount = 16
	particles.lifetime = 0.45
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.randomness = 0.35
	particles.visibility_aabb = AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 3.0, 6.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 70.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0.0, -1.5, 0.0)
	process.damping_min = 0.8
	process.damping_max = 1.6
	process.scale_min = 0.18
	process.scale_max = 0.5
	process.color = Color(0.58, 0.48, 0.34, 0.65)
	process.color_ramp = _make_alpha_ramp(
		Color(0.62, 0.52, 0.38, 0.0),
		Color(0.55, 0.45, 0.32, 0.6),
		Color(0.4, 0.34, 0.26, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(0.58, 0.48, 0.34, 0.5), 0.35)
	return particles


static func _make_hit_sparks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledHitSparks"
	particles.amount = 14
	particles.lifetime = 0.28
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.randomness = 0.4
	particles.visibility_aabb = AABB(Vector3(-2.0, -0.5, -2.0), Vector3(4.0, 3.0, 4.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 80.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.8
	process.gravity = Vector3(0.0, -8.0, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.2
	process.scale_min = 0.04
	process.scale_max = 0.1
	process.color = Color(1.0, 0.85, 0.45, 0.95)
	process.color_ramp = _make_alpha_ramp(
		Color(1.0, 0.95, 0.7, 0.0),
		Color(1.0, 0.75, 0.3, 0.9),
		Color(0.7, 0.35, 0.1, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(1.0, 0.85, 0.45, 0.9), 0.1)
	return particles


static func _make_shell_burst() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledShellBurst"
	particles.amount = 22
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 0.88
	particles.randomness = 0.4
	particles.visibility_aabb = AABB(Vector3(-4.0, -0.5, -4.0), Vector3(8.0, 4.0, 8.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.55
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 65.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.damping_min = 0.5
	process.damping_max = 1.4
	process.scale_min = 0.25
	process.scale_max = 0.7
	process.color = Color(0.45, 0.42, 0.38, 0.7)
	process.color_ramp = _make_alpha_ramp(
		Color(0.55, 0.5, 0.42, 0.0),
		Color(0.4, 0.38, 0.34, 0.6),
		Color(0.3, 0.28, 0.25, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(0.42, 0.4, 0.36, 0.55), 0.45)
	return particles


static func _make_alpha_ramp(start: Color, mid: Color, end: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	gradient.colors = PackedColorArray([start, mid, end])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _make_billboard_mesh(albedo: Color, quad_size: float) -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(quad_size, quad_size)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.albedo_color = albedo
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.particles_anim_h_frames = 1
	material.particles_anim_v_frames = 1
	material.particles_anim_loop = false
	mesh.material = material
	return mesh
