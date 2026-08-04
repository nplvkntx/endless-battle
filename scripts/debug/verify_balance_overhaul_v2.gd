extends SceneTree

## Headless balance overhaul smoke checks. Run with:
## godot --headless --path . --script scripts/debug/verify_balance_overhaul_v2.gd

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
	_check_economy(failures)
	_check_units(failures)
	_check_buildings(failures)
	_check_heroes(failures)
	_check_matrix(failures)
	_check_items(failures)
	_check_upgrades(failures)
	_check_creeps(failures)
	_check_construction(failures)

	if failures.is_empty():
		print("BALANCE_OVERHAUL_V2_OK")
		quit(0)
	else:
		print("BALANCE_OVERHAUL_V2_FAIL")
		for failure: String in failures:
			print(" - ", failure)
		quit(1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)


func _check_economy(failures: PackedStringArray) -> void:
	_expect(failures, "starting gold 500", EconomyStats.STARTING_GOLD == 500)
	_expect(failures, "starting wood 500", EconomyStats.STARTING_WOOD == 500)
	_expect(failures, "food max 15", EconomyStats.STARTING_FOOD_MAX == 15)
	_expect(failures, "workers 5", EconomyStats.STARTING_WORKER_COUNT == 5)
	_expect(failures, "worker train 6s", UnitStats.WORKER_TRAIN_SECONDS == 6.0)
	_expect(failures, "farm food 8", BuildingStats.FARM_FOOD_CAP_BONUS == 8)


func _check_units(failures: PackedStringArray) -> void:
	_expect(failures, "worker hp 90", UnitStats.WORKER_MAX_HEALTH == 90)
	_expect(failures, "spearman hp 110", UnitStats.SPEARMAN_MAX_HEALTH == 110)
	_expect(failures, "spearman cav bonus", UnitStats.SPEARMAN_CAVALRY_DAMAGE_MULTIPLIER == 1.5)
	_expect(failures, "swordsman dmg 12", UnitStats.SWORDSMAN_ATTACK_DAMAGE == 12)
	_expect(failures, "archer gold 95", UnitStats.ARCHER_GOLD_COST == 95)
	_expect(failures, "archer range/lvl 0.75", UnitStats.ARCHER_ATTACK_RANGE_PER_UPGRADE_LEVEL == 0.75)
	_expect(
		failures,
		"archer lvl5 range 11.75",
		is_equal_approx(8.0 + 5.0 * UnitStats.ARCHER_ATTACK_RANGE_PER_UPGRADE_LEVEL, 11.75)
	)
	_expect(failures, "light cav food 2", UnitStats.LIGHT_CAVALRY_FOOD_COST == 2)
	_expect(failures, "cav archer food 2", UnitStats.CAVALRY_ARCHER_FOOD_COST == 2)
	_expect(failures, "heavy cav food 3", UnitStats.HEAVY_CAVALRY_FOOD_COST == 3)
	_expect(failures, "cannon food 3", UnitStats.CANNON_FOOD_COST == 3)
	_expect(failures, "cannon splash min 0.35", UnitStats.CANNON_SPLASH_MIN_DAMAGE_RATIO == 0.35)
	_expect(failures, "archer train gold const", UnitStats.ARCHER_GOLD_COST == 95)
	_expect(failures, "archer train time const", UnitStats.ARCHER_TRAIN_SECONDS == 7.0)
	_expect(failures, "cav archer food const", UnitStats.CAVALRY_ARCHER_FOOD_COST == 2)


func _check_buildings(failures: PackedStringArray) -> void:
	_expect(failures, "farm hp 400", BuildingStats.FARM_MAX_HEALTH == 400)
	_expect(failures, "barracks hp 800", BuildingStats.BARRACKS_MAX_HEALTH == 800)
	_expect(failures, "stable hp 850", BuildingStats.STABLE_MAX_HEALTH == 850)
	_expect(failures, "no AI stable override", BuildingStats.ENEMY_STABLE_MAX_HEALTH == 850)
	_expect(failures, "cc hp 1600", BuildingStats.COMMAND_CENTER_MAX_HEALTH == 1600)
	_expect(failures, "tower dmg 18", BuildingStats.TOWER_ATTACK_DAMAGE == 18)
	_expect(failures, "farm build 10s", BuildingStats.FARM_CONSTRUCTION_SECONDS == 10.0)
	_expect(failures, "barracks build 18s", BuildingStats.BARRACKS_CONSTRUCTION_SECONDS == 18.0)
	_expect(
		failures,
		"2 workers 70%",
		is_equal_approx(BuildingStats.get_construction_seconds(&"farm", 2), 7.0)
	)
	_expect(
		failures,
		"3 workers 55%",
		is_equal_approx(BuildingStats.get_construction_seconds(&"farm", 3), 5.5)
	)


