extends Control

## Shows context actions for the current selection (worker build, town center training).

@export var selection_manager_path: NodePath = "../../SelectionManager"
@export var build_manager_path: NodePath = "../../BuildManager"

@onready var _build_farm_button: Button = $BuildFarmButton
@onready var _train_worker_button: Button = $TrainWorkerButton

var _selected_command_center: CommandCenter = null


func _ready() -> void:
	_build_farm_button.visible = false
	_train_worker_button.visible = false
	_build_farm_button.pressed.connect(_on_build_farm_pressed)
	_train_worker_button.pressed.connect(_on_train_worker_pressed)

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	_on_selection_changed(selection_manager.selected_units)
	_on_building_selection_changed(selection_manager.selected_building)


func _on_selection_changed(units: Array[Unit]) -> void:
	var has_worker: bool = false
	for unit: Unit in units:
		if unit is Worker:
			has_worker = true
			break

	_build_farm_button.visible = has_worker


func _on_building_selection_changed(building: Building) -> void:
	_selected_command_center = building as CommandCenter if building is CommandCenter else null
	_train_worker_button.visible = _selected_command_center != null


func _on_build_farm_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_farm_placement()


func _on_train_worker_pressed() -> void:
	if _selected_command_center == null:
		return

	_selected_command_center.try_train_worker()
