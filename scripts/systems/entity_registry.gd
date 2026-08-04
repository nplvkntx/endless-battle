extends Node

## Central registry of active gameplay entities.
## Stores identity metadata only — never retains freed Nodes.
## Systems resolve live objects through EntityHandle / resolve_* APIs.

signal entity_registered(instance_id: int, category: int, team_id: int)
signal entity_unregistered(instance_id: int, category: int, team_id: int)

## instance_id -> { category: int, team_id: int, gameplay_id: StringName }
var _entries: Dictionary = {}
## Categories that participate in the shared invalidation path.
var _category_index: Dictionary = {}


func _ready() -> void:
	var match_session: Node = get_node_or_null("/root/MatchSession")
	if match_session != null and match_session.has_method(&"register_match_reset"):
		match_session.call(&"register_match_reset", &"EntityRegistry", clear)


func clear() -> void:
	_entries.clear()
	_category_index.clear()


func register_entity(node: Variant) -> EntityHandle:
	if node == null or not is_instance_valid(node) or not (node is Node):
		return EntityHandle.empty()

	var live: Node = node as Node
	if not live.is_inside_tree():
		return EntityHandle.empty()

	var category: EntityHandle.Category = infer_category(live)
	var handle: EntityHandle = EntityHandle.from_node(
		live,
		category,
		EntityHandle.read_team_id(live),
		EntityHandle.read_gameplay_id(live)
	)
	if handle.is_empty():
		return handle

	var entry: Dictionary = {
		"category": handle.category,
		"team_id": handle.team_id,
		"gameplay_id": handle.gameplay_id,
	}
	var previous: Variant = _entries.get(handle.instance_id, null)
	_entries[handle.instance_id] = entry
	_index_add(handle.category, handle.instance_id)

	if previous == null:
		entity_registered.emit(handle.instance_id, int(handle.category), handle.team_id)
	return handle


func unregister_entity(node_or_id: Variant) -> void:
	var instance_id: int = _to_instance_id(node_or_id)
	if instance_id == 0:
		return
	_unregister_id(instance_id)


func unregister_by_id(instance_id: int) -> void:
	_unregister_id(instance_id)


func is_registered(instance_id: int) -> bool:
	return instance_id != 0 and _entries.has(instance_id)


func get_handle(instance_id: int) -> EntityHandle:
	if not _entries.has(instance_id):
		return EntityHandle.empty()

	var entry: Dictionary = _entries[instance_id]
	return EntityHandle.from_instance_id(
		instance_id,
		entry.get("category", EntityHandle.Category.NONE) as EntityHandle.Category,
		int(entry.get("team_id", -1)),
		StringName(str(entry.get("gameplay_id", "")))
	)


func make_handle_for(node: Variant) -> EntityHandle:
	var handle: EntityHandle = register_entity(node)
	if not handle.is_empty():
		return handle
	return EntityHandle.from_node(node)


## Resolve a handle safely. Never returns a freed object.
func resolve_handle(handle: EntityHandle) -> Node:
	if handle == null or handle.is_empty():
		return null

	if not _entries.has(handle.instance_id):
		## Allow resolve of non-registered live nodes without expanding the registry.
		return handle.resolve_without_registry()

	var entry: Dictionary = _entries[handle.instance_id]
	var expected_category: EntityHandle.Category = (
		handle.category if handle.category != EntityHandle.Category.NONE
		else entry.get("category", EntityHandle.Category.NONE) as EntityHandle.Category
	)
	var expected_team: int = handle.team_id if handle.team_id >= 0 else int(entry.get("team_id", -1))

	var node_ref: Variant = instance_from_id(handle.instance_id)
	if node_ref == null or not is_instance_valid(node_ref) or not (node_ref is Node):
		_unregister_id(handle.instance_id)
		return null

	var node: Node = node_ref as Node
	if node.is_queued_for_deletion() or not node.is_inside_tree():
		_unregister_id(handle.instance_id)
		return null

	var actual_category: EntityHandle.Category = infer_category(node)
	if not EntityHandle.category_matches(expected_category, actual_category):
		_unregister_id(handle.instance_id)
		return null

	if expected_team >= 0:
		var live_team: int = EntityHandle.read_team_id(node)
		if live_team >= 0 and live_team != expected_team:
			_unregister_id(handle.instance_id)
			return null

	_entries[handle.instance_id] = {
		"category": actual_category,
		"team_id": EntityHandle.read_team_id(node),
		"gameplay_id": EntityHandle.read_gameplay_id(node),
	}
	return node


