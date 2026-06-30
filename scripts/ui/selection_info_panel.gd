extends PanelContainer

## Shows basic name, type, and health info for the current selection.

@export var selection_manager_path: NodePath = "../../SelectionManager"

@onready var _name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var _type_label: Label = $MarginContainer/VBoxContainer/TypeLabel
@onready var _health_label: Label = $MarginContainer/VBoxContainer/HealthLabel

var _tracked_health_component: HealthComponent = null


func _ready() -> void:
	visible = false

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	_refresh_panel()


func _on_selection_changed(_units: Array[Unit]) -> void:
	_refresh_panel()


func _on_building_selection_changed(_building: Building) -> void:
	_refresh_panel()


func _refresh_panel() -> void:
	_clear_health_tracking()

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		_hide_panel()
		return

	var selected_building: Building = selection_manager.selected_building
	if selected_building != null:
		_show_building_info(selected_building)
		return

	var selected_units: Array[Unit] = selection_manager.selected_units
	if selected_units.is_empty():
		_hide_panel()
		return

	if selected_units.size() > 1:
		_show_multiple_units()
		return

	_show_unit_info(selected_units[0])


func _show_multiple_units() -> void:
	visible = true
	_name_label.text = "Multiple units selected"
	_type_label.visible = false
	_health_label.visible = false


func _show_unit_info(unit: Unit) -> void:
	var info: Dictionary = _get_unit_info(unit)
	if info.is_empty():
		_hide_panel()
		return

	visible = true
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_configure_health_display(unit)


func _show_building_info(building: Building) -> void:
	var info: Dictionary = _get_building_info(building)
	if info.is_empty():
		_hide_panel()
		return

	visible = true
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_configure_health_display(building)


func _configure_health_display(node: Node) -> void:
	var health_component: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		_health_label.visible = false
		return

	_tracked_health_component = health_component
	health_component.health_changed.connect(_on_tracked_health_changed)
	_update_health_label(health_component.current_health, health_component.max_health)
	_health_label.visible = true


func _update_health_label(current_health: int, max_health: int) -> void:
	_health_label.text = "Health: %d / %d" % [current_health, max_health]


func _on_tracked_health_changed(current_health: int, max_health: int) -> void:
	_update_health_label(current_health, max_health)


func _clear_health_tracking() -> void:
	if (
		_tracked_health_component != null
		and _tracked_health_component.health_changed.is_connected(_on_tracked_health_changed)
	):
		_tracked_health_component.health_changed.disconnect(_on_tracked_health_changed)
	_tracked_health_component = null


func _hide_panel() -> void:
	visible = false


func _get_unit_info(unit: Unit) -> Dictionary:
	if unit is Swordsman:
		return {"name": "Swordsman", "type": "Unit"}
	if unit is Archer:
		return {"name": "Archer", "type": "Unit"}
	if unit is Worker:
		return {"name": "Worker", "type": "Unit"}
	if unit is EnemyDummy:
		return {"name": "Enemy Dummy", "type": "Unit"}
	return {}


func _get_building_info(building: Building) -> Dictionary:
	if building is CommandCenter:
		return {"name": "Town Center", "type": "Building"}
	if building is Barracks:
		return {"name": "Barracks", "type": "Building"}
	if building is Farm:
		return {"name": "Farm", "type": "Building"}
	if building is Tower:
		return {"name": "Tower", "type": "Building"}
	return {}
