class_name ConstructionStageSet
extends Resource

## Ordered construction stage models for a building type.
## Indices map to progress thresholds:
##   0 → 0%,  1 → 25%,  2 → 50%,  3 → 75%,  4 → 100% (finished)
## Leave a slot empty to use the temporary reveal/placeholder for that stage.
## Leave stage 4 empty (recommended) so the scene's authored Visuals are restored.

const STAGE_COUNT := 5

@export var stage_0_scene: PackedScene
@export var stage_1_scene: PackedScene
@export var stage_2_scene: PackedScene
@export var stage_3_scene: PackedScene
@export var stage_4_scene: PackedScene

## Shared local transform applied to instantiated stage models under Visuals.
@export var stage_model_transform: Transform3D = Transform3D.IDENTITY


func get_stage_scene(stage_index: int) -> PackedScene:
	match clampi(stage_index, 0, STAGE_COUNT - 1):
		0:
			return stage_0_scene
		1:
			return stage_1_scene
		2:
			return stage_2_scene
		3:
			return stage_3_scene
		4:
			return stage_4_scene
		_:
			return null


func has_any_stage_scene() -> bool:
	for stage_index: int in STAGE_COUNT:
		if get_stage_scene(stage_index) != null:
			return true
	return false


func set_stage_scene(stage_index: int, scene: PackedScene) -> void:
	match clampi(stage_index, 0, STAGE_COUNT - 1):
		0:
			stage_0_scene = scene
		1:
			stage_1_scene = scene
		2:
			stage_2_scene = scene
		3:
			stage_3_scene = scene
		4:
			stage_4_scene = scene
