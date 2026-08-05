extends Node

## Owns AI hero kit selection (once per match) and hero tactical combat decisions.
## Autoload singleton - Wave manager / ArmyCommanderV2 call tick(); kit ability casts stay on heroes.
##
## Hero AI boundary (Military AI V2):
## MAY: cast abilities, choose targets during the current mission, perform survival micro.
## MAY NOT: choose the army mission, start creeping, launch attacks, order regrouping,
##          or override defend/retreat states owned by MilitaryDirectorV2.

const AIHeroComboPlanner = preload("res://scripts/systems/ai_hero_combo_planner.gd")

enum TacticalState {
	FOLLOW_ARMY,
	POKE,
	ENGAGE,
	COMBO,
	KITE,
	PROTECT_BACKLINE,
	ESCAPE,
	REPOSITION,
	DEFEND_BASE,
	RETURN_TO_ARMY,
}

const SEARCH_RANGE := 18.0
const HERO_PRIORITY_RANGE := 16.0
const FOCUS_STICK_SECONDS := 2.5
const MICRO_MOVE_COOLDOWN := 0.85
const TRAP_MIN_SPACING := 3.5
const OUTNUMBERED_RATIO := 0.45
const LOW_HP_RATIO := 0.38
const CRITICAL_HP_RATIO := 0.28
const SAFE_BUILDING_THREAT_RADIUS := 7.0
const ROLE_ANCHOR_SETTLE_DISTANCE := 1.6
const PALADIN_SQUAD_CHASE_LEASH := 10.0
const ASSASSIN_SQUAD_CHASE_LEASH := 14.0
## Enemy ability upgrade order: main damage, survival, secondary damage, then ultimate.
const ABILITY_UPGRADE_PRIORITY: Array[StringName] = [
	HeroAbilityProgression.ABILITY_Q,
	HeroAbilityProgression.ABILITY_W,
	HeroAbilityProgression.ABILITY_E,
	HeroAbilityProgression.ABILITY_R,
]

## Equal weight across the three Human kits (≈33.33% each).
const AI_HERO_POOL: Array[StringName] = [
	HeroCatalog.KIT_PALADIN,
	HeroCatalog.KIT_SHADOW_ASSASSIN,
	HeroCatalog.KIT_RANGER,
]

var _tactical_state: TacticalState = TacticalState.FOLLOW_ARMY
var _combo: RefCounted = null
var _focus_target_id: int = 0
var _focus_target_handle: EntityHandle = EntityHandle.empty()
var _focus_acquired_at: float = 0.0
var _last_micro_move_at: float = -999.0
var _last_trap_positions: Array[Vector3] = []
var _selection_announced: bool = false
var _forced_kit_override: StringName = &""
var _suppress_selection_log: bool = false
var _last_debug_state: String = ""
var _last_debug_retreat: String = ""
var _last_debug_trap: String = ""
var _last_debug_smoke: String = ""
var _last_debug_divine: String = ""


func reset_match_state() -> void:
	_tactical_state = TacticalState.FOLLOW_ARMY
	_combo = null
	_focus_target_id = 0
	_focus_target_handle = EntityHandle.empty()
	_focus_acquired_at = 0.0
	_last_micro_move_at = -999.0
	_last_trap_positions.clear()
	_selection_announced = false
	_forced_kit_override = &""
	_suppress_selection_log = false
	_last_debug_state = ""
	_last_debug_retreat = ""
	_last_debug_trap = ""
	_last_debug_smoke = ""
	_last_debug_divine = ""


func _planner() -> AIHeroComboPlanner:
	if _combo == null:
		_combo = AIHeroComboPlanner.new()
	return _combo as AIHeroComboPlanner


## Test helper — forces the next ensure_enemy_hero_choice() kit (still locked once).
func set_forced_kit_for_tests(kit_id: StringName) -> void:
	_forced_kit_override = HeroCatalog.normalize_kit_id(kit_id) if kit_id != &"" else &""


func set_suppress_selection_log_for_tests(suppress: bool) -> void:
	_suppress_selection_log = suppress


func get_tactical_state() -> TacticalState:
	return _tactical_state


func get_tactical_state_name(state: TacticalState = _tactical_state) -> String:
	match state:
		TacticalState.FOLLOW_ARMY:
			return "FOLLOW_ARMY"
		TacticalState.POKE:
			return "POKE"
		TacticalState.ENGAGE:
			return "ENGAGE"
		TacticalState.COMBO:
			return "COMBO"
		TacticalState.KITE:
			return "KITE"
		TacticalState.PROTECT_BACKLINE:
			return "PROTECT_BACKLINE"
		TacticalState.ESCAPE:
			return "ESCAPE"
		TacticalState.REPOSITION:
			return "REPOSITION"
		TacticalState.DEFEND_BASE:
			return "DEFEND_BASE"
		TacticalState.RETURN_TO_ARMY:
			return "RETURN_TO_ARMY"
		_:
			return "UNKNOWN"


## Choose and lock the AI hero once per match before the first Altar training order.
## Equal random weights. Never rerolls on death, resources, delay, or Altar rebuild.
func ensure_enemy_hero_choice() -> StringName:
	if HeroProgressionStore.has_locked_kit(true):
		var locked: StringName = HeroProgressionStore.get_locked_kit_id(true)
		_announce_selection_once(locked)
		return locked

	var kit_id: StringName = _pick_enemy_hero_kit()
	HeroProgressionStore.lock_kit(true, kit_id)
	_announce_selection_once(kit_id)
	return kit_id


func _pick_enemy_hero_kit() -> StringName:
	if _forced_kit_override != &"" and HeroCatalog.is_valid_kit(_forced_kit_override):
		return _forced_kit_override

	var saved: StringName = HeroProgressionStore.get_saved_kit_id(true)
	if saved != &"":
		return HeroCatalog.normalize_kit_id(saved)

	var index: int = randi() % AI_HERO_POOL.size()
	return AI_HERO_POOL[index]


func _announce_selection_once(kit_id: StringName) -> void:
	if _selection_announced:
		return
	_selection_announced = true
	if _suppress_selection_log:
		return
	var message: String = "AI selected hero: %s" % HeroCatalog.get_display_name(kit_id)
	print(message)
	_debug_log(message)


## Primary AI hero micro entry - owns tactical state and combos.
## Under Military AI V2, army mission / creep / attack / defend / retreat are owned by
## MilitaryDirectorV2. This tick only performs ability casting, target choice, and survival micro.
func tick(hero: Hero, context: Dictionary) -> void:
	if not NodeSafety.is_alive_node(hero):
		return
	if not CombatTargetValidation.is_enemy_faction(hero):
		return

	ensure_enemy_hero_choice()
	spend_ability_points(hero)
	if not NodeSafety.is_alive_node(hero):
		return

	var now: float = _now_seconds()
	var situation: Dictionary = _build_situation(hero, context)
	_update_tactical_state(hero, situation)
	situation["tactical_state"] = _tactical_state
	situation["tactical_state_name"] = get_tactical_state_name()

	var focus: Node3D = _resolve_focus_target(hero, situation, now)
	situation["focus_target"] = focus

	if _should_abort_combo(situation):
		var planner: AIHeroComboPlanner = _planner()
		if planner.is_active():
			var reason: String = str(situation.get("combo_abort_reason", "emergency"))
			planner.abort(reason)
			_debug_log_throttled("combo_abort", "Hero combo aborted: %s" % reason)

	if _planner().is_active():
		_set_state(TacticalState.COMBO)
		_tick_combo(hero, situation, now)
		_apply_opportunistic_defense(hero, situation)
		return

	if _try_start_combo(hero, situation, now):
		_set_state(TacticalState.COMBO)
		_tick_combo(hero, situation, now)
		return

	_run_kit_behavior(hero, situation, now)


