class_name HeroAbilityStats
extends RefCounted

## Per-rank stat scaling for hero abilities. Multipliers are indexed by rank (1 = index 0).
## Attribute ratios live in KIT_ABILITY_SCALING and are applied by Hero.
## Lookups are kit-aware so Paladin and Shadow Assassin can share QWER slots.

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
const STAT_RANGE := &"range"
const STAT_BONUS_DAMAGE := &"bonus_damage"
const STAT_MANA_REFUND := &"mana_refund"

const KIT_ABILITY_DISPLAY_NAMES: Dictionary = {
	HeroCatalog.KIT_PALADIN: {
		HeroAbilityProgression.ABILITY_Q: "Ground Slam",
		HeroAbilityProgression.ABILITY_W: "Divine Protection",
		HeroAbilityProgression.ABILITY_E: "Power Strike",
		HeroAbilityProgression.ABILITY_R: "Execute",
	},
	HeroCatalog.KIT_SHADOW_ASSASSIN: {
		HeroAbilityProgression.ABILITY_Q: "Axe Mark",
		HeroAbilityProgression.ABILITY_W: "Smoke",
		HeroAbilityProgression.ABILITY_E: "Slash",
		HeroAbilityProgression.ABILITY_R: "Dash",
	},
	HeroCatalog.KIT_RANGER: {
		HeroAbilityProgression.ABILITY_Q: "Combat Roll",
		HeroAbilityProgression.ABILITY_W: "Bear Trap",
		HeroAbilityProgression.ABILITY_E: "Crossbow Bolt",
		HeroAbilityProgression.ABILITY_R: "Camouflage",
	},
}

const KIT_DEFAULT_BASE_STATS: Dictionary = {
	HeroCatalog.KIT_PALADIN: {
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
	},
	HeroCatalog.KIT_SHADOW_ASSASSIN: {
		HeroAbilityProgression.ABILITY_Q: {
			STAT_DAMAGE: ShadowAssassinStats.AXE_MARK_DAMAGE,
			STAT_BONUS_DAMAGE: ShadowAssassinStats.AXE_MARK_BONUS_ON_CONSUME,
			STAT_EFFECT: ShadowAssassinStats.AXE_MARK_DURATION,
			STAT_RANGE: ShadowAssassinStats.AXE_MARK_RANGE,
			STAT_MANA_REFUND: ShadowAssassinStats.AXE_MARK_MANA_REFUND_RATIO,
			STAT_COOLDOWN: ShadowAssassinStats.AXE_MARK_COOLDOWN,
			STAT_MANA: ShadowAssassinStats.AXE_MARK_MANA_COST,
		},
		HeroAbilityProgression.ABILITY_W: {
			STAT_EFFECT: ShadowAssassinStats.SMOKE_DURATION,
			STAT_SPLASH: ShadowAssassinStats.SMOKE_RADIUS,
			STAT_COOLDOWN: ShadowAssassinStats.SMOKE_COOLDOWN,
			STAT_MANA: ShadowAssassinStats.SMOKE_MANA_COST,
		},
		HeroAbilityProgression.ABILITY_E: {
			STAT_DAMAGE: ShadowAssassinStats.SLASH_DAMAGE,
			STAT_SPLASH: ShadowAssassinStats.SLASH_RADIUS,
			STAT_COOLDOWN: ShadowAssassinStats.SLASH_COOLDOWN,
			STAT_MANA: ShadowAssassinStats.SLASH_MANA_COST,
		},
		HeroAbilityProgression.ABILITY_R: {
			STAT_DAMAGE: ShadowAssassinStats.DASH_DAMAGE,
			STAT_RANGE: ShadowAssassinStats.DASH_RANGE,
			STAT_COOLDOWN: ShadowAssassinStats.DASH_COOLDOWN,
			STAT_MANA: ShadowAssassinStats.DASH_MANA_COST,
		},
	},
	HeroCatalog.KIT_RANGER: {
		HeroAbilityProgression.ABILITY_Q: {
			STAT_RANGE: RangerStats.COMBAT_ROLL_DISTANCE,
			STAT_COOLDOWN: RangerStats.COMBAT_ROLL_COOLDOWN,
			STAT_MANA: RangerStats.COMBAT_ROLL_MANA_COST,
		},
		HeroAbilityProgression.ABILITY_W: {
			STAT_DAMAGE: RangerStats.BEAR_TRAP_DAMAGE,
			STAT_EFFECT: RangerStats.BEAR_TRAP_ROOT_DURATION,
			STAT_RANGE: RangerStats.BEAR_TRAP_PLACE_RANGE,
			STAT_COOLDOWN: RangerStats.BEAR_TRAP_COOLDOWN,
			STAT_MANA: RangerStats.BEAR_TRAP_MANA_COST,
		},
		HeroAbilityProgression.ABILITY_E: {
			STAT_DAMAGE: RangerStats.CROSSBOW_BOLT_DAMAGE,
			STAT_RANGE: RangerStats.CROSSBOW_BOLT_RANGE,
			STAT_COOLDOWN: RangerStats.CROSSBOW_BOLT_COOLDOWN,
			STAT_MANA: RangerStats.CROSSBOW_BOLT_MANA_COST,
		},
		HeroAbilityProgression.ABILITY_R: {
			STAT_EFFECT: RangerStats.CAMOUFLAGE_DURATION_RANK_1,
			STAT_COOLDOWN: RangerStats.CAMOUFLAGE_COOLDOWN,
			STAT_MANA: RangerStats.CAMOUFLAGE_MANA_COST,
		},
	},
}

