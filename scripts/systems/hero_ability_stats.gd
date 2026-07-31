class_name HeroAbilityStats
extends RefCounted

## Per-rank stat scaling for hero abilities. Multipliers are indexed by rank (1 = index 0).
## Attribute ratios (AP, AD, health, etc.) live in ABILITY_SCALING and are applied by Hero.

enum ScalingStat {
	ATTACK_DAMAGE,
	ABILITY_POWER,
	BONUS_HEALTH,
	MISSING_HEALTH,
	MAXIMUM_HEALTH,
	ARMOR,
	TARGET_HEALTH,
	HERO_LEVEL,
}

const STAT_DAMAGE := &"damage"
const STAT_SPLASH := &"splash"
const STAT_EFFECT := &"effect"
const STAT_COOLDOWN := &"cooldown"
const STAT_MANA := &"mana"

const ABILITY_DISPLAY_NAMES: Dictionary = {
	HeroAbilityProgression.ABILITY_Q: "Ground Slam",
	HeroAbilityProgression.ABILITY_W: "Divine Protection",
	HeroAbilityProgression.ABILITY_E: "Power Strike",
	HeroAbilityProgression.ABILITY_R: "Execute",
}

const DEFAULT_BASE_STATS: Dictionary = {
	HeroAbilityProgression.ABILITY_Q: {
		STAT_DAMAGE: HeroStats.GROUND_SLAM_DAMAGE,
		STAT_SPLASH: HeroStats.GROUND_SLAM_RADIUS,
		STAT_COOLDOWN: HeroStats.GROUND_SLAM_COOLDOWN,
		STAT_MANA: HeroStats.GROUND_SLAM_MANA_COST,
	},
	HeroAbilityProgression.ABILITY_W: {
		STAT_EFFECT: HeroStats.DIVINE_PROTECTION_DURATION,
		STAT_COOLDOWN: HeroStats.DIVINE_PROTECTION_COOLDOWN,
		STAT_MANA: HeroStats.DIVINE_PROTECTION_MANA_COST,
	},
	HeroAbilityProgression.ABILITY_E: {
		STAT_DAMAGE: HeroStats.POWER_STRIKE_DAMAGE,
		STAT_COOLDOWN: HeroStats.POWER_STRIKE_COOLDOWN,
		STAT_MANA: HeroStats.POWER_STRIKE_MANA_COST,
	},
	HeroAbilityProgression.ABILITY_R: {
		STAT_EFFECT: HeroStats.EXECUTE_HEALTH_THRESHOLD,
		STAT_COOLDOWN: HeroStats.EXECUTE_COOLDOWN,
		STAT_MANA: HeroStats.EXECUTE_MANA_COST,
	},
}

## ability_id -> output_stat -> { ScalingStat: coefficient }
## Current live ratios preserve flat AP behavior (Q/E +1 dmg/AP, W +0.01s/AP, R +0.001/AP).
const ABILITY_SCALING: Dictionary = {
	HeroAbilityProgression.ABILITY_Q: {
		STAT_DAMAGE: {
			ScalingStat.ABILITY_POWER: 1.0,
		},
	},
	HeroAbilityProgression.ABILITY_W: {
		STAT_EFFECT: {
			ScalingStat.ABILITY_POWER: HeroStats.ABILITY_POWER_EFFECT_SECONDS_PER_POINT,
		},
	},
	HeroAbilityProgression.ABILITY_E: {
		STAT_DAMAGE: {
			ScalingStat.ABILITY_POWER: 1.0,
		},
	},
	HeroAbilityProgression.ABILITY_R: {
		STAT_EFFECT: {
			ScalingStat.ABILITY_POWER: HeroStats.ABILITY_POWER_EXECUTE_THRESHOLD_PER_POINT,
		},
	},
}

const BASIC_DAMAGE_MULT: Array[float] = [1.0, 1.2, 1.4, 1.6, 1.8]
const BASIC_SPLASH_MULT: Array[float] = [1.0, 1.1, 1.2, 1.3, 1.4]
const BASIC_COOLDOWN_MULT: Array[float] = [1.0, 0.95, 0.9, 0.85, 0.8]
const BASIC_MANA_MULT: Array[float] = [1.0, 1.1, 1.2, 1.3, 1.4]
const BASIC_EFFECT_MULT: Array[float] = [1.0, 1.2, 1.4, 1.6, 1.8]

const ULTIMATE_EFFECT_MULT: Array[float] = [1.0, 1.2, 1.4]
const ULTIMATE_COOLDOWN_MULT: Array[float] = [1.0, 0.9, 0.8]
const ULTIMATE_MANA_MULT: Array[float] = [1.0, 1.2, 1.4]


static func get_display_name(ability_id: StringName) -> String:
	return String(ABILITY_DISPLAY_NAMES.get(ability_id, ability_id))


