extends HBoxContainer
class_name HeroInventorySlots

## Reusable HUD row of hero inventory slots. Empty placeholders until Shop items are added.

const SLOT_SIZE := Vector2(24, 24)
const EMPTY_SLOT_COLOR := Color(0.1, 0.11, 0.13, 1)
const EMPTY_SLOT_BORDER_COLOR := Color(0.28, 0.3, 0.34, 1)

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
		var slot: PanelContainer = _create_empty_slot_panel(slot_index)
		add_child(slot)
		_slot_panels.append(slot)


func _create_empty_slot_panel(slot_index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.tooltip_text = "Inventory slot %d" % (slot_index + 1)

	var style := StyleBoxFlat.new()
	style.bg_color = EMPTY_SLOT_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = EMPTY_SLOT_BORDER_COLOR
	style.set_corner_radius_all(2)
	slot.add_theme_stylebox_override("panel", style)

	return slot


func _refresh_slots() -> void:
	if _slot_panels.is_empty():
		_build_slots()

	for slot_index: int in _slot_panels.size():
		_update_slot_display(slot_index)


func _update_slot_display(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_panels.size():
		return

	var item = null
	if _tracked_hero != null and is_instance_valid(_tracked_hero):
		item = _tracked_hero.get_item_at_slot(slot_index)

	# Items are not implemented yet; keep empty placeholders until Shop fills slots.
	_set_slot_empty(_slot_panels[slot_index], item == null)


func _set_slot_empty(slot: PanelContainer, _is_empty: bool) -> void:
	var style := slot.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return

	style.bg_color = EMPTY_SLOT_COLOR
	style.border_color = EMPTY_SLOT_BORDER_COLOR


func _on_inventory_changed() -> void:
	_refresh_slots()


func _disconnect_tracked_hero() -> void:
	if _tracked_hero == null or not is_instance_valid(_tracked_hero):
		_tracked_hero = null
		return

	if _tracked_hero.inventory_changed.is_connected(_on_inventory_changed):
		_tracked_hero.inventory_changed.disconnect(_on_inventory_changed)
