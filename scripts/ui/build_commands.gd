extends PanelContainer

## Context-sensitive command panel for the current selection (build, train, attack).

@export var selection_manager_path: NodePath = "../../../../../../SelectionManager"
@export var build_manager_path: NodePath = "../../../../../../BuildManager"

@onready var _barracks_panel: VBoxContainer = $MarginContainer/HBoxContainer/CenterPanel/BarracksPanel
@onready var _hero_altar_panel: VBoxContainer = $MarginContainer/HBoxContainer/CenterPanel/HeroAltarPanel
@onready var _barracks_training_row: HBoxContainer = $MarginContainer/HBoxContainer/RightPanel/BarracksTrainingRow
@onready var _hero_altar_training_row: HBoxContainer = $MarginContainer/HBoxContainer/RightPanel/HeroAltarTrainingRow
@onready var _buttons_row: GridContainer = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow
@onready var _build_farm_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildFarmButton
@onready var _build_barracks_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildBarracksButton
@onready var _build_blacksmith_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildBlacksmithButton
@onready var _build_stable_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildStableButton
@onready var _build_artillery_depot_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildArtilleryDepotButton
)
@onready var _build_academy_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildAcademyButton
)
@onready var _build_shop_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildShopButton
@onready var _build_tower_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildTowerButton
@onready var _build_hero_altar_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildHeroAltarButton
@onready var _build_command_center_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/ButtonsRow/BuildCommandCenterButton
)
@onready var _train_worker_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/TrainWorkerButton
@onready var _attack_button: Button = $MarginContainer/HBoxContainer/RightPanel/ButtonsRow/AttackButton
@onready var _train_spearman_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BarracksTrainingRow/TrainSpearmanButton
)
@onready var _train_swordsman_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BarracksTrainingRow/TrainSwordsmanButton
)
@onready var _train_archer_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BarracksTrainingRow/TrainArcherButton
)
@onready var _worker_queue_label: Label = $MarginContainer/HBoxContainer/CenterPanel/WorkerQueueLabel
@onready var _center_panel: VBoxContainer = $MarginContainer/HBoxContainer/CenterPanel
@onready var _right_panel: HBoxContainer = $MarginContainer/HBoxContainer/RightPanel
@onready var _swordsman_queue_label: Label = (
	$MarginContainer/HBoxContainer/CenterPanel/BarracksPanel/BarracksQueuesRow/SwordsmanQueueLabel
)
@onready var _archer_queue_label: Label = (
	$MarginContainer/HBoxContainer/CenterPanel/BarracksPanel/BarracksQueuesRow/ArcherQueueLabel
)
@onready var _train_hero_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroAltarTrainingRow/TrainHeroButton
)
@onready var _hero_status_label: Label = (
	$MarginContainer/HBoxContainer/CenterPanel/HeroAltarPanel/HeroStatusLabel
)
@onready var _hero_panel: HBoxContainer = $MarginContainer/HBoxContainer/RightPanel/HeroPanel
@onready var _ground_slam_cooldown_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/GroundSlamColumn/GroundSlamCooldownLabel
)
@onready var _ground_slam_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/GroundSlamColumn/GroundSlamButton
)
@onready var _ground_slam_upgrade_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/GroundSlamColumn/GroundSlamUpgradeButton
)
@onready var _divine_protection_cooldown_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/DivineProtectionColumn/DivineProtectionCooldownLabel
)
@onready var _divine_protection_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/DivineProtectionColumn/DivineProtectionButton
)
@onready var _divine_protection_upgrade_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/DivineProtectionColumn/DivineProtectionUpgradeButton
)
@onready var _power_strike_cooldown_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/PowerStrikeColumn/PowerStrikeCooldownLabel
)
@onready var _power_strike_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/PowerStrikeColumn/PowerStrikeButton
)
@onready var _power_strike_upgrade_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/PowerStrikeColumn/PowerStrikeUpgradeButton
)
@onready var _execute_cooldown_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/ExecuteColumn/ExecuteCooldownLabel
)
@onready var _execute_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/ExecuteColumn/ExecuteButton
)
@onready var _execute_upgrade_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/HeroPanel/ExecuteColumn/ExecuteUpgradeButton
)
@onready var _blacksmith_panel: HBoxContainer = $MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel
@onready var _swordsman_attack_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/SwordsmanAttackColumn/SwordsmanAttackInfoLabel
)
@onready var _swordsman_attack_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/SwordsmanAttackColumn/SwordsmanAttackButton
)
@onready var _swordsman_armor_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/SwordsmanArmorColumn/SwordsmanArmorInfoLabel
)
@onready var _swordsman_armor_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/SwordsmanArmorColumn/SwordsmanArmorButton
)
@onready var _archer_attack_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/ArcherAttackColumn/ArcherAttackInfoLabel
)
@onready var _archer_attack_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/ArcherAttackColumn/ArcherAttackButton
)
@onready var _archer_speed_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/ArcherSpeedColumn/ArcherSpeedInfoLabel
)
@onready var _archer_speed_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/ArcherSpeedColumn/ArcherSpeedButton
)
@onready var _archer_range_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/ArcherRangeColumn/ArcherRangeInfoLabel
)
@onready var _archer_range_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/BlacksmithPanel/ArcherRangeColumn/ArcherRangeButton
)
@onready var _stable_panel: VBoxContainer = $MarginContainer/HBoxContainer/RightPanel/StablePanel
@onready var _stable_training_row: HBoxContainer = (
	$MarginContainer/HBoxContainer/RightPanel/StablePanel/StableTrainingRow
)
@onready var _artillery_depot_panel: VBoxContainer = (
	$MarginContainer/HBoxContainer/RightPanel/ArtilleryDepotPanel
)
@onready var _artillery_depot_training_row: HBoxContainer = (
	$MarginContainer/HBoxContainer/RightPanel/ArtilleryDepotPanel/ArtilleryDepotTrainingRow
)
@onready var _academy_panel: VBoxContainer = (
	$MarginContainer/HBoxContainer/RightPanel/AcademyPanel
)
@onready var _shop_panel: VBoxContainer = $MarginContainer/HBoxContainer/RightPanel/ShopPanel
@onready var _shop_status_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopStatusLabel
)
@onready var _long_sword_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/LongSwordColumn/LongSwordInfoLabel
)
@onready var _long_sword_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/LongSwordColumn/LongSwordButton
)
@onready var _ruby_crystal_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/RubyCrystalColumn/RubyCrystalInfoLabel
)
@onready var _ruby_crystal_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/RubyCrystalColumn/RubyCrystalButton
)
@onready var _boots_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/BootsColumn/BootsInfoLabel
)
@onready var _boots_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/BootsColumn/BootsButton
)
@onready var _wizard_orb_info_label: Label = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/WizardOrbColumn/WizardOrbInfoLabel
)
@onready var _wizard_orb_button: Button = (
	$MarginContainer/HBoxContainer/RightPanel/ShopPanel/ShopItemsRow/WizardOrbColumn/WizardOrbButton
)

var _selected_command_center: CommandCenter = null
var _selected_barracks: Barracks = null
var _selected_blacksmith: Blacksmith = null
var _selected_shop: Shop = null
var _selected_hero_altar: HeroAltar = null
var _selected_stable: Stable = null
var _selected_artillery_depot: ArtilleryDepot = null
var _selected_academy: Academy = null
var _tracked_barracks: Barracks = null
var _tracked_stable: Stable = null
var _tracked_artillery_depot: ArtilleryDepot = null
var _tracked_blacksmith: Blacksmith = null
var _tracked_shop: Shop = null
var _tracked_hero_altar: HeroAltar = null
var _tracked_hero: Hero = null
var _ui_refresh_timer: float = 0.0
const UI_REFRESH_INTERVAL := 0.1
var _auto_training_label: Label = null
var _train_worker_base_label: String = ""
var _train_spearman_base_label: String = ""
var _train_swordsman_base_label: String = ""
var _train_archer_base_label: String = ""
var _worker_queue_row: HBoxContainer = null
var _swordsman_queue_row: HBoxContainer = null
var _archer_queue_row: HBoxContainer = null
var _hero_queue_row: HBoxContainer = null

const QUEUE_SLOT_SIZE := Vector2(28, 28)
const QUEUE_SLOT_HINT := "Right-click to cancel"
const QUEUE_SLOT_COLOR := Color(0.28, 0.32, 0.38, 1)
const BLACKSMITH_UPGRADE_MAX_COLOR := Color(0.55, 0.58, 0.62, 1)

var _blacksmith_upgrade_buttons: Array[Button] = []
var _blacksmith_upgrade_info_labels: Array[Label] = []
var _blacksmith_upgrade_ids: Array[StringName] = []
var _shop_item_buttons: Array[Button] = []
var _shop_item_info_labels: Array[Label] = []
var _shop_item_ids: Array[StringName] = []
var _shop_item_button_handlers: Array[Callable] = []
var _blacksmith_upgrade_button_handlers: Array[Callable] = []
const QUEUE_SLOT_TRAINING_COLOR := Color(0.45, 0.38, 0.18, 1)
const PRODUCTION_ICON_SLOT_SCENE: PackedScene = preload("res://scenes/ui/production_icon_slot.tscn")
const BUILD_ICON_SLOT_SCENE: PackedScene = preload("res://scenes/ui/build_icon_slot.tscn")
const USE_PRODUCTION_ICON_SLOTS := true
const USE_BUILD_ICON_SLOTS := true
const BUILD_MANAGER_SCRIPT := preload("res://scripts/systems/build_manager.gd")

var _barracks_spearman_slot: ProductionIconSlot = null
var _barracks_swordsman_slot: ProductionIconSlot = null
var _barracks_archer_slot: ProductionIconSlot = null
var _stable_heavy_cavalry_slot: ProductionIconSlot = null
var _stable_light_cavalry_slot: ProductionIconSlot = null
var _stable_cavalry_archer_slot: ProductionIconSlot = null
var _artillery_depot_cannon_slot: ProductionIconSlot = null
var _town_center_worker_slot: ProductionIconSlot = null
var _town_center_upgrade_slot: ProductionIconSlot = null
var _hero_altar_slot: ProductionIconSlot = null
var _build_icon_slots: Dictionary = {}


func _ready() -> void:
	visible = false
	set_process_unhandled_input(true)
	_barracks_panel.visible = false
	_hero_altar_panel.visible = false
	_barracks_training_row.visible = false
	_stable_training_row.visible = false
	_hero_altar_training_row.visible = false
	_hero_panel.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_stable_training_row.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_buttons_row.visible = false
	_build_farm_button.visible = false
	_build_barracks_button.visible = false
	_build_blacksmith_button.visible = false
	_build_stable_button.visible = false
	_build_artillery_depot_button.visible = false
	_build_academy_button.visible = false
	_build_shop_button.visible = false
	_build_tower_button.visible = false
	_build_hero_altar_button.visible = false
	_build_command_center_button.visible = false
	_train_worker_button.visible = false
	_attack_button.visible = false
	_setup_production_controls()
	if USE_PRODUCTION_ICON_SLOTS:
		_setup_production_icon_slots()
	if USE_BUILD_ICON_SLOTS:
		_setup_build_icon_slots()
	_setup_blacksmith_upgrade_controls()
	_setup_shop_item_controls()
	_set_town_center_button_labels()
	_set_barracks_button_labels()
	_set_hero_altar_button_labels()
	_build_farm_button.pressed.connect(_on_build_farm_pressed)
	_build_barracks_button.pressed.connect(_on_build_barracks_pressed)
	_build_blacksmith_button.pressed.connect(_on_build_blacksmith_pressed)
	_build_stable_button.pressed.connect(_on_build_stable_pressed)
	_build_artillery_depot_button.pressed.connect(_on_build_artillery_depot_pressed)
	_build_academy_button.pressed.connect(_on_build_academy_pressed)
	_build_shop_button.pressed.connect(_on_build_shop_pressed)
	_build_tower_button.pressed.connect(_on_build_tower_pressed)
	_build_hero_altar_button.pressed.connect(_on_build_hero_altar_pressed)
	_build_command_center_button.pressed.connect(_on_build_command_center_pressed)
	_train_worker_button.pressed.connect(_on_train_worker_pressed)
	_train_swordsman_button.pressed.connect(_on_train_swordsman_pressed)
	_train_spearman_button.pressed.connect(_on_train_spearman_pressed)
	_train_archer_button.pressed.connect(_on_train_archer_pressed)
	_train_hero_button.pressed.connect(_on_train_hero_pressed)
	_attack_button.pressed.connect(_on_attack_pressed)
	_ground_slam_button.pressed.connect(_on_ground_slam_pressed)
	_ground_slam_upgrade_button.pressed.connect(_on_ground_slam_upgrade_pressed)
	_divine_protection_button.pressed.connect(_on_divine_protection_pressed)
	_divine_protection_upgrade_button.pressed.connect(_on_divine_protection_upgrade_pressed)
	_power_strike_button.pressed.connect(_on_power_strike_pressed)
	_power_strike_upgrade_button.pressed.connect(_on_power_strike_upgrade_pressed)
	_execute_button.pressed.connect(_on_execute_pressed)
	_execute_upgrade_button.pressed.connect(_on_execute_upgrade_pressed)
	_connect_blacksmith_upgrade_buttons()
	_connect_shop_item_buttons()
	_setup_command_tooltips()
	_hide_all_hero_upgrade_buttons()

	if not UpgradeManager.upgrade_levels_changed.is_connected(_on_upgrade_levels_changed):
		UpgradeManager.upgrade_levels_changed.connect(_on_upgrade_levels_changed)
	if not ResourceManager.resources_changed.is_connected(_on_resources_changed):
		ResourceManager.resources_changed.connect(_on_resources_changed)
	if not TechTree.progression_changed.is_connected(_on_tech_progression_changed):
		TechTree.progression_changed.connect(_on_tech_progression_changed)

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	_on_building_selection_changed(selection_manager.selected_building)
	_on_selection_changed(selection_manager.selected_units)
	set_process(false)


func _process(delta: float) -> void:
	_ui_refresh_timer += delta
	if _ui_refresh_timer < UI_REFRESH_INTERVAL:
		return

	_ui_refresh_timer = 0.0
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		_update_hero_abilities_ui()
	if _shop_panel.visible:
		_update_shop_item_ui()
	if _production_icons_visible():
		_refresh_all_production_slots()


