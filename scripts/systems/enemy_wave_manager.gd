class_name EnemyWaveManager
extends Node

## Launches scaled enemy attack waves on a timer and keeps the enemy hero with the army.

const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"

@export var player_command_center_path: NodePath
@export var wave_interval_seconds: float = 30.0

var _wave_active: bool = true
var _waves_launched: int = 0
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

	if not _has_any_attack_target():
		_wave_active = false
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var next_wave_number: int = _waves_launched + 1
	var min_non_hero_units: int = EnemyArmyCommand.get_min_non_hero_units_for_wave(
		next_wave_number
	)
	var wave_plan: Dictionary = EnemyArmyCommand.build_attack_wave_units(
		get_tree(),
		min_non_hero_units
	)

	if not wave_plan.get("can_launch", false):
		_hold_army_until_ready(rally_position, int(wave_plan.get("non_hero_count", 0)))
		_schedule_next_wave()
		return

	var attack_destination: Vector3 = EnemyArmyCommand.resolve_wave_attack_destination(
		get_tree(),
		rally_position
	)
	EnemyArmyCommand.command_attack_move(wave_plan.get("units", []), attack_destination)
	_waves_launched += 1
	_schedule_next_wave()


func _hold_army_until_ready(rally_position: Vector3, non_hero_count: int) -> void:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null:
		return

	var min_non_hero_units: int = EnemyArmyCommand.get_min_non_hero_units_for_wave(
		_waves_launched + 1
	)
	if non_hero_count >= min_non_hero_units:
		return

	EnemyArmyCommand.command_hold_at_rally([hero], rally_position)


func _has_any_attack_target() -> bool:
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	return EnemyArmyCommand.has_player_attack_targets(get_tree(), rally_position)


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
	_tracked_player_command_center = null
