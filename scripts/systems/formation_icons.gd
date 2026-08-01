class_name FormationIcons
extends RefCounted

## Procedural Cossacks-style formation shape icons for the command panel.

const ICON_SIZE := 32

static var _textures: Dictionary = {}


static func get_shape_icon(shape: FormationLayout.Shape) -> Texture2D:
	var key: StringName = StringName("shape_%d" % int(shape))
	if _textures.has(key):
		return _textures[key] as Texture2D

	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.14, 0.16, 0.92))
	var ink := Color(0.92, 0.88, 0.72, 1)
	var accent := Color(0.75, 0.55, 0.28, 1)

	match shape:
		FormationLayout.Shape.SQUARE:
			_draw_square_block(image, ink)
		FormationLayout.Shape.LINE:
			_draw_line(image, ink, accent)
		FormationLayout.Shape.ARROW:
			_draw_arrow(image, ink, accent)
		FormationLayout.Shape.HOLLOW_SQUARE:
			_draw_hollow_square(image, ink)
		_:
			_draw_square_block(image, ink)

	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func get_size_icon(size_preset: int) -> Texture2D:
	var key: StringName = StringName("size_%d" % size_preset)
	if _textures.has(key):
		return _textures[key] as Texture2D

	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.14, 0.16, 0.92))
	_draw_size_dots(image, size_preset, Color(0.9, 0.86, 0.7, 1))
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func get_dissolve_icon() -> Texture2D:
	var key: StringName = &"dissolve"
	if _textures.has(key):
		return _textures[key] as Texture2D

	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.18, 0.1, 0.1, 0.92))
	var red := Color(0.9, 0.35, 0.28, 1)
	_fill_rect(image, Rect2i(6, 14, 20, 4), red)
	_fill_rect(image, Rect2i(14, 6, 4, 20), red)
	# Rotate feel via corners
	_fill_rect(image, Rect2i(8, 8, 3, 3), red)
	_fill_rect(image, Rect2i(21, 21, 3, 3), red)
	_fill_rect(image, Rect2i(21, 8, 3, 3), red)
	_fill_rect(image, Rect2i(8, 21, 3, 3), red)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= ICON_SIZE or y >= ICON_SIZE:
				continue
			image.set_pixel(x, y, color)


static func _set_dot(image: Image, x: int, y: int, color: Color) -> void:
	_fill_rect(image, Rect2i(x, y, 2, 2), color)


static func _draw_square_block(image: Image, ink: Color) -> void:
	for row: int in range(4):
		for col: int in range(4):
			_set_dot(image, 8 + col * 4, 8 + row * 4, ink)


static func _draw_line(image: Image, ink: Color, accent: Color) -> void:
	for col: int in range(7):
		_set_dot(image, 4 + col * 3, 10, accent)
	for col: int in range(7):
		_set_dot(image, 4 + col * 3, 18, ink)


static func _draw_arrow(image: Image, ink: Color, accent: Color) -> void:
	# Tip
	_set_dot(image, 15, 4, accent)
	# Widening rows
	_set_dot(image, 13, 9, ink)
	_set_dot(image, 17, 9, ink)
	_set_dot(image, 11, 14, ink)
	_set_dot(image, 15, 14, ink)
	_set_dot(image, 19, 14, ink)
	_set_dot(image, 9, 19, ink)
	_set_dot(image, 13, 19, ink)
	_set_dot(image, 17, 19, ink)
	_set_dot(image, 21, 19, ink)
	_set_dot(image, 11, 24, ink)
	_set_dot(image, 15, 24, ink)
	_set_dot(image, 19, 24, ink)


static func _draw_hollow_square(image: Image, ink: Color) -> void:
	for i: int in range(5):
		_set_dot(image, 6 + i * 4, 6, ink)
		_set_dot(image, 6 + i * 4, 22, ink)
		_set_dot(image, 6, 6 + i * 4, ink)
		_set_dot(image, 22, 6 + i * 4, ink)


static func _draw_size_dots(image: Image, size_preset: int, ink: Color) -> void:
	var dots: int = 1
	match size_preset:
		5:
			dots = 1
		15:
			dots = 2
		30:
			dots = 3
		50:
			dots = 4
		_:
			dots = 1
	var start_x: int = 16 - dots * 3
	for i: int in range(dots):
		_fill_rect(image, Rect2i(start_x + i * 7, 12, 5, 5), ink)
	# Tiny label bar
	_fill_rect(image, Rect2i(6, 22, 20, 2), ink.darkened(0.25))
