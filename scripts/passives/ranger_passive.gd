class_name RangerPassive
extends HeroPassive

## Every 3rd consecutive basic attack vs the same non-building target deals bonus
## Physical Damage equal to a percentage of that target's Maximum Health.

const PROC_EFFECT_SCENE_PATH := "res://scenes/effects/ranger_passive_proc_effect.tscn"
const MARK_EFFECT_SCENE_PATH := "res://scenes/effects/ranger_hunter_mark_effect.tscn"

var _current_target_id: int = -1
var _current_target: Variant = null
var _consecutive_hits: int = 0
var _stack_timeout_remaining: float = 0.0
var _mark_effect: Node3D = null
var _host_glow_mesh: MeshInstance3D = null
var _host_glow_material: StandardMaterial3D = null
var _host_base_emission_energy: float = 0.0
var _host_proc_flash_remaining: float = 0.0


func get_status_text() -> String:
	var needed: int = RangerStats.HUNTERS_PRECISION_HIT_COUNT
	if _consecutive_hits <= 0:
		return "Passive"
	if _consecutive_hits >= needed - 1:
		return "Ready"
	return "%d/%d" % [_consecutive_hits, needed]


func is_effect_active() -> bool:
	return _consecutive_hits >= RangerStats.HUNTERS_PRECISION_HIT_COUNT - 1


func is_next_hit_precision_proc() -> bool:
	return (
		is_enabled()
		and _consecutive_hits == RangerStats.HUNTERS_PRECISION_HIT_COUNT - 1
		and _current_target_id >= 0
	)


func get_consecutive_hits() -> int:
	return _consecutive_hits


func tick(delta: float) -> void:
	if not is_enabled():
		return

	if _host_proc_flash_remaining > 0.0:
		_host_proc_flash_remaining = maxf(_host_proc_flash_remaining - delta, 0.0)
		if _host_proc_flash_remaining <= 0.0:
			_refresh_host_glow()

	if _consecutive_hits <= 0:
		_sanitize_mark_effect()
		return

	if not _is_current_target_valid():
		_reset_chain()
		return

	_stack_timeout_remaining = maxf(_stack_timeout_remaining - delta, 0.0)
	if _stack_timeout_remaining <= 0.0:
		_reset_chain()
		return

	_sanitize_mark_effect()


func on_basic_attack_hit(target: Object, result: Dictionary, _attack_index: int) -> void:
	if not is_enabled():
		return
	if target == null or not is_instance_valid(target):
		_reset_chain()
		return
	if not VariantUtils.to_bool(result.get(DamageService.RESULT_APPLIED, false)):
		return
	if target is Building:
		_reset_chain()
		return

	var target_id: int = target.get_instance_id()
	if target_id != _current_target_id:
		_current_target_id = target_id
		_current_target = target
		_consecutive_hits = 1
		_stack_timeout_remaining = RangerStats.HUNTERS_PRECISION_STACK_TIMEOUT
		_refresh_mark_visuals(false)
		_refresh_host_glow()
		_notify_state_changed()
		return

	_consecutive_hits += 1
	_stack_timeout_remaining = RangerStats.HUNTERS_PRECISION_STACK_TIMEOUT
	if _consecutive_hits < RangerStats.HUNTERS_PRECISION_HIT_COUNT:
		_refresh_mark_visuals(false)
		_refresh_host_glow()
		_notify_state_changed()
		return

	_consecutive_hits = 0
	_stack_timeout_remaining = 0.0
	_notify_state_changed()
	_play_proc_mark_flash()
	_play_host_proc_feedback()

	if not target is Node:
		_clear_current_target_refs()
		return

	var target_node: Node = target as Node
	if not is_instance_valid(target_node):
		_reset_chain()
		return

	var bonus: int = _get_bonus_damage(target_node)
	_clear_current_target_refs()
	if bonus <= 0 or host == null or not is_instance_valid(host):
		return

	DamageService.apply_damage(
		target_node,
		float(bonus),
		host,
		{DamageService.OPT_EMPHASIZE_FLOAT: true}
	)

	if is_instance_valid(target_node):
		_spawn_proc_effect(target_node)


