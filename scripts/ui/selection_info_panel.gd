extends PanelContainer

## Compact bottom-left panel for the current selection (portrait, bars, stats).

@export var selection_manager_path: NodePath = "../../../SelectionManager"

@onready var _portrait_color: ColorRect = $MarginContainer/HBoxContainer/PortraitFrame/PortraitColor
@onready var _portrait_label: Label = $MarginContainer/HBoxContainer/PortraitFrame/PortraitLabel
@onready var _name_label: Label = $MarginContainer/HBoxContainer/InfoVBox/NameLabel
@onready var _level_label: Label = $MarginContainer/HBoxContainer/InfoVBox/LevelLabel
@onready var _type_label: Label = $MarginContainer/HBoxContainer/InfoVBox/TypeLabel
@onready var _task_label: Label = $MarginContainer/HBoxContainer/InfoVBox/TaskLabel
@onready var _building_detail_label: Label = $MarginContainer/HBoxContainer/InfoVBox/BuildingDetailLabel
@onready var _hp_bar: ProgressBar = $MarginContainer/HBoxContainer/InfoVBox/HPBar
@onready var _mana_bar: ProgressBar = $MarginContainer/HBoxContainer/InfoVBox/ManaBar
@onready var _xp_bar: ProgressBar = $MarginContainer/HBoxContainer/InfoVBox/XPBar
@onready var _xp_label: Label = $MarginContainer/HBoxContainer/InfoVBox/XPBar/XPLabel
@onready var _health_label: Label = $MarginContainer/HBoxContainer/InfoVBox/HealthLabel
@onready var _mana_label: Label = $MarginContainer/HBoxContainer/InfoVBox/ManaLabel
@onready var _stats_row: HBoxContainer = $MarginContainer/HBoxContainer/InfoVBox/StatsRow
@onready var _damage_label: Label = $MarginContainer/HBoxContainer/InfoVBox/StatsRow/DamageLabel
@onready var _armor_label: Label = $MarginContainer/HBoxContainer/InfoVBox/StatsRow/ArmorLabel
@onready var _speed_label: Label = $MarginContainer/HBoxContainer/InfoVBox/StatsRow/SpeedLabel

var _tracked_health_component: HealthComponent = null
var _tracked_hero: Hero = null
var _tracked_command_center: CommandCenter = null
var _tracked_barracks: Barracks = null
var _tracked_hero_altar: HeroAltar = null
var _is_enemy_inspect: bool = false

const ENEMY_NAME_COLOR := Color(0.95, 0.35, 0.35, 1)
const ENEMY_ACCENT_COLOR := Color(0.75, 0.22, 0.22, 1)
const ENEMY_LEVEL_COLOR := Color(0.9, 0.55, 0.55, 1)
const ENEMY_STAT_COLOR := Color(0.85, 0.5, 0.5, 1)

const PORTRAIT_STYLES: Dictionary = {
	"worker": {"color": Color(0.55, 0.35, 0.15, 1), "label": "W"},
	"swordsman": {"color": Color(0.35, 0.45, 0.75, 1), "label": "SW"},
	"archer": {"color": Color(0.15, 0.65, 0.25, 1), "label": "A"},
	"hero": {"color": Color(0.85, 0.65, 0.15, 1), "label": "H"},
	"enemy_dummy": {"color": Color(0.75, 0.2, 0.2, 1), "label": "E"},
	"town_center": {"color": Color(0.75, 0.4, 0.15, 1), "label": "TC"},
	"barracks": {"color": Color(0.5, 0.32, 0.22, 1), "label": "B"},
	"hero_altar": {"color": Color(0.55, 0.35, 0.75, 1), "label": "HA"},
	"farm": {"color": Color(0.45, 0.7, 0.25, 1), "label": "F"},
	"tower": {"color": Color(0.55, 0.58, 0.62, 1), "label": "T"},
	"tree": {"color": Color(0.18, 0.58, 0.24, 1), "label": "Tr"},
	"gold_mine": {"color": Color(0.92, 0.78, 0.14, 1), "label": "Gm"},
	"multiple": {"color": Color(0.42, 0.44, 0.48, 1), "label": "++"},
	"mixed": {"color": Color(0.48, 0.4, 0.35, 1), "label": "Mx"},
}


