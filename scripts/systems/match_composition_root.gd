class_name MatchCompositionRoot
extends Node

## Match-owned composition root.
## Wires match systems. EnemyAI is the sole strategic enemy brain.

var enemy_ai: EnemyAI = null
var enemy_build_manager: EnemyBuildManager = null
var enemy_gather_manager: EnemyGatherManager = null
var selection_manager: Node = null
var build_manager: Node = null
var match_manager: Node = null


func _enter_tree() -> void:
	_resolve_systems()


func _ready() -> void:
	_resolve_systems()


static func find_from_tree(tree: SceneTree) -> MatchCompositionRoot:
	if tree == null:
		return null
	var root: Node = tree.root
	if root == null:
		return null
	return root.find_child("MatchSystems", true, false) as MatchCompositionRoot


func get_system(node_name: StringName) -> Node:
	return get_node_or_null(NodePath(String(node_name)))


func _resolve_systems() -> void:
	enemy_ai = get_node_or_null("EnemyAI") as EnemyAI
	enemy_build_manager = get_node_or_null("EnemyBuildManager") as EnemyBuildManager
	enemy_gather_manager = get_node_or_null("EnemyGatherManager") as EnemyGatherManager
	selection_manager = get_node_or_null("SelectionManager")
	build_manager = get_node_or_null("BuildManager")
	match_manager = get_node_or_null("MatchManager")
