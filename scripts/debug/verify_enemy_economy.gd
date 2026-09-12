extends Node

## Exercise real gather assignments on the real map, including a recovering miner.
const MATCH_SCENE := preload("res://scenes/main.tscn")
const WORKER_SCENE := preload("res://scenes/units/worker.tscn")
var failures: PackedStringArray = []

func _ready() -> void:
	var match_root: Node = MATCH_SCENE.instantiate()
	add_child(match_root)
	await get_tree().process_frame
	await get_tree().process_frame
	var ai: EnemyAI = match_root.get_node("MatchSystems/EnemyAI") as EnemyAI
	ai.set_process(false)
	ai._resolve_managers()
	ai._read_live_world()
	var cc: CommandCenter = ai._w.primary_cc as CommandCenter
	for i: int in 8:
		var worker: Worker = WORKER_SCENE.instantiate() as Worker
		worker.team_id = 1
		match_root.add_child(worker)
		worker.global_position = cc.global_position + Vector3(-7, 0, float(i))
		worker.add_to_group(&"enemy_workers")
		worker.add_to_group(&"enemies")
	await get_tree().process_frame
	ai._read_live_world()
	var workers: Array = ai._w.workers
	for worker: Worker in workers:
		worker.set_physics_process(false)
		worker._ai_unstuck_active = false
		worker._ai_unstuck_pending_stagger = 0.0
		worker._cancel_build_trip()
		ai._gather_manager.assign_gather_job(worker, true)
	var blocked: Worker = workers[0] as Worker
	blocked._ai_unstuck_active = true
	_expect("recovering miner rejects reassignment", not ai._gather_manager.assign_gather_job(blocked, false))
	_expect("recovering miner remains on gold", blocked.get_assigned_gather_resource_id() == &"gold")
	for tick: int in 8:
		ai._read_live_world()
		ai._maintain_worker_distribution()
		await get_tree().process_frame
	ai._read_live_world()
	_expect("other workers actually switch to wood", int(ai._w.wood_workers) >= 3)
	_expect("recovering first worker cannot starve wood allocation", blocked.get_assigned_gather_resource_id() == &"gold")
	for tree: WoodTree in ai._gather_manager._resolve_safe_trees():
		_expect("selected tree is usable and unguarded", tree.is_usable_by_faction(true) and WorkerGathering.is_safe_gather_source(tree, get_tree()))
	# Clear map guards so this checks discovery, not combat strength.
	for creep: Node in get_tree().get_nodes_in_group(&"neutral_creeps"):
		creep.queue_free()
	await get_tree().process_frame
	CreepCampSafety.reset_match_state()
	ai._read_live_world()
	var mine: GoldMine = ai._find_expansion_mine()
	_expect("expansion discovered through real resource registry", mine != null)
	if mine != null:
		var expansion: CommandCenter = load("res://scenes/buildings/command_center.tscn").instantiate() as CommandCenter
		expansion.team_id = 1
		match_root.add_child(expansion)
		expansion.global_position = mine.global_position + Vector3(-7, 0, 0)
		expansion.set_completed()
		expansion.add_to_group(&"enemy_command_center")
		expansion.remove_from_group(&"player_command_center")
		await get_tree().process_frame
		_expect("new base mine can receive workers", ai._gather_manager._resolve_gold_mine(mine.global_position) == mine)
	print("ECONOMY workers=%d gold=%d wood=%d" % [workers.size(), int(ai._w.gold_workers), int(ai._w.wood_workers)])
	print("PASS enemy_economy" if failures.is_empty() else "FAIL enemy_economy\n" + "\n".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
	print(("ok: " if ok else "FAIL: ") + label)
