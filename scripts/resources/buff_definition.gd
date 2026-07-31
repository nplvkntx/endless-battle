class_name BuffDefinition
extends Resource

## Data template for a buff or debuff. Runtime state lives on BuffInstance.

const INFINITE_DURATION := -1.0

enum StackRule {
	## Remove existing instances with the same buff_id, then apply fresh.
	REPLACE = 0,
	## Refresh remaining duration on the existing instance; keep stacks.
	REFRESH = 1,
	## Add stacks up to max_stacks; duration unchanged unless refresh_on_stack.
	STACK = 2,
	## Add stacks and refresh duration.
	STACK_REFRESH = 3,
	## If an instance with this buff_id exists, ignore the new apply.
	IGNORE = 4,
	## Always create a separate instance (same buff_id allowed).
	INDEPENDENT = 5,
}

@export var buff_id: StringName = &""
@export var display_name: String = ""
@export var is_debuff: bool = false

## Seconds. Use INFINITE_DURATION (-1) for permanent until removed.
@export var duration: float = 5.0
@export var stack_rule: StackRule = StackRule.REFRESH
@export var max_stacks: int = 1
## When stack_rule is STACK, also refresh duration on re-apply.
@export var refresh_on_stack: bool = false

# --- Stat modifiers (identity defaults — no effect until values change) ---
@export var move_speed_multiplier: float = 1.0
@export var move_speed_bonus: float = 0.0
@export var attack_damage_multiplier: float = 1.0
@export var attack_damage_bonus: float = 0.0
## Multiplies attack rate conceptually (1.2 = 20% faster). Consumers map to cooldown.
@export var attack_speed_multiplier: float = 1.0
@export var armor_bonus: float = 0.0
@export var armor_multiplier: float = 1.0
@export var damage_dealt_multiplier: float = 1.0
@export var damage_taken_multiplier: float = 1.0
@export var healing_dealt_multiplier: float = 1.0
@export var healing_received_multiplier: float = 1.0
## Additive cooldown reduction in 0..1 range (0.1 = 10% CDR).
@export var cooldown_reduction: float = 0.0

# --- Crowd control / flags ---
@export var grants_silence: bool = false
@export var grants_stun: bool = false
## Semantic slow tag; actual slow is usually move_speed_multiplier < 1.
@export var grants_slow: bool = false
@export var grants_root: bool = false
@export var grants_invulnerability: bool = false

# --- Periodic tick (period <= 0 disables) ---
@export var period: float = 0.0
@export var periodic_damage: float = 0.0
@export var periodic_heal: float = 0.0
## When true, periodic_damage uses DamageService.DamageType.TRUE.
@export var periodic_damage_is_true: bool = false


func is_infinite() -> bool:
	return duration < 0.0


static func create(buff_id: StringName, duration_seconds: float = 5.0) -> BuffDefinition:
	var definition := BuffDefinition.new()
	definition.buff_id = buff_id
	definition.duration = duration_seconds
	return definition
