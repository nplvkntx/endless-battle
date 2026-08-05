class_name EnemyAggression
extends RefCounted

## Recognizes player weakness / greed and drives AGGRESSION MODE:
## lethal scoring, greed confidence, hysteresis, counter-pressure, retreat.

enum Confidence {
	VERY_LOW,
	LOW,
	MEDIUM,
	HIGH,
	VERY_HIGH,
}

const EVAL_INTERVAL_SECONDS := 2.5
const COMMIT_MIN_SECONDS := 22.0
const EXIT_COOLDOWN_SECONDS := 12.0
const RETREAT_COOLDOWN_SECONDS := 18.0
const PLAYER_ARMY_MEMORY_SECONDS := 50.0
const HERO_RUSH_MEMORY_SECONDS := 40.0
const HERO_RUSH_REPEAT_COUNT := 2

const SCOUT_RANGE := 55.0
const BASE_DEFENSE_RADIUS := 32.0
const HERO_AWAY_DISTANCE := 30.0
const WORKER_EXPOSE_RADIUS := 22.0
const COUNTER_DEFEND_MIN_UNITS := 3
const COUNTER_DEFEND_MAX_UNITS := 5
const MIN_HOME_DEFENSE_UNITS := 2
const AGGRESSION_MIN_ARMY_UNITS := 6
const AGGRESSION_COMMIT_ARMY_RATIO := 0.85

## Enter / stay / exit hysteresis thresholds (combined opportunity 0–100).
const ENTER_HIGH_THRESHOLD := 55.0
const STAY_MEDIUM_THRESHOLD := 32.0
const FINISHING_LETHAL_THRESHOLD := 72.0
const RETREAT_LETHAL_THRESHOLD := 22.0
const RETREAT_STRENGTH_RATIO := 0.55

## Greed signal weights (sum toward 0–100).
const GREED_HERO_ALONE := 22.0
const GREED_HERO_SMALL_ARMY := 16.0
const GREED_LOW_VISIBLE := 14.0
const GREED_ECON_SKIP_ARMY := 18.0
const GREED_CREEPING_UNDEFENDED := 12.0
const GREED_HERO_ONLY_ATTACK := 20.0
const GREED_IGNORES_DEFENSE := 14.0
const GREED_FOCUS_TH_IGNORE_ARMY := 12.0
const GREED_RECENT_ARMY_LOSS := 16.0
const GREED_EXPOSED_WORKERS := 10.0
const GREED_EXPANSION := 14.0

static var _eval_timer: float = 0.0
static var _aggression_active: bool = false
static var _confidence: Confidence = Confidence.VERY_LOW
static var _lethal_score: float = 0.0
static var _greed_score: float = 0.0
static var _opportunity_score: float = 0.0
static var _last_reasons: Array[StringName] = []
static var _commit_timer: float = 0.0
static var _exit_cooldown: float = 0.0
static var _retreat_cooldown: float = 0.0
static var _counter_pressure_active: bool = false
static var _last_eval: Dictionary = {}

static var _peak_player_army_power: int = 0
static var _peak_player_army_msec: int = 0
static var _last_known_player_army_power: int = 0
static var _hero_rush_events: Array[int] = []
static var _player_ignored_defense_streak: int = 0


static func reset_match_state() -> void:
	_eval_timer = 0.0
	_aggression_active = false
	_confidence = Confidence.VERY_LOW
	_lethal_score = 0.0
	_greed_score = 0.0
	_opportunity_score = 0.0
	_last_reasons.clear()
	_commit_timer = 0.0
	_exit_cooldown = 0.0
	_retreat_cooldown = 0.0
	_counter_pressure_active = false
	_last_eval.clear()
	_peak_player_army_power = 0
	_peak_player_army_msec = 0
	_last_known_player_army_power = 0
	_hero_rush_events.clear()
	_player_ignored_defense_streak = 0


static func is_aggression_mode_active() -> bool:
	return _aggression_active


static func is_counter_pressure_active() -> bool:
	return _counter_pressure_active and _aggression_active


static func get_confidence() -> Confidence:
	return _confidence


static func get_lethal_score() -> float:
	return _lethal_score


static func get_greed_score() -> float:
	return _greed_score


static func get_opportunity_score() -> float:
	return _opportunity_score


static func get_last_eval() -> Dictionary:
	return _last_eval.duplicate(true)


static func should_suspend_creeping() -> bool:
	return _aggression_active and _confidence >= Confidence.HIGH


static func should_boost_attack_desire() -> bool:
	return _aggression_active or _confidence >= Confidence.MEDIUM


static func should_use_aggressive_strength_gate() -> bool:
	return _aggression_active and _confidence >= Confidence.HIGH


static func should_bypass_wave_delay() -> bool:
	return (
		_aggression_active
		or _confidence >= Confidence.HIGH
		or _counter_pressure_active
	)


