class_name MeleeHero
extends Hero

## Shared melee combat, movement, and orders for hero units (Paladin and future kits).

@export var attack_damage: int = HeroStats.ATTACK_DAMAGE
@export var attack_range: float = HeroStats.ATTACK_RANGE
@export var attack_cooldown: float = HeroStats.ATTACK_COOLDOWN
@export var mana_regen_rate: float = HeroStats.MANA_REGEN_RATE

const HEALTH_BAR_WIDTH := 1.4
const HEALTH_BAR_HUE_GREEN := 0.333333
const ATTACK_LUNGE_DISTANCE := 0.4
const ATTACK_LUNGE_DURATION := 0.12
const ATTACK_WINDUP_DURATION := 0.12
const MOVE_SPEED_PER_LEVEL_AFTER_18 := HeroStats.MOVE_SPEED_PER_LEVEL_AFTER_18
const ATTACK_MOVE_ENGAGEMENT_RANGE := 14.0
const HOLD_RETURN_DISTANCE := 1.25
const OPPORTUNISTIC_CHASE_LEASH := 18.0

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill
@onready var _body_mesh: MeshInstance3D = $MeshInstance3D

var _health_bar_fill_material: StandardMaterial3D
var _body_mesh_rest_position: Vector3
var _attack_lunge_tween: Tween
var _attack_target: Node3D = null
var _attack_target_tree_exiting_handler: Callable = Callable()
var _attack_approach_slot: int = -1
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false
var _has_active_attack_order: bool = false
var _committed_attack_order: bool = false
var _is_backing_off_for_range: bool = false
var _attack_move_destination: Vector3 = Vector3.ZERO
var _has_attack_move_destination: bool = false
var _is_holding_position: bool = false
var _hold_anchor: Vector3 = Vector3.ZERO
var _is_patrolling: bool = false
var _patrol_points: Array[Vector3] = []
var _patrol_index: int = 0
var _mana_regen_accumulator: float = 0.0
var _body_material: StandardMaterial3D
var _body_base_color: Color
## Set by subclass `_tick_hero_abilities` when an ability owns the physics frame.
var _ability_consumed_physics_frame: bool = false
var _attack_windup_active: bool = false
var _attack_windup_timer: float = 0.0
var _move_to_cast_ability_id: StringName = &""
var _move_to_cast_target: Node3D = null
var _has_move_to_cast: bool = false


func _ready() -> void:
	super._ready()
	_health_bar_fill_material = HealthBarDisplay.duplicate_mesh_material(_health_bar_fill)
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_body_mesh_rest_position = _body_mesh.position
	_body_material = HealthBarDisplay.duplicate_mesh_material(_body_mesh)
	_body_mesh.set_surface_override_material(0, _body_material)
	_body_base_color = _body_material.albedo_color
	if CombatTargetValidation.is_enemy_faction(self):
		if HeroProgressionStore.has_saved_enemy_progression():
			HeroProgressionStore.apply_to_hero(self)
		current_mana = max_mana
		mana_changed.emit(current_mana, max_mana)
	elif HeroProgressionStore.has_saved_progression():
		HeroProgressionStore.apply_to_hero(self)
	else:
		current_mana = max_mana
		mana_changed.emit(current_mana, max_mana)
	_update_health_bar(_health_component.current_health, _health_component.max_health)
	HeroProgressionStore.register_living_hero(self)
	died.connect(_notify_hero_altars_of_death)
	died.connect(_on_hero_died_cancel_targeting)


func _on_hero_died_cancel_targeting(_unit: Unit) -> void:
	HeroProgressionStore.clear_living_hero(self)
	if HeroAbilityTargetingController != null:
		HeroAbilityTargetingController.on_hero_died(self)


func get_hero_kit_id() -> StringName:
	return HeroCatalog.KIT_PALADIN


func get_display_name() -> String:
	return "Hero"


func get_kit_base_attack_damage() -> int:
	return HeroStats.ATTACK_DAMAGE


func get_kit_base_max_mana() -> int:
	return HeroStats.MAX_MANA


func get_kit_base_move_speed() -> float:
	return HeroStats.MOVE_SPEED


func get_kit_base_max_health() -> int:
	return HeroStats.MAX_HEALTH


func get_kit_attack_damage_per_level() -> int:
	return ATTACK_DAMAGE_PER_LEVEL


func get_kit_health_per_level() -> int:
	return HEALTH_PER_LEVEL


func get_kit_mana_per_level() -> int:
	return MANA_PER_LEVEL


func _tick_hero_abilities(_delta: float) -> void:
	pass


func _sanitize_hero_ability_targets() -> void:
	pass


func _on_prepare_for_new_player_order() -> void:
	pass


func _on_basic_attack_landed(_target: Node3D) -> void:
	pass


func _get_ability_facing_target() -> Node3D:
	return null


