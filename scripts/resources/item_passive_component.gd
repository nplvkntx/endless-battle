class_name ItemPassiveComponent
extends ItemComponent

## Always-on passive effect metadata. Gameplay hooks come later.

@export var passive_id: StringName = &""
## When true, only one copy of unique_key may be active on a hero.
@export var is_unique: bool = false
@export var unique_key: StringName = &""
## Optional buff applied while the item is equipped (unused until wired).
@export var equip_buff: BuffDefinition
@export var icon_hint: String = ""


func get_kind() -> Kind:
	if is_unique:
		return Kind.UNIQUE_PASSIVE
	return Kind.PASSIVE


func get_unique_key() -> StringName:
	if unique_key != &"":
		return unique_key
	if passive_id != &"":
		return passive_id
	return component_id
