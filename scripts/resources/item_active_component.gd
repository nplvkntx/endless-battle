class_name ItemActiveComponent
extends ItemComponent

## Activatable item ability metadata. Runtime cooldowns/charges live on HeroItemRuntime.

@export var active_id: StringName = &""
@export var cooldown: float = 0.0
## 0 = no charge system (simple cooldown). >0 enables charges.
@export var max_charges: int = 0
## -1 = start at max_charges when charges are enabled.
@export var starting_charges: int = -1
@export var mana_cost: int = 0
@export var gold_cost_per_use: int = 0
## Optional buff granted on activation (unused until wired).
@export var activation_buff: BuffDefinition
@export var activation_buff_duration: float = NAN


func get_kind() -> Kind:
	return Kind.ACTIVE


func uses_charges() -> bool:
	return max_charges > 0


func get_starting_charges() -> int:
	if not uses_charges():
		return 0
	if starting_charges < 0:
		return max_charges
	return clampi(starting_charges, 0, max_charges)
