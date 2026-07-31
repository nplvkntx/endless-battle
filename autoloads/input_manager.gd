extends Node

## Global input routing for selection, commands, and camera controls.
## Translates raw input into game commands via signals — no direct unit control here.

signal selection_requested(screen_position: Vector2)
signal move_command_requested(world_position: Vector3)
signal build_command_requested(building_id: StringName)

var attack_move_armed: bool = false
var patrol_armed: bool = false


func _ready() -> void:
	MatchSession.register_match_reset(&"InputManager", disarm_all_command_modes)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return

		if key_event.keycode == KEY_A:
			arm_attack_move()
		elif key_event.keycode == KEY_P:
			arm_patrol()


func arm_attack_move() -> void:
	patrol_armed = false
	attack_move_armed = true


func disarm_attack_move() -> void:
	attack_move_armed = false


func arm_patrol() -> void:
	attack_move_armed = false
	patrol_armed = true


func disarm_patrol() -> void:
	patrol_armed = false


func disarm_all_command_modes() -> void:
	attack_move_armed = false
	patrol_armed = false
