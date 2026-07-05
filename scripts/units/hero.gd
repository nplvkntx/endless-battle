extends Hero

## Player hero unit — melee combat, stronger than a Swordsman.

@export var attack_damage: int = 18
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 0.85
@export var ground_slam_mana_cost: int = 40
@export var mana_regen_rate: float = 5.0
@export var divine_protection_mana_cost: int = 30
@export var power_strike_mana_cost: int = 25
@export var execute_mana_cost: int = 50

signal divine_protection_state_changed(is_active: bool)

const HEALTH_BAR_WIDTH := 1.4
const HEALTH_BAR_HUE_GREEN := 0.333333
const ATTACK_LUNGE_DISTANCE := 0.4
const ATTACK_LUNGE_DURATION := 0.12
const GROUND_SLAM_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/ground_slam_effect.tscn")
const POWER_STRIKE_HIT_EFFECT_SCENE: PackedScene = preload(
	"res://scenes/effects/power_strike_hit_effect.tscn"
)
const EXECUTE_HIT_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/execute_hit_effect.tscn")
const GROUND_SLAM_BODY_PULSE_DURATION := 0.18
const DIVINE_PROTECTION_GLOW_PULSE_DURATION := 0.6
const POWER_STRIKE_LUNGE_DISTANCE := 0.55
const POWER_STRIKE_FLASH_DURATION := 0.15
const EXECUTE_LUNGE_DISTANCE := 0.5
const BASE_ATTACK_DAMAGE := 18
const BASE_MAX_MANA := 100
const BASE_MOVE_SPEED := 5.5
const MOVE_SPEED_PER_LEVEL_AFTER_18 := 0.05
const ATTACK_MOVE_ENGAGEMENT_RANGE := 14.0

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _health_bar: Node3D = $HealthBar
@onready var _health_bar_fill: MeshInstance3D = $HealthBar/Fill
@onready var _body_mesh: MeshInstance3D = $MeshInstance3D

var _health_bar_fill_material: StandardMaterial3D
var _body_mesh_rest_position: Vector3
var _attack_lunge_tween: Tween
var _attack_target: Node3D = null
var _attack_approach_slot: int = -1
var _attack_cooldown_timer: float = 0.0
var _has_chase_target: bool = false
var _attack_move_destination: Vector3 = Vector3.ZERO
var _has_attack_move_destination: bool = false
var _ground_slam_cooldown_timer: float = 0.0
var _ground_slam_pulse_tween: Tween
var _mana_regen_accumulator: float = 0.0
var _divine_protection_timer: float = 0.0
var _divine_protection_cooldown_timer: float = 0.0
var _body_material: StandardMaterial3D
var _body_base_color: Color
var _divine_protection_glow_tween: Tween
var _power_strike_cooldown_timer: float = 0.0
var _power_strike_target: Node3D = null
var _power_strike_approach_slot: int = -1
var _has_power_strike_pending: bool = false
var _power_strike_lunge_tween: Tween
var _power_strike_flash_tween: Tween
var _execute_cooldown_timer: float = 0.0
var _execute_target: Node3D = null
var _execute_approach_slot: int = -1
var _has_execute_pending: bool = false
var _execute_lunge_tween: Tween


func _ready() -> void:
	super._ready()
	_health_bar_fill_material = HealthBarDisplay.duplicate_mesh_material(_health_bar_fill)
	_health_bar_fill.set_surface_override_material(0, _health_bar_fill_material)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.health_depleted.connect(_on_health_depleted)
	_body_mesh_rest_position = _body_mesh.position
	_body_material = HealthBarDisplay.duplicate_mesh_material(_body_mesh)
	_body_mesh.set_surface_override_material(0, _body_material)
	_body_base_color = _body_material.albedo_color
	if CombatTargetValidation.is_enemy_faction(self):
		current_mana = max_mana
		mana_changed.emit(current_mana, max_mana)
	elif HeroProgressionStore.has_saved_progression():
		HeroProgressionStore.apply_to_hero(self)
	else:
		current_mana = max_mana
		mana_changed.emit(current_mana, max_mana)
	_update_health_bar(_health_component.current_health, _health_component.max_health)
	died.connect(_notify_hero_altars_of_death)


func _get_ability_base_overrides(ability_id: StringName) -> Dictionary:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return {HeroAbilityStats.STAT_MANA: ground_slam_mana_cost}
		HeroAbilityProgression.ABILITY_W:
			return {HeroAbilityStats.STAT_MANA: divine_protection_mana_cost}
		HeroAbilityProgression.ABILITY_E:
			return {HeroAbilityStats.STAT_MANA: power_strike_mana_cost}
		HeroAbilityProgression.ABILITY_R:
			return {HeroAbilityStats.STAT_MANA: execute_mana_cost}
		_:
			return {}


