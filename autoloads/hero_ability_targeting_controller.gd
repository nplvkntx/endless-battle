extends Node

## Shared LoL-style hero ability targeting for player-controlled heroes.
## AI heroes never enter this controller — they call kit try_* directly.

signal targeting_started(hero: Hero, ability_id: StringName)
signal targeting_cancelled(hero: Hero, ability_id: StringName)
signal targeting_confirmed(hero: Hero, ability_id: StringName)
signal targeting_changed()

enum CursorState { NONE, VALID, INVALID }

var _active_hero: Hero = null
var _active_ability_id: StringName = &""
var _active_definition: HeroAbilityDefinition = null
var _preview: HeroAbilityPreview = null
var _hovered_unit: Node3D = null
var _aim_ground: Vector3 = Vector3.ZERO
var _aim_valid: bool = false
var _cursor_state: CursorState = CursorState.NONE
var _holding_for_quick_indicator: bool = false
var _pending_move_to_cast: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MatchSession.register_match_reset(&"HeroAbilityTargetingController", cancel_targeting)
	set_process(false)
	set_process_unhandled_input(true)


func is_targeting() -> bool:
	return _active_definition != null and NodeSafety.is_alive_node(_active_hero)


func get_active_ability_id() -> StringName:
	return _active_ability_id if is_targeting() else &""


func get_active_hero() -> Hero:
	if not is_targeting():
		return null
	return HeroProgressionStore.as_living_hero(_active_hero)


func get_cursor_state() -> CursorState:
	return _cursor_state if is_targeting() else CursorState.NONE


func begin_targeting(hero: Hero, ability_id: StringName) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false
	if CombatTargetValidation.is_enemy_faction(hero):
		return false
	if not hero is MeleeHero:
		return false

	var melee: MeleeHero = hero as MeleeHero
	if not melee.is_ability_unlocked(ability_id):
		_feedback(hero, "Ability locked")
		return false
	if melee.get_ability_cooldown_remaining(ability_id) > 0.0:
		_feedback(hero, "Ability on cooldown")
		return false
	if melee.current_mana < melee.get_ability_mana_cost(ability_id):
		_feedback(hero, "Not enough mana")
		return false

	var definition: HeroAbilityDefinition = melee.get_ability_definition(ability_id)
	if definition == null:
		return false

	var cast_mode: int = get_cast_mode()

	# Instant self / no-target: cast immediately (no arming).
	if definition.is_instant_cast():
		cancel_targeting()
		return _execute_cast(melee, ability_id, null)

	# Quick cast: fire toward current mouse without preview.
	if cast_mode == HeroAbilityDefinition.CastMode.QUICK:
		cancel_targeting()
		return _confirm_from_world_state(melee, ability_id, definition)

	# Switching abilities replaces current targeting mode.
	if is_targeting() and _active_ability_id == ability_id:
		# Same key again: no unsafe quick-confirm by default.
		return true

	_arm(melee, ability_id, definition)
	if cast_mode == HeroAbilityDefinition.CastMode.QUICK_WITH_INDICATOR:
		_holding_for_quick_indicator = true
	return true


func cancel_targeting() -> void:
	var had_targeting: bool = is_targeting()
	var hero_ref: Variant = _active_hero
	var ability_id: StringName = _active_ability_id
	_clear_state()
	if had_targeting:
		## Prefer living hero for signal payload; never assign a freed Object into Hero.
		var hero: Hero = null
		if NodeSafety.is_alive_node(hero_ref) and hero_ref is Hero:
			hero = hero_ref as Hero
		targeting_cancelled.emit(hero, ability_id)
		targeting_changed.emit()


func confirm_at_screen(screen_position: Vector2) -> bool:
	if not is_targeting():
		return false
	if _is_screen_over_ui(screen_position):
		return false

	var hero: MeleeHero = _active_hero as MeleeHero
	var definition: HeroAbilityDefinition = _active_definition
	var ability_id: StringName = _active_ability_id
	if hero == null or definition == null:
		cancel_targeting()
		return false

	_refresh_aim(screen_position)
	if not _aim_valid:
		_feedback(hero, "Invalid target")
		return false

	var payload: Variant = _build_cast_payload(definition)
	_clear_state()
	targeting_confirmed.emit(hero, ability_id)
	targeting_changed.emit()
	return _execute_cast(hero, ability_id, payload)