func _setup_production_controls() -> void:
	_auto_training_label = Label.new()
	_auto_training_label.visible = false
	_auto_training_label.add_theme_font_size_override("font_size", 10)
	_auto_training_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82, 1))
	_center_panel.add_child(_auto_training_label)
	_center_panel.move_child(_auto_training_label, 0)

	_worker_queue_row = _create_queue_row(_worker_queue_label)
	_swordsman_queue_row = _create_queue_row(_swordsman_queue_label)
	_archer_queue_label.visible = false

	_hero_queue_row = HBoxContainer.new()
	_hero_queue_row.visible = false
	_hero_queue_row.add_theme_constant_override("separation", 2)
	_hero_altar_panel.add_child(_hero_queue_row)
	_hero_altar_panel.move_child(_hero_queue_row, _hero_status_label.get_index() + 1)


func _setup_production_icon_slots() -> void:
	_barracks_spearman_slot = _create_production_icon_slot(
		Barracks.TRAIN_ID_SPEARMAN, _barracks_training_row
	)
	_barracks_swordsman_slot = _create_production_icon_slot(
		Barracks.TRAIN_ID_SWORDSMAN, _barracks_training_row
	)
	_barracks_archer_slot = _create_production_icon_slot(Barracks.TRAIN_ID_ARCHER, _barracks_training_row)
	_stable_heavy_cavalry_slot = _create_production_icon_slot(
		Stable.TRAIN_ID_HEAVY_CAVALRY, _stable_training_row
	)
	_stable_light_cavalry_slot = _create_production_icon_slot(
		Stable.TRAIN_ID_LIGHT_CAVALRY, _stable_training_row
	)
	_stable_cavalry_archer_slot = _create_production_icon_slot(
		Stable.TRAIN_ID_CAVALRY_ARCHER, _stable_training_row
	)
	_artillery_depot_cannon_slot = _create_production_icon_slot(
		ArtilleryDepot.TRAIN_ID_CANNON, _artillery_depot_training_row
	)
	_town_center_worker_slot = _create_production_icon_slot(
		CommandCenter.TRAIN_ID_WORKER, _buttons_row
	)
	_town_center_upgrade_slot = _create_production_icon_slot(
		CommandCenter.UPGRADE_ID_TIER, _buttons_row
	)
	_hero_altar_slot = _create_production_icon_slot(&"hero", _hero_altar_training_row)

	_train_spearman_button.visible = false
	_train_swordsman_button.visible = false
	_train_archer_button.visible = false
	_train_worker_button.visible = false
	_train_hero_button.visible = false


func _setup_build_icon_slots() -> void:
	var build_commands: Array[Array] = [
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_FARM,
			_build_farm_button,
			"B",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_BARRACKS,
			_build_barracks_button,
			"R",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_BLACKSMITH,
			_build_blacksmith_button,
			"",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_STABLE,
			_build_stable_button,
			"",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_ARTILLERY_DEPOT,
			_build_artillery_depot_button,
			"",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_ACADEMY,
			_build_academy_button,
			"",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_SHOP,
			_build_shop_button,
			"",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_TOWER,
			_build_tower_button,
			"T",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_HERO_ALTAR,
			_build_hero_altar_button,
			"H",
		],
		[
			BUILD_MANAGER_SCRIPT.PLACEMENT_COMMAND_CENTER,
			_build_command_center_button,
			"C",
		],
	]

	for command: Array in build_commands:
		var placement_id: StringName = command[0] as StringName
		var legacy_button: Button = command[1] as Button
		var hotkey: String = String(command[2])
		var slot: BuildIconSlot = _create_build_icon_slot(placement_id, legacy_button, hotkey)
		if slot != null:
			_build_icon_slots[placement_id] = slot

	_update_build_icon_slots()


func _create_build_icon_slot(
	placement_id: StringName,
	legacy_button: Button,
	hotkey: String
) -> BuildIconSlot:
	var slot: BuildIconSlot = BUILD_ICON_SLOT_SCENE.instantiate() as BuildIconSlot
	if slot == null:
		push_warning("build_commands: failed to create build icon slot for %s" % placement_id)
		return null

	slot.visible = false
	slot.configure(placement_id, BuildingCommandIcons.get_icon_texture(placement_id), hotkey)
	slot.build_slot_clicked.connect(_on_build_slot_clicked)
	TooltipManager.bind_control(
		slot,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				placement_id,
				TooltipFormatter.get_build_blocked_reason(placement_id)
			)
	)

	var parent: Node = legacy_button.get_parent()
	if parent == null:
		return slot

	parent.add_child(slot)
	parent.move_child(slot, legacy_button.get_index())
	legacy_button.visible = false
	return slot


func _on_build_slot_clicked(placement_id: StringName) -> void:
	match placement_id:
		BUILD_MANAGER_SCRIPT.PLACEMENT_FARM:
			_on_build_farm_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_BARRACKS:
			_on_build_barracks_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_BLACKSMITH:
			_on_build_blacksmith_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_STABLE:
			_on_build_stable_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_ARTILLERY_DEPOT:
			_on_build_artillery_depot_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_ACADEMY:
			_on_build_academy_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_SHOP:
			_on_build_shop_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_TOWER:
			_on_build_tower_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_HERO_ALTAR:
			_on_build_hero_altar_pressed()
		BUILD_MANAGER_SCRIPT.PLACEMENT_COMMAND_CENTER:
			_on_build_command_center_pressed()
		_:
			return


func _should_use_legacy_build_button(placement_id: StringName) -> bool:
	if not USE_BUILD_ICON_SLOTS:
		return true

	return not _build_icon_slots.has(placement_id)


func _set_build_icon_visibility(show_worker_build: bool) -> void:
	if not USE_BUILD_ICON_SLOTS:
		return

	for placement_id: StringName in _build_icon_slots:
		var slot: BuildIconSlot = _build_icon_slots[placement_id] as BuildIconSlot
		if slot == null:
			continue

		slot.visible = show_worker_build

	_set_legacy_build_button_visibility(
		_build_farm_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_FARM)
	)
	_set_legacy_build_button_visibility(
		_build_barracks_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_BARRACKS)
	)
	_set_legacy_build_button_visibility(
		_build_blacksmith_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_BLACKSMITH)
	)
	_set_legacy_build_button_visibility(
		_build_stable_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_STABLE)
	)
	_set_legacy_build_button_visibility(
		_build_artillery_depot_button,
		show_worker_build and _should_use_legacy_build_button(
			BUILD_MANAGER_SCRIPT.PLACEMENT_ARTILLERY_DEPOT
		)
	)
	_set_legacy_build_button_visibility(
		_build_academy_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_ACADEMY)
	)
	_set_legacy_build_button_visibility(
		_build_shop_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_SHOP)
	)
	_set_legacy_build_button_visibility(
		_build_tower_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_TOWER)
	)
	_set_legacy_build_button_visibility(
		_build_hero_altar_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_HERO_ALTAR)
	)
	_set_legacy_build_button_visibility(
		_build_command_center_button,
		show_worker_build and _should_use_legacy_build_button(BUILD_MANAGER_SCRIPT.PLACEMENT_COMMAND_CENTER)
	)

	if show_worker_build:
		_update_build_icon_slots()


func _set_legacy_build_button_visibility(button: Button, visible: bool) -> void:
	if button == null:
		return

	button.visible = visible


func _update_build_icon_slots() -> void:
	if not USE_BUILD_ICON_SLOTS:
		return

	for placement_id: StringName in _build_icon_slots:
		var slot: BuildIconSlot = _build_icon_slots[placement_id] as BuildIconSlot
		if slot == null:
			continue

		var blocked_reason: String = TooltipFormatter.get_build_blocked_reason(placement_id)
		slot.set_affordable(blocked_reason.is_empty())


func _worker_build_icons_visible() -> bool:
	if not USE_BUILD_ICON_SLOTS:
		return false

	for placement_id: StringName in _build_icon_slots:
		var slot: BuildIconSlot = _build_icon_slots[placement_id] as BuildIconSlot
		if slot != null and slot.visible:
			return true

	return false


func _create_production_icon_slot(train_id: StringName, parent: Control) -> ProductionIconSlot:
	var slot: ProductionIconSlot = PRODUCTION_ICON_SLOT_SCENE.instantiate() as ProductionIconSlot
	if slot == null:
		push_warning("build_commands: failed to create production icon slot for %s" % train_id)
		return null

	slot.visible = false
	slot.production_slot_clicked.connect(_on_production_slot_clicked)
	parent.add_child(slot)
	parent.move_child(slot, 0)
	slot.configure(train_id, UnitProductionIcons.get_icon_texture(train_id))
	TooltipManager.bind_control(slot, func() -> String: return _get_production_slot_tooltip(train_id))
	return slot


func _production_icons_visible() -> bool:
	if not USE_PRODUCTION_ICON_SLOTS:
		return false

	return (
		(_barracks_spearman_slot != null and _barracks_spearman_slot.visible)
		or (_barracks_swordsman_slot != null and _barracks_swordsman_slot.visible)
		or (_stable_heavy_cavalry_slot != null and _stable_heavy_cavalry_slot.visible)
		or (_stable_light_cavalry_slot != null and _stable_light_cavalry_slot.visible)
		or (_stable_cavalry_archer_slot != null and _stable_cavalry_archer_slot.visible)
		or (_artillery_depot_cannon_slot != null and _artillery_depot_cannon_slot.visible)
		or (_town_center_worker_slot != null and _town_center_worker_slot.visible)
		or (_town_center_upgrade_slot != null and _town_center_upgrade_slot.visible)
		or (_hero_altar_slot != null and _hero_altar_slot.visible)
	)


func _refresh_all_production_slots() -> void:
	if _selected_barracks != null and is_instance_valid(_selected_barracks):
		_refresh_barracks_production_slots()
	if _selected_command_center != null and is_instance_valid(_selected_command_center):
		_refresh_town_center_production_slot()
	if _selected_hero_altar != null and is_instance_valid(_selected_hero_altar):
		_refresh_hero_altar_production_slot()
	if _selected_stable != null and is_instance_valid(_selected_stable):
		_refresh_stable_production_slots()
	if _selected_artillery_depot != null and is_instance_valid(_selected_artillery_depot):
		_refresh_artillery_depot_production_slots()


func _refresh_artillery_depot_production_slots() -> void:
	if _artillery_depot_cannon_slot == null:
		return

	if _selected_artillery_depot == null or not is_instance_valid(_selected_artillery_depot):
		return

	var depot: ArtilleryDepot = _selected_artillery_depot
	_artillery_depot_cannon_slot.set_queue_count(depot.get_cannon_queue_count())
	_artillery_depot_cannon_slot.set_infinite_enabled(
		depot.is_repeat_training_enabled(ArtilleryDepot.TRAIN_ID_CANNON)
	)
	_artillery_depot_cannon_slot.set_training_progress(
		depot.get_active_unit_training_progress(),
		depot.is_training_cannon()
	)
	_artillery_depot_cannon_slot.set_affordable(
		TooltipFormatter.get_train_blocked_reason(
			ArtilleryDepot.get_unit_train_gold_cost(ArtilleryDepot.TRAIN_ID_CANNON),
			ArtilleryDepot.get_unit_train_food_cost(ArtilleryDepot.TRAIN_ID_CANNON)
		).is_empty()
	)


func _refresh_stable_production_slots() -> void:
	if (
		_stable_heavy_cavalry_slot == null
		or _stable_light_cavalry_slot == null
		or _stable_cavalry_archer_slot == null
	):
		return

	if _selected_stable == null or not is_instance_valid(_selected_stable):
		return

	var stable: Stable = _selected_stable
	_stable_heavy_cavalry_slot.set_queue_count(stable.get_heavy_cavalry_queue_count())
	_stable_heavy_cavalry_slot.set_infinite_enabled(
		stable.is_repeat_training_enabled(Stable.TRAIN_ID_HEAVY_CAVALRY)
	)
	_stable_heavy_cavalry_slot.set_training_progress(
		stable.get_active_unit_training_progress(),
		stable.is_training_heavy_cavalry()
	)
	_stable_heavy_cavalry_slot.set_affordable(
		TooltipFormatter.get_train_blocked_reason(
			Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_HEAVY_CAVALRY),
			Stable.get_unit_train_food_cost(Stable.TRAIN_ID_HEAVY_CAVALRY)
		).is_empty()
	)

	_stable_light_cavalry_slot.set_queue_count(stable.get_light_cavalry_queue_count())
	_stable_light_cavalry_slot.set_infinite_enabled(
		stable.is_repeat_training_enabled(Stable.TRAIN_ID_LIGHT_CAVALRY)
	)
	_stable_light_cavalry_slot.set_training_progress(
		stable.get_active_unit_training_progress(),
		stable.is_training_light_cavalry()
	)
	_stable_light_cavalry_slot.set_affordable(
		TooltipFormatter.get_train_blocked_reason(
			Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_LIGHT_CAVALRY),
			Stable.get_unit_train_food_cost(Stable.TRAIN_ID_LIGHT_CAVALRY)
		).is_empty()
	)

	_stable_cavalry_archer_slot.set_queue_count(stable.get_cavalry_archer_queue_count())
	_stable_cavalry_archer_slot.set_infinite_enabled(
		stable.is_repeat_training_enabled(Stable.TRAIN_ID_CAVALRY_ARCHER)
	)
	_stable_cavalry_archer_slot.set_training_progress(
		stable.get_active_unit_training_progress(),
		stable.is_training_cavalry_archer()
	)
	_stable_cavalry_archer_slot.set_affordable(
		TooltipFormatter.get_train_blocked_reason(
			Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_CAVALRY_ARCHER),
			Stable.get_unit_train_food_cost(Stable.TRAIN_ID_CAVALRY_ARCHER)
		).is_empty()
	)


