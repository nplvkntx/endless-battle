class_name FloatingDamageNumber
extends Label3D

## Simple placeholder damage number that floats upward and fades out.

const SCENE: PackedScene = preload("res://scenes/ui/floating_damage_number.tscn")
const FLOAT_DISTANCE := 1.2
const EMPHASIZED_FLOAT_DISTANCE := 1.6
const DURATION := 0.75
const EMPHASIZED_DURATION := 0.9
const SPAWN_HEIGHT := 1.25
const NORMAL_FONT_SIZE := 48
const EMPHASIZED_FONT_SIZE := 72

static func spawn(target: Node3D, amount: int, emphasized: bool = false) -> void:
	if not is_instance_valid(target):
		return

	var instance: FloatingDamageNumber = SCENE.instantiate() as FloatingDamageNumber
	target.get_tree().current_scene.add_child(instance)
	instance._play(
		str(amount),
		target.global_position + Vector3(0.0, SPAWN_HEIGHT, 0.0),
		emphasized
	)


func _play(damage_text: String, start_position: Vector3, emphasized: bool = false) -> void:
	text = damage_text
	global_position = start_position
	modulate.a = 1.0

	if emphasized:
		font_size = EMPHASIZED_FONT_SIZE
		modulate = Color(1.0, 0.55, 0.15, 1.0)
	else:
		font_size = NORMAL_FONT_SIZE
		modulate = Color(1.0, 0.85, 0.2, 1.0)

	var float_distance: float = EMPHASIZED_FLOAT_DISTANCE if emphasized else FLOAT_DISTANCE
	var duration: float = EMPHASIZED_DURATION if emphasized else DURATION

	var end_position: Vector3 = start_position + Vector3(0.0, float_distance, 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", end_position, duration).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)
