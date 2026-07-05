class_name CombatTargetValidation
extends RefCounted

## Shared checks for whether a node can be safely targeted or damaged in combat.

const ENEMY_BUILDING_GROUP := &"enemy_command_center"
const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const NEUTRAL_CREEP_GROUP := &"neutral_creeps"
const ENEMY_TEAM_ID: int = 1

const ENEMY_ATTACK_PRIORITY_ENGAGED := 1
const ENEMY_ATTACK_PRIORITY_WORKER := 2
const ENEMY_ATTACK_PRIORITY_MILITARY := 3
const ENEMY_ATTACK_PRIORITY_NEUTRAL_CREEP := 4
const ENEMY_ATTACK_PRIORITY_BUILDING := 5
const ENEMY_ATTACK_PRIORITY_INVALID := 99

const ATTACK_SLOTS_PER_RING := 8
const ATTACK_SLOT_ANGLE_STEP := TAU / float(ATTACK_SLOTS_PER_RING)

static var _attack_slot_counter_by_target: Dictionary = {}
static var _group_cache_frame: int = -1
static var _group_cache_tree_id: int = -1
static var _cached_group_nodes: Dictionary = {}


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


static func clear_target_combat_state(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	clear_attack_approach_slots(target)
	CombatKillTracker.clear_attacker_record(target)


static func purge_stale_attack_slots() -> int:
	var removed: int = 0

	for target_id: Variant in _attack_slot_counter_by_target.keys():
		var node: Variant = instance_from_id(int(target_id))
		if NodeSafety.is_alive_node(node):
			continue

		_attack_slot_counter_by_target.erase(target_id)
		removed += 1

	return removed


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

	if target is EnemyDummy:
		return true

	if is_neutral_creep(target):
		return true

	if target is Node and (target as Node).is_in_group(&"enemies"):
		if target is Swordsman or target is Archer or target is Worker or target is Hero:
			return true

	return is_attackable_enemy_building(target)


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

	return false


static func are_hostile(attacker: Node, target: Variant) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false

	if not is_valid_combat_target(target):
		return false

	if is_neutral_creep(target) and not is_neutral_creep(attacker):
		return true

	if is_neutral_creep(attacker) and not is_neutral_creep(target):
		return is_valid_combat_target(target)

	return is_enemy_faction(attacker) != is_enemy_faction(target)


static func is_attack_target_for_attacker(attacker: Node, target: Variant) -> bool:
	if not are_hostile(attacker, target):
		return false

	if is_enemy_faction(attacker):
		if is_neutral_creep(target):
			return true
		if target is Unit and not target is Building:
			return true
		return is_attackable_player_command_center(target)

	return is_player_unit_attack_target(target)


static func is_hero_unit_ability_target(attacker: Node, target: Variant) -> bool:
	if attacker == null:
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


static func get_hostile_search_groups() -> Array[StringName]:
	return [&"enemies", ENEMY_BUILDING_GROUP, NEUTRAL_CREEP_GROUP]


static func find_closest_attack_target_for_attacker(attacker: Node3D) -> Node3D:
	if is_enemy_faction(attacker):
		return find_best_attack_target_for_attacker_in_range(attacker, INF)
	return find_closest_player_unit_attack_target_in_range(attacker, INF)


static func find_best_attack_target_for_attacker_in_range(
	attacker: Node3D, search_range: float
) -> Node3D:
	if attacker == null or search_range <= 0.0:
		return null

	if not is_enemy_faction(attacker):
		return find_closest_player_unit_attack_target_in_range(attacker, search_range)

	return _find_best_enemy_faction_attack_target(attacker, search_range)


static func is_tower_attack_target(target: Variant) -> bool:
	if not is_valid_combat_target(target):
		return false

	if not target is Node:
		return false

	var node: Node = target as Node
	if not node.is_in_group("enemies"):
		return false

	if target is GatherableResource:
		return false

	if target is Building:
		return false

	if target is EnemyDummy and (target as EnemyDummy).exclude_from_tower_auto_target:
		return false

	return true


static func find_closest_tower_attack_target_in_range(
	tower: Node3D, attack_range: float
) -> Node3D:
	if tower == null or attack_range <= 0.0:
		return null

	var closest_target: Node3D = null
	var closest_distance: float = INF

	for node_variant: Variant in get_cached_group_nodes(tower.get_tree(), &"enemies"):
		if node_variant == null or not is_instance_valid(node_variant) or not node_variant is Node:
			continue

		var node: Node = node_variant as Node
		if not node is Node3D:
			continue
		if not is_tower_attack_target(node):
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
	if target == null or not is_instance_valid(target):
		return false

	if not is_valid_combat_target(target):
		return false

	var safe_attacker: Node = sanitize_damage_attacker(attacker)
	if safe_attacker != null and not are_hostile(safe_attacker, target):
		return false

	if not target is Object:
		return false

	var target_object: Object = target as Object
	if not target_object.has_method("take_damage"):
		return false

	return _call_take_damage(target_object, amount, safe_attacker)


static func _call_take_damage(target: Object, amount: float, attacker = null) -> bool:
	if not target.has_method("take_damage"):
		return false

	if attacker != null:
		target.call("take_damage", amount, attacker)
	else:
		target.call("take_damage", amount)
	return true


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

	var retaliation_target: Node = CombatKillTracker.get_attacker(attacker)
	if target == retaliation_target:
		return ENEMY_ATTACK_PRIORITY_ENGAGED

	if target is Worker:
		return ENEMY_ATTACK_PRIORITY_WORKER

	if target is Swordsman or target is Archer or target is Hero:
		var attack_range: float = _get_attacker_attack_range(attacker)
		if distance <= attack_range:
			return ENEMY_ATTACK_PRIORITY_ENGAGED
		return ENEMY_ATTACK_PRIORITY_MILITARY

	if is_neutral_creep(target):
		var creep_attack_range: float = _get_attacker_attack_range(attacker)
		if distance <= creep_attack_range:
			return ENEMY_ATTACK_PRIORITY_ENGAGED
		return ENEMY_ATTACK_PRIORITY_NEUTRAL_CREEP

	if is_attackable_player_command_center(target):
		return ENEMY_ATTACK_PRIORITY_BUILDING

	return ENEMY_ATTACK_PRIORITY_INVALID


static func _find_best_enemy_faction_attack_target(
	attacker: Node3D, search_range: float
) -> Node3D:
	var best_target: Node3D = null
	var best_priority: int = ENEMY_ATTACK_PRIORITY_INVALID
	var best_distance: float = INF
	var groups_to_search: Array[StringName] = [&"units", PLAYER_COMMAND_CENTER_GROUP]

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
	var closest_target: Node3D = null
	var closest_distance: float = INF
	var groups_to_search: Array[StringName] = get_hostile_search_groups()

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


static func _get_attacker_attack_range(attacker: Node3D) -> float:
	if attacker == null:
		return 0.0

	if "attack_range" in attacker:
		return maxf(float(attacker.get("attack_range")), 0.0)

	return 2.0


static func claim_attack_approach_slot(target: Node) -> int:
	if target == null or not is_instance_valid(target):
		return 0

	var target_id: int = target.get_instance_id()
	var next_slot: int = int(_attack_slot_counter_by_target.get(target_id, 0))
	_attack_slot_counter_by_target[target_id] = next_slot + 1
	return next_slot


static func clear_attack_approach_slots(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	_attack_slot_counter_by_target.erase(target.get_instance_id())


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
	var to_attacker: Vector3 = attacker.global_position - target_center
	to_attacker.y = 0.0

	if to_attacker.length_squared() < 0.001:
		to_attacker = Vector3.FORWARD

	var standoff_distance: float
	if is_attackable_enemy_building(target) and target is CollisionObject3D:
		standoff_distance = (
			_get_collision_xz_radius(target as CollisionObject3D)
			+ _get_collision_xz_radius(attacker as CollisionObject3D)
			+ stopping_distance
		)
	else:
		standoff_distance = maxf(attack_range - stopping_distance, stopping_distance)

	var base_direction: Vector3 = to_attacker.normalized()
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
