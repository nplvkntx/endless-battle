extends Node

## Real battlefield with the camera near a player worker. Gameplay stays live.
func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var camera: Camera3D = main.get_node("Camera3D") as Camera3D
	var worker: Worker = main.get_node("PlayerStartingBase/Worker5") as Worker
	var best: WoodTree = null
	var nearest: float = INF
	for resource: Node in WorkerGathering.get_gatherable_resources(get_tree(), main):
		if resource is WoodTree and resource.is_usable_by_faction(false) and WorkerGathering.is_safe_gather_source(resource, get_tree()):
			var distance: float = resource.global_position.distance_squared_to(worker.global_position)
			if distance < nearest:
				best = resource as WoodTree
				nearest = distance
	if best != null:
		worker.command_gather_tree(best, false)
	camera.global_position = worker.global_position + Vector3(0, 8, 9)
	camera.look_at(worker.global_position)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			camera.set_process(false)
			for i: int in 3:
				await get_tree().create_timer(4.0).timeout
				var focus: Vector3 = worker.global_position
				camera.global_position = focus + Vector3(3, 5.5, 6.5)
				camera.look_at(focus + Vector3(0, 0.2, 0))
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=") + "-%d.png" % i)
				print("WORKER_MATCH state=", worker._gather_state, " carried=", worker._carried_amount, " clip=", worker._visual_animator._animation_player.current_animation)
			get_tree().quit()
