class_name ArmySquadV2
extends RefCounted

## Main-army squad payload for Military AI V2.
## Membership is mutated only by MilitaryDirectorV2.
## ArmyCommanderV2 may read this object but must not recruit or reshuffle.

enum UnitRole {
	FRONTLINE,
	MELEE_GUARD,
	RANGED,
	CAVALRY,
	SIEGE,
	HERO,
}

## Stable combat partitions of the main army (≈10–15 units). Not reshuffled every tick.
enum TacticalRole {
	FRONTLINE,
	RANGED_SUPPORT,
	RESERVE,
	SIEGE,
	HERO_ESCORT,
}

## Stable ordered membership (validated living nodes only).
var members: Array = []
## instance_id -> UnitRole. Assigned once on join; not reshuffled in combat.
var role_by_id: Dictionary = {}
## Optional squad leader / formation anchor.
var leader: Node3D = null
var center: Vector3 = Vector3.ZERO
var total_current_hp: int = 0
var estimated_army_value: float = 0.0
var estimated_dps: float = 0.0
var melee_count: int = 0
var ranged_count: int = 0
var siege_count: int = 0
var hero_present: bool = false
var role_counts: Dictionary = {}
## Tactical squad payloads: {id, role, members, hold_position}.
var tactical_squads: Array = []
## instance_id -> tactical squad id (stable across updates).
var unit_to_tactical_squad: Dictionary = {}
var _next_tactical_squad_id: int = 1


func clear() -> void:
	members.clear()
	role_by_id.clear()
	leader = null
	center = Vector3.ZERO
	total_current_hp = 0
	estimated_army_value = 0.0
	estimated_dps = 0.0
	melee_count = 0
	ranged_count = 0
	siege_count = 0
	hero_present = false
	role_counts.clear()
	tactical_squads.clear()
	unit_to_tactical_squad.clear()
	_next_tactical_squad_id = 1


func get_size() -> int:
	return members.size()


func has_member(unit: Variant) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	return role_by_id.has((unit as Node).get_instance_id())


func get_role(unit: Variant) -> UnitRole:
	if not NodeSafety.is_alive_node(unit):
		return UnitRole.FRONTLINE
	return role_by_id.get((unit as Node).get_instance_id(), UnitRole.FRONTLINE) as UnitRole


func get_members_copy() -> Array:
	return members.duplicate()


static func role_to_string(role: UnitRole) -> String:
	match role:
		UnitRole.FRONTLINE:
			return "frontline"
		UnitRole.MELEE_GUARD:
			return "melee_guard"
		UnitRole.RANGED:
			return "ranged"
		UnitRole.CAVALRY:
			return "cavalry"
		UnitRole.SIEGE:
			return "siege"
		UnitRole.HERO:
			return "hero"
		_:
			return "unknown"


static func classify_role(unit: Node) -> UnitRole:
	if unit == null or not is_instance_valid(unit):
		return UnitRole.FRONTLINE
	if unit is Hero:
		return UnitRole.HERO

	var formation_role: UnitFormationRole.Role = UnitFormationRole.get_role(unit)
	match formation_role:
		UnitFormationRole.Role.PIKE, UnitFormationRole.Role.HEAVY_MELEE:
			return UnitRole.FRONTLINE
		UnitFormationRole.Role.SWORDS:
			return UnitRole.MELEE_GUARD
		UnitFormationRole.Role.ARCHER, UnitFormationRole.Role.CAVALRY_ARCHER:
			return UnitRole.RANGED
		UnitFormationRole.Role.HEAVY_CAVALRY, UnitFormationRole.Role.LIGHT_CAVALRY:
			return UnitRole.CAVALRY
		UnitFormationRole.Role.SIEGE:
			return UnitRole.SIEGE
		_:
			if UnitFormationRole.is_siege_role(formation_role):
				return UnitRole.SIEGE
			if UnitFormationRole.is_ranged_role(formation_role):
				return UnitRole.RANGED
			if UnitFormationRole.is_cavalry_role(formation_role):
				return UnitRole.CAVALRY
			return UnitRole.FRONTLINE


