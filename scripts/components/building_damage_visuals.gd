class_name BuildingDamageVisuals
extends Node

## Shared building HP damage states: smoke / fire attached to the building.
## Driven only by HealthComponent signals — no gameplay side effects.

enum DamageLevel {
	NONE = 0,
	MINOR_SMOKE = 1,
	NOTICEABLE_SMOKE = 2,
	SMOKE_AND_FIRE = 3,
	HEAVY_FIRE = 4,
}

const HOST_NAME := &"BuildingDamageFxHost"
const COMPONENT_NAME := &"BuildingDamageVisuals"

## Smoke amount_ratio by damage level (NONE unused).
const SMOKE_AMOUNT_BY_LEVEL: Array[float] = [0.0, 0.35, 0.7, 0.75, 0.95]
## Fire amount_ratio by damage level.
const FIRE_AMOUNT_BY_LEVEL: Array[float] = [0.0, 0.0, 0.0, 0.55, 1.0]

var _building: Building
var _health: HealthComponent
var _profile: BuildingDamageVisualProfile
var _host: Node3D
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _current_level: int = DamageLevel.NONE
var _smoke_tween: Tween
var _fire_tween: Tween
var _connected: bool = false
var _cleaned: bool = false


static func ensure_on_building(
	building: Building,
	profile: BuildingDamageVisualProfile = null
) -> BuildingDamageVisuals:
	if building == null or not is_instance_valid(building):
		return null

	var existing := building.get_node_or_null(NodePath(String(COMPONENT_NAME)))
	if existing is BuildingDamageVisuals:
		var visuals := existing as BuildingDamageVisuals
		if profile != null:
			visuals.set_profile(profile)
		return visuals

	var component := BuildingDamageVisuals.new()
	component.name = COMPONENT_NAME
	building.add_child(component)
	component.setup(building, profile)
	return component


func setup(building: Building, profile: BuildingDamageVisualProfile = null) -> void:
	_cleaned = false
	_building = building
	_profile = profile if profile != null else BuildingDamageVisualProfile.default_profile()
	_health = building.get_node_or_null("HealthComponent") as HealthComponent
	_ensure_host()
	_connect_health()
	_refresh_from_health(true)


func set_profile(profile: BuildingDamageVisualProfile) -> void:
	_profile = profile if profile != null else BuildingDamageVisualProfile.default_profile()
	_refresh_from_health(true)


func get_current_level() -> int:
	return _current_level


func has_smoke_emitter() -> bool:
	return _smoke != null and is_instance_valid(_smoke)


func has_fire_emitter() -> bool:
	return _fire != null and is_instance_valid(_fire)


func force_refresh() -> void:
	_refresh_from_health(true)


func cleanup() -> void:
	if _cleaned:
		return
	_cleaned = true
	_disconnect_health()
	_kill_tweens()
	_release_smoke(true)
	_release_fire(true)
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null
	_current_level = DamageLevel.NONE


func _exit_tree() -> void:
	cleanup()


func _connect_health() -> void:
	if _connected or _health == null:
		return

	if not _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.connect(_on_health_changed)
	if not _health.health_depleted.is_connected(_on_health_depleted):
		_health.health_depleted.connect(_on_health_depleted)
	_connected = true


func _disconnect_health() -> void:
	if not _connected or _health == null or not is_instance_valid(_health):
		_connected = false
		return

	if _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	if _health.health_depleted.is_connected(_on_health_depleted):
		_health.health_depleted.disconnect(_on_health_depleted)
	_connected = false


func _on_health_changed(_current: int, _maximum: int) -> void:
	_refresh_from_health(false)


func _on_health_depleted() -> void:
	# Building is about to free; release pooled FX immediately.
	cleanup()


func _refresh_from_health(force: bool) -> void:
	if _building == null or not is_instance_valid(_building):
		return
	if _health == null or not is_instance_valid(_health):
		_apply_level(DamageLevel.NONE, force)
		return

	var maximum: int = maxi(_health.max_health, 1)
	var ratio: float = float(_health.current_health) / float(maximum)
	var next_level: int = level_for_ratio(ratio, _profile)
	_apply_level(next_level, force)


