class_name SimpleWc3AI
extends Node

## Stage 1 Simple WC3 melee AI (experimental replacement path).
## WAIT for hero + 5 pikemen → CREEP one camp via custom RTS movement → DONE.
## Does not use MilitaryDirectorV2 / ArmyCommanderV2 / legacy military owners.

enum State { WAIT, CREEP, DONE }

const MIN_PIKEMEN := 5
const TICK_SECONDS := 0.5
const REISSUE_SECONDS := 2.0
const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const ENEMY_CC_GROUP := &"enemy_command_center"

var _state: State = State.WAIT
var _tick_timer: float = 0.0
var _reissue_timer: float = 0.0
var _camp_id: int = 0
var _camp_name: String = "-"
var _camp_destination: Vector3 = Vector3.ZERO
var _sent_unit_ids: Dictionary = {}
var _debug_label: Label = null

var last_move_handled: bool = false
var last_move_squad_size: int = 0
var last_hero_alive: bool = false
var last_pikeman_count: int = 0
var last_army_count: int = 0


func _ready() -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return
	_ensure_debug_label()
	_update_debug_label()
	set_process(true)


func get_state() -> State:
	return _state


func get_state_label() -> String:
	match _state:
		State.WAIT:
			return "WAIT"
		State.CREEP:
			return "CREEP"
		State.DONE:
			return "DONE"
	return "?"


func get_camp_name() -> String:
	return _camp_name


func get_camp_destination() -> Vector3:
	return _camp_destination


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return

	_tick_timer += delta
	if _tick_timer < TICK_SECONDS:
		return
	_tick_timer = 0.0

	match _state:
		State.WAIT:
			_tick_wait()
		State.CREEP:
			_tick_creep(delta)
		State.DONE:
			pass

	_update_debug_label()


func _tick_wait() -> void:
	var army: Array = _collect_main_army()
	if not _has_minimum_force(army):
		return

	var camp: Node3D = _select_creep_camp(army)
	if camp == null:
		return

	_camp_id = camp.get_instance_id()
	_camp_name = String(camp.name)
	_camp_destination = Vector3(camp.global_position.x, 0.0, camp.global_position.z)
	_sent_unit_ids.clear()
	_state = State.CREEP
	_issue_army_to_camp(army)
	_reissue_timer = 0.0


func _tick_creep(_delta_accum: float) -> void:
	var camp: Node3D = _resolve_camp()
	if camp == null or not _camp_has_living_creeps(camp):
		_state = State.DONE
		return

	var army: Array = _collect_main_army()
	if army.is_empty():
		return

	## New pikemen / hero: send toward the same camp immediately.
	var newcomers: Array = []
	for unit_ref: Variant in army:
		var unit: Unit = unit_ref as Unit
		var id: int = unit.get_instance_id()
		if not _sent_unit_ids.has(id):
			newcomers.append(unit)
	if not newcomers.is_empty():
		_issue_army_to_camp(newcomers)

	_reissue_timer += TICK_SECONDS
	if _reissue_timer >= REISSUE_SECONDS:
		_reissue_timer = 0.0
		_issue_army_to_camp(army)


func _has_minimum_force(army: Array) -> bool:
	var hero_alive: bool = false
	var pikemen: int = 0
	for unit_ref: Variant in army:
		if unit_ref is Hero:
			hero_alive = true
		elif unit_ref is Spearman:
			pikemen += 1
	last_hero_alive = hero_alive
	last_pikeman_count = pikemen
	last_army_count = army.size()
	return hero_alive and pikemen >= MIN_PIKEMEN


func _collect_main_army() -> Array:
	var tree: SceneTree = get_tree()
	if tree == null:
		last_hero_alive = false
		last_pikeman_count = 0
		last_army_count = 0
		return []

	var army: Array = []
	var hero_alive: bool = false
	var pikemen: int = 0
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if not _is_living_enemy_unit(node_variant):
			continue
		var unit: Unit = node_variant as Unit
		if unit is Hero:
			army.append(unit)
			hero_alive = true
		elif unit is Spearman:
			army.append(unit)
			pikemen += 1

	last_hero_alive = hero_alive
	last_pikeman_count = pikemen
	last_army_count = army.size()
	return army