func _refresh_barracks_production_slots() -> void:
	if (
		_barracks_spearman_slot == null
		or _barracks_swordsman_slot == null
		or _barracks_archer_slot == null
	):
		return

	if _selected_barracks == null or not is_instance_valid(_selected_barracks):
		return

	var barracks: Barracks = _selected_barracks
	_barracks_spearman_slot.set_queue_count(barracks.get_spearman_queue_count())
	_barracks_spearman_slot.set_infinite_enabled(
		barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_SPEARMAN)
	)
	_barracks_spearman_slot.set_training_progress(
		barracks.get_active_unit_training_progress(),
		barracks.is_training_spearman()
	)
	_barracks_spearman_slot.set_affordable(
		TooltipFormatter.get_train_blocked_reason_for_unit(
			Barracks.TRAIN_ID_SPEARMAN,
			Barracks.get_unit_train_gold_cost(Barracks.TRAIN_ID_SPEARMAN),
			Barracks.TRAIN_FOOD_COST
		).is_empty()
	)

	_barracks_swordsman_slot.set_queue_count(barracks.get_swordsman_queue_count())
	_barracks_swordsman_slot.set_infinite_enabled(
		barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_SWORDSMAN)
	)
	_barracks_swordsman_slot.set_training_progress(
		barracks.get_active_unit_training_progress(),
		barracks.is_training_swordsman()
	)
	_barracks_swordsman_slot.set_affordable(
		TooltipFormatter.get_train_blocked_reason_for_unit(
			Barracks.TRAIN_ID_SWORDSMAN,
			Barracks.TRAIN_GOLD_COST,
			Barracks.TRAIN_FOOD_COST
		).is_empty()
	)

	_barracks_archer_slot.set_queue_count(barracks.get_archer_queue_count())
	_barracks_archer_slot.set_infinite_enabled(
		barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_ARCHER)
	)
	_barracks_archer_slot.set_training_progress(
		barracks.get_active_unit_training_progress(),
		barracks.is_training_archer()
	)
	_barracks_archer_slot.set_affordable(
		TooltipFormatter.get_train_blocked_reason_for_unit(
			Barracks.TRAIN_ID_ARCHER,
			Barracks.TRAIN_GOLD_COST,
			Barracks.TRAIN_FOOD_COST
		).is_empty()
	)

	_update_barracks_train_button_states()


func _refresh_town_center_production_slot() -> void:
	if _town_center_worker_slot == null or _selected_command_center == null:
		return

	if not is_instance_valid(_selected_command_center):
		_selected_command_center = null
		return

	var command_center: CommandCenter = _selected_command_center
	_town_center_worker_slot.set_queue_count(command_center.get_worker_queue_count())
	_town_center_worker_slot.set_infinite_enabled(
		command_center.is_repeat_training_enabled(CommandCenter.TRAIN_ID_WORKER)
	)
	_town_center_worker_slot.set_training_progress(
		command_center.get_active_unit_training_progress(),
		command_center.is_training_worker() and not command_center.is_upgrading_tier()
	)
	_refresh_town_center_upgrade_slot()


func _refresh_town_center_upgrade_slot() -> void:
	if _town_center_upgrade_slot == null or _selected_command_center == null:
		return

	if not is_instance_valid(_selected_command_center):
		_selected_command_center = null
		return

	var command_center: CommandCenter = _selected_command_center
	var show_upgrade: bool = command_center.can_show_tier_upgrade_button()
	_town_center_upgrade_slot.visible = show_upgrade

	if not show_upgrade:
		return

	_town_center_upgrade_slot.set_queue_count(0)
	_town_center_upgrade_slot.set_infinite_enabled(false)
	_town_center_upgrade_slot.set_training_progress(
		command_center.get_tier_upgrade_progress(),
		command_center.is_upgrading_tier()
	)


func _refresh_hero_altar_production_slot() -> void:
	if _hero_altar_slot == null or _selected_hero_altar == null:
		return

	var hero_altar: HeroAltar = _selected_hero_altar
	var queue_count: int = 1 if hero_altar.is_training_hero() else 0
	_hero_altar_slot.set_queue_count(queue_count)
	_hero_altar_slot.set_infinite_enabled(false)
	_hero_altar_slot.set_training_progress(
		hero_altar.get_active_unit_training_progress(),
		hero_altar.is_training_hero()
	)


func _should_use_legacy_train_button(slot: ProductionIconSlot) -> bool:
	return not USE_PRODUCTION_ICON_SLOTS or slot == null


func _set_production_icon_visibility(
	show_barracks: bool,
	show_town_center: bool,
	show_hero_altar: bool,
	show_stable: bool = false,
	show_artillery_depot: bool = false
) -> void:
	if not USE_PRODUCTION_ICON_SLOTS:
		return

	if _barracks_spearman_slot != null:
		_barracks_spearman_slot.visible = show_barracks
	if _barracks_swordsman_slot != null:
		_barracks_swordsman_slot.visible = show_barracks
	if _barracks_archer_slot != null:
		_barracks_archer_slot.visible = show_barracks
	if _stable_heavy_cavalry_slot != null:
		_stable_heavy_cavalry_slot.visible = show_stable
	if _stable_light_cavalry_slot != null:
		_stable_light_cavalry_slot.visible = show_stable
	if _stable_cavalry_archer_slot != null:
		_stable_cavalry_archer_slot.visible = show_stable
	if _artillery_depot_cannon_slot != null:
		_artillery_depot_cannon_slot.visible = show_artillery_depot
	if _town_center_worker_slot != null:
		_town_center_worker_slot.visible = show_town_center
	if _town_center_upgrade_slot != null:
		_town_center_upgrade_slot.visible = false
	if _hero_altar_slot != null:
		_hero_altar_slot.visible = show_hero_altar

	_train_spearman_button.visible = show_barracks and _should_use_legacy_train_button(_barracks_spearman_slot)
	_train_swordsman_button.visible = show_barracks and _should_use_legacy_train_button(_barracks_swordsman_slot)
	_train_archer_button.visible = show_barracks and _should_use_legacy_train_button(_barracks_archer_slot)
	_train_worker_button.visible = show_town_center and _should_use_legacy_train_button(_town_center_worker_slot)
	_train_hero_button.visible = show_hero_altar and _should_use_legacy_train_button(_hero_altar_slot)

	if USE_PRODUCTION_ICON_SLOTS:
		if show_barracks:
			_clear_queue_row(_swordsman_queue_row)
		if show_town_center:
			_clear_queue_row(_worker_queue_row)
		if show_hero_altar:
			_clear_queue_row(_hero_queue_row)

	if show_barracks:
		_refresh_barracks_production_slots()
	if show_stable:
		_refresh_stable_production_slots()
	if show_artillery_depot:
		_refresh_artillery_depot_production_slots()
	if show_town_center:
		_refresh_town_center_production_slot()
	if show_hero_altar:
		_refresh_hero_altar_production_slot()


func _on_production_slot_clicked(train_id: StringName, event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_production_left_click(train_id, event)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_production_right_click(train_id, event)


func _handle_production_left_click(train_id: StringName, event: InputEventMouseButton) -> void:
	if event.ctrl_pressed:
		if train_id == CommandCenter.UPGRADE_ID_TIER:
			return
		_handle_production_toggle_repeat(train_id)
		_after_production_action()
		return

	var queue_amount: int = 5 if event.shift_pressed else 1

	if train_id == Barracks.TRAIN_ID_SPEARMAN:
		if _selected_barracks == null:
			return

		for _unused: int in queue_amount:
			_selected_barracks.try_train_spearman()
	elif train_id == Barracks.TRAIN_ID_SWORDSMAN:
		if _selected_barracks == null:
			return

		for _unused: int in queue_amount:
			_selected_barracks.try_train_swordsman()
	elif train_id == Barracks.TRAIN_ID_ARCHER:
		if _selected_barracks == null:
			return

		for _unused: int in queue_amount:
			_selected_barracks.try_train_archer()
	elif train_id == CommandCenter.TRAIN_ID_WORKER:
		if _selected_command_center == null:
			return

		for _unused: int in queue_amount:
			_selected_command_center.try_train_worker()
	elif train_id == CommandCenter.UPGRADE_ID_TIER:
		if _selected_command_center == null or not is_instance_valid(_selected_command_center):
			return

		_selected_command_center.try_upgrade_tier()
	elif train_id == &"hero":
		if _selected_hero_altar == null:
			return

		_selected_hero_altar.try_train_hero()
	elif train_id == Stable.TRAIN_ID_HEAVY_CAVALRY:
		if _selected_stable == null:
			return

		for _unused: int in queue_amount:
			_selected_stable.try_train_heavy_cavalry()
	elif train_id == Stable.TRAIN_ID_LIGHT_CAVALRY:
		if _selected_stable == null:
			return

		for _unused: int in queue_amount:
			_selected_stable.try_train_light_cavalry()
	elif train_id == Stable.TRAIN_ID_CAVALRY_ARCHER:
		if _selected_stable == null:
			return

		for _unused: int in queue_amount:
			_selected_stable.try_train_cavalry_archer()
	elif train_id == ArtilleryDepot.TRAIN_ID_CANNON:
		if _selected_artillery_depot == null:
			return

		for _unused: int in queue_amount:
			_selected_artillery_depot.try_train_cannon()
	else:
		return

	_after_production_action()


func _handle_production_right_click(train_id: StringName, event: InputEventMouseButton) -> void:
	if train_id == CommandCenter.UPGRADE_ID_TIER:
		return

	if event.ctrl_pressed:
		_disable_production_repeat(train_id)
		_after_production_action()
		return

	var cancel_amount: int = 5 if event.shift_pressed else 1
	_cancel_production_units(train_id, cancel_amount)
	_after_production_action()


func _handle_production_toggle_repeat(train_id: StringName) -> void:
	if train_id == Barracks.TRAIN_ID_SPEARMAN and _selected_barracks != null:
		_selected_barracks.try_train_spearman_with_repeat(true)
	elif train_id == Barracks.TRAIN_ID_SWORDSMAN and _selected_barracks != null:
		_selected_barracks.try_train_swordsman_with_repeat(true)
	elif train_id == Barracks.TRAIN_ID_ARCHER and _selected_barracks != null:
		_selected_barracks.try_train_archer_with_repeat(true)
	elif train_id == CommandCenter.TRAIN_ID_WORKER and _selected_command_center != null:
		_selected_command_center.try_train_worker_with_repeat(true)
	elif train_id == Stable.TRAIN_ID_HEAVY_CAVALRY and _selected_stable != null:
		_selected_stable.try_train_heavy_cavalry_with_repeat(true)
	elif train_id == Stable.TRAIN_ID_LIGHT_CAVALRY and _selected_stable != null:
		_selected_stable.try_train_light_cavalry_with_repeat(true)
	elif train_id == Stable.TRAIN_ID_CAVALRY_ARCHER and _selected_stable != null:
		_selected_stable.try_train_cavalry_archer_with_repeat(true)
	elif train_id == ArtilleryDepot.TRAIN_ID_CANNON and _selected_artillery_depot != null:
		_selected_artillery_depot.try_train_cannon_with_repeat(true)


func _disable_production_repeat(train_id: StringName) -> void:
	if train_id == Barracks.TRAIN_ID_SPEARMAN and _selected_barracks != null:
		if _selected_barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_SPEARMAN):
			_selected_barracks.set_repeat_training(false)
	elif train_id == Barracks.TRAIN_ID_SWORDSMAN and _selected_barracks != null:
		if _selected_barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_SWORDSMAN):
			_selected_barracks.set_repeat_training(false)
	elif train_id == Barracks.TRAIN_ID_ARCHER and _selected_barracks != null:
		if _selected_barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_ARCHER):
			_selected_barracks.set_repeat_training(false)
	elif train_id == CommandCenter.TRAIN_ID_WORKER and _selected_command_center != null:
		if _selected_command_center.is_repeat_training_enabled(CommandCenter.TRAIN_ID_WORKER):
			_selected_command_center.set_repeat_training(false)
	elif train_id == Stable.TRAIN_ID_HEAVY_CAVALRY and _selected_stable != null:
		if _selected_stable.is_repeat_training_enabled(Stable.TRAIN_ID_HEAVY_CAVALRY):
			_selected_stable.set_repeat_training(false)
	elif train_id == Stable.TRAIN_ID_LIGHT_CAVALRY and _selected_stable != null:
		if _selected_stable.is_repeat_training_enabled(Stable.TRAIN_ID_LIGHT_CAVALRY):
			_selected_stable.set_repeat_training(false)
	elif train_id == Stable.TRAIN_ID_CAVALRY_ARCHER and _selected_stable != null:
		if _selected_stable.is_repeat_training_enabled(Stable.TRAIN_ID_CAVALRY_ARCHER):
			_selected_stable.set_repeat_training(false)
	elif train_id == ArtilleryDepot.TRAIN_ID_CANNON and _selected_artillery_depot != null:
		if _selected_artillery_depot.is_repeat_training_enabled(ArtilleryDepot.TRAIN_ID_CANNON):
			_selected_artillery_depot.set_repeat_training(false)


func _cancel_production_units(train_id: StringName, cancel_amount: int) -> void:
	if train_id == Barracks.TRAIN_ID_SPEARMAN:
		_cancel_barracks_unit_type(_selected_barracks, train_id, cancel_amount)
	elif train_id == Barracks.TRAIN_ID_SWORDSMAN:
		_cancel_barracks_unit_type(_selected_barracks, train_id, cancel_amount)
	elif train_id == Barracks.TRAIN_ID_ARCHER:
		_cancel_barracks_unit_type(_selected_barracks, train_id, cancel_amount)
	elif train_id == Stable.TRAIN_ID_HEAVY_CAVALRY:
		_cancel_stable_unit_type(_selected_stable, train_id, cancel_amount)
	elif train_id == Stable.TRAIN_ID_LIGHT_CAVALRY:
		_cancel_stable_unit_type(_selected_stable, train_id, cancel_amount)
	elif train_id == Stable.TRAIN_ID_CAVALRY_ARCHER:
		_cancel_stable_unit_type(_selected_stable, train_id, cancel_amount)
	elif train_id == ArtilleryDepot.TRAIN_ID_CANNON:
		_cancel_artillery_depot_unit_type(_selected_artillery_depot, train_id, cancel_amount)
	elif train_id == CommandCenter.TRAIN_ID_WORKER:
		_cancel_worker_units(cancel_amount)
	elif train_id == &"hero":
		if _selected_hero_altar != null:
			_selected_hero_altar.cancel_hero_training()


func _cancel_barracks_unit_type(barracks: Barracks, train_id: StringName, cancel_amount: int) -> void:
	if barracks == null or not is_instance_valid(barracks):
		return

	for _unused: int in cancel_amount:
		var type_count: int = 0
		match train_id:
			Barracks.TRAIN_ID_SPEARMAN:
				type_count = barracks.get_spearman_queue_count()
			Barracks.TRAIN_ID_SWORDSMAN:
				type_count = barracks.get_swordsman_queue_count()
			Barracks.TRAIN_ID_ARCHER:
				type_count = barracks.get_archer_queue_count()
		if type_count <= 0:
			break

		var type_slot_index: int = type_count - 1
		var cancelled: bool = false
		match train_id:
			Barracks.TRAIN_ID_SPEARMAN:
				cancelled = barracks.cancel_spearman_training_at(type_slot_index)
			Barracks.TRAIN_ID_SWORDSMAN:
				cancelled = barracks.cancel_swordsman_training_at(type_slot_index)
			Barracks.TRAIN_ID_ARCHER:
				cancelled = barracks.cancel_archer_training_at(type_slot_index)
		if not cancelled:
			break