## Spend every available point using shared learn rules (AP, max rank, ultimate levels).
func spend_ability_points(hero: Hero) -> void:
	if not NodeSafety.is_alive_node(hero):
		return
	if not CombatTargetValidation.is_enemy_faction(hero):
		return
	if hero.ability_progression == null:
		return
	if hero.ability_points <= 0:
		return

	var spend_guard: int = 0
	var max_spends: int = hero.ability_points
	while hero.ability_points > 0 and spend_guard < max_spends:
		spend_guard += 1
		if not NodeSafety.is_alive_node(hero):
			return
		var learned_ability: bool = false
		for ability_id: StringName in ABILITY_UPGRADE_PRIORITY:
			if hero.try_learn_ability(ability_id, false):
				learned_ability = true
				break
		if not learned_ability:
			break


## Count hostile player military near the hero; optionally include neutrals while creeping.
func count_nearby_hostiles(hero: Hero, include_neutrals: bool = false) -> int:
	if not NodeSafety.is_alive_node(hero):
		return 0
	var tree: SceneTree = hero.get_tree()
	if tree == null:
		return 0

	var hostiles: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		hero.global_position,
		EnemyArmyCommand.HERO_AOE_CHECK_RANGE
	)
	hostiles = NodeSafety.clean_node_array(hostiles)
	var count: int = hostiles.size()
	if not include_neutrals:
		return count

	for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(
		tree,
		CombatTargetValidation.NEUTRAL_CREEP_GROUP
	):
		if not NodeSafety.is_alive_node(node_variant) or not node_variant is Node3D:
			continue
		if not CombatTargetValidation.is_neutral_creep(node_variant):
			continue
		if CombatTargetValidation.get_target_current_health(node_variant) <= 0:
			continue
		if (
			_horizontal_distance(hero.global_position, (node_variant as Node3D).global_position)
			> EnemyArmyCommand.HERO_AOE_CHECK_RANGE
		):
			continue
		count += 1
	return count


func _build_situation(hero: Hero, context: Dictionary) -> Dictionary:
	var tree: SceneTree = hero.get_tree()
	var health_ratio: float = float(context.get("health_ratio", EnemyArmyCommand.get_health_ratio(hero)))
	var nearby_enemies: int = int(context.get("nearby_enemy_count", -1))
	var creeping_hint: bool = VariantUtils.to_bool(context.get("creeping", false))
	if nearby_enemies < 0:
		nearby_enemies = count_nearby_hostiles(hero, creeping_hint)
	var nearby_allies: int = _count_allied_military_near(hero, 12.0)
	var enemy_strength: float = float(nearby_enemies)
	var ally_strength: float = float(maxi(nearby_allies, 1))
	var outnumbered: bool = enemy_strength > ally_strength * (1.0 / OUTNUMBERED_RATIO) * 0.35 and nearby_enemies >= 3
	if nearby_enemies >= nearby_allies + 3 and health_ratio < 0.7:
		outnumbered = true

	var military_ai_v2: bool = VariantUtils.to_bool(context.get("military_ai_v2", false))
	var army_mission: String = str(context.get("army_mission", ""))
	var army_state: String = str(context.get("army_state", ""))
	if army_mission.is_empty() and army_state != "":
		army_mission = army_state

	var army_center: Vector3 = context.get("squad_center", Vector3.ZERO) as Vector3
	if army_center == Vector3.ZERO:
		var army_units: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(tree)
		army_center = EnemyArmyCommand.compute_army_center(army_units)
	var distance_to_army: float = 0.0
	if army_center != Vector3.ZERO:
		distance_to_army = _horizontal_distance(hero.global_position, army_center)

	var rally: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	var distance_to_base: float = (
		_horizontal_distance(hero.global_position, rally) if rally != Vector3.ZERO else 0.0
	)

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	var defend_base: bool = (
		VariantUtils.to_bool(context.get("defend_base", false))
		or EnemyArmyCommand.is_emergency_defense_active()
		or army_mode in [EnemyArmyCommand.ArmyMode.DEFENDING, EnemyArmyCommand.ArmyMode.INTERCEPTING]
		or army_mission == "DEFEND"
		or army_state == "DEFEND"
	)
	var creeping: bool = (
		creeping_hint
		or army_mode == EnemyArmyCommand.ArmyMode.CREEPING
		or EnemyUnitMission.get_main_army_mission() == EnemyUnitMission.Mission.CREEP
		or army_mission == "CREEP"
		or army_state == "CREEP"
	)
	var attacking: bool = (
		VariantUtils.to_bool(context.get("attacking", false))
		or army_mode == EnemyArmyCommand.ArmyMode.ATTACKING
		or army_mission == "ATTACK"
		or army_state == "ATTACK"
	)
	var retreating: bool = (
		VariantUtils.to_bool(context.get("retreating", false))
		or army_mission == "RETREAT"
		or army_state == "RETREAT"
		or army_mode == EnemyArmyCommand.ArmyMode.RETREATING
		or health_ratio < LOW_HP_RATIO
	)
	var role_anchor: Vector3 = context.get("role_anchor", Vector3.ZERO) as Vector3
	if role_anchor == Vector3.ZERO and army_center != Vector3.ZERO:
		role_anchor = _default_role_anchor(hero, army_center, context)

	return {
		"health_ratio": health_ratio,
		"mana_ratio": float(hero.current_mana) / float(maxi(hero.max_mana, 1)),
		"nearby_enemy_count": nearby_enemies,
		"nearby_ally_count": nearby_allies,
		"outnumbered": outnumbered,
		"army_center": army_center,
		"distance_to_army": distance_to_army,
		"distance_to_base": distance_to_base,
		"rally": rally,
		"role_anchor": role_anchor,
		"retreating": retreating,
		"defend_base": defend_base,
		"creeping": creeping,
		"attacking": attacking,
		"military_ai_v2": military_ai_v2,
		"army_mission": army_mission,
		"army_state": army_state,
		"aoe_needed": int(context.get("aoe_needed", EnemyArmyCommand.HERO_AOE_PLAYER_COUNT)),
		"defensive_hp_ratio": float(
			context.get("defensive_hp_ratio", EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO)
		),
		"power_strike_range": float(context.get("power_strike_range", 14.0)),
		"execute_range": float(context.get("execute_range", 14.0)),
		"kit_id": hero.get_hero_kit_id(),
		"level": hero.level,
		"combo_abort_reason": "",
		"mission_destination": context.get("mission_destination", Vector3.ZERO),
		"mission_target": context.get("mission_target"),
		"hero_follow_spacing": float(context.get("hero_follow_spacing", 2.4)),
	}


func _default_role_anchor(hero: Hero, army_center: Vector3, context: Dictionary) -> Vector3:
	var destination: Vector3 = context.get("mission_destination", Vector3.ZERO) as Vector3
	var mission_target: Node3D = context.get("mission_target") as Node3D
	var forward: Vector3 = Vector3.ZERO
	if NodeSafety.is_alive_node(mission_target):
		forward = mission_target.global_position - army_center
	elif destination != Vector3.ZERO:
		forward = destination - army_center
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0.0, 0.0, 1.0)
	else:
		forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var spacing: float = float(context.get("hero_follow_spacing", 2.4))
	var local_offset: Vector3 = UnitFormationRole.hero_follow_offset(
		UnitFormationRole.get_role(hero),
		spacing
	)
	return Vector3(
		army_center.x + right.x * local_offset.x + forward.x * local_offset.z,
		army_center.y,
		army_center.z + right.z * local_offset.x + forward.z * local_offset.z
	)