func get_ground_slam_damage() -> int:
	return get_ability_damage(HeroAbilityProgression.ABILITY_Q)


func get_ground_slam_radius() -> float:
	return get_ability_splash_radius(HeroAbilityProgression.ABILITY_Q)


func get_ground_slam_cooldown() -> float:
	return get_ability_cooldown(HeroAbilityProgression.ABILITY_Q)


func get_divine_protection_duration() -> float:
	return get_ability_effect_strength(HeroAbilityProgression.ABILITY_W)


func get_divine_protection_cooldown() -> float:
	return get_ability_cooldown(HeroAbilityProgression.ABILITY_W)


func get_power_strike_damage() -> int:
	return get_ability_damage(HeroAbilityProgression.ABILITY_E)


func get_power_strike_cooldown() -> float:
	return get_ability_cooldown(HeroAbilityProgression.ABILITY_E)


func get_execute_health_threshold() -> float:
	return get_ability_effect_strength(HeroAbilityProgression.ABILITY_R)


func get_execute_cooldown() -> float:
	return get_ability_cooldown(HeroAbilityProgression.ABILITY_R)


func _notify_hero_altars_of_death(_unit: Unit) -> void:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is HeroAltar:
			(node as HeroAltar).hero_altar_state_changed.emit()


func _apply_level_mana_gain() -> void:
	max_mana += MANA_PER_LEVEL
	current_mana = mini(current_mana + MANA_PER_LEVEL, max_mana)
	mana_changed.emit(current_mana, max_mana)


func _apply_level_attack_damage_gain() -> void:
	attack_damage += ATTACK_DAMAGE_PER_LEVEL


func _apply_level_move_speed_gain() -> void:
	move_speed += MOVE_SPEED_PER_LEVEL_AFTER_18


func _apply_accumulated_level_combat_stats(levels_gained: int) -> void:
	attack_damage = BASE_ATTACK_DAMAGE + levels_gained * ATTACK_DAMAGE_PER_LEVEL
	max_mana = BASE_MAX_MANA + levels_gained * MANA_PER_LEVEL
	current_mana = max_mana
	mana_changed.emit(current_mana, max_mana)


func _apply_accumulated_level_move_speed_bonus() -> void:
	var levels_after_18: int = maxi(0, level - MAX_ABILITY_POINT_LEVEL)
	move_speed = BASE_MOVE_SPEED + float(levels_after_18) * MOVE_SPEED_PER_LEVEL_AFTER_18


func _on_progression_restored() -> void:
	_update_health_bar(_health_component.current_health, _health_component.max_health)


func _on_health_changed(current_health: int, max_health: int) -> void:
	_update_health_bar(current_health, max_health)


func _update_health_bar(current_health: int, max_health: int) -> void:
	HealthBarDisplay.update_world_bar(
		_health_bar,
		_health_bar_fill,
		_health_bar_fill_material,
		current_health,
		max_health,
		HEALTH_BAR_WIDTH,
		HEALTH_BAR_HUE_GREEN
	)


func _get_health_bar_color(ratio: float) -> Color:
	return Color.from_hsv(ratio * HEALTH_BAR_HUE_GREEN, 0.85, 0.9)


func get_attack_facing_direction() -> Vector3:
	var target: Node3D = null
	if _has_execute_pending and CombatTargetValidation.is_valid_combat_target(_execute_target):
		target = _execute_target
	elif _has_power_strike_pending and CombatTargetValidation.is_valid_combat_target(_power_strike_target):
		target = _power_strike_target
	elif _attack_target != null and CombatTargetValidation.is_valid_combat_target(_attack_target):
		target = _attack_target

	if target == null:
		return Vector3.ZERO

	var direction: Vector3 = target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return Vector3.ZERO

	return direction.normalized()


func command_attack(target: Node3D, assigned_slot: int = -1) -> void:
	if not NodeSafety.is_alive_node(target):
		return
	if not CombatTargetValidation.is_attack_target_for_attacker(self, target):
		return

	_cancel_power_strike()
	_cancel_execute()
	_assign_attack_approach_slot(target, assigned_slot)
	_attack_target = NodeSafety.safe_node(target) as Node3D
	if _attack_target == null:
		return
	_has_chase_target = false

	if not _is_in_attack_range(_attack_target):
		_begin_chase()


func command_attack_move(destination: Vector3) -> void:
	_cancel_power_strike()
	_cancel_execute()
	_attack_move_destination = destination
	_has_attack_move_destination = true
	cancel_attack()
	_set_move_destination(destination)


func cancel_attack_move() -> void:
	_has_attack_move_destination = false


func cancel_attack() -> void:
	if NodeSafety.is_alive_node(_attack_target):
		CombatTargetValidation.clear_attack_approach_slots(_attack_target)
	_attack_target = null
	_attack_approach_slot = -1
	_has_chase_target = false


