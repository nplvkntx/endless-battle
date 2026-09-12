extends Node3D

## Visual inspection scene: F6 to view imported animation clips in Godot.
func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.045, 0.065)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	environment.environment.ambient_light_energy = 0.45
	add_child(environment)
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.8
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 5.6, 9)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.8
	camera.current = true
	var clips: Array[StringName] = [&"Idle", &"Walk", &"Chop", &"Mine", &"CarryWood", &"CarryGold"]
	for i: int in clips.size():
		var model: Node3D = load("res://assets/art/endless_worker/worker.glb").instantiate() as Node3D
		add_child(model)
		model.position = Vector3(float(i % 3 - 1) * 2.7, 0, float(i / 3) * 3.2 - 1.6)
		model.rotation.y = -0.2
		var player: AnimationPlayer = UnitVisualAnimator._find_animation_player(model)
		player.get_animation(clips[i]).loop_mode = Animation.LOOP_LINEAR
		player.play(clips[i])
		for child: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = child as MeshInstance3D
			if String(mesh.name).begins_with("CargoWood"):
				mesh.visible = clips[i] == &"CarryWood"
			elif String(mesh.name).begins_with("CargoGold"):
				mesh.visible = clips[i] == &"CarryGold"
			elif String(mesh.name).begins_with("Tool_"):
				mesh.visible = i < 4
			if i >= 3:
				for surface: int in mesh.mesh.get_surface_count():
					var original: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
					if original != null and original.resource_name == "TeamCloth":
						var red: StandardMaterial3D = original.duplicate() as StandardMaterial3D
						red.albedo_color = Color(0.55, 0.065, 0.035)
						mesh.set_surface_override_material(surface, red)
		var label := Label3D.new()
		add_child(label)
		label.position = model.position + Vector3(0, 2.2, 0)
		label.text = String(clips[i])
		label.font_size = 48
		label.pixel_size = 0.007
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	await get_tree().create_timer(0.35).timeout
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture="))
			get_tree().quit()