func _update_tactical_state(hero: Hero, situation: Dictionary) -> void:
	var health_ratio: float = float(situation.get("health_ratio", 1.0))
	var kit_id: StringName = StringName(str(situation.get("kit_id", "")))
	var desired: TacticalState = TacticalState.FOLLOW_ARMY
	var retreating_mission: bool = _is_retreat_mission(situation)

	if VariantUtils.to_bool(situation.get("defend_base", false)):
		desired = TacticalState.DEFEND_BASE
	elif retreating_mission or health_ratio <= CRITICAL_HP_RATIO or (
		VariantUtils.to_bool(situation.get("outnumbered", false)) and health_ratio < 0.55
	):
		desired = TacticalState.ESCAPE if not retreating_mission else TacticalState.ESCAPE
		_debug_log_throttled(
			"retreat",
			"Hero retreat triggered (hp=%.2f outnumbered=%s mission=%s)"
			% [
				health_ratio,
				str(situation.get("outnumbered", false)),
				str(situation.get("army_mission", "")),
			]
		)
	elif float(situation.get("distance_to_army", 0.0)) > EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY:
		desired = TacticalState.RETURN_TO_ARMY
	elif _planner().is_active():
		desired = TacticalState.COMBO
	elif kit_id == HeroCatalog.KIT_RANGER and _ranger_should_kite(hero, situation):
		desired = TacticalState.KITE
	elif kit_id == HeroCatalog.KIT_PALADIN and _paladin_should_protect(hero, situation):
		desired = TacticalState.PROTECT_BACKLINE
	elif kit_id == HeroCatalog.KIT_SHADOW_ASSASSIN and int(situation.get("nearby_enemy_count", 0)) > 0:
		## Assassin only commits to engage/combo under valid attack/defend pressure - never solo opens.
		if _assassin_may_engage(situation) and health_ratio > 0.45 and not VariantUtils.to_bool(situation.get("outnumbered", false)):
			desired = TacticalState.POKE if hero.level < 6 else TacticalState.ENGAGE
		else:
			desired = TacticalState.REPOSITION
	elif int(situation.get("nearby_enemy_count", 0)) > 0:
		desired = TacticalState.ENGAGE
	elif VariantUtils.to_bool(situation.get("creeping", false)):
		## Stay with the creep squad even when briefly between camp pulls.
		desired = TacticalState.FOLLOW_ARMY
	else:
		desired = TacticalState.FOLLOW_ARMY

	_set_state(desired)


func _is_retreat_mission(situation: Dictionary) -> bool:
	return (
		str(situation.get("army_mission", "")) == "RETREAT"
		or str(situation.get("army_state", "")) == "RETREAT"
	)


func _assassin_may_engage(situation: Dictionary) -> bool:
	## Does not independently start attacks - only engage under army ATTACK/DEFEND.
	if VariantUtils.to_bool(situation.get("attacking", false)):
		return true
	if VariantUtils.to_bool(situation.get("defend_base", false)):
		return true
	## While creeping, poke is fine but full engage/combo is not an independent open.
	return false


func _set_state(state: TacticalState) -> void:
	if _tactical_state == state:
		return
	_tactical_state = state
	_debug_log_throttled("state", "Hero tactical state: %s" % get_tactical_state_name(state))


func _should_abort_combo(situation: Dictionary) -> bool:
	if not _planner().is_active():
		return false
	if VariantUtils.to_bool(situation.get("defend_base", false)):
		situation["combo_abort_reason"] = "base defense"
		return true
	if _is_retreat_mission(situation) or VariantUtils.to_bool(situation.get("retreating", false)):
		situation["combo_abort_reason"] = "retreat"
		return true
	if float(situation.get("health_ratio", 1.0)) <= CRITICAL_HP_RATIO:
		situation["combo_abort_reason"] = "low health"
		return true
	if VariantUtils.to_bool(situation.get("outnumbered", false)) and float(situation.get("health_ratio", 1.0)) < 0.5:
		situation["combo_abort_reason"] = "outnumbered"
		return true
	if float(situation.get("mana_ratio", 1.0)) < 0.08:
		situation["combo_abort_reason"] = "out of mana"
		return true
	if float(situation.get("distance_to_army", 0.0)) > ASSASSIN_SQUAD_CHASE_LEASH * 1.25:
		situation["combo_abort_reason"] = "too far from squad"
		return true
	return false


func _resolve_focus_target(hero: Hero, situation: Dictionary, now: float) -> Node3D:
	var sticky: Node3D = _resolve_focus_node()
	if (
		NodeSafety.is_alive_node(sticky)
		and CombatTargetValidation.is_attack_target_for_attacker(hero, sticky)
		and not StealthService.is_combat_hidden(sticky)
		and (now - _focus_acquired_at) < FOCUS_STICK_SECONDS
	):
		var stick_dist: float = CombatTargetValidation.get_horizontal_attack_distance(hero, sticky)
		if stick_dist <= HERO_PRIORITY_RANGE * 1.15:
			# Keep sticky target unless a much higher-priority option appears.
			var upgrade: Node3D = _find_priority_target(hero, situation, true)
			if upgrade == null or upgrade == sticky:
				return sticky
			if _target_priority_score(hero, upgrade, situation) + 25.0 < _target_priority_score(
				hero, sticky, situation
			):
				_set_focus_target(upgrade, now)
				return upgrade
			return sticky

	var chosen: Node3D = _find_priority_target(hero, situation, false)
	if NodeSafety.is_alive_node(chosen):
		_set_focus_target(chosen, now)
	else:
		_clear_focus_target()
	return chosen


func _set_focus_target(target: Node3D, now: float) -> void:
	_focus_target_handle = EntityHandle.from_node(target)
	_focus_target_id = target.get_instance_id() if NodeSafety.is_alive_node(target) else 0
	_focus_acquired_at = now


func _clear_focus_target() -> void:
	_focus_target_id = 0
	_focus_target_handle = EntityHandle.empty()


func _resolve_focus_node() -> Node3D:
	if _focus_target_handle != null and not _focus_target_handle.is_empty():
		var via_handle: Node = _focus_target_handle.resolve()
		if via_handle is Node3D:
			_focus_target_id = via_handle.get_instance_id()
			return via_handle as Node3D
		_clear_focus_target()
		return null
	return _get_node_by_id(_focus_target_id)


