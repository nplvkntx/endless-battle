class_name Blacksmith
extends Building

## Player military upgrade building for swordsman and archer research.

signal research_state_changed()

const RESEARCH_SECONDS: float = 5.0

@onready var _health_component: HealthComponent = get_node_or_null(
	"HealthComponent"
) as HealthComponent

var _is_researching: bool = false
var _research_upgrade_id: StringName = &""
var _research_started_at: float = 0.0
var _research_session: int = 0


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


func is_researching() -> bool:
	return _is_researching


func get_research_progress() -> float:
	if not _is_researching:
		return 0.0

	var elapsed: float = _get_time_seconds() - _research_started_at
	return clampf(elapsed / RESEARCH_SECONDS, 0.0, 1.0)


func get_research_activity_label() -> String:
	if not _is_researching:
		return ""

	var next_level: int = UpgradeManager.get_level(_research_upgrade_id) + 1
	return "%s %d/%d" % [
		UpgradeManager.get_display_name(_research_upgrade_id),
		next_level,
		UpgradeManager.MAX_LEVEL,
	]


func try_research_upgrade(upgrade_id: StringName) -> bool:
	if not can_research() or _is_researching:
		return false

	if not UpgradeManager.try_pay_for_research(upgrade_id):
		return false

	_begin_research(upgrade_id)
	return true


func take_damage(amount: float, _attacker = null) -> void:
	if _health_component == null or _health_component.current_health <= 0:
		return

	if not _health_component.has_method("take_damage"):
		return

	_health_component.take_damage(maxi(0, int(amount)))


func _begin_research(upgrade_id: StringName) -> void:
	_research_session += 1
	var session: int = _research_session
	_is_researching = true
	_research_upgrade_id = upgrade_id
	_research_started_at = _get_time_seconds()
	research_state_changed.emit()

	var wait_timer: SceneTreeTimer = get_tree().create_timer(RESEARCH_SECONDS)
	wait_timer.timeout.connect(func() -> void:
		_on_research_finished(session)
	, CONNECT_ONE_SHOT)


func _on_research_finished(session: int) -> void:
	if session != _research_session:
		return

	var completed_upgrade_id: StringName = _research_upgrade_id
	_is_researching = false
	_research_upgrade_id = &""
	UpgradeManager.finish_research(completed_upgrade_id)
	research_state_changed.emit()


func _invalidate_research() -> void:
	_research_session += 1
	_is_researching = false
	_research_upgrade_id = &""
	research_state_changed.emit()


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_health_depleted() -> void:
	_invalidate_research()
	destroy_building()
	queue_free()
