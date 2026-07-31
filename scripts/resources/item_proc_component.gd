class_name ItemProcComponent
extends ItemComponent

## Chance-based / on-event proc metadata. Combat hooks come later.

@export var proc_id: StringName = &""
@export var proc_chance: float = 0.0
@export var internal_cooldown: float = 0.0
@export var on_attack: bool = false
@export var on_crit: bool = false
@export var on_ability_cast: bool = false
@export var on_damage_taken: bool = false
@export var on_kill: bool = false
@export var proc_buff: BuffDefinition
@export var proc_damage: float = 0.0
@export var proc_heal: float = 0.0


func get_kind() -> Kind:
	return Kind.PROC
