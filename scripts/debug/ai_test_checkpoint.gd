class_name AiTestCheckpoint
extends CanvasLayer

## Developer-only single-slot match checkpoint for SimpleWc3AI testing.
## Not a save-game system — two buttons, one user:// file.

const CHECKPOINT_PATH := "user://ai_test_checkpoint.dat"
const CREEP_SCENE: PackedScene = preload("res://scenes/units/neutral_creep.tscn")

var _status_label: Label = null


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 90
	_build_buttons()


func save_checkpoint() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		_set_status("SAVE FAIL: no tree")
		return false

	var data: Dictionary = {
		"player": _collect_resources(false),
		"enemy": _collect_resources(true),
		"buildings": _collect_buildings(tree),
		"units": _collect_units(tree),
		"creeps": _collect_creeps(tree),
		"ai": _collect_ai_state(tree),
	}

	var file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("SAVE FAIL: open")
		return false
	file.store_var(data)
	file.close()
	_set_status("SAVE TEST ok")
	print("AiTestCheckpoint: saved ", CHECKPOINT_PATH)
	return true


func load_checkpoint() -> bool:
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		_set_status("LOAD FAIL: no file")
		return false

	var file := FileAccess.open(CHECKPOINT_PATH, FileAccess.READ)
	if file == null:
		_set_status("LOAD FAIL: open")
		return false
	var data: Variant = file.get_var()
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		_set_status("LOAD FAIL: bad data")
		return false

	var tree: SceneTree = get_tree()
	if tree == null:
		_set_status("LOAD FAIL: no tree")
		return false

	var payload: Dictionary = data as Dictionary
	_clear_dynamic_entities(tree)
	await tree.process_frame
	await tree.process_frame

	_restore_buildings(tree, payload.get("buildings", []) as Array)
	_restore_units(tree, payload.get("units", []) as Array)
	_restore_creeps(tree, payload.get("creeps", []) as Array)
	_restore_resources(payload.get("player", {}) as Dictionary, false)
	_restore_resources(payload.get("enemy", {}) as Dictionary, true)

	PlayerRouteNavigation.clear_all()
	await tree.process_frame

	_restore_ai_state(tree, payload.get("ai", {}) as Dictionary)
	_ensure_simple_ai_authority(tree)

	_set_status("LOAD TEST ok")
	print("AiTestCheckpoint: loaded ", CHECKPOINT_PATH)
	return true


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
	await load_checkpoint()


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


func _collect_buildings(tree: SceneTree) -> Array:
	var out: Array = []
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Building:
			continue
		var building: Building = node_variant as Building
		var path: String = building.scene_file_path
		if path.is_empty():
			continue
		var health: HealthComponent = building.get_node_or_null("HealthComponent") as HealthComponent
		out.append({
			"scene": path,
			"name": String(building.name),
			"pos": building.global_position,
			"team_id": building.team_id,
			"state": String(building.building_state),
			"hp": health.current_health if health != null else -1,
			"max_hp": health.max_health if health != null else -1,
			"enemy_group": building.is_in_group(&"enemy_command_center"),
			"player_group": building.is_in_group(&"player_command_center"),
			"keep": _is_starting_command_center(building),
		})
	return out