static func should_prefer_town_hall_focus() -> bool:
	return _aggression_active and _confidence >= Confidence.HIGH


static func should_leave_minimal_home_defense() -> bool:
	return _aggression_active and (
		_confidence >= Confidence.HIGH or _counter_pressure_active
	)


static func get_home_defense_budget(total_combat: int) -> int:
	if not should_leave_minimal_home_defense():
		return 0
	if _counter_pressure_active:
		return clampi(COUNTER_DEFEND_MIN_UNITS, MIN_HOME_DEFENSE_UNITS, COUNTER_DEFEND_MAX_UNITS)
	if total_combat <= AGGRESSION_MIN_ARMY_UNITS:
		return MIN_HOME_DEFENSE_UNITS
	return clampi(int(float(total_combat) * 0.12), MIN_HOME_DEFENSE_UNITS, COUNTER_DEFEND_MAX_UNITS)


static func get_commit_army_ratio() -> float:
	if not _aggression_active:
		return 0.7
	match _confidence:
		Confidence.VERY_HIGH:
			return 0.95
		Confidence.HIGH:
			return AGGRESSION_COMMIT_ARMY_RATIO
		Confidence.MEDIUM:
			return 0.7
		_:
			return 0.55


static func is_on_retreat_cooldown() -> bool:
	return _retreat_cooldown > 0.0


static func update(tree: SceneTree, delta: float) -> void:
	if _exit_cooldown > 0.0:
		_exit_cooldown = maxf(0.0, _exit_cooldown - delta)
	if _retreat_cooldown > 0.0:
		_retreat_cooldown = maxf(0.0, _retreat_cooldown - delta)
	if _aggression_active:
		_commit_timer += delta

	_eval_timer += delta
	if _eval_timer < EVAL_INTERVAL_SECONDS:
		return
	_eval_timer = 0.0

	if tree == null:
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	var lethal: Dictionary = compute_lethal_score(tree, rally_position)
	var greed: Dictionary = compute_greed_score(tree, rally_position)
	_lethal_score = float(lethal.get("score", 0.0))
	_greed_score = float(greed.get("score", 0.0))
	_last_reasons = []
	for reason_variant: Variant in greed.get("reasons", []):
		_last_reasons.append(reason_variant as StringName)
	for reason_variant: Variant in lethal.get("reasons", []):
		var reason: StringName = reason_variant as StringName
		if not _last_reasons.has(reason):
			_last_reasons.append(reason)

	## Opportunity blends lethal finish potential with greed punish confidence.
	_opportunity_score = clampf(
		_lethal_score * 0.62 + _greed_score * 0.48,
		0.0,
		100.0
	)
	_confidence = _score_to_confidence(_opportunity_score)
	_counter_pressure_active = VariantUtils.to_bool(greed.get("counter_pressure", false)) and (
		_opportunity_score >= STAY_MEDIUM_THRESHOLD
	)

	_last_eval = {
		"lethal_score": _lethal_score,
		"greed_score": _greed_score,
		"opportunity_score": _opportunity_score,
		"confidence": confidence_name(_confidence),
		"aggression_active": _aggression_active,
		"counter_pressure": _counter_pressure_active,
		"reasons": _last_reasons.duplicate(),
		"lethal": lethal,
		"greed": greed,
	}

	_update_aggression_state(tree, lethal)
	_maybe_escalate_finishing(tree)
	_publish_military_intents_v2()


## First-class MilitaryIntent publisher under V2 (no unit orders).
static func _publish_military_intents_v2() -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		return
	var state: AIPlayerState = EnemyArmyCommand.get_bound_ai_player_state()
	if state == null:
		return

	if should_suspend_creeping():
		state.publish_intent(
			MilitaryIntent.make_suspend_creep(&"aggression_suspend", &"aggression")
		)

	if EnemyArmyCommand.is_finishing_mode_active():
		state.publish_intent(
			MilitaryIntent.make_finish(&"finishing_mode", 95.0, &"aggression")
		)
		return

	if _lethal_score >= MilitaryAIConfig.V2_ATTACK_LETHAL_SCORE_THRESHOLD:
		state.publish_intent(
			MilitaryIntent.make_attack(&"lethal_score", _lethal_score, &"aggression")
		)
		return

	if _aggression_active:
		state.publish_intent(
			MilitaryIntent.make_attack(&"aggression_mode", _opportunity_score, &"aggression")
		)
		return

	if _greed_score >= MilitaryAIConfig.V2_CREEP_GREED_INTERRUPT_SCORE:
		state.publish_intent(
			MilitaryIntent.make_attack(&"greed_window", _greed_score, &"aggression")
		)


