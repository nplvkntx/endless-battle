class_name RangerPassive
extends HeroPassive

## Every 3rd consecutive basic attack vs the same non-building target deals bonus
## Physical Damage equal to a percentage of that target's Maximum Health.

const PROC_EFFECT_SCENE_PATH := "res://scenes/effects/ranger_passive_proc_effect.tscn"

var _current_target_id: int = -1
var _consecutive_hits: int = 0


func get_status_text() -> String:
	var needed: int = RangerStats.HUNTERS_PRECISION_HIT_COUNT
	if _consecutive_hits <= 0:
		return "Passive"
	if _consecutive_hits >= needed - 1:
		return "Ready"
	return "%d/%d" % [_consecutive_hits, needed]


func is_effect_active() -> bool:
	return _consecutive_hits >= RangerStats.HUNTERS_PRECISION_HIT_COUNT - 1


func on_basic_attack_hit(target: Object, result: Dictionary, _attack_index: int) -> void:
	if not is_enabled():
		return
	if target == null or not is_instance_valid(target):
		_reset_chain()
		return
	if not bool(result.get(DamageService.RESULT_APPLIED, false)):
		return
	if target is Building:
		_reset_chain()
		return

	var target_id: int = target.get_instance_id()
	if target_id != _current_target_id:
		_current_target_id = target_id
		_consecutive_hits = 1
		_notify_state_changed()
		return

	_consecutive_hits += 1
	if _consecutive_hits < RangerStats.HUNTERS_PRECISION_HIT_COUNT:
		_notify_state_changed()
		return

	_consecutive_hits = 0
	_notify_state_changed()

	if not target is Node:
		return

	var target_node: Node = target as Node
	if not is_instance_valid(target_node):
		_reset_chain()
		return

	var bonus: int = _get_bonus_damage(target_node)
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
	else:
		_reset_chain()


func on_damage_taken(_result: Dictionary) -> void:
	pass


func _format_tooltip_extra() -> String:
	return (
		"Every %dth consecutive basic attack vs the same target deals bonus Physical Damage equal to %d%% of that target's Maximum Health.\n"
		+ "Works on Heroes, Units, and Creeps. Does not work on Buildings. Resets when switching targets."
	) % [
		RangerStats.HUNTERS_PRECISION_HIT_COUNT,
		int(round(RangerStats.HUNTERS_PRECISION_MAX_HEALTH_RATIO * 100.0)),
	]


func _get_bonus_damage(target: Node) -> int:
	var health: HealthComponent = DamageService.resolve_health_component(target)
	if health == null or health.max_health <= 0:
		return 0
	return maxi(
		1,
		int(round(float(health.max_health) * RangerStats.HUNTERS_PRECISION_MAX_HEALTH_RATIO))
	)


func _reset_chain() -> void:
	if _consecutive_hits == 0 and _current_target_id < 0:
		return
	_current_target_id = -1
	_consecutive_hits = 0
	_notify_state_changed()


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
	ImpactEffects.play_unit_impact(target_3d.global_position, 1.35)
