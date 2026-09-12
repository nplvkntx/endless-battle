class_name WorkerArtVisuals
extends Node

## Presentation only. Worker remains the authority for jobs, movement and combat.
var _worker: Worker
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _last_team: int = -999
var _last_work: StringName = &""
var _last_move: StringName = &""


func _ready() -> void:
	_worker = get_parent() as Worker
	_model = _worker.get_node("MeshInstance3D/WorkerModel") as Node3D
	for child: Node in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(child as MeshInstance3D)
	_update_art()


func _process(_delta: float) -> void:
	_update_art()


func _update_art() -> void:
	if not NodeSafety.is_alive_node(_worker):
		return
	var carrying: bool = (
		_worker.is_carrying_gathered_resources()
		and _worker._gather_state != Worker.GatherTripState.GATHER_WAIT
	)
	var wood: bool = carrying and _worker.get_assigned_gather_resource_id() == &"wood"
	var gold: bool = carrying and _worker.get_assigned_gather_resource_id() == &"gold"
	var work: StringName = (
		&"Build"
		if _worker._build_trip_state == Worker.BuildTripState.CONSTRUCTION_WAIT
		else (&"Chop" if _worker.get_assigned_gather_resource_id() == &"wood" else &"Mine")
	)
	var move: StringName = &"CarryWood" if wood else (&"CarryGold" if gold else &"Walk")
	var team_changed: bool = _last_team != _worker.team_id
	if not team_changed and work == _last_work and move == _last_move:
		return

	if team_changed:
		_last_team = _worker.team_id
		for mesh: MeshInstance3D in _meshes:
			for surface: int in mesh.mesh.get_surface_count():
				var original: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if original != null and original.resource_name == "TeamCloth":
					var cloth: StandardMaterial3D = original.duplicate() as StandardMaterial3D
					cloth.albedo_color = (
						Color(0.55, 0.065, 0.035) if _last_team == 1 else Color(0.035, 0.13, 0.44)
					)
					mesh.set_surface_override_material(surface, cloth)
	for mesh: MeshInstance3D in _meshes:
		if String(mesh.name).begins_with("CargoWood"):
			mesh.visible = wood
		elif String(mesh.name).begins_with("CargoGold"):
			mesh.visible = gold
		elif String(mesh.name).begins_with("Tool_"):
			mesh.visible = not carrying
	if _worker._visual_animator != null and (work != _last_work or move != _last_move):
		_last_work = work
		_last_move = move
		_worker._visual_animator.set_clip_preferences({
			UnitVisualAnimator.STATE_WORK: [work],
			UnitVisualAnimator.STATE_MOVE: [move],
			UnitVisualAnimator.STATE_IDLE: [
				&"CarryWoodIdle" if wood else (&"CarryGoldIdle" if gold else &"Idle")
			],
		})
	else:
		_last_work = work
		_last_move = move


func create_death_model() -> Node3D:
	# Detached visuals can fall after the dead gameplay entity is removed.
	var corpse: Node3D = _model.duplicate() as Node3D
	corpse.transform = _model.global_transform
	corpse.set_meta(&"worker_animated_corpse", true)
	return corpse
