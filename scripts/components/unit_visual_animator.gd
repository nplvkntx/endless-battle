class_name UnitVisualAnimator
extends RefCounted

## Drives imported skeletal clips on a unit model. Visual-only; gameplay stays authoritative.

enum LoopState {
	IDLE,
	MOVE,
	WORK,
}

const STATE_IDLE: StringName = &"idle"
const STATE_MOVE: StringName = &"move"
const STATE_WORK: StringName = &"work"
const STATE_ATTACK: StringName = &"attack"

const DEFAULT_CLIP_PREFERENCES: Dictionary = {
	STATE_IDLE: [&"Idle"],
	STATE_MOVE: [&"Walk", &"Run", &"Run_Weapon", &"Run_Holding"],
	STATE_WORK: [&"PickUp", &"Work", &"Gather", &"Chop", &"Mine", &"Construct"],
	STATE_ATTACK: [
		&"Sword_Attack",
		&"Sword_Attack2",
		&"Bow_Shoot",
		&"Bow_Draw",
		&"Punch",
	],
}

var _animation_player: AnimationPlayer
var _clip_preferences: Dictionary = DEFAULT_CLIP_PREFERENCES.duplicate(true)
var _resolved_clips: Dictionary = {}
var _available_clips: PackedStringArray = PackedStringArray()
var _current_loop_state: LoopState = LoopState.IDLE
var _current_playing_clip: StringName = &""
var _one_shot_active: bool = false


static func create_from_model_root(model_root: Node) -> UnitVisualAnimator:
	if model_root == null or not is_instance_valid(model_root):
		return null

	var animation_player: AnimationPlayer = _find_animation_player(model_root)
	if animation_player == null:
		return null

	var animator := UnitVisualAnimator.new()
	animator._animation_player = animation_player
	animator._available_clips = animator._collect_animation_names()
	if animator._available_clips.is_empty():
		animator.release()
		return null

	if not animation_player.animation_finished.is_connected(animator._on_animation_finished):
		animation_player.animation_finished.connect(animator._on_animation_finished)

	return animator


static func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null or not is_instance_valid(root):
		return null

	if root is AnimationPlayer:
		return root as AnimationPlayer

	for child_variant: Variant in root.get_children():
		if child_variant == null or not is_instance_valid(child_variant):
			continue
		if not child_variant is Node:
			continue

		var found: AnimationPlayer = _find_animation_player(child_variant as Node)
		if found != null:
			return found

	return null


func release() -> void:
	if _animation_player != null and is_instance_valid(_animation_player):
		if _animation_player.animation_finished.is_connected(_on_animation_finished):
			_animation_player.animation_finished.disconnect(_on_animation_finished)

	_animation_player = null
	_one_shot_active = false
	_current_playing_clip = &""


func _clear_animation_player_if_stale() -> bool:
	if _animation_player == null:
		return false

	if is_instance_valid(_animation_player):
		return true

	release()
	return false


func set_clip_preferences(preferences: Dictionary) -> void:
	for state_key: StringName in preferences.keys():
		_clip_preferences[state_key] = preferences[state_key]
	_resolved_clips.clear()


func get_available_clips() -> PackedStringArray:
	return _available_clips


func has_animation_player() -> bool:
	return _animation_player != null and is_instance_valid(_animation_player)


func has_clip_for_state(state_key: StringName) -> bool:
	return not _resolve_clip(state_key).is_empty()


func play_initial_idle() -> void:
	if not _clear_animation_player_if_stale():
		return

	_current_loop_state = LoopState.IDLE
	_apply_loop_state(LoopState.IDLE, true)


func set_loop_state(new_state: LoopState) -> void:
	if not _clear_animation_player_if_stale():
		return

	if _current_loop_state == new_state and not _one_shot_active:
		_refresh_loop_clip_if_needed(new_state)
		return

	_current_loop_state = new_state
	if _one_shot_active:
		return

	_apply_loop_state(new_state, false)


func play_one_shot(state_key: StringName) -> bool:
	if not _clear_animation_player_if_stale():
		return false

	var clip_name: StringName = _resolve_clip(state_key)
	if clip_name.is_empty():
		return false

	_one_shot_active = true
	_current_playing_clip = clip_name
	_animation_player.play(clip_name)
	return true


func _refresh_loop_clip_if_needed(state: LoopState) -> void:
	if _one_shot_active:
		return

	var clip_name: StringName = _resolve_loop_clip(state)
	if clip_name.is_empty():
		return

	if (
		_animation_player.is_playing()
		and _animation_player.current_animation == clip_name
	):
		return

	_play_loop_clip(clip_name)


func _apply_loop_state(state: LoopState, force_restart: bool) -> void:
	var clip_name: StringName = _resolve_loop_clip(state)
	if clip_name.is_empty():
		return

	if (
		not force_restart
		and _animation_player.is_playing()
		and _animation_player.current_animation == clip_name
	):
		_current_playing_clip = clip_name
		return

	_play_loop_clip(clip_name)


func _resolve_loop_clip(state: LoopState) -> StringName:
	var clip_name: StringName = _resolve_clip(_loop_state_to_key(state))
	if clip_name.is_empty() and state == LoopState.WORK:
		clip_name = _resolve_clip(STATE_IDLE)
	if clip_name.is_empty() and state == LoopState.MOVE:
		clip_name = _resolve_clip(STATE_IDLE)
	return clip_name


func _play_loop_clip(clip_name: StringName) -> void:
	_current_playing_clip = clip_name
	var animation: Animation = _animation_player.get_animation(clip_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(clip_name)


func _resolve_clip(state_key: StringName) -> StringName:
	if _resolved_clips.has(state_key):
		return _resolved_clips[state_key]

	var preferred_names: Array = _clip_preferences.get(state_key, [])
	var resolved: StringName = _find_matching_clip(preferred_names)
	_resolved_clips[state_key] = resolved
	return resolved


func _find_matching_clip(preferred_names: Array) -> StringName:
	for preferred_name: Variant in preferred_names:
		var preferred: String = str(preferred_name)
		for available_name: String in _available_clips:
			if available_name == preferred:
				return StringName(available_name)
			if available_name.get_file() == preferred:
				return StringName(available_name)

	for preferred_name: Variant in preferred_names:
		var preferred_lower: String = str(preferred_name).to_lower()
		for available_name: String in _available_clips:
			if available_name.to_lower() == preferred_lower:
				return StringName(available_name)
			if available_name.get_file().to_lower() == preferred_lower:
				return StringName(available_name)

	return &""


func _collect_animation_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()

	for library_name: String in _animation_player.get_animation_library_list():
		var library: AnimationLibrary = _animation_player.get_animation_library(library_name)
		if library == null:
			continue
		for animation_name: String in library.get_animation_list():
			if library_name.is_empty():
				names.append(animation_name)
			else:
				names.append("%s/%s" % [library_name, animation_name])

	return names


func _loop_state_to_key(state: LoopState) -> StringName:
	match state:
		LoopState.MOVE:
			return STATE_MOVE
		LoopState.WORK:
			return STATE_WORK
		_:
			return STATE_IDLE


func _on_animation_finished(animation_name: StringName) -> void:
	if not _clear_animation_player_if_stale():
		return
	if not _one_shot_active:
		return
	if animation_name != _current_playing_clip:
		return

	_one_shot_active = false
	_apply_loop_state(_current_loop_state, true)
