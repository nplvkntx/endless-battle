class_name Archer
extends MilitaryUnit

## Ranged archer that stops at attack range and fires arrow projectiles.

var _base_attack_damage: int = -1
var _base_attack_range: float = -1.0
var _base_attack_cooldown: float = -1.0

const ARROW_SCENE: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
const ARROW_SPAWN_HEIGHT := 0.5


func _init() -> void:
	attack_damage = UnitStats.ARCHER_ATTACK_DAMAGE
	attack_range = UnitStats.ARCHER_ATTACK_RANGE
	attack_cooldown = UnitStats.ARCHER_ATTACK_COOLDOWN
	armor = UnitStats.ARCHER_ARMOR
	damage_type = DamageService.DamageType.PIERCE
	armor_type = DamageService.ArmorType.LIGHT


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
		UnitVisualAnimator.STATE_MOVE: [&"Walk", &"Run", &"Run_Holding"],
		UnitVisualAnimator.STATE_ATTACK: [&"Bow_Shoot", &"Bow_Draw"],
	})


func _deliver_attack() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		return false

	play_visual_attack_animation()
	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	get_tree().current_scene.add_child(arrow)
	var spawn_position: Vector3 = global_position + Vector3(0.0, ARROW_SPAWN_HEIGHT, 0.0)
	arrow.launch(_attack_target, float(attack_damage), spawn_position, self)
	return true


func apply_blacksmith_upgrades() -> void:
	_cache_base_stats()
	var attack_level: int = _get_blacksmith_upgrade_level(UpgradeManager.UPGRADE_ARCHER_ATTACK)
	var speed_level: int = _get_blacksmith_upgrade_level(UpgradeManager.UPGRADE_ARCHER_ATTACK_SPEED)
	var range_level: int = _get_blacksmith_upgrade_level(UpgradeManager.UPGRADE_ARCHER_RANGE)
	attack_damage = _base_attack_damage + attack_level * UnitStats.ARCHER_ATTACK_DAMAGE_PER_UPGRADE_LEVEL
	var bonus_attack_speed: float = (
		UnitStats.ARCHER_ATTACK_SPEED_BONUS_PER_LEVEL * float(speed_level)
	)
	attack_cooldown = UnitStats.get_final_attack_cooldown(_base_attack_cooldown, bonus_attack_speed)
	attack_range = (
		_base_attack_range + float(range_level) * UnitStats.ARCHER_ATTACK_RANGE_PER_UPGRADE_LEVEL
	)


func _get_blacksmith_upgrade_level(upgrade_id: StringName) -> int:
	if CombatTargetValidation.is_enemy_faction(self):
		return UpgradeManager.get_enemy_level(upgrade_id)

	return UpgradeManager.get_level(upgrade_id)


func _cache_base_stats() -> void:
	if _base_attack_damage < 0:
		_base_attack_damage = attack_damage
	if _base_attack_range < 0.0:
		_base_attack_range = attack_range
	if _base_attack_cooldown < 0.0:
		_base_attack_cooldown = attack_cooldown


func _try_apply_blacksmith_upgrades() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if CombatTargetValidation.is_enemy_faction(self):
		UpgradeManager.apply_enemy_upgrades_to_unit(self)
	else:
		UpgradeManager.apply_player_upgrades_to_unit(self)


func _on_blacksmith_upgrade_applied(_upgrade_id: StringName) -> void:
	_try_apply_blacksmith_upgrades()