func _sanitize_attack_target() -> void:
	if _attack_target == null:
		return

	if not NodeSafety.is_alive_node(_attack_target):
		cancel_attack()
		_resume_attack_move()
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		_resume_attack_move()


func _sanitize_ability_targets() -> void:
	if not NodeSafety.is_alive_node(_power_strike_target):
		_cancel_power_strike()

	if not NodeSafety.is_alive_node(_execute_target):
		_cancel_execute()


func set_movement_target(target: Vector3) -> void:
	_cancel_power_strike()
	_cancel_execute()
	cancel_attack_move()
	cancel_attack()
	_set_move_destination(target)


func _set_move_destination(target: Vector3) -> void:
	super.set_movement_target(target)


func get_ground_slam_cooldown_remaining() -> float:
	return maxf(_ground_slam_cooldown_timer, 0.0)


func get_divine_protection_cooldown_remaining() -> float:
	return maxf(_divine_protection_cooldown_timer, 0.0)


func get_divine_protection_remaining() -> float:
	return maxf(_divine_protection_timer, 0.0)


func is_divine_protection_active() -> bool:
	return _divine_protection_timer > 0.0


func _should_show_ability_feedback() -> bool:
	return not CombatTargetValidation.is_enemy_faction(self)


func _show_ability_feedback(message: String) -> void:
	if not _should_show_ability_feedback():
		return

	if ResourceManager != null:
		ResourceManager.show_feedback(message)


func _require_ability_learned(ability_id: StringName) -> bool:
	if is_ability_unlocked(ability_id):
		return true

	_show_ability_feedback("Ability locked")
	return false


func can_use_divine_protection() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_W)
		and _health_component.current_health > 0
		and not is_divine_protection_active()
		and _divine_protection_cooldown_timer <= 0.0
		and current_mana >= get_divine_protection_mana_cost()
	)


func try_divine_protection() -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_W):
		return false

	if is_divine_protection_active():
		_show_ability_feedback("Divine Protection already active")
		return false

	if _divine_protection_cooldown_timer > 0.0:
		_show_ability_feedback(
			"Divine Protection on cooldown (%.0fs)" % ceilf(_divine_protection_cooldown_timer)
		)
		return false

	if current_mana < get_divine_protection_mana_cost():
		_show_ability_feedback("Not enough mana")
		return false

	_execute_divine_protection()
	return true


func _execute_divine_protection() -> void:
	current_mana = maxi(0, current_mana - get_divine_protection_mana_cost())
	mana_changed.emit(current_mana, max_mana)
	_divine_protection_timer = get_divine_protection_duration()
	_apply_divine_protection_visual()
	divine_protection_state_changed.emit(true)


func _deactivate_divine_protection() -> void:
	_divine_protection_timer = 0.0
	_clear_divine_protection_visual()
	_divine_protection_cooldown_timer = get_divine_protection_cooldown()
	divine_protection_state_changed.emit(false)


func _apply_divine_protection_visual() -> void:
	if _divine_protection_glow_tween != null and _divine_protection_glow_tween.is_valid():
		_divine_protection_glow_tween.kill()

	_body_material.emission_enabled = true
	_body_material.albedo_color = Color(0.95, 0.92, 0.55, 1.0)
	_body_material.emission = Color(0.75, 0.9, 1.0, 1.0)

	_divine_protection_glow_tween = create_tween().set_loops()
	_divine_protection_glow_tween.tween_property(
		_body_material,
		"emission",
		Color(0.45, 0.75, 1.0, 1.0),
		DIVINE_PROTECTION_GLOW_PULSE_DURATION * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_divine_protection_glow_tween.tween_property(
		_body_material,
		"emission",
		Color(0.95, 0.98, 1.0, 1.0),
		DIVINE_PROTECTION_GLOW_PULSE_DURATION * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _clear_divine_protection_visual() -> void:
	if _divine_protection_glow_tween != null and _divine_protection_glow_tween.is_valid():
		_divine_protection_glow_tween.kill()

	_body_material.emission_enabled = false
	_body_material.emission = Color.BLACK
	_body_material.albedo_color = _body_base_color


func get_power_strike_cooldown_remaining() -> float:
	return maxf(_power_strike_cooldown_timer, 0.0)


func is_power_strike_pending() -> bool:
	return _has_power_strike_pending


func can_use_power_strike(search_range: float = ATTACK_MOVE_ENGAGEMENT_RANGE) -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_E)
		and _health_component.current_health > 0
		and not _has_power_strike_pending
		and _power_strike_cooldown_timer <= 0.0
		and current_mana >= get_power_strike_mana_cost()
		and _resolve_power_strike_target(search_range) != null
	)


