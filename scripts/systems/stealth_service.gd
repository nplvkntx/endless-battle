class_name StealthService
extends RefCounted

## Combat stealth helpers. Stealthed units are skipped by auto-targeting but remain
## valid for committed attacks, player orders, and area damage.


static func is_combat_hidden(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Unit:
		return (target as Unit).is_combat_hidden()
	if target.has_method(&"is_combat_hidden"):
		return bool(target.call(&"is_combat_hidden"))
	return false


static func can_auto_target(attacker: Variant, target: Variant) -> bool:
	if not CombatTargetValidation.is_valid_combat_target(target):
		return false
	if not is_combat_hidden(target):
		return true
	# Already committed / manually ordered attacks may keep the target; auto-acquire cannot.
	if attacker != null and is_instance_valid(attacker) and attacker.has_method(&"get_attack_target"):
		var current: Variant = attacker.call(&"get_attack_target")
		if current == target:
			return true
	return false


static func set_combat_hidden(unit: Unit, hidden: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.set_combat_hidden(hidden)
