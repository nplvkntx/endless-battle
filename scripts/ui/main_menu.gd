extends Control

@onready var _result_label: Label = $CenterContainer/VBoxContainer/ResultLabel


func _ready() -> void:
	$CenterContainer/VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	_apply_match_result()


func _apply_match_result() -> void:
	var result_message := MatchSession.last_match_result
	if result_message.is_empty():
		_result_label.visible = false
		return

	_result_label.text = result_message
	_result_label.visible = true


func _on_play_pressed() -> void:
	MatchSession.last_match_result = ""
	MatchSession.start_match()


func _on_quit_pressed() -> void:
	MatchSession.quit_game()
