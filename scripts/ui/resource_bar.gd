extends PanelContainer

## Top HUD bar showing current player resources from ResourceManager.

@onready var _gold_label: Label = $MarginContainer/HBoxContainer/GoldLabel
@onready var _wood_label: Label = $MarginContainer/HBoxContainer/WoodLabel
@onready var _food_label: Label = $MarginContainer/HBoxContainer/FoodLabel


func _ready() -> void:
	ResourceManager.resources_changed.connect(_refresh_display)
	ResourceManager.food_changed.connect(_on_food_changed)
	_refresh_display()


func _on_food_changed(_current: int, _maximum: int) -> void:
	_refresh_display()


func _refresh_display() -> void:
	_gold_label.text = "Gold: %d" % ResourceManager.gold
	_wood_label.text = "Wood: %d" % ResourceManager.wood
	_food_label.text = "Food: %d/%d" % [ResourceManager.food_current, ResourceManager.food_max]
