class_name MatchCompositionRoot
extends Node

## Match-owned composition root (PHASE 2 audit item 1).
## Owns AIPlayerState, resolves match systems once, and declares the sole
## military command authority for this match. Scene lifetime replaces static
## ownership for identity / exec / combat mirrors; EnemyArmyCommand remains a
## helper facade. Wave/creep/defense publish MilitaryIntent onto AIPlayerState.

const AI_PLAYER_STATE_NAME := &"AIPlayerState"

var ai_player_state: AIPlayerState = null
var military_director_v2: MilitaryDirectorV2 = null
var army_commander_v2: ArmyCommanderV2 = null
var enemy_combat_controller: EnemyCombatController = null
var enemy_strategic_director: EnemyStrategicDirector = null
var enemy_creep_manager: EnemyCreepManager = null
var enemy_wave_manager: EnemyWaveManager = null
var enemy_defense_manager: EnemyDefenseManager = null
var enemy_build_manager: EnemyBuildManager = null
var enemy_gather_manager: EnemyGatherManager = null
var simple_wc3_ai: SimpleWc3AI = null
var selection_manager: Node = null
var build_manager: Node = null
var match_manager: Node = null

## Sole node allowed to own main-army order issuance for this match.
## Variant so freed authority can be read before validation (typed Node getters cast first).
var military_command_authority: Variant = null


func _enter_tree() -> void:
	_ensure_ai_player_state()
	_resolve_systems()
	_declare_military_command_authority()


func _ready() -> void:
	## Bind after children have entered so authority nodes are fully constructed.
	_resolve_systems()
	if _uses_simple_wc3_ai():
		_disable_old_military_runtime()
	_declare_military_command_authority()
	_bind_ai_runtime()
	## Children may re-enable process in their own _ready; force-disable after.
	if _uses_simple_wc3_ai():
		call_deferred("_disable_old_military_runtime")


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
	if _uses_simple_wc3_ai():
		return false
	return MilitaryAIConfig.is_v2_enabled() and army_commander_v2 != null


func _uses_simple_wc3_ai() -> bool:
	return (
		MilitaryAIConfig.is_simple_wc3_ai_enabled()
		and simple_wc3_ai != null
	)


func _disable_old_military_runtime() -> void:
	## Prevent old military controllers from commanding units.
	## Keep nodes in the scene (wiring / economy helpers) but stop their process.
	## Intent publishers stay off too so nothing queues military work for a dead V2 consumer.
	const OLD_MILITARY_NODES: Array[StringName] = [
		&"MilitaryDirectorV2",
		&"ArmyCommanderV2",
		&"EnemyCombatController",
		&"EnemyCreepManager",
		&"EnemyWaveManager",
		&"EnemyDefenseManager",
	]
	for node_name: StringName in OLD_MILITARY_NODES:
		var node: Node = get_node_or_null(NodePath(String(node_name)))
		if node == null:
			continue
		node.set_process(false)
		node.set_physics_process(false)


func _ensure_ai_player_state() -> void:
	var existing: Node = get_node_or_null(NodePath(String(AI_PLAYER_STATE_NAME)))
	if existing is AIPlayerState:
		ai_player_state = existing as AIPlayerState
		return

	ai_player_state = AIPlayerState.new()
	ai_player_state.name = String(AI_PLAYER_STATE_NAME)
	add_child(ai_player_state)
	## Keep identity state first among siblings for stable tree order in tools.
	move_child(ai_player_state, 0)


func _resolve_systems() -> void:
	military_director_v2 = get_node_or_null("MilitaryDirectorV2") as MilitaryDirectorV2
	army_commander_v2 = get_node_or_null("ArmyCommanderV2") as ArmyCommanderV2
	enemy_combat_controller = get_node_or_null("EnemyCombatController") as EnemyCombatController
	enemy_strategic_director = get_node_or_null("EnemyStrategicDirector") as EnemyStrategicDirector
	enemy_creep_manager = get_node_or_null("EnemyCreepManager") as EnemyCreepManager
	enemy_wave_manager = get_node_or_null("EnemyWaveManager") as EnemyWaveManager
	enemy_defense_manager = get_node_or_null("EnemyDefenseManager") as EnemyDefenseManager
	enemy_build_manager = get_node_or_null("EnemyBuildManager") as EnemyBuildManager
	enemy_gather_manager = get_node_or_null("EnemyGatherManager") as EnemyGatherManager
	simple_wc3_ai = get_node_or_null("SimpleWc3AI") as SimpleWc3AI
	selection_manager = get_node_or_null("SelectionManager")
	build_manager = get_node_or_null("BuildManager")
	match_manager = get_node_or_null("MatchManager")


func _declare_military_command_authority() -> void:
	## PHASE 2 item 3: exactly one main-army order issuer per match.
	if _uses_simple_wc3_ai():
		military_command_authority = simple_wc3_ai
	elif MilitaryAIConfig.is_v2_enabled():
		military_command_authority = army_commander_v2
	else:
		military_command_authority = enemy_combat_controller

	if ai_player_state != null:
		ai_player_state.set_military_command_authority(military_command_authority)


func _bind_ai_runtime() -> void:
	if ai_player_state == null:
		push_warning("MatchCompositionRoot: AIPlayerState missing; AI identity stays static")
		return
	EnemyArmyCommand.bind_match_composition(ai_player_state, military_command_authority)
