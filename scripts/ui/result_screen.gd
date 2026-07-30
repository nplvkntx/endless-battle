extends Control

@export var title_text: String = "Victory"

@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var _restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var _main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton
@onready var _quit_button: Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_title_label.text = title_text

	_restart_button.pressed.connect(_on_restart_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_restart_pressed() -> void:
	MatchSession.restart_match()


func _on_main_menu_pressed() -> void:
	MatchSession.go_to_main_menu()


func _on_quit_pressed() -> void:
	MatchSession.quit_game()