func _ready() -> void:
	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		return

	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.building_selection_changed.connect(_on_building_selection_changed)
	if selection_manager.has_signal("inspection_changed"):
		selection_manager.inspection_changed.connect(_on_inspection_changed)
	_refresh_panel()


func _on_inspection_changed(_unit: Unit, _building: Building) -> void:
	_refresh_panel()


func _on_selection_changed(_units: Array[Unit]) -> void:
	_refresh_panel()


func _on_building_selection_changed(_building: Building) -> void:
	_refresh_panel()


func _refresh_panel() -> void:
	_clear_health_tracking()
	_clear_mana_tracking()
	_hide_xp_display()
	_clear_production_tracking()

	var selection_manager: Node = get_node_or_null(selection_manager_path)
	if selection_manager == null:
		_hide_panel()
		return

	if selection_manager.inspected_building != null:
		_show_enemy_building_info(selection_manager.inspected_building)
		return

	if selection_manager.inspected_unit != null:
		_show_enemy_unit_info(selection_manager.inspected_unit)
		return

	if selection_manager.inspected_resource != null:
		_show_resource_info(selection_manager.inspected_resource)
		return

	var selected_building: Building = selection_manager.selected_building
	if selected_building != null:
		_show_building_info(selected_building)
		return

	var selected_units: Array[Unit] = selection_manager.selected_units
	if selected_units.is_empty():
		_hide_panel()
		return

	_is_enemy_inspect = false
	_apply_player_visual_style()

	var primary_hero: Hero = selection_manager.get_primary_ui_hero()
	if primary_hero != null and selected_units.size() > 1:
		_show_unit_info(primary_hero)
		return

	if selected_units.size() > 1:
		var multi_category: StringName = selection_manager.get_multi_unit_selection_category()
		_show_multiple_units(selected_units, multi_category)
		return

	_show_unit_info(selected_units[0])


func _show_multiple_units(units: Array[Unit], category: StringName) -> void:
	_is_enemy_inspect = false
	_apply_player_visual_style()
	visible = true
	_level_label.visible = false
	_type_label.visible = true
	_hp_bar.visible = false
	_mana_bar.visible = false
	_hide_xp_display()
	_health_label.visible = false
	_mana_label.visible = false
	_stats_row.visible = false
	_hide_production_display()

	match category:
		&"workers":
			_set_portrait("worker")
			_name_label.text = "Multiple Units"
			_type_label.text = "%d Workers selected" % units.size()
		&"combat":
			_set_portrait("multiple")
			_name_label.text = "Multiple Units"
			_type_label.text = "%d units selected" % units.size()
		&"mixed":
			_set_portrait("mixed")
			_name_label.text = "Multiple Units"
			_type_label.text = "%d units selected" % units.size()
		_:
			_set_portrait("multiple")
			_name_label.text = "Multiple Units"
			_type_label.text = "%d units selected" % units.size()


func _show_unit_info(unit: Unit) -> void:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion():
		_hide_panel()
		return

	_is_enemy_inspect = false
	_apply_player_visual_style()

	var info: Dictionary = _get_unit_info(unit)
	if info.is_empty():
		_hide_panel()
		return

	visible = true
	_set_portrait(info.portrait_key)
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_configure_level_display(unit)
	_configure_health_display(unit)
	_configure_mana_display(unit)
	if unit is Hero:
		_configure_xp_display(unit as Hero)
	else:
		_hide_xp_display()
	_configure_stats_display(unit)
	_hide_production_display()


func _show_building_info(building: Building) -> void:
	_is_enemy_inspect = false
	_apply_player_visual_style()

	var info: Dictionary = _get_building_info(building)
	if info.is_empty():
		_hide_panel()
		return

	if _is_passive_building(building):
		_show_passive_building_info(info)
		return

	visible = true
	_set_portrait(info.portrait_key)
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_level_label.visible = false
	_configure_health_display(building)
	_mana_bar.visible = false
	_mana_label.visible = false
	_hide_xp_display()
	_configure_stats_display(building)
	_configure_production_display(building)


