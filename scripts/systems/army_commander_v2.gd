class_name ArmyCommanderV2
extends Node

## Executes the mission published by MilitaryDirectorV2.
## Does not choose creep / attack / defend / retreat itself.
##
## Foundation task: drains shared order batch infrastructure, ticks hero micro,
## and holds the army idle. Advanced execution is not migrated yet.

const HERO_MICRO_INTERVAL_SECONDS: float = 1.0
const HERO_EXECUTE_SEARCH_RANGE: float = 14.0

var _director: MilitaryDirectorV2 = null
var _hero_micro_timer: float = 0.0


func _ready() -> void:
	_director = get_parent().get_node_or_null("MilitaryDirectorV2") as MilitaryDirectorV2
	_hero_micro_timer = HERO_MICRO_INTERVAL_SECONDS * 0.4
	set_process(MilitaryAIConfig.is_v2_enabled())


func reset_match_state() -> void:
	_hero_micro_timer = HERO_MICRO_INTERVAL_SECONDS * 0.4


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_v2_enabled():
		set_process(false)
		return

	## Shared order-bus drain previously owned by EnemyCombatController.
	EnemyArmyCommand.apply_pending_strategic_transition()
	EnemyArmyCommand.tick_group_order_batch(get_tree())
	EnemyArmyCommand.tick_perf_diagnostics(get_tree(), delta)
	EnemyArmyCommand.tick_retreat_cooldown(delta)

	_hero_micro_timer += delta
	if _hero_micro_timer >= HERO_MICRO_INTERVAL_SECONDS:
		_hero_micro_timer = 0.0
		_tick_hero_micro()

	_execute_current_mission(delta)
	PerfCounters.record_ai_combat_update()


func _execute_current_mission(_delta: float) -> void:
	if _director == null:
		_director = get_parent().get_node_or_null("MilitaryDirectorV2") as MilitaryDirectorV2
	if _director == null:
		return

	var mission: ArmyMissionV2 = _director.get_mission()
	if mission == null:
		return

	mission.sanitize_target_object()

	## Foundation: no strategic self-decisions and no advanced order issuance yet.
	match _director.get_state():
		MilitaryDirectorV2.State.IDLE, MilitaryDirectorV2.State.RECOVER:
			pass
		MilitaryDirectorV2.State.ASSEMBLE, MilitaryDirectorV2.State.CREEP, MilitaryDirectorV2.State.ATTACK, MilitaryDirectorV2.State.DEFEND, MilitaryDirectorV2.State.RETREAT:
			## Reserved for future execution adapters. Commander still must not choose these.
			pass


func _tick_hero_micro() -> void:
	## Hero AI may cast abilities, choose targets during the current mission, and survive.
	## Hero AI may not choose the army mission or override defend/retreat (see AIHeroMastery).
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null or not is_instance_valid(hero):
		return

	var health_ratio: float = EnemyArmyCommand.get_health_ratio(hero)
	var state_name: String = "IDLE"
	var mission_type_name: String = "IDLE"
	if _director != null:
		state_name = _director.get_state_name()
		var mission: ArmyMissionV2 = _director.get_mission()
		if mission != null:
			mission_type_name = mission.get_mission_type_name()

	var creeping: bool = state_name == "CREEP" or mission_type_name == "CREEP"
	var retreating: bool = (
		state_name == "RETREAT"
		or mission_type_name == "RETREAT"
		or health_ratio < EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO
	)
	var defend_base: bool = state_name == "DEFEND" or mission_type_name == "DEFEND"

	AIHeroMastery.tick(
		hero,
		{
			"health_ratio": health_ratio,
			"nearby_enemy_count": 0,
			"aoe_needed": EnemyArmyCommand.HERO_AOE_PLAYER_COUNT,
			"defensive_hp_ratio": EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO,
			"power_strike_range": EnemyArmyCommand.HERO_POWER_STRIKE_SEARCH_RANGE,
			"execute_range": HERO_EXECUTE_SEARCH_RANGE,
			"retreating": retreating,
			"creeping": creeping,
			"defend_base": defend_base,
			"mastery_owned": true,
			"military_ai_v2": true,
			"army_state": state_name,
			"army_mission": mission_type_name,
		}
	)
