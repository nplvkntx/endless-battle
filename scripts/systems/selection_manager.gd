extends Node

## Handles unit selection through left-click and drag-box selection.

signal selection_changed(units: Array[Unit])
signal building_selection_changed(building: Building)
signal inspection_changed(unit: Unit, building: Building)

const DRAG_THRESHOLD_PIXELS: float = 4.0
const DOUBLE_CLICK_TIME_SECONDS: float = 0.3
const UNIT_GROUP: StringName = &"units"
const SELECTION_TYPE_WORKER: StringName = &"worker"
const SELECTION_TYPE_SPEARMAN: StringName = &"spearman"
const SELECTION_TYPE_SWORDSMAN: StringName = &"swordsman"
const SELECTION_TYPE_ARCHER: StringName = &"archer"
const SELECTION_TYPE_HEAVY_CAVALRY: StringName = &"heavy_cavalry"
const SELECTION_TYPE_LIGHT_CAVALRY: StringName = &"light_cavalry"
const SELECTION_TYPE_CAVALRY_ARCHER: StringName = &"cavalry_archer"
const SELECTION_TYPE_CANNON: StringName = &"cannon"
const SELECTION_TYPE_HERO: StringName = &"hero"
const MULTI_SELECTION_WORKERS: StringName = &"workers"
const MULTI_SELECTION_COMBAT: StringName = &"combat"
const MULTI_SELECTION_MIXED: StringName = &"mixed"
const MULTI_SELECTION_OTHER: StringName = &"other"

@export var camera_path: NodePath = "../Camera3D"
@export var selection_box_path: NodePath = "../SelectionUI/SelectionBox"

var selected_units: Array[Unit] = []
var selected_building: Building = null
var inspected_unit: Unit = null
var inspected_building: Building = null
var inspected_resource: GatherableResource = null
## Source-of-truth selection identity. Resolved caches above are refreshed from these.
var _selected_unit_handles: Array[EntityHandle] = []
var _selected_building_handle: EntityHandle = EntityHandle.empty()
var _inspected_unit_handle: EntityHandle = EntityHandle.empty()
var _inspected_building_handle: EntityHandle = EntityHandle.empty()
var _unit_tree_exiting_handlers: Dictionary = {}
var _inspected_building_destroyed_handler: Callable = Callable()
var _selected_building_destroyed_handler: Callable = Callable()
var _selected_building_tree_exiting_handler: Callable = Callable()
var _selection_purge_timer: float = 0.0
const SELECTION_PURGE_INTERVAL := 0.1


## Sole owner of selected-entity handles. UI should query these / resolved getters.
func get_selected_unit_handles() -> Array[EntityHandle]:
	_purge_invalid_selected_units()
	return _selected_unit_handles.duplicate()


func get_selected_building_handle() -> EntityHandle:
	_purge_invalid_selected_building()
	return _selected_building_handle.duplicate_handle()


func get_valid_selected_building() -> Building:
	_purge_invalid_selected_building()
	return selected_building


func get_valid_selected_units() -> Array[Unit]:
	_purge_invalid_selected_units()
	return selected_units.duplicate()


func get_multi_unit_selection_category() -> StringName:
	return get_multi_selection_ui_info().category


## Single-pass summary for multi-unit HUD and command panels.
func get_multi_selection_ui_info() -> Dictionary:
	_purge_invalid_selected_units()
	var count: int = selected_units.size()
	var primary_hero: Hero = null
	var has_worker: bool = false
	var has_combat: bool = false
	var category: StringName = &""

	for unit_variant: Variant in selected_units:
		if not _is_commandable_unit(unit_variant):
			continue
		if primary_hero == null:
			var as_hero: Hero = HeroProgressionStore.as_living_hero(unit_variant)
			if as_hero != null:
				primary_hero = as_hero
		if count <= 1:
			continue
		if unit_variant is Worker:
			has_worker = true
		elif _is_combat_order_unit(unit_variant):
			has_combat = true
		else:
			category = MULTI_SELECTION_OTHER
			break

	if count > 1 and category != MULTI_SELECTION_OTHER:
		if has_worker and has_combat:
			category = MULTI_SELECTION_MIXED
		elif has_worker:
			category = MULTI_SELECTION_WORKERS
		elif has_combat:
			category = MULTI_SELECTION_COMBAT
		else:
			category = MULTI_SELECTION_OTHER

	return {"count": count, "category": category, "primary_hero": primary_hero}


func has_commandable_selected_units() -> bool:
	_purge_invalid_selected_units()
	for unit_ref: Variant in selected_units:
		if _is_commandable_unit(unit_ref):
			return true
	return false


func get_primary_ui_hero() -> Hero:
	return HeroProgressionStore.as_living_hero(get_multi_selection_ui_info().get("primary_hero"))


## Units + optional building currently selected, for control-group assign/add.
func get_control_group_members() -> Array:
	_purge_invalid_selection()
	var members: Array = []
	for unit_ref: Variant in selected_units:
		if _is_commandable_unit(unit_ref):
			members.append(unit_ref)
	if _is_selectable_building(selected_building):
		members.append(selected_building)
	return members


## Apply a recalled control group (units preferred; otherwise first building).
func apply_control_group_selection(members: Array) -> void:
	var units: Array[Unit] = []
	var building: Building = null
	for entry: Variant in members:
		if entry is Unit and _is_selectable_unit(entry):
			units.append(entry as Unit)
		elif entry is Building and _is_selectable_building(entry) and building == null:
			building = entry as Building

	if not units.is_empty():
		_set_selected_units(units)
		# Ensure command panel refreshes even if membership matched.
		selection_changed.emit(selected_units)
		return

	if building != null:
		_set_selected_building(building)
		building_selection_changed.emit(selected_building)


func focus_camera_on_current_selection() -> void:
	var camera: Camera3D = _get_camera()
	if camera == null or not camera.has_method("focus_on_world_position"):
		return

	_purge_invalid_selection()
	var positions: Array[Vector3] = []
	for unit_ref: Variant in selected_units:
		if not _is_selectable_unit(unit_ref):
			continue
		positions.append((unit_ref as Unit).global_position)
	if _is_selectable_building(selected_building):
		positions.append(selected_building.global_position)

	if positions.is_empty():
		return

	var centroid := Vector3.ZERO
	for position: Vector3 in positions:
		centroid += position
	centroid /= float(positions.size())
	camera.focus_on_world_position(centroid)


func select_player_hero_and_focus() -> bool:
	var hero: Hero = _find_player_hero()
	if hero == null:
		return false
	_set_selected_units([hero])
	focus_camera_on_current_selection()
	return true


func select_next_idle_worker_and_focus() -> bool:
	var idle_workers: Array[Worker] = collect_idle_player_workers()
	if idle_workers.is_empty():
		return false

	var start_index: int = 0
	if selected_units.size() == 1 and selected_units[0] is Worker:
		var current_index: int = idle_workers.find(selected_units[0] as Worker)
		if current_index >= 0:
			start_index = (current_index + 1) % idle_workers.size()

	var worker: Worker = idle_workers[start_index]
	_set_selected_units([worker])
	focus_camera_on_current_selection()
	return true


func collect_idle_player_workers() -> Array[Worker]:
	var idle_workers: Array[Worker] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return idle_workers

	for node: Node in tree.get_nodes_in_group(&"workers"):
		var worker := node as Worker
		if worker == null:
			continue
		if not worker.is_player_idle():
			continue
		idle_workers.append(worker)
	return idle_workers