## Type / liveness gate for roster candidates. Trained-but-not-spawned units never appear.
static func is_roster_eligible(unit: Node) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	if not unit.is_inside_tree():
		return false
	if unit is Worker or unit is Building or unit is NeutralCreep:
		return false
	if not EnemyArmyCommand.is_combat_unit(unit):
		return false
	if unit is Hero:
		return EnemyArmyCommand.is_living_combat_unit(unit)
	return EnemyArmyCommand.is_living_combat_unit(unit)


## Low-level membership add. Caller must already own admission policy.
func try_add_member(unit: Node, role: UnitRole = UnitRole.FRONTLINE) -> bool:
	if not NodeSafety.is_alive_node(unit):
		return false
	if not unit.is_inside_tree():
		return false
	if unit is Worker or unit is Building or unit is NeutralCreep:
		return false

	var unit_id: int = unit.get_instance_id()
	if role_by_id.has(unit_id):
		return false

	members.append(unit)
	role_by_id[unit_id] = role
	return true


func remove_member(unit: Variant) -> bool:
	if not NodeSafety.is_alive_node(unit):
		## Freed refs cannot yield a reliable id; sanitize will sweep.
		return false

	var unit_id: int = (unit as Node).get_instance_id()
	if not role_by_id.has(unit_id):
		return false

	role_by_id.erase(unit_id)
	for i: int in range(members.size() - 1, -1, -1):
		var entry: Variant = members[i]
		if entry == null or not is_instance_valid(entry) or (entry as Node).get_instance_id() == unit_id:
			members.remove_at(i)
	if leader != null and (not is_instance_valid(leader) or leader.get_instance_id() == unit_id):
		leader = null
	return true


func remove_by_instance_id(unit_id: int) -> bool:
	if unit_id == 0 or not role_by_id.has(unit_id):
		return false
	role_by_id.erase(unit_id)
	for i: int in range(members.size() - 1, -1, -1):
		var entry: Variant = members[i]
		if entry == null or not is_instance_valid(entry) or (entry as Node).get_instance_id() == unit_id:
			members.remove_at(i)
	if leader != null and (not is_instance_valid(leader) or leader.get_instance_id() == unit_id):
		leader = null
	return true


## Drop dead / freed / out-of-tree / excluded types. Returns removed count.
func sanitize() -> int:
	var removed: int = 0
	var kept: Array = []
	var kept_roles: Dictionary = {}
	var seen_ids: Dictionary = {}

	for entry: Variant in members:
		if not NodeSafety.is_alive_node(entry):
			removed += 1
			continue
		var unit: Node = entry as Node
		if not unit.is_inside_tree():
			removed += 1
			continue
		if unit is Worker or unit is Building or unit is NeutralCreep:
			removed += 1
			continue
		var unit_id: int = unit.get_instance_id()
		if seen_ids.has(unit_id):
			removed += 1
			continue
		seen_ids[unit_id] = true
		kept.append(unit)
		kept_roles[unit_id] = role_by_id.get(unit_id, classify_role(unit))

	if removed > 0 or kept.size() != members.size() or kept_roles.size() != role_by_id.size():
		members = kept
		role_by_id = kept_roles

	if leader != null and not NodeSafety.is_alive_node(leader):
		leader = null
		removed += 1
	elif leader != null and not has_member(leader):
		leader = null

	return removed


func recompute_metrics() -> void:
	sanitize()

	center = Vector3.ZERO
	total_current_hp = 0
	estimated_army_value = 0.0
	estimated_dps = 0.0
	melee_count = 0
	ranged_count = 0
	siege_count = 0
	hero_present = false
	role_counts = {
		UnitRole.FRONTLINE: 0,
		UnitRole.MELEE_GUARD: 0,
		UnitRole.RANGED: 0,
		UnitRole.CAVALRY: 0,
		UnitRole.SIEGE: 0,
		UnitRole.HERO: 0,
	}

	var position_sum: Vector3 = Vector3.ZERO
	var position_count: int = 0

	for entry: Variant in members:
		if not NodeSafety.is_alive_node(entry):
			continue
		var unit: Node = entry as Node
		var unit_id: int = unit.get_instance_id()
		var role: UnitRole = role_by_id.get(unit_id, classify_role(unit)) as UnitRole
		role_by_id[unit_id] = role
		role_counts[role] = int(role_counts.get(role, 0)) + 1

		if role == UnitRole.HERO or unit is Hero:
			hero_present = true

		var formation_role: UnitFormationRole.Role = UnitFormationRole.get_role(unit)
		if UnitFormationRole.is_siege_role(formation_role) or role == UnitRole.SIEGE:
			siege_count += 1
		elif UnitFormationRole.is_ranged_role(formation_role) or role == UnitRole.RANGED:
			ranged_count += 1
		else:
			melee_count += 1

		total_current_hp += _read_current_hp(unit)
		estimated_army_value += _estimate_unit_value(unit)
		estimated_dps += _estimate_unit_dps(unit)

		if unit is Node3D:
			position_sum += (unit as Node3D).global_position
			position_count += 1

	if position_count > 0:
		center = position_sum / float(position_count)

	_select_leader()
	ensure_tactical_squads()


