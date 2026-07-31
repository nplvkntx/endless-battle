extends Node3D

## Assigns gather-resource owner factions by home-base proximity (no node-name checks).

@export var player_home: Vector3 = Vector3(-38.0, 0.0, -38.0)
@export var enemy_home: Vector3 = Vector3(38.0, 0.0, 38.0)
@export var home_radius: float = 16.0


func _ready() -> void:
	_assign_resource_factions()


func _assign_resource_factions() -> void:
	var home_radius_sq: float = home_radius * home_radius
	for child: Node in get_children():
		if not child is GatherableResource:
			continue

		var resource := child as GatherableResource
		if resource.owner_faction != GatherableResource.OwnerFaction.UNSET:
			resource.set_owner_faction(resource.owner_faction)
			continue

		var pos: Vector3 = resource.global_position
		pos.y = 0.0
		var to_player: Vector3 = pos - Vector3(player_home.x, 0.0, player_home.z)
		var to_enemy: Vector3 = pos - Vector3(enemy_home.x, 0.0, enemy_home.z)
		if to_player.length_squared() <= home_radius_sq:
			resource.set_owner_faction(GatherableResource.OwnerFaction.PLAYER)
		elif to_enemy.length_squared() <= home_radius_sq:
			resource.set_owner_faction(GatherableResource.OwnerFaction.ENEMY)
		else:
			resource.set_owner_faction(GatherableResource.OwnerFaction.NEUTRAL)
