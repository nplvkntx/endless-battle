class_name EnemyWaveManager
extends Node

## Launches scaled enemy attack waves on a timer and keeps the enemy hero with the army.

const PLAYER_COMMAND_CENTER_GROUP := &"player_command_center"
const HERO_BEHAVIOR_INTERVAL_SECONDS := 1.0

@export var player_command_center_path: NodePath
@export var wave_interval_seconds: float = 30.0

var _wave_active: bool = true
var _waves_launched: int = 0
var _tracked_player_command_center: CommandCenter = null
var _hero_behavior_timer: float = 0.0


func _ready() -> void:
	_tracked_player_command_center = _resolve_player_command_center()
	if _tracked_player_command_center != null:
		_tracked_player_command_center.destroyed.connect(
			_on_player_command_center_destroyed,
			CONNECT_ONE_SHOT
		)
	_schedule_next_wave()


func _process(delta: float) -> void:
	_hero_behavior_timer += delta
	if _hero_behavior_timer < HERO_BEHAVIOR_INTERVAL_SECONDS:
		return

	_hero_behavior_timer = 0.0
	_update_hero_army_behavior()


func _update_hero_army_behavior() -> void:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null or not is_instance_valid(hero):
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var non_hero_units: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(get_tree())
	var health_ratio: float = EnemyArmyCommand.get_health_ratio(hero)

	_try_enemy_hero_abilities(hero, health_ratio)

	if health_ratio < EnemyArmyCommand.HERO_RETREAT_HP_RATIO:
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	if non_hero_units.size() < EnemyArmyCommand.MIN_ARMY_UNITS_TO_CONTINUE_ATTACK:
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(non_hero_units)
	if army_center == Vector3.ZERO:
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	var distance_to_army: float = _horizontal_distance(hero.global_position, army_center)
	if distance_to_army > EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY:
		EnemyArmyCommand.command_retreat_hero(hero, army_center)
		return

	if non_hero_units.size() < EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN:
		var distance_to_rally: float = _horizontal_distance(hero.global_position, rally_position)
		if distance_to_rally > EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY * 0.5:
			EnemyArmyCommand.command_retreat_hero(hero, rally_position)


func _try_enemy_hero_abilities(hero: Hero, health_ratio: float) -> void:
	if not CombatTargetValidation.is_enemy_faction(hero):
		return

	_ensure_enemy_hero_combat_abilities(hero)

	if (
		health_ratio < EnemyArmyCommand.HERO_DEFENSIVE_ABILITY_HP_RATIO
		and hero.has_method("try_divine_protection")
		and hero.has_method("is_divine_protection_active")
		and hero.is_ability_unlocked(HeroAbilityProgression.ABILITY_W)
		and not hero.call("is_divine_protection_active")
	):
		hero.try_divine_protection()

	if (
		hero.has_method("try_ground_slam")
		and hero.is_ability_unlocked(HeroAbilityProgression.ABILITY_Q)
		and _count_player_military_near_hero(hero) >= EnemyArmyCommand.HERO_AOE_PLAYER_COUNT
	):
		hero.try_ground_slam()


func _ensure_enemy_hero_combat_abilities(hero: Hero) -> void:
	if hero.ability_progression == null:
		return

	if not hero.is_ability_unlocked(HeroAbilityProgression.ABILITY_Q):
		hero.ability_progression.learn_ability(HeroAbilityProgression.ABILITY_Q)

	if not hero.is_ability_unlocked(HeroAbilityProgression.ABILITY_W):
		hero.ability_progression.learn_ability(HeroAbilityProgression.ABILITY_W)