func _show_enemy_unit_info(unit: Unit) -> void:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion():
		_hide_panel()
		return

	var info: Dictionary = _get_enemy_unit_info(unit)
	if info.is_empty():
		_hide_panel()
		return

	_is_enemy_inspect = true
	_apply_enemy_visual_style()
	visible = true
	_set_portrait(info.portrait_key)
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_hide_production_display()

	if unit is Hero:
		_configure_enemy_level_display(unit)
		_configure_health_display(unit, true)
		_configure_enemy_mana_display(unit as Hero)
		_configure_stats_display(unit)
		return

	_level_label.visible = false
	_configure_health_display(unit, true)
	_mana_bar.visible = false
	_mana_label.visible = false
	_hide_xp_display()
	_configure_stats_display(unit)


func _show_resource_info(resource: GatherableResource) -> void:
	if not is_instance_valid(resource) or resource.is_queued_for_deletion():
		_hide_panel()
		return

	_is_enemy_inspect = false
	_apply_player_visual_style()
	visible = true
	_level_label.visible = false
	_hp_bar.visible = false
	_mana_bar.visible = false
	_hide_xp_display()
	_health_label.visible = false
	_mana_label.visible = false
	_stats_row.visible = false
	_hide_production_display()

	if resource is WoodTree:
		_set_portrait("tree")
		_name_label.text = "Tree"
		_type_label.text = "Resource type: Wood"
		_type_label.visible = true
		_building_detail_label.text = "Remaining: %d" % (resource as WoodTree).wood_amount
		_building_detail_label.visible = true
		return

	if resource is GoldMine:
		_set_portrait("gold_mine")
		_name_label.text = "Gold Mine"
		_type_label.text = "Resource type: Gold"
		_type_label.visible = true
		if "gold_amount" in resource:
			_building_detail_label.text = "Remaining: %d" % int(resource.get("gold_amount"))
			_building_detail_label.visible = true
		else:
			_building_detail_label.visible = false
		return

	_hide_panel()


func _show_passive_building_info(info: Dictionary) -> void:
	visible = true
	_set_portrait(info.portrait_key)
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_level_label.visible = false
	_hp_bar.visible = false
	_mana_bar.visible = false
	_hide_xp_display()
	_health_label.visible = false
	_mana_label.visible = false
	_stats_row.visible = false
	_hide_production_display()


func _is_passive_building(building: Building) -> bool:
	return building is Farm or building is Tower


func _show_enemy_building_info(building: Building) -> void:
	if not is_instance_valid(building) or building.is_queued_for_deletion():
		_hide_panel()
		return

	var info: Dictionary = _get_enemy_building_info(building)
	if info.is_empty():
		_hide_panel()
		return

	_is_enemy_inspect = true
	_apply_enemy_visual_style()
	visible = true
	_set_portrait(info.portrait_key)
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_level_label.visible = false
	_configure_health_display(building, true)
	_mana_bar.visible = false
	_mana_label.visible = false
	_hide_xp_display()
	_stats_row.visible = false
	_hide_production_display()


func _apply_enemy_visual_style() -> void:
	_name_label.add_theme_color_override("font_color", ENEMY_NAME_COLOR)
	_level_label.add_theme_color_override("font_color", ENEMY_LEVEL_COLOR)
	_type_label.add_theme_color_override("font_color", ENEMY_LEVEL_COLOR)
	_health_label.add_theme_color_override("font_color", ENEMY_NAME_COLOR)
	_damage_label.add_theme_color_override("font_color", ENEMY_STAT_COLOR)
	_armor_label.add_theme_color_override("font_color", ENEMY_STAT_COLOR)
	_speed_label.add_theme_color_override("font_color", ENEMY_STAT_COLOR)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.04, 0.04, 0.9)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = ENEMY_ACCENT_COLOR
	panel_style.content_margin_left = 4.0
	panel_style.content_margin_top = 4.0
	panel_style.content_margin_right = 4.0
	panel_style.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", panel_style)


func _apply_player_visual_style() -> void:
	_name_label.remove_theme_color_override("font_color")
	_level_label.remove_theme_color_override("font_color")
	_type_label.remove_theme_color_override("font_color")
	_health_label.remove_theme_color_override("font_color")
	_damage_label.remove_theme_color_override("font_color")
	_armor_label.remove_theme_color_override("font_color")
	_speed_label.remove_theme_color_override("font_color")
	remove_theme_stylebox_override("panel")


