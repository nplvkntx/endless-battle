class_name HeroPassiveCatalog
extends RefCounted

## Builds hero innate passive definitions. Every future hero registers here.

const PASSIVE_HOLY_RECOVERY := &"holy_recovery"

const HOLY_RECOVERY_SCRIPT := "res://scripts/passives/holy_recovery_passive.gd"

const HOLY_RECOVERY_DESCRIPTION := (
	"After not taking or dealing damage for 5 seconds, regenerate 2% of maximum HP per second. "
	+ "Entering combat immediately stops the regeneration."
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
		_:
			return String(passive_id)


static func get_description(passive_id: StringName) -> String:
	match passive_id:
		PASSIVE_HOLY_RECOVERY:
			return HOLY_RECOVERY_DESCRIPTION
		_:
			return ""
