class_name EnemyWaveManager
extends Node

## Sends gathered enemy combat units to attack the player Command Center on a timer.

const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"

@export var player_command_center_path: NodePath
@export var wave_interval_seconds: float = 30.0

var _wave_active: bool = true
var _tracked_player_command_center: CommandCenter = null


func _ready() -> void:
	_tracked_player_command_center = _resolve_player_command_center()
	if _tracked_player_command_center != null:
		_tracked_player_command_center.destroyed.connect(
			_on_player_command_center_destroyed,
			CONNECT_ONE_SHOT
		)
	_schedule_next_wave()


func _schedule_next_wave() -> void:
	if not _wave_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(wave_interval_seconds)
	wait_timer.timeout.connect(_on_wave_timer, CONNECT_ONE_SHOT)


func _on_wave_timer() -> void:
	if not _wave_active:
		return

	var target: CommandCenter = _resolve_player_command_center()
	if target == null or not _is_living_command_center(target):
		_wave_active = false
		return

	_send_enemy_combat_units_to_attack(target)
	_schedule_next_wave()


func _send_enemy_combat_units_to_attack(target: CommandCenter) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		if not _is_valid_enemy_combat_unit(node):
			continue

		if node is Swordsman:
			(node as Swordsman).command_attack(target)
		elif node is Archer:
			(node as Archer).command_attack(target)


func _is_valid_enemy_combat_unit(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not node.is_in_group(&"enemies"):
		return false

	return node is Swordsman or node is Archer


func _resolve_player_command_center() -> CommandCenter:
	if _tracked_player_command_center != null and _is_living_command_center(
		_tracked_player_command_center
	):
		return _tracked_player_command_center

	if not player_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(player_command_center_path)
		if path_node is CommandCenter and _is_living_command_center(path_node as CommandCenter):
			return path_node as CommandCenter

	for node: Node in get_tree().get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_command_center(node as CommandCenter):
			return node as CommandCenter

	return null


func _is_living_command_center(command_center: CommandCenter) -> bool:
	if command_center == null or not is_instance_valid(command_center):
		return false

	if command_center.is_queued_for_deletion():
		return false

	var health_component: HealthComponent = command_center.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


func _on_player_command_center_destroyed(_building: Building) -> void:
	_wave_active = false
	_tracked_player_command_center = null
