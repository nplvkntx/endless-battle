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
static var _last_opening_action: String = ""
static var _opening_complete_logged: bool = false
static var _last_early_army_action: String = ""
static var _last_early_army_pikemen: String = ""
static var _last_early_army_rally: String = ""
static var _early_army_complete_logged: bool = false
static var _last_creeping_action: String = ""
static var _last_creeping_camp: String = ""
static var _last_creeping_hero_level: int = 0
static var _creeping_complete_logged: bool = false
static var _last_tier_2_action: String = ""
static var _last_tier_2_missing: String = ""
static var _last_tier_2_save: String = ""
static var _last_tier_2_upgrade: String = ""
static var _tier_2_complete_logged: bool = false
static var _last_strategic_state: String = ""
static var _last_retreat: String = ""
static var _last_player_attack_blocked: String = ""


static func set_enabled(value: bool) -> void:
	enabled = value


static func reset_match_state() -> void:
	_last_phase = ""
	_last_mission_phrase = ""
	_last_strength_decision = ""
	_last_build_action = ""
	_last_train_action = ""
	_last_research_action = ""
	_last_expand_action = ""
	_last_upgrade_action = ""
	_last_hero_mission = ""
	_last_opening_action = ""
	_opening_complete_logged = false
	_last_early_army_action = ""
	_last_early_army_pikemen = ""
	_last_early_army_rally = ""
	_early_army_complete_logged = false
	_last_creeping_action = ""
	_last_creeping_camp = ""
	_last_creeping_hero_level = 0
	_creeping_complete_logged = false
	_last_tier_2_action = ""
	_last_tier_2_missing = ""
	_last_tier_2_save = ""
	_last_tier_2_upgrade = ""
	_tier_2_complete_logged = false
	_last_strategic_state = ""
	_last_retreat = ""
	_last_player_attack_blocked = ""


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
		"opening":
			if message == _last_opening_action:
				return
			_last_opening_action = message
		"early_army":
			if message == _last_early_army_action:
				return
			_last_early_army_action = message
		"early_army_pikemen":
			if message == _last_early_army_pikemen:
				return
			_last_early_army_pikemen = message
		"early_army_rally":
			if message == _last_early_army_rally:
				return
			_last_early_army_rally = message
		"creeping":
			if message == _last_creeping_action:
				return
			_last_creeping_action = message
		"creeping_camp":
			if message == _last_creeping_camp:
				return
			_last_creeping_camp = message
		"tier_2":
			if message == _last_tier_2_action:
				return
			_last_tier_2_action = message
		"tier_2_missing":
			if message == _last_tier_2_missing:
				return
			_last_tier_2_missing = message
		"tier_2_save":
			if message == _last_tier_2_save:
				return
			_last_tier_2_save = message
		"tier_2_upgrade":
			if message == _last_tier_2_upgrade:
				return
			_last_tier_2_upgrade = message
		"strategic_state":
			if message == _last_strategic_state:
				return
			_last_strategic_state = message
		"retreat":
			if message == _last_retreat:
				return
			_last_retreat = message
		"player_attack_blocked":
			if message == _last_player_attack_blocked:
				return
			_last_player_attack_blocked = message
		_:
			pass

	log_event(message)


static func log_phase(phase_name: String) -> void:
	log_once("phase", "Phase -> %s" % phase_name)


static func log_phase_transition(from_phase: String, to_phase: String, reason: String) -> void:
	var message: String = "Phase %s -> %s" % [from_phase, to_phase]
	if not reason.is_empty():
		message += " | %s" % reason
	log_once("phase", message)


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


static func log_opening(message: String) -> void:
	if message.is_empty():
		return
	log_once("opening", "Opening: %s" % message)


static func log_opening_training(current_workers: int, target_workers: int) -> void:
	log_opening("Training worker %d/%d" % [current_workers, target_workers])


