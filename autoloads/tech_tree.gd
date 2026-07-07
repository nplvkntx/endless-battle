extends Node

## Global manager for technology research and unlock state.
## Command Center tier is tracked per building; this autoload exposes the
## highest completed tier owned by a player team for future unlock checks.

signal tech_unlocked(tech_id: StringName)
signal research_started(tech_id: StringName)
signal research_completed(tech_id: StringName)
signal research_failed(tech_id: StringName, reason: StringName)

const PLAYER_TEAM_ID: int = 0
const ENEMY_TEAM_ID: int = TeamVisuals.ENEMY_TEAM_ID

const BLACKSMITH_REQUIRES_TIER_2_MESSAGE := "Requires Command Center Tier 2"
const STABLE_REQUIRES_TIER_2_AND_BLACKSMITH_MESSAGE := (
	"Requires Command Center Tier 2 and Blacksmith"
)
const ARTILLERY_DEPOT_REQUIRES_TIER_3_AND_BLACKSMITH_MESSAGE := (
	"Requires Command Center Tier 3 and Blacksmith"
)
const ADVANCED_UNIT_REQUIRES_BLACKSMITH_MESSAGE := "Requires Blacksmith"

signal progression_changed(team_id: int)


func _ready() -> void:
	# TODO: Load tech definitions from Resource files.
	call_deferred("_connect_progression_watchers")


func _connect_progression_watchers() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	if not tree.node_added.is_connected(_on_scene_node_added):
		tree.node_added.connect(_on_scene_node_added)

	for node: Node in tree.get_nodes_in_group(&"buildings"):
		_watch_progression_node(node)

	for node: Node in tree.get_nodes_in_group(&"player_command_center"):
		_watch_progression_node(node)

	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		_watch_progression_node(node)


func _on_scene_node_added(node: Node) -> void:
	_watch_progression_node(node)


func _watch_progression_node(node: Node) -> void:
	if node is Blacksmith:
		_watch_blacksmith(node as Blacksmith)
	elif node is CommandCenter:
		_watch_command_center(node as CommandCenter)


func _watch_blacksmith(blacksmith: Blacksmith) -> void:
	if blacksmith.has_meta(&"_tech_tree_watched"):
		return

	blacksmith.set_meta(&"_tech_tree_watched", true)

	if not blacksmith.building_state_changed.is_connected(_on_blacksmith_state_changed):
		blacksmith.building_state_changed.connect(
			_on_blacksmith_state_changed.bind(blacksmith)
		)

	var health_component: HealthComponent = (
		blacksmith.get_node_or_null("HealthComponent") as HealthComponent
	)
	if (
		health_component != null
		and health_component.has_signal("health_depleted")
		and not health_component.health_depleted.is_connected(_on_blacksmith_destroyed)
	):
		health_component.health_depleted.connect(
			_on_blacksmith_destroyed.bind(blacksmith)
		)


func _watch_command_center(command_center: CommandCenter) -> void:
	if command_center.has_meta(&"_tech_tree_tier_watched"):
		return

	command_center.set_meta(&"_tech_tree_tier_watched", true)

	if not command_center.tier_state_changed.is_connected(_on_command_center_tier_changed):
		command_center.tier_state_changed.connect(
			_on_command_center_tier_changed.bind(command_center)
		)


func _on_blacksmith_state_changed(state: StringName, blacksmith: Blacksmith) -> void:
	if state != Building.STATE_COMPLETED:
		return

	if not NodeSafety.is_alive_node(blacksmith):
		return

	_emit_progression_changed_for_team(TeamVisuals.resolve_team(blacksmith, blacksmith.team_id))


func _on_blacksmith_destroyed(blacksmith: Blacksmith) -> void:
	if not NodeSafety.is_alive_node(blacksmith):
		return

	var resolved_team: int = TeamVisuals.resolve_team(blacksmith, blacksmith.team_id)
	call_deferred("_emit_progression_changed_for_team", resolved_team)


func _on_command_center_tier_changed(command_center: CommandCenter) -> void:
	if not NodeSafety.is_alive_node(command_center):
		return

	if command_center.building_state != Building.STATE_COMPLETED:
		return

	_emit_progression_changed_for_team(
		TeamVisuals.resolve_team(command_center, command_center.team_id)
	)


func _emit_progression_changed_for_team(team_id: int) -> void:
	if team_id < 0:
		return

	progression_changed.emit(team_id)


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


func player_has_completed_blacksmith(team_id: int = PLAYER_TEAM_ID) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false

	for node: Node in tree.get_nodes_in_group(&"buildings"):
		if not NodeSafety.is_alive_node(node):
			continue
		if not node is Blacksmith:
			continue

		var blacksmith: Blacksmith = node as Blacksmith
		if blacksmith.building_state != Building.STATE_COMPLETED:
			continue
		if TeamVisuals.resolve_team(blacksmith, blacksmith.team_id) != team_id:
			continue

		return true

	return false


func can_build_blacksmith(team_id: int = PLAYER_TEAM_ID) -> bool:
	return player_has_tier_2(team_id)


func can_build_stable(team_id: int = PLAYER_TEAM_ID) -> bool:
	return player_has_tier_2(team_id) and player_has_completed_blacksmith(team_id)


func can_build_artillery_depot(team_id: int = PLAYER_TEAM_ID) -> bool:
	return player_has_tier_3(team_id) and player_has_completed_blacksmith(team_id)


func can_train_swordsman_or_archer(team_id: int = PLAYER_TEAM_ID) -> bool:
	return player_has_completed_blacksmith(team_id)
