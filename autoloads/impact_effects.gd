extends Node

## Shared projectile trail and impact visuals.
## Visual-only: never changes combat, targeting, XP, or AI behavior.

## Master switches — tune from inspector / debugger.
var enabled: bool = true
var trails_enabled: bool = true
var smoke_enabled: bool = true
var ground_dust_enabled: bool = true
var hit_sparks_enabled: bool = true

const MAX_ACTIVE_BURSTS := 56
const MAX_ACTIVE_TRAILS := 40
const PARTICLE_RELEASE_PADDING := 0.12

var _active_bursts: Array[Dictionary] = []
var _active_trails: Array[Dictionary] = []


func _ready() -> void:
	MatchSession.register_match_reset(&"ImpactEffects", clear_all)


func clear_all() -> void:
	_release_active_bursts_now()
	_release_active_trails_now()
	ImpactFxPool.reset_match_state()


func get_active_burst_count() -> int:
	_prune_active_bursts()
	return _active_bursts.size()


func get_active_trail_count() -> int:
	_prune_active_trails()
	return _active_trails.size()


## Subtle arrow streak while the projectile flies.
func attach_arrow_trail(host: Node3D) -> GPUParticles3D:
	if not enabled or not trails_enabled:
		return null
	return _attach_trail(host, ImpactFxPool.FxKind.ARROW_TRAIL)


## Continuous smoke puff while a shell flies.
func attach_shell_smoke(host: Node3D) -> GPUParticles3D:
	if not enabled or not smoke_enabled:
		return null
	return _attach_trail(host, ImpactFxPool.FxKind.SHELL_SMOKE)


## Detach and pool a trail/smoke emitter previously attached to a projectile.
func release_attached(particles: GPUParticles3D, kind: ImpactFxPool.FxKind) -> void:
	if particles == null:
		return
	_remove_trail_entry(particles)
	if is_instance_valid(particles):
		ImpactFxPool.release_particles(particles, kind)


## Ground / miss impact dust.
func play_ground_impact(world_position: Vector3, scale_factor: float = 1.0) -> void:
	if not enabled or not ground_dust_enabled:
		return
	if not world_position.is_finite():
		return
	_spawn_burst(
		ImpactFxPool.FxKind.GROUND_DUST,
		Vector3(world_position.x, 0.08, world_position.z),
		scale_factor
	)


## Unit / hero hit sparks.
func play_unit_impact(world_position: Vector3, scale_factor: float = 1.0) -> void:
	if not enabled or not hit_sparks_enabled:
		return
	if not world_position.is_finite():
		return
	_spawn_burst(
		ImpactFxPool.FxKind.HIT_SPARKS,
		world_position + Vector3(0.0, 0.55, 0.0),
		scale_factor
	)


## Artillery shell crater dust (ground-oriented).
func play_shell_impact(world_position: Vector3, scale_factor: float = 1.0) -> void:
	if not enabled:
		return
	if not world_position.is_finite():
		return

	var ground_pos := Vector3(world_position.x, 0.1, world_position.z)
	if ground_dust_enabled:
		_spawn_burst(ImpactFxPool.FxKind.SHELL_BURST, ground_pos, scale_factor)
		_spawn_burst(ImpactFxPool.FxKind.GROUND_DUST, ground_pos, scale_factor * 0.85)


func _attach_trail(host: Node3D, kind: ImpactFxPool.FxKind) -> GPUParticles3D:
	if host == null or not is_instance_valid(host):
		return null

	_prune_active_trails()
	while _active_trails.size() >= MAX_ACTIVE_TRAILS:
		_force_release_oldest_trail()

	var particles: GPUParticles3D = ImpactFxPool.acquire_particles(kind)
	if particles == null:
		return null

	host.add_child(particles)
	particles.position = Vector3.ZERO
	particles.rotation = Vector3.ZERO
	particles.scale = Vector3.ONE
	particles.emitting = true
	particles.restart()

	_active_trails.append({
		"node": particles,
		"kind": kind,
		"host_id": host.get_instance_id(),
	})
	return particles


