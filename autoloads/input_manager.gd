extends Node

## Global input routing for selection, commands, and camera controls.
## Translates raw input into game commands via signals — no direct unit control here.

signal selection_requested(screen_position: Vector2)
signal move_command_requested(world_position: Vector3)
signal build_command_requested(building_id: StringName)

var attack_move_armed: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return

		if key_event.keycode == KEY_A:
			arm_attack_move()


func arm_attack_move() -> void:
	attack_move_armed = true


func disarm_attack_move() -> void:
	attack_move_armed = false
