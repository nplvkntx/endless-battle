class_name WorkerGathering
extends RefCounted

## Shared deposit helpers for worker gathering trips.


static func deposit(resource_id: StringName, amount: int, for_enemy: bool = false) -> void:
	if amount <= 0:
		return

	if for_enemy:
		_deposit_to_enemy_stockpile(resource_id, amount)
		return

	match resource_id:
		&"gold":
			ResourceManager.add_gold(amount)
		&"wood":
			ResourceManager.add_wood(amount)
		_:
			push_error("Unknown gather resource id: %s" % resource_id)


static func _deposit_to_enemy_stockpile(resource_id: StringName, amount: int) -> void:
	match resource_id:
		&"gold":
			EnemyResourceManager.add_gold(amount)
		&"wood":
			EnemyResourceManager.add_wood(amount)
		_:
			push_error("Unknown gather resource id: %s" % resource_id)
