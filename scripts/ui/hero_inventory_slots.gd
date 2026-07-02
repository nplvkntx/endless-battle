extends HBoxContainer
class_name HeroInventorySlots

## Reusable HUD row of hero inventory slots with icons, drag reorder, and sell.

const SLOT_SIZE := Vector2(24, 24)
const EMPTY_SLOT_COLOR := Color(0.1, 0.11, 0.13, 1)
const EMPTY_SLOT_BORDER_COLOR := Color(0.28, 0.3, 0.34, 1)
const FILLED_SLOT_BORDER_COLOR := Color(0.62, 0.66, 0.72, 1)
const DRAG_DATA_TYPE := "hero_inventory_slot"

var _slot_panels: Array[PanelContainer] = []
var _tracked_hero: Hero = null


func _ready() -> void:
	if _slot_panels.is_empty():
		_build_slots()


func bind_hero(hero: Hero) -> void:
	_disconnect_tracked_hero()
	_tracked_hero = hero

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_refresh_slots()
		return

	if not _tracked_hero.inventory_changed.is_connected(_on_inventory_changed):
		_tracked_hero.inventory_changed.connect(_on_inventory_changed)
	_refresh_slots()


func unbind() -> void:
	_disconnect_tracked_hero()
	_tracked_hero = null
	_refresh_slots()


func _build_slots() -> void:
	for child: Node in get_children():
		child.queue_free()
	_slot_panels.clear()

	var slot_count: int = Hero.INVENTORY_SLOT_COUNT
	for slot_index: int in slot_count:
		var slot: PanelContainer = _create_slot_panel(slot_index)
		add_child(slot)
		_slot_panels.append(slot)


func _create_slot_panel(slot_index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.tooltip_text = ""
	TooltipManager.bind_control(slot, func() -> String: return _get_slot_tooltip(slot_index))

	var style := StyleBoxFlat.new()
	style.bg_color = EMPTY_SLOT_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = EMPTY_SLOT_BORDER_COLOR
	style.set_corner_radius_all(2)
	slot.add_theme_stylebox_override("panel", style)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	slot.add_child(icon)

	slot.set_drag_forwarding(
		func(at_position: Vector2): return _slot_get_drag_data(at_position, slot_index),
		func(at_position: Vector2, data: Variant): return _slot_can_drop_data(
			at_position, data, slot_index
		),
		func(at_position: Vector2, data: Variant): _slot_drop_data(
			at_position, data, slot_index
		)
	)
	slot.gui_input.connect(func(event: InputEvent): _on_slot_gui_input(event, slot_index))

	return slot


func _refresh_slots() -> void:
	if _slot_panels.is_empty():
		_build_slots()

	_update_slot_interactivity()

	for slot_index: int in _slot_panels.size():
		_update_slot_display(slot_index)


func _update_slot_interactivity() -> void:
	var can_modify: bool = _can_modify_inventory()
	for slot: PanelContainer in _slot_panels:
		slot.mouse_filter = (
			Control.MOUSE_FILTER_STOP if can_modify else Control.MOUSE_FILTER_IGNORE
		)


func _update_slot_display(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_panels.size():
		return

	var item = null
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		item = _tracked_hero.get_item_at_slot(slot_index)

	if item is HeroItemDefinition:
		_set_slot_item(_slot_panels[slot_index], item as HeroItemDefinition)
	else:
		_set_slot_empty(_slot_panels[slot_index])


func _set_slot_item(slot: PanelContainer, item: HeroItemDefinition) -> void:
	var style := slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return

	style.bg_color = EMPTY_SLOT_COLOR
	style.border_color = FILLED_SLOT_BORDER_COLOR

	var icon: TextureRect = slot.get_node_or_null("Icon") as TextureRect
	if icon != null:
		icon.texture = HeroItemIcons.get_icon_texture(item.item_id)
		icon.visible = true


func _set_slot_empty(slot: PanelContainer) -> void:
	var style := slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return

	style.bg_color = EMPTY_SLOT_COLOR
	style.border_color = EMPTY_SLOT_BORDER_COLOR

	var icon: TextureRect = slot.get_node_or_null("Icon") as TextureRect
	if icon != null:
		icon.texture = null
		icon.visible = false


func _can_modify_inventory() -> bool:
	return HeroItemService.can_modify_player_inventory(_tracked_hero)


func _get_slot_tooltip(slot_index: int) -> String:
	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		return "Empty inventory slot"

	var item = _tracked_hero.get_item_at_slot(slot_index)
	if item is HeroItemDefinition:
		return TooltipFormatter.format_inventory_item(item as HeroItemDefinition)

	return "Empty inventory slot"


func _slot_get_drag_data(_at_position: Vector2, slot_index: int) -> Variant:
	if not _can_modify_inventory():
		return null

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		return null

	var item = _tracked_hero.get_item_at_slot(slot_index)
	if not item is HeroItemDefinition:
		return null

	var definition: HeroItemDefinition = item as HeroItemDefinition
	var preview := TextureRect.new()
	preview.custom_minimum_size = SLOT_SIZE
	preview.texture = HeroItemIcons.get_icon_texture(definition.item_id)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_slot_panels[slot_index].set_drag_preview(preview)

	return {
		"type": DRAG_DATA_TYPE,
		"hero_id": _tracked_hero.get_instance_id(),
		"source_slot": slot_index,
	}


func _slot_can_drop_data(_at_position: Vector2, data: Variant, slot_index: int) -> bool:
	if not _is_valid_drag_data(data):
		return false

	if not _can_modify_inventory():
		return false

	var source_slot: int = int(data["source_slot"])
	return source_slot != slot_index


func _slot_drop_data(_at_position: Vector2, data: Variant, slot_index: int) -> void:
	if not _is_valid_drag_data(data):
		return

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		return

	if int(data["hero_id"]) != _tracked_hero.get_instance_id():
		return

	var source_slot: int = int(data["source_slot"])
	if source_slot == slot_index:
		return

	HeroItemService.try_reorder_inventory_slot(_tracked_hero, source_slot, slot_index)


func _is_valid_drag_data(data: Variant) -> bool:
	if data == null or not data is Dictionary:
		return false

	var drag_data: Dictionary = data
	return drag_data.get("type", "") == DRAG_DATA_TYPE and drag_data.has("source_slot")


func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not _can_modify_inventory():
		return

	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return

	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		return

	if _tracked_hero.get_item_at_slot(slot_index) == null:
		return

	if HeroItemService.try_sell_inventory_item(_tracked_hero, slot_index):
		_slot_panels[slot_index].accept_event()


func _on_inventory_changed() -> void:
	_refresh_slots()


func _disconnect_tracked_hero() -> void:
	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_tracked_hero = null
		return

	if _tracked_hero.inventory_changed.is_connected(_on_inventory_changed):
		_tracked_hero.inventory_changed.disconnect(_on_inventory_changed)