## Generic cast entry used by UI / hotkeys. Subclasses override try_cast_q/w/e/r.
func try_cast_ability(ability_id: StringName, target: Variant = null) -> bool:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return try_cast_q(target)
		HeroAbilityProgression.ABILITY_W:
			return try_cast_w(target)
		HeroAbilityProgression.ABILITY_E:
			return try_cast_e(target)
		HeroAbilityProgression.ABILITY_R:
			return try_cast_r(target)
		_:
			return false


func try_cast_q(_target: Variant = null) -> bool:
	return false


func try_cast_w(_target: Variant = null) -> bool:
	return false


func try_cast_e(_target: Variant = null) -> bool:
	return false


func try_cast_r(_target: Variant = null) -> bool:
	return false


enum AbilityTargetMode { INSTANT, SELF, UNIT, GROUND }


func get_ability_target_mode(ability_id: StringName) -> int:
	var definition: HeroAbilityDefinition = get_ability_definition(ability_id)
	if definition == null:
		return AbilityTargetMode.INSTANT
	match definition.targeting_type:
		HeroAbilityDefinition.TargetingType.INSTANT_SELF, \
		HeroAbilityDefinition.TargetingType.NO_TARGET, \
		HeroAbilityDefinition.TargetingType.CIRCULAR_SELF:
			return AbilityTargetMode.INSTANT
		HeroAbilityDefinition.TargetingType.TARGET_ENEMY, \
		HeroAbilityDefinition.TargetingType.TARGET_ALLY, \
		HeroAbilityDefinition.TargetingType.TARGET_UNIT, \
		HeroAbilityDefinition.TargetingType.DASH_TARGET:
			return AbilityTargetMode.UNIT
		HeroAbilityDefinition.TargetingType.TARGET_GROUND, \
		HeroAbilityDefinition.TargetingType.CIRCULAR_AREA, \
		HeroAbilityDefinition.TargetingType.DIRECTIONAL_LINE, \
		HeroAbilityDefinition.TargetingType.DASH_DIRECTION, \
		HeroAbilityDefinition.TargetingType.CONE:
			return AbilityTargetMode.GROUND
		_:
			return AbilityTargetMode.INSTANT


## Kit-specific targeting metadata for the shared player targeting controller.
func get_ability_definition(_ability_id: StringName) -> HeroAbilityDefinition:
	return null


func snap_ability_navigation_point(desired: Vector3) -> Vector3:
	var result: Vector3 = Vector3(desired.x, global_position.y, desired.z)
	if _navigation_agent != null and UnitNavigation.can_use(_navigation_agent):
		var nav_map: RID = _navigation_agent.get_navigation_map()
		if nav_map != RID():
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, result)
			result = Vector3(snapped.x, global_position.y, snapped.z)
	return result


func begin_move_to_cast(ability_id: StringName, target: Node3D) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	var definition: HeroAbilityDefinition = get_ability_definition(ability_id)
	if definition == null:
		return

	# Clear other orders without wiping this pending cast.
	_on_prepare_for_new_player_order()
	_clear_hold_position_state()
	_clear_patrol_state()
	cancel_attack_move()
	cancel_attack()

	_move_to_cast_ability_id = ability_id
	_move_to_cast_target = NodeSafety.safe_node(target) as Node3D
	_has_move_to_cast = _move_to_cast_target != null
	if not _has_move_to_cast:
		return

	var slot: int = CombatTargetValidation.claim_attack_approach_slot(_move_to_cast_target, self)
	_set_move_destination(
		_compute_attack_approach_position(_move_to_cast_target, slot),
		RepathUrgency.PLAYER_ORDER
	)


func cancel_move_to_cast() -> void:
	if _has_move_to_cast and NodeSafety.is_alive_node(_move_to_cast_target):
		CombatTargetValidation.release_attack_approach_slot(_move_to_cast_target, self)
	_has_move_to_cast = false
	_move_to_cast_ability_id = &""
	_move_to_cast_target = null


func is_player_controlled_hero() -> bool:
	return not CombatTargetValidation.is_enemy_faction(self)


func get_ability_cooldown_remaining(ability_id: StringName) -> float:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return get_ground_slam_cooldown_remaining()
		HeroAbilityProgression.ABILITY_W:
			return get_divine_protection_cooldown_remaining()
		HeroAbilityProgression.ABILITY_E:
			return get_power_strike_cooldown_remaining()
		HeroAbilityProgression.ABILITY_R:
			return get_execute_cooldown_remaining()
		_:
			return 0.0


func get_ability_active_status_text(_ability_id: StringName) -> String:
	return ""


## AI entry point — subclasses implement kit-specific casting.
func try_ai_cast_abilities(_context: Dictionary) -> void:
	pass


func _notify_hero_altars_of_death(_unit: Unit) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	for node_variant: Variant in tree.get_nodes_in_group("buildings"):
		if not NodeSafety.is_alive_node(node_variant) or not node_variant is HeroAltar:
			continue
		(node_variant as HeroAltar).hero_altar_state_changed.emit()


