extends MeleeHero

## Ranger — Combat Roll, Bear Trap, Crossbow Bolt, Camouflage.
## Ranged ADC/Marksman focused on positioning, traps, and sustained single-target damage.

const BASIC_ARROW_SCENE: PackedScene = preload("res://scenes/projectiles/ranger_basic_arrow.tscn")
const CROSSBOW_BOLT_SCENE: PackedScene = preload("res://scenes/projectiles/crossbow_bolt.tscn")
const BEAR_TRAP_SCENE: PackedScene = preload("res://scenes/effects/bear_trap.tscn")

const DEFAULT_AOE_NEEDED := 2
const DEFAULT_DEFENSIVE_HP_RATIO := 0.35
const ROLL_SQUASH_DURATION := 0.22

var _combat_roll_cooldown_timer: float = 0.0
var _bear_trap_cooldown_timer: float = 0.0
var _crossbow_bolt_cooldown_timer: float = 0.0
var _camouflage_cooldown_timer: float = 0.0

var _trap_charges: int = RangerStats.BEAR_TRAP_MAX_CHARGES
var _trap_recharge_timer: float = 0.0

var _is_rolling: bool = false
var _roll_remaining: float = 0.0
var _roll_speed_bonus: float = 0.0
var _roll_base_move_speed: float = 0.0

var _camouflage_remaining: float = 0.0
var _camouflage_active: bool = false
var _camouflage_restore_timer: float = 0.0
var _camouflage_speed_bonus_applied: float = 0.0

var _roll_squash_tween: Tween
var _active_traps: Array[BearTrap] = []


func _ready() -> void:
	if passive_definition == null:
		passive_definition = HeroPassiveCatalog.create_ranger()

	attack_damage = RangerStats.ATTACK_DAMAGE
	attack_range = RangerStats.ATTACK_RANGE
	attack_cooldown = RangerStats.ATTACK_COOLDOWN
	mana_regen_rate = RangerStats.MANA_REGEN_RATE
	max_mana = RangerStats.MAX_MANA
	_trap_charges = RangerStats.BEAR_TRAP_MAX_CHARGES

	super._ready()


func get_hero_kit_id() -> StringName:
	return HeroCatalog.KIT_RANGER


func get_display_name() -> String:
	return "Ranger"


func get_kit_base_attack_damage() -> int:
	return RangerStats.ATTACK_DAMAGE


func get_kit_base_max_mana() -> int:
	return RangerStats.MAX_MANA


func get_kit_base_move_speed() -> float:
	return RangerStats.MOVE_SPEED


func get_kit_base_max_health() -> int:
	return RangerStats.MAX_HEALTH


func get_kit_attack_damage_per_level() -> int:
	return RangerStats.ATTACK_DAMAGE_PER_LEVEL


func get_kit_health_per_level() -> int:
	return RangerStats.HEALTH_PER_LEVEL


func get_kit_mana_per_level() -> int:
	return RangerStats.MANA_PER_LEVEL


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


func try_cast_q(target: Variant = null) -> bool:
	return try_combat_roll(target)


func try_cast_w(target: Variant = null) -> bool:
	return try_bear_trap(target)


func try_cast_e(target: Variant = null) -> bool:
	return try_crossbow_bolt(target)


func try_cast_r(_target: Variant = null) -> bool:
	return try_camouflage()


func get_ability_target_mode(ability_id: StringName) -> int:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return AbilityTargetMode.GROUND
		HeroAbilityProgression.ABILITY_W:
			return AbilityTargetMode.GROUND
		HeroAbilityProgression.ABILITY_E:
			return AbilityTargetMode.GROUND
		HeroAbilityProgression.ABILITY_R:
			return AbilityTargetMode.INSTANT
		_:
			return AbilityTargetMode.INSTANT


func get_ability_cooldown_remaining(ability_id: StringName) -> float:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return maxf(_combat_roll_cooldown_timer, 0.0)
		HeroAbilityProgression.ABILITY_W:
			return maxf(_bear_trap_cooldown_timer, 0.0)
		HeroAbilityProgression.ABILITY_E:
			return maxf(_crossbow_bolt_cooldown_timer, 0.0)
		HeroAbilityProgression.ABILITY_R:
			return maxf(_camouflage_cooldown_timer, 0.0)
		_:
			return 0.0