static func compute_lethal_score(tree: SceneTree, rally_position: Vector3 = Vector3.ZERO) -> Dictionary:
	if tree == null:
		return {"score": 0.0, "reasons": []}

	if rally_position == Vector3.ZERO:
		rally_position = EnemyArmyCommand.resolve_enemy_rally_position(tree)

	var reasons: Array[StringName] = []
	var score: float = 0.0

	var ai_units: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	var ai_power: int = EnemyArmyCommand.estimate_military_power(ai_units)
	var ai_count: int = ai_units.size()
	var ai_hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	var ai_hero_hp: float = (
		EnemyArmyCommand.get_health_ratio(ai_hero) if ai_hero != null else 0.0
	)
	var ai_hero_level: int = ai_hero.level if ai_hero != null else 0
	var ai_mana_ratio: float = 0.0
	var ai_abilities_ready: int = 0
	if ai_hero != null:
		ai_mana_ratio = float(ai_hero.current_mana) / float(maxi(ai_hero.max_mana, 1))
		ai_abilities_ready = _count_ready_abilities(ai_hero)

	var player_visible: Array = _collect_visible_player_military(tree, rally_position)
	var visible_power: int = EnemyArmyCommand.estimate_military_power(player_visible)
	var composition: Dictionary = _count_player_composition(player_visible)
	var visible_count: int = int(composition.get("total", 0))
	var melee_count: int = int(composition.get("melee", 0))
	var ranged_count: int = int(composition.get("ranged", 0))
	var player_hero: Hero = _find_living_player_hero(tree)
	var player_hero_visible: bool = player_hero != null and _is_unit_near(
		player_hero,
		rally_position,
		SCOUT_RANGE
	)
	var player_hero_hp: float = (
		EnemyArmyCommand.get_health_ratio(player_hero) if player_hero != null else 0.0
	)
	var player_hero_level: int = player_hero.level if player_hero != null else 0
	var player_cc: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	var hero_distance_from_base: float = 0.0
	if player_hero != null and player_cc != null:
		hero_distance_from_base = EnemyArmyCommand.horizontal_distance(
			player_hero.global_position,
			player_cc.global_position
		)

	var worker_count: int = _count_player_workers(tree)
	var tower_count: int = _count_player_towers(tree)
	var production_count: int = _count_player_military_production(tree)
	var known_army_value: int = EnemyArmyCommand.estimate_known_player_army_strength(
		tree,
		rally_position
	)
	_track_player_army_power(known_army_value if known_army_value > 0 else visible_power)
	var recently_lost_army: bool = _player_recently_lost_army()
	var recently_expanded: bool = EnemyEarlyStrategy.is_player_expanding_greedily(tree)

	var wave_size: int = ai_count
	if EnemyArmyCommand.is_attack_wave_active():
		wave_size = maxi(wave_size, int(float(ai_count) * get_commit_army_ratio()))

	## --- Player weakness contributions ---
	if visible_count <= 1:
		score += 18.0
		reasons.append(&"player_nearly_no_army")
	elif visible_count <= 4:
		score += 12.0
		reasons.append(&"player_low_army_count")

	if visible_power > 0 and visible_power < 160:
		score += 10.0
	elif known_army_value > 0 and known_army_value < 180:
		score += 8.0

	if melee_count <= 1:
		score += 4.0
	if ranged_count <= 0:
		score += 3.0

	if player_hero == null:
		score += 10.0
		reasons.append(&"no_player_hero")
	elif player_hero_visible:
		if player_hero_hp <= 0.35:
			score += 12.0
			reasons.append(&"player_hero_low_hp")
		elif player_hero_hp <= 0.55:
			score += 6.0
		if player_hero_level <= 2:
			score += 4.0
		if hero_distance_from_base >= HERO_AWAY_DISTANCE:
			score += 8.0
			reasons.append(&"hero_far_from_base")

	if worker_count >= 10 and visible_count <= 3:
		score += 8.0
	if tower_count <= 0:
		score += 6.0
	elif tower_count <= 1:
		score += 3.0
	if production_count <= 1:
		score += 8.0
		reasons.append(&"weak_production")
	if recently_lost_army:
		score += 14.0
		reasons.append(&"player_recent_army_loss")
	if recently_expanded:
		score += 8.0
		reasons.append(&"recent_expansion")

	## --- AI strength contributions ---
	if ai_count >= 20:
		score += 14.0
	elif ai_count >= 12:
		score += 10.0
	elif ai_count >= AGGRESSION_MIN_ARMY_UNITS:
		score += 6.0

	if ai_power >= 900:
		score += 12.0
	elif ai_power >= 500:
		score += 8.0
	elif ai_power >= 300:
		score += 4.0

	if ai_hero != null:
		if ai_hero_hp >= 0.7:
			score += 5.0
		if ai_hero_level >= 4:
			score += 5.0
		elif ai_hero_level >= 3:
			score += 3.0
		if ai_mana_ratio >= 0.4:
			score += 3.0
		score += float(mini(ai_abilities_ready, 3)) * 2.0

	if wave_size >= 10:
		score += 4.0

	if visible_power > 0 and ai_power >= int(float(visible_power) * 1.4):
		score += 12.0
		reasons.append(&"decisive_power_advantage")
	elif known_army_value > 0 and ai_power >= int(float(known_army_value) * 1.25):
		score += 8.0
		reasons.append(&"known_army_advantage")

	score = clampf(score, 0.0, 100.0)
	return {
		"score": score,
		"reasons": reasons,
		"ai_power": ai_power,
		"ai_count": ai_count,
		"ai_hero_hp": ai_hero_hp,
		"ai_hero_level": ai_hero_level,
		"ai_mana_ratio": ai_mana_ratio,
		"ai_abilities_ready": ai_abilities_ready,
		"visible_count": visible_count,
		"visible_melee": melee_count,
		"visible_ranged": ranged_count,
		"visible_power": visible_power,
		"player_hero_visible": player_hero_visible,
		"player_hero_hp": player_hero_hp,
		"player_hero_level": player_hero_level,
		"hero_distance_from_base": hero_distance_from_base,
		"worker_count": worker_count,
		"tower_count": tower_count,
		"production_count": production_count,
		"known_army_value": known_army_value,
		"recently_lost_army": recently_lost_army,
		"recently_expanded": recently_expanded,
		"wave_size": wave_size,
	}


