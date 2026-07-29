class_name EnemyAIDebug
extends RefCounted

## Change-only enemy AI console logging. Prints only when a tracked state actually changes.

static var enabled: bool = false

static var _last_phase: String = ""
static var _last_mission_phrase: String = ""
static var _last_strength_decision: String = ""
static var _last_build_action: String = ""
static var _last_train_action: String = ""
static var _last_research_action: String = ""
static var _last_expand_action: String = ""
static var _last_upgrade_action: String = ""
static var _last_hero_mission: String = ""


static func set_enabled(value: bool) -> void:
	enabled = value


static func is_enabled() -> bool:
	return enabled


static func log_event(message: String) -> void:
	if not enabled:
		return

	if message.is_empty():
		return

	print("%s[AI] %s" % [_timestamp_prefix(), message])


static func log_once(key: String, message: String) -> void:
	if not enabled:
		return

	match key:
		"phase":
			if message == _last_phase:
				return
			_last_phase = message
		"mission":
			if message == _last_mission_phrase:
				return
			_last_mission_phrase = message
		"strength":
			if message == _last_strength_decision:
				return
			_last_strength_decision = message
		"build":
			if message == _last_build_action:
				return
			_last_build_action = message
		"train":
			if message == _last_train_action:
				return
			_last_train_action = message
		"research":
			if message == _last_research_action:
				return
			_last_research_action = message
		"expand":
			if message == _last_expand_action:
				return
			_last_expand_action = message
		"upgrade":
			if message == _last_upgrade_action:
				return
			_last_upgrade_action = message
		"hero_mission":
			if message == _last_hero_mission:
				return
			_last_hero_mission = message
		_:
			pass

	log_event(message)


static func log_phase(phase_name: String) -> void:
	log_once("phase", "Phase -> %s" % phase_name)


static func log_mission_change(
	_previous: EnemyUnitMission.Mission,
	mission: EnemyUnitMission.Mission,
	_reason: String = ""
) -> void:
	log_once("mission", "Mission: %s" % EnemyUnitMission.mission_to_debug_phrase(mission))


static func log_hero_mission(
	_previous: EnemyUnitMission.Mission,
	mission: EnemyUnitMission.Mission
) -> void:
	if mission == EnemyUnitMission.Mission.SHOP:
		log_once("hero_mission", "Mission: Shopping")


static func log_army_strength_decision(
	ai_strength: float,
	enemy_strength: float,
	decision: String
) -> void:
	var message: String = (
		"Army strength: %d vs Enemy: %d -> %s"
		% [int(round(ai_strength)), int(round(enemy_strength)), decision]
	)
	log_once("strength", message)


static func log_building(building_name: String) -> void:
	log_once("build", "Building %s" % building_name)


static func log_training(unit_name: String) -> void:
	log_once("train", "Training %s" % unit_name)


static func log_research(upgrade_name: String) -> void:
	log_once("research", "Researching %s" % upgrade_name)


static func log_expanding() -> void:
	log_once("expand", "Expanding to Gold Mine")


static func log_town_hall_upgrade(tier: int) -> void:
	log_once("upgrade", "Upgrading Town Hall to T%d" % tier)


static func match_phase_label(elapsed_seconds: float) -> String:
	if elapsed_seconds < EnemyArmyCommand.PHASE_EARLY_SECONDS:
		return "Early Economy"
	if elapsed_seconds < EnemyArmyCommand.PHASE_MID_SECONDS:
		return "Mid Game"
	return "Late Game"


static func _timestamp_prefix() -> String:
	var msec: int = Time.get_ticks_msec()
	var total_seconds: int = int(msec / 1000.0)
	var minutes: int = int(total_seconds / 60.0)
	var seconds: int = total_seconds % 60
	return "[%02d:%02d] " % [minutes, seconds]