func try_power_strike() -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_E):
		return false

	if _has_power_strike_pending:
		_show_ability_feedback("Power Strike already in progress")
		return false

	if _power_strike_cooldown_timer > 0.0:
		_show_ability_feedback(
			"Power Strike on cooldown (%.0fs)" % ceilf(_power_strike_cooldown_timer)
		)
		return false

	if current_mana < get_power_strike_mana_cost():
		_show_ability_feedback("Not enough mana")
		return false

	var target: Node3D = _resolve_power_strike_target(ATTACK_MOVE_ENGAGEMENT_RANGE)
	if target == null:
		_show_ability_feedback("No valid target")
		return false

	_begin_power_strike(target)
	return true


func _resolve_power_strike_target(search_range: float = ATTACK_MOVE_ENGAGEMENT_RANGE) -> Node3D:
	if CombatTargetValidation.is_enemy_faction(self):
		_sanitize_attack_target()
		if CombatTargetValidation.is_hero_unit_ability_target(self, _attack_target):
			if _is_in_attack_range(_attack_target):
				return _attack_target

		return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, search_range
		)

	return _resolve_ability_target()


func _resolve_ability_target() -> Node3D:
	_sanitize_attack_target()

	if CombatTargetValidation.is_hero_unit_ability_target(self, _attack_target):
		return _attack_target

	return CombatTargetValidation.find_closest_attack_target_for_attacker(self)


func _begin_power_strike(target: Node3D) -> void:
	_power_strike_target = NodeSafety.safe_node(target) as Node3D
	if _power_strike_target == null:
		return

	cancel_attack_move()
	cancel_attack()
	_power_strike_approach_slot = CombatTargetValidation.claim_attack_approach_slot(
		_power_strike_target
	)
	_has_power_strike_pending = true

	if not _is_in_attack_range(_power_strike_target):
		_set_move_destination(
			_compute_attack_approach_position(
				_power_strike_target, _power_strike_approach_slot
			)
		)


func _cancel_power_strike() -> void:
	_has_power_strike_pending = false
	_power_strike_target = null
	_power_strike_approach_slot = -1


func _process_power_strike(_delta: float) -> void:
	if not CombatTargetValidation.is_valid_combat_target(_power_strike_target):
		_cancel_power_strike()
		return

	if _is_in_attack_range(_power_strike_target):
		_execute_power_strike()
		return

	if not has_move_target:
		_set_move_destination(
			_compute_attack_approach_position(
				_power_strike_target, _power_strike_approach_slot
			)
		)


func _execute_power_strike() -> void:
	if not CombatTargetValidation.is_valid_combat_target(_power_strike_target):
		_cancel_power_strike()
		return

	if not _is_in_attack_range(_power_strike_target):
		return

	if current_mana < get_power_strike_mana_cost():
		_show_ability_feedback("Not enough mana")
		_cancel_power_strike()
		return

	var target: Node3D = _power_strike_target
	has_move_target = false
	velocity = Vector3.ZERO
	current_mana = maxi(0, current_mana - get_power_strike_mana_cost())
	mana_changed.emit(current_mana, max_mana)
	_power_strike_cooldown_timer = get_power_strike_cooldown()
	_cancel_power_strike()

	var strike_damage: int = get_power_strike_damage()
	if not CombatTargetValidation.apply_damage_to_target(
		target, float(strike_damage), self
	):
		return

	FloatingDamageNumber.spawn(target, strike_damage, true)
	MeleeHitSound.play_at(self, target.global_position)
	_play_power_strike_lunge(target)
	_play_power_strike_flash()
	_spawn_power_strike_hit_effect(target)


