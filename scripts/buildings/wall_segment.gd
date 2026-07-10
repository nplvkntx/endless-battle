class_name WallSegment
extends Building

## Placeholder wall segment that blocks movement and absorbs damage.
## Completed segments can be converted into gates with open/close passage control.

signal gate_state_changed

const GATE_CONVERSION_WOOD_COST := 100
const GATE_POST_SIZE := Vector3(0.22, 1.5, 0.22)
const GATE_POST_X_OFFSET := 0.36
const GATE_PASSAGE_SIZE := Vector3(0.46, 1.2, 0.12)
const GATE_WIDE_PASSAGE_SIZE := Vector3(0.9, 1.2, 0.12)
const GATE_WIDE_POST_OFFSET := 1.0

static var _next_wall_chain_id: int = 1

var is_gate: bool = false
var gate_open: bool = false
var wall_chain_id: int = 0
var gate_axis: Vector3 = Vector3.RIGHT
var gate_span: int = 1

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent
@onready var _wall_placeholder: MeshInstance3D = get_node_or_null(
	"Visuals/WallPlaceholder"
) as MeshInstance3D
@onready var _gate_visuals: Node3D = get_node_or_null("Visuals/GateVisuals") as Node3D
@onready var _gate_left_post_visual: MeshInstance3D = get_node_or_null(
	"Visuals/GateVisuals/LeftPost"
) as MeshInstance3D
@onready var _gate_right_post_visual: MeshInstance3D = get_node_or_null(
	"Visuals/GateVisuals/RightPost"
) as MeshInstance3D
@onready var _gate_panel: MeshInstance3D = get_node_or_null(
	"Visuals/GateVisuals/GatePanel"
) as MeshInstance3D
@onready var _collision_shape: CollisionShape3D = get_node_or_null(
	"CollisionShape3D"
) as CollisionShape3D

var _gate_left_post_collision: CollisionShape3D
var _gate_right_post_collision: CollisionShape3D
var _gate_passage_collision: CollisionShape3D
var _gate_post_navigation_obstacles: Array[NavigationObstacle3D] = []


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)

	if is_gate:
		_ensure_gate_collision_shapes()
		_apply_gate_visual_state()
		call_deferred("_enforce_gate_navigation_state")


func _wants_navigation_obstacle() -> bool:
	return not is_gate


static func allocate_wall_chain_id() -> int:
	var chain_id: int = _next_wall_chain_id
	_next_wall_chain_id += 1
	return chain_id


static func collect_unfinished_chain_segments(from_segment: WallSegment) -> Array[Building]:
	var segments: Array[Building] = []
	if not NodeSafety.is_alive_node(from_segment):
		return segments

	if from_segment.wall_chain_id > 0:
		var tree: SceneTree = from_segment.get_tree()
		if tree == null:
			return segments

		for node: Node in tree.get_nodes_in_group(&"buildings"):
			if not node is WallSegment:
				continue

			var segment: WallSegment = node as WallSegment
			if segment.wall_chain_id != from_segment.wall_chain_id:
				continue

			if segment.is_being_constructed():
				segments.append(segment)

		return segments

	return _flood_fill_connected_unfinished_segments(from_segment)


static func _flood_fill_connected_unfinished_segments(start: WallSegment) -> Array[Building]:
	var segments: Array[Building] = []
	if not NodeSafety.is_alive_node(start) or not start.is_being_constructed():
		return segments

	var visited: Dictionary = {}
	var queue: Array[WallSegment] = [start]

	while not queue.is_empty():
		var current: WallSegment = queue.pop_front()
		if visited.has(current):
			continue

		visited[current] = true
		if not current.is_being_constructed():
			continue

		segments.append(current)

		for neighbor: WallSegment in current._find_adjacent_wall_segments():
			if visited.has(neighbor):
				continue

			if neighbor.is_being_constructed():
				queue.append(neighbor)

	return segments


func can_show_commands() -> bool:
	if building_state != STATE_COMPLETED:
		return false

	return _is_player_owned()