static func level_for_ratio(ratio: float, profile: BuildingDamageVisualProfile) -> int:
	var safe_profile: BuildingDamageVisualProfile = (
		profile if profile != null else BuildingDamageVisualProfile.default_profile()
	)
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if clamped <= safe_profile.heavy_fire_ratio:
		return DamageLevel.HEAVY_FIRE
	if clamped <= safe_profile.smoke_and_fire_ratio:
		return DamageLevel.SMOKE_AND_FIRE
	if clamped <= safe_profile.noticeable_smoke_ratio:
		return DamageLevel.NOTICEABLE_SMOKE
	if clamped <= safe_profile.minor_smoke_ratio:
		return DamageLevel.MINOR_SMOKE
	return DamageLevel.NONE


func _apply_level(next_level: int, force: bool) -> void:
	var safe_level: int = clampi(next_level, DamageLevel.NONE, DamageLevel.HEAVY_FIRE)
	if not force and safe_level == _current_level:
		return

	var previous_level: int = _current_level
	_current_level = safe_level
	_ensure_host()
	_update_host_transform()

	var wants_smoke: bool = safe_level >= DamageLevel.MINOR_SMOKE
	var wants_fire: bool = safe_level >= DamageLevel.SMOKE_AND_FIRE
	var repairing: bool = safe_level < previous_level
	var fade_seconds: float = maxf(_profile.repair_fade_seconds, 0.05) if repairing else 0.2

	if wants_smoke:
		_ensure_smoke()
		_tween_emitter_amount(
			_smoke,
			_smoke_amount_for_level(safe_level),
			fade_seconds,
			true
		)
	else:
		_fade_and_release_smoke(fade_seconds if repairing else 0.15)

	if wants_fire:
		_ensure_fire()
		_tween_emitter_amount(
			_fire,
			_fire_amount_for_level(safe_level),
			fade_seconds,
			false
		)
	else:
		_fade_and_release_fire(fade_seconds if repairing else 0.15)


func _smoke_amount_for_level(level: int) -> float:
	var index: int = clampi(level, 0, SMOKE_AMOUNT_BY_LEVEL.size() - 1)
	return SMOKE_AMOUNT_BY_LEVEL[index] * maxf(_profile.smoke_intensity_scale, 0.01)


func _fire_amount_for_level(level: int) -> float:
	var index: int = clampi(level, 0, FIRE_AMOUNT_BY_LEVEL.size() - 1)
	return FIRE_AMOUNT_BY_LEVEL[index] * maxf(_profile.fire_intensity_scale, 0.01)


func _ensure_host() -> void:
	if _building == null or not is_instance_valid(_building):
		return

	if _host != null and is_instance_valid(_host):
		return

	var existing: Node = _building.get_node_or_null(NodePath(String(HOST_NAME)))
	if existing is Node3D:
		_host = existing as Node3D
		return

	_host = Node3D.new()
	_host.name = HOST_NAME
	_building.add_child(_host)


func _update_host_transform() -> void:
	if _host == null or not is_instance_valid(_host) or _building == null:
		return

	var height: float = _estimate_fx_height()
	var half_extents: Vector2 = Vector2(1.0, 1.0)
	if _building.has_method(&"_get_footprint_half_extents"):
		half_extents = _building.call(&"_get_footprint_half_extents") as Vector2

	_host.position = Vector3(
		_profile.local_offset.x,
		height + _profile.height_padding + _profile.local_offset.y,
		_profile.local_offset.z
	)

	var spread: float = maxf(0.35, (half_extents.x + half_extents.y) * 0.22)
	spread *= maxf(_profile.footprint_spread_scale, 0.1)
	_apply_emitter_spread(_smoke, spread)
	_apply_emitter_spread(_fire, spread * 0.75)


func _estimate_fx_height() -> float:
	if _building == null:
		return 1.0
	if _building.has_method(&"_collect_mesh_top_local_y"):
		return float(_building.call(&"_collect_mesh_top_local_y", _building, 0.75))
	return 1.0


