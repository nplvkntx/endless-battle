class_name DamageService
extends RefCounted

## Single combat damage entry point for units, heroes, buildings, towers, cannons,
## creeps, projectiles, splash, and hero abilities.
##
## Current callers preserve existing mitigation quirks. Options below are ready for
## physical / magic / siege / true damage, crits, lifesteal, reduction, and buffs.

enum DamageType {
	PHYSICAL = 0,
	MAGIC = 1,
	SIEGE = 2,
	TRUE = 3,
}

const OPT_DAMAGE_TYPE := &"damage_type"
const OPT_IGNORE_HOSTILITY := &"ignore_hostility"
const OPT_BYPASS_ARMOR := &"bypass_armor"
const OPT_CAN_CRIT := &"can_crit"
const OPT_CRIT_CHANCE := &"crit_chance"
const OPT_CRIT_MULTIPLIER := &"crit_multiplier"
const OPT_CAN_LIFESTEAL := &"can_lifesteal"
const OPT_LIFESTEAL_PERCENT := &"lifesteal_percent"
const OPT_DAMAGE_REDUCTION := &"damage_reduction"
const OPT_SHOW_FLOAT := &"show_floating_number"
const OPT_EMPHASIZE_FLOAT := &"emphasize_float"

const RESULT_APPLIED := &"applied"
const RESULT_BLOCKED := &"blocked"
const RESULT_DAMAGE_DEALT := &"damage_dealt"
const RESULT_ATTACKER := &"attacker"
const RESULT_WAS_CRITICAL := &"was_critical"
const RESULT_DAMAGE_TYPE := &"damage_type"
const RESULT_LIFESTEAL_HEALED := &"lifesteal_healed"


static func apply(
	target: Variant,
	amount: float,
	attacker = null,
	options: Dictionary = {}
) -> Dictionary:
	var result := _empty_result(options)
	if target == null or not is_instance_valid(target) or not target is Object:
		return result

	var target_object: Object = target as Object
	var ignore_hostility: bool = bool(options.get(OPT_IGNORE_HOSTILITY, false))
	var safe_attacker: Node = CombatTargetValidation.sanitize_damage_attacker(attacker)

	if not ignore_hostility:
		if not CombatTargetValidation.is_valid_combat_target(target_object):
			return result
		if safe_attacker != null and not CombatTargetValidation.are_hostile(safe_attacker, target_object):
			return result
	elif not _can_receive_pipeline_damage(target_object):
		return result

	result[RESULT_ATTACKER] = safe_attacker

	var health: HealthComponent = resolve_health_component(target_object)
	if health == null or health.current_health <= 0:
		return result

	if _is_damage_immune(target_object):
		result[RESULT_BLOCKED] = true
		return result

	var damage_type: int = int(options.get(OPT_DAMAGE_TYPE, DamageType.PHYSICAL))
	result[RESULT_DAMAGE_TYPE] = damage_type

	var working_amount: float = amount
	working_amount = _apply_attacker_buffs(safe_attacker, target_object, working_amount, damage_type)
	working_amount = _apply_target_buffs(target_object, safe_attacker, working_amount, damage_type)

	var crit_result: Dictionary = _roll_critical(working_amount, options)
	working_amount = float(crit_result.get("amount", working_amount))
	var was_critical: bool = bool(crit_result.get("was_critical", false))
	result[RESULT_WAS_CRITICAL] = was_critical

	working_amount = _apply_damage_reduction(target_object, working_amount, damage_type, options)

	var damage_dealt: int = _resolve_mitigated_damage(
		target_object,
		working_amount,
		damage_type,
		options
	)

	CombatKillTracker.record_attacker(target_object, safe_attacker)
	health.take_damage(damage_dealt)

	_maybe_spawn_floating_number(target_object, damage_dealt, was_critical, options)
	result[RESULT_LIFESTEAL_HEALED] = _apply_lifesteal(
		safe_attacker,
		damage_dealt,
		options
	)

	result[RESULT_APPLIED] = true
	result[RESULT_DAMAGE_DEALT] = damage_dealt

	if target_object.has_method(&"_on_combat_damage_received"):
		target_object.call(&"_on_combat_damage_received", result)

	return result


static func apply_damage(
	target: Variant,
	amount: float,
	attacker = null,
	options: Dictionary = {}
) -> bool:
	return bool(apply(target, amount, attacker, options).get(RESULT_APPLIED, false))


static func resolve_health_component(target: Object) -> HealthComponent:
	if target == null or not is_instance_valid(target):
		return null

	if target is Node:
		var from_node: HealthComponent = (target as Node).get_node_or_null(
			"HealthComponent"
		) as HealthComponent
		if from_node != null:
			return from_node

	var stored: Variant = target.get("_health_component")
	if stored is HealthComponent:
		return stored as HealthComponent

	return null


static func compute_armored_damage(amount: float, armor: int) -> int:
	return maxi(1, int(amount) - armor)