func get_ability_active_status_text(ability_id: StringName) -> String:
	match ability_id:
		HeroAbilityProgression.ABILITY_W:
			return "%d/%d" % [_trap_charges, RangerStats.BEAR_TRAP_MAX_CHARGES]
		HeroAbilityProgression.ABILITY_R:
			if _camouflage_active:
				return "Hidden %.1fs" % _camouflage_remaining
			if _camouflage_restore_timer > 0.0 and _camouflage_remaining > 0.0:
				return "Restore %.1fs" % _camouflage_restore_timer
			if _camouflage_remaining > 0.0:
				return "%.1fs" % _camouflage_remaining
			return ""
		_:
			return ""


func try_ai_cast_abilities(context: Dictionary) -> void:
	var health_ratio: float = float(context.get("health_ratio", 1.0))
	var retreating: bool = bool(context.get("retreating", false))
	var nearby_enemy_count: int = int(context.get("nearby_enemy_count", 0))
	var aoe_needed: int = int(context.get("aoe_needed", DEFAULT_AOE_NEEDED))
	var defensive_hp_ratio: float = float(
		context.get("defensive_hp_ratio", DEFAULT_DEFENSIVE_HP_RATIO)
	)

	# R — escape when low, or ambush before a large fight.
	if can_use_camouflage():
		if health_ratio < defensive_hp_ratio or retreating:
			try_camouflage()
		elif nearby_enemy_count >= aoe_needed and not _camouflage_active:
			try_camouflage()

	# Q — kite melee / escape / reposition.
	if can_use_combat_roll():
		if health_ratio < defensive_hp_ratio or retreating or _is_melee_threat_nearby():
			try_combat_roll(_resolve_ai_roll_target())

	# W — traps near self / army / retreat path.
	if can_use_bear_trap():
		if nearby_enemy_count > 0 or retreating or _should_defend_with_trap():
			try_bear_trap(_resolve_ai_trap_position(retreating))

	# E — poke heroes / pierce clumps.
	if can_use_crossbow_bolt():
		if nearby_enemy_count >= aoe_needed or _has_hero_in_bolt_range():
			try_crossbow_bolt()


func _tick_hero_abilities(delta: float) -> void:
	_tick_combat_roll_cooldown(delta)
	_tick_bear_trap_cooldown(delta)
	_tick_trap_recharge(delta)
	_tick_crossbow_bolt_cooldown(delta)
	_tick_camouflage_cooldown(delta)
	_tick_combat_roll_state(delta)
	_tick_camouflage_state(delta)
	_sanitize_active_traps()


func _sanitize_hero_ability_targets() -> void:
	_sanitize_active_traps()


func _on_basic_attack_landed(_target: Node3D) -> void:
	_break_camouflage_from_action(false)


## Ranged basic attacks — fire projectiles instead of melee DamageService hits.
func _stop_and_attack(delta: float) -> void:
	clear_move_target()
	_has_chase_target = false
	_is_backing_off_for_range = false
	UnitSeparation.apply_standing_push(self, move_speed, true)

	_attack_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		return

	if not CombatTargetValidation.is_valid_combat_target(_attack_target):
		_finish_attack_target_lost()
		return

	var strike_target: Node3D = _attack_target
	_break_camouflage_from_action(false)
	_fire_basic_arrow(strike_target)
	_attack_cooldown_timer = attack_cooldown
	_play_attack_animation()

	if not NodeSafety.is_alive_node(_attack_target):
		_finish_attack_target_lost()


func _fire_basic_arrow(target: Node3D) -> void:
	if not NodeSafety.is_alive_node(target):
		return

	var arrow: RangerBasicArrow = BASIC_ARROW_SCENE.instantiate() as RangerBasicArrow
	if arrow == null:
		return

	var spawn_parent: Node = get_tree().current_scene
	if spawn_parent == null:
		arrow.queue_free()
		return

	spawn_parent.add_child(arrow)
	var spawn_position: Vector3 = global_position + Vector3(0.0, RangerStats.BASIC_ARROW_SPAWN_HEIGHT, 0.0)
	arrow.launch(target, float(attack_damage), spawn_position, self)


# ---------------------------------------------------------------------------
# Q — Combat Roll
# ---------------------------------------------------------------------------


func can_use_combat_roll() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_Q)
		and _health_component.current_health > 0
		and _combat_roll_cooldown_timer <= 0.0
		and not _is_rolling
		and current_mana >= get_ability_mana_cost(HeroAbilityProgression.ABILITY_Q)
	)