func _configure_enemy_level_display(unit: Unit) -> void:
	if unit is Hero:
		var hero: Hero = unit as Hero
		_level_label.text = "Level %d" % hero.level
		_level_label.visible = true
		return

	_level_label.visible = false


func _configure_enemy_mana_display(hero: Hero) -> void:
	_clear_mana_tracking()

	if hero == null or not is_instance_valid(hero):
		_mana_bar.visible = false
		_mana_label.visible = false
		return

	_tracked_hero = hero
	if hero.has_signal("mana_changed"):
		hero.mana_changed.connect(_on_tracked_mana_changed)
	if hero.has_signal("level_changed"):
		hero.level_changed.connect(_on_tracked_enemy_hero_level_changed)
	_update_enemy_hero_mana_display(hero)
	_mana_bar.visible = true
	_mana_label.visible = true


func _update_enemy_hero_mana_display(hero: Hero) -> void:
	_level_label.text = "Level %d" % hero.level
	_level_label.visible = true
	_update_mana_display(hero.current_mana, hero.max_mana)
	_mana_label.text = "Mana: %d / %d" % [hero.current_mana, hero.max_mana]


func _on_tracked_enemy_hero_level_changed(_new_level: int = 0) -> void:
	if _tracked_hero != null and is_instance_valid(_tracked_hero) and _is_enemy_inspect:
		_update_enemy_hero_mana_display(_tracked_hero)


func _set_portrait(portrait_key: String) -> void:
	var style: Dictionary = PORTRAIT_STYLES.get(portrait_key, PORTRAIT_STYLES["multiple"])
	_portrait_color.color = style.color
	_portrait_label.text = style.label


func _configure_level_display(unit: Unit) -> void:
	if unit is Hero:
		var hero: Hero = unit as Hero
		_level_label.text = "Level %d" % hero.level
		_level_label.visible = true
		return

	_level_label.visible = false


func _configure_health_display(node: Node, show_numeric: bool = false) -> void:
	var health_component: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		_hp_bar.visible = false
		_health_label.visible = false
		return

	_tracked_health_component = health_component
	health_component.health_changed.connect(_on_tracked_health_changed)
	_update_health_display(health_component.current_health, health_component.max_health)
	_hp_bar.visible = true
	_health_label.visible = show_numeric


func _configure_xp_display(hero: Hero) -> void:
	if hero == null or not is_instance_valid(hero):
		_hide_xp_display()
		return

	if not hero.xp_changed.is_connected(_on_tracked_xp_changed):
		hero.xp_changed.connect(_on_tracked_xp_changed)
	if not hero.level_changed.is_connected(_on_tracked_xp_level_changed):
		hero.level_changed.connect(_on_tracked_xp_level_changed)
	_update_xp_display(hero)
	_xp_bar.visible = true
	_xp_label.visible = true


func _hide_xp_display() -> void:
	_xp_bar.visible = false
	_xp_label.visible = false


func _update_xp_display(hero: Hero) -> void:
	var xp_required: float = hero.get_xp_required_for_next_level()
	if xp_required <= 0.0 or hero.level >= Hero.MAX_LEVEL:
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_label.text = "XP: MAX"
		return

	var current_xp: float = hero.get_current_xp()
	_xp_bar.max_value = xp_required
	_xp_bar.value = current_xp
	_xp_label.text = "XP: %d / %d" % [int(current_xp), int(xp_required)]


func _on_tracked_xp_changed(_current_xp: float = 0.0, _xp_to_next_level: float = 0.0) -> void:
	if _tracked_hero != null and is_instance_valid(_tracked_hero) and not _is_enemy_inspect:
		_update_xp_display(_tracked_hero)


func _on_tracked_xp_level_changed(_new_level: int = 0) -> void:
	if _tracked_hero != null and is_instance_valid(_tracked_hero) and not _is_enemy_inspect:
		_update_xp_display(_tracked_hero)


