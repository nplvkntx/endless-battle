extends Node

## Warcraft III-style control groups (1–9), hero hotkey, and idle-worker hotkey.
## Stores group membership; SelectionManager owns selection and camera focus.

signal groups_changed
signal active_group_changed(group_index: int)

const GROUP_COUNT: int = 9
const DOUBLE_TAP_SECONDS: float = 0.35
const HOTKEY_SELECT_HERO: Key = KEY_F1
const HOTKEY_IDLE_WORKER: Key = KEY_PERIOD
const SELECTION_MANAGER_GROUP: StringName = &"selection_manager"

## Groups 1–9 stored as arrays of Unit/Building nodes (index 0 = key 1).
var _groups: Array = []
## instance_id -> {group_indices: Dictionary, died: Callable, tree_exiting: Callable, destroyed: Callable}
var _tracked_members: Dictionary = {}
var _last_recall_index: int = -1
var _last_recall_msec: int = -1
var _active_group_index: int = -1


func _ready() -> void:
	_groups.clear()
	for _i: int in GROUP_COUNT:
		_groups.append([])
	MatchSession.register_match_reset(&"ControlGroupManager", clear_all_groups)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == HOTKEY_SELECT_HERO:
		if _select_hero():
			get_viewport().set_input_as_handled()
		return

	if key_event.keycode == HOTKEY_IDLE_WORKER:
		if _select_idle_worker():
			get_viewport().set_input_as_handled()
		return

	var group_index: int = _keycode_to_group_index(key_event.keycode)
	if group_index < 0:
		return

	var ctrl_held: bool = key_event.ctrl_pressed
	var shift_held: bool = key_event.shift_pressed

	if ctrl_held and not shift_held:
		_assign_current_selection(group_index)
		get_viewport().set_input_as_handled()
		return

	if shift_held and not ctrl_held:
		_add_current_selection_to_group(group_index)
		get_viewport().set_input_as_handled()
		return

	if ctrl_held and shift_held:
		# Treat as add (WC3 Ctrl+Shift+# also adds in some builds).
		_add_current_selection_to_group(group_index)
		get_viewport().set_input_as_handled()
		return

	_recall_group(group_index)
	get_viewport().set_input_as_handled()


func clear_all_groups() -> void:
	for index: int in GROUP_COUNT:
		_clear_group_tracking(index)
		_groups[index] = []
	_last_recall_index = -1
	_last_recall_msec = -1
	_set_active_group(-1)
	_tracked_members.clear()
	groups_changed.emit()


func get_active_group_index() -> int:
	return _active_group_index


func get_group_members(group_index: int) -> Array:
	if group_index < 0 or group_index >= GROUP_COUNT:
		return []
	_prune_group(group_index)
	return (_groups[group_index] as Array).duplicate()


func get_group_size(group_index: int) -> int:
	return get_group_members(group_index).size()


func has_any_members() -> bool:
	for index: int in GROUP_COUNT:
		if get_group_size(index) > 0:
			return true
	return false


func assign_group(group_index: int, members: Array) -> void:
	if group_index < 0 or group_index >= GROUP_COUNT:
		return

	_clear_group_tracking(group_index)
	var cleaned: Array = _sanitize_members(members)
	_groups[group_index] = cleaned
	for member: Variant in cleaned:
		_track_member(member as Node, group_index)
	_set_active_group(group_index if not cleaned.is_empty() else -1)
	groups_changed.emit()


func append_members(group_index: int, members: Array) -> void:
	if group_index < 0 or group_index >= GROUP_COUNT:
		return

	var existing: Array = (_groups[group_index] as Array).duplicate()
	for member: Variant in _sanitize_members(members):
		if not _array_has_node(existing, member as Node):
			existing.append(member)
			_track_member(member as Node, group_index)
	_groups[group_index] = existing
	if not existing.is_empty():
		_set_active_group(group_index)
	groups_changed.emit()


func _assign_current_selection(group_index: int) -> void:
	var selection_manager: Node = _get_selection_manager()
	if selection_manager == null or not selection_manager.has_method("get_control_group_members"):
		return
	assign_group(group_index, selection_manager.get_control_group_members())


func _add_current_selection_to_group(group_index: int) -> void:
	var selection_manager: Node = _get_selection_manager()
	if selection_manager == null or not selection_manager.has_method("get_control_group_members"):
		return
	append_members(group_index, selection_manager.get_control_group_members())


