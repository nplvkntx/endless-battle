extends Node

## Verifies EntityHandle + EntityRegistry safety invariants.
## Godot --headless --path <project> res://scenes/debug/verify_entity_handles.tscn

const REPORT_PATH := "user://entity_handles_verify_result.txt"
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const SELECTION_MANAGER_SCRIPT: Script = preload("res://scripts/systems/selection_manager.gd")
const PLAYER_TEAM_ID: int = 0


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()
	if EntityRegistry != null:
		EntityRegistry.clear()

	await _verify_handle_resolve_and_clear(failures)
	await _verify_registry_unregister_on_death(failures)
	await _verify_selection_clears_on_unregister(failures)
	await _verify_selection_clears_on_tree_exit(failures)
	await _verify_hero_store_handle_separation(failures)
	_verify_mission_target_handle(failures)

	var report: String
	if failures.is_empty():
		report = "PASS entity_handles\n"
	else:
		report = "FAIL entity_handles\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_handle_resolve_and_clear(failures: PackedStringArray) -> void:
	var unit: Unit = SWORDSMAN_SCENE.instantiate() as Unit
	add_child(unit)
	unit.team_id = PLAYER_TEAM_ID
	await get_tree().process_frame

	var handle: EntityHandle = EntityHandle.from_node(unit)
	if handle.is_empty() or not handle.is_valid():
		failures.append("handle.from_node invalid for living unit")
	if handle.resolve() != unit:
		failures.append("handle.resolve mismatch for living unit")

	unit.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	if handle.resolve() != null:
		failures.append("handle.resolve returned freed unit")
	if handle.is_valid():
		failures.append("handle.is_valid true after free")


func _verify_registry_unregister_on_death(failures: PackedStringArray) -> void:
	var building: Building = FARM_SCENE.instantiate() as Building
	add_child(building)
	building.team_id = PLAYER_TEAM_ID
	building.building_state = Building.STATE_COMPLETED
	await get_tree().process_frame

	var instance_id: int = building.get_instance_id()
	if EntityRegistry == null or not EntityRegistry.is_registered(instance_id):
		failures.append("building not registered after enter tree")

	building.destroy_building()
	building.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	if EntityRegistry != null and EntityRegistry.is_registered(instance_id):
		failures.append("building still registered after destroy")
	if EntityRegistry != null and EntityRegistry.resolve_id(instance_id) != null:
		failures.append("registry resolve returned freed building")


func _verify_selection_clears_on_unregister(failures: PackedStringArray) -> void:
	var selection: Node = SELECTION_MANAGER_SCRIPT.new()
	add_child(selection)
	await get_tree().process_frame

	var building: Building = FARM_SCENE.instantiate() as Building
	add_child(building)
	building.team_id = PLAYER_TEAM_ID
	building.building_state = Building.STATE_COMPLETED
	await get_tree().process_frame

	selection.call("_set_selected_building", building)
	if selection.get("selected_building") != building:
		failures.append("selection did not set selected_building")

	building.destroy_building()
	building.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	if selection.get("selected_building") != null:
		failures.append("selection kept freed building")

	var handle: EntityHandle = selection.call("get_selected_building_handle") as EntityHandle
	if handle != null and not handle.is_empty() and handle.resolve() != null:
		failures.append("selection building handle still resolves after destroy")

	selection.queue_free()


func _verify_selection_clears_on_tree_exit(failures: PackedStringArray) -> void:
	var selection: Node = SELECTION_MANAGER_SCRIPT.new()
	add_child(selection)
	await get_tree().process_frame

	var building: Building = FARM_SCENE.instantiate() as Building
	add_child(building)
	building.team_id = PLAYER_TEAM_ID
	building.start_under_construction()
	building.setup_construction(10.0)
	await get_tree().process_frame

	selection.call("_set_selected_building", building)
	if selection.get("selected_building") != building:
		failures.append("selection did not track under-construction building")

	building.refund_and_cancel_construction()
	await get_tree().process_frame

	if selection.get("selected_building") != null:
		failures.append("selection kept building through tree exit cancel")

	var handle: EntityHandle = selection.call("get_selected_building_handle") as EntityHandle
	if handle != null and not handle.is_empty():
		failures.append("selection building handle not cleared on tree exit")

	selection.queue_free()


func _verify_hero_store_handle_separation(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	var locked: StringName = &"paladin"
	HeroProgressionStore.lock_kit(false, locked)
	if HeroProgressionStore.get_locked_kit_id(false) != locked:
		failures.append("chosen hero kit lock failed")
	if HeroProgressionStore.get_living_hero(false) != null:
		failures.append("living hero should be empty after clear")
	if not HeroProgressionStore.get_living_hero_handle(false).is_empty():
		failures.append("living hero handle should be empty after clear")


func _verify_mission_target_handle(failures: PackedStringArray) -> void:
	var mission := ArmyMissionV2.new()
	var building: Building = FARM_SCENE.instantiate() as Building
	add_child(building)
	building.team_id = CombatTargetValidation.ENEMY_TEAM_ID
	building.building_state = Building.STATE_COMPLETED

	mission.set_target_object(building)
	if mission.get_alive_target_object() != building:
		failures.append("mission target resolve failed")
	if mission.get_target_handle().is_empty():
		failures.append("mission target handle empty")

	building.destroy_building()
	building.queue_free()
	## Sync free without awaiting — sanitize must clear.
	mission.sanitize_target_object()
	if mission.get_alive_target_object() != null:
		failures.append("mission kept freed target")
	if not mission.get_target_handle().is_empty() and mission.get_target_handle().resolve() != null:
		failures.append("mission handle still resolves freed target")