## Lower score = higher priority (matches CombatTargetValidation style).
func _target_priority_score(hero: Hero, target: Node3D, situation: Dictionary) -> float:
	if not NodeSafety.is_alive_node(target):
		return 9999.0

	var dist: float = CombatTargetValidation.get_horizontal_attack_distance(hero, target)
	var hp_ratio: float = EnemyArmyCommand.get_health_ratio(target)
	var kit_id: StringName = StringName(str(situation.get("kit_id", "")))
	var score: float = dist
	var aggression_active: bool = EnemyAggression.is_aggression_mode_active()

	if target is Hero:
		score -= 400.0
		if hp_ratio <= 0.45:
			score -= 120.0
		# Assassin prefers fragile ranged heroes.
		if kit_id == HeroCatalog.KIT_SHADOW_ASSASSIN:
			var enemy_kit: StringName = (target as Hero).get_hero_kit_id()
			if enemy_kit == HeroCatalog.KIT_RANGER:
				score -= 80.0
		## During lethal push, do not chase heroes away from the Town Hall.
		if aggression_active and EnemyAggression.should_prefer_town_hall_focus():
			score += 350.0
		return score

	if target is Building:
		# Avoid buildings while dangerous units are actively attacking the hero.
		if (
			int(situation.get("nearby_enemy_count", 0)) > 0
			and _is_under_unit_pressure(hero)
			and not aggression_active
		):
			return 9000.0
		if aggression_active:
			if target is CommandCenter:
				score -= 520.0 if kit_id != HeroCatalog.KIT_SHADOW_ASSASSIN else 420.0
			elif target is Barracks or target is HeroAltar:
				score -= 360.0
			elif kit_id == HeroCatalog.KIT_PALADIN:
				## Paladin fronts siege - keep priority on buildings.
				score -= 180.0
			else:
				score -= 120.0
			return score
		if VariantUtils.to_bool(situation.get("fight_is_safe", false)):
			score += 200.0
		else:
			score += 500.0
		return score

	if target is Worker:
		if aggression_active and kit_id == HeroCatalog.KIT_SHADOW_ASSASSIN:
			## Assassin dives exposed workers before/alongside Town Hall pressure.
			score -= 220.0
			return score
		if VariantUtils.to_bool(situation.get("allow_worker_harass", false)):
			score += 80.0
		else:
			score += 600.0
		return score

	## Neutral camps: keep hero in XP range and focus dangerous creeps.
	if CombatTargetValidation.is_neutral_creep(target):
		if aggression_active:
			return 8000.0
		var creep_damage: int = 8
		if "attack_damage" in target:
			creep_damage = int(target.get("attack_damage"))
		score -= float(creep_damage) * 8.0
		if hp_ratio <= 0.35:
			score -= 40.0
		return score

	var role: UnitFormationRole.Role = UnitFormationRole.get_role(target)
	if UnitFormationRole.is_ranged_role(role):
		score -= 180.0
	elif UnitFormationRole.is_siege_role(role):
		score -= 160.0
	elif UnitFormationRole.is_melee_role(role):
		score -= 40.0
		# Paladin prioritizes melee diving the backline.
		if kit_id == HeroCatalog.KIT_PALADIN and _is_near_allied_ranged(hero, target):
			score -= 90.0

	if hp_ratio <= 0.35:
		score -= 50.0

	## Ranger keeps max range while army sieges - deprioritize diving melee packs.
	if aggression_active and kit_id == HeroCatalog.KIT_RANGER:
		if UnitFormationRole.is_melee_role(role):
			score += 120.0

	return score


func _find_priority_target(
	hero: Hero, situation: Dictionary, _prefer_upgrade: bool
) -> Node3D:
	var tree: SceneTree = hero.get_tree()
	if tree == null:
		return null

	var best: Node3D = null
	var best_score: float = INF
	situation["fight_is_safe"] = (
		int(situation.get("nearby_enemy_count", 0)) <= 1
		and float(situation.get("health_ratio", 1.0)) > 0.55
	)
	situation["allow_worker_harass"] = (
		(
			StringName(str(situation.get("kit_id", ""))) == HeroCatalog.KIT_SHADOW_ASSASSIN
			and float(situation.get("health_ratio", 1.0)) > 0.6
			and not VariantUtils.to_bool(situation.get("outnumbered", false))
		)
		or (
			EnemyAggression.is_aggression_mode_active()
			and StringName(str(situation.get("kit_id", ""))) == HeroCatalog.KIT_SHADOW_ASSASSIN
		)
	)

	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(hero):
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if not NodeSafety.is_alive_node(node_variant) or not node_variant is Node3D:
				continue
			var candidate: Node3D = node_variant as Node3D
			if not CombatTargetValidation.is_attack_target_for_attacker(hero, candidate):
				continue
			if StealthService.is_combat_hidden(candidate):
				continue
			var dist: float = CombatTargetValidation.get_horizontal_attack_distance(hero, candidate)
			if dist > HERO_PRIORITY_RANGE:
				continue
			var score: float = _target_priority_score(hero, candidate, situation)
			if score < best_score:
				best_score = score
				best = candidate

	return best


func _try_start_combo(hero: Hero, situation: Dictionary, now: float) -> bool:
	var planner: AIHeroComboPlanner = _planner()
	if planner.is_active():
		return true

	var kit_id: StringName = StringName(str(situation.get("kit_id", "")))
	if kit_id != HeroCatalog.KIT_SHADOW_ASSASSIN:
		return false
	if _tactical_state in [TacticalState.ESCAPE, TacticalState.RETURN_TO_ARMY]:
		return false
	if _is_retreat_mission(situation) or VariantUtils.to_bool(situation.get("retreating", false)):
		return false
	## Combos are attack/defend micro only - never an independent strategic open.
	if not _assassin_may_engage(situation):
		return false
	if VariantUtils.to_bool(situation.get("creeping", false)) and not VariantUtils.to_bool(situation.get("attacking", false)):
		## Avoid wasting ultimate combo resources while farming camps.
		return false
	if float(situation.get("health_ratio", 1.0)) < 0.32:
		return false
	if VariantUtils.to_bool(situation.get("outnumbered", false)) and hero.level < 6:
		return false

	var focus: Node3D = situation.get("focus_target") as Node3D
	if not NodeSafety.is_alive_node(focus):
		return false
	if focus is Building:
		return false

	if not hero.has_method("try_axe_mark"):
		return false

	var q_range: float = hero.get_ability_range(HeroAbilityProgression.ABILITY_Q)
	var dist: float = CombatTargetValidation.get_horizontal_attack_distance(hero, focus)
	if dist > q_range * 1.15 and not (
		hero.has_method("can_use_dash") and VariantUtils.to_bool(hero.call("can_use_dash"))
	):
		return false

	# Do not dive without escape when W is down and pressure is high.
	if (
		hero.has_method("can_use_smoke")
		and not VariantUtils.to_bool(hero.call("can_use_smoke"))
		and int(situation.get("nearby_enemy_count", 0)) >= 4
		and float(situation.get("health_ratio", 1.0)) < 0.55
	):
		return false

	var steps: Array[Dictionary] = _build_assassin_combo_steps(hero, hero.level)
	if steps.is_empty():
		return false

	planner.start(steps, focus, now)
	_debug_log("Hero combo started (%s)" % ("level6+" if hero.level >= 6 else "pre-6"))
	return true


func _build_assassin_combo_steps(assassin: Hero, level: int) -> Array[Dictionary]:
	var q_range: float = assassin.get_ability_range(HeroAbilityProgression.ABILITY_Q)
	var r_range: float = assassin.get_ability_range(HeroAbilityProgression.ABILITY_R)
	var attack_range: float = float(assassin.attack_range)
	var steps: Array[Dictionary] = []

	if level >= 6 and assassin.is_ability_unlocked(HeroAbilityProgression.ABILITY_R):
		# Q → R → AA → E → AA → Q → AA
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_Q, true, q_range, 2.2, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_R, true, r_range, 2.5, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_ATTACK, true, attack_range, 2.5, false))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_E, false, -1.0, 1.5, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_ATTACK, true, attack_range, 2.0, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_Q, true, q_range, 2.0, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_ATTACK, true, attack_range, 2.0, true))
	else:
		# Q → approach/AA → AA → E (W handled as opportunistic escape)
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_Q, true, q_range, 2.2, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_APPROACH, true, attack_range, 2.8, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_ATTACK, true, attack_range, 2.2, false))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_ATTACK, true, attack_range, 2.0, true))
		steps.append(AIHeroComboPlanner.make_step(AIHeroComboPlanner.ACTION_E, false, -1.0, 1.5, true))

	return steps