func _cancel_stable_unit_type(stable: Stable, train_id: StringName, cancel_amount: int) -> void:
	if stable == null or not is_instance_valid(stable):
		return

	for _unused: int in cancel_amount:
		var type_count: int = 0
		match train_id:
			Stable.TRAIN_ID_HEAVY_CAVALRY:
				type_count = stable.get_heavy_cavalry_queue_count()
			Stable.TRAIN_ID_LIGHT_CAVALRY:
				type_count = stable.get_light_cavalry_queue_count()
			Stable.TRAIN_ID_CAVALRY_ARCHER:
				type_count = stable.get_cavalry_archer_queue_count()
		if type_count <= 0:
			break

		var type_slot_index: int = type_count - 1
		var cancelled: bool = false
		match train_id:
			Stable.TRAIN_ID_HEAVY_CAVALRY:
				cancelled = stable.cancel_heavy_cavalry_training_at(type_slot_index)
			Stable.TRAIN_ID_LIGHT_CAVALRY:
				cancelled = stable.cancel_light_cavalry_training_at(type_slot_index)
			Stable.TRAIN_ID_CAVALRY_ARCHER:
				cancelled = stable.cancel_cavalry_archer_training_at(type_slot_index)
		if not cancelled:
			break


func _cancel_artillery_depot_unit_type(
	depot: ArtilleryDepot, train_id: StringName, cancel_amount: int
) -> void:
	if depot == null or not is_instance_valid(depot):
		return

	for _unused: int in cancel_amount:
		var type_count: int = 0
		if train_id == ArtilleryDepot.TRAIN_ID_CANNON:
			type_count = depot.get_cannon_queue_count()
		if type_count <= 0:
			break

		var type_slot_index: int = type_count - 1
		var cancelled: bool = false
		if train_id == ArtilleryDepot.TRAIN_ID_CANNON:
			cancelled = depot.cancel_cannon_training_at(type_slot_index)
		if not cancelled:
			break


func _cancel_worker_units(cancel_amount: int) -> void:
	if _selected_command_center == null:
		return

	for _unused: int in cancel_amount:
		var queue_count: int = _selected_command_center.get_worker_queue_count()
		if queue_count <= 0:
			break

		if not _selected_command_center.cancel_worker_training_at(queue_count - 1):
			break


func _after_production_action() -> void:
	_update_barracks_button_labels()
	_update_town_center_button_labels()
	_update_auto_training_label()
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_all_production_slots()
	else:
		_rebuild_worker_queue_slots()
		_rebuild_swordsman_queue_slots()
		_rebuild_archer_queue_slots()
		_rebuild_hero_queue_slots()


func _get_production_slot_tooltip(train_id: StringName) -> String:
	var base_tooltip: String = ""
	match train_id:
		Barracks.TRAIN_ID_SPEARMAN:
			base_tooltip = _get_train_spearman_tooltip()
		Barracks.TRAIN_ID_SWORDSMAN:
			base_tooltip = _get_train_swordsman_tooltip()
		Barracks.TRAIN_ID_ARCHER:
			base_tooltip = _get_train_archer_tooltip()
		Stable.TRAIN_ID_HEAVY_CAVALRY:
			base_tooltip = _get_train_heavy_cavalry_tooltip()
		Stable.TRAIN_ID_LIGHT_CAVALRY:
			base_tooltip = _get_train_light_cavalry_tooltip()
		Stable.TRAIN_ID_CAVALRY_ARCHER:
			base_tooltip = _get_train_cavalry_archer_tooltip()
		ArtilleryDepot.TRAIN_ID_CANNON:
			base_tooltip = _get_train_cannon_tooltip()
		CommandCenter.TRAIN_ID_WORKER:
			base_tooltip = _get_train_worker_tooltip()
		CommandCenter.UPGRADE_ID_TIER:
			base_tooltip = _get_town_center_upgrade_tooltip()
		&"hero":
			base_tooltip = _get_train_hero_tooltip()
		_:
			return ""

	if base_tooltip.is_empty():
		return base_tooltip

	if train_id == &"hero":
		return "%s\nLeft-click: train\nRight-click: cancel" % base_tooltip

	if train_id == CommandCenter.UPGRADE_ID_TIER:
		return "%s\nLeft-click: start upgrade" % base_tooltip

	return (
		"%s\nLeft-click: queue +1 | Shift: +5 | Ctrl: infinite\n"
		+ "Right-click: cancel -1 | Shift: -5 | Ctrl: off infinite"
	) % base_tooltip


func _setup_blacksmith_upgrade_controls() -> void:
	_blacksmith_upgrade_ids = UpgradeManager.BLACKSMITH_UPGRADE_ORDER.duplicate()
	_blacksmith_upgrade_info_labels = [
		_swordsman_attack_info_label,
		_swordsman_armor_info_label,
		_archer_attack_info_label,
		_archer_speed_info_label,
		_archer_range_info_label,
	]
	_blacksmith_upgrade_buttons = [
		_swordsman_attack_button,
		_swordsman_armor_button,
		_archer_attack_button,
		_archer_speed_button,
		_archer_range_button,
	]
	_update_blacksmith_upgrade_ui()


func _setup_shop_item_controls() -> void:
	_shop_item_ids = HeroItemCatalog.SHOP_ITEM_ORDER.duplicate()
	_shop_item_info_labels = [
		_long_sword_info_label,
		_ruby_crystal_info_label,
		_boots_info_label,
		_wizard_orb_info_label,
	]
	_shop_item_buttons = [
		_long_sword_button,
		_ruby_crystal_button,
		_boots_button,
		_wizard_orb_button,
	]
	_update_shop_item_ui()


func _connect_shop_item_buttons() -> void:
	for index: int in _shop_item_buttons.size():
		var button: Button = _shop_item_buttons[index]
		if button == null:
			continue
		if index < _shop_item_button_handlers.size():
			continue

		var item_id: StringName = _shop_item_ids[index]
		var handler := func() -> void:
			_on_shop_item_button_pressed(item_id)
		_shop_item_button_handlers.append(handler)
		button.pressed.connect(handler)


func _on_shop_item_button_pressed(item_id: StringName) -> void:
	if _selected_shop == null or not is_instance_valid(_selected_shop):
		_selected_shop = null
		return

	if _selected_shop.try_purchase_item(item_id):
		_update_shop_item_ui()


func _update_shop_item_ui() -> void:
	if _selected_shop == null or not is_instance_valid(_selected_shop):
		_selected_shop = null
		_shop_status_label.visible = false
		return

	var nearby_hero: Hero = _selected_shop.get_nearby_shop_hero()
	_shop_status_label.visible = nearby_hero == null
	if nearby_hero == null:
		_shop_status_label.text = "Move hero near shop"
	else:
		_shop_status_label.text = "Buying for nearby hero"

	for index: int in _shop_item_buttons.size():
		if index >= _shop_item_ids.size():
			break

		var item_id: StringName = _shop_item_ids[index]
		var item: HeroItemDefinition = HeroItemCatalog.get_definition(item_id)
		var info_label: Label = _shop_item_info_labels[index]
		var button: Button = _shop_item_buttons[index]
		if item == null or info_label == null or button == null:
			continue

		info_label.text = "%s\n%s" % [item.display_name, _get_shop_item_effect_label(item)]
		button.icon = HeroItemIcons.get_icon_texture(item_id)
		button.expand_icon = true
		button.text = "%s\n%dG" % [HeroItemCatalog.get_hotkey_label(item_id), item.gold_cost]
		button.disabled = not HeroItemService.can_purchase_from_shop(_selected_shop, item_id)


func _get_shop_item_effect_label(item: HeroItemDefinition) -> String:
	var parts: PackedStringArray = PackedStringArray()

	if item.bonus_attack_damage > 0:
		parts.append("+%d AD" % item.bonus_attack_damage)
	if item.bonus_max_health > 0:
		parts.append("+%d HP" % item.bonus_max_health)
	if item.bonus_move_speed > 0.0:
		parts.append("+%d MS" % int(item.bonus_move_speed))
	if item.bonus_max_mana > 0:
		parts.append("+%d Mana" % item.bonus_max_mana)
	if item.bonus_ability_power > 0:
		parts.append("+%d AP" % item.bonus_ability_power)
	if item.bonus_cooldown_reduction > 0.0:
		parts.append("+%d%% CDR" % int(round(item.bonus_cooldown_reduction * 100.0)))
	if item.bonus_mana_cost_reduction > 0.0:
		parts.append("+%d%% MCR" % int(round(item.bonus_mana_cost_reduction * 100.0)))
	if item.bonus_spell_radius > 0.0:
		parts.append("+%s Radius" % TooltipFormatter._format_number(item.bonus_spell_radius))

	return ", ".join(parts)


func _connect_blacksmith_upgrade_buttons() -> void:
	for index: int in _blacksmith_upgrade_buttons.size():
		var button: Button = _blacksmith_upgrade_buttons[index]
		if button == null:
			continue
		if index < _blacksmith_upgrade_button_handlers.size():
			continue

		var upgrade_id: StringName = _blacksmith_upgrade_ids[index]
		var handler := func() -> void:
			_on_blacksmith_upgrade_button_pressed(upgrade_id)
		_blacksmith_upgrade_button_handlers.append(handler)
		button.pressed.connect(handler)


func _on_blacksmith_upgrade_button_pressed(upgrade_id: StringName) -> void:
	if _selected_blacksmith == null or not is_instance_valid(_selected_blacksmith):
		_selected_blacksmith = null
		return

	if _selected_blacksmith.try_research_upgrade(upgrade_id):
		_update_blacksmith_upgrade_ui()


func _on_upgrade_levels_changed() -> void:
	_update_blacksmith_upgrade_ui()


func _update_barracks_train_button_states() -> void:
	_train_spearman_button.disabled = not TooltipFormatter.get_train_blocked_reason_for_unit(
		Barracks.TRAIN_ID_SPEARMAN,
		Barracks.get_unit_train_gold_cost(Barracks.TRAIN_ID_SPEARMAN),
		Barracks.TRAIN_FOOD_COST
	).is_empty()
	_train_swordsman_button.disabled = not TooltipFormatter.get_train_blocked_reason_for_unit(
		Barracks.TRAIN_ID_SWORDSMAN,
		Barracks.TRAIN_GOLD_COST,
		Barracks.TRAIN_FOOD_COST
	).is_empty()
	_train_archer_button.disabled = not TooltipFormatter.get_train_blocked_reason_for_unit(
		Barracks.TRAIN_ID_ARCHER,
		Barracks.TRAIN_GOLD_COST,
		Barracks.TRAIN_FOOD_COST
	).is_empty()


func _on_tech_progression_changed(team_id: int) -> void:
	if team_id != TechTree.PLAYER_TEAM_ID:
		return

	if _worker_build_icons_visible():
		_update_build_icon_slots()

	if _barracks_training_row.visible:
		_refresh_barracks_production_slots()
		_update_barracks_button_labels()


func _on_resources_changed() -> void:
	if _blacksmith_panel.visible:
		_update_blacksmith_upgrade_ui()
	if _shop_panel.visible:
		_update_shop_item_ui()
	if _worker_build_icons_visible():
		_update_build_icon_slots()
	if _barracks_training_row.visible:
		_refresh_barracks_production_slots()


func _update_blacksmith_upgrade_ui() -> void:
	if _selected_blacksmith == null or not is_instance_valid(_selected_blacksmith):
		_selected_blacksmith = null
		return

	var is_researching: bool = _selected_blacksmith.is_researching()

	for index: int in _blacksmith_upgrade_buttons.size():
		if index >= _blacksmith_upgrade_ids.size():
			break

		var upgrade_id: StringName = _blacksmith_upgrade_ids[index]
		var info_label: Label = _blacksmith_upgrade_info_labels[index]
		var button: Button = _blacksmith_upgrade_buttons[index]
		if info_label == null or button == null:
			continue

		var level: int = UpgradeManager.get_level(upgrade_id)
		var display_name: String = UpgradeManager.get_display_name(upgrade_id)
		info_label.text = "%s\n%d/%d" % [display_name, level, UpgradeManager.MAX_LEVEL]

		if is_researching:
			button.disabled = true
			continue

		if UpgradeManager.is_max_level(upgrade_id):
			info_label.add_theme_color_override("font_color", BLACKSMITH_UPGRADE_MAX_COLOR)
			button.text = "%s\nMAX" % UpgradeManager.get_hotkey_label(upgrade_id)
			button.disabled = true
			continue

		info_label.remove_theme_color_override("font_color")
		var cost: Dictionary = UpgradeManager.get_next_level_cost(upgrade_id)
		button.text = "%s\n%dW %dG" % [
			UpgradeManager.get_hotkey_label(upgrade_id),
			cost.wood,
			cost.gold,
		]
		button.disabled = not UpgradeManager.can_afford_upgrade(upgrade_id)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if _try_handle_shop_item_hotkey(key_event):
		return

	if _try_handle_blacksmith_upgrade_hotkey(key_event):
		return

	var hero: Hero = _get_tracked_hero_for_input()
	if hero == null:
		return

	match key_event.keycode:
		KEY_Q:
			if key_event.shift_pressed:
				hero.try_learn_ability(HeroAbilityProgression.ABILITY_Q)
			else:
				hero.try_ground_slam()
			get_viewport().set_input_as_handled()
		KEY_W:
			if key_event.shift_pressed:
				hero.try_learn_ability(HeroAbilityProgression.ABILITY_W)
			else:
				hero.try_divine_protection()
			get_viewport().set_input_as_handled()
		KEY_E:
			if key_event.shift_pressed:
				hero.try_learn_ability(HeroAbilityProgression.ABILITY_E)
			else:
				hero.try_power_strike()
			get_viewport().set_input_as_handled()
		KEY_R:
			if key_event.shift_pressed:
				hero.try_learn_ability(HeroAbilityProgression.ABILITY_R)
			else:
				hero.try_execute()
			get_viewport().set_input_as_handled()


func _try_handle_shop_item_hotkey(key_event: InputEventKey) -> bool:
	if _selected_shop == null or not is_instance_valid(_selected_shop):
		_selected_shop = null
		return false

	if not _selected_shop.can_sell_items():
		return false

	var item_id: StringName = &""
	var shop_items: Array[StringName] = HeroItemCatalog.SHOP_ITEM_ORDER
	match key_event.keycode:
		KEY_Q:
			if shop_items.size() > 0:
				item_id = shop_items[0]
		KEY_W:
			if shop_items.size() > 1:
				item_id = shop_items[1]
		KEY_E:
			if shop_items.size() > 2:
				item_id = shop_items[2]
		KEY_R:
			if shop_items.size() > 3:
				item_id = shop_items[3]
		_:
			return false

	if item_id.is_empty():
		return false

	if _selected_shop.try_purchase_item(item_id):
		_update_shop_item_ui()

	get_viewport().set_input_as_handled()
	return true


