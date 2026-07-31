class_name HeroCatalog
extends RefCounted

## Registry of playable hero kits. Altar / UI / AI resolve scenes and display data here.

const KIT_PALADIN := &"paladin"
const KIT_SHADOW_ASSASSIN := &"shadow_assassin"
const KIT_RANGER := &"ranger"

const PALADIN_SCENE_PATH := "res://scenes/units/hero.tscn"
const SHADOW_ASSASSIN_SCENE_PATH := "res://scenes/units/shadow_assassin.tscn"
const RANGER_SCENE_PATH := "res://scenes/units/ranger.tscn"

const KIT_ORDER: Array[StringName] = [KIT_PALADIN, KIT_SHADOW_ASSASSIN, KIT_RANGER]


static func get_display_name(kit_id: StringName) -> String:
	match kit_id:
		KIT_PALADIN:
			return "Human Paladin"
		KIT_SHADOW_ASSASSIN:
			return "Shadow Assassin"
		KIT_RANGER:
			return "Ranger"
		_:
			return String(kit_id)


static func get_role_description(kit_id: StringName) -> String:
	match kit_id:
		KIT_PALADIN:
			return "Durable melee fighter with slam, strike, invulnerability, and execute."
		KIT_SHADOW_ASSASSIN:
			return "Mobile melee assassin — mark, smoke, slash, and dash."
		KIT_RANGER:
			return "Fragile ranged marksman — roll, traps, piercing bolt, and camouflage."
		_:
			return "Hero unit."


static func get_scene_path(kit_id: StringName) -> String:
	match kit_id:
		KIT_SHADOW_ASSASSIN:
			return SHADOW_ASSASSIN_SCENE_PATH
		KIT_RANGER:
			return RANGER_SCENE_PATH
		_:
			return PALADIN_SCENE_PATH


static func load_scene(kit_id: StringName) -> PackedScene:
	var path: String = get_scene_path(kit_id)
	if not ResourceLoader.exists(path):
		push_warning("HeroCatalog: missing scene for kit %s (%s)" % [kit_id, path])
		return load(PALADIN_SCENE_PATH) as PackedScene
	return load(path) as PackedScene


static func is_valid_kit(kit_id: StringName) -> bool:
	return (
		kit_id == KIT_PALADIN
		or kit_id == KIT_SHADOW_ASSASSIN
		or kit_id == KIT_RANGER
	)


static func normalize_kit_id(kit_id: StringName) -> StringName:
	if is_valid_kit(kit_id):
		return kit_id
	return KIT_PALADIN