func _tick_combo(hero: Hero, situation: Dictionary, now: float) -> void:
	var planner: AIHeroComboPlanner = _planner()
	if not planner.is_active():
		return

	var focus: Node3D = situation.get("focus_target") as Node3D
	if not NodeSafety.is_alive_node(focus) or focus.get_instance_id() != planner.get_target_id():
		# Prefer the combo's original target if still alive.
		var combo_target: Node3D = _get_node_by_id(planner.get_target_id())
		if NodeSafety.is_alive_node(combo_target):
			focus = combo_target
			situation["focus_target"] = focus
		else:
			planner.abort("target died")
			_debug_log_throttled("combo_abort", "Hero combo aborted: target died")
			return

	if not hero.has_method("try_axe_mark"):
		planner.abort("not assassin")
		return

	var dist: float = CombatTargetValidation.get_horizontal_attack_distance(hero, focus)
	var result: Dictionary = planner.tick(now, true, dist <= float(hero.attack_range) * 1.05)
	if VariantUtils.to_bool(result.get("aborted", false)):
		_debug_log_throttled(
			"combo_abort",
			"Hero combo aborted: %s" % str(result.get("reason", "unknown"))
		)
		return
	if VariantUtils.to_bool(result.get("done", false)) or not VariantUtils.to_bool(result.get("active", false)):
		return

	var action: StringName = StringName(str(result.get("action", "")))
	var range_required: float = float(result.get("range_required", -1.0))
	var in_action_range: bool = range_required <= 0.0 or dist <= range_required * 1.05

	if VariantUtils.to_bool(result.get("waiting_for_range", false)) or (
		action == AIHeroComboPlanner.ACTION_APPROACH and not in_action_range
	):
		_issue_attack_on_focus(hero, focus)
		return

	var succeeded: bool = false
	match action:
		AIHeroComboPlanner.ACTION_Q:
			# Prefer Q before R when Q is ready.
			succeeded = VariantUtils.to_bool(hero.call("try_axe_mark", focus))
		AIHeroComboPlanner.ACTION_R:
			if VariantUtils.to_bool(hero.call("can_use_axe_mark")) and not AxeMarkBuff.has_mark(focus):
				# Spec: do not R before Q when Q is ready unless kill/escape critical.
				if float(situation.get("health_ratio", 1.0)) > 0.4:
					succeeded = VariantUtils.to_bool(hero.call("try_axe_mark", focus))
					if succeeded:
						planner.mark_step_succeeded(now)
						return
			succeeded = VariantUtils.to_bool(hero.call("try_dash", focus))
		AIHeroComboPlanner.ACTION_E:
			succeeded = VariantUtils.to_bool(hero.call("try_slash"))
		AIHeroComboPlanner.ACTION_ATTACK, AIHeroComboPlanner.ACTION_APPROACH:
			_issue_attack_on_focus(hero, focus)
			succeeded = dist <= float(hero.attack_range) * 1.1
		_:
			succeeded = false

	if succeeded:
		planner.mark_step_succeeded(now)
	elif VariantUtils.to_bool(result.get("optional", false)):
		planner.mark_step_failed(now, "optional unavailable")
	# Mandatory failure waits for timeout inside planner.


func _apply_opportunistic_defense(hero: Hero, situation: Dictionary) -> void:
	var kit_id: StringName = StringName(str(situation.get("kit_id", "")))
	if kit_id == HeroCatalog.KIT_SHADOW_ASSASSIN:
		_assassin_escape_if_needed(hero, situation)
	elif kit_id == HeroCatalog.KIT_PALADIN:
		_paladin_divine_if_needed(hero, situation)
	elif kit_id == HeroCatalog.KIT_RANGER:
		_ranger_escape_tools(hero, situation, _now_seconds())


func _run_kit_behavior(hero: Hero, situation: Dictionary, now: float) -> void:
	var kit_id: StringName = StringName(str(situation.get("kit_id", "")))
	var focus: Node3D = situation.get("focus_target") as Node3D

	if _tactical_state == TacticalState.ESCAPE or _tactical_state == TacticalState.RETURN_TO_ARMY:
		_handle_escape_or_return(hero, situation, now)
		match kit_id:
			HeroCatalog.KIT_SHADOW_ASSASSIN:
				_assassin_escape_if_needed(hero, situation)
			HeroCatalog.KIT_RANGER:
				_ranger_escape_tools(hero, situation, now)
			HeroCatalog.KIT_PALADIN:
				_paladin_divine_if_needed(hero, situation)
		return

	## RETREAT mission: survival / disengage tools only - no offensive opens.
	if _is_retreat_mission(situation):
		_handle_escape_or_return(hero, situation, now)
		match kit_id:
			HeroCatalog.KIT_SHADOW_ASSASSIN:
				_assassin_escape_if_needed(hero, situation)
			HeroCatalog.KIT_RANGER:
				_ranger_escape_tools(hero, situation, now)
			HeroCatalog.KIT_PALADIN:
				_paladin_divine_if_needed(hero, situation)
		return

	if NodeSafety.is_alive_node(focus) and _tactical_state != TacticalState.FOLLOW_ARMY:
		if _focus_within_squad_leash(hero, focus, situation):
			# Avoid attacking buildings under active unit pressure.
			if not (focus is Building and _is_under_unit_pressure(hero)):
				_issue_attack_on_focus(hero, focus)

	match kit_id:
		HeroCatalog.KIT_RANGER:
			_run_ranger(hero, situation, now)
		HeroCatalog.KIT_SHADOW_ASSASSIN:
			_run_assassin(hero, situation, now)
		_:
			_run_paladin(hero, situation, now)

	## Short tactical positioning around the squad role slot (never changes mission).
	_apply_role_positioning(hero, situation, now)


func _focus_within_squad_leash(hero: Hero, focus: Node3D, situation: Dictionary) -> bool:
	if not NodeSafety.is_alive_node(focus):
		return false
	var army_center: Vector3 = situation.get("army_center", Vector3.ZERO)
	if army_center == Vector3.ZERO:
		return true
	var kit_id: StringName = StringName(str(situation.get("kit_id", "")))
	var leash: float = EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY
	if kit_id == HeroCatalog.KIT_PALADIN:
		leash = PALADIN_SQUAD_CHASE_LEASH
	elif kit_id == HeroCatalog.KIT_SHADOW_ASSASSIN:
		leash = ASSASSIN_SQUAD_CHASE_LEASH
	elif kit_id == HeroCatalog.KIT_RANGER:
		## Ranger only chases under valid attack orders; otherwise shoot-in-range only.
		if not VariantUtils.to_bool(situation.get("attacking", false)) and not VariantUtils.to_bool(situation.get("defend_base", false)):
			var attack_range: float = float(hero.attack_range)
			return CombatTargetValidation.get_horizontal_attack_distance(hero, focus) <= attack_range * 1.05
		leash = EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY * 0.85
	return _horizontal_distance(focus.global_position, army_center) <= leash


func _handle_escape_or_return(hero: Hero, situation: Dictionary, now: float) -> void:
	if now - _last_micro_move_at < MICRO_MOVE_COOLDOWN:
		return

	var destination: Vector3 = situation.get("role_anchor", Vector3.ZERO)
	if destination == Vector3.ZERO:
		destination = situation.get("army_center", Vector3.ZERO)
	if destination == Vector3.ZERO:
		destination = situation.get("rally", Vector3.ZERO)
	if destination == Vector3.ZERO:
		return

	_last_micro_move_at = now
	## Under V2 never call command_retreat_hero - it can initiate full-army retreat.
	if VariantUtils.to_bool(situation.get("military_ai_v2", false)):
		_micro_hold_toward(hero, destination, situation)
		return
	EnemyArmyCommand.command_retreat_hero(hero, destination)


