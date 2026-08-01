extends Node

## Shared death visuals for units, heroes, and buildings.
## Visual-only: never changes combat, targeting, XP, or AI behavior.

## Master switches — tune from inspector / debugger.
var enabled: bool = true
var dust_enabled: bool = true
var blood_enabled: bool = true
var corpse_enabled: bool = true
var rubble_enabled: bool = true

## Corpse linger before fade (seconds).
var corpse_duration: float = 8.0
var corpse_fade_duration: float = 1.5

const MAX_ACTIVE_PARTICLES := 48
const MAX_ACTIVE_CORPSES := 40
const PARTICLE_RELEASE_PADDING := 0.15
const HERO_CORPSE_SCALE := 1.45
const UNIT_CORPSE_SCALE := 1.0
const HERO_BLOOD_SCALE := 1.35

var _played_instance_ids: Dictionary = {}
var _active_particles: Array[Dictionary] = []
var _active_corpses: Array[Dictionary] = []


func _ready() -> void:
	MatchSession.register_match_reset(&"DeathEffects", clear_all)


func clear_all() -> void:
	_played_instance_ids.clear()
	_release_active_particles_now()
	_release_active_corpses_now()
	DeathFxPool.reset_match_state()


func get_active_particle_count() -> int:
	_prune_active_particles()
	return _active_particles.size()


func get_active_corpse_count() -> int:
	_prune_active_corpses()
	return _active_corpses.size()


## Plays unit/hero death FX once per entity instance id.
func play_unit_death(unit: Node3D) -> void:
	if not enabled:
		return
	if unit == null or not is_instance_valid(unit):
		return
	if not unit.global_position.is_finite():
		return
	if not _mark_played(unit):
		return

	var world_position: Vector3 = unit.global_position
	var is_hero: bool = _is_hero(unit)
	var dust_kind: DeathFxPool.FxKind = (
		DeathFxPool.FxKind.HERO_DUST if is_hero else DeathFxPool.FxKind.UNIT_DUST
	)

	if dust_enabled:
		_spawn_burst(dust_kind, world_position + Vector3(0.0, 0.15, 0.0), 1.0)

	if blood_enabled:
		var blood_scale: float = HERO_BLOOD_SCALE if is_hero else 1.0
		_spawn_burst(
			DeathFxPool.FxKind.BLOOD,
			world_position + Vector3(0.0, 0.45, 0.0),
			blood_scale
		)

	if corpse_enabled:
		var corpse_scale: float = HERO_CORPSE_SCALE if is_hero else UNIT_CORPSE_SCALE
		_spawn_corpse(world_position, corpse_scale)


## Plays building rubble dust once per entity instance id.
func play_building_destruction(building: Node3D) -> void:
	if not enabled:
		return
	if building == null or not is_instance_valid(building):
		return
	if not building.global_position.is_finite():
		return
	if not _mark_played(building):
		return

	if not rubble_enabled:
		return

	_spawn_burst(
		DeathFxPool.FxKind.RUBBLE,
		building.global_position + Vector3(0.0, 0.35, 0.0),
		1.0
	)


func _mark_played(entity: Node) -> bool:
	var instance_id: int = entity.get_instance_id()
	if _played_instance_ids.has(instance_id):
		return false
	_played_instance_ids[instance_id] = true
	# Bound growth during long matches; instance ids are unique per process lifetime.
	if _played_instance_ids.size() > 4096:
		_played_instance_ids.clear()
		_played_instance_ids[instance_id] = true
	return true


func _is_hero(unit: Node) -> bool:
	if unit is Hero:
		return true
	return unit.is_in_group(&"heroes")


func _spawn_burst(kind: DeathFxPool.FxKind, world_position: Vector3, scale_factor: float) -> void:
	_prune_active_particles()
	while _active_particles.size() >= MAX_ACTIVE_PARTICLES:
		_force_release_oldest_particle()

	var particles: GPUParticles3D = DeathFxPool.acquire_particles(kind)
	if particles == null:
		return

	var parent: Node = _fx_parent()
	if parent == null:
		DeathFxPool.release_particles(particles, kind)
		return

	parent.add_child(particles)
	particles.global_position = world_position
	particles.scale = Vector3.ONE * maxf(0.1, scale_factor)
	particles.emitting = true
	particles.restart()

	var lifetime: float = maxf(0.2, particles.lifetime) + PARTICLE_RELEASE_PADDING
	var entry: Dictionary = {
		"node": particles,
		"kind": kind,
		"release_msec": Time.get_ticks_msec() + int(lifetime * 1000.0),
	}
	_active_particles.append(entry)


func _spawn_corpse(world_position: Vector3, scale_factor: float) -> void:
	_prune_active_corpses()
	while _active_corpses.size() >= MAX_ACTIVE_CORPSES:
		_force_release_oldest_corpse()

	var corpse: Node3D = DeathFxPool.acquire_corpse()
	if corpse == null:
		return

	var parent: Node = _fx_parent()
	if parent == null:
		DeathFxPool.release_corpse(corpse)
		return

	parent.add_child(corpse)
	corpse.global_position = Vector3(world_position.x, 0.02, world_position.z)
	corpse.rotation.y = randf_range(0.0, TAU)
	corpse.scale = Vector3.ONE * maxf(0.1, scale_factor)

	var corpse_id: int = corpse.get_instance_id()
	var linger: float = maxf(0.1, corpse_duration)
	var fade: float = maxf(0.05, corpse_fade_duration)
	var tween: Tween = create_tween()
	var entry: Dictionary = {
		"node": corpse,
		"id": corpse_id,
		"tween": tween,
	}
	_active_corpses.append(entry)

	# Use instance ids in callbacks so freed/pooled corpses cannot crash tweens.
	tween.tween_interval(linger)
	tween.tween_callback(_begin_corpse_fade_by_id.bind(corpse_id, fade))