func _play_power_strike_lunge(target: Node3D) -> void:
	if _power_strike_lunge_tween != null and _power_strike_lunge_tween.is_valid():
		_power_strike_lunge_tween.kill()

	var lunge_offset := Vector3.ZERO
	if CombatTargetValidation.is_valid_combat_target(target):
		var direction := target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			lunge_offset = (
				global_transform.basis.inverse()
				* (direction.normalized() * POWER_STRIKE_LUNGE_DISTANCE)
			)

	_body_mesh.position = _body_mesh_rest_position
	_power_strike_lunge_tween = create_tween()
	_power_strike_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position + lunge_offset,
		ATTACK_LUNGE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_power_strike_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position,
		ATTACK_LUNGE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _play_power_strike_flash() -> void:
	if is_divine_protection_active():
		return

	if _power_strike_flash_tween != null and _power_strike_flash_tween.is_valid():
		_power_strike_flash_tween.kill()

	_body_material.emission_enabled = true
	_body_material.emission = Color(1.0, 0.65, 0.15, 1.0)
	_body_material.albedo_color = Color(1.0, 0.82, 0.35, 1.0)

	_power_strike_flash_tween = create_tween()
	_power_strike_flash_tween.set_parallel(true)
	_power_strike_flash_tween.tween_property(
		_body_material,
		"albedo_color",
		_body_base_color,
		POWER_STRIKE_FLASH_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_power_strike_flash_tween.tween_property(
		_body_material,
		"emission",
		Color.BLACK,
		POWER_STRIKE_FLASH_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_power_strike_flash_tween.finished.connect(_on_power_strike_flash_finished, CONNECT_ONE_SHOT)


func _on_power_strike_flash_finished() -> void:
	if is_divine_protection_active():
		return

	_body_material.emission_enabled = false
	_body_material.albedo_color = _body_base_color


func _spawn_power_strike_hit_effect(target: Node3D) -> void:
	if not NodeSafety.is_alive_node(target):
		return

	var effect: PowerStrikeHitEffect = POWER_STRIKE_HIT_EFFECT_SCENE.instantiate() as PowerStrikeHitEffect
	if effect == null:
		return

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		effect.queue_free()
		return

	spawn_parent.add_child(effect)
	effect.global_position = target.global_position + Vector3(0.0, 0.75, 0.0)


func get_execute_cooldown_remaining() -> float:
	return maxf(_execute_cooldown_timer, 0.0)


func is_execute_pending() -> bool:
	return _has_execute_pending


func can_use_execute(search_range: float = ATTACK_MOVE_ENGAGEMENT_RANGE) -> bool:
	if not is_ability_unlocked(HeroAbilityProgression.ABILITY_R):
		return false

	if _health_component.current_health <= 0:
		return false

	if _has_execute_pending or _has_power_strike_pending:
		return false

	if _execute_cooldown_timer > 0.0:
		return false

	if current_mana < get_execute_mana_cost():
		return false

	return _resolve_execute_target(search_range) != null


func try_execute() -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_R):
		return false

	if _has_execute_pending:
		_show_ability_feedback("Execute already in progress")
		return false

	if _has_power_strike_pending:
		_show_ability_feedback("Another ability is in progress")
		return false

	if _execute_cooldown_timer > 0.0:
		_show_ability_feedback(
			"Execute on cooldown (%.0fs)" % ceilf(_execute_cooldown_timer)
		)
		return false

	if current_mana < get_execute_mana_cost():
		_show_ability_feedback("Not enough mana")
		return false

	var target: Node3D = _resolve_execute_target(ATTACK_MOVE_ENGAGEMENT_RANGE)
	if target == null:
		_show_ability_feedback("No valid target")
		return false

	_begin_execute(target)
	return true


func _resolve_execute_target(search_range: float = ATTACK_MOVE_ENGAGEMENT_RANGE) -> Node3D:
	if CombatTargetValidation.is_enemy_faction(self):
		return find_execute_target(search_range)

	return _resolve_ability_target()


func find_execute_target(search_range: float) -> Node3D:
	if search_range <= 0.0:
		return null

	var best_hero: Node3D = null
	var best_hero_distance: float = INF
	var best_unit: Node3D = null
	var best_unit_distance: float = INF

	for group_name: StringName in [&"units", &"heroes"]:
		for node: Node in CombatTargetValidation.get_cached_group_nodes(get_tree(), group_name):
			if not _is_player_military_unit(node):
				continue

			if not CombatTargetValidation.is_hero_unit_ability_target(self, node):
				continue

			var target: Node3D = node as Node3D
			if not is_instance_valid(target):
				continue

			var distance: float = _horizontal_distance_to(target)
			if distance > search_range:
				continue

			if not _can_execute_target(target):
				continue

			if node is Hero:
				if distance < best_hero_distance:
					best_hero = target
					best_hero_distance = distance
			elif distance < best_unit_distance:
				best_unit = target
				best_unit_distance = distance

	if best_hero != null:
		return best_hero

	return best_unit


func _is_player_military_unit(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if CombatTargetValidation.is_enemy_faction(node):
		return false

	return node is Swordsman or node is Archer or node is Hero


func _begin_execute(target: Node3D) -> void:
	_execute_target = NodeSafety.safe_node(target) as Node3D
	if _execute_target == null:
		return

	cancel_attack_move()
	cancel_attack()
	_cancel_power_strike()
	_execute_approach_slot = CombatTargetValidation.claim_attack_approach_slot(
		_execute_target
	)
	_has_execute_pending = true

	if not _is_in_attack_range(_execute_target):
		_set_move_destination(
			_compute_attack_approach_position(_execute_target, _execute_approach_slot)
		)


func _cancel_execute() -> void:
	_has_execute_pending = false
	_execute_target = null
	_execute_approach_slot = -1


func _process_execute(_delta: float) -> void:
	if not CombatTargetValidation.is_valid_combat_target(_execute_target):
		_cancel_execute()
		return

	if _is_in_attack_range(_execute_target):
		_perform_execute()
		return

	if not has_move_target:
		_set_move_destination(
			_compute_attack_approach_position(_execute_target, _execute_approach_slot)
		)


func _get_target_health_ratio(target: Node3D) -> float:
	var health_component: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null or health_component.max_health <= 0:
		return 1.0

	return float(health_component.current_health) / float(health_component.max_health)


func _can_execute_target(target: Node3D) -> bool:
	return _get_target_health_ratio(target) < get_execute_health_threshold()


func _perform_execute() -> void:
	if not CombatTargetValidation.is_valid_combat_target(_execute_target):
		_cancel_execute()
		return

	if not _is_in_attack_range(_execute_target):
		return

	if current_mana < get_execute_mana_cost():
		_show_ability_feedback("Not enough mana")
		_cancel_execute()
		return

	var target: Node3D = _execute_target
	if not _can_execute_target(target):
		_show_ability_feedback("Target health too high")
		_cancel_execute()
		return

	has_move_target = false
	velocity = Vector3.ZERO
	current_mana = maxi(0, current_mana - get_execute_mana_cost())
	mana_changed.emit(current_mana, max_mana)
	_execute_cooldown_timer = get_execute_cooldown()
	_cancel_execute()

	_kill_execute_target(target)
	MeleeHitSound.play_at(self, target.global_position)
	_play_execute_lunge(target)
	_spawn_execute_hit_effect(target)


func _kill_execute_target(target: Node3D) -> void:
	if not CombatTargetValidation.is_valid_combat_target(target):
		return

	var remaining_health: int = CombatTargetValidation.get_target_current_health(target)
	if remaining_health <= 0:
		return

	if not CombatTargetValidation.apply_damage_to_target(target, float(remaining_health), self):
		return

	FloatingDamageNumber.spawn(target, remaining_health, true)


func _play_execute_lunge(target: Node3D) -> void:
	if _execute_lunge_tween != null and _execute_lunge_tween.is_valid():
		_execute_lunge_tween.kill()

	var lunge_offset := Vector3.ZERO
	if CombatTargetValidation.is_valid_combat_target(target):
		var direction := target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			lunge_offset = (
				global_transform.basis.inverse() * (direction.normalized() * EXECUTE_LUNGE_DISTANCE)
			)

	_body_mesh.position = _body_mesh_rest_position
	_execute_lunge_tween = create_tween()
	_execute_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position + lunge_offset,
		ATTACK_LUNGE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_execute_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position,
		ATTACK_LUNGE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _spawn_execute_hit_effect(target: Node3D) -> void:
	if not NodeSafety.is_alive_node(target):
		return

	var effect: ExecuteHitEffect = EXECUTE_HIT_EFFECT_SCENE.instantiate() as ExecuteHitEffect
	if effect == null:
		return

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		effect.queue_free()
		return

	spawn_parent.add_child(effect)
	effect.global_position = target.global_position + Vector3(0.0, 0.6, 0.0)


func _tick_execute_cooldown(delta: float) -> void:
	if _execute_cooldown_timer <= 0.0:
		return

	_execute_cooldown_timer = maxf(_execute_cooldown_timer - delta, 0.0)


func _tick_power_strike_cooldown(delta: float) -> void:
	if _power_strike_cooldown_timer <= 0.0:
		return

	_power_strike_cooldown_timer = maxf(_power_strike_cooldown_timer - delta, 0.0)


func can_use_ground_slam() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_Q)
		and _health_component.current_health > 0
		and _ground_slam_cooldown_timer <= 0.0
		and current_mana >= get_ground_slam_mana_cost()
	)