## Keep existing tactical membership stable; only assign new / orphaned units.
func ensure_tactical_squads() -> void:
	var living_ids: Dictionary = {}
	for entry: Variant in members:
		if not NodeSafety.is_alive_node(entry):
			continue
		living_ids[(entry as Node).get_instance_id()] = entry as Node

	## Drop dead units from tactical maps without reshuffling survivors.
	var stale_ids: Array = []
	for unit_id: Variant in unit_to_tactical_squad.keys():
		if not living_ids.has(int(unit_id)):
			stale_ids.append(int(unit_id))
	for stale_id: int in stale_ids:
		unit_to_tactical_squad.erase(stale_id)

	for squad_entry: Variant in tactical_squads:
		if not squad_entry is Dictionary:
			continue
		var squad: Dictionary = squad_entry
		var kept_members: Array = []
		for member_variant: Variant in squad.get("members", []):
			if not NodeSafety.is_alive_node(member_variant):
				continue
			var member_id: int = (member_variant as Node).get_instance_id()
			if living_ids.has(member_id):
				kept_members.append(member_variant)
				unit_to_tactical_squad[member_id] = int(squad.get("id", 0))
		squad["members"] = kept_members

	## Remove empty squads (keep ids stable for surviving ones).
	var non_empty: Array = []
	for squad_entry: Variant in tactical_squads:
		if squad_entry is Dictionary and not (squad_entry as Dictionary).get("members", []).is_empty():
			non_empty.append(squad_entry)
	tactical_squads = non_empty

	## Assign unassigned living members into role-matching underfilled squads.
	for unit_id: Variant in living_ids.keys():
		var id_i: int = int(unit_id)
		if unit_to_tactical_squad.has(id_i):
			continue
		var unit: Node = living_ids[id_i]
		_assign_unit_to_tactical_squad(unit)


func _assign_unit_to_tactical_squad(unit: Node) -> void:
	if not NodeSafety.is_alive_node(unit):
		return
	var unit_id: int = unit.get_instance_id()
	if unit_to_tactical_squad.has(unit_id):
		return

	var tactical_role: TacticalRole = _unit_role_to_tactical(get_role(unit))
	var max_size: int = MilitaryAIConfig.V2_TACTICAL_SQUAD_MAX_SIZE

	## Prefer an existing underfilled matching-role squad.
	for squad_entry: Variant in tactical_squads:
		if not squad_entry is Dictionary:
			continue
		var squad: Dictionary = squad_entry
		if int(squad.get("role", -1)) != int(tactical_role):
			continue
		var squad_members: Array = squad.get("members", [])
		if squad_members.size() >= max_size:
			continue
		squad_members.append(unit)
		squad["members"] = squad_members
		unit_to_tactical_squad[unit_id] = int(squad.get("id", 0))
		return

	## Open a new squad for this role.
	var new_id: int = _next_tactical_squad_id
	_next_tactical_squad_id += 1
	tactical_squads.append({
		"id": new_id,
		"role": tactical_role,
		"members": [unit],
		"hold_position": Vector3.ZERO,
	})
	unit_to_tactical_squad[unit_id] = new_id


