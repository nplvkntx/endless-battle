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
	spawn_message(target, str(amount), Color(1.0, 0.85, 0.2, 1.0), emphasized)


static func spawn_message(
	target: Node3D,
	message: String,
	message_color: Color = Color(1.0, 0.85, 0.2, 1.0),
	emphasized: bool = false
) -> void:
	if not NodeSafety.is_alive_node(target):
		return

	spawn_message_at_position(
		target,
		message,
		target.global_position + Vector3(0.0, SPAWN_HEIGHT, 0.0),
		message_color,
		emphasized
	)


static func spawn_message_at_position(
	anchor: Node,
	message: String,
	world_position: Vector3,
	message_color: Color = Color(1.0, 0.85, 0.2, 1.0),
	emphasized: bool = false
) -> void:
	if not NodeSafety.is_alive_node(anchor):
		return

	var tree: SceneTree = anchor.get_tree()
	if tree == null or tree.current_scene == null:
		return

	var instance: FloatingDamageNumber = SCENE.instantiate() as FloatingDamageNumber
	tree.current_scene.add_child(instance)
	instance._play(message, world_position, emphasized, message_color)


func _play(
	damage_text: String,
	start_position: Vector3,
	emphasized: bool = false,
	message_color: Color = Color(1.0, 0.85, 0.2, 1.0)
) -> void:
	text = damage_text
	global_position = start_position
	modulate.a = 1.0

	if emphasized:
		font_size = EMPHASIZED_FONT_SIZE
		modulate = message_color.lightened(0.15)
	else:
		font_size = NORMAL_FONT_SIZE
		modulate = message_color

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
