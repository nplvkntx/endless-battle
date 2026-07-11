class_name EnemyStrategicDirector
extends Node

## High-level enemy AI coordinator. Evaluates world state and sets parallel strategic desires.
## Existing managers execute decisions; this node does not micromanage every unit.

const FAST_TICK_SECONDS: float = 0.75
const NORMAL_TICK_SECONDS: float = 3.0
const STRATEGIC_TICK_SECONDS: float = 12.0
const RECOVERY_TICK_SECONDS: float = 8.0
const NODE_CLEANUP_INTERVAL_SECONDS: float = 0.5

const DESIRE_HIGH: float = 0.75
const DESIRE_MEDIUM: float = 0.45
const DESIRE_LOW: float = 0.20

@export var debug_enabled: bool = false

var _fast_timer: float = 0.0
var _normal_timer: float = 0.0
var _strategic_timer: float = 0.0
var _recovery_timer: float = 0.0
var _node_cleanup_timer: float = 0.0
var _match_start_msec: int = 0
var _recent_attack_failed: bool = false
var _recent_loss_timer: float = 0.0
var _creep_target: Node3D = null
var _attack_target_position: Vector3 = Vector3.ZERO
var _last_debug_mission: EnemyUnitMission.Mission = EnemyUnitMission.Mission.IDLE
var _last_debug_desires: Dictionary = {}

var desires: Dictionary = {
	"economy": 0.8,
	"army": 0.5,
	"creep": 0.5,
	"attack": 0.1,
	"defense": 0.0,
	"expansion": 0.2,
	"upgrade": 0.2,
}

var snapshot: Dictionary = {}


func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	EnemyArmyCommand.set_debug_enabled(debug_enabled)
	call_deferred("_run_initial_evaluation")


func _run_initial_evaluation() -> void:
	if not is_inside_tree():
		return

	_evaluate_normal()
	_evaluate_strategic()


func _process(delta: float) -> void:
	_node_cleanup_timer += delta
	if _node_cleanup_timer >= NODE_CLEANUP_INTERVAL_SECONDS:
		_node_cleanup_timer = 0.0
		_run_node_reference_cleanup()

	_sanitize_creep_target()
	_fast_timer += delta
	_normal_timer += delta
	_strategic_timer += delta
	_recovery_timer += delta

	if _recent_loss_timer > 0.0:
		_recent_loss_timer = maxf(0.0, _recent_loss_timer - delta)

	if _fast_timer >= FAST_TICK_SECONDS:
		_fast_timer = 0.0
		_evaluate_fast()

	if _normal_timer >= NORMAL_TICK_SECONDS:
		_normal_timer = 0.0
		_evaluate_normal()

	if _strategic_timer >= STRATEGIC_TICK_SECONDS:
		_strategic_timer = 0.0
		_evaluate_strategic()

	if _recovery_timer >= RECOVERY_TICK_SECONDS:
		_recovery_timer = 0.0
		_run_recovery_checks()


func get_desire(key: String) -> float:
	return float(desires.get(key, 0.0))


func should_prioritize_creep() -> bool:
	return (
		get_desire("creep") >= DESIRE_MEDIUM
		and get_desire("defense") < DESIRE_HIGH
		and EnemyArmyCommand.get_army_mode() not in [
			EnemyArmyCommand.ArmyMode.DEFENDING,
			EnemyArmyCommand.ArmyMode.INTERCEPTING,
		]
	)


func should_prioritize_attack() -> bool:
	return (
		get_desire("attack") >= DESIRE_MEDIUM
		and get_desire("defense") < DESIRE_HIGH
	)


func should_prioritize_expansion() -> bool:
	return (
		get_desire("expansion") >= DESIRE_MEDIUM
		and get_desire("defense") < DESIRE_HIGH
		and not _recent_attack_failed
	)


func should_boost_army_production() -> bool:
	return get_desire("army") >= DESIRE_MEDIUM or get_desire("defense") >= DESIRE_MEDIUM


func should_boost_worker_production() -> bool:
	return get_desire("economy") >= DESIRE_MEDIUM