func _check_heroes(failures: PackedStringArray) -> void:
	_expect(failures, "paladin hp 240", HeroStats.MAX_HEALTH == 240)
	_expect(failures, "paladin armor 2", HeroStats.ARMOR == 2.0)
	_expect(failures, "paladin W duration 2", HeroStats.DIVINE_PROTECTION_DURATION == 2.0)
	_expect(failures, "paladin R thresh 0.25", HeroStats.EXECUTE_HEALTH_THRESHOLD == 0.25)
	_expect(failures, "assassin hp 190", ShadowAssassinStats.MAX_HEALTH == 190)
	_expect(failures, "assassin AD/lvl 2.5", ShadowAssassinStats.ATTACK_DAMAGE_PER_LEVEL == 2.5)
	_expect(failures, "ranger hp 170", RangerStats.MAX_HEALTH == 170)
	_expect(failures, "ranger AS/lvl 2.5%", RangerStats.ATTACK_SPEED_PER_LEVEL == 0.025)
	_expect(failures, "holy regen 1.5%", HeroPassiveStats.HOLY_RECOVERY_REGEN_PERCENT_PER_SECOND == 0.015)
	_expect(failures, "hunter ratio 8%", RangerStats.HUNTERS_PRECISION_MAX_HEALTH_RATIO == 0.08)
	_expect(failures, "hunter cap lvl1", RangerStats.get_hunters_precision_damage_cap(1) == 65)
	_expect(failures, "smoke dur r1", ShadowAssassinStats.get_smoke_duration(1) == 5.0)
	_expect(failures, "dash dmg r2", ShadowAssassinStats.get_dash_damage(2) == 65)
	_expect(failures, "trap root r3", RangerStats.get_bear_trap_root_duration(3) == 2.6)
	_expect(
		failures,
		"AS formula",
		is_equal_approx(UnitStats.get_final_attack_cooldown(1.0, 1.0), 0.5)
	)


func _check_matrix(failures: PackedStringArray) -> void:
	_expect(failures, "pierce vs light 1.25", DamageArmorMatrix.get_multiplier(1, 0) == 1.25)
	_expect(failures, "siege vs building 1.5", DamageArmorMatrix.get_multiplier(3, 4) == 1.5)
	_expect(failures, "true identity", DamageArmorMatrix.get_multiplier(4, 3) == 1.0)


func _check_items(failures: PackedStringArray) -> void:
	_expect(failures, "no long_sword", HeroItemCatalog.get_definition(&"long_sword") == null)
	_expect(failures, "iron blade exists", HeroItemCatalog.get_definition(&"iron_blade") != null)
	_expect(failures, "titan cleaver exists", HeroItemCatalog.get_definition(&"titan_cleaver") != null)
	var exec: HeroItemDefinition = HeroItemCatalog.get_definition(&"executioner_axe")
	_expect(failures, "executioner recipe", exec != null and exec.has_recipe())
	_expect(failures, "executioner total 950", exec != null and exec.gold_cost == 950)
	_expect(failures, "executioner combine 300", exec != null and exec.get_recipe_gold_cost() == 300)
	_expect(failures, "shop count 27", HeroItemCatalog.SHOP_ITEM_ORDER.size() == 27)
	_expect(failures, "sell ratio 0.5", ItemStats.SELL_REFUND_RATIO == 0.5)
	_expect(failures, "crit 1.75", ItemStats.CRITICAL_DAMAGE_MULTIPLIER == 1.75)


func _check_upgrades(failures: PackedStringArray) -> void:
	_expect(failures, "cav attack +2", UpgradeStats.CAVALRY_ATTACK_DAMAGE_PER_LEVEL == 2)
	_expect(failures, "swordsman attack +2", UnitStats.SWORDSMAN_ATTACK_DAMAGE_PER_UPGRADE_LEVEL == 2)


func _check_creeps(failures: PackedStringArray) -> void:
	_expect(failures, "medium xp/creep 40", EconomyStats.CREEP_XP_MEDIUM == 40)
	_expect(failures, "strong xp/creep 80", EconomyStats.CREEP_XP_STRONG == 80)
	_expect(failures, "medium total xp 240", EconomyStats.MEDIUM_CAMP_TOTAL_XP == 240)
	_expect(failures, "strong total xp 400", EconomyStats.STRONG_CAMP_TOTAL_XP == 400)


func _check_construction(failures: PackedStringArray) -> void:
	_expect(
		failures,
		"min ratio floor",
		BuildingStats.CONSTRUCTION_TIME_RATIO_MINIMUM == 0.45
	)
	_expect(failures, "ai thresholds creep 5", MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS == 5)
	_expect(failures, "ai attack 10", MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS == 10)
	_expect(failures, "ai preferred 12", MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS_PREFERRED == 12)
