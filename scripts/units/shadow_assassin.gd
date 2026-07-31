extends MeleeHero

## Shadow Assassin — Axe Mark, Smoke, Slash, Dash.

const SPINNING_AXE_SCENE: PackedScene = preload("res://scenes/projectiles/spinning_axe.tscn")
const SLASH_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/slash_effect.tscn")
const DASH_IMPACT_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/dash_impact_effect.tscn")
const MARK_CONSUME_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/mark_consume_effect.tscn")
const AREA_BUFF_ZONE_SCENE: PackedScene = preload("res://scenes/effects/area_buff_zone.tscn")

const AXE_SPAWN_HEIGHT := 0.6
const SLASH_PULSE_DURATION := 0.16
const DASH_FLASH_DURATION := 0.22
const DEFAULT_AOE_NEEDED := 2
const DEFAULT_DEFENSIVE_HP_RATIO := 0.35

var _axe_mark_cooldown_timer: float = 0.0
var _smoke_cooldown_timer: float = 0.0
var _slash_cooldown_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0

var _slash_pulse_tween: Tween
var _dash_flash_tween: Tween

var _active_smoke_zone: AreaBuffZone = null
var _is_in_smoke_zone: bool = false
var _smoke_reveal_timer: float = 0.0


func _ready() -> void:
	if passive_definition == null:
		passive_definition = HeroPassiveCatalog.create_assassin()

	attack_damage = ShadowAssassinStats.ATTACK_DAMAGE
	attack_range = ShadowAssassinStats.ATTACK_RANGE
	attack_cooldown = ShadowAssassinStats.ATTACK_COOLDOWN
	mana_regen_rate = ShadowAssassinStats.MANA_REGEN_RATE
	max_mana = ShadowAssassinStats.MAX_MANA

	super._ready()


func get_hero_kit_id() -> StringName:
	return HeroCatalog.KIT_SHADOW_ASSASSIN


func get_display_name() -> String:
	return "Shadow Assassin"


func get_kit_base_attack_damage() -> int:
	return ShadowAssassinStats.ATTACK_DAMAGE


func get_kit_base_max_mana() -> int:
	return ShadowAssassinStats.MAX_MANA


func get_kit_base_move_speed() -> float:
	return ShadowAssassinStats.MOVE_SPEED


func get_kit_base_max_health() -> int:
	return ShadowAssassinStats.MAX_HEALTH


func get_kit_attack_damage_per_level() -> int:
	return ShadowAssassinStats.ATTACK_DAMAGE_PER_LEVEL


func get_kit_health_per_level() -> int:
	return ShadowAssassinStats.HEALTH_PER_LEVEL


func get_kit_mana_per_level() -> int:
	return ShadowAssassinStats.MANA_PER_LEVEL


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


func try_cast_q(_target: Variant = null) -> bool:
	return try_axe_mark()


func try_cast_w(target: Variant = null) -> bool:
	return try_smoke(target)


func try_cast_e(_target: Variant = null) -> bool:
	return try_slash()


func try_cast_r(_target: Variant = null) -> bool:
	return try_dash()


func get_ability_target_mode(ability_id: StringName) -> int:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return AbilityTargetMode.UNIT
		HeroAbilityProgression.ABILITY_W:
			return AbilityTargetMode.GROUND
		HeroAbilityProgression.ABILITY_E:
			return AbilityTargetMode.INSTANT
		HeroAbilityProgression.ABILITY_R:
			return AbilityTargetMode.UNIT
		_:
			return AbilityTargetMode.INSTANT


func get_ability_cooldown_remaining(ability_id: StringName) -> float:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return maxf(_axe_mark_cooldown_timer, 0.0)
		HeroAbilityProgression.ABILITY_W:
			return maxf(_smoke_cooldown_timer, 0.0)
		HeroAbilityProgression.ABILITY_E:
			return maxf(_slash_cooldown_timer, 0.0)
		HeroAbilityProgression.ABILITY_R:
			return maxf(_dash_cooldown_timer, 0.0)
		_:
			return 0.0