func try_ground_slam() -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_Q):
		return false

	if _ground_slam_cooldown_timer > 0.0:
		_show_ability_feedback(
			"Ground Slam on cooldown (%.0fs)" % ceilf(_ground_slam_cooldown_timer)
		)
		return false

	if current_mana < get_ground_slam_mana_cost():
		_show_ability_feedback("Not enough mana")
		return false

	_execute_ground_slam()
	return true


func _execute_ground_slam() -> void:
	current_mana = maxi(0, current_mana - get_ground_slam_mana_cost())
	mana_changed.emit(current_mana, max_mana)
	_ground_slam_cooldown_timer = get_ground_slam_cooldown()
	_damage_enemies_in_ground_slam_radius()
	_spawn_ground_slam_effect()
	_play_ground_slam_pulse()
	MeleeHitSound.play_at(self, global_position)


func _damage_enemies_in_ground_slam_radius() -> void:
	var slam_radius: float = get_ground_slam_radius()
	var slam_damage: int = get_ground_slam_damage()

	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups():
		for node: Node in CombatTargetValidation.get_cached_group_nodes(get_tree(), group_name):
			if not NodeSafety.is_alive_node(node):
				continue
			if not node is Node3D:
				continue
			if not CombatTargetValidation.is_hero_unit_ability_target(self, node):
				continue

			var target: Node3D = node as Node3D
			if _horizontal_distance_to(target) > slam_radius:
				continue

			CombatTargetValidation.apply_damage_to_target(
				target, float(slam_damage), self
			)