## kit -> ability_id -> output_stat -> { ScalingStat: coefficient }
const KIT_ABILITY_SCALING: Dictionary = {
	HeroCatalog.KIT_PALADIN: {
		HeroAbilityProgression.ABILITY_Q: {
			STAT_DAMAGE: {ScalingStat.ABILITY_POWER: 1.0},
		},
		HeroAbilityProgression.ABILITY_W: {
			STAT_EFFECT: {
				ScalingStat.ABILITY_POWER: HeroStats.ABILITY_POWER_EFFECT_SECONDS_PER_POINT,
			},
		},
		HeroAbilityProgression.ABILITY_E: {
			STAT_DAMAGE: {ScalingStat.ABILITY_POWER: 1.0},
		},
		HeroAbilityProgression.ABILITY_R: {
			STAT_EFFECT: {
				ScalingStat.ABILITY_POWER: HeroStats.ABILITY_POWER_EXECUTE_THRESHOLD_PER_POINT,
			},
		},
	},
	HeroCatalog.KIT_SHADOW_ASSASSIN: {
		HeroAbilityProgression.ABILITY_Q: {
			STAT_DAMAGE: {ScalingStat.ABILITY_POWER: 0.8, ScalingStat.ATTACK_DAMAGE: 0.35},
			STAT_BONUS_DAMAGE: {ScalingStat.ABILITY_POWER: 0.6, ScalingStat.ATTACK_DAMAGE: 0.5},
		},
		HeroAbilityProgression.ABILITY_W: {
			STAT_EFFECT: {ScalingStat.ABILITY_POWER: 0.01},
		},
		HeroAbilityProgression.ABILITY_E: {
			STAT_DAMAGE: {ScalingStat.ABILITY_POWER: 0.9, ScalingStat.ATTACK_DAMAGE: 0.4},
		},
		HeroAbilityProgression.ABILITY_R: {
			STAT_DAMAGE: {ScalingStat.ABILITY_POWER: 1.0, ScalingStat.ATTACK_DAMAGE: 0.55},
		},
	},
	HeroCatalog.KIT_RANGER: {
		HeroAbilityProgression.ABILITY_Q: {},
		HeroAbilityProgression.ABILITY_W: {
			STAT_DAMAGE: {ScalingStat.ABILITY_POWER: 0.4, ScalingStat.ATTACK_DAMAGE: 0.2},
			STAT_EFFECT: {ScalingStat.ABILITY_POWER: 0.01},
		},
		HeroAbilityProgression.ABILITY_E: {
			STAT_DAMAGE: {ScalingStat.ABILITY_POWER: 0.85, ScalingStat.ATTACK_DAMAGE: 0.55},
		},
		HeroAbilityProgression.ABILITY_R: {
			STAT_EFFECT: {ScalingStat.ABILITY_POWER: 0.01},
		},
	},
}

