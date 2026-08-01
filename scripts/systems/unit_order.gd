class_name UnitOrder
extends RefCounted

## Shared RTS order representation for the unified WC3-style command queue.
## Movement, combat, gather, and build all share one queue on Unit.

enum Type {
	MOVE,
	ATTACK,
	ATTACK_MOVE,
	PATROL,
	HOLD_POSITION,
	STOP,
	BUILD,
	GATHER,
}

enum Status {
	PENDING,
	ACTIVE,
	DONE,
	CANCELLED,
}

var type: Type = Type.MOVE
var destination: Vector3 = Vector3.ZERO
## Stored untyped so freed targets do not crash on typed cast access.
var target: Variant = null
var patrol_points: Array[Vector3] = []
var assigned_slot: int = -1
## Placement metadata (build orders / future place-build entries).
var building_type: StringName = &""
var world_position: Vector3 = Vector3.ZERO
var rotation_y: float = 0.0
## Gold/wood tied to this order when resources were reserved or spent for it.
var reservation_gold: int = 0
var reservation_wood: int = 0
var status: Status = Status.PENDING


static func move(move_destination: Vector3) -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.MOVE
	order.destination = move_destination
	order.world_position = move_destination
	return order


static func attack(attack_target: Node3D, attack_assigned_slot: int = -1) -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.ATTACK
	order.target = NodeSafety.safe_node(attack_target)
	order.assigned_slot = attack_assigned_slot
	return order


static func attack_move(move_destination: Vector3) -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.ATTACK_MOVE
	order.destination = move_destination
	order.world_position = move_destination
	return order


static func patrol(points: Array[Vector3]) -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.PATROL
	order.patrol_points = points.duplicate()
	return order


static func hold_position() -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.HOLD_POSITION
	return order


static func stop() -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.STOP
	return order


static func build(building: Node3D) -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.BUILD
	order.target = NodeSafety.safe_node(building)
	if building is Node3D and is_instance_valid(building):
		order.world_position = (building as Node3D).global_position
		order.rotation_y = (building as Node3D).rotation.y
	return order


static func gather(gather_target: Node3D) -> UnitOrder:
	var order := UnitOrder.new()
	order.type = Type.GATHER
	order.target = NodeSafety.safe_node(gather_target)
	if gather_target is Node3D and is_instance_valid(gather_target):
		order.world_position = (gather_target as Node3D).global_position
	return order


func is_target_order() -> bool:
	return type == Type.ATTACK or type == Type.BUILD or type == Type.GATHER


func get_alive_target() -> Node3D:
	return NodeSafety.safe_node(target) as Node3D


func clear_invalid_target() -> void:
	if not NodeSafety.is_alive_node(target):
		target = null


## True when issuing `other` would not change behavior (same type/target/destination).
func is_equivalent(other: UnitOrder, destination_tolerance: float = 0.35) -> bool:
	if other == null or type != other.type:
		return false

	match type:
		Type.MOVE, Type.ATTACK_MOVE:
			var delta: Vector3 = destination - other.destination
			delta.y = 0.0
			return delta.length() <= destination_tolerance
		Type.ATTACK, Type.BUILD, Type.GATHER:
			var self_target: Node3D = get_alive_target()
			var other_target: Node3D = other.get_alive_target()
			if self_target == null or other_target == null:
				return false
			return self_target == other_target and assigned_slot == other.assigned_slot
		Type.HOLD_POSITION, Type.STOP:
			return true
		Type.PATROL:
			if patrol_points.size() != other.patrol_points.size():
				return false
			for index: int in patrol_points.size():
				var point_delta: Vector3 = patrol_points[index] - other.patrol_points[index]
				point_delta.y = 0.0
				if point_delta.length() > destination_tolerance:
					return false
			return true
		_:
			return false


func describe() -> String:
	match type:
		Type.MOVE:
			return "Move"
		Type.ATTACK:
			return "Attack"
		Type.ATTACK_MOVE:
			return "Attack-Move"
		Type.PATROL:
			return "Patrol"
		Type.HOLD_POSITION:
			return "Hold Position"
		Type.STOP:
			return "Stop"
		Type.BUILD:
			return "Build"
		Type.GATHER:
			return "Gather"
		_:
			return "Order"