func _try_handle_blacksmith_upgrade_hotkey(key_event: InputEventKey) -> bool:
	if _selected_blacksmith == null or not is_instance_valid(_selected_blacksmith):
		_selected_blacksmith = null
		return false

	if not _selected_blacksmith.can_research():
		return false

	if _selected_blacksmith.is_researching():
		get_viewport().set_input_as_handled()
		return true

	var upgrade_id: StringName = &""
	match key_event.keycode:
		KEY_Q:
			upgrade_id = UpgradeManager.UPGRADE_SWORDSMAN_ATTACK
		KEY_W:
			upgrade_id = UpgradeManager.UPGRADE_SWORDSMAN_ARMOR
		KEY_E:
			upgrade_id = UpgradeManager.UPGRADE_ARCHER_ATTACK
		KEY_R:
			upgrade_id = UpgradeManager.UPGRADE_ARCHER_ATTACK_SPEED
		KEY_T:
			upgrade_id = UpgradeManager.UPGRADE_ARCHER_RANGE
		_:
			return false

	if UpgradeManager.is_max_level(upgrade_id):
		get_viewport().set_input_as_handled()
		return true

	if _selected_blacksmith.try_research_upgrade(upgrade_id):
		_update_blacksmith_upgrade_ui()

	get_viewport().set_input_as_handled()
	return true


func _get_tracked_hero_for_input() -> Hero:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return null

	if selection_manager.selected_building != null:
		return null

	return selection_manager.get_primary_ui_hero()


func _set_hero_altar_button_labels() -> void:
	var cost_label := " (%d Gold, %d Food)" % [HeroAltar.TRAIN_GOLD_COST, HeroAltar.TRAIN_FOOD_COST]
	_train_hero_button.text = "Train Hero%s" % cost_label


func _set_barracks_button_labels() -> void:
	var spearman_cost_label := " (%d Gold, %d Food)" % [
		Barracks.get_unit_train_gold_cost(Barracks.TRAIN_ID_SPEARMAN),
		Barracks.TRAIN_FOOD_COST,
	]
	var cost_label := " (%d Gold, %d Food)" % [Barracks.TRAIN_GOLD_COST, Barracks.TRAIN_FOOD_COST]
	_train_spearman_base_label = "Train Spearman%s" % spearman_cost_label
	_train_swordsman_base_label = "Train Swordsman%s" % cost_label
	_train_archer_base_label = "Train Archer%s" % cost_label
	_update_barracks_button_labels()


func _set_town_center_button_labels() -> void:
	var cost_label := " (%d Gold, %d Food)" % [CommandCenter.TRAIN_GOLD_COST, CommandCenter.TRAIN_FOOD_COST]
	_train_worker_base_label = "Train Worker%s" % cost_label
	_update_town_center_button_labels()


func _update_town_center_button_labels() -> void:
	var label: String = _train_worker_base_label
	if (
		_selected_command_center != null
		and _selected_command_center.is_repeat_training_enabled(CommandCenter.TRAIN_ID_WORKER)
	):
		label += " [Repeat: ON]"
	_train_worker_button.text = label


func _update_barracks_button_labels() -> void:
	var spearman_label: String = _train_spearman_base_label
	var swordsman_label: String = _train_swordsman_base_label
	var archer_label: String = _train_archer_base_label
	if _selected_barracks != null:
		if _selected_barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_SPEARMAN):
			spearman_label += " [Repeat: ON]"
		if _selected_barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_SWORDSMAN):
			swordsman_label += " [Repeat: ON]"
		if _selected_barracks.is_repeat_training_enabled(Barracks.TRAIN_ID_ARCHER):
			archer_label += " [Repeat: ON]"
	_train_spearman_button.text = spearman_label
	_train_swordsman_button.text = swordsman_label
	_train_archer_button.text = archer_label


func _update_auto_training_label() -> void:
	if _auto_training_label == null:
		return

	var auto_training_name: String = ""
	if _selected_command_center != null:
		auto_training_name = _selected_command_center.get_repeat_unit_display_name()
	elif _selected_barracks != null:
		auto_training_name = _selected_barracks.get_repeat_unit_display_name()

	if auto_training_name.is_empty():
		_auto_training_label.visible = false
		_auto_training_label.text = ""
	else:
		_auto_training_label.visible = true
		_auto_training_label.text = "Auto-training: %s" % auto_training_name


func _clear_queue_row(row: HBoxContainer) -> void:
	if row == null:
		return

	for child: Node in row.get_children():
		child.queue_free()

	row.visible = false


func _create_queue_row(reference_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.visible = false
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)

	var parent: Node = reference_label.get_parent()
	var label_index: int = reference_label.get_index()
	parent.add_child(row)
	parent.move_child(row, label_index)

	reference_label.visible = false
	return row


func _rebuild_worker_queue_slots() -> void:
	if _worker_queue_row == null or _selected_command_center == null:
		return

	var queue_count: int = _selected_command_center.get_worker_queue_count()
	var in_progress: bool = _selected_command_center.is_training_worker()
	_rebuild_queue_slots(
		_worker_queue_row,
		queue_count,
		in_progress,
		CommandCenter.TRAIN_ID_WORKER,
		"W"
	)


func _rebuild_swordsman_queue_slots() -> void:
	_rebuild_barracks_queue_slots()


func _rebuild_archer_queue_slots() -> void:
	pass


func _rebuild_barracks_queue_slots() -> void:
	if _swordsman_queue_row == null or _tracked_barracks == null:
		return

	_clear_queue_row(_archer_queue_row)

	var queue: Array[StringName] = _tracked_barracks.get_training_queue()
	var in_progress: bool = _tracked_barracks.has_active_unit_training()

	for child: Node in _swordsman_queue_row.get_children():
		child.queue_free()

	_swordsman_queue_row.visible = queue.size() > 0
	if queue.is_empty():
		return

	for slot_index: int in queue.size():
		var train_id: StringName = queue[slot_index]
		var slot_label: String
		if train_id == Barracks.TRAIN_ID_SPEARMAN:
			slot_label = "SP"
		elif train_id == Barracks.TRAIN_ID_SWORDSMAN:
			slot_label = "SW"
		elif train_id == Barracks.TRAIN_ID_ARCHER:
			slot_label = "AR"
		var slot_in_progress: bool = in_progress and slot_index == 0
		var slot: PanelContainer = _create_queue_slot(slot_index, train_id, slot_in_progress, slot_label)
		_swordsman_queue_row.add_child(slot)


func _rebuild_hero_queue_slots() -> void:
	if _hero_queue_row == null or _tracked_hero_altar == null:
		return

	for child: Node in _hero_queue_row.get_children():
		child.queue_free()

	var is_training: bool = _tracked_hero_altar.is_training_hero()
	_hero_queue_row.visible = is_training

	if not is_training:
		return

	var slot: PanelContainer = _create_queue_slot(0, &"hero", true, "H")
	_hero_queue_row.add_child(slot)


func _rebuild_queue_slots(
	row: HBoxContainer,
	queue_count: int,
	in_progress: bool,
	train_id: StringName,
	slot_label: String
) -> void:
	for child: Node in row.get_children():
		child.queue_free()

	row.visible = queue_count > 0
	if queue_count <= 0:
		return

	for slot_index: int in queue_count:
		var slot_in_progress: bool = slot_index == 0 and in_progress
		var slot: PanelContainer = _create_queue_slot(slot_index, train_id, slot_in_progress, slot_label)
		row.add_child(slot)


func _create_queue_slot(
	slot_index: int,
	train_id: StringName,
	in_progress: bool,
	slot_label: String
) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = QUEUE_SLOT_SIZE
	slot.tooltip_text = ""
	TooltipManager.bind_static_tooltip(slot, QUEUE_SLOT_HINT)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = QUEUE_SLOT_TRAINING_COLOR if in_progress else QUEUE_SLOT_COLOR
	style.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = slot_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)

	slot.gui_input.connect(func(event: InputEvent) -> void:
		_on_queue_slot_gui_input(slot, event, train_id, slot_index)
	)
	return slot


func _on_queue_slot_gui_input(slot: Control, event: InputEvent, train_id: StringName, slot_index: int) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return

	slot.accept_event()

	var cancelled: bool = _try_cancel_production_at_slot(train_id, slot_index)
	if not cancelled:
		return

	_rebuild_worker_queue_slots()
	_rebuild_swordsman_queue_slots()
	_rebuild_archer_queue_slots()
	_rebuild_hero_queue_slots()
	_update_auto_training_label()
	_update_town_center_button_labels()
	_update_barracks_button_labels()


func _try_cancel_production_at_slot(train_id: StringName, slot_index: int) -> bool:
	if train_id == CommandCenter.TRAIN_ID_WORKER:
		if _selected_command_center == null:
			return false

		return _selected_command_center.cancel_worker_training_at(slot_index)

	if train_id == Barracks.TRAIN_ID_SPEARMAN or train_id == Barracks.TRAIN_ID_SWORDSMAN or train_id == Barracks.TRAIN_ID_ARCHER:
		var barracks: Barracks = _get_barracks_for_queue_cancel()
		if barracks == null:
			return false

		return barracks.cancel_training_at(slot_index)

	if train_id == &"hero":
		if _selected_hero_altar == null or slot_index != 0:
			return false

		return _selected_hero_altar.cancel_hero_training()

	return false


func _get_barracks_for_queue_cancel() -> Barracks:
	if _selected_barracks != null and is_instance_valid(_selected_barracks):
		return _selected_barracks

	if _tracked_barracks != null and is_instance_valid(_tracked_barracks):
		return _tracked_barracks

	return null


func _on_selection_changed(_units: Array[Unit]) -> void:
	_refresh_command_visibility()


func _set_tracked_hero(hero: Hero) -> void:
	_disconnect_tracked_hero_signals()
	if hero != null and is_instance_valid(hero):
		_tracked_hero = hero
	else:
		_tracked_hero = null
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		if not _tracked_hero.ability_progression_changed.is_connected(_on_tracked_hero_progression_changed):
			_tracked_hero.ability_progression_changed.connect(_on_tracked_hero_progression_changed)
		if not _tracked_hero.ability_points_changed.is_connected(_on_tracked_hero_progression_changed):
			_tracked_hero.ability_points_changed.connect(_on_tracked_hero_progression_changed)
		if not _tracked_hero.level_changed.is_connected(_on_tracked_hero_progression_changed):
			_tracked_hero.level_changed.connect(_on_tracked_hero_progression_changed)
	_update_hero_abilities_ui()


func _disconnect_tracked_hero_signals() -> void:
	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		return

	if _tracked_hero.ability_progression_changed.is_connected(_on_tracked_hero_progression_changed):
		_tracked_hero.ability_progression_changed.disconnect(_on_tracked_hero_progression_changed)
	if _tracked_hero.ability_points_changed.is_connected(_on_tracked_hero_progression_changed):
		_tracked_hero.ability_points_changed.disconnect(_on_tracked_hero_progression_changed)
	if _tracked_hero.level_changed.is_connected(_on_tracked_hero_progression_changed):
		_tracked_hero.level_changed.disconnect(_on_tracked_hero_progression_changed)


func _on_tracked_hero_progression_changed(_unused = null) -> void:
	_update_hero_abilities_ui()


func _update_hero_abilities_ui() -> void:
	_update_ground_slam_ui()
	_update_divine_protection_ui()
	_update_power_strike_ui()
	_update_execute_ui()
	_update_all_hero_upgrade_arrows()


func _get_ability_slot_label(ability_id: StringName) -> String:
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			return "Q"
		HeroAbilityProgression.ABILITY_W:
			return "W"
		HeroAbilityProgression.ABILITY_E:
			return "E"
		HeroAbilityProgression.ABILITY_R:
			return "R"
		_:
			return String(ability_id)


func _hide_all_hero_upgrade_buttons() -> void:
	_update_upgrade_arrow(_ground_slam_upgrade_button, HeroAbilityProgression.ABILITY_Q, null)
	_update_upgrade_arrow(_divine_protection_upgrade_button, HeroAbilityProgression.ABILITY_W, null)
	_update_upgrade_arrow(_power_strike_upgrade_button, HeroAbilityProgression.ABILITY_E, null)
	_update_upgrade_arrow(_execute_upgrade_button, HeroAbilityProgression.ABILITY_R, null)


func _update_all_hero_upgrade_arrows() -> void:
	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_hide_all_hero_upgrade_buttons()
		return

	_update_upgrade_arrow(
		_ground_slam_upgrade_button,
		HeroAbilityProgression.ABILITY_Q,
		_tracked_hero
	)
	_update_upgrade_arrow(
		_divine_protection_upgrade_button,
		HeroAbilityProgression.ABILITY_W,
		_tracked_hero
	)
	_update_upgrade_arrow(
		_power_strike_upgrade_button,
		HeroAbilityProgression.ABILITY_E,
		_tracked_hero
	)
	_update_upgrade_arrow(
		_execute_upgrade_button,
		HeroAbilityProgression.ABILITY_R,
		_tracked_hero
	)


func _update_upgrade_arrow(upgrade_button: Button, ability_id: StringName, hero: Hero) -> void:
	if upgrade_button == null:
		return

	if hero == null or not is_instance_valid(hero):
		upgrade_button.visible = false
		upgrade_button.disabled = true
		return

	var current_rank: int = hero.get_ability_rank(ability_id)
	var max_rank: int = hero.get_ability_max_rank(ability_id)
	var can_upgrade: bool = hero.can_learn_ability(ability_id)
	var show_button: bool = current_rank < max_rank

	upgrade_button.visible = show_button
	upgrade_button.disabled = not can_upgrade


func _format_ability_label(
	slot_label: String, hero: Hero, ability_id: StringName, status_text: String
) -> String:
	var rank: int = hero.get_ability_rank(ability_id)
	var max_rank: int = hero.get_ability_max_rank(ability_id)
	if rank <= 0:
		if status_text.is_empty():
			return "%s: Locked (%d/%d)" % [slot_label, rank, max_rank]
		return "%s: Locked (%d/%d) — %s" % [slot_label, rank, max_rank, status_text]

	if status_text.is_empty():
		return "%s: Rank %d/%d" % [slot_label, rank, max_rank]
	return "%s: %s (%d/%d)" % [slot_label, status_text, rank, max_rank]


func _try_learn_ability_from_ui(ability_id: StringName) -> void:
	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		return

	_tracked_hero.try_learn_ability(ability_id)
	_update_hero_abilities_ui()