func count_idle_player_workers() -> int:
	return collect_idle_player_workers().size()


func _find_player_hero() -> Hero:
	var registered: Hero = HeroProgressionStore.get_living_hero(false)
	if registered != null and _is_commandable_unit(registered):
		return registered

	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	for node_variant: Variant in tree.get_nodes_in_group(&"heroes"):
		var hero: Hero = HeroProgressionStore.as_living_hero(node_variant)
		if hero == null:
			continue
		if hero.is_in_group(&"enemies"):
			continue
		if CombatTargetValidation.is_enemy_faction(hero):
			continue
		if not _is_commandable_unit(hero):
			continue
		HeroProgressionStore.register_living_hero(hero)
		return hero

	for node_variant: Variant in tree.get_nodes_in_group(UNIT_GROUP):
		var hero: Hero = HeroProgressionStore.as_living_hero(node_variant)
		if hero == null:
			continue
		if not _is_commandable_unit(hero):
			continue
		HeroProgressionStore.register_living_hero(hero)
		return hero

	return null


var _left_button_down: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _last_clicked_unit_handle: EntityHandle = EntityHandle.empty()
var _last_click_time_msec: int = -1


func _unhandled_input(event: InputEvent) -> void:
	# Ability targeting consumes world clicks before selection / orders.
	if HeroAbilityTargetingController != null and HeroAbilityTargetingController.is_targeting():
		if event is InputEventMouseButton:
			var mouse_button := event as InputEventMouseButton
			if mouse_button.pressed:
				match mouse_button.button_index:
					MOUSE_BUTTON_LEFT:
						if HeroAbilityTargetingController.try_handle_left_click(mouse_button.position):
							get_viewport().set_input_as_handled()
							return
					MOUSE_BUTTON_RIGHT:
						if HeroAbilityTargetingController.try_handle_right_click(mouse_button.position):
							get_viewport().set_input_as_handled()
							return

	# Avoid scanning large selections on every mouse-move frame.
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_S:
					if _dispatch_stop_command():
						get_viewport().set_input_as_handled()
						return
				KEY_H:
					if _dispatch_hold_position_command():
						get_viewport().set_input_as_handled()
						return
	if event is InputEventMouseButton:
		_purge_invalid_selection()
		var mouse_button := event as InputEventMouseButton
		match mouse_button.button_index:
			MOUSE_BUTTON_LEFT:
				if mouse_button.pressed:
					_on_left_press(mouse_button.position)
				else:
					_on_left_release(mouse_button.position)
			MOUSE_BUTTON_RIGHT:
				if mouse_button.pressed:
					_handle_right_click(mouse_button.position)
	elif event is InputEventMouseMotion and _left_button_down:
		_on_mouse_motion((event as InputEventMouseMotion).position)


func _on_left_press(screen_position: Vector2) -> void:
	_left_button_down = true
	_drag_start = screen_position
	_is_dragging = false


func _on_mouse_motion(screen_position: Vector2) -> void:
	var selection_box := _get_selection_box()
	if selection_box == null:
		return

	if _is_dragging:
		selection_box.update_drag(screen_position)
		return

	if _drag_start.distance_to(screen_position) < DRAG_THRESHOLD_PIXELS:
		return

	_is_dragging = true
	selection_box.begin_drag(_drag_start)
	selection_box.update_drag(screen_position)


func _on_left_release(screen_position: Vector2) -> void:
	_left_button_down = false

	if _is_dragging:
		var selection_box := _get_selection_box()
		if selection_box:
			selection_box.end_drag()
		_is_dragging = false
		_finish_drag_selection(screen_position)
		return

	_handle_left_click(screen_position)


func _finish_drag_selection(screen_position: Vector2) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	var selection_rect := _make_screen_rect(_drag_start, screen_position)
	var units := _get_units_in_rect(camera, selection_rect)
	if Input.is_key_pressed(KEY_SHIFT) and not units.is_empty():
		_merge_units_into_selection(units)
	else:
		_set_selected_units(units)
	_reset_click_tracking()


func _handle_left_click(screen_position: Vector2) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	var unit: Unit = _raycast_unit(camera, screen_position)
	var building: Building = _raycast_building(camera, screen_position)
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
	var ctrl_held: bool = Input.is_key_pressed(KEY_CTRL)

	if unit != null and building != null:
		var unit_distance: float = _raycast_hit_distance(
			camera, screen_position, PhysicsLayers.UNITS
		)
		var building_distance: float = _raycast_hit_distance(
			camera, screen_position, PhysicsLayers.BUILDINGS
		)
		if building_distance < unit_distance:
			if _is_inspectable_building(building):
				_set_inspected_building(building)
				_reset_click_tracking()
				return
			if _is_selectable_building(building):
				_set_selected_building(building)
				_reset_click_tracking()
				return
		elif _is_inspectable_unit(unit):
			_set_inspected_unit(unit)
			_reset_click_tracking()
			return
		elif _is_selectable_unit(unit):
			_apply_unit_left_click(unit, camera, shift_held, ctrl_held)
			return

	if unit:
		if _is_inspectable_unit(unit):
			_set_inspected_unit(unit)
			_reset_click_tracking()
			return
		if _is_selectable_unit(unit):
			_apply_unit_left_click(unit, camera, shift_held, ctrl_held)
			return

	if building != null:
		if _is_inspectable_building(building):
			_set_inspected_building(building)
			_reset_click_tracking()
			return
		_set_selected_building(building)
		_reset_click_tracking()
		return

	var resource: GatherableResource = _raycast_gatherable_resource(camera, screen_position)
	if resource != null:
		_set_inspected_resource(resource)
		_reset_click_tracking()
		return

	if InputManager.attack_move_armed and has_commandable_selected_units():
		var attack_move_position: Vector3 = _raycast_ground_plane(camera, screen_position)
		if attack_move_position.is_finite():
			_dispatch_attack_move_command(attack_move_position, Input.is_key_pressed(KEY_SHIFT))
			InputManager.disarm_all_command_modes()
			return

	if InputManager.patrol_armed and has_commandable_selected_units():
		var patrol_position: Vector3 = _raycast_ground_plane(camera, screen_position)
		if patrol_position.is_finite():
			_dispatch_patrol_command(patrol_position, Input.is_key_pressed(KEY_SHIFT))
			if not Input.is_key_pressed(KEY_SHIFT):
				InputManager.disarm_patrol()
			return

	_clear_selection()
	_clear_building_selection()
	_clear_inspection()
	_reset_click_tracking()


func _apply_unit_left_click(
	unit: Unit, camera: Camera3D, shift_held: bool, ctrl_held: bool
) -> void:
	if shift_held and not ctrl_held:
		_toggle_unit_in_selection(unit)
		_record_click(unit)
		return

	if ctrl_held or _is_double_click(unit):
		_select_all_visible_same_type(unit, camera)
		_record_click(unit)
		return

	_set_selected_units([unit])
	_record_click(unit)


func _toggle_unit_in_selection(unit: Unit) -> void:
	if not _is_selectable_unit(unit):
		return

	if selected_units.has(unit):
		_remove_unit_from_selection(unit, true)
		return

	_merge_units_into_selection([unit])


func _merge_units_into_selection(units: Array[Unit]) -> void:
	var next_units: Array[Unit] = selected_units.duplicate()
	var existing_ids: Dictionary = {}
	for existing: Unit in next_units:
		existing_ids[existing.get_instance_id()] = true

	for unit: Unit in units:
		if not _is_selectable_unit(unit):
			continue
		var unit_id: int = unit.get_instance_id()
		if existing_ids.has(unit_id):
			continue
		existing_ids[unit_id] = true
		next_units.append(unit)

	_set_selected_units(next_units)