const BASIC_DAMAGE_MULT: Array[float] = [1.0, 1.2, 1.4, 1.6, 1.8]
const BASIC_SPLASH_MULT: Array[float] = [1.0, 1.1, 1.2, 1.3, 1.4]
const BASIC_COOLDOWN_MULT: Array[float] = [1.0, 0.95, 0.9, 0.85, 0.8]
const BASIC_MANA_MULT: Array[float] = [1.0, 1.1, 1.2, 1.3, 1.4]
const BASIC_EFFECT_MULT: Array[float] = [1.0, 1.2, 1.4, 1.6, 1.8]
const BASIC_RANGE_MULT: Array[float] = [1.0, 1.05, 1.1, 1.15, 1.2]

const ULTIMATE_EFFECT_MULT: Array[float] = [1.0, 1.2, 1.4]
const ULTIMATE_DAMAGE_MULT: Array[float] = [1.0, 1.2, 1.4]
const ULTIMATE_COOLDOWN_MULT: Array[float] = [1.0, 0.9, 0.8]
const ULTIMATE_MANA_MULT: Array[float] = [1.0, 1.2, 1.4]

## Backward-compatible aliases (Paladin defaults).
const ABILITY_DISPLAY_NAMES: Dictionary = {
	HeroAbilityProgression.ABILITY_Q: "Ground Slam",
	HeroAbilityProgression.ABILITY_W: "Divine Protection",
	HeroAbilityProgression.ABILITY_E: "Power Strike",
	HeroAbilityProgression.ABILITY_R: "Execute",
}
const DEFAULT_BASE_STATS: Dictionary = {}
const ABILITY_SCALING: Dictionary = {}


static func get_display_name(ability_id: StringName, kit_id: StringName = HeroCatalog.KIT_PALADIN) -> String:
	var by_kit: Dictionary = KIT_ABILITY_DISPLAY_NAMES.get(kit_id, {})
	if by_kit.has(ability_id):
		return String(by_kit[ability_id])
	return String(ABILITY_DISPLAY_NAMES.get(ability_id, ability_id))


static func get_scaling_ratios(
	ability_id: StringName, stat: StringName, kit_id: StringName = HeroCatalog.KIT_PALADIN
) -> Dictionary:
	var by_kit: Dictionary = KIT_ABILITY_SCALING.get(kit_id, {})
	var by_ability: Dictionary = by_kit.get(ability_id, {})
	return by_ability.get(stat, {})


static func compute_scaling_bonus(
	ability_id: StringName,
	stat: StringName,
	resolved_values: Dictionary,
	kit_id: StringName = HeroCatalog.KIT_PALADIN
) -> float:
	var ratios: Dictionary = get_scaling_ratios(ability_id, stat, kit_id)
	if ratios.is_empty():
		return 0.0

	var total: float = 0.0
	for scaling_stat: Variant in ratios.keys():
		var coefficient: float = float(ratios[scaling_stat])
		var resolved_value: float = float(resolved_values.get(scaling_stat, 0.0))
		total += coefficient * resolved_value

	return total


