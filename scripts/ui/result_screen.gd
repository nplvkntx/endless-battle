extends Control

@export var title_text: String = "Victory"

@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var _restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var _main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton
@onready var _quit_button: Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Result screen loaded: ", title_text)

	_title_label.text = title_text

	_restart_button.mouse_entered.connect(func() -> void: print("RESTART HOVER"))
	_main_menu_button.mouse_entered.connect(func() -> void: print("MAIN MENU HOVER"))
	_quit_button.mouse_entered.connect(func() -> void: print("QUIT HOVER"))

	_restart_button.pressed.connect(_on_restart_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