func _micro_hold_toward(hero: Hero, destination: Vector3, situation: Dictionary) -> void:
	if not NodeSafety.is_alive_node(hero) or destination == Vector3.ZERO:
		return
	var hold_mission: EnemyUnitMission.Mission = _mission_for_situation(situation)
	EnemyArmyCommand.with_authorized_orders(func() -> void:
		EnemyArmyCommand.command_hold_at_rally(
			[hero],
			destination,
			hold_mission
		)
	)


func _mission_for_situation(situation: Dictionary) -> EnemyUnitMission.Mission:
	var mission_name: String = str(situation.get("army_mission", ""))
	match mission_name:
		"CREEP":
			return EnemyUnitMission.Mission.CREEP
		"ATTACK":
			return EnemyUnitMission.Mission.ATTACK
		"DEFEND":
			return EnemyUnitMission.Mission.DEFEND
		"RETREAT":
			return EnemyUnitMission.Mission.RETREAT
		_:
			return EnemyUnitMission.Mission.RALLY


func _apply_role_positioning(hero: Hero, situation: Dictionary, now: float) -> void:
	if not VariantUtils.to_bool(situation.get("military_ai_v2", false)):
		return
	if _tactical_state in [TacticalState.ESCAPE, TacticalState.COMBO, TacticalState.KITE]:
		return
	if now - _last_micro_move_at < MICRO_MOVE_COOLDOWN:
		return

	var anchor: Vector3 = situation.get("role_anchor", Vector3.ZERO)
	if anchor == Vector3.ZERO:
		return
	var distance: float = _horizontal_distance(hero.global_position, anchor)
	if distance <= ROLE_ANCHOR_SETTLE_DISTANCE:
		return

	## During ENGAGE/POKE/PROTECT stay near role slot unless actively connecting a valid focus.
	var focus: Node3D = situation.get("focus_target") as Node3D
	if (
		_tactical_state in [TacticalState.ENGAGE, TacticalState.POKE, TacticalState.PROTECT_BACKLINE, TacticalState.DEFEND_BASE]
		and NodeSafety.is_alive_node(focus)
		and _focus_within_squad_leash(hero, focus, situation)
	):
		var focus_dist: float = CombatTargetValidation.get_horizontal_attack_distance(hero, focus)
		if focus_dist <= float(hero.attack_range) * 1.15:
			return

	_last_micro_move_at = now
	_micro_hold_toward(hero, anchor, situation)


func _issue_attack_on_focus(hero: Hero, focus: Node3D) -> void:
	if not NodeSafety.is_alive_node(hero) or not NodeSafety.is_alive_node(focus):
		return
	if hero.get_attack_target() == focus:
		return
	hero.command_attack(focus)


# ---------------------------------------------------------------------------
# Ranger
# ---------------------------------------------------------------------------


func _ranger_should_kite(hero: Hero, situation: Dictionary) -> bool:
	if float(situation.get("health_ratio", 1.0)) < 0.55 and int(situation.get("nearby_enemy_count", 0)) > 0:
		return true
	if hero.has_method("ai_has_melee_threat_nearby"):
		return VariantUtils.to_bool(hero.call("ai_has_melee_threat_nearby"))
	return false


func _run_ranger(ranger, situation: Dictionary, now: float) -> void:
	if ranger == null:
		return

	var health_ratio: float = float(situation.get("health_ratio", 1.0))
	var retreating: bool = VariantUtils.to_bool(situation.get("retreating", false)) or _tactical_state == TacticalState.ESCAPE
	var nearby: int = int(situation.get("nearby_enemy_count", 0))
	var defensive_hp: float = float(situation.get("defensive_hp_ratio", 0.4))
	var focus: Node3D = situation.get("focus_target") as Node3D

	# Stay behind melee / kite when pressured.
	if _tactical_state == TacticalState.KITE or ranger.ai_has_melee_threat_nearby():
		_ranger_kite_move(ranger, situation, now)

	# R - approach / escape / major fight.
	if ranger.can_use_camouflage():
		var allow_offensive_camo: bool = (
			VariantUtils.to_bool(situation.get("attacking", false))
			or VariantUtils.to_bool(situation.get("defend_base", false))
			or not VariantUtils.to_bool(situation.get("creeping", false))
		)
		if health_ratio < defensive_hp or retreating:
			ranger.try_camouflage()
		elif allow_offensive_camo and nearby >= int(situation.get("aoe_needed", 3)):
			ranger.try_camouflage()
		elif allow_offensive_camo and ranger.ai_has_valuable_hunt_prey_nearby():
			ranger.try_camouflage()
		elif (
			allow_offensive_camo
			and NodeSafety.is_alive_node(focus)
			and focus is Hero
			and health_ratio > 0.45
		):
			ranger.try_camouflage()

	# Q — roll away from melee / AoE pressure; prefer sideways / backline.
	if ranger.can_use_combat_roll():
		if ranger.is_combat_hidden() or ranger.is_camouflage_active():
			if (
				health_ratio < defensive_hp
				or retreating
				or ranger.ai_has_melee_threat_nearby()
				or ranger.ai_should_reposition_while_hunting()
			):
				ranger.try_combat_roll(ranger.ai_resolve_roll_target_while_camouflaged())
		elif health_ratio < defensive_hp or retreating or ranger.ai_has_melee_threat_nearby():
			ranger.try_combat_roll(_resolve_ranger_roll_destination(ranger, situation))

	if ranger.is_camouflage_active():
		ranger.ai_prefer_hunt_movement()

	# W — spaced traps on approach / retreat / defense.
	if ranger.can_use_bear_trap():
		var preserve_charge: bool = (
			ranger.ai_has_melee_threat_nearby()
			and ranger.get_bear_trap_charges() <= 1
		)
		if not preserve_charge and (nearby > 0 or retreating or VariantUtils.to_bool(situation.get("defend_base", false))):
			var reason: String = "approach path"
			if retreating:
				reason = "retreat path"
			elif VariantUtils.to_bool(situation.get("defend_base", false)):
				reason = "base defense"
			var place: Vector3 = _resolve_spaced_trap_position(ranger, situation, retreating)
			if place != Vector3.ZERO:
				if ranger.try_bear_trap(place):
					_last_trap_positions.append(place)
					if _last_trap_positions.size() > 6:
						_last_trap_positions.pop_front()
					_debug_log_throttled("trap", "Ranger trap: %s" % reason)

	# E — frequent bolt on heroes / lines.
	if ranger.can_use_crossbow_bolt():
		if nearby >= 2 or ranger.ai_has_hero_in_bolt_range() or NodeSafety.is_alive_node(focus):
			if NodeSafety.is_alive_node(focus):
				ranger.try_crossbow_bolt(focus)
			else:
				ranger.try_crossbow_bolt()


func _ranger_escape_tools(ranger, situation: Dictionary, now: float) -> void:
	if ranger == null:
		return
	if ranger.can_use_camouflage():
		ranger.try_camouflage()
	if ranger.can_use_combat_roll():
		ranger.try_combat_roll(_resolve_ranger_roll_destination(ranger, situation))
	if ranger.can_use_bear_trap() and VariantUtils.to_bool(situation.get("defend_base", false)):
		var place: Vector3 = _resolve_spaced_trap_position(ranger, situation, true)
		if place != Vector3.ZERO and ranger.try_bear_trap(place):
			_debug_log_throttled("trap", "Ranger trap: emergency defense")
	_ranger_kite_move(ranger, situation, now)


