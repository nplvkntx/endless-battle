extends Control

## Draws world entities and the camera view on the HUD minimap.

const ENEMY_TEAM_ID: int = 1

const FACTION_SKIP: int = -1
const FACTION_PLAYER: int = 0
const FACTION_ENEMY: int = 1
const FACTION_NEUTRAL: int = 2

const COLOR_BACKGROUND := Color(0.08, 0.1, 0.12, 1.0)
const COLOR_BORDER := Color(0.22, 0.24, 0.28, 1.0)
const COLOR_PLAYER_UNIT := Color(0.35, 0.65, 1.0, 1.0)
const COLOR_PLAYER_BUILDING := Color(0.25, 0.85, 0.35, 1.0)
const COLOR_ENEMY := Color(0.9, 0.25, 0.25, 1.0)
const COLOR_NEUTRAL_RESOURCE := Color(0.85, 0.75, 0.2, 1.0)
const COLOR_NEUTRAL_CREEP := Color(0.55, 0.55, 0.6, 1.0)
const COLOR_CAMERA_RECT := Color(1.0, 1.0, 1.0, 0.85)

@export var world_min_x: float = -50.0
@export var world_max_x: float = 50.0
@export var world_min_z: float = -50.0
@export var world_max_z: float = 50.0
@export var camera_path: NodePath
@export var update_interval: float = 0.1

var _camera: Camera3D
var _dots: Array[Dictionary] = []
var _camera_rect: Rect2 = Rect2()
var _has_camera_rect: bool = false
var _update_timer: float = 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_camera = _resolve_camera()
	_refresh_entities()
	queue_redraw()


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < update_interval:
		return

	_update_timer = 0.0
	_refresh_entities()
	queue_redraw()


func _on_resized() -> void:
	_refresh_entities()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 1.0)

	if _has_camera_rect:
		draw_rect(_camera_rect, COLOR_CAMERA_RECT, false, 1.0)

	for dot: Dictionary in _dots:
		draw_circle(dot.pos, dot.radius, dot.color)


func _resolve_camera() -> Camera3D:
	if not camera_path.is_empty():
		var path_camera: Camera3D = get_node_or_null(camera_path) as Camera3D
		if path_camera != null:
			return path_camera

	return get_viewport().get_camera_3d()


func _refresh_entities() -> void:
	_dots.clear()
	_has_camera_rect = false

	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var seen: Dictionary = {}
	_collect_group_dots(tree, &"units", seen)
	_collect_group_dots(tree, &"buildings", seen)
	_collect_group_dots(tree, &"enemy_command_center", seen)
	_collect_resource_dots(tree, seen)
	_update_camera_rect()


func _collect_group_dots(tree: SceneTree, group_name: StringName, seen: Dictionary) -> void:
	for node: Node in tree.get_nodes_in_group(group_name):
		_add_entity_dot(node, seen)


func _collect_resource_dots(tree: SceneTree, seen: Dictionary) -> void:
	for node: Node in tree.get_nodes_in_group(&"resource_nodes"):
		if not _mark_seen(node, seen):
			continue
		if not node is Node3D:
			continue

		var node_3d: Node3D = node as Node3D
		_dots.append(
			{
				"pos": _world_to_minimap(node_3d.global_position.x, node_3d.global_position.z),
				"radius": 2.0,
				"color": COLOR_NEUTRAL_RESOURCE,
			}
		)


func _add_entity_dot(node: Node, seen: Dictionary) -> void:
	if not _mark_seen(node, seen):
		return
	if not node is Node3D:
		return

	var faction: int = _classify_entity(node)
	if faction == FACTION_SKIP:
		return

	var is_building: bool = node is Building
	var node_3d: Node3D = node as Node3D
	var color: Color = _color_for_faction(faction, node, is_building)
	var radius: float = 3.5 if is_building else 2.5

	_dots.append(
		{
			"pos": _world_to_minimap(node_3d.global_position.x, node_3d.global_position.z),
			"radius": radius,
			"color": color,
		}
	)


func _mark_seen(node: Node, seen: Dictionary) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false

	var instance_id: int = node.get_instance_id()
	if seen.has(instance_id):
		return false

	seen[instance_id] = true
	return true


func _classify_entity(node: Node) -> int:
	if node.is_in_group(&"resource_nodes"):
		return FACTION_NEUTRAL

	if node.is_in_group(&"neutral_creeps"):
		return FACTION_NEUTRAL

	if node.is_in_group(&"enemies") or node.is_in_group(&"enemy_command_center"):
		return FACTION_ENEMY

	if node is Unit and (node as Unit).team_id >= ENEMY_TEAM_ID:
		return FACTION_ENEMY

	if node is Building and (node as Building).team_id >= ENEMY_TEAM_ID:
		return FACTION_ENEMY

	if node is Unit or node is Building:
		return FACTION_PLAYER

	return FACTION_SKIP


func _color_for_faction(faction: int, node: Node, is_building: bool) -> Color:
	match faction:
		FACTION_ENEMY:
			return COLOR_ENEMY
		FACTION_NEUTRAL:
			if node.is_in_group(&"neutral_creeps"):
				return COLOR_NEUTRAL_CREEP
			return COLOR_NEUTRAL_RESOURCE
		_:
			return COLOR_PLAYER_BUILDING if is_building else COLOR_PLAYER_UNIT


func _update_camera_rect() -> void:
	_camera = _resolve_camera()
	if _camera == null:
		return

	var cam_pos: Vector3 = _camera.global_position
	var half_extent: float = cam_pos.y * tan(deg_to_rad(_camera.fov * 0.5)) * 1.1
	var world_min := Vector2(cam_pos.x - half_extent, cam_pos.z - half_extent)
	var world_max := Vector2(cam_pos.x + half_extent, cam_pos.z + half_extent)

	var top_left: Vector2 = _world_to_minimap(world_min.x, world_min.y)
	var bottom_right: Vector2 = _world_to_minimap(world_max.x, world_max.y)
	_camera_rect = Rect2(top_left, bottom_right - top_left)
	_has_camera_rect = true


func _world_to_minimap(world_x: float, world_z: float) -> Vector2:
	var span_x: float = world_max_x - world_min_x
	var span_z: float = world_max_z - world_min_z
	if span_x <= 0.0 or span_z <= 0.0:
		return Vector2.ZERO

	var normalized_x: float = (world_x - world_min_x) / span_x
	var normalized_z: float = (world_z - world_min_z) / span_z
	return Vector2(normalized_x * size.x, (1.0 - normalized_z) * size.y)
