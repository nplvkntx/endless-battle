extends Node

## Scene wrapper so autoloads are available for balance checks.


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()
	_run_checks(failures)
	if failures.is_empty():
		print("PASS balance_overhaul_v2")
		get_tree().quit(0)
	else:
		print("FAIL balance_overhaul_v2")
		for failure: String in failures:
			print(" - ", failure)
		get_tree().quit(1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)


func _run_checks(failures: PackedStringArray) -> void:
	_expect(failures, "starting gold 500", EconomyStats.STARTING_GOLD == 500)
	_expect(failures, "worker hp 90", UnitStats.WORKER_MAX_HEALTH == 90)
	_expect(failures, "worker train 6s", UnitStats.WORKER_TRAIN_SECONDS == 6.0)
	_expect(failures, "spearman cav bonus", UnitStats.SPEARMAN_CAVALRY_DAMAGE_MULTIPLIER == 1.5)
	_expect(failures, "archer gold 95", UnitStats.ARCHER_GOLD_COST == 95)
	_expect(
		failures,
		"archer lvl5 range 11.75",
		is_equal_approx(8.0 + 5.0 * UnitStats.ARCHER_ATTACK_RANGE_PER_UPGRADE_LEVEL, 11.75)
	)
	_expect(failures, "barracks archer gold", Barracks.get_unit_train_gold_cost(&"archer") == 95)
	_expect(failures, "barracks archer food", Barracks.get_unit_train_food_cost(&"archer") == 1)
	_expect(failures, "barracks archer time", Barracks.get_unit_train_seconds(&"archer") == 7.0)
	_expect(failures, "stable cav archer food", Stable.get_unit_train_food_cost(&"cavalry_archer") == 2)
	_expect(failures, "food spearman", UnitFoodSupply.get_cost(Spearman.new()) == 1)
	_expect(failures, "food light cav", UnitFoodSupply.get_cost(LightCavalry.new()) == 2)
	_expect(failures, "food heavy cav", UnitFoodSupply.get_cost(HeavyCavalry.new()) == 3)
	_expect(failures, "food cannon", UnitFoodSupply.get_cost(Cannon.new()) == 3)
	_expect(failures, "farm build 10s", BuildingStats.FARM_CONSTRUCTION_SECONDS == 10.0)
	_expect(
		failures,
		"2 worker farm 7s",
		is_equal_approx(BuildingStats.get_construction_seconds(&"farm", 2), 7.0)
	)
	_expect(failures, "stable hp shared", BuildingStats.ENEMY_STABLE_MAX_HEALTH == BuildingStats.STABLE_MAX_HEALTH)
	_expect(failures, "paladin W 2.0", HeroStats.DIVINE_PROTECTION_DURATION == 2.0)
	_expect(failures, "paladin R 0.25", HeroStats.EXECUTE_HEALTH_THRESHOLD == 0.25)
	_expect(failures, "holy regen 1.5%", HeroPassiveStats.HOLY_RECOVERY_REGEN_PERCENT_PER_SECOND == 0.015)
	_expect(failures, "hunter 8%", RangerStats.HUNTERS_PRECISION_MAX_HEALTH_RATIO == 0.08)
	_expect(failures, "hunter cap l1", RangerStats.get_hunters_precision_damage_cap(1) == 65)
	_expect(failures, "dash dmg r3", ShadowAssassinStats.get_dash_damage(3) == 80)
	_expect(failures, "smoke dur r5", ShadowAssassinStats.get_smoke_duration(5) == 7.0)
	_expect(failures, "trap root r5", RangerStats.get_bear_trap_root_duration(5) == 3.2)
	_expect(failures, "pierce light 1.25", DamageArmorMatrix.get_multiplier(1, 0) == 1.25)
	_expect(failures, "siege building 1.5", DamageArmorMatrix.get_multiplier(3, 4) == 1.5)
	_expect(failures, "no long_sword", HeroItemCatalog.get_definition(&"long_sword") == null)
	_expect(failures, "iron_blade", HeroItemCatalog.get_definition(&"iron_blade") != null)
	var titan: HeroItemDefinition = HeroItemCatalog.get_definition(&"titan_cleaver")
	_expect(failures, "titan total 2700", titan != null and titan.gold_cost == 2700)
	_expect(failures, "titan recipe", titan != null and titan.has_recipe())
	_expect(failures, "shop 27 items", HeroItemCatalog.SHOP_ITEM_ORDER.size() == 27)
	_expect(failures, "medium creep xp 40", EconomyStats.CREEP_XP_MEDIUM == 40)
	_expect(failures, "strong creep xp 80", EconomyStats.CREEP_XP_STRONG == 80)
	_expect(failures, "cav upgrade +2", UpgradeStats.CAVALRY_ATTACK_DAMAGE_PER_LEVEL == 2)
	_expect(failures, "ai creep ready 5", MilitaryAIConfig.V2_CREEP_READY_MILITARY_UNITS == 5)
	_expect(failures, "ai attack ready 10", MilitaryAIConfig.V2_ATTACK_READY_MILITARY_UNITS == 10)
	_expect(failures, "paladin prefs", AIItemPreferences.get_base_goals(HeroCatalog.KIT_PALADIN).size() > 0)
	_expect(failures, "assassin prefs", AIItemPreferences.get_base_goals(HeroCatalog.KIT_SHADOW_ASSASSIN).size() > 0)
	_expect(failures, "ranger prefs", AIItemPreferences.get_base_goals(HeroCatalog.KIT_RANGER).size() > 0)

	var w_rank2: float = float(
		HeroAbilityStats.get_stat(
			HeroAbilityProgression.ABILITY_W,
			HeroAbilityStats.STAT_EFFECT,
			2,
			{},
			HeroCatalog.KIT_PALADIN
		)
	)
	_expect(failures, "paladin W rank2 2.4s", is_equal_approx(w_rank2, 2.4))
	var r_rank2: float = float(
		HeroAbilityStats.get_stat(
			HeroAbilityProgression.ABILITY_R,
			HeroAbilityStats.STAT_EFFECT,
			2,
			{},
			HeroCatalog.KIT_PALADIN
		)
	)
	_expect(failures, "paladin R rank2 30%", is_equal_approx(r_rank2, 0.30))
