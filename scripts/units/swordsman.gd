class_name Swordsman
extends MilitaryUnit

## Melee infantry with blacksmith upgrades and attack animation on strike.

var _base_attack_damage: int = -1


func _init() -> void:
	attack_damage = 10
	attack_range = 2.0
	attack_cooldown = 1.0
	armor = 0


func _ready() -> void:
	super._ready()
	_cache_base_stats()
	if CombatTargetValidation.is_enemy_faction(self):
		if not UpgradeManager.enemy_upgrade_applied.is_connected(_on_blacksmith_upgrade_applied):
			UpgradeManager.enemy_upgrade_applied.connect(_on_blacksmith_upgrade_applied)
	else:
		if not UpgradeManager.upgrade_applied.is_connected(_on_blacksmith_upgrade_applied):
			UpgradeManager.upgrade_applied.connect(_on_blacksmith_upgrade_applied)
	call_deferred("_try_apply_blacksmith_upgrades")


func _exit_tree() -> void:
	super._exit_tree()
	if UpgradeManager.upgrade_applied.is_connected(_on_blacksmith_upgrade_applied):
		UpgradeManager.upgrade_applied.disconnect(_on_blacksmith_upgrade_applied)
	if UpgradeManager.enemy_upgrade_applied.is_connected(_on_blacksmith_upgrade_applied):
		UpgradeManager.enemy_upgrade_applied.disconnect(_on_blacksmith_upgrade_applied)


func _configure_visual_animator(animator: UnitVisualAnimator) -> void:
	animator.set_clip_preferences({
		UnitVisualAnimator.STATE_IDLE: [&"Idle", &"Idle_Weapon"],
		UnitVisualAnimator.STATE_MOVE: [&"Walk", &"Run", &"Run_Weapon"],
		UnitVisualAnimator.STATE_ATTACK: [&"Sword_Attack", &"Sword_Attack2", &"Punch"],
	})


func _deliver_attack() -> bool:
	if not super._deliver_attack():
		return false

	play_visual_attack_animation()
	return true


func apply_blacksmith_upgrades() -> void:
	_cache_base_stats()
	var attack_level: int = _get_blacksmith_upgrade_level(UpgradeManager.UPGRADE_SWORDSMAN_ATTACK)
	var armor_level: int = _get_blacksmith_upgrade_level(UpgradeManager.UPGRADE_SWORDSMAN_ARMOR)
	attack_damage = _base_attack_damage + attack_level * 2
	armor = armor_level


func _get_blacksmith_upgrade_level(upgrade_id: StringName) -> int:
	if CombatTargetValidation.is_enemy_faction(self):
		return UpgradeManager.get_enemy_level(upgrade_id)

	return UpgradeManager.get_level(upgrade_id)


func _cache_base_stats() -> void:
	if _base_attack_damage < 0:
		_base_attack_damage = attack_damage


func _try_apply_blacksmith_upgrades() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if CombatTargetValidation.is_enemy_faction(self):
		UpgradeManager.apply_enemy_upgrades_to_unit(self)
	else:
		UpgradeManager.apply_player_upgrades_to_unit(self)


func _on_blacksmith_upgrade_applied(_upgrade_id: StringName) -> void:
	_try_apply_blacksmith_upgrades()
