class_name HeroAbilityStats
extends RefCounted

## Per-rank stat scaling for hero abilities. Multipliers are indexed by rank (1 = index 0).

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
		STAT_DAMAGE: 35,
		STAT_SPLASH: 3.5,
		STAT_COOLDOWN: 9.0,
		STAT_MANA: 40,
	},
	HeroAbilityProgression.ABILITY_W: {
		STAT_EFFECT: 4.0,
		STAT_COOLDOWN: 20.0,
		STAT_MANA: 30,
	},
	HeroAbilityProgression.ABILITY_E: {
		STAT_DAMAGE: 45,
		STAT_COOLDOWN: 10.0,
		STAT_MANA: 25,
	},
	HeroAbilityProgression.ABILITY_R: {
		STAT_EFFECT: 0.4,
		STAT_COOLDOWN: 45.0,
		STAT_MANA: 50,
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