func resolve_id(instance_id: int, expected_category: EntityHandle.Category = EntityHandle.Category.NONE) -> Node:
	return resolve_handle(EntityHandle.from_instance_id(instance_id, expected_category))


func get_registered_ids(category: EntityHandle.Category = EntityHandle.Category.NONE) -> Array[int]:
	var result: Array[int] = []
	if category == EntityHandle.Category.NONE:
		for instance_id: Variant in _entries.keys():
			result.append(int(instance_id))
		return result

	var bucket: Variant = _category_index.get(int(category), null)
	if bucket == null:
		return result
	for instance_id: Variant in (bucket as Dictionary).keys():
		if _entries.has(int(instance_id)):
			result.append(int(instance_id))
	return result


func count_registered(category: EntityHandle.Category = EntityHandle.Category.NONE) -> int:
	return get_registered_ids(category).size()


func infer_category(node: Node) -> EntityHandle.Category:
	if node == null or not is_instance_valid(node):
		return EntityHandle.Category.NONE
	if node.is_in_group(&"creep_camps"):
		return EntityHandle.Category.CREEP_CAMP
	if node.is_in_group(&"heroes"):
		return EntityHandle.Category.HERO
	if node.is_in_group(&"neutral_creeps"):
		return EntityHandle.Category.CREEP
	## Prefer script path checks to avoid hard class_name cycles.
	var script: Script = node.get_script() as Script
	var script_path: String = script.resource_path if script != null else ""
	if script_path.ends_with("tower.gd"):
		return EntityHandle.Category.TOWER
	if (
		script_path.ends_with("barracks.gd")
		or script_path.ends_with("command_center.gd")
		or script_path.ends_with("stable.gd")
		or script_path.ends_with("artillery_depot.gd")
		or script_path.ends_with("hero_altar.gd")
	):
		return EntityHandle.Category.PRODUCTION_BUILDING
	if script_path.contains("/buildings/") or node is StaticBody3D:
		## Building base and most structures are StaticBody3D.
		if node.has_method(&"destroy_building") or node.has_signal(&"destroyed"):
			return EntityHandle.Category.BUILDING
	if node is CharacterBody3D:
		return EntityHandle.Category.UNIT
	return EntityHandle.Category.NONE


func _unregister_id(instance_id: int) -> void:
	if not _entries.has(instance_id):
		return

	var entry: Dictionary = _entries[instance_id]
	var category: int = int(entry.get("category", EntityHandle.Category.NONE))
	var team_id: int = int(entry.get("team_id", -1))
	_entries.erase(instance_id)
	_index_remove(category, instance_id)
	entity_unregistered.emit(instance_id, category, team_id)


func _index_add(category: EntityHandle.Category, instance_id: int) -> void:
	var key: int = int(category)
	if not _category_index.has(key):
		_category_index[key] = {}
	(_category_index[key] as Dictionary)[instance_id] = true


func _index_remove(category: int, instance_id: int) -> void:
	if not _category_index.has(category):
		return
	var bucket: Dictionary = _category_index[category]
	bucket.erase(instance_id)
	if bucket.is_empty():
		_category_index.erase(category)


func _to_instance_id(node_or_id: Variant) -> int:
	if node_or_id == null:
		return 0
	if typeof(node_or_id) == TYPE_INT:
		return int(node_or_id)
	if typeof(node_or_id) == TYPE_OBJECT:
		var obj: Object = node_or_id as Object
		if obj != null:
			return obj.get_instance_id()
	return 0
