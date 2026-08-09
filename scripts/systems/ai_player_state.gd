class_name AIPlayerState
extends Node

## Match-owned enemy AI identity bag.
## Records which node is military_command_authority (SimpleWc3AI).

var military_command_authority_name: StringName = &""
var _military_command_authority: Variant = null


func reset_match_state() -> void:
	_military_command_authority = null
	military_command_authority_name = &""


func set_military_command_authority(authority: Variant) -> void:
	var raw: Variant = authority
	if raw == null or not is_instance_valid(raw) or not raw is Node:
		_military_command_authority = null
		military_command_authority_name = &""
		return
	var node: Node = raw as Node
	_military_command_authority = node
	military_command_authority_name = node.name


func get_military_command_authority() -> Node:
	var raw: Variant = _military_command_authority
	if raw != null and is_instance_valid(raw) and raw is Node:
		return raw as Node
	_military_command_authority = null
	return null
