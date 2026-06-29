extends Control

## Shows context actions for the current selection (worker build, town center training).

@export var selection_manager_path: NodePath = "../../SelectionManager"
@export var build_manager_path: NodePath = "../../BuildManager"

@onready var _build_farm_button: Button = $ButtonsRow/BuildFarmButton
@onready var _build_barracks_button: Button = $ButtonsRow/BuildBarracksButton
@onready var _train_worker_button: Button = $ButtonsRow/TrainWorkerButton
@onready var _worker_queue_label: Label = $WorkerQueueLabel

var _selected_command_center: CommandCenter = null


func _ready() -> void:
	_build_farm_button.visible = false
	_build_barracks_button.visible = false
	_train_worker_button.visible = false
	_worker_queue_label.visible = false
	_build_farm_button.pressed.connect(_on_build_farm_pressed)
	_build_barracks_button.pressed.connect(_on_build_barracks_pressed)
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
	_build_barracks_button.visible = has_worker


func _on_building_selection_changed(building: Building) -> void:
	_disconnect_queue_signal()
	_selected_command_center = building as CommandCenter if building is CommandCenter else null
	_train_worker_button.visible = _selected_command_center != null
	_worker_queue_label.visible = _selected_command_center != null

	if _selected_command_center != null:
		_selected_command_center.worker_queue_changed.connect(_on_worker_queue_changed)
		_on_worker_queue_changed(_selected_command_center.get_worker_queue_count())
	else:
		_worker_queue_label.text = "Worker Queue: 0"


func _on_worker_queue_changed(queue_count: int) -> void:
	_worker_queue_label.text = "Worker Queue: %d" % queue_count


func _disconnect_queue_signal() -> void:
	if _selected_command_center == null:
		return

	if _selected_command_center.worker_queue_changed.is_connected(_on_worker_queue_changed):
		_selected_command_center.worker_queue_changed.disconnect(_on_worker_queue_changed)


func _on_build_farm_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_farm_placement()


func _on_build_barracks_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_barracks_placement()


func _on_train_worker_pressed() -> void:
	if _selected_command_center == null:
		return

	_selected_command_center.try_train_worker()
