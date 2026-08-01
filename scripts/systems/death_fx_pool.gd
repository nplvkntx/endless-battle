class_name DeathFxPool
extends RefCounted

## Reuses one-shot death particle emitters and corpse meshes.
## Visual-only — does not affect combat, targeting, or AI.

enum FxKind { UNIT_DUST, HERO_DUST, BLOOD, RUBBLE, CORPSE }

const POOL_ROOT_NAME := &"DeathFxPoolRoot"
const MAX_IDLE_PER_KIND := 32

static var _unit_dust_idle: Array[GPUParticles3D] = []
static var _hero_dust_idle: Array[GPUParticles3D] = []
static var _blood_idle: Array[GPUParticles3D] = []
static var _rubble_idle: Array[GPUParticles3D] = []
static var _corpse_idle: Array[Node3D] = []
static var _pool_root: Node


static func reset_match_state() -> void:
	_release_idle_particles(_unit_dust_idle)
	_release_idle_particles(_hero_dust_idle)
	_release_idle_particles(_blood_idle)
	_release_idle_particles(_rubble_idle)
	_release_idle_nodes(_corpse_idle)
	if _pool_root != null and is_instance_valid(_pool_root):
		_pool_root.queue_free()
	_pool_root = null


static func acquire_particles(kind: FxKind) -> GPUParticles3D:
	if kind == FxKind.CORPSE:
		return null

	var idle: Array[GPUParticles3D] = _idle_particles_for(kind)
	var particles: GPUParticles3D = null
	while not idle.is_empty():
		var candidate_ref: Variant = idle.pop_back()
		if not NodeSafety.is_alive_node(candidate_ref):
			continue
		particles = candidate_ref as GPUParticles3D
		break

	if particles == null:
		particles = _create_particles(kind)

	_detach_from_current_parent(particles)
	particles.visible = true
	particles.emitting = false
	particles.restart()
	return particles


static func acquire_corpse() -> Node3D:
	var corpse: Node3D = null
	while not _corpse_idle.is_empty():
		var candidate_ref: Variant = _corpse_idle.pop_back()
		if not NodeSafety.is_alive_node(candidate_ref):
			continue
		corpse = candidate_ref as Node3D
		break

	if corpse == null:
		corpse = _create_corpse()

	_detach_from_current_parent(corpse)
	corpse.visible = true
	corpse.scale = Vector3.ONE
	_reset_corpse_materials(corpse)
	return corpse


static func release_particles(particles: GPUParticles3D, kind: FxKind) -> void:
	if particles == null or not is_instance_valid(particles):
		return
	if kind == FxKind.CORPSE:
		particles.queue_free()
		return

	particles.emitting = false
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


static func release_corpse(corpse: Node3D) -> void:
	if corpse == null or not is_instance_valid(corpse):
		return

	corpse.visible = false
	corpse.scale = Vector3.ONE
	_detach_from_current_parent(corpse)

	if _corpse_idle.size() >= MAX_IDLE_PER_KIND:
		corpse.queue_free()
		return

	var root: Node = _ensure_pool_root()
	if root == null:
		corpse.queue_free()
		return

	root.add_child(corpse)
	_corpse_idle.append(corpse)


static func get_idle_count(kind: FxKind) -> int:
	if kind == FxKind.CORPSE:
		return _corpse_idle.size()
	return _idle_particles_for(kind).size()


static func _idle_particles_for(kind: FxKind) -> Array[GPUParticles3D]:
	match kind:
		FxKind.HERO_DUST:
			return _hero_dust_idle
		FxKind.BLOOD:
			return _blood_idle
		FxKind.RUBBLE:
			return _rubble_idle
		_:
			return _unit_dust_idle


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
	for particles_ref: Variant in idle:
		if NodeSafety.is_alive_node(particles_ref):
			(particles_ref as GPUParticles3D).queue_free()
	idle.clear()


static func _release_idle_nodes(idle: Array[Node3D]) -> void:
	for node_ref: Variant in idle:
		if NodeSafety.is_alive_node(node_ref):
			(node_ref as Node3D).queue_free()
	idle.clear()