func _apply_level_mana_gain() -> void:
	var mana_gain: int = get_kit_mana_per_level()
	max_mana += mana_gain
	current_mana = mini(current_mana + mana_gain, max_mana)
	mana_changed.emit(current_mana, max_mana)


func _apply_level_attack_damage_gain() -> void:
	attack_damage += get_kit_attack_damage_per_level()


func _apply_level_move_speed_gain() -> void:
	move_speed += MOVE_SPEED_PER_LEVEL_AFTER_18


func _apply_accumulated_level_combat_stats(levels_gained: int) -> void:
	attack_damage = get_kit_base_attack_damage() + levels_gained * get_kit_attack_damage_per_level()
	max_mana = get_kit_base_max_mana() + levels_gained * get_kit_mana_per_level()
	current_mana = max_mana
	mana_changed.emit(current_mana, max_mana)


func _apply_accumulated_level_move_speed_bonus() -> void:
	var levels_after_18: int = maxi(0, level - MAX_ABILITY_POINT_LEVEL)
	move_speed = get_kit_base_move_speed() + float(levels_after_18) * MOVE_SPEED_PER_LEVEL_AFTER_18


func _on_progression_restored() -> void:
	_update_health_bar(_health_component.current_health, _health_component.max_health)


func _on_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(current_health, max_health)


func _update_health_bar(current_health: int, max_health: int) -> void:
	HealthBarDisplay.update_world_bar(
		_health_bar,
		_health_bar_fill,
		_health_bar_fill_material,
		current_health,
		max_health,
		HEALTH_BAR_WIDTH,
		HEALTH_BAR_HUE_GREEN
	)


func _get_health_bar_color(ratio: float) -> Color:
	return Color.from_hsv(ratio * HEALTH_BAR_HUE_GREEN, 0.85, 0.9)


func get_attack_facing_direction() -> Vector3:
	var target: Node3D = _get_ability_facing_target()
	if target == null or not CombatTargetValidation.is_valid_combat_target(target):
		if _attack_target != null and CombatTargetValidation.is_valid_combat_target(_attack_target):
			target = _attack_target
		else:
			target = null

	if target == null:
		return Vector3.ZERO

	var direction: Vector3 = target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return Vector3.ZERO

	return direction.normalized()


func supports_combat_orders() -> bool:
	return true


func _prepare_for_new_player_order() -> void:
	_on_prepare_for_new_player_order()
	_clear_hold_position_state()
	_clear_patrol_state()
	cancel_move_to_cast()
	cancel_attack_move()
	cancel_attack()


func command_attack(target: Node3D, assigned_slot: int = -1) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if not CombatTargetValidation.is_attack_target_for_attacker(self, target):
		return

	if (
		_attack_target == target
		and _has_active_attack_order
		and (assigned_slot < 0 or assigned_slot == _attack_approach_slot)
	):
		return

	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.attack(target, assigned_slot)
		_prepare_for_new_player_order()

	_begin_attack_on_target(target, assigned_slot, true)


func _begin_attack_on_target(target: Node3D, assigned_slot: int, committed: bool) -> void:
	_on_prepare_for_new_player_order()
	_assign_attack_approach_slot(target, assigned_slot)
	_set_attack_target(NodeSafety.safe_node(target) as Node3D)
	if _attack_target == null:
		return
	_has_active_attack_order = true
	_committed_attack_order = committed
	_has_chase_target = false

	if _is_holding_position:
		if not _is_in_attack_range(_attack_target):
			cancel_attack()
		return

	if not _is_in_attack_range(_attack_target):
		_begin_chase()


func _set_attack_target(target: Node3D) -> void:
	_clear_attack_target_lifetime_watch()
	_attack_target = NodeSafety.safe_node(target) as Node3D
	if _attack_target == null:
		return
	_watch_attack_target_lifetime(_attack_target)