func try_handle_left_click(screen_position: Vector2) -> bool:
	if not is_targeting():
		return false
	return confirm_at_screen(screen_position)


func try_handle_right_click(_screen_position: Vector2) -> bool:
	if not is_targeting():
		return false
	cancel_targeting()
	return true


func on_selection_changed() -> void:
	if not is_targeting():
		return
	var selection: Node = _find_selection_manager()
	if selection == null:
		cancel_targeting()
		return
	if selection.has_method(&"get_primary_ui_hero"):
		var primary: Hero = HeroProgressionStore.as_living_hero(
			selection.call(&"get_primary_ui_hero")
		)
		if primary != _active_hero:
			cancel_targeting()


func on_hero_died(hero: Variant) -> void:
	var dying: Hero = null
	if hero != null and is_instance_valid(hero) and hero is Hero:
		dying = hero as Hero
	if dying != null:
		HeroProgressionStore.clear_living_hero(dying)
	if is_targeting() and (
		dying == _active_hero or not NodeSafety.is_alive_node(_active_hero)
	):
		cancel_targeting()


func get_cast_mode() -> int:
	if GameSettings != null and GameSettings.has_method(&"get_hero_ability_cast_mode"):
		return int(GameSettings.call(&"get_hero_ability_cast_mode"))
	return HeroAbilityDefinition.CastMode.NORMAL


func _unhandled_input(event: InputEvent) -> void:
	if not is_targeting():
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			cancel_targeting()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and _holding_for_quick_indicator:
		var key_event2 := event as InputEventKey
		if not key_event2.pressed and _is_ability_hotkey(key_event2.keycode):
			confirm_at_screen(get_viewport().get_mouse_position())
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_targeting():
		set_process(false)
		return

	if not NodeSafety.is_alive_node(_active_hero):
		cancel_targeting()
		return

	_refresh_aim(get_viewport().get_mouse_position())
	_update_preview()


func _arm(hero: MeleeHero, ability_id: StringName, definition: HeroAbilityDefinition) -> void:
	_active_hero = hero
	_active_ability_id = ability_id
	_active_definition = definition
	_holding_for_quick_indicator = false
	_ensure_preview()
	InputManager.disarm_attack_move()
	InputManager.disarm_patrol()
	set_process(true)
	_refresh_aim(get_viewport().get_mouse_position())
	_update_preview()
	targeting_started.emit(hero, ability_id)
	targeting_changed.emit()


func _clear_state() -> void:
	_active_hero = null
	_active_ability_id = &""
	_active_definition = null
	_hovered_unit = null
	_aim_valid = false
	_cursor_state = CursorState.NONE
	_holding_for_quick_indicator = false
	if _preview != null and is_instance_valid(_preview):
		_preview.clear()
		_preview.visible = false
	set_process(false)
	_restore_cursor()


func _ensure_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.visible = true
		return
	_preview = HeroAbilityPreview.new()
	_preview.name = "HeroAbilityPreview"
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = self
	parent.add_child(_preview)


