class_name TowerAutoCombat
extends RefCounted

## Stationary auto-attacker state: search cadence, cached target, and fire cooldown.
## Owner supplies range checks via CombatTargetValidation tower APIs and fires projectiles.

const TARGET_SEARCH_INTERVAL := 0.4
const TARGET_SEARCH_JITTER := 0.25

var attack_range: float = 10.0
var attack_cooldown: float = 1.5
var attack_cooldown_timer: float = 0.0
var target_search_timer: float = 0.0
var cached_attack_target: Node3D = null


func randomize_search_timer() -> void:
	target_search_timer = randf() * (TARGET_SEARCH_INTERVAL + TARGET_SEARCH_JITTER)


## Advances timers and target cache. Returns a live in-range target ready to fire, or null.
func update(delta: float, owner: Node3D) -> Node3D:
	attack_cooldown_timer -= delta
	target_search_timer -= delta

	if not _is_cached_target_valid(owner):
		cached_attack_target = null
		if target_search_timer <= 0.0:
			cached_attack_target = CombatTargetValidation.find_closest_tower_attack_target_in_range(
				owner, attack_range
			)
			target_search_timer = TARGET_SEARCH_INTERVAL + randf() * TARGET_SEARCH_JITTER

	if attack_cooldown_timer > 0.0:
		return null

	var target: Node3D = cached_attack_target
	if target == null:
		return null

	if not CombatTargetValidation.is_within_attack_range(owner, target, attack_range):
		cached_attack_target = null
		return null

	return target


func mark_fired() -> void:
	attack_cooldown_timer = attack_cooldown


func clear_target() -> void:
	cached_attack_target = null


func _is_cached_target_valid(owner: Node3D) -> bool:
	if not NodeSafety.is_alive_node(cached_attack_target):
		return false

	if not CombatTargetValidation.is_tower_attack_target(owner, cached_attack_target):
		return false

	return CombatTargetValidation.is_within_attack_range(
		owner,
		cached_attack_target,
		attack_range
	)