func _watch_attack_target_lifetime(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_attack_target_tree_exiting_handler = _on_attack_target_tree_exiting.bind(target.get_instance_id())
	if not target.tree_exiting.is_connected(_attack_target_tree_exiting_handler):
		target.tree_exiting.connect(_attack_target_tree_exiting_handler, CONNECT_ONE_SHOT)


func _clear_attack_target_lifetime_watch() -> void:
	if not _attack_target_tree_exiting_handler.is_valid():
		_attack_target_tree_exiting_handler = Callable()
		return

	var target_ref: Variant = _attack_target
	if (
		target_ref != null
		and is_instance_valid(target_ref)
		and target_ref is Node
		and (target_ref as Node).tree_exiting.is_connected(_attack_target_tree_exiting_handler)
	):
		(target_ref as Node).tree_exiting.disconnect(_attack_target_tree_exiting_handler)

	_attack_target_tree_exiting_handler = Callable()


func _on_attack_target_tree_exiting(expected_instance_id: int) -> void:
	_attack_target_tree_exiting_handler = Callable()
	var target_ref: Variant = _attack_target
	if target_ref != null and is_instance_valid(target_ref):
		if int(target_ref.get_instance_id()) != expected_instance_id:
			return
	_attack_target = null
	if _has_active_attack_order:
		_finish_attack_target_lost()
	else:
		_has_chase_target = false
		_committed_attack_order = false
		_attack_approach_slot = -1


func command_attack_move(
	destination: Vector3,
	urgency: RepathUrgency = RepathUrgency.PLAYER_ORDER
) -> void:
	var flat_destination: Vector3 = Vector3(destination.x, global_position.y, destination.z)
	if _has_attack_move_destination:
		var existing_delta: Vector3 = flat_destination - _attack_move_destination
		existing_delta.y = 0.0
		var skip_threshold: float = (
			PLAYER_DEST_NEAR_SKIP
			if urgency == RepathUrgency.PLAYER_ORDER
			else MOVE_DEST_TOLERANCE
		)
		if existing_delta.length() <= skip_threshold:
			if not _issuing_order and urgency == RepathUrgency.PLAYER_ORDER:
				_active_order = UnitOrder.attack_move(destination)
			if has_move_target or _attack_target != null:
				return
			if _is_at_attack_move_destination():
				return

	if not _issuing_order and urgency == RepathUrgency.PLAYER_ORDER:
		_order_queue.clear()
		_active_order = UnitOrder.attack_move(destination)
		_clear_hold_position_state()
		_clear_patrol_state()
		_on_prepare_for_new_player_order()
	elif not _issuing_order:
		_clear_hold_position_state()
		_clear_patrol_state()

	_attack_move_destination = flat_destination
	_has_attack_move_destination = true
	cancel_attack()
	_set_move_destination(flat_destination, urgency)


func command_hold_position() -> void:
	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.hold_position()
		_clear_patrol_state()
		_on_prepare_for_new_player_order()
		cancel_attack_move()
		cancel_attack()

	_is_holding_position = true
	_hold_anchor = global_position
	clear_move_target()


func command_patrol(points: Array[Vector3]) -> void:
	var resolved_points: Array[Vector3] = []
	for point: Vector3 in points:
		resolved_points.append(Vector3(point.x, global_position.y, point.z))
	if resolved_points.size() == 1:
		resolved_points.insert(0, global_position)
	if resolved_points.size() < 2:
		return

	if not _issuing_order:
		_order_queue.clear()
		_active_order = UnitOrder.patrol(resolved_points)
		_clear_hold_position_state()
		_on_prepare_for_new_player_order()

	_patrol_points = resolved_points
	_patrol_index = 0
	_is_patrolling = true
	cancel_attack()
	_start_patrol_leg()


func append_patrol_point(point: Vector3) -> void:
	if not _is_patrolling:
		command_patrol([global_position, point] as Array[Vector3])
		return
	var next_point := Vector3(point.x, global_position.y, point.z)
	_patrol_points.append(next_point)
	if _active_order != null and _active_order.type == UnitOrder.Type.PATROL:
		_active_order.patrol_points = _patrol_points.duplicate()


func _start_patrol_leg() -> void:
	if _patrol_points.is_empty():
		_clear_patrol_state()
		return
	_patrol_index = posmod(_patrol_index, _patrol_points.size())
	var destination: Vector3 = _patrol_points[_patrol_index]
	_attack_move_destination = destination
	_has_attack_move_destination = true
	_set_move_destination(destination, RepathUrgency.PLAYER_ORDER)


func _advance_patrol_waypoint() -> void:
	if not _is_patrolling or _patrol_points.is_empty():
		return
	_patrol_index = (_patrol_index + 1) % _patrol_points.size()
	_start_patrol_leg()


## Current attack target, if any. Used by StealthService to let committed
## attacks keep a stealthed target that auto-targeting would otherwise skip.
func get_attack_target() -> Node3D:
	return _attack_target


func cancel_attack_move() -> void:
	_has_attack_move_destination = false


func cancel_attack() -> void:
	if NodeSafety.is_alive_node(_attack_target):
		CombatTargetValidation.release_attack_approach_slot(_attack_target, self)
	_clear_attack_target_lifetime_watch()
	_attack_target = null
	_attack_approach_slot = -1
	_has_chase_target = false
	_is_backing_off_for_range = false
	_has_active_attack_order = false
	_committed_attack_order = false
	_clear_attack_windup()


func _clear_attack_windup() -> void:
	_attack_windup_active = false
	_attack_windup_timer = 0.0


func _clear_hold_position_state() -> void:
	_is_holding_position = false


func _clear_patrol_state() -> void:
	_is_patrolling = false
	_patrol_points.clear()
	_patrol_index = 0


func _sanitize_attack_target() -> void:
	var target_ref: Variant = _attack_target
	if target_ref != null and not is_instance_valid(target_ref):
		_clear_attack_target_lifetime_watch()
		_attack_target = null
		if _has_active_attack_order:
			_finish_attack_target_lost()
		elif _has_chase_target:
			_has_chase_target = false
			clear_move_target()
			_resume_attack_move_or_patrol()
		return

	if _has_active_attack_order and not NodeSafety.is_alive_node(_attack_target):
		_finish_attack_target_lost()
		return

	if _attack_target == null:
		if _has_chase_target:
			_has_chase_target = false
			clear_move_target()
			_resume_attack_move_or_patrol()
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		_finish_attack_target_lost()


func _finish_attack_target_lost() -> void:
	var was_committed: bool = _committed_attack_order
	cancel_attack()
	if _resume_attack_move_or_patrol():
		return
	if was_committed:
		notify_order_completed(UnitOrder.Type.ATTACK)


func set_movement_target(
	target: Vector3,
	urgency: RepathUrgency = RepathUrgency.PLAYER_ORDER
) -> bool:
	if not _issuing_order and urgency == RepathUrgency.PLAYER_ORDER:
		_order_queue.clear()
		_active_order = UnitOrder.move(target)
		_prepare_for_new_player_order()
	elif not _issuing_order:
		_on_prepare_for_new_player_order()
		cancel_attack_move()
		cancel_attack()
	else:
		_on_prepare_for_new_player_order()
		cancel_attack_move()
		cancel_attack()
	return _set_move_destination(target, urgency)


func stop_movement() -> void:
	_on_prepare_for_new_player_order()
	_clear_hold_position_state()
	_clear_patrol_state()
	cancel_attack_move()
	cancel_attack()
	super.stop_movement()


func _on_movement_arrived() -> void:
	# Direct attack chase is only complete when inside effective strike range.
	# Nav finished / soft-arrival / blocked settle near an approach waypoint must not stop the chase.
	if (
		_has_active_attack_order
		and NodeSafety.is_alive_node(_attack_target)
		and CombatTargetValidation.is_valid_combat_target(_attack_target)
		and not _is_in_attack_range(_attack_target)
		and _approach_slot_should_enter_strike_range()
	):
		_has_chase_target = false
		_update_chase_movement(0.0, true)
		return

	if _is_patrolling and _has_attack_move_destination:
		_advance_patrol_waypoint()
		return
	if _has_attack_move_destination and _is_at_attack_move_destination():
		cancel_attack_move()
		notify_order_completed(UnitOrder.Type.ATTACK_MOVE)
		return
	super._on_movement_arrived()


func _set_move_destination(
	target: Vector3,
	urgency: RepathUrgency = RepathUrgency.NORMAL
) -> bool:
	return request_movement_target(target, urgency)


func _tick_mana_regen(delta: float) -> void:
	if current_mana >= max_mana:
		_mana_regen_accumulator = 0.0
		return

	if mana_regen_rate <= 0.0:
		return

	_mana_regen_accumulator += mana_regen_rate * delta
	if _mana_regen_accumulator < 1.0:
		return

	var mana_gain: int = int(_mana_regen_accumulator)
	_mana_regen_accumulator -= float(mana_gain)
	var new_mana: int = mini(max_mana, current_mana + mana_gain)
	if new_mana == current_mana:
		return

	current_mana = new_mana
	mana_changed.emit(current_mana, max_mana)


func _physics_process(delta: float) -> void:
	if _health_component.current_health <= 0:
		return

	_sanitize_attack_target()
	_sanitize_hero_ability_targets()
	_sanitize_move_to_cast_target()

	_ability_consumed_physics_frame = false
	_tick_hero_abilities(delta)
	_tick_mana_regen(delta)

	if _ability_consumed_physics_frame:
		return

	if _has_move_to_cast:
		_process_move_to_cast(delta)
		return

	var can_scan_targets: bool = tick_combat_target_scan_timer(delta)

	if _is_holding_position:
		_update_hold_position(can_scan_targets, delta)
		return

	# Player heroes never idle-auto-acquire; AI heroes and Attack-Move keep acquisition.
	if _attack_target == null and not has_move_target:
		if can_scan_targets:
			_try_auto_attack()

	if _has_attack_move_destination and _attack_target == null:
		if can_scan_targets:
			_try_attack_move_engagement()

	if _has_active_attack_order:
		if not NodeSafety.is_alive_node(_attack_target):
			_finish_attack_target_lost()
		elif not CombatTargetValidation.is_valid_combat_target(_attack_target):
			_finish_attack_target_lost()
		elif not _committed_attack_order and _should_break_opportunistic_chase():
			cancel_attack()
			_resume_attack_move_or_patrol()
		else:
			_process_attack(delta)
			return

	super._physics_process(delta)

	if _has_attack_move_destination and _attack_target == null and not has_move_target:
		if _is_patrolling:
			_advance_patrol_waypoint()
		elif _is_at_attack_move_destination():
			cancel_attack_move()
			notify_order_completed(UnitOrder.Type.ATTACK_MOVE)


func _update_hold_position(can_scan_targets: bool, delta: float) -> void:
	var offset: Vector3 = global_position - _hold_anchor
	offset.y = 0.0
	if offset.length() > HOLD_RETURN_DISTANCE and _attack_target == null:
		_set_move_destination(_hold_anchor, RepathUrgency.NORMAL)
		super._physics_process(delta)
		return

	if _attack_target == null:
		clear_move_target()
		if can_scan_targets:
			var nearby: Node3D = _find_closest_attack_target_in_range()
			if nearby != null:
				_begin_attack_on_target(nearby, -1, false)
		apply_standing_separation(true)
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		apply_standing_separation(true)
		return

	if _is_in_attack_range(_attack_target):
		_stop_and_attack(delta)
	else:
		cancel_attack()
		apply_standing_separation(true)


func _try_auto_attack() -> void:
	# Player-controlled heroes require explicit Attack / Attack-Move / right-click.
	if is_player_controlled_hero():
		return

	if CombatTargetValidation.is_enemy_faction(self) and not EnemyUnitMission.allows_combat_micro(self):
		return

	var closest_target: Node3D = _find_closest_attack_target_in_range()
	if closest_target != null:
		_begin_attack_on_target(closest_target, -1, false)


func _find_closest_attack_target_in_range() -> Node3D:
	if CombatTargetValidation.is_enemy_faction(self):
		return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, attack_range
		)

	return CombatTargetValidation.find_closest_player_unit_attack_target_in_range(
		self, attack_range
	)