func _refresh_aim(screen_position: Vector2) -> void:
	_hovered_unit = null
	_aim_valid = false
	_cursor_state = CursorState.INVALID

	var hero: MeleeHero = _active_hero as MeleeHero
	var definition: HeroAbilityDefinition = _active_definition
	if hero == null or definition == null:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	_aim_ground = _raycast_ground(camera, screen_position)
	var unit: Node3D = _raycast_ability_unit(camera, screen_position)

	match definition.targeting_type:
		HeroAbilityDefinition.TargetingType.CIRCULAR_SELF:
			_aim_valid = true
			_cursor_state = CursorState.VALID
		HeroAbilityDefinition.TargetingType.TARGET_ENEMY, \
		HeroAbilityDefinition.TargetingType.TARGET_UNIT, \
		HeroAbilityDefinition.TargetingType.DASH_TARGET:
			_hovered_unit = unit
			_aim_valid = _is_valid_unit_target(hero, definition, unit)
			_cursor_state = CursorState.VALID if _aim_valid else CursorState.INVALID
		HeroAbilityDefinition.TargetingType.TARGET_ALLY:
			_hovered_unit = unit
			_aim_valid = _is_valid_ally_target(hero, definition, unit)
			_cursor_state = CursorState.VALID if _aim_valid else CursorState.INVALID
		HeroAbilityDefinition.TargetingType.TARGET_GROUND, \
		HeroAbilityDefinition.TargetingType.CIRCULAR_AREA:
			_aim_valid = _is_valid_ground_point(hero, definition, _aim_ground)
			_cursor_state = CursorState.VALID if _aim_valid else CursorState.INVALID
		HeroAbilityDefinition.TargetingType.DIRECTIONAL_LINE, \
		HeroAbilityDefinition.TargetingType.DASH_DIRECTION, \
		HeroAbilityDefinition.TargetingType.CONE:
			_aim_valid = _aim_ground.is_finite()
			if definition.targeting_type == HeroAbilityDefinition.TargetingType.DASH_DIRECTION:
				var endpoint: Vector3 = _compute_dash_endpoint(hero, definition, _aim_ground)
				_aim_valid = _is_valid_dash_endpoint(hero, endpoint)
			_cursor_state = CursorState.VALID if _aim_valid else CursorState.INVALID
		_:
			_aim_valid = false

	_apply_cursor()


func _update_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	var hero: MeleeHero = _active_hero as MeleeHero
	var definition: HeroAbilityDefinition = _active_definition
	if hero == null or definition == null:
		_preview.clear()
		return

	_preview.clear()
	var origin: Vector3 = hero.global_position
	if definition.show_cast_range and definition.cast_range > 0.0:
		_preview.set_cast_range(origin, definition.cast_range, true)

	match definition.targeting_type:
		HeroAbilityDefinition.TargetingType.CIRCULAR_SELF:
			var radius: float = maxf(definition.effect_radius, 0.5)
			_preview.set_aoe_circle(origin, radius, _aim_valid)
		HeroAbilityDefinition.TargetingType.CIRCULAR_AREA, \
		HeroAbilityDefinition.TargetingType.TARGET_GROUND:
			var ground: Vector3 = _clamped_ground(hero, definition, _aim_ground)
			_preview.set_aoe_circle(ground, maxf(definition.effect_radius, 0.4), _aim_valid)
		HeroAbilityDefinition.TargetingType.DIRECTIONAL_LINE:
			var end_point: Vector3 = _line_endpoint(hero, definition, _aim_ground)
			_preview.set_line(
				origin,
				end_point,
				maxf(definition.line_width, 0.2),
				_aim_valid,
				true
			)
		HeroAbilityDefinition.TargetingType.DASH_DIRECTION:
			var dash_end: Vector3 = _compute_dash_endpoint(hero, definition, _aim_ground)
			_preview.set_line(origin, dash_end, 0.35, _aim_valid, true)
			_preview.set_endpoint(dash_end, 0.45, _aim_valid)
		HeroAbilityDefinition.TargetingType.CONE:
			var cone_end: Vector3 = _line_endpoint(hero, definition, _aim_ground)
			_preview.set_line(origin, cone_end, maxf(definition.line_width, 0.5), _aim_valid, true)
		HeroAbilityDefinition.TargetingType.TARGET_ENEMY, \
		HeroAbilityDefinition.TargetingType.TARGET_UNIT, \
		HeroAbilityDefinition.TargetingType.TARGET_ALLY, \
		HeroAbilityDefinition.TargetingType.DASH_TARGET:
			if NodeSafety.is_alive_node(_hovered_unit):
				_preview.set_target_highlight(_hovered_unit, _aim_valid)
				_preview.set_target_line(origin, _hovered_unit.global_position, _aim_valid)