func _begin_corpse_fade_by_id(corpse_id: int, fade_duration: float) -> void:
	var entry: Dictionary = _find_corpse_entry(corpse_id)
	if entry.is_empty():
		return

	var corpse_ref: Variant = entry.get("node")
	if not NodeSafety.is_alive_node(corpse_ref):
		_remove_corpse_entry(corpse_id)
		return

	var corpse: Node3D = corpse_ref as Node3D
	var mesh_instance := corpse.get_node_or_null("CorpseMesh") as MeshInstance3D
	var material: StandardMaterial3D = null
	if mesh_instance != null:
		material = mesh_instance.material_override as StandardMaterial3D

	var tween: Tween = create_tween()
	entry["tween"] = tween
	tween.set_parallel(true)
	tween.tween_property(corpse, "scale", corpse.scale * 0.85, fade_duration)
	if material != null:
		tween.tween_property(material, "albedo_color:a", 0.0, fade_duration)
	tween.chain().tween_callback(_finish_corpse_by_id.bind(corpse_id))


func _finish_corpse_by_id(corpse_id: int) -> void:
	var entry: Dictionary = _find_corpse_entry(corpse_id)
	_remove_corpse_entry(corpse_id)
	if entry.is_empty():
		return

	var corpse_ref: Variant = entry.get("node")
	if not NodeSafety.is_alive_node(corpse_ref):
		return
	DeathFxPool.release_corpse(corpse_ref as Node3D)


func _find_corpse_entry(corpse_id: int) -> Dictionary:
	for entry: Dictionary in _active_corpses:
		if int(entry.get("id", 0)) == corpse_id:
			return entry
	return {}


func _remove_corpse_entry(corpse_id: int) -> void:
	for i: int in range(_active_corpses.size() - 1, -1, -1):
		if int(_active_corpses[i].get("id", 0)) == corpse_id:
			_kill_entry_tween(_active_corpses[i])
			_active_corpses.remove_at(i)
			return


func _kill_entry_tween(entry: Dictionary) -> void:
	var tween_ref: Variant = entry.get("tween")
	if tween_ref == null or not is_instance_valid(tween_ref):
		return
	var tween: Tween = tween_ref as Tween
	if tween.is_valid():
		tween.kill()


func _fx_parent() -> Node:
	# Parent under this autoload so match-scene teardown cannot free live FX
	# while DeathEffects tweens are still running.
	return self


func _prune_active_particles() -> void:
	var now_msec: int = Time.get_ticks_msec()
	var write: int = 0
	for entry: Dictionary in _active_particles:
		var particles_ref: Variant = entry.get("node")
		if not NodeSafety.is_alive_node(particles_ref):
			continue
		var particles: GPUParticles3D = particles_ref as GPUParticles3D
		if now_msec >= int(entry.get("release_msec", 0)):
			DeathFxPool.release_particles(particles, entry.get("kind") as DeathFxPool.FxKind)
			continue
		_active_particles[write] = entry
		write += 1
	_active_particles.resize(write)


func _prune_active_corpses() -> void:
	var write: int = 0
	for entry: Dictionary in _active_corpses:
		var corpse_ref: Variant = entry.get("node")
		if not NodeSafety.is_alive_node(corpse_ref):
			_kill_entry_tween(entry)
			continue
		_active_corpses[write] = entry
		write += 1
	_active_corpses.resize(write)


func _force_release_oldest_particle() -> void:
	if _active_particles.is_empty():
		return
	var entry: Dictionary = _active_particles.pop_front()
	var particles_ref: Variant = entry.get("node")
	if NodeSafety.is_alive_node(particles_ref):
		DeathFxPool.release_particles(
			particles_ref as GPUParticles3D,
			entry.get("kind") as DeathFxPool.FxKind
		)


func _force_release_oldest_corpse() -> void:
	if _active_corpses.is_empty():
		return
	var entry: Dictionary = _active_corpses.pop_front()
	_kill_entry_tween(entry)
	var corpse_ref: Variant = entry.get("node")
	if NodeSafety.is_alive_node(corpse_ref):
		DeathFxPool.release_corpse(corpse_ref as Node3D)


func _release_active_particles_now() -> void:
	# Free directly — clear_all also resets the pool, and release-to-pool can fail
	# if called while the scene tree is still setting up children (match prepare).
	for entry: Dictionary in _active_particles:
		var particles_ref: Variant = entry.get("node")
		if NodeSafety.is_alive_node(particles_ref):
			_detach_and_free(particles_ref as Node)
	_active_particles.clear()


func _release_active_corpses_now() -> void:
	for entry: Dictionary in _active_corpses:
		_kill_entry_tween(entry)
		var corpse_ref: Variant = entry.get("node")
		if NodeSafety.is_alive_node(corpse_ref):
			_detach_and_free(corpse_ref as Node)
	_active_corpses.clear()


func _detach_and_free(node: Node) -> void:
	var current_parent: Node = node.get_parent()
	if current_parent != null:
		current_parent.remove_child(node)
	node.queue_free()


func _process(_delta: float) -> void:
	if _active_particles.is_empty():
		return
	_prune_active_particles()
