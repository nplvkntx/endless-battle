class_name WoodTree
extends GatherableResource

## Tree resource node with a finite wood supply.

@export var wood_amount: int = GatheringConfig.TREE_STARTING_WOOD

var _assigned_worker_count: int = 0


func _ready() -> void:
	super._ready()
	_activate_tree_variant()


func _activate_tree_variant() -> void:
	var visuals: Node3D = get_node_or_null("Visuals") as Node3D
	if visuals == null:
		return

	var variants: Array[Node] = []
	for child: Node in visuals.get_children():
		variants.append(child)

	if variants.is_empty():
		return

	var variant_index: int = absi(
		hash(str(global_position.snapped(Vector3(0.01, 0.01, 0.01))))
	) % variants.size()

	for index: int in variants.size():
		variants[index].visible = index == variant_index


func get_assigned_worker_count() -> int:
	return _assigned_worker_count


func register_assigned_worker() -> void:
	_assigned_worker_count += 1


func unregister_assigned_worker() -> void:
	_assigned_worker_count = maxi(0, _assigned_worker_count - 1)


func get_resource_id() -> StringName:
	return &"wood"


func can_gather() -> bool:
	return wood_amount > 0


func gather(amount: int) -> int:
	if wood_amount <= 0:
		return 0

	var gathered: int = mini(amount, wood_amount)
	wood_amount -= gathered
	if wood_amount <= 0:
		depleted.emit()
	return gathered