func _build_cast_payload(definition: HeroAbilityDefinition) -> Variant:
	match definition.targeting_type:
		HeroAbilityDefinition.TargetingType.CIRCULAR_SELF, \
		HeroAbilityDefinition.TargetingType.INSTANT_SELF, \
		HeroAbilityDefinition.TargetingType.NO_TARGET:
			return null
		HeroAbilityDefinition.TargetingType.TARGET_ENEMY, \
		HeroAbilityDefinition.TargetingType.TARGET_UNIT, \
		HeroAbilityDefinition.TargetingType.TARGET_ALLY, \
		HeroAbilityDefinition.TargetingType.DASH_TARGET:
			return _hovered_unit
		HeroAbilityDefinition.TargetingType.TARGET_GROUND, \
		HeroAbilityDefinition.TargetingType.CIRCULAR_AREA:
			return _clamped_ground(_active_hero as MeleeHero, definition, _aim_ground)
		HeroAbilityDefinition.TargetingType.DIRECTIONAL_LINE, \
		HeroAbilityDefinition.TargetingType.CONE, \
		HeroAbilityDefinition.TargetingType.DASH_DIRECTION:
			return _clamped_ground(_active_hero as MeleeHero, definition, _aim_ground)
		_:
			return null


func _confirm_from_world_state(
	hero: MeleeHero, ability_id: StringName, definition: HeroAbilityDefinition
) -> bool:
	_active_hero = hero
	_active_ability_id = ability_id
	_active_definition = definition
	_refresh_aim(get_viewport().get_mouse_position())
	if not _aim_valid:
		_clear_state()
		_feedback(hero, "Invalid target")
		return false
	var payload: Variant = _build_cast_payload(definition)
	_clear_state()
	return _execute_cast(hero, ability_id, payload)


func _execute_cast(hero: MeleeHero, ability_id: StringName, payload: Variant) -> bool:
	if not NodeSafety.is_alive_node(hero):
		return false

	var definition: HeroAbilityDefinition = hero.get_ability_definition(ability_id)
	if definition != null and definition.is_unit_targeted() and payload is Node3D:
		var target: Node3D = payload as Node3D
		if not _is_valid_unit_target(hero, definition, target) and not _is_valid_ally_target(
			hero, definition, target
		):
			_feedback(hero, "Invalid target")
			return false
		if definition.allows_move_to_cast and definition.cast_range > 0.0:
			var distance: float = _horizontal_distance(hero.global_position, target.global_position)
			if distance > definition.cast_range:
				hero.begin_move_to_cast(ability_id, target)
				return true

	var cast_ok: bool = hero.try_cast_ability(ability_id, payload)
	if cast_ok:
		_play_cast_confirm_fx(hero)
	return cast_ok


func _is_valid_unit_target(
	hero: MeleeHero, definition: HeroAbilityDefinition, target: Node3D
) -> bool:
	if not NodeSafety.is_alive_node(target):
		return false
	if definition.requires_living_target and not CombatTargetValidation.is_valid_combat_target(target):
		return false
	if StealthService.is_combat_hidden(target) and not CombatTargetValidation.is_enemy_faction(hero):
		# Player cannot target stealthed hostiles they don't already have locked.
		if hero.get_attack_target() != target:
			return false
	if target is Building and not definition.can_target_buildings:
		return false
	if CombatTargetValidation.is_neutral_creep(target) and not definition.can_target_creeps:
		return false

	var hostile: bool = CombatTargetValidation.are_hostile(hero, target)
	if hostile and not definition.can_target_enemies:
		return false
	if not hostile and not definition.can_target_allies:
		# Same-faction non-hostile
		if target == hero:
			return definition.can_target_allies
		return false

	if not CombatTargetValidation.is_hero_unit_ability_target(hero, target):
		if not (definition.can_target_buildings and target is Building):
			return false

	if definition.cast_range > 0.0 and not definition.allows_move_to_cast:
		if _horizontal_distance(hero.global_position, target.global_position) > definition.cast_range:
			return false

	# Soft out-of-range: still valid if move-to-cast allowed (show as valid when clickable).
	if definition.cast_range > 0.0 and definition.allows_move_to_cast:
		# Allow selecting beyond cast range only within a reasonable acquisition leash.
		var leash: float = maxf(definition.cast_range * 2.5, definition.cast_range + 8.0)
		if _horizontal_distance(hero.global_position, target.global_position) > leash:
			return false

	return true


func _is_valid_ally_target(
	hero: MeleeHero, definition: HeroAbilityDefinition, target: Node3D
) -> bool:
	if not definition.can_target_allies:
		return false
	if not NodeSafety.is_alive_node(target):
		return false
	if CombatTargetValidation.are_hostile(hero, target):
		return false
	return true


