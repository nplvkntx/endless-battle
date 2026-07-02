class_name HeroItemDefinition
extends Resource

## Data for a hero shop item. Extend with recipes, actives, and passives later.

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var gold_cost: int = 0
@export var hotkey: String = ""
@export var icon_color: Color = Color(0.55, 0.58, 0.65, 1)

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

@export var is_consumable: bool = false
@export var is_active_item: bool = false