func get_ability_active_status_text(ability_id: StringName) -> String:
	if ability_id != HeroAbilityProgression.ABILITY_W:
		return ""

	if not NodeSafety.is_alive_node(_active_smoke_zone):
		return ""

	if _is_in_smoke_zone:
		if is_combat_hidden():
			return "Hidden %.1fs" % _active_smoke_zone.get_remaining_duration()
		return "Revealed %.1fs" % maxf(_smoke_reveal_timer, 0.0)

	return "Active %.1fs" % _active_smoke_zone.get_remaining_duration()


func try_ai_cast_abilities(context: Dictionary) -> void:
	var health_ratio: float = float(context.get("health_ratio", 1.0))
	var retreating: bool = bool(context.get("retreating", false))
	var nearby_enemy_count: int = int(context.get("nearby_enemy_count", 0))
	var aoe_needed: int = int(context.get("aoe_needed", DEFAULT_AOE_NEEDED))
	var defensive_hp_ratio: float = float(
		context.get("defensive_hp_ratio", DEFAULT_DEFENSIVE_HP_RATIO)
	)
	var dash_range: float = float(
		context.get("dash_range", get_ability_range(HeroAbilityProgression.ABILITY_R))
	)
	var axe_mark_range: float = float(
		context.get("axe_mark_range", get_ability_range(HeroAbilityProgression.ABILITY_Q))
	)

	var wants_dash: bool = can_use_dash(dash_range)
	var wants_engage: bool = can_use_axe_mark(axe_mark_range) or wants_dash

	# Smoke before diving, when retreating, or when low HP.
	if can_use_smoke() and (wants_dash or retreating or health_ratio < defensive_hp_ratio):
		try_smoke()

	# Mark before engaging.
	if wants_engage and can_use_axe_mark(axe_mark_range):
		try_axe_mark()

	if wants_dash:
		try_dash()

	if can_use_slash() and nearby_enemy_count >= aoe_needed:
		try_slash()


func _tick_hero_abilities(delta: float) -> void:
	_tick_axe_mark_cooldown(delta)
	_tick_smoke_cooldown(delta)
	_tick_slash_cooldown(delta)
	_tick_dash_cooldown(delta)
	_tick_smoke_reveal(delta)


func _sanitize_hero_ability_targets() -> void:
	if _active_smoke_zone != null and not NodeSafety.is_alive_node(_active_smoke_zone):
		_clear_active_smoke_zone_state()


func _on_basic_attack_landed(target: Node3D) -> void:
	_notify_smoke_action()

	if target == null or not is_instance_valid(target):
		return

	if not AxeMarkBuff.consume(target):
		return

	if not is_instance_valid(target):
		return

	var bonus_damage: int = get_ability_bonus_damage(HeroAbilityProgression.ABILITY_Q, target)
	if bonus_damage <= 0:
		return

	if not DamageService.apply_damage(
		target, float(bonus_damage), self, {DamageService.OPT_EMPHASIZE_FLOAT: true}
	):
		return

	_refund_axe_mark_mana()

	if not is_instance_valid(target):
		return

	_spawn_mark_consume_effect(target)
	MeleeHitSound.play_at(self, target.global_position)


func _refund_axe_mark_mana() -> void:
	var refund_ratio: float = _get_axe_mark_mana_refund_ratio()
	if refund_ratio <= 0.0:
		return

	var mana_cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_Q)
	var refund: int = int(round(float(mana_cost) * refund_ratio))
	if refund <= 0:
		return

	current_mana = mini(max_mana, current_mana + refund)
	mana_changed.emit(current_mana, max_mana)


func _get_axe_mark_mana_refund_ratio() -> float:
	return float(
		HeroAbilityStats.get_stat(
			HeroAbilityProgression.ABILITY_Q,
			HeroAbilityStats.STAT_MANA_REFUND,
			get_ability_rank(HeroAbilityProgression.ABILITY_Q),
			_get_ability_base_overrides(HeroAbilityProgression.ABILITY_Q),
			get_hero_kit_id()
		)
	)


