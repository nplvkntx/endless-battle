extends Node

## Spawns a test Hero near the Town Center when the scene starts without one.

const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const SPAWN_POSITION: Vector3 = Vector3(8.5, 0.5, -3)


func _ready() -> void:
	if _player_has_hero():
		return

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	var spawn_parent: Node = get_parent()
	if spawn_parent == null or hero == null:
		return

	spawn_parent.add_child(hero)
	hero.global_position = SPAWN_POSITION


func _player_has_hero() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"heroes"):
		if node is Hero and is_instance_valid(node):
			return true
	return false
