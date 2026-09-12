extends Node3D

var failures: PackedStringArray = []


func _ready() -> void:
	var worker: Worker = load("res://scenes/units/worker.tscn").instantiate() as Worker
	add_child(worker)
	worker.set_physics_process(false)
	await get_tree().process_frame
	var model: Node3D = worker.get_node("MeshInstance3D/WorkerModel") as Node3D
	var animator: AnimationPlayer = UnitVisualAnimator._find_animation_player(model)
	check(animator != null, "model has animation player")
	if animator == null:
		get_tree().quit(1)
		return
	for clip: StringName in [&"Idle", &"Walk", &"Run", &"Attack", &"Chop", &"Mine", &"CarryWood", &"CarryGold", &"Build", &"Repair", &"Death"]:
		check(animator.has_animation(clip), "imported clip " + String(clip))
	var art: WorkerArtVisuals = worker.get_node("WorkerArtVisuals") as WorkerArtVisuals
	for mesh: MeshInstance3D in art._meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material.resource_name.begins_with("Worker"):
				check(material.vertex_color_use_as_albedo, "import preserves vertex paint")
			elif material.resource_name == "TeamCloth":
				check(not material.vertex_color_use_as_albedo, "team colour is independent of vertex paint")
	worker._assigned_resource_id = &"wood"
	worker._gather_state = Worker.GatherTripState.GATHER_WAIT
	worker._carried_amount = 4
	art._update_art()
	worker._visual_animator.set_loop_state(UnitVisualAnimator.LoopState.WORK)
	check(animator.current_animation == "Chop", "wood job plays chop")
	check(not _any_visible(model, "CargoWood"), "gathering keeps cargo hidden")
	check(_any_visible(model, "Tool_"), "gathering shows hammer")
	worker._gather_state = Worker.GatherTripState.TO_COMMAND_CENTER
	art._update_art()
	worker._visual_animator.set_loop_state(UnitVisualAnimator.LoopState.MOVE)
	check(animator.current_animation == "CarryWood", "wood delivery plays carry")
	check(_any_visible(model, "CargoWood") and not _any_visible(model, "CargoGold"), "wood delivery shows only logs")
	worker._assigned_resource_id = &"gold"
	art._update_art()
	worker._visual_animator.set_loop_state(UnitVisualAnimator.LoopState.MOVE)
	check(animator.current_animation == "CarryGold", "gold delivery plays carry")
	check(_any_visible(model, "CargoGold") and not _any_visible(model, "CargoWood"), "gold delivery shows only sack")
	worker._gather_state = Worker.GatherTripState.GATHER_WAIT
	art._update_art()
	worker._visual_animator.set_loop_state(UnitVisualAnimator.LoopState.WORK)
	check(animator.current_animation == "Mine", "gold job plays mine")
	worker._build_trip_state = Worker.BuildTripState.CONSTRUCTION_WAIT
	art._update_art()
	worker._visual_animator.set_loop_state(UnitVisualAnimator.LoopState.WORK)
	check(animator.current_animation == "Build", "construction plays build")
	worker.team_id = 1
	art._update_art()
	var red: bool = false
	for mesh: MeshInstance3D in art._meshes:
		for index: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.get_surface_override_material(index) as StandardMaterial3D
			if material != null and material.resource_name == "TeamCloth":
				red = material.albedo_color.r > material.albedo_color.b
	check(red, "enemy scarf is red")
	DeathEffects.clear_all()
	DeathEffects.play_unit_death(worker)
	check(DeathEffects.get_active_corpse_count() == 1, "one corpse visual registered")
	var corpse: Node3D = DeathEffects._active_corpses[0].get("node") as Node3D
	check(corpse.has_meta(&"worker_animated_corpse"), "worker death uses its model")
	check(UnitVisualAnimator._find_animation_player(corpse).current_animation == "Death", "corpse plays death")
	worker.queue_free()
	await get_tree().process_frame
	DeathEffects.clear_all()
	check(DeathEffects.get_active_corpse_count() == 0, "match reset clears model corpses")
	print("PASS worker_art" if failures.is_empty() else "FAIL worker_art: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func _any_visible(root: Node, prefix: String) -> bool:
	for node: Node in root.find_children(prefix + "*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).visible:
			return true
	return false


func check(ok: bool, label: String) -> void:
	print("  OK " if ok else "  FAIL ", label)
	if not ok:
		failures.append(label)
