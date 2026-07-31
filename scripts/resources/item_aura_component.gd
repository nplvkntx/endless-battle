class_name ItemAuraComponent
extends ItemComponent

## Aura item metadata. Radius / targeting only — no tick logic until wired.

@export var aura_id: StringName = &""
@export var radius: float = 0.0
@export var affects_allies: bool = true
@export var affects_enemies: bool = false
@export var affects_self: bool = true
@export var aura_buff: BuffDefinition
@export var tick_interval: float = 0.5


func get_kind() -> Kind:
	return Kind.AURA
