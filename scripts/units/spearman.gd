class_name Spearman
extends MilitaryUnit

## Tier 1 melee infantry.
var _art_guarding: bool = false


func get_visual_loop_state() -> UnitVisualAnimator.LoopState:
	if _visual_animator != null and _art_guarding != _is_holding_position:
		_art_guarding = _is_holding_position
		_visual_animator.set_clip_preferences({UnitVisualAnimator.STATE_IDLE: [&"Guard" if _art_guarding else &"Idle"]})
	return super.get_visual_loop_state()


func _configure_visual_animator(animator: UnitVisualAnimator) -> void:
	animator.set_clip_preferences({
		UnitVisualAnimator.STATE_IDLE: [&"Idle"],
		UnitVisualAnimator.STATE_MOVE: [&"Walk"],
		UnitVisualAnimator.STATE_ATTACK: [&"Attack"],
	})


func _detect_visual_facing_yaw_offset() -> float:
	return 0.0


func _deliver_attack() -> bool:
	if not super._deliver_attack():
		return false
	play_visual_attack_animation()
	return true


func apply_team_visuals() -> void:
	super.apply_team_visuals()
	var art: SpearmanArtVisuals = get_node_or_null("SpearmanArtVisuals") as SpearmanArtVisuals
	if art != null:
		art.apply_team(team_id)


func _init() -> void:
	attack_damage = UnitStats.SPEARMAN_ATTACK_DAMAGE
	attack_range = UnitStats.SPEARMAN_ATTACK_RANGE
	attack_cooldown = UnitStats.SPEARMAN_ATTACK_COOLDOWN
	armor = UnitStats.SPEARMAN_ARMOR
	damage_type = DamageService.DamageType.PIERCE
	armor_type = DamageService.ArmorType.MEDIUM


func modify_outgoing_damage(amount: float, target: Object, _damage_type: int) -> float:
	if _is_cavalry_target(target):
		return amount * UnitStats.SPEARMAN_CAVALRY_DAMAGE_MULTIPLIER
	return amount


func _is_cavalry_target(target: Object) -> bool:
	if target == null:
		return false
	return target is LightCavalry or target is CavalryArcher or target is HeavyCavalry
