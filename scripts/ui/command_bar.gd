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
	if selection_manager.has_signal("inspection_changed"):
		selection_manager.inspection_changed.connect(_on_inspection_changed)
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


func _on_inspection_changed(_unit: Unit, _building: Building) -> void:
	_refresh_frame_visibility()


func _refresh_frame_visibility() -> void:
	call_deferred("_apply_frame_visibility")


func _apply_frame_visibility() -> void:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		visible = false
		return

	visible = _selection_has_commands(selection_manager)
	if visible:
		_sync_command_grid()
	else:
		_command_button_grid.visible = false


func _selection_has_commands(selection_manager: Node) -> bool:
	if selection_manager.inspected_resource != null:
		return false

	if selection_manager.inspected_unit != null or selection_manager.inspected_building != null:
		return false

	if not selection_manager.selected_units.is_empty():
		return selection_manager.has_commandable_selected_units()

	var building: Building = selection_manager.selected_building
	if building == null:
		return false

	if building is CommandCenter:
		return true

	if building is Barracks:
		return (building as Barracks).building_state == Building.STATE_COMPLETED

	if building is HeroAltar:
		return (building as HeroAltar).building_state == Building.STATE_COMPLETED

	if building is Blacksmith:
		return (building as Blacksmith).can_research()

	if building is Shop:
		return (building as Shop).can_show_purchase_ui()

	return false


func _sync_command_grid() -> void:
	_command_button_grid.visible = false
