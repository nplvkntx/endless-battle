extends PanelContainer

## RTS bottom command bar shell; visible while selection info or commands are shown.

@onready var _selection_info: Control = $HBoxContainer/SelectionInfoPanel
@onready var _command_panel: Control = $HBoxContainer/SelectionCommandPanel


func _ready() -> void:
	visible = false
	_selection_info.visibility_changed.connect(_sync_visibility)
	_command_panel.visibility_changed.connect(_sync_visibility)


func _sync_visibility() -> void:
	visible = _selection_info.visible or _command_panel.visible
