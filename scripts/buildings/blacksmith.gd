class_name Blacksmith
extends Building

## Player military upgrade building for swordsman and archer research.

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent


func _ready() -> void:
	super._ready()
	if building_state.is_empty():
		set_completed()

	if _health_component != null and _health_component.has_signal("health_depleted"):
		_health_component.health_depleted.connect(_on_health_depleted, CONNECT_ONE_SHOT)


func can_research() -> bool:
	if building_state != STATE_COMPLETED:
		return false

	return TeamVisuals.resolve_team(self, team_id) == TeamVisuals.PLAYER_TEAM_ID


func try_research_upgrade(upgrade_id: StringName) -> bool:
	if not can_research():
		return false

	return UpgradeManager.try_research(upgrade_id)


func take_damage(amount: float, _attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	_health_component.take_damage(maxi(0, int(amount)))


func _on_health_depleted() -> void:
	destroy_building()
	queue_free()