func can_build_gate() -> bool:
	if not NodeSafety.is_alive_node(self):
		return false

	return can_show_commands() and not is_gate


func try_convert_to_gate() -> bool:
	if not can_build_gate():
		return false

	if not ResourceManager.can_afford(0, GATE_CONVERSION_WOOD_COST):
		ResourceManager.show_feedback("Not enough wood")
		return false

	if not ResourceManager.try_spend(0, GATE_CONVERSION_WOOD_COST):
		ResourceManager.show_feedback("Not enough wood")
		return false

	_convert_to_gate()
	return true


func try_open_gate() -> bool:
	if not is_gate or gate_open or not NodeSafety.is_alive_node(self):
		return false

	gate_open = true
	_apply_gate_passage_blocking(false)
	_apply_gate_visual_state()
	gate_state_changed.emit()
	call_deferred("_enforce_gate_navigation_state")
	return true


func try_close_gate() -> bool:
	if not is_gate or not gate_open or not NodeSafety.is_alive_node(self):
		return false

	gate_open = false
	_apply_gate_passage_blocking(true)
	_apply_gate_visual_state()
	gate_state_changed.emit()
	call_deferred("_enforce_gate_navigation_state")
	return true


func take_damage(amount: float, attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(self, attacker)
	_health_component.take_damage(maxi(0, int(amount)))


func _convert_to_gate() -> void:
	var layout: Dictionary = _resolve_gate_layout()
	gate_axis = layout.get("axis", Vector3.RIGHT) as Vector3
	gate_span = int(layout.get("span", 1))

	var left_neighbor: WallSegment = layout.get("left_neighbor") as WallSegment
	var right_neighbor: WallSegment = layout.get("right_neighbor") as WallSegment
	_consume_gate_neighbor_segments(left_neighbor, right_neighbor)

	is_gate = true
	gate_open = false

	if _wall_placeholder != null:
		_wall_placeholder.visible = false

	if _gate_visuals != null:
		_gate_visuals.visible = true

	_reset_gate_collision_shapes()
	_ensure_gate_collision_shapes()
	_apply_gate_passage_blocking(true)
	_apply_gate_visual_state()
	apply_team_visuals()
	gate_state_changed.emit()
	call_deferred("_enforce_gate_navigation_state")


func _resolve_gate_layout() -> Dictionary:
	var axis: Vector3 = Vector3.RIGHT
	var left_neighbor: WallSegment = null
	var right_neighbor: WallSegment = null

	for test_axis: Vector3 in [Vector3.RIGHT, Vector3.FORWARD]:
		var negative_neighbor: WallSegment = _find_wall_segment_at(
			global_position - test_axis * EnemyBuildPlacement.GRID_SIZE
		)
		var positive_neighbor: WallSegment = _find_wall_segment_at(
			global_position + test_axis * EnemyBuildPlacement.GRID_SIZE
		)
		var negative_valid: bool = _can_consume_for_gate(negative_neighbor)
		var positive_valid: bool = _can_consume_for_gate(positive_neighbor)
		if not negative_valid and not positive_valid:
			continue

		axis = test_axis
		if negative_valid:
			left_neighbor = negative_neighbor
		if positive_valid:
			right_neighbor = positive_neighbor
		break

	var span: int = 1
	if left_neighbor != null and right_neighbor != null:
		span = 3
	elif left_neighbor != null or right_neighbor != null:
		span = 2

	return {
		"axis": axis,
		"span": span,
		"left_neighbor": left_neighbor,
		"right_neighbor": right_neighbor,
	}


func _can_consume_for_gate(segment: WallSegment) -> bool:
	if not NodeSafety.is_alive_node(segment):
		return false

	if segment == self or segment.is_gate:
		return false

	return _is_player_owned() and segment._is_player_owned()


func _consume_gate_neighbor_segments(
	left_neighbor: WallSegment, right_neighbor: WallSegment
) -> void:
	for neighbor: WallSegment in [left_neighbor, right_neighbor]:
		if neighbor == null or not NodeSafety.is_alive_node(neighbor):
			continue

		neighbor.destroy_building()
		neighbor.queue_free()


func _find_adjacent_wall_segments() -> Array[WallSegment]:
	var neighbors: Array[WallSegment] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return neighbors

	for axis_offset: Vector3 in [
		Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK
	]:
		var neighbor: WallSegment = _find_wall_segment_at(
			global_position + axis_offset * EnemyBuildPlacement.GRID_SIZE
		)
		if neighbor != null:
			neighbors.append(neighbor)

	return neighbors


func _find_wall_segment_at(world_position: Vector3) -> WallSegment:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	for node: Node in tree.get_nodes_in_group(&"buildings"):
		if not node is WallSegment or node == self:
			continue

		var segment: WallSegment = node as WallSegment
		var offset: Vector3 = segment.global_position - world_position
		offset.y = 0.0
		if offset.length_squared() <= 0.01:
			return segment

	return null


func _apply_gate_visual_state() -> void:
	if _gate_visuals != null:
		_gate_visuals.visible = is_gate

	if _wall_placeholder != null:
		_wall_placeholder.visible = not is_gate

	if _gate_panel != null:
		_gate_panel.visible = is_gate and not gate_open

	if not is_gate:
		return

	var post_offset: float = (
		GATE_WIDE_POST_OFFSET if gate_span >= 2 else GATE_POST_X_OFFSET
	)
	var post_position: Vector3 = gate_axis * post_offset

	if _gate_left_post_visual != null:
		_gate_left_post_visual.position = -post_position

	if _gate_right_post_visual != null:
		_gate_right_post_visual.position = post_position


func _apply_gate_passage_blocking(passage_blocked: bool) -> void:
	if not is_gate:
		if _collision_shape != null:
			_collision_shape.disabled = not passage_blocked
		_sync_wall_navigation_obstacle(passage_blocked)
		return

	_ensure_gate_collision_shapes()

	if _collision_shape != null:
		_collision_shape.disabled = true

	if _gate_passage_collision != null:
		_gate_passage_collision.disabled = not passage_blocked

	if _gate_left_post_collision != null:
		_gate_left_post_collision.disabled = false

	if _gate_right_post_collision != null:
		_gate_right_post_collision.disabled = false

	_sync_gate_navigation_obstacles(passage_blocked)


func _reset_gate_collision_shapes() -> void:
	for child: Node in get_children():
		if child is CollisionShape3D and child != _collision_shape:
			var shape_node: CollisionShape3D = child as CollisionShape3D
			if shape_node.name.begins_with("Gate"):
				shape_node.queue_free()

	_gate_left_post_collision = null
	_gate_right_post_collision = null
	_gate_passage_collision = null


func _ensure_gate_collision_shapes() -> void:
	if _collision_shape != null:
		_collision_shape.disabled = true

	if _gate_passage_collision != null:
		return

	var post_offset: float = (
		GATE_WIDE_POST_OFFSET if gate_span >= 2 else GATE_POST_X_OFFSET
	)
	var post_position: Vector3 = gate_axis * post_offset
	var passage_size: Vector3 = (
		GATE_WIDE_PASSAGE_SIZE if gate_span >= 2 else GATE_PASSAGE_SIZE
	)

	_gate_left_post_collision = _create_gate_box_collision(
		"GateLeftPostCollision",
		-post_position,
		GATE_POST_SIZE
	)
	_gate_right_post_collision = _create_gate_box_collision(
		"GateRightPostCollision",
		post_position,
		GATE_POST_SIZE
	)
	_gate_passage_collision = _create_gate_box_collision(
		"GatePassageCollision",
		Vector3.ZERO,
		passage_size
	)


func _create_gate_box_collision(
	node_name: String, position: Vector3, size: Vector3
) -> CollisionShape3D:
	var shape_node := CollisionShape3D.new()
	shape_node.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = position
	add_child(shape_node)
	return shape_node


func _sync_wall_navigation_obstacle(blocked: bool) -> void:
	if blocked:
		var obstacle: NavigationObstacle3D = (
			get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
		)
		if obstacle == null and _collision_shape != null and not _collision_shape.disabled:
			NavigationObstacleSetup.apply_from_collision_body(self)
		elif obstacle != null:
			obstacle.avoidance_enabled = true
			obstacle.carve_navigation_mesh = true
	else:
		_remove_navigation_obstacle()


func _sync_gate_navigation_obstacles(passage_blocked: bool) -> void:
	_remove_navigation_obstacle()
	_remove_gate_post_navigation_obstacles()

	if passage_blocked and _gate_passage_collision != null and not _gate_passage_collision.disabled:
		_add_navigation_obstacle_for_collision(_gate_passage_collision, &"NavigationObstacle3D")

	if _gate_left_post_collision != null and not _gate_left_post_collision.disabled:
		var left_obstacle: NavigationObstacle3D = _add_navigation_obstacle_for_collision(
			_gate_left_post_collision,
			&"GateLeftNavigationObstacle3D"
		)
		_gate_post_navigation_obstacles.append(left_obstacle)

	if _gate_right_post_collision != null and not _gate_right_post_collision.disabled:
		var right_obstacle: NavigationObstacle3D = _add_navigation_obstacle_for_collision(
			_gate_right_post_collision,
			&"GateRightNavigationObstacle3D"
		)
		_gate_post_navigation_obstacles.append(right_obstacle)


func _add_navigation_obstacle_for_collision(
	collision_shape: CollisionShape3D, obstacle_name: StringName
) -> NavigationObstacle3D:
	var obstacle := NavigationObstacle3D.new()
	obstacle.name = obstacle_name
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.avoidance_enabled = true
	obstacle.position = collision_shape.position

	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape != null:
		obstacle.radius = maxf(box_shape.size.x, box_shape.size.z) * 0.5
		obstacle.height = box_shape.size.y
	else:
		obstacle.radius = 0.25
		obstacle.height = GATE_PASSAGE_SIZE.y

	add_child(obstacle)
	return obstacle


func _remove_gate_post_navigation_obstacles() -> void:
	for obstacle: NavigationObstacle3D in _gate_post_navigation_obstacles:
		if obstacle != null and is_instance_valid(obstacle):
			obstacle.free()

	_gate_post_navigation_obstacles.clear()

	for child_name: StringName in [
		&"GateLeftNavigationObstacle3D",
		&"GateRightNavigationObstacle3D",
	]:
		var obstacle: NavigationObstacle3D = get_node_or_null(NodePath(str(child_name))) as NavigationObstacle3D
		if obstacle != null:
			obstacle.free()


func _remove_navigation_obstacle() -> void:
	var obstacle: NavigationObstacle3D = (
		get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
	)
	if obstacle != null:
		obstacle.free()


func _enforce_gate_navigation_state() -> void:
	if not is_gate or not is_inside_tree():
		return

	_remove_navigation_obstacle()
	_apply_gate_passage_blocking(not gate_open)


func _get_footprint_half_extents() -> Vector2:
	if is_gate and gate_span >= 2:
		if absf(gate_axis.x) > 0.5:
			return Vector2(
				EnemyBuildPlacement.GRID_SIZE * float(gate_span) * 0.5,
				EnemyBuildPlacement.GRID_SIZE * 0.5
			)

		return Vector2(
			EnemyBuildPlacement.GRID_SIZE * 0.5,
			EnemyBuildPlacement.GRID_SIZE * float(gate_span) * 0.5
		)

	return super._get_footprint_half_extents()


func _is_player_owned() -> bool:
	return TeamVisuals.resolve_team(self, team_id) == TeamVisuals.PLAYER_TEAM_ID


func _on_health_depleted() -> void:
	destroy_building()
	queue_free()
