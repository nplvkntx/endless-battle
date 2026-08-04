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
		HeroItemCatalog.ITEM_IRON_BLADE:
			_draw_sword(image, Color(0.72, 0.74, 0.80, 1))
		HeroItemCatalog.ITEM_WAR_AXE:
			_draw_axe(image, Color(0.82, 0.48, 0.30, 1))
		HeroItemCatalog.ITEM_VITALITY_GEM:
			_draw_gem(image, Color(0.88, 0.22, 0.28, 1), Color(1.0, 0.5, 0.55, 1))
		HeroItemCatalog.ITEM_IRON_PLATE:
			_draw_plate(image, Color(0.58, 0.60, 0.66, 1))
		HeroItemCatalog.ITEM_TRAVEL_BOOTS:
			_draw_boots(image, Color(0.48, 0.32, 0.18, 1), Color(0.30, 0.20, 0.12, 1))
		HeroItemCatalog.ITEM_HUNTER_GLOVES:
			_draw_gloves(image, Color(0.50, 0.66, 0.34, 1))
		HeroItemCatalog.ITEM_LUCKY_TALISMAN:
			_draw_talisman(image, Color(0.92, 0.76, 0.24, 1))
		HeroItemCatalog.ITEM_VAMPIRIC_FANG:
			_draw_fang(image, Color(0.78, 0.16, 0.24, 1))
		HeroItemCatalog.ITEM_SAPPHIRE_GEM:
			_draw_gem(image, Color(0.28, 0.48, 0.92, 1), Color(0.55, 0.75, 1.0, 1))
		HeroItemCatalog.ITEM_MAGE_SIGIL:
			_draw_sigil(image, Color(0.58, 0.36, 0.92, 1))
		HeroItemCatalog.ITEM_FOCUS_CRYSTAL:
			_draw_crystal(image, Color(0.42, 0.72, 0.88, 1), Color(0.7, 0.9, 1.0, 1))
		HeroItemCatalog.ITEM_SAGE_PENDANT:
			_draw_pendant(image, Color(0.35, 0.58, 0.78, 1))
		HeroItemCatalog.ITEM_EXECUTIONER_AXE:
			_draw_axe(image, Color(0.78, 0.28, 0.18, 1))
		HeroItemCatalog.ITEM_CRESCENT_CLEAVER:
			_draw_cleaver(image, Color(0.68, 0.72, 0.82, 1))
		HeroItemCatalog.ITEM_GUARDIAN_PLATE:
			_draw_plate(image, Color(0.52, 0.58, 0.70, 1))
		HeroItemCatalog.ITEM_VAMPIRE_BLADE:
			_draw_sword(image, Color(0.82, 0.18, 0.28, 1))
		HeroItemCatalog.ITEM_DEADEYE_BOW:
			_draw_bow(image, Color(0.76, 0.58, 0.28, 1))
		HeroItemCatalog.ITEM_HUNTER_BOOTS:
			_draw_boots(image, Color(0.38, 0.55, 0.28, 1), Color(0.22, 0.36, 0.18, 1))
		HeroItemCatalog.ITEM_ARCANE_FOCUS:
			_draw_orb(image, Color(0.48, 0.30, 0.88, 1), Color(0.75, 0.55, 1.0, 1))
		HeroItemCatalog.ITEM_SAGE_ORB:
			_draw_orb(image, Color(0.28, 0.52, 0.90, 1), Color(0.55, 0.78, 1.0, 1))
		HeroItemCatalog.ITEM_BATTLE_STANDARD:
			_draw_banner(image, Color(0.78, 0.55, 0.20, 1))
		HeroItemCatalog.ITEM_TITAN_CLEAVER:
			_draw_cleaver(image, Color(0.58, 0.62, 0.78, 1))
		HeroItemCatalog.ITEM_BLOODLORD_BLADE:
			_draw_sword(image, Color(0.62, 0.08, 0.16, 1))
		HeroItemCatalog.ITEM_FORTRESS_HEART:
			_draw_heart(image, Color(0.55, 0.52, 0.58, 1), Color(0.78, 0.28, 0.32, 1))
		HeroItemCatalog.ITEM_PHANTOM_HUNTER:
			_draw_bow(image, Color(0.42, 0.72, 0.40, 1))
		HeroItemCatalog.ITEM_SOUL_CROWN:
			_draw_crown(image, Color(0.58, 0.32, 0.92, 1))
		HeroItemCatalog.ITEM_WARLORD_STANDARD:
			_draw_banner(image, Color(0.86, 0.48, 0.16, 1))
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


static func _draw_sword(image: Image, blade: Color) -> void:
	var guard := Color(0.55, 0.42, 0.2, 1)
	var handle := Color(0.35, 0.22, 0.12, 1)
	_fill_rect(image, Rect2i(7, 1, 2, 9), blade)
	_fill_rect(image, Rect2i(5, 9, 6, 2), guard)
	_fill_rect(image, Rect2i(7, 11, 2, 3), handle)


static func _draw_axe(image: Image, head: Color) -> void:
	var handle := Color(0.40, 0.26, 0.14, 1)
	_fill_rect(image, Rect2i(7, 2, 2, 12), handle)
	_fill_rect(image, Rect2i(3, 2, 8, 4), head)
	_fill_rect(image, Rect2i(2, 3, 2, 3), head)


static func _draw_cleaver(image: Image, blade: Color) -> void:
	var handle := Color(0.35, 0.22, 0.12, 1)
	_fill_rect(image, Rect2i(4, 2, 8, 6), blade)
	_fill_rect(image, Rect2i(10, 3, 3, 4), blade)
	_fill_rect(image, Rect2i(6, 8, 3, 6), handle)


