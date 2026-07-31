class_name CombatTargetValidation
extends RefCounted

## Shared checks for whether a node can be safely targeted or damaged in combat.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const NEUTRAL_CREEP_GROUP := &"neutral_creeps"
const ENEMY_TEAM_ID: int = 1

const ENEMY_ATTACK_PRIORITY_COMMAND_CENTER := 1
const ENEMY_ATTACK_PRIORITY_PRODUCTION_BUILDING := 2
const ENEMY_ATTACK_PRIORITY_SUPPORT_BUILDING := 3
const ENEMY_ATTACK_PRIORITY_TOWER := 4
const ENEMY_ATTACK_PRIORITY_ENGAGED_MILITARY := 5
const ENEMY_ATTACK_PRIORITY_MILITARY := 6
const ENEMY_ATTACK_PRIORITY_WORKER := 7
const ENEMY_ATTACK_PRIORITY_LOW_VALUE_BUILDING := 8
const ENEMY_ATTACK_PRIORITY_NEUTRAL_CREEP := 9
const ENEMY_ATTACK_PRIORITY_INVALID := 99

const ENEMY_DEFENSE_PRIORITY_ATTACKING_MILITARY := 1
const ENEMY_DEFENSE_PRIORITY_HERO := 2
const ENEMY_DEFENSE_PRIORITY_ATTACKING_WORKER := 3
const ENEMY_DEFENSE_PRIORITY_INVALID := 99

const BUILDINGS_GROUP := &"buildings"
const ENEMY_WORKER_BUILDING_GUARD_RANGE := 48.0

const ATTACK_SLOTS_PER_RING := 8
const ATTACK_SLOT_ANGLE_STEP := TAU / float(ATTACK_SLOTS_PER_RING)
const MELEE_RANGE_THRESHOLD := 3.5
const APPROACH_RING_SPACING := 1.15
const RANGED_STANDOFF_RATIO := 0.88
const RANGED_TOO_CLOSE_RATIO := 0.72
const RANGED_HOLD_RATIO := 0.85

static var _attack_slot_counter_by_target: Dictionary = {}
## target_id -> Dictionary[attacker_id -> slot_index]
static var _attack_slot_owners_by_target: Dictionary = {}
## target_id -> frozen ring forward (XZ) so slots do not rotate as attackers move
static var _attack_slot_ring_basis_by_target: Dictionary = {}
static var _group_cache_frame: int = -1
static var _group_cache_tree_id: int = -1
static var _cached_group_nodes: Dictionary = {}


## Clear attack-slot and group caches so instance IDs cannot leak across matches.
static func reset_match_state() -> void:
	_attack_slot_counter_by_target.clear()
	_attack_slot_owners_by_target.clear()
	_attack_slot_ring_basis_by_target.clear()
	_group_cache_frame = -1
	_group_cache_tree_id = -1
	_cached_group_nodes.clear()


static func get_cached_group_nodes(tree: SceneTree, group_name: StringName) -> Array:
	if tree == null:
		return []

	var frame: int = Engine.get_process_frames()
	var tree_id: int = tree.get_instance_id()
	if frame != _group_cache_frame or tree_id != _group_cache_tree_id:
		_group_cache_frame = frame
		_group_cache_tree_id = tree_id
		_cached_group_nodes.clear()

	if not _cached_group_nodes.has(group_name):
		var valid_nodes: Array = []
		PerfCounters.record_get_nodes_in_group_call()
		for node_variant: Variant in tree.get_nodes_in_group(group_name):
			if node_variant != null and is_instance_valid(node_variant):
				valid_nodes.append(node_variant)
		_cached_group_nodes[group_name] = valid_nodes

	return _cached_group_nodes[group_name]


static func is_neutral_creep(target: Variant) -> bool:
	if target == null or not target is Node:
		return false

	return (target as Node).is_in_group(NEUTRAL_CREEP_GROUP)


static func is_valid_combat_target(target: Variant) -> bool:
	if not NodeSafety.is_alive_node(target):
		return false

	if not _can_receive_damage(target):
		return false

	return _is_alive(target)