func notify_attack_launched() -> void:
	_recent_attack_failed = false
	_set_main_mission(EnemyUnitMission.Mission.ATTACK, "attack wave launched")


func notify_attack_failed() -> void:
	_recent_attack_failed = true
	_recent_loss_timer = 45.0
	_set_main_mission(EnemyUnitMission.Mission.REGROUP, "attack failed, rebuilding")


func notify_army_losses() -> void:
	_recent_loss_timer = 30.0
	desires["army"] = maxf(desires["army"], DESIRE_HIGH)
	desires["attack"] = minf(desires["attack"], DESIRE_LOW)


func set_creep_target(camp) -> void:
	_creep_target = NodeSafety.safe_node(camp) as Node3D


func clear_creep_target() -> void:
	_creep_target = null


func _sanitize_creep_target() -> void:
	if not NodeSafety.is_alive_node(_creep_target):
		_creep_target = null


func _run_node_reference_cleanup() -> void:
	var removed: int = 0
	removed += EnemyUnitMission.purge_stale_entries()
	removed += CombatTargetValidation.purge_stale_attack_slots()

	if debug_enabled and removed > 0:
		print("AI cleanup: purged %d stale node references" % removed)


func set_attack_target_position(position: Vector3) -> void:
	_attack_target_position = position


func _evaluate_fast() -> void:
	EnemyArmyCommand.apply_pending_strategic_transition()
	var tree: SceneTree = get_tree()
	var emergency_threat: Dictionary = EnemyArmyCommand.evaluate_emergency_defense_threat(tree)
	if emergency_threat.get("threatened", false):
		desires["defense"] = 1.0
		desires["attack"] = 0.0
		desires["creep"] = 0.0
		desires["expansion"] = 0.0
		_set_main_mission(
			EnemyUnitMission.Mission.DEFEND,
			"threat near base (%s)" % String(emergency_threat.get("reason", "unknown"))
		)
		return

	var threat: Dictionary = EnemyArmyCommand.evaluate_defense_threat(tree)
	if threat.get("threatened", false):
		desires["defense"] = 1.0
		desires["attack"] = 0.0
		desires["creep"] = 0.0
		desires["expansion"] = 0.0
		_set_main_mission(
			EnemyUnitMission.Mission.DEFEND,
			"threat near base (%s)" % String(threat.get("reason", "unknown"))
		)
	else:
		desires["defense"] = maxf(0.0, desires["defense"] - 0.25)


func _evaluate_normal() -> void:
	snapshot = _build_world_snapshot()
	_update_desires_from_snapshot()
	_recommend_main_army_mission()
	_maybe_log_debug()


func _evaluate_strategic() -> void:
	if desires["expansion"] >= DESIRE_MEDIUM and snapshot.get("economy_healthy", false):
		desires["expansion"] = minf(1.0, desires["expansion"] + 0.15)

	if snapshot.get("hero_alive", false) and int(snapshot.get("hero_level", 1)) >= 2:
		desires["upgrade"] = minf(1.0, desires["upgrade"] + 0.1)


