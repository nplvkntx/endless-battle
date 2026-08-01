class_name HeroAbilityDefinition
extends RefCounted

## Data describing how a hero ability is targeted and previewed.
## Execution damage stays in kit scripts; this only drives player targeting UX.

enum TargetingType {
	INSTANT_SELF,
	NO_TARGET,
	TARGET_ENEMY,
	TARGET_ALLY,
	TARGET_UNIT,
	TARGET_GROUND,
	DIRECTIONAL_LINE,
	CIRCULAR_AREA,
	CIRCULAR_SELF,
	CONE,
	DASH_DIRECTION,
	DASH_TARGET,
}

## Future settings hook — controller reads GameSettings / this default.
enum CastMode {
	NORMAL,
	QUICK,
	QUICK_WITH_INDICATOR,
}

var ability_id: StringName = &""
var targeting_type: TargetingType = TargetingType.NO_TARGET
var cast_range: float = 0.0
var effect_radius: float = 0.0
var line_width: float = 0.0
var cone_angle_degrees: float = 0.0
var max_travel_distance: float = 0.0
var allows_move_to_cast: bool = true
var terrain_blocks: bool = false
var units_block: bool = false
var can_target_buildings: bool = false
var can_target_creeps: bool = true
var can_target_allies: bool = false
var can_target_enemies: bool = true
var requires_living_target: bool = true
var pierces_units: bool = false
var clamps_ground_to_range: bool = true
var show_cast_range: bool = true


static func make(
	p_ability_id: StringName,
	p_type: TargetingType,
	p_cast_range: float = 0.0
) -> HeroAbilityDefinition:
	var def := HeroAbilityDefinition.new()
	def.ability_id = p_ability_id
	def.targeting_type = p_type
	def.cast_range = p_cast_range
	return def


func is_instant_cast() -> bool:
	return (
		targeting_type == TargetingType.INSTANT_SELF
		or targeting_type == TargetingType.NO_TARGET
	)


func is_unit_targeted() -> bool:
	return (
		targeting_type == TargetingType.TARGET_ENEMY
		or targeting_type == TargetingType.TARGET_ALLY
		or targeting_type == TargetingType.TARGET_UNIT
		or targeting_type == TargetingType.DASH_TARGET
	)


func is_ground_targeted() -> bool:
	return (
		targeting_type == TargetingType.TARGET_GROUND
		or targeting_type == TargetingType.CIRCULAR_AREA
		or targeting_type == TargetingType.DASH_DIRECTION
		or targeting_type == TargetingType.DIRECTIONAL_LINE
		or targeting_type == TargetingType.CONE
	)


func uses_direction_preview() -> bool:
	return (
		targeting_type == TargetingType.DIRECTIONAL_LINE
		or targeting_type == TargetingType.DASH_DIRECTION
		or targeting_type == TargetingType.CONE
	)