static func _draw_gem(image: Image, base: Color, highlight: Color) -> void:
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dx: float = absf(float(x) - 7.5) / 7.0
			var dy: float = absf(float(y) - 7.5) / 7.0
			if dx + dy <= 1.0:
				image.set_pixel(x, y, highlight if (x + y) % 2 == 0 else base)


static func _draw_crystal(image: Image, base: Color, tip: Color) -> void:
	_fill_rect(image, Rect2i(6, 2, 4, 3), tip)
	_fill_rect(image, Rect2i(5, 5, 6, 3), base)
	_fill_rect(image, Rect2i(6, 8, 4, 4), base)
	_fill_rect(image, Rect2i(7, 12, 2, 2), tip)


static func _draw_plate(image: Image, metal: Color) -> void:
	var rim := metal.darkened(0.25)
	_fill_rect(image, Rect2i(3, 3, 10, 10), metal)
	_fill_rect(image, Rect2i(5, 5, 6, 6), rim)
	_fill_rect(image, Rect2i(6, 6, 4, 4), metal.lightened(0.15))


static func _draw_boots(image: Image, body: Color, sole: Color) -> void:
	_fill_rect(image, Rect2i(3, 4, 5, 6), body)
	_fill_rect(image, Rect2i(3, 10, 10, 3), sole)
	_fill_rect(image, Rect2i(3, 7, 3, 6), body)


static func _draw_gloves(image: Image, leather: Color) -> void:
	_fill_rect(image, Rect2i(3, 5, 4, 7), leather)
	_fill_rect(image, Rect2i(9, 5, 4, 7), leather)
	_fill_rect(image, Rect2i(4, 3, 2, 3), leather.lightened(0.12))
	_fill_rect(image, Rect2i(10, 3, 2, 3), leather.lightened(0.12))


static func _draw_talisman(image: Image, gold: Color) -> void:
	var center := Vector2(7.5, 9.0)
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dist: float = Vector2(float(x), float(y)).distance_to(center)
			if dist <= 4.5:
				image.set_pixel(x, y, gold if dist > 2.0 else gold.lightened(0.25))
	_fill_rect(image, Rect2i(7, 1, 2, 4), gold.darkened(0.2))


static func _draw_fang(image: Image, ivory: Color) -> void:
	_fill_rect(image, Rect2i(6, 2, 4, 3), ivory.lightened(0.15))
	_fill_rect(image, Rect2i(5, 5, 5, 4), ivory)
	_fill_rect(image, Rect2i(6, 9, 3, 3), ivory.darkened(0.1))
	_fill_rect(image, Rect2i(7, 12, 2, 2), ivory.darkened(0.2))


static func _draw_sigil(image: Image, ink: Color) -> void:
	var center := Vector2(7.5, 7.5)
	for y: int in ICON_SIZE:
		for x: int in ICON_SIZE:
			var dist: float = Vector2(float(x), float(y)).distance_to(center)
			if dist >= 4.5 and dist <= 6.5:
				image.set_pixel(x, y, ink)
			elif dist <= 2.0:
				image.set_pixel(x, y, ink.lightened(0.2))
	_fill_rect(image, Rect2i(7, 3, 2, 10), ink)
	_fill_rect(image, Rect2i(3, 7, 10, 2), ink)


static func _draw_pendant(image: Image, jewel: Color) -> void:
	_fill_rect(image, Rect2i(7, 1, 2, 5), jewel.darkened(0.25))
	_fill_rect(image, Rect2i(5, 6, 6, 6), jewel)
	_fill_rect(image, Rect2i(6, 7, 4, 4), jewel.lightened(0.2))


static func _draw_orb(image: Image, core: Color, glow: Color) -> void:
	var highlight := glow.lightened(0.25)
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


static func _draw_bow(image: Image, wood: Color) -> void:
	var string_color := Color(0.85, 0.85, 0.8, 1)
	_fill_rect(image, Rect2i(3, 2, 2, 12), wood)
	_fill_rect(image, Rect2i(4, 2, 4, 2), wood)
	_fill_rect(image, Rect2i(4, 12, 4, 2), wood)
	_fill_rect(image, Rect2i(8, 3, 1, 10), string_color)
	_fill_rect(image, Rect2i(9, 7, 4, 2), wood.lightened(0.1))


static func _draw_banner(image: Image, cloth: Color) -> void:
	var pole := Color(0.45, 0.32, 0.18, 1)
	_fill_rect(image, Rect2i(3, 1, 2, 14), pole)
	_fill_rect(image, Rect2i(5, 2, 8, 7), cloth)
	_fill_rect(image, Rect2i(7, 4, 4, 3), cloth.lightened(0.15))


static func _draw_heart(image: Image, shell: Color, core: Color) -> void:
	_fill_rect(image, Rect2i(3, 4, 4, 4), shell)
	_fill_rect(image, Rect2i(9, 4, 4, 4), shell)
	_fill_rect(image, Rect2i(4, 7, 8, 5), shell)
	_fill_rect(image, Rect2i(6, 11, 4, 2), shell)
	_fill_rect(image, Rect2i(6, 6, 4, 4), core)


static func _draw_crown(image: Image, metal: Color) -> void:
	var jewel := metal.lightened(0.25)
	_fill_rect(image, Rect2i(3, 7, 10, 5), metal)
	_fill_rect(image, Rect2i(3, 4, 2, 4), metal)
	_fill_rect(image, Rect2i(7, 3, 2, 5), metal)
	_fill_rect(image, Rect2i(11, 4, 2, 4), metal)
	_fill_rect(image, Rect2i(7, 8, 2, 2), jewel)
