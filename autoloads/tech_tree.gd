extends Node

## Global manager for technology research and unlock state.
## Command Center tier is tracked per building; this autoload exposes the
## highest completed tier owned by a player team for future unlock checks.

signal tech_unlocked(tech_id: StringName)
signal research_started(tech_id: StringName)
signal research_completed(tech_id: StringName)
signal research_failed(tech_id: StringName, reason: StringName)

const PLAYER_TEAM_ID: int = 0


func _ready() -> void:
	# TODO: Load tech definitions from Resource files.
	pass


func get_highest_command_center_tier(team_id: int = PLAYER_TEAM_ID) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return CommandCenter.MIN_TIER

	var group_name: StringName = (
		&"player_command_center" if team_id == PLAYER_TEAM_ID else &"enemy_command_center"
	)
	var highest: int = CommandCenter.MIN_TIER

	for node: Node in tree.get_nodes_in_group(group_name):
		if not NodeSafety.is_alive_node(node):
			continue
		if not node is CommandCenter:
			continue

		var command_center: CommandCenter = node as CommandCenter
		if command_center.team_id != team_id:
			continue
		if command_center.building_state != Building.STATE_COMPLETED:
			continue

		highest = maxi(highest, command_center.command_center_tier)

	return highest


func player_has_tier_2(team_id: int = PLAYER_TEAM_ID) -> bool:
	return get_highest_command_center_tier(team_id) >= 2


func player_has_tier_3(team_id: int = PLAYER_TEAM_ID) -> bool:
	return get_highest_command_center_tier(team_id) >= 3
