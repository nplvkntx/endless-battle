extends Control

## Shows worker build actions when at least one Worker is selected.

@export var selection_manager_path: NodePath = "../../SelectionManager"
@export var build_manager_path: NodePath = "../../BuildManager"

@onready var _build_farm_button: Button = $BuildFarmButton


func _ready() -> void:
	_build_farm_button.visible = false
	_build_farm_button.pressed.connect(_on_build_farm_pressed)

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(selection_manager.selected_units)


func _on_selection_changed(units: Array[Unit]) -> void:
	var has_worker: bool = false
	for unit: Unit in units:
		if unit is Worker:
			has_worker = true
			break

	_build_farm_button.visible = has_worker


func _on_build_farm_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_farm_placement()
