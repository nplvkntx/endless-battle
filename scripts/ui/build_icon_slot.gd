class_name BuildIconSlot
extends PanelContainer

## Square RTS build command button with model thumbnail and hotkey label.

signal build_slot_clicked(placement_id: StringName)

const SLOT_SIZE := Vector2(48, 48)
const DISABLED_MODULATE := Color(0.42, 0.42, 0.46, 1)

@onready var _icon_rect: TextureRect = $IconLayer/IconRect
@onready var _initials_label: Label = $IconLayer/InitialsLabel
@onready var _hotkey_label: Label = $IconLayer/HotkeyLabel
@onready var _icon_layer: Control = $IconLayer

var placement_id: StringName = &""
var _pending_icon_texture: Texture2D = null
var _pending_hotkey: String = ""
var _affordable: bool = true


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_child_refs()

	if not _pending_hotkey.is_empty():
		_apply_hotkey(_pending_hotkey)
	if _pending_icon_texture != null:
		_apply_icon_texture(_pending_icon_texture)
		_pending_icon_texture = null

	gui_input.connect(_on_gui_input)
	_refresh_modulate()


func configure(
	p_placement_id: StringName,
	icon_texture: Texture2D,
	hotkey: String = ""
) -> void:
	placement_id = p_placement_id
	_pending_hotkey = hotkey

	if is_node_ready():
		_apply_hotkey(hotkey)
		_apply_icon_texture(icon_texture)
	else:
		_pending_icon_texture = icon_texture


func set_affordable(affordable: bool) -> void:
	_affordable = affordable
	_refresh_modulate()


func _ensure_child_refs() -> void:
	if _icon_rect == null:
		_icon_rect = get_node_or_null("IconLayer/IconRect") as TextureRect
	if _initials_label == null:
		_initials_label = get_node_or_null("IconLayer/InitialsLabel") as Label
	if _hotkey_label == null:
		_hotkey_label = get_node_or_null("IconLayer/HotkeyLabel") as Label
	if _icon_layer == null:
		_icon_layer = get_node_or_null("IconLayer") as Control


func _apply_icon_texture(icon_texture: Texture2D) -> void:
	_ensure_child_refs()
	if _icon_rect == null:
		return

	var resolved_texture: Texture2D = icon_texture
	if resolved_texture == null and not placement_id.is_empty():
		resolved_texture = BuildingCommandIcons.get_icon_texture(placement_id)

	_icon_rect.texture = resolved_texture

	if _initials_label != null:
		_initials_label.visible = resolved_texture == null
		if resolved_texture == null:
			_initials_label.text = BuildingCommandIcons.get_initials(placement_id)


func _apply_hotkey(hotkey: String) -> void:
	_ensure_child_refs()
	if _hotkey_label == null:
		return

	_hotkey_label.visible = not hotkey.is_empty()
	_hotkey_label.text = hotkey


func _refresh_modulate() -> void:
	_ensure_child_refs()
	if _icon_layer == null:
		return

	_icon_layer.modulate = Color.WHITE if _affordable else DISABLED_MODULATE


func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	accept_event()
	build_slot_clicked.emit(placement_id)