func on_damage_taken(_result: Dictionary) -> void:
	pass


func _on_disabled() -> void:
	_reset_chain()
	_clear_host_glow()


func _format_tooltip_extra() -> String:
	return (
		"Every %dth consecutive basic attack vs the same target deals bonus Physical Damage equal to %d%% of that target's Maximum Health.\n"
		+ "Works on Heroes, Units, and Creeps. Does not work on Buildings. Resets when switching targets or after %.0fs without a hit."
	) % [
		RangerStats.HUNTERS_PRECISION_HIT_COUNT,
		int(round(RangerStats.HUNTERS_PRECISION_MAX_HEALTH_RATIO * 100.0)),
		RangerStats.HUNTERS_PRECISION_STACK_TIMEOUT,
	]


func _get_bonus_damage(target: Node) -> int:
	var health: HealthComponent = DamageService.resolve_health_component(target)
	if health == null or health.max_health <= 0:
		return 0
	var raw: int = int(
		round(float(health.max_health) * RangerStats.HUNTERS_PRECISION_MAX_HEALTH_RATIO)
	)
	var hero_level: int = 1
	if host != null and is_instance_valid(host) and "level" in host:
		hero_level = int(host.get("level"))
	var cap: int = RangerStats.get_hunters_precision_damage_cap(hero_level)
	return clampi(raw, 1, cap)


func _reset_chain() -> void:
	if _consecutive_hits == 0 and _current_target_id < 0 and _mark_effect == null:
		_refresh_host_glow()
		return
	_clear_current_target_refs()
	_consecutive_hits = 0
	_stack_timeout_remaining = 0.0
	_clear_mark_effect()
	_refresh_host_glow()
	_notify_state_changed()


func _clear_current_target_refs() -> void:
	_current_target_id = -1
	_current_target = null


func _is_current_target_valid() -> bool:
	if _current_target_id < 0:
		return false
	if not NodeSafety.is_alive_node(_current_target):
		return false
	if not CombatTargetValidation.is_valid_combat_target(_current_target):
		return false
	if _current_target is Building:
		return false
	return int((_current_target as Object).get_instance_id()) == _current_target_id


func _refresh_mark_visuals(_is_proc: bool) -> void:
	if _consecutive_hits <= 0 or not _is_current_target_valid():
		_clear_mark_effect()
		return

	var target_3d: Node3D = _current_target as Node3D
	if target_3d == null:
		_clear_mark_effect()
		return

	if _mark_effect == null or not is_instance_valid(_mark_effect):
		_mark_effect = _spawn_mark_effect(target_3d)
	elif not NodeSafety.is_alive_node(_mark_effect):
		_mark_effect = _spawn_mark_effect(target_3d)
	else:
		if _mark_effect.has_method(&"bind_target"):
			_mark_effect.call(&"bind_target", target_3d)

	if _mark_effect == null:
		return
	if _mark_effect.has_method(&"set_mark_count"):
		_mark_effect.call(&"set_mark_count", mini(_consecutive_hits, 2))


func _spawn_mark_effect(target_3d: Node3D) -> Node3D:
	if target_3d == null or not is_instance_valid(target_3d):
		return null
	if not ResourceLoader.exists(MARK_EFFECT_SCENE_PATH):
		return null

	var effect: Node3D = load(MARK_EFFECT_SCENE_PATH).instantiate() as Node3D
	if effect == null:
		return null

	var parent: Node = target_3d.get_tree().current_scene if target_3d.get_tree() != null else null
	if parent == null:
		parent = target_3d.get_parent()
	if parent == null:
		effect.queue_free()
		return null

	parent.add_child(effect)
	if effect.has_method(&"bind_target"):
		effect.call(&"bind_target", target_3d)
	return effect


func _play_proc_mark_flash() -> void:
	if _mark_effect != null and is_instance_valid(_mark_effect):
		if _mark_effect.has_method(&"play_proc_flash_and_free"):
			_mark_effect.call(&"play_proc_flash_and_free")
		else:
			_mark_effect.queue_free()
		_mark_effect = null
	else:
		_clear_mark_effect()


