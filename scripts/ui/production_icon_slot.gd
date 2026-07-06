class_name ProductionIconSlot
extends PanelContainer

## Cossacks-style production square: unit icon, queue count, infinite marker, training progress.

signal production_slot_clicked(train_id: StringName, event: InputEventMouseButton)

const SLOT_SIZE := Vector2(48, 48)

const DISABLED_MODULATE := Color(0.42, 0.42, 0.46, 1)

@onready var _icon_rect: TextureRect = $IconLayer/IconRect
@onready var _progress_fill: ColorRect = $IconLayer/ProgressFill
@onready var _queue_label: Label = $IconLayer/QueueLabel
@onready var _infinite_label: Label = $IconLayer/InfiniteLabel
@onready var _icon_layer: Control = $IconLayer

var train_id: StringName = &""
var _pending_icon_texture: Texture2D = null
var _affordable: bool = true


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_child_refs()
	if _progress_fill != null:
		_progress_fill.visible = false
	if _queue_label != null:
		_queue_label.visible = false
	if _infinite_label != null:
		_infinite_label.visible = false
	gui_input.connect(_on_gui_input)

	if _pending_icon_texture != null:
		_apply_icon_texture(_pending_icon_texture)
		_pending_icon_texture = null

	_refresh_modulate()


func set_affordable(affordable: bool) -> void:
	_affordable = affordable
	_refresh_modulate()


func _refresh_modulate() -> void:
	_ensure_child_refs()
	if _icon_layer == null:
		return

	_icon_layer.modulate = Color.WHITE if _affordable else DISABLED_MODULATE


func configure(p_train_id: StringName, icon_texture: Texture2D) -> void:
	train_id = p_train_id
	if is_node_ready():
		_apply_icon_texture(icon_texture)
	else:
		_pending_icon_texture = icon_texture


func _ensure_child_refs() -> void:
	if _icon_rect == null:
		_icon_rect = get_node_or_null("IconLayer/IconRect") as TextureRect
	if _progress_fill == null:
		_progress_fill = get_node_or_null("IconLayer/ProgressFill") as ColorRect
	if _queue_label == null:
		_queue_label = get_node_or_null("IconLayer/QueueLabel") as Label
	if _infinite_label == null:
		_infinite_label = get_node_or_null("IconLayer/InfiniteLabel") as Label
	if _icon_layer == null:
		_icon_layer = get_node_or_null("IconLayer") as Control


func _apply_icon_texture(icon_texture: Texture2D) -> void:
	_ensure_child_refs()
	if _icon_rect == null:
		return

	var resolved_texture: Texture2D = icon_texture
	if resolved_texture == null and not train_id.is_empty():
		resolved_texture = UnitProductionIcons.get_icon_texture(train_id)
	_icon_rect.texture = resolved_texture


func set_queue_count(count: int) -> void:
	_ensure_child_refs()
	if _queue_label == null:
		return
	_queue_label.visible = count > 0
	_queue_label.text = str(count)


func set_infinite_enabled(enabled: bool) -> void:
	_ensure_child_refs()
	if _infinite_label == null:
		return
	_infinite_label.visible = enabled


func set_training_progress(ratio: float, is_training: bool) -> void:
	_ensure_child_refs()
	if _progress_fill == null:
		return
	_progress_fill.visible = is_training
	if not is_training:
		return

	var clamped: float = clampf(ratio, 0.0, 1.0)
	_progress_fill.anchor_top = 1.0 - clamped
	_progress_fill.offset_top = 0.0
	_progress_fill.offset_bottom = 0.0


func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if (
		mouse_event.button_index != MOUSE_BUTTON_LEFT
		and mouse_event.button_index != MOUSE_BUTTON_RIGHT
	):
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT and not _affordable:
		return

	accept_event()
	production_slot_clicked.emit(train_id, mouse_event)