static func compute_greed_score(tree: SceneTree, rally_position: Vector3 = Vector3.ZERO) -> Dictionary:
	if tree == null:
		return {"score": 0.0, "reasons": [], "counter_pressure": false}

	if rally_position == Vector3.ZERO:
		rally_position = EnemyArmyCommand.resolve_enemy_rally_position(tree)

	var reasons: Array[StringName] = []
	var score: float = 0.0

	var player_visible: Array = _collect_visible_player_military(tree, rally_position)
	var composition: Dictionary = _count_player_composition(player_visible)
	var visible_count: int = int(composition.get("total", 0))
	var non_hero_count: int = int(composition.get("non_hero", 0))
	var visible_power: int = EnemyArmyCommand.estimate_military_power(player_visible)
	var player_hero: Hero = _find_living_player_hero(tree)
	var player_cc: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	var enemy_cc: CommandCenter = _find_living_enemy_command_center(tree)
	var worker_count: int = _count_player_workers(tree)
	var exposed_workers: int = _count_exposed_player_workers(tree, player_cc)
	var ai_units: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	var ai_power: int = EnemyArmyCommand.estimate_military_power(ai_units)
	var ai_count: int = ai_units.size()

	var hero_alone: bool = (
		player_hero != null
		and _is_unit_near(player_hero, rally_position, SCOUT_RANGE)
		and non_hero_count <= 0
	)
	var hero_small_army: bool = (
		player_hero != null
		and _is_unit_near(player_hero, rally_position, SCOUT_RANGE)
		and non_hero_count > 0
		and non_hero_count <= 3
	)
	var low_visible: bool = visible_count > 0 and visible_count <= 3 and visible_power <= 200
	var econ_skip_army: bool = worker_count >= 12 and non_hero_count <= 2
	var greedy_expansion: bool = EnemyEarlyStrategy.is_player_expanding_greedily(tree)
	var hero_away_undefended: bool = false
	if player_hero != null and player_cc != null:
		var hero_from_base: float = EnemyArmyCommand.horizontal_distance(
			player_hero.global_position,
			player_cc.global_position
		)
		var base_defenders: int = _count_player_military_near(
			tree,
			player_cc.global_position,
			BASE_DEFENSE_RADIUS
		)
		hero_away_undefended = (
			hero_from_base >= HERO_AWAY_DISTANCE and base_defenders <= 1
		)

	var hero_only_attack: bool = false
	var focus_th_ignore_army: bool = false
	if enemy_cc != null:
		var attackers_near_ai: Array = EnemyArmyCommand.collect_player_military_near(
			tree,
			enemy_cc.global_position,
			BASE_DEFENSE_RADIUS + 8.0
		)
		var attack_comp: Dictionary = _count_player_composition(attackers_near_ai)
		var attack_non_hero: int = int(attack_comp.get("non_hero", 0))
		var attack_has_hero: bool = VariantUtils.to_bool(attack_comp.get("has_hero", false))
		if attack_has_hero and attack_non_hero <= 0:
			hero_only_attack = true
			_record_hero_rush()
		elif attack_has_hero and attack_non_hero <= 3:
			hero_only_attack = true
			_record_hero_rush()

		## Player focusing enemy TH while ignoring a larger AI field army elsewhere.
		if attack_has_hero and ai_count >= 8 and attack_non_hero <= 3:
			var field_ai: int = 0
			for unit: Variant in ai_units:
				if not NodeSafety.is_alive_node(unit) or not unit is Node3D:
					continue
				if (
					EnemyArmyCommand.horizontal_distance(
						(unit as Node3D).global_position,
						enemy_cc.global_position
					)
					> BASE_DEFENSE_RADIUS
				):
					field_ai += 1
			if field_ai >= 5:
				focus_th_ignore_army = true

	if hero_only_attack or hero_away_undefended:
		_player_ignored_defense_streak = mini(_player_ignored_defense_streak + 1, 8)
	else:
		_player_ignored_defense_streak = maxi(_player_ignored_defense_streak - 1, 0)

	var ignores_defense: bool = _player_ignored_defense_streak >= 3
	var recent_loss: bool = _player_recently_lost_army()
	var repeated_hero_rush: bool = _hero_rush_repeat_count() >= HERO_RUSH_REPEAT_COUNT

	if hero_alone:
		score += GREED_HERO_ALONE
		reasons.append(&"hero_alone")
	if hero_small_army:
		score += GREED_HERO_SMALL_ARMY
		reasons.append(&"hero_small_army")
	if low_visible:
		score += GREED_LOW_VISIBLE
		reasons.append(&"low_visible_army")
	if econ_skip_army:
		score += GREED_ECON_SKIP_ARMY
		reasons.append(&"econ_skip_army")
	if hero_away_undefended:
		score += GREED_CREEPING_UNDEFENDED
		reasons.append(&"base_undefended")
	if hero_only_attack:
		score += GREED_HERO_ONLY_ATTACK
		reasons.append(&"hero_only_attack")
	if ignores_defense:
		score += GREED_IGNORES_DEFENSE
		reasons.append(&"ignores_defense")
	if focus_th_ignore_army:
		score += GREED_FOCUS_TH_IGNORE_ARMY
		reasons.append(&"focus_th_ignore_army")
	if recent_loss:
		score += GREED_RECENT_ARMY_LOSS
		reasons.append(&"recent_army_loss")
	if exposed_workers >= 3:
		score += GREED_EXPOSED_WORKERS
		reasons.append(&"exposed_workers")
	if greedy_expansion:
		score += GREED_EXPANSION
		reasons.append(&"greedy_expansion")

	var power_advantage: bool = (
		ai_power > 0
		and (visible_power <= 0 or float(ai_power) >= float(maxi(visible_power, 1)) * 1.35)
		and ai_count >= AGGRESSION_MIN_ARMY_UNITS
	)
	var counter_pressure: bool = (
		(hero_only_attack or repeated_hero_rush or hero_small_army)
		and power_advantage
	)
	if counter_pressure:
		score = minf(100.0, score + 10.0)
		reasons.append(&"counter_pressure")

	score = clampf(score, 0.0, 100.0)
	return {
		"score": score,
		"reasons": reasons,
		"counter_pressure": counter_pressure,
		"hero_alone": hero_alone,
		"hero_small_army": hero_small_army,
		"low_visible": low_visible,
		"econ_skip_army": econ_skip_army,
		"hero_away_undefended": hero_away_undefended,
		"hero_only_attack": hero_only_attack,
		"ignores_defense": ignores_defense,
		"focus_th_ignore_army": focus_th_ignore_army,
		"recent_loss": recent_loss,
		"exposed_workers": exposed_workers,
		"greedy_expansion": greedy_expansion,
		"repeated_hero_rush": repeated_hero_rush,
		"worker_count": worker_count,
		"visible_count": visible_count,
		"ai_power": ai_power,
		"visible_power": visible_power,
	}


