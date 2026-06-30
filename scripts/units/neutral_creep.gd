class_name NeutralCreep
extends EnemyDummy

## Idle neutral camp unit. Fights back when attacked; no patrol AI yet.


func _ready() -> void:
	if is_in_group(&"enemies"):
		remove_from_group(&"enemies")
	if not is_in_group(&"neutral_creeps"):
		add_to_group(&"neutral_creeps")
	team_id = -1
	super._ready()


func _on_health_depleted() -> void:
	_health_bar.visible = false
	print("NeutralCreep died")
	queue_free()
