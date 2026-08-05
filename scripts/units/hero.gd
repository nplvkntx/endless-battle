extends MeleeHero

## Human Paladin — Ground Slam, Divine Protection, Power Strike, Execute.

@export var ground_slam_mana_cost: int = HeroStats.GROUND_SLAM_MANA_COST
@export var divine_protection_mana_cost: int = HeroStats.DIVINE_PROTECTION_MANA_COST
@export var power_strike_mana_cost: int = HeroStats.POWER_STRIKE_MANA_COST
@export var execute_mana_cost: int = HeroStats.EXECUTE_MANA_COST

signal divine_protection_state_changed(is_active: bool)

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

var _ground_slam_cooldown_timer: float = 0.0
var _ground_slam_pulse_tween: Tween
var _divine_protection_timer: float = 0.0
var _divine_protection_cooldown_timer: float = 0.0
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
	if passive_definition == null:
		passive_definition = HeroPassiveCatalog.create_holy_recovery()
	super._ready()


func get_hero_kit_id() -> StringName:
	return HeroCatalog.KIT_PALADIN


func get_display_name() -> String:
	return "Human Paladin"


func try_cast_q(_target: Variant = null) -> bool:
	return try_ground_slam()


func try_cast_w(_target: Variant = null) -> bool:
	return try_divine_protection()


func try_cast_e(target: Variant = null) -> bool:
	return try_power_strike(target)


func try_cast_r(target: Variant = null) -> bool:
	return try_execute(target)


func get_ability_definition(ability_id: StringName) -> HeroAbilityDefinition:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			var slam := HeroAbilityDefinition.make(
				ability_id,
				HeroAbilityDefinition.TargetingType.CIRCULAR_SELF,
				0.0
			)
			slam.effect_radius = get_ground_slam_radius()
			slam.allows_move_to_cast = false
			slam.can_target_enemies = true
			slam.can_target_creeps = true
			slam.show_cast_range = false
			return slam
		HeroAbilityProgression.ABILITY_W:
			var shield := HeroAbilityDefinition.make(
				ability_id,
				HeroAbilityDefinition.TargetingType.INSTANT_SELF,
				0.0
			)
			shield.allows_move_to_cast = false
			shield.show_cast_range = false
			return shield
		HeroAbilityProgression.ABILITY_E:
			var strike := HeroAbilityDefinition.make(
				ability_id,
				HeroAbilityDefinition.TargetingType.TARGET_ENEMY,
				ATTACK_MOVE_ENGAGEMENT_RANGE
			)
			# Kit chase-casts into melee after the player confirms a target.
			strike.allows_move_to_cast = false
			strike.can_target_buildings = false
			strike.can_target_creeps = true
			strike.can_target_enemies = true
			return strike
		HeroAbilityProgression.ABILITY_R:
			var execute_def := HeroAbilityDefinition.make(
				ability_id,
				HeroAbilityDefinition.TargetingType.TARGET_ENEMY,
				ATTACK_MOVE_ENGAGEMENT_RANGE
			)
			execute_def.allows_move_to_cast = false
			execute_def.can_target_buildings = false
			execute_def.can_target_creeps = true
			execute_def.can_target_enemies = true
			return execute_def
		_:
			return null


func get_ability_target_mode(ability_id: StringName) -> int:
	return super.get_ability_target_mode(ability_id)


func get_ability_cooldown_remaining(ability_id: StringName) -> float:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return get_ground_slam_cooldown_remaining()
		HeroAbilityProgression.ABILITY_W:
			return get_divine_protection_cooldown_remaining()
		HeroAbilityProgression.ABILITY_E:
			return get_power_strike_cooldown_remaining()
		HeroAbilityProgression.ABILITY_R:
			return get_execute_cooldown_remaining()
		_:
			return 0.0


func get_ability_active_status_text(ability_id: StringName) -> String:
	if ability_id == HeroAbilityProgression.ABILITY_W and is_divine_protection_active():
		return "Active %.1fs" % get_divine_protection_remaining()
	if ability_id == HeroAbilityProgression.ABILITY_E and is_power_strike_pending():
		return "Moving..."
	if ability_id == HeroAbilityProgression.ABILITY_R and is_execute_pending():
		return "Moving..."
	return ""


