extends PanelContainer

## Context-sensitive command panel for the current selection (build, train, attack).

@export var selection_manager_path: NodePath = "../../SelectionManager"
@export var build_manager_path: NodePath = "../../BuildManager"

@onready var _barracks_panel: VBoxContainer = $MarginContainer/VBoxContainer/BarracksPanel
@onready var _hero_altar_panel: VBoxContainer = $MarginContainer/VBoxContainer/HeroAltarPanel
@onready var _buttons_row: HBoxContainer = $MarginContainer/VBoxContainer/ButtonsRow
@onready var _build_farm_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/BuildFarmButton
@onready var _build_barracks_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/BuildBarracksButton
@onready var _build_tower_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/BuildTowerButton
@onready var _build_hero_altar_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/BuildHeroAltarButton
@onready var _train_worker_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/TrainWorkerButton
@onready var _attack_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/AttackButton
@onready var _train_swordsman_button: Button = (
	$MarginContainer/VBoxContainer/BarracksPanel/BarracksTrainingRow/TrainSwordsmanButton
)
@onready var _train_archer_button: Button = (
	$MarginContainer/VBoxContainer/BarracksPanel/BarracksTrainingRow/TrainArcherButton
)
@onready var _worker_queue_label: Label = $MarginContainer/VBoxContainer/WorkerQueueLabel
@onready var _swordsman_queue_label: Label = (
	$MarginContainer/VBoxContainer/BarracksPanel/BarracksQueuesRow/SwordsmanQueueLabel
)
@onready var _archer_queue_label: Label = (
	$MarginContainer/VBoxContainer/BarracksPanel/BarracksQueuesRow/ArcherQueueLabel
)
@onready var _train_hero_button: Button = (
	$MarginContainer/VBoxContainer/HeroAltarPanel/HeroAltarTrainingRow/TrainHeroButton
)
@onready var _hero_status_label: Label = (
	$MarginContainer/VBoxContainer/HeroAltarPanel/HeroStatusLabel
)

var _selected_command_center: CommandCenter = null
var _selected_barracks: Barracks = null
var _selected_hero_altar: HeroAltar = null
var _tracked_barracks: Barracks = null
var _tracked_hero_altar: HeroAltar = null


func _ready() -> void:
	visible = false
	_barracks_panel.visible = false
	_hero_altar_panel.visible = false
	_buttons_row.visible = false
	_build_farm_button.visible = false
	_build_barracks_button.visible = false
	_build_tower_button.visible = false
	_build_hero_altar_button.visible = false
	_train_worker_button.visible = false
	_attack_button.visible = false
	_worker_queue_label.visible = false
	_set_barracks_button_labels()
	_set_hero_altar_button_labels()
	_build_farm_button.pressed.connect(_on_build_farm_pressed)
	_build_barracks_button.pressed.connect(_on_build_barracks_pressed)
	_build_tower_button.pressed.connect(_on_build_tower_pressed)
	_build_hero_altar_button.pressed.connect(_on_build_hero_altar_pressed)
	_train_worker_button.pressed.connect(_on_train_worker_pressed)
	_train_swordsman_button.pressed.connect(_on_train_swordsman_pressed)
	_train_archer_button.pressed.connect(_on_train_archer_pressed)
	_train_hero_button.pressed.connect(_on_train_hero_pressed)
	_attack_button.pressed.connect(_on_attack_pressed)

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	_on_building_selection_changed(selection_manager.selected_building)
	_on_selection_changed(selection_manager.selected_units)


func _set_hero_altar_button_labels() -> void:
	var cost_label := " (%d Gold, %d Food)" % [HeroAltar.TRAIN_GOLD_COST, HeroAltar.TRAIN_FOOD_COST]
	_train_hero_button.text = "Train Hero%s" % cost_label


func _set_barracks_button_labels() -> void:
	var cost_label := " (%d Gold, %d Food)" % [Barracks.TRAIN_GOLD_COST, Barracks.TRAIN_FOOD_COST]
	_train_swordsman_button.text = "Train Swordsman%s" % cost_label
	_train_archer_button.text = "Train Archer%s" % cost_label


func _on_selection_changed(_units: Array[Unit]) -> void:
	_refresh_command_visibility()


func _on_building_selection_changed(building: Building) -> void:
	_disconnect_worker_queue_signal()
	_disconnect_barracks_signals()
	_disconnect_hero_altar_signals()
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

	if building is HeroAltar:
		_tracked_hero_altar = building as HeroAltar
		_tracked_hero_altar.building_state_changed.connect(_on_hero_altar_state_changed)
		_tracked_hero_altar.hero_altar_state_changed.connect(_on_hero_altar_state_changed)
		_update_hero_altar_status()
	else:
		_hero_status_label.text = "Hero: Ready to train"

	_refresh_command_visibility()


func _on_barracks_state_changed(_state: StringName) -> void:
	_refresh_command_visibility()