func _spawn_mark_consume_effect(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return

	var effect: Node3D = MARK_CONSUME_EFFECT_SCENE.instantiate() as Node3D
	if effect == null:
		return

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		effect.queue_free()
		return

	spawn_parent.add_child(effect)
	effect.global_position = target.global_position + Vector3(0.0, 0.65, 0.0)
	ImpactEffects.play_unit_impact(target.global_position, 1.1)


# ---------------------------------------------------------------------------
# Q — Axe Mark
# ---------------------------------------------------------------------------


func get_axe_mark_cooldown_remaining() -> float:
	return maxf(_axe_mark_cooldown_timer, 0.0)


func can_use_axe_mark(search_range: float = -1.0) -> bool:
	if not is_ability_unlocked(HeroAbilityProgression.ABILITY_Q):
		return false
	if _health_component.current_health <= 0:
		return false
	if _axe_mark_cooldown_timer > 0.0:
		return false
	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_Q):
		return false

	var resolved_range: float = search_range
	if resolved_range < 0.0:
		resolved_range = get_ability_range(HeroAbilityProgression.ABILITY_Q)
	return NodeSafety.is_alive_node(_resolve_axe_mark_target(resolved_range))


func try_axe_mark() -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_Q):
		return false

	if _axe_mark_cooldown_timer > 0.0:
		_show_ability_feedback("Axe Mark on cooldown (%.0fs)" % ceilf(_axe_mark_cooldown_timer))
		return false

	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_Q):
		_show_ability_feedback("Not enough mana")
		return false

	var target: Node3D = _resolve_axe_mark_target(get_ability_range(HeroAbilityProgression.ABILITY_Q))
	if target == null:
		_show_ability_feedback("No valid target")
		return false

	_execute_axe_mark(target)
	return true


func _resolve_axe_mark_target(search_range: float) -> Node3D:
	_sanitize_attack_target()

	var attack_target_ref: Variant = _attack_target
	if CombatTargetValidation.is_hero_unit_ability_target(self, attack_target_ref):
		var locked_target: Node3D = NodeSafety.safe_node(attack_target_ref) as Node3D
		if locked_target != null and _horizontal_distance_to(locked_target) <= search_range:
			return locked_target

	return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
		self, search_range
	)


func _execute_axe_mark(target: Node3D) -> void:
	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_Q)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_axe_mark_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_Q)
	_spawn_spinning_axe(target)
	_notify_smoke_action()


func _spawn_spinning_axe(target: Node3D) -> void:
	var safe_target: Node3D = NodeSafety.safe_node(target) as Node3D
	if safe_target == null:
		return

	var axe: SpinningAxe = SPINNING_AXE_SCENE.instantiate() as SpinningAxe
	if axe == null:
		return

	var spawn_parent: Node = get_tree().current_scene
	if spawn_parent == null:
		axe.queue_free()
		return

	spawn_parent.add_child(axe)
	var spawn_position: Vector3 = global_position + Vector3(0.0, AXE_SPAWN_HEIGHT, 0.0)
	var damage: int = get_ability_damage(HeroAbilityProgression.ABILITY_Q, safe_target)
	var mark_duration: float = get_ability_effect_strength(
		HeroAbilityProgression.ABILITY_Q, safe_target
	)
	var mark_source_id: int = get_instance_id()

	axe.launch(
		safe_target,
		float(damage),
		spawn_position,
		self,
		func(hit_target: Node3D) -> void:
			if hit_target == null or not is_instance_valid(hit_target):
				return
			var source_node: Variant = instance_from_id(mark_source_id)
			if not NodeSafety.is_alive_node(source_node):
				return
			AxeMarkBuff.apply(hit_target, source_node as Node, mark_duration)
	)


func _tick_axe_mark_cooldown(delta: float) -> void:
	if _axe_mark_cooldown_timer <= 0.0:
		return
	_axe_mark_cooldown_timer = maxf(_axe_mark_cooldown_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# W — Smoke
# ---------------------------------------------------------------------------


func get_smoke_cooldown_remaining() -> float:
	return maxf(_smoke_cooldown_timer, 0.0)


func can_use_smoke() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_W)
		and _health_component.current_health > 0
		and _smoke_cooldown_timer <= 0.0
		and current_mana >= get_ability_mana_cost(HeroAbilityProgression.ABILITY_W)
	)


func try_smoke(target: Variant = null) -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_W):
		return false

	if _smoke_cooldown_timer > 0.0:
		_show_ability_feedback("Smoke on cooldown (%.0fs)" % ceilf(_smoke_cooldown_timer))
		return false

	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_W):
		_show_ability_feedback("Not enough mana")
		return false

	var cast_position: Vector3 = global_position
	if target is Vector3:
		cast_position = target as Vector3

	_execute_smoke(cast_position)
	return true