func _clear_mark_effect() -> void:
	if _mark_effect != null and is_instance_valid(_mark_effect):
		if _mark_effect.has_method(&"clear_and_free"):
			_mark_effect.call(&"clear_and_free")
		else:
			_mark_effect.queue_free()
	_mark_effect = null


func _sanitize_mark_effect() -> void:
	if _mark_effect == null:
		return
	if not is_instance_valid(_mark_effect):
		_mark_effect = null
		return
	if _consecutive_hits <= 0 or not _is_current_target_valid():
		_clear_mark_effect()


func _refresh_host_glow() -> void:
	if host == null or not is_instance_valid(host):
		return
	_ensure_host_glow()
	if _host_glow_material == null:
		return

	if _host_proc_flash_remaining > 0.0:
		_host_glow_mesh.visible = true
		_host_glow_material.albedo_color = Color(1.0, 0.85, 0.3, 0.75)
		_host_glow_material.emission_energy_multiplier = 4.5
		return

	if _consecutive_hits <= 0:
		_host_glow_mesh.visible = false
		_host_glow_material.emission_energy_multiplier = _host_base_emission_energy
		return

	_host_glow_mesh.visible = true
	if _consecutive_hits == 1:
		_host_glow_material.albedo_color = Color(0.95, 0.75, 0.25, 0.35)
		_host_glow_material.emission_energy_multiplier = 1.4
	else:
		_host_glow_material.albedo_color = Color(1.0, 0.8, 0.25, 0.55)
		_host_glow_material.emission_energy_multiplier = 2.6


func _play_host_proc_feedback() -> void:
	_host_proc_flash_remaining = 0.28
	_refresh_host_glow()


func _ensure_host_glow() -> void:
	if host == null or not is_instance_valid(host):
		return
	if _host_glow_mesh != null and is_instance_valid(_host_glow_mesh):
		return

	_host_glow_mesh = MeshInstance3D.new()
	_host_glow_mesh.name = "HunterPrecisionGlow"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.05
	disc.radial_segments = 16
	_host_glow_mesh.mesh = disc
	_host_glow_material = StandardMaterial3D.new()
	_host_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_host_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_host_glow_material.albedo_color = Color(0.95, 0.75, 0.25, 0.35)
	_host_glow_material.emission_enabled = true
	_host_glow_material.emission = Color(1.0, 0.72, 0.2, 1.0)
	_host_glow_material.emission_energy_multiplier = 1.4
	_host_glow_material.no_depth_test = true
	_host_base_emission_energy = 1.4
	_host_glow_mesh.set_surface_override_material(0, _host_glow_material)
	_host_glow_mesh.position = Vector3(0.0, 0.06, 0.0)
	_host_glow_mesh.visible = false
	host.add_child(_host_glow_mesh)


func _clear_host_glow() -> void:
	_host_proc_flash_remaining = 0.0
	if _host_glow_mesh != null and is_instance_valid(_host_glow_mesh):
		_host_glow_mesh.queue_free()
	_host_glow_mesh = null
	_host_glow_material = null


func _spawn_proc_effect(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target is Node3D:
		return

	var target_3d: Node3D = target as Node3D
	if not ResourceLoader.exists(PROC_EFFECT_SCENE_PATH):
		ImpactEffects.play_unit_impact(target_3d.global_position, 1.25)
		return

	var effect: Node3D = load(PROC_EFFECT_SCENE_PATH).instantiate() as Node3D
	if effect == null:
		return

	var parent: Node = target_3d.get_parent()
	if parent == null:
		var tree: SceneTree = target_3d.get_tree()
		parent = tree.current_scene if tree != null else null
	if parent == null:
		effect.queue_free()
		return

	parent.add_child(effect)
	effect.global_position = target_3d.global_position + Vector3(0.0, 0.75, 0.0)
	ImpactEffects.play_unit_impact(target_3d.global_position, 1.55)
