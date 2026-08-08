class_name SimpleWc3AI
extends Node

## Simple WC3 melee AI — sole runtime military authority when enabled.
## This bootstrap observes the enemy army and owns future military decisions.
## Current behavior: WAIT ONLY (no creep / attack / defend orders yet).

enum State { WAIT }

const TICK_SECONDS := 0.5
const ENEMY_COMBAT_GROUP := &"enemy_combat_units"
const AUTHORITY_LOG_INTERVAL_SECONDS := 8.0

var _state: State = State.WAIT
var _tick_timer: float = 0.0
var _authority_log_timer: float = AUTHORITY_LOG_INTERVAL_SECONDS
var _debug_label: Label = null
var _logged_authority_once: bool = false

var last_hero_alive: bool = false
var last_pikeman_count: int = 0
var last_army_count: int = 0
## Strategic military orders issued by this controller (must stay 0 while WAIT-only).
var strategic_orders_issued: int = 0


func _ready() -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return
	_ensure_debug_label()
	_observe_army()
	_update_debug_label()
	_log_authority_proof(true)
	set_process(true)


func get_state() -> State:
	return _state


func get_state_label() -> String:
	return "WAIT"


func _process(delta: float) -> void:
	if not MilitaryAIConfig.is_simple_wc3_ai_enabled():
		set_process(false)
		return

	_tick_timer += delta
	_authority_log_timer += delta
	if _tick_timer < TICK_SECONDS:
		return
	_tick_timer = 0.0

	## WAIT ONLY — observe army ownership; issue no strategic orders.
	_observe_army()
	_update_debug_label()
	if _authority_log_timer >= AUTHORITY_LOG_INTERVAL_SECONDS:
		_authority_log_timer = 0.0
		_log_authority_proof(false)


func _observe_army() -> void:
	var army: Array = _collect_main_army()
	last_army_count = army.size()
	var hero_alive: bool = false
	var pikemen: int = 0
	for unit_ref: Variant in army:
		if unit_ref is Hero:
			hero_alive = true
		elif unit_ref is Spearman:
			pikemen += 1
	last_hero_alive = hero_alive
	last_pikeman_count = pikemen


func _collect_main_army() -> Array:
	var tree: SceneTree = get_tree()
	if tree == null:
		last_hero_alive = false
		last_pikeman_count = 0
		last_army_count = 0
		return []

	var army: Array = []
	for node_variant: Variant in tree.get_nodes_in_group(ENEMY_COMBAT_GROUP):
		if not _is_living_enemy_unit(node_variant):
			continue
		var unit: Unit = node_variant as Unit
		if unit is Hero or unit is Spearman:
			army.append(unit)
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


func _log_authority_proof(force: bool) -> void:
	if _logged_authority_once and not force:
		## Low-frequency refresh after the first proof line.
		pass
	_logged_authority_once = true
	var old_active: bool = false
	var composition: MatchCompositionRoot = get_parent() as MatchCompositionRoot
	if composition != null:
		old_active = composition.is_old_military_runtime_active()
	print(
		"Simple WC3 AI active: YES | Old Military AI active: %s | Old military strategic orders issued: %d | Simple orders: %d | State: WAIT"
		% [
			"YES" if old_active else "NO",
			EnemyArmyCommand.get_legacy_military_strategic_orders_issued(),
			strategic_orders_issued,
		]
	)


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
		+ "State: WAIT\n"
		+ "Hero: %s\n" % ("YES" if last_hero_alive else "NO")
		+ "Pikemen: %d\n" % last_pikeman_count
		+ "Army: %d\n" % last_army_count
		+ "Old military: OFF\n"
		+ "Orders: 0 (WAIT ONLY)"
	)