func _execute_smoke(cast_position: Vector3) -> void:
	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_W)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_smoke_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_W)

	var zone: AreaBuffZone = AREA_BUFF_ZONE_SCENE.instantiate() as AreaBuffZone
	if zone == null:
		return

	var spawn_parent: Node = get_tree().current_scene
	if spawn_parent == null:
		zone.queue_free()
		return

	var radius: float = get_ability_splash_radius(HeroAbilityProgression.ABILITY_W)
	var duration: float = get_ability_effect_strength(HeroAbilityProgression.ABILITY_W)
	zone.affects_allies = true
	zone.affects_enemies = false
	zone.grants_stealth_to_source_only = true
	zone.configure(radius, duration, self, ShadowAssassinStats.SMOKE_MOVE_SPEED_BONUS)

	spawn_parent.add_child(zone)
	zone.global_position = Vector3(cast_position.x, 0.0, cast_position.z)

	zone.unit_entered.connect(_on_smoke_zone_unit_entered)
	zone.unit_exited.connect(_on_smoke_zone_unit_exited)
	zone.zone_expired.connect(_on_smoke_zone_expired)
	_active_smoke_zone = zone
	_is_in_smoke_zone = false
	_smoke_reveal_timer = 0.0

	ImpactEffects.play_ground_impact(zone.global_position, maxf(1.0, radius * 0.3))


func _on_smoke_zone_unit_entered(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit == self:
		_is_in_smoke_zone = true


func _on_smoke_zone_unit_exited(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit == self:
		_is_in_smoke_zone = false


func _on_smoke_zone_expired() -> void:
	_clear_active_smoke_zone_state()


func _clear_active_smoke_zone_state() -> void:
	if NodeSafety.is_alive_node(_active_smoke_zone):
		if _active_smoke_zone.unit_entered.is_connected(_on_smoke_zone_unit_entered):
			_active_smoke_zone.unit_entered.disconnect(_on_smoke_zone_unit_entered)
		if _active_smoke_zone.unit_exited.is_connected(_on_smoke_zone_unit_exited):
			_active_smoke_zone.unit_exited.disconnect(_on_smoke_zone_unit_exited)
		if _active_smoke_zone.zone_expired.is_connected(_on_smoke_zone_expired):
			_active_smoke_zone.zone_expired.disconnect(_on_smoke_zone_expired)

	_active_smoke_zone = null
	_is_in_smoke_zone = false
	_smoke_reveal_timer = 0.0


## Briefly reveals the assassin when acting while hidden in Smoke, then lets
## the zone re-hide it once the reveal window ends (if still standing inside).
func _notify_smoke_action() -> void:
	if not _is_in_smoke_zone:
		return

	_smoke_reveal_timer = ShadowAssassinStats.SMOKE_REVEAL_SECONDS
	if is_combat_hidden():
		set_combat_hidden(false)


func _tick_smoke_reveal(delta: float) -> void:
	if _smoke_reveal_timer <= 0.0:
		return

	_smoke_reveal_timer = maxf(_smoke_reveal_timer - delta, 0.0)
	if _smoke_reveal_timer > 0.0:
		return

	if _is_in_smoke_zone and NodeSafety.is_alive_node(_active_smoke_zone):
		set_combat_hidden(true)


func _tick_smoke_cooldown(delta: float) -> void:
	if _smoke_cooldown_timer <= 0.0:
		return
	_smoke_cooldown_timer = maxf(_smoke_cooldown_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# E — Slash
# ---------------------------------------------------------------------------


func get_slash_cooldown_remaining() -> float:
	return maxf(_slash_cooldown_timer, 0.0)


func can_use_slash() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_E)
		and _health_component.current_health > 0
		and _slash_cooldown_timer <= 0.0
		and current_mana >= get_ability_mana_cost(HeroAbilityProgression.ABILITY_E)
	)


func try_slash() -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_E):
		return false

	if _slash_cooldown_timer > 0.0:
		_show_ability_feedback("Slash on cooldown (%.0fs)" % ceilf(_slash_cooldown_timer))
		return false

	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_E):
		_show_ability_feedback("Not enough mana")
		return false

	_execute_slash()
	return true


func _execute_slash() -> void:
	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_E)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_slash_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_E)
	_damage_enemies_in_slash_radius()
	_spawn_slash_effect()
	_play_slash_pulse()
	MeleeHitSound.play_at(self, global_position)
	_notify_smoke_action()


