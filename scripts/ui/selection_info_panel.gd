extends PanelContainer

## Shows basic name, type, health, and portrait placeholder for the current selection.

@export var selection_manager_path: NodePath = "../../../../SelectionManager"

@onready var _portrait_color: ColorRect = $MarginContainer/HBoxContainer/PortraitFrame/PortraitColor
@onready var _portrait_label: Label = $MarginContainer/HBoxContainer/PortraitFrame/PortraitLabel
@onready var _name_label: Label = $MarginContainer/HBoxContainer/InfoVBox/NameLabel
@onready var _type_label: Label = $MarginContainer/HBoxContainer/InfoVBox/TypeLabel
@onready var _health_label: Label = $MarginContainer/HBoxContainer/InfoVBox/HealthLabel
@onready var _mana_label: Label = $MarginContainer/HBoxContainer/InfoVBox/ManaLabel

var _tracked_health_component: HealthComponent = null
var _tracked_hero: Hero = null

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
	"multiple": {"color": Color(0.42, 0.44, 0.48, 1), "label": "++"},
	"mixed": {"color": Color(0.48, 0.4, 0.35, 1), "label": "Mx"},
}


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
	_clear_mana_tracking()

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
	visible = true
	_type_label.visible = false
	_health_label.visible = false
	_mana_label.visible = false

	match category:
		&"workers":
			_set_portrait("worker")
			_name_label.text = "%d Workers selected" % units.size()
		&"combat":
			_set_portrait("multiple")
			_name_label.text = "%d combat units selected" % units.size()
		&"mixed":
			_set_portrait("mixed")
			_name_label.text = "Mixed Selection"
		_:
			_set_portrait("multiple")
			_name_label.text = "Multiple units selected"


func _show_unit_info(unit: Unit) -> void:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion():
		_hide_panel()
		return

	if unit.is_in_group(&"enemies"):
		_hide_panel()
		return

	var info: Dictionary = _get_unit_info(unit)
	if info.is_empty():
		_hide_panel()
		return

	visible = true
	_set_portrait(info.portrait_key)
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_configure_health_display(unit)
	_configure_mana_display(unit)


func _show_building_info(building: Building) -> void:
	var info: Dictionary = _get_building_info(building)
	if info.is_empty():
		_hide_panel()
		return

	visible = true
	_set_portrait(info.portrait_key)
	_name_label.text = info.name
	_type_label.text = "Type: %s" % info.type
	_type_label.visible = true
	_configure_health_display(building)
	_mana_label.visible = false


func _set_portrait(portrait_key: String) -> void:
	var style: Dictionary = PORTRAIT_STYLES.get(portrait_key, PORTRAIT_STYLES["multiple"])
	_portrait_color.color = style.color
	_portrait_label.text = style.label


func _configure_health_display(node: Node) -> void:
	var health_component: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		_health_label.visible = false
		return

	_tracked_health_component = health_component
	health_component.health_changed.connect(_on_tracked_health_changed)
	_update_health_label(health_component.current_health, health_component.max_health)


func _configure_mana_display(unit: Unit) -> void:
	_clear_mana_tracking()

	if not unit is Hero:
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
	_mana_label.visible = true


func _update_hero_details(hero: Hero) -> void:
	_type_label.text = "Type: Hero | Level %d | AP: %d" % [hero.level, hero.ability_points]
	_update_mana_label(hero.current_mana, hero.max_mana)


func _on_tracked_hero_stats_changed(_value: int = 0) -> void:
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		_update_hero_details(_tracked_hero)


func _update_mana_label(current_mana: int, max_mana: int) -> void:
	_mana_label.text = "Mana: %d / %d" % [current_mana, max_mana]


func _on_tracked_mana_changed(current_mana: int, max_mana: int) -> void:
	_update_mana_label(current_mana, max_mana)


func _clear_mana_tracking() -> void:
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		if _tracked_hero.mana_changed.is_connected(_on_tracked_mana_changed):
			_tracked_hero.mana_changed.disconnect(_on_tracked_mana_changed)
		if _tracked_hero.level_changed.is_connected(_on_tracked_hero_stats_changed):
			_tracked_hero.level_changed.disconnect(_on_tracked_hero_stats_changed)
		if _tracked_hero.ability_points_changed.is_connected(_on_tracked_hero_stats_changed):
			_tracked_hero.ability_points_changed.disconnect(_on_tracked_hero_stats_changed)
		if _tracked_hero.ability_progression_changed.is_connected(_on_tracked_hero_stats_changed):
			_tracked_hero.ability_progression_changed.disconnect(_on_tracked_hero_stats_changed)
	_tracked_hero = null


func _update_health_label(current_health: int, max_health: int) -> void:
	if HealthBarDisplay.should_show(current_health, max_health):
		_health_label.text = "Health: %d / %d" % [current_health, max_health]
		_health_label.visible = true
	else:
		_health_label.visible = false


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