func _ranger_kite_move(ranger, situation: Dictionary, now: float) -> void:
	if now - _last_micro_move_at < MICRO_MOVE_COOLDOWN:
		return
	var army_center: Vector3 = situation.get("role_anchor", Vector3.ZERO)
	if army_center == Vector3.ZERO:
		army_center = situation.get("army_center", Vector3.ZERO)
	var focus: Node3D = situation.get("focus_target") as Node3D
	var destination: Vector3 = army_center
	if destination == Vector3.ZERO:
		destination = situation.get("rally", Vector3.ZERO)
	if destination == Vector3.ZERO and NodeSafety.is_alive_node(focus):
		var away: Vector3 = ranger.global_position - focus.global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			destination = ranger.global_position + away.normalized() * 4.0
	if destination == Vector3.ZERO:
		return

	# Keep attack range when safe - don't chase into melee.
	if NodeSafety.is_alive_node(focus) and not ranger.ai_has_melee_threat_nearby():
		var dist: float = CombatTargetValidation.get_horizontal_attack_distance(ranger, focus)
		if dist <= float(ranger.attack_range) and dist >= float(ranger.attack_range) * 0.55:
			return

	_last_micro_move_at = now
	_micro_hold_toward(ranger, destination, situation)


func _resolve_ranger_roll_destination(ranger, situation: Dictionary) -> Vector3:
	var army_center: Vector3 = situation.get("army_center", Vector3.ZERO)
	if army_center != Vector3.ZERO:
		var to_army: Vector3 = army_center - ranger.global_position
		to_army.y = 0.0
		if to_army.length_squared() > 0.001:
			# Sideways bias toward backline rather than pure reverse.
			var side: Vector3 = Vector3(-to_army.z, 0.0, to_army.x).normalized()
			var back: Vector3 = to_army.normalized()
			return ranger.global_position + (back * 0.65 + side * 0.35).normalized() * RangerStats.COMBAT_ROLL_DISTANCE
	return ranger.ai_resolve_roll_target()


func _resolve_spaced_trap_position(
	ranger, situation: Dictionary, retreating: bool
) -> Vector3:
	var candidate: Vector3 = ranger.ai_resolve_trap_position(retreating)
	if VariantUtils.to_bool(situation.get("defend_base", false)):
		var rally: Vector3 = situation.get("rally", Vector3.ZERO)
		if rally != Vector3.ZERO:
			candidate = (ranger.global_position + rally) * 0.5
			candidate.y = 0.0

	for prior: Vector3 in _last_trap_positions:
		var offset: Vector3 = candidate - prior
		offset.y = 0.0
		if offset.length() < TRAP_MIN_SPACING:
			var nudge: Vector3 = Vector3(TRAP_MIN_SPACING, 0.0, 0.0)
			if offset.length_squared() > 0.001:
				nudge = offset.normalized() * TRAP_MIN_SPACING
			candidate = prior + nudge
			candidate.y = 0.0
			break

	return candidate


# ---------------------------------------------------------------------------
# Shadow Assassin
# ---------------------------------------------------------------------------


func _run_assassin(assassin, situation: Dictionary, now: float) -> void:
	if assassin == null:
		return

	_assassin_escape_if_needed(assassin, situation)

	if assassin.is_combat_hidden():
		# Reposition while smoked; avoid instant re-engage unless kill is safe.
		_assassin_smoke_reposition(assassin, situation, now)
		var focus: Node3D = situation.get("focus_target") as Node3D
		if (
			_assassin_may_engage(situation)
			and NodeSafety.is_alive_node(focus)
			and focus is Hero
			and EnemyArmyCommand.get_health_ratio(focus) <= 0.3
			and float(situation.get("health_ratio", 1.0)) > 0.4
			and _focus_within_squad_leash(assassin, focus, situation)
		):
			_issue_attack_on_focus(assassin, focus)
		return

	var focus_target: Node3D = situation.get("focus_target") as Node3D
	if NodeSafety.is_alive_node(focus_target) and not _focus_within_squad_leash(assassin, focus_target, situation):
		## Return to flank slot instead of wandering after a dive.
		_apply_role_positioning(assassin, situation, now)
		return

	var q_range: float = assassin.get_ability_range(HeroAbilityProgression.ABILITY_Q)

	# Frequent Q poke on reachable priority targets (allowed during creep/attack).
	if assassin.can_use_axe_mark(q_range) and NodeSafety.is_alive_node(focus_target):
		var dist: float = CombatTargetValidation.get_horizontal_attack_distance(assassin, focus_target)
		if dist <= q_range:
			assassin.try_axe_mark(focus_target)
		elif dist <= q_range * 1.3 and _assassin_may_engage(situation) and not VariantUtils.to_bool(situation.get("outnumbered", false)):
			_issue_attack_on_focus(assassin, focus_target)

	# Consume mark with basic attack when marked target is near.
	if NodeSafety.is_alive_node(focus_target) and AxeMarkBuff.has_mark(focus_target):
		_issue_attack_on_focus(assassin, focus_target)

	if assassin.can_use_slash() and int(situation.get("nearby_enemy_count", 0)) >= 2:
		assassin.try_slash()

	# Dash only when follow-up is realistic and army is already committing.
	if (
		_assassin_may_engage(situation)
		and assassin.can_use_dash()
		and NodeSafety.is_alive_node(focus_target)
		and not (focus_target is Building)
		and float(situation.get("health_ratio", 1.0)) > 0.4
		and not VariantUtils.to_bool(situation.get("outnumbered", false))
	):
		var marked_or_low: bool = (
			AxeMarkBuff.has_mark(focus_target)
			or EnemyArmyCommand.get_health_ratio(focus_target) <= 0.4
			or focus_target is Hero
		)
		if marked_or_low:
			assassin.try_dash(focus_target)


func _assassin_escape_if_needed(assassin, situation: Dictionary) -> void:
	if assassin == null or not assassin.can_use_smoke():
		return

	var reason: String = ""
	if float(situation.get("health_ratio", 1.0)) < float(situation.get("defensive_hp_ratio", 0.4)):
		reason = "low HP"
	elif VariantUtils.to_bool(situation.get("retreating", false)) or _tactical_state == TacticalState.ESCAPE:
		reason = "retreat"
	elif VariantUtils.to_bool(situation.get("outnumbered", false)):
		reason = "focused / outnumbered"
	elif (
		int(situation.get("nearby_enemy_count", 0)) >= 3
		and not assassin.can_use_axe_mark()
		and not assassin.can_use_dash()
	):
		reason = "waiting for cooldowns"

	if reason.is_empty():
		return
	if assassin.try_smoke():
		_debug_log_throttled("smoke", "Assassin W escape: %s" % reason)


func _assassin_smoke_reposition(
	assassin, situation: Dictionary, now: float
) -> void:
	if now - _last_micro_move_at < MICRO_MOVE_COOLDOWN:
		return
	var army_center: Vector3 = situation.get("role_anchor", Vector3.ZERO)
	if army_center == Vector3.ZERO:
		army_center = situation.get("army_center", Vector3.ZERO)
	if army_center == Vector3.ZERO:
		army_center = situation.get("rally", Vector3.ZERO)
	if army_center == Vector3.ZERO:
		return
	_last_micro_move_at = now
	if VariantUtils.to_bool(situation.get("military_ai_v2", false)):
		_micro_hold_toward(assassin, army_center, situation)
		return
	EnemyArmyCommand.command_retreat_hero(assassin, army_center)


# ---------------------------------------------------------------------------
# Paladin
# ---------------------------------------------------------------------------


