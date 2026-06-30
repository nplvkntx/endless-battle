extends Label

## Temporary HUD message for blocked training and other player feedback.

const DISPLAY_SECONDS := 2.5

var _message_id: int = 0


func _ready() -> void:
	visible = false
	ResourceManager.feedback_message.connect(_on_feedback_message)


func _on_feedback_message(message: String) -> void:
	_message_id += 1
	var current_id: int = _message_id
	text = message
	modulate.a = 1.0
	visible = true

	await get_tree().create_timer(DISPLAY_SECONDS).timeout

	if current_id == _message_id:
		visible = false