func _count_player_military_near_hero(hero: Hero) -> int:
	var count: int = 0
	var search_range: float = EnemyArmyCommand.HERO_AOE_CHECK_RANGE

	for group_name: StringName in [&"units", &"heroes"]:
		for node: Node in get_tree().get_nodes_in_group(group_name):
			if CombatTargetValidation.is_enemy_faction(node):
				continue

			if not (node is Swordsman or node is Archer or node is Hero):
				continue

			if node is Worker:
				continue

			var health_component: HealthComponent = node.get_node_or_null(
				"HealthComponent"
			) as HealthComponent
			if health_component != null and health_component.current_health <= 0:
				continue

			var target: Node3D = node as Node3D
			if _horizontal_distance(hero.global_position, target.global_position) > search_range:
				continue

			count += 1

	return count


func _horizontal_distance(from_position: Vector3, to_position: Vector3) -> float:
	var offset: Vector3 = from_position - to_position
	offset.y = 0.0
	return offset.length()


func _schedule_next_wave() -> void:
	if not _wave_active:
		return

	var wait_timer: SceneTreeTimer = get_tree().create_timer(wave_interval_seconds)
	wait_timer.timeout.connect(_on_wave_timer, CONNECT_ONE_SHOT)


func _on_wave_timer() -> void:
	if not _wave_active:
		return

	if not _has_any_attack_target():
		_wave_active = false
		return

	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	var next_wave_number: int = _waves_launched + 1
	var min_non_hero_units: int = EnemyArmyCommand.get_min_non_hero_units_for_wave(
		next_wave_number
	)
	var wave_plan: Dictionary = EnemyArmyCommand.build_attack_wave_units(
		get_tree(),
		min_non_hero_units
	)

	if not wave_plan.get("can_launch", false):
		_hold_army_until_ready(rally_position, int(wave_plan.get("non_hero_count", 0)))
		_schedule_next_wave()
		return

	var attack_destination: Vector3 = EnemyArmyCommand.resolve_wave_attack_destination(
		get_tree(),
		rally_position
	)
	EnemyArmyCommand.command_attack_move(wave_plan.get("units", []), attack_destination)
	_waves_launched += 1
	_schedule_next_wave()


func _hold_army_until_ready(rally_position: Vector3, non_hero_count: int) -> void:
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(get_tree())
	if hero == null or not is_instance_valid(hero):
		return

	if not EnemyArmyCommand.is_hero_healthy_enough_for_wave(hero):
		EnemyArmyCommand.command_retreat_hero(hero, rally_position)
		return

	var min_non_hero_units: int = EnemyArmyCommand.get_min_non_hero_units_for_wave(
		_waves_launched + 1
	)
	if non_hero_count >= min_non_hero_units:
		return

	if non_hero_count < EnemyArmyCommand.MIN_NON_HERO_FOR_HERO_JOIN:
		EnemyArmyCommand.command_hold_at_rally([hero], rally_position)


func _has_any_attack_target() -> bool:
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(get_tree())
	return EnemyArmyCommand.has_player_attack_targets(get_tree(), rally_position)


func _resolve_player_command_center() -> CommandCenter:
	if _tracked_player_command_center != null and _is_living_command_center(
		_tracked_player_command_center
	):
		return _tracked_player_command_center

	if not player_command_center_path.is_empty():
		var path_node: Node = get_node_or_null(player_command_center_path)
		if path_node is CommandCenter and _is_living_command_center(path_node as CommandCenter):
			return path_node as CommandCenter

	for node: Node in get_tree().get_nodes_in_group(PLAYER_COMMAND_CENTER_GROUP):
		if node is CommandCenter and _is_living_command_center(node as CommandCenter):
			return node as CommandCenter

	return null


func _is_living_command_center(command_center: CommandCenter) -> bool:
	if command_center == null or not is_instance_valid(command_center):
		return false

	if command_center.is_queued_for_deletion():
		return false

	var health_component: HealthComponent = command_center.get_node_or_null(
		"HealthComponent"
	) as HealthComponent
	if health_component != null:
		return health_component.current_health > 0

	return true


func _on_player_command_center_destroyed(_building: Building) -> void:
	_tracked_player_command_center = null