func _build_world_snapshot() -> Dictionary:
	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	var workers: Array = _collect_workers(tree)
	var idle_workers: int = 0
	var gold_workers: int = 0
	var wood_workers: int = 0

	for worker: Variant in workers:
		if not NodeSafety.is_alive_node(worker):
			continue

		if not worker is Worker:
			continue

		var w: Worker = worker as Worker
		if w.is_on_construction_trip():
			continue

		match w.get_assigned_gather_resource_id():
			&"gold":
				gold_workers += 1
			&"wood":
				wood_workers += 1

		if _is_idle_worker(w):
			idle_workers += 1

	var non_hero_army: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(tree)
	var all_combat: Array = EnemyArmyCommand.collect_living_combat_units(tree)
	var army_power: int = EnemyArmyCommand.estimate_military_power(all_combat)
	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	var visible_threat_power: int = 0
	if rally_position != Vector3.ZERO:
		visible_threat_power = EnemyArmyCommand.estimate_player_threat_power_near(
			tree,
			rally_position,
			EnemyArmyCommand.BASE_THREAT_DETECTION_RANGE
		)

	var food_headroom: int = (
		EnemyResourceManager.food_max - EnemyResourceManager.food_current
	)
	var supply_block_risk: bool = food_headroom <= 3

	return {
		"workers": workers.size(),
		"idle_workers": idle_workers,
		"gold_workers": gold_workers,
		"wood_workers": wood_workers,
		"gold": EnemyResourceManager.gold,
		"wood": EnemyResourceManager.wood,
		"food_used": EnemyResourceManager.food_current,
		"food_cap": EnemyResourceManager.food_max,
		"supply_block_risk": supply_block_risk,
		"town_centers": _count_group(tree, &"enemy_command_center"),
		"production_buildings": _count_barracks(tree),
		"expansion_count": maxi(0, _count_group(tree, &"enemy_command_center") - 1),
		"base_under_attack": EnemyArmyCommand.is_enemy_base_threatened(tree),
		"hero_alive": hero != null,
		"hero_level": hero.level if hero != null else 0,
		"combat_unit_count": non_hero_army.size(),
		"army_power": army_power,
		"army_mode": EnemyArmyCommand.get_army_mode(),
		"visible_enemy_power": visible_threat_power,
		"economy_healthy": (
			workers.size() >= 8
			and EnemyResourceManager.gold >= 100
			and EnemyResourceManager.wood >= 80
		),
		"match_elapsed_seconds": _get_match_elapsed_seconds(),
		"recent_losses": _recent_loss_timer > 0.0,
	}


func _update_desires_from_snapshot() -> void:
	var workers: int = int(snapshot.get("workers", 0))
	var idle_workers: int = int(snapshot.get("idle_workers", 0))
	var army_power: int = int(snapshot.get("army_power", 0))
	var hero_alive: bool = snapshot.get("hero_alive", false)
	var hero_level: int = int(snapshot.get("hero_level", 0))
	var base_under_attack: bool = snapshot.get("base_under_attack", false)
	var supply_block_risk: bool = snapshot.get("supply_block_risk", false)
	var economy_healthy: bool = snapshot.get("economy_healthy", false)
	var visible_enemy_power: int = int(snapshot.get("visible_enemy_power", 0))
	var elapsed: float = float(snapshot.get("match_elapsed_seconds", 0.0))

	if base_under_attack or get_desire("defense") >= DESIRE_HIGH:
		desires["defense"] = maxf(desires["defense"], DESIRE_HIGH)
		desires["attack"] = DESIRE_LOW
		desires["creep"] = DESIRE_LOW
		desires["expansion"] = 0.0
	else:
		desires["defense"] = maxf(0.0, desires["defense"] - 0.15)

	desires["economy"] = clampf(
		0.55
		+ float(maxi(0, 14 - workers)) * 0.04
		+ float(idle_workers) * 0.08
		+ (0.15 if supply_block_risk else 0.0),
		0.0,
		1.0
	)

	var army_target_power: float = float(EnemyArmyCommand.MIN_ATTACK_ARMY_POWER)
	desires["army"] = clampf(
		float(army_power) / army_target_power,
		0.0,
		1.0
	)
	if _recent_loss_timer > 0.0:
		desires["army"] = maxf(desires["army"], DESIRE_HIGH)

	if hero_alive and army_power >= int(army_target_power * 0.6):
		desires["creep"] = clampf(
			0.35 + float(hero_level) * 0.08 + (0.2 if army_power >= 400 else 0.0),
			0.0,
			1.0
		)
	else:
		desires["creep"] = DESIRE_LOW

	if (
		not hero_alive
		or EnemyArmyCommand.is_rebuilding_army()
		or _recent_loss_timer > 0.0
		or _recent_attack_failed
	):
		desires["attack"] = DESIRE_LOW
	elif not _can_launch_offensive_attack():
		desires["attack"] = DESIRE_LOW
	elif visible_enemy_power > 0 and army_power >= int(float(visible_enemy_power) * EnemyArmyCommand.PLAYER_ARMY_STRENGTH_RATIO):
		desires["attack"] = clampf(
			0.5 + float(army_power - visible_enemy_power) / 600.0,
			DESIRE_MEDIUM,
			1.0
		)
	elif elapsed >= 420.0 and army_power >= EnemyArmyCommand.MIN_ATTACK_ARMY_POWER:
		desires["attack"] = DESIRE_MEDIUM
	else:
		desires["attack"] = clampf(
			float(army_power) / (army_target_power * 1.4),
			DESIRE_LOW,
			DESIRE_MEDIUM
		)

	if economy_healthy and elapsed > 300.0 and desires["defense"] < DESIRE_MEDIUM:
		desires["expansion"] = clampf(
			0.25 + float(snapshot.get("expansion_count", 0)) * -0.1 + (0.2 if workers >= 16 else 0.0),
			0.0,
			0.85
		)
	else:
		desires["expansion"] = minf(desires["expansion"], DESIRE_LOW)

	if hero_alive and hero_level >= 2 and economy_healthy:
		desires["upgrade"] = clampf(0.3 + float(hero_level) * 0.05, DESIRE_LOW, 0.9)
	else:
		desires["upgrade"] = DESIRE_LOW