func _update_ground_slam_ui() -> void:
	if _ground_slam_button == null or _ground_slam_cooldown_label == null:
		return

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_ground_slam_button.disabled = true
		_ground_slam_cooldown_label.text = "Q: Locked"
		return

	var ability_id: StringName = HeroAbilityProgression.ABILITY_Q
	if not _tracked_hero.is_ability_unlocked(ability_id):
		_ground_slam_button.disabled = true
		_ground_slam_cooldown_label.text = _format_ability_label("Q", _tracked_hero, ability_id, "")
		return

	var remaining: float = _tracked_hero.get_ground_slam_cooldown_remaining()
	if remaining > 0.0:
		_ground_slam_button.disabled = true
		_ground_slam_cooldown_label.text = _format_ability_label(
			"Q", _tracked_hero, ability_id, "%.1fs" % remaining
		)
	else:
		_ground_slam_button.disabled = false
		_ground_slam_cooldown_label.text = _format_ability_label(
			"Q", _tracked_hero, ability_id, "Ready"
		)


func _on_ground_slam_pressed() -> void:
	if _tracked_hero == null:
		return

	_tracked_hero.try_ground_slam()
	_update_hero_abilities_ui()


func _on_ground_slam_upgrade_pressed() -> void:
	_try_learn_ability_from_ui(HeroAbilityProgression.ABILITY_Q)


func _update_divine_protection_ui() -> void:
	if _divine_protection_button == null or _divine_protection_cooldown_label == null:
		return

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_divine_protection_button.disabled = true
		_divine_protection_cooldown_label.text = "W: Locked"
		return

	var ability_id: StringName = HeroAbilityProgression.ABILITY_W
	if not _tracked_hero.is_ability_unlocked(ability_id):
		_divine_protection_button.disabled = true
		_divine_protection_cooldown_label.text = _format_ability_label("W", _tracked_hero, ability_id, "")
		return

	if _tracked_hero.is_divine_protection_active():
		_divine_protection_button.disabled = true
		_divine_protection_cooldown_label.text = _format_ability_label(
			"W",
			_tracked_hero,
			ability_id,
			"Active %.1fs" % _tracked_hero.get_divine_protection_remaining()
		)
		return

	var cooldown_remaining: float = _tracked_hero.get_divine_protection_cooldown_remaining()
	if cooldown_remaining > 0.0:
		_divine_protection_button.disabled = true
		_divine_protection_cooldown_label.text = _format_ability_label(
			"W", _tracked_hero, ability_id, "%.1fs" % cooldown_remaining
		)
		return

	var has_mana: bool = _tracked_hero.current_mana >= _tracked_hero.get_divine_protection_mana_cost()
	_divine_protection_button.disabled = not has_mana
	_divine_protection_cooldown_label.text = _format_ability_label(
		"W", _tracked_hero, ability_id, "Ready"
	)


func _on_divine_protection_pressed() -> void:
	if _tracked_hero == null:
		return

	_tracked_hero.try_divine_protection()
	_update_hero_abilities_ui()


func _on_divine_protection_upgrade_pressed() -> void:
	_try_learn_ability_from_ui(HeroAbilityProgression.ABILITY_W)


func _update_power_strike_ui() -> void:
	if _power_strike_button == null or _power_strike_cooldown_label == null:
		return

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_power_strike_button.disabled = true
		_power_strike_cooldown_label.text = "E: Locked"
		return

	var ability_id: StringName = HeroAbilityProgression.ABILITY_E
	if not _tracked_hero.is_ability_unlocked(ability_id):
		_power_strike_button.disabled = true
		_power_strike_cooldown_label.text = _format_ability_label("E", _tracked_hero, ability_id, "")
		return

	if _tracked_hero.is_power_strike_pending():
		_power_strike_button.disabled = true
		_power_strike_cooldown_label.text = _format_ability_label(
			"E", _tracked_hero, ability_id, "Moving..."
		)
		return

	var cooldown_remaining: float = _tracked_hero.get_power_strike_cooldown_remaining()
	if cooldown_remaining > 0.0:
		_power_strike_button.disabled = true
		_power_strike_cooldown_label.text = _format_ability_label(
			"E", _tracked_hero, ability_id, "%.1fs" % cooldown_remaining
		)
		return

	var has_mana: bool = _tracked_hero.current_mana >= _tracked_hero.get_power_strike_mana_cost()
	_power_strike_button.disabled = not has_mana
	_power_strike_cooldown_label.text = _format_ability_label(
		"E", _tracked_hero, ability_id, "Ready"
	)


func _on_power_strike_pressed() -> void:
	if _tracked_hero == null:
		return

	_tracked_hero.try_power_strike()
	_update_hero_abilities_ui()


func _on_power_strike_upgrade_pressed() -> void:
	_try_learn_ability_from_ui(HeroAbilityProgression.ABILITY_E)


func _update_execute_ui() -> void:
	if _execute_button == null or _execute_cooldown_label == null:
		return

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_execute_button.disabled = true
		_execute_cooldown_label.text = "R: Locked"
		return

	var ability_id: StringName = HeroAbilityProgression.ABILITY_R
	if not _tracked_hero.is_ability_unlocked(ability_id):
		_execute_button.disabled = true
		var required_level: int = HeroAbilityProgression.R_FIRST_RANK_LEVEL
		if _tracked_hero.level < required_level:
			_execute_cooldown_label.text = _format_ability_label(
				"R", _tracked_hero, ability_id, "Lv %d" % required_level
			)
		else:
			_execute_cooldown_label.text = _format_ability_label(
				"R", _tracked_hero, ability_id, ""
			)
		return

	if _tracked_hero.is_execute_pending():
		_execute_button.disabled = true
		_execute_cooldown_label.text = _format_ability_label(
			"R", _tracked_hero, ability_id, "Moving..."
		)
		return

	var cooldown_remaining: float = _tracked_hero.get_execute_cooldown_remaining()
	if cooldown_remaining > 0.0:
		_execute_button.disabled = true
		_execute_cooldown_label.text = _format_ability_label(
			"R", _tracked_hero, ability_id, "%.1fs" % cooldown_remaining
		)
		return

	var has_mana: bool = _tracked_hero.current_mana >= _tracked_hero.get_execute_mana_cost()
	_execute_button.disabled = not has_mana
	_execute_cooldown_label.text = _format_ability_label(
		"R", _tracked_hero, ability_id, "Ready"
	)


func _on_execute_pressed() -> void:
	if _tracked_hero == null:
		return

	_tracked_hero.try_execute()
	_update_hero_abilities_ui()


func _on_execute_upgrade_pressed() -> void:
	_try_learn_ability_from_ui(HeroAbilityProgression.ABILITY_R)


func _on_building_selection_changed(building: Building) -> void:
	_disconnect_worker_queue_signal()
	_disconnect_barracks_signals()
	_disconnect_stable_signals()
	_disconnect_artillery_depot_signals()
	_disconnect_hero_altar_signals()
	_disconnect_blacksmith_signals()
	_disconnect_shop_signals()
	_selected_command_center = null

	if building != null and not is_instance_valid(building):
		building = null

	if building is CommandCenter and is_instance_valid(building):
		_selected_command_center = building as CommandCenter
		_selected_command_center.worker_queue_changed.connect(_on_worker_queue_changed)
		_selected_command_center.repeat_state_changed.connect(_on_production_repeat_state_changed)
		if not _selected_command_center.tier_state_changed.is_connected(_on_command_center_tier_state_changed):
			_selected_command_center.tier_state_changed.connect(_on_command_center_tier_state_changed)
		_on_worker_queue_changed(_selected_command_center.get_worker_queue_count())
		_set_town_center_button_labels()
		_update_town_center_button_labels()
	else:
		_clear_queue_row(_worker_queue_row)

	if building is Barracks and is_instance_valid(building):
		_tracked_barracks = building as Barracks
		_tracked_barracks.building_state_changed.connect(_on_barracks_state_changed)
		_tracked_barracks.swordsman_queue_changed.connect(_on_swordsman_queue_changed)
		_tracked_barracks.archer_queue_changed.connect(_on_archer_queue_changed)
		if _tracked_barracks.has_signal("training_queue_changed"):
			_tracked_barracks.training_queue_changed.connect(_on_barracks_training_queue_changed)
		_tracked_barracks.repeat_state_changed.connect(_on_production_repeat_state_changed)
		_on_barracks_training_queue_changed()
		_update_barracks_button_labels()
	else:
		_clear_queue_row(_swordsman_queue_row)
		_clear_queue_row(_archer_queue_row)

	if building is Stable and is_instance_valid(building):
		_tracked_stable = building as Stable
		_tracked_stable.building_state_changed.connect(_on_stable_state_changed)
		_tracked_stable.heavy_cavalry_queue_changed.connect(_on_stable_queue_changed)
		_tracked_stable.light_cavalry_queue_changed.connect(_on_stable_queue_changed)
		_tracked_stable.cavalry_archer_queue_changed.connect(_on_stable_queue_changed)
		if _tracked_stable.has_signal("training_queue_changed"):
			_tracked_stable.training_queue_changed.connect(_on_stable_training_queue_changed)
		_tracked_stable.repeat_state_changed.connect(_on_production_repeat_state_changed)
		_on_stable_training_queue_changed()
	else:
		_tracked_stable = null

	if building is ArtilleryDepot and is_instance_valid(building):
		_tracked_artillery_depot = building as ArtilleryDepot
		_tracked_artillery_depot.building_state_changed.connect(_on_artillery_depot_state_changed)
		_tracked_artillery_depot.cannon_queue_changed.connect(_on_artillery_depot_queue_changed)
		if _tracked_artillery_depot.has_signal("training_queue_changed"):
			_tracked_artillery_depot.training_queue_changed.connect(_on_artillery_depot_training_queue_changed)
		_tracked_artillery_depot.repeat_state_changed.connect(_on_production_repeat_state_changed)
		_on_artillery_depot_training_queue_changed()
	else:
		_tracked_artillery_depot = null

	if building is HeroAltar and is_instance_valid(building):
		_tracked_hero_altar = building as HeroAltar
		_tracked_hero_altar.building_state_changed.connect(_on_hero_altar_state_changed)
		_tracked_hero_altar.hero_altar_state_changed.connect(_on_hero_altar_state_changed)
		_update_hero_altar_status()
	else:
		_hero_status_label.text = "Hero: Ready to train"
		_clear_queue_row(_hero_queue_row)

	if building is Blacksmith and is_instance_valid(building):
		_tracked_blacksmith = building as Blacksmith
		_tracked_blacksmith.building_state_changed.connect(_on_blacksmith_state_changed)
		if not _tracked_blacksmith.research_state_changed.is_connected(_on_blacksmith_research_state_changed):
			_tracked_blacksmith.research_state_changed.connect(_on_blacksmith_research_state_changed)
	else:
		_tracked_blacksmith = null

	if building is Shop and is_instance_valid(building):
		_tracked_shop = building as Shop
		_tracked_shop.building_state_changed.connect(_on_shop_state_changed)
	else:
		_tracked_shop = null

	_refresh_command_visibility()


func _on_barracks_state_changed(_state: StringName) -> void:
	_refresh_command_visibility()


func _on_stable_state_changed(_state: StringName) -> void:
	_refresh_command_visibility()


func _on_artillery_depot_state_changed(_state: StringName) -> void:
	_refresh_command_visibility()


func _on_artillery_depot_queue_changed(_queue_count: int) -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_artillery_depot_production_slots()


func _on_artillery_depot_training_queue_changed() -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_artillery_depot_production_slots()
	else:
		_update_auto_training_label()


func _on_stable_queue_changed(_queue_count: int) -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_stable_production_slots()


func _on_stable_training_queue_changed() -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_stable_production_slots()
	else:
		_update_auto_training_label()


func _on_blacksmith_state_changed(_state: StringName) -> void:
	_refresh_command_visibility()
	_update_blacksmith_upgrade_ui()
	if _barracks_training_row.visible:
		_refresh_barracks_production_slots()


func _on_blacksmith_research_state_changed() -> void:
	_update_blacksmith_upgrade_ui()


func _on_shop_state_changed(_state: StringName) -> void:
	_refresh_command_visibility()
	_update_shop_item_ui()


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
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_hero_altar_production_slot()
	else:
		_rebuild_hero_queue_slots()


