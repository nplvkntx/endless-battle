extends PanelContainer

## Top HUD bar showing current player resources from ResourceManager.

@onready var _resource_label: Label = $MarginContainer/ResourceLabel


func _ready() -> void:
	ResourceManager.resources_changed.connect(_refresh_display)
	ResourceManager.food_changed.connect(_on_food_changed)
	_refresh_display()


func _on_food_changed(_current: int, _maximum: int) -> void:
	_refresh_display()


func _refresh_display() -> void:
	_resource_label.text = "Gold: %d | Wood: %d | Food: %d/%d" % [
		ResourceManager.gold,
		ResourceManager.wood,
		ResourceManager.food_current,
		ResourceManager.food_max,
	]