func try_combat_roll(target: Variant = null) -> bool:
	if _health_component.current_health <= 0:
		return false
	if not _require_ability_learned(HeroAbilityProgression.ABILITY_Q):
		return false
	if _is_rolling:
		return false
	if _combat_roll_cooldown_timer > 0.0:
		_show_ability_feedback("Combat Roll on cooldown (%.0fs)" % ceilf(_combat_roll_cooldown_timer))
		return false
	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_Q):
		_show_ability_feedback("Not enough mana")
		return false

	var destination: Vector3 = _resolve_roll_destination(target)
	_execute_combat_roll(destination)
	return true


func _resolve_roll_destination(target: Variant) -> Vector3:
	var aim: Vector3 = _resolve_ground_aim(target)
	var direction: Vector3 = aim - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = -global_transform.basis.z
		direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD

	direction = direction.normalized()
	var desired: Vector3 = global_position + direction * RangerStats.COMBAT_ROLL_DISTANCE
	return _snap_to_navigation(desired)


func _execute_combat_roll(destination: Vector3) -> void:
	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_Q)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_combat_roll_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_Q)

	# Special: Q while camouflaged temporarily breaks stealth, then may restore.
	var was_camouflaged: bool = _camouflage_active or (
		_camouflage_remaining > 0.0 and _camouflage_restore_timer > 0.0
	)
	_break_camouflage_from_action(true)
	if was_camouflaged and _camouflage_remaining > 0.0:
		_camouflage_restore_timer = RangerStats.CAMOUFLAGE_ROLL_RESTORE_SECONDS

	cancel_attack_move()
	cancel_attack()

	_is_rolling = true
	_roll_remaining = RangerStats.COMBAT_ROLL_MAX_DURATION
	_roll_base_move_speed = move_speed
	_roll_speed_bonus = move_speed * (RangerStats.COMBAT_ROLL_MOVE_SPEED_MULT - 1.0)
	move_speed += _roll_speed_bonus

	set_movement_target(destination)
	_play_roll_squash()
	ImpactEffects.play_ground_impact(global_position, 0.85)


func _tick_combat_roll_state(delta: float) -> void:
	if not _is_rolling:
		return

	_roll_remaining = maxf(_roll_remaining - delta, 0.0)
	var arrived: bool = not has_move_target
	if arrived or _roll_remaining <= 0.0:
		_finish_combat_roll()


func _finish_combat_roll() -> void:
	if not _is_rolling:
		return
	_is_rolling = false
	_roll_remaining = 0.0
	if _roll_speed_bonus != 0.0:
		move_speed = maxf(move_speed - _roll_speed_bonus, 0.1)
		_roll_speed_bonus = 0.0
	clear_move_target()


func _play_roll_squash() -> void:
	if _roll_squash_tween != null and _roll_squash_tween.is_valid():
		_roll_squash_tween.kill()

	_body_mesh.scale = Vector3.ONE
	_roll_squash_tween = create_tween()
	_roll_squash_tween.tween_property(
		_body_mesh, "scale", Vector3(1.25, 0.7, 1.25), ROLL_SQUASH_DURATION * 0.4
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_roll_squash_tween.tween_property(
		_body_mesh, "scale", Vector3.ONE, ROLL_SQUASH_DURATION * 0.6
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _tick_combat_roll_cooldown(delta: float) -> void:
	if _combat_roll_cooldown_timer <= 0.0:
		return
	_combat_roll_cooldown_timer = maxf(_combat_roll_cooldown_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# W — Bear Trap
# ---------------------------------------------------------------------------


func can_use_bear_trap() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_W)
		and _health_component.current_health > 0
		and _bear_trap_cooldown_timer <= 0.0
		and _trap_charges > 0
		and current_mana >= get_ability_mana_cost(HeroAbilityProgression.ABILITY_W)
	)


func try_bear_trap(target: Variant = null) -> bool:
	if _health_component.current_health <= 0:
		return false
	if not _require_ability_learned(HeroAbilityProgression.ABILITY_W):
		return false
	if _trap_charges <= 0:
		_show_ability_feedback("No Bear Trap charges")
		return false
	if _bear_trap_cooldown_timer > 0.0:
		_show_ability_feedback("Bear Trap on cooldown (%.0fs)" % ceilf(_bear_trap_cooldown_timer))
		return false
	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_W):
		_show_ability_feedback("Not enough mana")
		return false

	var place_position: Vector3 = _resolve_trap_position(target)
	_execute_bear_trap(place_position)
	return true