func _is_shift_queue() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


func _handle_right_click(screen_position: Vector2) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return

	_purge_invalid_selected_building()
	var selected_building_ref: Variant = selected_building
	if NodeSafety.is_alive_node(selected_building_ref) and selected_building_ref is Building:
		var building: Building = selected_building_ref as Building

		if building is CommandCenter:
			var command_center: CommandCenter = building as CommandCenter
			var rally_gold_mine: GoldMine = _raycast_gold_mine(camera, screen_position)
			if rally_gold_mine != null:
				command_center.set_rally_resource(rally_gold_mine)
				return

			var rally_tree: WoodTree = _raycast_tree(camera, screen_position)
			if rally_tree != null:
				command_center.set_rally_resource(rally_tree)
				return

			var rally_ground_position: Vector3 = _raycast_ground_plane(camera, screen_position)
			if rally_ground_position.is_finite():
				command_center.set_rally_point(rally_ground_position)
			return

		if building is Barracks:
			var barracks_rally_position: Vector3 = _raycast_ground_plane(camera, screen_position)
			if barracks_rally_position.is_finite():
				(building as Barracks).set_rally_point(barracks_rally_position)
			return

		if building is HeroAltar:
			var hero_altar_rally_position: Vector3 = _raycast_ground_plane(camera, screen_position)
			if hero_altar_rally_position.is_finite():
				(building as HeroAltar).set_rally_point(hero_altar_rally_position)
			return

		if building is Stable:
			var stable_rally_position: Vector3 = _raycast_ground_plane(camera, screen_position)
			if stable_rally_position.is_finite():
				(building as Stable).set_rally_point(stable_rally_position)
			return

		if building is ArtilleryDepot:
			var depot_rally_position: Vector3 = _raycast_ground_plane(camera, screen_position)
			if depot_rally_position.is_finite():
				(building as ArtilleryDepot).set_rally_point(depot_rally_position)
			return

	if selected_units.is_empty():
		return

	_purge_invalid_selected_units()
	if selected_units.is_empty():
		return

	var queued: bool = _is_shift_queue()

	var clicked_unit: Unit = _raycast_unit(camera, screen_position)
	if (
		clicked_unit != null
		and CombatTargetValidation.is_player_unit_attack_target(clicked_unit)
	):
		_dispatch_attack_command(clicked_unit, queued)
		return

	var clicked_building: Building = _raycast_building(camera, screen_position)
	if (
		clicked_building != null
		and CombatTargetValidation.is_attackable_enemy_building(clicked_building)
	):
		_dispatch_attack_command(clicked_building, queued)
		return

	if (
		clicked_building != null
		and _is_unfinished_player_construction(clicked_building)
	):
		_dispatch_construction_command(clicked_building, queued)
		return

	var gold_mine: GoldMine = _raycast_gold_mine(camera, screen_position)
	if gold_mine != null:
		_dispatch_gold_mine_gather_command(gold_mine, queued)
		return

	var ground_position: Vector3 = _raycast_ground_plane(camera, screen_position)
	if not ground_position.is_finite():
		return

	if InputManager.patrol_armed:
		_dispatch_patrol_command(ground_position, queued)
		if not queued:
			InputManager.disarm_patrol()
		return

	if InputManager.attack_move_armed:
		_dispatch_attack_move_command(ground_position, queued)
		InputManager.disarm_all_command_modes()
		return

	InputManager.disarm_all_command_modes()
	_dispatch_move_command(ground_position, queued)


func _dispatch_move_command(ground_position: Vector3, queued: bool = false) -> void:
	_purge_invalid_selected_units()
	var commandable_units := _get_commandable_selected_units()
	if commandable_units.is_empty():
		return

	# Formation-aware destinations when any selected military unit is formed.
	if FormationManager.issue_formation_ground_order(
		commandable_units,
		ground_position,
		&"move",
		queued
	):
		CommandFeedback.show_move_marker(ground_position)
		return

	# PlayerRouteNavigation — single or multi unit strategic group move.
	var custom_result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		commandable_units,
		ground_position,
		&"move",
		queued
	)
	if custom_result.get("handled", false):
		CommandFeedback.show_move_marker(
			custom_result.get("accepted_destination", ground_position) as Vector3
		)
		return

	# Last-resort: spaced per-unit orders (Unit uses custom direct locomotion).
	commandable_units.sort_custom(_compare_units_by_instance_id)
	var move_targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
		ground_position,
		commandable_units.size()
	)
	for index: int in commandable_units.size():
		var unit: Unit = commandable_units[index]
		if unit is Worker and not queued:
			(unit as Worker).cancel_gathering()
		unit.issue_order(UnitOrder.move(move_targets[index]), queued)

	# Marker at accepted command point (click destination), not per-unit spacing slots.
	CommandFeedback.show_move_marker(ground_position)


func _compare_units_by_instance_id(a: Unit, b: Unit) -> bool:
	return a.get_instance_id() < b.get_instance_id()


func _dispatch_attack_command(target: Node3D, queued: bool = false) -> void:
	if not CombatTargetValidation.is_player_unit_attack_target(target):
		return

	InputManager.disarm_all_command_modes()
	_purge_invalid_selected_units()
	var military_units: Array[Unit] = []
	for unit_ref: Variant in selected_units:
		if not _is_commandable_unit(unit_ref):
			continue
		var unit: Unit = unit_ref as Unit
		if _is_combat_order_unit(unit):
			military_units.append(unit)

	if military_units.is_empty():
		return

	military_units.sort_custom(_compare_units_by_instance_id)
	var approach_slots: Dictionary = FormationManager.compute_attack_approach_slots(
		military_units,
		target
	)
	for index: int in military_units.size():
		var unit: Unit = military_units[index]
		# Approach slots keep backline protection; attack target remains shared.
		if approach_slots.has(unit.get_instance_id()):
			var approach: Vector3 = approach_slots[unit.get_instance_id()] as Vector3
			if _horizontal_distance_xz(unit.global_position, approach) > 1.5:
				unit.issue_order(UnitOrder.move(approach), queued)
				unit.issue_order(UnitOrder.attack(target, index), true)
				continue
		unit.issue_order(UnitOrder.attack(target, index), queued)

	_play_attack_target_feedback(target)

func _dispatch_attack_move_command(ground_position: Vector3, queued: bool = false) -> void:
	_purge_invalid_selected_units()
	var commandable_units := _get_commandable_selected_units()
	if commandable_units.is_empty():
		return

	if FormationManager.issue_formation_ground_order(
		commandable_units,
		ground_position,
		&"attack_move",
		queued
	):
		CommandFeedback.show_attack_move_marker(ground_position)
		return

	var custom_result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		commandable_units,
		ground_position,
		&"attack_move",
		queued
	)
	if custom_result.get("handled", false):
		var any_combat := false
		for unit: Unit in commandable_units:
			if _is_combat_order_unit(unit):
				any_combat = true
				break
		if any_combat:
			CommandFeedback.show_attack_move_marker(
				custom_result.get("accepted_destination", ground_position) as Vector3
			)
		else:
			CommandFeedback.show_move_marker(
				custom_result.get("accepted_destination", ground_position) as Vector3
			)
		return

	commandable_units.sort_custom(_compare_units_by_instance_id)
	var move_targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
		ground_position,
		commandable_units.size()
	)
	var issued_attack_move := false
	for index: int in commandable_units.size():
		var unit: Unit = commandable_units[index]
		if _is_combat_order_unit(unit):
			unit.issue_order(UnitOrder.attack_move(move_targets[index]), queued)
			issued_attack_move = true
		else:
			# Mixed selection: non-combat units receive a compatible move.
			if unit is Worker and not queued:
				(unit as Worker).cancel_gathering()
			unit.issue_order(UnitOrder.move(move_targets[index]), queued)

	if issued_attack_move:
		CommandFeedback.show_attack_move_marker(ground_position)
	else:
		CommandFeedback.show_move_marker(ground_position)