func _refresh_command_visibility() -> void:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		visible = false
		return

	if selection_manager.has_method("purge_invalid_selection"):
		selection_manager.purge_invalid_selection()

	var selected_units: Array[Unit] = selection_manager.selected_units
	var selected_building: Building = selection_manager.selected_building
	if selected_building != null and not is_instance_valid(selected_building):
		selected_building = null
	var nothing_selected: bool = selected_units.is_empty() and selected_building == null

	if nothing_selected:
		_set_tracked_hero(null)
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
	var show_blacksmith_upgrades: bool = (
		selected_building is Blacksmith
		and (selected_building as Blacksmith).can_research()
	)
	var show_stable_commands: bool = (
		selected_building is Stable
		and (selected_building as Stable).can_show_commands()
	)
	var show_artillery_depot_commands: bool = (
		selected_building is ArtilleryDepot
		and (selected_building as ArtilleryDepot).can_show_commands()
	)
	var show_academy_commands: bool = (
		selected_building is Academy
		and (selected_building as Academy).can_show_commands()
	)
	var show_shop_items: bool = (
		selected_building is Shop
		and (selected_building as Shop).can_show_purchase_ui()
	)
	var show_town_center_commands: bool = selected_building is CommandCenter

	_selected_barracks = selected_building as Barracks if show_barracks_training else null
	_selected_blacksmith = selected_building as Blacksmith if show_blacksmith_upgrades else null
	_selected_shop = selected_building as Shop if show_shop_items else null
	_selected_hero_altar = selected_building as HeroAltar if show_hero_altar_training else null
	_selected_stable = selected_building as Stable if show_stable_commands else null
	_selected_artillery_depot = (
		selected_building as ArtilleryDepot if show_artillery_depot_commands else null
	)
	_selected_academy = selected_building as Academy if show_academy_commands else null

	if not selected_units.is_empty() and selected_building == null and selected_units.size() > 1:
		var multi_info: Dictionary = selection_manager.get_multi_selection_ui_info()
		var primary_hero: Hero = multi_info.primary_hero
		if primary_hero != null:
			_apply_hero_command_visibility()
			_set_tracked_hero(primary_hero)
			visible = true
			return

		var multi_category: StringName = multi_info.category
		if multi_category == &"workers":
			_apply_worker_command_visibility()
			_set_tracked_hero(null)
			visible = true
			return
		if multi_category == &"combat":
			_apply_combat_command_visibility()
			_set_tracked_hero(null)
			visible = true
			return
		_set_tracked_hero(null)
		visible = false
		return

	var single_unit: Unit = selected_units[0] if not selected_units.is_empty() else null
	if not selected_units.is_empty() and not NodeSafety.is_alive_node(single_unit):
		_set_tracked_hero(null)
		visible = false
		return

	var single_worker: bool = selected_units.size() == 1 and single_unit is Worker
	var single_hero: bool = selected_units.size() == 1 and single_unit is Hero
	var single_combat_unit: bool = (
		selected_units.size() == 1
		and (single_unit is Spearman or single_unit is Swordsman or single_unit is Archer or single_unit is HeavyCavalry or single_unit is LightCavalry or single_unit is CavalryArcher or single_unit is Cannon or single_unit is Hero)
	)

	if single_worker:
		_apply_worker_command_visibility()
		_set_tracked_hero(null)
	elif single_hero:
		_apply_hero_command_visibility()
		_set_tracked_hero(single_unit as Hero)
	elif single_combat_unit:
		_apply_combat_command_visibility()
		_set_tracked_hero(null)
	elif show_town_center_commands:
		_apply_town_center_command_visibility()
		_set_tracked_hero(null)
	elif show_blacksmith_upgrades:
		_apply_blacksmith_command_visibility()
		_set_tracked_hero(null)
	elif show_stable_commands:
		_apply_stable_command_visibility()
		_set_tracked_hero(null)
	elif show_artillery_depot_commands:
		_apply_artillery_depot_command_visibility()
		_set_tracked_hero(null)
	elif show_academy_commands:
		_apply_academy_command_visibility()
		_set_tracked_hero(null)
	elif show_shop_items:
		_apply_shop_command_visibility()
		_set_tracked_hero(null)
	elif show_barracks_training:
		_apply_barracks_command_visibility()
		_set_tracked_hero(null)
	elif show_hero_altar_training:
		_apply_hero_altar_command_visibility()
		_set_tracked_hero(null)
	else:
		_apply_hidden_command_buttons()
		_set_tracked_hero(null)

	_center_panel.visible = (
		show_town_center_commands or show_barracks_training or show_hero_altar_training
	)
	_barracks_panel.visible = show_barracks_training
	_barracks_training_row.visible = show_barracks_training
	_hero_altar_panel.visible = show_hero_altar_training
	_hero_altar_training_row.visible = show_hero_altar_training
	_blacksmith_panel.visible = show_blacksmith_upgrades
	_stable_panel.visible = show_stable_commands
	_stable_training_row.visible = show_stable_commands
	_artillery_depot_panel.visible = show_artillery_depot_commands
	_artillery_depot_training_row.visible = show_artillery_depot_commands
	_academy_panel.visible = show_academy_commands
	_shop_panel.visible = show_shop_items
	_hero_panel.visible = single_hero

	if show_blacksmith_upgrades:
		_update_blacksmith_upgrade_ui()

	if show_shop_items:
		_update_shop_item_ui()

	if show_hero_altar_training:
		_update_hero_altar_status()

	if show_town_center_commands:
		if not USE_PRODUCTION_ICON_SLOTS:
			_rebuild_worker_queue_slots()
	if show_barracks_training:
		if not USE_PRODUCTION_ICON_SLOTS:
			_rebuild_swordsman_queue_slots()
			_rebuild_archer_queue_slots()
		_update_barracks_train_button_states()
	if show_stable_commands:
		_refresh_stable_production_slots()
	if show_artillery_depot_commands:
		_refresh_artillery_depot_production_slots()
	if show_hero_altar_training:
		if not USE_PRODUCTION_ICON_SLOTS:
			_rebuild_hero_queue_slots()
	else:
		_clear_queue_row(_hero_queue_row)

	if not show_town_center_commands:
		_clear_queue_row(_worker_queue_row)
	if not show_barracks_training:
		_clear_queue_row(_swordsman_queue_row)
		_clear_queue_row(_archer_queue_row)

	_set_production_icon_visibility(
		show_barracks_training,
		show_town_center_commands,
		show_hero_altar_training,
		show_stable_commands,
		show_artillery_depot_commands
	)

	_update_auto_training_label()

	visible = (
		single_worker
		or show_town_center_commands
		or show_barracks_training
		or show_hero_altar_training
		or show_blacksmith_upgrades
		or show_stable_commands
		or show_artillery_depot_commands
		or show_academy_commands
		or show_shop_items
		or single_combat_unit
	)
	_sync_ui_process()


func _sync_ui_process() -> void:
	var needs_refresh: bool = (
		(_tracked_hero != null and is_instance_valid(_tracked_hero))
		or _shop_panel.visible
		or _production_icons_visible()
	)
	set_process(needs_refresh)
	if not needs_refresh:
		_ui_refresh_timer = 0.0


func _apply_hero_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = true
	_buttons_row.visible = true
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_clear_queue_row(_worker_queue_row)
	_hero_panel.visible = true


func _apply_worker_command_visibility() -> void:
	_set_build_icon_visibility(true)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = true
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_clear_queue_row(_worker_queue_row)
	_hero_panel.visible = false


func _apply_combat_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = true
	_buttons_row.visible = true
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_clear_queue_row(_worker_queue_row)
	_hero_panel.visible = false


func _apply_barracks_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_panel.visible = true
	_barracks_training_row.visible = true
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_hero_panel.visible = false


func _apply_hero_altar_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = true
	_hero_altar_training_row.visible = true
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_hero_panel.visible = false


func _apply_town_center_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = true
	_attack_button.visible = false
	_buttons_row.visible = true
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_hero_panel.visible = false


func _apply_blacksmith_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_hero_panel.visible = false
	_blacksmith_panel.visible = true
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_clear_queue_row(_worker_queue_row)
	_clear_queue_row(_swordsman_queue_row)
	_clear_queue_row(_archer_queue_row)
	_clear_queue_row(_hero_queue_row)


func _apply_stable_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_hero_panel.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = true
	_stable_training_row.visible = true
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_shop_panel.visible = false
	_clear_queue_row(_worker_queue_row)
	_clear_queue_row(_swordsman_queue_row)
	_clear_queue_row(_archer_queue_row)
	_clear_queue_row(_hero_queue_row)
	_refresh_stable_production_slots()


func _apply_artillery_depot_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_hero_panel.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_stable_training_row.visible = false
	_artillery_depot_panel.visible = true
	_artillery_depot_training_row.visible = true
	_academy_panel.visible = false
	_shop_panel.visible = false
	_clear_queue_row(_worker_queue_row)
	_clear_queue_row(_swordsman_queue_row)
	_clear_queue_row(_archer_queue_row)
	_clear_queue_row(_hero_queue_row)
	_refresh_artillery_depot_production_slots()


func _apply_academy_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_hero_panel.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_stable_training_row.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = true
	_shop_panel.visible = false
	_clear_queue_row(_worker_queue_row)
	_clear_queue_row(_swordsman_queue_row)
	_clear_queue_row(_archer_queue_row)
	_clear_queue_row(_hero_queue_row)


func _apply_shop_command_visibility() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_panel.visible = false
	_barracks_training_row.visible = false
	_hero_altar_panel.visible = false
	_hero_altar_training_row.visible = false
	_hero_panel.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_shop_panel.visible = true
	_clear_queue_row(_worker_queue_row)
	_clear_queue_row(_swordsman_queue_row)
	_clear_queue_row(_archer_queue_row)
	_clear_queue_row(_hero_queue_row)


func _apply_hidden_command_buttons() -> void:
	_set_build_icon_visibility(false)
	_train_worker_button.visible = false
	_attack_button.visible = false
	_buttons_row.visible = false
	_barracks_training_row.visible = false
	_stable_training_row.visible = false
	_artillery_depot_panel.visible = false
	_artillery_depot_training_row.visible = false
	_academy_panel.visible = false
	_hero_altar_training_row.visible = false
	_blacksmith_panel.visible = false
	_stable_panel.visible = false
	_shop_panel.visible = false
	_hero_panel.visible = false


func _on_attack_pressed() -> void:
	InputManager.arm_attack_move()


func _on_worker_queue_changed(_queue_count: int) -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_town_center_production_slot()
	else:
		_rebuild_worker_queue_slots()


func _on_command_center_tier_state_changed() -> void:
	if _selected_command_center == null or not is_instance_valid(_selected_command_center):
		_selected_command_center = null
		return

	_refresh_town_center_production_slot()
	if _worker_build_icons_visible():
		_update_build_icon_slots()


func _on_swordsman_queue_changed(_queue_count: int) -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_barracks_production_slots()
	else:
		_rebuild_barracks_queue_slots()


func _on_archer_queue_changed(_queue_count: int) -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_barracks_production_slots()
	else:
		_rebuild_barracks_queue_slots()


func _on_barracks_training_queue_changed() -> void:
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_barracks_production_slots()
	else:
		_rebuild_barracks_queue_slots()


func _on_production_repeat_state_changed() -> void:
	_update_auto_training_label()
	_update_town_center_button_labels()
	_update_barracks_button_labels()
	if USE_PRODUCTION_ICON_SLOTS:
		_refresh_all_production_slots()


func _disconnect_worker_queue_signal() -> void:
	if _selected_command_center != null and is_instance_valid(_selected_command_center):
		if _selected_command_center.worker_queue_changed.is_connected(_on_worker_queue_changed):
			_selected_command_center.worker_queue_changed.disconnect(_on_worker_queue_changed)

		if _selected_command_center.repeat_state_changed.is_connected(_on_production_repeat_state_changed):
			_selected_command_center.repeat_state_changed.disconnect(_on_production_repeat_state_changed)

		if _selected_command_center.tier_state_changed.is_connected(_on_command_center_tier_state_changed):
			_selected_command_center.tier_state_changed.disconnect(_on_command_center_tier_state_changed)

	_selected_command_center = null


func _disconnect_barracks_signals() -> void:
	if _tracked_barracks != null and is_instance_valid(_tracked_barracks):
		if _tracked_barracks.building_state_changed.is_connected(_on_barracks_state_changed):
			_tracked_barracks.building_state_changed.disconnect(_on_barracks_state_changed)

		if _tracked_barracks.swordsman_queue_changed.is_connected(_on_swordsman_queue_changed):
			_tracked_barracks.swordsman_queue_changed.disconnect(_on_swordsman_queue_changed)

		if _tracked_barracks.archer_queue_changed.is_connected(_on_archer_queue_changed):
			_tracked_barracks.archer_queue_changed.disconnect(_on_archer_queue_changed)

		if (
			_tracked_barracks.has_signal("training_queue_changed")
			and _tracked_barracks.training_queue_changed.is_connected(_on_barracks_training_queue_changed)
		):
			_tracked_barracks.training_queue_changed.disconnect(_on_barracks_training_queue_changed)

		if _tracked_barracks.repeat_state_changed.is_connected(_on_production_repeat_state_changed):
			_tracked_barracks.repeat_state_changed.disconnect(_on_production_repeat_state_changed)

	_tracked_barracks = null


func _disconnect_stable_signals() -> void:
	if _tracked_stable != null and is_instance_valid(_tracked_stable):
		if _tracked_stable.building_state_changed.is_connected(_on_stable_state_changed):
			_tracked_stable.building_state_changed.disconnect(_on_stable_state_changed)

		if _tracked_stable.heavy_cavalry_queue_changed.is_connected(_on_stable_queue_changed):
			_tracked_stable.heavy_cavalry_queue_changed.disconnect(_on_stable_queue_changed)

		if _tracked_stable.light_cavalry_queue_changed.is_connected(_on_stable_queue_changed):
			_tracked_stable.light_cavalry_queue_changed.disconnect(_on_stable_queue_changed)

		if _tracked_stable.cavalry_archer_queue_changed.is_connected(_on_stable_queue_changed):
			_tracked_stable.cavalry_archer_queue_changed.disconnect(_on_stable_queue_changed)

		if (
			_tracked_stable.has_signal("training_queue_changed")
			and _tracked_stable.training_queue_changed.is_connected(_on_stable_training_queue_changed)
		):
			_tracked_stable.training_queue_changed.disconnect(_on_stable_training_queue_changed)

		if _tracked_stable.repeat_state_changed.is_connected(_on_production_repeat_state_changed):
			_tracked_stable.repeat_state_changed.disconnect(_on_production_repeat_state_changed)

	_tracked_stable = null


func _disconnect_artillery_depot_signals() -> void:
	if _tracked_artillery_depot != null and is_instance_valid(_tracked_artillery_depot):
		if _tracked_artillery_depot.building_state_changed.is_connected(_on_artillery_depot_state_changed):
			_tracked_artillery_depot.building_state_changed.disconnect(_on_artillery_depot_state_changed)

		if _tracked_artillery_depot.cannon_queue_changed.is_connected(_on_artillery_depot_queue_changed):
			_tracked_artillery_depot.cannon_queue_changed.disconnect(_on_artillery_depot_queue_changed)

		if (
			_tracked_artillery_depot.has_signal("training_queue_changed")
			and _tracked_artillery_depot.training_queue_changed.is_connected(
				_on_artillery_depot_training_queue_changed
			)
		):
			_tracked_artillery_depot.training_queue_changed.disconnect(_on_artillery_depot_training_queue_changed)

		if _tracked_artillery_depot.repeat_state_changed.is_connected(_on_production_repeat_state_changed):
			_tracked_artillery_depot.repeat_state_changed.disconnect(_on_production_repeat_state_changed)

	_tracked_artillery_depot = null


func _disconnect_hero_altar_signals() -> void:
	if _tracked_hero_altar != null and is_instance_valid(_tracked_hero_altar):
		if _tracked_hero_altar.building_state_changed.is_connected(_on_hero_altar_state_changed):
			_tracked_hero_altar.building_state_changed.disconnect(_on_hero_altar_state_changed)

		if _tracked_hero_altar.hero_altar_state_changed.is_connected(_on_hero_altar_state_changed):
			_tracked_hero_altar.hero_altar_state_changed.disconnect(_on_hero_altar_state_changed)

	_tracked_hero_altar = null


func _disconnect_blacksmith_signals() -> void:
	if _tracked_blacksmith != null and is_instance_valid(_tracked_blacksmith):
		if _tracked_blacksmith.building_state_changed.is_connected(_on_blacksmith_state_changed):
			_tracked_blacksmith.building_state_changed.disconnect(_on_blacksmith_state_changed)

		if _tracked_blacksmith.research_state_changed.is_connected(_on_blacksmith_research_state_changed):
			_tracked_blacksmith.research_state_changed.disconnect(_on_blacksmith_research_state_changed)

	_tracked_blacksmith = null


