extends Control

## Shows context actions for the current selection (worker build, town center training).

@export var selection_manager_path: NodePath = "../../SelectionManager"
@export var build_manager_path: NodePath = "../../BuildManager"

@onready var _barracks_panel: VBoxContainer = $BarracksPanel
@onready var _build_farm_button: Button = $ButtonsRow/BuildFarmButton
@onready var _build_barracks_button: Button = $ButtonsRow/BuildBarracksButton
@onready var _build_tower_button: Button = $ButtonsRow/BuildTowerButton
@onready var _train_worker_button: Button = $ButtonsRow/TrainWorkerButton
@onready var _train_swordsman_button: Button = $BarracksPanel/BarracksTrainingRow/TrainSwordsmanButton
@onready var _train_archer_button: Button = $BarracksPanel/BarracksTrainingRow/TrainArcherButton
@onready var _worker_queue_label: Label = $WorkerQueueLabel
@onready var _swordsman_queue_label: Label = $BarracksPanel/BarracksQueuesRow/SwordsmanQueueLabel
@onready var _archer_queue_label: Label = $BarracksPanel/BarracksQueuesRow/ArcherQueueLabel

var _selected_command_center: CommandCenter = null
var _selected_barracks: Barracks = null
var _tracked_barracks: Barracks = null


func _ready() -> void:
	_barracks_panel.visible = false
	_build_farm_button.visible = false
	_build_barracks_button.visible = false
	_build_tower_button.visible = false
	_train_worker_button.visible = false
	_worker_queue_label.visible = false
	_set_barracks_button_labels()
	_build_farm_button.pressed.connect(_on_build_farm_pressed)
	_build_barracks_button.pressed.connect(_on_build_barracks_pressed)
	_build_tower_button.pressed.connect(_on_build_tower_pressed)
	_train_worker_button.pressed.connect(_on_train_worker_pressed)
	_train_swordsman_button.pressed.connect(_on_train_swordsman_pressed)
	_train_archer_button.pressed.connect(_on_train_archer_pressed)

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	_on_building_selection_changed(selection_manager.selected_building)
	_on_selection_changed(selection_manager.selected_units)


func _set_barracks_button_labels() -> void:
	var cost_label := " (%d Gold, %d Food)" % [Barracks.TRAIN_GOLD_COST, Barracks.TRAIN_FOOD_COST]
	_train_swordsman_button.text = "Train Swordsman%s" % cost_label
	_train_archer_button.text = "Train Archer%s" % cost_label


func _on_selection_changed(_units: Array[Unit]) -> void:
	_refresh_command_visibility()


func _on_building_selection_changed(building: Building) -> void:
	_disconnect_worker_queue_signal()
	_disconnect_barracks_signals()
	_selected_command_center = null

	if building is CommandCenter:
		_selected_command_center = building as CommandCenter
		_selected_command_center.worker_queue_changed.connect(_on_worker_queue_changed)
		_on_worker_queue_changed(_selected_command_center.get_worker_queue_count())
	else:
		_worker_queue_label.text = "Worker Queue: 0"

	if building is Barracks:
		_tracked_barracks = building as Barracks
		_tracked_barracks.building_state_changed.connect(_on_barracks_state_changed)
		_tracked_barracks.swordsman_queue_changed.connect(_on_swordsman_queue_changed)
		_tracked_barracks.archer_queue_changed.connect(_on_archer_queue_changed)
		_on_swordsman_queue_changed(_tracked_barracks.get_swordsman_queue_count())
		_on_archer_queue_changed(_tracked_barracks.get_archer_queue_count())
	else:
		_swordsman_queue_label.text = "Swordsman Queue: 0"
		_archer_queue_label.text = "Archer Queue: 0"

	_refresh_command_visibility()


func _on_barracks_state_changed(_state: StringName) -> void:
	_refresh_command_visibility()


func _refresh_command_visibility() -> void:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	var has_worker: bool = false
	for unit: Unit in selection_manager.selected_units:
		if unit is Worker:
			has_worker = true
			break

	var selected_building: Building = selection_manager.selected_building
	var show_barracks_training: bool = (
		selected_building is Barracks
		and (selected_building as Barracks).building_state == Building.STATE_COMPLETED
	)

	_selected_barracks = selected_building as Barracks if show_barracks_training else null

	_barracks_panel.visible = show_barracks_training
	_build_farm_button.visible = has_worker
	_build_barracks_button.visible = has_worker
	_build_tower_button.visible = has_worker
	_train_worker_button.visible = _selected_command_center != null
	_worker_queue_label.visible = _selected_command_center != null


func _on_worker_queue_changed(queue_count: int) -> void:
	_worker_queue_label.text = "Worker Queue: %d" % queue_count


func _on_swordsman_queue_changed(queue_count: int) -> void:
	_swordsman_queue_label.text = "Swordsman Queue: %d" % queue_count


func _on_archer_queue_changed(queue_count: int) -> void:
	_archer_queue_label.text = "Archer Queue: %d" % queue_count


func _disconnect_worker_queue_signal() -> void:
	if _selected_command_center == null:
		return

	if _selected_command_center.worker_queue_changed.is_connected(_on_worker_queue_changed):
		_selected_command_center.worker_queue_changed.disconnect(_on_worker_queue_changed)

	_selected_command_center = null


func _disconnect_barracks_signals() -> void:
	if _tracked_barracks == null:
		return

	if _tracked_barracks.building_state_changed.is_connected(_on_barracks_state_changed):
		_tracked_barracks.building_state_changed.disconnect(_on_barracks_state_changed)

	if _tracked_barracks.swordsman_queue_changed.is_connected(_on_swordsman_queue_changed):
		_tracked_barracks.swordsman_queue_changed.disconnect(_on_swordsman_queue_changed)

	if _tracked_barracks.archer_queue_changed.is_connected(_on_archer_queue_changed):
		_tracked_barracks.archer_queue_changed.disconnect(_on_archer_queue_changed)

	_tracked_barracks = null


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


func _on_build_tower_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_tower_placement()


func _on_train_worker_pressed() -> void:
	if _selected_command_center == null:
		return

	_selected_command_center.try_train_worker()


func _on_train_swordsman_pressed() -> void:
	if _selected_barracks == null:
		return

	_selected_barracks.try_train_swordsman()


func _on_train_archer_pressed() -> void:
	if _selected_barracks == null:
		return

	_selected_barracks.try_train_archer()