func _recommend_main_army_mission() -> void:
	if EnemyArmyCommand.get_strategic_state() == EnemyArmyCommand.StrategicState.EMERGENCY_DEFENDING:
		_set_main_mission(EnemyUnitMission.Mission.DEFEND, "emergency defending")
		return

	if desires["defense"] >= DESIRE_HIGH:
		return

	var army_mode: EnemyArmyCommand.ArmyMode = EnemyArmyCommand.get_army_mode()
	match army_mode:
		EnemyArmyCommand.ArmyMode.DEFENDING, EnemyArmyCommand.ArmyMode.INTERCEPTING:
			_set_main_mission(EnemyUnitMission.Mission.DEFEND, "army defending")
			return
		EnemyArmyCommand.ArmyMode.ATTACKING:
			_set_main_mission(EnemyUnitMission.Mission.ATTACK, "army attacking")
			return
		EnemyArmyCommand.ArmyMode.CREEPING:
			_set_main_mission(EnemyUnitMission.Mission.CREEP, "army clearing creep camp")
			return

	if _recent_loss_timer > 0.0 or desires["army"] >= DESIRE_HIGH:
		_set_main_mission(
			EnemyUnitMission.Mission.REGROUP,
			"rebuilding army (power %d)" % int(snapshot.get("army_power", 0))
		)
		return

	if should_prioritize_creep():
		_set_main_mission(
			EnemyUnitMission.Mission.CREEP,
			"safe creep available, army power %d" % int(snapshot.get("army_power", 0))
		)
		return

	if should_prioritize_attack():
		if not _can_launch_offensive_attack():
			_set_main_mission(
				EnemyUnitMission.Mission.REGROUP,
				"attack gate not met, army power %d" % int(snapshot.get("army_power", 0))
			)
			return

		_set_main_mission(
			EnemyUnitMission.Mission.ATTACK,
			"attack desire %.2f, hero %s" % [
				get_desire("attack"),
				"alive" if snapshot.get("hero_alive", false) else "dead",
			]
		)
		return

	_set_main_mission(
		EnemyUnitMission.Mission.REGROUP,
		"holding at rally, army power %d" % int(snapshot.get("army_power", 0))
	)


func _set_main_mission(mission: EnemyUnitMission.Mission, reason: String) -> void:
	if EnemyUnitMission.set_main_army_mission(mission, reason):
		_maybe_log_mission_change(mission, reason)