func _resolve_trap_position(target: Variant) -> Vector3:
	var aim: Vector3 = _resolve_ground_aim(target)
	var offset: Vector3 = aim - global_position
	offset.y = 0.0
	var place_range: float = RangerStats.BEAR_TRAP_PLACE_RANGE
	if offset.length() > place_range:
		offset = offset.normalized() * place_range
		aim = global_position + offset
	aim.y = 0.0
	return _snap_to_navigation(aim)


func _execute_bear_trap(place_position: Vector3) -> void:
	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_W)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_bear_trap_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_W)
	_trap_charges = maxi(0, _trap_charges - 1)
	if _trap_charges < RangerStats.BEAR_TRAP_MAX_CHARGES and _trap_recharge_timer <= 0.0:
		_trap_recharge_timer = RangerStats.BEAR_TRAP_RECHARGE_SECONDS

	_break_camouflage_from_action(false)

	var trap: BearTrap = BEAR_TRAP_SCENE.instantiate() as BearTrap
	if trap == null:
		return

	var spawn_parent: Node = get_tree().current_scene
	if spawn_parent == null:
		trap.queue_free()
		return

	var trap_damage: int = get_ability_damage(HeroAbilityProgression.ABILITY_W)
	var root_duration: float = get_ability_effect_strength(HeroAbilityProgression.ABILITY_W)
	trap.configure(
		float(trap_damage),
		root_duration,
		RangerStats.BEAR_TRAP_LIFETIME,
		RangerStats.BEAR_TRAP_TRIGGER_RADIUS,
		self
	)

	spawn_parent.add_child(trap)
	trap.global_position = Vector3(place_position.x, 0.0, place_position.z)
	_active_traps.append(trap)
	ImpactEffects.play_ground_impact(trap.global_position, 0.7)


func _tick_trap_recharge(delta: float) -> void:
	if _trap_charges >= RangerStats.BEAR_TRAP_MAX_CHARGES:
		_trap_recharge_timer = 0.0
		return
	if _trap_recharge_timer <= 0.0:
		_trap_recharge_timer = RangerStats.BEAR_TRAP_RECHARGE_SECONDS
		return

	_trap_recharge_timer = maxf(_trap_recharge_timer - delta, 0.0)
	if _trap_recharge_timer > 0.0:
		return

	_trap_charges = mini(RangerStats.BEAR_TRAP_MAX_CHARGES, _trap_charges + 1)
	if _trap_charges < RangerStats.BEAR_TRAP_MAX_CHARGES:
		_trap_recharge_timer = RangerStats.BEAR_TRAP_RECHARGE_SECONDS


func _tick_bear_trap_cooldown(delta: float) -> void:
	if _bear_trap_cooldown_timer <= 0.0:
		return
	_bear_trap_cooldown_timer = maxf(_bear_trap_cooldown_timer - delta, 0.0)


func _sanitize_active_traps() -> void:
	var alive: Array[BearTrap] = []
	for trap: BearTrap in _active_traps:
		if NodeSafety.is_alive_node(trap):
			alive.append(trap)
	_active_traps = alive


# ---------------------------------------------------------------------------
# E — Crossbow Bolt
# ---------------------------------------------------------------------------


func can_use_crossbow_bolt() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_E)
		and _health_component.current_health > 0
		and _crossbow_bolt_cooldown_timer <= 0.0
		and current_mana >= get_ability_mana_cost(HeroAbilityProgression.ABILITY_E)
	)


func try_crossbow_bolt(target: Variant = null) -> bool:
	if _health_component.current_health <= 0:
		return false
	if not _require_ability_learned(HeroAbilityProgression.ABILITY_E):
		return false
	if _crossbow_bolt_cooldown_timer > 0.0:
		_show_ability_feedback("Crossbow Bolt on cooldown (%.0fs)" % ceilf(_crossbow_bolt_cooldown_timer))
		return false
	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_E):
		_show_ability_feedback("Not enough mana")
		return false

	var direction: Vector3 = _resolve_bolt_direction(target)
	_execute_crossbow_bolt(direction)
	return true


func _resolve_bolt_direction(target: Variant) -> Vector3:
	if target is Node3D and NodeSafety.is_alive_node(target):
		var to_unit: Vector3 = (target as Node3D).global_position - global_position
		to_unit.y = 0.0
		if to_unit.length_squared() > 0.001:
			return to_unit.normalized()

	_sanitize_attack_target()
	if NodeSafety.is_alive_node(_attack_target):
		var to_attack: Vector3 = _attack_target.global_position - global_position
		to_attack.y = 0.0
		if to_attack.length_squared() > 0.001:
			return to_attack.normalized()

	var aim: Vector3 = _resolve_ground_aim(target)
	var direction: Vector3 = aim - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = -global_transform.basis.z
		direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	return direction.normalized()


