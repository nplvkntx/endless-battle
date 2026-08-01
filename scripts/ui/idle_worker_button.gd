extends Button

## HUD idle-worker button: cycles idle player workers and centers the camera.

const HOTKEY_LABEL := "."

@export var selection_manager_path: NodePath = NodePath("")

var _selection_manager: Node = null
var _connected_workers: Dictionary = {}


func _ready() -> void:
	text = "Idle\n%s" % HOTKEY_LABEL
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(52, 52)
	disabled = true
	modulate = Color(0.55, 0.55, 0.58, 1.0)
	pressed.connect(_on_pressed)
	TooltipManager.bind_control(self, _tooltip_text)

	_resolve_selection_manager()
	_connect_existing_workers()
	var tree: SceneTree = get_tree()
	if tree != null:
		if not tree.node_added.is_connected(_on_tree_node_added):
			tree.node_added.connect(_on_tree_node_added)
	_refresh()


func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree != null and tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	_disconnect_all_workers()


func _on_pressed() -> void:
	_resolve_selection_manager()
	if _selection_manager == null:
		return
	if not _selection_manager.has_method("select_next_idle_worker_and_focus"):
		return
	_selection_manager.select_next_idle_worker_and_focus()
	_refresh()


func _tooltip_text() -> String:
	var count: int = _idle_count()
	if count <= 0:
		return "Idle Worker (%s)\nNo idle workers." % HOTKEY_LABEL
	return "Idle Worker (%s)\nSelect next idle worker and center camera.\nIdle: %d" % [
		HOTKEY_LABEL,
		count,
	]


func _refresh() -> void:
	var count: int = _idle_count()
	disabled = count <= 0
	modulate = Color(1, 1, 1, 1) if count > 0 else Color(0.55, 0.55, 0.58, 1.0)
	text = "Idle\n%d" % count if count > 0 else "Idle\n%s" % HOTKEY_LABEL


func _idle_count() -> int:
	_resolve_selection_manager()
	if _selection_manager != null and _selection_manager.has_method("count_idle_player_workers"):
		return int(_selection_manager.count_idle_player_workers())
	return 0


func _resolve_selection_manager() -> void:
	if _selection_manager != null and is_instance_valid(_selection_manager):
		return
	if not selection_manager_path.is_empty():
		_selection_manager = get_node_or_null(selection_manager_path)
	if _selection_manager != null:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var grouped: Array[Node] = tree.get_nodes_in_group(ControlGroupManager.SELECTION_MANAGER_GROUP)
	if not grouped.is_empty():
		_selection_manager = grouped[0]


func _connect_existing_workers() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(&"workers"):
		_try_connect_worker(node)


func _on_tree_node_added(node: Node) -> void:
	_try_connect_worker(node)


func _try_connect_worker(node: Node) -> void:
	if not node is Worker:
		return
	var worker: Worker = node as Worker
	if worker.is_in_group(&"enemy_workers") or worker.is_in_group(&"enemies"):
		return

	var id: int = worker.get_instance_id()
	if _connected_workers.has(id):
		return

	var on_idle: Callable = _on_worker_idle_status_changed
	var on_exit: Callable = _on_worker_tree_exiting.bind(id)
	worker.idle_status_changed.connect(on_idle)
	worker.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	_connected_workers[id] = {"idle": on_idle, "exit": on_exit}
	_refresh()


func _on_worker_idle_status_changed(_is_idle: bool) -> void:
	_refresh()


func _on_worker_tree_exiting(expected_instance_id: int) -> void:
	if not _connected_workers.has(expected_instance_id):
		return
	var handlers: Dictionary = _connected_workers[expected_instance_id]
	var idle_handler: Callable = handlers.get("idle", Callable())
	var worker_ref: Variant = instance_from_id(expected_instance_id)
	if (
		NodeSafety.is_alive_node(worker_ref)
		and worker_ref is Worker
		and idle_handler.is_valid()
		and (worker_ref as Worker).idle_status_changed.is_connected(idle_handler)
	):
		(worker_ref as Worker).idle_status_changed.disconnect(idle_handler)
	_connected_workers.erase(expected_instance_id)
	_refresh()


func _disconnect_all_workers() -> void:
	for id: Variant in _connected_workers.keys():
		var worker_obj: Object = instance_from_id(int(id))
		if worker_obj == null or not is_instance_valid(worker_obj):
			continue
		if not worker_obj is Worker:
			continue
		var worker: Worker = worker_obj as Worker
		var handlers: Dictionary = _connected_workers[id]
		var idle_handler: Callable = handlers.get("idle", Callable())
		if idle_handler.is_valid() and worker.idle_status_changed.is_connected(idle_handler):
			worker.idle_status_changed.disconnect(idle_handler)
	_connected_workers.clear()