static func is_valid_target(target: Variant) -> bool:
	return is_valid_combat_target(target)


static func clear_target_combat_state(target) -> void:
	if target == null or not is_instance_valid(target):
		return

	clear_attack_approach_slots(target)
	CombatKillTracker.clear_attacker_record(target)


static func purge_stale_attack_slots() -> int:
	var removed: int = 0
	var target_ids: Array = _attack_slot_counter_by_target.keys()
	for owner_id: Variant in _attack_slot_owners_by_target.keys():
		if not target_ids.has(owner_id):
			target_ids.append(owner_id)

	for target_id: Variant in target_ids:
		var node: Variant = instance_from_id(int(target_id))
		if NodeSafety.is_alive_node(node):
			_purge_stale_slot_owners_for_target(int(target_id))
			continue

		_attack_slot_counter_by_target.erase(target_id)
		_attack_slot_owners_by_target.erase(target_id)
		_attack_slot_ring_basis_by_target.erase(target_id)
		removed += 1

	return removed


static func _purge_stale_slot_owners_for_target(target_id: int) -> void:
	if not _attack_slot_owners_by_target.has(target_id):
		return

	var owners: Dictionary = _attack_slot_owners_by_target[target_id]
	var stale_attackers: Array = []
	for attacker_id: Variant in owners.keys():
		var attacker: Variant = instance_from_id(int(attacker_id))
		if not NodeSafety.is_alive_node(attacker):
			stale_attackers.append(attacker_id)

	for attacker_id: Variant in stale_attackers:
		owners.erase(attacker_id)

	if owners.is_empty():
		_attack_slot_owners_by_target.erase(target_id)
	else:
		_attack_slot_owners_by_target[target_id] = owners


