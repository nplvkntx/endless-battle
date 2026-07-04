class_name Farm
extends Building

## Placeholder farm building used for early 3D scene testing.

const FOOD_CAP_BONUS: int = 8

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func complete_construction() -> void:
	if building_state == STATE_COMPLETED:
		return

	super.complete_construction()
	if is_in_group(&"enemy_command_center"):
		EnemyResourceManager.add_food_max(FOOD_CAP_BONUS)
	else:
		ResourceManager.add_food_max(FOOD_CAP_BONUS)


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


func take_damage(amount: float, attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	attacker = CombatTargetValidation.sanitize_damage_attacker(attacker)
	CombatKillTracker.record_attacker(self, attacker)
	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	destroy_building()
	queue_free()
