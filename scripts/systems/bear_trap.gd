class_name BearTrap
extends Node3D

## Placeable one-shot trap. Roots and damages the first enemy that walks over it.
## Registered in a group so enemy AI can avoid visible traps when pathing.

signal trap_triggered(target: Unit)
signal trap_expired()

const GROUP_NAME := &"bear_traps"
const ACTIVATION_EFFECT_SCENE_PATH := "res://scenes/effects/bear_trap_activation_effect.tscn"

@export var trigger_radius: float = RangerStats.BEAR_TRAP_TRIGGER_RADIUS
@export var lifetime: float = RangerStats.BEAR_TRAP_LIFETIME
@export var root_duration: float = RangerStats.BEAR_TRAP_ROOT_DURATION
@export var damage: float = float(RangerStats.BEAR_TRAP_DAMAGE)
@export var tick_interval: float = 0.08

var source_unit: Unit = null
var source_team_id: int = -1
var _remaining: float = 0.0
var _tick_accumulator: float = 0.0
var _triggered: bool = false
var _jaw_mesh: MeshInstance3D = null
var _base_mesh: MeshInstance3D = null


func configure(
	trap_damage: float,
	trap_root_duration: float,
	trap_lifetime: float,
	trap_radius: float,
	source: Unit
) -> void:
	damage = trap_damage
	root_duration = trap_root_duration
	lifetime = trap_lifetime
	trigger_radius = trap_radius
	source_unit = source
	if source != null and is_instance_valid(source):
		source_team_id = source.team_id


func _ready() -> void:
	_remaining = lifetime
	add_to_group(GROUP_NAME)
	_build_visuals()
	set_physics_process(true)


func _exit_tree() -> void:
	if is_in_group(GROUP_NAME):
		remove_from_group(GROUP_NAME)


func _physics_process(delta: float) -> void:
	if _triggered:
		return

	_remaining -= delta
	if _remaining <= 0.0:
		trap_expired.emit()
		queue_free()
		return

	_tick_accumulator += delta
	if _tick_accumulator < tick_interval:
		return
	_tick_accumulator = 0.0
	_scan_for_trigger()


func get_remaining_lifetime() -> float:
	return maxf(_remaining, 0.0)


func is_hostile_to(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if source_unit != null and is_instance_valid(source_unit):
		return CombatTargetValidation.are_hostile(source_unit, unit)
	return unit.team_id != source_team_id


## Returns true when an AI-controlled unit should try to path around this trap.
func should_be_avoided_by(unit: Unit) -> bool:
	return is_hostile_to(unit)


static func adjust_destination_away_from_traps(
	mover: Unit, destination: Vector3, avoid_radius: float = 2.25
) -> Vector3:
	if mover == null or not is_instance_valid(mover):
		return destination

	var tree: SceneTree = mover.get_tree()
	if tree == null:
		return destination

	var adjusted: Vector3 = destination
	adjusted.y = mover.global_position.y
	var avoid_radius_sq: float = avoid_radius * avoid_radius

	for node_variant: Variant in tree.get_nodes_in_group(GROUP_NAME):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is BearTrap:
			continue
		var trap: BearTrap = node_variant as BearTrap
		if not trap.should_be_avoided_by(mover):
			continue

		var to_dest: Vector3 = adjusted - trap.global_position
		to_dest.y = 0.0
		if to_dest.length_squared() > avoid_radius_sq:
			continue

		var push: Vector3 = to_dest
		if push.length_squared() < 0.001:
			var from_mover: Vector3 = mover.global_position - trap.global_position
			from_mover.y = 0.0
			push = from_mover if from_mover.length_squared() > 0.001 else Vector3.RIGHT
		push = push.normalized() * avoid_radius
		adjusted = trap.global_position + push
		adjusted.y = mover.global_position.y

	return adjusted


func _scan_for_trigger() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var radius_sq: float = trigger_radius * trigger_radius
	for group_name: StringName in [&"units", &"enemies", &"heroes"]:
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Unit:
				continue
			var unit: Unit = node_variant as Unit
			if unit is Building:
				continue
			if not is_hostile_to(unit):
				continue

			var offset: Vector3 = unit.global_position - global_position
			offset.y = 0.0
			if offset.length_squared() > radius_sq:
				continue

			_trigger_on(unit)
			return


func _trigger_on(unit: Unit) -> void:
	if _triggered or unit == null or not is_instance_valid(unit):
		return
	_triggered = true

	BearTrapRootBuff.apply(unit, source_unit, root_duration)
	# Reveal while rooted (breaks combat stealth).
	if unit.is_combat_hidden():
		unit.set_combat_hidden(false)

	if damage > 0.0:
		DamageService.apply_damage(
			unit,
			damage,
			source_unit,
			{DamageService.OPT_EMPHASIZE_FLOAT: true}
		)

	_spawn_activation_effect()
	trap_triggered.emit(unit)
	queue_free()


func _spawn_activation_effect() -> void:
	ImpactEffects.play_ground_impact(global_position, 1.2)
	if not ResourceLoader.exists(ACTIVATION_EFFECT_SCENE_PATH):
		return

	var effect: Node3D = load(ACTIVATION_EFFECT_SCENE_PATH).instantiate() as Node3D
	if effect == null:
		return

	var parent: Node = get_parent()
	if parent == null:
		var tree: SceneTree = get_tree()
		parent = tree.current_scene if tree != null else null
	if parent == null:
		effect.queue_free()
		return

	parent.add_child(effect)
	effect.global_position = global_position + Vector3(0.0, 0.05, 0.0)


func _build_visuals() -> void:
	_base_mesh = MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 0.35
	base.bottom_radius = 0.4
	base.height = 0.06
	_base_mesh.mesh = base
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.22, 0.18, 0.14, 1.0)
	base_mat.metallic = 0.35
	base_mat.roughness = 0.55
	_base_mesh.material_override = base_mat
	_base_mesh.position = Vector3(0.0, 0.03, 0.0)
	add_child(_base_mesh)

	_jaw_mesh = MeshInstance3D.new()
	var jaw := TorusMesh.new()
	jaw.inner_radius = 0.18
	jaw.outer_radius = 0.34
	_jaw_mesh.mesh = jaw
	var jaw_mat := StandardMaterial3D.new()
	jaw_mat.albedo_color = Color(0.45, 0.42, 0.4, 1.0)
	jaw_mat.metallic = 0.75
	jaw_mat.roughness = 0.3
	jaw_mat.emission_enabled = true
	jaw_mat.emission = Color(0.35, 0.2, 0.05, 1.0)
	jaw_mat.emission_energy_multiplier = 0.35
	_jaw_mesh.material_override = jaw_mat
	_jaw_mesh.position = Vector3(0.0, 0.08, 0.0)
	add_child(_jaw_mesh)

	# Placement pop
	scale = Vector3(0.2, 0.2, 0.2)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
