class_name BuildingCommandIcons
extends RefCounted

## Procedural building command icons with optional scene thumbnail upgrade.

const ICON_SIZE := 48

const _BUILD_MANAGER := preload("res://scripts/systems/build_manager.gd")

static var _textures: Dictionary = {}
static var _thumbnail_attempted: Dictionary = {}

const _ICON_TEXTURE_PATHS: Dictionary = {}

const _PLACEMENT_SCENES: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_FARM: _BUILD_MANAGER.FARM_SCENE,
	_BUILD_MANAGER.PLACEMENT_BARRACKS: _BUILD_MANAGER.BARRACKS_SCENE,
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: _BUILD_MANAGER.BLACKSMITH_SCENE,
	_BUILD_MANAGER.PLACEMENT_STABLE: _BUILD_MANAGER.STABLE_SCENE,
	_BUILD_MANAGER.PLACEMENT_ARTILLERY_DEPOT: _BUILD_MANAGER.ARTILLERY_DEPOT_SCENE,
	_BUILD_MANAGER.PLACEMENT_ACADEMY: _BUILD_MANAGER.ACADEMY_SCENE,
	_BUILD_MANAGER.PLACEMENT_SHOP: _BUILD_MANAGER.SHOP_SCENE,
	_BUILD_MANAGER.PLACEMENT_TOWER: _BUILD_MANAGER.TOWER_SCENE,
	_BUILD_MANAGER.PLACEMENT_WALL_SEGMENT: _BUILD_MANAGER.WALL_SEGMENT_SCENE,
	_BUILD_MANAGER.PLACEMENT_HERO_ALTAR: _BUILD_MANAGER.HERO_ALTAR_SCENE,
	_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER: _BUILD_MANAGER.COMMAND_CENTER_SCENE,
}

const _PORTRAIT_COLORS: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_FARM: Color(0.45, 0.7, 0.25, 1),
	_BUILD_MANAGER.PLACEMENT_BARRACKS: Color(0.5, 0.32, 0.22, 1),
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: Color(0.58, 0.42, 0.22, 1),
	_BUILD_MANAGER.PLACEMENT_STABLE: Color(0.42, 0.48, 0.28, 1),
	_BUILD_MANAGER.PLACEMENT_ARTILLERY_DEPOT: Color(0.34, 0.38, 0.3, 1),
	_BUILD_MANAGER.PLACEMENT_ACADEMY: Color(0.42, 0.38, 0.58, 1),
	_BUILD_MANAGER.PLACEMENT_SHOP: Color(0.72, 0.48, 0.22, 1),
	_BUILD_MANAGER.PLACEMENT_TOWER: Color(0.55, 0.58, 0.62, 1),
	_BUILD_MANAGER.PLACEMENT_WALL_SEGMENT: Color(0.48, 0.5, 0.52, 1),
	_BUILD_MANAGER.PLACEMENT_HERO_ALTAR: Color(0.55, 0.35, 0.75, 1),
	_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER: Color(0.75, 0.4, 0.15, 1),
}

const _INITIALS: Dictionary = {
	_BUILD_MANAGER.PLACEMENT_FARM: "F",
	_BUILD_MANAGER.PLACEMENT_BARRACKS: "B",
	_BUILD_MANAGER.PLACEMENT_BLACKSMITH: "BS",
	_BUILD_MANAGER.PLACEMENT_STABLE: "St",
	_BUILD_MANAGER.PLACEMENT_ARTILLERY_DEPOT: "AD",
	_BUILD_MANAGER.PLACEMENT_ACADEMY: "Ac",
	_BUILD_MANAGER.PLACEMENT_SHOP: "Sh",
	_BUILD_MANAGER.PLACEMENT_TOWER: "T",
	_BUILD_MANAGER.PLACEMENT_WALL_SEGMENT: "W",
	_BUILD_MANAGER.PLACEMENT_HERO_ALTAR: "HA",
	_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER: "TC",
}

const GATE_COMMAND_BUILD := &"gate_build"
const GATE_COMMAND_OPEN := &"gate_open"
const GATE_COMMAND_CLOSE := &"gate_close"

const _GATE_COMMAND_COLORS: Dictionary = {
	GATE_COMMAND_BUILD: Color(0.48, 0.5, 0.52, 1),
	GATE_COMMAND_OPEN: Color(0.35, 0.62, 0.38, 1),
	GATE_COMMAND_CLOSE: Color(0.62, 0.38, 0.32, 1),
}


