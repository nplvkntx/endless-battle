class_name WorkerGathering
extends RefCounted

## Shared deposit helpers for worker gathering trips.

static var _enemy_stockpile_warning_shown: bool = false


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
	if not _is_enemy_stockpile_available():
		_warn_enemy_stockpile_unavailable(resource_id, amount)
		return

	match resource_id:
		&"gold":
			EnemyResourceManager.add_gold(amount)
		&"wood":
			EnemyResourceManager.add_wood(amount)
		_:
			push_error("Unknown gather resource id: %s" % resource_id)


static func _is_enemy_stockpile_available() -> bool:
	if not is_instance_valid(EnemyResourceManager):
		return false

	if not EnemyResourceManager.has_method("is_stockpile_available"):
		return (
			EnemyResourceManager.has_method("add_gold")
			and EnemyResourceManager.has_method("add_wood")
		)

	return EnemyResourceManager.is_stockpile_available()


static func _warn_enemy_stockpile_unavailable(resource_id: StringName, amount: int) -> void:
	if _enemy_stockpile_warning_shown:
		return

	_enemy_stockpile_warning_shown = true
	push_warning(
		"WorkerGathering: enemy stockpile unavailable; dropped %d %s" % [amount, resource_id]
	)
