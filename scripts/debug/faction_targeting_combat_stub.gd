extends Node3D

## Minimal damageable combat stub for headless faction targeting verification.


func take_damage(amount: float, attacker = null) -> void:
	DamageService.apply(
		self,
		amount,
		attacker,
		{DamageService.OPT_IGNORE_HOSTILITY: true}
	)


func get_current_health() -> int:
	var health: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return 0
	return health.current_health
