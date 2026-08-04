extends Control

@onready var _result_label: Label = $CenterContainer/VBoxContainer/ResultLabel
@onready var _easy_button: Button = $CenterContainer/VBoxContainer/DifficultyRow/EasyButton
@onready var _normal_button: Button = $CenterContainer/VBoxContainer/DifficultyRow/NormalButton
@onready var _hard_button: Button = $CenterContainer/VBoxContainer/DifficultyRow/HardButton


func _ready() -> void:
	$CenterContainer/VBoxContainer/StartMatchButton.pressed.connect(_on_start_match_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	_easy_button.pressed.connect(_on_difficulty_pressed.bind(AIDifficultyConfig.Difficulty.EASY))
	_normal_button.pressed.connect(_on_difficulty_pressed.bind(AIDifficultyConfig.Difficulty.NORMAL))
	_hard_button.pressed.connect(_on_difficulty_pressed.bind(AIDifficultyConfig.Difficulty.HARD))
	_apply_match_result()
	_refresh_difficulty_buttons()


func _apply_match_result() -> void:
	var result_message := MatchSession.last_match_result
	if result_message.is_empty():
		_result_label.visible = false
		return

	_result_label.text = result_message
	_result_label.visible = true


func _on_difficulty_pressed(difficulty: int) -> void:
	MatchSession.set_ai_difficulty(difficulty)
	_refresh_difficulty_buttons()


func _refresh_difficulty_buttons() -> void:
	var selected: int = MatchSession.get_ai_difficulty()
	_easy_button.button_pressed = selected == AIDifficultyConfig.Difficulty.EASY
	_normal_button.button_pressed = selected == AIDifficultyConfig.Difficulty.NORMAL
	_hard_button.button_pressed = selected == AIDifficultyConfig.Difficulty.HARD


func _on_start_match_pressed() -> void:
	MatchSession.last_match_result = ""
	MatchSession.set_ai_difficulty(MatchSession.get_ai_difficulty())
	MatchSession.start_match()


func _on_quit_pressed() -> void:
	MatchSession.quit_game()
