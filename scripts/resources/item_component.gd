class_name ItemComponent
extends Resource

## Modular item effect piece. Attach via HeroItemDefinition.components.
## Existing flat bonus_* fields remain the live stat path until migrated.

enum Kind {
	STATS = 0,
	PASSIVE = 1,
	ACTIVE = 2,
	AURA = 3,
	PROC = 4,
	UNIQUE_PASSIVE = 5,
}

@export var component_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""


func get_kind() -> Kind:
	return Kind.STATS