static func get_gate_command_icon(command_id: StringName) -> Texture2D:
	if _textures.has(command_id):
		return _textures[command_id] as Texture2D

	var base_color: Color = _GATE_COMMAND_COLORS.get(command_id, Color(0.48, 0.5, 0.52, 1))
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(base_color.darkened(0.38))

	match command_id:
		GATE_COMMAND_BUILD:
			_draw_gate_build(image, base_color)
		GATE_COMMAND_OPEN:
			_draw_gate_open(image, base_color)
		GATE_COMMAND_CLOSE:
			_draw_gate_close(image, base_color)
		_:
			_draw_initials(image, "?", base_color)

	var texture := ImageTexture.create_from_image(image)
	_textures[command_id] = texture
	return texture


static func get_icon_texture(placement_id: StringName) -> Texture2D:
	if _textures.has(placement_id):
		return _textures[placement_id] as Texture2D

	var texture_path: String = String(_ICON_TEXTURE_PATHS.get(placement_id, ""))
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var loaded_texture: Texture2D = load(texture_path) as Texture2D
		if loaded_texture != null:
			_textures[placement_id] = loaded_texture
			return loaded_texture

	var procedural_texture: Texture2D = _create_procedural_icon(placement_id)
	_textures[placement_id] = procedural_texture
	_try_schedule_scene_thumbnail(placement_id)
	return procedural_texture


static func get_initials(placement_id: StringName) -> String:
	return String(_INITIALS.get(placement_id, "?"))


static func _try_schedule_scene_thumbnail(placement_id: StringName) -> void:
	if _thumbnail_attempted.get(placement_id, false):
		return

	if _should_skip_scene_thumbnails():
		return

	if not _PLACEMENT_SCENES.has(placement_id):
		return

	_thumbnail_attempted[placement_id] = true

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return

	var scene: PackedScene = _PLACEMENT_SCENES[placement_id] as PackedScene
	if scene == null:
		return

	var renderer := _ThumbnailRenderer.new(placement_id, scene)
	tree.root.call_deferred("add_child", renderer)


static func _should_skip_scene_thumbnails() -> bool:
	return DisplayServer.get_name() == "headless"


static func _cache_texture(placement_id: StringName, texture: Texture2D) -> void:
	if texture != null:
		_textures[placement_id] = texture


