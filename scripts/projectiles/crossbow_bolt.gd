class_name CrossbowBolt
extends Node3D

## Piercing heavy bolt fired by Ranger E. Travels in a straight line, damages
## multiple enemies, and reduces damage after each pierce via the combat pipeline.

const MAX_LIFETIME := 3.5

var _attacker: Node = null
var _damage: float = 0.0
var _direction: Vector3 = Vector3.ZERO
var _speed: float = RangerStats.CROSSBOW_BOLT_SPEED
var _max_travel: float = 0.0
var _traveled: float = 0.0
var _lifetime: float = 0.0
var _hit_radius: float = RangerStats.CROSSBOW_BOLT_HIT_RADIUS
var _pierce_mult: float = RangerStats.CROSSBOW_BOLT_PIERCE_DAMAGE_MULT
var _max_pierces: int = RangerStats.CROSSBOW_BOLT_MAX_PIERCES
var _hit_ids: Dictionary = {}
var _pierce_count: int = 0
var _trail: GPUParticles3D = null
var _impact_played: bool = false


func launch(
	direction: Vector3,
	damage: float,
	spawn_position: Vector3,
	max_range: float,
	attacker: Node = null,
	pierce_damage_mult: float = RangerStats.CROSSBOW_BOLT_PIERCE_DAMAGE_MULT
) -> void:
	_attacker = NodeSafety.safe_node(attacker) as Node
	_damage = damage
	_pierce_mult = pierce_damage_mult
	global_position = spawn_position
	PerfCounters.register_projectile()
	tree_exiting.connect(_on_bolt_tree_exiting, CONNECT_ONE_SHOT)

	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		queue_free()
		return

	_direction = flat.normalized()
	_max_travel = maxf(max_range, 0.5)
	look_at(global_position + _direction, Vector3.UP)
	_trail = ImpactEffects.attach_arrow_trail(self)


func _on_bolt_tree_exiting() -> void:
	_release_trail()
	PerfCounters.unregister_projectile()


func _release_trail() -> void:
	if _trail == null:
		return
	ImpactEffects.release_attached(_trail, ImpactFxPool.FxKind.ARROW_TRAIL)
	_trail = null


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME or _traveled >= _max_travel:
		_play_ground_miss()
		queue_free()
		return

	var step: float = _speed * delta
	global_position += _direction * step
	_traveled += step
	_try_hit_enemies()


func _try_hit_enemies() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var hit_radius_sq: float = _hit_radius * _hit_radius
	var safe_attacker: Node = CombatTargetValidation.sanitize_damage_attacker(_attacker)

	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(safe_attacker):
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Node3D:
				continue
			if not CombatTargetValidation.is_hero_unit_ability_target(safe_attacker, node_variant):
				continue
			if StealthService.is_combat_hidden(node_variant):
				# Piercing skillshots still hit committed/visible targets only for auto-stealth.
				# Area skillshots usually hit stealthed; keep consistent with axe/slash = yes hit.
				pass

			var target: Node3D = node_variant as Node3D
			var target_id: int = target.get_instance_id()
			if _hit_ids.has(target_id):
				continue

			var offset: Vector3 = target.global_position - global_position
			offset.y = 0.0
			if offset.length_squared() > hit_radius_sq:
				continue

			_hit_ids[target_id] = true
			var applied_damage: float = _damage * pow(_pierce_mult, float(_pierce_count))
			DamageService.apply_damage(
				target,
				applied_damage,
				safe_attacker,
				{DamageService.OPT_EMPHASIZE_FLOAT: true}
			)

			if NodeSafety.is_alive_node(target):
				MeleeHitSound.play_at(self, target.global_position)
				ImpactEffects.play_unit_impact(target.global_position, 1.15)
				_impact_played = true

			_pierce_count += 1
			if _pierce_count > _max_pierces:
				queue_free()
				return


func _play_ground_miss() -> void:
	if _impact_played:
		return
	_impact_played = true
	ImpactEffects.play_ground_impact(global_position)
