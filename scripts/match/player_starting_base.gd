extends Node3D

## TEMPORARY DEVELOPMENT TEST SETUP — remove when cannon testing no longer needs instant Tier 3 + Artillery Depot.

const DEV_FAST_TEST_SETUP_ENABLED := true
const DEV_ARTILLERY_DEPOT_SCENE: PackedScene = preload("res://scenes/buildings/artillery_depot.tscn")
const DEV_ARTILLERY_DEPOT_POSITION := Vector3(-26.0, 1.0, -33.0)


func _ready() -> void:
	if not DEV_FAST_TEST_SETUP_ENABLED:
		return

	call_deferred("_apply_dev_fast_test_setup")


func _apply_dev_fast_test_setup() -> void:
	var command_center: CommandCenter = get_node_or_null("CommandCenter") as CommandCenter
	if command_center != null:
		command_center.apply_dev_starting_tier_3()

	_spawn_dev_artillery_depot()


func _spawn_dev_artillery_depot() -> void:
	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		return

	var depot: ArtilleryDepot = DEV_ARTILLERY_DEPOT_SCENE.instantiate() as ArtilleryDepot
	if depot == null:
		return

	spawn_parent.add_child(depot)
	depot.global_position = DEV_ARTILLERY_DEPOT_POSITION
	depot.set_completed()