static func _render_scene_thumbnail_async(host: Node, scene: PackedScene) -> Texture2D:
	if scene == null or host == null:
		return null

	var tree: SceneTree = host.get_tree()
	if tree == null:
		return null

	var viewport := SubViewport.new()
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = true
	viewport.handle_input_locally = false

	var world := Node3D.new()
	viewport.add_child(world)

	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		viewport.queue_free()
		return null

	_prepare_thumbnail_instance(instance)
	world.add_child(instance)

	var bounds: AABB = _estimate_visual_bounds(instance)
	if bounds.size.length_squared() <= 0.0001:
		bounds = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))

	var center: Vector3 = bounds.get_center()
	var max_extent: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	max_extent = maxf(max_extent, 0.5)

	host.add_child(viewport)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = max_extent * 1.35
	world.add_child(camera)
	var camera_offset := Vector3(max_extent * 0.85, max_extent * 0.65, max_extent * 0.95)
	var camera_position: Vector3 = center + camera_offset
	camera.position = camera_position
	camera.look_at_from_position(camera_position, center, Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.45
	world.add_child(fill)

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await tree.process_frame
	await tree.process_frame

	var viewport_texture: ViewportTexture = viewport.get_texture()
	if viewport_texture == null:
		viewport.queue_free()
		return null

	var image: Image = viewport_texture.get_image()
	viewport.queue_free()

	if image == null or image.is_empty():
		return null

	return ImageTexture.create_from_image(image)


static func _prepare_thumbnail_instance(instance: Node3D) -> void:
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance is CollisionObject3D:
		var collision_object := instance as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0

	for child: Node in instance.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
		elif child is Node3D:
			_prepare_thumbnail_instance(child as Node3D)


static func _estimate_visual_bounds(
	node: Node,
	parent_transform: Transform3D = Transform3D.IDENTITY,
	bounds: AABB = AABB()
) -> AABB:
	var node_transform: Transform3D = parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible:
			var mesh_aabb: AABB = mesh_instance.get_aabb()
			var transformed: AABB = node_transform * mesh_aabb
			bounds = bounds.merge(transformed)

	for child: Node in node.get_children():
		if child.name == &"SelectionIndicator":
			continue
		bounds = _estimate_visual_bounds(child, node_transform, bounds)

	return bounds


static func _create_procedural_icon(placement_id: StringName) -> Texture2D:
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var base_color: Color = _PORTRAIT_COLORS.get(placement_id, Color(0.42, 0.44, 0.48, 1))
	image.fill(base_color.darkened(0.38))

	match placement_id:
		_BUILD_MANAGER.PLACEMENT_FARM:
			_draw_farm(image, base_color)
		_BUILD_MANAGER.PLACEMENT_BARRACKS:
			_draw_barracks(image, base_color)
		_BUILD_MANAGER.PLACEMENT_BLACKSMITH:
			_draw_blacksmith(image, base_color)
		_BUILD_MANAGER.PLACEMENT_STABLE:
			_draw_stable(image, base_color)
		_BUILD_MANAGER.PLACEMENT_ARTILLERY_DEPOT:
			_draw_artillery_depot(image, base_color)
		_BUILD_MANAGER.PLACEMENT_ACADEMY:
			_draw_academy(image, base_color)
		_BUILD_MANAGER.PLACEMENT_SHOP:
			_draw_shop(image, base_color)
		_BUILD_MANAGER.PLACEMENT_TOWER:
			_draw_tower(image, base_color)
		_BUILD_MANAGER.PLACEMENT_WALL_SEGMENT:
			_draw_wall_segment(image, base_color)
		_BUILD_MANAGER.PLACEMENT_HERO_ALTAR:
			_draw_hero_altar(image, base_color)
		_BUILD_MANAGER.PLACEMENT_COMMAND_CENTER:
			_draw_town_center(image, base_color)
		_:
			_draw_initials(image, get_initials(placement_id), base_color)

	var texture := ImageTexture.create_from_image(image)
	return texture


static func _draw_initials(image: Image, initials: String, color: Color) -> void:
	if initials.is_empty():
		return

	var glyph_color := color.lightened(0.35)
	var start_x: int = ICON_SIZE / 2 - initials.length() * 4
	for index: int in initials.length():
		_fill_rect(image, Rect2i(start_x + index * 8, 16, 6, 14), glyph_color)


static func _draw_farm(image: Image, color: Color) -> void:
	var field := color.darkened(0.1)
	var crop := color.lightened(0.2)
	var roof := Color(0.55, 0.28, 0.12, 1)
	_fill_rect(image, Rect2i(4, 24, 40, 16), field)
	_fill_rect(image, Rect2i(8, 18, 14, 10), roof)
	_fill_rect(image, Rect2i(10, 10, 4, 8), crop)
	_fill_rect(image, Rect2i(18, 12, 4, 6), crop)
	_fill_rect(image, Rect2i(26, 10, 4, 8), crop)


static func _draw_barracks(image: Image, color: Color) -> void:
	var wall := color
	var roof := color.darkened(0.25)
	var door := color.darkened(0.4)
	_fill_rect(image, Rect2i(10, 16, 28, 22), wall)
	_fill_rect(image, Rect2i(8, 10, 32, 8), roof)
	_fill_rect(image, Rect2i(20, 26, 8, 12), door)
	_fill_rect(image, Rect2i(30, 8, 4, 10), Color(0.85, 0.2, 0.2, 1))


static func _draw_blacksmith(image: Image, color: Color) -> void:
	var wall := color
	var anvil := Color(0.35, 0.38, 0.42, 1)
	_fill_rect(image, Rect2i(8, 18, 32, 20), wall)
	_fill_rect(image, Rect2i(16, 28, 16, 6), anvil)
	_fill_rect(image, Rect2i(20, 24, 8, 4), anvil.lightened(0.15))


static func _draw_stable(image: Image, color: Color) -> void:
	var wall := color
	var roof := color.darkened(0.2)
	var door := color.darkened(0.35)
	_fill_rect(image, Rect2i(10, 18, 28, 20), wall)
	_fill_rect(image, Rect2i(8, 12, 32, 8), roof)
	_fill_rect(image, Rect2i(20, 26, 8, 12), door)


static func _draw_artillery_depot(image: Image, color: Color) -> void:
	var wall := color
	var roof := color.darkened(0.15)
	var bay := color.darkened(0.35)
	var barrel := Color(0.3, 0.32, 0.36, 1)
	_fill_rect(image, Rect2i(8, 20, 32, 16), wall)
	_fill_rect(image, Rect2i(6, 14, 36, 7), roof)
	_fill_rect(image, Rect2i(24, 24, 12, 10), bay)
	_fill_rect(image, Rect2i(28, 27, 14, 4), barrel)


static func _draw_academy(image: Image, color: Color) -> void:
	var wall := color
	var dome := color.lightened(0.12)
	var column := Color(0.78, 0.76, 0.86, 1)
	var step := color.darkened(0.2)
	_fill_rect(image, Rect2i(10, 22, 28, 14), wall)
	_fill_rect(image, Rect2i(14, 8, 20, 10), dome)
	_fill_rect(image, Rect2i(12, 18, 4, 12), column)
	_fill_rect(image, Rect2i(32, 18, 4, 12), column)
	_fill_rect(image, Rect2i(16, 34, 16, 4), step)


static func _draw_shop(image: Image, color: Color) -> void:
	var stall := color
	var awning := color.lightened(0.15)
	var post := color.darkened(0.3)
	_fill_rect(image, Rect2i(10, 24, 28, 12), stall)
	_fill_rect(image, Rect2i(8, 16, 32, 8), awning)
	_fill_rect(image, Rect2i(12, 16, 3, 20), post)
	_fill_rect(image, Rect2i(33, 16, 3, 20), post)


static func _draw_tower(image: Image, color: Color) -> void:
	var stone := color
	var top := color.lightened(0.12)
	_fill_rect(image, Rect2i(18, 10, 12, 30), stone)
	_fill_rect(image, Rect2i(16, 8, 16, 4), top)
	_fill_rect(image, Rect2i(22, 18, 4, 6), color.darkened(0.35))


static func _draw_wall_segment(image: Image, color: Color) -> void:
	var stone := color
	var mortar := color.darkened(0.25)
	var highlight := color.lightened(0.1)
	_fill_rect(image, Rect2i(8, 12, 32, 28), mortar)
	_fill_rect(image, Rect2i(10, 14, 13, 7), stone)
	_fill_rect(image, Rect2i(25, 14, 13, 7), highlight)
	_fill_rect(image, Rect2i(10, 23, 13, 7), highlight)
	_fill_rect(image, Rect2i(25, 23, 13, 7), stone)
	_fill_rect(image, Rect2i(10, 32, 13, 6), stone)
	_fill_rect(image, Rect2i(25, 32, 13, 6), highlight)


static func _draw_gate_build(image: Image, color: Color) -> void:
	var post := color.darkened(0.15)
	var panel := color.lightened(0.12)
	_fill_rect(image, Rect2i(10, 12, 6, 28), post)
	_fill_rect(image, Rect2i(32, 12, 6, 28), post)
	_fill_rect(image, Rect2i(16, 16, 16, 20), panel)


static func _draw_gate_open(image: Image, color: Color) -> void:
	var post := color.darkened(0.15)
	var arrow := color.lightened(0.35)
	_fill_rect(image, Rect2i(10, 12, 6, 28), post)
	_fill_rect(image, Rect2i(32, 12, 6, 28), post)
	_fill_rect(image, Rect2i(18, 24, 12, 4), arrow)
	_fill_rect(image, Rect2i(24, 20, 4, 12), arrow)


static func _draw_gate_close(image: Image, color: Color) -> void:
	var post := color.darkened(0.15)
	var panel := color.lightened(0.12)
	_fill_rect(image, Rect2i(10, 12, 6, 28), post)
	_fill_rect(image, Rect2i(32, 12, 6, 28), post)
	_fill_rect(image, Rect2i(16, 16, 16, 20), panel)
	_fill_rect(image, Rect2i(22, 8, 4, 8), color.lightened(0.25))


static func _draw_hero_altar(image: Image, color: Color) -> void:
	var base := color.darkened(0.15)
	var column := color.lightened(0.1)
	var roof := color.lightened(0.2)
	_fill_rect(image, Rect2i(8, 30, 32, 8), base)
	_fill_rect(image, Rect2i(12, 14, 5, 18), column)
	_fill_rect(image, Rect2i(31, 14, 5, 18), column)
	_fill_rect(image, Rect2i(10, 10, 28, 6), roof)


static func _draw_town_center(image: Image, color: Color) -> void:
	var wall := color
	var roof := color.darkened(0.2)
	var accent := color.lightened(0.25)
	_fill_rect(image, Rect2i(6, 18, 36, 20), wall)
	_fill_rect(image, Rect2i(4, 12, 40, 8), roof)
	_fill_rect(image, Rect2i(20, 24, 8, 14), accent)
	_fill_rect(image, Rect2i(10, 20, 6, 6), accent.darkened(0.1))
	_fill_rect(image, Rect2i(32, 20, 6, 6), accent.darkened(0.1))


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= ICON_SIZE or y >= ICON_SIZE:
				continue
			image.set_pixel(x, y, color)


class _ThumbnailRenderer extends Node:
	var _placement_id: StringName = &""
	var _scene: PackedScene = null


	func _init(placement_id: StringName, scene: PackedScene) -> void:
		_placement_id = placement_id
		_scene = scene


	func _ready() -> void:
		_capture_and_cache()


	func _capture_and_cache() -> void:
		await get_tree().process_frame
		var thumbnail: Texture2D = await BuildingCommandIcons._render_scene_thumbnail_async(self, _scene)
		BuildingCommandIcons._cache_texture(_placement_id, thumbnail)
		queue_free()
