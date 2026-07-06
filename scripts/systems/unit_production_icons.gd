class_name UnitProductionIcons
extends RefCounted

## Procedural placeholder portraits for production UI until real unit art exists.

const ICON_SIZE := 48

static var _textures: Dictionary = {}

static var _PORTRAIT_COLORS: Dictionary = {
	&"worker": Color(0.55, 0.35, 0.15, 1),
	&"spearman": Color(0.62, 0.48, 0.28, 1),
	&"swordsman": Color(0.35, 0.45, 0.75, 1),
	&"archer": Color(0.15, 0.65, 0.25, 1),
	&"hero": Color(0.85, 0.65, 0.15, 1),
}


static func get_icon_texture(train_id: StringName) -> Texture2D:
	if _textures.has(train_id):
		return _textures[train_id] as Texture2D

	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var base_color: Color = _PORTRAIT_COLORS.get(train_id, Color(0.42, 0.44, 0.48, 1))
	image.fill(base_color.darkened(0.35))

	match train_id:
		CommandCenter.TRAIN_ID_WORKER:
			_draw_worker(image, base_color)
		Barracks.TRAIN_ID_SPEARMAN:
			_draw_spearman(image, base_color)
		Barracks.TRAIN_ID_SWORDSMAN:
			_draw_swordsman(image, base_color)
		Barracks.TRAIN_ID_ARCHER:
			_draw_archer(image, base_color)
		&"hero":
			_draw_hero(image, base_color)
		_:
			image.fill(base_color)

	var texture := ImageTexture.create_from_image(image)
	_textures[train_id] = texture
	return texture


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= ICON_SIZE or y >= ICON_SIZE:
				continue
			image.set_pixel(x, y, color)


static func _draw_worker(image: Image, color: Color) -> void:
	var skin := color.lightened(0.2)
	var hat := color.darkened(0.15)
	_fill_rect(image, Rect2i(18, 10, 12, 12), skin)
	_fill_rect(image, Rect2i(16, 6, 16, 6), hat)
	_fill_rect(image, Rect2i(20, 22, 8, 16), color)


static func _draw_spearman(image: Image, color: Color) -> void:
	var spear_shaft := Color(0.45, 0.3, 0.15, 1)
	var spear_tip := Color(0.72, 0.74, 0.78, 1)
	_fill_rect(image, Rect2i(18, 10, 12, 14), color)
	_fill_rect(image, Rect2i(32, 4, 3, 30), spear_shaft)
	_fill_rect(image, Rect2i(31, 2, 5, 6), spear_tip)
	_fill_rect(image, Rect2i(18, 30, 12, 8), color.darkened(0.25))


static func _draw_swordsman(image: Image, color: Color) -> void:
	var blade := Color(0.82, 0.85, 0.92, 1)
	var guard_color := color.darkened(0.2)
	_fill_rect(image, Rect2i(18, 8, 12, 14), color)
	_fill_rect(image, Rect2i(30, 6, 4, 28), blade)
	_fill_rect(image, Rect2i(28, 18, 8, 4), guard_color)
	_fill_rect(image, Rect2i(18, 30, 12, 10), color.darkened(0.25))


static func _draw_archer(image: Image, color: Color) -> void:
	var bow := Color(0.55, 0.35, 0.15, 1)
	var string_color := Color(0.9, 0.88, 0.8, 1)
	_fill_rect(image, Rect2i(18, 10, 12, 14), color)
	_fill_rect(image, Rect2i(8, 12, 4, 20), bow)
	_fill_rect(image, Rect2i(36, 12, 4, 20), bow)
	for y: int in range(14, 30):
		image.set_pixel(20, y, string_color)
	_fill_rect(image, Rect2i(18, 30, 12, 8), color.darkened(0.25))


static func _draw_hero(image: Image, color: Color) -> void:
	var crown := Color(0.95, 0.82, 0.2, 1)
	_fill_rect(image, Rect2i(16, 12, 16, 16), color)
	_fill_rect(image, Rect2i(14, 6, 20, 8), crown)
	_fill_rect(image, Rect2i(18, 4, 4, 4), crown.lightened(0.15))
	_fill_rect(image, Rect2i(26, 4, 4, 4), crown.lightened(0.15))
	_fill_rect(image, Rect2i(16, 32, 16, 10), color.darkened(0.2))
