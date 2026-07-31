extends Node

## Headless check: dirty persistent state, prepare twice, compare clean snapshots.
## Run:
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_match_reset.tscn

const REPORT_PATH := "user://match_reset_verify_result.txt"

var _dirty_control_group_unit: Node = null


func _ready() -> void:
	var exit_code: int = 0
	MatchSession._register_static_match_resets()

	_dirty_persistent_match_state()
	MatchSession.prepare_new_match()
	var first_snapshot: Dictionary = _capture_persistent_snapshot()

	_dirty_persistent_match_state()
	MatchSession.prepare_new_match()
	var second_snapshot: Dictionary = _capture_persistent_snapshot()

	var msg: String = ""
	if not _snapshots_equal(first_snapshot, second_snapshot):
		msg = "FAIL: successive prepares differ\nFirst: %s\nSecond: %s" % [
			str(first_snapshot),
			str(second_snapshot),
		]
		exit_code = 1
	elif not bool(first_snapshot.get("is_clean", false)):
		msg = "FAIL: prepared state is not clean\n%s" % str(first_snapshot)
		exit_code = 1
	else:
		msg = (
			"PASS: identical clean state across prepares (registry=%d)\n%s"
			% [MatchSession.registered_match_reset_count(), str(first_snapshot)]
		)

	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report:
		report.store_string(msg)
		report.close()
	print(msg)
	if exit_code != 0:
		push_error(msg)

	get_tree().quit(exit_code)


func _dirty_persistent_match_state() -> void:
	ResourceManager.gold = 9999
	ResourceManager.wood = 8888
	ResourceManager.food_current = 40
	ResourceManager.food_max = 99
	EnemyResourceManager.gold = 7777
	EnemyResourceManager.wood = 6666
	EnemyResourceManager.reserve_resources(50, 25)
	UpgradeManager.finish_research(UpgradeManager.UPGRADE_SWORDSMAN_ATTACK)
	UpgradeManager.finish_enemy_research(UpgradeManager.UPGRADE_ARCHER_ATTACK)
	UpgradeManager.finish_academy_research(UpgradeManager.UPGRADE_FASTER_GATHERING)
	InputManager.arm_attack_move()
	if _dirty_control_group_unit != null and is_instance_valid(_dirty_control_group_unit):
		_dirty_control_group_unit.queue_free()
		_dirty_control_group_unit = null
	_dirty_control_group_unit = load("res://scenes/units/swordsman.tscn").instantiate()
	add_child(_dirty_control_group_unit)
	ControlGroupManager.assign_group(0, [_dirty_control_group_unit])
	HeroProgressionStore._player_snapshot = {"level": 5}
	HeroProgressionStore._enemy_snapshot = {"level": 3}


func _capture_persistent_snapshot() -> Dictionary:
	var player_upgrades: Dictionary = {}
	var enemy_upgrades: Dictionary = {}
	for upgrade_id: StringName in UpgradeManager.BLACKSMITH_UPGRADE_ORDER:
		player_upgrades[String(upgrade_id)] = UpgradeManager.get_level(upgrade_id)
		enemy_upgrades[String(upgrade_id)] = UpgradeManager.get_enemy_level(upgrade_id)
	for upgrade_id: StringName in UpgradeManager.ACADEMY_UPGRADE_ORDER:
		player_upgrades[String(upgrade_id)] = UpgradeManager.get_level(upgrade_id)
		enemy_upgrades[String(upgrade_id)] = UpgradeManager.get_enemy_level(upgrade_id)
	for upgrade_id: StringName in UpgradeManager.STABLE_UPGRADE_ORDER:
		player_upgrades[String(upgrade_id)] = UpgradeManager.get_level(upgrade_id)
		enemy_upgrades[String(upgrade_id)] = UpgradeManager.get_enemy_level(upgrade_id)

	var all_upgrades_zero: bool = true
	for value: Variant in player_upgrades.values():
		if int(value) != 0:
			all_upgrades_zero = false
			break
	for value: Variant in enemy_upgrades.values():
		if int(value) != 0:
			all_upgrades_zero = false
			break

	var is_clean: bool = (
		ResourceManager.gold == MatchConfig.NORMAL_STARTING_GOLD
		and ResourceManager.wood == MatchConfig.NORMAL_STARTING_WOOD
		and ResourceManager.food_current == MatchConfig.HUMAN_STARTING_FOOD
		and ResourceManager.food_max == MatchConfig.HUMAN_STARTING_FOOD_MAX
		and EnemyResourceManager.gold == MatchConfig.NORMAL_STARTING_GOLD
		and EnemyResourceManager.wood == MatchConfig.NORMAL_STARTING_WOOD
		and EnemyResourceManager.get_spendable_gold() == EnemyResourceManager.gold
		and EnemyResourceManager.get_spendable_wood() == EnemyResourceManager.wood
		and all_upgrades_zero
		and not InputManager.attack_move_armed
		and not ControlGroupManager.has_any_members()
		and ControlGroupManager.get_active_group_index() < 0
		and not HeroProgressionStore.has_saved_progression()
		and not HeroProgressionStore.has_saved_enemy_progression()
		and EnemyArmyCommand.get_army_mode() == EnemyArmyCommand.ArmyMode.IDLE
	)

	return {
		"is_clean": is_clean,
		"player_gold": ResourceManager.gold,
		"player_wood": ResourceManager.wood,
		"player_food": ResourceManager.food_current,
		"player_food_max": ResourceManager.food_max,
		"enemy_gold": EnemyResourceManager.gold,
		"enemy_wood": EnemyResourceManager.wood,
		"enemy_spendable_gold": EnemyResourceManager.get_spendable_gold(),
		"enemy_spendable_wood": EnemyResourceManager.get_spendable_wood(),
		"player_upgrades": player_upgrades,
		"enemy_upgrades": enemy_upgrades,
		"attack_move_armed": InputManager.attack_move_armed,
		"control_groups_empty": not ControlGroupManager.has_any_members(),
		"control_group_active": ControlGroupManager.get_active_group_index(),
		"hero_player_saved": HeroProgressionStore.has_saved_progression(),
		"hero_enemy_saved": HeroProgressionStore.has_saved_enemy_progression(),
		"army_mode": int(EnemyArmyCommand.get_army_mode()),
		"strategic_state": int(EnemyArmyCommand.get_strategic_state()),
	}


func _snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	return str(a) == str(b)
