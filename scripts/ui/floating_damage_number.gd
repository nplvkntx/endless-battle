class_name FloatingDamageNumber
extends Label3D

## Simple placeholder damage number that floats upward and fades out.

const SCENE: PackedScene = preload("res://scenes/ui/floating_damage_number.tscn")
const FLOAT_DISTANCE := 1.2
const DURATION := 0.75
const SPAWN_HEIGHT := 1.25

static func spawn(target: Node3D, amount: int) -> void:
	if not is_instance_valid(target):
		return

	var instance: FloatingDamageNumber = SCENE.instantiate() as FloatingDamageNumber
	target.get_tree().current_scene.add_child(instance)
	instance._play(str(amount), target.global_position + Vector3(0.0, SPAWN_HEIGHT, 0.0))


func _play(damage_text: String, start_position: Vector3) -> void:
	text = damage_text
	global_position = start_position
	modulate.a = 1.0

	var end_position: Vector3 = start_position + Vector3(0.0, FLOAT_DISTANCE, 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", end_position, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(self, "modulate:a", 0.0, DURATION).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)
