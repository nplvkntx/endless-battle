extends Node

## Observe the real map/economy without player pressure; no resource grants.
## Speed up wall-clock playback while keeping the normal 1/60 physics step.
func _ready() -> void:
	seed(9122026)
	MatchSession.set_ai_difficulty(AIDifficultyConfig.Difficulty.HARD)
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = 4.0
	var match_root: Node = load("res://scenes/main.tscn").instantiate()
	add_child(match_root)
	await get_tree().process_frame
	await get_tree().process_frame
	var ai: EnemyAI = match_root.get_node("MatchSystems/EnemyAI") as EnemyAI
	# Keep the observation running if the unattended player loses its base.
	for base: Node in get_tree().get_nodes_in_group(&"player_command_center"):
		var health: HealthComponent = base.get_node("HealthComponent") as HealthComponent
		health.max_health = 1000000
		health.current_health = 1000000
	var reached_t2: bool = false
	var reached_t3: bool = false
	var expanded: bool = false
	for sample: int in 40:
		await get_tree().create_timer(15.0).timeout
		ai._read_live_world()
		reached_t2 = reached_t2 or int(ai._w.tier) >= 2
		reached_t3 = reached_t3 or int(ai._w.tier) >= 3
		expanded = expanded or ai._w.expansion_cc != null
		print("PROGRESSION t=%d tier=%d gold=%d wood=%d workers=%d wood_workers=%d army=%d bases=%d camps=%d decision=%s" % [
			(sample + 1) * 15, int(ai._w.tier), int(ai._w.gold), int(ai._w.wood),
			(ai._w.workers as Array).size(), int(ai._w.wood_workers), (ai._w.army as Array).size(),
			(ai._w.command_centers as Array).size(), CreepCampSafety.collect_active_camps(get_tree()).size(), ai.get_debug_priority()
		])
		if sample % 4 == 3:
			for worker: Worker in ai._w.workers:
				if worker.get_assigned_gather_resource_id() == &"wood":
					print("WOOD worker=%s pos=%s state=%d carry=%d moving=%s source=%s destination=%s recovery=%s" % [worker.name, worker.global_position, worker._gather_state, worker._carried_amount, worker.has_move_target, worker._gather_source, worker.get_movement_destination(), WorkerAiUnstuck.blocks_external_commands(worker)])
		if reached_t3 and expanded:
			break
	var passed: bool = reached_t2 and reached_t3 and expanded
	print("%s enemy_progression T2=%s T3=%s expansion=%s" % ["PASS" if passed else "FAIL", reached_t2, reached_t3, expanded])
	get_tree().quit(0 if passed else 1)