func _process_attack(delta: float) -> void:
	if _is_in_attack_range(_attack_target):
		if _should_reposition_for_preferred_range():
			_update_chase_movement(delta)
			super._physics_process(delta)
			if _attack_target != null and _is_in_attack_range(_attack_target):
				if not _should_reposition_for_preferred_range():
					_is_backing_off_for_range = false
					_stop_and_attack(delta)
			return

		_is_backing_off_for_range = false
		_stop_and_attack(delta)
		return

	_update_chase_movement(delta)
	super._physics_process(delta)

	if _attack_target != null and _is_in_attack_range(_attack_target):
		if not _should_reposition_for_preferred_range():
			_is_backing_off_for_range = false
			_stop_and_attack(delta)


func _stop_and_attack(delta: float) -> void:
	clear_move_target()
	_has_chase_target = false
	_is_backing_off_for_range = false
	apply_standing_separation(true)

	# Windup in progress: finish or wait. Move orders cancel via cancel_attack().
	if _attack_windup_active:
		_tick_attack_windup(delta)
		return

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		_finish_attack_target_lost()
		return

	# Start windup — damage / projectile only after windup completes.
	_attack_windup_active = true
	_attack_windup_timer = get_attack_windup_duration()
	_play_attack_animation()


func get_attack_windup_duration() -> float:
	return ATTACK_WINDUP_DURATION


