class_name AiTestCheckpoint
extends CanvasLayer

## Developer-only single-slot match checkpoint for SimpleWc3AI testing.
## Packs the live Main scene tree (units/buildings/creeps/AI nodes) — not a save-game system.

const SCENE_PATH := "user://ai_test_checkpoint.scn"
const META_PATH := "user://ai_test_checkpoint_meta.dat"
## Kept for verify / cleanup of the old single-file format.
const CHECKPOINT_PATH := META_PATH

## Filled by LOAD TEST; applied by the new checkpoint after change_scene_to_packed.
static var _pending_restore: Dictionary = {}

var _status_label: Label = null


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 90
	_build_buttons()
	if not _pending_restore.is_empty():
		call_deferred("_apply_pending_restore")


func save_checkpoint() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		_set_status("SAVE FAIL: no tree")
		return false

	var main: Node = tree.root.get_node_or_null("Main")
	if main == null:
		main = tree.current_scene
	if main == null:
		_set_status("SAVE FAIL: no Main")
		return false

	var packed := PackedScene.new()
	_assign_pack_owners(main, main)
	var pack_err: Error = packed.pack(main)
	if pack_err != OK:
		_set_status("SAVE FAIL: pack %d" % int(pack_err))
		return false

	var save_err: Error = ResourceSaver.save(packed, SCENE_PATH)
	if save_err != OK:
		_set_status("SAVE FAIL: scene %d" % int(save_err))
		return false

	var meta: Dictionary = {
		"player": _collect_resources(false),
		"enemy": _collect_resources(true),
		"ai": _collect_ai_state(tree),
	}
	var file := FileAccess.open(META_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("SAVE FAIL: meta open")
		return false
	file.store_var(meta)
	file.close()
	_set_status("SAVE TEST ok")
	print("AiTestCheckpoint: saved ", SCENE_PATH)
	return true


## PackedScene.pack only stores nodes whose owner is the packed root (or owned under it).
func _assign_pack_owners(node: Node, root_owner: Node) -> void:
	for child_variant: Variant in node.get_children():
		if not child_variant is Node:
			continue
		var child: Node = child_variant as Node
		child.owner = root_owner
		_assign_pack_owners(child, root_owner)

func load_checkpoint() -> bool:
	if not FileAccess.file_exists(SCENE_PATH) or not FileAccess.file_exists(META_PATH):
		_set_status("LOAD FAIL: no file")
		return false

	var file := FileAccess.open(META_PATH, FileAccess.READ)
	if file == null:
		_set_status("LOAD FAIL: meta open")
		return false
	var data: Variant = file.get_var()
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		_set_status("LOAD FAIL: bad meta")
		return false

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		_set_status("LOAD FAIL: no scene")
		return false

	var payload: Dictionary = data as Dictionary
	_pending_restore = {
		"player": payload.get("player", {}) as Dictionary,
		"enemy": payload.get("enemy", {}) as Dictionary,
		"ai": payload.get("ai", {}) as Dictionary,
	}

	PlayerRouteNavigation.clear_all()
	HeroProgressionStore.clear()
	CreepCampSafety.reset_match_state()
	EnemyArmyCommand.reset_match_state()

	var err: Error = get_tree().change_scene_to_packed(packed)
	if err != OK:
		_pending_restore.clear()
		_set_status("LOAD FAIL: change_scene %d" % int(err))
		return false

	_set_status("LOAD TEST…")
	print("AiTestCheckpoint: loading packed Main")
	return true


func _apply_pending_restore() -> void:
	var pending: Dictionary = _pending_restore.duplicate(true)
	_pending_restore.clear()
	if pending.is_empty():
		return

	var tree: SceneTree = get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame

	_restore_resources(pending.get("player", {}) as Dictionary, false)
	_restore_resources(pending.get("enemy", {}) as Dictionary, true)

	PlayerRouteNavigation.clear_all()
	PlayerRouteNavigation.ensure_grid_ready()
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if NodeSafety.is_alive_node(node_variant) and node_variant is Building:
			PlayerRouteNavigation.register_static_obstacle(node_variant as Building)

	var root: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	if root != null:
		root._ensure_simple_wc3_ai()
		root._declare_military_command_authority()
		root._bind_ai_runtime()

	var ai: SimpleWc3AI = _find_simple_ai(tree)
	if ai != null:
		ai.restore_test_checkpoint_state(pending.get("ai", {}) as Dictionary)
		ai.set_process(MilitaryAIConfig.is_simple_wc3_ai_enabled())

	_set_status("LOAD TEST ok")
	print("AiTestCheckpoint: loaded ", SCENE_PATH)


func _build_buttons() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.offset_left = -220.0
	root.offset_top = 12.0
	root.offset_right = -12.0
	root.offset_bottom = 110.0
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)

	var save_btn := Button.new()
	save_btn.text = "SAVE TEST"
	save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "LOAD TEST"
	load_btn.pressed.connect(_on_load_pressed)
	vbox.add_child(load_btn)

	_status_label = Label.new()
	_status_label.text = "checkpoint: -"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7, 1.0))
	vbox.add_child(_status_label)


func _on_save_pressed() -> void:
	save_checkpoint()


func _on_load_pressed() -> void:
	load_checkpoint()


func _set_status(text: String) -> void:
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = text


func _collect_resources(is_enemy: bool) -> Dictionary:
	if is_enemy:
		return {
			"gold": EnemyResourceManager.gold,
			"wood": EnemyResourceManager.wood,
			"food_current": EnemyResourceManager.food_current,
			"food_max": EnemyResourceManager.food_max,
		}
	return {
		"gold": ResourceManager.gold,
		"wood": ResourceManager.wood,
		"food_current": ResourceManager.food_current,
		"food_max": ResourceManager.food_max,
	}


func _restore_resources(data: Dictionary, is_enemy: bool) -> void:
	if data.is_empty():
		return
	if is_enemy:
		EnemyResourceManager.gold = int(data.get("gold", EnemyResourceManager.gold))
		EnemyResourceManager.wood = int(data.get("wood", EnemyResourceManager.wood))
		EnemyResourceManager.food_current = int(data.get("food_current", EnemyResourceManager.food_current))
		EnemyResourceManager.food_max = int(data.get("food_max", EnemyResourceManager.food_max))
		EnemyResourceManager.resources_changed.emit()
	else:
		ResourceManager.gold = int(data.get("gold", ResourceManager.gold))
		ResourceManager.wood = int(data.get("wood", ResourceManager.wood))
		ResourceManager.food_current = int(data.get("food_current", ResourceManager.food_current))
		ResourceManager.food_max = int(data.get("food_max", ResourceManager.food_max))
		ResourceManager.resources_changed.emit()


func _collect_ai_state(tree: SceneTree) -> Dictionary:
	var ai: SimpleWc3AI = _find_simple_ai(tree)
	if ai == null:
		return {}
	return ai.export_test_checkpoint_state()


func _find_simple_ai(tree: SceneTree) -> SimpleWc3AI:
	var root: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	if root != null and root.simple_wc3_ai != null:
		return root.simple_wc3_ai
	return tree.root.find_child("SimpleWc3AI", true, false) as SimpleWc3AI