func _apply_emitter_spread(particles: GPUParticles3D, radius: float) -> void:
	if particles == null or not is_instance_valid(particles):
		return
	var process := particles.process_material as ParticleProcessMaterial
	if process == null:
		return
	process.emission_sphere_radius = radius


func _ensure_smoke() -> void:
	if _smoke != null and is_instance_valid(_smoke):
		return
	if _host == null:
		return
	# Prevent duplicates if a previous host still has children.
	var existing: Node = _host.get_node_or_null("PooledSmoke")
	if existing is GPUParticles3D:
		_smoke = existing as GPUParticles3D
		return
	_smoke = BuildingDamageFxPool.acquire(BuildingDamageFxPool.FxKind.SMOKE, _host)


func _ensure_fire() -> void:
	if _fire != null and is_instance_valid(_fire):
		return
	if _host == null:
		return
	var existing: Node = _host.get_node_or_null("PooledFire")
	if existing is GPUParticles3D:
		_fire = existing as GPUParticles3D
		return
	_fire = BuildingDamageFxPool.acquire(BuildingDamageFxPool.FxKind.FIRE, _host)


func _tween_emitter_amount(
	particles: GPUParticles3D,
	target_amount: float,
	duration: float,
	is_smoke: bool
) -> void:
	if particles == null or not is_instance_valid(particles):
		return

	var clamped_target: float = clampf(target_amount, 0.0, 1.0)
	if is_smoke:
		if _smoke_tween != null and _smoke_tween.is_valid():
			_smoke_tween.kill()
	else:
		if _fire_tween != null and _fire_tween.is_valid():
			_fire_tween.kill()

	particles.emitting = clamped_target > 0.001
	particles.visible = true

	if duration <= 0.001:
		particles.amount_ratio = clamped_target
		return

	var tween: Tween = create_tween()
	tween.tween_property(particles, "amount_ratio", clamped_target, duration).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	if is_smoke:
		_smoke_tween = tween
	else:
		_fire_tween = tween


func _fade_and_release_smoke(duration: float) -> void:
	if _smoke == null or not is_instance_valid(_smoke):
		_smoke = null
		return

	if _smoke_tween != null and _smoke_tween.is_valid():
		_smoke_tween.kill()

	if duration <= 0.001 or _smoke.amount_ratio <= 0.001:
		_release_smoke(true)
		return

	_smoke_tween = create_tween()
	_smoke_tween.tween_property(_smoke, "amount_ratio", 0.0, duration).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	_smoke_tween.tween_callback(_release_smoke.bind(true))


func _fade_and_release_fire(duration: float) -> void:
	if _fire == null or not is_instance_valid(_fire):
		_fire = null
		return

	if _fire_tween != null and _fire_tween.is_valid():
		_fire_tween.kill()

	if duration <= 0.001 or _fire.amount_ratio <= 0.001:
		_release_fire(true)
		return

	_fire_tween = create_tween()
	_fire_tween.tween_property(_fire, "amount_ratio", 0.0, duration).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	_fire_tween.tween_callback(_release_fire.bind(true))


func _release_smoke(_from_callback: bool = false) -> void:
	if _smoke_tween != null and _smoke_tween.is_valid():
		_smoke_tween.kill()
	_smoke_tween = null
	if _smoke != null and is_instance_valid(_smoke):
		BuildingDamageFxPool.release(_smoke, BuildingDamageFxPool.FxKind.SMOKE)
	_smoke = null


func _release_fire(_from_callback: bool = false) -> void:
	if _fire_tween != null and _fire_tween.is_valid():
		_fire_tween.kill()
	_fire_tween = null
	if _fire != null and is_instance_valid(_fire):
		BuildingDamageFxPool.release(_fire, BuildingDamageFxPool.FxKind.FIRE)
	_fire = null


func _kill_tweens() -> void:
	if _smoke_tween != null and _smoke_tween.is_valid():
		_smoke_tween.kill()
	if _fire_tween != null and _fire_tween.is_valid():
		_fire_tween.kill()
	_smoke_tween = null
	_fire_tween = null