func _collect_units(tree: SceneTree) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for group_name: StringName in [&"units", &"enemies", &"enemy_combat_units", &"workers", &"enemy_workers", &"heroes"]:
		for node_variant: Variant in tree.get_nodes_in_group(group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Unit:
				continue
			var unit: Unit = node_variant as Unit
			var id: int = unit.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			var path: String = unit.scene_file_path
			if path.is_empty():
				continue
			var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
			var entry: Dictionary = {
				"scene": path,
				"name": String(unit.name),
				"pos": unit.global_position,
				"team_id": unit.team_id,
				"hp": health.current_health if health != null else -1,
				"max_hp": health.max_health if health != null else -1,
				"is_hero": unit is Hero,
				"is_worker": unit is Worker,
				"enemy": CombatTargetValidation.is_enemy_faction(unit),
			}
			if unit is Hero:
				entry["progression"] = (unit as Hero).export_progression_snapshot()
			out.append(entry)
	return out


func _collect_creeps(tree: SceneTree) -> Array:
	var out: Array = []
	for node_variant: Variant in tree.get_nodes_in_group(&"creep_camps"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Node3D:
			continue
		var camp: Node3D = node_variant as Node3D
		var creeps: Array = []
		for child_variant: Variant in camp.get_children():
			if not NodeSafety.is_alive_node(child_variant):
				continue
			if not child_variant is NeutralCreep:
				continue
			var creep: NeutralCreep = child_variant as NeutralCreep
			var health: HealthComponent = creep.get_node_or_null("HealthComponent") as HealthComponent
			creeps.append({
				"pos": creep.global_position,
				"hp": health.current_health if health != null else -1,
				"max_hp": health.max_health if health != null else -1,
				"alive": health == null or health.current_health > 0,
			})
		out.append({
			"camp_name": String(camp.name),
			"creeps": creeps,
		})
	return out


func _collect_ai_state(tree: SceneTree) -> Dictionary:
	var ai: SimpleWc3AI = _find_simple_ai(tree)
	if ai == null:
		return {}
	return ai.export_test_checkpoint_state()


func _clear_dynamic_entities(tree: SceneTree) -> void:
	## Free units / workers / heroes — will be recreated from checkpoint.
	var to_free: Array[Node] = []
	var seen: Dictionary = {}
	for group_name: StringName in [&"units", &"enemies", &"enemy_combat_units", &"workers", &"enemy_workers", &"heroes"]:
		for node_variant: Variant in tree.get_nodes_in_group(group_name):
			if not NodeSafety.is_alive_node(node_variant):
				continue
			if not node_variant is Node:
				continue
			var node: Node = node_variant as Node
			var id: int = node.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			to_free.append(node)

	## Free non-starting buildings.
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Building:
			continue
		var building: Building = node_variant as Building
		if _is_starting_command_center(building):
			continue
		var id2: int = building.get_instance_id()
		if seen.has(id2):
			continue
		seen[id2] = true
		to_free.append(building)

	## Free living creeps (camps stay).
	for node_variant: Variant in tree.get_nodes_in_group(&"neutral_creeps"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		var id3: int = (node_variant as Node).get_instance_id()
		if seen.has(id3):
			continue
		seen[id3] = true
		to_free.append(node_variant as Node)

	for node: Node in to_free:
		if is_instance_valid(node):
			node.queue_free()

	HeroProgressionStore.clear()
	PlayerRouteNavigation.clear_all()


func _restore_buildings(tree: SceneTree, buildings: Array) -> void:
	var parent: Node = _resolve_spawn_parent(tree)
	if parent == null:
		return

	for entry_ref: Variant in buildings:
		if typeof(entry_ref) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_ref as Dictionary
		var keep: bool = bool(entry.get("keep", false))
		if keep:
			_update_starting_command_center(tree, entry)
			continue

		var scene_path: String = String(entry.get("scene", ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			continue
		var building: Building = packed.instantiate() as Building
		if building == null:
			continue
		building.name = String(entry.get("name", building.name))
		building.team_id = int(entry.get("team_id", building.team_id))
		parent.add_child(building)
		building.global_position = entry.get("pos", Vector3.ZERO) as Vector3
		if bool(entry.get("enemy_group", false)):
			if building.is_in_group(&"player_command_center"):
				building.remove_from_group(&"player_command_center")
			if not building.is_in_group(&"enemy_command_center"):
				building.add_to_group(&"enemy_command_center")
		if bool(entry.get("player_group", false)):
			if not building.is_in_group(&"player_command_center"):
				building.add_to_group(&"player_command_center")
		if not building.is_in_group(&"buildings"):
			building.add_to_group(&"buildings")
		var state_name: String = String(entry.get("state", "completed"))
		if state_name == String(Building.STATE_COMPLETED) or state_name.is_empty():
			building.set_completed()
		building.apply_team_visuals()
		_apply_health(building.get_node_or_null("HealthComponent") as HealthComponent, entry)
		PlayerRouteNavigation.register_static_obstacle(building)


func _update_starting_command_center(tree: SceneTree, entry: Dictionary) -> void:
	var enemy: bool = bool(entry.get("enemy_group", false))
	for node_variant: Variant in tree.get_nodes_in_group(&"buildings"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is CommandCenter:
			continue
		var cc: CommandCenter = node_variant as CommandCenter
		if not _is_starting_command_center(cc):
			continue
		if enemy and not cc.is_in_group(&"enemy_command_center"):
			continue
		if not enemy and not cc.is_in_group(&"player_command_center"):
			continue
		cc.global_position = entry.get("pos", cc.global_position) as Vector3
		_apply_health(cc.get_node_or_null("HealthComponent") as HealthComponent, entry)
		PlayerRouteNavigation.register_static_obstacle(cc)
		return


func _restore_units(tree: SceneTree, units: Array) -> void:
	var parent: Node = _resolve_spawn_parent(tree)
	if parent == null:
		return

	for entry_ref: Variant in units:
		if typeof(entry_ref) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_ref as Dictionary
		var scene_path: String = String(entry.get("scene", ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			continue
		var unit: Unit = packed.instantiate() as Unit
		if unit == null:
			continue
		unit.name = String(entry.get("name", unit.name))
		unit.team_id = int(entry.get("team_id", unit.team_id))
		parent.add_child(unit)
		unit.global_position = entry.get("pos", Vector3.ZERO) as Vector3

		var is_enemy: bool = bool(entry.get("enemy", false))
		if is_enemy:
			if unit.is_in_group(&"units"):
				unit.remove_from_group(&"units")
			if not unit.is_in_group(&"enemies"):
				unit.add_to_group(&"enemies")
			if unit is Worker:
				if unit.is_in_group(&"workers"):
					unit.remove_from_group(&"workers")
				if not unit.is_in_group(&"enemy_workers"):
					unit.add_to_group(&"enemy_workers")
			elif not (unit is Worker):
				EnemyArmyCommand.register_combat_unit(unit)
		else:
			if not unit.is_in_group(&"units"):
				unit.add_to_group(&"units")
			if unit is Hero and not unit.is_in_group(&"heroes"):
				unit.add_to_group(&"heroes")
			if unit is Worker and not unit.is_in_group(&"workers"):
				unit.add_to_group(&"workers")

		unit.apply_team_visuals()
		if unit is Hero:
			var progression: Variant = entry.get("progression", {})
			if typeof(progression) == TYPE_DICTIONARY:
				(unit as Hero).restore_progression_snapshot(progression as Dictionary)
			HeroProgressionStore.register_living_hero(unit as Hero)
		_apply_health(unit.get_node_or_null("HealthComponent") as HealthComponent, entry)


func _restore_creeps(tree: SceneTree, camps_data: Array) -> void:
	var camps_by_name: Dictionary = {}
	for node_variant: Variant in tree.get_nodes_in_group(&"creep_camps"):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if not node_variant is Node3D:
			continue
		camps_by_name[String((node_variant as Node3D).name)] = node_variant

	for entry_ref: Variant in camps_data:
		if typeof(entry_ref) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_ref as Dictionary
		var camp_name: String = String(entry.get("camp_name", ""))
		if not camps_by_name.has(camp_name):
			continue
		var camp: Node3D = camps_by_name[camp_name] as Node3D
		var creeps: Array = entry.get("creeps", []) as Array
		for creep_ref: Variant in creeps:
			if typeof(creep_ref) != TYPE_DICTIONARY:
				continue
			var creep_entry: Dictionary = creep_ref as Dictionary
			if not bool(creep_entry.get("alive", true)):
				continue
			var creep: NeutralCreep = CREEP_SCENE.instantiate() as NeutralCreep
			if creep == null:
				continue
			camp.add_child(creep)
			creep.global_position = creep_entry.get("pos", camp.global_position) as Vector3
			if not creep.is_in_group(&"neutral_creeps"):
				creep.add_to_group(&"neutral_creeps")
			_apply_health(creep.get_node_or_null("HealthComponent") as HealthComponent, creep_entry)

	CreepCampSafety.reset_match_state()


func _restore_ai_state(tree: SceneTree, data: Dictionary) -> void:
	var ai: SimpleWc3AI = _find_simple_ai(tree)
	if ai == null:
		return
	ai.restore_test_checkpoint_state(data)


func _ensure_simple_ai_authority(tree: SceneTree) -> void:
	var root: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	if root == null:
		return
	## Re-declare SimpleWc3AI only — never revive deleted military systems.
	if root.get_node_or_null("MilitaryDirectorV2") != null:
		root.get_node_or_null("MilitaryDirectorV2").queue_free()
	if root.get_node_or_null("EnemyStrategicDirector") != null:
		root.get_node_or_null("EnemyStrategicDirector").queue_free()
	if root.get_node_or_null("EnemyWaveManager") != null:
		root.get_node_or_null("EnemyWaveManager").queue_free()
	if root.get_node_or_null("EnemyCreepManager") != null:
		root.get_node_or_null("EnemyCreepManager").queue_free()
	root._ensure_simple_wc3_ai()
	root._declare_military_command_authority()
	root._bind_ai_runtime()
	var ai: SimpleWc3AI = root.simple_wc3_ai
	if ai != null and is_instance_valid(ai):
		ai.set_process(MilitaryAIConfig.is_simple_wc3_ai_enabled())


func _find_simple_ai(tree: SceneTree) -> SimpleWc3AI:
	var root: MatchCompositionRoot = MatchCompositionRoot.find_from_tree(tree)
	if root != null and root.simple_wc3_ai != null:
		return root.simple_wc3_ai
	return tree.root.find_child("SimpleWc3AI", true, false) as SimpleWc3AI


func _resolve_spawn_parent(tree: SceneTree) -> Node:
	var main: Node = tree.root.get_node_or_null("Main")
	if main != null:
		return main
	return tree.current_scene


func _is_starting_command_center(building: Building) -> bool:
	if building == null or not (building is CommandCenter):
		return false
	var parent: Node = building.get_parent()
	if parent == null:
		return false
	var parent_name: String = String(parent.name)
	return parent_name.contains("StartingBase")


func _apply_health(health: HealthComponent, entry: Dictionary) -> void:
	if health == null:
		return
	var max_hp: int = int(entry.get("max_hp", -1))
	var hp: int = int(entry.get("hp", -1))
	if max_hp > 0:
		health.max_health = max_hp
	if hp >= 0:
		health.current_health = mini(health.max_health, hp)
		health.health_changed.emit(health.current_health, health.max_health)