func _is_living_enemy_unit(node_variant: Variant) -> bool:
	if not NodeSafety.is_alive_node(node_variant):
		return false
	if not node_variant is Unit:
		return false
	var unit: Unit = node_variant as Unit
	if not unit.is_inside_tree():
		return false
	if not CombatTargetValidation.is_enemy_faction(unit):
		return false
	var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.current_health <= 0:
		return false
	return true


func _select_creep_camp(army: Array) -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	var origin: Vector3 = _army_centroid(army)
	if origin == Vector3.ZERO:
		origin = _enemy_base_position(tree)
	if origin == Vector3.ZERO:
		return null

	var active_camps: Array[Node3D] = CreepCampSafety.collect_active_camps(tree)
	if active_camps.is_empty():
		return null

	## Prefer Medium* early camps when available; otherwise nearest active camp.
	var preferred: Array[Node3D] = []
	for camp: Node3D in active_camps:
		if camp == null or not is_instance_valid(camp):
			continue
		var camp_name: String = String(camp.name)
		if camp_name.begins_with("Medium") or camp_name.contains("Medium"):
			preferred.append(camp)

	var pool: Array[Node3D] = preferred if not preferred.is_empty() else active_camps
	var best: Node3D = null
	var best_dist: float = INF
	for camp: Node3D in pool:
		if camp == null or not is_instance_valid(camp):
			continue
		var dist: float = _horizontal_distance(origin, camp.global_position)
		if dist < best_dist:
			best_dist = dist
			best = camp
	return best


func _resolve_camp() -> Node3D:
	if _camp_id == 0:
		return null
	var obj: Object = instance_from_id(_camp_id)
	if obj == null or not is_instance_valid(obj) or not obj is Node3D:
		return null
	return obj as Node3D


func _camp_has_living_creeps(camp: Node3D) -> bool:
	if camp == null or not is_instance_valid(camp):
		return false
	for child_variant: Variant in camp.get_children():
		if not NodeSafety.is_alive_node(child_variant):
			continue
		if not child_variant is NeutralCreep:
			continue
		var creep: NeutralCreep = child_variant as NeutralCreep
		var health: HealthComponent = creep.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.current_health > 0:
			return true
	return false


func _issue_army_to_camp(units: Array) -> void:
	if units.is_empty() or _camp_destination == Vector3.ZERO:
		return
	if not PlayerRouteNavigation.is_custom_rts_movement_enabled():
		last_move_handled = false
		return

	var result: Dictionary = PlayerRouteNavigation.issue_player_group_command(
		units,
		_camp_destination,
		&"attack_move",
		false,
		&"simple_wc3_ai"
	)
	last_move_handled = bool(result.get("handled", false))
	last_move_squad_size = int(result.get("squad_size", 0))
	if last_move_handled:
		for unit_ref: Variant in units:
			if NodeSafety.is_alive_node(unit_ref) and unit_ref is Unit:
				_sent_unit_ids[(unit_ref as Unit).get_instance_id()] = true


func _army_centroid(army: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for unit_ref: Variant in army:
		if not NodeSafety.is_alive_node(unit_ref):
			continue
		sum += (unit_ref as Unit).global_position
		count += 1
	if count <= 0:
		return Vector3.ZERO
	var c: Vector3 = sum / float(count)
	c.y = 0.0
	return c


func _enemy_base_position(tree: SceneTree) -> Vector3:
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_CC_GROUP):
		if not NodeSafety.is_alive_node(node_variant):
			continue
		if node_variant is Node3D:
			var pos: Vector3 = (node_variant as Node3D).global_position
			pos.y = 0.0
			return pos
	return Vector3.ZERO


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _ensure_debug_label() -> void:
	if _debug_label != null and is_instance_valid(_debug_label):
		return
	var layer := CanvasLayer.new()
	layer.name = "SimpleWc3AIDebugLayer"
	layer.layer = 80
	add_child(layer)
	_debug_label = Label.new()
	_debug_label.name = "SimpleWc3AIDebug"
	_debug_label.position = Vector2(12, 120)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.55, 1.0))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_debug_label)


func _update_debug_label() -> void:
	if _debug_label == null or not is_instance_valid(_debug_label):
		return
	_debug_label.text = (
		"WC3 SIMPLE AI\n"
		+ "State: %s\n" % get_state_label()
		+ "Hero: %s\n" % ("YES" if last_hero_alive else "NO")
		+ "Pikemen: %d\n" % last_pikeman_count
		+ "Army: %d\n" % last_army_count
		+ "Target: %s\n" % _camp_name
		+ "Movement: CUSTOM"
	)