func _tick_attack_windup(delta: float) -> void:
	_attack_windup_timer -= delta
	if _attack_windup_timer > 0.0:
		return

	_attack_windup_active = false
	_attack_windup_timer = 0.0
	_complete_basic_attack_strike()


func _complete_basic_attack_strike() -> void:
	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		_finish_attack_target_lost()
		return

	var strike_target: Node3D = _attack_target
	if not _deliver_basic_attack_hit(strike_target):
		_finish_attack_target_lost()
		return

	_attack_cooldown_timer = attack_cooldown

	if strike_target == null or not is_instance_valid(strike_target):
		_finish_attack_target_lost()
		return

	_on_basic_attack_landed(strike_target)

	if not NodeSafety.is_alive_node(_attack_target):
		_finish_attack_target_lost()


## Override in ranged kits to fire projectiles instead of melee DamageService hits.
func _deliver_basic_attack_hit(strike_target: Node3D) -> bool:
	if not DamageService.apply_damage(
		strike_target,
		float(attack_damage),
		self,
		{DamageService.OPT_IS_BASIC_ATTACK: true}
	):
		return false
	MeleeHitSound.play_at(self, strike_target.global_position)
	return true


func _sanitize_move_to_cast_target() -> void:
	if not _has_move_to_cast:
		return
	if not NodeSafety.is_alive_node(_move_to_cast_target):
		cancel_move_to_cast()
		clear_move_target()
		return
	if not CombatTargetValidation.is_valid_combat_target(_move_to_cast_target):
		cancel_move_to_cast()
		clear_move_target()


