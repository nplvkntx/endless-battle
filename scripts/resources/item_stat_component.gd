class_name ItemStatComponent
extends ItemComponent

## Optional modular mirror of flat item stats. HeroItemService still applies
## HeroItemDefinition.bonus_* today; this exists for future composition.

@export var bonus_attack_damage: int = 0
@export var bonus_max_health: int = 0
@export var heal_on_purchase: int = 0
@export var bonus_move_speed: float = 0.0
@export var bonus_max_mana: int = 0
@export var restore_mana_on_purchase: int = 0
@export var bonus_ability_power: int = 0
@export var bonus_cooldown_reduction: float = 0.0
@export var bonus_mana_cost_reduction: float = 0.0
@export var bonus_spell_radius: float = 0.0
@export var bonus_armor: float = 0.0


func get_kind() -> Kind:
	return Kind.STATS