func _disconnect_shop_signals() -> void:
	if _tracked_shop != null and is_instance_valid(_tracked_shop):
		if _tracked_shop.building_state_changed.is_connected(_on_shop_state_changed):
			_tracked_shop.building_state_changed.disconnect(_on_shop_state_changed)

	_tracked_shop = null


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


func _on_build_blacksmith_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_blacksmith_placement()


func _on_build_stable_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_stable_placement()


func _on_build_artillery_depot_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_artillery_depot_placement()


func _on_build_academy_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_academy_placement()


func _on_build_shop_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_shop_placement()


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


func _on_build_command_center_pressed() -> void:
	var build_manager: Node = get_node_or_null(build_manager_path)
	if build_manager == null:
		return

	build_manager.start_command_center_placement()


func _on_train_worker_pressed() -> void:
	if _selected_command_center == null:
		return

	_selected_command_center.try_train_worker_with_repeat(Input.is_key_pressed(KEY_CTRL))
	_update_town_center_button_labels()
	_update_auto_training_label()
	_rebuild_worker_queue_slots()


func _on_train_spearman_pressed() -> void:
	if _selected_barracks == null:
		return

	_selected_barracks.try_train_spearman_with_repeat(Input.is_key_pressed(KEY_CTRL))
	_update_barracks_button_labels()
	_update_auto_training_label()
	_rebuild_swordsman_queue_slots()


func _on_train_swordsman_pressed() -> void:
	if _selected_barracks == null:
		return

	_selected_barracks.try_train_swordsman_with_repeat(Input.is_key_pressed(KEY_CTRL))
	_update_barracks_button_labels()
	_update_auto_training_label()
	_rebuild_swordsman_queue_slots()


func _on_train_archer_pressed() -> void:
	if _selected_barracks == null:
		return

	_selected_barracks.try_train_archer_with_repeat(Input.is_key_pressed(KEY_CTRL))
	_update_barracks_button_labels()
	_update_auto_training_label()
	_rebuild_archer_queue_slots()


func _on_train_hero_pressed() -> void:
	if _selected_hero_altar == null:
		return

	_selected_hero_altar.try_train_hero()


func _setup_command_tooltips() -> void:
	const BUILD_MANAGER := preload("res://scripts/systems/build_manager.gd")

	_clear_control_tooltip(_build_farm_button)
	_clear_control_tooltip(_build_barracks_button)
	_clear_control_tooltip(_build_blacksmith_button)
	_clear_control_tooltip(_build_stable_button)
	_clear_control_tooltip(_build_shop_button)
	_clear_control_tooltip(_build_tower_button)
	_clear_control_tooltip(_build_hero_altar_button)
	_clear_control_tooltip(_build_command_center_button)
	_clear_control_tooltip(_train_worker_button)
	_clear_control_tooltip(_train_spearman_button)
	_clear_control_tooltip(_train_swordsman_button)
	_clear_control_tooltip(_train_archer_button)
	_clear_control_tooltip(_train_hero_button)
	_clear_control_tooltip(_attack_button)
	_clear_control_tooltip(_ground_slam_button)
	_clear_control_tooltip(_ground_slam_upgrade_button)
	_clear_control_tooltip(_divine_protection_button)
	_clear_control_tooltip(_divine_protection_upgrade_button)
	_clear_control_tooltip(_power_strike_button)
	_clear_control_tooltip(_power_strike_upgrade_button)
	_clear_control_tooltip(_execute_button)
	_clear_control_tooltip(_execute_upgrade_button)

	TooltipManager.bind_control(
		_build_farm_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_FARM,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_FARM)
			)
	)
	TooltipManager.bind_control(
		_build_barracks_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_BARRACKS,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_BARRACKS)
			)
	)
	TooltipManager.bind_control(
		_build_blacksmith_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_BLACKSMITH,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_BLACKSMITH)
			)
	)
	TooltipManager.bind_control(
		_build_stable_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_STABLE,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_STABLE)
			)
	)
	TooltipManager.bind_control(
		_build_shop_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_SHOP,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_SHOP)
			)
	)
	TooltipManager.bind_control(
		_build_tower_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_TOWER,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_TOWER)
			)
	)
	TooltipManager.bind_control(
		_build_hero_altar_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_HERO_ALTAR,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_HERO_ALTAR)
			)
	)
	TooltipManager.bind_control(
		_build_command_center_button,
		func() -> String:
			return TooltipFormatter.format_build_placement(
				BUILD_MANAGER.PLACEMENT_COMMAND_CENTER,
				TooltipFormatter.get_build_blocked_reason(BUILD_MANAGER.PLACEMENT_COMMAND_CENTER)
			)
	)

	TooltipManager.bind_control(_train_worker_button, _get_train_worker_tooltip)
	TooltipManager.bind_control(_train_spearman_button, _get_train_spearman_tooltip)
	TooltipManager.bind_control(_train_swordsman_button, _get_train_swordsman_tooltip)
	TooltipManager.bind_control(_train_archer_button, _get_train_archer_tooltip)
	TooltipManager.bind_control(_train_hero_button, _get_train_hero_tooltip)
	TooltipManager.bind_static_tooltip(_attack_button, "Attack-move\nMove while engaging enemies.")

	TooltipManager.bind_control(
		_ground_slam_button,
		func() -> String:
			return TooltipFormatter.format_ability_cast(
				_tracked_hero, HeroAbilityProgression.ABILITY_Q, "Q"
			)
	)
	TooltipManager.bind_control(
		_ground_slam_upgrade_button,
		func() -> String:
			return TooltipFormatter.format_ability_upgrade(
				_tracked_hero, HeroAbilityProgression.ABILITY_Q, "Q"
			)
	)
	TooltipManager.bind_control(
		_divine_protection_button,
		func() -> String:
			return TooltipFormatter.format_ability_cast(
				_tracked_hero, HeroAbilityProgression.ABILITY_W, "W"
			)
	)
	TooltipManager.bind_control(
		_divine_protection_upgrade_button,
		func() -> String:
			return TooltipFormatter.format_ability_upgrade(
				_tracked_hero, HeroAbilityProgression.ABILITY_W, "W"
			)
	)
	TooltipManager.bind_control(
		_power_strike_button,
		func() -> String:
			return TooltipFormatter.format_ability_cast(
				_tracked_hero, HeroAbilityProgression.ABILITY_E, "E"
			)
	)
	TooltipManager.bind_control(
		_power_strike_upgrade_button,
		func() -> String:
			return TooltipFormatter.format_ability_upgrade(
				_tracked_hero, HeroAbilityProgression.ABILITY_E, "E"
			)
	)
	TooltipManager.bind_control(
		_execute_button,
		func() -> String:
			return TooltipFormatter.format_ability_cast(
				_tracked_hero, HeroAbilityProgression.ABILITY_R, "R"
			)
	)
	TooltipManager.bind_control(
		_execute_upgrade_button,
		func() -> String:
			return TooltipFormatter.format_ability_upgrade(
				_tracked_hero, HeroAbilityProgression.ABILITY_R, "R"
			)
	)

	for index: int in _blacksmith_upgrade_buttons.size():
		if index >= _blacksmith_upgrade_ids.size():
			break

		var upgrade_id: StringName = _blacksmith_upgrade_ids[index]
		var button: Button = _blacksmith_upgrade_buttons[index]
		_clear_control_tooltip(button)
		TooltipManager.bind_control(button, func() -> String: return _get_blacksmith_upgrade_tooltip(upgrade_id))

	for index: int in _shop_item_buttons.size():
		if index >= _shop_item_ids.size():
			break

		var item_id: StringName = _shop_item_ids[index]
		var button: Button = _shop_item_buttons[index]
		_clear_control_tooltip(button)
		TooltipManager.bind_control(button, func() -> String: return _get_shop_item_tooltip(item_id))


func _clear_control_tooltip(control: Control) -> void:
	if control == null:
		return

	control.tooltip_text = ""


func _get_train_worker_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Worker",
		CommandCenter.TRAIN_GOLD_COST,
		0,
		CommandCenter.TRAIN_FOOD_COST,
		CommandCenter.TRAIN_SECONDS,
		CommandCenter.TRAIN_ID_WORKER,
		TooltipFormatter.get_train_blocked_reason(
			CommandCenter.TRAIN_GOLD_COST, CommandCenter.TRAIN_FOOD_COST
		)
	)


func _get_town_center_upgrade_tooltip() -> String:
	if _selected_command_center == null or not is_instance_valid(_selected_command_center):
		return ""

	var target_tier: int = _selected_command_center.get_next_upgrade_tier()
	if target_tier <= 0:
		return ""

	var costs: Dictionary = CommandCenter.get_upgrade_costs(target_tier)
	var blocked_reason: String = ""
	if _selected_command_center.is_upgrading_tier():
		blocked_reason = "Upgrade in progress"
	elif _selected_command_center.is_training_worker() or _selected_command_center.get_worker_queue_count() > 0:
		blocked_reason = "Finish or cancel worker training first"
	elif not ResourceManager.can_afford(int(costs.gold), int(costs.wood)):
		blocked_reason = "Not enough resources"

	return TooltipFormatter.format_command_center_tier_upgrade(
		target_tier,
		int(costs.gold),
		int(costs.wood),
		float(costs.seconds),
		blocked_reason
	)


func _get_train_spearman_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Spearman",
		Barracks.get_unit_train_gold_cost(Barracks.TRAIN_ID_SPEARMAN),
		0,
		Barracks.TRAIN_FOOD_COST,
		Barracks.get_unit_train_seconds(Barracks.TRAIN_ID_SPEARMAN),
		Barracks.TRAIN_ID_SPEARMAN,
		TooltipFormatter.get_train_blocked_reason(
			Barracks.get_unit_train_gold_cost(Barracks.TRAIN_ID_SPEARMAN),
			Barracks.TRAIN_FOOD_COST
		)
	)


func _get_train_swordsman_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Swordsman",
		Barracks.TRAIN_GOLD_COST,
		0,
		Barracks.TRAIN_FOOD_COST,
		Barracks.TRAIN_SECONDS,
		Barracks.TRAIN_ID_SWORDSMAN,
		TooltipFormatter.get_train_blocked_reason_for_unit(
			Barracks.TRAIN_ID_SWORDSMAN,
			Barracks.TRAIN_GOLD_COST,
			Barracks.TRAIN_FOOD_COST
		)
	)


func _get_train_archer_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Archer",
		Barracks.TRAIN_GOLD_COST,
		0,
		Barracks.TRAIN_FOOD_COST,
		Barracks.TRAIN_SECONDS,
		Barracks.TRAIN_ID_ARCHER,
		TooltipFormatter.get_train_blocked_reason_for_unit(
			Barracks.TRAIN_ID_ARCHER,
			Barracks.TRAIN_GOLD_COST,
			Barracks.TRAIN_FOOD_COST
		)
	)


func _get_train_heavy_cavalry_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Heavy Cavalry",
		Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_HEAVY_CAVALRY),
		0,
		Stable.get_unit_train_food_cost(Stable.TRAIN_ID_HEAVY_CAVALRY),
		Stable.get_unit_train_seconds(Stable.TRAIN_ID_HEAVY_CAVALRY),
		Stable.TRAIN_ID_HEAVY_CAVALRY,
		TooltipFormatter.get_train_blocked_reason(
			Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_HEAVY_CAVALRY),
			Stable.get_unit_train_food_cost(Stable.TRAIN_ID_HEAVY_CAVALRY)
		)
	)


func _get_train_light_cavalry_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Light Cavalry",
		Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_LIGHT_CAVALRY),
		0,
		Stable.get_unit_train_food_cost(Stable.TRAIN_ID_LIGHT_CAVALRY),
		Stable.get_unit_train_seconds(Stable.TRAIN_ID_LIGHT_CAVALRY),
		Stable.TRAIN_ID_LIGHT_CAVALRY,
		TooltipFormatter.get_train_blocked_reason(
			Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_LIGHT_CAVALRY),
			Stable.get_unit_train_food_cost(Stable.TRAIN_ID_LIGHT_CAVALRY)
		)
	)


func _get_train_cavalry_archer_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Cavalry Archer",
		Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_CAVALRY_ARCHER),
		0,
		Stable.get_unit_train_food_cost(Stable.TRAIN_ID_CAVALRY_ARCHER),
		Stable.get_unit_train_seconds(Stable.TRAIN_ID_CAVALRY_ARCHER),
		Stable.TRAIN_ID_CAVALRY_ARCHER,
		TooltipFormatter.get_train_blocked_reason(
			Stable.get_unit_train_gold_cost(Stable.TRAIN_ID_CAVALRY_ARCHER),
			Stable.get_unit_train_food_cost(Stable.TRAIN_ID_CAVALRY_ARCHER)
		)
	)


func _get_train_cannon_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Cannon",
		ArtilleryDepot.get_unit_train_gold_cost(ArtilleryDepot.TRAIN_ID_CANNON),
		0,
		ArtilleryDepot.get_unit_train_food_cost(ArtilleryDepot.TRAIN_ID_CANNON),
		ArtilleryDepot.get_unit_train_seconds(ArtilleryDepot.TRAIN_ID_CANNON),
		ArtilleryDepot.TRAIN_ID_CANNON,
		TooltipFormatter.get_train_blocked_reason(
			ArtilleryDepot.get_unit_train_gold_cost(ArtilleryDepot.TRAIN_ID_CANNON),
			ArtilleryDepot.get_unit_train_food_cost(ArtilleryDepot.TRAIN_ID_CANNON)
		)
	)


func _get_train_hero_tooltip() -> String:
	return TooltipFormatter.format_train_command(
		"Hero",
		HeroAltar.TRAIN_GOLD_COST,
		0,
		HeroAltar.TRAIN_FOOD_COST,
		HeroAltar.TRAIN_SECONDS,
		&"hero",
		TooltipFormatter.get_hero_train_blocked_reason(_selected_hero_altar)
	)


func _get_blacksmith_upgrade_tooltip(upgrade_id: StringName) -> String:
	var is_researching: bool = (
		_selected_blacksmith != null
		and is_instance_valid(_selected_blacksmith)
		and _selected_blacksmith.is_researching()
	)
	return TooltipFormatter.format_upgrade_research(
		upgrade_id,
		TooltipFormatter.get_upgrade_blocked_reason(upgrade_id, is_researching),
		is_researching
	)


func _get_shop_item_tooltip(item_id: StringName) -> String:
	return TooltipFormatter.format_shop_item(
		item_id,
		TooltipFormatter.get_shop_item_blocked_reason(_selected_shop, item_id)
	)