static func is_attackable_enemy_building(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if not target is Building:
		return false

	if target is GatherableResource:
		return false

	var building_node: Node = target as Node
	return building_node.is_in_group(ENEMY_BUILDING_GROUP)


static func is_player_selectable_building(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if not target is Building:
		return false

	if target is GatherableResource:
		return false

	var building_node: Node = target as Node
	if building_node.is_queued_for_deletion():
		return false

	return not building_node.is_in_group(ENEMY_BUILDING_GROUP)


static func is_attackable_player_command_center(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if not target is Building:
		return false

	if target is GatherableResource:
		return false

	return (target as Node).is_in_group(PLAYER_COMMAND_CENTER_GROUP)


static func is_player_unit_attack_target(target: Variant) -> bool:
	if not is_valid_combat_target(target):
		return false

	if is_neutral_creep(target):
		return true

	if target is EnemyDummy:
		return true

	if target is Unit and not target is Building and is_enemy_faction(target):
		return true

	return is_attackable_enemy_building(target)


## True when the node belongs to the enemy faction (team_id / faction groups).
static func is_enemy_faction(node: Variant) -> bool:
	if node == null or not node is Node:
		return false

	var scene_node: Node = node as Node
	if scene_node.is_in_group(ENEMY_BUILDING_GROUP):
		return true

	if scene_node.is_in_group(&"enemies"):
		return true

	if node is Unit and (node as Unit).team_id >= ENEMY_TEAM_ID:
		return true

	if node is Building and (node as Building).team_id >= ENEMY_TEAM_ID:
		return true

	return false


## Shared faction hostility check. Friendly fire is blocked unless an ability
## bypasses apply_damage_to_target / are_hostile intentionally.
static func are_hostile(attacker, target: Variant) -> bool:
	if not NodeSafety.is_alive_node(attacker):
		return false

	if not is_valid_combat_target(target):
		return false

	if attacker == target:
		return false

	if is_neutral_creep(target) and not is_neutral_creep(attacker):
		return true

	if is_neutral_creep(attacker) and not is_neutral_creep(target):
		return true

	return is_enemy_faction(attacker) != is_enemy_faction(target)


static func is_attack_target_for_attacker(attacker, target: Variant) -> bool:
	if not are_hostile(attacker, target):
		return false

	if target is GatherableResource:
		return false

	if is_enemy_faction(attacker):
		if is_neutral_creep(target):
			return true
		if target is Unit and not target is Building:
			return true
		if is_player_selectable_building(target):
			return is_valid_combat_target(target)
		return false

	if is_neutral_creep(target):
		return true
	if target is EnemyDummy:
		return true
	if target is Unit and not target is Building:
		return true
	if is_attackable_enemy_building(target):
		return true
	return false


static func is_hero_unit_ability_target(attacker, target: Variant) -> bool:
	if not NodeSafety.is_alive_node(attacker):
		return false
	if target == null:
		return false
	if not is_instance_valid(target):
		return false

	var target_node: Node = target as Node
	if target_node != null and target_node.is_queued_for_deletion():
		return false

	if not is_attack_target_for_attacker(attacker, target):
		return false

	if target is Building:
		return false

	return target is Node3D


## Scene groups that may contain targets hostile to the attacker.
## Always filter results with are_hostile / is_attack_target_for_attacker.
static func get_hostile_search_groups(attacker = null) -> Array[StringName]:
	if attacker != null and is_neutral_creep(attacker):
		return [
			&"enemies",
			ENEMY_BUILDING_GROUP,
			PLAYER_COMMAND_CENTER_GROUP,
			BUILDINGS_GROUP,
			&"units",
			&"heroes",
			NEUTRAL_CREEP_GROUP,
		]

	if attacker != null and is_enemy_faction(attacker):
		return [
			PLAYER_COMMAND_CENTER_GROUP,
			BUILDINGS_GROUP,
			&"units",
			&"heroes",
			NEUTRAL_CREEP_GROUP,
		]

	return [&"enemies", ENEMY_BUILDING_GROUP, NEUTRAL_CREEP_GROUP]


## Unit/creep groups towers auto-acquire against (buildings excluded).
static func get_tower_hostile_search_groups(tower) -> Array[StringName]:
	if tower != null and is_enemy_faction(tower):
		return [&"units", &"heroes", NEUTRAL_CREEP_GROUP]

	return [&"enemies", NEUTRAL_CREEP_GROUP]


static func find_closest_attack_target_for_attacker(attacker) -> Node3D:
	if not NodeSafety.is_alive_node(attacker):
		return null

	if not attacker is Node3D:
		return null

	if is_enemy_faction(attacker):
		return find_best_attack_target_for_attacker_in_range(attacker, INF)
	return find_closest_player_unit_attack_target_in_range(attacker, INF)


static func find_best_attack_target_for_attacker_in_range(
	attacker, search_range: float
) -> Node3D:
	if not NodeSafety.is_alive_node(attacker):
		return null

	if not attacker is Node3D:
		return null

	if search_range <= 0.0:
		return null

	if not is_enemy_faction(attacker):
		return find_closest_player_unit_attack_target_in_range(attacker, search_range)

	return _find_best_enemy_faction_attack_target(attacker, search_range)


static func is_tower_attack_target(tower, target: Variant) -> bool:
	if not NodeSafety.is_alive_node(tower):
		return false

	if not is_valid_combat_target(target):
		return false

	if not target is Node3D:
		return false

	if target is GatherableResource:
		return false

	if target is Building:
		return false

	if target is EnemyDummy and (target as EnemyDummy).exclude_from_tower_auto_target:
		return false

	return are_hostile(tower, target)


static func find_closest_tower_attack_target_in_range(
	tower: Node3D, attack_range: float
) -> Node3D:
	PerfCounters.record_enemy_target_search()
	if tower == null or attack_range <= 0.0:
		return null

	var tree: SceneTree = tower.get_tree()
	if tree == null:
		return null

	var closest_target: Node3D = null
	var closest_distance: float = INF

	for group_name: StringName in get_tower_hostile_search_groups(tower):
		for node_variant: Variant in get_cached_group_nodes(tree, group_name):
			if node_variant == null or not is_instance_valid(node_variant) or not node_variant is Node:
				continue

			var node: Node = node_variant as Node
			if not node is Node3D:
				continue
			if not is_tower_attack_target(tower, node):
				continue

			var target: Node3D = node as Node3D
			var distance: float = get_horizontal_center_distance(tower, target)
			if distance > attack_range:
				continue

			if distance < closest_distance:
				closest_distance = distance
				closest_target = target

	return closest_target


static func get_target_current_health(target: Variant) -> int:
	if target == null or not is_instance_valid(target):
		return 0

	var health_component: HealthComponent = _get_health_component(target)
	if health_component != null:
		return health_component.current_health

	if target is Object and (target as Object).has_method("get_current_health"):
		return (target as Object).call("get_current_health")

	return 0


static func sanitize_damage_attacker(attacker: Variant) -> Node:
	var safe_attacker: Variant = NodeSafety.safe_node(attacker)
	if safe_attacker == null or not safe_attacker is Node:
		return null

	return safe_attacker as Node


static func apply_damage_to_target(target: Variant, amount: float, attacker = null) -> bool:
	# Runtime load + Script.call avoids a class_name cycle with DamageService.
	var damage_service: Variant = load("res://scripts/systems/damage_service.gd")
	if damage_service == null:
		return false
	return bool(damage_service.call(&"apply_damage", target, amount, attacker))


static func _call_take_damage(target: Object, amount: float, attacker = null) -> bool:
	var damage_service: Variant = load("res://scripts/systems/damage_service.gd")
	if damage_service == null:
		return false
	return bool(
		damage_service.call(
			&"apply_damage",
			target,
			amount,
			attacker,
			{&"ignore_hostility": true}
		)
	)


static func is_within_attack_range(
	attacker: Node3D, target: Node3D, attack_range: float
) -> bool:
	if attacker == null or target == null:
		return false

	if is_attackable_enemy_building(target):
		return (
			get_horizontal_attack_distance_to_surface(attacker, target) <= attack_range
		)

	return get_horizontal_center_distance(attacker, target) <= attack_range


static func get_horizontal_attack_distance_to_surface(from: Node3D, target: Node3D) -> float:
	var center_distance: float = get_horizontal_center_distance(from, target)
	if target is CollisionObject3D:
		return maxf(
			0.0,
			center_distance - _get_collision_xz_radius(target as CollisionObject3D)
		)

	return center_distance


static func get_horizontal_center_distance(from: Node3D, to: Node3D) -> float:
	if not NodeSafety.is_alive_node(from) or not NodeSafety.is_alive_node(to):
		return INF

	var offset: Vector3 = from.global_position - to.global_position
	offset.y = 0.0
	return offset.length()


static func get_horizontal_attack_distance(attacker: Node3D, target: Node3D) -> float:
	if attacker == null or target == null:
		return INF

	if is_attackable_enemy_building(target):
		return get_horizontal_attack_distance_to_surface(attacker, target)

	return get_horizontal_center_distance(attacker, target)


static func find_closest_player_unit_attack_target_in_range(
	attacker: Node3D, attack_range: float
) -> Node3D:
	if attacker == null or attack_range <= 0.0:
		return null

	return _find_closest_hostile_attack_target_in_range(attacker, attack_range)


static func get_enemy_attack_target_priority(
	attacker: Node3D, target: Node3D, distance: float
) -> int:
	if not is_attack_target_for_attacker(attacker, target):
		return ENEMY_ATTACK_PRIORITY_INVALID

	var mission: EnemyUnitMission.Mission = EnemyUnitMission.get_unit_mission(attacker)
	if mission == EnemyUnitMission.Mission.DEFEND:
		return get_enemy_defense_target_priority(attacker, target, distance)

	var attack_range: float = _get_attacker_attack_range(attacker)

	if target is Building:
		if is_attackable_player_command_center(target):
			return ENEMY_ATTACK_PRIORITY_COMMAND_CENTER
		if target is Tower:
			return ENEMY_ATTACK_PRIORITY_TOWER
		if target is Barracks or target is Stable or target is ArtilleryDepot:
			return ENEMY_ATTACK_PRIORITY_PRODUCTION_BUILDING
		if target is HeroAltar or target is Shop or target is Blacksmith or target is Academy:
			return ENEMY_ATTACK_PRIORITY_SUPPORT_BUILDING
		if target is Farm:
			return ENEMY_ATTACK_PRIORITY_LOW_VALUE_BUILDING
		if is_player_selectable_building(target):
			return ENEMY_ATTACK_PRIORITY_SUPPORT_BUILDING
		return ENEMY_ATTACK_PRIORITY_LOW_VALUE_BUILDING

	if target is Worker:
		if not _can_enemy_target_worker(attacker, distance, attack_range):
			return ENEMY_ATTACK_PRIORITY_INVALID
		return ENEMY_ATTACK_PRIORITY_WORKER

	if target is Spearman or target is Swordsman or target is Archer or target is HeavyCavalry or target is LightCavalry or target is CavalryArcher or target is Cannon or target is Hero:
		var retaliation_target: Node = CombatKillTracker.get_attacker(attacker)
		if target == retaliation_target or distance <= attack_range:
			return ENEMY_ATTACK_PRIORITY_ENGAGED_MILITARY
		return ENEMY_ATTACK_PRIORITY_MILITARY

	if is_neutral_creep(target):
		if distance <= attack_range:
			return ENEMY_ATTACK_PRIORITY_ENGAGED_MILITARY
		return ENEMY_ATTACK_PRIORITY_NEUTRAL_CREEP

	return ENEMY_ATTACK_PRIORITY_INVALID


static func get_enemy_defense_target_priority(
	attacker: Node3D, target: Node3D, _distance: float
) -> int:
	if not is_attack_target_for_attacker(attacker, target):
		return ENEMY_DEFENSE_PRIORITY_INVALID

	if target is Spearman or target is Swordsman or target is Archer or target is HeavyCavalry or target is LightCavalry or target is CavalryArcher or target is Cannon:
		return ENEMY_DEFENSE_PRIORITY_ATTACKING_MILITARY

	if target is Hero:
		return ENEMY_DEFENSE_PRIORITY_HERO

	if target is Worker and _is_worker_attacking_enemy_buildings(attacker.get_tree(), target):
		return ENEMY_DEFENSE_PRIORITY_ATTACKING_WORKER

	return ENEMY_DEFENSE_PRIORITY_INVALID


static func _find_best_enemy_faction_attack_target(
	attacker: Node3D, search_range: float
) -> Node3D:
	PerfCounters.record_enemy_target_search()
	var best_target: Node3D = null
	var best_priority: int = ENEMY_ATTACK_PRIORITY_INVALID
	var best_distance: float = INF
	var groups_to_search: Array[StringName] = get_hostile_search_groups(attacker)

	var tree: SceneTree = attacker.get_tree()
	for group_name: StringName in groups_to_search:
		for node_variant: Variant in get_cached_group_nodes(tree, group_name):
			if node_variant == null or not is_instance_valid(node_variant) or not node_variant is Node:
				continue

			var node: Node = node_variant as Node
			if not node is Node3D:
				continue

			var target: Node3D = node as Node3D
			if not is_attack_target_for_attacker(attacker, target):
				continue

			var distance: float = get_horizontal_attack_distance(attacker, target)
			if distance > search_range:
				continue

			var priority: int = get_enemy_attack_target_priority(attacker, target, distance)
			if priority >= ENEMY_ATTACK_PRIORITY_INVALID:
				continue

			if priority > best_priority:
				continue

			if priority < best_priority or distance < best_distance:
				best_priority = priority
				best_distance = distance
				best_target = target

	return best_target


static func _find_closest_hostile_attack_target_in_range(
	attacker: Node3D, attack_range: float
) -> Node3D:
	PerfCounters.record_target_search()
	var closest_target: Node3D = null
	var closest_distance: float = INF
	var groups_to_search: Array[StringName] = get_hostile_search_groups(attacker)

	var tree: SceneTree = attacker.get_tree()
	for group_name: StringName in groups_to_search:
		for node_variant: Variant in get_cached_group_nodes(tree, group_name):
			if node_variant == null or not is_instance_valid(node_variant) or not node_variant is Node:
				continue

			var node: Node = node_variant as Node
			if not node is Node3D:
				continue
			if not is_attack_target_for_attacker(attacker, node):
				continue

			var target: Node3D = node as Node3D
			var distance: float = get_horizontal_attack_distance(attacker, target)
			if distance > attack_range:
				continue

			if distance < closest_distance:
				closest_distance = distance
				closest_target = target

	return closest_target


static func _can_enemy_target_worker(
	attacker: Node3D, distance: float, attack_range: float
) -> bool:
	if distance <= attack_range:
		return true

	var tree: SceneTree = attacker.get_tree()
	if tree == null:
		return false

	if _has_living_player_buildings_near(attacker, ENEMY_WORKER_BUILDING_GUARD_RANGE):
		return false

	return not _has_any_living_player_building(tree)


static func _has_living_player_buildings_near(attacker: Node3D, search_range: float) -> bool:
	var tree: SceneTree = attacker.get_tree()
	if tree == null:
		return false

	for node_variant: Variant in get_cached_group_nodes(tree, BUILDINGS_GROUP):
		if not _is_living_player_building(node_variant):
			continue

		var building: Node3D = node_variant as Node3D
		if get_horizontal_center_distance(attacker, building) <= search_range:
			return true

	return false


static func _has_any_living_player_building(tree: SceneTree) -> bool:
	for node_variant: Variant in get_cached_group_nodes(tree, BUILDINGS_GROUP):
		if _is_living_player_building(node_variant):
			return true

	return false


static func _is_living_player_building(target: Variant) -> bool:
	if not is_player_selectable_building(target):
		return false

	return is_valid_combat_target(target)


static func _is_worker_attacking_enemy_buildings(tree: SceneTree, worker) -> bool:
	if tree == null or not NodeSafety.is_alive_node(worker):
		return false

	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.ENEMY_COMMAND_CENTER_GROUP):
		if not node is Building:
			continue

		var building: Building = node as Building
		if building.building_state != Building.STATE_COMPLETED:
			continue

		var attacker: Variant = CombatKillTracker.get_attacker(building)
		if attacker == worker:
			return true

	return false


static func _get_attacker_attack_range(attacker) -> float:
	if not NodeSafety.is_alive_node(attacker):
		return 0.0

	if "attack_range" in attacker:
		return maxf(float(attacker.get("attack_range")), 0.0)

	return 2.0


static func claim_attack_approach_slot(target, attacker = null) -> int:
	if target == null or not is_instance_valid(target):
		return 0

	var target_id: int = target.get_instance_id()
	if attacker != null and is_instance_valid(attacker):
		var existing: int = get_attack_approach_slot(target, attacker)
		if existing >= 0:
			return existing

	var occupied: Dictionary = {}
	if _attack_slot_owners_by_target.has(target_id):
		var owners: Dictionary = _attack_slot_owners_by_target[target_id]
		for attacker_id: Variant in owners.keys():
			occupied[int(owners[attacker_id])] = true

	var next_slot: int = int(_attack_slot_counter_by_target.get(target_id, 0))
	while occupied.has(next_slot):
		next_slot += 1

	_attack_slot_counter_by_target[target_id] = next_slot + 1
	if attacker != null and is_instance_valid(attacker):
		_register_attack_approach_slot(target, attacker, next_slot)
	return next_slot


static func reserve_attack_approach_slot(target, attacker, slot_index: int) -> int:
	if target == null or not is_instance_valid(target):
		return maxi(slot_index, 0)

	var resolved_slot: int = maxi(slot_index, 0)
	if attacker != null and is_instance_valid(attacker):
		_register_attack_approach_slot(target, attacker, resolved_slot)
	var target_id: int = target.get_instance_id()
	var next_counter: int = int(_attack_slot_counter_by_target.get(target_id, 0))
	_attack_slot_counter_by_target[target_id] = maxi(next_counter, resolved_slot + 1)
	return resolved_slot


static func get_attack_approach_slot(target, attacker) -> int:
	if target == null or not is_instance_valid(target):
		return -1
	if attacker == null or not is_instance_valid(attacker):
		return -1

	var target_id: int = target.get_instance_id()
	if not _attack_slot_owners_by_target.has(target_id):
		return -1

	var owners: Dictionary = _attack_slot_owners_by_target[target_id]
	var attacker_id: int = attacker.get_instance_id()
	if not owners.has(attacker_id):
		return -1

	return int(owners[attacker_id])


static func release_attack_approach_slot(target, attacker) -> void:
	if target == null or not is_instance_valid(target):
		return
	if attacker == null or not is_instance_valid(attacker):
		return

	var target_id: int = target.get_instance_id()
	if not _attack_slot_owners_by_target.has(target_id):
		return

	var owners: Dictionary = _attack_slot_owners_by_target[target_id]
	owners.erase(attacker.get_instance_id())
	if owners.is_empty():
		_attack_slot_owners_by_target.erase(target_id)
		_attack_slot_counter_by_target.erase(target_id)
		_attack_slot_ring_basis_by_target.erase(target_id)
	else:
		_attack_slot_owners_by_target[target_id] = owners


static func clear_attack_approach_slots(target) -> void:
	if target == null or not is_instance_valid(target):
		return

	var target_id: int = target.get_instance_id()
	_attack_slot_counter_by_target.erase(target_id)
	_attack_slot_owners_by_target.erase(target_id)
	_attack_slot_ring_basis_by_target.erase(target_id)


static func _register_attack_approach_slot(target, attacker, slot_index: int) -> void:
	var target_id: int = target.get_instance_id()
	var owners: Dictionary = {}
	if _attack_slot_owners_by_target.has(target_id):
		owners = _attack_slot_owners_by_target[target_id]
	owners[attacker.get_instance_id()] = slot_index
	_attack_slot_owners_by_target[target_id] = owners
	_ensure_attack_slot_ring_basis(target, attacker)


static func _ensure_attack_slot_ring_basis(target, attacker) -> void:
	if target == null or not is_instance_valid(target):
		return
	if attacker == null or not is_instance_valid(attacker):
		return

	var target_id: int = target.get_instance_id()
	if _attack_slot_ring_basis_by_target.has(target_id):
		return

	var to_attacker: Vector3 = attacker.global_position - target.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.001:
		to_attacker = Vector3.FORWARD
	_attack_slot_ring_basis_by_target[target_id] = to_attacker.normalized()


static func _get_attack_slot_ring_basis(attacker: Node3D, target: Node3D) -> Vector3:
	if target != null and is_instance_valid(target):
		var target_id: int = target.get_instance_id()
		if _attack_slot_ring_basis_by_target.has(target_id):
			return (_attack_slot_ring_basis_by_target[target_id] as Vector3).normalized()

	var to_attacker: Vector3 = attacker.global_position - target.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.001:
		return Vector3.FORWARD
	return to_attacker.normalized()


static func is_ranged_attack_range(attack_range: float) -> bool:
	return attack_range > MELEE_RANGE_THRESHOLD


static func get_preferred_attack_standoff(
	attacker: Node3D,
	target: Node3D,
	attack_range: float,
	stopping_distance: float,
	slot_index: int = 0
) -> float:
	var ring: int = maxi(slot_index, 0) / ATTACK_SLOTS_PER_RING
	var ring_bonus: float = float(ring) * APPROACH_RING_SPACING
	var attacker_radius: float = 0.5
	if attacker is CollisionObject3D:
		attacker_radius = _get_collision_xz_radius(attacker as CollisionObject3D)

	if target != null and is_attackable_enemy_building(target) and target is CollisionObject3D:
		return (
			_get_collision_xz_radius(target as CollisionObject3D)
			+ attacker_radius
			+ stopping_distance
			+ ring_bonus
		)

	if is_ranged_attack_range(attack_range):
		return maxf(attack_range * RANGED_STANDOFF_RATIO, stopping_distance) + ring_bonus

	return (
		maxf(attack_range - stopping_distance, maxf(attacker_radius + 0.35, stopping_distance))
		+ ring_bonus
	)


static func is_too_close_for_preferred_range(
	attacker: Node3D,
	target: Node3D,
	attack_range: float,
	stopping_distance: float,
	slot_index: int = 0
) -> bool:
	if not is_ranged_attack_range(attack_range):
		return false
	if attacker == null or target == null:
		return false

	var preferred: float = get_preferred_attack_standoff(
		attacker, target, attack_range, stopping_distance, slot_index
	)
	var distance: float = get_horizontal_attack_distance(attacker, target)
	return distance < preferred * RANGED_TOO_CLOSE_RATIO


static func is_at_preferred_hold_range(
	attacker: Node3D,
	target: Node3D,
	attack_range: float,
	stopping_distance: float,
	slot_index: int = 0
) -> bool:
	if attacker == null or target == null:
		return true

	var preferred: float = get_preferred_attack_standoff(
		attacker, target, attack_range, stopping_distance, slot_index
	)
	var distance: float = get_horizontal_attack_distance(attacker, target)
	return distance >= preferred * RANGED_HOLD_RATIO


static func compute_attack_approach_position(
	attacker: Node3D,
	target: Node3D,
	attack_range: float,
	stopping_distance: float,
	slot_index: int = 0
) -> Vector3:
	if attacker == null or not is_instance_valid(attacker):
		return Vector3.ZERO

	if target == null or not is_instance_valid(target):
		return attacker.global_position

	var target_center: Vector3 = target.global_position
	var base_direction: Vector3 = _get_attack_slot_ring_basis(attacker, target)
	if slot_index <= 0 and not _attack_slot_ring_basis_by_target.has(target.get_instance_id()):
		# Solo / untracked approach still faces current attacker direction.
		var to_attacker: Vector3 = attacker.global_position - target_center
		to_attacker.y = 0.0
		if to_attacker.length_squared() >= 0.001:
			base_direction = to_attacker.normalized()

	var standoff_distance: float = get_preferred_attack_standoff(
		attacker, target, attack_range, stopping_distance, slot_index
	)
	var direction: Vector3 = _apply_attack_slot_direction(base_direction, slot_index)
	var approach_position: Vector3 = target_center + direction * standoff_distance
	approach_position.y = attacker.global_position.y
	return approach_position


static func _apply_attack_slot_direction(base_direction: Vector3, slot_index: int) -> Vector3:
	if slot_index <= 0:
		return base_direction

	var slot_in_ring: int = slot_index % ATTACK_SLOTS_PER_RING
	var ring: int = slot_index / ATTACK_SLOTS_PER_RING
	var angle: float = float(slot_in_ring) * ATTACK_SLOT_ANGLE_STEP
	if ring > 0:
		angle += ATTACK_SLOT_ANGLE_STEP * 0.5 * float(ring)

	return base_direction.rotated(Vector3.UP, angle).normalized()


static func _get_collision_xz_radius(body: CollisionObject3D) -> float:
	if body == null:
		return 0.5

	var collision_shape: CollisionShape3D = body.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 0.5

	if collision_shape.shape is BoxShape3D:
		var box_shape := collision_shape.shape as BoxShape3D
		return maxf(box_shape.size.x, box_shape.size.z) * 0.5

	if collision_shape.shape is CylinderShape3D:
		var cylinder_shape := collision_shape.shape as CylinderShape3D
		return cylinder_shape.radius

	if collision_shape.shape is SphereShape3D:
		var sphere_shape := collision_shape.shape as SphereShape3D
		return sphere_shape.radius

	return 0.5


static func _can_receive_damage(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if target is Node and (target as Node).get_node_or_null("HealthComponent") != null:
		return true

	return target is Object and (target as Object).has_method("take_damage")


static func _is_alive(target: Variant) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var health_component: HealthComponent = _get_health_component(target)
	if health_component != null:
		return health_component.current_health > 0

	if target is Object and (target as Object).has_method("get_current_health"):
		return (target as Object).call("get_current_health") > 0

	return true


static func _get_health_component(target: Variant) -> HealthComponent:
	if target == null or not is_instance_valid(target):
		return null

	if target is Node:
		return (target as Node).get_node_or_null("HealthComponent") as HealthComponent
	return null