func _configure_mana_display(unit: Unit) -> void:
	_clear_mana_tracking()

	if not unit is Hero:
		_mana_bar.visible = false
		_mana_label.visible = false
		return

	_tracked_hero = unit as Hero
	_tracked_hero.mana_changed.connect(_on_tracked_mana_changed)
	if not _tracked_hero.level_changed.is_connected(_on_tracked_hero_stats_changed):
		_tracked_hero.level_changed.connect(_on_tracked_hero_stats_changed)
	if not _tracked_hero.ability_points_changed.is_connected(_on_tracked_hero_stats_changed):
		_tracked_hero.ability_points_changed.connect(_on_tracked_hero_stats_changed)
	if not _tracked_hero.ability_progression_changed.is_connected(_on_tracked_hero_stats_changed):
		_tracked_hero.ability_progression_changed.connect(_on_tracked_hero_stats_changed)
	_update_hero_details(_tracked_hero)
	_mana_bar.visible = true
	_mana_label.visible = false


func _configure_stats_display(node: Node) -> void:
	var stats: Dictionary = _get_display_stats(node)
	_damage_label.text = "DMG: %s" % stats.damage
	_armor_label.text = "ARM: %s" % stats.armor
	_speed_label.text = "SPD: %s" % stats.speed
	_stats_row.visible = true


func _get_display_stats(node: Node) -> Dictionary:
	var damage: String = "—"
	var armor: String = "0"
	var speed: String = "—"

	if "attack_damage" in node:
		damage = str(node.get("attack_damage"))

	if node is Unit:
		var unit: Unit = node as Unit
		speed = str(snapped(unit.move_speed, 0.1))

	return {"damage": damage, "armor": armor, "speed": speed}


func _update_hero_details(hero: Hero) -> void:
	_level_label.text = "Level %d | AP: %d" % [hero.level, hero.ability_points]
	_level_label.visible = true
	_update_mana_display(hero.current_mana, hero.max_mana)


func _on_tracked_hero_stats_changed(_value: int = 0) -> void:
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		_update_hero_details(_tracked_hero)


func _update_mana_display(current_mana: int, max_mana: int) -> void:
	_mana_bar.max_value = max(max_mana, 1)
	_mana_bar.value = current_mana


func _on_tracked_mana_changed(current_mana: int, max_mana: int) -> void:
	_update_mana_display(current_mana, max_mana)
	if _is_enemy_inspect:
		_mana_label.text = "Mana: %d / %d" % [current_mana, max_mana]


func _clear_mana_tracking() -> void:
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		if _tracked_hero.mana_changed.is_connected(_on_tracked_mana_changed):
			_tracked_hero.mana_changed.disconnect(_on_tracked_mana_changed)
		if _tracked_hero.xp_changed.is_connected(_on_tracked_xp_changed):
			_tracked_hero.xp_changed.disconnect(_on_tracked_xp_changed)
		if _tracked_hero.level_changed.is_connected(_on_tracked_hero_stats_changed):
			_tracked_hero.level_changed.disconnect(_on_tracked_hero_stats_changed)
		if _tracked_hero.level_changed.is_connected(_on_tracked_xp_level_changed):
			_tracked_hero.level_changed.disconnect(_on_tracked_xp_level_changed)
		if _tracked_hero.ability_points_changed.is_connected(_on_tracked_hero_stats_changed):
			_tracked_hero.ability_points_changed.disconnect(_on_tracked_hero_stats_changed)
		if _tracked_hero.ability_progression_changed.is_connected(_on_tracked_hero_stats_changed):
			_tracked_hero.ability_progression_changed.disconnect(_on_tracked_hero_stats_changed)
		if _tracked_hero.level_changed.is_connected(_on_tracked_enemy_hero_level_changed):
			_tracked_hero.level_changed.disconnect(_on_tracked_enemy_hero_level_changed)
	_tracked_hero = null


func _update_health_display(current_health: int, max_health: int) -> void:
	_hp_bar.max_value = max(max_health, 1)
	_hp_bar.value = current_health
	_health_label.text = "Health: %d / %d" % [current_health, max_health]


func _on_tracked_health_changed(current_health: int, max_health: int) -> void:
	_update_health_display(current_health, max_health)
	if _health_label.visible:
		_health_label.text = "Health: %d / %d" % [current_health, max_health]