func _recall_group(group_index: int) -> void:
	_prune_group(group_index)
	var members: Array = _groups[group_index] as Array
	if members.is_empty():
		return

	var selection_manager: Node = _get_selection_manager()
	if selection_manager == null or not selection_manager.has_method("apply_control_group_selection"):
		return

	selection_manager.apply_control_group_selection(members)
	_set_active_group(group_index)

	var now_msec: int = Time.get_ticks_msec()
	var should_center: bool = (
		_last_recall_index == group_index
		and _last_recall_msec >= 0
		and float(now_msec - _last_recall_msec) / 1000.0 <= DOUBLE_TAP_SECONDS
	)
	_last_recall_index = group_index
	_last_recall_msec = now_msec

	if should_center and selection_manager.has_method("focus_camera_on_current_selection"):
		selection_manager.focus_camera_on_current_selection()
		_last_recall_index = -1
		_last_recall_msec = -1


func _select_hero() -> bool:
	var selection_manager: Node = _get_selection_manager()
	if selection_manager == null or not selection_manager.has_method("select_player_hero_and_focus"):
		return false
	return bool(selection_manager.select_player_hero_and_focus())


func _select_idle_worker() -> bool:
	var selection_manager: Node = _get_selection_manager()
	if selection_manager == null or not selection_manager.has_method("select_next_idle_worker_and_focus"):
		return false
	return bool(selection_manager.select_next_idle_worker_and_focus())


func _sanitize_members(members: Array) -> Array:
	var cleaned: Array = []
	var seen: Dictionary = {}
	for entry: Variant in members:
		if not NodeSafety.is_alive_node(entry):
			continue
		if not (entry is Unit or entry is Building):
			continue
		if entry is Unit and (entry as Unit).is_in_group(&"enemies"):
			continue
		if entry is Unit and (entry as Unit).is_in_group(&"neutral_creeps"):
			continue
		if entry is Building and not CombatTargetValidation.is_player_selectable_building(entry):
			continue
		var node: Node = entry as Node
		var id: int = node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		cleaned.append(node)
	return cleaned


func _prune_group(group_index: int) -> void:
	if group_index < 0 or group_index >= GROUP_COUNT:
		return

	var members: Array = _groups[group_index] as Array
	var cleaned: Array = _sanitize_members(members)
	if cleaned.size() == members.size():
		var unchanged: bool = true
		for i: int in cleaned.size():
			if cleaned[i] != members[i]:
				unchanged = false
				break
		if unchanged:
			return

	# Rebuild tracking for this group from cleaned members.
	_clear_group_tracking(group_index)
	_groups[group_index] = cleaned
	for member: Variant in cleaned:
		_track_member(member as Node, group_index)
	groups_changed.emit()


func _track_member(member: Node, group_index: int) -> void:
	if not NodeSafety.is_alive_node(member):
		return

	var id: int = member.get_instance_id()
	var entry: Dictionary
	if _tracked_members.has(id):
		entry = _tracked_members[id]
	else:
		entry = {
			"group_indices": {},
			"tree_exiting": Callable(),
		}
		_tracked_members[id] = entry

		if member is Unit:
			var unit: Unit = member as Unit
			if not unit.died.is_connected(_on_tracked_unit_died):
				unit.died.connect(_on_tracked_unit_died)
			var exit_handler: Callable = _on_tracked_node_tree_exiting.bind(id)
			entry["tree_exiting"] = exit_handler
			if not unit.tree_exiting.is_connected(exit_handler):
				unit.tree_exiting.connect(exit_handler, CONNECT_ONE_SHOT)
		elif member is Building:
			var building: Building = member as Building
			if not building.destroyed.is_connected(_on_tracked_building_destroyed):
				building.destroyed.connect(_on_tracked_building_destroyed)
			var exit_handler: Callable = _on_tracked_node_tree_exiting.bind(id)
			entry["tree_exiting"] = exit_handler
			if not building.tree_exiting.is_connected(exit_handler):
				building.tree_exiting.connect(exit_handler, CONNECT_ONE_SHOT)

	(entry["group_indices"] as Dictionary)[group_index] = true


func _clear_group_tracking(group_index: int) -> void:
	var members: Array = _groups[group_index] as Array
	for entry: Variant in members:
		if entry == null or not is_instance_valid(entry):
			continue
		_untrack_member_from_group(entry as Node, group_index)


