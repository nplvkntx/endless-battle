extends Node3D
var failed: bool = false
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	failed = failed or not ok

func _ready() -> void:
	var hero: MeleeHero = load("res://scenes/units/hero.tscn").instantiate() as MeleeHero
	add_child(hero)
	hero.set_physics_process(false)
	var enemy: Spearman = load("res://scenes/units/spearman.tscn").instantiate() as Spearman
	enemy.team_id = 1
	add_child(enemy)
	enemy.position = Vector3(0, 0, 1)
	enemy.set_physics_process(false)
	await get_tree().process_frame
	var player: AnimationPlayer = UnitVisualAnimator._find_animation_player(hero)
	check(player != null, "model animation player")
	if player == null:
		get_tree().quit(1)
		return
	var meshes: Array[Node] = hero.get_node("MeshInstance3D/PaladinModel").find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty() and (meshes[0] as MeshInstance3D).is_visible_in_tree(), "model visible")
	for clip: StringName in [&"Idle", &"Walk", &"Attack", &"GroundSlam", &"Invulnerability", &"PowerStrike", &"Execution", &"Death"]:
		check(player.has_animation(clip), "clip " + clip)
	check(player.current_animation == "Idle", "idle integration")
	hero.has_move_target = true
	hero._update_visual_animation()
	check(player.current_animation == "Walk", "walk integration")
	player.advance(0.25)
	hero.has_move_target = false
	hero._attack_target = enemy
	hero._stop_and_attack(0.01)
	check(player.current_animation == "Attack", "combat windup animation")
	var hp: int = enemy._health_component.current_health
	hero._tick_attack_windup(1.0)
	check(enemy._health_component.current_health < hp, "basic attack damage")
	hero.level = 16
	hero.ability_points = 20
	for id: StringName in [&"q", &"w", &"e", &"r"]:
		while hero.can_learn_ability(id):
			hero.try_learn_ability(id, false)
	hero.current_mana = 1000
	enemy._health_component.max_health = 10000
	enemy._health_component.current_health = 10000
	check(hero.try_cast_q() and player.current_animation == "GroundSlam", "Q cast animation")
	check(hero.try_cast_w() and player.current_animation == "Invulnerability", "W cast animation")
	hp = hero._health_component.current_health
	hero.take_damage(50, enemy)
	check(hero._health_component.current_health == hp, "W prevents damage")
	check(hero.try_cast_e(enemy), "E accepted")
	hero._process_power_strike(0.01)
	check(player.current_animation == "PowerStrike", "E animation")
	enemy._health_component.current_health = 1
	check(hero.try_cast_r(enemy), "R accepted")
	hero._process_execute(0.01)
	check(player.current_animation == "Execution", "R animation")
	hero._deactivate_divine_protection()
	DeathEffects.clear_all()
	hero._health_component.take_damage(100000)
	check(not DeathEffects._active_corpses.is_empty(), "death creates corpse")
	if not DeathEffects._active_corpses.is_empty():
		var corpse: Node3D = DeathEffects._active_corpses[0].get("node") as Node3D
		check(UnitVisualAnimator._find_animation_player(corpse).current_animation == "Death", "death animation")
	DeathEffects.clear_all()
	print("FAIL paladin_art" if failed else "PASS paladin_art")
	get_tree().quit(1 if failed else 0)
