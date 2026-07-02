class_name HeroItemIcons
extends RefCounted

## Procedural placeholder icons for hero shop items until real art exists.

const ICON_SIZE := 16

static var _textures: Dictionary = {}


static func get_icon_texture(item_id: StringName) -> Texture2D:
	if _textures.has(item_id):
		return _textures[item_id] as Texture2D

	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	match item_id:
		HeroItemCatalog.ITEM_LONG_SWORD:
			_draw_sword(image)
		HeroItemCatalog.ITEM_RUBY_CRYSTAL:
			_draw_ruby(image)
		HeroItemCatalog.ITEM_BOOTS:
			_draw_boots(image)
		HeroItemCatalog.ITEM_WIZARD_ORB:
			_draw_orb(image)
		HeroItemCatalog.ITEM_MAGE_RING:
			_draw_ring(image)
		HeroItemCatalog.ITEM_MANA_CRYSTAL:
			_draw_mana_crystal(image)
		HeroItemCatalog.ITEM_SORCERER_STAFF:
			_draw_staff(image)
		HeroItemCatalog.ITEM_ARCANE_BOOTS:
			_draw_arcane_boots(image)
		HeroItemCatalog.ITEM_ARCHMAGE_ORB:
			_draw_archmage_orb(image)
		_:
			image.fill(Color(0.5, 0.52, 0.58, 1))

	var texture := ImageTexture.create_from_image(image)
	_textures[item_id] = texture
	return texture


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= ICON_SIZE or y >= ICON_SIZE:
				continue
			image.set_pixel(x, y, color)


static func _draw_sword(image: Image) -> void:
	var blade := Color(0.78, 0.8, 0.88, 1)
	var guard := Color(0.55, 0.42, 0.2, 1)
	var handle := Color(0.35, 0.22, 0.12, 1)
	_fill_rect(image, Rect2i(7, 1, 2, 9), blade)
	_fill_rect(image, Rect2i(5, 9, 6, 2), guard)
	_fill_rect(image, Rect2i(7, 11, 2, 3), handle)


static func _draw_ruby(image: Image) -> void:
	var red := Color(0.9, 0.15, 0.2, 1)
	var highlight := Color(1, 0.45, 0.5, 1)
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dx: float = absf(float(x) - 7.5) / 7.0
			var dy: float = absf(float(y) - 7.5) / 7.0
			if dx + dy <= 1.0:
				image.set_pixel(x, y, highlight if (x + y) % 2 == 0 else red)


static func _draw_boots(image: Image) -> void:
	var brown := Color(0.45, 0.28, 0.14, 1)
	var sole := Color(0.28, 0.18, 0.1, 1)
	_fill_rect(image, Rect2i(3, 4, 5, 6), brown)
	_fill_rect(image, Rect2i(3, 10, 10, 3), sole)
	_fill_rect(image, Rect2i(3, 7, 3, 6), brown)


static func _draw_orb(image: Image) -> void:
	var core := Color(0.35, 0.45, 0.95, 1)
	var glow := Color(0.55, 0.35, 0.92, 1)
	var highlight := Color(0.75, 0.8, 1, 1)
	var center := Vector2(7.5, 7.5)
	var radius := 6.0
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dist: float = Vector2(float(x), float(y)).distance_to(center)
			if dist > radius:
				continue
			var color: Color = highlight if dist <= 3.0 else core
			if dist > radius - 1.5:
				color = glow
			image.set_pixel(x, y, color)


static func _draw_ring(image: Image) -> void:
	var band := Color(0.72, 0.55, 0.95, 1)
	var gem := Color(0.45, 0.25, 0.85, 1)
	var center := Vector2(7.5, 7.5)
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dist: float = Vector2(float(x), float(y)).distance_to(center)
			if dist >= 4.0 and dist <= 6.0:
				image.set_pixel(x, y, band)
			elif dist <= 2.0:
				image.set_pixel(x, y, gem)


static func _draw_mana_crystal(image: Image) -> void:
	var blue := Color(0.25, 0.55, 0.95, 1)
	var highlight := Color(0.55, 0.8, 1.0, 1)
	_fill_rect(image, Rect2i(6, 2, 4, 3), highlight)
	_fill_rect(image, Rect2i(5, 5, 6, 3), blue)
	_fill_rect(image, Rect2i(6, 8, 4, 4), blue)
	_fill_rect(image, Rect2i(7, 12, 2, 2), highlight)


static func _draw_staff(image: Image) -> void:
	var wood := Color(0.45, 0.28, 0.12, 1)
	var crystal := Color(0.75, 0.45, 0.95, 1)
	_fill_rect(image, Rect2i(7, 3, 2, 10), wood)
	_fill_rect(image, Rect2i(5, 1, 6, 3), crystal)


static func _draw_arcane_boots(image: Image) -> void:
	var blue := Color(0.28, 0.42, 0.72, 1)
	var glow := Color(0.45, 0.7, 1.0, 1)
	_fill_rect(image, Rect2i(3, 4, 5, 6), blue)
	_fill_rect(image, Rect2i(3, 10, 10, 3), glow)
	_fill_rect(image, Rect2i(3, 7, 3, 6), blue)


static func _draw_archmage_orb(image: Image) -> void:
	var core := Color(0.55, 0.2, 0.9, 1)
	var glow := Color(0.85, 0.45, 1.0, 1)
	var highlight := Color(0.95, 0.75, 1.0, 1)
	var center := Vector2(7.5, 7.5)
	var radius := 6.5
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dist: float = Vector2(float(x), float(y)).distance_to(center)
			if dist > radius:
				continue
			var color: Color = highlight if dist <= 2.5 else core
			if dist > radius - 1.5:
				color = glow
			image.set_pixel(x, y, color)
