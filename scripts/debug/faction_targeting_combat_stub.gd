extends Node3D

## Minimal damageable combat stub for headless faction targeting verification.


func take_damage(amount: float, _attacker = null) -> void:
	var health: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.current_health <= 0:
		return

	health.take_damage(maxi(0, int(amount)))


func get_current_health() -> int:
	var health: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return 0
	return health.current_health