static func get_stat(
	ability_id: StringName,
	stat: StringName,
	rank: int,
	base_overrides: Dictionary = {},
	kit_id: StringName = HeroCatalog.KIT_PALADIN
) -> Variant:
	if rank <= 0:
		rank = 1

	match stat:
		STAT_DAMAGE, STAT_BONUS_DAMAGE:
			return _scale_int(
				_resolve_base(kit_id, ability_id, stat, base_overrides),
				_multiplier_for(kit_id, ability_id, BASIC_DAMAGE_MULT, ULTIMATE_DAMAGE_MULT, rank)
			)
		STAT_SPLASH:
			return _scale_float(
				float(_resolve_base(kit_id, ability_id, STAT_SPLASH, base_overrides)),
				_multiplier_at(BASIC_SPLASH_MULT, rank)
			)
		STAT_RANGE:
			return _scale_float(
				float(_resolve_base(kit_id, ability_id, STAT_RANGE, base_overrides)),
				_multiplier_at(BASIC_RANGE_MULT, rank)
			)
		STAT_EFFECT:
			# Ranger Camouflage uses explicit per-rank durations (12 / 18 / 24).
			if kit_id == HeroCatalog.KIT_RANGER and ability_id == HeroAbilityProgression.ABILITY_R:
				return RangerStats.get_camouflage_duration(rank)
			var base_effect: float = float(_resolve_base(kit_id, ability_id, STAT_EFFECT, base_overrides))
			var effect_mult: float = _multiplier_for(
				kit_id, ability_id, BASIC_EFFECT_MULT, ULTIMATE_EFFECT_MULT, rank
			)
			if (
				kit_id == HeroCatalog.KIT_PALADIN
				and ability_id == HeroAbilityProgression.ABILITY_R
			):
				return clampf(base_effect * effect_mult, 0.0, 0.75)
			return _scale_float(base_effect, effect_mult)
		STAT_COOLDOWN:
			return _scale_float(
				float(_resolve_base(kit_id, ability_id, STAT_COOLDOWN, base_overrides)),
				_multiplier_for(kit_id, ability_id, BASIC_COOLDOWN_MULT, ULTIMATE_COOLDOWN_MULT, rank)
			)
		STAT_MANA:
			return _scale_int(
				_resolve_base(kit_id, ability_id, STAT_MANA, base_overrides),
				_multiplier_for(kit_id, ability_id, BASIC_MANA_MULT, ULTIMATE_MANA_MULT, rank)
			)
		STAT_MANA_REFUND:
			return float(_resolve_base(kit_id, ability_id, STAT_MANA_REFUND, base_overrides))
		_:
			return _resolve_base(kit_id, ability_id, stat, base_overrides)


static func format_tooltip(
	ability_id: StringName,
	rank: int,
	base_overrides: Dictionary = {},
	kit_id: StringName = HeroCatalog.KIT_PALADIN
) -> String:
	if rank <= 0:
		return "%s\n(Locked — learn to view stats)" % get_display_name(ability_id, kit_id)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s (Rank %d)" % [get_display_name(ability_id, kit_id), rank])

	if kit_id == HeroCatalog.KIT_SHADOW_ASSASSIN:
		_format_assassin_tooltip_lines(lines, ability_id, rank, base_overrides)
	elif kit_id == HeroCatalog.KIT_RANGER:
		_format_ranger_tooltip_lines(lines, ability_id, rank, base_overrides)
	else:
		_format_paladin_tooltip_lines(lines, ability_id, rank, base_overrides)

	var cooldown: float = float(get_stat(ability_id, STAT_COOLDOWN, rank, base_overrides, kit_id))
	var mana: int = int(get_stat(ability_id, STAT_MANA, rank, base_overrides, kit_id))
	lines.append("CD: %.1fs | %d mana" % [cooldown, mana])

	return "\n".join(lines)


static func _format_paladin_tooltip_lines(
	lines: PackedStringArray, ability_id: StringName, rank: int, base_overrides: Dictionary
) -> void:
	var kit_id: StringName = HeroCatalog.KIT_PALADIN
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			lines.append(
				"%d damage | %.1f radius"
				% [
					get_stat(ability_id, STAT_DAMAGE, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_SPLASH, rank, base_overrides, kit_id),
				]
			)
		HeroAbilityProgression.ABILITY_W:
			lines.append(
				"%.1fs invulnerability"
				% get_stat(ability_id, STAT_EFFECT, rank, base_overrides, kit_id)
			)
		HeroAbilityProgression.ABILITY_E:
			lines.append(
				"%d damage" % get_stat(ability_id, STAT_DAMAGE, rank, base_overrides, kit_id)
			)
		HeroAbilityProgression.ABILITY_R:
			var threshold: float = float(
				get_stat(ability_id, STAT_EFFECT, rank, base_overrides, kit_id)
			)
			lines.append("Execute below %d%% HP" % int(round(threshold * 100.0)))