static func log_opening_complete(
	workers: int,
	farm_ready: bool,
	altar_ready: bool,
	barracks_ready: bool
) -> void:
	if _opening_complete_logged:
		return
	_opening_complete_logged = true
	log_event(
		"Opening complete | Workers: %d, Farm: %s, Altar: %s, Barracks: %s"
		% [
			workers,
			"ready" if farm_ready else "pending",
			"ready" if altar_ready else "pending",
			"ready" if barracks_ready else "pending",
		]
	)


static func log_early_army(message: String) -> void:
	if message.is_empty():
		return
	if message == "Rallying army" or message == "Regrouping":
		log_once("early_army_rally", "Early Army: Regrouping")
		return
	log_once("early_army", "Early Army: %s" % message)


static func log_early_army_pikemen(current: int, target: int) -> void:
	log_once(
		"early_army_pikemen",
		"Early Army: Pikemen %d/%d" % [current, target]
	)


static func log_early_army_complete(_pikemen: int) -> void:
	if _early_army_complete_logged:
		return
	_early_army_complete_logged = true
	log_event("Early Army complete -> CREEPING")

static func log_creeping_phase() -> void:
	log_once("phase", "Phase: CREEPING")


static func log_creeping(message: String) -> void:
	if message.is_empty():
		return
	log_once("creeping", message)


static func log_creeping_camp_selected(camp_name: String, distance: float) -> void:
	log_once(
		"creeping_camp",
		"Selected creep camp: %s (distance %d)" % [camp_name, int(round(distance))]
	)


static func log_creep_squad_ready(non_hero_count: int) -> void:
	log_once(
		"creeping",
		"AI creep squad ready: hero + %d units" % non_hero_count
	)


static func log_creep_camp_selected_safety(camp_name: String, safety: float) -> void:
	log_once(
		"creeping_camp",
		"AI selected creep camp: %s, estimated safety: %.2f" % [camp_name, safety]
	)


static func log_creep_mission_started() -> void:
	log_once("creeping", "AI creep mission started")


static func log_creep_retreat(reason: String) -> void:
	var message: String = "AI retreating from camp"
	if not reason.is_empty():
		message += ": %s" % reason
	log_once("retreat", message)


static func log_creep_camp_cleared(camp_name: String) -> void:
	log_event("AI cleared camp: %s" % camp_name)


static func log_creeping_hero_level(level: int) -> void:
	if level <= _last_creeping_hero_level:
		return
	_last_creeping_hero_level = level
	# Prefer the explicit "Creeping: Hero level N" message from the creep manager.


static func log_creeping_retreat_hero_hp(hp_ratio: float) -> void:
	log_once("retreat", "Retreat: Hero HP %d%%" % int(round(hp_ratio * 100.0)))


static func log_creeping_complete() -> void:
	if _creeping_complete_logged:
		return
	_creeping_complete_logged = true
	log_event("Creeping complete -> TIER_2")


static func log_tier_2(message: String) -> void:
	if message.is_empty():
		return
	log_once("tier_2", "Tier 2: %s" % message)


static func log_tier_2_missing_building(building_name: String) -> void:
	if building_name.is_empty():
		return
	log_once("tier_2_missing", "Tier 2: Missing Tier 1 building -> %s" % building_name)


static func log_tier_2_saving(gold: int, gold_needed: int, wood: int, wood_needed: int) -> void:
	log_once(
		"tier_2_save",
		"Tier 2: Saving resources | Gold %d/%d, Wood %d/%d"
		% [gold, gold_needed, wood, wood_needed]
	)


static func log_tier_2_upgrade(message: String) -> void:
	if message.is_empty():
		return
	log_once("tier_2_upgrade", "Tier 2: %s" % message)


static func log_tier_2_complete() -> void:
	if _tier_2_complete_logged:
		return
	_tier_2_complete_logged = true
	log_event("Tier 2 complete | Town Hall reached Tier 2")


static func match_phase_label(elapsed_seconds: float) -> String:
	# Legacy time-bucket label; prefer EnemyStrategicDirector.get_strategic_phase_name().
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
