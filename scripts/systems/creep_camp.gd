class_name CreepCamp
extends Node3D

## Owns a neutral creep camp: snapshots spawn layout and respawns after clear.

const RESPAWN_DELAY_SECONDS: float = 180.0
const CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")

var _spawn_configs: Array[Dictionary] = []
var _respawn_timer: float = -1.0
var _waiting_to_respawn: bool = false


func _ready() -> void:
	add_to_group(&"creep_camps")
	_capture_spawn_configs()


func _process(delta: float) -> void:
	if not _waiting_to_respawn:
		return

	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		return

	if not CreepCampSafety.is_camp_area_clear(global_position, get_tree()):
		return

	_respawn_camp()
	_waiting_to_respawn = false
	_respawn_timer = -1.0


func alert_camp_to_attacker(attacker: Unit, excluding: NeutralCreep = null) -> void:
	if not NodeSafety.is_alive_node(attacker):
		return

	for child: Node in get_children():
		if child == excluding:
			continue

		if not child is NeutralCreep:
			continue

		var creep: NeutralCreep = child as NeutralCreep
		if not NodeSafety.is_alive_node(creep):
			continue

		creep.alert_to_attacker(attacker)


func notify_creep_died(_creep: Node) -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return

	if not is_inside_tree():
		return

	if _has_living_creeps():
		return

	_start_respawn_timer()


func _capture_spawn_configs() -> void:
	_spawn_configs.clear()

	for child: Node in get_children():
		if not child is NeutralCreep:
			continue

		var creep: NeutralCreep = child as NeutralCreep
		_spawn_configs.append({
			"name": child.name,
			"transform": child.transform,
			"attack_damage": creep.attack_damage,
			"attack_cooldown": creep.attack_cooldown,
		})


func _start_respawn_timer() -> void:
	_waiting_to_respawn = true
	_respawn_timer = RESPAWN_DELAY_SECONDS


func _respawn_camp() -> void:
	if _spawn_configs.is_empty():
		_capture_spawn_configs()

	for config: Dictionary in _spawn_configs:
		if config.is_empty():
			continue

		var creep: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
		if creep == null:
			continue

		creep.name = str(config.get("name", "Creep"))
		creep.attack_damage = int(config.get("attack_damage", creep.attack_damage))
		creep.attack_cooldown = float(config.get("attack_cooldown", creep.attack_cooldown))
		creep.transform = config.get("transform", Transform3D.IDENTITY) as Transform3D
		add_child(creep)


func _has_living_creeps() -> bool:
	for child: Node in get_children():
		if _is_living_creep(child):
			return true

	return false


func _is_living_creep(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node.is_queued_for_deletion():
		return false

	if not CombatTargetValidation.is_neutral_creep(node):
		return false

	return CombatTargetValidation.get_target_current_health(node) > 0
