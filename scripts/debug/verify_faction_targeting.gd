extends Node

## Headless check: faction-relative hostility, tower acquire, splash, friendly-fire block.
## Run:
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_faction_targeting.tscn

const REPORT_PATH := "user://faction_targeting_verify_result.txt"
const STUB_SCRIPT := preload("res://scripts/debug/faction_targeting_combat_stub.gd")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	var player_tower: Node3D = _make_combat_stub("PlayerTower", Vector3(0, 0, 0), [&"buildings"])
	var enemy_tower: Node3D = _make_combat_stub(
		"EnemyTower", Vector3(20, 0, 0), [&"buildings", &"enemy_command_center"]
	)
	var player_unit: Node3D = _make_combat_stub("PlayerUnit", Vector3(21, 0, 0), [&"units"])
	var enemy_unit: Node3D = _make_combat_stub("EnemyUnit", Vector3(1, 0, 0), [&"enemies"])
	var ally_enemy_unit: Node3D = _make_combat_stub(
		"AllyEnemyUnit", Vector3(22, 0, 0), [&"enemies"]
	)
	var neutral_creep: Node3D = _make_combat_stub(
		"NeutralCreep", Vector3(5, 0, 0), [&"neutral_creeps"]
	)
	var dead_enemy: Node3D = _make_combat_stub("DeadEnemy", Vector3(2, 0, 0), [&"enemies"])
	_set_health(dead_enemy, 0)

	_expect(
		failures,
		"player tower hostile to enemy unit",
		CombatTargetValidation.are_hostile(player_tower, enemy_unit)
	)
	_expect(
		failures,
		"player tower not hostile to player unit",
		not CombatTargetValidation.are_hostile(player_tower, player_unit)
	)
	_expect(
		failures,
		"enemy tower hostile to player unit",
		CombatTargetValidation.are_hostile(enemy_tower, player_unit)
	)
	_expect(
		failures,
		"enemy tower not hostile to enemy unit",
		not CombatTargetValidation.are_hostile(enemy_tower, ally_enemy_unit)
	)
	_expect(
		failures,
		"neutral hostile to player",
		CombatTargetValidation.are_hostile(neutral_creep, player_unit)
	)
	_expect(
		failures,
		"neutral hostile to enemy",
		CombatTargetValidation.are_hostile(neutral_creep, enemy_unit)
	)
	_expect(
		failures,
		"player hostile to neutral",
		CombatTargetValidation.are_hostile(player_unit, neutral_creep)
	)
	_expect(
		failures,
		"enemy hostile to neutral",
		CombatTargetValidation.are_hostile(enemy_unit, neutral_creep)
	)
	_expect(
		failures,
		"dead enemy ignored",
		not CombatTargetValidation.are_hostile(player_tower, dead_enemy)
	)

	var player_tower_target: Node3D = (
		CombatTargetValidation.find_closest_tower_attack_target_in_range(player_tower, 15.0)
	)
	_expect(failures, "player tower acquires enemy unit", player_tower_target == enemy_unit)

	var enemy_tower_target: Node3D = (
		CombatTargetValidation.find_closest_tower_attack_target_in_range(enemy_tower, 15.0)
	)
	_expect(failures, "enemy tower acquires player unit", enemy_tower_target == player_unit)

	_expect(
		failures,
		"player tower rejects ally via is_tower_attack_target",
		not CombatTargetValidation.is_tower_attack_target(player_tower, player_unit)
	)
	_expect(
		failures,
		"enemy tower rejects ally via is_tower_attack_target",
		not CombatTargetValidation.is_tower_attack_target(enemy_tower, ally_enemy_unit)
	)

	var ally_health_before: int = _get_health(player_unit)
	var hostile_applied: bool = CombatTargetValidation.apply_damage_to_target(
		enemy_unit, 5.0, player_tower
	)
	var friendly_blocked: bool = not CombatTargetValidation.apply_damage_to_target(
		player_unit, 5.0, player_tower
	)
	_expect(failures, "hostile damage applied", hostile_applied)
	_expect(failures, "friendly fire blocked", friendly_blocked)
	_expect(failures, "ally health unchanged", _get_health(player_unit) == ally_health_before)

	var player_groups: Array[StringName] = CombatTargetValidation.get_hostile_search_groups(
		player_tower
	)
	var enemy_groups: Array[StringName] = CombatTargetValidation.get_hostile_search_groups(enemy_tower)
	_expect(failures, "player search includes enemies", player_groups.has(&"enemies"))
	_expect(failures, "enemy search includes units", enemy_groups.has(&"units"))
	_expect(failures, "enemy search excludes enemies group", not enemy_groups.has(&"enemies"))

	var player_hp_before_splash: int = _get_health(player_unit)
	var ally_hp_before_splash: int = _get_health(ally_enemy_unit)
	SplashDamage.apply_radial_damage(
		get_tree(),
		player_unit.global_position,
		enemy_tower,
		10.0,
		5.0,
		1.0
	)
	_expect(
		failures,
		"enemy splash damages player unit",
		_get_health(player_unit) < player_hp_before_splash
	)
	_expect(
		failures,
		"enemy splash skips allied enemy",
		_get_health(ally_enemy_unit) == ally_hp_before_splash
	)

	var enemy_hp_before: int = _get_health(enemy_unit)
	var player_hp_before: int = _get_health(player_unit)
	SplashDamage.apply_radial_damage(
		get_tree(),
		enemy_unit.global_position,
		player_tower,
		10.0,
		5.0,
		1.0
	)
	_expect(
		failures,
		"player splash damages enemy unit",
		_get_health(enemy_unit) < enemy_hp_before
	)
	_expect(
		failures,
		"player splash skips player unit",
		_get_health(player_unit) == player_hp_before
	)

	var msg: String
	var exit_code: int = 0
	if failures.is_empty():
		msg = "PASS: faction-relative targeting verified for towers, hostility, splash, neutrals"
	else:
		exit_code = 1
		msg = "FAIL:\n- " + "\n- ".join(failures)

	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report:
		report.store_string(msg)
		report.close()
	print(msg)
	if exit_code != 0:
		push_error(msg)

	get_tree().quit(exit_code)


func _make_combat_stub(
	stub_name: String, position: Vector3, groups: Array[StringName]
) -> Node3D:
	var stub: Node3D = STUB_SCRIPT.new() as Node3D
	stub.name = stub_name
	add_child(stub)
	stub.global_position = position
	for group_name: StringName in groups:
		stub.add_to_group(group_name)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100
	stub.add_child(health)
	return stub


func _set_health(node: Node3D, value: int) -> void:
	var health: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.current_health = value


func _get_health(node: Node3D) -> int:
	var health: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return 0
	return health.current_health


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