func _is_valid_ground_point(
	hero: MeleeHero, definition: HeroAbilityDefinition, ground: Vector3
) -> bool:
	if not ground.is_finite():
		return false
	if definition.cast_range <= 0.0:
		return true
	if definition.clamps_ground_to_range:
		return true
	return _horizontal_distance(hero.global_position, ground) <= definition.cast_range + 0.05


func _is_valid_dash_endpoint(hero: MeleeHero, endpoint: Vector3) -> bool:
	if not endpoint.is_finite():
		return false
	var snapped: Vector3 = hero.snap_ability_navigation_point(endpoint)
	var delta: Vector3 = snapped - endpoint
	delta.y = 0.0
	# If navigation pulls the point very far, treat as blocked.
	return delta.length() <= 1.25


func _clamped_ground(
	hero: MeleeHero, definition: HeroAbilityDefinition, ground: Vector3
) -> Vector3:
	if hero == null or not ground.is_finite():
		return hero.global_position if hero != null else Vector3.ZERO
	if definition.cast_range <= 0.0 or not definition.clamps_ground_to_range:
		return Vector3(ground.x, 0.0, ground.z)

	var offset: Vector3 = ground - hero.global_position
	offset.y = 0.0
	if offset.length() > definition.cast_range:
		offset = offset.normalized() * definition.cast_range
	var clamped: Vector3 = hero.global_position + offset
	clamped.y = 0.0
	return clamped


func _line_endpoint(
	hero: MeleeHero, definition: HeroAbilityDefinition, ground: Vector3
) -> Vector3:
	var travel: float = definition.max_travel_distance
	if travel <= 0.0:
		travel = definition.cast_range
	var direction: Vector3 = ground - hero.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = -hero.global_transform.basis.z
		direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	return hero.global_position + direction * travel


func _compute_dash_endpoint(
	hero: MeleeHero, definition: HeroAbilityDefinition, ground: Vector3
) -> Vector3:
	var desired: Vector3 = _line_endpoint(hero, definition, ground)
	return hero.snap_ability_navigation_point(desired)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var delta: Vector3 = b - a
	delta.y = 0.0
	return delta.length()


func _raycast_ground(camera: Camera3D, screen_position: Vector2) -> Vector3:
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var dir: Vector3 = camera.project_ray_normal(screen_position)
	if absf(dir.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var distance: float = -from.y / dir.y
	if distance < 0.0:
		return Vector3(INF, INF, INF)
	var hit: Vector3 = from + dir * distance
	return Vector3(hit.x, 0.0, hit.z)


func _raycast_ability_unit(camera: Camera3D, screen_position: Vector2) -> Node3D:
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	if space == null:
		return null
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var to: Vector3 = from + camera.project_ray_normal(screen_position) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PhysicsLayers.UNITS | PhysicsLayers.BUILDINGS
	query.collide_with_areas = false
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return null
	var collider: Variant = result.get("collider")
	if not collider is Node:
		return null
	var node: Node = collider as Node
	while node != null:
		if node is Unit or node is Hero or node is Building:
			return node as Node3D
		node = node.get_parent()
	return null


func _apply_cursor() -> void:
	match _cursor_state:
		CursorState.VALID:
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		CursorState.INVALID:
			Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
		_:
			_restore_cursor()


func _restore_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _play_cast_confirm_fx(hero: MeleeHero) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if ImpactEffects != null:
		ImpactEffects.play_ground_impact(hero.global_position, 0.55)


func _feedback(hero: Hero, message: String) -> void:
	if hero == null:
		return
	if CombatTargetValidation.is_enemy_faction(hero):
		return
	if ResourceManager != null:
		ResourceManager.show_feedback(message)


func _is_screen_over_ui(screen_position: Vector2) -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	var hovered: Control = viewport.gui_get_hovered_control()
	return hovered != null


func _is_ability_hotkey(keycode: int) -> bool:
	return keycode == KEY_Q or keycode == KEY_W or keycode == KEY_E or keycode == KEY_R


func _find_selection_manager() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var root: Node = tree.current_scene
	if root == null:
		return null
	return root.find_child("SelectionManager", true, false)