func _clear_health_tracking() -> void:
	if (
		_tracked_health_component != null
		and _tracked_health_component.health_changed.is_connected(_on_tracked_health_changed)
	):
		_tracked_health_component.health_changed.disconnect(_on_tracked_health_changed)
	_tracked_health_component = null


func _hide_panel() -> void:
	_is_enemy_inspect = false
	_apply_player_visual_style()
	visible = false
	_hide_production_display()


func _hide_production_display() -> void:
	_task_label.visible = false
	_building_detail_label.visible = false


func _configure_production_display(building: Building) -> void:
	if building is CommandCenter:
		_tracked_command_center = building as CommandCenter
		if _tracked_command_center.has_signal("worker_queue_changed"):
			_tracked_command_center.worker_queue_changed.connect(_on_production_changed)
		_update_command_center_production()
		return

	if building is Barracks:
		_tracked_barracks = building as Barracks
		if _tracked_barracks.has_signal("swordsman_queue_changed"):
			_tracked_barracks.swordsman_queue_changed.connect(_on_production_changed)
		if _tracked_barracks.has_signal("archer_queue_changed"):
			_tracked_barracks.archer_queue_changed.connect(_on_production_changed)
		_update_barracks_production()
		return

	if building is HeroAltar:
		_tracked_hero_altar = building as HeroAltar
		if _tracked_hero_altar.has_signal("hero_altar_state_changed"):
			_tracked_hero_altar.hero_altar_state_changed.connect(_on_production_changed)
		_update_hero_altar_production()
		return

	_hide_production_display()


func _on_production_changed(_value: int = 0) -> void:
	if _tracked_command_center != null and is_instance_valid(_tracked_command_center):
		_update_command_center_production()
		return

	if _tracked_barracks != null and is_instance_valid(_tracked_barracks):
		_update_barracks_production()
		return

	if _tracked_hero_altar != null and is_instance_valid(_tracked_hero_altar):
		_update_hero_altar_production()


func _update_command_center_production() -> void:
	if _tracked_command_center == null or not is_instance_valid(_tracked_command_center):
		_hide_production_display()
		return

	var queue_count: int = -1
	if _tracked_command_center.has_method("get_worker_queue_count"):
		queue_count = _tracked_command_center.get_worker_queue_count()

	if queue_count > 0:
		_task_label.text = "Training: Worker"
		_task_label.visible = true
		_building_detail_label.text = "Queue: %d" % queue_count
		_building_detail_label.visible = true
	elif queue_count == 0:
		_task_label.text = "Production: Idle"
		_task_label.visible = true
		_building_detail_label.visible = false
	else:
		_hide_production_display()


func _update_barracks_production() -> void:
	if _tracked_barracks == null or not is_instance_valid(_tracked_barracks):
		_hide_production_display()
		return

	var swordsman_count: int = -1
	var archer_count: int = -1
	if _tracked_barracks.has_method("get_swordsman_queue_count"):
		swordsman_count = _tracked_barracks.get_swordsman_queue_count()
	if _tracked_barracks.has_method("get_archer_queue_count"):
		archer_count = _tracked_barracks.get_archer_queue_count()

	var training_parts: PackedStringArray = []
	if swordsman_count > 0:
		training_parts.append("Swordsman")
	if archer_count > 0:
		training_parts.append("Archer")

	if training_parts.is_empty():
		if swordsman_count == 0 and archer_count == 0:
			_task_label.text = "Production: Idle"
			_task_label.visible = true
			_building_detail_label.visible = false
		else:
			_hide_production_display()
		return

	_task_label.text = "Training: %s" % ", ".join(training_parts)
	_task_label.visible = true

	var queue_parts: PackedStringArray = []
	if swordsman_count >= 0:
		queue_parts.append("SW %d" % swordsman_count)
	if archer_count >= 0:
		queue_parts.append("AR %d" % archer_count)

	if queue_parts.is_empty():
		_building_detail_label.visible = false
	else:
		_building_detail_label.text = "Queue: %s" % " | ".join(queue_parts)
		_building_detail_label.visible = true