func _run_recovery_checks() -> void:
	if EnemyArmyCommand.is_attack_wave_controlling_hero():
		return

	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return

	if EnemyArmyCommand.get_army_mode() in [
		EnemyArmyCommand.ArmyMode.DEFENDING,
		EnemyArmyCommand.ArmyMode.INTERCEPTING,
	]:
		return

	var main_mission: EnemyUnitMission.Mission = EnemyUnitMission.get_main_army_mission()
	if (
		main_mission == EnemyUnitMission.Mission.REGROUP
		or main_mission == EnemyUnitMission.Mission.ATTACK
		or main_mission == EnemyUnitMission.Mission.CREEP
	):
		EnemyArmyCommand.pull_reinforcement_units_to_rally(tree, rally_position)

	var hero: Hero = EnemyArmyCommand.find_living_enemy_hero(tree)
	if hero == null:
		return

	var non_hero: Array = EnemyArmyCommand.collect_living_non_hero_combat_units(tree)
	if non_hero.is_empty():
		return

	var army_center: Vector3 = EnemyArmyCommand.compute_army_center(non_hero)
	if army_center == Vector3.ZERO:
		return

	if (
		EnemyArmyCommand.horizontal_distance(hero.global_position, army_center)
		> EnemyArmyCommand.HERO_MAX_DISTANCE_FROM_ARMY * 1.5
		and main_mission != EnemyUnitMission.Mission.RETREAT
	):
		EnemyArmyCommand.assign_reinforcement_regroup(tree, hero)


func _maybe_log_debug() -> void:
	if not debug_enabled:
		return

	var desires_changed: bool = false
	for key: String in desires.keys():
		var current: float = float(desires[key])
		var previous: float = float(_last_debug_desires.get(key, -1.0))
		if absf(current - previous) >= 0.15:
			desires_changed = true
			break

	if desires_changed:
		print(
			"AI desires: economy=%.2f army=%.2f creep=%.2f attack=%.2f defense=%.2f expansion=%.2f upgrade=%.2f"
			% [
				get_desire("economy"),
				get_desire("army"),
				get_desire("creep"),
				get_desire("attack"),
				get_desire("defense"),
				get_desire("expansion"),
				get_desire("upgrade"),
			]
		)
		_last_debug_desires = desires.duplicate()


func _maybe_log_mission_change(mission: EnemyUnitMission.Mission, reason: String) -> void:
	if not debug_enabled:
		return

	if mission == _last_debug_mission:
		return

	print(
		"AI mission: %s -> %s\nReason: %s"
		% [
			EnemyUnitMission.mission_to_label(_last_debug_mission),
			EnemyUnitMission.mission_to_label(mission),
			reason,
		]
	)
	print(
		"AI status: army strength %d, workers %d, creep target %s, attack target %s"
		% [
			int(snapshot.get("army_power", 0)),
			int(snapshot.get("workers", 0)),
			_creep_target.name if _creep_target != null and is_instance_valid(_creep_target) else "none",
			str(_attack_target_position) if _attack_target_position != Vector3.ZERO else "none",
		]
	)
	_last_debug_mission = mission


func _collect_workers(tree: SceneTree) -> Array:
	var workers: Array = []
	for node: Node in tree.get_nodes_in_group(&"enemy_workers"):
		if not NodeSafety.is_alive_node(node):
			continue

		if node is Worker and (node as Worker).get_current_health() > 0:
			workers.append(node)
	return NodeSafety.clean_node_array(workers)


func _is_idle_worker(worker) -> bool:
	if not NodeSafety.is_alive_node(worker):
		return false

	if not worker is Worker:
		return false

	if worker.is_on_construction_trip() or worker.is_carrying_gathered_resources():
		return false

	if worker.has_method(&"is_enemy_gather_fallback_idle"):
		return worker.is_enemy_gather_fallback_idle()

	return worker.needs_gather_target_reassignment()


func _count_group(tree: SceneTree, group_name: StringName) -> int:
	return tree.get_nodes_in_group(group_name).size()


func _count_barracks(tree: SceneTree) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(&"enemy_command_center"):
		if node is Barracks:
			count += 1
	return count


func get_match_elapsed_seconds() -> float:
	return _get_match_elapsed_seconds()


func _get_match_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _match_start_msec) / 1000.0


func _can_launch_offensive_attack() -> bool:
	var tree: SceneTree = get_tree()
	var rally_position: Vector3 = EnemyArmyCommand.resolve_enemy_rally_position(tree)
	if rally_position == Vector3.ZERO:
		return false

	return EnemyArmyCommand.evaluate_attack_gate(tree, rally_position).get("can_commit", false)
