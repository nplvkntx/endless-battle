extends Node

## Cross-scene navigation and match reset for menu, restart, and end screens.
## Scene reload destroys units, buildings, projectiles, and scene AI managers.
## Autoload/static runtime state is wiped via registered reset callbacks.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE := "res://scenes/main.tscn"

var last_match_result: String = ""
## AI-only match setting chosen in Create Match. Survives rematch; not wiped by prepare.
var ai_difficulty: int = AIDifficultyConfig.DEFAULT_DIFFICULTY


func set_ai_difficulty(difficulty: int) -> void:
	ai_difficulty = AIDifficultyConfig.clamp_difficulty(difficulty)


func get_ai_difficulty() -> int:
	return AIDifficultyConfig.clamp_difficulty(ai_difficulty)


func get_ai_difficulty_name() -> String:
	return AIDifficultyConfig.display_name(ai_difficulty)


## Owners register once; prepare_new_match() invokes every callback.
var _match_resetters: Array[Callable] = []
var _match_resetter_ids: Dictionary = {}


func _ready() -> void:
	_register_static_match_resets()


## Register a match-scoped wipe. Prefer this over growing hardcoded calls in prepare.
func register_match_reset(id: StringName, resetter: Callable) -> void:
	if _match_resetter_ids.has(id):
		return

	if not resetter.is_valid():
		push_warning("MatchSession: invalid match resetter for %s" % String(id))
		return

	_match_resetter_ids[id] = true
	_match_resetters.append(resetter)


func registered_match_reset_count() -> int:
	return _match_resetters.size()


func prepare_new_match() -> void:
	## Called from MatchBootstrap when main.tscn loads. Guarantees a clean slate.
	get_tree().paused = false
	for resetter: Callable in _match_resetters:
		if resetter.is_valid():
			resetter.call()
	if OS.is_debug_build():
		_verify_clean_match_state()


func start_match() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MATCH_SCENE)


func restart_match() -> void:
	## Reloads the match scene; MatchBootstrap then calls prepare_new_match().
	start_match()


func go_to_main_menu() -> void:
	get_tree().paused = false
	TooltipManager.hide_tooltip()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func quit_game() -> void:
	get_tree().quit()


func show_victory_screen() -> void:
	_go_to_main_menu_with_result("Victory!")


func show_defeat_screen() -> void:
	_go_to_main_menu_with_result("Defeat!")


func _go_to_main_menu_with_result(result_message: String) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	## End-of-match navigation only. Persistent state is reset on the next prepare_new_match().
	TooltipManager.hide_tooltip()
	InputManager.disarm_all_command_modes()
	last_match_result = result_message
	tree.paused = false
	tree.change_scene_to_file(MAIN_MENU_SCENE)


func _register_static_match_resets() -> void:
	## Static utility classes cannot self-register from _ready; list them once here.
	register_match_reset(&"HeroProgressionStore", HeroProgressionStore.clear)
	register_match_reset(&"AIHeroMastery", AIHeroMastery.reset_match_state)
	register_match_reset(&"EnemyArmyCommand", EnemyArmyCommand.reset_match_state)
	register_match_reset(&"EnemyAIDebug", EnemyAIDebug.reset_match_state)
	register_match_reset(&"CombatTargetValidation", CombatTargetValidation.reset_match_state)
	register_match_reset(&"WorkerAiUnstuck", WorkerAiUnstuck.reset_match_state)
	register_match_reset(&"WorkerGathering", WorkerGathering.reset_match_state)
	register_match_reset(&"CreepCampSafety", CreepCampSafety.reset_match_state)
	register_match_reset(&"ConstructionReservations", ConstructionReservations.reset_match_state)
	register_match_reset(&"BuildingDamageFxPool", BuildingDamageFxPool.reset_match_state)
	register_match_reset(&"DeathFxPool", DeathFxPool.reset_match_state)
	register_match_reset(&"ImpactFxPool", ImpactFxPool.reset_match_state)