static func should_retreat_aggression(tree: SceneTree) -> Dictionary:
	if not _aggression_active:
		return {"should_retreat": false}

	var ai_units: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	var ai_power: int = EnemyArmyCommand.estimate_military_power(ai_units)
	var ai_hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	var player_power: int = EnemyArmyCommand.estimate_known_player_army_strength(
		tree,
		rally_position
	)
	if player_power <= 0:
		player_power = EnemyArmyCommand.estimate_military_power(
			_collect_visible_player_military(tree, rally_position)
		)

	if ai_units.size() < 4:
		return {"should_retreat": true, "reason": &"army_too_small"}

	if ai_hero == null or EnemyArmyCommand.get_health_ratio(ai_hero) <= 0.2:
		return {"should_retreat": true, "reason": &"hero_critical"}

	if (
		player_power > 0
		and ai_power > 0
		and float(ai_power) < float(player_power) * RETREAT_STRENGTH_RATIO
	):
		return {"should_retreat": true, "reason": &"outpowered"}

	if _lethal_score <= RETREAT_LETHAL_THRESHOLD and _greed_score < 25.0:
		return {"should_retreat": true, "reason": &"opportunity_collapsed"}

	return {"should_retreat": false}


static func notify_attack_failed() -> void:
	_set_aggression_active(false, "attack_failed")
	_retreat_cooldown = RETREAT_COOLDOWN_SECONDS
	_confidence = Confidence.LOW


