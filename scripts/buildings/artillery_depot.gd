class_name ArtilleryDepot
extends Building

## Tier 3 military workshop. Will train horse-drawn cannons in a future update.

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


func can_show_commands() -> bool:
	if building_state != STATE_COMPLETED:
		return false

	return TeamVisuals.resolve_team(self, team_id) == TeamVisuals.PLAYER_TEAM_ID


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