static func _empty_result(options: Dictionary) -> Dictionary:
	return {
		RESULT_APPLIED: false,
		RESULT_BLOCKED: false,
		RESULT_DAMAGE_DEALT: 0,
		RESULT_ATTACKER: null,
		RESULT_WAS_CRITICAL: false,
		RESULT_DAMAGE_TYPE: int(options.get(OPT_DAMAGE_TYPE, DamageType.PHYSICAL)),
		RESULT_LIFESTEAL_HEALED: 0,
	}


static func _can_receive_pipeline_damage(target: Object) -> bool:
	if target.has_method(&"take_damage"):
		return true
	return resolve_health_component(target) != null


static func _is_damage_immune(target: Object) -> bool:
	if target.has_method(&"is_divine_protection_active"):
		return bool(target.call(&"is_divine_protection_active"))
	if target.has_method(&"is_damage_immune"):
		return bool(target.call(&"is_damage_immune"))
	return false


static func _apply_attacker_buffs(
	attacker: Node,
	target: Object,
	amount: float,
	damage_type: int
) -> float:
	if attacker != null and attacker.has_method(&"modify_outgoing_damage"):
		return float(attacker.call(&"modify_outgoing_damage", amount, target, damage_type))
	return amount


static func _apply_target_buffs(
	target: Object,
	attacker: Node,
	amount: float,
	damage_type: int
) -> float:
	if target.has_method(&"modify_incoming_damage"):
		return float(target.call(&"modify_incoming_damage", amount, attacker, damage_type))
	return amount


static func _roll_critical(amount: float, options: Dictionary) -> Dictionary:
	var result := {"amount": amount, "was_critical": false}
	if not bool(options.get(OPT_CAN_CRIT, false)):
		return result

	var chance: float = clampf(float(options.get(OPT_CRIT_CHANCE, 0.0)), 0.0, 1.0)
	if chance <= 0.0 or randf() >= chance:
		return result

	var multiplier: float = maxf(1.0, float(options.get(OPT_CRIT_MULTIPLIER, 2.0)))
	result["amount"] = amount * multiplier
	result["was_critical"] = true
	return result


static func _apply_damage_reduction(
	target: Object,
	amount: float,
	damage_type: int,
	options: Dictionary
) -> float:
	var reduction: float = float(options.get(OPT_DAMAGE_REDUCTION, 0.0))
	if target.has_method(&"get_incoming_damage_reduction"):
		reduction = maxf(
			reduction,
			float(target.call(&"get_incoming_damage_reduction", damage_type))
		)
	reduction = clampf(reduction, 0.0, 1.0)
	if reduction <= 0.0:
		return amount
	return amount * (1.0 - reduction)


static func _resolve_mitigated_damage(
	target: Object,
	amount: float,
	damage_type: int,
	options: Dictionary
) -> int:
	var bypass_armor: bool = bool(options.get(OPT_BYPASS_ARMOR, false))
	if damage_type == DamageType.TRUE:
		bypass_armor = true

	# Magic / siege hooks stay identity for now so live combat is unchanged.
	if damage_type == DamageType.MAGIC and target.has_method(&"get_magic_resist"):
		pass
	elif damage_type == DamageType.SIEGE and _is_building_target(target):
		pass

	if bypass_armor:
		return _truncate_raw_damage(target, amount)

	if target.has_method(&"_compute_incoming_damage"):
		return int(target.call(&"_compute_incoming_damage", amount))

	if _is_building_target(target):
		return maxi(0, int(amount))

	return int(amount)


static func _truncate_raw_damage(target: Object, amount: float) -> int:
	if _is_building_target(target):
		return maxi(0, int(amount))
	return int(amount)


static func _is_building_target(target: Object) -> bool:
	return target is StaticBody3D and target.has_method(&"destroy_building")


static func _maybe_spawn_floating_number(
	target: Object,
	damage_dealt: int,
	was_critical: bool,
	options: Dictionary
) -> void:
	if not _should_show_floating_number(target, options):
		return
	if not target is Node3D:
		return

	var emphasized: bool = bool(options.get(OPT_EMPHASIZE_FLOAT, false)) or was_critical
	FloatingDamageNumber.spawn(target as Node3D, damage_dealt, emphasized)


static func _should_show_floating_number(target: Object, options: Dictionary) -> bool:
	if options.has(OPT_SHOW_FLOAT):
		return bool(options[OPT_SHOW_FLOAT])
	# Combat units are CharacterBody3D; buildings are StaticBody3D (no float text).
	return target is CharacterBody3D


static func _apply_lifesteal(attacker: Node, damage_dealt: int, options: Dictionary) -> int:
	if not bool(options.get(OPT_CAN_LIFESTEAL, false)):
		return 0
	if damage_dealt <= 0 or attacker == null:
		return 0

	var percent: float = maxf(0.0, float(options.get(OPT_LIFESTEAL_PERCENT, 0.0)))
	if percent <= 0.0:
		return 0

	var heal_amount: int = int(round(float(damage_dealt) * percent))
	if heal_amount <= 0:
		return 0

	var health: HealthComponent = resolve_health_component(attacker)
	if health == null:
		return 0

	health.heal(heal_amount)
	return heal_amount