static func notify_attack_succeeded_partial() -> void:
	## Keep commitment; refresh commit timer slightly so we do not flap.
	if _aggression_active:
		_commit_timer = maxf(_commit_timer, COMMIT_MIN_SECONDS * 0.5)


static func confidence_name(level: Confidence) -> String:
	match level:
		Confidence.VERY_HIGH:
			return "very_high"
		Confidence.HIGH:
			return "high"
		Confidence.MEDIUM:
			return "medium"
		Confidence.LOW:
			return "low"
		_:
			return "very_low"


static func resolve_aggression_attack_objective(
	tree: SceneTree,
	fallback_position: Vector3
) -> Dictionary:
	## Town Hall → production → workers → remaining military.
	var command_center: CommandCenter = EnemyArmyCommand.find_living_player_command_center(tree)
	if command_center != null:
		return {
			"node": command_center,
			"position": command_center.global_position,
		}

	var production: Node3D = _find_nearest_player_production(tree, fallback_position)
	if production != null:
		return {
			"node": production,
			"position": production.global_position,
		}

	var worker: Node3D = _find_nearest_player_worker(tree, fallback_position)
	if worker != null:
		var kit_bias: StringName = _enemy_kit_id()
		## Assassin may dive workers first when Town Hall is already gone.
		if kit_bias == HeroCatalog.KIT_SHADOW_ASSASSIN:
			return {
				"node": worker,
				"position": worker.global_position,
			}
		return {
			"node": worker,
			"position": worker.global_position,
		}

	var military: Array = EnemyArmyCommand.collect_player_military_near(
		tree,
		fallback_position if fallback_position != Vector3.ZERO else (
			command_center.global_position if command_center != null else Vector3.ZERO
		),
		90.0
	)
	if not military.is_empty() and military[0] is Node3D:
		return {
			"node": military[0] as Node3D,
			"position": (military[0] as Node3D).global_position,
		}

	if fallback_position != Vector3.ZERO:
		return {"node": null, "position": fallback_position}
	return {"node": null, "position": Vector3.ZERO}


static func build_aggression_attack_force(tree: SceneTree) -> Array:
	var all_units: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	if all_units.is_empty():
		return []

	var defense_budget: int = get_home_defense_budget(all_units.size())
	var commit_ratio: float = get_commit_army_ratio()
	var desired_attackers: int = maxi(
		AGGRESSION_MIN_ARMY_UNITS,
		int(ceil(float(all_units.size()) * commit_ratio))
	)
	desired_attackers = mini(desired_attackers, all_units.size() - defense_budget)
	desired_attackers = maxi(desired_attackers, 0)

	var enemy_cc: CommandCenter = _find_living_enemy_command_center(tree)
	var base_pos: Vector3 = (
		enemy_cc.global_position if enemy_cc != null else EnemyArmyCommand.resolve_enemy_rally_position(tree)
	)

	## Keep closest units as home defense; send the rest.
	var sorted_units: Array = all_units.duplicate()
	if base_pos != Vector3.ZERO:
		sorted_units.sort_custom(func(a: Variant, b: Variant) -> bool:
			if not a is Node3D:
				return false
			if not b is Node3D:
				return true
			return (
				EnemyArmyCommand.horizontal_distance((a as Node3D).global_position, base_pos)
				< EnemyArmyCommand.horizontal_distance((b as Node3D).global_position, base_pos)
			)
		)

	var defenders: Array = []
	var attackers: Array = []
	for i: int in range(sorted_units.size()):
		var unit: Variant = sorted_units[i]
		if defenders.size() < defense_budget and not EnemyArmyCommand.is_hero_unit(unit as Node):
			defenders.append(unit)
			continue
		attackers.append(unit)

	while attackers.size() > desired_attackers:
		var overflow: Variant = attackers.pop_back()
		if overflow != null:
			defenders.append(overflow)

	## Hero always joins the commit when aggression is high.
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero != null and _confidence >= Confidence.HIGH and not attackers.has(hero):
		attackers.append(hero)

	return NodeSafety.clean_node_array(attackers)


## --- Internal state machine -------------------------------------------------