func _damage_enemies_in_slash_radius() -> void:
	var slash_radius: float = get_ability_splash_radius(HeroAbilityProgression.ABILITY_E)
	var slash_damage: int = get_ability_damage(HeroAbilityProgression.ABILITY_E)

	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(self):
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(get_tree(), group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Node3D:
				continue
			if not CombatTargetValidation.is_hero_unit_ability_target(self, node_variant):
				continue

			var target: Node3D = node_variant as Node3D
			if not NodeSafety.is_alive_node(target):
				continue
			if _horizontal_distance_to(target) > slash_radius:
				continue

			DamageService.apply_damage(target, float(slash_damage), self)


func _spawn_slash_effect() -> void:
	var effect: SlashEffect = SLASH_EFFECT_SCENE.instantiate() as SlashEffect
	if effect == null:
		return

	effect.radius = get_ability_splash_radius(HeroAbilityProgression.ABILITY_E)

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		effect.queue_free()
		return

	spawn_parent.add_child(effect)
	effect.global_position = Vector3(global_position.x, 0.03, global_position.z)
	ImpactEffects.play_ground_impact(
		global_position, maxf(1.0, get_ability_splash_radius(HeroAbilityProgression.ABILITY_E) * 0.35)
	)


func _play_slash_pulse() -> void:
	if _slash_pulse_tween != null and _slash_pulse_tween.is_valid():
		_slash_pulse_tween.kill()

	_body_mesh.scale = Vector3.ONE
	_slash_pulse_tween = create_tween()
	_slash_pulse_tween.tween_property(
		_body_mesh,
		"scale",
		Vector3(1.2, 0.85, 1.2),
		SLASH_PULSE_DURATION * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slash_pulse_tween.tween_property(
		_body_mesh,
		"scale",
		Vector3.ONE,
		SLASH_PULSE_DURATION * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _tick_slash_cooldown(delta: float) -> void:
	if _slash_cooldown_timer <= 0.0:
		return
	_slash_cooldown_timer = maxf(_slash_cooldown_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# R — Dash
# ---------------------------------------------------------------------------


func get_dash_cooldown_remaining() -> float:
	return maxf(_dash_cooldown_timer, 0.0)


func can_use_dash(search_range: float = -1.0) -> bool:
	if not is_ability_unlocked(HeroAbilityProgression.ABILITY_R):
		return false
	if _health_component.current_health <= 0:
		return false
	if _dash_cooldown_timer > 0.0:
		return false
	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_R):
		return false

	var resolved_range: float = search_range
	if resolved_range < 0.0:
		resolved_range = get_ability_range(HeroAbilityProgression.ABILITY_R)
	return NodeSafety.is_alive_node(_resolve_dash_target(resolved_range))


func try_dash() -> bool:
	if _health_component.current_health <= 0:
		return false

	if not _require_ability_learned(HeroAbilityProgression.ABILITY_R):
		return false

	if _dash_cooldown_timer > 0.0:
		_show_ability_feedback("Dash on cooldown (%.0fs)" % ceilf(_dash_cooldown_timer))
		return false

	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_R):
		_show_ability_feedback("Not enough mana")
		return false

	var target: Node3D = _resolve_dash_target(get_ability_range(HeroAbilityProgression.ABILITY_R))
	if target == null:
		_show_ability_feedback("No valid target")
		return false

	_execute_dash(target)
	return true


## Prefers the lowest-HP hostile hero in range, falls back to the current
## attack target, then the nearest hostile.
func _resolve_dash_target(search_range: float) -> Node3D:
	_sanitize_attack_target()

	if search_range <= 0.0:
		return null

	var best_hero: Node3D = null
	var best_hero_ratio: float = 1.0

	for group_name: StringName in [&"units", &"heroes"]:
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(get_tree(), group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Hero:
				continue
			if not CombatTargetValidation.is_hero_unit_ability_target(self, node_variant):
				continue
			if StealthService.is_combat_hidden(node_variant):
				continue

			var target: Node3D = node_variant as Node3D
			if not NodeSafety.is_alive_node(target):
				continue
			if _horizontal_distance_to(target) > search_range:
				continue

			var ratio: float = _get_target_health_ratio(target)
			if ratio < best_hero_ratio:
				best_hero_ratio = ratio
				best_hero = target

	if NodeSafety.is_alive_node(best_hero):
		return best_hero

	var attack_target_ref: Variant = _attack_target
	if CombatTargetValidation.is_hero_unit_ability_target(self, attack_target_ref):
		var locked_target: Node3D = NodeSafety.safe_node(attack_target_ref) as Node3D
		if locked_target != null and _horizontal_distance_to(locked_target) <= search_range:
			return locked_target

	return CombatTargetValidation.find_best_attack_target_for_attacker_in_range(
		self, search_range
	)


func _get_target_health_ratio(target: Node3D) -> float:
	if not NodeSafety.is_alive_node(target):
		return 1.0

	var health_component: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null or health_component.max_health <= 0:
		return 1.0

	return float(health_component.current_health) / float(health_component.max_health)


func _execute_dash(target: Node3D) -> void:
	var safe_target: Node3D = NodeSafety.safe_node(target) as Node3D
	if safe_target == null:
		return

	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_R)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_dash_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_R)

	cancel_attack_move()
	cancel_attack()
	clear_move_target()

	var arrival_position: Vector3 = _compute_dash_arrival_position(safe_target)
	global_position = arrival_position
	_face_toward(safe_target)

	if not NodeSafety.is_alive_node(safe_target):
		_play_dash_flash()
		_notify_smoke_action()
		return

	var dash_damage: int = get_ability_damage(HeroAbilityProgression.ABILITY_R, safe_target)
	DamageService.apply_damage(
		safe_target, float(dash_damage), self, {DamageService.OPT_EMPHASIZE_FLOAT: true}
	)

	if NodeSafety.is_alive_node(safe_target):
		MeleeHitSound.play_at(self, safe_target.global_position)
		_spawn_dash_impact_effect(safe_target)

	_play_dash_flash()
	_notify_smoke_action()


func _compute_dash_arrival_position(target: Node3D) -> Vector3:
	if not NodeSafety.is_alive_node(target):
		return global_position

	var offset: Vector3 = global_position - target.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.001:
		offset = Vector3.FORWARD
	else:
		offset = offset.normalized()

	var arrival: Vector3 = target.global_position + offset * ShadowAssassinStats.DASH_ARRIVAL_OFFSET
	arrival.y = global_position.y
	return arrival


func _face_toward(target: Node3D) -> void:
	if not NodeSafety.is_alive_node(target):
		return

	var direction: Vector3 = target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return

	look_at(global_position + direction.normalized(), Vector3.UP)


func _spawn_dash_impact_effect(target: Node3D) -> void:
	if not NodeSafety.is_alive_node(target):
		return

	var effect: DashImpactEffect = DASH_IMPACT_EFFECT_SCENE.instantiate() as DashImpactEffect
	if effect == null:
		return

	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		effect.queue_free()
		return

	spawn_parent.add_child(effect)
	effect.global_position = target.global_position + Vector3(0.0, 0.7, 0.0)
	ImpactEffects.play_unit_impact(target.global_position, 1.35)


func _play_dash_flash() -> void:
	if _dash_flash_tween != null and _dash_flash_tween.is_valid():
		_dash_flash_tween.kill()

	_body_material.emission_enabled = true
	_body_material.emission = Color(0.6, 0.2, 0.85, 1.0)
	_body_material.albedo_color = Color(0.8, 0.55, 0.95, 1.0)

	_body_mesh.scale = Vector3(0.75, 1.15, 0.75)

	_dash_flash_tween = create_tween()
	_dash_flash_tween.set_parallel(true)
	_dash_flash_tween.tween_property(
		_body_mesh, "scale", Vector3.ONE, DASH_FLASH_DURATION
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_dash_flash_tween.tween_property(
		_body_material, "albedo_color", _body_base_color, DASH_FLASH_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dash_flash_tween.tween_property(
		_body_material, "emission", Color.BLACK, DASH_FLASH_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dash_flash_tween.finished.connect(_on_dash_flash_finished, CONNECT_ONE_SHOT)


func _on_dash_flash_finished() -> void:
	_body_material.emission_enabled = false
	_body_material.albedo_color = _body_base_color


func _tick_dash_cooldown(delta: float) -> void:
	if _dash_cooldown_timer <= 0.0:
		return
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
