class_name EntityHandle
extends RefCounted

## Lightweight safe reference to a gameplay entity.
## Stores identity only — never keeps a live Node that could become freed.
## Intentionally avoids referencing Unit/Building/Hero class_names to prevent
## GDScript cyclic parse dependencies with the gameplay registry.

enum Category {
	NONE = 0,
	UNIT = 1,
	HERO = 2,
	BUILDING = 3,
	CREEP = 4,
	CREEP_CAMP = 5,
	TOWER = 6,
	PRODUCTION_BUILDING = 7,
}

## Stable Godot Object instance id. 0 means empty.
var instance_id: int = 0
## Optional stable gameplay identity (kit id, train id, camp name, etc.).
var gameplay_id: StringName = &""
var category: Category = Category.NONE
## Faction / team when known. -1 means unset / neutral.
var team_id: int = -1


func is_valid() -> bool:
	return resolve() != null


func resolve() -> Node:
	if instance_id == 0:
		return null

	var registry: Node = _registry()
	if registry != null and registry.has_method(&"resolve_handle"):
		var via_registry: Variant = registry.call(&"resolve_handle", self)
		if via_registry == null:
			return null
		if via_registry is Node:
			return via_registry as Node
		return null

	return resolve_without_registry()


## Direct resolve used when EntityRegistry is unavailable.
func resolve_without_registry() -> Node:
	var node_ref: Variant = instance_from_id(instance_id)
	if node_ref == null or not is_instance_valid(node_ref):
		return null
	if not (node_ref is Node):
		return null

	var node: Node = node_ref as Node
	if node.is_queued_for_deletion():
		return null
	if not node.is_inside_tree():
		return null
	if team_id >= 0:
		var live_team: int = read_team_id(node)
		if live_team >= 0 and live_team != team_id:
			return null
	return node


func clear() -> void:
	instance_id = 0
	gameplay_id = &""
	category = Category.NONE
	team_id = -1


func matches(other_handle: EntityHandle) -> bool:
	if other_handle == null:
		return false
	if instance_id == 0 or other_handle.instance_id == 0:
		return false
	return instance_id == other_handle.instance_id


func is_empty() -> bool:
	return instance_id == 0


func duplicate_handle() -> EntityHandle:
	var copy := new() as EntityHandle
	copy.instance_id = instance_id
	copy.gameplay_id = gameplay_id
	copy.category = category
	copy.team_id = team_id
	return copy


static func from_node(
	node: Variant,
	p_category: Category = Category.NONE,
	p_team_id: int = -1,
	p_gameplay_id: StringName = &""
) -> EntityHandle:
	var handle := new() as EntityHandle
	if node == null or not is_instance_valid(node) or not (node is Node):
		return handle

	var live: Node = node as Node
	handle.instance_id = live.get_instance_id()
	handle.category = p_category
	handle.team_id = p_team_id if p_team_id >= 0 else read_team_id(live)
	handle.gameplay_id = p_gameplay_id if p_gameplay_id != &"" else read_gameplay_id(live)
	return handle


static func from_instance_id(
	p_instance_id: int,
	p_category: Category = Category.NONE,
	p_team_id: int = -1,
	p_gameplay_id: StringName = &""
) -> EntityHandle:
	var handle := new() as EntityHandle
	if p_instance_id == 0:
		return handle
	handle.instance_id = p_instance_id
	handle.category = p_category
	handle.team_id = p_team_id
	handle.gameplay_id = p_gameplay_id
	return handle


static func empty() -> EntityHandle:
	return new() as EntityHandle


static func category_matches(expected: Category, actual: Category) -> bool:
	if expected == Category.NONE:
		return true
	if expected == actual:
		return true
	if expected == Category.BUILDING and (
		actual == Category.PRODUCTION_BUILDING or actual == Category.TOWER
	):
		return true
	if expected == Category.UNIT and (
		actual == Category.HERO or actual == Category.CREEP
	):
		return true
	return false


static func _registry() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/EntityRegistry")


static func read_team_id(node: Node) -> int:
	if node == null:
		return -1
	if "team_id" in node:
		return int(node.get("team_id"))
	return -1


static func read_gameplay_id(node: Node) -> StringName:
	if node == null:
		return &""
	if node.has_method(&"get_hero_kit_id"):
		var kit: Variant = node.call(&"get_hero_kit_id")
		if typeof(kit) == TYPE_STRING_NAME:
			return kit as StringName
		if typeof(kit) == TYPE_STRING:
			return StringName(kit)
	return StringName(node.name)