func _dispatch_patrol_command(ground_position: Vector3, queued: bool = false) -> void:
	_purge_invalid_selected_units()
	var commandable_units := _get_commandable_selected_units()
	if commandable_units.is_empty():
		return

	if FormationManager.issue_formation_ground_order(
		commandable_units,
		ground_position,
		&"patrol",
		queued
	):
		CommandFeedback.show_patrol_marker(ground_position)
		return

	if not queued:
		var custom_result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
			commandable_units,
			ground_position,
			&"patrol",
			false
		)
		if custom_result.get("handled", false):
			CommandFeedback.show_patrol_marker(
				custom_result.get("accepted_destination", ground_position) as Vector3
			)
			return

	commandable_units.sort_custom(_compare_units_by_instance_id)
	var move_targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
		ground_position,
		commandable_units.size()
	)
	var issued_patrol := false
	for index: int in commandable_units.size():
		var unit: Unit = commandable_units[index]
		if not unit.supports_patrol():
			# Compatible fallback for mixed selections.
			unit.issue_order(UnitOrder.move(move_targets[index]), queued)
			continue

		if queued and unit.get_active_order() != null and unit.get_active_order().type == UnitOrder.Type.PATROL:
			unit.append_patrol_point(move_targets[index])
			issued_patrol = true
			continue

		var points: Array[Vector3] = [unit.global_position, move_targets[index]]
		unit.issue_order(UnitOrder.patrol(points), queued)
		issued_patrol = true

	if issued_patrol:
		CommandFeedback.show_patrol_marker(ground_position)
	else:
		CommandFeedback.show_move_marker(ground_position)


func _dispatch_hold_position_command() -> bool:
	_purge_invalid_selected_units()
	var commandable_units := _get_commandable_selected_units()
	if commandable_units.is_empty():
		return false

	InputManager.disarm_all_command_modes()
	var any_dispatched := false
	for unit: Unit in commandable_units:
		if unit.supports_hold_position():
			unit.issue_order(UnitOrder.hold_position(), false)
			any_dispatched = true
	return any_dispatched


func _dispatch_stop_command() -> bool:
	_purge_invalid_selected_units()
	var commandable_units := _get_commandable_selected_units()
	if commandable_units.is_empty():
		return false

	InputManager.disarm_all_command_modes()
	for unit: Unit in commandable_units:
		if unit is Worker:
			(unit as Worker).cancel_gathering()
		unit.issue_stop()
	return true


func _dispatch_construction_command(building: Building, queued: bool = false) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not _is_unfinished_player_construction(building):
		return

	if building is WallSegment:
		_dispatch_wall_chain_construction_command(building as WallSegment, queued)
		return

	InputManager.disarm_all_command_modes()
	_purge_invalid_selected_units()
	var dispatched_to_worker := false
	for unit_ref: Variant in selected_units:
		if not _is_commandable_unit(unit_ref):
			continue
		var unit: Unit = unit_ref as Unit
		if unit is Worker:
			unit.issue_order(UnitOrder.build(building), queued)
			dispatched_to_worker = true
		elif _is_combat_order_unit(unit) and not queued:
			unit.cancel_attack()

	if dispatched_to_worker:
		_play_construction_target_feedback(building)


func _dispatch_wall_chain_construction_command(clicked_segment: WallSegment, queued: bool = false) -> void:
	if not NodeSafety.is_alive_node(clicked_segment):
		return

	var segments: Array[Building] = WallSegment.collect_unfinished_chain_segments(
		clicked_segment
	)
	if segments.is_empty():
		return

	InputManager.disarm_all_command_modes()
	_purge_invalid_selected_units()

	var workers: Array[Worker] = []
	for unit_ref: Variant in selected_units:
		if not _is_commandable_unit(unit_ref):
			continue
		if unit_ref is Worker:
			workers.append(unit_ref as Worker)

	if workers.is_empty():
		return

	if queued:
		for worker_ref: Variant in workers:
			if not NodeSafety.is_alive_node(worker_ref) or not worker_ref is Worker:
				continue
			(worker_ref as Worker).issue_order(UnitOrder.build(segments[0]), true)
	else:
		var wall_job := WallBuildJob.new(segments, workers)
		wall_job.start()
	_play_construction_target_feedback(clicked_segment)


func _is_unfinished_player_construction(building: Building) -> bool:
	if not CombatTargetValidation.is_player_selectable_building(building):
		return false

	return (
		building.building_state == Building.STATE_UNDER_CONSTRUCTION
		or building.building_state == Building.STATE_CONSTRUCTING
	)


