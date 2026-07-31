class_name AssassinPassive
extends HeroPassive

## Consecutive basic attacks vs the same target deal bonus physical damage.
## Switching targets resets the chain. Empowers every attack after the first.

const PROC_EFFECT_SCENE_PATH := "res://scenes/effects/assassin_passive_proc_effect.tscn"

var _current_target_id: int = -1
var _consecutive_hits: int = 0


func get_status_text() -> String:
	if _consecutive_hits >= 2:
		return "Stacked x%d" % _consecutive_hits
	if _consecutive_hits == 1:
		return "Primed"
	return "Passive"


func is_effect_active() -> bool:
	return _consecutive_hits >= 2


func on_basic_attack_hit(target: Object, result: Dictionary, _attack_index: int) -> void:
	if not is_enabled():
		return
	if target == null or not is_instance_valid(target):
		_reset_chain()
		return
	if not bool(result.get(DamageService.RESULT_APPLIED, false)):
		return

	var target_id: int = target.get_instance_id()
	if target_id != _current_target_id:
		_current_target_id = target_id
		_consecutive_hits = 1
		_notify_state_changed()
		return

	_consecutive_hits += 1
	if _consecutive_hits < 2:
		_notify_state_changed()
		return

	var bonus: int = _get_bonus_damage()
	if bonus <= 0 or host == null or not is_instance_valid(host):
		_notify_state_changed()
		return

	if not target is Node:
		_notify_state_changed()
		return

	var target_node: Node = target as Node
	if not is_instance_valid(target_node):
		_reset_chain()
		return

	DamageService.apply_damage(target_node, float(bonus), host)

	# Bonus damage may have freed the target — never cast a freed node.
	if is_instance_valid(target_node):
		_spawn_proc_effect(target_node)
	else:
		_reset_chain()

	_notify_state_changed()


func on_damage_taken(_result: Dictionary) -> void:
	pass


func _format_tooltip_extra() -> String:
	return "Bonus damage: %d + %d%% AD\nResets when switching targets." % [
		ShadowAssassinStats.ASSASSIN_PASSIVE_BONUS_DAMAGE,
		int(round(ShadowAssassinStats.ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO * 100.0)),
	]


func _get_bonus_damage() -> int:
	var ad: float = 0.0
	if host != null and is_instance_valid(host) and "attack_damage" in host:
		ad = float(host.get("attack_damage"))
	return maxi(
		1,
		ShadowAssassinStats.ASSASSIN_PASSIVE_BONUS_DAMAGE
		+ int(round(ad * ShadowAssassinStats.ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO))
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
		ImpactEffects.play_unit_impact(target_3d.global_position, 1.1)
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
	effect.global_position = target_3d.global_position + Vector3(0.0, 0.7, 0.0)
