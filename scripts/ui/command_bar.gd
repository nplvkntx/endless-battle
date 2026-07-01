extends PanelContainer

## Compact bottom-center command bar; hidden when nothing is selected.

@export var selection_manager_path: NodePath = "../../../SelectionManager"

@onready var _legacy_command_panel: Control = $MarginContainer/VBoxContainer/SelectionCommandPanel
@onready var _command_button_grid: Control = $MarginContainer/VBoxContainer/CommandButtonGrid

const _PLACEHOLDER_HOTKEYS: Array[String] = ["Q", "W", "E", "R", "A", "S", "H", "M", "", ""]


func _ready() -> void:
	visible = false
	_legacy_command_panel.visibility_changed.connect(_sync_command_grid)
	_setup_placeholder_hotkeys()

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	_refresh_frame_visibility()


func _setup_placeholder_hotkeys() -> void:
	for index in range(_command_button_grid.get_child_count()):
		var button: Button = _command_button_grid.get_child(index) as Button
		if button == null:
			continue

		if index < _PLACEHOLDER_HOTKEYS.size() and not _PLACEHOLDER_HOTKEYS[index].is_empty():
			button.text = _PLACEHOLDER_HOTKEYS[index]
		else:
			button.text = ""


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