func _update_hero_altar_production() -> void:
	if _tracked_hero_altar == null or not is_instance_valid(_tracked_hero_altar):
		_hide_production_display()
		return

	var is_training: bool = false
	if _tracked_hero_altar.has_method("is_training_hero"):
		is_training = _tracked_hero_altar.is_training_hero()

	if is_training:
		_task_label.text = "Training: Hero"
	else:
		_task_label.text = "Production: Idle"
	_task_label.visible = true
	_building_detail_label.visible = false


func _clear_production_tracking() -> void:
	if _tracked_command_center != null and is_instance_valid(_tracked_command_center):
		if (
			_tracked_command_center.has_signal("worker_queue_changed")
			and _tracked_command_center.worker_queue_changed.is_connected(_on_production_changed)
		):
			_tracked_command_center.worker_queue_changed.disconnect(_on_production_changed)

	if _tracked_barracks != null and is_instance_valid(_tracked_barracks):
		if (
			_tracked_barracks.has_signal("swordsman_queue_changed")
			and _tracked_barracks.swordsman_queue_changed.is_connected(_on_production_changed)
		):
			_tracked_barracks.swordsman_queue_changed.disconnect(_on_production_changed)
		if (
			_tracked_barracks.has_signal("archer_queue_changed")
			and _tracked_barracks.archer_queue_changed.is_connected(_on_production_changed)
		):
			_tracked_barracks.archer_queue_changed.disconnect(_on_production_changed)

	if _tracked_hero_altar != null and is_instance_valid(_tracked_hero_altar):
		if (
			_tracked_hero_altar.has_signal("hero_altar_state_changed")
			and _tracked_hero_altar.hero_altar_state_changed.is_connected(_on_production_changed)
		):
			_tracked_hero_altar.hero_altar_state_changed.disconnect(_on_production_changed)

	_tracked_command_center = null
	_tracked_barracks = null
	_tracked_hero_altar = null


func _get_unit_info(unit: Unit) -> Dictionary:
	if unit is Swordsman:
		return {"name": "Swordsman", "type": "Unit", "portrait_key": "swordsman"}
	if unit is Archer:
		return {"name": "Archer", "type": "Unit", "portrait_key": "archer"}
	if unit is Hero:
		return {"name": "Hero", "type": "Unit", "portrait_key": "hero"}
	if unit is Worker:
		return {"name": "Worker", "type": "Unit", "portrait_key": "worker"}
	if unit is EnemyDummy:
		return {"name": "Enemy Dummy", "type": "Unit", "portrait_key": "enemy_dummy"}
	return {}


func _get_enemy_unit_info(unit: Unit) -> Dictionary:
	if unit is Hero:
		return {"name": "Enemy Hero", "type": "Unit", "portrait_key": "hero"}
	if unit is Worker:
		return {"name": "Enemy Worker", "type": "Unit", "portrait_key": "worker"}
	if unit is Swordsman:
		return {"name": "Enemy Soldier", "type": "Unit", "portrait_key": "swordsman"}
	if unit is Archer:
		return {"name": "Enemy Archer", "type": "Unit", "portrait_key": "archer"}
	if unit is EnemyDummy:
		return {"name": "Enemy Dummy", "type": "Unit", "portrait_key": "enemy_dummy"}
	return {"name": "Enemy Unit", "type": "Unit", "portrait_key": "enemy_dummy"}


func _get_enemy_building_info(building: Building) -> Dictionary:
	var info: Dictionary = _get_building_info(building)
	if info.is_empty():
		return {}
	info.name = "Enemy %s" % info.name
	return info


func _get_building_info(building: Building) -> Dictionary:
	if building is CommandCenter:
		return {"name": "Town Center", "type": "Building", "portrait_key": "town_center"}
	if building is Barracks:
		return {"name": "Barracks", "type": "Building", "portrait_key": "barracks"}
	if building is HeroAltar:
		return {"name": "Hero Altar", "type": "Building", "portrait_key": "hero_altar"}
	if building is Farm:
		return {"name": "Farm", "type": "Building", "portrait_key": "farm"}
	if building is Tower:
		return {"name": "Tower", "type": "Building", "portrait_key": "tower"}
	return {}
