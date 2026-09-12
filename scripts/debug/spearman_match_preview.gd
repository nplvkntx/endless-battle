extends Node

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var soldiers: Array[Spearman] = []
	for team: int in 2:
		var soldier: Spearman = load("res://scenes/units/spearman.tscn").instantiate() as Spearman
		soldier.team_id = team
		soldier.position = Vector3(-25, 0.5, -18 + team * 1.8)
		main.add_child(soldier)
		soldiers.append(soldier)
	var camera: Camera3D = main.get_node("Camera3D") as Camera3D
	var focus := Vector3(-25, 0.7, -17.1)
	camera.global_position = focus + Vector3(4, 4, 5)
	camera.look_at(focus)
	soldiers[0].command_attack(soldiers[1])
	soldiers[1].command_attack(soldiers[0])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			camera.set_process(false)
			await get_tree().create_timer(1.7).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture="))
			print("SPEARMAN_MATCH health=", soldiers[0]._health_component.current_health, ",", soldiers[1]._health_component.current_health)
			get_tree().quit()