func _spawn_ground_slam_effect() -> void:
	var effect: GroundSlamEffect = GROUND_SLAM_EFFECT_SCENE.instantiate() as GroundSlamEffect
	if effect == null:
		return

	effect.radius = get_ground_slam_radius()

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		effect.queue_free()
		return

	spawn_parent.add_child(effect)
	effect.global_position = Vector3(global_position.x, 0.03, global_position.z)


func _play_ground_slam_pulse() -> void:
	if _ground_slam_pulse_tween != null and _ground_slam_pulse_tween.is_valid():
		_ground_slam_pulse_tween.kill()

	_body_mesh.scale = Vector3.ONE
	_ground_slam_pulse_tween = create_tween()
	_ground_slam_pulse_tween.tween_property(
		_body_mesh,
		"scale",
		Vector3(1.25, 0.75, 1.25),
		GROUND_SLAM_BODY_PULSE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ground_slam_pulse_tween.tween_property(
		_body_mesh,
		"scale",
		Vector3.ONE,
		GROUND_SLAM_BODY_PULSE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _tick_ground_slam_cooldown(delta: float) -> void:
	if _ground_slam_cooldown_timer <= 0.0:
		return

	_ground_slam_cooldown_timer = maxf(_ground_slam_cooldown_timer - delta, 0.0)


func _tick_divine_protection(delta: float) -> void:
	if _divine_protection_timer <= 0.0:
		return

	_divine_protection_timer = maxf(_divine_protection_timer - delta, 0.0)
	if _divine_protection_timer > 0.0:
		return

	_deactivate_divine_protection()


func _tick_divine_protection_cooldown(delta: float) -> void:
	if _divine_protection_cooldown_timer <= 0.0:
		return

	_divine_protection_cooldown_timer = maxf(_divine_protection_cooldown_timer - delta, 0.0)


func _tick_mana_regen(delta: float) -> void:
	if current_mana >= max_mana:
		_mana_regen_accumulator = 0.0
		return

	if mana_regen_rate <= 0.0:
		return

	_mana_regen_accumulator += mana_regen_rate * delta
	if _mana_regen_accumulator < 1.0:
		return

	var mana_gain: int = int(_mana_regen_accumulator)
	_mana_regen_accumulator -= float(mana_gain)
	var new_mana: int = mini(max_mana, current_mana + mana_gain)
	if new_mana == current_mana:
		return

	current_mana = new_mana
	mana_changed.emit(current_mana, max_mana)


func _physics_process(delta: float) -> void:
	if _health_component.current_health <= 0:
		return

	_sanitize_attack_target()
	_sanitize_ability_targets()

	_tick_ground_slam_cooldown(delta)
	_tick_divine_protection(delta)
	_tick_divine_protection_cooldown(delta)
	_tick_power_strike_cooldown(delta)
	_tick_execute_cooldown(delta)
	_tick_mana_regen(delta)

	var can_scan_targets: bool = tick_combat_target_scan_timer(delta)

	if _has_execute_pending:
		_process_execute(delta)
	elif _has_power_strike_pending:
		_process_power_strike(delta)
	elif _attack_target == null and not has_move_target:
		if can_scan_targets:
			_try_auto_attack()

	if (
		_has_attack_move_destination
		and _attack_target == null
		and not _has_power_strike_pending
		and not _has_execute_pending
	):
		if can_scan_targets:
			_try_attack_move_engagement()

	if _attack_target != null and not _has_power_strike_pending and not _has_execute_pending:
		if not CombatTargetValidation.is_valid_combat_target(_attack_target):
			cancel_attack()
			_resume_attack_move()
		else:
			_process_attack(delta)
			return

	super._physics_process(delta)

	if _has_attack_move_destination and _attack_target == null and not has_move_target:
		if _is_at_attack_move_destination():
			cancel_attack_move()


func _try_auto_attack() -> void:
	var closest_target: Node3D = _find_closest_attack_target_in_range()
	if closest_target != null:
		command_attack(closest_target)


func _find_closest_attack_target_in_range() -> Node3D:
	if CombatTargetValidation.is_enemy_faction(self):
		return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, attack_range
		)

	return CombatTargetValidation.find_closest_player_unit_attack_target_in_range(
		self, attack_range
	)


func _process_attack(delta: float) -> void:
	if _is_in_attack_range(_attack_target):
		_stop_and_attack(delta)
		return

	if not has_move_target:
		_has_chase_target = false
		_begin_chase()

	super._physics_process(delta)

	if _attack_target != null and _is_in_attack_range(_attack_target):
		_stop_and_attack(delta)


func _stop_and_attack(delta: float) -> void:
	has_move_target = false
	_has_chase_target = false
	velocity = Vector3.ZERO

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		cancel_attack()
		_resume_attack_move()
		return

	if not CombatTargetValidation.apply_damage_to_target(_attack_target, float(attack_damage), self):
		cancel_attack()
		_resume_attack_move()
		return

	MeleeHitSound.play_at(self, _attack_target.global_position)
	_play_attack_animation()
	_attack_cooldown_timer = attack_cooldown


func _play_attack_animation() -> void:
	if _attack_lunge_tween != null and _attack_lunge_tween.is_valid():
		_attack_lunge_tween.kill()

	var lunge_offset := Vector3.ZERO
	if CombatTargetValidation.is_valid_combat_target(_attack_target):
		var direction := _attack_target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.001:
			lunge_offset = global_transform.basis.inverse() * (direction.normalized() * ATTACK_LUNGE_DISTANCE)

	_body_mesh.position = _body_mesh_rest_position
	_attack_lunge_tween = create_tween()
	_attack_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position + lunge_offset,
		ATTACK_LUNGE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_lunge_tween.tween_property(
		_body_mesh,
		"position",
		_body_mesh_rest_position,
		ATTACK_LUNGE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func take_damage(amount: float, attacker = null) -> void:
	if _health_component.current_health <= 0:
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)

	if is_divine_protection_active():
		return

	CombatKillTracker.record_attacker(self, attacker)

	var damage_amount := int(amount)
	_health_component.take_damage(damage_amount)
	FloatingDamageNumber.spawn(self, damage_amount)


func get_current_health() -> int:
	return _health_component.current_health


func _on_health_depleted() -> void:
	if not CombatTargetValidation.is_enemy_faction(self):
		HeroProgressionStore.save_from_hero(self)
	else:
		HeroXpRewards.notify_unit_killed(self)
		if is_in_group(&"enemy_combat_units"):
			remove_from_group(&"enemy_combat_units")
	EnemyUnitMission.clear_unit_mission(self)
	_health_bar.visible = false
	cancel_attack_move()
	cancel_attack()
	_cancel_power_strike()
	_cancel_execute()
	has_move_target = false
	velocity = Vector3.ZERO
	die()
	queue_free()


func _exit_tree() -> void:
	cancel_attack_move()
	cancel_attack()
	_cancel_power_strike()
	_cancel_execute()
	EnemyUnitMission.clear_unit_mission(self)


func _begin_chase() -> void:
	if not NodeSafety.is_alive_node(_attack_target):
		cancel_attack()
		return

	if _has_chase_target:
		return

	_set_move_destination(_compute_attack_approach_position(_attack_target))
	_has_chase_target = true


func _try_attack_move_engagement() -> void:
	var closest_target: Node3D = null
	if CombatTargetValidation.is_enemy_faction(self):
		closest_target = CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
			self, maxf(attack_range, ATTACK_MOVE_ENGAGEMENT_RANGE)
		)
	else:
		closest_target = _find_closest_attack_target_in_range()

	if closest_target != null:
		command_attack(closest_target)