static func get_scaling_ratios(ability_id: StringName, stat: StringName) -> Dictionary:
	var by_ability: Dictionary = ABILITY_SCALING.get(ability_id, {})
	return by_ability.get(stat, {})


static func compute_scaling_bonus(ability_id: StringName, stat: StringName, resolved_values: Dictionary) -> float:
	var ratios: Dictionary = get_scaling_ratios(ability_id, stat)
	if ratios.is_empty():
		return 0.0

	var total: float = 0.0
	for scaling_stat: Variant in ratios.keys():
		var coefficient: float = float(ratios[scaling_stat])
		var resolved_value: float = float(resolved_values.get(scaling_stat, 0.0))
		total += coefficient * resolved_value

	return total


static func get_stat(
	ability_id: StringName, stat: StringName, rank: int, base_overrides: Dictionary = {}
) -> Variant:
	if rank <= 0:
		rank = 1

	match stat:
		STAT_DAMAGE:
			return _scale_int(
				_resolve_base(ability_id, STAT_DAMAGE, base_overrides),
				_multiplier_for(ability_id, BASIC_DAMAGE_MULT, ULTIMATE_EFFECT_MULT, rank)
			)
		STAT_SPLASH:
			return _scale_float(
				float(_resolve_base(ability_id, STAT_SPLASH, base_overrides)),
				_multiplier_at(BASIC_SPLASH_MULT, rank)
			)
		STAT_EFFECT:
			var base_effect: float = float(_resolve_base(ability_id, STAT_EFFECT, base_overrides))
			var effect_mult: float = _multiplier_for(
				ability_id, BASIC_EFFECT_MULT, ULTIMATE_EFFECT_MULT, rank
			)
			if ability_id == HeroAbilityProgression.ABILITY_R:
				return clampf(base_effect * effect_mult, 0.0, 0.75)
			return _scale_float(base_effect, effect_mult)
		STAT_COOLDOWN:
			return _scale_float(
				float(_resolve_base(ability_id, STAT_COOLDOWN, base_overrides)),
				_multiplier_for(ability_id, BASIC_COOLDOWN_MULT, ULTIMATE_COOLDOWN_MULT, rank)
			)
		STAT_MANA:
			return _scale_int(
				_resolve_base(ability_id, STAT_MANA, base_overrides),
				_multiplier_for(ability_id, BASIC_MANA_MULT, ULTIMATE_MANA_MULT, rank)
			)
		_:
			return _resolve_base(ability_id, stat, base_overrides)


static func format_tooltip(ability_id: StringName, rank: int, base_overrides: Dictionary = {}) -> String:
	if rank <= 0:
		return "%s\n(Locked — learn to view stats)" % get_display_name(ability_id)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s (Rank %d)" % [get_display_name(ability_id), rank])

	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			lines.append(
				"%d damage | %.1f radius"
				% [
					get_stat(ability_id, STAT_DAMAGE, rank, base_overrides),
					get_stat(ability_id, STAT_SPLASH, rank, base_overrides),
				]
			)
		HeroAbilityProgression.ABILITY_W:
			lines.append(
				"%.1fs invulnerability"
				% get_stat(ability_id, STAT_EFFECT, rank, base_overrides)
			)
		HeroAbilityProgression.ABILITY_E:
			lines.append(
				"%d damage" % get_stat(ability_id, STAT_DAMAGE, rank, base_overrides)
			)
		HeroAbilityProgression.ABILITY_R:
			var threshold: float = float(get_stat(ability_id, STAT_EFFECT, rank, base_overrides))
			lines.append("Execute below %d%% HP" % int(round(threshold * 100.0)))

	var cooldown: float = float(get_stat(ability_id, STAT_COOLDOWN, rank, base_overrides))
	var mana: int = int(get_stat(ability_id, STAT_MANA, rank, base_overrides))
	lines.append("CD: %.1fs | %d mana" % [cooldown, mana])

	return "\n".join(lines)


static func _resolve_base(
	ability_id: StringName, stat: StringName, base_overrides: Dictionary
) -> Variant:
	if base_overrides.has(stat):
		return base_overrides[stat]

	var ability_bases: Dictionary = DEFAULT_BASE_STATS.get(ability_id, {})
	return ability_bases.get(stat, 0)


static func _multiplier_for(
	ability_id: StringName,
	basic_multipliers: Array,
	ultimate_multipliers: Array,
	rank: int
) -> float:
	if ability_id == HeroAbilityProgression.ABILITY_R:
		return _multiplier_at(ultimate_multipliers, rank)

	return _multiplier_at(basic_multipliers, rank)


static func _multiplier_at(multipliers: Array, rank: int) -> float:
	var index: int = clampi(rank - 1, 0, multipliers.size() - 1)
	return float(multipliers[index])


static func _scale_int(base_value: Variant, multiplier: float) -> int:
	return maxi(1, int(round(float(base_value) * multiplier)))


static func _scale_float(base_value: float, multiplier: float) -> float:
	return base_value * multiplier
