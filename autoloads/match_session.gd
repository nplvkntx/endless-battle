extends Node

## Cross-scene navigation and match reset for menu, restart, and end screens.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE := "res://scenes/main.tscn"

var last_match_result: String = ""


func prepare_new_match() -> void:
	get_tree().paused = false
	ResourceManager.reset_to_starting_values()
	EnemyResourceManager.reset_to_starting_values()
	HeroProgressionStore.clear()


func start_match() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MATCH_SCENE)


func restart_match() -> void:
	start_match()


func go_to_main_menu() -> void:
	get_tree().paused = false
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

	TooltipManager.hide_tooltip()
	last_match_result = result_message
	tree.paused = false
	tree.change_scene_to_file(MAIN_MENU_SCENE)
