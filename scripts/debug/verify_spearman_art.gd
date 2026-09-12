extends Node3D

func _ready() -> void:
	var soldier: Spearman = load("res://scenes/units/spearman.tscn").instantiate() as Spearman
	add_child(soldier)
	soldier.set_physics_process(false)
	var opponent: Spearman = load("res://scenes/units/spearman.tscn").instantiate() as Spearman
	opponent.team_id = 1
	add_child(opponent)
	opponent.position = Vector3(0,0,1.5)
	opponent.set_physics_process(false)
	await get_tree().process_frame
	var player: AnimationPlayer = UnitVisualAnimator._find_animation_player(soldier)
	var passed: bool = player != null
	for clip: StringName in [&"Idle", &"Walk", &"Run", &"Attack", &"AttackSweep", &"Hit", &"Guard", &"Death"]:
		passed = passed and player.has_animation(clip)
	var before: int = opponent._health_component.current_health
	soldier._attack_target = opponent
	passed = soldier._deliver_attack() and passed
	passed = passed and opponent._health_component.current_health < before and player.current_animation == "Attack"
	print("Strike damages target and plays Attack: ", passed)
	var red: bool = false
	for node: Node in opponent.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for index: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.get_surface_override_material(index) as StandardMaterial3D
			if material != null and material.resource_name == "TeamCloth":
				red = material.albedo_color.r > material.albedo_color.b
	passed = passed and red
	DeathEffects.clear_all()
	DeathEffects.play_unit_death(soldier)
	var corpse: Node3D = DeathEffects._active_corpses[0].get("node") as Node3D
	passed = passed and UnitVisualAnimator._find_animation_player(corpse).current_animation == "Death"
	DeathEffects.clear_all()
	print("PASS spearman_art" if passed else "FAIL spearman_art")
	get_tree().quit(0 if passed else 1)