func _paladin_should_protect(hero: Hero, situation: Dictionary) -> bool:
	return int(situation.get("nearby_enemy_count", 0)) > 0 and _allied_ranged_threatened(hero)


func _run_paladin(hero: Hero, situation: Dictionary, _now: float) -> void:
	_paladin_divine_if_needed(hero, situation)

	var focus: Node3D = situation.get("focus_target") as Node3D
	var power_range: float = float(situation.get("power_strike_range", 14.0))
	var execute_range: float = float(situation.get("execute_range", 14.0))
	var nearby: int = int(situation.get("nearby_enemy_count", 0))
	var aoe_needed: int = int(situation.get("aoe_needed", 3))
	var creeping: bool = VariantUtils.to_bool(situation.get("creeping", false)) and not VariantUtils.to_bool(situation.get("attacking", false))

	# R - only valid execute-threshold targets; prefer heroes.
	## During CREEP avoid wasting ultimate on random camp fodder.
	if hero.has_method("can_use_execute") and VariantUtils.to_bool(hero.call("can_use_execute", execute_range)):
		var allow_execute: bool = true
		if creeping:
			allow_execute = NodeSafety.is_alive_node(focus) and focus is Hero
		if allow_execute:
			if NodeSafety.is_alive_node(focus) and focus is Hero:
				hero.call("try_execute", focus)
			elif not creeping:
				hero.call("try_execute")

	# E - heroes / dangerous melee / sieges / finishes.
	if hero.has_method("can_use_power_strike") and VariantUtils.to_bool(hero.call("can_use_power_strike", power_range)):
		if NodeSafety.is_alive_node(focus):
			hero.call("try_power_strike", focus)
		else:
			hero.call("try_power_strike")

	# Q - groups / choke / diving melee near ranged.
	if hero.has_method("can_use_ground_slam") and VariantUtils.to_bool(hero.call("can_use_ground_slam")):
		var slam_ok: bool = nearby >= aoe_needed
		if not slam_ok and nearby >= 2 and _allied_ranged_threatened(hero):
			slam_ok = true
		if not slam_ok and NodeSafety.is_alive_node(focus) and focus is Hero and nearby >= 2:
			slam_ok = true
		## During DEFEND, slam packs threatening the backline even at 2.
		if not slam_ok and VariantUtils.to_bool(situation.get("defend_base", false)) and nearby >= 2:
			slam_ok = true
		if slam_ok:
			hero.call("try_ground_slam")


func _paladin_divine_if_needed(hero: Hero, situation: Dictionary) -> void:
	if hero == null or not hero.has_method("can_use_divine_protection"):
		return
	if not VariantUtils.to_bool(hero.call("can_use_divine_protection")):
		return

	var health_ratio: float = float(situation.get("health_ratio", 1.0))
	var defensive_hp: float = float(situation.get("defensive_hp_ratio", 0.4))
	var reason: String = ""

	if health_ratio < defensive_hp:
		reason = "low HP / burst"
	elif VariantUtils.to_bool(situation.get("retreating", false)) and health_ratio < 0.55:
		reason = "retreat"
	elif int(situation.get("nearby_enemy_count", 0)) >= 3 and health_ratio < 0.7:
		reason = "holding frontline"
	elif _tactical_state == TacticalState.PROTECT_BACKLINE and health_ratio < 0.75:
		reason = "protecting backline"

	# Do not waste at full HP with no threat.
	if reason.is_empty():
		return
	if health_ratio > 0.92 and int(situation.get("nearby_enemy_count", 0)) <= 0:
		return

	if VariantUtils.to_bool(hero.call("try_divine_protection")):
		_debug_log_throttled("divine", "Paladin W defensive: %s" % reason)


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


func _is_under_unit_pressure(hero: Hero) -> bool:
	var tree: SceneTree = hero.get_tree()
	if tree == null:
		return false
	var count: int = 0
	for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(hero):
		for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if node_variant is Building or node_variant is Worker:
				continue
			if not CombatTargetValidation.are_hostile(hero, node_variant):
				continue
			if CombatTargetValidation.get_horizontal_attack_distance(hero, node_variant as Node3D) > SAFE_BUILDING_THREAT_RADIUS:
				continue
			count += 1
			if count >= 2:
				return true
	return false


func _is_near_allied_ranged(hero: Hero, enemy: Node3D) -> bool:
	var tree: SceneTree = hero.get_tree()
	if tree == null:
		return false
	for unit: Variant in EnemyArmyCommand.collect_living_non_hero_combat_units(tree):
		if not NodeSafety.is_alive_node(unit):
			continue
		var role: UnitFormationRole.Role = UnitFormationRole.get_role(unit as Node)
		if not UnitFormationRole.is_ranged_role(role) and not UnitFormationRole.is_siege_role(role):
			continue
		if _horizontal_distance((unit as Node3D).global_position, enemy.global_position) <= 8.0:
			return true
	return false


func _allied_ranged_threatened(hero: Hero) -> bool:
	var tree: SceneTree = hero.get_tree()
	if tree == null:
		return false
	for unit: Variant in EnemyArmyCommand.collect_living_non_hero_combat_units(tree):
		if not NodeSafety.is_alive_node(unit):
			continue
		var role: UnitFormationRole.Role = UnitFormationRole.get_role(unit as Node)
		if not UnitFormationRole.is_ranged_role(role) and not UnitFormationRole.is_siege_role(role):
			continue
		var ranged: Node3D = unit as Node3D
		for group_name: StringName in CombatTargetValidation.get_hostile_search_groups(hero):
			for node_variant: Variant in CombatTargetValidation.get_cached_group_nodes(tree, group_name):
				if not NodeSafety.is_alive_node(node_variant) or node_variant is Building:
					continue
				if not CombatTargetValidation.are_hostile(hero, node_variant):
					continue
				if _horizontal_distance(ranged.global_position, (node_variant as Node3D).global_position) <= 6.0:
					return true
	return false


func _count_allied_military_near(hero: Hero, radius: float) -> int:
	var tree: SceneTree = hero.get_tree()
	if tree == null:
		return 0
	var count: int = 0
	for unit: Variant in EnemyArmyCommand.collect_living_non_hero_combat_units(tree):
		if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
			continue
		if _horizontal_distance(hero.global_position, (unit as Node3D).global_position) <= radius:
			count += 1
	return count


func _get_node_by_id(instance_id: int) -> Node3D:
	if instance_id == 0:
		return null
	if EntityRegistry != null:
		var via_registry: Node = EntityRegistry.resolve_id(instance_id)
		if via_registry is Node3D:
			return via_registry as Node3D
	var node: Object = instance_from_id(instance_id)
	if node == null or not is_instance_valid(node) or not node is Node3D:
		return null
	if node is Node and not (node as Node).is_inside_tree():
		return null
	return node as Node3D


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var delta: Vector3 = a - b
	delta.y = 0.0
	return delta.length()


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _debug_log(message: String) -> void:
	if not OS.is_debug_build():
		return
	print("[AIHero] %s" % message)


func _debug_log_throttled(key: String, message: String) -> void:
	if not OS.is_debug_build():
		return
	match key:
		"state":
			if message == _last_debug_state:
				return
			_last_debug_state = message
		"retreat":
			if message == _last_debug_retreat:
				return
			_last_debug_retreat = message
		"trap":
			if message == _last_debug_trap:
				return
			_last_debug_trap = message
		"smoke":
			if message == _last_debug_smoke:
				return
			_last_debug_smoke = message
		"divine":
			if message == _last_debug_divine:
				return
			_last_debug_divine = message
		"combo_abort":
			pass
		_:
			pass
	print("[AIHero] %s" % message)