func try_ai_cast_abilities(context: Dictionary) -> void:
	## Kit micro is owned by AIHeroMastery (tactical states + combo planner).
	if context.get("mastery_owned", false):
		return

	var health_ratio: float = float(context.get("health_ratio", 1.0))
	var aoe_count: int = int(context.get("nearby_enemy_count", 0))
	var aoe_needed: int = int(context.get("aoe_needed", 3))
	var power_strike_range: float = float(context.get("power_strike_range", 14.0))
	var execute_range: float = float(context.get("execute_range", 14.0))

	if (
		health_ratio < float(context.get("defensive_hp_ratio", 0.4))
		and can_use_divine_protection()
	):
		try_divine_protection()

	if can_use_execute(execute_range):
		try_execute()
	elif can_use_power_strike(power_strike_range):
		try_power_strike()

	if can_use_ground_slam() and aoe_count >= aoe_needed:
		try_ground_slam()

func _tick_hero_abilities(delta: float) -> void:
	_tick_ground_slam_cooldown(delta)
	_tick_divine_protection(delta)
	_tick_divine_protection_cooldown(delta)
	_tick_power_strike_cooldown(delta)
	_tick_execute_cooldown(delta)

	if _has_execute_pending:
		_process_execute(delta)
		_ability_consumed_physics_frame = true
		return
	if _has_power_strike_pending:
		_process_power_strike(delta)
		_ability_consumed_physics_frame = true


func _sanitize_hero_ability_targets() -> void:
	if not NodeSafety.is_alive_node(_power_strike_target):
		_cancel_power_strike()

	if not NodeSafety.is_alive_node(_execute_target):
		_cancel_execute()


func _on_prepare_for_new_player_order() -> void:
	_cancel_power_strike()
	_cancel_execute()


func _get_ability_facing_target() -> Node3D:
	if _has_execute_pending and CombatTargetValidation.is_valid_combat_target(_execute_target):
		return _execute_target
	if _has_power_strike_pending and CombatTargetValidation.is_valid_combat_target(_power_strike_target):
		return _power_strike_target
	return null


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


func try_power_strike(target: Variant = null) -> bool:
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

	var resolved: Node3D = null
	## Never use `target is Node3D` on a Variant that may be freed — that throws.
	var clicked: Node3D = NodeSafety.safe_node(target) as Node3D
	if clicked != null and CombatTargetValidation.is_hero_unit_ability_target(self, clicked):
		resolved = clicked
	else:
		resolved = _resolve_power_strike_target(ATTACK_MOVE_ENGAGEMENT_RANGE)

	if resolved == null:
		_show_ability_feedback("No valid target")
		return false

	_begin_power_strike(resolved)
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
		_power_strike_target, self
	)
	_has_power_strike_pending = true

	if not _is_in_attack_range(_power_strike_target):
		_set_move_destination(
			_compute_attack_approach_position(
				_power_strike_target, _power_strike_approach_slot
			)
		)


func _cancel_power_strike() -> void:
	if NodeSafety.is_alive_node(_power_strike_target):
		CombatTargetValidation.release_attack_approach_slot(_power_strike_target, self)
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
	if not DamageService.apply_damage(target, float(strike_damage), self):
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
	ImpactEffects.play_unit_impact(target.global_position, 1.25)


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

	var target: Node3D = _resolve_execute_target(search_range)
	return NodeSafety.is_alive_node(target)


func try_execute(target: Variant = null) -> bool:
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

	var resolved: Node3D = null
	## Never use `target is Node3D` on a Variant that may be freed — that throws.
	var clicked: Node3D = NodeSafety.safe_node(target) as Node3D
	if clicked != null and CombatTargetValidation.is_hero_unit_ability_target(self, clicked):
		if _can_execute_target(clicked):
			resolved = clicked
	else:
		resolved = _resolve_execute_target(ATTACK_MOVE_ENGAGEMENT_RANGE)

	if resolved == null:
		_show_ability_feedback("No valid target")
		return false

	_begin_execute(resolved)
	return true