static func _update_aggression_state(tree: SceneTree, lethal: Dictionary) -> void:
	if _retreat_cooldown > 0.0 and not _aggression_active:
		return

	if _aggression_active:
		var retreat: Dictionary = should_retreat_aggression(tree)
		if VariantUtils.to_bool(retreat.get("should_retreat", false)) and _commit_timer >= COMMIT_MIN_SECONDS * 0.45:
			_set_aggression_active(false, String(retreat.get("reason", &"retreat")))
			_retreat_cooldown = RETREAT_COOLDOWN_SECONDS
			return

		if (
			_commit_timer >= COMMIT_MIN_SECONDS
			and _opportunity_score < STAY_MEDIUM_THRESHOLD
			and not _counter_pressure_active
		):
			_set_aggression_active(false, "opportunity_faded")
		return

	if _exit_cooldown > 0.0:
		return

	if not EnemyArmyCommand.can_launch_player_attack(tree):
		## Allow counter-pressure / high greed punish from EXPANSION onward only.
		return

	var ai_count: int = int(lethal.get("ai_count", 0))
	if ai_count < AGGRESSION_MIN_ARMY_UNITS:
		return

	if _confidence >= Confidence.HIGH or (
		_counter_pressure_active and _opportunity_score >= ENTER_HIGH_THRESHOLD * 0.85
	):
		_set_aggression_active(true, confidence_name(_confidence))


static func _maybe_escalate_finishing(tree: SceneTree) -> void:
	if not _aggression_active:
		return
	if EnemyArmyCommand.is_finishing_mode_active():
		return
	if _lethal_score < FINISHING_LETHAL_THRESHOLD and _confidence != Confidence.VERY_HIGH:
		return
	if not EnemyArmyCommand.can_launch_player_attack(tree):
		return

	## Soft escalate: finishing mode owns endgame focus-fire once lethal is clear.
	## Activation still goes through ArmyCommand's finishing evaluator; we only hint
	## by keeping aggression active and high attack desire.


static func _set_aggression_active(active: bool, reason: String) -> void:
	if active == _aggression_active:
		return

	_aggression_active = active
	if active:
		_commit_timer = 0.0
		print("[AI] ENTER AGGRESSION MODE reason=%s lethal=%.0f greed=%.0f" % [
			reason,
			_lethal_score,
			_greed_score,
		])
		EnemyAIDebug.log_event(
			"Aggression Mode ON (%s, lethal=%.0f, greed=%.0f)" % [
				reason,
				_lethal_score,
				_greed_score,
			]
		)
	else:
		_exit_cooldown = EXIT_COOLDOWN_SECONDS
		_counter_pressure_active = false
		print("[AI] EXIT AGGRESSION MODE reason=%s" % reason)
		EnemyAIDebug.log_event("Aggression Mode OFF (%s)" % reason)


static func _score_to_confidence(score: float) -> Confidence:
	if score >= 75.0:
		return Confidence.VERY_HIGH
	if score >= ENTER_HIGH_THRESHOLD:
		return Confidence.HIGH
	if score >= STAY_MEDIUM_THRESHOLD:
		return Confidence.MEDIUM
	if score >= 18.0:
		return Confidence.LOW
	return Confidence.VERY_LOW


## --- Scouting / counting helpers -------------------------------------------

static func _track_player_army_power(power: int) -> void:
	if power <= 0:
		return

	_last_known_player_army_power = power
	if power >= _peak_player_army_power:
		_peak_player_army_power = power
		_peak_player_army_msec = Time.get_ticks_msec()
	elif power < int(float(_peak_player_army_power) * 0.45):
		## Keep peak timestamp so "recent loss" window remains valid.
		pass


static func _player_recently_lost_army() -> bool:
	if _peak_player_army_power < 220:
		return false
	if _last_known_player_army_power <= 0:
		return false
	if _last_known_player_army_power > int(float(_peak_player_army_power) * 0.5):
		return false
	var age_ms: int = Time.get_ticks_msec() - _peak_player_army_msec
	return age_ms <= int(PLAYER_ARMY_MEMORY_SECONDS * 1000.0)


static func _record_hero_rush() -> void:
	var now: int = Time.get_ticks_msec()
	_hero_rush_events.append(now)
	_prune_hero_rush_events(now)


static func _hero_rush_repeat_count() -> int:
	_prune_hero_rush_events(Time.get_ticks_msec())
	return _hero_rush_events.size()


static func _prune_hero_rush_events(now_msec: int) -> void:
	var cutoff: int = now_msec - int(HERO_RUSH_MEMORY_SECONDS * 1000.0)
	var kept: Array[int] = []
	for stamp: int in _hero_rush_events:
		if stamp >= cutoff:
			kept.append(stamp)
	_hero_rush_events = kept


static func _collect_visible_player_military(tree: SceneTree, rally_position: Vector3) -> Array:
	return EnemyArmyCommand.collect_player_military_near(tree, rally_position, SCOUT_RANGE)


static func _count_player_composition(units: Array) -> Dictionary:
	var total: int = 0
	var non_hero: int = 0
	var melee: int = 0
	var ranged: int = 0
	var has_hero: bool = false

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue
		total += 1
		if unit is Hero:
			has_hero = true
			continue
		non_hero += 1
		if unit is Archer or unit is CavalryArcher or unit is Cannon:
			ranged += 1
		else:
			melee += 1

	return {
		"total": total,
		"non_hero": non_hero,
		"melee": melee,
		"ranged": ranged,
		"has_hero": has_hero,
	}


