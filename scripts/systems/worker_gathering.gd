class_name WorkerGathering
extends RefCounted

## Shared deposit helpers for worker gathering trips.


static func deposit(resource_id: StringName, amount: int) -> void:
	if amount <= 0:
		return

	match resource_id:
		&"gold":
			ResourceManager.add_gold(amount)
		&"wood":
			ResourceManager.add_wood(amount)
		_:
			push_error("Unknown gather resource id: %s" % resource_id)
