extends Node

## Tracks 1v1 win/loss when the main command centers are destroyed.

enum MatchState {
	PLAYING,
	VICTORY,
	DEFEAT,
}

const VICTORY_MESSAGE := "Victory"
const DEFEAT_MESSAGE := "Defeat"
const DEBUG_DESTROY_ENEMY_KEY := KEY_F8
const DEBUG_DESTROY_PLAYER_KEY := KEY_F9

@export var player_command_center_path: NodePath
@export var enemy_command_center_path: NodePath
@export var match_result_label_path: NodePath

var _match_state: MatchState = MatchState.PLAYING
var _player_command_center: CommandCenter
var _enemy_command_center: CommandCenter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player_command_center = _resolve_command_center(
		player_command_center_path,
		&"player_command_center"
	)
	_enemy_command_center = _resolve_command_center(
		enemy_command_center_path,
		&"enemy_command_center"
	)
	_connect_command_center(_player_command_center, _on_player_command_center_destroyed)
	_connect_command_center(_enemy_command_center, _on_enemy_command_center_destroyed)


func _unhandled_input(event: InputEvent) -> void:
	if _match_state != MatchState.PLAYING or not OS.is_debug_build():
		return

	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		DEBUG_DESTROY_ENEMY_KEY:
			_apply_debug_damage(_enemy_command_center)
		DEBUG_DESTROY_PLAYER_KEY:
			_apply_debug_damage(_player_command_center)


func _resolve_command_center(path: NodePath, fallback_group: StringName) -> CommandCenter:
	if not path.is_empty():
		var path_node: Node = get_node_or_null(path)
		if path_node is CommandCenter:
			return path_node as CommandCenter

	for node: Node in get_tree().get_nodes_in_group(fallback_group):
		if node is CommandCenter:
			return node as CommandCenter

	push_warning("MatchManager: missing command center for group %s" % fallback_group)
	return null


func _connect_command_center(command_center: CommandCenter, callback: Callable) -> void:
	if command_center == null or not is_instance_valid(command_center):
		return

	if not command_center.has_signal("destroyed"):
		push_warning("MatchManager: command center is missing destroyed signal")
		return

	if not command_center.destroyed.is_connected(callback):
		command_center.destroyed.connect(callback)


func _on_player_command_center_destroyed(_building: Building) -> void:
	_player_command_center = null
	_end_match(MatchState.DEFEAT, DEFEAT_MESSAGE)


func _on_enemy_command_center_destroyed(_building: Building) -> void:
	_enemy_command_center = null
	_end_match(MatchState.VICTORY, VICTORY_MESSAGE)


func _end_match(next_state: MatchState, _message: String) -> void:
	if _match_state != MatchState.PLAYING:
		return

	_match_state = next_state
	match next_state:
		MatchState.VICTORY:
			MatchSession.call_deferred("show_victory_screen")
		MatchState.DEFEAT:
			MatchSession.call_deferred("show_defeat_screen")


func _apply_debug_damage(command_center: CommandCenter) -> void:
	if command_center == null or not is_instance_valid(command_center):
		return

	if not command_center.has_method("take_damage"):
		return

	command_center.take_damage(999999.0)