func _resolve_execute_target(search_range: float = ATTACK_MOVE_ENGAGEMENT_RANGE) -> Node3D:
	_sanitize_hero_ability_targets()

	if CombatTargetValidation.is_enemy_faction(self):
		return NodeSafety.safe_node(find_execute_target(search_range)) as Node3D

	return NodeSafety.safe_node(_resolve_ability_target()) as Node3D


func find_execute_target(search_range: float) -> Node3D:
	if search_range <= 0.0:
		return null

	PerfCounters.record_target_search()
	var best_hero: Node3D = null
	var best_hero_distance: float = INF
	var best_unit: Node3D = null
	var best_unit_distance: float = INF

	for group_name: StringName in [&"units", &"heroes"]:
		var candidates: Array = NodeSafety.clean_node_array(
			CombatTargetValidation.get_cached_group_nodes(get_tree(), group_name)
		)
		for node_variant: Variant in candidates:
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Node:
				continue

			var node: Node = node_variant as Node
			if not _is_player_military_unit(node):
				continue

			if not CombatTargetValidation.is_hero_unit_ability_target(self, node):
				continue
			if not node is Node3D:
				continue

			var target: Node3D = node as Node3D
			if not NodeSafety.is_alive_node(target):
				continue
			if not CombatTargetValidation.is_valid_combat_target(target):
				continue
			if StealthService.is_combat_hidden(target):
				continue

			var distance: float = _horizontal_distance_to(target)
			if distance > search_range:
				continue

			if not _can_execute_target(target):
				continue

			var safe_target: Node3D = NodeSafety.safe_node(target) as Node3D
			if safe_target == null:
				continue

			if node is Hero:
				if distance < best_hero_distance:
					best_hero = safe_target
					best_hero_distance = distance
			elif distance < best_unit_distance:
				best_unit = safe_target
				best_unit_distance = distance

	if NodeSafety.is_alive_node(best_hero):
		return best_hero

	if NodeSafety.is_alive_node(best_unit):
		return best_unit

	return null


func _is_player_military_unit(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if not NodeSafety.is_alive_node(node):
		return false

	if CombatTargetValidation.is_enemy_faction(node):
		return false

	return node is Spearman or node is Swordsman or node is Archer or node is HeavyCavalry or node is LightCavalry or node is CavalryArcher or node is Cannon or node is Hero


func _begin_execute(target: Node3D) -> void:
	_execute_target = NodeSafety.safe_node(target) as Node3D
	if _execute_target == null:
		return

	cancel_attack_move()
	cancel_attack()
	_cancel_power_strike()
	_execute_approach_slot = CombatTargetValidation.claim_attack_approach_slot(
		_execute_target, self
	)
	_has_execute_pending = true

	if not _is_in_attack_range(_execute_target):
		_set_move_destination(
			_compute_attack_approach_position(_execute_target, _execute_approach_slot)
		)


func _cancel_execute() -> void:
	if NodeSafety.is_alive_node(_execute_target):
		CombatTargetValidation.release_attack_approach_slot(_execute_target, self)
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
	if not NodeSafety.is_alive_node(target):
		return 1.0

	var health_component: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null or health_component.max_health <= 0:
		return 1.0

	return float(health_component.current_health) / float(health_component.max_health)


func _can_execute_target(target: Node3D) -> bool:
	if not NodeSafety.is_alive_node(target):
		return false
	if not CombatTargetValidation.is_valid_combat_target(target):
		return false

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

	if not DamageService.apply_damage(target, float(remaining_health), self):
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
	ImpactEffects.play_unit_impact(target.global_position, 1.45)


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

	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(self):
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

			DamageService.apply_damage(target, float(slam_damage), self)


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
	ImpactEffects.play_ground_impact(global_position, maxf(1.0, get_ground_slam_radius() * 0.35))


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
