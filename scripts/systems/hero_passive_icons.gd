class_name HeroPassiveIcons
extends RefCounted

## Procedural placeholder icons for hero innate passives until real art exists.

const ICON_SIZE := 32

static var _textures: Dictionary = {}


static func get_icon_texture(icon_id: StringName) -> Texture2D:
	if _textures.has(icon_id):
		return _textures[icon_id] as Texture2D

	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	match icon_id:
		HeroPassiveCatalog.PASSIVE_HOLY_RECOVERY:
			_draw_holy_recovery(image)
		HeroPassiveCatalog.PASSIVE_ASSASSIN:
			_draw_assassin(image)
		_:
			_draw_default(image)

	var texture := ImageTexture.create_from_image(image)
	_textures[icon_id] = texture
	return texture


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= ICON_SIZE or y >= ICON_SIZE:
				continue
			image.set_pixel(x, y, color)


static func _draw_default(image: Image) -> void:
	_fill_rect(image, Rect2i(4, 4, 24, 24), Color(0.35, 0.38, 0.45, 1))
	_fill_rect(image, Rect2i(12, 8, 8, 16), Color(0.7, 0.72, 0.78, 1))
	_fill_rect(image, Rect2i(8, 12, 16, 8), Color(0.7, 0.72, 0.78, 1))


static func _draw_holy_recovery(image: Image) -> void:
	var gold := Color(0.95, 0.82, 0.28, 1)
	var soft := Color(1.0, 0.94, 0.65, 1)
	var rim := Color(0.55, 0.4, 0.12, 1)

	# Soft circular aura
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dx: float = float(x) - 15.5
			var dy: float = float(y) - 15.5
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= 14.5:
				image.set_pixel(x, y, Color(0.22, 0.18, 0.08, 1))
			if dist <= 13.0:
				image.set_pixel(x, y, Color(0.42, 0.32, 0.1, 1))

	# Cross
	_fill_rect(image, Rect2i(14, 6, 4, 20), gold)
	_fill_rect(image, Rect2i(8, 12, 16, 4), gold)
	_fill_rect(image, Rect2i(15, 7, 2, 18), soft)
	_fill_rect(image, Rect2i(9, 13, 14, 2), soft)
	_fill_rect(image, Rect2i(13, 5, 6, 2), rim)
	_fill_rect(image, Rect2i(7, 11, 2, 6), rim)
	_fill_rect(image, Rect2i(23, 11, 2, 6), rim)
	_fill_rect(image, Rect2i(13, 25, 6, 2), rim)


static func _draw_assassin(image: Image) -> void:
	var purple := Color(0.42, 0.2, 0.55, 1)
	var blade := Color(0.82, 0.86, 0.95, 1)
	var accent := Color(0.95, 0.35, 0.55, 1)

	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dx: float = float(x) - 15.5
			var dy: float = float(y) - 15.5
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= 14.5:
				image.set_pixel(x, y, Color(0.12, 0.08, 0.16, 1))
			if dist <= 13.0:
				image.set_pixel(x, y, purple)

	# Dagger
	_fill_rect(image, Rect2i(15, 6, 3, 18), blade)
	_fill_rect(image, Rect2i(14, 7, 5, 2), blade)
	_fill_rect(image, Rect2i(12, 22, 9, 3), accent)
	_fill_rect(image, Rect2i(15, 25, 3, 3), Color(0.55, 0.45, 0.25, 1))