static func _create_particles(kind: FxKind) -> GPUParticles3D:
	match kind:
		FxKind.HERO_DUST:
			return _make_dust_particles(&"PooledHeroDeathDust", 48, 1.15, 0.85, 1.6)
		FxKind.BLOOD:
			return _make_blood_particles()
		FxKind.RUBBLE:
			return _make_rubble_particles()
		_:
			return _make_dust_particles(&"PooledUnitDeathDust", 28, 0.55, 0.55, 1.05)


static func _make_dust_particles(
	node_name: StringName,
	amount: int,
	sphere_radius: float,
	lifetime: float,
	speed_max: float
) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.randomness = 0.4
	particles.visibility_aabb = AABB(Vector3(-4.0, -0.5, -4.0), Vector3(8.0, 5.0, 8.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = sphere_radius
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 55.0
	process.initial_velocity_min = speed_max * 0.35
	process.initial_velocity_max = speed_max
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.damping_min = 0.8
	process.damping_max = 1.8
	process.scale_min = 0.2
	process.scale_max = 0.65
	process.color = Color(0.58, 0.48, 0.34, 0.7)
	process.color_ramp = _make_alpha_ramp(
		Color(0.62, 0.52, 0.38, 0.0),
		Color(0.55, 0.45, 0.32, 0.65),
		Color(0.4, 0.34, 0.26, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(0.58, 0.48, 0.34, 0.55), 0.45)
	return particles


static func _make_blood_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledBloodBurst"
	particles.amount = 36
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.randomness = 0.45
	particles.visibility_aabb = AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 4.0, 6.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.22
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 70.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0.0, -6.5, 0.0)
	process.damping_min = 1.2
	process.damping_max = 2.4
	process.scale_min = 0.08
	process.scale_max = 0.22
	process.color = Color(0.55, 0.05, 0.05, 0.9)
	process.color_ramp = _make_alpha_ramp(
		Color(0.7, 0.08, 0.08, 0.0),
		Color(0.5, 0.04, 0.04, 0.85),
		Color(0.25, 0.02, 0.02, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(0.55, 0.05, 0.05, 0.85), 0.18)
	return particles


static func _make_rubble_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = &"PooledRubbleDust"
	particles.amount = 56
	particles.lifetime = 1.1
	particles.one_shot = true
	particles.explosiveness = 0.88
	particles.randomness = 0.5
	particles.visibility_aabb = AABB(Vector3(-6.0, -0.5, -6.0), Vector3(12.0, 7.0, 12.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.1
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 65.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 2.6
	process.gravity = Vector3(0.0, -2.2, 0.0)
	process.damping_min = 0.6
	process.damping_max = 1.6
	process.scale_min = 0.25
	process.scale_max = 0.9
	process.color = Color(0.45, 0.42, 0.38, 0.75)
	process.color_ramp = _make_alpha_ramp(
		Color(0.5, 0.47, 0.42, 0.0),
		Color(0.4, 0.38, 0.34, 0.7),
		Color(0.3, 0.28, 0.25, 0.0)
	)
	particles.process_material = process
	particles.draw_pass_1 = _make_billboard_mesh(Color(0.42, 0.4, 0.36, 0.6), 0.55)
	return particles


static func _create_corpse() -> Node3D:
	var root := Node3D.new()
	root.name = &"PooledCorpse"

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = &"CorpseMesh"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 0.85
	mesh_instance.mesh = capsule
	mesh_instance.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	mesh_instance.position = Vector3(0.0, 0.12, 0.0)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = _make_corpse_material(Color(0.28, 0.26, 0.24, 0.92))
	root.add_child(mesh_instance)
	return root


static func _reset_corpse_materials(corpse: Node3D) -> void:
	var mesh_instance := corpse.get_node_or_null("CorpseMesh") as MeshInstance3D
	if mesh_instance == null:
		return
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		material = _make_corpse_material(Color(0.28, 0.26, 0.24, 0.92))
		mesh_instance.material_override = material
	else:
		material.albedo_color.a = 0.92


static func _make_corpse_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


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