func _resume_attack_move() -> void:
	if not _has_attack_move_destination:
		return

	if _is_at_attack_move_destination():
		cancel_attack_move()
		return

	_has_chase_target = false
	_set_move_destination(_attack_move_destination)


func _is_at_attack_move_destination() -> bool:
	var offset: Vector3 = global_position - _attack_move_destination
	offset.y = 0.0
	return offset.length() <= stopping_distance


func _is_in_attack_range(target: Node3D) -> bool:
	return CombatTargetValidation.is_within_attack_range(self, target, attack_range)


func _horizontal_distance_to(target: Node3D) -> float:
	return CombatTargetValidation.get_horizontal_center_distance(self, target)


func _compute_attack_approach_position(target: Node3D, approach_slot: int = -1) -> Vector3:
	var slot_index: int = approach_slot
	if slot_index < 0:
		slot_index = maxi(_attack_approach_slot, 0)
	return CombatTargetValidation.compute_attack_approach_position(
		self, target, attack_range, stopping_distance, slot_index
	)


func _assign_attack_approach_slot(target: Node3D, assigned_slot: int) -> void:
	if assigned_slot >= 0:
		_attack_approach_slot = assigned_slot
	elif _attack_target != target:
		_attack_approach_slot = CombatTargetValidation.claim_attack_approach_slot(target)