func _execute_crossbow_bolt(direction: Vector3) -> void:
	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_E)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_crossbow_bolt_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_E)
	_break_camouflage_from_action(false)

	var bolt: CrossbowBolt = CROSSBOW_BOLT_SCENE.instantiate() as CrossbowBolt
	if bolt == null:
		return

	var spawn_parent: Node = get_tree().current_scene
	if spawn_parent == null:
		bolt.queue_free()
		return

	spawn_parent.add_child(bolt)
	var spawn_position: Vector3 = global_position + Vector3(0.0, 0.6, 0.0)
	var bolt_damage: int = get_ability_damage(HeroAbilityProgression.ABILITY_E)
	var bolt_range: float = get_ability_range(HeroAbilityProgression.ABILITY_E)
	bolt.launch(
		direction,
		float(bolt_damage),
		spawn_position,
		bolt_range,
		self,
		RangerStats.CROSSBOW_BOLT_PIERCE_DAMAGE_MULT
	)
	_face_direction(direction)


func _tick_crossbow_bolt_cooldown(delta: float) -> void:
	if _crossbow_bolt_cooldown_timer <= 0.0:
		return
	_crossbow_bolt_cooldown_timer = maxf(_crossbow_bolt_cooldown_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# R — Camouflage
# ---------------------------------------------------------------------------


func can_use_camouflage() -> bool:
	return (
		is_ability_unlocked(HeroAbilityProgression.ABILITY_R)
		and _health_component.current_health > 0
		and _camouflage_cooldown_timer <= 0.0
		and not _camouflage_active
		and _camouflage_remaining <= 0.0
		and current_mana >= get_ability_mana_cost(HeroAbilityProgression.ABILITY_R)
	)


func try_camouflage() -> bool:
	if _health_component.current_health <= 0:
		return false
	if not _require_ability_learned(HeroAbilityProgression.ABILITY_R):
		return false
	if _camouflage_cooldown_timer > 0.0:
		_show_ability_feedback("Camouflage on cooldown (%.0fs)" % ceilf(_camouflage_cooldown_timer))
		return false
	if _camouflage_active or _camouflage_remaining > 0.0:
		_show_ability_feedback("Already camouflaged")
		return false
	if current_mana < get_ability_mana_cost(HeroAbilityProgression.ABILITY_R):
		_show_ability_feedback("Not enough mana")
		return false

	_execute_camouflage()
	return true


func _execute_camouflage() -> void:
	var cost: int = get_ability_mana_cost(HeroAbilityProgression.ABILITY_R)
	current_mana = maxi(0, current_mana - cost)
	mana_changed.emit(current_mana, max_mana)
	_camouflage_cooldown_timer = get_ability_cooldown(HeroAbilityProgression.ABILITY_R)

	_camouflage_remaining = RangerStats.get_camouflage_duration(
		get_ability_rank(HeroAbilityProgression.ABILITY_R)
	)
	_camouflage_restore_timer = 0.0
	_apply_camouflage_hidden(true)


func _apply_camouflage_hidden(hidden: bool) -> void:
	_camouflage_active = hidden
	StealthService.set_combat_hidden(self, hidden)
	if hidden:
		if _camouflage_speed_bonus_applied <= 0.0:
			_camouflage_speed_bonus_applied = RangerStats.CAMOUFLAGE_MOVE_SPEED_BONUS
			move_speed += _camouflage_speed_bonus_applied
	else:
		if _camouflage_speed_bonus_applied > 0.0:
			move_speed = maxf(move_speed - _camouflage_speed_bonus_applied, 0.1)
			_camouflage_speed_bonus_applied = 0.0


## break_only_stealth: Q special — ends visibility but keeps remaining duration for restore.
func _break_camouflage_from_action(break_only_stealth: bool) -> void:
	if _camouflage_remaining <= 0.0 and not _camouflage_active:
		_camouflage_restore_timer = 0.0
		return

	if break_only_stealth:
		if _camouflage_active:
			_apply_camouflage_hidden(false)
		return

	# Permanent break from AA / W / E.
	_camouflage_remaining = 0.0
	_camouflage_restore_timer = 0.0
	if _camouflage_active or is_combat_hidden():
		_apply_camouflage_hidden(false)


func _tick_camouflage_state(delta: float) -> void:
	if _camouflage_remaining > 0.0:
		_camouflage_remaining = maxf(_camouflage_remaining - delta, 0.0)
		if _camouflage_remaining <= 0.0:
			_camouflage_restore_timer = 0.0
			if _camouflage_active:
				_apply_camouflage_hidden(false)
			return

	if _camouflage_restore_timer > 0.0:
		_camouflage_restore_timer = maxf(_camouflage_restore_timer - delta, 0.0)
		if _camouflage_restore_timer <= 0.0 and _camouflage_remaining > 0.0 and not _camouflage_active:
			_apply_camouflage_hidden(true)


func _tick_camouflage_cooldown(delta: float) -> void:
	if _camouflage_cooldown_timer <= 0.0:
		return
	_camouflage_cooldown_timer = maxf(_camouflage_cooldown_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


func _resolve_ground_aim(target: Variant) -> Vector3:
	if target is Vector3:
		var as_vector: Vector3 = target as Vector3
		if as_vector.is_finite():
			return as_vector

	var mouse_ground: Vector3 = _get_mouse_ground_position()
	if mouse_ground.is_finite():
		return mouse_ground

	return global_position - global_transform.basis.z


func _get_mouse_ground_position() -> Vector3:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector3(INF, INF, INF)

	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return Vector3(INF, INF, INF)

	var screen_position: Vector2 = viewport.get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return Vector3(INF, INF, INF)

	var intersection_distance: float = -ray_origin.y / ray_direction.y
	if intersection_distance < 0.0:
		return Vector3(INF, INF, INF)

	return ray_origin + ray_direction * intersection_distance


func _snap_to_navigation(desired: Vector3) -> Vector3:
	var result: Vector3 = desired
	result.y = global_position.y

	if _navigation_agent != null and UnitNavigation.can_use(_navigation_agent):
		var nav_map: RID = _navigation_agent.get_navigation_map()
		if nav_map != RID():
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, result)
			result = Vector3(snapped.x, global_position.y, snapped.z)

	return result


func _face_direction(direction: Vector3) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() <= 0.001:
		return
	look_at(global_position + flat.normalized(), Vector3.UP)


func _is_melee_threat_nearby() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false

	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(self):
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Unit:
				continue
			if not CombatTargetValidation.are_hostile(self, node_variant):
				continue
			var unit: Unit = node_variant as Unit
			if _horizontal_distance_to(unit) > 3.5:
				continue
			if "attack_range" in unit and float(unit.get("attack_range")) <= 3.5:
				return true
			if unit is Hero:
				return true
	return false


func _resolve_ai_roll_target() -> Vector3:
	var away: Vector3 = Vector3.ZERO
	var tree: SceneTree = get_tree()
	if tree != null:
		for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(self):
			for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
				if not NodeSafety.is_alive_node(node_variant) or not node_variant is Node3D:
					continue
				if not CombatTargetValidation.are_hostile(self, node_variant):
					continue
				var target: Node3D = node_variant as Node3D
				var offset: Vector3 = global_position - target.global_position
				offset.y = 0.0
				var dist: float = offset.length()
				if dist > 8.0 or dist < 0.001:
					continue
				away += offset.normalized() / maxf(dist, 0.5)

	if away.length_squared() < 0.001:
		away = global_transform.basis.z
		away.y = 0.0
	return global_position + away.normalized() * RangerStats.COMBAT_ROLL_DISTANCE


func _resolve_ai_trap_position(retreating: bool) -> Vector3:
	if retreating:
		return global_position
	if NodeSafety.is_alive_node(_attack_target):
		var mid: Vector3 = (_attack_target.global_position + global_position) * 0.5
		mid.y = 0.0
		return mid
	return global_position + (-global_transform.basis.z) * 2.0


func _should_defend_with_trap() -> bool:
	return _trap_charges >= 2


func _has_hero_in_bolt_range() -> bool:
	var bolt_range: float = get_ability_range(HeroAbilityProgression.ABILITY_E)
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, &"heroes"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Hero:
			continue
		if not CombatTargetValidation.is_hero_unit_ability_target(self, node_variant):
			continue
		if _horizontal_distance_to(node_variant as Node3D) <= bolt_range:
			return true
	return false


func _exit_tree() -> void:
	if _is_rolling:
		_finish_combat_roll()
	if _camouflage_speed_bonus_applied > 0.0 or _camouflage_active:
		_apply_camouflage_hidden(false)
	super._exit_tree()
