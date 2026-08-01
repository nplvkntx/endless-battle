class_name UnitFormationRole
extends RefCounted

## Reusable combat-role metadata for formation slot assignment.
## Prefer role categories over hardcoding scene/class names at call sites.

enum Role {
	NONE = 0,
	PIKE = 1,
	HEAVY_MELEE = 2,
	SWORDS = 3,
	HEAVY_CAVALRY = 4,
	LIGHT_CAVALRY = 5,
	ARCHER = 6,
	CAVALRY_ARCHER = 7,
	SIEGE = 8,
	HERO_FRONT = 9,
	HERO_FLANK = 10,
	HERO_REAR = 11,
}

## Lower = closer to the front / outer edge priority when sorting for slots.
const ROLE_FRONT_PRIORITY: Dictionary = {
	Role.PIKE: 0,
	Role.HEAVY_MELEE: 1,
	Role.HEAVY_CAVALRY: 2,
	Role.SWORDS: 3,
	Role.LIGHT_CAVALRY: 4,
	Role.ARCHER: 10,
	Role.CAVALRY_ARCHER: 11,
	Role.SIEGE: 20,
	Role.HERO_FRONT: 5,
	Role.HERO_FLANK: 6,
	Role.HERO_REAR: 12,
	Role.NONE: 50,
}

const ROLE_LABELS: Dictionary = {
	Role.PIKE: "Pikeman",
	Role.HEAVY_MELEE: "Heavy Melee",
	Role.SWORDS: "Swordsman",
	Role.HEAVY_CAVALRY: "Heavy Cavalry",
	Role.LIGHT_CAVALRY: "Light Cavalry",
	Role.ARCHER: "Archer",
	Role.CAVALRY_ARCHER: "Cavalry Archer",
	Role.SIEGE: "Siege",
	Role.HERO_FRONT: "Hero (Front)",
	Role.HERO_FLANK: "Hero (Flank)",
	Role.HERO_REAR: "Hero (Rear)",
	Role.NONE: "None",
}


static func get_role(unit: Node) -> Role:
	if unit == null or not is_instance_valid(unit):
		return Role.NONE
	if unit is Worker or unit is NeutralCreep or unit is Building:
		return Role.NONE
	if unit is Hero:
		return _hero_follow_role(unit as Hero)
	if unit is Cannon:
		return Role.SIEGE
	if unit is Spearman:
		return Role.PIKE
	if unit is Swordsman:
		return Role.SWORDS
	if unit is HeavyCavalry:
		return Role.HEAVY_CAVALRY
	if unit is LightCavalry:
		return Role.LIGHT_CAVALRY
	if unit is Archer:
		return Role.ARCHER
	if unit is CavalryArcher:
		return Role.CAVALRY_ARCHER
	if unit is MilitaryUnit:
		# Unknown military subclass — treat as durable melee filler.
		return Role.SWORDS
	return Role.NONE


static func is_formation_eligible(unit: Node, allow_siege: bool = true) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit is Hero or unit is Worker or unit is NeutralCreep or unit is Building:
		return false
	if not unit is Unit:
		return false
	var role: Role = get_role(unit)
	if role == Role.NONE:
		return false
	if role == Role.SIEGE and not allow_siege:
		return false
	if unit is MilitaryUnit or unit is Cannon:
		return true
	return false


static func is_siege_role(role: Role) -> bool:
	return role == Role.SIEGE


static func is_ranged_role(role: Role) -> bool:
	return role == Role.ARCHER or role == Role.CAVALRY_ARCHER


static func is_melee_role(role: Role) -> bool:
	return role in [
		Role.PIKE,
		Role.HEAVY_MELEE,
		Role.SWORDS,
		Role.HEAVY_CAVALRY,
		Role.LIGHT_CAVALRY,
	]


static func is_cavalry_role(role: Role) -> bool:
	return role in [Role.HEAVY_CAVALRY, Role.LIGHT_CAVALRY, Role.CAVALRY_ARCHER]


static func is_front_preferred(role: Role) -> bool:
	return role in [Role.PIKE, Role.HEAVY_MELEE, Role.HEAVY_CAVALRY, Role.SWORDS]


static func front_priority(role: Role) -> int:
	return int(ROLE_FRONT_PRIORITY.get(role, 50))


static func compare_units_front_first(a: Variant, b: Variant) -> bool:
	var a_role: Role = get_role(a as Node)
	var b_role: Role = get_role(b as Node)
	var a_pri: int = front_priority(a_role)
	var b_pri: int = front_priority(b_role)
	if a_pri != b_pri:
		return a_pri < b_pri
	var a_id: int = (a as Node).get_instance_id() if is_instance_valid(a) else 0
	var b_id: int = (b as Node).get_instance_id() if is_instance_valid(b) else 0
	return a_id < b_id


static func compare_units_rear_first(a: Variant, b: Variant) -> bool:
	return not compare_units_front_first(a, b)


static func _hero_follow_role(hero: Hero) -> Role:
	var kit_id: StringName = hero.get_hero_kit_id()
	if kit_id == HeroCatalog.KIT_SHADOW_ASSASSIN:
		return Role.HERO_FLANK
	if kit_id == HeroCatalog.KIT_RANGER:
		return Role.HERO_REAR
	# Paladin / default melee heroes stay near front-center.
	return Role.HERO_FRONT


static func hero_follow_offset(role: Role, spacing: float) -> Vector3:
	## Local offset relative to formation forward (+Z local = forward in layout space).
	## Layout space: +Z forward, +X right.
	match role:
		Role.HERO_FRONT:
			return Vector3(0.0, 0.0, spacing * 0.35)
		Role.HERO_FLANK:
			return Vector3(spacing * 2.2, 0.0, 0.0)
		Role.HERO_REAR:
			return Vector3(0.0, 0.0, -spacing * 2.4)
		_:
			return Vector3(0.0, 0.0, -spacing)