static func _unit_role_to_tactical(role: UnitRole) -> TacticalRole:
	match role:
		UnitRole.RANGED:
			return TacticalRole.RANGED_SUPPORT
		UnitRole.SIEGE:
			return TacticalRole.SIEGE
		UnitRole.HERO:
			return TacticalRole.HERO_ESCORT
		UnitRole.CAVALRY:
			## Cavalry fills reserve / reaction duty when not needed on the line.
			return TacticalRole.RESERVE
		_:
			return TacticalRole.FRONTLINE


func get_tactical_squads_copy() -> Array:
	return tactical_squads.duplicate(true)


func get_tactical_squad_members(squad_id: int) -> Array:
	for squad_entry: Variant in tactical_squads:
		if not squad_entry is Dictionary:
			continue
		if int((squad_entry as Dictionary).get("id", -1)) == squad_id:
			return NodeSafety.clean_node_array((squad_entry as Dictionary).get("members", []))
	return []


func get_tactical_squad_id_for_unit(unit: Variant) -> int:
	if not NodeSafety.is_alive_node(unit):
		return 0
	return int(unit_to_tactical_squad.get((unit as Node).get_instance_id(), 0))


func set_tactical_hold_position(squad_id: int, position: Vector3) -> void:
	for squad_entry: Variant in tactical_squads:
		if not squad_entry is Dictionary:
			continue
		if int((squad_entry as Dictionary).get("id", -1)) == squad_id:
			(squad_entry as Dictionary)["hold_position"] = position
			return


static func tactical_role_to_string(role: TacticalRole) -> String:
	match role:
		TacticalRole.FRONTLINE:
			return "frontline"
		TacticalRole.RANGED_SUPPORT:
			return "ranged"
		TacticalRole.RESERVE:
			return "reserve"
		TacticalRole.SIEGE:
			return "siege"
		TacticalRole.HERO_ESCORT:
			return "hero_escort"
		_:
			return "unknown"


func _select_leader() -> void:
	leader = null
	if members.is_empty():
		return

	## Prefer living hero as anchor when present.
	for entry: Variant in members:
		if not NodeSafety.is_alive_node(entry):
			continue
		if entry is Hero:
			leader = entry as Node3D
			return

	## Else prefer a frontline unit closest to squad center.
	var best: Node3D = null
	var best_dist_sq: float = INF
	for entry: Variant in members:
		if not NodeSafety.is_alive_node(entry) or not entry is Node3D:
			continue
		var unit: Node3D = entry as Node3D
		var role: UnitRole = get_role(unit)
		if role != UnitRole.FRONTLINE and role != UnitRole.MELEE_GUARD:
			continue
		var dist_sq: float = unit.global_position.distance_squared_to(center)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = unit
	if best != null:
		leader = best
		return

	## Fallback: first living member.
	for entry: Variant in members:
		if NodeSafety.is_alive_node(entry) and entry is Node3D:
			leader = entry as Node3D
			return


static func _read_current_hp(unit: Node) -> int:
	return maxi(0, CombatTargetValidation.get_target_current_health(unit))


static func _estimate_unit_value(unit: Node) -> float:
	var weight: float = EnemyArmyForceMath.get_unit_type_strength_weight(unit)
	var health_ratio: float = EnemyArmyForceMath.get_health_ratio(unit)
	return weight * health_ratio * 100.0


static func _estimate_unit_dps(unit: Node) -> float:
	if unit == null or not is_instance_valid(unit):
		return 0.0
	var damage: float = 0.0
	var cooldown: float = 1.0
	if "attack_damage" in unit:
		damage = float(unit.get("attack_damage"))
	if "attack_cooldown" in unit:
		cooldown = float(unit.get("attack_cooldown"))
	cooldown = maxf(cooldown, 0.05)
	return maxf(0.0, damage / cooldown)


func get_role_count(role: UnitRole) -> int:
	return int(role_counts.get(role, 0))


func get_role_counts_label() -> String:
	return "F%d G%d R%d C%d S%d H%d" % [
		get_role_count(UnitRole.FRONTLINE),
		get_role_count(UnitRole.MELEE_GUARD),
		get_role_count(UnitRole.RANGED),
		get_role_count(UnitRole.CAVALRY),
		get_role_count(UnitRole.SIEGE),
		get_role_count(UnitRole.HERO),
	]