func _spawn_burst(kind: ImpactFxPool.FxKind, world_position: Vector3, scale_factor: float) -> void:
	_prune_active_bursts()
	while _active_bursts.size() >= MAX_ACTIVE_BURSTS:
		_force_release_oldest_burst()

	var particles: GPUParticles3D = ImpactFxPool.acquire_particles(kind)
	if particles == null:
		return

	var parent: Node = _fx_parent()
	if parent == null:
		ImpactFxPool.release_particles(particles, kind)
		return

	parent.add_child(particles)
	particles.global_position = world_position
	particles.scale = Vector3.ONE * maxf(0.1, scale_factor)
	particles.emitting = true
	particles.restart()

	var lifetime: float = maxf(0.15, particles.lifetime) + PARTICLE_RELEASE_PADDING
	_active_bursts.append({
		"node": particles,
		"kind": kind,
		"release_msec": Time.get_ticks_msec() + int(lifetime * 1000.0),
	})


func _fx_parent() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var current: Node = tree.current_scene
	if current != null:
		return current
	return tree.root


func _prune_active_bursts() -> void:
	var now_msec: int = Time.get_ticks_msec()
	var write: int = 0
	for entry: Dictionary in _active_bursts:
		var particles: GPUParticles3D = _as_valid_particles(entry.get("node"))
		if particles == null:
			continue
		if now_msec >= int(entry.get("release_msec", 0)):
			ImpactFxPool.release_particles(particles, entry.get("kind") as ImpactFxPool.FxKind)
			continue
		_active_bursts[write] = entry
		write += 1
	_active_bursts.resize(write)


func _prune_active_trails() -> void:
	var write: int = 0
	for entry: Dictionary in _active_trails:
		var particles: GPUParticles3D = _as_valid_particles(entry.get("node"))
		if particles == null:
			continue
		var host_id: int = int(entry.get("host_id", 0))
		if host_id != 0 and not is_instance_id_valid(host_id):
			# Host already freed (took children with it) — drop the stale entry.
			continue
		_active_trails[write] = entry
		write += 1
	_active_trails.resize(write)


func _force_release_oldest_burst() -> void:
	if _active_bursts.is_empty():
		return
	var entry: Dictionary = _active_bursts.pop_front()
	var particles: GPUParticles3D = _as_valid_particles(entry.get("node"))
	if particles != null:
		ImpactFxPool.release_particles(particles, entry.get("kind") as ImpactFxPool.FxKind)


func _force_release_oldest_trail() -> void:
	if _active_trails.is_empty():
		return
	var entry: Dictionary = _active_trails.pop_front()
	var particles: GPUParticles3D = _as_valid_particles(entry.get("node"))
	if particles != null:
		ImpactFxPool.release_particles(particles, entry.get("kind") as ImpactFxPool.FxKind)


func _remove_trail_entry(particles: GPUParticles3D) -> void:
	for i: int in range(_active_trails.size() - 1, -1, -1):
		if _active_trails[i].get("node") == particles:
			_active_trails.remove_at(i)
			return


func _release_active_bursts_now() -> void:
	for entry: Dictionary in _active_bursts:
		var particles: GPUParticles3D = _as_valid_particles(entry.get("node"))
		if particles != null:
			_detach_and_free(particles)
	_active_bursts.clear()


func _release_active_trails_now() -> void:
	for entry: Dictionary in _active_trails:
		var particles: GPUParticles3D = _as_valid_particles(entry.get("node"))
		if particles != null:
			_detach_and_free(particles)
	_active_trails.clear()


func _as_valid_particles(node_variant: Variant) -> GPUParticles3D:
	if node_variant == null:
		return null
	if not is_instance_valid(node_variant):
		return null
	return node_variant as GPUParticles3D


func _detach_and_free(node: Node) -> void:
	var current_parent: Node = node.get_parent()
	if current_parent != null:
		current_parent.remove_child(node)
	node.queue_free()


func _process(_delta: float) -> void:
	if not _active_bursts.is_empty():
		_prune_active_bursts()
	if not _active_trails.is_empty():
		_prune_active_trails()
