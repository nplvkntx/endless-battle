class_name SelectionBox
extends Control

## Draws the RTS drag-selection rectangle on screen.

@export var border_color: Color = Color(0.2, 0.9, 0.25, 1.0)
@export var fill_color: Color = Color(0.2, 0.9, 0.25, 0.15)
@export var border_width: float = 1.0

var _active: bool = false
var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2.ZERO


func begin_drag(start: Vector2) -> void:
	_active = true
	_start = start
	_end = start
	visible = true
	queue_redraw()


func update_drag(end: Vector2) -> void:
	if not _active:
		return

	_end = end
	queue_redraw()


func end_drag() -> void:
	_active = false
	visible = false
	queue_redraw()


func _draw() -> void:
	if not _active:
		return

	var rect := _get_rect()
	draw_rect(rect, fill_color, true)
	draw_rect(rect, border_color, false, border_width)


func _get_rect() -> Rect2:
	return Rect2(
		Vector2(minf(_start.x, _end.x), minf(_start.y, _end.y)),
		Vector2(absf(_start.x - _end.x), absf(_start.y - _end.y))
	)
