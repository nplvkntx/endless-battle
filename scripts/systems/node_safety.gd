class_name NodeSafety
extends RefCounted

## Helpers for safely storing and iterating node references after queue_free.


static func is_alive_node(node: Variant) -> bool:
	if node == null:
		return false

	if not is_instance_valid(node):
		return false

	if node is Node and (node as Node).is_queued_for_deletion():
		return false

	return true


static func safe_node(node: Variant) -> Variant:
	if is_alive_node(node):
		return node

	return null


static func assign_node(_target: Variant, new_node: Variant) -> Variant:
	return safe_node(new_node)


static func clean_node_array(arr: Array) -> Array:
	return arr.filter(func(x: Variant) -> bool: return is_alive_node(x))


static func clean_invalid_units(arr: Array) -> Array:
	return clean_node_array(arr)


static func clean_node_dict_keys(dict: Dictionary) -> void:
	for key: Variant in dict.keys():
		if not is_alive_node(key):
			dict.erase(key)


static func clean_node_dict_values(dict: Dictionary) -> void:
	for key: Variant in dict.keys():
		if not is_alive_node(dict[key]):
			dict.erase(key)


static func purge_stale_instance_id_dict(dict: Dictionary) -> int:
	var removed: int = 0

	for instance_id: Variant in dict.keys():
		var node: Variant = instance_from_id(int(instance_id))
		if is_alive_node(node):
			continue

		dict.erase(instance_id)
		removed += 1

	return removed


static func prepare_node_for_death(node) -> void:
	if node == null or not is_instance_valid(node):
		return

	CombatTargetValidation.clear_target_combat_state(node)
