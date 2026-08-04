class_name HeroPassiveCatalog
extends RefCounted

## Builds hero innate passive definitions. Every future hero registers here.

const PASSIVE_HOLY_RECOVERY := &"holy_recovery"
const PASSIVE_ASSASSIN := &"assassin"
const PASSIVE_HUNTERS_PRECISION := &"hunters_precision"

const HOLY_RECOVERY_SCRIPT := "res://scripts/passives/holy_recovery_passive.gd"
const ASSASSIN_SCRIPT := "res://scripts/passives/assassin_passive.gd"
const RANGER_SCRIPT := "res://scripts/passives/ranger_passive.gd"

const HOLY_RECOVERY_DESCRIPTION := (
	"After not taking or dealing damage for 5 seconds, regenerate 1.5% of maximum HP per second. "
	+ "Entering combat immediately stops the regeneration."
)

const ASSASSIN_DESCRIPTION := (
	"Every consecutive basic attack against the same target deals bonus physical damage. "
	+ "Switching targets resets the passive."
)

const HUNTERS_PRECISION_DESCRIPTION := (
	"Every 3rd consecutive basic attack against the same target deals bonus Physical Damage "
	+ "equal to 8% of that target's Maximum Health (capped). Does not work on Buildings. "
	+ "Switching targets resets the counter."
)


static func create_holy_recovery() -> HeroPassiveDefinition:
	var definition: HeroPassiveDefinition = HeroPassiveDefinition.create(
		PASSIVE_HOLY_RECOVERY,
		"Holy Recovery",
		HOLY_RECOVERY_DESCRIPTION,
		HOLY_RECOVERY_SCRIPT,
		PASSIVE_HOLY_RECOVERY
	)
	definition.tracks_out_of_combat = true
	definition.out_of_combat_seconds = HeroPassiveStats.HOLY_RECOVERY_OUT_OF_COMBAT_SECONDS
	return definition


static func create_assassin() -> HeroPassiveDefinition:
	var definition: HeroPassiveDefinition = HeroPassiveDefinition.create(
		PASSIVE_ASSASSIN,
		"Assassin",
		ASSASSIN_DESCRIPTION,
		ASSASSIN_SCRIPT,
		PASSIVE_ASSASSIN
	)
	definition.tracks_basic_attacks = true
	definition.attacks_per_proc = 0
	return definition


static func create_ranger() -> HeroPassiveDefinition:
	var definition: HeroPassiveDefinition = HeroPassiveDefinition.create(
		PASSIVE_HUNTERS_PRECISION,
		"Hunter's Precision",
		HUNTERS_PRECISION_DESCRIPTION,
		RANGER_SCRIPT,
		PASSIVE_HUNTERS_PRECISION
	)
	definition.tracks_basic_attacks = true
	definition.attacks_per_proc = 0
	return definition


## Resolves the innate passive for a hero.
## Prefer hero.passive_definition (set per hero script/scene). Catalog fallback is for tooling only.
static func resolve_for_hero(hero: Hero) -> HeroPassiveDefinition:
	if hero == null:
		return null

	if hero.passive_definition != null:
		return hero.passive_definition

	return null


static func get_display_name(passive_id: StringName) -> String:
	match passive_id:
		PASSIVE_HOLY_RECOVERY:
			return "Holy Recovery"
		PASSIVE_ASSASSIN:
			return "Assassin"
		PASSIVE_HUNTERS_PRECISION:
			return "Hunter's Precision"
		_:
			return String(passive_id)


static func get_description(passive_id: StringName) -> String:
	match passive_id:
		PASSIVE_HOLY_RECOVERY:
			return HOLY_RECOVERY_DESCRIPTION
		PASSIVE_ASSASSIN:
			return ASSASSIN_DESCRIPTION
		PASSIVE_HUNTERS_PRECISION:
			return HUNTERS_PRECISION_DESCRIPTION
		_:
			return ""