func _play_construction_target_feedback(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not _is_unfinished_player_construction(building):
		return
	if not building.has_method("play_target_feedback"):
		return
	building.play_target_feedback()


func _dispatch_gold_mine_gather_command(gold_mine: GoldMine, queued: bool = false) -> void:
	_purge_invalid_selected_units()
	var workers: Array[Worker] = []
	for unit_ref: Variant in selected_units:
		if not _is_commandable_unit(unit_ref):
			continue
		if unit_ref is Worker:
			workers.append(unit_ref as Worker)

	if workers.is_empty():
		return

	workers.sort_custom(
		func(a: Worker, b: Worker) -> bool:
			return a.get_instance_id() < b.get_instance_id()
	)
	# Unique approach slots for multi-worker mine orders — not military formation spacing.
	for index: int in workers.size():
		workers[index].set_gather_approach_slot_hint(index)
		workers[index].issue_order(UnitOrder.gather(gold_mine), queued)
	_play_gather_target_feedback(gold_mine)


func _play_gather_target_feedback(resource: GatherableResource) -> void:
	if resource == null or not is_instance_valid(resource):
		return
	if not resource.has_method("play_target_feedback"):
		return
	resource.play_target_feedback()


func _play_attack_target_feedback(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not CombatTargetValidation.is_player_unit_attack_target(target):
		return
	CommandFeedback.pulse_attack_target(target)


func _get_units_in_rect(camera: Camera3D, rect: Rect2) -> Array[Unit]:
	var units: Array[Unit] = []
	var world_xz_bounds: Rect2 = _get_world_xz_bounds_from_screen_rect(camera, rect)
	var use_world_bounds: bool = world_xz_bounds.size.length_squared() > 0.0

	for node: Node in get_tree().get_nodes_in_group(UNIT_GROUP):
		var unit := node as Unit
		if unit == null:
			continue
		if not _is_selectable_unit(unit):
			continue
		if use_world_bounds and not _is_unit_in_world_xz_bounds(unit, world_xz_bounds):
			continue
		if not _is_unit_in_selection_rect(unit, camera, rect):
			continue
		units.append(unit)
	return units


func _is_unit_in_selection_rect(unit: Unit, camera: Camera3D, rect: Rect2) -> bool:
	if not camera.is_position_in_frustum(unit.global_position):
		return false

	var screen_position: Vector2 = camera.unproject_position(unit.global_position)
	return rect.has_point(screen_position)


func _get_world_xz_bounds_from_screen_rect(camera: Camera3D, rect: Rect2) -> Rect2:
	var corners: Array[Vector2] = [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	]

	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	var any_valid: bool = false

	for corner: Vector2 in corners:
		var world_position: Vector3 = _raycast_ground_plane(camera, corner)
		if not world_position.is_finite():
			continue
		any_valid = true
		min_x = minf(min_x, world_position.x)
		max_x = maxf(max_x, world_position.x)
		min_z = minf(min_z, world_position.z)
		max_z = maxf(max_z, world_position.z)

	if not any_valid:
		return Rect2()

	const BOUNDS_PADDING: float = 1.5
	return Rect2(
		min_x - BOUNDS_PADDING,
		min_z - BOUNDS_PADDING,
		(max_x - min_x) + BOUNDS_PADDING * 2.0,
		(max_z - min_z) + BOUNDS_PADDING * 2.0
	)


func _is_unit_in_world_xz_bounds(unit: Unit, bounds: Rect2) -> bool:
	var position: Vector3 = unit.global_position
	return bounds.has_point(Vector2(position.x, position.z))


func _make_screen_rect(start: Vector2, end: Vector2) -> Rect2:
	return Rect2(
		Vector2(minf(start.x, end.x), minf(start.y, end.y)),
		Vector2(absf(start.x - end.x), absf(start.y - end.y))
	)


func _set_selected_units(units: Array[Unit]) -> void:
	var next_units: Array[Unit] = _filter_selectable_units(units.duplicate())
	if _arrays_match(selected_units, next_units):
		return

	_clear_inspection_without_signal()
	_clear_building_selection()
	_apply_units_selection_diff(next_units)
	selection_changed.emit(selected_units)
	if HeroAbilityTargetingController != null:
		HeroAbilityTargetingController.on_selection_changed()


func _apply_units_selection_diff(next_units: Array[Unit]) -> void:
	var next_ids: Dictionary = {}
	for unit_variant: Variant in next_units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		next_ids[(unit_variant as Object).get_instance_id()] = true

	for index: int in range(selected_units.size() - 1, -1, -1):
		var unit_variant: Variant = selected_units[index]
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			selected_units.remove_at(index)
			continue
		var unit: Unit = unit_variant as Unit
		if next_ids.has(unit.get_instance_id()):
			continue
		_untrack_unit_selection(unit)
		selected_units.remove_at(index)

	var current_ids: Dictionary = {}
	for unit_variant: Variant in selected_units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		current_ids[(unit_variant as Object).get_instance_id()] = true

	var ordered_units: Array[Unit] = []
	for unit_variant: Variant in next_units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		var unit: Unit = unit_variant as Unit
		ordered_units.append(unit)
		if current_ids.has(unit.get_instance_id()):
			continue
		_safe_set_unit_selected(unit, true)
		_track_unit_selection(unit)

	selected_units = ordered_units
	_rebuild_selected_unit_handles()


func _rebuild_selected_unit_handles() -> void:
	_selected_unit_handles.clear()
	for unit_variant: Variant in selected_units:
		if not NodeSafety.is_alive_node(unit_variant) or not unit_variant is Unit:
			continue
		_selected_unit_handles.append(EntityHandle.from_node(unit_variant))


func _clear_selection() -> void:
	if selected_units.is_empty():
		return

	_clear_selection_without_signal()
	selection_changed.emit(selected_units)


func _set_selected_building(building: Building) -> void:
	if not _is_selectable_building(building):
		return

	if selected_building == building:
		return

	_clear_inspection_without_signal()
	_clear_selection_without_signal()
	_clear_building_selection_without_signal()
	if not is_instance_valid(building):
		return

	selected_building = building
	_selected_building_handle = EntityHandle.from_node(building)
	_connect_selected_building_destroyed(building)
	_connect_selected_building_tree_exiting(building)
	if _is_selectable_building(selected_building):
		_safe_set_building_selected(selected_building, true)
	building_selection_changed.emit(selected_building)
	selection_changed.emit(selected_units)


func _clear_building_selection() -> void:
	var building_ref: Variant = selected_building
	if building_ref == null:
		return

	_clear_selected_building_reference(true)


func _clear_building_selection_without_signal() -> void:
	_clear_selected_building_reference(false)


func _clear_selection_without_signal() -> void:
	for index: int in range(selected_units.size() - 1, -1, -1):
		var unit_variant: Variant = selected_units[index]
		if NodeSafety.is_alive_node(unit_variant) and unit_variant is Unit:
			_untrack_unit_selection(unit_variant as Unit)
		else:
			## Drop freed/stale entries without typed assignment.
			pass
	selected_units.clear()
	_selected_unit_handles.clear()


func _on_unit_died(unit: Unit) -> void:
	if unit != null and is_instance_valid(unit) and unit is Hero:
		HeroProgressionStore.clear_living_hero(unit as Hero)

	if not selected_units.has(unit):
		return

	_remove_unit_from_selection(unit, true)


func _on_selected_unit_tree_exiting(expected_instance_id: int) -> void:
	_unit_tree_exiting_handlers.erase(expected_instance_id)

	## Always purge by instance id — the Object may already be invalid.
	var removed: bool = false
	for index: int in range(selected_units.size() - 1, -1, -1):
		var unit_variant: Variant = selected_units[index]
		if not is_instance_valid(unit_variant):
			selected_units.remove_at(index)
			removed = true
			continue
		if (unit_variant as Object).get_instance_id() != expected_instance_id:
			continue
		if unit_variant is Unit:
			_untrack_unit_selection(unit_variant as Unit)
		selected_units.remove_at(index)
		removed = true

	if _last_clicked_unit_handle.is_empty():
		pass
	elif (
		_last_clicked_unit_handle.instance_id == expected_instance_id
		or _last_clicked_unit_handle.resolve() == null
	):
		_reset_click_tracking()

	if removed:
		_rebuild_selected_unit_handles()
		selection_changed.emit(selected_units)


func _remove_unit_from_selection(unit: Unit, emit_signal: bool) -> void:
	_untrack_unit_selection(unit)
	selected_units.erase(unit)
	_rebuild_selected_unit_handles()
	if not _last_clicked_unit_handle.is_empty() and unit != null and is_instance_valid(unit):
		if _last_clicked_unit_handle.instance_id == unit.get_instance_id():
			_reset_click_tracking()

	if emit_signal:
		selection_changed.emit(selected_units)


func _track_unit_selection(unit: Unit) -> void:
	if not _is_selectable_unit(unit):
		return

	if not unit.died.is_connected(_on_unit_died):
		unit.died.connect(_on_unit_died)

	var unit_id: int = unit.get_instance_id()
	if _unit_tree_exiting_handlers.has(unit_id):
		return

	var handler: Callable = _on_selected_unit_tree_exiting.bind(unit_id)
	_unit_tree_exiting_handlers[unit_id] = handler
	unit.tree_exiting.connect(handler, CONNECT_ONE_SHOT)


func _untrack_unit_selection(candidate: Variant) -> void:
	if candidate == null or not is_instance_valid(candidate):
		return

	if not candidate is Unit:
		return

	var unit: Unit = candidate as Unit
	_safe_set_unit_selected(unit, false)

	if unit.died.is_connected(_on_unit_died):
		unit.died.disconnect(_on_unit_died)

	_clear_unit_tree_exiting_handler(unit)


func _clear_unit_tree_exiting_handler(unit: Unit) -> void:
	if unit == null:
		return

	var unit_id: int = unit.get_instance_id()
	if not _unit_tree_exiting_handlers.has(unit_id):
		return

	var handler: Callable = _unit_tree_exiting_handlers[unit_id]
	if is_instance_valid(unit) and unit.tree_exiting.is_connected(handler):
		unit.tree_exiting.disconnect(handler)
	_unit_tree_exiting_handlers.erase(unit_id)


## Public wrapper for UI/systems that read selected_units or selected_building directly.
func purge_invalid_selection() -> void:
	_purge_invalid_selection()


func safe_clear_selection() -> void:
	purge_invalid_selection()


func _purge_invalid_selection() -> void:
	_purge_invalid_selected_units()
	_purge_invalid_selected_building()
	_purge_invalid_inspection()
	_purge_invalid_last_clicked_unit()


func _purge_invalid_selected_units() -> void:
	selected_units = NodeSafety.clean_node_array(selected_units)
	var removed_any: bool = false

	for index: int in range(selected_units.size() - 1, -1, -1):
		var candidate: Variant = selected_units[index]
		if _is_selectable_unit(candidate):
			continue

		_untrack_unit_selection(candidate)
		selected_units.remove_at(index)
		removed_any = true

	_rebuild_selected_unit_handles()
	if removed_any:
		selection_changed.emit(selected_units)


func _purge_invalid_selected_building() -> void:
	var building_ref: Variant = selected_building
	if building_ref == null:
		_selected_building_handle = EntityHandle.empty()
		return

	if _is_selectable_building(building_ref):
		_selected_building_handle = EntityHandle.from_node(building_ref)
		return

	_clear_selected_building_reference(true)


func _purge_invalid_inspection() -> void:
	var unit_ref: Variant = inspected_unit
	var building_ref: Variant = inspected_building
	var resource_ref: Variant = inspected_resource
	var had_inspection: bool = (
		unit_ref != null or building_ref != null or resource_ref != null
	)

	if unit_ref != null and not _is_inspectable_unit(unit_ref):
		_safe_set_unit_inspected(unit_ref, false)
		inspected_unit = null
		_inspected_unit_handle = EntityHandle.empty()

	if building_ref != null and not _is_inspectable_building(building_ref):
		_disconnect_inspected_building_destroyed()
		_safe_set_building_inspected(building_ref, false)
		inspected_building = null
		_inspected_building_handle = EntityHandle.empty()

	if resource_ref != null and not _is_inspectable_resource(resource_ref):
		inspected_resource = null

	if (
		had_inspection
		and inspected_unit == null
		and inspected_building == null
		and inspected_resource == null
	):
		inspection_changed.emit(null, null)


func _set_inspected_unit(unit: Unit) -> void:
	if not _is_inspectable_unit(unit):
		return

	if inspected_unit == unit and selected_units.is_empty() and selected_building == null:
		return

	_clear_selection_without_signal()
	_clear_building_selection_without_signal()
	if inspected_unit != null and inspected_unit != unit:
		_safe_set_unit_inspected(inspected_unit, false)
	if inspected_building != null:
		_disconnect_inspected_building_destroyed()
		_safe_set_building_inspected(inspected_building, false)
		inspected_building = null
	inspected_resource = null
	if not is_instance_valid(unit):
		return

	inspected_unit = unit
	_inspected_unit_handle = EntityHandle.from_node(unit)
	_inspected_building_handle = EntityHandle.empty()
	_safe_set_unit_inspected(unit, true)
	inspection_changed.emit(inspected_unit, null)
	selection_changed.emit(selected_units)
	building_selection_changed.emit(null)


func _set_inspected_building(building: Building) -> void:
	if not _is_inspectable_building(building):
		return

	if inspected_building == building and selected_units.is_empty() and selected_building == null:
		return

	_clear_selection_without_signal()
	_clear_building_selection_without_signal()
	if inspected_unit != null:
		_safe_set_unit_inspected(inspected_unit, false)
		inspected_unit = null
	if inspected_building != null and inspected_building != building:
		_disconnect_inspected_building_destroyed()
		_safe_set_building_inspected(inspected_building, false)
	inspected_resource = null
	if not is_instance_valid(building):
		return

	inspected_building = building
	_inspected_building_handle = EntityHandle.from_node(building)
	_inspected_unit_handle = EntityHandle.empty()
	_connect_inspected_building_destroyed(building)
	_safe_set_building_inspected(building, true)
	inspection_changed.emit(null, inspected_building)
	selection_changed.emit(selected_units)
	building_selection_changed.emit(null)


func _set_inspected_resource(resource: GatherableResource) -> void:
	if not _is_inspectable_resource(resource):
		return

	if (
		inspected_resource == resource
		and selected_units.is_empty()
		and selected_building == null
	):
		return

	_clear_selection_without_signal()
	_clear_building_selection_without_signal()
	if inspected_unit != null:
		_safe_set_unit_inspected(inspected_unit, false)
		inspected_unit = null
	if inspected_building != null:
		_disconnect_inspected_building_destroyed()
		_safe_set_building_inspected(inspected_building, false)
		inspected_building = null
	if not is_instance_valid(resource):
		return

	inspected_resource = resource
	inspection_changed.emit(null, null)
	selection_changed.emit(selected_units)
	building_selection_changed.emit(null)


func _clear_inspection() -> void:
	if inspected_unit == null and inspected_building == null and inspected_resource == null:
		return

	_clear_inspection_without_signal()
	inspection_changed.emit(null, null)


func _clear_inspection_without_signal() -> void:
	if inspected_unit != null:
		_safe_set_unit_inspected(inspected_unit, false)
	if inspected_building != null:
		_disconnect_inspected_building_destroyed()
		_safe_set_building_inspected(inspected_building, false)
	inspected_unit = null
	inspected_building = null
	inspected_resource = null
	_inspected_unit_handle = EntityHandle.empty()
	_inspected_building_handle = EntityHandle.empty()


func _connect_inspected_building_destroyed(building: Building) -> void:
	_disconnect_inspected_building_destroyed()
	if building == null or not is_instance_valid(building):
		return
	if not building.has_signal("destroyed"):
		return

	_inspected_building_destroyed_handler = _on_inspected_building_destroyed
	if not building.destroyed.is_connected(_inspected_building_destroyed_handler):
		building.destroyed.connect(_inspected_building_destroyed_handler, CONNECT_ONE_SHOT)


func _disconnect_inspected_building_destroyed() -> void:
	if not _inspected_building_destroyed_handler.is_valid():
		_inspected_building_destroyed_handler = Callable()
		return

	var building_ref: Variant = inspected_building
	if (
		building_ref != null
		and is_instance_valid(building_ref)
		and building_ref is Building
		and (building_ref as Building).has_signal("destroyed")
		and (building_ref as Building).destroyed.is_connected(_inspected_building_destroyed_handler)
	):
		(building_ref as Building).destroyed.disconnect(_inspected_building_destroyed_handler)

	_inspected_building_destroyed_handler = Callable()


func _on_inspected_building_destroyed(_building: Building) -> void:
	_inspected_building_destroyed_handler = Callable()
	inspected_building = null
	_inspected_building_handle = EntityHandle.empty()
	inspection_changed.emit(null, null)


func _connect_selected_building_destroyed(building: Building) -> void:
	_disconnect_selected_building_destroyed()
	if building == null or not is_instance_valid(building):
		return
	if not building.has_signal("destroyed"):
		return

	_selected_building_destroyed_handler = _on_selected_building_destroyed
	if not building.destroyed.is_connected(_selected_building_destroyed_handler):
		building.destroyed.connect(_selected_building_destroyed_handler, CONNECT_ONE_SHOT)


func _connect_selected_building_tree_exiting(building: Building) -> void:
	_disconnect_selected_building_tree_exiting()
	if building == null or not is_instance_valid(building):
		return

	_selected_building_tree_exiting_handler = _on_selected_building_tree_exiting.bind(
		building.get_instance_id()
	)
	if not building.tree_exiting.is_connected(_selected_building_tree_exiting_handler):
		building.tree_exiting.connect(_selected_building_tree_exiting_handler, CONNECT_ONE_SHOT)


func _disconnect_selected_building_destroyed() -> void:
	if not _selected_building_destroyed_handler.is_valid():
		_selected_building_destroyed_handler = Callable()
		return

	var building_ref: Variant = selected_building
	if (
		building_ref != null
		and is_instance_valid(building_ref)
		and building_ref is Building
		and (building_ref as Building).has_signal("destroyed")
		and (building_ref as Building).destroyed.is_connected(_selected_building_destroyed_handler)
	):
		(building_ref as Building).destroyed.disconnect(_selected_building_destroyed_handler)

	_selected_building_destroyed_handler = Callable()


func _disconnect_selected_building_tree_exiting() -> void:
	if not _selected_building_tree_exiting_handler.is_valid():
		_selected_building_tree_exiting_handler = Callable()
		return

	var building_ref: Variant = selected_building
	if (
		building_ref != null
		and is_instance_valid(building_ref)
		and building_ref is Building
		and (building_ref as Building).tree_exiting.is_connected(_selected_building_tree_exiting_handler)
	):
		(building_ref as Building).tree_exiting.disconnect(_selected_building_tree_exiting_handler)

	_selected_building_tree_exiting_handler = Callable()


func _on_selected_building_destroyed(_building: Building) -> void:
	_selected_building_destroyed_handler = Callable()
	_clear_selected_building_reference(true)


func _on_selected_building_tree_exiting(expected_instance_id: int) -> void:
	_selected_building_tree_exiting_handler = Callable()
	if (
		_selected_building_handle == null
		or _selected_building_handle.instance_id != expected_instance_id
	):
		return

	_clear_selected_building_reference(true)


func _clear_selected_building_reference(emit_signal: bool) -> void:
	_disconnect_selected_building_destroyed()
	_disconnect_selected_building_tree_exiting()
	var building_ref: Variant = selected_building
	if NodeSafety.is_alive_node(building_ref) and building_ref is Building:
		_safe_set_building_selected(building_ref, false)
	selected_building = null
	_selected_building_handle = EntityHandle.empty()
	if emit_signal:
		building_selection_changed.emit(null)


func _filter_selectable_units(units: Array[Unit]) -> Array[Unit]:
	var selectable_units: Array[Unit] = []
	for candidate: Variant in units:
		if not _is_selectable_unit(candidate):
			continue
		selectable_units.append(candidate as Unit)
	return selectable_units


func _is_selectable_unit(candidate: Variant) -> bool:
	return NodeSafety.is_alive_node(candidate) and candidate is Unit and not (candidate as Unit).is_in_group(&"enemies")


func _get_commandable_selected_units() -> Array[Unit]:
	var commandable_units: Array[Unit] = []
	for unit_ref: Variant in NodeSafety.clean_node_array(selected_units):
		if not _is_commandable_unit(unit_ref):
			continue
		commandable_units.append(unit_ref as Unit)
	return commandable_units


func _is_commandable_unit(candidate: Variant) -> bool:
	if not _is_selectable_unit(candidate):
		return false

	return not (candidate as Unit).is_in_group(&"neutral_creeps")


func _is_combat_order_unit(unit: Unit) -> bool:
	return unit != null and unit.supports_combat_orders()


func _is_inspectable_unit(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false

	if not candidate is Unit:
		return false

	var unit: Unit = candidate as Unit
	if unit.is_queued_for_deletion():
		return false

	if unit.is_in_group(&"enemies"):
		return true

	return CombatTargetValidation.is_enemy_faction(unit)


func _is_inspectable_building(candidate: Variant) -> bool:
	return CombatTargetValidation.is_attackable_enemy_building(candidate)


func _is_inspectable_resource(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false

	if not candidate is GatherableResource:
		return false

	return not (candidate as GatherableResource).is_queued_for_deletion()


func _is_selectable_building(candidate: Variant) -> bool:
	if candidate == null:
		return false

	if not is_instance_valid(candidate):
		return false

	if not candidate is Building:
		return false

	return CombatTargetValidation.is_player_selectable_building(candidate)


func _safe_set_unit_selected(candidate: Variant, selected: bool) -> void:
	if not _is_selectable_unit(candidate):
		return

	(candidate as Unit).set_selected(selected)


func _safe_set_building_selected(candidate: Variant, selected: bool) -> void:
	if not _is_selectable_building(candidate):
		return

	(candidate as Building).set_selected(selected)


func _safe_set_unit_inspected(candidate: Variant, inspected: bool) -> void:
	if candidate == null or not is_instance_valid(candidate):
		return

	if not candidate is Unit:
		return

	(candidate as Unit).set_inspected(inspected)


func _safe_set_building_inspected(candidate: Variant, inspected: bool) -> void:
	if candidate == null or not is_instance_valid(candidate):
		return

	if not candidate is Building:
		return

	(candidate as Building).set_inspected(inspected)


func _arrays_match(current: Array[Unit], next: Array[Unit]) -> bool:
	if current.size() != next.size():
		return false

	for index: int in current.size():
		if current[index] != next[index]:
			return false
	return true


func _get_camera() -> Camera3D:
	return get_node_or_null(camera_path) as Camera3D


func _get_selection_box() -> SelectionBox:
	return get_node_or_null(selection_box_path) as SelectionBox


func _raycast_unit(camera: Camera3D, screen_position: Vector2) -> Unit:
	var result: Dictionary = _raycast_with_mask(camera, screen_position, PhysicsLayers.UNITS)
	if result.is_empty():
		return null

	return _find_unit_from_collider(result.collider as Node)


func _raycast_gold_mine(camera: Camera3D, screen_position: Vector2) -> GoldMine:
	var resource := _raycast_gatherable_resource(camera, screen_position)
	if resource is GoldMine:
		return resource as GoldMine
	return null


func _raycast_tree(camera: Camera3D, screen_position: Vector2) -> WoodTree:
	var resource := _raycast_gatherable_resource(camera, screen_position)
	if resource is WoodTree:
		return resource as WoodTree
	return null


func _raycast_gatherable_resource(camera: Camera3D, screen_position: Vector2) -> GatherableResource:
	var result: Dictionary = _raycast_without_mask(camera, screen_position)
	if result.is_empty():
		return null

	return _find_gatherable_resource_from_collider(result.collider as Node)


func _raycast_without_mask(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	return space_state.intersect_ray(query)


func _find_gatherable_resource_from_collider(node: Node) -> GatherableResource:
	var current: Node = node
	while current:
		if current is GatherableResource:
			return current as GatherableResource
		current = current.get_parent()
	return null


func _is_double_click(unit: Unit) -> bool:
	var last_clicked: Unit = _resolve_last_clicked_unit()
	if not _is_selectable_unit(last_clicked) or _last_click_time_msec < 0:
		return false

	if not _is_same_unit_type(last_clicked, unit):
		return false

	var elapsed_seconds: float = float(Time.get_ticks_msec() - _last_click_time_msec) / 1000.0
	return elapsed_seconds <= DOUBLE_CLICK_TIME_SECONDS


func _record_click(unit: Unit) -> void:
	if is_instance_valid(unit):
		_last_clicked_unit_handle = EntityHandle.from_node(unit)
	else:
		_last_clicked_unit_handle = EntityHandle.empty()
	_last_click_time_msec = Time.get_ticks_msec()


func _reset_click_tracking() -> void:
	_last_clicked_unit_handle = EntityHandle.empty()
	_last_click_time_msec = -1


func _resolve_last_clicked_unit() -> Unit:
	if _last_clicked_unit_handle == null or _last_clicked_unit_handle.is_empty():
		return null
	var node: Node = _last_clicked_unit_handle.resolve()
	return node as Unit if node is Unit else null


func _is_same_unit_type(first_unit: Unit, second_unit: Unit) -> bool:
	if not _is_selectable_unit(first_unit) or not _is_selectable_unit(second_unit):
		return false

	var first_type: StringName = _get_unit_selection_group(first_unit)
	var second_type: StringName = _get_unit_selection_group(second_unit)
	if first_type.is_empty() or second_type.is_empty():
		return false
	return first_type == second_type


func _get_unit_selection_group(unit: Unit) -> StringName:
	if unit is Worker:
		return SELECTION_TYPE_WORKER
	if unit is Spearman:
		return SELECTION_TYPE_SPEARMAN
	if unit is Swordsman:
		return SELECTION_TYPE_SWORDSMAN
	if unit is Archer:
		return SELECTION_TYPE_ARCHER
	if unit is HeavyCavalry:
		return SELECTION_TYPE_HEAVY_CAVALRY
	if unit is LightCavalry:
		return SELECTION_TYPE_LIGHT_CAVALRY
	if unit is CavalryArcher:
		return SELECTION_TYPE_CAVALRY_ARCHER
	if unit is Cannon:
		return SELECTION_TYPE_CANNON
	if unit is Hero:
		return SELECTION_TYPE_HERO
	return &""


func _select_all_visible_same_type(clicked_unit: Unit, camera: Camera3D) -> void:
	var selection_type: StringName = _get_unit_selection_group(clicked_unit)
	if selection_type.is_empty():
		_set_selected_units([clicked_unit])
		return

	var units: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group(UNIT_GROUP):
		var unit := node as Unit
		if unit == null:
			continue
		if not _is_selectable_unit(unit):
			continue
		if _get_unit_selection_group(unit) != selection_type:
			continue
		if not camera.is_position_in_frustum(unit.global_position):
			continue
		units.append(unit)

	_set_selected_units(units)


func _raycast_ground_plane(camera: Camera3D, screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return Vector3(INF, INF, INF)

	var intersection_distance: float = -ray_origin.y / ray_direction.y
	if intersection_distance < 0.0:
		return Vector3(INF, INF, INF)

	return ray_origin + ray_direction * intersection_distance


func _find_unit_from_collider(node: Node) -> Unit:
	var current: Node = node
	while current:
		if current is Unit:
			return current as Unit
		current = current.get_parent()
	return null


func _raycast_building(camera: Camera3D, screen_position: Vector2) -> Building:
	var result: Dictionary = _raycast_with_mask(
		camera, screen_position, PhysicsLayers.BUILDINGS
	)
	if result.is_empty():
		return null

	return _find_building_from_collider(result.collider as Node)


func _raycast_hit_distance(
	camera: Camera3D, screen_position: Vector2, collision_mask: int
) -> float:
	var result: Dictionary = _raycast_with_mask(camera, screen_position, collision_mask)
	if result.is_empty():
		return INF

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	return ray_origin.distance_to(result.position)


func _raycast_with_mask(
	camera: Camera3D, screen_position: Vector2, collision_mask: int
) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = collision_mask

	return space_state.intersect_ray(query)


func _find_building_from_collider(node: Node) -> Building:
	var current: Node = node
	while current:
		if current is Building:
			return current as Building
		current = current.get_parent()
	return null


func _ready() -> void:
	add_to_group(ControlGroupManager.SELECTION_MANAGER_GROUP)
	set_process(true)
	if EntityRegistry != null and not EntityRegistry.entity_unregistered.is_connected(
		_on_entity_unregistered
	):
		EntityRegistry.entity_unregistered.connect(_on_entity_unregistered)


func _on_entity_unregistered(instance_id: int, _category: int, _team_id: int) -> void:
	if instance_id == 0:
		return

	var units_changed: bool = false
	for index: int in range(selected_units.size() - 1, -1, -1):
		var unit_variant: Variant = selected_units[index]
		if is_instance_valid(unit_variant) and (unit_variant as Object).get_instance_id() == instance_id:
			_untrack_unit_selection(unit_variant)
			selected_units.remove_at(index)
			units_changed = true
		elif not is_instance_valid(unit_variant):
			selected_units.remove_at(index)
			units_changed = true

	for index: int in range(_selected_unit_handles.size() - 1, -1, -1):
		var handle: EntityHandle = _selected_unit_handles[index]
		if handle != null and handle.instance_id == instance_id:
			_selected_unit_handles.remove_at(index)

	if (
		_selected_building_handle != null
		and _selected_building_handle.instance_id == instance_id
	):
		_clear_selected_building_reference(true)

	if (
		_inspected_unit_handle != null
		and _inspected_unit_handle.instance_id == instance_id
	):
		inspected_unit = null
		_inspected_unit_handle = EntityHandle.empty()
		inspection_changed.emit(null, inspected_building)

	if (
		_inspected_building_handle != null
		and _inspected_building_handle.instance_id == instance_id
	):
		_disconnect_inspected_building_destroyed()
		inspected_building = null
		_inspected_building_handle = EntityHandle.empty()
		inspection_changed.emit(inspected_unit, null)

	if (
		_last_clicked_unit_handle != null
		and _last_clicked_unit_handle.instance_id == instance_id
	):
		_reset_click_tracking()

	if units_changed:
		_rebuild_selected_unit_handles()
		selection_changed.emit(selected_units)


func _process(delta: float) -> void:
	_selection_purge_timer += delta
	if _selection_purge_timer >= SELECTION_PURGE_INTERVAL:
		_selection_purge_timer = 0.0
		_purge_invalid_selection()

	_update_world_tooltip()


func _purge_invalid_last_clicked_unit() -> void:
	if _last_clicked_unit_handle == null or _last_clicked_unit_handle.is_empty():
		return

	if _is_selectable_unit(_resolve_last_clicked_unit()):
		return

	_last_clicked_unit_handle = EntityHandle.empty()


func _horizontal_distance_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _update_world_tooltip() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return

	if viewport.gui_get_hovered_control() != null:
		TooltipManager.hide_world_tooltip()
		return

	var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
	if camera == null:
		TooltipManager.hide_world_tooltip()
		return

	var mouse_position: Vector2 = viewport.get_mouse_position()
	var unit: Unit = _raycast_unit(camera, mouse_position)
	if unit != null:
		TooltipManager.show_tooltip(TooltipFormatter.format_unit(unit))
		return

	var building: Building = _raycast_building(camera, mouse_position)
	if building != null:
		TooltipManager.show_tooltip(TooltipFormatter.format_unit(building))
		return

	TooltipManager.hide_world_tooltip()