static func _format_assassin_tooltip_lines(
	lines: PackedStringArray, ability_id: StringName, rank: int, base_overrides: Dictionary
) -> void:
	var kit_id: StringName = HeroCatalog.KIT_SHADOW_ASSASSIN
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			lines.append(
				"%d damage | mark %.1fs | consume +%d"
				% [
					get_stat(ability_id, STAT_DAMAGE, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_EFFECT, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_BONUS_DAMAGE, rank, base_overrides, kit_id),
				]
			)
		HeroAbilityProgression.ABILITY_W:
			lines.append(
				"%.1fs smoke | %.1f radius"
				% [
					get_stat(ability_id, STAT_EFFECT, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_SPLASH, rank, base_overrides, kit_id),
				]
			)
		HeroAbilityProgression.ABILITY_E:
			lines.append(
				"%d damage | %.1f radius"
				% [
					get_stat(ability_id, STAT_DAMAGE, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_SPLASH, rank, base_overrides, kit_id),
				]
			)
		HeroAbilityProgression.ABILITY_R:
			lines.append(
				"%d damage | %.1f range"
				% [
					get_stat(ability_id, STAT_DAMAGE, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_RANGE, rank, base_overrides, kit_id),
				]
			)


static func _format_ranger_tooltip_lines(
	lines: PackedStringArray, ability_id: StringName, rank: int, base_overrides: Dictionary
) -> void:
	var kit_id: StringName = HeroCatalog.KIT_RANGER
	match ability_id:
		HeroAbilityProgression.ABILITY_Q:
			lines.append(
				"Dash %.1f range"
				% get_stat(ability_id, STAT_RANGE, rank, base_overrides, kit_id)
			)
		HeroAbilityProgression.ABILITY_W:
			lines.append(
				"%d damage | root %.1fs | %d charges"
				% [
					get_stat(ability_id, STAT_DAMAGE, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_EFFECT, rank, base_overrides, kit_id),
					RangerStats.BEAR_TRAP_MAX_CHARGES,
				]
			)
		HeroAbilityProgression.ABILITY_E:
			lines.append(
				"%d damage | %.1f range | pierces"
				% [
					get_stat(ability_id, STAT_DAMAGE, rank, base_overrides, kit_id),
					get_stat(ability_id, STAT_RANGE, rank, base_overrides, kit_id),
				]
			)
		HeroAbilityProgression.ABILITY_R:
			lines.append(
				"Camouflage %.1fs | +%.1f move speed"
				% [
					get_stat(ability_id, STAT_EFFECT, rank, base_overrides, kit_id),
					RangerStats.CAMOUFLAGE_MOVE_SPEED_BONUS,
				]
			)


static func _resolve_base(
	kit_id: StringName, ability_id: StringName, stat: StringName, base_overrides: Dictionary
) -> Variant:
	if base_overrides.has(stat):
		return base_overrides[stat]

	var kit_bases: Dictionary = KIT_DEFAULT_BASE_STATS.get(kit_id, {})
	var ability_bases: Dictionary = kit_bases.get(ability_id, {})
	if ability_bases.has(stat):
		return ability_bases[stat]

	# Legacy paladin fallback for tooling that still reads DEFAULT_BASE_STATS shape.
	if kit_id == HeroCatalog.KIT_PALADIN:
		var legacy: Dictionary = {
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
		return legacy.get(ability_id, {}).get(stat, 0)

	return 0


static func _multiplier_for(
	kit_id: StringName,
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
