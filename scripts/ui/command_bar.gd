extends PanelContainer

## Permanent RTS bottom HUD shell; hides placeholder command grid when legacy commands show.

@onready var _legacy_command_panel: Control = (
	$MarginContainer/HBoxContainer/CommandPanel/MarginContainer/VBoxContainer/SelectionCommandPanel
)
@onready var _command_button_grid: Control = (
	$MarginContainer/HBoxContainer/CommandPanel/MarginContainer/VBoxContainer/CommandButtonGrid
)


func _ready() -> void:
	_legacy_command_panel.visibility_changed.connect(_sync_command_grid)
	_sync_command_grid()


func _sync_command_grid() -> void:
	_command_button_grid.visible = not _legacy_command_panel.visible
