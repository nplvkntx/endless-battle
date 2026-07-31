class_name LightCavalry
extends MilitaryUnit

## Fast light mounted melee cavalry.

const UNIT_ID: StringName = &"light_cavalry"

var _base_attack_damage: int = -1
var _base_armor: int = -1


func _init() -> void:
	attack_damage = UnitStats.LIGHT_CAVALRY_ATTACK_DAMAGE
	attack_range = UnitStats.LIGHT_CAVALRY_ATTACK_RANGE
	attack_cooldown = UnitStats.LIGHT_CAVALRY_ATTACK_COOLDOWN
	armor = UnitStats.LIGHT_CAVALRY_ARMOR


func _ready() -> void:
	super._ready()
	_cache_base_stats()
	if CombatTargetValidation.is_enemy_faction(self):
		if not UpgradeManager.enemy_upgrade_applied.is_connected(_on_stable_upgrade_applied):
			UpgradeManager.enemy_upgrade_applied.connect(_on_stable_upgrade_applied)
	else:
		if not UpgradeManager.upgrade_applied.is_connected(_on_stable_upgrade_applied):
			UpgradeManager.upgrade_applied.connect(_on_stable_upgrade_applied)
	call_deferred("_try_apply_stable_upgrades")


func _exit_tree() -> void:
	super._exit_tree()
	if UpgradeManager.upgrade_applied.is_connected(_on_stable_upgrade_applied):
		UpgradeManager.upgrade_applied.disconnect(_on_stable_upgrade_applied)
	if UpgradeManager.enemy_upgrade_applied.is_connected(_on_stable_upgrade_applied):
		UpgradeManager.enemy_upgrade_applied.disconnect(_on_stable_upgrade_applied)


func apply_stable_upgrades() -> void:
	_cache_base_stats()
	var attack_level: int = _get_stable_upgrade_level(
		UpgradeManager.get_cavalry_attack_upgrade_id(UNIT_ID)
	)
	var defense_level: int = _get_stable_upgrade_level(
		UpgradeManager.get_cavalry_defense_upgrade_id(UNIT_ID)
	)
	attack_damage = _base_attack_damage + attack_level * UpgradeStats.CAVALRY_ATTACK_DAMAGE_PER_LEVEL
	armor = _base_armor + defense_level * UpgradeStats.CAVALRY_DEFENSE_ARMOR_PER_LEVEL


func _get_stable_upgrade_level(upgrade_id: StringName) -> int:
	if CombatTargetValidation.is_enemy_faction(self):
		return UpgradeManager.get_enemy_level(upgrade_id)

	return UpgradeManager.get_level(upgrade_id)


func _cache_base_stats() -> void:
	if _base_attack_damage < 0:
		_base_attack_damage = attack_damage
	if _base_armor < 0:
		_base_armor = armor


func _try_apply_stable_upgrades() -> void:
	if not NodeSafety.is_alive_node(self):
		return

	if CombatTargetValidation.is_enemy_faction(self):
		UpgradeManager.apply_enemy_upgrades_to_unit(self)
	else:
		UpgradeManager.apply_player_upgrades_to_unit(self)


func _on_stable_upgrade_applied(upgrade_id: StringName) -> void:
	if upgrade_id != UpgradeManager.get_cavalry_attack_upgrade_id(UNIT_ID):
		if upgrade_id != UpgradeManager.get_cavalry_defense_upgrade_id(UNIT_ID):
			return

	_try_apply_stable_upgrades()
