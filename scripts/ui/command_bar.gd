extends PanelContainer

## Permanent RTS bottom HUD shell; hidden when nothing is selected.

@export var selection_manager_path: NodePath = "../../../SelectionManager"

@onready var _legacy_command_panel: Control = (
	$MarginContainer/HBoxContainer/CommandPanel/MarginContainer/VBoxContainer/SelectionCommandPanel
)
@onready var _command_button_grid: Control = (
	$MarginContainer/HBoxContainer/CommandPanel/MarginContainer/VBoxContainer/CommandButtonGrid
)


func _ready() -> void:
	visible = false
	_legacy_command_panel.visibility_changed.connect(_sync_command_grid)

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	_refresh_frame_visibility()


func _on_selection_changed(_units: Array[Unit]) -> void:
	_refresh_frame_visibility()


func _on_building_selection_changed(_building: Building) -> void:
	_refresh_frame_visibility()


func _refresh_frame_visibility() -> void:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		visible = false
		return

	var has_selection: bool = (
		not selection_manager.selected_units.is_empty()
		or selection_manager.selected_building != null
	)
	visible = has_selection
	if visible:
		_sync_command_grid()


func _sync_command_grid() -> void:
	_command_button_grid.visible = not _legacy_command_panel.visible
