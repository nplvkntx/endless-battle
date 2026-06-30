class_name MeleeHitSound
extends RefCounted

## Plays a short placeholder sound for successful melee hits.

const HIT_SOUND: AudioStream = preload("res://assets/audio/hit.wav")
const VOLUME_DB: float = 2.0


static func play_at(parent: Node, _world_position: Vector3 = Vector3.ZERO) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var tree := parent.get_tree()
	if tree == null:
		return

	var player := AudioStreamPlayer.new()
	player.stream = HIT_SOUND
	player.volume_db = VOLUME_DB
	tree.root.add_child(player)
	player.play()
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