static func _count_player_military_near(tree: SceneTree, position: Vector3, radius: float) -> int:
	return EnemyArmyCommand.collect_player_military_near(tree, position, radius).size()


static func _count_player_workers(tree: SceneTree) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.UNITS_GROUP):
		if not node is Worker:
			continue
		if CombatTargetValidation.is_enemy_faction(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		count += 1
	return count


static func _count_exposed_player_workers(tree: SceneTree, player_cc: CommandCenter) -> int:
	if player_cc == null:
		return 0
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.UNITS_GROUP):
		if not node is Worker:
			continue
		if CombatTargetValidation.is_enemy_faction(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		var worker: Node3D = node as Node3D
		var dist: float = EnemyArmyCommand.horizontal_distance(
			worker.global_position,
			player_cc.global_position
		)
		if dist > WORKER_EXPOSE_RADIUS:
			var nearby_guard: int = _count_player_military_near(
				tree,
				worker.global_position,
				14.0
			)
			if nearby_guard <= 0:
				count += 1
	return count


static func _count_player_towers(tree: SceneTree) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.BUILDINGS_GROUP):
		if not node is Tower:
			continue
		if not CombatTargetValidation.is_player_selectable_building(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		count += 1
	return count


static func _count_player_military_production(tree: SceneTree) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.BUILDINGS_GROUP):
		if not (node is Barracks or node is HeroAltar):
			continue
		if not CombatTargetValidation.is_player_selectable_building(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		count += 1
	return count


static func _find_living_player_hero(tree: SceneTree) -> Hero:
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.HEROES_GROUP):
		if not node is Hero:
			continue
		if CombatTargetValidation.is_enemy_faction(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		return node as Hero
	return null


static func _find_living_enemy_command_center(tree: SceneTree) -> CommandCenter:
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.ENEMY_COMMAND_CENTER_GROUP):
		if node is CommandCenter and CombatTargetValidation.get_target_current_health(node) > 0:
			return node as CommandCenter
	return null


static func _find_nearest_player_production(tree: SceneTree, from_position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.BUILDINGS_GROUP):
		if not (node is Barracks or node is HeroAltar):
			continue
		if not CombatTargetValidation.is_player_selectable_building(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		var building: Node3D = node as Node3D
		var distance: float = (
			EnemyArmyCommand.horizontal_distance(from_position, building.global_position)
			if from_position != Vector3.ZERO
			else 0.0
		)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


static func _find_nearest_player_worker(tree: SceneTree, from_position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in tree.get_nodes_in_group(EnemyArmyCommand.UNITS_GROUP):
		if not node is Worker:
			continue
		if CombatTargetValidation.is_enemy_faction(node):
			continue
		if CombatTargetValidation.get_target_current_health(node) <= 0:
			continue
		var worker: Node3D = node as Node3D
		var distance: float = (
			EnemyArmyCommand.horizontal_distance(from_position, worker.global_position)
			if from_position != Vector3.ZERO
			else 0.0
		)
		if distance < best_distance:
			best_distance = distance
			best = worker
	return best


static func _is_unit_near(unit: Node3D, position: Vector3, radius: float) -> bool:
	if unit == null or position == Vector3.ZERO:
		return false
	return EnemyArmyCommand.horizontal_distance(unit.global_position, position) <= radius


static func _count_ready_abilities(hero: Hero) -> int:
	if hero == null:
		return 0
	var ready: int = 0
	for ability_id: StringName in [
		HeroAbilityProgression.ABILITY_Q,
		HeroAbilityProgression.ABILITY_W,
		HeroAbilityProgression.ABILITY_E,
		HeroAbilityProgression.ABILITY_R,
	]:
		if hero.has_method("is_ability_unlocked") and not hero.is_ability_unlocked(ability_id):
			continue
		if hero.get_ability_cooldown_remaining(ability_id) <= 0.05:
			ready += 1
	return ready


static func _enemy_kit_id() -> StringName:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return &""
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero != null:
		return hero.get_hero_kit_id()
	return &""


## Test helpers — force confidence / aggression without a full match simulation.
static func force_scores_for_tests(lethal: float, greed: float) -> void:
	_lethal_score = clampf(lethal, 0.0, 100.0)
	_greed_score = clampf(greed, 0.0, 100.0)
	_opportunity_score = clampf(_lethal_score * 0.62 + _greed_score * 0.48, 0.0, 100.0)
	_confidence = _score_to_confidence(_opportunity_score)


static func force_aggression_for_tests(active: bool, reason: String = "test") -> void:
	if active and _confidence < Confidence.HIGH:
		_confidence = Confidence.HIGH
	_set_aggression_active(active, reason)
	if active:
		_commit_timer = COMMIT_MIN_SECONDS


static func force_counter_pressure_for_tests(active: bool) -> void:
	_counter_pressure_active = active
