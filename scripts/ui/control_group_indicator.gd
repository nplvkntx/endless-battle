extends HBoxContainer

## Subtle 1–9 indicators for assigned control groups; highlights the active group.

const SLOT_COUNT: int = 9

var _slots: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_build_slots()
	ControlGroupManager.groups_changed.connect(_refresh)
	ControlGroupManager.active_group_changed.connect(_on_active_group_changed)
	_refresh()


func _exit_tree() -> void:
	if ControlGroupManager.groups_changed.is_connected(_refresh):
		ControlGroupManager.groups_changed.disconnect(_refresh)
	if ControlGroupManager.active_group_changed.is_connected(_on_active_group_changed):
		ControlGroupManager.active_group_changed.disconnect(_on_active_group_changed)


func _on_active_group_changed(_group_index: int) -> void:
	_refresh()


func _build_slots() -> void:
	for child: Node in get_children():
		child.queue_free()
	_slots.clear()

	for index: int in SLOT_COUNT:
		var slot := Label.new()
		slot.text = str(index + 1)
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.custom_minimum_size = Vector2(18, 18)
		slot.add_theme_font_size_override("font_size", 11)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		_slots.append(slot)


func _refresh() -> void:
	var active: int = ControlGroupManager.get_active_group_index()
	for index: int in SLOT_COUNT:
		var slot: Label = _slots[index]
		var size: int = ControlGroupManager.get_group_size(index)
		var has_members: bool = size > 0
		slot.visible = has_members or index == active
		if not slot.visible:
			continue

		if index == active and has_members:
			slot.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35, 1.0))
			slot.modulate = Color(1, 1, 1, 1)
		elif has_members:
			slot.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82, 0.85))
			slot.modulate = Color(1, 1, 1, 0.9)
		else:
			slot.add_theme_color_override("font_color", Color(0.45, 0.48, 0.52, 0.5))
			slot.modulate = Color(1, 1, 1, 0.5)