func _process_move_to_cast(_delta: float) -> void:
	if not _has_move_to_cast or not NodeSafety.is_alive_node(_move_to_cast_target):
		cancel_move_to_cast()
		return

	var definition: HeroAbilityDefinition = get_ability_definition(_move_to_cast_ability_id)
	var required_range: float = attack_range
	if definition != null and definition.cast_range > 0.0:
		required_range = definition.cast_range

	if _horizontal_distance_to(_move_to_cast_target) <= required_range:
		var ability_id: StringName = _move_to_cast_ability_id
		var target: Node3D = _move_to_cast_target
		cancel_move_to_cast()
		clear_move_target()
		try_cast_ability(ability_id, target)
		return

	if not has_move_target:
		_set_move_destination(
			_compute_attack_approach_position(_move_to_cast_target, -1),
			RepathUrgency.PLAYER_ORDER
		)
	super._physics_process(_delta)


func _should_reposition_for_preferred_range() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		_is_backing_off_for_range = false
		return false
	if _is_holding_position:
		_is_backing_off_for_range = false
		return false

	if _is_backing_off_for_range:
		if CombatTargetValidation.is_at_preferred_hold_range(
			self,
			_attack_target,
			attack_range,
			stopping_distance,
			maxi(_attack_approach_slot, 0)
		):
			_is_backing_off_for_range = false
			return false
		return true

	if CombatTargetValidation.is_too_close_for_preferred_range(
		self,
		_attack_target,
		attack_range,
		stopping_distance,
		maxi(_attack_approach_slot, 0)
	):
		_is_backing_off_for_range = true
		return true

	return false


func _play_attack_animation() -> void:
	if _attack_lunge_tween != null and _attack_lunge_tween.is_valid():
		_attack_lunge_tween.kill()

	var lunge_offset := Vector3.ZERO
	if CombatTargetValidation.is_valid_combat_target(_attack_target):
		var direction := _attack_target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			lunge_offset = global_transform.basis.inverse() * (direction.normalized() * ATTACK_LUNGE_DISTANCE)

	_body_mesh.position = _body_mesh_rest_position
	_attack_lunge_tween = create_tween()
	_attack_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position + lunge_offset,
		ATTACK_LUNGE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position,
		ATTACK_LUNGE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func take_damage(amount: float, attacker = null) -> void:
	DamageService.apply(
		self,
		amount,
		attacker,
		{DamageService.OPT_IGNORE_HOSTILITY: true}
	)


func get_current_health() -> int:
	return _health_component.current_health


func _on_health_depleted() -> void:
	## Save progression and clear living-hero registry before UI/selection reacts.
	HeroProgressionStore.save_from_hero(self)
	HeroProgressionStore.clear_living_hero(self)
	if HeroAbilityTargetingController != null:
		HeroAbilityTargetingController.on_hero_died(self)
	if CombatTargetValidation.is_enemy_faction(self):
		HeroXpRewards.notify_unit_killed(self)
		if is_in_group(&"enemy_combat_units"):
			remove_from_group(&"enemy_combat_units")
	EnemyUnitMission.clear_unit_mission(self)
	_health_bar.visible = false
	cancel_attack_move()
	cancel_attack()
	_on_prepare_for_new_player_order()
	clear_move_target()
	die()
	queue_free()


func _exit_tree() -> void:
	HeroProgressionStore.clear_living_hero(self)
	cancel_attack_move()
	cancel_attack()
	_on_prepare_for_new_player_order()
	EnemyUnitMission.clear_unit_mission(self)


func _begin_chase() -> void:
	_update_chase_movement(0.0, true)


func _update_chase_movement(delta: float = 0.0, force: bool = false) -> void:
	if not NodeSafety.is_alive_node(_attack_target):
		cancel_attack()
		return
	if _is_holding_position:
		return
	if _is_in_attack_range(_attack_target):
		return

	if not force and not tick_chase_update_timer(delta, false):
		return

	var approach_position: Vector3 = _compute_attack_approach_position(_attack_target)
	var needs_close_in: bool = _needs_attack_close_in(approach_position)
	if needs_close_in:
		if _should_reclaim_approach_slot(approach_position):
			_reclaim_unreachable_approach_slot()
		approach_position = CombatTargetValidation.compute_attack_close_position(
			self,
			_attack_target,
			attack_range,
			stopping_distance,
			maxi(_attack_approach_slot, 0)
		)

	if _has_chase_target and has_move_target and not needs_close_in:
		var destination_delta: Vector3 = approach_position - _movement_target
		destination_delta.y = 0.0
		if destination_delta.length() < CHASE_TARGET_MOVE_THRESHOLD:
			return

	var urgency: RepathUrgency = (
		RepathUrgency.STUCK_RECOVERY if needs_close_in else RepathUrgency.CHASE
	)
	if _set_move_destination(approach_position, urgency):
		_has_chase_target = true
	elif not has_move_target:
		# Near-skip rejected a tiny remaining gap — force a close-in destination once.
		if needs_close_in or force:
			var close_position: Vector3 = CombatTargetValidation.compute_attack_close_position(
				self,
				_attack_target,
				attack_range,
				stopping_distance,
				maxi(_attack_approach_slot, 0)
			)
			if _set_move_destination(close_position, RepathUrgency.STUCK_RECOVERY):
				_has_chase_target = true
			else:
				_has_chase_target = true
		else:
			_has_chase_target = true