func _untrack_member_from_group(member: Node, group_index: int) -> void:
	if member == null:
		return

	var id: int = member.get_instance_id()
	if not _tracked_members.has(id):
		return

	var entry: Dictionary = _tracked_members[id]
	var indices: Dictionary = entry.get("group_indices", {})
	indices.erase(group_index)
	if not indices.is_empty():
		return

	_disconnect_member_tracking(member, entry)
	_tracked_members.erase(id)


func _disconnect_member_tracking(member: Node, entry: Dictionary) -> void:
	if member is Unit:
		var unit: Unit = member as Unit
		if unit.died.is_connected(_on_tracked_unit_died):
			unit.died.disconnect(_on_tracked_unit_died)
		var exit_handler: Callable = entry.get("tree_exiting", Callable())
		if (
			exit_handler.is_valid()
			and is_instance_valid(unit)
			and unit.tree_exiting.is_connected(exit_handler)
		):
			unit.tree_exiting.disconnect(exit_handler)
	elif member is Building:
		var building: Building = member as Building
		if building.destroyed.is_connected(_on_tracked_building_destroyed):
			building.destroyed.disconnect(_on_tracked_building_destroyed)
		var exit_handler: Callable = entry.get("tree_exiting", Callable())
		if (
			exit_handler.is_valid()
			and is_instance_valid(building)
			and building.tree_exiting.is_connected(exit_handler)
		):
			building.tree_exiting.disconnect(exit_handler)


func _on_tracked_unit_died(unit: Unit) -> void:
	_remove_member_from_all_groups(unit)


func _on_tracked_building_destroyed(building: Building) -> void:
	_remove_member_from_all_groups(building)


func _on_tracked_node_tree_exiting(expected_instance_id: int) -> void:
	var node_ref: Variant = instance_from_id(expected_instance_id)
	if not NodeSafety.is_alive_node(node_ref) or not node_ref is Node:
		_tracked_members.erase(expected_instance_id)
		return
	_remove_member_from_all_groups(node_ref as Node)


func _remove_member_from_all_groups(member: Node) -> void:
	if member == null:
		return

	var id: int = member.get_instance_id()
	var entry: Dictionary = _tracked_members.get(id, {})
	var indices: Dictionary = entry.get("group_indices", {})
	var changed: bool = false

	for group_index: Variant in indices.keys():
		var index: int = int(group_index)
		if index < 0 or index >= GROUP_COUNT:
			continue
		var members: Array = _groups[index] as Array
		if _erase_node_from_array(members, member):
			_groups[index] = members
			changed = true

	if _tracked_members.has(id):
		_disconnect_member_tracking(member, entry)
		_tracked_members.erase(id)

	if changed:
		if _active_group_index >= 0:
			var active_members: Array = _sanitize_members(_groups[_active_group_index] as Array)
			_groups[_active_group_index] = active_members
			if active_members.is_empty():
				_set_active_group(-1)
		groups_changed.emit()


func _set_active_group(group_index: int) -> void:
	if _active_group_index == group_index:
		return
	_active_group_index = group_index
	active_group_changed.emit(_active_group_index)


func _get_selection_manager() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	var grouped: Array[Node] = tree.get_nodes_in_group(SELECTION_MANAGER_GROUP)
	if not grouped.is_empty():
		return grouped[0]

	return tree.root.find_child("SelectionManager", true, false)


func _keycode_to_group_index(keycode: Key) -> int:
	match keycode:
		KEY_1, KEY_KP_1:
			return 0
		KEY_2, KEY_KP_2:
			return 1
		KEY_3, KEY_KP_3:
			return 2
		KEY_4, KEY_KP_4:
			return 3
		KEY_5, KEY_KP_5:
			return 4
		KEY_6, KEY_KP_6:
			return 5
		KEY_7, KEY_KP_7:
			return 6
		KEY_8, KEY_KP_8:
			return 7
		KEY_9, KEY_KP_9:
			return 8
		_:
			return -1


func _array_has_node(arr: Array, node: Node) -> bool:
	if node == null:
		return false
	for entry: Variant in arr:
		if entry == node:
			return true
	return false


func _erase_node_from_array(arr: Array, node: Node) -> bool:
	for index: int in range(arr.size() - 1, -1, -1):
		if arr[index] == node:
			arr.remove_at(index)
			return true
	return false