## Debug-only: fail loudly if any known persistent match state survived prepare.
func _verify_clean_match_state() -> void:
	var failures: PackedStringArray = PackedStringArray()

	if ResourceManager.gold != MatchConfig.NORMAL_STARTING_GOLD:
		failures.append("ResourceManager.gold")
	if ResourceManager.wood != MatchConfig.NORMAL_STARTING_WOOD:
		failures.append("ResourceManager.wood")
	if ResourceManager.food_current != MatchConfig.HUMAN_STARTING_FOOD:
		failures.append("ResourceManager.food_current")
	if ResourceManager.food_max != MatchConfig.HUMAN_STARTING_FOOD_MAX:
		failures.append("ResourceManager.food_max")

	if EnemyResourceManager.gold != MatchConfig.NORMAL_STARTING_GOLD:
		failures.append("EnemyResourceManager.gold")
	if EnemyResourceManager.wood != MatchConfig.NORMAL_STARTING_WOOD:
		failures.append("EnemyResourceManager.wood")

	for upgrade_id: StringName in UpgradeManager.BLACKSMITH_UPGRADE_ORDER:
		if UpgradeManager.get_level(upgrade_id) != 0:
			failures.append("UpgradeManager.player.%s" % String(upgrade_id))
		if UpgradeManager.get_enemy_level(upgrade_id) != 0:
			failures.append("UpgradeManager.enemy.%s" % String(upgrade_id))
	for upgrade_id: StringName in UpgradeManager.ACADEMY_UPGRADE_ORDER:
		if UpgradeManager.get_level(upgrade_id) != 0:
			failures.append("UpgradeManager.player.%s" % String(upgrade_id))
		if UpgradeManager.get_enemy_level(upgrade_id) != 0:
			failures.append("UpgradeManager.enemy.%s" % String(upgrade_id))
	for upgrade_id: StringName in UpgradeManager.STABLE_UPGRADE_ORDER:
		if UpgradeManager.get_level(upgrade_id) != 0:
			failures.append("UpgradeManager.player.%s" % String(upgrade_id))
		if UpgradeManager.get_enemy_level(upgrade_id) != 0:
			failures.append("UpgradeManager.enemy.%s" % String(upgrade_id))

	if InputManager.attack_move_armed:
		failures.append("InputManager.attack_move_armed")
	if ControlGroupManager.has_any_members():
		failures.append("ControlGroupManager.groups")
	if ControlGroupManager.get_active_group_index() >= 0:
		failures.append("ControlGroupManager.active_group")
	if HeroProgressionStore.has_saved_progression():
		failures.append("HeroProgressionStore.player")
	if HeroProgressionStore.has_saved_enemy_progression():
		failures.append("HeroProgressionStore.enemy")
	if HeroProgressionStore.has_locked_kit(false):
		failures.append("HeroProgressionStore.player_lock")
	if HeroProgressionStore.has_locked_kit(true):
		failures.append("HeroProgressionStore.enemy_lock")
	if HeroProgressionStore.has_living_hero(false):
		failures.append("HeroProgressionStore.player_living_hero")
	if HeroProgressionStore.has_living_hero(true):
		failures.append("HeroProgressionStore.enemy_living_hero")
	if EnemyArmyCommand.get_army_mode() != EnemyArmyCommand.ArmyMode.IDLE:
		failures.append("EnemyArmyCommand.army_mode")
	if (
		EnemyArmyCommand.get_strategic_state()
		!= EnemyArmyCommand.StrategicState.ECONOMY
	):
		failures.append("EnemyArmyCommand.strategic_state")
	if registered_match_reset_count() <= 0:
		failures.append("MatchSession.resetters_empty")

	if not failures.is_empty():
		push_error(
			"MatchSession: unclean match state after prepare_new_match: %s"
			% ", ".join(failures)
		)
