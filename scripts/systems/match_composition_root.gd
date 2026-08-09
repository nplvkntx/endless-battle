class_name MatchCompositionRoot
extends Node

## Match-owned composition root.
## Declares SimpleWc3AI as the sole enemy decision / military command authority.

const AI_PLAYER_STATE_NAME := &"AIPlayerState"

var ai_player_state: AIPlayerState = null
var simple_wc3_ai: SimpleWc3AI = null
var enemy_build_manager: EnemyBuildManager = null
var enemy_gather_manager: EnemyGatherManager = null
var selection_manager: Node = null
var build_manager: Node = null
var match_manager: Node = null

## Sole node allowed to own enemy strategic decisions for this match.
var military_command_authority: Variant = null


func _enter_tree() -> void:
	_ensure_ai_player_state()
	_resolve_systems()
	_declare_military_command_authority()


func _ready() -> void:
	_resolve_systems()
	_ensure_simple_wc3_ai()
	_declare_military_command_authority()
	_bind_ai_runtime()


func _exit_tree() -> void:
	EnemyArmyCommand.unbind_match_composition()
	ai_player_state = null
	military_command_authority = null


static func find_from_tree(tree: SceneTree) -> MatchCompositionRoot:
	if tree == null:
		return null
	var root: Node = tree.root
	if root == null:
		return null
	return root.find_child("MatchSystems", true, false) as MatchCompositionRoot


func get_ai_player_state() -> AIPlayerState:
	return ai_player_state


func get_military_command_authority() -> Node:
	var raw: Variant = military_command_authority
	if raw != null and is_instance_valid(raw) and raw is Node:
		return raw as Node
	military_command_authority = null
	return null


func get_system(node_name: StringName) -> Node:
	return get_node_or_null(NodePath(String(node_name)))


func is_v2_military_active() -> bool:
	return false


func is_old_military_runtime_active() -> bool:
	return false


func _ensure_simple_wc3_ai() -> void:
	if simple_wc3_ai != null and is_instance_valid(simple_wc3_ai):
		return
	simple_wc3_ai = get_node_or_null("SimpleWc3AI") as SimpleWc3AI
	if simple_wc3_ai != null:
		return
	simple_wc3_ai = SimpleWc3AI.new()
	simple_wc3_ai.name = "SimpleWc3AI"
	add_child(simple_wc3_ai)


func _ensure_ai_player_state() -> void:
	var existing: Node = get_node_or_null(NodePath(String(AI_PLAYER_STATE_NAME)))
	if existing is AIPlayerState:
		ai_player_state = existing as AIPlayerState
		return

	ai_player_state = AIPlayerState.new()
	ai_player_state.name = String(AI_PLAYER_STATE_NAME)
	add_child(ai_player_state)
	move_child(ai_player_state, 0)


func _resolve_systems() -> void:
	simple_wc3_ai = get_node_or_null("SimpleWc3AI") as SimpleWc3AI
	enemy_build_manager = get_node_or_null("EnemyBuildManager") as EnemyBuildManager
	enemy_gather_manager = get_node_or_null("EnemyGatherManager") as EnemyGatherManager
	selection_manager = get_node_or_null("SelectionManager")
	build_manager = get_node_or_null("BuildManager")
	match_manager = get_node_or_null("MatchManager")


func _declare_military_command_authority() -> void:
	military_command_authority = simple_wc3_ai
	if ai_player_state != null:
		ai_player_state.set_military_command_authority(military_command_authority)


func _bind_ai_runtime() -> void:
	if ai_player_state == null:
		push_warning("MatchCompositionRoot: AIPlayerState missing; AI identity stays static")
		return
	EnemyArmyCommand.bind_match_composition(ai_player_state, military_command_authority)