func _on_hero_altar_state_changed(_state: Variant = null) -> void:
	_update_hero_altar_status()
	_refresh_command_visibility()


func _update_hero_altar_status() -> void:
	if _tracked_hero_altar == null:
		return

	if _tracked_hero_altar.player_has_hero():
		_hero_status_label.text = "Hero: Already active"
	elif _tracked_hero_altar.is_training_hero():
		_hero_status_label.text = "Hero: Training..."
	else:
		_hero_status_label.text = "Hero: Ready to train"

	_train_hero_button.disabled = not _tracked_hero_altar.can_train_hero()


func _refresh_command_visibility() -> void:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		visible = false
		return

	var selected_units: Array[Unit] = selection_manager.selected_units
	var selected_building: Building = selection_manager.selected_building
	var nothing_selected: bool = selected_units.is_empty() and selected_building == null

	if nothing_selected:
		visible = false
		return

	var show_barracks_training: bool = (
		selected_building is Barracks
		and (selected_building as Barracks).building_state == Building.STATE_COMPLETED
	)
	var show_hero_altar_training: bool = (
		selected_building is HeroAltar
		and (selected_building as HeroAltar).building_state == Building.STATE_COMPLETED
	)
	var show_town_center_commands: bool = selected_building is CommandCenter

	_selected_barracks = selected_building as Barracks if show_barracks_training else null
	_selected_hero_altar = selected_building as HeroAltar if show_hero_altar_training else null

	if not selected_units.is_empty() and selected_building == null and selected_units.size() > 1:
		var multi_category: StringName = selection_manager.get_multi_unit_selection_category()
		if multi_category == &"workers":
			_apply_worker_command_visibility()
			visible = true
			return
		if multi_category == &"combat":
			_apply_combat_command_visibility()
			visible = true
			return
		visible = false
		return

	var single_worker: bool = selected_units.size() == 1 and selected_units[0] is Worker
	var single_combat_unit: bool = (
		selected_units.size() == 1
		and (selected_units[0] is Swordsman or selected_units[0] is Archer or selected_units[0] is Hero)
	)

	if single_worker:
		_apply_worker_command_visibility()
	elif single_combat_unit:
		_apply_combat_command_visibility()
	elif show_town_center_commands:
		_apply_town_center_command_visibility()
	else:
		_apply_hidden_command_buttons()

	_barracks_panel.visible = show_barracks_training
	_hero_altar_panel.visible = show_hero_altar_training
	_worker_queue_label.visible = show_town_center_commands

	if show_hero_altar_training:
		_update_hero_altar_status()

	visible = (
		single_worker
		or show_town_center_commands
		or show_barracks_training
		or show_hero_altar_training
		or single_combat_unit
	)


func _apply_worker_command_visibility() -> void:
	_build_farm_button.visible = true
	_build_barracks_button.visible = true
	_build_tower_button.visible = true
	_build_hero_altar_button.visible = true
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = true
	_barracks_panel.visible = false
	_hero_altar_panel.visible = false
	_worker_queue_label.visible = false


func _apply_combat_command_visibility() -> void:
	_build_farm_button.visible = false
	_build_barracks_button.visible = false
	_build_tower_button.visible = false
	_build_hero_altar_button.visible = false
	_train_worker_button.visible = false
	_attack_button.visible = true
	_buttons_row.visible = true
	_barracks_panel.visible = false
	_hero_altar_panel.visible = false
	_worker_queue_label.visible = false


func _apply_town_center_command_visibility() -> void:
	_build_farm_button.visible = false
	_build_barracks_button.visible = false
	_build_tower_button.visible = false
	_build_hero_altar_button.visible = false
	_train_worker_button.visible = true
	_attack_button.visible = false
	_buttons_row.visible = true
	_barracks_panel.visible = false
	_hero_altar_panel.visible = false


func _apply_hidden_command_buttons() -> void:
	_build_farm_button.visible = false
	_build_barracks_button.visible = false
	_build_tower_button.visible = false
	_build_hero_altar_button.visible = false
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false


func _on_attack_pressed() -> void:
	InputManager.arm_attack_move()


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


func _disconnect_hero_altar_signals() -> void:
	if _tracked_hero_altar == null:
		return

	if _tracked_hero_altar.building_state_changed.is_connected(_on_hero_altar_state_changed):
		_tracked_hero_altar.building_state_changed.disconnect(_on_hero_altar_state_changed)

	if _tracked_hero_altar.hero_altar_state_changed.is_connected(_on_hero_altar_state_changed):
		_tracked_hero_altar.hero_altar_state_changed.disconnect(_on_hero_altar_state_changed)

	_tracked_hero_altar = null


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


func _on_build_hero_altar_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_hero_altar_placement()


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


func _on_train_hero_pressed() -> void:
	if _selected_hero_altar == null:
		return

	_selected_hero_altar.try_train_hero()