func _needs_attack_close_in(approach_position: Vector3) -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		return false
	if _is_in_attack_range(_attack_target):
		return false
	# Outer-ring slots intentionally sit outside strike reach — do not collapse inward.
	if not _approach_slot_should_enter_strike_range():
		return false

	var to_approach: Vector3 = approach_position - global_position
	to_approach.y = 0.0
	var near_approach: bool = to_approach.length() <= get_soft_arrival_radius() + 0.2

	# Settled near the approach waypoint but still outside strike reach.
	if not has_move_target and near_approach:
		return true

	if has_move_target:
		var remaining: Vector3 = _movement_target - global_position
		remaining.y = 0.0
		if remaining.length() <= get_soft_arrival_radius() + 0.2 and near_approach:
			return true

	if (
		_navigation_agent != null
		and is_instance_valid(_navigation_agent)
		and has_move_target
		and not _navigation_agent.is_target_reachable()
	):
		return true

	return false


func _approach_slot_should_enter_strike_range() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		return false
	var slot_standoff: float = CombatTargetValidation.get_preferred_attack_standoff(
		self,
		_attack_target,
		attack_range,
		stopping_distance,
		maxi(_attack_approach_slot, 0)
	)
	var effective: float = CombatTargetValidation.get_effective_attack_range(attack_range)
	return slot_standoff <= effective + 0.05


func _should_reclaim_approach_slot(_approach_position: Vector3) -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		return false

	# Only rotate slots when the current approach destination is unreachable.
	return (
		_navigation_agent != null
		and is_instance_valid(_navigation_agent)
		and has_move_target
		and not _navigation_agent.is_target_reachable()
	)


func _reclaim_unreachable_approach_slot() -> void:
	if not NodeSafety.is_alive_node(_attack_target):
		return
	_attack_approach_slot = CombatTargetValidation.reclaim_attack_approach_slot(
		_attack_target, self
	)


func _try_attack_move_engagement() -> void:
	if CombatTargetValidation.is_enemy_faction(self) and not EnemyUnitMission.allows_combat_micro(self):
		return

	var search_range: float = maxf(attack_range, ATTACK_MOVE_ENGAGEMENT_RANGE)
	var closest_target: Node3D = CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
		self, search_range
	)
	if closest_target != null:
		_begin_attack_on_target(closest_target, -1, false)


func _should_break_opportunistic_chase() -> bool:
	if not NodeSafety.is_alive_node(_attack_target):
		return true
	var distance: float = CombatTargetValidation.get_horizontal_attack_distance(self, _attack_target)
	if distance > OPPORTUNISTIC_CHASE_LEASH:
		return true
	if _has_attack_move_destination:
		var target_from_dest: Vector3 = _attack_target.global_position - _attack_move_destination
		target_from_dest.y = 0.0
		if target_from_dest.length() > OPPORTUNISTIC_CHASE_LEASH:
			return true
	return false


func _resume_attack_move() -> bool:
	return _resume_attack_move_or_patrol()


func _resume_attack_move_or_patrol() -> bool:
	if _is_patrolling:
		_start_patrol_leg()
		return true

	if not _has_attack_move_destination:
		return false

	if _is_at_attack_move_destination():
		cancel_attack_move()
		notify_order_completed(UnitOrder.Type.ATTACK_MOVE)
		return false

	_has_chase_target = false
	_set_move_destination(_attack_move_destination, RepathUrgency.NORMAL)
	return true


func _is_at_attack_move_destination() -> bool:
	var offset: Vector3 = global_position - _attack_move_destination
	offset.y = 0.0
	return offset.length() <= get_movement_acceptance_radius()


func _should_skip_stuck_recovery() -> bool:
	if _is_holding_position:
		return true
	if _attack_target != null and _is_in_attack_range(_attack_target):
		if not _should_reposition_for_preferred_range():
			return true
	return false


func _is_in_attack_range(target: Variant) -> bool:
	return CombatTargetValidation.is_within_attack_range(self, target, attack_range)


func _horizontal_distance_to(target: Variant) -> float:
	return CombatTargetValidation.get_horizontal_center_distance(self, target)


func _compute_attack_approach_position(target: Node3D, approach_slot: int = -1) -> Vector3:
	var slot_index: int = approach_slot
	if slot_index < 0:
		slot_index = maxi(_attack_approach_slot, 0)
	return CombatTargetValidation.compute_attack_approach_position(
		self, target, attack_range, stopping_distance, slot_index
	)


func _assign_attack_approach_slot(target: Node3D, assigned_slot: int) -> void:
	if assigned_slot >= 0:
		_attack_approach_slot = CombatTargetValidation.reserve_attack_approach_slot(
			target, self, assigned_slot
		)
	elif _attack_target != target:
		_attack_approach_slot = CombatTargetValidation.claim_attack_approach_slot(target, self)
